import SwiftUI
import CoreServices
import AppKit
import os

@main
struct WorkDockApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    private let log = Logger(subsystem: "cn.dylanliu.workdock", category: "App")

    /// The single app graph, owned by `AppDelegate` so bootstrap runs on a
    /// launch hook instead of a view that is hidden at startup.
    private var container: AppContainer { appDelegate.container }

    init() {
        // Registering the bundle with LaunchServices is a system-wide side
        // effect; a throwaway smoke bundle must not leave one behind.
        guard !GUISmoke.isEnabled else { return }
        LSRegisterURL(Bundle.main.bundleURL as CFURL, false)
    }

    var body: some Scene {
        Window("WorkDock", id: "main") {
            MainWindowView(registry: container.registry, router: container.router)
        }
        .defaultSize(width: 460, height: 520)
        .windowResizability(.contentMinSize)
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button(L.openApp) {
                    // One presentation path for every caller: the router
                    // orders the window in, re-creates the scene when it was
                    // dismissed, then activates the app.
                    container.router.openMainWindow()
                }
            }
        }

        MenuBarExtra("WorkDock", systemImage: "square.grid.2x2") {
            MenuBarView(registry: container.registry, router: container.router)
        }
        .menuBarExtraStyle(.menu)
    }
}
