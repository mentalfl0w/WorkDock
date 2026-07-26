import AppKit
import SwiftUI

/// Only resizes on first appearance and module switch — not on every layout.
struct WindowSizeObserver: NSViewRepresentable {
    @ObservedObject var router: NavigationRouter
    private static var hasResized = false
    private static var lastModuleID: String? = nil

    func makeNSView(context: Context) -> NSView {
        let v = NSView()
        DispatchQueue.main.async {
            v.window?.isMovableByWindowBackground = true
            v.window?.isOpaque = false
            v.window?.backgroundColor = .clear
            Self.resizeWindow(for: v, animate: false)
        }
        return v
    }
    func updateNSView(_ nsView: NSView, context: Context) {
        // Only resize on module switch
        let current = router.selectedModuleID
        guard current != Self.lastModuleID else { return }
        Self.lastModuleID = current
        DispatchQueue.main.async {
            Self.resizeWindow(for: nsView, animate: Self.hasResized)
        }
    }

    static func resizeWindow(for nsView: NSView, animate: Bool) {
        guard let window = nsView.window else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            guard let contentView = window.contentView else { return }
            let fit = contentView.fittingSize
            let newW = max(fit.width, 480)
            let newH = max(fit.height + ModuleContainer.headerHeight, 460)
            let newFrame: NSRect
            if hasResized {
                let current = window.frame
                newFrame = NSRect(
                    x: current.origin.x,
                    y: current.origin.y + current.height - newH,
                    width: newW,
                    height: newH
                )
            } else {
                hasResized = true
                let screen = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 800, height: 600)
                newFrame = NSRect(x: screen.midX - newW/2, y: screen.midY - newH/2, width: newW, height: newH)
            }
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = animate ? 0.2 : 0
                ctx.allowsImplicitAnimation = animate
                window.setFrame(newFrame, display: true)
            }
        }
    }
}
