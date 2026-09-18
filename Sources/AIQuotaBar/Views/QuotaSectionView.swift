import SwiftUI

struct QuotaSectionView: View {
    let pool: QuotaPool
    let warningThreshold: Double
    let accountConnection: ChatGPTConnectionState
    let onRefresh: () -> Void
    let onConnect: () -> Void
    let onOpenLoginPage: () -> Void
    let onCancelLogin: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            titleRow

            switch pool.availability {
            case .loading:
                loadingState
            case .available, .stale:
                availableState
            case .unavailable, .authorizationRequired:
                unavailableState
            }
        }
        .accessibilityLabel(accessibilityLabel)
    }

    private var titleRow: some View {
        HStack(alignment: .center, spacing: 8) {
            Image(systemName: pool.id.symbolName)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(pool.id.accent)
                .frame(width: 22)

            Text(pool.id.displayName)
                .font(DesignTokens.productFont)
                .foregroundStyle(DesignTokens.primaryText)

            if pool.id.isShared {
                Text("共享额度")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(DesignTokens.cyan.opacity(0.95))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .adaptiveCompactGlass(
                        tint: DesignTokens.cyan.opacity(0.10),
                        in: Capsule(style: .continuous)
                    )
            }

            Spacer(minLength: 10)

            if let plan = pool.planLabel {
                Text(plan)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(DesignTokens.tertiaryText)
            }
        }
    }

    private var availableState: some View {
        VStack(alignment: .leading, spacing: 14) {
            let windows = displayWindows

            if windows.isEmpty {
                Text("暂时没有可显示的额度窗口")
                    .font(DesignTokens.bodyFont)
                    .foregroundStyle(DesignTokens.secondaryText)
                    .frame(minHeight: 70)
            } else {
                ForEach(windows.indices, id: \.self) { index in
                    let window = windows[index]
                    QuotaWindowBlock(
                        window: window,
                        isPrimary: index == 0,
                        isStale: pool.availability == .stale,
                        warningThreshold: warningThreshold,
                        accent: pool.id.accent
                    )

                    if index < windows.count - 1 {
                        Divider()
                            .overlay(DesignTokens.divider.opacity(0.46))
                    }
                }
            }

            if pool.availability == .stale, let message = pool.message {
                Text(message)
                    .font(.system(size: 10))
                    .foregroundStyle(DesignTokens.amber)
                    .lineLimit(2)
            }
        }
    }

    private var displayWindows: [QuotaWindow] {
        var result: [QuotaWindow] = []

        if let weekly = pool.weeklyWindow {
            result.append(weekly)
        }
        if let session = pool.sessionWindow, !result.contains(where: { $0.id == session.id }) {
            result.append(session)
        }

        for window in pool.windows where !result.contains(where: { $0.id == window.id }) {
            result.append(window)
        }
        return Array(result.prefix(2))
    }

    private var loadingState: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("正在读取额度…")
                    .font(DesignTokens.bodyFont)
                    .foregroundStyle(DesignTokens.secondaryText)
                Spacer()
                ProgressView().controlSize(.small)
            }

            VStack(spacing: 13) {
                placeholderWindow(widthFraction: 0.63)
                Divider().overlay(DesignTokens.divider.opacity(0.46))
                placeholderWindow(widthFraction: 0.86)
            }
        }
        .frame(minHeight: 122)
    }

    private func placeholderWindow(widthFraction: Double) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text("额度窗口")
                    .font(.system(size: 13, weight: .medium))
                Spacer()
                HStack(alignment: .lastTextBaseline, spacing: 1) {
                    Text("00")
                        .font(.system(size: 28, weight: .medium))
                        .tracking(-0.8)
                    Text("%")
                        .font(.system(size: 18, weight: .medium))
                        .tracking(-0.4)
                }
            }
            .foregroundStyle(DesignTokens.secondaryText)

            QuotaProgressBar(value: widthFraction, color: pool.id.accent)
                .redacted(reason: .placeholder)

            Text("读取重置时间…")
                .font(.system(size: 10))
                .foregroundStyle(DesignTokens.tertiaryText)
        }
        .redacted(reason: .placeholder)
    }

    @ViewBuilder
    private var unavailableState: some View {
        switch accountConnection {
        case .starting:
            loginStartingState
        case .awaiting(_):
            browserLoginState
        default:
            unavailableMessageState
        }
    }

    private var loginStartingState: some View {
        HStack(spacing: 10) {
            ProgressView().controlSize(.small)
            Text("正在准备 ChatGPT 验证…")
                .font(DesignTokens.bodyFont)
                .foregroundStyle(DesignTokens.secondaryText)
            Spacer()
        }
        .frame(minHeight: 72)
    }

    private var browserLoginState: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack(spacing: 8) {
                Image(systemName: "safari")
                    .foregroundStyle(DesignTokens.cyan)
                Text("等待浏览器完成授权")
                    .font(DesignTokens.bodyFont)
                    .foregroundStyle(DesignTokens.secondaryText)
            }

            Text("确认当前 ChatGPT 账号和工作区后，额度会自动出现。")
                .font(DesignTokens.smallFont)
                .foregroundStyle(DesignTokens.tertiaryText)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                Button("重新打开登录页", action: onOpenLoginPage)
                    .buttonStyle(.borderedProminent)
                    .tint(DesignTokens.cyan.opacity(0.82))
                    .controlSize(.small)

                Spacer()

                Button("取消", action: onCancelLogin)
                    .buttonStyle(.plain)
                    .font(.system(size: 11))
                    .foregroundStyle(DesignTokens.tertiaryText)
            }

            Text("浏览器只用于 OpenAI 官方登录，不读取网页聊天内容")
                .font(.system(size: 10))
                .foregroundStyle(DesignTokens.tertiaryText)
        }
        .frame(minHeight: 104)
    }

    private var unavailableMessageState: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: pool.availability == .authorizationRequired ? "person.crop.circle.badge.exclamationmark" : "exclamationmark.circle")
                    .foregroundStyle(DesignTokens.secondaryText)
                Text(pool.message ?? "暂时无法读取额度")
                    .font(DesignTokens.bodyFont)
                    .foregroundStyle(DesignTokens.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer()
            }

            switch accountConnection {
            case .signedOut, .failed(_):
                Button("连接 ChatGPT", action: onConnect)
                    .font(.system(size: 12, weight: .medium))
                    .buttonStyle(.borderedProminent)
                    .tint(DesignTokens.cyan.opacity(0.82))
                    .controlSize(.small)
            case .helperMissing:
                Button("重新检测", action: onRefresh)
                    .font(.system(size: 12, weight: .medium))
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            default:
                Button("重新检测", action: onRefresh)
                    .font(.system(size: 12, weight: .medium))
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
        }
        .frame(minHeight: 72)
    }

    private var accessibilityLabel: String {
        let descriptions = displayWindows.map { window in
            "\(window.title)剩余 \(QuotaFormatters.percent(window.remainingPercent))，\(QuotaFormatters.resetCountdown(to: window.resetsAt))"
        }
        guard !descriptions.isEmpty else {
            return "\(pool.id.displayName)，\(pool.message ?? "暂时无法读取")"
        }
        return "\(pool.id.displayName)，" + descriptions.joined(separator: "；")
    }
}

private struct QuotaWindowBlock: View {
    let window: QuotaWindow
    let isPrimary: Bool
    let isStale: Bool
    let warningThreshold: Double
    let accent: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .lastTextBaseline, spacing: 8) {
                Text(window.title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(DesignTokens.secondaryText)

                Spacer()

                HStack(alignment: .lastTextBaseline, spacing: 4) {
                    Text("剩余")
                        .font(.system(size: 10))
                        .foregroundStyle(DesignTokens.tertiaryText)

                    HStack(alignment: .lastTextBaseline, spacing: 1) {
                        Text("\(Int(window.remainingPercent.rounded()))")
                            .font(.system(size: isPrimary ? 36 : 30, weight: .medium, design: .default))
                            .tracking(isPrimary ? -1.2 : -0.9)

                        Text("%")
                            .font(.system(size: isPrimary ? 23 : 19, weight: .medium, design: .default))
                            .tracking(-0.4)
                    }
                    .foregroundStyle(DesignTokens.primaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.84)
                }
            }

            QuotaProgressBar(
                value: window.remainingPercent / 100,
                color: visualState.color
            )

            HStack(spacing: 7) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(visualState.color)
                        .frame(width: 5, height: 5)
                    Text(visualState.label)
                }
                .foregroundStyle(visualState.color)

                Spacer(minLength: 8)

                Text(resetDisplayText)
                    .monospacedDigit()
                    .foregroundStyle(DesignTokens.tertiaryText)
                    .lineLimit(1)
                    .help(QuotaFormatters.resetExactTime(to: window.resetsAt))
            }
            .font(.system(size: 10.5, weight: .regular))
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(window.title)，剩余 \(QuotaFormatters.percent(window.remainingPercent))，\(visualState.label)，\(resetDisplayText)")
    }

    private var resetDisplayText: String {
        let countdown = QuotaFormatters.resetCountdown(to: window.resetsAt)
        guard let absolute = QuotaFormatters.resetAbsoluteDateTime(to: window.resetsAt) else {
            return countdown
        }
        return "\(countdown) · \(absolute)"
    }

    private var visualState: WindowVisualState {
        if isStale {
            return WindowVisualState(label: "上次数据", color: DesignTokens.amber)
        }
        if window.remainingPercent <= 10 {
            return WindowVisualState(label: "额度紧张", color: DesignTokens.red)
        }
        if window.remainingPercent <= warningThreshold {
            return WindowVisualState(label: "额度偏低", color: DesignTokens.amber)
        }
        if window.remainingPercent >= 70 {
            return WindowVisualState(label: "额度充足", color: accent)
        }
        return WindowVisualState(label: "消耗正常", color: accent)
    }
}

private struct WindowVisualState {
    let label: String
    let color: Color
}

private struct QuotaProgressBar: View {
    let value: Double
    let color: Color

    var body: some View {
        GeometryReader { proxy in
            let progressWidth = max(5, proxy.size.width * min(1, max(0, value)))

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(DesignTokens.track)
                    .overlay(alignment: .top) {
                        Capsule()
                            .stroke(Color.white.opacity(0.075), lineWidth: 0.45)
                    }

                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [color.opacity(0.98), color.opacity(0.72)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .overlay {
                        Capsule()
                            .stroke(Color.white.opacity(0.13), lineWidth: 0.45)
                    }
                    .shadow(color: color.opacity(0.20), radius: 2.5)
                    .frame(width: progressWidth)
            }
        }
        .frame(height: 6)
        .accessibilityHidden(true)
    }
}
