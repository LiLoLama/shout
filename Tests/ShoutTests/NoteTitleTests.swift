import XCTest

/// Ein Dateiverwalter, der den Ordner nicht auflisten kann — wie bei einem
/// Ordner ohne Leserecht oder einem iCloud-Fehler.
private final class UnlesbarerDateiverwalter: FileManager {
    override func contentsOfDirectory(atPath path: String) throws -> [String] {
        throw CocoaError(.fileReadNoPermission)
    }
}

/// Wie aus dem Text ein Dateiname wird — und wie zwei Notizen sich nie
/// gegenseitig überschreiben.
final class NoteTitleTests: XCTestCase {

    private var ordner: URL!

    override func setUpWithError() throws {
        ordner = FileManager.default.temporaryDirectory
            .appendingPathComponent("shout-notiztitel-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: ordner, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: ordner)
    }

    private func lege(_ name: String) throws {
        try Data().write(to: ordner.appendingPathComponent(name))
    }

    // MARK: - Ableiten

    func testErsteFuenfWoerter() {
        XCTAssertEqual(NoteFile.deriveTitle(from: "Newsletter Idee für Oktober mit Umfrage und mehr"),
                       "Newsletter Idee für Oktober mit")
    }

    func testMarkdownZeichenFallenWeg() {
        XCTAssertEqual(NoteFile.deriveTitle(from: "## **Wichtig**: Termin"), "Wichtig Termin")
        XCTAssertEqual(NoteFile.deriveTitle(from: "- [ ] Milch kaufen"), "Milch kaufen")
        XCTAssertEqual(NoteFile.deriveTitle(from: "> Zitat hier"), "Zitat hier")
    }

    func testLeereZeilenUndBilderWerdenUebersprungen() {
        XCTAssertEqual(NoteFile.deriveTitle(from: "\n\n![](Anhänge/a.png)\nEchter Anfang"), "Echter Anfang")
    }

    /// „\r\n“ ist in Swift ein einzelnes Zeichen und trennt trotzdem Zeilen.
    func testWindowsZeilenumbruch() {
        XCTAssertEqual(NoteFile.deriveTitle(from: "Kurz\r\nzweite Zeile"), "Kurz")
        XCTAssertEqual(NoteFile.deriveTitle(from: "![](x.png)\r\nEchter Anfang"), "Echter Anfang")
    }

    func testNurLeerraumGibtNichts() {
        XCTAssertNil(NoteFile.deriveTitle(from: "  \n\n "))
        XCTAssertNil(NoteFile.deriveTitle(from: "# "))
    }

    // MARK: - Säubern

    /// Zeichen, die Pfade zerlegen, unter Windows unzulässig sind oder
    /// Obsidian-Links brechen (`# ^ [ ]`), kommen nicht in den Dateinamen.
    func testUnzulaessigeZeichen() {
        XCTAssertEqual(NoteFile.safeTitle("Team: Q3/Q4?"), "Team Q3-Q4")
        XCTAssertEqual(NoteFile.safeTitle("Ticket #42 [neu]"), "Ticket 42 neu")
        XCTAssertEqual(NoteFile.safeTitle("...versteckt"), "versteckt")
        XCTAssertEqual(NoteFile.safeTitle("Ende."), "Ende")
        XCTAssertNil(NoteFile.safeTitle(" ?: "))
    }

    /// Punkte und Leerzeichen am Rand fallen wiederholt weg, bis nichts mehr übrig ist.
    func testRandPunkteUndLeerraumWiederholt() {
        XCTAssertEqual(NoteFile.safeTitle("Hallo Welt ..."), "Hallo Welt")
        XCTAssertEqual(NoteFile.safeTitle(". Idee"), "Idee")
        XCTAssertEqual(NoteFile.safeTitle(" . . Idee . . "), "Idee")
        XCTAssertNil(NoteFile.safeTitle(" . . "))
    }

    /// Auch der Schnitt bei 60 Zeichen darf keinen Rand aus Leerzeichen oder Punkten lassen.
    func testSechzigZeichenSchnittOhneRand() {
        XCTAssertEqual(NoteFile.safeTitle(String(repeating: "a", count: 59) + " b"),
                       String(repeating: "a", count: 59))
        XCTAssertEqual(NoteFile.safeTitle(String(repeating: "a", count: 59) + ".b"),
                       String(repeating: "a", count: 59))
        XCTAssertEqual(NoteFile.safeTitle(String(repeating: "a", count: 57) + " . b"),
                       String(repeating: "a", count: 57))
    }

    func testSechzigZeichen() throws {
        let titel = try XCTUnwrap(NoteFile.safeTitle(String(repeating: "a", count: 100)))
        XCTAssertEqual(titel.count, 60)
    }

    func testUmlauteBleiben() {
        XCTAssertEqual(NoteFile.safeTitle("Jahresgespräch Müller"), "Jahresgespräch Müller")
    }

    /// Das Kästchen einer erledigten Aufgabe ist kein Wort.
    func testHakenKastenZaehltNicht() {
        XCTAssertEqual(NoteFile.wordCount("- [x] Milch"), 1)
        XCTAssertEqual(NoteFile.wordCount("- [X] Milch und Brot"), 3)
        XCTAssertEqual(NoteFile.wordCount("[x] [X] [ ]"), 0)
    }

    func testWoerterZaehlen() {
        XCTAssertEqual(NoteFile.wordCount("- [ ] Milch"), 1)
        XCTAssertEqual(NoteFile.wordCount("Milch und Kaffee"), 3)
        XCTAssertEqual(NoteFile.wordCount("# —  "), 0)
    }

    /// Der Zusatz muss auch bei langen Titeln vollständig stehen bleiben.
    func testKonflikttitelBleibtImRahmen() {
        let titel = NoteFile.conflictTitle(String(repeating: "b", count: 60), suffix: "(Konflikt)")
        XCTAssertTrue(titel.hasSuffix(" (Konflikt)"))
        XCTAssertLessThanOrEqual(titel.count, 60)
        XCTAssertEqual(NoteFile.conflictTitle("Idee", suffix: "(Konflikt)"), "Idee (Konflikt)")
    }

    // MARK: - iCloud-Platzhalter

    func testPlatzhalterName() {
        XCTAssertEqual(NoteFile.placeholderTarget(".Idee.md.icloud"), "Idee.md")
        XCTAssertNil(NoteFile.placeholderTarget("Idee.md"))
        XCTAssertNil(NoteFile.placeholderTarget(".Bild.png.icloud"))
    }

    // MARK: - Freier Name

    func testFreierNameBleibt() {
        XCTAssertEqual(NoteFile.freeFileName(for: "Idee", in: ordner), "Idee.md")
    }

    /// APFS unterscheidet standardmäßig nicht nach Groß- und Kleinschreibung —
    /// „idee.md" belegt also auch „Idee.md".
    func testBelegtOhneGrossKlein() throws {
        try lege("idee.md")
        XCTAssertEqual(NoteFile.freeFileName(for: "Idee", in: ordner), "Idee 2.md")
        try lege("Idee 2.md")
        XCTAssertEqual(NoteFile.freeFileName(for: "Idee", in: ordner), "Idee 3.md")
    }

    /// Die eigene Datei zählt nicht als belegt: So kann eine Notiz ihren Namen
    /// behalten oder nur die Schreibweise ändern.
    func testEigeneDateiZaehltNicht() throws {
        try lege("idee.md")
        XCTAssertEqual(NoteFile.freeFileName(for: "Idee", in: ordner, current: "idee.md"), "Idee.md")
    }

    /// Eine ausgelagerte iCloud-Datei belegt ihren Namen, auch wenn sie gerade
    /// nur als `.Name.md.icloud` daliegt.
    func testPlatzhalterBelegtDenNamen() throws {
        try lege(".Idee.md.icloud")
        XCTAssertEqual(NoteFile.freeFileName(for: "Idee", in: ordner), "Idee 2.md")
    }

    /// Lässt sich der Ordner nicht auflisten, gilt er nicht als leer: Jeder
    /// Kandidat wird einzeln geprüft.
    func testUnlesbarerOrdnerGiltNichtAlsLeer() throws {
        try lege("Idee.md")
        let verwalter = UnlesbarerDateiverwalter()
        XCTAssertEqual(NoteFile.freeFileName(for: "Idee", in: ordner, fileManager: verwalter), "Idee 2.md")
        try lege("Idee 2.md")
        try lege(".Idee 3.md.icloud")
        XCTAssertEqual(NoteFile.freeFileName(for: "Idee", in: ordner, fileManager: verwalter), "Idee 4.md")
        XCTAssertEqual(NoteFile.freeFileName(for: "Idee", in: ordner, current: "idee.md", fileManager: verwalter), "Idee.md")
    }
}
