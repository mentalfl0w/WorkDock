import SwiftUI
import ServiceManagement
import os

/// Built-in Settings module — appears in the gallery alongside real modules.
///
/// App-level concerns (Dock visibility, launch-at-login, network proxy, about)
/// without a separate Settings scene. Uses standard Form; system components
/// pick up Liquid Glass.
///
/// Network proxy policy is persisted through the shared
/// ``NetworkProxySettingsStore``. After a successful save the module invokes
/// `onNetworkSettingsSaved`, which lets the app hard-cut-over any live
/// Fujian Education session to the new policy. The closure returns
/// `true` when the policy is active now (or will apply to a future session)
/// and `false` when saving succeeded but rebuilding the active session failed.
public final class SettingsModule: Module {
    public let id = "settings"
    public let displayName = L.settings
    public let icon = "gearshape.fill"
    public let summary = L.settingsSummary
    public let router: NavigationRouter
    /// Shared proxy policy store; the module's Network section edits it.
    public let networkProxySettings: NetworkProxySettingsStore
    /// Re-connect the active session after a policy change. `true` = policy
    /// active now or applies to a future session; `false` = the active session
    /// was hard-closed but could not be rebuilt.
    public let onNetworkSettingsSaved: () async -> Bool
    public let isAuxiliary = true

    public init(
        router: NavigationRouter,
        networkProxySettings: NetworkProxySettingsStore,
        onNetworkSettingsSaved: @escaping () async -> Bool
    ) {
        self.router = router
        self.networkProxySettings = networkProxySettings
        self.onNetworkSettingsSaved = onNetworkSettingsSaved
    }

    public var isSignedIn: Bool {
        get async { true }
    }

    public func menuItems() async -> [ModuleMenuItem] {
        [.action(title: "\(L.settings)…", icon: "gearshape") { [weak self] in
            guard let self else { return }
            self.router.openMainWindow()
            self.router.navigate(moduleID: self.id, payload: nil)
        }]
    }

    @MainActor
    public func mainView() -> AnyView {
        AnyView(SettingsModuleView(
            store: networkProxySettings,
            onNetworkSettingsSaved: onNetworkSettingsSaved
        ))
    }

    public func start() async {}
    public func stop() async {}
}

struct SettingsModuleView: View {
    /// Outcome of the most recent save-and-reconnect attempt, shown truthfully
    /// under the Network section's controls.
    private enum SaveStatus: Equatable {
        case applied
        case rebuildFailed
        case saveFailed(String)

        /// Whether pressing Save again makes sense without further edits
        /// (retry of a failed reconnect / failed persist).
        var allowsRetry: Bool {
            switch self {
            case .applied: return false
            case .rebuildFailed, .saveFailed: return true
            }
        }
    }

    private let store: NetworkProxySettingsStore
    private let onNetworkSettingsSaved: () async -> Bool

    @AppStorage("hideDockIcon") private var hideDockIcon = false
    @State private var launchAtLogin = false
    private let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
    private let author = "Dylan Liu"
    private let log = Logger(subsystem: "cn.dylanliu.workdock", category: "Settings")

    // Network proxy draft. Seeded from the store on appear; custom host/port
    // survive mode toggles so switching Direct ⇄ System ⇄ Custom never loses
    // a typed configuration.
    @State private var mode: NetworkProxyMode = .direct
    @State private var customType: CustomProxyType = .http
    @State private var host = ""
    @State private var portText = ""
    @State private var saved: NetworkProxySettings = .direct
    @State private var status: SaveStatus?
    @State private var applying = false

    init(store: NetworkProxySettingsStore, onNetworkSettingsSaved: @escaping () async -> Bool) {
        self.store = store
        self.onNetworkSettingsSaved = onNetworkSettingsSaved
    }

    var body: some View {
        ModuleContainerView(title: L.settings) {
            Form {
                Section(L.general) {
                    Toggle(L.showDockIcon, isOn: Binding(
                        get: { !hideDockIcon },
                        set: { show in
                            hideDockIcon = !show
                            NSApp.setActivationPolicy(show ? .regular : .accessory)
                            NSApp.activate(ignoringOtherApps: true)
                            for window in NSApp.windows where !window.title.isEmpty {
                                window.makeKeyAndOrderFront(nil)
                            }
                        }
                    ))
                    Toggle("\(L.launchAtLogin) \(L.appName)", isOn: $launchAtLogin)
                        .onChange(of: launchAtLogin) { _, on in
                            toggleLaunchAtLogin(on)
                        }
                }
                Section(L.network) {
                    Picker(L.proxyMode, selection: $mode) {
                        Text(L.proxyDirect).tag(NetworkProxyMode.direct)
                        Text(L.proxySystem).tag(NetworkProxyMode.system)
                        Text(L.proxyCustom).tag(NetworkProxyMode.custom)
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: mode) { _, _ in status = nil }

                    if mode == .custom {
                        Picker(L.proxyType, selection: $customType) {
                            Text(L.proxyTypeHTTP).tag(CustomProxyType.http)
                            Text(L.proxyTypeSOCKS5).tag(CustomProxyType.socks5)
                        }
                        .onChange(of: customType) { _, _ in status = nil }

                        TextField(L.proxyHost, text: $host, prompt: Text(L.proxyHostPlaceholder))
                            .onChange(of: host) { _, _ in status = nil }

                        TextField(L.proxyPort, text: $portText)
                            .onChange(of: portText) { _, newValue in
                                // Keep the field digits-only and ≤ 5 chars
                                // (65535 is the largest valid port).
                                let digits = String(newValue.filter { $0.isNumber }.prefix(5))
                                if digits != newValue {
                                    portText = digits
                                }
                                status = nil
                            }

                        if let message = validationError {
                            Text(message)
                                .font(.caption)
                                .foregroundStyle(.red)
                        }
                    }

                    HStack {
                        Spacer()
                        Button(applying ? L.proxyApplying : L.proxySaveApply) {
                            Task { await applySettings() }
                        }
                        .buttonStyle(.glassProminent)
                        .disabled(!canSave)
                    }

                    switch status {
                    case .applied:
                        Text(L.proxyApplied)
                            .font(.caption)
                            .foregroundStyle(.green)
                    case .rebuildFailed:
                        Text(L.proxyRebuildFailed)
                            .font(.caption)
                            .foregroundStyle(.orange)
                    case .saveFailed(let message):
                        Text(message)
                            .font(.caption)
                            .foregroundStyle(.red)
                    case nil:
                        EmptyView()
                    }
                }
                Section(L.about) {
                    HStack(spacing: 12) {
                        if let logoURL = Bundle.main.url(forResource: "logo", withExtension: "png"),
                           let nsImage = NSImage(contentsOf: logoURL) {
                            Image(nsImage: nsImage)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 48, height: 48)
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text(L.appName).font(.headline)
                            Text("\(L.version): \(appVersion)").font(.caption).foregroundStyle(.secondary)
                            Text("\(L.author): Dylan Liu").font(.caption).foregroundStyle(.secondary)
                            Text("\(L.copyright): © 2026 Dylan Liu").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
            .onAppear {
                launchAtLogin = (SMAppService.mainApp.status == .enabled)
            }
            .task {
                await syncDraftFromStore()
            }
        }
    }

    // MARK: - Network proxy draft

    private var trimmedHost: String {
        host.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var parsedPort: Int? {
        Int(portText)
    }

    /// Human-readable validation failure for the current draft, or `nil` when
    /// the draft is saveable. Only custom mode has constraints — the host must
    /// be non-empty and the port in 1...65535, mirroring
    /// `NetworkProxySettings.validated()`.
    private var validationError: String? {
        guard mode == .custom else { return nil }
        if trimmedHost.isEmpty { return L.proxyHostRequired }
        guard let port = parsedPort, (1...65535).contains(port) else {
            return L.proxyPortInvalid
        }
        return nil
    }

    private func makeDraft() -> NetworkProxySettings? {
        guard validationError == nil else { return nil }
        return NetworkProxySettings(
            mode: mode,
            customProxyType: customType,
            host: trimmedHost,
            port: parsedPort ?? 0
        )
    }

    private var isDirty: Bool {
        guard let draft = makeDraft() else { return false }
        return draft != saved
    }

    private var canSave: Bool {
        guard !applying, validationError == nil else { return false }
        return isDirty || status?.allowsRetry == true
    }

    @MainActor
    private func syncDraftFromStore() async {
        let settings = store.settings
        mode = settings.mode
        customType = settings.customProxyType
        host = settings.host
        portText = settings.port == 0 ? "" : "\(settings.port)"
        saved = settings
    }

    @MainActor
    private func applySettings() async {
        guard let draft = makeDraft() else { return }
        applying = true
        defer { applying = false }
        do {
            let persisted = try store.save(draft)
            saved = persisted
            let active = await onNetworkSettingsSaved()
            status = active ? .applied : .rebuildFailed
        } catch let error as NetworkProxyValidationError {
            // Defensive: UI validation should have caught these already.
            switch error {
            case .emptyHost:
                status = .saveFailed(L.proxyHostRequired)
            case .invalidPort:
                status = .saveFailed(L.proxyPortInvalid)
            }
        } catch {
            status = .saveFailed(L.proxySaveFailed)
        }
    }

    private func toggleLaunchAtLogin(_ on: Bool) {
        do {
            if on {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            log.error("launch-at-login toggle failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}
