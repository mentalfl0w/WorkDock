import Foundation
import os

/// Registry of all available modules.
///
/// Modules register at launch; the menu bar and main window iterate the
/// registry to render the gallery and build menu sections. The registry is
/// the single source of truth for "which modules exist and in what order".
@MainActor
public final class ModuleRegistry: ObservableObject {
    @Published public private(set) var modules: [any Module] = []
    private let router: NavigationRouter

    private let log = Logger(subsystem: "cn.dylanliu.workdock", category: "Registry")

    public init(router: NavigationRouter) {
        self.router = router
    }

    public func register(_ module: any Module) {
        log.info("registering module: \(module.id, privacy: .public)")
        // Module contract: router is injected at construction. Modules that
        // accept it via init get it here; the protocol only requires `get`.
        modules.append(module)
        Task { await module.start() }
    }

    public func module(for id: String) -> (any Module)? {
        modules.first { $0.id == id }
    }
}
