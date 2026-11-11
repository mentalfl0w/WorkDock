import SwiftUI

/// Reusable settings UI for the global screenshot shortcut.
///
/// Fits both a `Form` row and a compact sidebar card. Drop it anywhere:
///
/// ```swift
/// // Settings Form
/// Form {
///     HotkeySettingsSection(store: hotkeyStore)
/// }
///
/// // OCR module sidebar
/// ocrModule.setShortcutSettingsView {
///     HotkeySettingsView(store: hotkeyStore)
/// }
/// ```
///
/// The recorder edits a draft; **Save** commits it through
/// ``HotkeySettingsStore/apply(hotkey:enabled:)``. A conflict or validation
/// failure leaves the previous shortcut registered and persisted. The recorder
/// keeps the rejected draft for adjustment, the active-value line shows what
/// will actually fire, and the error row offers a retry while the shortcut is
/// enabled.
public struct HotkeySettingsView: View {
    @ObservedObject private var store: HotkeySettingsStore

    @State private var draft: GlobalHotkey
    @State private var enabledDraft: Bool
    @State private var status: String?

    @MainActor
    public init(store: HotkeySettingsStore) {
        self.store = store
        _draft = State(initialValue: store.settings.hotkey)
        _enabledDraft = State(initialValue: store.settings.isEnabled)
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle(HotkeyText.enabled, isOn: enabledBinding)
                .controlSize(.small)

            VStack(alignment: .leading, spacing: 4) {
                Text(HotkeyText.shortcutLabel)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                HotkeyRecorderView(hotkey: $draft) { captured in
                    draft = captured
                    status = nil
                    store.clearRegistrationError()
                }
            }

            HStack(spacing: 6) {
                Text(store.isRegistered ? HotkeyText.active : HotkeyText.inactive)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                if store.isRegistered {
                    Text(store.settings.hotkey.displayString)
                        .font(.caption2)
                        .monospaced()
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                Spacer(minLength: 4)
                if store.settings.isEnabled && !store.isRegistered {
                    Button(HotkeyText.retry) {
                        retry()
                    }
                    .font(.caption2)
                    .buttonStyle(.link)
                }
            }

            HStack(spacing: 6) {
                Button(HotkeyText.restoreDefault) {
                    restoreDefault()
                }
                .font(.caption)
                .buttonStyle(.borderless)
                .disabled(
                    store.settings.hotkey == .defaultScreenshot
                        && draft == .defaultScreenshot
                        && store.isRegistered
                )

                Spacer(minLength: 4)

                Button(HotkeyText.save) {
                    saveDraft()
                }
                .font(.caption)
                .buttonStyle(.glassProminent)
                .controlSize(.small)
                .disabled(draft == store.settings.hotkey)
            }

            if let error = store.registrationError {
                Text("\(error.message) \(HotkeyText.retained)")
                    .font(.caption2)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let status {
                Text(status)
                    .font(.caption2)
                    .foregroundStyle(.green)
            }

            Text(HotkeyText.hint)
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .onChange(of: store.settings) { oldValue, newValue in
            enabledDraft = newValue.isEnabled
            // Preserve an unsaved recording when only enabled state changed.
            if draft == oldValue.hotkey {
                draft = newValue.hotkey
            }
        }
        .onAppear {
            draft = store.settings.hotkey
            enabledDraft = store.settings.isEnabled
        }
    }

    // MARK: - Bindings and actions

    private var enabledBinding: Binding<Bool> {
        Binding(
            get: { enabledDraft },
            set: { newValue in
                guard newValue != enabledDraft else { return }
                let previous = enabledDraft
                enabledDraft = newValue

                switch store.setEnabled(newValue) {
                case .success:
                    enabledDraft = store.settings.isEnabled
                    status = store.settings.isEnabled
                        ? HotkeyText.enabledStatus
                        : HotkeyText.disabledStatus
                case .failure:
                    // Keep the previous state; the error row explains why.
                    enabledDraft = previous
                    status = nil
                }
            }
        )
    }

    private func saveDraft() {
        switch store.apply(hotkey: draft, enabled: store.settings.isEnabled) {
        case .success(let saved):
            draft = saved.hotkey
            enabledDraft = saved.isEnabled
            status = saved.isEnabled ? HotkeyText.saved : HotkeyText.savedInactive
        case .failure:
            // The store kept the previous shortcut active and persisted; the
            // recorder keeps the rejected draft so it can be adjusted or
            // retried. The active-value line above shows what will fire.
            status = nil
        }
    }

    private func restoreDefault() {
        draft = .defaultScreenshot
        switch store.restoreDefault() {
        case .success(let restored):
            draft = restored.hotkey
            enabledDraft = restored.isEnabled
            status = restored.isEnabled
                ? HotkeyText.restored
                : HotkeyText.restoredInactive
        case .failure:
            status = nil
        }
    }

    private func retry() {
        switch store.apply(hotkey: draft, enabled: store.settings.isEnabled) {
        case .success(let current):
            draft = current.hotkey
            enabledDraft = current.isEnabled
            status = current.isEnabled ? HotkeyText.saved : HotkeyText.disabledStatus
        case .failure:
            status = nil
        }
    }
}

/// `Form`-friendly wrapper around ``HotkeySettingsView``.
public struct HotkeySettingsSection: View {
    private let store: HotkeySettingsStore

    @MainActor
    public init(store: HotkeySettingsStore) {
        self.store = store
    }

    public var body: some View {
        Section {
            HotkeySettingsView(store: store)
        } header: {
            Text(HotkeyText.sectionTitle)
        }
    }
}
