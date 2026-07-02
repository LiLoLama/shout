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
        let base = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = base.appendingPathComponent("shout", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = dir.appendingPathComponent("history.json")
        load()
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

    // MARK: - Persistenz

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode([Entry].self, from: data) else { return }
        entries = decoded
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
