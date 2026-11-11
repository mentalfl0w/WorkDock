import AppKit

/// App-wide Dock icon policy.
///
/// The preference is expressed at runtime as an activation policy instead of
/// `LSUIElement`, because `LSUIElement` is static: it cannot be toggled without
/// a relaunch. `.accessory` means "no Dock icon", `.regular` means "Dock icon".
///
/// Two call sites own it: application launch (``AppDelegate``) and the Settings
/// toggle. Window-scoped SwiftUI code must not: a view `.task` is tied to its
/// window's lifetime, and startup hides the main window — that is what left a
/// login-item launch with a visible Dock icon.
enum DockVisibility {
    /// Stable `UserDefaults` key shared with the Settings toggle.
    static let hideKey = "hideDockIcon"

    /// Re-asserts the stored preference. Idempotent: AppKit is not touched when
    /// the live policy already matches.
    @MainActor
    static func applyCurrentPreference() {
        let policy: NSApplication.ActivationPolicy =
            UserDefaults.standard.bool(forKey: hideKey) ? .accessory : .regular
        let app = NSApplication.shared
        guard app.activationPolicy() != policy else { return }
        app.setActivationPolicy(policy)
    }
}
