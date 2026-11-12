import AppKit
import Combine
import Foundation

/// Observable state for the OCR module page.
///
/// The module owns exactly one store and the page observes it, so a run
/// started from a menu item or a global shortcut is visible as soon as the
/// page is shown. There is no second result surface.
///
/// Results are memory-only. Nothing is written to disk, and closing the app
/// discards the current image and text.
@MainActor
final class OCRStore: ObservableObject {
    enum Phase: Equatable {
        case idle
        case capturing
        case recognizing
        case finished
        case cancelled
        case failed(String)

        var isBusy: Bool { self == .capturing || self == .recognizing }
    }

    /// Editable recognition result shown by the module page. The image stays
    /// in memory with it and is discarded on quit.
    @Published var text: String = ""
    @Published private(set) var imageData: Data?
    @Published private(set) var phase: Phase = .idle
    @Published private(set) var recognition: OCRRecognition?
    @Published private(set) var permissionBlocked = false
    @Published private(set) var lastSource: OCRSource = .screen
    @Published private(set) var copied = false

    // MARK: - Cleanup preferences

    /// Stable `UserDefaults` keys for the two cleanup options. Dotted and
    /// OCR-scoped so they cannot collide with the framework or another module.
    nonisolated static let stripLineBreaksKey = "ocr.stripLineBreaks"
    nonisolated static let stripSpacesKey = "ocr.stripSpaces"

    /// Drop line breaks from the next recognition result. Off by default.
    ///
    /// The choice is persisted right away but read only when a result arrives,
    /// so toggling it never edits the text already in the editor.
    @Published var stripLineBreaks: Bool {
        didSet {
            guard stripLineBreaks != oldValue else { return }
            defaults.set(stripLineBreaks, forKey: Self.stripLineBreaksKey)
        }
    }

    /// Drop spaces from the next recognition result. Off by default.
    @Published var stripSpaces: Bool {
        didSet {
            guard stripSpaces != oldValue else { return }
            defaults.set(stripSpaces, forKey: Self.stripSpacesKey)
        }
    }

    /// Cleanup the next result goes through, from the current options.
    var textCleanup: OCRTextCleanup {
        OCRTextCleanup(stripLineBreaks: stripLineBreaks, stripSpaces: stripSpaces)
    }

    private let defaults: UserDefaults

    /// - Parameter defaults: Preference store holding the cleanup options.
    ///   Injected so tests use a throwaway suite instead of the app's
    ///   preferences; the app passes the standard suite.
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.stripLineBreaks = defaults.bool(forKey: Self.stripLineBreaksKey)
        self.stripSpaces = defaults.bool(forKey: Self.stripSpacesKey)
    }

    var isBusy: Bool { phase.isBusy }

    /// Decoded preview of the source image.
    var sourceImage: NSImage? {
        guard let imageData else { return nil }
        return NSImage(data: imageData)
    }

    private var copyResetTask: Task<Void, Never>?

    // MARK: - Run lifecycle

    func begin(_ source: OCRSource) {
        lastSource = source
        permissionBlocked = false
        copied = false
        phase = source == .screen ? .capturing : .recognizing
    }

    func attach(image data: Data) {
        imageData = data
    }

    func markRecognizing() {
        phase = .recognizing
    }

    /// Publishes a completed run.
    ///
    /// The raw Vision text stays in ``recognition`` for the statistics; the
    /// editable field receives the same text after the cleanup options are
    /// applied. The options are read here, once, so a later toggle can neither
    /// rewrite this result nor a manual edit on top of it.
    func finish(_ result: OCRRecognition, image data: Data, source: OCRSource) {
        text = textCleanup.apply(to: result.text)
        recognition = result
        imageData = data
        lastSource = source
        permissionBlocked = false
        phase = .finished
    }

    func fail(_ message: String) {
        phase = .failed(message)
    }

    func markCancelled() {
        phase = .cancelled
    }

    func requirePermission() {
        permissionBlocked = true
        phase = .idle
    }

    // MARK: - Clipboard

    func copyText() {
        guard !text.isEmpty else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        copied = true
        copyResetTask?.cancel()
        copyResetTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(1.5))
            guard !Task.isCancelled else { return }
            self?.copied = false
        }
    }
}
