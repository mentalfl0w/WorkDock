import Foundation
import Carbon.HIToolbox

/// Carbon modifier flags for a global hotkey.
///
/// Raw values match the Carbon `cmdKey` / `shiftKey` / `optionKey` /
/// `controlKey` masks, so a binding can be handed to `RegisterEventHotKey`
/// without translation. Unknown high bits are stripped by
/// ``GlobalHotkey/validated()``.
public struct HotkeyModifiers: OptionSet, Codable, Hashable, Sendable {
    public let rawValue: UInt32

    public init(rawValue: UInt32) {
        self.rawValue = rawValue
    }

    public static let command = HotkeyModifiers(rawValue: UInt32(cmdKey))
    public static let shift = HotkeyModifiers(rawValue: UInt32(shiftKey))
    public static let option = HotkeyModifiers(rawValue: UInt32(optionKey))
    public static let control = HotkeyModifiers(rawValue: UInt32(controlKey))

    /// Every modifier this app understands. Used to normalize persisted or
    /// recorded values before registration.
    public static let shortcutMask: HotkeyModifiers = [.control, .option, .shift, .command]

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        self.init(rawValue: try container.decode(UInt32.self))
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

/// Why a key combination cannot be used as a global shortcut.
public enum HotkeyValidationError: Error, Equatable, Sendable {
    /// A bare modifier key (⌘, ⌥, ⌃, ⇧, Caps Lock, Fn) was supplied as the key.
    case unsupportedKey
    /// The combination has no ⌘, ⌥ or ⌃ and the key is not a function key.
    case modifierRequired
}

/// A global key combination identified by a Carbon virtual key code.
///
/// Key codes are physical keys, so a persisted binding keeps working across
/// keyboard-layout changes. ``displayString`` uses the standard US key legends;
/// the registration itself is layout independent.
public struct GlobalHotkey: Codable, Hashable, Sendable {
    public let keyCode: UInt32
    public let modifiers: HotkeyModifiers

    public init(keyCode: UInt32, modifiers: HotkeyModifiers) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    /// ⌃⌥⌘O — no system or common-app meaning.
    public static let defaultScreenshot = GlobalHotkey(
        keyCode: UInt32(kVK_ANSI_O),
        modifiers: [.control, .option, .command]
    )

    /// Human-readable combination, e.g. `⌃⌥⌘O`.
    public var displayString: String {
        var result = ""
        if modifiers.contains(.control) { result += "⌃" }
        if modifiers.contains(.option) { result += "⌥" }
        if modifiers.contains(.shift) { result += "⇧" }
        if modifiers.contains(.command) { result += "⌘" }
        result += Self.keyLabels[keyCode] ?? "Key \(keyCode)"
        return result
    }

    /// Normalized copy that is safe to persist and register.
    ///
    /// Strips modifier bits the app does not handle and rejects bare modifiers
    /// or combinations that would hijack ordinary typing.
    public func validated() throws -> GlobalHotkey {
        let normalizedModifiers = HotkeyModifiers(
            rawValue: modifiers.rawValue & HotkeyModifiers.shortcutMask.rawValue
        )
        guard !Self.modifierKeyCodes.contains(keyCode) else {
            throw HotkeyValidationError.unsupportedKey
        }
        let commandLike: HotkeyModifiers = [.command, .option, .control]
        if normalizedModifiers.intersection(commandLike).isEmpty,
           !Self.standaloneKeyCodes.contains(keyCode) {
            throw HotkeyValidationError.modifierRequired
        }
        return GlobalHotkey(keyCode: keyCode, modifiers: normalizedModifiers)
    }

    // MARK: - Key table

    private static let modifierKeyCodes: Set<UInt32> = [
        UInt32(kVK_Command), UInt32(kVK_RightCommand),
        UInt32(kVK_Shift), UInt32(kVK_RightShift),
        UInt32(kVK_Option), UInt32(kVK_RightOption),
        UInt32(kVK_Control), UInt32(kVK_RightControl),
        UInt32(kVK_CapsLock), UInt32(kVK_Function),
    ]

    /// Function keys are safe to register without another modifier.
    private static let standaloneKeyCodes: Set<UInt32> = [
        UInt32(kVK_F1), UInt32(kVK_F2), UInt32(kVK_F3), UInt32(kVK_F4),
        UInt32(kVK_F5), UInt32(kVK_F6), UInt32(kVK_F7), UInt32(kVK_F8),
        UInt32(kVK_F9), UInt32(kVK_F10), UInt32(kVK_F11), UInt32(kVK_F12),
        UInt32(kVK_F13), UInt32(kVK_F14), UInt32(kVK_F15), UInt32(kVK_F16),
        UInt32(kVK_F17), UInt32(kVK_F18), UInt32(kVK_F19), UInt32(kVK_F20),
    ]

    private static let keyLabels: [UInt32: String] = [
        // Letters
        UInt32(kVK_ANSI_A): "A",
        UInt32(kVK_ANSI_B): "B",
        UInt32(kVK_ANSI_C): "C",
        UInt32(kVK_ANSI_D): "D",
        UInt32(kVK_ANSI_E): "E",
        UInt32(kVK_ANSI_F): "F",
        UInt32(kVK_ANSI_G): "G",
        UInt32(kVK_ANSI_H): "H",
        UInt32(kVK_ANSI_I): "I",
        UInt32(kVK_ANSI_J): "J",
        UInt32(kVK_ANSI_K): "K",
        UInt32(kVK_ANSI_L): "L",
        UInt32(kVK_ANSI_M): "M",
        UInt32(kVK_ANSI_N): "N",
        UInt32(kVK_ANSI_O): "O",
        UInt32(kVK_ANSI_P): "P",
        UInt32(kVK_ANSI_Q): "Q",
        UInt32(kVK_ANSI_R): "R",
        UInt32(kVK_ANSI_S): "S",
        UInt32(kVK_ANSI_T): "T",
        UInt32(kVK_ANSI_U): "U",
        UInt32(kVK_ANSI_V): "V",
        UInt32(kVK_ANSI_W): "W",
        UInt32(kVK_ANSI_X): "X",
        UInt32(kVK_ANSI_Y): "Y",
        UInt32(kVK_ANSI_Z): "Z",
        // Digits
        UInt32(kVK_ANSI_0): "0",
        UInt32(kVK_ANSI_1): "1",
        UInt32(kVK_ANSI_2): "2",
        UInt32(kVK_ANSI_3): "3",
        UInt32(kVK_ANSI_4): "4",
        UInt32(kVK_ANSI_5): "5",
        UInt32(kVK_ANSI_6): "6",
        UInt32(kVK_ANSI_7): "7",
        UInt32(kVK_ANSI_8): "8",
        UInt32(kVK_ANSI_9): "9",
        // Punctuation
        UInt32(kVK_ANSI_Equal): "=",
        UInt32(kVK_ANSI_Minus): "-",
        UInt32(kVK_ANSI_RightBracket): "]",
        UInt32(kVK_ANSI_LeftBracket): "[",
        UInt32(kVK_ANSI_Quote): "'",
        UInt32(kVK_ANSI_Semicolon): ";",
        UInt32(kVK_ANSI_Backslash): "\\",
        UInt32(kVK_ANSI_Comma): ",",
        UInt32(kVK_ANSI_Slash): "/",
        UInt32(kVK_ANSI_Period): ".",
        UInt32(kVK_ANSI_Grave): "`",
        UInt32(kVK_ISO_Section): "§",
        UInt32(kVK_JIS_Yen): "¥",
        UInt32(kVK_JIS_Underscore): "_",
        UInt32(kVK_JIS_KeypadComma): ",",
        UInt32(kVK_JIS_Eisu): "英数",
        UInt32(kVK_JIS_Kana): "かな",
        // Editing and navigation
        UInt32(kVK_Return): "↩",
        UInt32(kVK_Tab): "⇥",
        UInt32(kVK_Space): "Space",
        UInt32(kVK_Delete): "⌫",
        UInt32(kVK_ForwardDelete): "⌦",
        UInt32(kVK_Escape): "Esc",
        UInt32(kVK_Help): "Help",
        UInt32(kVK_Home): "↖",
        UInt32(kVK_End): "↘",
        UInt32(kVK_PageUp): "⇞",
        UInt32(kVK_PageDown): "⇟",
        UInt32(kVK_LeftArrow): "←",
        UInt32(kVK_RightArrow): "→",
        UInt32(kVK_UpArrow): "↑",
        UInt32(kVK_DownArrow): "↓",
        UInt32(kVK_ContextualMenu): "Menu",
        // Function keys
        UInt32(kVK_F1): "F1",
        UInt32(kVK_F2): "F2",
        UInt32(kVK_F3): "F3",
        UInt32(kVK_F4): "F4",
        UInt32(kVK_F5): "F5",
        UInt32(kVK_F6): "F6",
        UInt32(kVK_F7): "F7",
        UInt32(kVK_F8): "F8",
        UInt32(kVK_F9): "F9",
        UInt32(kVK_F10): "F10",
        UInt32(kVK_F11): "F11",
        UInt32(kVK_F12): "F12",
        UInt32(kVK_F13): "F13",
        UInt32(kVK_F14): "F14",
        UInt32(kVK_F15): "F15",
        UInt32(kVK_F16): "F16",
        UInt32(kVK_F17): "F17",
        UInt32(kVK_F18): "F18",
        UInt32(kVK_F19): "F19",
        UInt32(kVK_F20): "F20",
        // Keypad
        UInt32(kVK_ANSI_KeypadDecimal): ".",
        UInt32(kVK_ANSI_KeypadMultiply): "*",
        UInt32(kVK_ANSI_KeypadPlus): "+",
        UInt32(kVK_ANSI_KeypadClear): "⌧",
        UInt32(kVK_ANSI_KeypadDivide): "/",
        UInt32(kVK_ANSI_KeypadEnter): "⌤",
        UInt32(kVK_ANSI_KeypadMinus): "-",
        UInt32(kVK_ANSI_KeypadEquals): "=",
        UInt32(kVK_ANSI_Keypad0): "0",
        UInt32(kVK_ANSI_Keypad1): "1",
        UInt32(kVK_ANSI_Keypad2): "2",
        UInt32(kVK_ANSI_Keypad3): "3",
        UInt32(kVK_ANSI_Keypad4): "4",
        UInt32(kVK_ANSI_Keypad5): "5",
        UInt32(kVK_ANSI_Keypad6): "6",
        UInt32(kVK_ANSI_Keypad7): "7",
        UInt32(kVK_ANSI_Keypad8): "8",
        UInt32(kVK_ANSI_Keypad9): "9",
        // Media
        UInt32(kVK_VolumeUp): "Vol+",
        UInt32(kVK_VolumeDown): "Vol-",
        UInt32(kVK_Mute): "Mute",
        // Modifier keys (rejected by validation, but displayable)
        UInt32(kVK_Command): "⌘",
        UInt32(kVK_RightCommand): "⌘",
        UInt32(kVK_Shift): "⇧",
        UInt32(kVK_RightShift): "⇧",
        UInt32(kVK_Option): "⌥",
        UInt32(kVK_RightOption): "⌥",
        UInt32(kVK_Control): "⌃",
        UInt32(kVK_RightControl): "⌃",
        UInt32(kVK_CapsLock): "⇪",
        UInt32(kVK_Function): "Fn",
    ]
}
