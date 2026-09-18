import Foundation
import SwiftUI

enum SettingsTab: String, CaseIterable, Identifiable, Hashable, Sendable {
    case general
    case menuBar
    case alerts
    case data
    case about

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: return "常规"
        case .menuBar: return "菜单栏"
        case .alerts: return "提醒"
        case .data: return "数据"
        case .about: return "关于"
        }
    }
}

enum QuotaPoolID: String, Codable, CaseIterable, Identifiable {
    case chatGPT
    case workCodex

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .chatGPT: return "GPT Chat"
        case .workCodex: return "Work + Codex"
        }
    }

    var isShared: Bool { self == .workCodex }

    var accent: Color {
        switch self {
        case .chatGPT: return DesignTokens.pearl
        case .workCodex: return DesignTokens.cyan
        }
    }

    var symbolName: String {
        switch self {
        case .chatGPT: return "bubble.left.and.bubble.right"
        case .workCodex: return "chevron.left.forwardslash.chevron.right"
        }
    }
}

enum QuotaWindowKind: String, Codable, CaseIterable {
    case session
    case daily
    case weekly
    case monthly
    case unknown

    var defaultTitle: String {
        switch self {
        case .session: return "短期额度"
        case .daily: return "今日"
        case .weekly: return "本周"
        case .monthly: return "本月"
        case .unknown: return "当前周期"
        }
    }
}

struct QuotaWindow: Identifiable, Codable, Equatable {
    let id: String
    let kind: QuotaWindowKind
    let title: String
    let remainingPercent: Double
    let resetsAt: Date?
    let durationMinutes: Int?

    init(
        id: String,
        kind: QuotaWindowKind,
        title: String? = nil,
        remainingPercent: Double,
        resetsAt: Date?,
        durationMinutes: Int? = nil
    ) {
        self.id = id
        self.kind = kind
        self.title = title ?? kind.defaultTitle
        self.remainingPercent = min(100, max(0, remainingPercent))
        self.resetsAt = resetsAt
        self.durationMinutes = durationMinutes
    }

    var usedPercent: Double { 100 - remainingPercent }
}

enum QuotaAvailability: String, Codable, Equatable {
    case loading
    case available
    case unavailable
    case authorizationRequired
    case stale
}

struct QuotaPool: Identifiable, Codable, Equatable {
    let id: QuotaPoolID
    var availability: QuotaAvailability
    var windows: [QuotaWindow]
    var updatedAt: Date?
    var planLabel: String?
    var message: String?
    var sourceLabel: String?

    var mostConstrainedWindow: QuotaWindow? {
        windows.min { $0.remainingPercent < $1.remainingPercent }
    }

    var remainingPercent: Double? { mostConstrainedWindow?.remainingPercent }

    /// Stable semantic windows used by the v0.1.9 popup. These helpers select
    /// only real values returned by OpenAI; they never estimate missing quota.
    var weeklyWindow: QuotaWindow? {
        windows.first(where: { $0.kind == .weekly })
    }

    var sessionWindow: QuotaWindow? {
        windows.first(where: { $0.kind == .session && $0.durationMinutes == 300 })
            ?? windows.first(where: { $0.kind == .session })
    }

    static func loading(_ id: QuotaPoolID) -> QuotaPool {
        QuotaPool(
            id: id,
            availability: .loading,
            windows: [],
            updatedAt: nil,
            planLabel: nil,
            message: "正在读取额度…",
            sourceLabel: nil
        )
    }

    static func unavailable(
        _ id: QuotaPoolID,
        message: String,
        authorizationRequired: Bool = false,
        updatedAt: Date? = nil
    ) -> QuotaPool {
        QuotaPool(
            id: id,
            availability: authorizationRequired ? .authorizationRequired : .unavailable,
            windows: [],
            updatedAt: updatedAt,
            planLabel: nil,
            message: message,
            sourceLabel: nil
        )
    }

    func preservingAsStale(errorMessage: String) -> QuotaPool? {
        guard !windows.isEmpty else { return nil }
        var copy = self
        copy.availability = .stale
        copy.message = "更新失败，正在显示上次数据：\(errorMessage)"
        return copy
    }
}

enum ConsumptionState {
    case normal
    case fast
    case warning
    case stale
    case unavailable

    var label: String {
        switch self {
        case .normal: return "消耗正常"
        case .fast: return "消耗偏快"
        case .warning: return "即将用完"
        case .stale: return "上次数据"
        case .unavailable: return "暂时无法读取"
        }
    }

    var color: Color {
        switch self {
        case .normal: return DesignTokens.secondaryText
        case .fast: return DesignTokens.amber
        case .warning: return DesignTokens.red
        case .stale: return DesignTokens.amber
        case .unavailable: return DesignTokens.secondaryText
        }
    }
}

extension QuotaPool {
    func consumptionState(warningThreshold: Double) -> ConsumptionState {
        if availability == .stale { return .stale }
        guard availability == .available, let remainingPercent else { return .unavailable }
        if remainingPercent <= 10 { return .warning }
        if remainingPercent <= warningThreshold { return .fast }
        return .normal
    }
}

struct UsageSample: Identifiable, Codable, Equatable {
    let id: UUID
    let poolID: QuotaPoolID
    let date: Date
    let usedPercent: Double
    let windowKind: QuotaWindowKind?

    init(
        id: UUID = UUID(),
        poolID: QuotaPoolID,
        date: Date,
        usedPercent: Double,
        windowKind: QuotaWindowKind? = nil
    ) {
        self.id = id
        self.poolID = poolID
        self.date = date
        self.usedPercent = min(100, max(0, usedPercent))
        self.windowKind = windowKind
    }
}

enum RefreshState: Equatable {
    case idle
    case refreshing
    case failed(String)
}

enum ChatGPTConnectionState: Equatable {
    case checking
    case helperMissing
    case signedOut
    case starting
    case awaiting(CodexLoginChallenge)
    case connected(email: String?, plan: String?)
    case failed(String)

    var isLoginInProgress: Bool {
        switch self {
        case .starting, .awaiting(_): return true
        default: return false
        }
    }
}
