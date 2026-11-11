import SwiftUI
import os

/// Single shared application environment.
///
/// Owns the cross-cutting services (notification, persistence, registry) and
/// wires them together at launch. Modules receive the services they need via
/// their initializer; the container is the only place that knows the full
/// graph.
@MainActor
final class AppContainer: ObservableObject {
    let router = NavigationRouter()
    let notifications = NotificationService()
    let persistence = Persistence()
    /// App-scoped proxy policy. Shared by the Settings module (edit surface)
    /// and the FJJYT module (applies it to the live session).
    let networkProxySettings = NetworkProxySettingsStore()
    let hotkeys = HotkeySettingsStore()
    lazy var registry: ModuleRegistry = ModuleRegistry(router: router)

    private let log = Logger(subsystem: "cn.dylanliu.workdock", category: "Container")

    init() {
        notifications.attach(router: router)
        log.info("container wired")
    }

    private var bootstrapped = false

    /// Registers modules and asks for notification authorization.
    ///
    /// Driven by `AppDelegate.applicationDidFinishLaunching`, not by a view:
    /// the main window is only hidden at startup, and a launch that goes
    /// straight into a notification click must still have every module wired
    /// before the click is routed. Re-entry is a no-op.
    func bootstrap() async {
        guard !bootstrapped else { return }
        bootstrapped = true
        // Wiring first: a notification click can land while the authorization
        // prompt is still on screen, and the module it routes to must already
        // be registered by then.
        registerModules()
        await notifications.requestAuthorization()
    }

    private func registerModules() {
        // Modules register here. FujianEducation is the first; future modules
        // append in display order.
        let fjjyt = FujianEducationModule(
            router: router,
            persistence: persistence,
            notifications: notifications,
            networkProxySettings: networkProxySettings
        )
        registry.register(fjjyt)
        let ocr = OCRModule(router: router)
        hotkeys.bind { [weak ocr] in
            ocr?.triggerScreenshot()
        }
        ocr.setShortcutSettingsView {
            HotkeySettingsView(store: hotkeys)
        }
        registry.register(ocr)
        registry.register(SettingsModule(
            router: router,
            networkProxySettings: networkProxySettings,
            onNetworkSettingsSaved: { [weak fjjyt] in
                // Re-apply the (possibly new) proxy policy to the live FJJYT
                // session. Absent a session, the policy simply applies to the
                // next one built — still a success from the UI's perspective.
                guard let fjjyt else { return true }
                return await fjjyt.applyNetworkSettings()
            }
        ))
        registry.register(DemoModule(router: router))
    }
}
