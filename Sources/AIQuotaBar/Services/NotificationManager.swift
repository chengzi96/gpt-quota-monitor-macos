import Foundation
import UserNotifications

final class NotificationManager: @unchecked Sendable {
    private let center: UNUserNotificationCenter
    private let defaults: UserDefaults

    init(center: UNUserNotificationCenter = .current(), defaults: UserDefaults = .standard) {
        self.center = center
        self.defaults = defaults
    }

    func requestAuthorization() async -> Bool {
        (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
    }

    func sendTestNotification() async -> Bool {
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized
            || settings.authorizationStatus == .provisional else {
            return false
        }

        let content = UNMutableNotificationContent()
        content.title = "GPT流量监控测试提醒"
        content.body = "通知工作正常。额度低于设定阈值时会在这里提醒你。"
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "aiquotabar.test.\(UUID().uuidString)",
            content: content,
            trigger: nil
        )
        do {
            try await center.add(request)
            return true
        } catch {
            return false
        }
    }

    func evaluate(pool: QuotaPool, warningThreshold: Double) async {
        guard defaults.object(forKey: "alertsEnabled") as? Bool ?? false else { return }
        guard let window = pool.mostConstrainedWindow else { return }

        let remaining = window.remainingPercent
        let level: Int?
        if remaining <= 10 { level = 10 }
        else if remaining <= warningThreshold { level = Int(warningThreshold.rounded()) }
        else { level = nil }
        guard let level else { return }

        let cycle = window.resetsAt.map { String(Int($0.timeIntervalSince1970)) } ?? "unknown"
        let key = "notified.\(pool.id.rawValue).\(window.id).\(cycle).\(level)"
        guard !defaults.bool(forKey: key) else { return }

        let content = UNMutableNotificationContent()
        content.title = "GPT流量监控"
        content.subtitle = "\(window.title)额度提醒"
        content.body = "剩余 \(QuotaFormatters.percent(remaining))，\(QuotaFormatters.resetCountdown(to: window.resetsAt))。"
        content.sound = .default

        let request = UNNotificationRequest(identifier: key, content: content, trigger: nil)
        do {
            try await center.add(request)
            await markNotified(key)
        } catch {
            // Notification delivery failure should not affect quota refresh.
        }
    }

    @MainActor
    private func markNotified(_ key: String) {
        // UserDefaults.didChangeNotification is delivered on the thread that
        // performs the write. Keep this mutation on MainActor so AppKit/Combine
        // observers can never be entered from a background executor.
        defaults.set(true, forKey: key)
    }
}
