import SwiftUI
import AppKit
import Carbon.HIToolbox

/// SwiftUI field that records a key combination.
///
/// Clicking the field starts recording; the next key press (including ⌘-based
/// combinations) is captured and written back through the binding. Escape
/// cancels. Recording lives in a small `NSView` so Command-key equivalents are
/// intercepted before the menu bar consumes them.
///
/// The view only captures input. Validation, persistence and registration are
/// the caller's job (``HotkeySettingsStore`` does all three).
public struct HotkeyRecorderView: View {
    @Binding private var hotkey: GlobalHotkey
    private let isEnabled: Bool
    private let onChange: (@MainActor (GlobalHotkey) -> Void)?

    /// - Parameters:
    ///   - hotkey: Binding updated with the recorded combination.
    ///   - isEnabled: When `false` the field is dimmed and ignores clicks.
    ///   - onChange: Called on the main actor after a successful capture.
    public init(
        hotkey: Binding<GlobalHotkey>,
        isEnabled: Bool = true,
        onChange: (@MainActor (GlobalHotkey) -> Void)? = nil
    ) {
        _hotkey = hotkey
        self.isEnabled = isEnabled
        self.onChange = onChange
    }

    public var body: some View {
        HotkeyRecorderRepresentable(
            hotkey: hotkey,
            isEnabled: isEnabled,
            onCapture: { captured in
                hotkey = captured
                onChange?(captured)
            }
        )
        .frame(minWidth: 120, maxWidth: 220, minHeight: 24, maxHeight: 24)
        .accessibilityLabel(Text(HotkeyText.shortcutLabel))
    }
}

// MARK: - AppKit bridge

private struct HotkeyRecorderRepresentable: NSViewRepresentable {
    var hotkey: GlobalHotkey
    var isEnabled: Bool
    var onCapture: @MainActor (GlobalHotkey) -> Void

    func makeNSView(context: Context) -> HotkeyRecorderControl {
        let view = HotkeyRecorderControl()
        view.hotkey = hotkey
        view.isEnabled = isEnabled
        view.onCapture = onCapture
        return view
    }

    func updateNSView(_ view: HotkeyRecorderControl, context: Context) {
        view.hotkey = hotkey
        view.isEnabled = isEnabled
        view.onCapture = onCapture
    }
}

/// A bezeled field that owns first responder status while recording.
@MainActor
private final class HotkeyRecorderControl: NSView {
    var hotkey: GlobalHotkey = .defaultScreenshot {
        didSet {
            needsDisplay = true
            setAccessibilityValue(hotkey.displayString)
        }
    }

    var isEnabled: Bool = true {
        didSet {
            if !isEnabled {
                cancelRecording()
            }
            needsDisplay = true
            window?.invalidateCursorRects(for: self)
        }
    }

    var onCapture: (@MainActor (GlobalHotkey) -> Void)?

    private var recording = false
    private var localMonitor: Any?

    override var acceptsFirstResponder: Bool { isEnabled }
    override var intrinsicContentSize: NSSize { NSSize(width: 148, height: 24) }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if newWindow !== window {
            // SwiftUI removed or reparented the field while it was recording.
            abortRecording()
        }
        super.viewWillMove(toWindow: newWindow)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel(HotkeyText.shortcutLabel)
        setAccessibilityValue(hotkey.displayString)
        setAccessibilityHelp(HotkeyText.recordHint)
        toolTip = HotkeyText.recordHint
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: isEnabled ? .pointingHand : .arrow)
    }

    override func mouseDown(with event: NSEvent) {
        guard isEnabled else { return }
        if recording {
            cancelRecording()
        } else {
            beginRecording()
        }
    }

    override func keyDown(with event: NSEvent) {
        guard recording else {
            super.keyDown(with: event)
            return
        }
        capture(keyCode: event.keyCode, modifiers: HotkeyModifiers(event.modifierFlags))
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard recording else {
            return super.performKeyEquivalent(with: event)
        }
        capture(keyCode: event.keyCode, modifiers: HotkeyModifiers(event.modifierFlags))
        return true
    }

    override func resignFirstResponder() -> Bool {
        abortRecording()
        return super.resignFirstResponder()
    }

    override func draw(_ dirtyRect: NSRect) {
        let fieldRect = bounds.insetBy(dx: 0.5, dy: 0.5)
        let path = NSBezierPath(roundedRect: fieldRect, xRadius: 6, yRadius: 6)

        if recording {
            NSColor.controlAccentColor.withAlphaComponent(0.14).setFill()
        } else {
            NSColor.textBackgroundColor.withAlphaComponent(isEnabled ? 0.7 : 0.35).setFill()
        }
        path.fill()

        (recording ? NSColor.controlAccentColor : NSColor.separatorColor).setStroke()
        path.lineWidth = recording ? 2 : 1
        path.stroke()

        let text = recording ? HotkeyText.recording : hotkey.displayString
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12, weight: .medium),
            .foregroundColor: isEnabled ? NSColor.labelColor : NSColor.disabledControlTextColor,
        ]
        let attributed = NSAttributedString(string: text, attributes: attributes)
        let size = attributed.size()
        attributed.draw(at: NSPoint(
            x: bounds.midX - size.width / 2,
            y: bounds.midY - size.height / 2
        ))
    }

    private func beginRecording() {
        guard isEnabled, !recording else { return }
        recording = true
        needsDisplay = true
        setAccessibilityValue(HotkeyText.recording)
        installLocalMonitor()
        window?.makeFirstResponder(self)
    }

    private func cancelRecording() {
        guard recording else { return }
        abortRecording()
        if window?.firstResponder === self {
            window?.makeFirstResponder(nil)
        }
    }

    /// Stop recording without touching first-responder state.
    private func abortRecording() {
        guard recording else { return }
        recording = false
        needsDisplay = true
        setAccessibilityValue(hotkey.displayString)
        stopLocalMonitor()
    }

    private func capture(keyCode: UInt16, modifiers: HotkeyModifiers) {
        guard recording else { return }
        if keyCode == UInt16(kVK_Escape) {
            cancelRecording()
            return
        }

        let captured = GlobalHotkey(
            keyCode: UInt32(keyCode),
            modifiers: modifiers
        )
        recording = false
        needsDisplay = true
        setAccessibilityValue(captured.displayString)
        stopLocalMonitor()
        if window?.firstResponder === self {
            window?.makeFirstResponder(nil)
        }
        onCapture?(captured)
    }

    /// Intercept every key while recording, before menus and app shortcuts.
    ///
    /// The `keyDown` / `performKeyEquivalent` overrides remain as a fallback,
    /// but a local monitor makes recording deterministic: ⌘Q, ⌘W and similar
    /// combinations are captured instead of acting on the app.
    private func installLocalMonitor() {
        guard localMonitor == nil else { return }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            // NSEvent is not Sendable; copy the value data before hopping to
            // the main actor. The monitor only exists while recording, so the
            // event is swallowed unconditionally.
            let keyCode = event.keyCode
            let modifiers = HotkeyModifiers(event.modifierFlags)
            MainActor.assumeIsolated {
                guard self.recording else { return }
                self.capture(keyCode: keyCode, modifiers: modifiers)
            }
            return nil
        }
    }

    private func stopLocalMonitor() {
        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
            self.localMonitor = nil
        }
    }
}

private extension HotkeyModifiers {
    /// Translate AppKit flags into the Carbon masks used for registration.
    init(_ flags: NSEvent.ModifierFlags) {
        var modifiers: HotkeyModifiers = []
        if flags.contains(.command) { modifiers.insert(.command) }
        if flags.contains(.option) { modifiers.insert(.option) }
        if flags.contains(.control) { modifiers.insert(.control) }
        if flags.contains(.shift) { modifiers.insert(.shift) }
        self = modifiers
    }
}
