import AppKit
import Foundation
import SwiftUI

@MainActor
final class QuotaStore: ObservableObject {
    @Published private(set) var pools: [QuotaPoolID: QuotaPool]
    @Published private(set) var refreshState: RefreshState = .idle
    @Published private(set) var lastSuccessfulUpdate: Date?
    @Published var selectedTrendPoolID: QuotaPoolID = .workCodex
    @Published var selectedSettingsTab: SettingsTab = .general
    @Published private(set) var historyRevision = 0
    @Published private(set) var accountConnection: ChatGPTConnectionState = .checking
    @Published private(set) var refreshNotice: String?

    private let codexClient: CodexUsageClient
    private let accountService: CodexAccountService
    private let notificationManager: NotificationManager
    private var historyStore: HistoryStore
    private var refreshTask: Task<Void, Never>?
    private var refreshNoticeTask: Task<Void, Never>?
    private var loginTask: Task<Void, Never>?
    private var loginSession: CodexLoginSession?
    private var wakeObserver: NSObjectProtocol?
    private var lastRefreshAttempt: Date?
    private var refreshInFlight = false
    private var started = false
    private let preview: Bool

    static let onDemandStaleAge: TimeInterval = 5 * 60

    init(
        codexClient: CodexUsageClient = CodexUsageClient(),
        accountService: CodexAccountService = CodexAccountService(),
        notificationManager: NotificationManager = NotificationManager(),
        historyStore: HistoryStore = HistoryStore(),
        preview: Bool = false
    ) {
        self.codexClient = codexClient
        self.accountService = accountService
        self.notificationManager = notificationManager
        self.historyStore = historyStore
        self.preview = preview
        self.pools = [.workCodex: .loading(.workCodex)]

        if preview {
            applyPreviewData()
        }
    }

    isolated deinit {
        refreshTask?.cancel()
        refreshNoticeTask?.cancel()
        loginTask?.cancel()
        if let wakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver)
        }
    }

    func startIfNeeded() async {
        guard !started else { return }
        started = true
        if preview { return }

        registerWakeObserverIfNeeded()
        await refresh()
        restartRefreshLoop()
    }

    func refreshIfStale(maxAge: TimeInterval = QuotaStore.onDemandStaleAge) async {
        guard started, !preview else { return }
        guard !accountConnection.isLoginInProgress else { return }
        guard !refreshInFlight else { return }

        let freshnessReference = lastSuccessfulUpdate ?? lastRefreshAttempt
        guard let freshnessReference else {
            await refresh()
            return
        }
        guard Date().timeIntervalSince(freshnessReference) >= maxAge else { return }
        await refresh()
    }

    func refreshScheduleDidChange() {
        guard started, !preview else { return }
        restartRefreshLoop()
    }

    func refresh() async {
        guard !preview else { return }
        guard !accountConnection.isLoginInProgress else { return }
        guard !refreshInFlight else { return }

        refreshInFlight = true
        defer { refreshInFlight = false }

        RuntimeDiagnostics.shared.record("refresh_start")
        refreshNoticeTask?.cancel()
        refreshNotice = nil
        lastRefreshAttempt = Date()
        refreshState = .refreshing

        do {
            let workCodex = try await codexClient.fetch()
            pools[.workCodex] = workCodex
            lastSuccessfulUpdate = workCodex.updatedAt
            refreshState = .idle
            RuntimeDiagnostics.shared.record("refresh_success")
            showRefreshNotice("刷新成功")

            let connectedEmail: String?
            if case .connected(let email, _) = accountConnection {
                connectedEmail = email
            } else {
                connectedEmail = nil
            }
            accountConnection = .connected(email: connectedEmail, plan: workCodex.planLabel)

            historyStore.record(pool: workCodex)
            historyRevision &+= 1
            await notificationManager.evaluate(pool: workCodex, warningThreshold: warningThreshold)
        } catch {
            RuntimeDiagnostics.shared.record("refresh_failure_\(diagnosticErrorCategory(error))")
            let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            let cachedPool = pools[.workCodex]
            let hasCachedQuota = !(cachedPool?.windows.isEmpty ?? true)
            let needsAuthorization: Bool

            if let codexError = error as? CodexUsageError {
                switch codexError {
                case .signInRequired:
                    needsAuthorization = true
                    accountConnection = .signedOut
                case .helperMissing:
                    needsAuthorization = false
                    accountConnection = .helperMissing
                default:
                    needsAuthorization = false
                    if !hasCachedQuota {
                        accountConnection = .failed(message)
                    }
                }
            } else {
                needsAuthorization = false
                if !hasCachedQuota {
                    accountConnection = .failed(message)
                }
            }

            if let stalePool = cachedPool?.preservingAsStale(errorMessage: message) {
                pools[.workCodex] = stalePool
            } else {
                pools[.workCodex] = .unavailable(
                    .workCodex,
                    message: message,
                    authorizationRequired: needsAuthorization,
                    updatedAt: cachedPool?.updatedAt
                )
            }
            refreshState = .failed(message)
        }
    }

    func beginChatGPTLogin() {
        guard !preview, loginTask == nil else { return }

        accountConnection = .starting
        pools[.workCodex] = QuotaPool.unavailable(
            .workCodex,
            message: "正在准备 ChatGPT 验证…",
            authorizationRequired: true
        )

        loginTask = Task { [weak self] in
            guard let self else { return }
            do {
                let session = try await accountService.beginBrowserLogin()
                guard !Task.isCancelled else {
                    await session.cancel()
                    return
                }

                loginSession = session
                accountConnection = .awaiting(session.challenge)
                pools[.workCodex] = QuotaPool.unavailable(
                    .workCodex,
                    message: "请在浏览器中确认 ChatGPT 账号与工作区",
                    authorizationRequired: true
                )
                NSWorkspace.shared.open(session.challenge.authorizationURL)

                let result = try await session.waitForCompletion()
                guard !Task.isCancelled else { return }

                loginSession = nil
                accountConnection = .connected(email: result.email, plan: result.planType)
                refreshState = .idle
                await refresh()
            } catch {
                guard !Task.isCancelled else { return }
                loginSession = nil
                let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                if let appError = error as? CodexAppServerError, case .notFound = appError {
                    accountConnection = .helperMissing
                } else {
                    accountConnection = .failed(message)
                }
                pools[.workCodex] = QuotaPool.unavailable(
                    .workCodex,
                    message: message,
                    authorizationRequired: true
                )
                refreshState = .failed(message)
            }
            loginTask = nil
        }
    }

    func cancelChatGPTLogin() {
        let session = loginSession
        loginTask?.cancel()
        loginTask = nil
        loginSession = nil
        accountConnection = .signedOut
        pools[.workCodex] = QuotaPool.unavailable(
            .workCodex,
            message: "连接 ChatGPT 后读取共享额度",
            authorizationRequired: true
        )
        refreshState = .idle
        Task { await session?.cancel() }
    }

    func openLoginPage() {
        guard case .awaiting(let challenge) = accountConnection else { return }
        NSWorkspace.shared.open(challenge.authorizationURL)
    }

    func requestNotificationAuthorization() async -> Bool {
        await notificationManager.requestAuthorization()
    }

    func sendTestNotification() async -> Bool {
        await notificationManager.sendTestNotification()
    }

    func openSystemNotificationSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension") else {
            return
        }
        NSWorkspace.shared.open(url)
    }

    func samples(for poolID: QuotaPoolID, days: Int = 7) -> [UsageSample] {
        _ = historyRevision
        return historyStore.samples(for: poolID, days: days)
    }

    func clearHistory() {
        historyStore.clear()
        historyRevision &+= 1
    }

    var orderedPools: [QuotaPool] {
        [pools[.workCodex]].compactMap { $0 }
    }

    var menuBarRemainingPercent: Double? {
        orderedPools.compactMap(\.remainingPercent).min()
    }

    var menuBarWeeklyPercent: Double? {
        pools[.workCodex]?.weeklyWindow?.remainingPercent
    }

    var menuBarSessionPercent: Double? {
        pools[.workCodex]?.sessionWindow?.remainingPercent
    }

    var menuBarSummaryText: String {
        "周 \(menuBarCompactPercent(menuBarWeeklyPercent))｜5h \(menuBarCompactPercent(menuBarSessionPercent))"
    }

    var menuBarDetailedHelp: String {
        let weekly = menuBarWeeklyPercent.map(QuotaFormatters.percent) ?? "暂不可读"
        let session = menuBarSessionPercent.map(QuotaFormatters.percent) ?? "暂不可读"
        return "本周剩余 \(weekly)｜近 5 小时剩余 \(session)"
    }

    private func menuBarCompactPercent(_ value: Double?) -> String {
        guard let value else { return "--%" }
        return "\(Int(value.rounded()))%"
    }

    var menuBarColor: Color {
        guard let remaining = menuBarRemainingPercent else { return .primary }
        if remaining <= 10 { return DesignTokens.red }
        if remaining <= warningThreshold { return DesignTokens.amber }
        return .primary
    }

    var updatedLabel: String {
        switch accountConnection {
        case .signedOut, .helperMissing: return "等待连接"
        case .starting, .awaiting(_): return "正在连接"
        default: break
        }

        switch refreshState {
        case .refreshing:
            return "正在更新"
        case .failed(_) where lastSuccessfulUpdate == nil:
            return "更新失败"
        case .failed(_):
            return "更新失败 · 显示\(QuotaFormatters.staleDataAge(lastSuccessfulUpdate))"
        case .idle where refreshNotice != nil:
            return refreshNotice ?? "刷新成功"
        default:
            return QuotaFormatters.lastUpdated(lastSuccessfulUpdate)
        }
    }

    var warningThreshold: Double {
        let stored = UserDefaults.standard.double(forKey: "warningThreshold")
        return stored == 0 ? 20 : stored
    }

    private var refreshIntervalSeconds: Double {
        let stored = UserDefaults.standard.double(forKey: "refreshIntervalMinutes")
        return max(60, (stored == 0 ? 5 : stored) * 60)
    }

    private func restartRefreshLoop() {
        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                let seconds = self.refreshIntervalSeconds
                do {
                    try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                } catch {
                    return
                }
                guard !Task.isCancelled else { return }
                await self.refresh()
            }
        }
    }

    private func registerWakeObserverIfNeeded() {
        guard wakeObserver == nil else { return }
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.refreshIfStale()
            }
        }
    }

    private func showRefreshNotice(_ message: String) {
        refreshNoticeTask?.cancel()
        refreshNotice = message
        refreshNoticeTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            guard !Task.isCancelled else { return }
            self?.refreshNotice = nil
        }
    }

    private func diagnosticErrorCategory(_ error: Error) -> String {
        if let usageError = error as? CodexUsageError {
            switch usageError {
            case .helperMissing: return "helper_missing"
            case .signInRequired: return "sign_in_required"
            case .unsupportedBilling: return "unsupported_billing"
            case .localServiceUnavailable: return "service_unavailable"
            case .invalidResponse: return "invalid_response"
            }
        }
        if error is CancellationError { return "cancelled" }
        return "other"
    }

    private func applyPreviewData() {
        let now = Date()
        let work = QuotaPool(
            id: .workCodex,
            availability: .available,
            windows: [
                QuotaWindow(
                    id: "primary",
                    kind: .session,
                    title: "近 5 小时",
                    remainingPercent: 10,
                    resetsAt: now.addingTimeInterval(1 * 3_600 + 56 * 60),
                    durationMinutes: 300
                ),
                QuotaWindow(
                    id: "secondary",
                    kind: .weekly,
                    title: "本周",
                    remainingPercent: 63,
                    resetsAt: now.addingTimeInterval(4 * 24 * 3_600),
                    durationMinutes: 10_080
                )
            ],
            updatedAt: now,
            planLabel: "Plus",
            message: nil,
            sourceLabel: "预览数据"
        )
        pools = [.workCodex: work]
        accountConnection = .connected(email: "name@example.com", plan: "Plus")
        lastSuccessfulUpdate = now

        let values: [(Int, Double)] = [(-6, 24), (-5, 31), (-4, 28), (-3, 45), (-2, 36), (-1, 52), (0, 90)]
        for (offset, used) in values {
            let date = Calendar.current.date(byAdding: .day, value: offset, to: now) ?? now
            let samplePool = QuotaPool(
                id: .workCodex,
                availability: .available,
                windows: [QuotaWindow(id: "preview-weekly", kind: .weekly, title: "本周", remainingPercent: 100 - used, resetsAt: nil, durationMinutes: 10_080)],
                updatedAt: date,
                planLabel: nil,
                message: nil,
                sourceLabel: nil
            )
            historyStore.record(pool: samplePool, at: date)
        }
        historyRevision &+= 1
    }
}
