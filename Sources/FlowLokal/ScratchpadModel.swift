import Foundation

/// Die Tabs des Panels: welche Notizen offen sind, welche vorne ist, und wohin
/// ein Diktat geht. Die Sitzungen kommen aus der Registry — dieselbe Notiz auf
/// der Seite und im Panel ist dieselbe Sitzung.
@MainActor
final class ScratchpadModel: ObservableObject {

    /// Was beim Einblenden offen ist.
    enum OpenBehavior: String, CaseIterable {
        /// Die Tabs vom letzten Mal; ohne Tabs eine neue Notiz.
        case resume
        /// Ein neuer Tab, außer der vordere ist noch leer.
        case newTab
        /// Die zuletzt benutzte angeheftete Notiz, sonst die neueste angeheftete.
        case lastPinned
    }

    static let maxTabs = 5

    let store: NoteStore
    let registry: NoteSessionRegistry
    @Published private(set) var tabs: [NoteEditorSession] = []
    @Published private(set) var activeIndex: Int?
    @Published var showsList: Bool {
        didSet { defaults.set(showsList, forKey: K.liste) }
    }
    @Published var query = ""
    private let defaults: UserDefaults
    private var wiederhergestellt = false

    /// Schlüssel des Eingangs-Dateinamens in den UserDefaults (auch fürs Backup).
    static let inboxFileNameKey = "scratchpad.inboxFileName"

    private enum K {
        static let tabs = "scratchpad.tabs"
        /// Dateiname des aktiven Tabs. Nicht die Stelle: Neue Tabs werden nicht
        /// gemerkt, eine Stelle zeigte nach dem Neustart auf die falsche Notiz.
        static let aktiv = "scratchpad.activeTabName"
        static let liste = "scratchpad.showsList"
        static let angeheftet = "scratchpad.lastPinned"
        static let eingang = ScratchpadModel.inboxFileNameKey
    }

    init(store: NoteStore, registry: NoteSessionRegistry, defaults: UserDefaults = .standard) {
        self.store = store
        self.registry = registry
        self.defaults = defaults
        showsList = defaults.object(forKey: K.liste) as? Bool ?? true
        registry.onDiscard { [weak self] id in self?.dropTab(id) }
        store.observeRenames { [weak self] alt, neu in
            guard let self, alt.lowercased() == self.inboxFileName.lowercased() else { return }
            self.inboxFileName = neu
        }
    }

    var active: NoteEditorSession? {
        guard let activeIndex, tabs.indices.contains(activeIndex) else { return nil }
        return tabs[activeIndex]
    }

    var results: [NoteSearch.Result] { NoteSearch.filter(store.notes, query: query) }

    // MARK: - Tabs

    /// Holt die Tabs vom letzten Mal zurück (einmal je Programmlauf).
    func restoreTabs() {
        guard !wiederhergestellt else { return }
        wiederhergestellt = true
        guard tabs.isEmpty else { return }
        for name in (defaults.stringArray(forKey: K.tabs) ?? []).prefix(Self.maxTabs) {
            // Doppelt gemerkt (von Hand geändert): ein Tab, ein Halter.
            guard let note = store.notes.first(where: { $0.fileName == name }),
                  !tabs.contains(where: { $0.id == note.id }) else { continue }
            tabs.append(registry.acquire(note))
        }
        let aktiv = defaults.string(forKey: K.aktiv)
        activeIndex = tabs.isEmpty ? nil : (tabs.firstIndex { $0.note.fileName == aktiv } ?? 0)
    }

    /// Beim Einblenden des Panels.
    func prepareForShowing(behavior: OpenBehavior) {
        restoreTabs()
        switch behavior {
        case .resume:
            if tabs.isEmpty { newTab() }
        case .newTab:
            let vorneLeer = active.map { $0.note.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty } ?? false
            if !vorneLeer { newTab() }
        case .lastPinned:
            let angeheftet = store.notes.filter(\.pinned)
            let gemerkt = defaults.string(forKey: K.angeheftet)
            if let ziel = angeheftet.first(where: { $0.fileName == gemerkt }) ?? angeheftet.first {
                open(ziel.id, inNewTab: false)
            } else if tabs.isEmpty {
                newTab()
            }
        }
    }

    /// Ein neuer Tab mit einer neuen Notiz. Sind schon fünf offen, ersetzt sie den
    /// aktiven. `nil`, wenn der aktive ungesicherten Text behält.
    @discardableResult
    func newTab() -> NoteEditorSession? {
        // Sonst überschriebe der erste neue Tab die gemerkten vom letzten Mal.
        restoreTabs()
        let neu = registry.acquireNew()
        guard place(neu, inNewTab: true) else {
            registry.release(neu)
            return nil
        }
        return neu
    }

    /// Öffnet eine Notiz. Ist sie schon in einem Tab, wird der gewählt.
    func open(_ id: UUID, inNewTab: Bool) {
        restoreTabs()
        if let index = tabs.firstIndex(where: { $0.id == id }) {
            select(index)
            return
        }
        guard let note = store.note(id: id) else { return }
        let session = registry.acquire(note)
        if !place(session, inNewTab: inNewTab) { registry.release(session) }
    }

    func select(_ index: Int) {
        guard tabs.indices.contains(index) else { return }
        activeIndex = index
        merkeAngeheftet(tabs[index])
        persist()
    }

    /// ⌃⇥ und ⌃⇧⇥ (auch ⌘⌥→ und ⌘⌥←) — rundherum.
    func selectNext(_ offset: Int) {
        guard !tabs.isEmpty else { return }
        let jetzt = activeIndex ?? 0
        select(((jetzt + offset) % tabs.count + tabs.count) % tabs.count)
    }

    /// Schließt einen Tab. Lässt sich sein Text nicht sichern, bleibt er offen
    /// und wird gewählt: Geschlossen stünde der Text unsichtbar nur im Speicher.
    /// Der Ausweg ist „Verwerfen …“ (`discard`).
    func close(_ index: Int) {
        guard tabs.indices.contains(index) else { return }
        tabs[index].flush()
        guard !tabs[index].hasUnsavedText else {
            select(index)
            return
        }
        let weg = tabs.remove(at: index)
        rueckeAuswahl(nachEntfernen: index)
        registry.release(weg)
        persist()
    }

    /// Beim Ausblenden: alle Tabs sichern, die Tabs bleiben.
    func flushAll() {
        // Sonst schriebe `persist()` eine leere Liste über die gemerkten Tabs.
        restoreTabs()
        for tab in tabs { tab.flush() }
        persist()
    }

    /// Nach einem Ordnerwechsel: Die Sitzungen gehören zum alten Ordner.
    func resetTabs() {
        tabs = []
        activeIndex = nil
        persist()
    }

    /// Verwirft eine Sitzung ohne zu sichern (Hinweis „Verwerfen …“).
    func discard(_ session: NoteEditorSession) {
        registry.discard(session)      // meldet zurück an dropTab
    }

    // MARK: - Diktat

    /// Der Tab für ein Diktat per Scratchpad-Taste: der aktive, außer er hat schon
    /// Text und `newIfActiveHasText` — dann ein neuer.
    func tabForDictation(newIfActiveHasText: Bool) -> NoteEditorSession? {
        restoreTabs()
        if let aktiv = active {
            let leer = aktiv.note.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            if leer || !newIfActiveHasText { return aktiv }
        }
        return newTab() ?? active
    }

    /// Fügt ein Diktat am Cursor der Notiz ein. Ist sie nicht mehr offen, landet
    /// es in einem neuen Tab. `false` nur, wenn auch das nicht geht.
    func insertDictation(_ text: String, into id: UUID) -> Bool {
        // Nichts gesprochen: nichts verloren, und kein leerer Tab.
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return true }
        if let session = tabs.first(where: { $0.id == id }) ?? registry.session(id: id),
           session.insert(text, at: .cursor) {
            return true
        }
        guard let neu = newTab() else { return false }
        return neu.insert(text, at: .cursor)
    }

    // MARK: - Eingang

    /// Dateiname der Eingangs-Notiz; folgt einer Umbenennung in shout.
    var inboxFileName: String {
        // Eigener Schlüssel „Eingang.md“: „Eingang“ allein heißt in der Oberfläche
        // schon „Input“ (Audio-Eingang).
        get { defaults.string(forKey: K.eingang) ?? Loc.t("Eingang.md") }
        set { defaults.set(newValue, forKey: K.eingang) }
    }

    /// Hängt ein Diktat an die Eingangs-Notiz (legt sie bei Bedarf angeheftet an).
    /// `false`, wenn der Text nicht in der Datei steht — der Aufrufer legt ihn
    /// dann zusätzlich in die Zwischenablage.
    func appendToInbox(_ text: String, now: Date = Date(), locale: Locale? = nil) -> Bool {
        // Nichts gesprochen: nichts anzuhängen, also auch nichts verloren — und
        // keine leere Eingangs-Notiz anlegen.
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return true }
        let sprache = locale ?? Locale(identifier: Loc.isGerman ? "de_DE" : "en_US")
        let note: Note
        if let vorhanden = store.notes.first(where: { $0.fileName.lowercased() == inboxFileName.lowercased() }) {
            note = vorhanden
        } else {
            let titel = (inboxFileName as NSString).deletingPathExtension
            guard case .saved(let neu) = store.create(title: titel, body: "", pinned: true) else { return false }
            inboxFileName = neu.fileName
            note = neu
        }
        let session = registry.acquire(note)
        defer { registry.release(session) }
        let anhang = NoteInbox.appendix(to: session.note.body, text: text, date: now, locale: sprache)
        guard session.insert(anhang, at: .end) else { return false }
        session.flush()
        // Konflikt beim Sichern: Der Text steht nur in der Konfliktdatei, davon
        // erführe der Nutzer sonst nichts — `false` legt ihn zusätzlich in die Zwischenablage.
        return !session.hasUnsavedText && session.conflictNotice == nil
    }

    func openInbox() {
        guard let note = store.notes.first(where: { $0.fileName.lowercased() == inboxFileName.lowercased() }) else { return }
        open(note.id, inNewTab: true)
    }

    // MARK: - Intern

    /// Setzt eine Sitzung in einen neuen Tab oder an die Stelle des aktiven
    /// (wenn gewünscht oder alle fünf belegt). Ersetzen nur, wenn der aktive
    /// danach gesichert ist.
    private func place(_ session: NoteEditorSession, inNewTab: Bool) -> Bool {
        if let aktiv = activeIndex, !(inNewTab && tabs.count < Self.maxTabs) {
            let alt = tabs[aktiv]
            alt.flush()
            guard !alt.hasUnsavedText else { return false }
            tabs[aktiv] = session
            registry.release(alt)
        } else {
            tabs.append(session)
            activeIndex = tabs.count - 1
        }
        merkeAngeheftet(session)
        persist()
        return true
    }

    private func dropTab(_ id: UUID) {
        guard let index = tabs.firstIndex(where: { $0.id == id }) else { return }
        tabs.remove(at: index)
        rueckeAuswahl(nachEntfernen: index)
        persist()
    }

    private func rueckeAuswahl(nachEntfernen index: Int) {
        guard let aktiv = activeIndex else { return }
        if tabs.isEmpty {
            activeIndex = nil
        } else if aktiv > index {
            activeIndex = aktiv - 1
        } else if aktiv == index {
            activeIndex = min(index, tabs.count - 1)
        }
    }

    private func merkeAngeheftet(_ session: NoteEditorSession) {
        if session.note.pinned { defaults.set(session.note.fileName, forKey: K.angeheftet) }
    }

    private func persist() {
        defaults.set(tabs.filter { !$0.note.isNew }.map(\.note.fileName), forKey: K.tabs)
        if let aktiv = active, !aktiv.note.isNew {
            defaults.set(aktiv.note.fileName, forKey: K.aktiv)
        } else {
            defaults.removeObject(forKey: K.aktiv)
        }
    }
}
