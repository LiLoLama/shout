import Foundation

/// Die Notizen eines Ordners — und der einzige, der diesen Ordner anfasst.
/// Liest `.md`-Dateien, sichert atomar und verliert nie still einen Text:
/// Kollisionen werden zu Konfliktdateien, ein fehlender Ordner zu einem Puffer
/// in Application Support, der beim Wiederauftauchen zurückwandert.
@MainActor
final class NoteStore: ObservableObject {

    enum FolderState: Equatable { case ok, unreachable }

    enum SaveResult: Equatable {
        case saved(Note)
        /// Neue Notiz ohne Text — es wird keine Datei angelegt.
        case skippedEmpty
        /// Ordner nicht erreichbar; die Notiz liegt im Puffer.
        case buffered(Note)
        /// Von außen geändert, während hier ungesichert bearbeitet wurde.
        case conflict(external: Note, conflictFileName: String)
        /// Die Datei wurde von außen entfernt oder umbenannt.
        case missing
        /// Weder der Ordner noch der Puffer ließ sich beschreiben (z. B. Platte
        /// voll). Nichts wurde geschrieben — der Aufrufer muss den Text als
        /// ungesichert behalten und den Nutzer warnen.
        case failed
    }

    @Published private(set) var notes: [Note] = []
    @Published private(set) var folderState: FolderState = .ok
    private(set) var folder: URL

    private let bufferFolder: URL
    private let fileManager: FileManager
    private let watch: Bool
    /// In den Papierkorb legen; gibt die Adresse im Papierkorb zurück (Aufgabe 7).
    let trash: (URL) throws -> URL
    private var createIfMissing: Bool

    /// Dateiname → zuletzt gelesene oder geschriebene Fassung. Dateien mit
    /// unverändertem mtime werden beim Neueinlesen nicht erneut gelesen.
    var cache: [String: Note] = [:]
    /// Gepufferte Dateien: welche Notiz-ID dazugehört und welches mtime die
    /// Datei im Ordner hatte, bevor gepuffert wurde.
    private var bufferedIDs: [String: UUID] = [:]
    private var bufferedBase: [String: Date] = [:]
    /// Aus dem Puffer zurückgewandert: Die Datei behält beim Einlesen ihre ID.
    private var pendingIDs: [String: UUID] = [:]
    private var watcher: NoteFolderWatcher?
    private var retryTimer: Timer?

    init(folder: URL,
         bufferFolder: URL = StoreIO.directory().appendingPathComponent("Notizen-Puffer", isDirectory: true),
         fileManager: FileManager = .default,
         watch: Bool = true,
         createIfMissing: Bool? = nil,
         trash: ((URL) throws -> URL)? = nil) {
        self.folder = folder
        self.bufferFolder = bufferFolder
        self.fileManager = fileManager
        self.watch = watch
        self.createIfMissing = createIfMissing ?? NotesFolder.isDefault(folder)
        self.trash = trash ?? NoteStore.moveToTrash
        reload()
    }

    private static func moveToTrash(_ url: URL) throws -> URL {
        var ergebnis: NSURL?
        try FileManager.default.trashItem(at: url, resultingItemURL: &ergebnis)
        guard let imKorb = ergebnis as URL? else { throw CocoaError(.fileNoSuchFile) }
        return imKorb
    }

    // MARK: - Lesen

    func note(id: UUID) -> Note? { cache.values.first { $0.id == id } }

    func url(for note: Note) -> URL { folder.appendingPathComponent(note.fileName) }

    /// Wechselt den Ordner. Offene Sitzungen sichert der Aufrufer vorher.
    func setFolder(_ url: URL) {
        folder = url
        createIfMissing = NotesFolder.isDefault(url)
        cache = [:]
        pendingIDs = [:]
        watcher = nil
        publish()
        reload()
    }

    /// Liest den Ordner neu ein. Fehlt er, bleibt die Liste stehen — ein
    /// abgestecktes Laufwerk soll nicht aussehen, als wären die Notizen weg.
    func reload() {
        switch checkFolder(create: false) {
        case .unreachable:
            folderState = .unreachable
            watcher = nil
            scheduleRetry()
            return
        case .notYetCreated:
            folderState = .ok
            cache = [:]
            publish()
            return
        case .ready:
            folderState = .ok
            retryTimer?.invalidate()
            retryTimer = nil
            startWatchingIfNeeded()
        }

        flushBuffer()
        let namen = (try? fileManager.contentsOfDirectory(atPath: folder.path)) ?? []
        let vorhanden = Set(namen)
        var frisch: [String: Note] = [:]
        for name in namen {
            if let echt = NoteFile.placeholderTarget(name) {
                if !vorhanden.contains(echt) { frisch[echt] = placeholder(fileName: echt) }
                continue
            }
            guard isNoteFile(name, in: folder) else { continue }
            let mtime = modificationDate(of: folder.appendingPathComponent(name))
            if let bekannt = cache[name], !bekannt.isPlaceholder, bekannt.modified == mtime,
               pendingIDs[name] == nil {
                frisch[name] = bekannt
            } else if let gelesen = read(name, keepingID: pendingIDs.removeValue(forKey: name) ?? cache[name]?.id) {
                frisch[name] = gelesen
            }
        }
        cache = frisch
        publish()
    }

    // MARK: - Sichern

    /// Sichert eine Notiz. Neue Notizen ohne Text werden nicht angelegt.
    @discardableResult
    func save(_ input: Note) -> SaveResult {
        var note = input
        if note.isNew && note.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return .skippedEmpty
        }
        if note.isPlaceholder { return .saved(note) }     // nichts da, nichts zu schreiben
        guard checkFolder(create: true) == .ready else {
            folderState = .unreachable
            scheduleRetry()
            return buffer(note)
        }
        folderState = .ok
        startWatchingIfNeeded()
        flushBuffer()

        let alt = note.fileName
        var neu = targetFileName(for: note)
        if !note.isNew && neu != alt && !move(alt, to: neu) { neu = alt }
        note.fileName = neu
        if NoteFile.wordCount(note.body) >= NoteFile.fixedTitleWordCount { note.titleIsFixed = true }

        guard let mtime = write(note, to: folder.appendingPathComponent(note.fileName)) else {
            // Schreiben gescheitert: die Umbenennung zurücknehmen, damit Datei
            // und Notiz im Speicher denselben Namen behalten.
            if !input.isNew && note.fileName != alt && move(note.fileName, to: alt) { note.fileName = alt }
            return buffer(note)
        }
        note.modified = mtime
        // Ein Rückwanderer-Eintrag gilt nur für das nächste Einlesen; bleibt er
        // stehen, erbt später eine andere Datei desselben Namens fremde ID.
        pendingIDs[alt] = nil
        pendingIDs[note.fileName] = nil
        if alt != note.fileName { cache[alt] = nil }
        cache[note.fileName] = note
        publish()
        return .saved(note)
    }

    private func buffer(_ note: Note) -> SaveResult {
        guard let gepuffert = writeToBuffer(note) else { return .failed }
        return .buffered(gepuffert)
    }

    /// Dateiname nach der Titelregel: fest, sobald `titleIsFixed`; sonst aus den
    /// ersten Wörtern, ohne die eigene Datei als belegt zu zählen.
    private func targetFileName(for note: Note) -> String {
        if note.titleIsFixed && !note.isNew { return note.fileName }
        let titel = NoteFile.deriveTitle(from: note.body) ?? Loc.t("Unbenannt")
        if !note.isNew && note.title == titel { return note.fileName }
        return NoteFile.freeFileName(for: titel, in: folder,
                                     current: note.isNew ? nil : note.fileName,
                                     fileManager: fileManager)
    }

    // MARK: - Ordner

    enum FolderCheck { case ready, notYetCreated, unreachable }

    /// Die Vorgabe in „Dokumente“ wird erst beim ersten Sichern angelegt
    /// (`create: true`). Ein gewählter Ordner, der fehlt, wird nie angelegt.
    func checkFolder(create: Bool) -> FolderCheck {
        var istOrdner: ObjCBool = false
        if fileManager.fileExists(atPath: folder.path, isDirectory: &istOrdner) {
            return istOrdner.boolValue ? .ready : .unreachable
        }
        guard createIfMissing else { return .unreachable }
        guard create else { return .notYetCreated }
        do {
            try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
            return .ready
        } catch {
            NSLog("shout: Notizordner konnte nicht angelegt werden: \(error)")
            return .unreachable
        }
    }

    private func startWatchingIfNeeded() {
        guard watch, watcher == nil else { return }
        watcher = NoteFolderWatcher(url: folder) { [weak self] in
            MainActor.assumeIsolated { self?.reload() }
        }
    }

    /// Fehlt der Ordner, wird alle fünf Sekunden nachgesehen, ob er wieder da ist.
    private func scheduleRetry() {
        guard watch, retryTimer == nil else { return }
        retryTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] timer in
            // Ist der Store weg, darf der Timer nicht ewig weiterlaufen.
            guard let self else { timer.invalidate(); return }
            MainActor.assumeIsolated { self.reload() }
        }
    }

    // MARK: - Puffer

    /// Sichert in Application Support, solange der Ordner fehlt. Merkt sich, zu
    /// welcher Notiz die Datei gehört und wie die Datei im Ordner vorher aussah.
    /// `nil`, wenn auch der Puffer nicht beschreibbar ist — dann ist nichts
    /// geschrieben und der Aufrufer meldet `.failed`.
    func writeToBuffer(_ input: Note) -> Note? {
        var note = input
        do {
            try fileManager.createDirectory(at: bufferFolder, withIntermediateDirectories: true)
        } catch {
            NSLog("shout: Notizpuffer konnte nicht angelegt werden: \(error)")
            return nil
        }
        var basis: Date?
        if note.isNew {
            note.fileName = freeBufferName(for: NoteFile.deriveTitle(from: note.body) ?? Loc.t("Unbenannt"))
        } else if bufferNameBelongsToOther(note.fileName, than: note.id) {
            // Der Name im Puffer gehört einer anderen Notiz: nichts überschreiben,
            // die Fassung wandert als Konfliktdatei zurück.
            let titel = NoteFile.conflictTitle(note.title, suffix: Loc.t("(Konflikt)"))
            note.fileName = freeBufferName(for: titel)
        } else if bufferedBase[note.fileName] == nil && bufferedIDs[note.fileName] == nil {
            basis = input.modified
        }
        guard let mtime = write(note, to: bufferFolder.appendingPathComponent(note.fileName)) else { return nil }
        note.modified = mtime
        bufferedIDs[note.fileName] = note.id
        if let basis { bufferedBase[note.fileName] = basis }
        return note
    }

    /// Belegt im Puffer, in der Liste oder bei einer anderen gepufferten Notiz.
    private func freeBufferName(for title: String) -> String {
        let belegt = Set(cache.keys.map { $0.lowercased() } + bufferedIDs.keys.map { $0.lowercased() })
        var zahl = 1
        while true {
            let t = zahl == 1 ? title : "\(title) \(zahl)"
            let name = "\(t).\(NoteFile.fileExtension)"
            if !belegt.contains(name.lowercased()),
               NoteFile.freeFileName(for: t, in: bufferFolder, fileManager: fileManager) == name { return name }
            zahl += 1
        }
    }

    /// Liegt unter diesem Namen schon etwas im Puffer, das nicht zu `id` gehört?
    /// Eine Datei ohne Eintrag (Rest aus einer früheren Sitzung) zählt auch.
    private func bufferNameBelongsToOther(_ name: String, than id: UUID) -> Bool {
        if let fremd = bufferedIDs[name] { return fremd != id }
        return fileManager.fileExists(atPath: bufferFolder.appendingPathComponent(name).path)
    }

    /// Bringt Gepuffertes zurück in den Ordner. Unverändertes Original: wird
    /// ersetzt. Verändertes oder unbekanntes: unsere Fassung wird Konfliktdatei.
    /// Der Puffer liegt oft auf einem anderen Volume als der Ordner (USB-Stick,
    /// Netzlaufwerk) — dort scheitern `moveItem`/`replaceItemAt` mit „Cross-device
    /// link". Deshalb wird gelesen und atomar neu geschrieben; die Pufferdatei
    /// wird erst nach erfolgreichem Schreiben entfernt.
    private func flushBuffer() {
        guard let namen = try? fileManager.contentsOfDirectory(atPath: bufferFolder.path) else { return }
        for name in namen where isNoteFile(name, in: bufferFolder) {
            let quelle = bufferFolder.appendingPathComponent(name)
            let ziel = folder.appendingPathComponent(name)
            do {
                let daten = try Data(contentsOf: quelle)
                let platzhalter = folder.appendingPathComponent("." + name + ".icloud")
                var zielName = name
                var zurueck = true      // geht die ID an die Datei im Ordner zurück?
                if fileManager.fileExists(atPath: ziel.path) {
                    let basis = bufferedBase[name]
                    if basis == nil || modificationDate(of: ziel) != basis {
                        zielName = conflictFileName(for: name)
                        zurueck = false
                    }
                } else if fileManager.fileExists(atPath: platzhalter.path) {
                    // Ausgelagert bei iCloud: die Datei ist da, nur nicht lokal.
                    zielName = conflictFileName(for: name)
                    zurueck = false
                }
                let zielURL = folder.appendingPathComponent(zielName)
                try daten.write(to: zielURL, options: .atomic)
                // mtime der Pufferdatei übernehmen: so passt `Note.modified` der Sitzung.
                adoptModificationTime(of: quelle, onto: zielURL)
                if !zurueck {
                    NSLog("shout: Gepufferte Notiz \(name) kollidiert — gesichert als \(zielName)")
                } else if let id = bufferedIDs[name] {
                    pendingIDs[name] = id
                }
                try fileManager.removeItem(at: quelle)
                bufferedIDs[name] = nil
                bufferedBase[name] = nil
            } catch {
                NSLog("shout: Gepufferte Notiz \(name) konnte nicht zurück: \(error)")
            }
        }
    }

    /// Übernimmt das mtime nanosekundengenau. `setAttributes` mit einem `Date`
    /// rundet (Double) und träfe das mtime der Sitzung um Bruchteile daneben.
    private func adoptModificationTime(of quelle: URL, onto ziel: URL) {
        var st = stat()
        guard lstat(quelle.path, &st) == 0 else { return }
        var zeiten = [timespec(tv_sec: 0, tv_nsec: Int(UTIME_OMIT)), st.st_mtimespec]
        if utimensat(AT_FDCWD, ziel.path, &zeiten, 0) != 0 {
            NSLog("shout: mtime von \(ziel.lastPathComponent) konnte nicht gesetzt werden")
        }
    }

    private func conflictFileName(for name: String) -> String {
        let titel = NoteFile.conflictTitle((name as NSString).deletingPathExtension,
                                           suffix: Loc.t("(Konflikt)"))
        return NoteFile.freeFileName(for: titel, in: folder, fileManager: fileManager)
    }

    // MARK: - Dateien

    private func isNoteFile(_ name: String, in ordner: URL) -> Bool {
        guard !name.hasPrefix("."),
              (name as NSString).pathExtension.lowercased() == NoteFile.fileExtension else { return false }
        var istOrdner: ObjCBool = false
        return fileManager.fileExists(atPath: ordner.appendingPathComponent(name).path,
                                      isDirectory: &istOrdner) && !istOrdner.boolValue
    }

    func read(_ name: String, keepingID id: UUID?) -> Note? {
        let url = folder.appendingPathComponent(name)
        // mtime vor dem Inhalt: Schreibt jemand dazwischen, ist die Notiz eher
        // „zu alt" (wird neu gelesen) als „zu neu" (Änderung ginge unter).
        let werte = try? url.resourceValues(forKeys: [.contentModificationDateKey, .creationDateKey])
        guard let data = try? Data(contentsOf: url), let text = String(data: data, encoding: .utf8) else {
            NSLog("shout: Notiz \(name) ist nicht lesbar (kein UTF-8?) — übersprungen.")
            return nil
        }
        let parsed = NoteFile.parse(text)
        return Note(id: id ?? UUID(), fileName: name, body: parsed.body,
                    created: parsed.created ?? werte?.creationDate ?? Date(),
                    modified: werte?.contentModificationDate ?? .distantPast,
                    pinned: parsed.pinned, extraFrontmatter: parsed.extraFrontmatter,
                    titleIsFixed: true)
    }

    /// Ausgelagert von iCloud: Eintrag ohne Inhalt, der Download wird angestoßen.
    private func placeholder(fileName: String) -> Note {
        let url = folder.appendingPathComponent(fileName)
        try? fileManager.startDownloadingUbiquitousItem(at: url)
        let platzhalter = folder.appendingPathComponent("." + fileName + ".icloud")
        return Note(id: cache[fileName]?.id ?? UUID(), fileName: fileName, body: "",
                    created: Date(), modified: modificationDate(of: platzhalter),
                    pinned: false, extraFrontmatter: [], titleIsFixed: true, isPlaceholder: true)
    }

    /// Schreibt atomar und gibt das neue mtime zurück (nil bei Fehler).
    func write(_ note: Note, to url: URL) -> Date? {
        let text = NoteFile.serialize(body: note.body, created: note.created,
                                      pinned: note.pinned, extraFrontmatter: note.extraFrontmatter)
        do {
            try Data(text.utf8).write(to: url, options: .atomic)
        } catch {
            NSLog("shout: Notiz \(url.lastPathComponent) konnte nicht gesichert werden: \(error)")
            return nil
        }
        return modificationDate(of: url)
    }

    /// Benennt im Ordner um. Ändert sich nur die Schreibweise, ist es auf APFS
    /// dieselbe Datei; `moveItem` lehnt dann ab, `rename(2)` kann es.
    func move(_ alt: String, to neu: String) -> Bool {
        let von = folder.appendingPathComponent(alt)
        let nach = folder.appendingPathComponent(neu)
        if alt.lowercased() == neu.lowercased() {
            // Auf einem Volume mit Groß-/Kleinschreibung kann `nach` eine andere,
            // vorhandene Datei sein — `rename(2)` würde sie überschreiben.
            if fileManager.fileExists(atPath: nach.path) {
                let a = try? von.resourceValues(forKeys: [.fileResourceIdentifierKey]).fileResourceIdentifier
                let b = try? nach.resourceValues(forKeys: [.fileResourceIdentifierKey]).fileResourceIdentifier
                guard let a, let b, a.isEqual(b) else { return false }
            }
            return Darwin.rename(von.path, nach.path) == 0
        }
        do {
            try fileManager.moveItem(at: von, to: nach)
            return true
        } catch {
            NSLog("shout: Notiz konnte nicht umbenannt werden: \(error)")
            return false
        }
    }

    func modificationDate(of url: URL) -> Date {
        var frisch = url
        frisch.removeAllCachedResourceValues()
        return (try? frisch.resourceValues(forKeys: [.contentModificationDateKey]))?
            .contentModificationDate ?? .distantPast
    }

    func publish() {
        let sortiert = NoteSearch.sorted(Array(cache.values))
        if sortiert != notes { notes = sortiert }
    }
}
