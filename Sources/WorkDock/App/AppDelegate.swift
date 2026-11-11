import AppKit

/// Application-level lifecycle hooks.
///
/// Two process-wide invariants live here, because both must hold whether or not
/// any window exists:
///
/// - The Dock icon policy. It used to be applied from a window's SwiftUI
///   `.task`; the launch path tore that window down before the awaited
///   bootstrap returned, cancelling the task, so a login-item launch kept the
///   default `.regular` policy and showed a Dock icon until the user reopened
///   the window.
/// - The app graph and its bootstrap. Module registration and notification
///   authorization must not be scoped to a window that startup hides.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Single app graph. Owned here because `bootstrap()` must run on a
    /// launch hook, not on a view that startup hides.
    let container = AppContainer()

    func applicationDidFinishLaunching(_ notification: Notification) {
        DockVisibility.applyCurrentPreference()
        Task { @MainActor in
            await container.bootstrap()
        }
    }
}
