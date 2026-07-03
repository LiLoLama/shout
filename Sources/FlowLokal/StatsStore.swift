import Foundation
import Combine

/// Kumulative Nutzungs-Statistiken (bleiben erhalten, auch wenn der Verlauf
/// gekappt wird). JSON in ~/Library/Application Support/shout/stats.json.
@MainActor
final class StatsStore: ObservableObject {

    struct Data: Codable {
        var totalWords = 0
        var totalDictations = 0
        var totalSeconds = 0.0
        var activeDays: [String] = []   // "yyyy-MM-dd"
    }

    @Published private(set) var data = Data()

    private let fileURL: URL

    init() {
        fileURL = StoreIO.directory().appendingPathComponent("stats.json")
        if let decoded = StoreIO.load(Data.self, from: fileURL) { data = decoded }
    }

    func record(words: Int, seconds: Double, date: Date = Date()) {
        guard words > 0 else { return }
        data.totalWords += words
        data.totalDictations += 1
        data.totalSeconds += max(0, seconds)
        let key = Self.dayKey(date)
        if !data.activeDays.contains(key) { data.activeDays.append(key) }
        save()
    }

    var averageWPM: Int {
        guard data.totalSeconds > 1 else { return 0 }
        return Int((Double(data.totalWords) / (data.totalSeconds / 60)).rounded())
    }

    /// Aktueller Streak in Tagen (bis heute oder gestern zurück).
    var currentStreak: Int {
        let days = Set(data.activeDays)
        let cal = Calendar.current
        var streak = 0
        var day = cal.startOfDay(for: Date())
        // Wenn heute noch nichts, ab gestern zählen.
        if !days.contains(Self.dayKey(day)) { day = cal.date(byAdding: .day, value: -1, to: day)! }
        while days.contains(Self.dayKey(day)) {
            streak += 1
            day = cal.date(byAdding: .day, value: -1, to: day)!
        }
        return streak
    }

    var longestStreak: Int {
        let keys = data.activeDays.sorted()
        guard !keys.isEmpty else { return 0 }
        let cal = Calendar.current
        let dates = keys.compactMap { Self.dayFormatter.date(from: $0) }
        var longest = 1, run = 1
        for i in 1..<max(1, dates.count) {
            if let prev = cal.date(byAdding: .day, value: 1, to: dates[i - 1]),
               cal.isDate(prev, inSameDayAs: dates[i]) {
                run += 1
            } else {
                run = 1
            }
            longest = max(longest, run)
        }
        return longest
    }

    func isActive(_ date: Date) -> Bool {
        Set(data.activeDays).contains(Self.dayKey(date))
    }

    /// Ersetzt die Statistik-Daten (für Import).
    func replaceData(_ newData: Data) {
        data = newData
        save()
    }

    // MARK: - Persistenz

    private func save() {
        StoreIO.save(data, to: fileURL)
    }

    // MARK: - Helfer

    static func dayKey(_ date: Date) -> String { dayFormatter.string(from: date) }
    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; f.locale = Locale(identifier: "en_US_POSIX"); return f
    }()
}
