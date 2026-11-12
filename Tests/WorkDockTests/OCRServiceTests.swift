import Foundation
import XCTest
@testable import WorkDock

// MARK: - Error contract

final class OCRServiceErrorTests: XCTestCase {
    func testUndecodableInputSharesOneDecodeMessage() {
        XCTAssertEqual(OCRServiceError.emptyImage.errorDescription, L.ocrImageInvalid)
        XCTAssertEqual(OCRServiceError.invalidImage.errorDescription, L.ocrImageInvalid)
    }

    func testMissingTextHasItsOwnMessage() {
        XCTAssertEqual(OCRServiceError.noTextFound.errorDescription, L.ocrNoText)
        XCTAssertNotEqual(
            OCRServiceError.noTextFound.errorDescription,
            OCRServiceError.invalidImage.errorDescription)
    }

    func testRecognitionFailureCarriesTheReason() {
        let description = OCRServiceError.recognitionFailed("model unavailable").errorDescription
        XCTAssertTrue((description ?? "").contains("model unavailable"))
    }
}

// MARK: - Input handling

final class OCRServiceInputTests: XCTestCase {
    private let service = OCRService()

    func testEmptyDataIsRejectedAsAnEmptyImage() async {
        let error = await recognizeFailure(Data())
        guard let serviceError = error as? OCRServiceError, case .emptyImage = serviceError else {
            XCTFail("expected .emptyImage, got \(String(describing: error))")
            return
        }
    }

    func testNonImageDataIsRejectedAsAnInvalidImage() async {
        let error = await recognizeFailure(Data("this is not an image".utf8))
        guard let serviceError = error as? OCRServiceError, case .invalidImage = serviceError else {
            XCTFail("expected .invalidImage, got \(String(describing: error))")
            return
        }
    }

    func testImageWithoutGlyphsIsRejectedAsMissingText() async {
        let error = await recognizeFailure(OCRTestImages.blankPNG())
        guard let serviceError = error as? OCRServiceError, case .noTextFound = serviceError else {
            XCTFail("expected .noTextFound, got \(String(describing: error))")
            return
        }
    }

    /// Cancellation is checked before any validation: a cancelled run reports
    /// cancellation, never a misleading image error.
    func testAlreadyCancelledCallThrowsCancellationInsteadOfValidatingInput() async {
        let service = OCRService()
        let outcome = await Task { () -> Outcome in
            withUnsafeCurrentTask { $0?.cancel() }
            do {
                _ = try await service.recognize(imageData: Data())
                return .recognized
            } catch is CancellationError {
                return .cancelled
            } catch {
                return .other(String(describing: error))
            }
        }.value
        XCTAssertEqual(outcome, .cancelled, "a cancelled run must not report an image error")
    }

    private enum Outcome: Equatable, Sendable {
        case recognized
        case cancelled
        case other(String)
    }

    private func recognizeFailure(_ data: Data) async -> Error? {
        do {
            _ = try await service.recognize(imageData: data)
            return nil
        } catch {
            return error
        }
    }
}

// MARK: - Real Vision pass

/// Runs the actual Vision pipeline on a committed bilingual fixture. No screen,
/// clipboard, or user file is involved.
final class OCRServiceVisionTests: XCTestCase {
    func testRecognizesEnglishAndSimplifiedChineseText() async throws {
        let data = try OCRTestImages.bilingualFixture()
        let result = try await OCRService().recognize(imageData: data)

        XCTAssertEqual(result.pixelWidth, 1040, "recognition must report the source image width")
        XCTAssertEqual(result.pixelHeight, 340, "recognition must report the source image height")
        XCTAssertGreaterThan(result.lineCount, 0)
        XCTAssertGreaterThan(result.averageConfidence, 0.3, "fixture text should be read confidently")

        // Line breaks and spacing are layout, not content: compare without
        // whitespace so harmless re-layout never fails the test while a missing
        // language still does.
        let compact = Self.compacted(result.text)
        XCTAssertTrue(
            compact.contains("workdock"),
            "English text missing from recognition: \(result.text)")
        XCTAssertTrue(
            compact.contains("ocr"),
            "English text missing from recognition: \(result.text)")
        XCTAssertTrue(
            compact.contains("福建省教育厅"),
            "Simplified Chinese text missing from recognition: \(result.text)")
        XCTAssertTrue(
            compact.contains("收文提醒"),
            "Simplified Chinese text missing from recognition: \(result.text)")
    }

    /// Lowercased with every whitespace and newline removed.
    private static func compacted(_ text: String) -> String {
        text.lowercased().components(separatedBy: .whitespacesAndNewlines).joined()
    }
}
