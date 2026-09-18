import Foundation

struct HistoryStore {
    private(set) var samples: [UsageSample] = []
    private let fileManager: FileManager
    private let calendar: Calendar
    private let retentionDays: Int

    init(fileManager: FileManager = .default, calendar: Calendar = .current, retentionDays: Int = 90) {
        self.fileManager = fileManager
        self.calendar = calendar
        self.retentionDays = retentionDays
        self.samples = Self.load(fileManager: fileManager)
        prune()
    }

    mutating func record(pool: QuotaPool, at date: Date = Date()) {
        // v0.1.9 charts only the weekly quota. Recording the most constrained
        // window would mix a rolling 5-hour limit into a chart labeled “本周”.
        guard let trackedWindow = pool.weeklyWindow else { return }
        let usedPercent = trackedWindow.usedPercent
        let day = calendar.startOfDay(for: date)
        if let index = samples.firstIndex(where: {
            $0.poolID == pool.id
                && $0.windowKind == .weekly
                && calendar.isDate($0.date, inSameDayAs: day)
        }) {
            let previous = samples[index]
            samples[index] = UsageSample(
                id: previous.id,
                poolID: pool.id,
                date: day,
                usedPercent: max(previous.usedPercent, usedPercent),
                windowKind: .weekly
            )
        } else {
            samples.append(UsageSample(
                poolID: pool.id,
                date: day,
                usedPercent: usedPercent,
                windowKind: .weekly
            ))
        }
        prune()
        persist()
    }

    func samples(for poolID: QuotaPoolID, days: Int = 7, now: Date = Date()) -> [UsageSample] {
        let start = calendar.date(byAdding: .day, value: -(days - 1), to: calendar.startOfDay(for: now)) ?? now
        return samples
            .filter { $0.poolID == poolID && $0.windowKind == .weekly && $0.date >= start }
            .sorted { $0.date < $1.date }
    }

    mutating func clear() {
        samples = []
        try? fileManager.removeItem(at: Self.historyURL(fileManager: fileManager))
    }

    private mutating func prune(now: Date = Date()) {
        let cutoff = calendar.date(byAdding: .day, value: -retentionDays, to: now) ?? now
        samples.removeAll { $0.date < cutoff }
    }

    private func persist() {
        let url = Self.historyURL(fileManager: fileManager)
        do {
            try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(samples).write(to: url, options: .atomic)
        } catch {
            // History is best-effort. Quota refresh should never fail because local history could not be written.
        }
    }

    private static func load(fileManager: FileManager) -> [UsageSample] {
        let url = historyURL(fileManager: fileManager)
        guard let data = try? Data(contentsOf: url) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([UsageSample].self, from: data)) ?? []
    }

    private static func historyURL(fileManager: FileManager) -> URL {
        let root = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        return root
            .appendingPathComponent("AIQuotaBar", isDirectory: true)
            .appendingPathComponent("history.json", isDirectory: false)
    }
}
