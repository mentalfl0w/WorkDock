import CoreGraphics
import Foundation
import ImageIO
import Vision

enum OCRServiceError: LocalizedError {
    case emptyImage
    case invalidImage
    case noTextFound
    case recognitionFailed(String)

    var errorDescription: String? {
        switch self {
        case .emptyImage, .invalidImage:
            return L.ocrImageInvalid
        case .noTextFound:
            return L.ocrNoText
        case .recognitionFailed(let reason):
            return L.ocrRecognitionFailed(reason)
        }
    }
}

/// Serializes local Vision text recognition.
///
/// An actor so back-to-back triggers cannot pile up Vision work on the
/// cooperative pool; a detached task keeps the synchronous Vision call off the
/// main actor. No network access is involved.
actor OCRService {
    /// Recognizes Simplified Chinese + English text in `imageData`.
    ///
    /// - Throws: ``OCRServiceError`` for undecodable/empty images or when no
    ///   text is found, and `CancellationError` if the calling task is cancelled
    ///   before the result is consumed.
    func recognize(imageData: Data) async throws -> OCRRecognition {
        try Task.checkCancellation()
        let task = Task.detached(priority: .userInitiated) {
            try Self.recognizeSynchronously(imageData)
        }
        return try await withTaskCancellationHandler {
            try await task.value
        } onCancel: {
            // Vision's synchronous pass cannot be interrupted mid-flight; the
            // result is discarded because the awaiting task is cancelled.
            task.cancel()
        }
    }

    private static func recognizeSynchronously(_ data: Data) throws -> OCRRecognition {
        guard !data.isEmpty else { throw OCRServiceError.emptyImage }
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw OCRServiceError.invalidImage
        }

        let startedAt = Date()
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        // Domain knowledge: WorkDock is a Chinese/English workflow. Listing
        // Simplified Chinese first makes mixed CJK + Latin text come out right.
        request.recognitionLanguages = ["zh-Hans", "en-US"]
        // Vision's language correction is not supported for Chinese; enabling
        // it can distort mixed CJK + Latin results, so keep raw recognition.
        request.usesLanguageCorrection = false
        request.automaticallyDetectsLanguage = false
        request.minimumTextHeight = 0

        let handler = VNImageRequestHandler(
            cgImage: image,
            orientation: orientation(of: source),
            options: [:])
        do {
            try handler.perform([request])
        } catch {
            throw OCRServiceError.recognitionFailed(error.localizedDescription)
        }
        try Task.checkCancellation()

        let observations = request.results ?? []
        let lines: [RecognizedLine] = observations.compactMap { observation in
            guard let candidate = observation.topCandidates(1).first else { return nil }
            return RecognizedLine(
                text: candidate.string,
                confidence: candidate.confidence,
                box: observation.boundingBox)
        }
        guard !lines.isEmpty else { throw OCRServiceError.noTextFound }

        // Vision's bounding boxes use a bottom-left origin. Build reading
        // order deterministically in two passes:
        // 1. strict top-to-bottom sort (midY descending, minX tie-break) — the
        //    comparator has no tolerance, so it is a valid strict weak order;
        // 2. group consecutive lines into visual rows using the first line as
        //    the row anchor, then order each row left-to-right.
        // Anchor-based grouping keeps the row decision transitive instead of
        // comparing every pair with a tolerance.
        let rowTolerance: CGFloat = 0.005
        let byPosition = lines.sorted { lhs, rhs in
            if lhs.box.midY == rhs.box.midY {
                return lhs.box.minX < rhs.box.minX
            }
            return lhs.box.midY > rhs.box.midY
        }

        var rows: [[RecognizedLine]] = []
        var currentRow: [RecognizedLine] = []
        var rowAnchorY: CGFloat = 0
        for line in byPosition {
            if currentRow.isEmpty {
                currentRow = [line]
                rowAnchorY = line.box.midY
            } else if abs(rowAnchorY - line.box.midY) <= rowTolerance {
                currentRow.append(line)
            } else {
                rows.append(currentRow)
                currentRow = [line]
                rowAnchorY = line.box.midY
            }
        }
        if !currentRow.isEmpty {
            rows.append(currentRow)
        }

        let ordered = rows.flatMap { row in
            row.sorted { lhs, rhs in
                if lhs.box.minX == rhs.box.minX {
                    return lhs.box.midY > rhs.box.midY
                }
                return lhs.box.minX < rhs.box.minX
            }
        }

        let text = ordered.map(\.text).joined(separator: "\n")
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw OCRServiceError.noTextFound
        }
        let confidence = ordered.reduce(0.0) { $0 + Double($1.confidence) } / Double(ordered.count)
        return OCRRecognition(
            text: text,
            lineCount: ordered.count,
            averageConfidence: confidence,
            duration: Date().timeIntervalSince(startedAt),
            pixelWidth: image.width,
            pixelHeight: image.height)
    }

    /// Respects EXIF orientation so photos and rotated screenshots are read in
    /// their displayed orientation.
    private static func orientation(of source: CGImageSource) -> CGImagePropertyOrientation {
        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let raw = properties[kCGImagePropertyOrientation] as? NSNumber,
              let orientation = CGImagePropertyOrientation(rawValue: raw.uint32Value) else {
            return .up
        }
        return orientation
    }

    private struct RecognizedLine {
        let text: String
        let confidence: Float
        let box: CGRect
    }
}
