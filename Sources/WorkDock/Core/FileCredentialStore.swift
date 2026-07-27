import Foundation
import os

/// File-backed credential storage — replaces KeychainStore for ad-hoc signed
/// builds where keychain access prompts on every call.
///
/// Stores JSON at `Application Support/WorkDock/credentials.json`. Values are
/// scoped by `service`/`account` like the keychain API. This is NOT secure
/// storage — it's a development-time credential cache that avoids the
/// repeated keychain unlock prompts an ad-hoc signed app triggers.
public enum FileCredentialStore {

    private static let lock = NSLock()
    private static let log = Logger(subsystem: "cn.dylanliu.workdock", category: "FileCreds")

    private static var storeURL: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = support.appendingPathComponent("WorkDock", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("credentials.json")
    }

    private struct Entry: Codable {
        let value: String
    }

    private static func loadAll() -> [String: [String: Entry]] {
        lock.lock(); defer { lock.unlock() }
        guard let data = try? Data(contentsOf: storeURL) else { return [:] }
        return (try? JSONDecoder().decode([String: [String: Entry]].self, from: data)) ?? [:]
    }

    private static func saveAll(_ dict: [String: [String: Entry]]) {
        lock.lock(); defer { lock.unlock() }
        do {
            let data = try JSONEncoder().encode(dict)
            try data.write(to: storeURL, options: .atomic)
        } catch {
            log.error("save failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    public static func set(service: String, account: String, value: String) {
        var all = loadAll()
        all[service, default: [:]][account] = Entry(value: value)
        saveAll(all)
    }

    public static func get(service: String, account: String) -> String? {
        loadAll()[service]?[account]?.value
    }

    public static func delete(service: String, account: String) {
        var all = loadAll()
        all[service]?[account] = nil
        if all[service]?.isEmpty ?? false { all[service] = nil }
        saveAll(all)
    }
}
