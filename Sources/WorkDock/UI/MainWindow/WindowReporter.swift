import AppKit
import SwiftUI

/// Reports the `NSWindow` that hosts the main scene, and `nil` when that scene
/// is torn down.
///
/// SwiftUI gives a view the `openWindow` action but not its own `NSWindow`, and
/// the router must not guess among `NSApp.windows` — the OCR result panel and
/// the status bar window live there too. `viewDidMoveToWindow` fires exactly
/// when the hosting window is installed or removed, which is also the moment a
/// pending notification click has to be finished, or the reference dropped.
struct WindowReporter: NSViewRepresentable {
    /// Main-actor closure: it runs from AppKit view plumbing, which is main
    /// actor isolated, and the router it talks to is too.
    let onWindowChanged: @MainActor (NSWindow?) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = ReporterView(frame: .zero)
        view.onWindowChanged = onWindowChanged
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        guard let view = nsView as? ReporterView else { return }
        view.onWindowChanged = onWindowChanged
    }

    private final class ReporterView: NSView {
        var onWindowChanged: (@MainActor (NSWindow?) -> Void)?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            onWindowChanged?(window)
        }
    }
}
