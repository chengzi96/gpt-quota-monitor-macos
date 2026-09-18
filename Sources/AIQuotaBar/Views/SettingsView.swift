import AppKit
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var store: QuotaStore
    @StateObject private var launchAtLogin = LaunchAtLoginManager()
    @Namespace private var tabHighlight

    var body: some View {
        VStack(spacing: 0) {
            SettingsTabBar(
                selection: $store.selectedSettingsTab,
                highlightNamespace: tabHighlight
            )
            .padding(.horizontal, 12)
            .padding(.top, 2)

            selectedPane
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: 520, height: 390)
        .padding(12)
        .preferredColorScheme(.dark)
    }

    @ViewBuilder
    private var selectedPane: some View {
        switch store.selectedSettingsTab {
        case .general:
            GeneralSettingsView(launchAtLogin: launchAtLogin)
        case .menuBar:
            MenuBarSettingsView()
        case .alerts:
            AlertSettingsView()
        case .data:
            DataSettingsView()
        case .about:
            AboutSettingsView()
        }
    }
}

private struct SettingsTabBar: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Binding var selection: SettingsTab
    let highlightNamespace: Namespace.ID

    var body: some View {
        HStack(spacing: 3) {
            ForEach(SettingsTab.allCases) { tab in
                Button {
                    withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.18)) {
                        selection = tab
                    }
                } label: {
                    ZStack {
                        if selection == tab {
                            Capsule(style: .continuous)
                                .fill(Color.white.opacity(0.18))
                                .matchedGeometryEffect(id: "settings-tab-highlight", in: highlightNamespace)
                        }

                        Text(tab.title)
                            .font(.system(size: 13, weight: selection == tab ? .semibold : .medium))
                            .foregroundStyle(
                                selection == tab
                                    ? DesignTokens.primaryText
                                    : DesignTokens.secondaryText
                            )
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 32)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selection == tab ? .isSelected : [])
            }
        }
        .padding(4)
        .background(Color.black.opacity(0.16), in: Capsule(style: .continuous))
        .overlay {
            Capsule(style: .continuous)
                .stroke(Color.white.opacity(0.13), lineWidth: 1)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("设置分类")
    }
}

private struct SettingsPane<Content: View>: View {
    let title: String
    let content: Content

    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(title)
                .font(.system(size: 20, weight: .semibold))
            Form {
                content
            }
            .formStyle(.grouped)
        }
        .padding(12)
    }
}

private struct GeneralSettingsView: View {
    @EnvironmentObject private var store: QuotaStore
    @ObservedObject var launchAtLogin: LaunchAtLoginManager
    @AppStorage("refreshIntervalMinutes") private var refreshIntervalMinutes = 5.0

    var body: some View {
        SettingsPane(title: "常规") {
            Section {
                Toggle("登录时自动启动", isOn: Binding(
                    get: { launchAtLogin.isEnabled },
                    set: { launchAtLogin.setEnabled($0) }
                ))
                if let error = launchAtLogin.errorMessage {
                    Text(error).foregroundStyle(DesignTokens.red)
                }
            }

            Section("刷新") {
                Picker("自动刷新间隔", selection: $refreshIntervalMinutes) {
                    Text("1 分钟").tag(1.0)
                    Text("5 分钟").tag(5.0)
                    Text("15 分钟").tag(15.0)
                }
                .onChange(of: refreshIntervalMinutes) { _ in
                    store.refreshScheduleDidChange()
                }
            }
        }
    }
}

private struct MenuBarSettingsView: View {
    @AppStorage("showMenuBarQuotaSummary") private var showPercentage = true

    var body: some View {
        SettingsPane(title: "菜单栏") {
            Section {
                Toggle("显示剩余百分比", isOn: $showPercentage)
                Text("关闭后仅显示面性沙漏图标。")
                    .foregroundStyle(.secondary)
            }

            Section("展示规则") {
                LabeledContent("额度来源", value: "Work + Codex")
                Text("开启后同时显示“周 xx% · 5h xx%”，一眼区分两个真实额度窗口。")
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct AlertSettingsView: View {
    @EnvironmentObject private var store: QuotaStore
    @AppStorage("alertsEnabled") private var alertsEnabled = false
    @AppStorage("warningThreshold") private var warningThreshold = 20.0
    @State private var permissionMessage: String?
    @State private var permissionMessageIsError = false
    @State private var isSendingTest = false

    var body: some View {
        SettingsPane(title: "额度提醒") {
            Section {
                Toggle("开启系统通知", isOn: $alertsEnabled)
                    .onChange(of: alertsEnabled) { enabled in
                        guard enabled else {
                            permissionMessage = nil
                            return
                        }
                        Task {
                            let granted = await store.requestNotificationAuthorization()
                            if !granted {
                                await MainActor.run {
                                    alertsEnabled = false
                                    permissionMessageIsError = true
                                    permissionMessage = "通知权限未开启，可前往系统设置修改。"
                                }
                            } else {
                                await MainActor.run {
                                    permissionMessageIsError = false
                                    permissionMessage = "系统通知已开启。"
                                }
                            }
                        }
                    }
                if let permissionMessage {
                    Text(permissionMessage)
                        .foregroundStyle(permissionMessageIsError ? DesignTokens.amber : DesignTokens.green)
                }
            }

            Section("阈值") {
                Picker("剩余额度低于", selection: $warningThreshold) {
                    Text("10%").tag(10.0)
                    Text("20%").tag(20.0)
                    Text("30%").tag(30.0)
                }
                Text("低于 10% 时会进入严重提醒状态；每个重置周期同一档只提醒一次。")
                    .foregroundStyle(.secondary)
            }

            Section("验证") {
                Button(isSendingTest ? "正在发送…" : "发送测试提醒") {
                    isSendingTest = true
                    Task {
                        let sent = await store.sendTestNotification()
                        await MainActor.run {
                            isSendingTest = false
                            permissionMessageIsError = !sent
                            permissionMessage = sent
                                ? "测试提醒已发送。"
                                : "无法发送测试提醒，请检查系统通知权限。"
                        }
                    }
                }
                .disabled(!alertsEnabled || isSendingTest)

                Button("打开系统通知设置") {
                    store.openSystemNotificationSettings()
                }
            }
        }
    }
}

private struct DataSettingsView: View {
    @EnvironmentObject private var store: QuotaStore
    @State private var showClearConfirmation = false

    var body: some View {
        SettingsPane(title: "数据与连接") {
            Section("额度来源") {
                connectionRow
            }

            Section("GPT Chat") {
                LabeledContent("剩余额度", value: "暂无统一可读百分比")
                Text("Chat 的使用上限会随模型、套餐和系统策略变化；GPT流量监控不会用估算值或网页抓取结果冒充真实额度。")
                    .foregroundStyle(.secondary)
            }

            Section("ChatGPT 连接") {
                connectionActions
            }

            Section {
                Button("立即刷新") {
                    Task { await store.refresh() }
                }
                .disabled(store.refreshState == .refreshing || store.accountConnection.isLoginInProgress)

                Button("清除本地历史记录", role: .destructive) {
                    showClearConfirmation = true
                }
            }

            Section("隐私") {
                Text("GPT流量监控只读取额度信息，不读取或保存你的提示词、回复和项目代码；访问令牌不会写入本应用的数据文件或日志。")
                    .foregroundStyle(.secondary)
            }
        }
        .confirmationDialog("确定清除历史记录？", isPresented: $showClearConfirmation) {
            Button("清除", role: .destructive) { store.clearHistory() }
            Button("取消", role: .cancel) {}
        }
    }

    private var connectionRow: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text(QuotaPoolID.workCodex.displayName)
                    .font(.system(size: 13, weight: .medium, design: .monospaced))
                Text("ChatGPT Work 与 Codex 共享")
                    .font(.system(size: 10))
                    .foregroundStyle(DesignTokens.cyan)
            }
            Spacer()
            Text(connectionLabel)
                .foregroundStyle(connectionColor)
        }
    }

    @ViewBuilder
    private var connectionActions: some View {
        switch store.accountConnection {
        case .signedOut, .failed(_):
            Button("连接 ChatGPT") { store.beginChatGPTLogin() }
        case .helperMissing:
            Text("缺少 OpenAI 官方额度组件，请重新运行安装器。")
                .foregroundStyle(DesignTokens.amber)
        case .starting:
            HStack {
                ProgressView().controlSize(.small)
                Text("正在准备验证…")
            }
        case .awaiting(_):
            Text("请在浏览器中确认 ChatGPT 账号和工作区。")
                .foregroundStyle(.secondary)
            HStack {
                Button("重新打开登录页") { store.openLoginPage() }
                Button("取消") { store.cancelChatGPTLogin() }
            }
        case .checking:
            Text("正在检查连接…")
                .foregroundStyle(.secondary)
        case .connected(let email, _):
            Text(email.map { "已连接：\($0)" } ?? "已通过 OpenAI 官方登录连接")
                .foregroundStyle(.secondary)
        }
    }

    private var connectionLabel: String {
        switch store.accountConnection {
        case .connected(_, _): return "连接正常"
        case .starting, .awaiting(_): return "正在连接"
        case .signedOut: return "需要登录"
        case .helperMissing: return "缺少组件"
        case .failed(_): return "连接失败"
        case .checking: return "正在检查"
        }
    }

    private var connectionColor: Color {
        switch store.accountConnection {
        case .connected(_, _): return DesignTokens.green
        case .failed(_), .helperMissing: return DesignTokens.amber
        default: return DesignTokens.secondaryText
        }
    }
}

private struct AboutSettingsView: View {
    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "开发版"
    }

    var body: some View {
        SettingsPane(title: "关于 GPT流量监控") {
            Section {
                LabeledContent("版本", value: version)
                LabeledContent("额度组件", value: "OpenAI App Server 0.151.0")
                LabeledContent("系统要求", value: "macOS 13+ · Apple Silicon")
            }

            Section {
                Link("查看 OpenAI 官方额度说明", destination: URL(string: "https://learn.chatgpt.com/docs/pricing")!)
                Link("查看 OpenAI 官方登录说明", destination: URL(string: "https://developers.openai.com/codex/auth")!)
            }

            Section {
                Button("退出 GPT流量监控") {
                    NSApp.terminate(nil)
                }
            }
        }
    }
}

#Preview {
    SettingsView()
        .environmentObject(QuotaStore(preview: true))
}
