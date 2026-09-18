import Foundation

struct CodexLoginChallenge: Equatable, Sendable {
    let loginID: String
    let authorizationURL: URL
}

struct CodexLoginResult: Equatable, Sendable {
    let email: String?
    let planType: String?
}

/// Starts the official ChatGPT browser OAuth flow through Codex app-server.
/// Codex owns the local callback, credential storage, and token refresh.
struct CodexAccountService: @unchecked Sendable {
    private let fileManager: FileManager
    private let environment: [String: String]

    init(
        fileManager: FileManager = .default,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) {
        self.fileManager = fileManager
        self.environment = environment
    }

    func beginBrowserLogin() async throws -> CodexLoginSession {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    continuation.resume(returning: try self.beginBrowserLoginBlocking())
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private func beginBrowserLoginBlocking() throws -> CodexLoginSession {
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
                    timeout: 15
                )
                let result = try connection!.request(
                    method: "account/login/start",
                    params: [
                        "type": "chatgpt",
                        "useHostedLoginSuccessPage": true,
                        "appBrand": "chatgpt"
                    ]
                )

                guard
                    let loginID = nonEmptyString(result["loginId"] ?? result["login_id"]),
                    let rawURL = nonEmptyString(result["authUrl"] ?? result["auth_url"]),
                    let authorizationURL = URL(string: rawURL)
                else {
                    throw CodexAppServerError.invalidResponse
                }

                return CodexLoginSession(
                    connection: connection!,
                    challenge: CodexLoginChallenge(loginID: loginID, authorizationURL: authorizationURL)
                )
            } catch CodexAppServerError.rpc(let message) {
                connection?.stop()
                lastError = CodexAppServerError.loginFailed(localizedLoginError(message))
            } catch {
                connection?.stop()
                lastError = error
            }
        }
        throw lastError
    }

    private func localizedLoginError(_ message: String) -> String {
        let normalized = message.lowercased()
        if normalized.contains("network") || normalized.contains("connect") {
            return "暂时无法连接 OpenAI，请检查网络后重试。"
        }
        if normalized.contains("rate") || normalized.contains("too many") {
            return "登录请求过于频繁，请稍后再试。"
        }
        return "无法开始 ChatGPT 登录，请稍后重试。"
    }

    private func nonEmptyString(_ value: Any?) -> String? {
        guard let value = value as? String else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

final class CodexLoginSession: @unchecked Sendable {
    let challenge: CodexLoginChallenge

    private let connection: CodexAppServerConnection
    private let finishLock = NSLock()
    private var finished = false

    init(connection: CodexAppServerConnection, challenge: CodexLoginChallenge) {
        self.connection = connection
        self.challenge = challenge
    }

    deinit { connection.stop() }

    func waitForCompletion() async throws -> CodexLoginResult {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                do {
                    continuation.resume(returning: try self.waitForCompletionBlocking())
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    func cancel() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            DispatchQueue.global(qos: .utility).async {
                if self.markFinished() {
                    _ = try? self.connection.request(
                        method: "account/login/cancel",
                        params: ["loginId": self.challenge.loginID]
                    )
                    self.connection.stop()
                }
                continuation.resume()
            }
        }
    }

    private func waitForCompletionBlocking() throws -> CodexLoginResult {
        let deadline = Date().addingTimeInterval(10 * 60)
        defer { connection.stop() }

        while Date() < deadline {
            let remaining = max(1, deadline.timeIntervalSinceNow)
            let params: [String: Any]
            do {
                params = try connection.waitForNotification(
                    method: "account/login/completed",
                    timeout: remaining
                )
            } catch {
                if isFinished() { throw CancellationError() }
                throw CodexAppServerError.loginFailed("浏览器登录等待超时，请重新连接 ChatGPT。")
            }

            guard string(params["loginId"] ?? params["login_id"]) == challenge.loginID else { continue }
            guard !isFinished() else { throw CancellationError() }

            let success = bool(params["success"]) ?? false
            guard success else {
                let detail = string(params["error"])
                throw CodexAppServerError.loginFailed(localizedCompletionError(detail))
            }

            _ = markFinished()
            let accountResult = try? connection.request(
                method: "account/read",
                params: ["refreshToken": false]
            )
            let account = accountResult?["account"] as? [String: Any]
            return CodexLoginResult(
                email: string(account?["email"]),
                planType: string(account?["planType"] ?? account?["plan_type"])
            )
        }

        throw CodexAppServerError.loginFailed("浏览器登录等待超时，请重新连接 ChatGPT。")
    }

    private func markFinished() -> Bool {
        finishLock.lock(); defer { finishLock.unlock() }
        guard !finished else { return false }
        finished = true
        return true
    }

    private func isFinished() -> Bool {
        finishLock.lock(); defer { finishLock.unlock() }
        return finished
    }

    private func string(_ value: Any?) -> String? {
        guard let value = value as? String else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func bool(_ value: Any?) -> Bool? {
        switch value {
        case let value as Bool: return value
        case let value as NSNumber: return value.boolValue
        case let value as String: return ["true", "1", "yes"].contains(value.lowercased())
        default: return nil
        }
    }

    private func localizedCompletionError(_ detail: String?) -> String {
        let normalized = detail?.lowercased() ?? ""
        if normalized.contains("cancel") || normalized.contains("denied") {
            return "ChatGPT 授权已取消，请重新连接。"
        }
        if normalized.contains("callback") || normalized.contains("localhost") {
            return "浏览器授权未能返回 GPT流量监控，请检查网络代理后重试。"
        }
        return "ChatGPT 登录没有完成，请重试。"
    }
}
