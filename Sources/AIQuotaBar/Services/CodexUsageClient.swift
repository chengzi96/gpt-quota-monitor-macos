import Foundation

enum CodexUsageError: LocalizedError {
    case helperMissing
    case signInRequired
    case unsupportedBilling
    case localServiceUnavailable
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .helperMissing:
            return "缺少 OpenAI 官方额度组件，请重新运行安装器"
        case .signInRequired:
            return "连接 ChatGPT 后读取共享额度"
        case .unsupportedBilling:
            return "当前使用 API Key 计费，没有套餐额度"
        case .localServiceUnavailable:
            return "暂时无法连接 OpenAI 额度服务，请稍后重试"
        case .invalidResponse:
            return "额度数据格式暂时无法识别"
        }
    }
}

struct CodexUsageClient: @unchecked Sendable {
    private let fileManager: FileManager
    private let environment: [String: String]

    init(
        fileManager: FileManager = .default,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) {
        self.fileManager = fileManager
        self.environment = environment
    }

    func fetch() async throws -> QuotaPool {
        let appServer = CodexAppServerClient(fileManager: fileManager, environment: environment)
        do {
            let data = try await appServer.fetchUsageData()
            return try parseUsage(data, sourceLabel: "OpenAI 官方额度服务")
        } catch let error as CodexAppServerError {
            switch error {
            case .notFound:
                throw CodexUsageError.helperMissing
            case .notConfigured:
                throw CodexUsageError.signInRequired
            case .invalidResponse:
                throw CodexUsageError.invalidResponse
            case .transport:
                throw CodexUsageError.localServiceUnavailable
            case .rpc(let message):
                let normalized = message.lowercased()
                if normalized.contains("login") || normalized.contains("auth") || normalized.contains("account") {
                    throw CodexUsageError.signInRequired
                }
                throw CodexUsageError.localServiceUnavailable
            case .loginFailed(_):
                throw CodexUsageError.signInRequired
            }
        } catch {
            throw CodexUsageError.localServiceUnavailable
        }
    }

    private func parseUsage(_ data: Data, sourceLabel: String) throws -> QuotaPool {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw CodexUsageError.invalidResponse
        }
        let rateLimit = dictionary(root["rate_limit"] ?? root["rateLimit"])
        let primary = dictionary(rateLimit?["primary_window"] ?? rateLimit?["primaryWindow"])
        let secondary = dictionary(rateLimit?["secondary_window"] ?? rateLimit?["secondaryWindow"])

        var windows: [QuotaWindow] = []
        if let primary, let window = parseWindow(primary, fallbackID: "primary") { windows.append(window) }
        if let secondary, let window = parseWindow(secondary, fallbackID: "secondary") { windows.append(window) }

        if windows.isEmpty {
            let planType = string(root["plan_type"] ?? root["planType"])?.lowercased() ?? ""
            if planType.contains("usage_based") || planType.contains("usage based") {
                throw CodexUsageError.unsupportedBilling
            }
            throw CodexUsageError.invalidResponse
        }

        return QuotaPool(
            id: .workCodex,
            availability: .available,
            windows: windows,
            updatedAt: Date(),
            planLabel: displayPlan(string(root["plan_type"] ?? root["planType"])),
            message: nil,
            sourceLabel: sourceLabel
        )
    }

    func parseUsageData(_ data: Data) throws -> QuotaPool {
        try parseUsage(data, sourceLabel: "测试数据")
    }

    private func parseWindow(_ raw: [String: Any], fallbackID: String) -> QuotaWindow? {
        guard let used = double(raw["used_percent"] ?? raw["usedPercent"]) else { return nil }
        let durationSeconds = double(raw["limit_window_seconds"] ?? raw["limitWindowSeconds"])
        let durationMinutes = durationSeconds.map { Int(($0 / 60).rounded()) }
        let kind = windowKind(minutes: durationMinutes)
        return QuotaWindow(
            id: fallbackID,
            kind: kind,
            title: windowTitle(kind: kind, minutes: durationMinutes),
            remainingPercent: 100 - used,
            resetsAt: parseDate(raw["reset_at"] ?? raw["resets_at"] ?? raw["resetAt"] ?? raw["resetsAt"]),
            durationMinutes: durationMinutes
        )
    }

    private func windowKind(minutes: Int?) -> QuotaWindowKind {
        guard let minutes else { return .unknown }
        if minutes >= 28 * 24 * 60 { return .monthly }
        if minutes >= 7 * 24 * 60 { return .weekly }
        if minutes >= 24 * 60 { return .daily }
        return .session
    }

    private func windowTitle(kind: QuotaWindowKind, minutes: Int?) -> String {
        guard let minutes else { return kind.defaultTitle }
        if minutes == 300 { return "近 5 小时" }
        if kind == .weekly { return "本周" }
        if kind == .monthly { return "本月" }
        if kind == .daily { return "今日" }
        if minutes >= 60 { return "近 \(minutes / 60) 小时" }
        return "近 \(minutes) 分钟"
    }

    private func displayPlan(_ raw: String?) -> String? {
        guard let raw, !raw.isEmpty else { return nil }
        let normalized = raw.lowercased()
        if normalized.contains("plus") { return "Plus" }
        if normalized.contains("pro") { return "Pro" }
        if normalized.contains("business") { return "Business" }
        if normalized.contains("enterprise") { return "Enterprise" }
        if normalized.contains("edu") { return "Edu" }
        if normalized.contains("free") { return "Free" }
        return raw
    }

    private func parseDate(_ value: Any?) -> Date? {
        if let number = double(value) {
            let seconds = number > 10_000_000_000 ? number / 1_000 : number
            return Date(timeIntervalSince1970: seconds)
        }
        if let string = string(value) { return ISO8601DateFormatter().date(from: string) }
        return nil
    }

    private func dictionary(_ value: Any?) -> [String: Any]? { value as? [String: Any] }

    private func string(_ value: Any?) -> String? {
        switch value {
        case let value as String: return value.trimmingCharacters(in: .whitespacesAndNewlines)
        case let value as NSNumber: return value.stringValue
        default: return nil
        }
    }

    private func double(_ value: Any?) -> Double? {
        switch value {
        case let value as Double: return value
        case let value as Int: return Double(value)
        case let value as NSNumber: return value.doubleValue
        case let value as String: return Double(value)
        default: return nil
        }
    }
}
