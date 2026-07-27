import SwiftUI
import ServiceManagement
import os

/// Built-in Settings module — appears in the gallery alongside real modules.
///
/// App-level concerns (Dock visibility, launch-at-login, about) without a
/// separate Settings scene. Uses standard Form; system components pick up
/// Liquid Glass.
public final class SettingsModule: Module {
    public let id = "settings"
    public let displayName = L.settings
    public let icon = "gearshape.fill"
    public let summary = L.settingsSummary
    public let router: NavigationRouter
    public let isAuxiliary = true

    public init(router: NavigationRouter) {
        self.router = router
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
        AnyView(SettingsModuleView())
    }

    public func start() async {}
    public func stop() async {}
}

struct SettingsModuleView: View {
    @AppStorage("hideDockIcon") private var hideDockIcon = false
    @State private var launchAtLogin = false
    private let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
    private let author = "Dylan Liu"
    private let log = Logger(subsystem: "cn.dylanliu.workdock", category: "Settings")

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
