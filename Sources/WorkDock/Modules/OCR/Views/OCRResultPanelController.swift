import AppKit
import SwiftUI

/// Owns the reusable floating result panel.
///
/// AppKit is used directly instead of a SwiftUI `Window` scene so the OCR
/// module stays self-contained: it can pop a result from a global shortcut
/// without new scene wiring in the app entry point.
@MainActor
final class OCRResultPanelController {
    private weak var module: OCRModule?
    private var panel: NSPanel?

    init(module: OCRModule) {
        self.module = module
    }

    func show() {
        guard let module else { return }
        let panel = panel ?? makePanel(for: module)
        self.panel = panel
        if panel.isMiniaturized {
            panel.deminiaturize(nil)
        }
        panel.makeKeyAndOrderFront(nil)
    }

    func close() {
        panel?.orderOut(nil)
    }

    private func makePanel(for module: OCRModule) -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 580, height: 460),
            styleMask: [.titled, .closable, .resizable, .utilityWindow],
            backing: .buffered,
            defer: false)
        panel.title = module.displayName
        panel.isReleasedWhenClosed = false
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentMinSize = NSSize(width: 460, height: 320)
        panel.contentView = NSHostingView(rootView: OCRResultPanelView(module: module))
        panel.center()
        return panel
    }
}
