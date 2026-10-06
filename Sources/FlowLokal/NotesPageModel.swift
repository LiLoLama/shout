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
    /// Hierhin rettet das Beenden ungesicherten Text (`NoteSessionRegistry.writeRescueCopies`).
    let rescueDirectory: URL
    /// Der Rettungsordner im App-Support — die eine Stelle für Seite und Beenden.
    nonisolated static var defaultRescueDirectory: URL {
        StoreIO.directory().appendingPathComponent("Notizen-Rettung", isDirectory: true)
    }
    /// Gerettete Notizen (`.md` im Rettungsordner). Solange welche da sind, zeigt
    /// die Seite einen Hinweis — sonst lägen sie unbemerkt im App-Support.
    @Published private(set) var rescuedFiles: [URL] = []
    /// Teilt die Sitzungen mit dem Panel: eine pro Notiz.
    let registry: NoteSessionRegistry
    /// Nach einem Ordnerwechsel — das Panel räumt dann seine Tabs ab.
    var onFolderChanged: (() -> Void)?
    /// Frühere Stände (vom AppDelegate gesetzt; in Tests eigene).
    var versions: NoteVersions?

    init(store: NoteStore, registry: NoteSessionRegistry? = nil, defaults: UserDefaults = .standard,
         rescueDirectory: URL = NotesPageModel.defaultRescueDirectory) {
        self.store = store
        self.registry = registry ?? NoteSessionRegistry(store: store)
        self.defaults = defaults
        self.rescueDirectory = rescueDirectory
        refreshRescuedFiles()
        self.registry.onDiscard { [weak self] id in
            guard let self, self.session?.id == id else { return }
            self.session = nil
        }
    }

    /// Liest den Rettungsordner neu ein.
    func refreshRescuedFiles() {
        let inhalt = (try? FileManager.default.contentsOfDirectory(at: rescueDirectory,
                                                                   includingPropertiesForKeys: nil)) ?? []
        let dateien = inhalt
            .filter { !$0.lastPathComponent.hasPrefix(".") && $0.pathExtension.lowercased() == NoteFile.fileExtension }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        if dateien != rescuedFiles { rescuedFiles = dateien }
    }

    /// Holt die geretteten Notizen in den Notizordner, jede unter einem freien
    /// Namen. Die Rettungsdatei wird erst entfernt, wenn die Notiz geschrieben
    /// ist; scheitert etwas, bleibt sie liegen. Gibt die Zahl der geholten zurück.
    @discardableResult
    func adoptRescuedNotes() -> Int {
        refreshRescuedFiles()
        guard !rescuedFiles.isEmpty, store.checkFolder(create: true) == .ready else { return 0 }
        var geholt = 0
        for datei in rescuedFiles {
            guard let daten = try? Data(contentsOf: datei), let text = String(data: daten, encoding: .utf8) else {
                NSLog("shout: Gerettete Notiz \(datei.lastPathComponent) ist nicht lesbar — bleibt liegen.")
                continue
            }
            let parsed = NoteFile.parse(text)
            let titel = NoteFile.safeTitle(datei.deletingPathExtension().lastPathComponent)
                ?? NoteFile.deriveTitle(from: parsed.body)
                ?? Loc.t("Unbenannt")
            let name = NoteFile.freeFileName(for: titel, in: store.folder)
            let note = Note(id: UUID(), fileName: name, body: parsed.body, created: parsed.created ?? Date(),
                            modified: Date(), pinned: parsed.pinned, extraFrontmatter: parsed.extraFrontmatter,
                            titleIsFixed: true, createdRaw: parsed.createdRaw)
            guard store.write(note, to: store.folder.appendingPathComponent(name)) != nil else { continue }
            geholt += 1
            do {
                try FileManager.default.removeItem(at: datei)
            } catch {
                NSLog("shout: Gerettete Notiz \(datei.lastPathComponent) konnte nicht entfernt werden: \(error)")
            }
        }
        store.reload()
        refreshRescuedFiles()
        return geholt
    }

    var results: [NoteSearch.Result] { NoteSearch.filter(store.notes, query: query) }

    /// Sichert die offene Sitzung, bevor die Seite sie verlässt. `false`, wenn
    /// danach noch Text nur im Speicher steht (Sichern gescheitert): Die Sitzung
    /// bleibt dann offen, sonst ginge der Text verloren. Die Oberfläche warnt
    /// über `session.saveFailed`.
    private func leaveSession() -> Bool {
        guard let session else { return true }
        session.flush()
        guard !session.hasUnsavedText else { return false }
        registry.release(session)
        self.session = nil
        return true
    }

    func select(_ id: UUID) {
        guard session?.id != id, store.note(id: id) != nil, leaveSession() else { return }
        // Erst nach dem Sichern holen: Das kann neu eingelesen haben (Konflikt),
        // eine vorher geholte Fassung wäre dann veraltet.
        guard let note = store.note(id: id) else { return }
        session = registry.acquire(note)
    }

    func createNote() {
        guard leaveSession() else { return }
        query = ""
        session = registry.acquireNew()
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
    /// Fassung nur im Speicher zurück. Das gilt auch, wenn die Notiz nur im Panel
    /// offen ist — die Sitzung kommt dann aus der Registry.
    func delete(_ id: UUID) {
        let istOffen = session?.id == id
        let offen = istOffen ? session : registry.session(id: id)
        if let offen {
            offen.flush()
            if offen.hasUnsavedText { return }
            // Nie gesichert und leer geblieben: keine Datei, nichts zurückzuholen.
            // (Getippter Text wurde eben gesichert und geht regulär in den Papierkorb.)
            if offen.note.isNew {
                registry.discard(offen)
                if istOffen { session = nil }
                return
            }
        }
        let vorher = results
        let index = vorher.firstIndex { $0.id == id }
        guard let titel = store.note(id: id)?.title, let token = store.delete(id) else { return }
        lastDeleted = UndoDelete(title: titel, token: token)
        // Die Datei liegt im Papierkorb: Wer die Sitzung hält (Seite, Panel), erfährt es.
        if let offen { registry.discard(offen) }

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

    /// `true`, wenn der Ordner gewechselt wurde. Bleibt Text irgendeiner offenen
    /// Notiz ungesichert, bleibt alles, wie es ist.
    @discardableResult
    func changeFolder(to url: URL) -> Bool {
        // Alle Sitzungen, auch die Tabs des Panels: Bleibt irgendwo Text
        // ungesichert, bleibt alles, wie es ist.
        guard registry.flushAll().isEmpty else { return false }
        registry.removeAll()
        session = nil
        lastDeleted = nil
        NotesFolder.set(url, defaults: defaults)
        store.setFolder(url)
        onFolderChanged?()
        return true
    }

    /// Ausweg, wenn das Sichern dauerhaft scheitert: schließt die Sitzung, ohne
    /// zu sichern. Ihr ungesicherter Text ist danach weg — die Oberfläche fragt
    /// vorher nach und bietet an, ihn zu kopieren.
    func discardSession() {
        if let offen = session { registry.discard(offen) }
        session = nil
    }

    func versionList(for id: UUID) -> [NoteVersions.Version] {
        guard let versions, let note = store.note(id: id), !note.isNew else { return [] }
        return versions.list(for: note.fileName)
    }

    /// Holt einen früheren Stand zurück. Der aktuelle wird vorher selbst als
    /// Version gesichert. `false`, wenn nichts geändert wurde (Platzhalter,
    /// laufender Transform, Text, der sich nicht sichern lässt).
    @discardableResult
    func restore(_ version: NoteVersions.Version, of id: UUID) -> Bool {
        guard let versions, let text = version.text() else { return false }
        let offen: NoteEditorSession? = session?.id == id ? session : registry.session(id: id)
        guard let sitzung = offen ?? store.note(id: id).map({ registry.acquire($0) }) else { return false }
        defer { if offen == nil { registry.release(sitzung) } }
        guard sitzung.status != .placeholder, !sitzung.isTransforming else { return false }
        sitzung.flush()
        guard !sitzung.hasUnsavedText else { return false }
        versions.save(sitzung.note.body, for: sitzung.note.fileName)
        let ganz = NSRange(location: 0, length: (sitzung.note.body as NSString).length)
        guard sitzung.replace(ganz, with: text) else { return false }
        sitzung.flush()
        return !sitzung.hasUnsavedText
    }

    func flush() { session?.flush() }

    /// Letzte Sicherung beim Beenden für die offene Notiz der Seite; schreibt
    /// über `registry.writeRescueCopy(for:in:)`. Eine neue Kopie erscheint sofort
    /// im Hinweis.
    @discardableResult
    func writeRescueCopyIfNeeded(in directory: URL) -> URL? {
        guard let session else { return nil }
        let url = registry.writeRescueCopy(for: session, in: directory)
        if url != nil { refreshRescuedFiles() }
        return url
    }
}
