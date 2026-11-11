import Foundation
import Combine
import os

/// Persisted user preferences for the global screenshot shortcut.
public struct HotkeySettings: Codable, Equatable, Sendable {
    public var isEnabled: Bool
    public var hotkey: GlobalHotkey

    public init(isEnabled: Bool, hotkey: GlobalHotkey) {
        self.isEnabled = isEnabled
        self.hotkey = hotkey
    }

    /// Enabled with ⌃⌥⌘O.
    public static let `default` = HotkeySettings(isEnabled: true, hotkey: .defaultScreenshot)

    /// Normalized, registration-safe copy.
    public func validated() throws -> HotkeySettings {
        HotkeySettings(isEnabled: isEnabled, hotkey: try hotkey.validated())
    }
}

/// Persists and applies the global screenshot shortcut.
///
/// The store owns the transaction around a shortcut change:
///
/// 1. validate the candidate;
/// 2. encode it (before touching live state);
/// 3. register it with ``GlobalHotkeyManager`` while the previous
///    registration is still live;
/// 4. only after registration succeeds, persist and publish it.
///
/// A validation failure, a system conflict, or a handler failure leaves both
/// the persisted settings and the active registration untouched. The failure is
/// published through ``registrationError`` so the settings UI can explain it.
///
/// Call ``bind(action:)`` once during app bootstrap with the screenshot
/// action. Without a bound action the shortcut can still be registered, but
/// pressing it does nothing.
@MainActor
public final class HotkeySettingsStore: ObservableObject {
    /// Stable `UserDefaults` key holding the JSON-encoded ``HotkeySettings``.
    nonisolated public static let storageKey = "GlobalHotkeySettings"

    /// The active, persisted preferences.
    @Published public private(set) var settings: HotkeySettings

    /// The most recent registration failure, if the configured shortcut is
    /// currently not held by the system. Cleared by the next successful apply.
    @Published public private(set) var registrationError: GlobalHotkeyRegistrationError?

    /// Whether the configured shortcut is currently registered and will fire.
    @Published public private(set) var isRegistered: Bool

    public var isEnabled: Bool { settings.isEnabled }
    public var hotkey: GlobalHotkey { settings.hotkey }

    private let defaults: UserDefaults
    private let manager: GlobalHotkeyManager
    private let log = Logger(subsystem: "cn.dylanliu.workdock", category: "Hotkey")

    public init(defaults: UserDefaults = .standard, manager: GlobalHotkeyManager? = nil) {
        self.defaults = defaults
        self.manager = manager ?? GlobalHotkeyManager()
        self.settings = Self.loadSettings(from: defaults)
        self.isRegistered = false
        self.registrationError = nil
    }

    /// Attach the action fired by the shortcut and reconcile the persisted
    /// preferences with the system immediately.
    ///
    /// Safe to call more than once; later calls replace the action without
    /// re-registering an already active combination.
    public func bind(action: @escaping @MainActor () -> Void) {
        manager.setAction(action)
        reconcile()
    }

    /// Enable or disable the shortcut.
    ///
    /// Disabling always succeeds. Enabling attempts to register the configured
    /// combination; on failure the previous state is kept.
    @discardableResult
    public func setEnabled(_ enabled: Bool) -> Result<HotkeySettings, GlobalHotkeyRegistrationError> {
        if enabled == settings.isEnabled {
            if !enabled || isRegistered {
                return .success(settings)
            }
        }
        return apply(hotkey: settings.hotkey, enabled: enabled)
    }

    /// Validate, register and persist a candidate.
    ///
    /// `enabled` defaults to the current enabled state. On failure neither the
    /// persisted settings nor the active registration change.
    @discardableResult
    public func apply(
        hotkey: GlobalHotkey,
        enabled: Bool? = nil
    ) -> Result<HotkeySettings, GlobalHotkeyRegistrationError> {
        let targetEnabled = enabled ?? settings.isEnabled

        let candidate: HotkeySettings
        do {
            candidate = try HotkeySettings(isEnabled: targetEnabled, hotkey: hotkey).validated()
        } catch let error as HotkeyValidationError {
            let failure = GlobalHotkeyRegistrationError.invalidCombination(error)
            registrationError = failure
            log.error("rejected hotkey: \(hotkey.displayString, privacy: .public)")
            return .failure(failure)
        } catch {
            let failure = GlobalHotkeyRegistrationError.systemError(-1)
            registrationError = failure
            return .failure(failure)
        }

        // Encode before mutating any live state so a failure cannot leave a
        // half-applied preference behind.
        let data: Data
        do {
            data = try JSONEncoder().encode(candidate)
        } catch {
            log.error("hotkey encode failed: \(error.localizedDescription, privacy: .public)")
            let failure = GlobalHotkeyRegistrationError.systemError(-1)
            registrationError = failure
            return .failure(failure)
        }

        if candidate.isEnabled {
            if case .failure(let failure) = manager.register(candidate.hotkey) {
                // The manager keeps the previous registration alive.
                isRegistered = manager.isRegistered
                registrationError = failure
                return .failure(failure)
            }
        } else {
            manager.unregister()
        }

        defaults.set(data, forKey: Self.storageKey)
        settings = candidate
        isRegistered = manager.isRegistered
        registrationError = nil
        return .success(candidate)
    }

    /// Restore the default combination, preserving the current enabled state.
    ///
    /// On failure the previous registration and settings remain active.
    @discardableResult
    public func restoreDefault() -> Result<HotkeySettings, GlobalHotkeyRegistrationError> {
        apply(hotkey: .defaultScreenshot, enabled: settings.isEnabled)
    }

    /// Retry the currently configured combination after a conflict or failed
    /// registration (for example when another app released the shortcut).
    @discardableResult
    public func retryRegistration() -> Result<HotkeySettings, GlobalHotkeyRegistrationError> {
        apply(hotkey: settings.hotkey, enabled: settings.isEnabled)
    }

    /// Drop a displayed error without changing the active registration.
    public func clearRegistrationError() {
        registrationError = nil
    }

    // MARK: - Startup

    private func reconcile() {
        guard settings.isEnabled else {
            manager.unregister()
            isRegistered = false
            registrationError = nil
            return
        }

        switch manager.register(settings.hotkey) {
        case .success:
            isRegistered = true
            registrationError = nil
        case .failure(let failure):
            isRegistered = manager.isRegistered
            registrationError = failure
            log.error("startup hotkey registration failed")
        }
    }

    private nonisolated static func loadSettings(from defaults: UserDefaults) -> HotkeySettings {
        guard let data = defaults.data(forKey: storageKey) else { return .default }
        do {
            let decoded = try JSONDecoder().decode(HotkeySettings.self, from: data)
            if let validated = try? decoded.validated() {
                return validated
            }
            // Corrupt key data must not register an arbitrary shortcut.
            return HotkeySettings(isEnabled: false, hotkey: .defaultScreenshot)
        } catch {
            return .default
        }
    }
}
