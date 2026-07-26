import SwiftUI
import CoreServices
import AppKit
import os

@main
struct WorkDockApp: App {
    @StateObject private var container = AppContainer()
    private let log = Logger(subsystem: "cn.liujiangnan.WorkDock", category: "App")

    init() {
        // Register with LaunchServices so notification center can find our icon
        LSRegisterURL(Bundle.main.bundleURL as CFURL, false)
    }

    var body: some Scene {
        Window("WorkDock", id: "main") {
            MainWindowView(registry: container.registry, router: container.router)
                .task {
                    await container.bootstrap()
                    applyDockPolicy()
                }
                .background(WindowSizeObserver(router: container.router))
        }
        .defaultSize(width: 460, height: 520)
        .windowResizability(.automatic)
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button(L.openApp) {
                    NSApp.activate(ignoringOtherApps: true)
                    for w in NSApp.windows where w.title == "WorkDock" {
                        w.makeKeyAndOrderFront(nil)
                        return
                    }
                }
            }
        }

        MenuBarExtra("WorkDock", systemImage: "square.grid.2x2") {
            MenuBarView(registry: container.registry, router: container.router)
        }
        .menuBarExtraStyle(.menu)
    }

    private func applyDockPolicy() {
        let hide = UserDefaults.standard.bool(forKey: "hideDockIcon")
        NSApp.setActivationPolicy(hide ? .accessory : .regular)
    }
}

extension Notification.Name {
    static let openMainWindow = Notification.Name("cn.liujiangnan.WorkDock.openMainWindow")
}

