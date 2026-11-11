import Foundation
import Carbon.HIToolbox
import os

/// Why a global hotkey could not be registered.
public enum GlobalHotkeyRegistrationError: Error, Equatable, Sendable {
    /// The combination itself is not usable as a global shortcut.
    case invalidCombination(HotkeyValidationError)
    /// Another application (or another registration in this app) owns the combo.
    case alreadyInUse(GlobalHotkey)
    /// Carbon returned an unexpected status while registering.
    case systemError(OSStatus)
    /// The Carbon event handler could not be installed.
    case handlerInstallationFailed(OSStatus)

    public var message: String {
        HotkeyText.message(for: self)
    }
}

extension GlobalHotkeyRegistrationError: LocalizedError {
    public var errorDescription: String? { message }
}

/// Registers exactly one Carbon global hotkey and invokes a closure when it
/// fires.
///
/// Replacement is transactional: the new combination is registered while the
/// previous one is still live, and the previous registration is only released
/// after the new one succeeds. A conflict therefore leaves the old shortcut
/// untouched and working.
///
/// Carbon hot keys do not require Accessibility or Input Monitoring
/// permission. The manager is app-scoped; the event handler is installed lazily
/// on the first successful registration and removed on deallocation.
@MainActor
public final class GlobalHotkeyManager {
    /// The combination currently held with the system, if any.
    public private(set) var registeredHotkey: GlobalHotkey?

    public var isRegistered: Bool { carbon.hotKeyRef != nil }

    /// Carbon resources live in a plain reference type so their deinit can
    /// release them without touching main-actor-isolated state.
    private final class CarbonResources {
        var hotKeyRef: EventHotKeyRef?
        var eventHandlerRef: EventHandlerRef?

        deinit {
            if let hotKeyRef {
                _ = UnregisterEventHotKey(hotKeyRef)
            }
            if let eventHandlerRef {
                _ = RemoveEventHandler(eventHandlerRef)
            }
        }
    }

    private let carbon = CarbonResources()
    private var activeHotKeyID: UInt32?
    private var nextHotKeyID: UInt32 = 1
    private var action: (@MainActor () -> Void)?
    private let log = Logger(subsystem: "cn.dylanliu.workdock", category: "Hotkey")

    /// Per-manager Carbon signature. A process-wide constant would let two
    /// manager instances with the same hot-key id both react to one event.
    private let hotKeySignature = OSType.random(in: 1...UInt32.max)

    public init() {}

    /// Install or replace the closure fired by the registered shortcut.
    public func setAction(_ action: (@MainActor () -> Void)?) {
        self.action = action
    }

    /// Register `hotkey`, replacing the previous registration on success.
    ///
    /// On failure the previous registration is kept and remains active.
    @discardableResult
    public func register(_ hotkey: GlobalHotkey) -> Result<GlobalHotkey, GlobalHotkeyRegistrationError> {
        let normalized: GlobalHotkey
        do {
            normalized = try hotkey.validated()
        } catch let error as HotkeyValidationError {
            return .failure(.invalidCombination(error))
        } catch {
            return .failure(.systemError(-1))
        }

        if normalized == registeredHotkey, carbon.hotKeyRef != nil {
            return .success(normalized)
        }

        if let failure = ensureEventHandler() {
            return .failure(failure)
        }

        var newRef: EventHotKeyRef?
        let identifier = EventHotKeyID(signature: hotKeySignature, id: nextHotKeyID)
        let status = RegisterEventHotKey(
            normalized.keyCode,
            normalized.modifiers.rawValue,
            identifier,
            GetApplicationEventTarget(),
            0,
            &newRef
        )

        guard status == noErr, let newRef else {
            if status == OSStatus(eventHotKeyExistsErr) {
                log.error("hotkey conflict: \(normalized.displayString, privacy: .public)")
                return .failure(.alreadyInUse(normalized))
            }
            log.error("hotkey register failed status=\(String(status), privacy: .public)")
            return .failure(.systemError(status))
        }

        // The new shortcut is live; only now release the previous one.
        if let oldRef = carbon.hotKeyRef {
            _ = UnregisterEventHotKey(oldRef)
        }
        nextHotKeyID &+= 1
        carbon.hotKeyRef = newRef
        activeHotKeyID = identifier.id
        registeredHotkey = normalized
        log.info("hotkey registered: \(normalized.displayString, privacy: .public)")
        return .success(normalized)
    }

    /// Release the current registration. Leaves the Carbon event handler
    /// installed so a later ``register(_:)`` only creates the hot key.
    public func unregister() {
        if let hotKeyRef = carbon.hotKeyRef {
            _ = UnregisterEventHotKey(hotKeyRef)
        }
        carbon.hotKeyRef = nil
        registeredHotkey = nil
        activeHotKeyID = nil
    }

    // MARK: - Carbon plumbing

    private func ensureEventHandler() -> GlobalHotkeyRegistrationError? {
        if carbon.eventHandlerRef != nil { return nil }

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        var handlerRef: EventHandlerRef?
        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, userData in
                guard let event, let userData else { return noErr }

                var identifier = EventHotKeyID()
                let parameterStatus = GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &identifier
                )
                guard parameterStatus == noErr else { return parameterStatus }

                let manager = Unmanaged<GlobalHotkeyManager>
                    .fromOpaque(userData)
                    .takeUnretainedValue()
                let hotKeyID = identifier.id
                let signature = identifier.signature
                Task { @MainActor in
                    manager.handleHotKey(id: hotKeyID, signature: signature)
                }
                return noErr
            },
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &handlerRef
        )

        guard status == noErr, let handlerRef else {
            log.error("hotkey handler install failed status=\(String(status), privacy: .public)")
            return .handlerInstallationFailed(status)
        }
        carbon.eventHandlerRef = handlerRef
        return nil
    }

    private func handleHotKey(id: UInt32, signature: OSType) {
        guard signature == hotKeySignature else { return }
        guard activeHotKeyID == id, registeredHotkey != nil else { return }
        action?()
    }
}
