import Foundation
import os

/// JSON persistence in Application Support, scoped per module.
///
/// Each module gets its own file under `WorkDock/<moduleID>.json`. Reads are
/// cached in memory; writes flush to disk atomically. This is for non-secret
/// state (last-seen document ids, pagination cursors, preferences). Credentials
/// live in ``KeychainStore``.
public final class Persistence: @unchecked Sendable {
    private let log = Logger(subsystem: "cn.liujiangnan.WorkDock", category: "Persistence")
    private let baseDir: URL
    private var cache: [String: Data] = [:]
    private let queue = DispatchQueue(label: "cn.liujiangnan.WorkDock.persistence", attributes: .concurrent)

    public init(appName: String = "WorkDock") {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        baseDir = support.appendingPathComponent(appName, isDirectory: true)
        try? FileManager.default.createDirectory(at: baseDir, withIntermediateDirectories: true)
    }

    /// Load a `Codable` value for a module, falling back to `default`.
    public func load<T: Decodable>(_ type: T.Type, moduleID: String, key: String, default: T) -> T {
        let cacheKey = "\(moduleID).\(key)"
        let url = path(moduleID: moduleID, key: key)
        return queue.sync {
            if let cached = cache[cacheKey] {
                return (try? JSONDecoder().decode(T.self, from: cached)) ?? `default`
            }
            guard let data = try? Data(contentsOf: url) else { return `default` }
            cache[cacheKey] = data
            return (try? JSONDecoder().decode(T.self, from: data)) ?? `default`
        }
    }

    /// Persist a `Codable` value for a module.
    public func store<T: Encodable & Sendable>(_ value: T, moduleID: String, key: String) {
        let cacheKey = "\(moduleID).\(key)"
        let url = path(moduleID: moduleID, key: key)
        queue.async(flags: .barrier) {
            do {
                let data = try JSONEncoder().encode(value)
                self.cache[cacheKey] = data
                try data.write(to: url, options: .atomic)
            } catch {
                self.log.error("store failed module=\(moduleID, privacy: .public) key=\(key, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    public func remove(moduleID: String, key: String) {
        let cacheKey = "\(moduleID).\(key)"
        let url = path(moduleID: moduleID, key: key)
        queue.async(flags: .barrier) {
            self.cache[cacheKey] = nil
            try? FileManager.default.removeItem(at: url)
        }
    }

    private func path(moduleID: String, key: String) -> URL {
        baseDir.appendingPathComponent("\(moduleID).\(key).json")
    }
}
