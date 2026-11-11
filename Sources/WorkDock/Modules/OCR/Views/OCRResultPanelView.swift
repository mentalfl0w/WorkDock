import SwiftUI

/// Compact floating panel shown after a run, so a global shortcut can produce
/// a result without opening the full WorkDock window.
struct OCRResultPanelView: View {
    @ObservedObject var module: OCRModule
    @ObservedObject var store: OCRStore

    init(module: OCRModule) {
        self.module = module
        self.store = module.store
    }

    var body: some View {
        VStack(spacing: 10) {
            header
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
                    .frame(maxWidth: .infinity, maxHeight: 70)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            OCREditorView(store: store, minHeight: 200)
        }
        .padding(16)
        .frame(minWidth: 460, minHeight: 360)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Label(store.lastSource.label, systemImage: store.lastSource.icon)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Text(L.ocrLocalOnly)
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .lineLimit(1)
            Button(L.ocrOpenModule) {
                module.showInMainWindow()
            }
            .controlSize(.small)
        }
    }
}
