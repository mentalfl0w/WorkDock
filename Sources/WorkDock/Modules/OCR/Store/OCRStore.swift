import AppKit
import Combine
import Foundation

/// Observable state shared by the module page and the floating result panel.
///
/// The module owns exactly one store; both surfaces observe it, so a run
/// started from a global shortcut is visible everywhere at once.
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

    /// Editable recognition result. The panel and the module page edit the
    /// same value. The image stays in memory with it and is discarded on quit.
    @Published var text: String = ""
    @Published private(set) var imageData: Data?
    @Published private(set) var phase: Phase = .idle
    @Published private(set) var recognition: OCRRecognition?
    @Published private(set) var permissionBlocked = false
    @Published private(set) var lastSource: OCRSource = .screen
    @Published private(set) var copied = false

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

    func finish(_ result: OCRRecognition, image data: Data, source: OCRSource) {
        text = result.text
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
