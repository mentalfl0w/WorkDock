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
    lazy var registry: ModuleRegistry = ModuleRegistry(router: router)

    private let log = Logger(subsystem: "cn.liujiangnan.WorkDock", category: "Container")

    init() {
        notifications.attach(router: router)
        log.info("container wired")
    }

    private var bootstrapped = false

    func bootstrap() async {
        guard !bootstrapped else { return }
        bootstrapped = true
        await notifications.requestAuthorization()
        // Modules register here. FujianEducation is the first; future modules
        // append in display order.
        let fjjyt = FujianEducationModule(
            router: router,
            persistence: persistence,
            notifications: notifications
        )
        registry.register(fjjyt)
        registry.register(SettingsModule(router: router))
        registry.register(DemoModule(router: router))
    }
}
