import AppKit
import SwiftUI

/// Full module page: inputs, editable in-memory result, and the hotkey
/// settings slot injected by the separate hotkey manager.
///
/// This page is the single result surface for the module (the floating panel
/// is gone), so it must stay usable after a shortcut-triggered run and in a
/// small window:
///
/// - The page scrolls. Content that is taller than the window is reachable
///   instead of being clipped or drawn over the navigation bar.
/// - The editor absorbs the free vertical space, so a large window shows more
///   text while a small one falls back to a comfortable minimum and scrolls.
/// - Action layer (inputs, cancel) uses system glass buttons; content layer
///   (status, banners, preview, cleanup options, editor, shortcut settings)
///   stays on readable surfaces. No card stacks its own glass over the window
///   material.
struct OCRRootView: View {
    @ObservedObject var module: OCRModule
    @ObservedObject var store: OCRStore

    /// Measured height of everything above the editor, and of the shortcut
    /// card. Neither depends on the editor's height, so the two-pass sizing
    /// below settles immediately instead of oscillating.
    @State private var chromeHeight: CGFloat = 170
    @State private var shortcutHeight: CGFloat = 150
    /// Start of the current run, for the live elapsed counter. Set when the
    /// store turns busy; `nil` when idle.
    @State private var busySince: Date?

    private enum Metrics {
        static let spacing: CGFloat = 10
        static let pagePadding: CGFloat = 4
        /// Minimum total height of the editor (surface + footer) before the
        /// page starts scrolling on its own.
        static let editorMinHeight: CGFloat = 220
        static let editorAnchor = "ocr.result"
        static let statusAnchor = "ocr.status"
    }

    init(module: OCRModule) {
        self.module = module
        self.store = module.store
    }

    var body: some View {
        ModuleContainerView(title: module.displayName) {
            GeometryReader { proxy in
                ScrollViewReader { scroller in
                    ScrollView(.vertical) {
                        VStack(alignment: .leading, spacing: Metrics.spacing) {
                            chrome
                                .id(Metrics.statusAnchor)
                                .onGeometryChange(for: CGFloat.self) { measured in
                                    measured.size.height
                                } action: { height in
                                    chromeHeight = height
                                }

                            OCREditorView(
                                store: store,
                                height: editorHeight(viewport: proxy.size.height))
                                .id(Metrics.editorAnchor)

                            shortcutSection
                                .onGeometryChange(for: CGFloat.self) { measured in
                                    measured.size.height
                                } action: { height in
                                    shortcutHeight = height
                                }
                        }
                        .padding(.vertical, Metrics.pagePadding)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .guiSmokeContentHeight()
                    }
                    .scrollBounceBehavior(.basedOnSize)
                    // The GUI smoke run needs the real viewport to prove the
                    // page scrolls at the smallest window size.
                    .guiSmokeViewportHeight()
                    .guiSmokeIdentified(GUISmokeID.ocrPageScroll)
                    // A result arriving from a global shortcut should be what
                    // the page shows, even when it was already open.
                    .onChange(of: store.recognition) { _, newValue in
                        guard newValue != nil else { return }
                        withAnimation(.easeOut(duration: 0.25)) {
                            scroller.scrollTo(Metrics.editorAnchor, anchor: .top)
                        }
                    }
                    // A run started elsewhere (menu bar, global shortcut) must
                    // not stay invisible: start the elapsed counter and bring
                    // the action/status area back into view.
                    .onChange(of: store.isBusy) { _, busy in
                        busySince = busy ? Date() : nil
                        guard busy else { return }
                        withAnimation(.easeOut(duration: 0.2)) {
                            scroller.scrollTo(Metrics.statusAnchor, anchor: .top)
                        }
                    }
                    .onAppear {
                        if store.isBusy && busySince == nil {
                            busySince = Date()
                        }
                    }
                }
            }
        }
    }

    // MARK: - Sizing

    /// Editor height that fills the page when the window is tall, and stops at
    /// `editorMinHeight` when it is short — the scroll view then takes over.
    private func editorHeight(viewport: CGFloat) -> CGFloat {
        let reserved = chromeHeight
            + shortcutHeight
            + Metrics.spacing * 2
            + Metrics.pagePadding * 2
        return max(Metrics.editorMinHeight, viewport - reserved)
    }

    // MARK: - Sections

    private var chrome: some View {
        VStack(alignment: .leading, spacing: 8) {
            actionBar
            OCRStatusRow(store: store, busySince: busySince)
            if store.permissionBlocked {
                OCRPermissionBanner(module: module)
            }
            if case .failed(let message) = store.phase {
                OCRMessageBanner(message: message)
            }
            if let image = store.sourceImage {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: 88)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(Color.secondary.opacity(0.15), lineWidth: 0.5))
            }
            cleanupOptions
        }
    }

    /// Action layer: system glass controls grouped by `GlassEffectContainer`
    /// so neighbouring buttons share one Liquid Glass surface.
    private var actionBar: some View {
        GlassEffectContainer(spacing: 8) {
            OCRActionRow(module: module, store: store)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Pre-recognition cleanup, in the content layer: plain checkboxes with a
    /// hint, no card, so it stays legible over the window material.
    ///
    /// The options are read when a result arrives, which is why the hint spells
    /// out that they never touch text that is already on screen. They sit
    /// directly above the editor so the connection is visible.
    private var cleanupOptions: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 12) {
                lineBreaksToggle
                spacesToggle
                Spacer(minLength: 0)
            }
            Text(L.ocrCleanupHint)
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 2)
    }

    private var lineBreaksToggle: some View {
        Toggle(L.ocrCleanupLineBreaks, isOn: $store.stripLineBreaks)
            .toggleStyle(.checkbox)
            .controlSize(.small)
            .guiSmokeIdentified(GUISmokeID.ocrStripLineBreaksOption)
    }

    private var spacesToggle: some View {
        Toggle(L.ocrCleanupSpaces, isOn: $store.stripSpaces)
            .toggleStyle(.checkbox)
            .controlSize(.small)
            .guiSmokeIdentified(GUISmokeID.ocrStripSpacesOption)
    }

    /// Injectable shortcut settings. The hotkey manager owns the actual
    /// recorder; OCR only reserves the slot. Content surface, not glass, so it
    /// stays legible and does not stack another material layer.
    private var shortcutSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "command")
                Text(L.ocrShortcuts)
                    .fontWeight(.semibold)
                Spacer(minLength: 0)
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            if let injected = module.shortcutSettingsView {
                injected
            } else {
                Text(L.ocrShortcutHint)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            Color(nsColor: .textBackgroundColor).opacity(0.5),
            in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Color.secondary.opacity(0.15), lineWidth: 0.5))
    }
}
