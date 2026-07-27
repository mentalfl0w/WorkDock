import Foundation
import SwiftUI
import os

/// WorkDock module: Fujian Provincial Department of Education document platform.
///
/// Wraps ``FujianEducationSpider`` and exposes menu items, a main view, and
/// background polling. Credentials live in ``Creds`` (routed to Keychain or
/// file storage based on user preference); the last-seen UNID list lives in
/// ``Persistence``. On new documents, it fires a ``NotificationService``
/// notification whose click deep-links into the detail.
public final class FujianEducationModule: Module, CredentialStore {
    public let id = "fjsjyt"
    public let displayName = L.fjjytName
    public let icon = "doc.text.image"
    public let summary = L.fjjytSummary

    private let persistence: Persistence
    public let router: NavigationRouter
    private let notifications: NotificationService
    private let log = Logger(subsystem: "cn.dylanliu.workdock.fjsjyt", category: "Module")

    private var spider: FujianEducationSpider?
    private var cookieRefreshTask: Task<Void, Never>?
    private var reminderTask: Task<Void, Never>?
    /// Last time `isSignedIn` validation succeeded. Cached for 30 seconds
    /// to avoid hammering the server on every UI refresh.
    private var lastValidatedAt: ContinuousClock.Instant?
    private static let validationTTL: Duration = .seconds(30)

    // Defaults: cookie refresh 30 min, unread reminder 15 min.
    private var cookieRefreshInterval: TimeInterval {
        let m = UserDefaults.standard.double(forKey: "fjsjyt.cookieRefreshMinutes")
        return m > 0 ? m * 60 : 1800
    }
    private var reminderInterval: TimeInterval {
        let m = UserDefaults.standard.double(forKey: "fjsjyt.reminderMinutes")
        return m > 0 ? m * 60 : 900
    }

    public init(router: NavigationRouter, persistence: Persistence, notifications: NotificationService) {
        self.router = router
        self.persistence = persistence
        self.notifications = notifications
    }

    public var isSignedIn: Bool {
        get async {
            guard let spider = spider else { return false }
            if !(await spider.isLoggedIn) { return false }
            // Use cached validation if recent enough
            if let last = lastValidatedAt, ContinuousClock.now - last < Self.validationTTL {
                return true
            }
            // Validate session with a lightweight request
            do {
                _ = try await spider.fetchUserProfile()
                lastValidatedAt = ContinuousClock.now
                return true
            } catch {
                // Transient network failure — do NOT invalidate the session.
                // The cookie may still be valid; a network blip should not log
                // the user out. Return the last known state instead.
                log.warning("session validation failed (transient): \(error.localizedDescription, privacy: .public)")
                return await spider.isLoggedIn
            }
        }
    }

    public func menuItems() async -> [ModuleMenuItem] {
        // Use isSignedIn (with 30s cache) so the menu stays in sync with the
        // main view's login state. Direct spider.isLoggedIn can go false after
        // a transient validation failure, causing "not signed in" to show
        // even though the session is still alive.
        guard await isSignedIn else {
            return [
                .action(title: L.notSignedIn, icon: "person.crop.circle.badge.exclaimmark") { [weak self] in
                    guard let self else { return }
                    self.openMain(route: ["tab": "unread"])
                }
            ]
        }
        guard let spider = spider else {
            return [
                .action(title: L.notSignedIn, icon: "person.crop.circle.badge.exclaimmark") { [weak self] in
                    guard let self else { return }
                    self.openMain(route: ["tab": "unread"])
                }
            ]
        }
        let unread = (try? await spider.unreadCount()) ?? 0
        let latest = (try? await spider.unreadDocuments(pageSize: 1, start: 1).docs.first)
        var items: [ModuleMenuItem] = [
            .action(title: L.unreadMenuCount(unread), icon: "envelope.badge") { [weak self] in
                guard let self else { return }
                self.openMain(route: ["tab": "unread"])
            }
        ]
        if let latest = latest {
            items.append(.action(title: latest.title, icon: "doc.text") { [weak self] in
                guard let self else { return }
                self.openDetail(unid: latest.id)
            })
        }
        return items
    }

    @MainActor
    public func mainView() -> AnyView {
        AnyView(FujianEducationRootView(module: self))
    }

    public func start() async {
        guard cookieRefreshTask == nil else { return }
        // Try silent restore from persisted cookies.
        if let username = Creds.get(service: id, account: "username"),
           let cookieJSON = Creds.get(service: id, account: "cookies"),
           let data = cookieJSON.data(using: .utf8),
           let dicts = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
            let cookies = dicts.compactMap { d -> HTTPCookie? in
                var p: [HTTPCookiePropertyKey: Any] = [:]
                if let n = d["name"] as? String { p[.name] = n }
                if let v = d["value"] as? String { p[.value] = v }
                if let dom = d["domain"] as? String { p[.domain] = dom }
                if let pa = d["path"] as? String { p[.path] = pa }
                if let ex = d["expires"] as? String,
                   let date = ISO8601DateFormatter().date(from: ex) {
                    p[.expires] = date
                }
                return HTTPCookie(properties: p)
            }
            guard !cookies.isEmpty else {
                await tryPasswordLogin(username: username)
                startTimers()
                return
            }
            do {
                spider = try await FujianEducationSpider(username: username, cookies: cookies)
                log.info("restored session for \(username, privacy: .public)")
            } catch {
                log.error("cookie restore failed, trying password: \(error.localizedDescription, privacy: .public)")
                await tryPasswordLogin(username: username)
            }
        }
        startTimers()
    }

    private func startTimers() {
        // Cookie refresh: periodically re-login to keep cookies alive.
        cookieRefreshTask?.cancel()
        cookieRefreshTask = Task { [weak self] in
            while let self = self, !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(self.cookieRefreshInterval * 1_000_000_000))
                guard !Task.isCancelled else { break }
                await self.refreshCookies()
            }
        }
        // Unread reminder: periodically check unread count and notify a summary.
        reminderTask?.cancel()
        reminderTask = Task { [weak self] in
            while let self = self, !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(self.reminderInterval * 1_000_000_000))
                guard !Task.isCancelled else { break }
                await self.remindUnread()
            }
        }
    }

    public func stop() async {
        cookieRefreshTask?.cancel(); cookieRefreshTask = nil
        reminderTask?.cancel(); reminderTask = nil
    }

    /// Re-login with saved password to refresh cookies before they expire.
    private func refreshCookies() async {
        guard let username = Creds.get(service: id, account: "username"),
              let password = Creds.get(service: id, account: "password") else { return }
        do {
            let s = try await FujianEducationSpider(username: username, password: password)
            spider = s
            let cookies = await s.cookies()
            let dicts: [[String: Any]] = cookies.map { c in
                var p: [String: Any] = ["name": c.name, "value": c.value, "domain": c.domain, "path": c.path]
                if let d = c.expiresDate { p["expires"] = ISO8601DateFormatter().string(from: d) }
                return p
            }
            let data = try JSONSerialization.data(withJSONObject: dicts)
            Creds.set(service: id, account: "cookies", value: String(data: data, encoding: .utf8) ?? "")
            log.info("cookie refreshed for \(username, privacy: .public)")
        } catch {
            log.error("cookie refresh failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Periodic unread summary notification — one notification summarising
    /// how many unread documents remain, grouped by urgency level.
    private func remindUnread() async {
        guard let spider = spider, await spider.isLoggedIn else { return }
        do {
            let (docs, total) = try await spider.unreadDocuments(pageSize: 100, start: 1)
            let count = max(docs.count, total)
            guard count > 0 else { return }
            // Group by urgency label.
            var groups: [String: Int] = [:]
            for d in docs {
                let label = urgencyLabel(d.urgency)
                groups[label, default: 0] += 1
            }
            let parts = groups.sorted { $0.key < $1.key }.map { "\($0.key) \($0.value) \(L.items)" }
            let body = "\(count) \(L.unreadCount)" + parts.joined(separator: L.separator)
            let target = JumpTarget.route(moduleID: id, payload: ["tab": "unread"])
            await notifications.notify(title: L.unreadReminderTitle, body: body, target: target)
            log.info("unread reminder sent: \(count, privacy: .public) docs")
        } catch {
            log.error("reminder failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func urgencyLabel(_ u: String) -> String {
        let v = u.trimmingCharacters(in: .whitespacesAndNewlines)
        if v.contains("特急") || v == "3" { return L.urgent }
        if v.contains("加急") || v == "2" { return L.rush }
        return L.normal
    }

    /// Attempt silent re-login with persisted password (cookie expired fallback).
    private func tryPasswordLogin(username: String) async {
        guard let password = Creds.get(service: id, account: "password") else {
            spider = nil
            return
        }
        do {
            spider = try await FujianEducationSpider(username: username, password: password)
            log.info("re-logged in with saved password for \(username, privacy: .public)")
        } catch {
            spider = nil
            log.error("password re-login failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Public entry points for the UI

    /// Password login (called from the login view).
    public func signIn(username: String, password: String, remember: Bool = true) async throws {
        let s = try await FujianEducationSpider(username: username, password: password)
        self.spider = s
        let cookies = await s.cookies()
        let dicts: [[String: Any]] = cookies.map { c in
            var p: [String: Any] = [
                "name": c.name, "value": c.value,
                "domain": c.domain, "path": c.path
            ]
            if let d = c.expiresDate {
                p["expires"] = ISO8601DateFormatter().string(from: d)
            }
            return p
        }
        let data = try JSONSerialization.data(withJSONObject: dicts)
        Creds.set(service: id, account: "username", value: username)
        if remember {
            Creds.set(service: id, account: "password", value: password)
        } else {
            Creds.delete(service: id, account: "password")
        }
        Creds.set(service: id, account: "cookies", value: String(data: data, encoding: .utf8) ?? "")
    }

    public func signOut() {
        spider = nil
        Creds.delete(service: id, account: "password")
        Creds.delete(service: id, account: "cookies")
    }

    // MARK: - CredentialStore

    public func load() async -> (identifier: String, secret: String)? {
        guard let user = Creds.get(service: id, account: "username") else { return nil }
        let pass = Creds.get(service: id, account: "password") ?? ""
        return (user, pass)
    }



    public func unreadDocuments(pageSize: Int = 20, start: Int = 1) async throws -> (docs: [DocumentSummary], total: Int) {
        guard let spider = spider else { throw SpiderError.notLoggedIn }
        return try await spider.unreadDocuments(pageSize: pageSize, start: start)
    }

    public func readDocuments(pageSize: Int = 20, start: Int = 1) async throws -> (docs: [DocumentSummary], total: Int) {
        guard let spider = spider else { throw SpiderError.notLoggedIn }
        return try await spider.readDocuments(pageSize: pageSize, start: start)
    }

    public func unreadDetail(unid: String) async throws -> DocumentDetail {
        guard let spider = spider else { throw SpiderError.notLoggedIn }
        return try await spider.unreadDetail(unid: unid)
    }

    public func attachments(for detail: DocumentDetail) async throws -> [Attachment] {
        guard let spider = spider else { throw SpiderError.notLoggedIn }
        return try await spider.attachments(key: detail.key, database: detail.database)
    }

    public func downloadAttachment(url: URL) async throws -> Data {
        guard let spider = spider else { throw SpiderError.notLoggedIn }
        return try await spider.downloadData(url: url)
    }

    /// Download attachment to a destination file.
    public func downloadAttachment(url: URL, to destination: URL) async throws {
        guard let spider = spider else { throw SpiderError.notLoggedIn }
        try await spider.downloadFile(url: url, to: destination)
    }

    public func signDocument(unid: String) async throws -> Bool {
        guard let spider = spider else { throw SpiderError.notLoggedIn }
        return try await spider.signDocument(unid: unid)
    }

    public func search(_ word: String, pageSize: Int = 20, isRead: Bool = true) async throws -> (docs: [DocumentSummary], noteIDs: [String], total: Int) {
        guard let spider = spider else { throw SpiderError.notLoggedIn }
        return try await spider.search(word, pageSize: pageSize, isRead: isRead)
    }

    public func searchPage(noteIDs: [String], isRead: Bool = true) async throws -> [DocumentSummary] {
        guard let spider = spider else { throw SpiderError.notLoggedIn }
        return try await spider.searchPage(noteIDs: noteIDs, isRead: isRead)
    }

    @MainActor
    private func openMain(route: [String: String]) {
        router.openMainWindow()
        router.navigate(moduleID: id, payload: route)
    }

    @MainActor
    private func openDetail(unid: String) {
        router.openMainWindow()
        router.navigate(moduleID: id, payload: ["unid": unid])
    }
    // MARK: - Credential Store Routing

    /// Routes credential operations to Keychain or File storage based on user preference.
    private enum Creds {
        static var useKeychain: Bool {
            UserDefaults.standard.bool(forKey: "fjsjyt.useKeychain")
        }
        static func set(service: String, account: String, value: String) {
            if useKeychain {
                KeychainCredentialStore.set(service: service, account: account, value: value)
            } else {
                FileCredentialStore.set(service: service, account: account, value: value)
            }
        }
        static func get(service: String, account: String) -> String? {
            if useKeychain {
                return KeychainCredentialStore.get(service: service, account: account)
            } else {
                return FileCredentialStore.get(service: service, account: account)
            }
        }
        static func delete(service: String, account: String) {
            if useKeychain {
                KeychainCredentialStore.delete(service: service, account: account)
            } else {
                FileCredentialStore.delete(service: service, account: account)
            }
        }
    }
}

