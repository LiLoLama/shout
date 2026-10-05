import Foundation

/// Gibt für jede Notiz genau eine `NoteEditorSession` heraus — Seite und Panel
/// teilen sie. Zwei Sitzungen auf derselben Datei hielten sonst die Sicherung
/// der jeweils anderen für eine Änderung von außen.
///
/// Halter zählen: Wer eine Sitzung holt (`acquire`), gibt sie wieder ab
/// (`release`). Beim letzten Abgeben wird gesichert. Bleibt Text ungesichert,
/// behält die Registry die Sitzung trotzdem — sonst wäre er beim Beenden weg.
@MainActor
final class NoteSessionRegistry {

    private struct Eintrag {
        let session: NoteEditorSession
        var halter: Int
    }

    let store: NoteStore
    private let saveDelay: TimeInterval
    private var eintraege: [UUID: Eintrag] = [:]
    private var verwerfenMelden: [(UUID) -> Void] = []
    /// Text und Datei der letzten Rettungskopie je Sitzung: Wird das Beenden
    /// abgebrochen und erneut versucht, entsteht für denselben Text keine zweite.
    private var letzteRettung: [UUID: (body: String, url: URL)] = [:]

    init(store: NoteStore, saveDelay: TimeInterval = 1.0) {
        self.store = store
        self.saveDelay = saveDelay
    }

    func session(id: UUID) -> NoteEditorSession? { eintraege[id]?.session }

    var sessions: [NoteEditorSession] { eintraege.values.map(\.session) }

    var unsavedSessions: [NoteEditorSession] { sessions.filter(\.hasUnsavedText) }

    func acquire(_ note: Note) -> NoteEditorSession {
        if var eintrag = eintraege[note.id] {
            eintrag.halter += 1
            eintraege[note.id] = eintrag
            return eintrag.session
        }
        let neu = NoteEditorSession(note: note, store: store, saveDelay: saveDelay)
        eintraege[note.id] = Eintrag(session: neu, halter: 1)
        return neu
    }

    func acquireNew() -> NoteEditorSession { acquire(.blank()) }

    func release(_ session: NoteEditorSession) {
        guard var eintrag = eintraege[session.id], eintrag.session === session else { return }
        eintrag.halter = max(eintrag.halter - 1, 0)
        guard eintrag.halter == 0 else {
            eintraege[session.id] = eintrag
            return
        }
        session.flush()
        if session.hasUnsavedText {
            eintraege[session.id] = eintrag     // ohne Halter, aber nicht vergessen
        } else {
            eintraege[session.id] = nil
            letzteRettung[session.id] = nil
        }
    }

    /// Wirft die Sitzung weg, ohne zu sichern (nach Rückfrage im Hinweis, oder
    /// weil ihre Datei in den Papierkorb ging). Alle, die sie halten, erfahren es.
    func discard(_ session: NoteEditorSession) {
        guard eintraege[session.id]?.session === session else { return }
        eintraege[session.id] = nil
        letzteRettung[session.id] = nil
        for melden in verwerfenMelden { melden(session.id) }
    }

    func onDiscard(_ handler: @escaping (UUID) -> Void) {
        verwerfenMelden.append(handler)
    }

    /// Sichert alle. Gibt die zurück, deren Text danach noch nicht gesichert ist.
    @discardableResult
    func flushAll() -> [NoteEditorSession] {
        for session in sessions { session.flush() }
        for (id, eintrag) in eintraege where eintrag.halter == 0 && !eintrag.session.hasUnsavedText {
            eintraege[id] = nil
            letzteRettung[id] = nil
        }
        return unsavedSessions
    }

    /// Nach einem Ordnerwechsel: Die Sitzungen gehören zum alten Ordner. Der
    /// Aufrufer hat vorher mit `flushAll()` sichergestellt, dass nichts offen ist.
    /// Alle Halter erfahren es (einmal je Sitzung, wie bei `discard`) — sonst
    /// hielten Seite oder Panel Sitzungen, die die Registry nicht mehr kennt.
    func removeAll() {
        let weg = Array(eintraege.keys)
        eintraege = [:]
        letzteRettung = [:]
        for id in weg {
            for melden in verwerfenMelden { melden(id) }
        }
    }

    /// Letzte Sicherung beim Beenden: Steht nach `flush()` noch Text nur im
    /// Speicher (Platte voll, fremde Änderung nicht lesbar), geht er als eigene
    /// Datei in `directory`, damit er nicht mit der App verschwindet. Die Datei
    /// heißt „Titel yyyy-MM-dd HH-mm-ss.md“. Gibt ihre URL zurück, oder `nil`,
    /// wenn nichts zu retten war oder das Schreiben scheiterte.
    @discardableResult
    func writeRescueCopy(for session: NoteEditorSession, in directory: URL) -> URL? {
        guard session.hasUnsavedText else { return nil }
        let note = session.note
        // Beenden abgebrochen und erneut versucht: Derselbe Text liegt schon gerettet da.
        if let letzte = letzteRettung[session.id], letzte.body == note.body,
           letzte.url.deletingLastPathComponent().standardizedFileURL == directory.standardizedFileURL,
           FileManager.default.fileExists(atPath: letzte.url.path) {
            return letzte.url
        }
        let titel = (note.isNew ? nil : NoteFile.safeTitle(note.title))
            ?? NoteFile.deriveTitle(from: note.body)
            ?? Loc.t("Unbenannt")

        let format = DateFormatter()
        format.locale = Locale(identifier: "en_US_POSIX")
        format.dateFormat = "yyyy-MM-dd HH-mm-ss"
        let zeit = format.string(from: Date())

        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let name = NoteFile.freeFileName(for: "\(titel) \(zeit)", in: directory)
            let url = directory.appendingPathComponent(name)
            try Data(note.body.utf8).write(to: url, options: .atomic)
            letzteRettung[session.id] = (note.body, url)
            return url
        } catch {
            NSLog("shout: Rettungskopie der Notiz konnte nicht geschrieben werden: \(error)")
            return nil
        }
    }

    func writeRescueCopies(in directory: URL) -> (written: [URL], failed: [NoteEditorSession]) {
        var geschrieben: [URL] = []
        var gescheitert: [NoteEditorSession] = []
        for session in unsavedSessions {
            if let url = writeRescueCopy(for: session, in: directory) {
                geschrieben.append(url)
            } else {
                gescheitert.append(session)
            }
        }
        return (geschrieben, gescheitert)
    }
}
