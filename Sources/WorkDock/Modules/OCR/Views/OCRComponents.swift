import Foundation
import SwiftUI

/// Input row for the OCR page.
///
/// The action row is the page's action layer: system buttons with the Liquid
/// Glass button style, laid out adaptively. It keeps the three inputs always
/// visible and adds **Cancel** only while a run is in flight, so every entry
/// point stays reachable at any window width.
struct OCRActionRow: View {
    @ObservedObject var module: OCRModule
    @ObservedObject var store: OCRStore

    var body: some View {
        ViewThatFits(in: .horizontal) {
            // Wide: one row with the actions left and Cancel trailing.
            HStack(spacing: 8) {
                screenshotButton
                clipboardButton
                imageButton
                cancelButton
                Spacer(minLength: 4)
            }

            // Narrow: two rows, labels preserved instead of truncated.
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    screenshotButton
                    clipboardButton
                    Spacer(minLength: 0)
                }
                HStack(spacing: 8) {
                    imageButton
                    cancelButton
                    Spacer(minLength: 0)
                }
            }
        }
        .buttonStyle(.glass)
        .controlSize(.small)
    }

    private var screenshotButton: some View {
        Button {
            module.triggerScreenshot()
        } label: {
            Label(L.ocrScreenshot, systemImage: "text.viewfinder")
        }
        .help(L.ocrScreenshot)
        .disabled(store.isBusy)
        .guiSmokeIdentified(GUISmokeID.ocrScreenshotAction)
    }

    private var clipboardButton: some View {
        Button {
            module.triggerClipboardOCR()
        } label: {
            Label(L.ocrClipboard, systemImage: "doc.on.clipboard")
        }
        .help(L.ocrClipboard)
        .disabled(store.isBusy)
        .guiSmokeIdentified(GUISmokeID.ocrClipboardAction)
    }

    private var imageButton: some View {
        Button {
            module.chooseImageAndRecognize()
        } label: {
            Label(L.ocrChooseImage, systemImage: "photo")
        }
        .help(L.ocrChooseImage)
        .disabled(store.isBusy)
        .guiSmokeIdentified(GUISmokeID.ocrImageFileAction)
    }

    @ViewBuilder
    private var cancelButton: some View {
        if store.isBusy {
            Button {
                module.cancelActiveWork()
            } label: {
                Label(L.ocrCancel, systemImage: "xmark")
            }
            .help(L.ocrCancel)
        }
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
///
/// This is the page's content layer: an opaque-enough text surface (no glass),
/// so recognised text stays readable over the window material.
struct OCREditorView: View {
    @ObservedObject var store: OCRStore
    /// Total height (text surface + footer), decided by the page so the editor
    /// can absorb the window's free space or stop at a comfortable minimum.
    var height: CGFloat

    var body: some View {
        VStack(spacing: 8) {
            ZStack(alignment: .topLeading) {
                TextEditor(text: $store.text)
                    .font(.system(size: 13))
                    .scrollContentBackground(.hidden)
                    .padding(6)
                    .guiSmokeIdentified(GUISmokeID.ocrEditor)
                if store.text.isEmpty {
                    Text(L.ocrPlaceholder)
                        .font(.system(size: 12))
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 12)
                        .allowsHitTesting(false)
                }
            }
            .frame(maxHeight: .infinity)
            .background(
                Color(nsColor: .textBackgroundColor).opacity(0.65),
                in: RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(Color.secondary.opacity(0.2), lineWidth: 0.5))

            footer
        }
        .frame(maxWidth: .infinity)
        .frame(height: height)
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
            .help(L.ocrCopy)
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

/// Compact one-line status for the OCR page.
///
/// A run can take several seconds, so the busy state is not a static label:
/// it adds a spinner and a live elapsed counter, which shows the run is still
/// progressing and keeps **Cancel** (in `OCRActionRow`) the obvious exit. No
/// prewarming happens here — the module only runs when the user asks.
struct OCRStatusRow: View {
    @ObservedObject var store: OCRStore
    /// When the current run was noticed as busy; `nil` outside a run.
    var busySince: Date? = nil

    var body: some View {
        HStack(spacing: 6) {
            if store.isBusy {
                ProgressView()
                    .controlSize(.mini)
                Text(store.phase.label)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                if let busySince {
                    TimelineView(.periodic(from: busySince, by: 0.5)) { context in
                        Text(elapsedText(since: busySince, now: context.date))
                            .font(.caption2)
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                }
            } else {
                Text(store.phase.label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            Label(store.lastSource.label, systemImage: store.lastSource.icon)
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .lineLimit(1)
        }
        .padding(.horizontal, store.isBusy ? 8 : 0)
        .padding(.vertical, store.isBusy ? 6 : 0)
        .background {
            if store.isBusy {
                RoundedRectangle(cornerRadius: 7)
                    .fill(Color.accentColor.opacity(0.10))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: store.isBusy)
        .animation(.easeInOut(duration: 0.15), value: store.phase)
    }

    private func elapsedText(since start: Date, now: Date) -> String {
        let seconds = max(0, Int(now.timeIntervalSince(start).rounded(.down)))
        return "\(seconds)s"
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
