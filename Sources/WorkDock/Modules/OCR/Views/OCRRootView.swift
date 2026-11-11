import SwiftUI

/// Full module page: inputs, editable in-memory result, and the hotkey
/// settings slot injected by the separate hotkey manager.
struct OCRRootView: View {
    @ObservedObject var module: OCRModule
    @ObservedObject var store: OCRStore

    init(module: OCRModule) {
        self.module = module
        self.store = module.store
    }

    var body: some View {
        ModuleContainerView(title: module.displayName) {
            VStack(spacing: 8) {
                OCRActionRow(module: module, store: store)
                OCRStatusRow(store: store)
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
                        .frame(maxWidth: .infinity, maxHeight: 80)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                OCREditorView(store: store)
                shortcutSection
            }
            .frame(minHeight: 380)
        }
    }

    /// Injectable shortcut settings. The hotkey manager owns the actual
    /// recorder; OCR only reserves the slot.
    private var shortcutSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(L.ocrShortcuts, systemImage: "command")
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
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(in: .rect(cornerRadius: 10))
    }
}
