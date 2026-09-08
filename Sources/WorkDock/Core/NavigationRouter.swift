import SwiftUI
import os
import Combine
/// Navigation bus shared by menu bar, main window, and notification clicks.
///
/// The main window is hidden with `NSWindow.orderOut(_:)`, rather than
/// dismissed, so it remains available for notification and menu-bar routing.
@MainActor
public final class NavigationRouter: ObservableObject {
    @Published public var selectedModuleID: String?
    @Published public var pendingPayload: [String: String]?
    var hasShownInitially = false
    private let log = Logger(subsystem: "cn.dylanliu.workdock", category: "Router")

    public init() {}

    /// Bring the retained main window to the foreground.
    public func openMainWindow() {
        NSApp.activate(ignoringOtherApps: true)
        guard let window = NSApp.windows.first(where: { $0.title == "WorkDock" }) else {
            log.error("main window unavailable")
            return
        }
        window.makeKeyAndOrderFront(nil)
    }

    public func navigate(moduleID: String, payload: [String: String]? = nil) {
        log.info("navigate → module=\(moduleID, privacy: .public) payload=\(payload ?? [:])")
        selectedModuleID = moduleID
        pendingPayload = payload
    }
}
