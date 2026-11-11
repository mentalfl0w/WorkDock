import Foundation
import Carbon.HIToolbox

/// Localized copy for the global-hotkey feature.
///
/// Kept in its own file so the feature can be added to the app without editing
/// the shared ``L`` namespace.
enum HotkeyText {
    private static let isZh = (Locale.current.language.languageCode?.identifier ?? "en").hasPrefix("zh")

    // MARK: - Settings UI

    static let sectionTitle = isZh ? "截图快捷键" : "Screenshot Shortcut"
    static let enabled = isZh ? "启用快捷键" : "Enable Shortcut"
    static let shortcutLabel = isZh ? "快捷键" : "Shortcut"
    static let recording = isZh ? "请按快捷键…" : "Press shortcut…"
    static let recordHint = isZh
        ? "点击后按下新的组合键，Esc 取消"
        : "Click, then press a new combination. Esc cancels."
    static let save = isZh ? "保存" : "Save"
    static let restoreDefault = isZh ? "恢复默认" : "Restore Default"
    static let retry = isZh ? "重试" : "Retry"
    static let active = isZh ? "当前生效" : "Active"
    static let inactive = isZh ? "当前未生效" : "Not active"
    static let hint = isZh
        ? "在其他应用处于前台时也能触发。系统或其它应用已占用的组合无法注册。"
        : "Works while another app is frontmost. Combinations owned by the system or another app cannot be registered."

    // MARK: - Status

    static let enabledStatus = isZh ? "快捷键已启用。" : "Shortcut enabled."
    static let disabledStatus = isZh ? "快捷键已停用。" : "Shortcut disabled."
    static let saved = isZh ? "快捷键已保存并生效。" : "Shortcut saved and active."
    static let savedInactive = isZh ? "快捷键已保存，启用后生效。" : "Shortcut saved; it takes effect when enabled."
    static let restored = isZh ? "已恢复默认快捷键。" : "Default shortcut restored."
    static let restoredInactive = isZh ? "已恢复默认快捷键，启用后生效。" : "Default shortcut restored; it takes effect when enabled."
    static let retained = isZh ? "原快捷键保持不变。" : "The previous shortcut is unchanged."

    // MARK: - Errors

    static let unsupportedKey = isZh
        ? "该按键不能用作全局快捷键。"
        : "That key cannot be used as a global shortcut."
    static let modifierRequired = isZh
        ? "请至少使用 ⌘、⌥ 或 ⌃ 之一（F1–F20 可单独使用）。"
        : "Use at least one of ⌘, ⌥, or ⌃ (F1–F20 work alone)."
    static let alreadyInUse = isZh
        ? "该快捷键已被系统或其它应用占用。"
        : "That shortcut is already used by the system or another app."

    static func systemFailure(_ status: OSStatus) -> String {
        isZh
            ? "系统未能注册该快捷键（错误 \(status)）。"
            : "The system could not register that shortcut (error \(status))."
    }

    static func handlerFailure(_ status: OSStatus) -> String {
        isZh
            ? "快捷键监听初始化失败（错误 \(status)）。"
            : "Shortcut monitoring failed to initialize (error \(status))."
    }

    static func message(for error: GlobalHotkeyRegistrationError) -> String {
        switch error {
        case .invalidCombination(let validation):
            switch validation {
            case .unsupportedKey: return unsupportedKey
            case .modifierRequired: return modifierRequired
            }
        case .alreadyInUse:
            return alreadyInUse
        case .systemError(let status):
            return systemFailure(status)
        case .handlerInstallationFailed(let status):
            return handlerFailure(status)
        }
    }
}
