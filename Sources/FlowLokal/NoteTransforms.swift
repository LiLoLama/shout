import Foundation
import Combine

/// Ein eigener Transform: Name im Menü, Anweisung ans Textmodell.
struct NoteTransform: Codable, Equatable, Identifiable {
    var id: UUID
    var name: String
    var prompt: String
}

/// Die eingebauten Transforms des Zauberstabs. Die Anweisungen bleiben deutsch
/// (wie alle Prompts); das Modell antwortet in der Sprache, die sie verlangen.
enum BuiltinTransform: String, CaseIterable, Identifiable {
    case cleanUp, mail, summary, todos, english

    var id: String { rawValue }

    var instruction: String {
        switch self {
        case .cleanUp:
            return "Räume den Text auf: Streiche Füllwörter und Wiederholungen, korrigiere Grammatik und Rechtschreibung und gliedere ihn in sinnvolle Absätze. Inhalt, Sprache und Ton bleiben."
        case .mail:
            return "Schreibe den Text als E-Mail mit Anrede, Absätzen und Gruß. Bleib in der Sprache des Textes und erfinde keine Inhalte dazu."
        case .summary:
            return "Fasse die wichtigsten Punkte als kurze Liste zusammen, jede Zeile beginnt mit „- “. Bleib in der Sprache des Textes."
        case .todos:
            return "Mache aus dem Text eine To-do-Liste: jede Aufgabe als eigene Zeile „- [ ] …“, sonst nichts."
        case .english:
            return "Übersetze den Text ins Englische. Überschriften, Listen, Hervorhebungen und Links bleiben erhalten."
        }
    }

    @MainActor var name: String {
        switch self {
        case .cleanUp: return Loc.t("Aufräumen")
        case .mail: return Loc.t("Als Mail")
        case .summary: return Loc.t("Zusammenfassen")
        case .todos: return Loc.t("To-do-Liste")
        case .english: return Loc.t("Ins Englische")
        }
    }

    /// Steht im Hinweis, solange das Modell arbeitet.
    @MainActor var working: String {
        switch self {
        case .cleanUp: return Loc.t("Räume auf …")
        case .mail: return Loc.t("Schreibe als Mail …")
        case .summary: return Loc.t("Fasse zusammen …")
        case .todos: return Loc.t("Erstelle To-dos …")
        case .english: return Loc.t("Übersetze …")
        }
    }

    /// Steht danach im Balken mit „Rückgängig“.
    @MainActor var done: String {
        switch self {
        case .cleanUp: return Loc.t("Aufgeräumt")
        case .mail: return Loc.t("Als Mail umgeschrieben")
        case .summary: return Loc.t("Zusammengefasst")
        case .todos: return Loc.t("To-do-Liste erstellt")
        case .english: return Loc.t("Übersetzt")
        }
    }
}

/// Die eigenen Transforms, gesichert in `transforms.json` im App-Support.
@MainActor
final class TransformStore: ObservableObject {
    @Published private(set) var custom: [NoteTransform]
    private let url: URL

    nonisolated static var defaultURL: URL {
        StoreIO.directory().appendingPathComponent("transforms.json")
    }

    init(url: URL = TransformStore.defaultURL) {
        self.url = url
        custom = StoreIO.load([NoteTransform].self, from: url) ?? []
    }

    @discardableResult
    func add(name: String, prompt: String) -> NoteTransform? {
        guard let name = Self.cleaned(name), let prompt = Self.cleaned(prompt) else { return nil }
        let neu = NoteTransform(id: UUID(), name: name, prompt: prompt)
        custom.append(neu)
        persist()
        return neu
    }

    @discardableResult
    func update(_ id: UUID, name: String, prompt: String) -> Bool {
        guard let index = custom.firstIndex(where: { $0.id == id }),
              let name = Self.cleaned(name), let prompt = Self.cleaned(prompt) else { return false }
        custom[index].name = name
        custom[index].prompt = prompt
        persist()
        return true
    }

    func remove(_ id: UUID) {
        custom.removeAll { $0.id == id }
        persist()
    }

    /// Aus einem Backup.
    func replaceAll(_ neu: [NoteTransform]) {
        custom = neu
        persist()
    }

    private func persist() { StoreIO.save(custom, to: url) }

    private static func cleaned(_ s: String) -> String? {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }
}
