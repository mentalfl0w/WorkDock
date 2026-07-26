import Foundation
import os

/// File-backed rotating logger.
///
/// Writes to `~/Library/Application Support/WorkDock/logs/workdock.log`.
/// Rotates when the file exceeds `maxBytes` (default 1 MB), keeping up to
/// `maxFiles` archives (default 3). All writes are serialized on a serial
/// queue. Use ``shared`` for app-wide logging; subsystem-specific `os.Logger`
/// instances still go to the unified log, but ``FileLog`` is for things you
/// want to read back from disk when debugging.
public final class FileLog: @unchecked Sendable {
    public static let shared = FileLog()

    private let queue = DispatchQueue(label: "cn.liujiangnan.WorkDock.filelog")
    private let logDir: URL
    private let maxBytes: UInt64 = 1_000_000
    private let maxFiles = 3
    private let dateFormatter: DateFormatter

    private init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        logDir = support.appendingPathComponent("WorkDock/logs", isDirectory: true)
        try? FileManager.default.createDirectory(at: logDir, withIntermediateDirectories: true)
        print("[FileLog] init dir=\(logDir.path) exists=\(FileManager.default.fileExists(atPath: logDir.path))")
        dateFormatter = DateFormatter()
    }

    public func log(_ message: String, level: String = "INFO") {
        queue.async { [logDir, dateFormatter, maxBytes, maxFiles] in
            let line = "\(dateFormatter.string(from: Date())) [\(level)] \(message)\n"
            let url = logDir.appendingPathComponent("workdock.log")
            if FileManager.default.fileExists(atPath: url.path) {
                if let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
                   let size = attrs[.size] as? UInt64, size > maxBytes {
                    // rotate
                    for i in stride(from: maxFiles - 1, through: 1, by: -1) {
                        let src = logDir.appendingPathComponent("workdock.\(i).log")
                        let dst = logDir.appendingPathComponent("workdock.\(i+1).log")
                        try? FileManager.default.removeItem(at: dst)
                        try? FileManager.default.moveItem(at: src, to: dst)
                    }
                    let archive = logDir.appendingPathComponent("workdock.1.log")
                    try? FileManager.default.removeItem(at: archive)
                    try? FileManager.default.moveItem(at: url, to: archive)
                }
            }
            if !FileManager.default.fileExists(atPath: url.path) {
                FileManager.default.createFile(atPath: url.path, contents: nil)
            }
            if let handle = try? FileHandle(forWritingTo: url) {
                handle.seekToEndOfFile()
                if let data = line.data(using: .utf8) {
                    handle.write(data)
                }
                try? handle.close()
            }
        }
    }

    public func error(_ message: String) { log(message, level: "ERROR") }
    public func debug(_ message: String) { log(message, level: "DEBUG") }
}

/// Convenience for call sites that want both file log + os.Logger.
public func logBoth(_ message: String, category: String = "App") {
    FileLog.shared.log(message)
    Logger(subsystem: "cn.liujiangnan.WorkDock", category: category).info("\(message, privacy: .public)")
}
