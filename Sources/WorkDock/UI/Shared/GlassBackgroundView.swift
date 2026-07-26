import AppKit
import SwiftUI

/// NSVisualEffectView wrapper with `.behindWindow` blending — blurs the desktop.
///
/// Used as the bottom layer of the main window and detail sheets so the
/// desktop content shows through as frosted glass.
struct GlassBackgroundView: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material = .hudWindow
        v.blendingMode = .behindWindow
        v.state = .active
        return v
    }
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}
