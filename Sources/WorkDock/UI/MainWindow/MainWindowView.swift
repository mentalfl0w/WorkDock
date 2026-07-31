import SwiftUI

/// Main window: content-driven size, switches between gallery and module.
///
/// - No module selected: compact card gallery (~720×480).
/// - Module selected: module's `mainView()` fills a wider window (~900×600).
/// Window size follows content via `.windowResizability(.contentSize)`.
struct MainWindowView: View {
    @ObservedObject var registry: ModuleRegistry
    @ObservedObject var router: NavigationRouter
    @Environment(\.dismissWindow) private var dismissWindow

    var body: some View {
        ZStack {
            GlassBackgroundView()
                .ignoresSafeArea()
                .allowsHitTesting(false)
            Group {
                if let id = router.selectedModuleID, let module = registry.module(for: id) {
                    ModuleHostView(module: module, router: router)
                        .transition(.asymmetric(
                            insertion: .move(edge: .trailing).combined(with: .opacity),
                            removal: .move(edge: .trailing).combined(with: .opacity)))
                } else {
                    ModuleGallery(registry: registry, router: router)
                        .transition(.opacity)
                }
            }
        }
        .animation(.spring(duration: 0.3), value: router.selectedModuleID)
        .task {
            // On launch, only show menu bar — dismiss the window.
            if router.selectedModuleID == nil && !router.hasShownInitially {
                router.hasShownInitially = true
                dismissWindow(id: "main")
            }
        }
    }
}

/// Card-based gallery — the WorkDock home.
struct ModuleGallery: View {
    @ObservedObject var registry: ModuleRegistry
    @ObservedObject var router: NavigationRouter

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                header
                VStack(spacing: 12) {
                    ForEach(registry.modules.filter { !$0.isAuxiliary }, id: \.id) { module in
                        GalleryCard(module: module) {
                            router.navigate(moduleID: module.id, payload: nil)
                        }
                    }
                }
                .padding(.horizontal, 24)

                Divider().padding(.horizontal, 32)

                VStack(spacing: 12) {
                    ForEach(registry.modules.filter(\.isAuxiliary), id: \.id) { module in
                        GalleryCard(module: module) {
                            router.navigate(moduleID: module.id, payload: nil)
                        }
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 32)
            }
        }
        .frame(minWidth: 420, idealWidth: 460, minHeight: 420)
    }

    private var header: some View {
        VStack(spacing: 8) {
            if let logoURL = Bundle.main.url(forResource: "logo", withExtension: "png"),
               let nsImage = NSImage(contentsOf: logoURL) {
                Image(nsImage: nsImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 56, height: 56)
            }
            Text(L.appName)
                .font(.system(size: 26, weight: .bold, design: .rounded))
            Text(L.chooseModule)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.top, 20)
    }
}

/// One card in the gallery.
struct GalleryCard: View {
    let module: any Module
    let onTap: () -> Void
    @State private var signedIn = false
    @State private var hover = false

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Image(systemName: module.icon)
                        .font(.system(size: 20))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Circle()
                        .fill(signedIn ? Color.green : Color.secondary.opacity(0.3))
                        .frame(width: 8, height: 8)
                }
                Text(module.displayName)
                    .font(.headline)
                    .lineLimit(1)
                Text(module.summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .glassEffect(in: .rect(cornerRadius: 12))
        .shadow(color: .black.opacity(hover ? 0.15 : 0.05), radius: hover ? 8 : 4, y: 2)
        .onHover { hover = $0 }
        .task(id: module.id) {
            signedIn = await module.isSignedIn
        }
    }
}

/// Hosts a module's main view with a back button.
struct ModuleHostView: View {
    let module: any Module
    @ObservedObject var router: NavigationRouter

    var body: some View {
        module.mainView()
            .frame(minWidth: 480, idealWidth: 600, maxWidth: .infinity, minHeight: 400, idealHeight: 540, maxHeight: .infinity)
            .environment(\.moduleBackAction, {
                Task { @MainActor in
                    withAnimation(.spring(duration: 0.3)) {
                        router.selectedModuleID = nil
                    }
                }
            })
    }
}
