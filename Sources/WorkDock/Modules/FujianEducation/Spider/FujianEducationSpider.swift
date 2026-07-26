import Foundation
import os

/// Network client for the Fujian Provincial Department of Education document platform.
///
/// Native Swift port of the original Python `FJJYT_Spider`. An `actor`
/// serializes access to the cookie jar (the Python `requests.session()`
/// equivalent), so concurrent callers can't race on login state. All endpoints
/// map 1:1 to the original methods; the Flask layer (`fjsjyt_module.py`) is
/// gone — callers invoke these methods directly.
public actor FujianEducationSpider {

    // MARK: - Endpoints (private, mirroring __*_url in the Python class)

    private static let loginURL = URL(string: "http://yunoa.fjsjyt.cn:8080/servlet/UniLogin?Open&Debug=false&Log=false&SSO=false")!
    private static let readedCountURL = URL(string: "http://yunoa.fjsjyt.cn:8080/egov60/rjmain.nsf/GetRecordCount?OpenAgent&View=ReceivedByTime&DbName=docs/10003.nsf&Server=CN=FJSJYT/OU=SRV/O=FJJY")!
    private static let unreadCountURL = URL(string: "http://yunoa.fjsjyt.cn:8080/egov60/rjmain.nsf/GetRecordCount?OpenAgent&View=ToReceiveSort&DbName=docs/10003.nsf&Server=CN=FJSJYT/OU=SRV/O=FJJY")!
    private static let userInfoURL = URL(string: "http://yunoa.fjsjyt.cn:8080/egov60/DocUnit.nsf/DbInterfaceConfig?OpenForm&Module=10003&DbName=docs/10003.nsf")!
    private static let attachURL = URL(string: "http://yunoa.fjsjyt.cn:8080/servlet/GetDocInfos?open")!
    private static let signinBase = "http://yunoa.fjsjyt.cn:8080/egov60/docunit.nsf/DocumentSignin?OpenAgent"
    private static let searchBase = "http://yunoa.fjsjyt.cn:8080/egov60/rjmain.nsf/ViewSearch?OpenAgent"

    private static let defaultHeaders: [String: String] = [
        "Host": "yunoa.fjsjyt.cn:8080",
        "Origin": "http://yunoa.fjsjyt.cn:8080",
        "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/112.0.0.0 Safari/537.36 Edg/112.0.1722.34"
    ]

    // MARK: - State

    private let session: URLSession
    /// Manually managed cookie store. Private HTTPCookieStorage() instances
    /// silently reject setCookie for cookies whose domain/path don't pass
    /// validation, which is why URLSession auto-cookie handling failed us.
    /// Mirrors Python `requests.Session.cookies` as a flat dict. Thread-safe
    /// via OSAllocatedUnfairLock so the URLSession delegate (non-isolated)
    /// and the actor can both mutate it.
    private let cookieJar: CookieBox = CookieBox()
    private var interceptor: RedirectCookieInterceptor?
    private let log = Logger(subsystem: "cn.liujiangnan.WorkDock.fjsjyt", category: "Spider")
    public private(set) var isLoggedIn = false
    /// Marks the session as invalid (called when a request fails due to expired cookies).
    public func invalidateSession() {
        isLoggedIn = false
        log.warning("session invalidated")
    }
    public let username: String

    // MARK: - Init (two paths: password or persisted cookies)

    public init(username: String, password: String) async throws {
        self.username = username
        let config = URLSessionConfiguration.ephemeral
        config.httpShouldSetCookies = false
        config.httpCookieAcceptPolicy = .never
        config.timeoutIntervalForRequest = 20
        let delegate = RedirectCookieInterceptor { [cookieJar] name, value in
            cookieJar.set(name, value)
        }
        self.session = URLSession(configuration: config, delegate: delegate, delegateQueue: nil)
        self.interceptor = delegate
        try await login(password: password)
    }

    public init(username: String, cookies: [HTTPCookie]) async throws {
        self.username = username
        let config = URLSessionConfiguration.ephemeral
        config.httpShouldSetCookies = false
        config.httpCookieAcceptPolicy = .never
        config.timeoutIntervalForRequest = 20
        let delegate = RedirectCookieInterceptor { [cookieJar] name, value in
            cookieJar.set(name, value)
        }
        self.session = URLSession(configuration: config, delegate: delegate, delegateQueue: nil)
        self.interceptor = delegate
        for c in cookies { cookieJar.set(c.name, c.value) }
        let profile = try await fetchUserProfile()
        guard !profile.userName.isEmpty else {
            log.error("cookie login returned empty profile — session is stale")
            throw SpiderError.http(status: 0, body: "cookie restore returned empty user profile")
        }
        isLoggedIn = true
        log.info("cookie login ok for \(username, privacy: .public)")
    }

    // MARK: - Auth

    private func login(password: String) async throws {
        let encoded = Data(password.utf8).base64EncodedString()
        let body = "Username=\(username)&Password=\(encoded)&RedirectTo=%2Fegov60%2Fdocnames.nsf%2FIndex%3FOpenForm&b=1"
        var req = URLRequest(url: Self.loginURL)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        for (k, v) in Self.defaultHeaders { req.setValue(v, forHTTPHeaderField: k) }
        req.httpBody = body.data(using: .utf8)

        let (_, resp) = try await session.data(for: req)
        // Manually extract Set-Cookie from the login response too — the
        // redirect interceptor handles 302s, but the final 200 may also set
        // cookies, and we cannot rely on URLSession auto-storing them into
        // our private HTTPCookieStorage instance.
        if let http = resp as? HTTPURLResponse, let url = req.url {
            let headers = http.allHeaderFields as? [String: String] ?? [:]
            for cookie in HTTPCookie.cookies(withResponseHeaderFields: headers, for: url) {
                FileLog.shared.debug("  login cookie props: name=\(cookie.name) domain=\(cookie.domain) path=\(cookie.path) value=\(cookie.value.prefix(20))")
                cookieJar.set(cookie.name, cookie.value)
            }
        }
        guard let http = resp as? HTTPURLResponse else { throw SpiderError.network(URLError(.badServerResponse)) }
        // URLSession follows redirects by default (unlike Python's
        // allow_redirects=False). Login success = session cookie present.
        let cookieSnapshot = cookieJar.snapshot()
        FileLog.shared.log("[Spider] login status=\(http.statusCode) cookies=\(cookieSnapshot.map { "\($0.key)=\($0.value.prefix(20))" })")
        let hasSession = cookieSnapshot.keys.contains { $0 == "DomAuthSessId" || $0 == "LtpaToken" || $0 == "SessionID" }
        if hasSession {
            isLoggedIn = true
            FileLog.shared.log("[Spider] login ok for \(self.username) status=\(http.statusCode)")
        } else {
            isLoggedIn = false
            FileLog.shared.error("[Spider] login failed status=\(http.statusCode)")
            throw SpiderError.http(status: http.statusCode, body: "no session cookie after login")
        }
    }

    /// Snapshot cookies for persistence (Python `get_cookies_str`).
    public func cookieDictionary() -> [String: String] {
        cookieJar.snapshot()
    }

    public func cookies() -> [HTTPCookie] {
        guard let url = URL(string: "http://yunoa.fjsjyt.cn:8080") else { return [] }
        let snapshot = cookieJar.snapshot()
        return snapshot.compactMap { (name, value) in
            HTTPCookie(properties: [.name: name, .value: value, .domain: url.host!, .path: "/"])
        }
    }

    // MARK: - Counts

    public func unreadCount() async throws -> Int {
        let data = try await postData(url: Self.unreadCountURL)
        let doc = try XMLDocument(xmlData: data)
        guard let s = doc.first("//DIV/text()")?.trimmingCharacters(in: .whitespacesAndNewlines),
              let n = Int(s) else { throw SpiderError.parse(message: "unread count: \(String(data: data, encoding: .utf8) ?? "?")") }
        return n
    }

    public func readCount() async throws -> Int {
        let data = try await postData(url: Self.readedCountURL)
        let doc = try XMLDocument(xmlData: data)
        guard let s = doc.first("//DIV/text()")?.trimmingCharacters(in: .whitespacesAndNewlines),
              let n = Int(s) else { throw SpiderError.parse(message: "read count: \(String(data: data, encoding: .utf8) ?? "?")") }
        return n
    }

    // MARK: - Lists

    public func unreadDocuments(pageSize: Int = 40, start: Int = 1) async throws -> (docs: [DocumentSummary], total: Int) {
        let urlStr = "http://yunoa.fjsjyt.cn:8080/docs/10003.nsf/ToReceiveSort?ReadViewEntries&Count=\(pageSize)&Start=\(start)&ResortAscending=0"
        let data = try await postData(url: URL(string: urlStr)!)
        let doc = try XMLDocument(xmlData: data)
        let total = Int(doc.attr("//viewentries", "toplevelentries") ?? "0") ?? 0
        let count = doc.count("//viewentry")
        var out: [DocumentSummary] = []
        for i in 1...max(count, 1) {
            guard i <= count else { break }
            let pos = i + start - 1
            let subject = xpathFirst(doc, "//viewentry[@position='\(pos)']//entrydata[@name='$Subject']/text/text()")
            let pubTime = xpathFirst(doc, "//viewentry[@position='\(pos)']//entrydata[@name='$PublishTime']/text/text()")
            let unit = xpathFirst(doc, "//viewentry[@position='\(pos)']//entrydata[@name='$Unit']/text/text()")
            let unid = doc.attr("//viewentry[@position='\(pos)']", "unid") ?? ""
            let noteid = doc.attr("//viewentry[@position='\(pos)']", "noteid") ?? ""
            let docMark = xpathFirst(doc, "//viewentry[@position='\(pos)']//entrydata[@name='$DocMark']/text/text()")
            let urgency = xpathFirst(doc, "//viewentry[@position='\(pos)']//entrydata[@name='$UrgencyLevel']/text/text()")
            FileLog.shared.debug("[Spider] unread urgency raw: '\(urgency ?? "")' for pos=\(pos)")
            guard let s = subject, let p = pubTime, let u = unit, !unid.isEmpty else { continue }
            out.append(DocumentSummary(
                id: unid, noteID: noteid, title: s, publisher: u,
                publishedAt: p, docMark: docMark ?? "", urgency: urgency ?? ""))
        }
        return (out, total)
    }

    public func readDocuments(pageSize: Int = 20, start: Int = 1) async throws -> (docs: [DocumentSummary], total: Int) {
        let urlStr = "http://yunoa.fjsjyt.cn:8080/docs/10003.nsf/ReceivedByTime?ReadViewEntries&Count=\(pageSize)&Start=\(start)&ResortDescending=2"
        let data = try await postData(url: URL(string: urlStr)!)
        let doc = try XMLDocument(xmlData: data)
        let total = Int(doc.attr("//viewentries", "toplevelentries") ?? "0") ?? 0
        let count = doc.count("//viewentry")
        var out: [DocumentSummary] = []
        for i in 1...max(count, 1) {
            guard i <= count else { break }
            let pos = i + start - 1
            let subject = xpathFirst(doc, "//viewentry[@position='\(pos)']//entrydata[@name='$Subject']/text/text()")
            let pubTime = xpathFirst(doc, "//viewentry[@position='\(pos)']//entrydata[@name='$PublishTime']/text/text()")
            let unit = xpathFirst(doc, "//viewentry[@position='\(pos)']//entrydata[@name='$Unit']/text/text()")
            let unid = doc.attr("//viewentry[@position='\(pos)']", "unid") ?? ""
            let noteid = doc.attr("//viewentry[@position='\(pos)']", "noteid") ?? ""
            let docMark = xpathFirst(doc, "//viewentry[@position='\(pos)']//entrydata[@name='$DocMark']/text/text()")
            let urgency = xpathFirst(doc, "//viewentry[@position='\(pos)']//entrydata[@name='$UrgencyLevel']/text/text()")
                ?? xpathFirst(doc, "//viewentry[@position='\(pos)']//entrydata[@name='$UrgencyLevel']/number/text()")
            FileLog.shared.debug("[Spider] read urgency raw: '\(urgency ?? "")' for pos=\(pos)")
            guard let s = subject, let p = pubTime, let u = unit, !unid.isEmpty else { continue }
            out.append(DocumentSummary(
                id: unid, noteID: noteid, title: s, publisher: u,
                publishedAt: p, docMark: docMark ?? "", urgency: urgency ?? ""))
        }
        return (out, total)
    }

    /// Download raw bytes for an attachment URL (carries auth cookies).
    public func downloadData(url: URL) async throws -> Data {
        try await getData(url: url)
    }

    /// Download attachment to a destination file.
    public func downloadFile(url: URL, to destination: URL) async throws {
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        for (k, v) in Self.defaultHeaders { req.setValue(v, forHTTPHeaderField: k) }
        if let cookie = cookieJar.header() { req.setValue(cookie, forHTTPHeaderField: "Cookie") }
        FileLog.shared.debug("→ GET \(url.path) cookies=\(cookieJar.allKeys)")

        let (tmpURL, resp) = try await session.download(for: req)
        guard let http = resp as? HTTPURLResponse else { throw SpiderError.network(URLError(.badServerResponse)) }
        guard (200...299).contains(http.statusCode) else {
            throw SpiderError.http(status: http.statusCode, body: "download failed")
        }
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.moveItem(at: tmpURL, to: destination)
        FileLog.shared.debug("← downloaded to \(destination.lastPathComponent)")
    }

    // MARK: - Detail

    public func unreadDetail(unid: String) async throws -> DocumentDetail {
        let urlStr = "http://yunoa.fjsjyt.cn:8080/egov60/docunit.nsf/DocToReceive?OpenForm&Server=CN%3DFJSJYT%2FOU%3DSRV%2FO%3DFJJY&DbName=docs/10003.nsf&unid=\(unid)&Form=DocToReceive&System="
        let data = try await getData(url: URL(string: urlStr)!)
        let doc = try XMLDocument(htmlData: data)
        let title = xpathFirst(doc, "//span[@id='idSubject']/text()") ?? ""
        let docMark = xpathFirst(doc, "//td[@id='tdDocMark']/text()") ?? ""
        let unit = xpathFirst(doc, "//td[text()='来文机关']/following-sibling::td[1]/text()") ?? ""
        let note = xpathFirst(doc, "//td[text()='发布说明']/following-sibling::td[1]/text()") ?? ""
        let pubAttr = xpathFirst(doc, "//td[text()='公开属性']/following-sibling::td[1]/text()") ?? ""
        let priority = xpathFirst(doc, "//td[text()='缓　　急']/following-sibling::td[1]/text()") ?? ""
        let database = doc.attr("//input[@name='MssDatabase']", "value") ?? ""
        let key = doc.attr("//input[@name='InitUnid']", "value") ?? ""
        return DocumentDetail(
            id: unid, title: title, docMark: docMark, publisher: unit,
            publishNote: note, publicAttribute: pubAttr, priority: priority,
            database: database, key: key)
    }

    public func readDetail(unid: String) async throws -> DocumentDetail {
        // Same parsing layout as unread; URL differs only in form name.
        return try await unreadDetail(unid: unid)
    }

    // MARK: - Attachments

    public func attachments(key: String, database: String) async throws -> [Attachment] {
        let body = "[{\"Server\":\"CN=FJSJYT/OU=SRV/O=FJJY\",\"DbPath\":\"\(database)\",\"View\":\"AllAttachmentView\",\"Keys\":[\"\(key)\"],\"Fields\":[\"ATTACHFILE\",\"ATTACHTITLE\",\"info\"],\"ValuesType\":1}]"
        var req = URLRequest(url: Self.attachURL)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = body.data(using: .utf8)
        let (data, _) = try await send(req)
        guard let arr = try JSONSerialization.jsonObject(with: data) as? [[Any]],
              let first = arr.first, first.count >= 1,
              let raw = first[0] as? [String: Any] else {
            throw SpiderError.parse(message: "attachments: unexpected json")
        }
        let titles = raw["ATTACHTITLE"] as? [String] ?? []
        let files = raw["ATTACHFILE"] as? [String] ?? []
        let unid = raw["Universalid"] as? String ?? ""
        var out: [Attachment] = []
        for i in 0..<min(titles.count, files.count) {
            let u = "http://yunoa.fjsjyt.cn:8080/\(database)/0/\(unid)/%24File/\(files[i])"
            if let url = URL(string: u) {
                out.append(Attachment(name: titles[i], fileName: files[i], url: url))
            }
        }
        return out
    }

    // MARK: - Sign-in

    public func signDocument(unid: String) async throws -> Bool {
        let info = try await fetchUserProfile()
        let urlStr = "\(Self.signinBase)&Server=CN=FJSJYT/OU=SRV/O=FJJY&DbName=docs/10003.nsf&Unid=\(unid)&UserName=\(info.userName)&UserTitle=\(info.userNameTitle)&Unit=\(info.unit)&UnitID=\(info.unitID)&remoteaddr=58.23.73.15&signType=0&reason="
        let data = try await getData(url: URL(string: urlStr)!)
        let doc = try XMLDocument(xmlData: data)
        let ok = doc.first("//center/text()")?.trimmingCharacters(in: .whitespacesAndNewlines) == "OK"
        return ok
    }

    // MARK: - Search

    public func search(_ word: String, pageSize: Int = 10, isRead: Bool = true, noteIDs: [String] = []) async throws -> (count: Int, documents: [DocumentSummary]) {
        var url = "\(Self.searchBase)&Server=CN=FJSJYT/OU=SRV/O=FJJY&DbName=docs/10003.nsf&View=\(isRead ? "ReceivedByTime" : "ToReceiveSort")"
        var body: String
        if noteIDs.isEmpty {
            let esc = word.unicodeScalars.reduce(into: "") { r, s in
                r += s.value > 127 ? "%u\(String(s.value, radix: 16, uppercase: false))" : String(s)
            }
            body = "#Condition=\(esc)"
            url += "&Count=\(pageSize)&Start=1&FTSearch=1&Sort=1&SortColumn=2"
        } else {
            var dbs = "&dbs="
            var ids = "&ids="
            for (i, nid) in noteIDs.enumerated() {
                dbs += "docs/10003.nsf,"
                ids += i == noteIDs.count - 1 ? nid : "\(nid),"
            }
            dbs += "docs\\10003.nsf"
            body = dbs + ids
        }
        var req = URLRequest(url: URL(string: url)!)
        req.httpMethod = "POST"
        req.httpBody = body.data(using: .utf8)
        let (data, _) = try await send(req)
        let doc = try XMLDocument(xmlData: data)
        let count = doc.count("//viewentry")
        var out: [DocumentSummary] = []
        if count > 0 {
            for i in 1...count {
                let subject = xpathFirst(doc, "//viewentry[\(i)]//entrydata[@name='$Subject']/text/text()")
                let pubTime = xpathFirst(doc, "//viewentry[\(i)]//entrydata[@name='$PublishTime']/text/text()")
                let unit = xpathFirst(doc, "//viewentry[\(i)]//entrydata[@name='$Unit']/text/text()")
                let unid = doc.attr("//viewentry[\(i)]", "unid") ?? ""
                let noteid = doc.attr("//viewentry[\(i)]", "noteid") ?? ""
                let docMark = xpathFirst(doc, "//viewentry[\(i)]//entrydata[@name='$DocMark']/text/text()")
                out.append(DocumentSummary(
                    id: unid, noteID: noteid, title: subject ?? "", publisher: unit ?? "",
                    publishedAt: pubTime ?? "", docMark: docMark ?? "", urgency: ""))
            }
        }
        return (count, out)
    }

    // MARK: - User profile

    public func fetchUserProfile() async throws -> UserProfile {
        let data = try await getData(url: Self.userInfoURL)
        let doc = try XMLDocument(htmlData: data)
        let userName = doc.attr("//input[@name='UserName']", "value") ?? ""
        let title = doc.attr("//input[@name='UserNameTitle']", "value") ?? ""
        let unit = doc.attr("//input[@name='Unit']", "value") ?? ""
        let unitID = doc.attr("//input[@name='UnitID']", "value") ?? ""
        return UserProfile(userName: userName, userNameTitle: title, unit: unit, unitID: unitID)
    }

    // MARK: - Helpers

    @inline(__always)
    private func xpathFirst(_ doc: XMLDocument, _ expr: String) -> String? {
        doc.first(expr)
    }

    private func postData(url: URL) async throws -> Data {
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        let (data, _) = try await send(req)
        return data
    }

    private func getData(url: URL) async throws -> Data {
        let (data, _) = try await send(URLRequest(url: url))
        return data
    }

    private func send(_ req: URLRequest) async throws -> (Data, URLResponse) {
        var r = req
        for (k, v) in Self.defaultHeaders where r.value(forHTTPHeaderField: k) == nil {
            r.setValue(v, forHTTPHeaderField: k)
        }
        // Inject cookies manually — we bypass HTTPCookieStorage entirely.
        if let cookieHeader = cookieJar.header() {
            r.setValue(cookieHeader, forHTTPHeaderField: "Cookie")
            FileLog.shared.debug("  Cookie header: \(cookieHeader.prefix(100))")
        }
        let cookieNames = cookieJar.allKeys.sorted()
        FileLog.shared.debug("→ \(r.httpMethod ?? "?") \(r.url?.path ?? "?") cookies=\(cookieNames)")
        do {
            let (data, resp) = try await session.data(for: r)
            let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
            FileLog.shared.debug("← \(status) \(data.count) bytes")
            // Extract Set-Cookie from the final response into our jar.
            if let http = resp as? HTTPURLResponse, let url = r.url {
                let headers = http.allHeaderFields as? [String: String] ?? [:]
                for cookie in HTTPCookie.cookies(withResponseHeaderFields: headers, for: url) {
                    cookieJar.set(cookie.name, cookie.value)
                    FileLog.shared.debug("  set-cookie: \(cookie.name)=\(cookie.value.prefix(20))")
                }
            }
            return (data, resp)
        } catch {
            FileLog.shared.error("network: \(error.localizedDescription)")
            throw SpiderError.network(error)
        }
    }
}

/// URLSession task delegate that extracts Set-Cookie from redirect (302)
/// responses before URLSession follows them. Without this, cookies set in
/// the 302 intermediate response are lost when URLSession delivers only the
/// final 200 response to the caller. Forwards cookies via a callback so the
/// spider can store them in its manual cookie jar.
private final class RedirectCookieInterceptor: NSObject, URLSessionTaskDelegate {
    let onCookie: @Sendable (String, String) -> Void
    init(onCookie: @escaping @Sendable (String, String) -> Void) {
        self.onCookie = onCookie
        super.init()
    }

    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        let headers = response.allHeaderFields as? [String: String] ?? [:]
        for c in HTTPCookie.cookies(withResponseHeaderFields: headers, for: response.url!) {
            FileLog.shared.debug("  redirect set-cookie: \(c.name)=\(c.value.prefix(20))")
            onCookie(c.name, c.value)
        }
        completionHandler(request)
    }
}


/// Thread-safe cookie container shared between the actor and the
/// URLSession delegate. Uses `OSAllocatedUnfairLock` so the non-isolated
/// delegate callback can mutate cookies without crossing actor boundaries.
private final class CookieBox: @unchecked Sendable {
    private let lock = OSAllocatedUnfairLock(initialState: [String: String]())
    func set(_ name: String, _ value: String) { lock.withLock { $0[name] = value } }
    func snapshot() -> [String: String] { lock.withLock { $0 } }
    func header() -> String? {
        lock.withLock { jar in
            jar.isEmpty ? nil : jar.map { "\($0.key)=\($0.value)" }.joined(separator: "; ")
        }
    }
    var allKeys: [String] { lock.withLock { Array($0.keys) } }
}
