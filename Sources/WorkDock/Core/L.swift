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
    public static let settingsSummary = isZh ? "Dock 显示、开机自启、关于。" : "Dock visibility, launch at login, about."
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
}
