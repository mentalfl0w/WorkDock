import AppKit
import XCTest
@testable import WorkDock

@MainActor
final class InitialWindowHiderTests: XCTestCase {
    func testHiddenMainWindowRemainsReopenableByRouter() {
        _ = NSApplication.shared
        let window = NSWindow(
            contentRect: NSRect(x: -10_000, y: -10_000, width: 1, height: 1),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.title = "WorkDock"
        defer { window.close() }

        window.makeKeyAndOrderFront(nil)
        InitialWindowHider.hide(window)

        XCTAssertFalse(window.isVisible)
        XCTAssertTrue(NSApp.windows.contains { $0 === window })

        let router = NavigationRouter()
        router.openMainWindow()

        XCTAssertTrue(window.isVisible)
    }
}
