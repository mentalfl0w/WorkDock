import SwiftUI

/// Document detail view — reusable across modules and demo.
///
/// Decoupled from `FujianEducationModule` via closures:
/// - `onDownloadAttachment`: download a single file (receives source URL + destination URL)
/// - `onSignin`: sign/receipt action
/// - `onClose`: dismiss the detail view
struct DocumentDetailView: View {
    let detail: DocumentDetail
    let attachments: [Attachment]
    let canSignin: Bool
    let onClose: () -> Void
    let onSignin: () -> Void
    let onDownloadAttachment: @Sendable (URL, URL) async throws -> Void

    @State private var downloading: String?
    @State private var signedIn = false
    @State private var downloadError: String?
    @State private var batchDownloading = false
    @State private var batchProgress: Double = 0

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Header card
                VStack(alignment: .leading, spacing: 8) {
                    Text(detail.title)
                        .font(.title3.weight(.semibold))
                        .lineLimit(3)
                    HStack(spacing: 12) {
                        Label(detail.publisher, systemImage: "building.2")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if !detail.priority.isEmpty {
                            Label(detail.priority, systemImage: "flag")
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }
                    }
                    if !detail.docMark.isEmpty {
                        Label(detail.docMark, systemImage: "number")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Label(detail.publicAttribute, systemImage: "lock.shield")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .glassEffect(in: .rect(cornerRadius: 14))

                if !detail.publishNote.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(L.publishNote).font(.headline)
                        Text(detail.publishNote).font(.body)
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .glassEffect(in: .rect(cornerRadius: 14))
                }

                // Attachments
                if !attachments.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(L.attachments).font(.headline)
                            Spacer()
                            if attachments.count > 1 {
                                Button {
                                    batchDownload()
                                } label: {
                                    if batchDownloading {
                                        HStack(spacing: 4) {
                                            ProgressView(value: batchProgress)
                                                .frame(width: 60)
                                            Text("\(Int(batchProgress * 100))%")
                                                .font(.caption2)
                                                .foregroundStyle(.secondary)
                                        }
                                    } else {
                                        Label(L.downloadAll, systemImage: "arrow.down.circle.fill")
                                            .font(.caption)
                                    }
                                }
                                .buttonStyle(.bordered)
                                .disabled(batchDownloading)
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .glassEffect(in: .rect(cornerRadius: 10))
                        ForEach(attachments, id: \.name) { a in
                            HStack {
                                Image(systemName: "paperclip")
                                    .foregroundStyle(.tint)
                                Text(a.displayName).font(.body)
                                Spacer()
                                if downloading == a.name {
                                    ProgressView().scaleEffect(0.7)
                                } else {
                                    Image(systemName: "arrow.down.circle")
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .padding(10)
                            .glassEffect(in: .rect(cornerRadius: 10))
                            .contentShape(Rectangle())
                            .onTapGesture { download(a) }
                        }
                    }
                }

                if let err = downloadError {
                    Text(err).font(.caption).foregroundStyle(.red)
                }
            }
            .padding(20)
        }
        .background(Color.clear)
        .safeAreaInset(edge: .bottom) {
            HStack {
                Button(L.close) { onClose() }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                Spacer()
                if canSignin && !signedIn {
                    Button(action: {
                        signedIn = true
                        onSignin()
                    }) {
                        Label(L.signin, systemImage: "checkmark.circle.fill")
                            .font(.body.weight(.medium))
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .glassEffect(in: .rect(cornerRadius: 10))
        }
    }

    // MARK: - Download

    private func download(_ attachment: Attachment) {
        downloading = attachment.name
        downloadError = nil
        let panel = NSSavePanel()
        panel.title = L.download
        panel.nameFieldStringValue = attachment.saveName
        panel.canCreateDirectories = true
        if panel.runModal() == .OK, let dest = panel.url {
            Task {
                do {
                    try await onDownloadAttachment(attachment.url, dest)
                } catch {
                    await MainActor.run { downloadError = "\(L.downloadFailed): \(error.localizedDescription)" }
                }
                await MainActor.run { downloading = nil }
            }
        } else {
            downloading = nil
        }
    }

    private func batchDownload() {
        let panel = NSOpenPanel()
        panel.title = L.selectFolder
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        if panel.runModal() == .OK, let dir = panel.url {
            batchDownloading = true
            downloadError = nil
            batchProgress = 0
            Task {
                var failed = 0
                let total = Double(attachments.count)
                for (i, a) in attachments.enumerated() {
                    do {
                        try await onDownloadAttachment(a.url, dir.appendingPathComponent(a.saveName))
                    } catch {
                        failed += 1
                    }
                    await MainActor.run { batchProgress = Double(i + 1) / total }
                }
                await MainActor.run {
                    batchDownloading = false
                    if failed > 0 {
                        downloadError = "\(failed)/\(attachments.count) \(L.batchFailed)"
                    }
                }
            }
        }
    }
}
