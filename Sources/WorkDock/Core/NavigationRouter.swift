import SwiftUI
import os
import Combine

/// Navigation bus shared by menu bar, main window, and notification clicks.
///
/// Presentation is event-driven, with no retries and no guessing among
/// `NSApp.windows`. The app starts menu-bar-only: the launch window reports
/// itself, is hidden, and stays alive, so a later click only has to order it
/// back in and activate the app. A window the user really closed takes its
/// scene with it; ``openMainWindow()`` then marks the request pending and asks
/// SwiftUI to rebuild the scene through the `openWindow` action stashed by
/// ``registerMainWindowOpener(_:)`` — the rebuilt window finishes the request
/// the moment it reports itself.
@MainActor
public final class NavigationRouter: ObservableObject {
    @Published public var selectedModuleID: String?
    /// Deep-link request for the selected module, cleared once a consumer
    /// takes it through ``takePendingPayload(moduleID:)``.
    @Published public private(set) var pendingPayload: [String: String]?

    /// Scene id of the single app window declared in `WorkDockApp`.
    static let mainWindowID = "main"

    private let log = Logger(subsystem: "cn.dylanliu.workdock", category: "Router")

    /// `@Environment(\.openWindow)` handed over by a live view. Only this
    /// action can rebuild a `Window` scene that SwiftUI tore down.
    private var openWindowAction: OpenWindowAction?

    /// The window hosting `MainWindowView`, reported by that view. Weak, so a
    /// window SwiftUI releases drops the reference on its own.
    private weak var mainWindow: NSWindow?

    /// A click that arrived while no main window existed. Finished by
    /// ``mainWindowChanged(_:)`` as soon as SwiftUI builds the scene.
    private var pendingPresentation = false

    /// The launch window has been offered to the user already.
    private var launchWindowSettled = false

    /// `mainWindowAppeared()` ran before the window reported itself; finish the
    /// launch hide on that first report.
    private var hideLaunchWindowOnReport = false

    public init() {}

    // MARK: - Scene registration

    /// Hands a view's `openWindow` action to the router.
    ///
    /// Registered by the main window and by the menu bar dropdown. If a click
    /// asked for a rebuild before any view could hand the action over, that
    /// request is fulfilled now instead of being dropped.
    public func registerMainWindowOpener(_ openWindow: OpenWindowAction) {
        openWindowAction = openWindow
        if pendingPresentation, mainWindow == nil {
            openWindow(id: Self.mainWindowID)
        }
    }

    /// Reports the window hosting the main scene — `nil` when the scene is torn
    /// down.
    ///
    /// Called from `viewDidMoveToWindow`, i.e. exactly when the window comes and
    /// goes, which is also when a pending click can be finished.
    func mainWindowChanged(_ window: NSWindow?) {
        guard let window else {
            mainWindow = nil
            return
        }
        mainWindow = window
        if pendingPresentation {
            // A click asked for this window before it existed: it owns it now,
            // so the launch hide must not take it away.
            pendingPresentation = false
            present(window)
            return
        }
        guard hideLaunchWindowOnReport, !launchWindowSettled else { return }
        hideLaunchWindowOnReport = false
        launchWindowSettled = true
        guard selectedModuleID == nil else { return }
        window.orderOut(nil)
    }

    /// Called when the scene's content is on screen.
    ///
    /// Hides the launch window, which is the menu-bar-only startup contract.
    /// Hiding — unlike closing — keeps the scene alive, so a notification click
    /// later simply orders it back in. A window with a route or a pending click
    /// waiting for it is never hidden.
    func mainWindowAppeared() {
        guard !launchWindowSettled else { return }
        guard let window = mainWindow else {
            // The window accessor has not reported yet: finish on its report.
            hideLaunchWindowOnReport = true
            return
        }
        launchWindowSettled = true
        guard selectedModuleID == nil, !pendingPresentation else { return }
        window.orderOut(nil)
    }

    // MARK: - Navigation

    /// Request the main window from any context — View or not.
    public func openMainWindow() {
        // An explicit request owns the window: the launch hide in
        // `mainWindowAppeared()` must not undo it.
        launchWindowSettled = true
        hideLaunchWindowOnReport = false
        if let mainWindow {
            pendingPresentation = false
            present(mainWindow)
            return
        }
        // The scene went away with the window the user closed: ask SwiftUI to
        // rebuild it, and present it when it reports itself.
        pendingPresentation = true
        openWindowAction?(id: Self.mainWindowID)
    }

    public func navigate(moduleID: String, payload: [String: String]? = nil) {
        log.info("navigate → module=\(moduleID, privacy: .public) payload=\(payload ?? [:])")
        selectedModuleID = moduleID
        pendingPayload = payload
    }

    /// Hands the pending payload to its module and clears it, so a module view
    /// that appears later cannot replay a navigation the user already left.
    ///
    /// Payloads are delivered on appearance instead of relying on
    /// `onChange(of:)`: a click can set the payload before the module's view
    /// exists (cold start, or a window rebuilt from a click), and no change
    /// event is emitted for a value that predates the view.
    public func takePendingPayload(moduleID: String) -> [String: String]? {
        guard selectedModuleID == moduleID, let payload = pendingPayload else { return nil }
        pendingPayload = nil
        return payload
    }

    // MARK: - Presentation

    /// Orders the window in first, then activates: activating an app whose
    /// window is not on screen is ignored by the window server. A minimized or
    /// `Cmd`-hidden app is restored first, and activating after the window is
    /// visible covers the click that still has Notification Center focused.
    private func present(_ window: NSWindow) {
        if NSApp.isHidden { NSApp.unhide(nil) }
        if window.isMiniaturized { window.deminiaturize(nil) }
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
