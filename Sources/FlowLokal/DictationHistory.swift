import Foundation
import Combine

/// Verlauf der Diktate — lokal als JSON in ~/Library/Application Support/shout/history.json.
@MainActor
final class DictationHistory: ObservableObject {

    struct Entry: Codable, Identifiable {
        var id = UUID()
        var text: String
        var date: Date
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

    func add(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        entries.insert(Entry(text: trimmed, date: Date()), at: 0)
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
