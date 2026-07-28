import SwiftUI

/// Menu bar dropdown content.
///
/// Renders a section per registered module (its `menuItems()`), then app-level
/// actions (open window, quit). Settings appears as a module section via
/// `SettingsModule.menuItems()` — no separate settings button needed.
struct MenuBarView: View {
    let registry: ModuleRegistry
    @ObservedObject var router: NavigationRouter
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack {
            ForEach(registry.modules.filter(\.showsInMenuBar), id: \.id) { module in
                ModuleMenuSection(module: module, router: router)
            }
            Divider()
            Button(L.openApp) {
                openWindow(id: "main")
                NSApp.activate(ignoringOtherApps: true)
            }
            .keyboardShortcut("o")

            Button(L.quitApp) {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q")
        }
    }
}

/// One module's slice of the menu bar.
struct ModuleMenuSection: View {
    let module: any Module
    @ObservedObject var router: NavigationRouter
    @State private var items: [ModuleMenuItem] = []

    var body: some View {
        Section(module.displayName) {
            MenuItemsView(items: items, module: module, router: router)
        }
        .onAppear {
            Task { items = await module.menuItems() }
        }
    }
}

struct MenuItemsView: View {
    let items: [ModuleMenuItem]
    let module: any Module
    @ObservedObject var router: NavigationRouter

    var body: some View {
        ForEach(items.indices, id: \.self) { i in
            renderItem(items[i])
        }
    }

    private func renderItem(_ item: ModuleMenuItem) -> AnyView {
        switch item {
        case .action(let title, let icon, let handler):
            return AnyView(Button {
                Task { await handler() }
            } label: {
                Label(title, systemImage: icon ?? "circle")
            })
        case .submenu(let title, let icon, let sub):
            return AnyView(Menu {
                ForEach(sub.indices, id: \.self) { i in
                    renderItem(sub[i])
                }
            } label: {
                Label(title, systemImage: icon ?? "folder")
            })
        case .separator:
            return AnyView(Divider())
        }
    }
}
