import Foundation

enum CodexAppServerError: LocalizedError {
    case notFound
    case notConfigured
    case invalidResponse
    case transport
    case rpc(String)
    case loginFailed(String)

    var errorDescription: String? {
        switch self {
        case .notFound: return "缺少 OpenAI 官方额度组件"
        case .notConfigured: return "尚未连接 ChatGPT"
        case .invalidResponse: return "OpenAI 返回了无法识别的额度数据"
        case .transport: return "OpenAI 额度组件暂时不可用"
        case .rpc(let message): return message.isEmpty ? "OpenAI 额度组件请求失败" : message
        case .loginFailed(let message): return message
        }
    }
}

struct CodexAppServerClient: @unchecked Sendable {
    private let fileManager: FileManager
    private let environment: [String: String]
    private let timeout: TimeInterval

    init(
        fileManager: FileManager = .default,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        timeout: TimeInterval = 12
    ) {
        self.fileManager = fileManager
        self.environment = environment
        self.timeout = timeout
    }

    func fetchUsageData() async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                do { continuation.resume(returning: try self.fetchUsageDataBlocking()) }
                catch { continuation.resume(throwing: error) }
            }
        }
    }

    private func fetchUsageDataBlocking() throws -> Data {
        let locator = CodexExecutableLocator(fileManager: fileManager, environment: environment)
        let candidates = locator.executableCandidates()
        guard !candidates.isEmpty else { throw CodexAppServerError.notFound }

        var lastError: Error = CodexAppServerError.transport
        for executable in candidates {
            var connection: CodexAppServerConnection?
            do {
                connection = try CodexAppServerConnection(
                    executable: executable,
                    environment: locator.environmentWithPathHints(),
                    timeout: timeout
                )

                let rateResult: [String: Any]
                do {
                    rateResult = try connection!.request(method: "account/rateLimits/read")
                } catch CodexAppServerError.rpc(let message) where isAuthenticationError(message) {
                    throw CodexAppServerError.notConfigured
                }

                let accountResult = try? connection!.request(
                    method: "account/read",
                    params: ["refreshToken": false]
                )
                let data = try normalize(rateResult: rateResult, accountResult: accountResult)
                connection?.stop()
                return data
            } catch {
                connection?.stop()
                lastError = error
                if let appError = error as? CodexAppServerError, case .notConfigured = appError {
                    throw appError
                }
            }
        }
        throw lastError
    }

    private func normalize(rateResult: [String: Any], accountResult: [String: Any]?) throws -> Data {
        let byID = dictionary(rateResult["rateLimitsByLimitId"] ?? rateResult["rate_limits_by_limit_id"])
        let rateLimits = dictionary(byID?["codex"])
            ?? dictionary(rateResult["rateLimits"] ?? rateResult["rate_limits"])
            ?? dictionary(rateResult["rateLimit"] ?? rateResult["rate_limit"])

        guard let rateLimits else {
            if dictionary(accountResult?["account"]) == nil { throw CodexAppServerError.notConfigured }
            throw CodexAppServerError.invalidResponse
        }

        let primary = normalizedWindow(
            dictionary(rateLimits["primary"] ?? rateLimits["primaryWindow"] ?? rateLimits["primary_window"])
        )
        let secondary = normalizedWindow(
            dictionary(rateLimits["secondary"] ?? rateLimits["secondaryWindow"] ?? rateLimits["secondary_window"])
        )
        guard primary != nil || secondary != nil else { throw CodexAppServerError.invalidResponse }

        let account = dictionary(accountResult?["account"])
        let plan = string(account?["planType"] ?? account?["plan_type"])
            ?? string(rateLimits["planType"] ?? rateLimits["plan_type"])

        var rateLimitPayload: [String: Any] = [:]
        if let primary { rateLimitPayload["primary_window"] = primary }
        if let secondary { rateLimitPayload["secondary_window"] = secondary }
        var payload: [String: Any] = ["rate_limit": rateLimitPayload]
        if let plan { payload["plan_type"] = plan }
        return try JSONSerialization.data(withJSONObject: payload)
    }

    private func normalizedWindow(_ raw: [String: Any]?) -> [String: Any]? {
        guard let raw, let used = number(raw["usedPercent"] ?? raw["used_percent"]) else { return nil }
        var window: [String: Any] = ["used_percent": used]
        if let reset = raw["resetsAt"] ?? raw["resets_at"] ?? raw["resetAt"] ?? raw["reset_at"] {
            window["reset_at"] = reset
        }
        if let minutes = number(raw["windowDurationMins"] ?? raw["window_duration_mins"]) {
            window["limit_window_seconds"] = minutes * 60
        } else if let seconds = number(raw["limitWindowSeconds"] ?? raw["limit_window_seconds"]) {
            window["limit_window_seconds"] = seconds
        }
        return window
    }

    private func isAuthenticationError(_ message: String) -> Bool {
        let normalized = message.lowercased()
        return normalized.contains("login")
            || normalized.contains("logged in")
            || normalized.contains("account")
            || normalized.contains("auth")
            || normalized.contains("credential")
            || normalized.contains("unauthorized")
    }

    private func dictionary(_ value: Any?) -> [String: Any]? { value as? [String: Any] }
    private func string(_ value: Any?) -> String? {
        guard let value = value as? String else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
    private func number(_ value: Any?) -> Double? {
        switch value {
        case let value as NSNumber: return value.doubleValue
        case let value as String: return Double(value)
        default: return nil
        }
    }
}

struct CodexExecutableLocator {
    let fileManager: FileManager
    let environment: [String: String]

    func executableCandidates() -> [URL] {
        var paths: [String] = []

        if environment["AIQUOTABAR_ALLOW_CODEX_OVERRIDE"] == "1",
           let override = environment["CODEX_APP_SERVER_PATH"],
           !override.isEmpty {
            paths.append(override)
        }
        if let resourcePath = Bundle.main.resourceURL?.appendingPathComponent("codex-app-server").path {
            paths.append(resourcePath)
        }

        var seen = Set<String>()
        return paths.compactMap { path in
            guard seen.insert(path).inserted, fileManager.isExecutableFile(atPath: path) else { return nil }
            return URL(fileURLWithPath: path, isDirectory: false)
        }
    }

    func environmentWithPathHints() -> [String: String] {
        var result = environment
        let current = result["PATH"] ?? ""
        let home = fileManager.homeDirectoryForCurrentUser.path
        let hints = [home + "/.local/bin", "/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin"]
        result["PATH"] = (hints + current.split(separator: ":").map(String.init))
            .reduce(into: [String]()) { values, value in
                if !value.isEmpty && !values.contains(value) { values.append(value) }
            }
            .joined(separator: ":")
        applySystemProxy(to: &result)
        return result
    }

    private func applySystemProxy(to environment: inout [String: String]) {
        if environment["HTTPS_PROXY"] != nil
            || environment["https_proxy"] != nil
            || environment["ALL_PROXY"] != nil { return }

        let settings = systemProxySettings()
        if settings["HTTPSEnable"] == "1",
           let host = settings["HTTPSProxy"], let port = settings["HTTPSPort"] {
            let proxy = "http://\(host):\(port)"
            environment["HTTPS_PROXY"] = proxy
            environment["HTTP_PROXY"] = proxy
            environment["https_proxy"] = proxy
            environment["http_proxy"] = proxy
            environment["NO_PROXY"] = "localhost,127.0.0.1,::1"
            environment["no_proxy"] = environment["NO_PROXY"]
            return
        }
        if settings["SOCKSEnable"] == "1",
           let host = settings["SOCKSProxy"], let port = settings["SOCKSPort"] {
            let proxy = "socks5h://\(host):\(port)"
            environment["ALL_PROXY"] = proxy
            environment["all_proxy"] = proxy
            environment["NO_PROXY"] = "localhost,127.0.0.1,::1"
            environment["no_proxy"] = environment["NO_PROXY"]
        }
    }

    private func systemProxySettings() -> [String: String] {
        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/scutil")
        process.arguments = ["--proxy"]
        process.standardOutput = output
        process.standardError = Pipe()
        guard (try? process.run()) != nil else { return [:] }
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return [:] }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        guard let text = String(data: data, encoding: .utf8) else { return [:] }
        var values: [String: String] = [:]
        for line in text.split(whereSeparator: { $0.isNewline }) {
            let parts = line.split(separator: ":", maxSplits: 1)
            guard parts.count == 2 else { continue }
            let key = parts[0].trimmingCharacters(in: .whitespaces)
            let value = parts[1].trimmingCharacters(in: .whitespaces)
            if !key.isEmpty, !value.isEmpty { values[key] = value }
        }
        return values
    }
}

final class CodexAppServerConnection: @unchecked Sendable {
    private let process: Process
    private let inputPipe: Pipe
    private let outputPipe: Pipe
    private let errorPipe: Pipe
    private let channel: JSONLineChannel
    private let stopLock = NSLock()
    private var stopped = false

    init(executable: URL, environment: [String: String], timeout: TimeInterval) throws {
        process = Process()
        inputPipe = Pipe()
        outputPipe = Pipe()
        errorPipe = Pipe()
        channel = JSONLineChannel(
            input: inputPipe.fileHandleForWriting,
            output: outputPipe.fileHandleForReading,
            timeout: timeout
        )

        process.executableURL = executable
        process.arguments = []
        process.environment = environment
        process.standardInput = inputPipe
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        errorPipe.fileHandleForReading.readabilityHandler = { handle in _ = handle.availableData }

        do {
            RuntimeDiagnostics.shared.record("appserver_start_attempt")
            try process.run()
            RuntimeDiagnostics.shared.record("appserver_started")
            _ = try channel.request(
                method: "initialize",
                params: [
                    "clientInfo": [
                        "name": "ai-quota-bar",
                        "title": "GPT流量监控",
                        "version": "0.3.28"
                    ]
                ]
            )
            try channel.notify(method: "initialized", params: [:])
        } catch let error as CodexAppServerError {
            stop(); throw error
        } catch {
            stop(); throw CodexAppServerError.transport
        }
    }

    deinit { stop() }

    func request(method: String, params: [String: Any]? = nil) throws -> [String: Any] {
        try channel.request(method: method, params: params)
    }

    func waitForNotification(method: String, timeout: TimeInterval) throws -> [String: Any] {
        try channel.waitForNotification(method: method, timeout: timeout)
    }

    func stop() {
        stopLock.lock()
        let shouldStop = !stopped
        stopped = true
        stopLock.unlock()
        guard shouldStop else { return }

        RuntimeDiagnostics.shared.record("appserver_stop")
        channel.close()
        errorPipe.fileHandleForReading.readabilityHandler = nil
        try? inputPipe.fileHandleForWriting.close()
        if process.isRunning { process.terminate() }
    }
}

final class JSONLineChannel: @unchecked Sendable {
    private let input: FileHandle
    private let output: FileHandle
    private let timeout: TimeInterval
    private let lock = NSLock()
    private var buffer = Data()
    private var nextID = 1
    private var responses: [Int: [String: Any]] = [:]
    private var responseWaiters: [Int: DispatchSemaphore] = [:]
    private var notifications: [String: [[String: Any]]] = [:]
    private var notificationWaiters: [String: DispatchSemaphore] = [:]
    private var closed = false

    init(input: FileHandle, output: FileHandle, timeout: TimeInterval) {
        self.input = input
        self.output = output
        self.timeout = timeout
        output.readabilityHandler = { [weak self] handle in self?.receive(handle.availableData) }
    }

    func request(method: String, params: [String: Any]? = nil) throws -> [String: Any] {
        let semaphore = DispatchSemaphore(value: 0)
        let id: Int
        lock.lock()
        guard !closed else { lock.unlock(); throw CodexAppServerError.transport }
        id = nextID
        nextID += 1
        responseWaiters[id] = semaphore
        lock.unlock()

        var message: [String: Any] = ["method": method, "id": id]
        if let params { message["params"] = params }
        do { try write(message) }
        catch { removeResponseWaiter(id); throw CodexAppServerError.transport }

        guard semaphore.wait(timeout: .now() + timeout) == .success else {
            removeResponseWaiter(id)
            throw CodexAppServerError.transport
        }

        lock.lock()
        let response = responses.removeValue(forKey: id)
        responseWaiters.removeValue(forKey: id)
        lock.unlock()

        guard let response else { throw CodexAppServerError.transport }
        if let rpcError = response["error"] as? [String: Any] {
            let rpcMessage = String(describing: rpcError["message"] ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            throw CodexAppServerError.rpc(rpcMessage)
        }
        guard let result = response["result"] as? [String: Any] else {
            throw CodexAppServerError.invalidResponse
        }
        return result
    }

    func notify(method: String, params: [String: Any]? = nil) throws {
        var message: [String: Any] = ["method": method]
        if let params { message["params"] = params }
        try write(message)
    }

    func waitForNotification(method: String, timeout customTimeout: TimeInterval) throws -> [String: Any] {
        let semaphore: DispatchSemaphore
        lock.lock()
        if var queued = notifications[method], !queued.isEmpty {
            let first = queued.removeFirst()
            notifications[method] = queued
            lock.unlock()
            return first
        }
        guard !closed else { lock.unlock(); throw CodexAppServerError.transport }
        if let existing = notificationWaiters[method] { semaphore = existing }
        else {
            semaphore = DispatchSemaphore(value: 0)
            notificationWaiters[method] = semaphore
        }
        lock.unlock()

        guard semaphore.wait(timeout: .now() + customTimeout) == .success else {
            lock.lock(); notificationWaiters.removeValue(forKey: method); lock.unlock()
            throw CodexAppServerError.transport
        }

        lock.lock()
        let params: [String: Any]?
        if var queued = notifications[method], !queued.isEmpty {
            params = queued.removeFirst()
            notifications[method] = queued
        } else { params = nil }
        notificationWaiters.removeValue(forKey: method)
        lock.unlock()

        guard let params else { throw CodexAppServerError.transport }
        return params
    }

    func close() {
        lock.lock()
        guard !closed else { lock.unlock(); return }
        closed = true
        let waitingResponses = Array(responseWaiters.values)
        let waitingNotifications = Array(notificationWaiters.values)
        responseWaiters.removeAll()
        notificationWaiters.removeAll()
        lock.unlock()

        output.readabilityHandler = nil
        for semaphore in waitingResponses { semaphore.signal() }
        for semaphore in waitingNotifications { semaphore.signal() }
    }

    private func write(_ message: [String: Any]) throws {
        var data = try JSONSerialization.data(withJSONObject: message)
        data.append(0x0A)
        try input.write(contentsOf: data)
    }

    private func receive(_ data: Data) {
        guard !data.isEmpty else { return }
        var completedResponses: [DispatchSemaphore] = []
        var completedNotifications: [DispatchSemaphore] = []

        lock.lock()
        buffer.append(data)
        while let newline = buffer.firstIndex(of: 0x0A) {
            let line = buffer.prefix(upTo: newline)
            buffer.removeSubrange(...newline)
            guard !line.isEmpty,
                  let message = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any]
            else { continue }

            if let id = (message["id"] as? NSNumber)?.intValue {
                responses[id] = message
                if let semaphore = responseWaiters[id] { completedResponses.append(semaphore) }
            } else if let method = message["method"] as? String {
                let params = message["params"] as? [String: Any] ?? [:]
                notifications[method, default: []].append(params)
                if let semaphore = notificationWaiters[method] { completedNotifications.append(semaphore) }
            }
        }
        lock.unlock()

        for semaphore in completedResponses { semaphore.signal() }
        for semaphore in completedNotifications { semaphore.signal() }
    }

    private func removeResponseWaiter(_ id: Int) {
        lock.lock()
        responseWaiters.removeValue(forKey: id)
        responses.removeValue(forKey: id)
        lock.unlock()
    }
}
