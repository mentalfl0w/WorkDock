import AppKit
import Foundation
import SwiftUI

/// Opt-in GUI smoke probe for the Screenshot OCR page.
///
/// A smoke run is a separately packaged app with its own bundle identifier and
/// a throwaway home directory, launched by `gui-smoke.sh`. This code ships in
/// the normal binary but is inert unless that launcher sets ``modeVariable``:
/// a regular launch never reads the environment, never records a control, and
/// never writes a report.
///
/// The probe inspects only this process's own window and views. It never runs
/// OCR, never captures the screen, and never asks for Accessibility, Screen
/// Recording, or notification permission.
enum GUISmoke {
    /// Environment variables set by the launcher. Any other value, or no
    /// value, leaves the probe off.
    static let modeVariable = "WORKDOCK_GUI_SMOKE"
    static let outputVariable = "WORKDOCK_GUI_SMOKE_OUTPUT"
    static let expectedBundleIdentifierVariable = "WORKDOCK_GUI_SMOKE_BUNDLE_ID"

    enum Mode: String, Sendable {
        /// Navigate to the OCR page, shrink the window to its minimum, report.
        case ocrPage = "ocr-page"
    }

    static let mode: Mode? = ProcessInfo.processInfo.environment[modeVariable]
        .flatMap { Mode(rawValue: $0) }

    static var isEnabled: Bool { mode != nil }

    static var outputURL: URL? {
        ProcessInfo.processInfo.environment[outputVariable].map { URL(fileURLWithPath: $0) }
    }

    static var expectedBundleIdentifier: String? {
        ProcessInfo.processInfo.environment[expectedBundleIdentifierVariable]
    }
}

/// Language-independent identifiers the smoke run asserts on.
///
/// They are also the accessibility identifiers of the same controls, so a
/// screen reader or a future UI test addresses a control by the same string the
/// smoke run expects — the two cannot drift apart.
enum GUISmokeID {
    static let ocrScreenshotAction = "ocr.action.screenshot"
    static let ocrClipboardAction = "ocr.action.clipboard"
    static let ocrImageFileAction = "ocr.action.image"
    static let ocrEditor = "ocr.editor"
    static let ocrPageScroll = "ocr.page"
    /// Pre-recognition option: drop CR/LF from a new result.
    static let ocrStripLineBreaksOption = "ocr.option.strip-line-breaks"
    /// Pre-recognition option: drop spaces from a new result.
    static let ocrStripSpacesOption = "ocr.option.strip-spaces"

    /// Controls the OCR page must expose for the smoke run to pass.
    ///
    /// The two option toggles are part of the page's control surface: the smoke
    /// run fails until the page tags them with `guiSmokeIdentified(_:)`.
    static let requiredOCRPage: [String] = [
        ocrScreenshotAction,
        ocrClipboardAction,
        ocrImageFileAction,
        ocrEditor,
        ocrPageScroll,
        ocrStripLineBreaksOption,
        ocrStripSpacesOption,
    ]
}

/// What the app actually laid out, recorded only while the probe is enabled.
///
/// The probe lives inside the process because a GUI harness outside it would
/// need Accessibility permission to read another app's controls. Reading the
/// values the views publish keeps the check permission-free and deterministic.
@MainActor
final class GUISmokeRecorder {
    static let shared = GUISmokeRecorder()

    private(set) var identifiers: Set<String> = []
    private(set) var contentHeight: CGFloat?
    private(set) var viewportHeight: CGFloat?

    func note(identifier: String) {
        guard GUISmoke.isEnabled else { return }
        identifiers.insert(identifier)
    }

    func note(contentHeight height: CGFloat) {
        guard GUISmoke.isEnabled else { return }
        contentHeight = height
    }

    func note(viewportHeight height: CGFloat) {
        guard GUISmoke.isEnabled else { return }
        viewportHeight = height
    }
}

extension View {
    /// Tags a control with its language-independent identifier and reports its
    /// appearance to the smoke probe.
    func guiSmokeIdentified(_ identifier: String) -> some View {
        modifier(GUISmokeIdentifierModifier(identifier: identifier))
    }

    /// Reports the height of the scroll content to the smoke probe.
    func guiSmokeContentHeight() -> some View {
        modifier(GUISmokeHeightModifier(isContent: true))
    }

    /// Reports the height of the scroll viewport to the smoke probe.
    func guiSmokeViewportHeight() -> some View {
        modifier(GUISmokeHeightModifier(isContent: false))
    }
}

private struct GUISmokeIdentifierModifier: ViewModifier {
    let identifier: String

    func body(content: Content) -> some View {
        content
            .accessibilityIdentifier(identifier)
            .onAppear { GUISmokeRecorder.shared.note(identifier: identifier) }
    }
}

private struct GUISmokeHeightModifier: ViewModifier {
    let isContent: Bool

    func body(content: Content) -> some View {
        content.onGeometryChange(for: CGFloat.self) { proxy in
            proxy.size.height
        } action: { height in
            if isContent {
                GUISmokeRecorder.shared.note(contentHeight: height)
            } else {
                GUISmokeRecorder.shared.note(viewportHeight: height)
            }
        }
    }
}

// MARK: - Report

/// Machine-readable result of one smoke run. `gui-smoke.sh` validates it.
struct GUISmokeReport: Codable {
    struct Size: Codable {
        let width: Double
        let height: Double

        init(_ size: CGSize) {
            width = size.width
            height = size.height
        }
    }

    struct Window: Codable {
        let isMain: Bool
        let isVisible: Bool
        let level: Int
        let canBecomeKey: Bool
        let contentSize: Size
    }

    let schemaVersion: Int
    let bundleIdentifier: String?
    let expectedBundleIdentifier: String?
    let processIdentifier: Int32
    let homeDirectory: String
    let userFacingWindowCount: Int
    let mainWindowCount: Int
    let windows: [Window]
    let minContentSize: Size?
    let requestedContentSize: Size?
    let appliedContentSize: Size?
    let identifiers: [String]
    let missingIdentifiers: [String]
    let contentHeight: Double?
    let viewportHeight: Double?
    let isScrollable: Bool
    let ocrPhase: String
    let failures: [String]
}

// MARK: - Run

extension GUISmoke {
    /// Drives the app to the OCR page, shrinks the window to the smallest size
    /// the app allows, and writes the report. Called from
    /// `AppContainer.bootstrap()` and nowhere else.
    @MainActor
    static func run(router: NavigationRouter, registry: ModuleRegistry) async {
        guard mode == .ocrPage else { return }
        guard let outputURL else {
            FileHandle.standardError.write(Data("gui smoke: \(outputVariable) is not set\n".utf8))
            exit(EXIT_FAILURE)
        }

        let recorder = GUISmokeRecorder.shared
        var failures: [String] = []

        router.navigate(moduleID: OCRModule.moduleID)
        router.openMainWindow()

        // The window scene appears asynchronously; SwiftUI may even rebuild it
        // from the pending request, so poll instead of assuming it exists.
        let window = await firstMainWindow(timeout: .seconds(20))
        if window == nil {
            failures.append("the main window did not appear within 20s")
        }

        _ = await waitUntil(timeout: .seconds(15)) {
            let recorded = recorder.identifiers
            return GUISmokeID.requiredOCRPage.allSatisfy { recorded.contains($0) }
                && recorder.viewportHeight != nil
        }

        // Smallest supported size: the window's own content minimum, which
        // SwiftUI derives from the page's minimum frame. Never a hard-coded
        // size, so the run cannot shrink the window below what the app allows.
        var minContentSize: CGSize?
        var requestedContentSize: CGSize?
        var appliedContentSize: CGSize?
        if let window {
            let minimum = window.contentMinSize
            minContentSize = minimum
            let requested = (minimum.width >= 1 && minimum.height >= 1)
                ? minimum
                : CGSize(width: 360, height: 320)
            requestedContentSize = requested
            window.setContentSize(requested)
            window.makeKeyAndOrderFront(nil)
            // Let SwiftUI lay the page out again at the smallest size.
            try? await Task.sleep(for: .milliseconds(700))
            appliedContentSize = window.contentLayoutRect.size
        }

        let missing = GUISmokeID.requiredOCRPage.filter { !recorder.identifiers.contains($0) }
        let content = recorder.contentHeight
        let viewport = recorder.viewportHeight
        let phase = ocrPhase(in: registry)

        if !missing.isEmpty {
            failures.append("OCR page is missing controls: \(missing.joined(separator: ", "))")
        }
        if let content, let viewport {
            if content <= viewport + 1 {
                failures.append("the page does not scroll at the smallest window size "
                    + "(content \(Int(content))pt, viewport \(Int(viewport))pt)")
            }
        } else {
            failures.append("the OCR page did not report its scroll geometry")
        }
        if phase != "idle" {
            failures.append("OCR must not run during the smoke run (phase: \(phase))")
        }
        let windows = mainWindows()
        if windows.count != 1 {
            failures.append("expected exactly one main window, found \(windows.count)")
        }
        if let appliedContentSize,
           appliedContentSize.width < 1 || appliedContentSize.height < 1 {
            failures.append("the window has no usable content area")
        }

        let report = GUISmokeReport(
            schemaVersion: 1,
            bundleIdentifier: Bundle.main.bundleIdentifier,
            expectedBundleIdentifier: expectedBundleIdentifier,
            processIdentifier: ProcessInfo.processInfo.processIdentifier,
            homeDirectory: NSHomeDirectory(),
            userFacingWindowCount: userFacingWindows().count,
            mainWindowCount: windows.count,
            windows: NSApp.windows.map { candidate in
                GUISmokeReport.Window(
                    isMain: isMainWindow(candidate),
                    isVisible: candidate.isVisible,
                    level: candidate.level.rawValue,
                    canBecomeKey: candidate.canBecomeKey,
                    contentSize: GUISmokeReport.Size(candidate.contentLayoutRect.size))
            },
            minContentSize: minContentSize.map { GUISmokeReport.Size($0) },
            requestedContentSize: requestedContentSize.map { GUISmokeReport.Size($0) },
            appliedContentSize: appliedContentSize.map { GUISmokeReport.Size($0) },
            identifiers: recorder.identifiers.sorted(),
            missingIdentifiers: missing,
            contentHeight: content.map { Double($0) },
            viewportHeight: viewport.map { Double($0) },
            isScrollable: (content ?? 0) > (viewport ?? .greatestFiniteMagnitude) + 1,
            ocrPhase: phase,
            failures: failures)

        write(report, to: outputURL)
        exit(failures.isEmpty ? EXIT_SUCCESS : EXIT_FAILURE)
    }

    /// Language-independent phase name for the report.
    @MainActor
    private static func ocrPhase(in registry: ModuleRegistry) -> String {
        guard let module = registry.module(for: OCRModule.moduleID) as? OCRModule else {
            return "missing-module"
        }
        switch module.store.phase {
        case .idle: return "idle"
        case .capturing: return "capturing"
        case .recognizing: return "recognizing"
        case .finished: return "finished"
        case .cancelled: return "cancelled"
        case .failed: return "failed"
        }
    }

    /// Writes the report; a run that cannot report is a hard failure.
    private static func write(_ report: GUISmokeReport, to url: URL) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        do {
            try encoder.encode(report).write(to: url, options: .atomic)
        } catch {
            FileHandle.standardError.write(
                Data("gui smoke: could not write \(url.path): \(error)\n".utf8))
            exit(EXIT_FAILURE)
        }
    }

    /// Count visible app windows that can take focus, including floating result
    /// panels; status-item windows are not user-facing app windows.
    @MainActor
    private static func userFacingWindows() -> [NSWindow] {
        NSApp.windows.filter { window in
            window.isVisible
                && window.canBecomeKey
                && (window.level == .normal || window.level == .floating)
        }
    }

    /// The main scene's normal-level window.
    @MainActor
    private static func mainWindows() -> [NSWindow] {
        userFacingWindows().filter { $0.level == .normal }
    }

    @MainActor
    private static func isMainWindow(_ window: NSWindow) -> Bool {
        window.isVisible && window.level == .normal && window.canBecomeKey
    }

    @MainActor
    private static func firstMainWindow(timeout: Duration) async -> NSWindow? {
        _ = await waitUntil(timeout: timeout) { !mainWindows().isEmpty }
        return mainWindows().first
    }

    /// Polls on the main actor; each sleep yields to the run loop so SwiftUI can
    /// build and lay out the page while the probe waits.
    @MainActor
    private static func waitUntil(
        timeout: Duration,
        _ condition: @MainActor () -> Bool
    ) async -> Bool {
        let deadline = ContinuousClock.now.advanced(by: timeout)
        while ContinuousClock.now < deadline {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(100))
            if Task.isCancelled { break }
        }
        return condition()
    }
}
