import AppKit
import SwiftUI

/// Hides the launch-created main window without dismissing its SwiftUI scene.
struct InitialWindowHider: NSViewRepresentable {
    @ObservedObject var router: NavigationRouter

    func makeNSView(context: Context) -> NSView {
        NSView(frame: .zero)
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        guard !router.hasShownInitially, let window = nsView.window else { return }
        router.hasShownInitially = true
        guard router.selectedModuleID == nil else { return }

        DispatchQueue.main.async { [router] in
            guard router.selectedModuleID == nil else { return }
            Self.hide(window)
        }
    }

    static func hide(_ window: NSWindow) {
        window.orderOut(nil)
    }
}
