import Foundation
import SwiftUI

/// A single top-level entry in a module's menu bar section.
/// Each item carries its own semantics — actions run immediately, submenus
/// nest, separators divide. Modules build these fresh on every menu refresh.
public enum ModuleMenuItem {
    case action(title: String, icon: String? = nil, handler: () async -> Void)
    case submenu(title: String, icon: String? = nil, items: [ModuleMenuItem])
    case separator
}

/// Where a notification or menu click should land the user.
/// - ``web``: open an external URL in the default browser.
/// - ``route``: bring the app to front, open the main window, and navigate to a module-defined route.
public enum JumpTarget: Sendable, Hashable {
    case web(URL)
    case route(moduleID: String, payload: [String: String])
}

/// The contract every WorkDock module implements.
///
/// A module owns its data layer, its views, and its polling cadence; the
/// framework owns the menu bar, the main window shell, notifications, and
/// navigation. Modules describe *what* to show and *when* to nudge; the
/// framework decides *how* and *where*.
@MainActor
public protocol Module: AnyObject {
    /// Stable, unique identifier — used as the route key and persistence scope.
    var id: String { get }
    /// Human-readable name shown in the module gallery and menus.
    var displayName: String { get }
    /// SF Symbol name for the module icon.
    var icon: String { get }
    /// Short one-line description for the module gallery card.
    var summary: String { get }
    /// Whether the module is authenticated and ready. Drives menu greying.
    var isSignedIn: Bool { get async }
    /// Framework-provided navigation bus, injected at construction. Modules
    /// call `navigate(moduleID:payload:)` + `openMainWindow()` for **all**
    /// "open X" actions (menu clicks, notification clicks, deep links) —
    /// there is exactly one navigation path per app.
    var router: NavigationRouter { get }

    // MARK: - Placement

    /// Whether this module appears in the menu bar dropdown.
    /// Default: `true`. Set `false` for utility/demo modules.
    var showsInMenuBar: Bool { get }
    /// Whether this module is grouped with Settings in the gallery's lower section.
    /// Default: `false`. Set `true` for auxiliary modules (settings, demo).
    var isAuxiliary: Bool { get }

    /// Menu items rendered under the module's section in the menu bar.
    /// Called on every menu refresh — keep it cheap.
    func menuItems() async -> [ModuleMenuItem]
    /// The full SwiftUI view shown when the user opens this module from the gallery.
    @MainActor
    func mainView() -> AnyView
    /// Begin background polling (new-document checks, etc.). Idempotent.
    func start() async
    /// Stop background polling. Idempotent.
    func stop() async
}

// MARK: - Default placements

public extension Module {
    var showsInMenuBar: Bool { true }
    var isAuxiliary: Bool { false }
}
