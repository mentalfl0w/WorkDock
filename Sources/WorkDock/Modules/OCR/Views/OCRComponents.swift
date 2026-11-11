import SwiftUI

/// Shared input row for the module page and the floating result panel.
struct OCRActionRow: View {
    @ObservedObject var module: OCRModule
    @ObservedObject var store: OCRStore

    var body: some View {
        Group {
            if store.isBusy {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text(L.ocrWorking)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 4)
                    Button(L.ocrCancel) {
                        module.cancelActiveWork()
                    }
                }
            } else {
                HStack(spacing: 8) {
                    Button {
                        module.triggerScreenshot()
                    } label: {
                        Label(L.ocrScreenshot, systemImage: "text.viewfinder")
                    }

                    Button {
                        module.triggerClipboardOCR()
                    } label: {
                        Label(L.ocrClipboard, systemImage: "doc.on.clipboard")
                    }

                    Button {
                        module.chooseImageAndRecognize()
                    } label: {
                        Label(L.ocrChooseImage, systemImage: "photo")
                    }

                    Spacer(minLength: 4)
                }
            }
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
    }
}

/// Screen Recording permission guidance. Shown instead of a modal alert, so
/// the user can enable access in System Settings and retry in place.
struct OCRPermissionBanner: View {
    @ObservedObject var module: OCRModule

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.shield.fill")
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 3) {
                Text(L.ocrPermissionTitle)
                    .font(.callout.weight(.semibold))
                Text(L.ocrPermissionBody)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            VStack(spacing: 6) {
                Button(L.ocrOpenSettings) {
                    module.openScreenRecordingSettings()
                }
                Button(L.ocrRetry) {
                    module.triggerScreenshot()
                }
            }
            .controlSize(.small)
        }
        .padding(10)
        .background(Color.orange.opacity(0.10), in: RoundedRectangle(cornerRadius: 8))
    }
}

/// Inline error row for failed runs.
struct OCRMessageBanner: View {
    let message: String

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(8)
        .background(Color.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
    }
}

/// Editable recognition result plus copy action and run statistics.
struct OCREditorView: View {
    @ObservedObject var store: OCRStore
    var minHeight: CGFloat = 180

    var body: some View {
        VStack(spacing: 8) {
            ZStack(alignment: .topLeading) {
                TextEditor(text: $store.text)
                    .font(.system(size: 13))
                    .scrollContentBackground(.hidden)
                    .padding(6)
                if store.text.isEmpty {
                    Text(L.ocrPlaceholder)
                        .font(.system(size: 12))
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 12)
                        .allowsHitTesting(false)
                }
            }
            .frame(minHeight: minHeight)
            .background(
                Color(nsColor: .textBackgroundColor).opacity(0.4),
                in: RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(Color.secondary.opacity(0.2), lineWidth: 0.5))

            footer
        }
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Group {
                if let result = store.recognition {
                    Text(statsText(result))
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .help(statsText(result))
                } else {
                    Text(store.lastSource.label)
                }
            }
            .font(.caption2)
            .foregroundStyle(.secondary)

            Spacer(minLength: 8)

            Button(store.copied ? L.ocrCopied : L.ocrCopy) {
                store.copyText()
            }
            .controlSize(.small)
            .disabled(store.text.isEmpty)
        }
    }

    private func statsText(_ result: OCRRecognition) -> String {
        [
            L.ocrConfidence(Int((result.averageConfidence * 100).rounded())),
            L.ocrLineCount(result.lineCount),
            L.ocrPixelSize(result.pixelWidth, result.pixelHeight),
            L.ocrDuration(result.duration)
        ].joined(separator: " · ")
    }
}

/// Compact one-line status used by the module page and the result panel.
struct OCRStatusRow: View {
    @ObservedObject var store: OCRStore

    var body: some View {
        HStack(spacing: 6) {
            Text(store.phase.label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer(minLength: 4)
            Text(store.lastSource.label)
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }
}

extension OCRStore.Phase {
    var label: String {
        switch self {
        case .idle:
            return L.ocrIdle
        case .capturing:
            return L.ocrCapturing
        case .recognizing:
            return L.ocrRecognizing
        case .finished:
            return L.ocrDone
        case .cancelled:
            return L.ocrCancelled
        case .failed:
            return ""
        }
    }
}
