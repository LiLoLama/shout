import XCTest

@MainActor
final class NoteStoreTests: XCTestCase {

    private var u: NotizUmgebung!

    override func setUpWithError() throws {
        Loc.shared.apply("de")      // „Unbenannt“, „(Konflikt)“ auf Deutsch
        u = try NotizUmgebung()
    }

    override func tearDown() {
        u.aufraeumen()
        Loc.shared.apply("system")
        super.tearDown()
    }

    private func gesichert(_ ergebnis: NoteStore.SaveResult,
                           file: StaticString = #filePath, line: UInt = #line) throws -> Note {
        guard case .saved(let notiz) = ergebnis else {
            XCTFail("erwartet .saved, war \(ergebnis)", file: file, line: line)
            throw XCTSkip()
        }
        return notiz
    }

    // MARK: - Sichern und Titel

    func testLeereNeueNotizLegtNichtsAn() {
        let s = u.store()
        var n = Note.blank()
        n.body = "  \n "
        XCTAssertEqual(s.save(n), .skippedEmpty)
        XCTAssertEqual(u.dateien(), [])
    }

    func testNeueNotizBekommtTitelAusDemText() throws {
        let s = u.store()
        var n = Note.blank()
        n.body = "Milch und Kaffee kaufen"
        let notiz = try gesichert(s.save(n))
        XCTAssertEqual(notiz.fileName, "Milch und Kaffee kaufen.md")
        XCTAssertTrue(notiz.titleIsFixed)
        XCTAssertEqual(u.text("Milch und Kaffee kaufen.md"), "Milch und Kaffee kaufen")
        XCTAssertEqual(s.notes.map(\.id), [n.id])
    }

    /// Unter drei Wörtern wandert der Name mit, danach steht er fest.
    func testKurzerTitelWandertMitDannFest() throws {
        let s = u.store()
        var n = Note.blank()
        n.body = "Milch"
        var a = try gesichert(s.save(n))
        XCTAssertEqual(a.fileName, "Milch.md")
        XCTAssertFalse(a.titleIsFixed)

        a.body = "Milch und Brot"
        var b = try gesichert(s.save(a))
        XCTAssertEqual(b.fileName, "Milch und Brot.md")
        XCTAssertTrue(b.titleIsFixed)
        XCTAssertEqual(u.dateien(), ["Milch und Brot.md"])

        b.body = "Ganz anderer Anfang jetzt"
        XCTAssertEqual(try gesichert(s.save(b)).fileName, "Milch und Brot.md")
    }

    func testGleicherTitelBekommtZahl() throws {
        let s = u.store()
        var a = Note.blank(); a.body = "Idee für morgen"
        var b = Note.blank(); b.body = "Idee für morgen"
        XCTAssertEqual(try gesichert(s.save(a)).fileName, "Idee für morgen.md")
        XCTAssertEqual(try gesichert(s.save(b)).fileName, "Idee für morgen 2.md")
    }

    func testOhneVerwertbarenTitelHeisstUnbenannt() throws {
        let s = u.store()
        var n = Note.blank(); n.body = "# ***"
        XCTAssertEqual(try gesichert(s.save(n)).fileName, "Unbenannt.md")
    }

    func testFrontmatterWirdGeschrieben() throws {
        let s = u.store()
        var n = Note.blank(); n.body = "Ein Text mit Inhalt"
        _ = try gesichert(s.save(n))
        let roh = try XCTUnwrap(u.lies("Ein Text mit Inhalt.md"))
        XCTAssertTrue(roh.hasPrefix("---\ncreated: "))
        XCTAssertFalse(roh.contains("pinned"))
    }

    /// `created` aus Obsidian bleibt beim Sichern wörtlich stehen: ein reines
    /// Datum bleibt ein reines Datum, eine Uhrzeit ohne Sekunden bleibt so.
    func testCreatedAusObsidianBleibtWoertlich() throws {
        let werte = ["2026-10-05", "2026-10-05T14:32", "2026-10-05 14:32", "\"2026-10-05\""]
        for (i, wert) in werte.enumerated() {
            try u.schreibe("N\(i).md", "---\ncreated: \(wert)\ntags: [a]\n---\nText",
                           zeit: Date().addingTimeInterval(-60))
        }
        let s = u.store()
        for var n in s.notes {
            n.body = "Text, ergänzt"
            _ = try gesichert(s.save(n))
        }
        for (i, wert) in werte.enumerated() {
            XCTAssertEqual(u.lies("N\(i).md"), "---\ncreated: \(wert)\ntags: [a]\n---\nText, ergänzt")
        }
    }

    // MARK: - Lesen

    func testVorhandeneDateienWerdenGelesen() throws {
        try u.schreibe("Aus Obsidian.md", "---\ntags: [x]\n---\nHallo")
        try u.schreibe("Notiz.txt", "keine Notiz")
        try u.schreibe(".versteckt.md", "keine Notiz")
        try FileManager.default.createDirectory(at: u.ordner.appendingPathComponent("Anhänge"),
                                                withIntermediateDirectories: true)
        let s = u.store()
        XCTAssertEqual(s.notes.map(\.title), ["Aus Obsidian"])
        XCTAssertEqual(s.notes[0].body, "Hallo")
        XCTAssertEqual(s.notes[0].extraFrontmatter, ["tags: [x]"])
        XCTAssertTrue(s.notes[0].titleIsFixed)
    }

    /// Fremde Felder überleben das Speichern.
    func testFremdeFelderUeberlebenDasSpeichern() throws {
        try u.schreibe("Aus Obsidian.md", "---\ntags: [x]\n---\nHallo")
        let s = u.store()
        var n = s.notes[0]
        n.body = "Hallo Welt"
        _ = try gesichert(s.save(n))
        XCTAssertTrue(try XCTUnwrap(u.lies("Aus Obsidian.md")).contains("tags: [x]"))
    }

    func testNeueinlesenBehaeltIDUndUebernimmtAenderung() throws {
        try u.schreibe("X.md", "alt")
        let s = u.store()
        let id = s.notes[0].id
        try u.schreibe("X.md", "neu von außen", zeit: Date().addingTimeInterval(10))
        s.reload()
        XCTAssertEqual(s.notes[0].body, "neu von außen")
        XCTAssertEqual(s.notes[0].id, id)
    }

    func testICloudPlatzhalterWirdGelistet() throws {
        try u.schreibe(".Fern.md.icloud", "")
        let s = u.store()
        XCTAssertEqual(s.notes.map(\.title), ["Fern"])
        XCTAssertTrue(s.notes[0].isPlaceholder)
    }

    // MARK: - Ordner fehlt

    /// Die Vorgabe in „Dokumente“ entsteht erst beim ersten Sichern — wer die
    /// Seite nur ansieht, bekommt keinen leeren Ordner.
    func testVorgabeordnerEntstehtErstBeimSichern() throws {
        let vorgabe = u.wurzel.appendingPathComponent("Dokumente/shout Notizen", isDirectory: true)
        let s = u.store(ordner: vorgabe, createIfMissing: true)
        XCTAssertEqual(s.folderState, .ok)
        XCTAssertFalse(FileManager.default.fileExists(atPath: vorgabe.path))
        var n = Note.blank(); n.body = "Erste Notiz überhaupt"
        _ = try gesichert(s.save(n))
        XCTAssertTrue(FileManager.default.fileExists(atPath: vorgabe.appendingPathComponent("Erste Notiz überhaupt.md").path))
    }

    func testFehlenderOrdnerPuffertUndHoltNach() throws {
        let laufwerk = u.wurzel.appendingPathComponent("Laufwerk", isDirectory: true)
        let s = u.store(ordner: laufwerk)
        XCTAssertEqual(s.folderState, .unreachable)

        var n = Note.blank(); n.body = "Unterwegs notiert heute"
        guard case .buffered(let gepuffert) = s.save(n) else { return XCTFail("nicht gepuffert") }
        XCTAssertEqual(gepuffert.fileName, "Unterwegs notiert heute.md")
        XCTAssertTrue(FileManager.default.fileExists(atPath: u.puffer.appendingPathComponent("Unterwegs notiert heute.md").path))

        try FileManager.default.createDirectory(at: laufwerk, withIntermediateDirectories: true)
        s.reload()
        XCTAssertEqual(s.folderState, .ok)
        XCTAssertTrue(FileManager.default.fileExists(atPath: laufwerk.appendingPathComponent("Unterwegs notiert heute.md").path))
        XCTAssertEqual((try? FileManager.default.contentsOfDirectory(atPath: u.puffer.path)) ?? [], [])
        XCTAssertEqual(s.notes.map(\.id), [n.id])      // dieselbe Notiz, nicht eine neue
    }

    /// Hat in der Zwischenzeit niemand die Datei angefasst, ist die gepufferte
    /// Fassung einfach die neuere und ersetzt sie — ohne Konfliktdatei.
    func testUnveraendertesOriginalWirdErsetzt() throws {
        try u.schreibe("A.md", "alt", zeit: Date().addingTimeInterval(-60))
        let s = u.store()
        var n = s.notes[0]
        let weg = u.wurzel.appendingPathComponent("abgesteckt", isDirectory: true)
        try FileManager.default.moveItem(at: u.ordner, to: weg)

        n.body = "neu unterwegs"
        guard case .buffered = s.save(n) else { return XCTFail("nicht gepuffert") }

        try FileManager.default.moveItem(at: weg, to: u.ordner)
        s.reload()
        XCTAssertEqual(u.dateien(), ["A.md"])
        XCTAssertEqual(u.text("A.md"), "neu unterwegs")
    }

    /// Liegt dort inzwischen etwas anderes, wird die gepufferte Fassung zur
    /// Konfliktdatei. Nichts wird überschrieben.
    func testPufferKollisionWirdKonfliktdatei() throws {
        try FileManager.default.createDirectory(at: u.puffer, withIntermediateDirectories: true)
        try Data("---\ncreated: 2026-10-05\n---\naus dem Puffer".utf8)
            .write(to: u.puffer.appendingPathComponent("A.md"))
        try u.schreibe("A.md", "im Ordner")
        _ = u.store()
        XCTAssertEqual(u.dateien(), ["A (Konflikt).md", "A.md"])
        XCTAssertEqual(u.text("A.md"), "im Ordner")
        XCTAssertEqual(u.text("A (Konflikt).md"), "aus dem Puffer")
    }

    // MARK: - Puffer: Namen, Fehler, Laufwerke

    private func fremdeNotiz(_ name: String, _ text: String) -> Note {
        Note(id: UUID(), fileName: name, body: text, created: Date(), modified: Date(),
             pinned: false, extraFrontmatter: [], titleIsFixed: true)
    }

    private func puffer(_ name: String) -> String? {
        (try? String(contentsOf: u.puffer.appendingPathComponent(name), encoding: .utf8))
            .map { NoteFile.parse($0).body }
    }

    /// Neue Notiz gleichen Namens wie eine vorhandene: Beide Texte überleben.
    func testNeuePufferNotizUeberschreibtNichtDieVorhandene() throws {
        try u.schreibe("Einkaufsliste.md", "alt")
        let s = u.store()
        var vorhanden = s.notes[0]
        let weg = u.wurzel.appendingPathComponent("abgesteckt", isDirectory: true)
        try FileManager.default.moveItem(at: u.ordner, to: weg)

        var neu = Note.blank(); neu.body = "Einkaufsliste"
        guard case .buffered = s.save(neu) else { return XCTFail("neu nicht gepuffert") }
        vorhanden.body = "alt, jetzt ergänzt"
        guard case .buffered = s.save(vorhanden) else { return XCTFail("alt nicht gepuffert") }

        XCTAssertEqual(Set((try? FileManager.default.contentsOfDirectory(atPath: u.puffer.path)) ?? []).count, 2)
        XCTAssertEqual(puffer("Einkaufsliste.md"), "alt, jetzt ergänzt")
        XCTAssertEqual(puffer("Einkaufsliste 2.md"), "Einkaufsliste")

        try FileManager.default.moveItem(at: weg, to: u.ordner)
        s.reload()
        XCTAssertEqual(u.dateien(), ["Einkaufsliste 2.md", "Einkaufsliste.md"])
        XCTAssertEqual(u.text("Einkaufsliste.md"), "alt, jetzt ergänzt")
        XCTAssertEqual(u.text("Einkaufsliste 2.md"), "Einkaufsliste")
    }

    /// Gehört der Pufferdateiname einer anderen Notiz, wird die zweite Fassung
    /// unter einem Konfliktnamen gepuffert statt die erste zu überschreiben.
    func testPufferNameEinerAnderenNotizWirdKonfliktname() throws {
        let laufwerk = u.wurzel.appendingPathComponent("Laufwerk", isDirectory: true)
        let s = u.store(ordner: laufwerk)
        var erste = Note.blank(); erste.body = "Foo"
        guard case .buffered(let a) = s.save(erste) else { return XCTFail("erste nicht gepuffert") }
        XCTAssertEqual(a.fileName, "Foo.md")

        guard case .buffered(let b) = s.save(fremdeNotiz("Foo.md", "andere Fassung")) else {
            return XCTFail("zweite nicht gepuffert")
        }
        XCTAssertEqual(b.fileName, "Foo (Konflikt).md")
        XCTAssertEqual(puffer("Foo.md"), "Foo")
        XCTAssertEqual(puffer("Foo (Konflikt).md"), "andere Fassung")

        try FileManager.default.createDirectory(at: laufwerk, withIntermediateDirectories: true)
        s.reload()
        XCTAssertEqual((try? FileManager.default.contentsOfDirectory(atPath: laufwerk.path))?.sorted(),
                       ["Foo (Konflikt).md", "Foo.md"])
    }

    /// Ist auch der Puffer nicht beschreibbar, darf `save` nicht „gepuffert" melden.
    func testSchreibfehlerImPufferMeldetFailed() throws {
        let kaputt = u.wurzel.appendingPathComponent("Puffer-ist-eine-Datei")
        try Data("x".utf8).write(to: kaputt)
        let s = u.store(ordner: u.wurzel.appendingPathComponent("Laufwerk"), puffer: kaputt)
        XCTAssertEqual(s.folderState, .unreachable)
        var n = Note.blank(); n.body = "Das darf nicht verschwinden"
        XCTAssertEqual(s.save(n), .failed)
        XCTAssertEqual(s.notes, [])
    }

    /// Eine Datei, die aus dem Puffer zurückwandert und danach umbenannt wird,
    /// darf ihre ID nicht an eine spätere Notiz gleichen Namens vererben.
    func testRueckwandernderNameVererbtKeineID() throws {
        let laufwerk = u.wurzel.appendingPathComponent("Laufwerk", isDirectory: true)
        let s = u.store(ordner: laufwerk)
        var idee = Note.blank(); idee.body = "Idee"
        guard case .buffered(var gepuffert) = s.save(idee) else { return XCTFail("nicht gepuffert") }

        try FileManager.default.createDirectory(at: laufwerk, withIntermediateDirectories: true)
        gepuffert.body = "Idee für morgen früh"
        let umbenannt = try gesichert(s.save(gepuffert))
        XCTAssertEqual(umbenannt.fileName, "Idee für morgen früh.md")

        var zweite = Note.blank(); zweite.body = "Idee"
        _ = try gesichert(s.save(zweite))
        s.reload()
        XCTAssertEqual(s.notes.count, 2)
        XCTAssertEqual(Set(s.notes.map(\.id)).count, 2)
        XCTAssertEqual(s.notes.first { $0.fileName == "Idee.md" }?.id, zweite.id)
    }

    /// Ein ausgelagertes Ziel (`.A.md.icloud`) zählt als vorhanden.
    func testPufferGegenICloudPlatzhalterWirdKonfliktdatei() throws {
        try FileManager.default.createDirectory(at: u.puffer, withIntermediateDirectories: true)
        try Data("---\ncreated: 2026-10-05\n---\naus dem Puffer".utf8)
            .write(to: u.puffer.appendingPathComponent("A.md"))
        try u.schreibe(".A.md.icloud", "")
        _ = u.store()
        XCTAssertEqual(u.dateien(), [".A.md.icloud", "A (Konflikt).md"])
        XCTAssertEqual(u.text("A (Konflikt).md"), "aus dem Puffer")
    }

    /// Ist die gepufferte Fassung schon im Ordner angekommen (Entfernen der
    /// Pufferdatei war gescheitert), entsteht keine doppelte Konfliktkopie.
    func testIdentischePufferDateiErzeugtKeineKonfliktkopie() throws {
        let inhalt = "---\ncreated: 2026-10-05\n---\ngleicher Text"
        try FileManager.default.createDirectory(at: u.puffer, withIntermediateDirectories: true)
        try Data(inhalt.utf8).write(to: u.puffer.appendingPathComponent("A.md"))
        try u.schreibe("A.md", inhalt)
        let s = u.store()
        XCTAssertEqual(u.dateien(), ["A.md"])
        XCTAssertEqual(u.text("A.md"), "gleicher Text")
        XCTAssertEqual((try? FileManager.default.contentsOfDirectory(atPath: u.puffer.path)) ?? [], [])
        XCTAssertEqual(s.notes.count, 1)
    }

    /// Notizordner auf einem anderen Volume als der Puffer: neue Notiz.
    func testPufferWandertUeberLaufwerksgrenzeNeueNotiz() throws {
        let stick = try u.laufwerk()
        let ziel = stick.appendingPathComponent("Notizen", isDirectory: true)
        let s = u.store(ordner: ziel)
        var n = Note.blank(); n.body = "Auf dem Stick vergessen"
        guard case .buffered(let g) = s.save(n) else { return XCTFail("nicht gepuffert") }

        try FileManager.default.createDirectory(at: ziel, withIntermediateDirectories: true)
        s.reload()
        XCTAssertEqual((try? FileManager.default.contentsOfDirectory(atPath: u.puffer.path)) ?? [], [])
        let text = try String(contentsOf: ziel.appendingPathComponent("Auf dem Stick vergessen.md"), encoding: .utf8)
        XCTAssertEqual(NoteFile.parse(text).body, "Auf dem Stick vergessen")
        XCTAssertEqual(s.notes.map(\.id), [n.id])
        XCTAssertEqual(s.notes[0].modified, g.modified)     // mtime des Puffers übernommen
    }

    /// Dasselbe für eine vorhandene Notiz: unverändertes Original wird ersetzt.
    func testPufferWandertUeberLaufwerksgrenzeErsetztOriginal() throws {
        let stick = try u.laufwerk()
        let ziel = stick.appendingPathComponent("Notizen", isDirectory: true)
        try FileManager.default.createDirectory(at: ziel, withIntermediateDirectories: true)
        let datei = ziel.appendingPathComponent("A.md")
        try Data("alt".utf8).write(to: datei)
        try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(-60)],
                                              ofItemAtPath: datei.path)
        let s = u.store(ordner: ziel)
        var n = s.notes[0]
        let weg = stick.appendingPathComponent("abgesteckt", isDirectory: true)
        try FileManager.default.moveItem(at: ziel, to: weg)

        n.body = "neu unterwegs"
        guard case .buffered(let g) = s.save(n) else { return XCTFail("nicht gepuffert") }
        try FileManager.default.moveItem(at: weg, to: ziel)
        s.reload()

        XCTAssertEqual((try FileManager.default.contentsOfDirectory(atPath: ziel.path)).sorted(), ["A.md"])
        XCTAssertEqual(NoteFile.parse(try String(contentsOf: datei, encoding: .utf8)).body, "neu unterwegs")
        XCTAssertEqual((try? FileManager.default.contentsOfDirectory(atPath: u.puffer.path)) ?? [], [])
        XCTAssertEqual(s.notes[0].modified, g.modified)
    }
}
