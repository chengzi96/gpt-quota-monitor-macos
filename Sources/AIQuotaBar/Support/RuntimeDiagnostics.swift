import Foundation

final class RuntimeDiagnostics: @unchecked Sendable {
    static let shared = RuntimeDiagnostics()

    private let lock = NSLock()
    private let fileManager = FileManager.default
    private let sessionID = UUID().uuidString.prefix(8)
    private let logURL: URL
    private let markerURL: URL

    private init() {
        let base = fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/GPT流量监控", isDirectory: true)
        logURL = base.appendingPathComponent("运行诊断.log", isDirectory: false)
        markerURL = base.appendingPathComponent("session-state.txt", isDirectory: false)
    }

    func markLaunch() {
        locked {
            ensureDirectory()
            if let previous = readMarker(), previous.hasPrefix("running\t") {
                let parts = previous.split(separator: "\t", omittingEmptySubsequences: false)
                let stage = parts.count >= 3 ? sanitize(String(parts[2])) : "unknown"
                appendLine("previous_session_unclean last_stage=\(stage)")
            }
            appendLine("launch")
            writeMarker(state: "running", event: "launch")
        }
    }

    func record(_ event: String) {
        locked {
            ensureDirectory()
            let safe = sanitize(event)
            appendLine(safe)
            writeMarker(state: "running", event: safe)
        }
    }

    func markNormalExit() {
        locked {
            ensureDirectory()
            appendLine("normal_exit")
            writeMarker(state: "clean", event: "normal_exit")
        }
    }

    private func locked(_ body: () -> Void) {
        lock.lock()
        defer { lock.unlock() }
        body()
    }

    private func ensureDirectory() {
        try? fileManager.createDirectory(
            at: logURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
    }

    private func timestamp() -> String {
        ISO8601DateFormatter().string(from: Date())
    }

    private func sanitize(_ raw: String) -> String {
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_=.:-")
        let scalars = raw.unicodeScalars.map { allowed.contains($0) ? Character(String($0)) : "_" }
        return String(scalars.prefix(96))
    }

    private func appendLine(_ event: String) {
        let line = "\(timestamp()) session=\(sessionID) event=\(event)\n"
        guard let data = line.data(using: .utf8) else { return }

        if !fileManager.fileExists(atPath: logURL.path) {
            _ = fileManager.createFile(atPath: logURL.path, contents: nil)
        }
        do {
            let handle = try FileHandle(forWritingTo: logURL)
            try handle.seekToEnd()
            try handle.write(contentsOf: data)
            try handle.close()
            trimLogIfNeeded()
        } catch {}
    }

    private func trimLogIfNeeded() {
        guard let attributes = try? fileManager.attributesOfItem(atPath: logURL.path),
              let size = attributes[.size] as? NSNumber,
              size.intValue > 160_000,
              let data = try? Data(contentsOf: logURL)
        else { return }

        let keep = 96_000
        let suffix = data.suffix(min(keep, data.count))
        try? Data(suffix).write(to: logURL, options: .atomic)
    }

    private func writeMarker(state: String, event: String) {
        let text = "\(state)\t\(timestamp())\t\(sanitize(event))\n"
        try? text.data(using: .utf8)?.write(to: markerURL, options: .atomic)
    }

    private func readMarker() -> String? {
        guard let data = try? Data(contentsOf: markerURL),
              let text = String(data: data, encoding: .utf8)
        else { return nil }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
