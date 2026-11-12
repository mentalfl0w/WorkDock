import AppKit
import CoreGraphics
import SwiftUI
import UniformTypeIdentifiers
import os

enum OCRModuleError: LocalizedError {
    case clipboardEmpty
    case imageUnreadable(String)

    var errorDescription: String? {
        switch self {
        case .clipboardEmpty:
            return L.ocrClipboardEmpty
        case .imageUnreadable(let name):
            return L.ocrImageUnreadable(name)
        }
    }
}

/// WorkDock module: local, offline screenshot OCR (Simplified Chinese + English).
///
/// Three inputs — an interactive screen region, the clipboard image, or an
/// image file — feed one Vision pass. The result is editable and copyable and
/// stays in memory only; WorkDock never writes recognition results to disk.
/// Nothing leaves the machine.
///
/// Every visible outcome — progress, a result, an error, or the Screen
/// Recording guidance — is shown on this module's page in the main window.
/// There is no separate result window, so a hotkey run and a run started from
/// the page always end in the same place, and the framework keeps exactly one
/// navigation path.
///
/// Hotkeys are owned by the app's separate hotkey manager: it retrieves this
/// module from ``ModuleRegistry`` and calls ``triggerScreenshot()``. The
/// settings UI is injected through ``shortcutSettingsView`` /
/// ``setShortcutSettingsView(_:)``.
@MainActor
public final class OCRModule: ObservableObject, Module {
    public static let moduleID = "ocr"

    public let id = OCRModule.moduleID
    public let displayName = L.ocrName
    public let icon = "text.viewfinder"
    public let summary = L.ocrSummary
    public let router: NavigationRouter

    /// Mounting point for the separately implemented hotkey manager's
    /// SwiftUI settings view. The OCR page renders it in its sidebar; `nil`
    /// shows a placeholder instead.
    @Published public var shortcutSettingsView: AnyView?

    let store: OCRStore

    private let recognizer = OCRService()
    private let log = Logger(subsystem: "cn.dylanliu.workdock.ocr", category: "Module")
    private var activeTask: Task<Void, Never>?
    private var captureService: ScreenCaptureService?

    /// WorkDock windows ordered out for the duration of an interactive
    /// capture, so the window is never part of its own screenshot. Each entry
    /// remembers whether it was key, which lets an Esc cancel drop the user
    /// back exactly where they were.
    private var windowsHiddenForCapture: [(window: NSWindow, wasKey: Bool)] = []
    private var appWasActiveBeforeCapture = false

    /// - Parameter router: Framework navigation bus.
    public init(router: NavigationRouter) {
        self.router = router
        self.store = OCRStore()
    }

    // MARK: - Module

    public var isSignedIn: Bool {
        get async { true }
    }

    public func menuItems() async -> [ModuleMenuItem] {
        [
            .action(title: L.ocrScreenshot, icon: "text.viewfinder") { [weak self] in
                self?.triggerScreenshot()
            },
            .action(title: L.ocrClipboard, icon: "doc.on.clipboard") { [weak self] in
                self?.triggerClipboardOCR()
            },
            .action(title: L.ocrChooseImage, icon: "photo") { [weak self] in
                self?.chooseImageAndRecognize()
            },
            .separator,
            .action(title: L.ocrOpenPanel, icon: "macwindow") { [weak self] in
                self?.showInMainWindow()
            }
        ]
    }

    @MainActor
    public func mainView() -> AnyView {
        AnyView(OCRRootView(module: self))
    }

    /// Nothing to poll: OCR is on-demand and fully local.
    public func start() async {}

    public func stop() async {
        cancelActiveWork()
        // A capture cancelled by shutdown may never reach its own cleanup.
        restoreWindowsHiddenForCapture()
    }

    // MARK: - Trigger API (main-thread callable)

    /// Starts an interactive region screenshot followed by OCR.
    ///
    /// This is the public entry point for the menu bar, the module page, and
    /// the external hotkey manager. It is main-actor isolated, returns
    /// immediately, and publishes progress through ``store``; the outcome is
    /// shown on the OCR page. While a run is in flight a new trigger is
    /// ignored rather than queued.
    public func triggerScreenshot() {
        guard activeTask == nil else {
            handleBusyTrigger()
            return
        }
        guard ensureScreenRecordingPermission() else {
            store.requirePermission()
            showInMainWindow()
            log.notice("screenshot blocked: screen recording permission missing")
            return
        }
        start(input: .screen)
    }

    /// Runs OCR on the current clipboard image. Main-thread callable.
    public func triggerClipboardOCR() {
        guard activeTask == nil else {
            handleBusyTrigger()
            return
        }
        start(input: .clipboard)
    }

    /// Lets the user pick an image file, then runs OCR. Main-thread callable.
    public func chooseImageAndRecognize() {
        guard activeTask == nil else {
            handleBusyTrigger()
            return
        }
        activateForDialog()
        let panel = NSOpenPanel()
        panel.title = L.ocrChooseImageTitle
        panel.prompt = L.ocrOpen
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        start(input: .file(url))
    }

    /// Cancels the capture subprocess or the in-flight recognition. Safe to
    /// call at any time.
    public func cancelActiveWork() {
        captureService?.cancel()
        activeTask?.cancel()
    }

    /// Brings the OCR page in the main window forward — the single place where
    /// progress, results, errors, and permission guidance appear.
    ///
    /// Navigation happens before the window request on purpose: a click can
    /// arrive while the scene is gone, and the rebuilt window then lands on
    /// this module instead of the gallery.
    public func showInMainWindow() {
        router.navigate(moduleID: id)
        router.openMainWindow()
    }

    /// Injects the hotkey manager's settings view into the OCR page.
    public func setShortcutSettingsView<Content: View>(@ViewBuilder _ content: () -> Content) {
        shortcutSettingsView = AnyView(content())
    }

    /// Opens the Screen Recording pane in System Settings.
    public func openScreenRecordingSettings() {
        let candidates = [
            "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_ScreenCapture",
            "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"
        ]
        for raw in candidates {
            guard let url = URL(string: raw) else { continue }
            if NSWorkspace.shared.open(url) { return }
        }
        log.error("could not open Screen Recording settings")
    }

    // MARK: - Pipeline

    /// A second trigger never starts a parallel capture or Vision pass. While
    /// the system selection UI is open nothing is raised, so the crosshair
    /// stays unobstructed; otherwise the running progress is brought forward.
    private func handleBusyTrigger() {
        guard store.phase != .capturing else { return }
        showInMainWindow()
    }

    private enum Input {
        case screen
        case clipboard
        case file(URL)

        var source: OCRSource {
            switch self {
            case .screen: return .screen
            case .clipboard: return .clipboard
            case .file: return .file
            }
        }
    }

    private func start(input: Input) {
        store.begin(input.source)
        activeTask = Task { [weak self] in
            guard let self else { return }
            await self.perform(input)
            self.activeTask = nil
            self.captureService = nil
        }
    }

    private func perform(_ input: Input) async {
        do {
            let data: Data
            switch input {
            case .screen:
                data = try await captureScreen()
            case .clipboard:
                data = try readClipboardImage()
            case .file(let url):
                data = try await readFileImage(url)
            }

            try Task.checkCancellation()
            store.attach(image: data)
            store.markRecognizing()
            showInMainWindow()

            let result = try await recognizer.recognize(imageData: data)
            try Task.checkCancellation()
            // The page already shows the result through `store`; presenting
            // again here would pull focus back if the user switched apps
            // while recognition ran.
            store.finish(result, image: data, source: input.source)
            log.info("ocr finished: \(result.lineCount, privacy: .public) lines")
        } catch is CancellationError {
            store.markCancelled()
            log.info("ocr run cancelled")
        } catch let error as ScreenCaptureError {
            if case .cancelled = error {
                // Esc in the system selection UI is a normal outcome, not an
                // error banner, and it must not pull a window forward.
                store.markCancelled()
            } else {
                store.fail(error.localizedDescription)
                showInMainWindow()
                log.error("screen capture failed: \(error.localizedDescription, privacy: .public)")
            }
        } catch {
            store.fail(error.localizedDescription)
            showInMainWindow()
            log.error("ocr failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Captures one interactive region while WorkDock's own windows are out of
    /// the way, and puts them back exactly as they were when the selection UI
    /// ends — by result, by error, or by Esc.
    private func captureScreen() async throws -> Data {
        hideWorkDockWindowsForCapture()
        defer { restoreWindowsHiddenForCapture() }
        let service = ScreenCaptureService()
        captureService = service
        return try await service.captureRegion()
    }

    // MARK: - Inputs

    private func readClipboardImage() throws -> Data {
        let pasteboard = NSPasteboard.general
        if let png = pasteboard.data(forType: .png), !png.isEmpty {
            return png
        }
        if let tiff = pasteboard.data(forType: .tiff), !tiff.isEmpty {
            return tiff
        }
        if let image = NSImage(pasteboard: pasteboard),
           let tiff = image.tiffRepresentation,
           !tiff.isEmpty {
            return tiff
        }
        throw OCRModuleError.clipboardEmpty
    }

    private func readFileImage(_ url: URL) async throws -> Data {
        let data: Data
        do {
            data = try await Task.detached(priority: .userInitiated) {
                try Data(contentsOf: url)
            }.value
        } catch {
            throw OCRModuleError.imageUnreadable(url.lastPathComponent)
        }
        guard !data.isEmpty else {
            throw OCRModuleError.imageUnreadable(url.lastPathComponent)
        }
        return data
    }

    // MARK: - Capture window occlusion

    /// Orders WorkDock's own content windows out before the system selection
    /// UI opens, so the app can never end up inside its own screenshot.
    ///
    /// Only windows this app owns are reachable from `NSApp.windows`, so the
    /// user's other windows and other apps are untouched. Menu, status-item,
    /// popover, and tooltip windows stay put: they are not key-capable
    /// normal-level windows, and ordering them out would disturb AppKit's own
    /// lifecycle.
    private func hideWorkDockWindowsForCapture() {
        guard windowsHiddenForCapture.isEmpty else { return }
        appWasActiveBeforeCapture = NSApp.isActive
        for window in NSApp.windows {
            guard window.isVisible, window.level == .normal, window.canBecomeKey else { continue }
            windowsHiddenForCapture.append((window: window, wasKey: window.isKeyWindow))
            window.orderOut(nil)
        }
        log.notice("hid \(self.windowsHiddenForCapture.count, privacy: .public) window(s) for capture")
    }

    /// Puts the windows hidden for a capture back, leaving focus where the
    /// user left it.
    ///
    /// When WorkDock was active before the capture, the window that was key
    /// becomes key again — this is the Esc-cancel path back to the page. A
    /// capture started while WorkDock was in the background restores the same
    /// windows without activating the app or stealing focus from whatever the
    /// user is doing.
    private func restoreWindowsHiddenForCapture() {
        let hidden = windowsHiddenForCapture
        let wasActive = appWasActiveBeforeCapture
        windowsHiddenForCapture.removeAll()
        appWasActiveBeforeCapture = false
        guard !hidden.isEmpty else { return }

        for entry in hidden {
            if wasActive, entry.wasKey {
                entry.window.makeKeyAndOrderFront(nil)
            } else {
                entry.window.orderFront(nil)
            }
        }
        if wasActive {
            activateForDialog()
        }
    }

    // MARK: - Permissions

    private func ensureScreenRecordingPermission() -> Bool {
        if CGPreflightScreenCaptureAccess() { return true }
        // Bring WorkDock forward so the system TCC prompt is visibly attached
        // to it. This only happens when permission has never been granted, so
        // normal captures never disturb the frontmost app.
        activateForDialog()
        // Surfaces the system prompt on first use. A previously denied process
        // is not re-prompted; the in-app banner then points to System Settings.
        if CGRequestScreenCaptureAccess() { return true }
        return false
    }

    private func activateForDialog() {
        if !NSApp.isActive {
            NSApp.activate()
        }
    }
}
