import Foundation
import XCTest
@testable import WorkDock

/// The OCR page's shared state machine. One store drives every surface, so
/// these transitions are the module's contract with its UI.
@MainActor
final class OCRStoreTests: XCTestCase {
    private var suiteNames: [String] = []

    override func tearDown() async throws {
        for suiteName in suiteNames {
            UserDefaults.standard.removePersistentDomain(forName: suiteName)
        }
        suiteNames.removeAll()
        try await super.tearDown()
    }

    /// Each store gets an empty preference domain, never the app's defaults.
    private func makeStore() -> OCRStore {
        let suiteName = "cn.dylanliu.workdock.tests.ocr-store.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        suiteNames.append(suiteName)
        return OCRStore(defaults: defaults)
    }

    private func result(
        text: String = "recognized",
        lines: Int = 1
    ) -> OCRRecognition {
        OCRRecognition(
            text: text,
            lineCount: lines,
            averageConfidence: 0.9,
            duration: 0.25,
            pixelWidth: 240,
            pixelHeight: 120)
    }

    // MARK: - Initial state

    func testFreshStoreIsIdleWithoutResultOrImage() {
        let store = makeStore()
        XCTAssertEqual(store.phase, .idle)
        XCTAssertFalse(store.isBusy)
        XCTAssertFalse(store.permissionBlocked)
        XCTAssertFalse(store.copied)
        XCTAssertEqual(store.text, "")
        XCTAssertNil(store.recognition)
        XCTAssertNil(store.sourceImage)
        XCTAssertEqual(store.lastSource, .screen)
    }

    // MARK: - Run lifecycle

    func testScreenRunStartsByWaitingForTheSelection() {
        let store = makeStore()
        store.begin(.screen)
        XCTAssertEqual(store.phase, .capturing)
        XCTAssertTrue(store.isBusy)
        XCTAssertEqual(store.lastSource, .screen)
    }

    func testClipboardAndFileRunsStartRecognizingDirectly() {
        for source in [OCRSource.clipboard, .file] {
            let store = makeStore()
            store.begin(source)
            XCTAssertEqual(store.phase, .recognizing, "\(source) has no selection step")
            XCTAssertTrue(store.isBusy)
            XCTAssertEqual(store.lastSource, source)
        }
    }

    func testAttachPublishesThePreviewWithoutEndingTheRun() {
        let store = makeStore()
        let image = OCRTestImages.blankPNG()
        store.begin(.clipboard)
        store.attach(image: image)
        XCTAssertNotNil(store.sourceImage)
        XCTAssertTrue(store.isBusy)

        store.markRecognizing()
        XCTAssertEqual(store.phase, .recognizing)
        XCTAssertTrue(store.isBusy)
    }

    func testFinishPublishesResultImageAndSource() {
        let store = makeStore()
        let image = OCRTestImages.blankPNG()
        let recognition = result(text: "福建省教育厅", lines: 3)

        store.begin(.file)
        store.finish(recognition, image: image, source: .file)

        XCTAssertEqual(store.phase, .finished)
        XCTAssertFalse(store.isBusy)
        XCTAssertEqual(store.text, recognition.text)
        XCTAssertEqual(store.recognition, recognition)
        XCTAssertEqual(store.lastSource, .file)
        XCTAssertNotNil(store.sourceImage)
    }

    func testFinishReplacesThePreviousRun() {
        let store = makeStore()
        let first = result(text: "first")
        let second = result(text: "second", lines: 2)

        store.finish(first, image: OCRTestImages.blankPNG(), source: .screen)
        store.finish(second, image: OCRTestImages.blankPNG(), source: .clipboard)

        XCTAssertEqual(store.text, "second")
        XCTAssertEqual(store.recognition, second)
        XCTAssertEqual(store.lastSource, .clipboard)
    }

    func testFailureStopsTheRunAndCarriesTheMessage() {
        let store = makeStore()
        store.begin(.screen)
        store.fail("capture failed")

        XCTAssertEqual(store.phase, .failed("capture failed"))
        XCTAssertFalse(store.isBusy)
    }

    func testCancelledRunStopsBusyWithoutAnError() {
        let store = makeStore()
        store.begin(.screen)
        store.markCancelled()

        XCTAssertEqual(store.phase, .cancelled)
        XCTAssertFalse(store.isBusy)
    }

    // MARK: - Permission guidance

    func testRequirePermissionShowsGuidanceAndReturnsToIdle() {
        let store = makeStore()
        store.begin(.screen)
        store.requirePermission()

        XCTAssertTrue(store.permissionBlocked)
        XCTAssertEqual(store.phase, .idle)
        XCTAssertFalse(store.isBusy)
    }

    func testStartingASupportedInputClearsStalePermissionGuidance() {
        let store = makeStore()
        store.requirePermission()
        store.begin(.clipboard)
        XCTAssertFalse(store.permissionBlocked)
        XCTAssertEqual(store.phase, .recognizing)
    }

    func testFinishClearsStalePermissionGuidance() {
        let store = makeStore()
        store.requirePermission()
        store.finish(result(), image: OCRTestImages.blankPNG(), source: .file)
        XCTAssertFalse(store.permissionBlocked)
        XCTAssertEqual(store.phase, .finished)
    }

    // MARK: - Clipboard

    func testCopyingEmptyTextIsIgnored() {
        let store = makeStore()
        store.copyText()
        XCTAssertFalse(store.copied)
    }

    // MARK: - Phase presentation

    func testOnlyCaptureAndRecognitionAreBusy() {
        XCTAssertTrue(OCRStore.Phase.capturing.isBusy)
        XCTAssertTrue(OCRStore.Phase.recognizing.isBusy)
        for phase in [OCRStore.Phase.idle, .finished, .cancelled, .failed("x")] {
            XCTAssertFalse(phase.isBusy, "\(phase) must not block a new run")
        }
    }

}
