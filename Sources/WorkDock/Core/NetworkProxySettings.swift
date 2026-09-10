import Foundation
import Combine
import os

/// How WorkDock routes network traffic.
///
/// - ``direct``: connect without any proxy — the system proxy settings are
///   explicitly bypassed.
/// - ``system``: let URLSession use the macOS system proxy settings.
/// - ``custom``: route through a user-supplied proxy (``CustomProxyType``).
public enum NetworkProxyMode: String, Codable, CaseIterable, Sendable {
    case direct
    case system
    case custom
}

/// Transport used by a ``NetworkProxyMode/custom`` proxy.
///
/// Both flavors are unauthenticated: no credentials are attached to the proxy
/// configuration.
public enum CustomProxyType: String, Codable, CaseIterable, Sendable {
    case http
    case socks5
}

/// Why a proxy policy failed validation.
public enum NetworkProxyValidationError: Error, Equatable, Sendable {
    /// ``NetworkProxyMode/custom`` proxy host was empty after trimming.
    case emptyHost
    /// ``NetworkProxyMode/custom`` proxy port is outside 1...65535.
    case invalidPort
}

/// The network proxy policy applied to FJJYT sessions.
///
/// ``NetworkProxySettings/direct`` and ``NetworkProxySettings/system`` ignore
/// `customProxyType`, `host`, and `port`; only ``NetworkProxyMode/custom``
/// consults them.
///
/// Apply a policy to a session configuration with ``apply(to:)``. Persist and
/// observe the current policy through ``NetworkProxySettingsStore``.
public struct NetworkProxySettings: Codable, Equatable, Sendable {
    public let mode: NetworkProxyMode
    public let customProxyType: CustomProxyType
    public let host: String
    public let port: Int

    public init(
        mode: NetworkProxyMode,
        customProxyType: CustomProxyType,
        host: String,
        port: Int
    ) {
        self.mode = mode
        self.customProxyType = customProxyType
        self.host = host
        self.port = port
    }

    /// Direct connectivity — never the system proxy.
    public static let direct = NetworkProxySettings(
        mode: .direct,
        customProxyType: .http,
        host: "",
        port: 0
    )

    /// Normalized copy that is safe to persist and apply.
    ///
    /// Trims the host. A ``NetworkProxyMode/custom`` policy additionally
    /// requires a non-empty host and a port in 1...65535.
    public func validated() throws -> NetworkProxySettings {
        let trimmedHost = host.trimmingCharacters(in: .whitespacesAndNewlines)
        if mode == .custom {
            guard !trimmedHost.isEmpty else { throw NetworkProxyValidationError.emptyHost }
            guard (1...65535).contains(port) else { throw NetworkProxyValidationError.invalidPort }
        }
        return NetworkProxySettings(
            mode: mode,
            customProxyType: customProxyType,
            host: trimmedHost,
            port: port
        )
    }

    /// Configure `config` so its tasks follow this policy.
    ///
    /// - ``NetworkProxyMode/direct``: installs a proxy dictionary that
    ///   explicitly disables HTTP, HTTPS, SOCKS, PAC, and proxy auto-discovery.
    /// - ``NetworkProxyMode/system``: leaves `connectionProxyDictionary` nil so
    ///   URLSession falls back to the system proxy settings.
    /// - ``NetworkProxyMode/custom``: enables the chosen HTTP/HTTPS or SOCKS
    ///   proxy (`host`:`port`) and disables every other proxy path.
    ///
    /// Never throws: an unconfigured proxy cannot silently fall back to direct
    /// networking, it simply fails like any unreachable proxy would.
    public func apply(to config: URLSessionConfiguration) {
        let trimmedHost = host.trimmingCharacters(in: .whitespacesAndNewlines)
        switch mode {
        case .direct:
            config.connectionProxyDictionary = [
                ProxyKey.httpEnable: false,
                ProxyKey.httpsEnable: false,
                ProxyKey.socksEnable: false,
                ProxyKey.pacEnable: false,
                ProxyKey.autoDiscoveryEnable: false,
            ]
        case .system:
            config.connectionProxyDictionary = nil
        case .custom:
            switch customProxyType {
            case .http:
                config.connectionProxyDictionary = [
                    ProxyKey.httpEnable: true,
                    ProxyKey.httpProxy: trimmedHost,
                    ProxyKey.httpPort: port,
                    ProxyKey.httpsEnable: true,
                    ProxyKey.httpsProxy: trimmedHost,
                    ProxyKey.httpsPort: port,
                    ProxyKey.socksEnable: false,
                    ProxyKey.pacEnable: false,
                    ProxyKey.autoDiscoveryEnable: false,
                ]
            case .socks5:
                config.connectionProxyDictionary = [
                    ProxyKey.socksEnable: true,
                    ProxyKey.socksProxy: trimmedHost,
                    ProxyKey.socksPort: port,
                    ProxyKey.httpEnable: false,
                    ProxyKey.httpsEnable: false,
                    ProxyKey.pacEnable: false,
                    ProxyKey.autoDiscoveryEnable: false,
                ]
            }
        }
    }
}

/// CFNetwork keys for ``URLSessionConfiguration.connectionProxyDictionary``,
/// as plain Swift strings so the dictionaries stay canonical across bridging.
private enum ProxyKey {
    static let httpEnable = kCFNetworkProxiesHTTPEnable as String
    static let httpProxy = kCFNetworkProxiesHTTPProxy as String
    static let httpPort = kCFNetworkProxiesHTTPPort as String
    static let httpsEnable = kCFNetworkProxiesHTTPSEnable as String
    static let httpsProxy = kCFNetworkProxiesHTTPSProxy as String
    static let httpsPort = kCFNetworkProxiesHTTPSPort as String
    static let socksEnable = kCFNetworkProxiesSOCKSEnable as String
    static let socksProxy = kCFNetworkProxiesSOCKSProxy as String
    static let socksPort = kCFNetworkProxiesSOCKSPort as String
    static let pacEnable = kCFNetworkProxiesProxyAutoConfigEnable as String
    static let autoDiscoveryEnable = kCFNetworkProxiesProxyAutoDiscoveryEnable as String
}

/// Persists and publishes the current ``NetworkProxySettings``.
///
/// The whole Codable policy lives under one stable `UserDefaults` key
/// (``storageKey``). Missing, corrupt, or invalid persisted data degrades to
/// ``NetworkProxySettings/direct``; the store never applies a broken policy.
@MainActor
public final class NetworkProxySettingsStore: ObservableObject {
    /// Single stable key under which the entire policy is stored.
    nonisolated static let storageKey = "NetworkProxySettings"

    /// The active policy. Always valid: direct by default, or whatever was
    /// last persisted through ``save(_:)``.
    @Published public private(set) var settings: NetworkProxySettings

    private let defaults: UserDefaults
    private let log = Logger(subsystem: "cn.dylanliu.workdock", category: "Proxy")

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.settings = Self.loadPolicy(from: defaults)
    }

    /// Validate, persist, and publish `draft`.
    ///
    /// Persists the validated (host-trimmed) copy under ``storageKey``,
    /// publishes it as the active policy, and returns it. Throws
    /// ``NetworkProxyValidationError`` when the draft is invalid; on throw
    /// nothing is persisted and the active policy is unchanged.
    @discardableResult
    public func save(_ draft: NetworkProxySettings) throws -> NetworkProxySettings {
        let validated = try draft.validated()
        do {
            let data = try JSONEncoder().encode(validated)
            defaults.set(data, forKey: Self.storageKey)
        } catch {
            log.error("persist failed: \(error.localizedDescription, privacy: .public)")
            throw error
        }
        settings = validated
        return validated
    }

    private nonisolated static func loadPolicy(from defaults: UserDefaults) -> NetworkProxySettings {
        guard let data = defaults.data(forKey: storageKey) else { return .direct }
        do {
            let decoded = try JSONDecoder().decode(NetworkProxySettings.self, from: data)
            return (try? decoded.validated()) ?? .direct
        } catch {
            return .direct
        }
    }
}
