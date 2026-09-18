import Foundation

enum QuotaFormatters {
    private static func relativePast(_ date: Date, now: Date) -> String {
        let interval = max(0, now.timeIntervalSince(date))
        if interval < 3_600 { return "\(max(1, Int(interval / 60))) 分钟前" }
        if interval < 86_400 { return "\(max(1, Int(interval / 3_600))) 小时前" }
        return "\(max(1, Int(interval / 86_400))) 天前"
    }

    private static func timeFormatter() -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_Hans_CN")
        formatter.dateFormat = "HH:mm"
        return formatter
    }

    private static func monthDayTimeFormatter() -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_Hans_CN")
        formatter.dateFormat = "M月d日 HH:mm"
        return formatter
    }

    private static func shortDateFormatter() -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_Hans_CN")
        formatter.dateFormat = "M月d日"
        return formatter
    }

    static func percent(_ value: Double) -> String { "\(Int(value.rounded()))%" }

    static func resetCountdown(to date: Date?, now: Date = Date()) -> String {
        guard let date else { return "重置时间未知" }
        let seconds = max(0, Int(date.timeIntervalSince(now)))
        if seconds == 0 { return "即将重置" }
        let days = seconds / 86_400
        let hours = (seconds % 86_400) / 3_600
        let minutes = (seconds % 3_600) / 60
        if days > 0 { return "\(days) 天 \(hours) 小时后重置" }
        if hours > 0 { return "\(hours) 小时 \(minutes) 分后重置" }
        return "\(max(1, minutes)) 分钟后重置"
    }

    static func resetExactTime(to date: Date?, now: Date = Date(), calendar: Calendar = .current) -> String {
        guard let date else { return "重置时间未知" }
        if calendar.isDate(date, inSameDayAs: now) {
            return "今天 \(timeFormatter().string(from: date)) 重置"
        }
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: now),
           calendar.isDate(date, inSameDayAs: tomorrow) {
            return "明天 \(timeFormatter().string(from: date)) 重置"
        }
        return "\(monthDayTimeFormatter().string(from: date)) 重置"
    }

    static func resetAbsoluteDateTime(to date: Date?) -> String? {
        guard let date else { return nil }
        return monthDayTimeFormatter().string(from: date)
    }

    static func lastUpdated(_ date: Date?, now: Date = Date()) -> String {
        guard let date else { return "尚未更新" }
        let interval = max(0, now.timeIntervalSince(date))
        if interval < 45 { return "刚刚更新" }
        if interval < 3_600 { return "\(max(1, Int(interval / 60))) 分钟前更新" }
        return relativePast(date, now: now) + "更新"
    }

    static func staleDataAge(_ date: Date?, now: Date = Date()) -> String {
        guard let date else { return "上次数据" }
        let interval = max(0, now.timeIntervalSince(date))
        if interval < 60 { return "刚刚的数据" }
        if interval < 3_600 { return "\(max(1, Int(interval / 60))) 分钟前数据" }
        if interval < 86_400 { return "\(max(1, Int(interval / 3_600))) 小时前数据" }
        return relativePast(date, now: now) + "数据"
    }

    static func shortDate(_ date: Date) -> String { shortDateFormatter().string(from: date) }
}
