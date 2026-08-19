import Foundation
import Combine

/// Verlauf der Diktate — lokal als JSON in ~/Library/Application Support/shout/history.json.
@MainActor
final class DictationHistory: ObservableObject {

    struct Entry: Codable, Identifiable {
        var id = UUID()
        var text: String
        var date: Date
        /// Rohtext der Spracherkennung — vor gesprochenen Befehlen, KI-Aufbereitung
        /// und Korrekturen. `nil`, wenn identisch mit `text` (nichts wurde verändert)
        /// oder bei Einträgen aus älteren Versionen.
        var raw: String?

        init(text: String, date: Date, raw: String? = nil) {
            self.text = text
            self.date = date
            self.raw = raw
        }

        // Tolerantes Decoding: fehlende Felder → Default statt „Datei defekt".
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
            text = try c.decodeIfPresent(String.self, forKey: .text) ?? ""
            date = try c.decodeIfPresent(Date.self, forKey: .date) ?? Date()
            raw = try c.decodeIfPresent(String.self, forKey: .raw)
        }
    }

    @Published private(set) var entries: [Entry] = []

    private let fileURL: URL
    private let maxEntries = 300

    init() {
        fileURL = StoreIO.directory().appendingPathComponent("history.json")
        if let decoded = StoreIO.load([Entry].self, from: fileURL) {
            entries = Array(decoded.prefix(maxEntries))
        }
    }

    func add(_ text: String, raw: String? = nil) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        // Rohtext nur behalten, wenn er sich vom Ergebnis unterscheidet — sonst
        // stünde in der Oberfläche zweimal dasselbe.
        let rawTrimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines)
        let storedRaw = (rawTrimmed?.isEmpty == false && rawTrimmed != trimmed) ? rawTrimmed : nil
        entries.insert(Entry(text: trimmed, date: Date(), raw: storedRaw), at: 0)
        if entries.count > maxEntries { entries.removeLast(entries.count - maxEntries) }
        save()
    }

    func delete(_ entry: Entry) {
        entries.removeAll { $0.id == entry.id }
        save()
    }

    func clear() {
        entries.removeAll()
        save()
    }

    /// Ersetzt alle Einträge (für Import) — ebenfalls auf das Limit gekappt.
    func replaceEntries(_ newEntries: [Entry]) {
        entries = Array(newEntries.prefix(maxEntries))
        save()
    }

    // MARK: - Persistenz

    private func save() {
        StoreIO.save(entries, to: fileURL)
    }
}
