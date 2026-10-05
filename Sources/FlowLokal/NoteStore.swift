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
        /// Nichts wurde geschrieben — der Aufrufer muss den Text als ungesichert
        /// behalten und den Nutzer warnen. Gründe: Weder der Ordner noch der
        /// Puffer ließ sich beschreiben (z. B. Platte voll), die Konfliktdatei
        /// ließ sich nicht schreiben, oder die von außen geänderte Datei war
        /// nicht lesbar und bleibt deshalb unangetastet.
        case failed
    }

    @Published private(set) var notes: [Note] = []
    @Published private(set) var folderState: FolderState = .ok
    /// Nach jedem Umbenennen über `rename(_:to:)`: alter und neuer Dateiname.
    /// Das Panel folgt so der umbenannten Eingangs-Notiz.
    var onRename: ((String, String) -> Void)?
    /// Für diese Platzhalter wurde der iCloud-Download schon angestoßen.
    private var angestosseneDownloads = Set<String>()
    /// Gepufferter Text einer vorhandenen Notiz, der als Konfliktdatei in den
    /// Ordner zurückkam (Notiz-ID → Name der Konfliktdatei). Die Sitzung der
    /// Notiz zeigt den Hinweis und quittiert mit `acknowledgeReturnedConflict`.
    @Published private(set) var returnedAsConflict: [UUID: String] = [:]
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
    /// Pufferdateien, deren Konfliktdatei schon geschrieben ist (Puffername →
    /// Konfliktdatei), deren Aufräumen aber noch aussteht. Ein weiterer Versuch
    /// schreibt dann keine zweite Kopie und meldet die Rückkehr nicht noch einmal.
    private var writtenConflicts: [String: String] = [:]
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

    /// Die Sitzung hat den Hinweis auf die zurückgekehrte Konfliktdatei gezeigt.
    func acknowledgeReturnedConflict(_ id: UUID) {
        returnedAsConflict[id] = nil
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
        angestosseneDownloads = []
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

        if !note.isNew {
            let url = url(for: note)
            guard fileManager.fileExists(atPath: url.path) else { return .missing }
            if modificationDate(of: url) != note.modified {
                // Von außen angefasst, aber nicht lesbar (kein UTF-8, E/A-Fehler,
                // halb synchronisiert): nichts schreiben. Die Fremddatei bleibt
                // wie sie ist, unser Text bleibt beim Aufrufer ungesichert.
                guard let extern = read(note.fileName, keepingID: note.id) else { return .failed }
                if extern.body != note.body {
                    return resolveConflict(mine: note, external: extern)
                }
                // Nur Frontmatter geändert: Der Editor bearbeitet es nicht, also
                // gilt die Fassung von der Platte (Tags aus Obsidian, Anheften auf
                // einem anderen Mac). Ein bewusstes Anheften geht über `setPinned`,
                // das bei neuem mtime vorher neu einliest.
                note.extraFrontmatter = extern.extraFrontmatter
                note.pinned = extern.pinned
                note.created = extern.created
                note.createdRaw = extern.createdRaw
            }
        }

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

    /// Beide Seiten haben geändert. Die eigene Fassung wird daneben gesichert,
    /// die Datei behält die Fassung von außen — keine gewinnt still.
    /// Scheitert das Schreiben der Konfliktdatei, existiert unser Text sonst
    /// nirgends: dann `.failed`, damit der Aufrufer ihn als ungesichert behält.
    /// `freeFileName` liefert einen freien Namen, die Konfliktdatei überschreibt
    /// also nie eine vorhandene Datei.
    private func resolveConflict(mine: Note, external: Note) -> SaveResult {
        let titel = NoteFile.conflictTitle(mine.title, suffix: Loc.t("(Konflikt)"))
        let name = NoteFile.freeFileName(for: titel, in: folder, fileManager: fileManager)
        guard write(mine, to: folder.appendingPathComponent(name)) != nil else { return .failed }
        reload()
        return .conflict(external: note(id: mine.id) ?? external, conflictFileName: name)
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
        watcher = NoteFolderWatcher(url: folder, onPaths: { [weak self] pfade in
            MainActor.assumeIsolated {
                guard let self, NoteFolderWatcher.concernsFolder(pfade, folder: self.folder) else { return }
                self.reload()
            }
        })
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
        // Neuer Inhalt unter diesem Namen: Eine früher geschriebene Konfliktdatei
        // ist nicht mehr seine Kopie.
        writtenConflicts[note.fileName] = nil
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
    /// wird erst entfernt, wenn die Zieldatei und ihr Ordner auf der Platte
    /// angekommen sind (`F_FULLFSYNC`). Scheitert das, bleibt der Puffer liegen.
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
                var schonGeschrieben = false
                if fileManager.fileExists(atPath: ziel.path) {
                    let basis = bufferedBase[name]
                    if basis == nil || modificationDate(of: ziel) != basis {
                        if (try? Data(contentsOf: ziel)) == daten {
                            // Schon angekommen (z. B. scheiterte das Entfernen der
                            // Pufferdatei beim letzten Mal): keine Kopie, nur aufräumen.
                            try makeDurable(ziel)
                            try fileManager.removeItem(at: quelle)
                            bufferedIDs[name] = nil
                            bufferedBase[name] = nil
                            continue
                        }
                        (zielName, schonGeschrieben) = conflictTarget(for: name, data: daten)
                        zurueck = false
                    }
                } else if fileManager.fileExists(atPath: platzhalter.path) {
                    // Ausgelagert bei iCloud: die Datei ist da, nur nicht lokal.
                    (zielName, schonGeschrieben) = conflictTarget(for: name, data: daten)
                    zurueck = false
                }
                let zielURL = folder.appendingPathComponent(zielName)
                if !schonGeschrieben {
                    try daten.write(to: zielURL, options: .atomic)
                    // mtime der Pufferdatei übernehmen: so passt `Note.modified` der Sitzung.
                    adoptModificationTime(of: quelle, onto: zielURL)
                }
                try makeDurable(zielURL)
                if !zurueck {
                    // Nur beim ersten Mal melden: Ein weiterer Versuch räumt bloß auf.
                    if writtenConflicts[name] == nil {
                        NSLog("shout: Gepufferte Notiz \(name) kollidiert — gesichert als \(zielName)")
                        writtenConflicts[name] = zielName
                        if let id = bufferedIDs[name] {
                            if note(id: id) == nil {
                                // Neue Notiz, nie im Ordner gewesen: Ihr Text ist ganz da,
                                // nur unter anderem Namen. Die Sitzung folgt ihm — sonst
                                // läse ihr nächstes Sichern die fremde Datei unter ihrer ID.
                                pendingIDs[zielName] = id
                            } else {
                                // Vorhandene Notiz: Die Sitzung bleibt bei der Datei im
                                // Ordner und sagt, wo ihre Fassung liegt.
                                returnedAsConflict[id] = zielName
                            }
                        }
                    }
                } else if let id = bufferedIDs[name] {
                    pendingIDs[name] = id
                }
                try fileManager.removeItem(at: quelle)
                bufferedIDs[name] = nil
                bufferedBase[name] = nil
                writtenConflicts[name] = nil
            } catch {
                NSLog("shout: Gepufferte Notiz \(name) konnte nicht zurück: \(error)")
            }
        }
    }

    /// Zwingt Datei und Ordner auf die Platte. `F_FULLFSYNC` leert auch den
    /// Schreibcache des Laufwerks; wo es nicht geht (z. B. Netzlaufwerke), bleibt
    /// `fsync`. Wirft, wenn das für die Datei scheitert — dann darf der Puffer nicht weg.
    private func makeDurable(_ datei: URL) throws {
        try sync(path: datei.path)
        // Der Ordner-Sync ist nur Bemühen: Manche Netzlaufwerke lehnen fsync auf
        // Verzeichnissen ab. Dort bliebe sonst der Puffer für immer liegen, obwohl
        // die Datei selbst schon sicher geschrieben ist.
        do {
            try sync(path: datei.deletingLastPathComponent().path)
        } catch {
            NSLog("shout: Ordner-Sync für \(datei.lastPathComponent) nicht möglich: \(error)")
        }
    }

    private func sync(path: String) throws {
        let fd = open(path, O_RDONLY)
        guard fd >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        defer { close(fd) }
        if fcntl(fd, F_FULLFSYNC) == -1 && fsync(fd) == -1 {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
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

    /// Wohin eine kollidierende Pufferdatei kommt. Liegt sie schon byte-gleich als
    /// „X (Konflikt).md“, „X (Konflikt) 2.md“ … im Ordner, wurde sie beim letzten
    /// Mal geschrieben und nur das Aufräumen (Sync, Entfernen) scheiterte: dann
    /// diese Datei, ohne neu zu schreiben. Sonst ein freier Konfliktname.
    private func conflictTarget(for name: String, data: Data) -> (name: String, written: Bool) {
        let titel = NoteFile.conflictTitle((name as NSString).deletingPathExtension,
                                           suffix: Loc.t("(Konflikt)"))
        let gleich = { (kandidat: String) in
            (try? Data(contentsOf: self.folder.appendingPathComponent(kandidat))) == data
        }
        if let bekannt = writtenConflicts[name], gleich(bekannt) { return (bekannt, true) }
        let praefix = titel.lowercased()
        let namen = ((try? fileManager.contentsOfDirectory(atPath: folder.path)) ?? []).sorted()
        for kandidat in namen where (kandidat as NSString).pathExtension.lowercased() == NoteFile.fileExtension {
            let ohne = (kandidat as NSString).deletingPathExtension.lowercased()
            let istKonfliktname = ohne == praefix
                || (ohne.hasPrefix(praefix + " ") && Int(ohne.dropFirst(praefix.count + 1)) != nil)
            if istKonfliktname, gleich(kandidat) { return (kandidat, true) }
        }
        return (NoteFile.freeFileName(for: titel, in: folder, fileManager: fileManager), false)
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
                    titleIsFixed: true, createdRaw: parsed.createdRaw)
    }

    /// Ausgelagert von iCloud: Eintrag ohne Inhalt, der Download wird angestoßen.
    private func placeholder(fileName: String) -> Note {
        let url = folder.appendingPathComponent(fileName)
        if angestosseneDownloads.insert(fileName).inserted {
            try? fileManager.startDownloadingUbiquitousItem(at: url)
        }
        let platzhalter = folder.appendingPathComponent("." + fileName + ".icloud")
        return Note(id: cache[fileName]?.id ?? UUID(), fileName: fileName, body: "",
                    created: Date(), modified: modificationDate(of: platzhalter),
                    pinned: false, extraFrontmatter: [], titleIsFixed: true, isPlaceholder: true)
    }

    private func serialized(_ note: Note) -> String {
        NoteFile.serialize(body: note.body, created: note.created, createdRaw: note.createdRaw,
                           pinned: note.pinned, extraFrontmatter: note.extraFrontmatter)
    }

    enum ExclusiveWrite: Equatable {
        case written(Date)
        /// Unter diesem Namen liegt schon etwas — es wurde nichts angefasst.
        case exists
        case failed
    }

    /// Legt eine neue Datei an und überschreibt nie eine vorhandene: Der Text
    /// geht erst in eine versteckte Zwischendatei im selben Ordner und wird dann
    /// mit `RENAME_EXCL` an seinen Platz gebracht. Wo das Dateisystem das nicht
    /// kennt (manche Netzlaufwerke), bleibt die Prüfung unmittelbar davor.
    func writeExclusively(_ note: Note, to url: URL) -> ExclusiveWrite {
        let zwischen = url.deletingLastPathComponent()
            .appendingPathComponent(".shout-neu-\(UUID().uuidString).tmp")
        do {
            try Data(serialized(note).utf8).write(to: zwischen)
        } catch {
            NSLog("shout: Notiz \(url.lastPathComponent) konnte nicht gesichert werden: \(error)")
            return .failed
        }
        var fehler = renamex_np(zwischen.path, url.path, UInt32(RENAME_EXCL)) == 0 ? 0 : errno
        if fehler == ENOTSUP || fehler == EINVAL {
            if fileManager.fileExists(atPath: url.path) {
                fehler = EEXIST
            } else {
                fehler = Darwin.rename(zwischen.path, url.path) == 0 ? 0 : errno
            }
        }
        guard fehler == 0 else {
            try? fileManager.removeItem(at: zwischen)
            if fehler == EEXIST { return .exists }
            NSLog("shout: Notiz \(url.lastPathComponent) konnte nicht angelegt werden: \(String(cString: strerror(fehler)))")
            return .failed
        }
        return .written(modificationDate(of: url))
    }

    /// Schreibt atomar und gibt das neue mtime zurück (nil bei Fehler).
    func write(_ note: Note, to url: URL) -> Date? {
        let text = serialized(note)
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

// MARK: - Umbenennen, Anheften, Papierkorb

extension NoteStore {

    struct DeletedNote: Equatable {
        let id: UUID
        let fileName: String
        let trashURL: URL
    }

    /// Benennt um und hält den Titel danach fest. Gibt `nil` zurück, wenn der
    /// Name nach dem Säubern leer ist oder das Umbenennen scheitert.
    @discardableResult
    func rename(_ id: UUID, to raw: String) -> Note? {
        guard var note = note(id: id), !note.isPlaceholder,
              let titel = NoteFile.safeTitle(raw) else { return nil }
        // Die Liste kann hinter der Platte herhinken (Watcher-Verzögerung). Ein
        // neues mtime auf eine veraltete Fassung zu setzen ließe das nächste
        // Einlesen den alten Text für aktuell halten — deshalb zuerst die Datei
        // neu lesen (mit derselben ID), wenn das mtime nicht mehr passt.
        if modificationDate(of: url(for: note)) != note.modified {
            guard let frisch = read(note.fileName, keepingID: note.id) else { return nil }
            note = frisch
            cache[note.fileName] = note
        }
        let alterName = note.fileName
        let neu = NoteFile.freeFileName(for: titel, in: folder, current: note.fileName)
        if neu != note.fileName {
            guard move(note.fileName, to: neu) else { return nil }
            cache[note.fileName] = nil
            // `rename(2)` lässt das mtime unberührt: `modified` bleibt, was es war.
            note.fileName = neu
        }
        note.titleIsFixed = true
        cache[note.fileName] = note
        publish()
        if alterName != note.fileName { onRename?(alterName, note.fileName) }
        return note
    }

    /// Legt eine Notiz unter einem festen Titel an (die Eingangs-Notiz). Ist der
    /// Name belegt, wird es „Titel 2“. Ein leerer Text ist hier erlaubt.
    /// `.failed`, wenn der Ordner fehlt oder das Schreiben scheitert. Eine
    /// vorhandene Datei wird nie überschrieben: Taucht der Name zwischen Wahl und
    /// Schreiben doch noch auf, wird ein neuer gewählt.
    func create(title raw: String, body: String, pinned: Bool) -> SaveResult {
        guard let titel = NoteFile.safeTitle(raw) else { return .failed }
        guard checkFolder(create: true) == .ready else {
            folderState = .unreachable
            return .failed
        }
        folderState = .ok
        var note = Note.blank()
        note.body = body
        note.pinned = pinned
        note.titleIsFixed = true
        for _ in 0..<20 {
            note.fileName = NoteFile.freeFileName(for: titel, in: folder, fileManager: fileManager)
            switch writeExclusively(note, to: folder.appendingPathComponent(note.fileName)) {
            case .written(let mtime):
                note.modified = mtime
                cache[note.fileName] = note
                publish()
                return .saved(note)
            case .exists:
                continue
            case .failed:
                return .failed
            }
        }
        return .failed
    }

    /// Ändert nur `pinned` und sichert. Offene Sitzungen gehen über
    /// `NoteEditorSession.setPinned`, damit ungesicherter Text mitkommt.
    @discardableResult
    func setPinned(_ id: UUID, _ pinned: Bool) -> SaveResult? {
        guard var note = note(id: id), !note.isPlaceholder else { return nil }
        // Die Liste kann hinter der Platte herhinken (Watcher-Verzögerung). Wer
        // aus einer veralteten Fassung sichert, überschriebe die Änderung von
        // außen — deshalb zuerst neu einlesen, wenn das mtime nicht mehr passt.
        if modificationDate(of: url(for: note)) != note.modified {
            reload()
            guard let frisch = self.note(id: id) else { return nil }
            note = frisch
        }
        note.pinned = pinned
        return save(note)
    }

    /// In den Papierkorb, nicht endgültig — ein Versehen lässt sich zurückholen.
    func delete(_ id: UUID) -> DeletedNote? {
        guard let note = note(id: id), !note.isNew, !note.isPlaceholder else { return nil }
        do {
            let imKorb = try trash(url(for: note))
            cache[note.fileName] = nil
            publish()
            return DeletedNote(id: note.id, fileName: note.fileName, trashURL: imKorb)
        } catch {
            NSLog("shout: Notiz \(note.fileName) konnte nicht in den Papierkorb: \(error)")
            // Fehlt die Datei längst, soll auch ihr Eintrag aus der Liste verschwinden.
            reload()
            return nil
        }
    }

    /// Holt aus dem Papierkorb zurück — unter dem alten Namen oder, wenn der
    /// inzwischen vergeben ist, als „Name 2“. Überschreibt nie etwas: `moveItem`
    /// scheitert, wenn das Ziel doch existiert, und die Datei bleibt im Papierkorb.
    func undoDelete(_ deleted: DeletedNote) -> Note? {
        let titel = (deleted.fileName as NSString).deletingPathExtension
        let name = NoteFile.freeFileName(for: titel, in: folder)
        do {
            try fileManager.moveItem(at: deleted.trashURL, to: folder.appendingPathComponent(name))
        } catch {
            NSLog("shout: Notiz konnte nicht aus dem Papierkorb zurück: \(error)")
            return nil
        }
        // Die Notiz behält ihre ID — außer sie ist inzwischen anderweitig vergeben.
        if note(id: deleted.id) == nil { pendingIDs[name] = deleted.id }
        reload()
        return cache[name]
    }

    /// Legt eine Notiz neu an, deren Datei von außen entfernt wurde. Behält ID
    /// und Titel; ist der Name belegt, wird es „Titel 2“.
    func restore(_ input: Note) -> SaveResult {
        var note = input
        guard checkFolder(create: true) == .ready else {
            folderState = .unreachable
            scheduleRetry()
            // Der Dateiname bleibt: Er trägt den Titel, den der Nutzer kennt. Eine
            // leere Angabe ließe den Puffer einen Namen aus dem Text ableiten.
            return buffer(note)
        }
        folderState = .ok
        startWatchingIfNeeded()
        let titel = note.title.isEmpty ? (NoteFile.deriveTitle(from: note.body) ?? Loc.t("Unbenannt")) : note.title
        note.fileName = NoteFile.freeFileName(for: titel, in: folder)
        guard let mtime = write(note, to: folder.appendingPathComponent(note.fileName)) else {
            return buffer(note)
        }
        note.modified = mtime
        note.titleIsFixed = true
        // Ein veralteter Listeneintrag derselben Notiz, dessen Datei weg ist,
        // darf nicht neben der neuen Fassung stehen bleiben (zwei Einträge, eine ID).
        for (name, alt) in cache where alt.id == note.id && name != note.fileName
            && !fileManager.fileExists(atPath: folder.appendingPathComponent(name).path) {
            cache[name] = nil
        }
        // Lebt ein anderer Eintrag noch mit dieser ID (Originaldatei vorhanden oder
        // unter dem Namen neu aufgetaucht), bekommt er eine frische — die
        // wiederhergestellte Notiz behält ihre, damit der Editor sie wiederfindet.
        for (name, andere) in cache where andere.id == note.id && name != note.fileName {
            cache[name] = Note(id: UUID(), fileName: andere.fileName, body: andere.body,
                               created: andere.created, modified: andere.modified,
                               pinned: andere.pinned, extraFrontmatter: andere.extraFrontmatter,
                               titleIsFixed: andere.titleIsFixed, isPlaceholder: andere.isPlaceholder,
                               createdRaw: andere.createdRaw)
        }
        cache[note.fileName] = note
        publish()
        return .saved(note)
    }
}
