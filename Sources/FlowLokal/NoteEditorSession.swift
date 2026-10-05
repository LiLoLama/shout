import Foundation
import Combine

/// Ein Editor, in den die Sitzung Text einfügen kann — so landet ein Diktat am
/// Cursor und lässt sich mit ⌘Z in einem Schritt zurücknehmen.
@MainActor
protocol NoteTextEditing: AnyObject {
    /// `false`, wenn der Editor gerade nichts annehmen kann; dann fügt die Sitzung selbst ein.
    func insertText(_ text: String, at point: NoteEditorSession.InsertionPoint) -> Bool
}

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

    /// Wo eingefügter Text landet.
    enum InsertionPoint: Equatable {
        case cursor
        case end
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
    /// Steigt bei jeder Eingabe. Zeigen zwei Editoren dieselbe Notiz (Seite und
    /// Panel), lädt der jeweils andere daran neu.
    @Published private(set) var editRevision = 0
    /// Der Editor, von dem die letzte Eingabe kam; `nil`, wenn ohne Editor eingefügt wurde.
    private(set) weak var lastEditSource: AnyObject?
    /// Der zuletzt benutzte Editor — dorthin geht ein Diktat.
    private(set) weak var editor: NoteTextEditing?
    /// Cursor bzw. Auswahl, zuletzt vom Editor gemeldet (UTF-16, wie `NSTextView`).
    private(set) var lastSelection = NSRange(location: 0, length: 0)

    private let store: NoteStore
    private let saveDelay: TimeInterval
    private let retryDelay: TimeInterval
    private var saveTask: Task<Void, Never>?
    private var subscription: AnyCancellable?
    private var conflictSubscription: AnyCancellable?
    /// Es gibt Text, der nicht in der Datei steht und nur in dieser Sitzung lebt,
    /// weil die Datei fehlt. Taucht sie wieder auf, darf ihr Inhalt ihn nicht ersetzen.
    private var unsavedWhileMissing = false
    /// Läuft gerade der eine Wiederholversuch? Dann folgt auf einen Fehlschlag kein weiterer.
    private var isRetrying = false

    init(note: Note, store: NoteStore, saveDelay: TimeInterval = 1.0, retryDelay: TimeInterval = 5.0) {
        id = note.id
        self.note = note
        self.store = store
        self.saveDelay = saveDelay
        self.retryDelay = retryDelay
        status = note.isPlaceholder ? .placeholder : .clean
        subscription = store.$notes.dropFirst().sink { [weak self] notes in
            MainActor.assumeIsolated { self?.storeChanged(notes) }
        }
        // Ohne `dropFirst`: Eine Sitzung, die erst nach der Rückkehr geöffnet wird,
        // zeigt den noch nicht quittierten Hinweis auch.
        conflictSubscription = store.$returnedAsConflict.sink { [weak self] eintraege in
            MainActor.assumeIsolated { self?.returnedAsConflict(eintraege) }
        }
    }

    /// Es gibt Text (oder ein Anheften), der nicht in der Datei steht.
    var hasUnsavedText: Bool { status == .dirty || unsavedWhileMissing }

    /// Vom Editor bei jeder Eingabe; `source` ist der meldende Editor.
    func edit(_ text: String, from source: AnyObject? = nil) {
        guard status != .placeholder, text != note.body else { return }
        note.body = text
        lastEditSource = source
        editRevision += 1
        // Fehlt die Datei, wird nicht ins Leere gesichert; „Wieder sichern“
        // nimmt dann den aktuellen Text.
        if status == .missing {
            unsavedWhileMissing = true
            return
        }
        status = .dirty
        scheduleSave()
    }

    func attach(editor: NoteTextEditing) { self.editor = editor }

    func detach(editor: NoteTextEditing) {
        if self.editor === editor { self.editor = nil }
    }

    func selectionChanged(_ range: NSRange) { lastSelection = range }

    /// Fügt Text ein — über den angehängten Editor (ein Rückgängig-Schritt) oder,
    /// ohne Editor, direkt in den Text. `.cursor` setzt bei Bedarf ein Leerzeichen
    /// davor (`DictationInsertion`), `.end` hängt wörtlich an. `false` nur bei
    /// einem iCloud-Platzhalter oder leerem Text.
    @discardableResult
    func insert(_ text: String, at point: InsertionPoint) -> Bool {
        guard status != .placeholder, !text.isEmpty else { return false }
        // Ein Editor gilt nur als angenommen, wenn er die Änderung auch gemeldet hat
        // (`edit` hebt `editRevision`). Sonst stünde der Text nirgends.
        let revision = editRevision
        if let editor, editor.insertText(text, at: point), editRevision != revision { return true }
        let hatEditor = editor != nil
        let ns = note.body as NSString
        var ort = point == .end ? ns.length : min(max(lastSelection.location, 0), ns.length)
        // Ein veralteter Cursor kann mitten in einem Zeichen (Emoji, Kombination)
        // liegen; dort einzufügen risse es auseinander.
        if ort < ns.length { ort = ns.rangeOfComposedCharacterSequence(at: ort).location }
        let vorher: Character? = ort > 0
            ? ns.substring(with: ns.rangeOfComposedCharacterSequence(at: ort - 1)).last
            : nil
        let einfuegen = point == .end ? text : DictationInsertion.text(text, after: vorher)
        let neu = ns.replacingCharacters(in: NSRange(location: ort, length: 0), with: einfuegen)
        if point == .cursor {
            lastSelection = NSRange(location: ort + (einfuegen as NSString).length, length: 0)
        }
        edit(neu)
        // Der angehängte Editor kennt die Einfügung nicht: Er muss neu laden, sonst
        // überschriebe seine nächste Eingabe sie.
        if hatEditor { externalRevision += 1 }
        return true
    }

    /// Für Aufrufer von außen, wenn die Sitzung endet oder wechselt (Schließen,
    /// Beenden, anderer Tab): sichert, und legt eine fehlende Datei neu an, wenn
    /// ohne sie weitergeschrieben (oder angeheftet) wurde — der Text geht so nicht
    /// verloren. Zeitgeber, Wiederholung, Anheften und Umbenennen legen nie neu
    /// an; dort soll der Nutzer „fehlt“ sehen.
    func flush() {
        saveIfDirty()
        if status == .missing, unsavedWhileMissing { restoreMissing() }
    }

    /// Sichert, wenn etwas ungesichert ist. Stellt nie eine fehlende Datei her.
    private func saveIfDirty() {
        cancelTimer()
        guard status == .dirty else { return }
        apply(store.save(note), restoring: false)
    }

    /// Heftet an oder löst. Ungesicherter Text wird zuerst gesichert; danach
    /// ändert der Store nur `pinned` und liest dafür die Datei neu, wenn sie sich
    /// inzwischen von außen geändert hat (sonst gingen deren Änderungen verloren).
    func setPinned(_ pinned: Bool) {
        guard status != .placeholder else { return }
        saveIfDirty()
        // Fehlende Datei, neue Notiz oder gescheitertes Sichern: Es gibt nichts,
        // worauf der Store aufsetzen könnte. Die Absicht bleibt im Speicher und
        // wird mit dem nächsten Sichern (bzw. „Wieder sichern“) geschrieben.
        if status == .missing {
            note.pinned = pinned
            unsavedWhileMissing = true
            return
        }
        guard status == .clean, !note.isNew else {
            note.pinned = pinned
            return
        }
        // Der Store darf nur aufsetzen, wenn er denselben Text kennt wie die
        // Sitzung. Nach `.buffered` hält er noch den alten (Puffer-Fassung steht
        // nur hier); dann ginge der neue Text verloren. Also lokal sichern.
        guard storeMatchesSession, let ergebnis = store.setPinned(id, pinned) else {
            note.pinned = pinned
            status = .dirty
            saveIfDirty()
            return
        }
        if case .failed = ergebnis {
            // Nichts geschrieben: die Absicht als ungesichert festhalten.
            note.pinned = pinned
            status = .dirty
        }
        apply(ergebnis, restoring: false)
    }

    /// `true`, wenn umbenannt wurde.
    @discardableResult
    func rename(to title: String) -> Bool {
        saveIfDirty()
        // Bleibt Text ungesichert (Sichern gescheitert) oder kennt der Store den
        // Text nicht (gepuffert), würde seine Fassung ihn ersetzen. Dann lieber
        // nicht umbenennen: `saveFailed` bzw. die Pufferanzeige warnt.
        guard status == .clean, storeMatchesSession else { return false }
        guard let umbenannt = store.rename(id, to: title) else { return false }
        if umbenannt.body != note.body { externalRevision += 1 }
        note = umbenannt
        return true
    }

    func restoreMissing() {
        guard status == .missing else { return }
        apply(store.restore(note), restoring: true)
    }

    func dismissNotice() { conflictNotice = nil }

    // MARK: - Intern

    /// Der Store hält denselben Text wie die Sitzung und der Ordner ist da.
    private var storeMatchesSession: Bool {
        store.folderState == .ok && store.note(id: id)?.body == note.body
    }

    private func cancelTimer() {
        saveTask?.cancel()
        saveTask = nil
    }

    private func scheduleSave() {
        cancelTimer()
        let delay = saveDelay
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            self?.saveIfDirty()
        }
    }

    /// Ein einziger neuer Versuch nach einem Fehlschlag. Scheitert auch er, wartet
    /// die Sitzung auf die nächste Eingabe oder ein ausdrückliches `flush()`.
    /// Nach gescheitertem „Wieder sichern“ wiederholt er genau das.
    private func scheduleRetry(restoring: Bool) {
        cancelTimer()
        let delay = retryDelay
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled, let self else { return }
            self.isRetrying = true
            defer { self.isRetrying = false }
            if restoring { self.restoreMissing() } else { self.saveIfDirty() }
        }
    }

    /// Ersetzt `note` durch das Ergebnis des Stores. Kommt ein anderer Text zurück
    /// als der aktuelle, hat der Editor ihn nicht — dann muss er neu geladen
    /// werden, sonst klaffen Editor und `note` still auseinander.
    private func apply(_ result: NoteStore.SaveResult, restoring: Bool) {
        switch result {
        case .saved(let gesichert), .buffered(let gesichert):
            if gesichert.body != note.body { externalRevision += 1 }
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
            // Ein Versuch später noch einmal; die nächste Eingabe oder `flush()` ersetzt ihn.
            saveFailed = true
            if !isRetrying { scheduleRetry(restoring: restoring) }
        }
    }

    private func markSaved() {
        status = .clean
        saveFailed = false
        unsavedWhileMissing = false
    }

    private func markMissing() {
        cancelTimer()
        if status == .dirty { unsavedWhileMissing = true }
        status = .missing
        saveFailed = false
    }

    /// Gepufferter Text dieser Notiz kam als Konfliktdatei in den Ordner zurück:
    /// Der Hinweis nennt sie, so wie bei einem Konflikt beim Sichern.
    private func returnedAsConflict(_ eintraege: [UUID: String]) {
        guard let name = eintraege[id] else { return }
        conflictNotice = name
        // Nicht hier im Sink quittieren: `@Published` meldet vor dem Speichern,
        // eine Änderung mitten darin würde gleich wieder überschrieben.
        let store = store, id = id
        DispatchQueue.main.async {
            MainActor.assumeIsolated { store.acknowledgeReturnedConflict(id) }
        }
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
        // Von iCloud ausgelagert, während hier Text ungesichert ist: Der Platzhalter
        // hat keinen Inhalt und darf ihn nicht ersetzen. Der Text bleibt ungesichert;
        // kommt die Datei zurück, entscheidet die Konfliktprüfung, `flush()` legt
        // ihn sonst unter einem freien Namen daneben an.
        if hasUnsavedText, frisch.isPlaceholder { return }
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
        if status == .missing, unsavedWhileMissing, !frisch.isPlaceholder,
           frisch.body == note.body, frisch.pinned != note.pinned {
            // Gleicher Text, aber hier wurde ohne Datei angeheftet: Die Absicht
            // bleibt ungesichert. Gleiches mtime, also kein Konflikt beim Sichern.
            note.fileName = frisch.fileName
            note.modified = frisch.modified
            note.created = frisch.created
            note.createdRaw = frisch.createdRaw
            note.extraFrontmatter = frisch.extraFrontmatter
            status = .dirty
            scheduleSave()
            return
        }
        guard frisch != note || status == .missing else { return }
        let textGeaendert = frisch.body != note.body
        note = frisch
        status = frisch.isPlaceholder ? .placeholder : .clean
        unsavedWhileMissing = false
        saveFailed = false
        if textGeaendert { externalRevision += 1 }
    }
}
