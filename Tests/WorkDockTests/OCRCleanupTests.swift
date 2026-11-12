import Foundation
import XCTest
@testable import WorkDock

/// Throwaway preferences for one test.
///
/// `OCRStore` persists the cleanup options in `UserDefaults`, so a test must
/// never borrow the app's suite: every instance owns a unique, empty domain
/// that ``dispose()`` erases again. Nothing here can read or write the
/// preferences of the machine running the tests.
private struct OCRTestPreferences {
    let suiteName: String
    let defaults: UserDefaults

    init() throws {
        let name = "cn.dylanliu.workdock.tests.ocr-cleanup.\(UUID().uuidString)"
        let domain = try XCTUnwrap(UserDefaults(suiteName: name))
        domain.removePersistentDomain(forName: name)
        suiteName = name
        defaults = domain
    }

    /// Erases everything the test persisted.
    func dispose() {
        defaults.removePersistentDomain(forName: suiteName)
    }
}

/// The two pre-recognition cleanup options: what they remove, that they start
/// off, that a choice survives a relaunch, and that changing one never rewrites
/// the result — or a manual edit — already on screen.
@MainActor
final class OCRCleanupTests: XCTestCase {
    /// Fixture for the exact-output tests: a space, a CRLF pair, an ideographic
    /// space, a tab, and a lone CR.
    private let sample = "a b\r\nc\u{3000}d\te\rf"

    private func recognition(_ text: String, lines: Int = 1) -> OCRRecognition {
        OCRRecognition(
            text: text,
            lineCount: lines,
            averageConfidence: 0.9,
            duration: 0.2,
            pixelWidth: 200,
            pixelHeight: 100)
    }

    // MARK: - Options

    func testBothOptionsAreOffByDefault() throws {
        let preferences = try OCRTestPreferences()
        defer { preferences.dispose() }

        let store = OCRStore(defaults: preferences.defaults)

        XCTAssertFalse(store.stripLineBreaks)
        XCTAssertFalse(store.stripSpaces)
        XCTAssertEqual(store.textCleanup, OCRTextCleanup.none)
    }

    func testPreferenceKeysAreStable() {
        XCTAssertEqual(OCRStore.stripLineBreaksKey, "ocr.stripLineBreaks")
        XCTAssertEqual(OCRStore.stripSpacesKey, "ocr.stripSpaces")
    }

    func testChoicesSurviveARelaunch() throws {
        let preferences = try OCRTestPreferences()
        defer { preferences.dispose() }

        let store = OCRStore(defaults: preferences.defaults)
        store.stripLineBreaks = true

        let relaunched = OCRStore(defaults: preferences.defaults)
        XCTAssertTrue(relaunched.stripLineBreaks)
        XCTAssertFalse(relaunched.stripSpaces, "each option persists on its own")

        relaunched.stripLineBreaks = false
        relaunched.stripSpaces = true

        let reopened = OCRStore(defaults: preferences.defaults)
        XCTAssertFalse(reopened.stripLineBreaks)
        XCTAssertTrue(reopened.stripSpaces)
    }

    // MARK: - Transformation

    func testNoOptionsKeepTheRawText() {
        XCTAssertEqual(OCRTextCleanup.none.apply(to: sample), sample)
    }

    func testLineBreaksOptionRemovesCRAndLFOnly() {
        let cleanup = OCRTextCleanup(stripLineBreaks: true, stripSpaces: false)
        XCTAssertEqual(cleanup.apply(to: sample), "a bc\u{3000}d\tef")
        XCTAssertEqual(cleanup.apply(to: "line1\r\nline2"), "line1line2")
    }

    func testSpacesOptionRemovesSpacesOnly() {
        let cleanup = OCRTextCleanup(stripLineBreaks: false, stripSpaces: true)
        XCTAssertEqual(cleanup.apply(to: sample), "ab\r\ncd\te\rf")
        XCTAssertEqual(cleanup.apply(to: "福建 省\u{3000}厅"), "福建省厅")
    }

    func testBothOptionsRemoveEverythingTheyCover() {
        let cleanup = OCRTextCleanup(stripLineBreaks: true, stripSpaces: true)
        XCTAssertEqual(cleanup.apply(to: sample), "abcd\tef")
        XCTAssertEqual(cleanup.apply(to: ""), "")
    }

    // MARK: - Result handoff

    func testResultIsCleanedWhenItArrives() throws {
        let preferences = try OCRTestPreferences()
        defer { preferences.dispose() }

        let store = OCRStore(defaults: preferences.defaults)
        store.stripLineBreaks = true
        store.stripSpaces = true

        store.begin(.clipboard)
        store.finish(
            recognition("福建 省\r\n教育厅"),
            image: OCRTestImages.blankPNG(),
            source: .clipboard)

        XCTAssertEqual(store.text, "福建省教育厅")
        XCTAssertEqual(store.phase, .finished)
    }

    func testStatisticsKeepTheRawRecognition() throws {
        let preferences = try OCRTestPreferences()
        defer { preferences.dispose() }

        let store = OCRStore(defaults: preferences.defaults)
        store.stripSpaces = true
        let raw = recognition("a b", lines: 2)

        store.finish(raw, image: OCRTestImages.blankPNG(), source: .file)

        XCTAssertEqual(store.text, "ab")
        XCTAssertEqual(store.recognition, raw, "the statistics describe the raw pass")
        XCTAssertEqual(store.recognition?.text, "a b")
        XCTAssertEqual(store.recognition?.lineCount, 2)
    }

    func testOptionEnabledDuringARunAppliesToThatResult() throws {
        let preferences = try OCRTestPreferences()
        defer { preferences.dispose() }

        let store = OCRStore(defaults: preferences.defaults)
        store.begin(.clipboard)

        // The run is in flight; its result has not reached the editor yet, so
        // it is still a "new" result and the option applies to it.
        store.stripLineBreaks = true
        store.finish(
            recognition("line1\r\nline2"),
            image: OCRTestImages.blankPNG(),
            source: .clipboard)

        XCTAssertEqual(store.text, "line1line2")
    }

    func testChangingAnOptionLeavesTheCurrentResultAndManualEditsAlone() throws {
        let preferences = try OCRTestPreferences()
        defer { preferences.dispose() }

        let store = OCRStore(defaults: preferences.defaults)
        let raw = "第一行 有空格\r\n第二行"

        store.finish(recognition(raw, lines: 2), image: OCRTestImages.blankPNG(), source: .screen)
        XCTAssertEqual(store.text, raw, "with both options off the result arrives verbatim")

        store.text = "手动改过的文本"
        store.stripLineBreaks = true
        store.stripSpaces = true
        XCTAssertEqual(store.text, "手动改过的文本", "a toggle must not rewrite the editor")

        // Only the next recognition goes through the options.
        store.finish(recognition(raw, lines: 2), image: OCRTestImages.blankPNG(), source: .screen)
        XCTAssertEqual(store.text, "第一行有空格第二行")
    }
}
