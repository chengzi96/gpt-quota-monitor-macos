import AppKit
import SwiftUI

struct QuotaPopoverView: View {
    @EnvironmentObject private var store: QuotaStore
    @AppStorage("alertsEnabled") private var alertsEnabled = false

    var onHoverChanged: ((Bool) -> Void)? = nil
    var onOpenSettings: ((SettingsTab) -> Void)? = nil

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.bottom, 16)

            Divider().overlay(DesignTokens.divider)

            VStack(spacing: 0) {
                let pools = store.orderedPools
                ForEach(pools.indices, id: \.self) { index in
                    let pool = pools[index]
                    QuotaSectionView(
                        pool: pool,
                        warningThreshold: store.warningThreshold,
                        accountConnection: store.accountConnection,
                        onRefresh: { Task { await store.refresh() } },
                        onConnect: { store.beginChatGPTLogin() },
                        onOpenLoginPage: { store.openLoginPage() },
                        onCancelLogin: { store.cancelChatGPTLogin() }
                    )
                    .padding(.vertical, 17)

                    if index < pools.count - 1 {
                        Divider().overlay(DesignTokens.divider)
                    }
                }

                Divider().overlay(DesignTokens.divider)

                reminderFooter
                    .padding(.top, 12)
            }
        }
        .padding(.horizontal, DesignTokens.contentInset)
        .padding(.top, 18)
        .padding(.bottom, 14)
        .background {
            TransparentPopoverWindowConfigurator()
                .frame(width: 0, height: 0)
                .allowsHitTesting(false)
        }
        .adaptivePanelGlass()
        .clipShape(
            RoundedRectangle(cornerRadius: DesignTokens.panelRadius, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: DesignTokens.panelRadius, style: .continuous)
                .stroke(Color.white.opacity(0.070), lineWidth: 0.6)
                .allowsHitTesting(false)

            LiquidGlassSheen()
                .clipShape(
                    RoundedRectangle(cornerRadius: DesignTokens.panelRadius, style: .continuous)
                )
                .allowsHitTesting(false)
        }
        .frame(width: DesignTokens.panelWidth)
        .environment(\.colorScheme, .dark)
        .onHover { inside in
            onHoverChanged?(inside)
        }
        .task {
            await store.startIfNeeded()
            await store.refreshIfStale()
        }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 5) {
                Text("GPT流量监控")
                    .font(DesignTokens.titleFont)
                    .foregroundStyle(DesignTokens.primaryText)

                Text(store.updatedLabel)
                    .font(DesignTokens.smallFont)
                    .foregroundStyle(updatedLabelColor)
            }

            Spacer()

            headerActions
        }
    }

    @ViewBuilder
    private var headerActions: some View {
        if #available(macOS 26.0, *) {
            GlassEffectContainer(spacing: 8) {
                headerButtonRow
            }
        } else {
            headerButtonRow
        }
    }

    private var headerButtonRow: some View {
        HStack(spacing: 8) {
            HeaderGlassButton(
                symbol: "arrow.clockwise",
                help: "立即刷新",
                isBusy: store.refreshState == .refreshing
            ) {
                Task { await store.refresh() }
            }

            HeaderGlassButton(symbol: "gearshape.fill", help: "设置") {
                openSettings(.general)
            }
        }
    }

    private var updatedLabelColor: Color {
        if case .failed(_) = store.refreshState { return DesignTokens.amber }
        if store.refreshNotice != nil { return DesignTokens.green }
        return DesignTokens.secondaryText
    }

    private var reminderFooter: some View {
        Button(action: { openSettings(.alerts) }) {
            HStack(spacing: 9) {
                Image(systemName: alertsEnabled ? "bell" : "bell.slash")
                    .font(.system(size: 13, weight: .medium))
                Text(alertsEnabled ? "低于 \(Int(store.warningThreshold))% 时提醒" : "额度提醒未开启")
                    .font(DesignTokens.bodyFont)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(DesignTokens.tertiaryText)
            }
            .foregroundStyle(DesignTokens.secondaryText)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("打开额度提醒设置")
    }

    private func openSettings(_ tab: SettingsTab) {
        store.selectedSettingsTab = tab
        onOpenSettings?(tab)
    }
}

private struct LiquidGlassSheen: View {
    var body: some View {
        GeometryReader { proxy in
            LinearGradient(
                colors: [
                    Color.white.opacity(0.165),
                    Color.white.opacity(0.040),
                    Color.clear
                ],
                startPoint: .topLeading,
                endPoint: UnitPoint(x: 0.72, y: 0.46)
            )
            .frame(height: max(72, proxy.size.height * 0.28))
            .frame(maxHeight: .infinity, alignment: .top)
            .blendMode(.screen)
        }
    }
}

private struct HeaderGlassButton: View {
    let symbol: String
    let help: String
    var isBusy = false
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Group {
                if isBusy {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .controlSize(.small)
                        .tint(DesignTokens.primaryText.opacity(0.94))
                } else {
                    HeaderSymbol(symbol: symbol)
                }
            }
            .frame(width: 31, height: 31)
            .contentShape(Circle())
        }
        .buttonStyle(
            HeaderFeedbackButtonStyle(
                isHovering: isHovering,
                isBusy: isBusy
            )
        )
        .disabled(isBusy)
        .onHover { inside in
            isHovering = inside
        }
        .accessibilityLabel(help)
        .help(help)
    }
}

private struct HeaderFeedbackButtonStyle: ButtonStyle {
    let isHovering: Bool
    let isBusy: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background {
                Circle()
                    .fill(
                        Color.white.opacity(
                            configuration.isPressed ? 0.18 :
                            (isHovering ? 0.105 : 0.065)
                        )
                    )
            }
            .overlay {
                Circle()
                    .stroke(
                        Color.white.opacity(
                            configuration.isPressed ? 0.22 :
                            (isHovering ? 0.135 : 0.075)
                        ),
                        lineWidth: 0.7
                    )
            }
            .brightness(configuration.isPressed ? 0.08 : 0)
            .opacity(isBusy ? 0.88 : 1)
            .animation(.easeOut(duration: 0.065), value: configuration.isPressed)
            .animation(.easeOut(duration: 0.085), value: isHovering)
    }
}

private struct HeaderSymbol: View {
    let symbol: String

    var body: some View {
        Image(systemName: symbol)
            .symbolRenderingMode(.hierarchical)
            .font(.system(size: 18.5, weight: .semibold))
            .foregroundStyle(DesignTokens.primaryText.opacity(0.94))
            .frame(width: 20, height: 20)
    }
}

#Preview {
    QuotaPopoverView()
        .environmentObject(QuotaStore(preview: true))
}
