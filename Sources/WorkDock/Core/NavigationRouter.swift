import SwiftUI
import os
import Combine
/// Navigation bus shared by menu bar, main window, and notification clicks.
///
/// ``openMainWindow()`` brings the app to front and requests the main window
/// to open. Because the app is `LSUIElement`, `WindowGroup` does not pre-create
/// a window — View-bound callers use `@Environment(\.openWindow)` directly;
/// non-View callers (notification clicks) post ``.openMainWindow`` and the
/// `WindowGroup` content observes it to activate the app.
@MainActor
public final class NavigationRouter: ObservableObject {
    @Published public var selectedModuleID: String?
    @Published public var pendingPayload: [String: String]?
    var hasShownInitially = false
    private let log = Logger(subsystem: "cn.dylanliu.workdock", category: "Router")

    public init() {}

    /// Request the main window from a non-View context (notification click).
    /// View contexts should use `@Environment(\.openWindow)` directly.
    public func openMainWindow() {
        NSApp.activate(ignoringOtherApps: true)
        for w in NSApp.windows where !w.title.isEmpty {
            w.makeKeyAndOrderFront(nil)
        }
        NotificationCenter.default.post(name: .openMainWindow, object: nil)
    }

    public func navigate(moduleID: String, payload: [String: String]? = nil) {
        log.info("navigate → module=\(moduleID, privacy: .public) payload=\(payload ?? [:])")
        selectedModuleID = moduleID
        pendingPayload = payload
    }
}
