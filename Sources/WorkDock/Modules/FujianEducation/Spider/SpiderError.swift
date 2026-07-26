import Foundation

/// Errors surfaced by ``FujianEducationSpider``.
public enum SpiderError: Error, CustomStringConvertible {
    case notLoggedIn
    case http(status: Int, body: String?)
    case parse(message: String)
    case network(Error)
    case invalidURL

    public var description: String {
        switch self {
        case .notLoggedIn: return "not logged in"
        case .http(let s, let b): return "http \(s): \(b ?? "")"
        case .parse(let m): return "parse: \(m)"
        case .network(let e): return "network: \(e.localizedDescription)"
        case .invalidURL: return "invalid url"
        }
    }
}
