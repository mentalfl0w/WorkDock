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
    private lazy var resultPanel = OCRResultPanelController(module: self)

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
                self?.presentResultPanel()
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
        resultPanel.close()
    }

    // MARK: - Trigger API (main-thread callable)

    /// Starts an interactive region screenshot followed by OCR.
    ///
    /// This is the public entry point for the menu bar, the module page, and
    /// the external hotkey manager. It is main-actor isolated, returns
    /// immediately, and publishes progress through ``store`` plus the floating
    /// result panel. While a run is in flight a new trigger is ignored rather
    /// than queued.
    public func triggerScreenshot() {
        guard activeTask == nil else {
            handleBusyTrigger()
            return
        }
        guard ensureScreenRecordingPermission() else {
            store.requirePermission()
            presentResultPanel()
            log.notice("screenshot blocked: screen recording permission missing")
            return
        }
        resultPanel.close()
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

    /// Shows the floating result/editor panel, creating it on first use and
    /// reusing it afterwards.
    public func presentResultPanel() {
        activateForDialog()
        resultPanel.show()
    }

    /// Deep-links into this module's full page (settings and hotkey slot)
    /// through the framework's single navigation path.
    public func showInMainWindow() {
        router.openMainWindow()
        router.navigate(moduleID: id)
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
    /// the system selection UI is open the panel stays hidden so it cannot
    /// cover the crosshair; otherwise the existing progress is brought forward.
    private func handleBusyTrigger() {
        guard store.phase != .capturing else { return }
        presentResultPanel()
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
                let service = ScreenCaptureService()
                captureService = service
                data = try await service.captureRegion()
            case .clipboard:
                data = try readClipboardImage()
            case .file(let url):
                data = try await readFileImage(url)
            }

            try Task.checkCancellation()
            store.attach(image: data)
            store.markRecognizing()
            presentResultPanel()

            let result = try await recognizer.recognize(imageData: data)
            try Task.checkCancellation()
            store.finish(result, image: data, source: input.source)
            log.info("ocr finished: \(result.lineCount, privacy: .public) lines")
        } catch is CancellationError {
            store.markCancelled()
            log.info("ocr run cancelled")
        } catch let error as ScreenCaptureError {
            if case .cancelled = error {
                // Esc in the system selection UI is a normal outcome, not an
                // error banner.
                store.markCancelled()
            } else {
                store.fail(error.localizedDescription)
                presentResultPanel()
                log.error("screen capture failed: \(error.localizedDescription, privacy: .public)")
            }
        } catch {
            store.fail(error.localizedDescription)
            presentResultPanel()
            log.error("ocr failed: \(error.localizedDescription, privacy: .public)")
        }
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
