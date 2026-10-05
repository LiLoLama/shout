import Foundation

/// Zustand der Seite „Notizen“: Suche, Auswahl, Löschen mit Rückgängig.
/// Lebt beim AppDelegate, damit beim Schließen und Beenden gesichert wird.
@MainActor
final class NotesPageModel: ObservableObject {

    struct UndoDelete: Equatable {
        let title: String
        let token: NoteStore.DeletedNote
    }

    let store: NoteStore
    @Published var query = ""
    @Published private(set) var session: NoteEditorSession?
    @Published private(set) var lastDeleted: UndoDelete?
    private let defaults: UserDefaults

    init(store: NoteStore, defaults: UserDefaults = .standard) {
        self.store = store
        self.defaults = defaults
    }

    var results: [NoteSearch.Result] { NoteSearch.filter(store.notes, query: query) }

    /// Sichert die offene Sitzung, bevor die Seite sie verlässt. `false`, wenn
    /// danach noch Text nur im Speicher steht (Sichern gescheitert): Die Sitzung
    /// bleibt dann offen, sonst ginge der Text verloren. Die Oberfläche warnt
    /// über `session.saveFailed`.
    private func leaveSession() -> Bool {
        guard let session else { return true }
        session.flush()
        return !session.hasUnsavedText
    }

    func select(_ id: UUID) {
        guard session?.id != id, let note = store.note(id: id), leaveSession() else { return }
        session = NoteEditorSession(note: note, store: store)
    }

    func createNote() {
        guard leaveSession() else { return }
        query = ""
        session = NoteEditorSession(note: .blank(), store: store)
    }

    /// ↑/↓ und j/k. Ohne Auswahl wird die erste Notiz gewählt; am Rand bleibt es stehen.
    func moveSelection(by offset: Int) {
        let liste = results
        guard !liste.isEmpty else { return }
        let ziel = liste.firstIndex { $0.id == session?.id }
            .map { min(max($0 + offset, 0), liste.count - 1) } ?? 0
        select(liste[ziel].id)
    }

    /// Ist die Notiz offen, geht es über die Sitzung — sonst ginge ungesicherter Text verloren.
    func togglePin(_ id: UUID) {
        if let session, session.id == id {
            session.setPinned(!session.note.pinned)
        } else if let note = store.note(id: id) {
            store.setPinned(id, !note.pinned)
        }
    }

    func rename(_ id: UUID, to title: String) {
        if let session, session.id == id {
            session.rename(to: title)
        } else {
            store.rename(id, to: title)
        }
    }

    /// Löscht in den Papierkorb. Steht in der offenen Notiz Text, der sich nicht
    /// sichern lässt, passiert nichts: Die Datei zu entsorgen ließe die neuere
    /// Fassung nur im Speicher zurück.
    func delete(_ id: UUID) {
        let istOffen = session?.id == id
        if istOffen {
            session?.flush()
            if session?.hasUnsavedText == true { return }
            // Nie gesichert und leer geblieben: keine Datei, nichts zurückzuholen.
            // (Getippter Text wurde eben gesichert und geht regulär in den Papierkorb.)
            if session?.note.isNew == true {
                session = nil
                return
            }
        }
        let vorher = results
        let index = vorher.firstIndex { $0.id == id }
        guard let titel = store.note(id: id)?.title, let token = store.delete(id) else { return }
        lastDeleted = UndoDelete(title: titel, token: token)

        guard istOffen else { return }
        session = nil
        let rest = results
        if let index, !rest.isEmpty { select(rest[min(index, rest.count - 1)].id) }
    }

    /// Holt die zuletzt gelöschte Notiz zurück und öffnet sie. Hält die offene
    /// Sitzung ungesicherten Text, der sich nicht sichern lässt, wird die Notiz
    /// trotzdem zurückgeholt, die Sitzung aber nicht ersetzt.
    func undoDelete() {
        guard let geloescht = lastDeleted else { return }
        lastDeleted = nil
        guard let note = store.undoDelete(geloescht.token) else { return }
        select(note.id)
    }

    func dismissUndo() { lastDeleted = nil }

    /// `true`, wenn der Ordner gewechselt wurde. Bleibt Text der offenen Notiz
    /// ungesichert, bleibt alles, wie es ist.
    @discardableResult
    func changeFolder(to url: URL) -> Bool {
        guard leaveSession() else { return false }
        session = nil
        lastDeleted = nil
        NotesFolder.set(url, defaults: defaults)
        store.setFolder(url)
        return true
    }

    /// Ausweg, wenn das Sichern dauerhaft scheitert: schließt die Sitzung, ohne
    /// zu sichern. Ihr ungesicherter Text ist danach weg — die Oberfläche fragt
    /// vorher nach und bietet an, ihn zu kopieren.
    func discardSession() {
        session = nil
    }

    func flush() { session?.flush() }
}
