import XCTest
import Foundation
import CFNetwork
@testable import WorkDock


// MARK: - Construction and validation

final class NetworkProxySettingsValidationTests: XCTestCase {
    private func settings(
        mode: NetworkProxyMode,
        type: CustomProxyType = .http,
        host: String = "",
        port: Int = 0
    ) -> NetworkProxySettings {
        NetworkProxySettings(mode: mode, customProxyType: type, host: host, port: port)
    }


    func testValidatedTrimsCustomHost() throws {
        let s = settings(mode: .custom, type: .http, host: "  proxy.example.edu \n", port: 8080)
        let expected = settings(mode: .custom, type: .http, host: "proxy.example.edu", port: 8080)
        XCTAssertEqual(try s.validated(), expected)
    }

    func testValidatedAcceptsBoundaryPorts() throws {
        XCTAssertNoThrow(try settings(mode: .custom, host: "h", port: 1).validated())
        XCTAssertNoThrow(try settings(mode: .custom, host: "h", port: 65535).validated())
    }

    func testValidatedRejectsEmptyCustomHost() {
        XCTAssertThrowsError(try settings(mode: .custom, host: "   ").validated()) { error in
            XCTAssertEqual(error as? NetworkProxyValidationError, .emptyHost)
        }
    }

    func testValidatedRejectsPortsOutsideRange() {
        XCTAssertThrowsError(try settings(mode: .custom, host: "h", port: 0).validated()) { error in
            XCTAssertEqual(error as? NetworkProxyValidationError, .invalidPort)
        }
        XCTAssertThrowsError(try settings(mode: .custom, host: "h", port: -1).validated()) { error in
            XCTAssertEqual(error as? NetworkProxyValidationError, .invalidPort)
        }
        XCTAssertThrowsError(try settings(mode: .custom, host: "h", port: 65536).validated()) { error in
            XCTAssertEqual(error as? NetworkProxyValidationError, .invalidPort)
        }
    }

    func testDirectAndSystemIgnoreHostAndPortValidation() throws {
        XCTAssertNoThrow(try settings(mode: .direct, host: "", port: 0).validated())
        XCTAssertNoThrow(try settings(mode: .system, host: "  leftover.host ", port: 99999).validated())
    }

}

// MARK: - Applying policy to URLSessionConfiguration

final class NetworkProxySettingsApplyTests: XCTestCase {
    private enum Key {
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

    private func appliedDictionary(_ s: NetworkProxySettings) -> [String: Any]? {
        let config = URLSessionConfiguration.ephemeral
        s.apply(to: config)
        guard let raw = config.connectionProxyDictionary else { return nil }
        var out: [String: Any] = [:]
        for (key, value) in raw {
            if let stringKey = key as? String { out[stringKey] = value }
        }
        return out
    }
    private func proxyTypes(for url: URL, settings: NetworkProxySettings) -> [String] {
        let config = URLSessionConfiguration.ephemeral
        settings.apply(to: config)
        guard let dictionary = config.connectionProxyDictionary else { return [] }
        let proxies = CFNetworkCopyProxiesForURL(url as CFURL, dictionary as CFDictionary)
            .takeRetainedValue() as NSArray
        return proxies.compactMap {
            ($0 as? [String: Any])?[kCFProxyTypeKey as String] as? String
        }
    }

    private func enabled(_ dict: [String: Any]?, _ key: String) -> Bool? {
        dict?[key] as? Bool
    }

    private func stringValue(_ dict: [String: Any]?, _ key: String) -> String? {
        dict?[key] as? String
    }

    private func intValue(_ dict: [String: Any]?, _ key: String) -> Int? {
        dict?[key] as? Int
    }

    func testSystemLeavesProxyDictionaryNil() {
        let dict = appliedDictionary(NetworkProxySettings(mode: .system, customProxyType: .http, host: "", port: 0))
        XCTAssertNil(dict, "system policy must defer to the OS proxy settings (nil dictionary)")
    }

    func testDirectExplicitlyDisablesEveryProxyPath() {
        let s = NetworkProxySettings.direct
        let dict = appliedDictionary(s)
        XCTAssertNotNil(dict, "direct policy must not defer to the system proxy")
        XCTAssertEqual(enabled(dict, Key.httpEnable), false)
        XCTAssertEqual(enabled(dict, Key.httpsEnable), false)
        XCTAssertEqual(enabled(dict, Key.socksEnable), false)
        XCTAssertEqual(enabled(dict, Key.pacEnable), false)
        XCTAssertEqual(enabled(dict, Key.autoDiscoveryEnable), false)
        XCTAssertNil(stringValue(dict, Key.httpProxy))
        XCTAssertNil(stringValue(dict, Key.socksProxy))
    }
    func testDirectResolvesToNoProxyForHTTPAndHTTPS() {
        for url in [URL(string: "http://example.com")!, URL(string: "https://example.com")!] {
            XCTAssertEqual(proxyTypes(for: url, settings: .direct), [kCFProxyTypeNone as String])
        }
    }

    func testCustomHTTPEnablesHTTPAndHTTPSProxy() {
        let s = NetworkProxySettings(mode: .custom, customProxyType: .http, host: "proxy.example.edu", port: 8080)
        let dict = appliedDictionary(s)
        XCTAssertNotNil(dict, "custom policy must replace, not defer to, the system proxy")
        XCTAssertEqual(enabled(dict, Key.httpEnable), true)
        XCTAssertEqual(stringValue(dict, Key.httpProxy), "proxy.example.edu")
        XCTAssertEqual(intValue(dict, Key.httpPort), 8080)
        XCTAssertEqual(enabled(dict, Key.httpsEnable), true)
        XCTAssertEqual(stringValue(dict, Key.httpsProxy), "proxy.example.edu")
        XCTAssertEqual(intValue(dict, Key.httpsPort), 8080)
        XCTAssertEqual(enabled(dict, Key.socksEnable), false)
        XCTAssertEqual(enabled(dict, Key.pacEnable), false)
        XCTAssertEqual(enabled(dict, Key.autoDiscoveryEnable), false)
        XCTAssertNil(stringValue(dict, Key.socksProxy))
    }

    func testCustomSOCKS5EnablesOnlySOCKSProxy() {
        let s = NetworkProxySettings(mode: .custom, customProxyType: .socks5, host: "socks.example.edu", port: 1080)
        let dict = appliedDictionary(s)
        XCTAssertNotNil(dict)
        XCTAssertEqual(enabled(dict, Key.socksEnable), true)
        XCTAssertEqual(stringValue(dict, Key.socksProxy), "socks.example.edu")
        XCTAssertEqual(intValue(dict, Key.socksPort), 1080)
        XCTAssertEqual(enabled(dict, Key.httpEnable), false)
        XCTAssertEqual(enabled(dict, Key.httpsEnable), false)
        XCTAssertEqual(enabled(dict, Key.pacEnable), false)
        XCTAssertEqual(enabled(dict, Key.autoDiscoveryEnable), false)
        XCTAssertNil(stringValue(dict, Key.httpProxy))
        }
    }

// MARK: - Store persistence

@MainActor
final class NetworkProxySettingsStoreTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() async throws {
        try await super.setUp()
        suiteName = "NetworkProxySettingsTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() async throws {
        defaults?.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        try await super.tearDown()
    }

    private func makeStore() -> NetworkProxySettingsStore {
        NetworkProxySettingsStore(defaults: defaults)
    }

    private func custom(_ host: String, _ port: Int, type: CustomProxyType = .http) -> NetworkProxySettings {
        NetworkProxySettings(mode: .custom, customProxyType: type, host: host, port: port)
    }

    func testEmptyPersistenceLoadsDirect() {
        XCTAssertEqual(makeStore().settings, .direct)
    }

    func testNonDataValueUnderKeyLoadsDirect() {
        defaults.set("not data", forKey: NetworkProxySettingsStore.storageKey)
        XCTAssertEqual(makeStore().settings, .direct)
    }

    func testCorruptJSONLoadsDirect() {
        defaults.set(Data("{{{not json".utf8), forKey: NetworkProxySettingsStore.storageKey)
        XCTAssertEqual(makeStore().settings, .direct)
    }

    func testUnknownModeInJSONLoadsDirect() throws {
        let json = #"{"mode":"banana","customProxyType":"http","host":"h","port":8080}"#
        defaults.set(Data(json.utf8), forKey: NetworkProxySettingsStore.storageKey)
        XCTAssertEqual(makeStore().settings, .direct)
    }

    func testDecodedButInvalidPolicyLoadsDirect() throws {
        // Valid JSON that fails validation (custom proxy with empty host).
        let invalid = custom("", 8080)
        defaults.set(try JSONEncoder().encode(invalid), forKey: NetworkProxySettingsStore.storageKey)
        XCTAssertEqual(makeStore().settings, .direct)
    }

    func testSavePublishesAndPersistsEachMode() throws {
        let samples: [(NetworkProxySettings, NetworkProxySettings)] = [
            (.direct, .direct),
            (
                NetworkProxySettings(mode: .system, customProxyType: .http, host: "", port: 0),
                NetworkProxySettings(mode: .system, customProxyType: .http, host: "", port: 0)
            ),
            (custom("proxy.example.edu", 8080), custom("proxy.example.edu", 8080)),
            (custom("socks.example.edu", 1080, type: .socks5), custom("socks.example.edu", 1080, type: .socks5)),
        ]
        for (input, expected) in samples {
            let store = makeStore()
            let saved = try store.save(input)
            XCTAssertEqual(saved, expected, "save returns the persisted policy")
            XCTAssertEqual(store.settings, expected, "save publishes the persisted policy")
            XCTAssertEqual(makeStore().settings, expected, "a fresh store reloads the persisted policy")
        }
    }

    func testSavePersistsValidatedTrimmedHost() throws {
        let store = makeStore()
        let saved = try store.save(custom("  proxy.example.edu \n", 8080))
        XCTAssertEqual(saved.host, "proxy.example.edu")
        XCTAssertEqual(makeStore().settings, custom("proxy.example.edu", 8080))
    }

    func testRejectedSaveLeavesStateAndPersistenceUntouched() throws {
        let store = makeStore()
        try store.save(custom("proxy.example.edu", 8080))

        XCTAssertThrowsError(try store.save(custom("   ", 8080))) { error in
            XCTAssertEqual(error as? NetworkProxyValidationError, .emptyHost)
        }
        XCTAssertEqual(store.settings, custom("proxy.example.edu", 8080), "failed save must not republish")
        XCTAssertEqual(makeStore().settings, custom("proxy.example.edu", 8080), "failed save must not persist")

        XCTAssertThrowsError(try store.save(custom("h", 0))) { error in
            XCTAssertEqual(error as? NetworkProxyValidationError, .invalidPort)
        }
        XCTAssertEqual(store.settings, custom("proxy.example.edu", 8080))
        XCTAssertEqual(makeStore().settings, custom("proxy.example.edu", 8080))
    }
}
