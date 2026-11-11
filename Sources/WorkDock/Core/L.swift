import Foundation

/// Localization support for WorkDock. Provides zh/en strings for all UI labels.
///
/// Usage: `L.title`, `L.settings`, etc. Automatically picks the system language.
public enum L {
    private static let isZh = (Locale.current.language.languageCode?.identifier ?? "en").hasPrefix("zh")

    // MARK: - App
    public static let appName = isZh ? "工作坞" : "WorkDock"
    public static let chooseModule = isZh ? "选择一个模块开始" : "Choose a module to start"
    public static let openApp = isZh ? "打开 工作坞" : "Open WorkDock"
    public static let quitApp = isZh ? "退出 工作坞" : "Quit WorkDock"

    // MARK: - Navigation
    public static let backToModules = isZh ? "模块" : "Modules"

    // MARK: - Settings
    public static let settings = isZh ? "设置" : "Settings"
    public static let settingsSummary = isZh ? "Dock 显示、开机自启、网络代理、关于。" : "Dock visibility, launch at login, network proxy, about."
    public static let general = isZh ? "通用" : "General"
    public static let showDockIcon = isZh ? "在 Dock 中显示图标" : "Show icon in Dock"
    public static let launchAtLogin = isZh ? "开机时自动启动" : "Launch at login"
    public static let about = isZh ? "关于" : "About"
    public static let version = isZh ? "版本" : "Version"
    public static let author = isZh ? "作者" : "Author"
    public static let copyright = isZh ? "版权" : "Copyright"

    // MARK: - Login
    public static let rememberCredential = isZh ? "记住凭据" : "Remember"
    public static let cancel = isZh ? "取消" : "Cancel"
    public static let loggingIn = isZh ? "登录中…" : "Logging in…"
    public static let login = isZh ? "登录" : "Login"
    public static let credentialEmpty = isZh ? "凭据不能为空" : "Credentials cannot be empty"

    // MARK: - FJJYT Module
    public static let fjjytName = isZh ? "福建省教育厅收文" : "Fujian Education Receipt"
    public static let fjjytSummary = isZh ? "收文列表、详情查看、附件下载与签收。" : "Document list, detail view, download & sign."
    public static let username = isZh ? "用户名" : "Username"
    public static let password = isZh ? "密码" : "Password"
    public static let unread = isZh ? "未收" : "Unread"
    public static let read = isZh ? "已收" : "Read"
    public static let search = isZh ? "搜索" : "Search"
    public static let settingsLabel = isZh ? "设置" : "Settings"
    public static let logout = isZh ? "退出" : "Logout"
    public static let close = isZh ? "关闭" : "Close"
    public static let refresh = isZh ? "刷新" : "Refresh"
    public static let download = isZh ? "下载附件" : "Download"
    public static let downloadAll = isZh ? "下载全部" : "Download All"
    public static let selectFolder = isZh ? "选择保存文件夹" : "Select Save Folder"
    public static let attachments = isZh ? "附件" : "Attachments"
    public static let signin = isZh ? "签收" : "Sign"
    public static let publishNote = isZh ? "发布说明" : "Publish Note"
    public static let pageSize = isZh ? "每页" : "Per page"
    public static let pages = isZh ? "页" : "pages"
    public static let itemsPerPage = isZh ? "条" : "items"
    public static let totalDocs = isZh ? "篇" : "docs"
    public static let downloadFailed = isZh ? "下载失败" : "Download failed"
    public static let batchFailed = isZh ? "个附件下载失败" : "attachments failed"
    public static let keyword = isZh ? "关键词" : "Keywords"
    public static let searchInRead = isZh ? "已收" : "Received"
    public static let searchInUnread = isZh ? "未收" : "Unreceived"
    public static let notSignedIn = isZh ? "未登录" : "Not signed in"

    // MARK: - FJJYT Settings
    public static let cookieRefreshInterval = isZh ? "Cookie 刷新间隔" : "Cookie refresh interval"
    public static let reminderInterval = isZh ? "未收提醒间隔" : "Unread reminder interval"
    public static let minutes = isZh ? "分钟" : "min"

    // MARK: - FJJYT Notifications
    public static let unreadReminderTitle = isZh ? "福建省教育厅未收提醒" : "Fujian Education unread reminder"
    public static let unreadCount = isZh ? "件未收：" : "unread: "
    public static let separator = isZh ? "，" : ", "
    public static let items = isZh ? "件" : "items"

    // MARK: - FJJYT Urgency
    public static let urgent = isZh ? "特急" : "Urgent"
    public static let rush = isZh ? "加急" : "Rush"
    public static let normal = isZh ? "一般" : "Normal"

    // MARK: - Pagination
    public static func totalCount(_ count: Int, page: Int, total: Int) -> String {
        if isZh { return "共 \(count) 篇 · 第 \(page)/\(total) 页" }
        return "\(count) docs · Page \(page)/\(total)"
    }
    public static func pageSizeLabel(_ n: Int) -> String {
        if isZh { return "\(n)条" }
        return "\(n) items"
    }
    public static func unreadMenuCount(_ n: Int) -> String {
        if isZh { return "未读 \(n) 篇" }
        return "\(n) unread"
    }
    // MARK: - Demo Module
    public static let demoName = isZh ? "组件预览" : "Components"
    public static let demoSummary = isZh ? "预览 Liquid Glass、按钮、分页等组件。" : "Preview Liquid Glass, buttons, pagination."
    public static let demoGlassEffect = isZh ? "液态玻璃" : "Glass Effect"
    public static let demoUrgency = isZh ? "紧急程度" : "Urgency"
    public static let demoDocDetail = isZh ? "文档详情" : "Document Detail"
    public static let demoOpenDocDetail = isZh ? "打开文档详情预览" : "Open Document Detail Preview"
    public static let demoPagination = isZh ? "分页" : "Pagination"
    public static let demoButtons = isZh ? "按钮" : "Buttons"
    // MARK: - Credential Storage
    public static let useKeychain = isZh ? "使用钥匙串存储" : "Use Keychain Storage"
    public static let useKeychainDesc = isZh ? "更安全，但需要 Apple 开发者证书签名。当前使用文件存储。" : "More secure, requires Apple Developer certificate. Currently using file storage."

    // MARK: - Network Proxy
    public static let network = isZh ? "网络" : "Network"
    public static let proxyMode = isZh ? "代理模式" : "Proxy Mode"
    public static let proxyDirect = isZh ? "直接连接" : "Direct"
    public static let proxySystem = isZh ? "系统代理" : "System"
    public static let proxyCustom = isZh ? "自定义" : "Custom"
    public static let proxyType = isZh ? "代理类型" : "Proxy Type"
    public static let proxyTypeHTTP = isZh ? "HTTP/HTTPS" : "HTTP/HTTPS"
    public static let proxyTypeSOCKS5 = isZh ? "SOCKS5" : "SOCKS5"
    public static let proxyHost = isZh ? "代理主机" : "Proxy Host"
    public static let proxyPort = isZh ? "端口" : "Port"
    public static let proxyHostPlaceholder = isZh ? "例如 proxy.example.com" : "e.g. proxy.example.com"
    public static let proxySaveApply = isZh ? "保存并应用" : "Save & Apply"
    public static let proxyApplying = isZh ? "应用中…" : "Applying…"
    public static let proxyHostRequired = isZh ? "请输入代理主机地址" : "Enter a proxy host address"
    public static let proxyPortInvalid = isZh ? "端口需在 1–65535 之间" : "Port must be between 1 and 65535"
    public static let proxyApplied = isZh ? "设置已保存，代理策略已生效。" : "Settings saved; the proxy policy is now in effect."
    public static let proxyRebuildFailed = isZh ? "设置已保存，但活动会话重建失败（原会话已关闭）。" : "Settings saved, but the active session could not be rebuilt (it was closed)."
    public static let proxySaveFailed = isZh ? "保存失败，请重试。" : "Save failed. Please try again."

    // MARK: - OCR Module
    public static let ocrName = isZh ? "截图识字" : "Screenshot OCR"
    public static let ocrSummary = isZh ? "本地中英文 OCR：框选截图、剪贴板或图片文件。" : "Local Chinese/English OCR from a screen region, clipboard, or file."
    public static let ocrScreenshot = isZh ? "截图" : "Screenshot"
    public static let ocrClipboard = isZh ? "剪贴板" : "Clipboard"
    public static let ocrChooseImage = isZh ? "图片…" : "Image…"
    public static let ocrChooseImageTitle = isZh ? "选择图片" : "Choose an Image"
    public static let ocrOpen = isZh ? "打开" : "Open"
    public static let ocrOpenPanel = isZh ? "打开识别窗口" : "Open OCR Window"
    public static let ocrOpenModule = isZh ? "在模块中打开" : "Open in Module"
    public static let ocrCancel = isZh ? "取消识别" : "Cancel"
    public static let ocrWorking = isZh ? "处理中" : "Working"
    public static let ocrCapturing = isZh ? "等待框选区域…（Esc 取消）" : "Select a region… (Esc to cancel)"
    public static let ocrRecognizing = isZh ? "正在识别…" : "Recognizing…"
    public static let ocrIdle = isZh ? "截图、粘贴或选择图片开始识别" : "Capture, paste, or choose an image to start."
    public static let ocrDone = isZh ? "识别完成" : "Done"
    public static let ocrCancelled = isZh ? "已取消" : "Cancelled"
    public static let ocrCopy = isZh ? "复制文本" : "Copy Text"
    public static let ocrCopied = isZh ? "已复制" : "Copied"
    public static let ocrPlaceholder = isZh ? "识别出的文字会显示在这里，可自行编辑。" : "Recognized text appears here and can be edited."
    public static let ocrShortcuts = isZh ? "快捷键" : "Shortcuts"
    public static let ocrShortcutHint = isZh ? "由快捷键管理器接入后显示" : "Provided by the hotkey manager."
    public static let ocrLocalOnly = isZh ? "全部识别均在本机完成，不联网，结果不会保存。" : "All recognition runs locally, offline. Results are never saved."
    public static let ocrPermissionTitle = isZh ? "需要屏幕录制权限" : "Screen Recording required"
    public static let ocrPermissionBody = isZh ? "框选截图需要“屏幕录制”权限。请在系统设置中为 WorkDock 开启；若已开启仍失败，请重启 WorkDock。" : "Capturing a region needs Screen Recording access. Enable it for WorkDock in System Settings; restart WorkDock if it still fails."
    public static let ocrOpenSettings = isZh ? "打开系统设置" : "Open Settings"
    public static let ocrRetry = isZh ? "重试" : "Try Again"
    public static let ocrClipboardEmpty = isZh ? "剪贴板里没有图片。" : "The clipboard has no image."
    public static let ocrImageInvalid = isZh ? "无法解码这张图片。" : "This image could not be decoded."
    public static let ocrNoText = isZh ? "未识别到文字。" : "No text was found."
    public static let ocrCaptureBusy = isZh ? "已有截图正在进行。" : "A capture is already running."
    public static let ocrScreenSource = isZh ? "截图" : "Screen"
    public static let ocrClipboardSource = isZh ? "剪贴板" : "Clipboard"
    public static let ocrFileSource = isZh ? "图片" : "Image"

    public static func ocrImageUnreadable(_ name: String) -> String {
        isZh ? "无法读取“\(name)”。" : "Could not read “\(name)”."
    }
    public static func ocrRecognitionFailed(_ reason: String) -> String {
        isZh ? "识别失败：\(reason)" : "Recognition failed: \(reason)"
    }
    public static func ocrCaptureFailed(_ reason: String) -> String {
        isZh ? "无法截图：\(reason)" : "Capture failed: \(reason)"
    }
    public static func ocrConfidence(_ percent: Int) -> String {
        isZh ? "置信度 \(percent)%" : "Confidence \(percent)%"
    }
    public static func ocrLineCount(_ count: Int) -> String {
        isZh ? "\(count) 行" : "\(count) lines"
    }
    public static func ocrPixelSize(_ width: Int, _ height: Int) -> String {
        "\(width)×\(height)"
    }
    public static func ocrDuration(_ seconds: Double) -> String {
        isZh ? String(format: "%.2f 秒", seconds) : String(format: "%.2f s", seconds)
    }
}
