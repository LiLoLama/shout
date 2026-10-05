import Foundation
import Combine

/// Eine geöffnete Notiz: nimmt Eingaben an, sichert eine Sekunde nach der
/// letzten und entscheidet, was bei Änderungen von außen passiert. Die Seite
/// „Notizen“ hat eine Sitzung, das Panel (Plan 2) eine pro Tab.
@MainActor
final class NoteEditorSession: ObservableObject, Identifiable {

    enum Status: Equatable {
        case clean
        case dirty
        /// Die Datei ist nicht mehr im Ordner; „Wieder sichern“ legt sie neu an.
        case missing
        /// Von iCloud ausgelagert, Inhalt kommt noch. Bis dahin gesperrt.
        case placeholder
    }

    let id: UUID
    @Published private(set) var note: Note
    @Published private(set) var status: Status
    /// Steigt, wenn eine Fassung von außen übernommen wurde. Nur dann ersetzt der
    /// Editor seinen Text — sonst spränge bei jeder Eingabe der Cursor.
    @Published private(set) var externalRevision = 0
    /// Name der Konfliktdatei, solange der Hinweis steht.
    @Published private(set) var conflictNotice: String?
    /// Das letzte Sichern hat nichts geschrieben (Platte voll, Fremddatei nicht
    /// lesbar …). Der Text bleibt ungesichert (`status == .dirty`); die nächste
    /// Eingabe oder `flush()` versucht es erneut. Die Oberfläche warnt, solange das steht.
    @Published private(set) var saveFailed = false

    private let store: NoteStore
    private let saveDelay: TimeInterval
    private var saveTask: Task<Void, Never>?
    private var subscription: AnyCancellable?
    /// Es gibt Text, der nicht in der Datei steht und nur in dieser Sitzung lebt,
    /// weil die Datei fehlt. Taucht sie wieder auf, darf ihr Inhalt ihn nicht ersetzen.
    private var unsavedWhileMissing = false

    init(note: Note, store: NoteStore, saveDelay: TimeInterval = 1.0) {
        id = note.id
        self.note = note
        self.store = store
        self.saveDelay = saveDelay
        status = note.isPlaceholder ? .placeholder : .clean
        subscription = store.$notes.dropFirst().sink { [weak self] notes in
            self?.storeChanged(notes)
        }
    }

    /// Vom Editor bei jeder Eingabe.
    func edit(_ text: String) {
        guard status != .placeholder, text != note.body else { return }
        note.body = text
        // Fehlt die Datei, wird nicht ins Leere gesichert; „Wieder sichern“
        // nimmt dann den aktuellen Text.
        if status == .missing {
            unsavedWhileMissing = true
            return
        }
        status = .dirty
        scheduleSave()
    }

    /// Sichert sofort, wenn es etwas zu sichern gibt.
    func flush() {
        saveTask?.cancel()
        saveTask = nil
        guard status == .dirty else { return }
        apply(store.save(note))
    }

    /// Heftet an oder löst. Ungesicherter Text wird zuerst gesichert; danach
    /// ändert der Store nur `pinned` und liest dafür die Datei neu, wenn sie sich
    /// inzwischen von außen geändert hat (sonst gingen deren Änderungen verloren).
    func setPinned(_ pinned: Bool) {
        guard status != .placeholder else { return }
        flush()
        // Neue Notiz, fehlende Datei oder gescheitertes Sichern: Es gibt nichts,
        // worauf der Store aufsetzen könnte. Die Absicht bleibt im Speicher und
        // wird mit dem nächsten Sichern (bzw. „Wieder sichern“) geschrieben.
        guard status == .clean, !note.isNew else {
            note.pinned = pinned
            return
        }
        guard let ergebnis = store.setPinned(id, pinned) else {
            note.pinned = pinned
            status = .dirty
            flush()
            return
        }
        if case .failed = ergebnis {
            // Nichts geschrieben: die Absicht als ungesichert festhalten.
            note.pinned = pinned
            status = .dirty
        }
        apply(ergebnis)
    }

    func rename(to title: String) {
        flush()
        // Bleibt Text ungesichert (Sichern gescheitert), würde die Fassung des
        // Stores ihn ersetzen. Dann lieber nicht umbenennen: `saveFailed` warnt.
        guard status == .clean else { return }
        guard let umbenannt = store.rename(id, to: title) else { return }
        note = umbenannt
    }

    func restoreMissing() {
        guard status == .missing else { return }
        apply(store.restore(note))
    }

    func dismissNotice() { conflictNotice = nil }

    // MARK: - Intern

    private func scheduleSave() {
        saveTask?.cancel()
        let delay = saveDelay
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            self?.flush()
        }
    }

    private func apply(_ result: NoteStore.SaveResult) {
        switch result {
        case .saved(let gesichert), .buffered(let gesichert):
            note = gesichert
            markSaved()
        case .skippedEmpty:
            markSaved()
        case .missing:
            markMissing()
        case .conflict(let extern, let dateiname):
            note = extern
            markSaved()
            conflictNotice = dateiname
            externalRevision += 1
        case .failed:
            // Nichts geschrieben: Status bleibt, wie er ist (ungesichert bzw. fehlend).
            saveFailed = true
        }
    }

    private func markSaved() {
        status = .clean
        saveFailed = false
        unsavedWhileMissing = false
    }

    private func markMissing() {
        if status == .dirty { unsavedWhileMissing = true }
        status = .missing
        saveFailed = false
    }

    /// Die Liste des Stores hat sich geändert (eigene Sicherung, Neueinlesen,
    /// Umbenennen). Ungesicherter Text wird hier nie überschrieben — das
    /// entscheidet beim Sichern die Konfliktprüfung.
    private func storeChanged(_ notes: [Note]) {
        guard let frisch = notes.first(where: { $0.id == id }) else {
            // Nie gesicherte Notizen stehen nicht in der Liste; alle anderen fehlen jetzt.
            if !note.isNew, !note.isPlaceholder, store.folderState == .ok { markMissing() }
            return
        }
        if status == .dirty { return }
        if status == .missing, unsavedWhileMissing, !frisch.isPlaceholder, frisch.body != note.body {
            // Die Datei ist wieder da, hier wurde aber ohne sie weitergeschrieben.
            // Unser Text bleibt ungesichert; das veraltete mtime erzwingt beim
            // Sichern die Konfliktprüfung, die beide Fassungen aufhebt.
            note.fileName = frisch.fileName
            note.modified = .distantPast
            status = .dirty
            scheduleSave()
            return
        }
        // Eine fehlende Notiz, die unverändert zurückkommt, ist wieder da.
        guard frisch != note || status == .missing else { return }
        let textGeaendert = frisch.body != note.body
        note = frisch
        status = frisch.isPlaceholder ? .placeholder : .clean
        unsavedWhileMissing = false
        saveFailed = false
        if textGeaendert { externalRevision += 1 }
    }
}
