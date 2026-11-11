import Foundation

enum ScreenCaptureError: LocalizedError {
    case cancelled
    case busy
    case launchFailed(String)
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .cancelled:
            return L.ocrCancelled
        case .busy:
            return L.ocrCaptureBusy
        case .launchFailed(let reason), .failed(let reason):
            return L.ocrCaptureFailed(reason)
        }
    }
}

/// Runs the system `screencapture` tool in interactive region mode.
///
/// The system utility supplies the native crosshair, multi-display selection,
/// and Esc-to-cancel behaviour, so WorkDock does not reimplement an overlay.
/// One instance performs exactly one capture; the module creates a fresh
/// service per run and keeps it only to support cancellation.
///
/// Cancellation terminates the child process. A capture the user cancels
/// produces no output file and is reported as ``ScreenCaptureError/cancelled``
/// — never as a hard error.
final class ScreenCaptureService: @unchecked Sendable {
    private let lock = NSLock()
    private var process: Process?
    private var running = false
    private var cancelRequested = false
    private var resumed = false

    /// Presents the system selection UI and returns the PNG bytes of the
    /// chosen region.
    func captureRegion() async throws -> Data {
        let outputURL = try Self.makeOutputURL()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        process.arguments = ["-i", "-s", "-x", "-t", "png", outputURL.path]
        let errorPipe = Pipe()
        process.standardError = errorPipe

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Data, Error>) in
                lock.lock()
                guard self.process == nil else {
                    lock.unlock()
                    Self.remove(outputURL)
                    continuation.resume(throwing: ScreenCaptureError.busy)
                    return
                }
                if cancelRequested {
                    lock.unlock()
                    Self.remove(outputURL)
                    continuation.resume(throwing: CancellationError())
                    return
                }
                self.process = process
                lock.unlock()

                process.terminationHandler = { [self] _ in
                    let data = try? Data(contentsOf: outputURL)
                    let errorText = Self.readError(errorPipe)
                    Self.remove(outputURL)

                    lock.lock()
                    running = false
                    self.process = nil
                    let cancelled = cancelRequested
                    let alreadyResumed = resumed
                    resumed = true
                    lock.unlock()
                    guard !alreadyResumed else { return }

                    if cancelled {
                        continuation.resume(throwing: CancellationError())
                    } else if let data, !data.isEmpty {
                        continuation.resume(returning: data)
                    } else if !errorText.isEmpty {
                        continuation.resume(throwing: ScreenCaptureError.failed(errorText))
                    } else {
                        // Esc in the system selection UI exits without
                        // producing a file; report it as a normal cancellation
                        // and never as a hard error.
                        continuation.resume(throwing: ScreenCaptureError.cancelled)
                    }
                }

                do {
                    try process.run()
                } catch {
                    Self.remove(outputURL)
                    lock.lock()
                    self.process = nil
                    let alreadyResumed = resumed
                    resumed = true
                    lock.unlock()
                    guard !alreadyResumed else { return }
                    continuation.resume(throwing: ScreenCaptureError.launchFailed(error.localizedDescription))
                    return
                }

                lock.lock()
                if resumed {
                    // The process can exit (and resume the continuation)
                    // before `run()` returns; never resurrect its state.
                    lock.unlock()
                    return
                }
                running = true
                let shouldTerminate = cancelRequested
                lock.unlock()
                if shouldTerminate {
                    process.terminate()
                }
            }
        } onCancel: {
            self.cancel()
        }
    }

    /// Terminates an in-flight capture. Safe from any thread; no-op afterwards.
    func cancel() {
        lock.lock()
        cancelRequested = true
        let active = running ? process : nil
        lock.unlock()
        if let active, active.isRunning {
            active.terminate()
        }
    }

    private static func readError(_ pipe: Pipe) -> String {
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(decoding: data, as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func makeOutputURL() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("WorkDockOCR", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("capture-\(UUID().uuidString).png")
    }

    private static func remove(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }
}
