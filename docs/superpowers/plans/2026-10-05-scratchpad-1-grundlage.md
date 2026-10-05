# Scratchpad, Teil 1: Grundlage — Umsetzungsplan

> **Für agentische Ausführung:** ERFORDERLICHER UNTER-SKILL: `superpowers:subagent-driven-development` (empfohlen) oder `superpowers:executing-plans`, Aufgabe für Aufgabe. Die Schritte nutzen Checkbox-Syntax (`- [ ]`).

Entwurf: `docs/superpowers/specs/2026-10-05-scratchpad-design.md`
Dies ist **Plan 1 von 3**. Plan 2 (Panel, Tasten, Diktat-Routing, Eingang) und
Plan 3 (Ablegen, Transforms, Versionen, Bilder) bauen darauf auf.

**Ziel:** Notizen als Markdown-Dateien in einem wählbaren Ordner anlegen,
bearbeiten, suchen, anheften, umbenennen und löschen — auf einer neuen Seite
„Notizen“ im Dashboard, noch ohne schwebendes Panel.

**Architektur:** Reine Funktionen (`NoteFile`, `NoteSearch`) kennen das Format
und die Regeln. `NoteStore` ist der einzige, der den Ordner anfasst: Er liest,
sichert atomar, erkennt Änderungen von außen (FSEvents) und verliert nie still
einen Text (Konfliktdatei, Puffer bei fehlendem Ordner). `NoteEditorSession`
hält eine geöffnete Notiz und sichert eine Sekunde nach der letzten Eingabe.
`NoteEditorView` ist ein `NSTextView` mit `MarkdownHighlighter`. Die Seite
selbst (`NotesView`) hängt nur an `NotesPageModel`.

**Technik:** Swift 5.10, SwiftUI + AppKit (`NSTextView`, `NSTextStorage`),
CoreServices (FSEvents), XCTest, XcodeGen. Keine neuen Pakete.

## Globale Vorgaben

- **Umlaute immer als echtes UTF-8** — `ä ö ü Ä Ö Ü ß`, nie `ae`/`oe`/`ue`/`ss`.
  Ausnahme: Swift-Bezeichner in Tests folgen dem Projektbrauch (`testLoeschen…`).
- **Code, Kommentare, Commits und Oberfläche auf Deutsch**, wie im ganzen Projekt.
- **macOS 14** ist die Untergrenze (`project.yml`: `deploymentTarget macOS 14.0`).
  Keine API, die erst ab macOS 15 da ist.
- **Oberflächentexte gehen durch `Loc.t("deutscher Text")` / `Loc.f(…)`** und
  brauchen einen Eintrag in `Localization.english`
  (`Sources/FlowLokal/Localization.swift`, das Literal endet bei Z. 913). Zwei
  Fallen: Ein **doppelter Schlüssel im Wörterbuch-Literal stürzt zur Laufzeit
  ab**, und ein **falsches Anführungszeichen** lässt die Suche still ins
  Deutsche zurückfallen. Typografische Zeichen („…“, „ …“) im Schlüssel müssen im
  Aufruf exakt gleich geschrieben sein.
- **Jede getestete Datei aus `Sources/FlowLokal/` muss einzeln in die
  Quellenliste des Testziels** (`project.yml`, Abschnitt `ShoutTests:` ab
  Z. 327). Das Testziel zieht den Ordner nicht als Ganzes.
- **Nach jeder Änderung an `project.yml` und nach jeder neuen Datei:
  `xcodegen generate`**, sonst kennt das Xcode-Projekt die Datei nicht.
- **Kein Text geht still verloren** (Spec, Abschnitt 6). Wo eine Regel das nicht
  sicherstellt, ist es ein Fehler im Plan — melden, nicht umgehen.
- **Die App wird nicht als Debug-Build gestartet.** Geprüft wird über Tests und
  einen Kompilierlauf; sichtbare Änderungen gehen über ein echtes Release.
- Testbefehl (ganze Suite):
  ```bash
  cd /Users/liam/Developer/LIAM/flow-lokal && xcodebuild test -project FlowLokal.xcodeproj -scheme ShoutTests -destination 'platform=macOS,arch=arm64' -skipPackagePluginValidation -skipMacroValidation 2>&1 | tail -25
  ```
  Eine einzelne Testklasse: denselben Befehl mit
  `-only-testing:ShoutTests/<Klassenname>` vor `2>&1`.
- Kompilierlauf der App (ohne Signieren, ohne Start):
  ```bash
  cd /Users/liam/Developer/LIAM/flow-lokal && xcodebuild build -project FlowLokal.xcodeproj -scheme FlowLokal -configuration Debug -destination 'platform=macOS,arch=arm64' -skipPackagePluginValidation -skipMacroValidation CODE_SIGNING_ALLOWED=NO 2>&1 | tail -20
  ```

## Nicht in diesem Plan

Panel, globale Tasten, Diktat in Notizen, Eingangs-Notiz, Menüeintrag,
Hinweiskarte (Plan 2) · Ablegen, Transforms, Versionen, Bilder, Backup der neuen
Einstellungen (Plan 3). Der Editor bekommt hier noch keine Methode zum Einfügen
am Cursor; die kommt mit Plan 2.

---

## Dateiaufteilung

| Datei | Verantwortung |
|---|---|
| `Sources/FlowLokal/Note.swift` (neu) | Datentyp einer Notiz im Speicher. |
| `Sources/FlowLokal/NoteFile.swift` (neu) | Reine Funktionen: Frontmatter lesen/schreiben, Titel ableiten, Namen säubern, freier Dateiname, iCloud-Platzhalter. |
| `Sources/FlowLokal/NoteSearch.swift` (neu) | Reine Funktionen: Sortierung, Suche, Ausschnitt, Vorschau. |
| `Sources/FlowLokal/NotesFolder.swift` (neu) | Wo der Ordner liegt (UserDefaults, Vorgabe). |
| `Sources/FlowLokal/NoteFolderWatcher.swift` (neu) | FSEvents auf den Ordner. |
| `Sources/FlowLokal/NoteStore.swift` (neu) | Einziger Zugriff auf den Ordner: lesen, sichern, umbenennen, anheften, Papierkorb, Konflikt, Puffer. |
| `Sources/FlowLokal/NoteEditorSession.swift` (neu) | Eine geöffnete Notiz: Eingaben, verzögertes Sichern, Änderungen von außen. |
| `Sources/FlowLokal/NotesPageModel.swift` (neu) | Zustand der Seite: Suche, Auswahl, Löschen mit Rückgängig, Ordnerwechsel. |
| `Sources/FlowLokal/MarkdownHighlighter.swift` (neu) | Darstellung von Markdown im `NSTextStorage`, Text bleibt unverändert. |
| `Sources/FlowLokal/NoteEditorView.swift` (neu) | `NSViewRepresentable` um `NSTextView`. |
| `Sources/FlowLokal/NotesView.swift` (neu) | Seite „Notizen“. |
| `Sources/FlowLokal/DashboardView.swift` (ändern) | Tab, Seitenleiste, `switch`. |
| `Sources/FlowLokal/AppDelegate.swift` (ändern) | Modell anlegen, durchreichen, beim Schließen/Beenden sichern. |
| `Sources/FlowLokal/Localization.swift` (ändern) | Englische Einträge. |
| `Tests/ShoutTests/NotizUmgebung.swift` (neu) | Gemeinsame Test-Umgebung (Temp-Ordner, Store, Dateien). |
| `Tests/ShoutTests/NoteFileTests.swift`, `NoteTitleTests.swift`, `NoteSearchTests.swift`, `NotesFolderTests.swift`, `NoteFolderWatcherTests.swift`, `NoteStoreTests.swift`, `NoteStoreAktionenTests.swift`, `NoteStoreKonfliktTests.swift`, `NoteEditorSessionTests.swift`, `NotesPageModelTests.swift`, `MarkdownHighlighterTests.swift`, `LocalizationNotesTests.swift` (neu) | Tests. |
| `project.yml` (ändern) | Neue Dateien ins Testziel. |

---

### Aufgabe 1: `Note` und Frontmatter

**Dateien:**
- Neu: `Sources/FlowLokal/Note.swift`
- Neu: `Sources/FlowLokal/NoteFile.swift`
- Neu: `Tests/ShoutTests/NoteFileTests.swift`
- Ändern: `project.yml` (Quellenliste `ShoutTests`, nach `- path: Sources/FlowLokal/Abkuerzungsgedaechtnis.swift`)

**Schnittstellen:**
- Benutzt: nichts (nur `Foundation`)
- Liefert:
  - `struct Note: Identifiable, Equatable` mit `id: UUID` (let), `fileName`, `body`, `created`, `modified`, `pinned`, `extraFrontmatter: [String]`, `titleIsFixed`, `isPlaceholder = false`; berechnet `title: String`, `isNew: Bool`; `static func blank(now: Date = Date()) -> Note`
  - `enum NoteFile` mit `fileExtension = "md"`, `struct Parsed: Equatable { body, created: Date?, pinned, extraFrontmatter }`, `parse(_:) -> Parsed`, `serialize(body:created:pinned:extraFrontmatter:timeZone:) -> String`, `date(from:) -> Date?`, `string(from:timeZone:) -> String`

- [ ] **Schritt 1: Den fehlschlagenden Test schreiben**

`Tests/ShoutTests/NoteFileTests.swift`:

```swift
import XCTest

/// Das Dateiformat einer Notiz: Frontmatter oben, Markdown darunter.
/// Obsidian liest dieselben Dateien — fremde Felder dürfen nie verloren gehen.
final class NoteFileTests: XCTestCase {

    private let berlin = TimeZone(identifier: "Europe/Berlin")!
    private let utc = TimeZone(identifier: "UTC")!

    private func datum(_ text: String) -> Date { NoteFile.date(from: text)! }

    func testOhneFrontmatterIstAllesText() {
        let gelesen = NoteFile.parse("Einfach nur Text\nZweite Zeile")
        XCTAssertEqual(gelesen, .init(body: "Einfach nur Text\nZweite Zeile",
                                      created: nil, pinned: false, extraFrontmatter: []))
    }

    func testFrontmatterWirdGelesen() {
        let gelesen = NoteFile.parse("---\ncreated: 2026-10-05T14:32:00+02:00\npinned: true\n---\nText")
        XCTAssertEqual(gelesen.body, "Text")
        XCTAssertEqual(gelesen.created, datum("2026-10-05T12:32:00Z"))
        XCTAssertTrue(gelesen.pinned)
        XCTAssertEqual(gelesen.extraFrontmatter, [])
    }

    /// Kernregel für Obsidian: `tags`, `aliases` & Co. bleiben wörtlich und in
    /// ihrer Reihenfolge stehen — auch mehrzeilige Listen.
    func testUnbekannteFelderBleibenErhalten() {
        let roh = "---\ntags:\n  - idee\n  - shout\ncreated: 2026-10-05T14:32:00+02:00\naliases: [NL]\n---\nText"
        let gelesen = NoteFile.parse(roh)
        XCTAssertEqual(gelesen.extraFrontmatter, ["tags:", "  - idee", "  - shout", "aliases: [NL]"])

        let neu = NoteFile.serialize(body: gelesen.body, created: gelesen.created!, pinned: false,
                                     extraFrontmatter: gelesen.extraFrontmatter, timeZone: berlin)
        XCTAssertEqual(neu, "---\ncreated: 2026-10-05T14:32:00+02:00\ntags:\n  - idee\n  - shout\naliases: [NL]\n---\nText")
    }

    func testRundlauf() {
        let erstellt = datum("2026-10-05T14:32:00+02:00")
        let text = NoteFile.serialize(body: "# Titel\n\nText\n", created: erstellt, pinned: true,
                                      extraFrontmatter: ["tags: [a]"], timeZone: berlin)
        XCTAssertEqual(NoteFile.parse(text),
                       .init(body: "# Titel\n\nText\n", created: erstellt, pinned: true,
                             extraFrontmatter: ["tags: [a]"]))
    }

    /// Unter Windows bearbeitete Dateien kommen mit CRLF. Gelesen wird beides,
    /// geschrieben wird LF.
    func testCRLFWirdGelesen() {
        let gelesen = NoteFile.parse("---\r\npinned: true\r\n---\r\nA\r\nB")
        XCTAssertTrue(gelesen.pinned)
        XCTAssertEqual(gelesen.body, "A\nB")
    }

    func testPinnedFalseUndFehlend() {
        XCTAssertFalse(NoteFile.parse("---\npinned: false\n---\nx").pinned)
        XCTAssertFalse(NoteFile.parse("---\ncreated: 2026-10-05\n---\nx").pinned)
    }

    /// Obsidian schreibt Datumsfelder oft ohne Uhrzeit.
    func testNurDatumWieInObsidian() {
        XCTAssertNotNil(NoteFile.parse("---\ncreated: 2026-10-05\n---\nx").created)
    }

    /// Ein unlesbares Datum fällt weg und wird beim nächsten Speichern neu
    /// geschrieben — sonst stünde `created` danach doppelt in der Datei.
    func testKaputtesDatumFaelltWeg() {
        let gelesen = NoteFile.parse("---\ncreated: gestern\n---\nx")
        XCTAssertNil(gelesen.created)
        XCTAssertEqual(gelesen.extraFrontmatter, [])
    }

    /// Eine Trennlinie ohne Gegenstück ist kein Frontmatter, sondern Text.
    func testOhneSchlusslinieKeinFrontmatter() {
        let roh = "---\nNur eine Trennlinie am Anfang"
        XCTAssertEqual(NoteFile.parse(roh).body, roh)
    }

    func testNichtAngeheftetSchreibtKeinPinned() {
        let text = NoteFile.serialize(body: "x", created: datum("2026-10-05T12:00:00Z"),
                                      pinned: false, extraFrontmatter: [], timeZone: utc)
        XCTAssertEqual(text, "---\ncreated: 2026-10-05T12:00:00Z\n---\nx")
    }

    func testNeueNotizIstLeerUndNeu() {
        let notiz = Note.blank()
        XCTAssertTrue(notiz.isNew)
        XCTAssertEqual(notiz.title, "")
        var benannt = notiz
        benannt.fileName = "Idee 2.md"
        XCTAssertEqual(benannt.title, "Idee 2")
        XCTAssertFalse(benannt.isNew)
    }
}
```

- [ ] **Schritt 2: Dateien ins Testziel eintragen, Projekt erzeugen, Test laufen lassen**

In `project.yml` unter `ShoutTests: sources:` nach der Zeile
`      - path: Sources/FlowLokal/Abkuerzungsgedaechtnis.swift` einfügen:

```yaml
      # Scratchpad / Notizen: nur Foundation, AppKit und CoreServices.
      - path: Sources/FlowLokal/Note.swift
      - path: Sources/FlowLokal/NoteFile.swift
```

Dann leere Platzhalter anlegen, damit das Projekt erzeugt werden kann:

```bash
cd /Users/liam/Developer/LIAM/flow-lokal && touch Sources/FlowLokal/Note.swift Sources/FlowLokal/NoteFile.swift && xcodegen generate
```

Testbefehl mit `-only-testing:ShoutTests/NoteFileTests`.
Erwartet: Build-Fehler „cannot find 'NoteFile' in scope“.

- [ ] **Schritt 3: `Note` schreiben**

`Sources/FlowLokal/Note.swift`:

```swift
import Foundation

/// Eine Notiz im Speicher. Auf der Platte ist sie eine `.md`-Datei im
/// Notizordner; die `id` lebt nur zur Laufzeit und hält Editor und Liste
/// zusammen, auch wenn die Datei umbenannt wird.
struct Note: Identifiable, Equatable {
    let id: UUID
    /// „Newsletter-Idee Oktober.md“ — leer, solange die Notiz nie gesichert wurde.
    var fileName: String
    /// Der Text ohne Frontmatter.
    var body: String
    var created: Date
    /// mtime der Datei beim letzten Lesen oder Schreiben. Daran erkennt der
    /// Store, ob jemand anderes die Datei inzwischen geändert hat.
    var modified: Date
    var pinned: Bool
    /// Unbekannte Frontmatter-Zeilen (z. B. `tags` aus Obsidian), wörtlich.
    var extraFrontmatter: [String]
    /// Ab drei Wörtern steht der Dateiname fest; vorher wandert er mit dem Text.
    var titleIsFixed: Bool
    /// iCloud hat die Datei ausgelagert; der Inhalt ist noch nicht da.
    var isPlaceholder: Bool = false

    var title: String { (fileName as NSString).deletingPathExtension }
    var isNew: Bool { fileName.isEmpty }

    static func blank(now: Date = Date()) -> Note {
        Note(id: UUID(), fileName: "", body: "", created: now, modified: now,
             pinned: false, extraFrontmatter: [], titleIsFixed: false)
    }
}
```

- [ ] **Schritt 4: Frontmatter in `NoteFile` schreiben**

`Sources/FlowLokal/NoteFile.swift`:

```swift
import Foundation

/// Reine Funktionen rund um die Notizdatei. Kein Zustand, kein Dateizugriff
/// außer beim Suchen eines freien Namens.
enum NoteFile {

    static let fileExtension = "md"

    struct Parsed: Equatable {
        var body: String
        var created: Date?
        var pinned: Bool
        var extraFrontmatter: [String]
    }

    // MARK: - Frontmatter

    /// Zerlegt eine Datei in Frontmatter und Text. Gelesen werden nur `created`
    /// und `pinned`; alle anderen Zeilen wandern unverändert nach
    /// `extraFrontmatter`, damit Obsidian-Felder beim Speichern erhalten bleiben.
    static func parse(_ raw: String) -> Parsed {
        var text = raw.replacingOccurrences(of: "\r\n", with: "\n")
        if text.hasPrefix("\u{FEFF}") { text.removeFirst() }
        let ohne = Parsed(body: text, created: nil, pinned: false, extraFrontmatter: [])
        guard text.hasPrefix("---\n") else { return ohne }

        let rest = text.dropFirst(4)
        var lines: [Substring] = []
        var bodyStart: String.Index?
        var cursor = rest.startIndex
        while cursor < rest.endIndex {
            let lineEnd = rest[cursor...].firstIndex(of: "\n") ?? rest.endIndex
            let line = rest[cursor..<lineEnd]
            let next = lineEnd < rest.endIndex ? rest.index(after: lineEnd) : rest.endIndex
            if line == "---" {
                bodyStart = next
                break
            }
            lines.append(line)
            cursor = next
        }
        // Keine Schlusslinie: Die Striche am Anfang sind Text, kein Frontmatter.
        guard let bodyStart else { return ohne }

        var parsed = Parsed(body: String(rest[bodyStart...]), created: nil,
                            pinned: false, extraFrontmatter: [])
        for line in lines {
            if let value = value(of: "created", in: line) {
                // Unlesbar: Die Zeile fällt weg und wird beim Speichern neu geschrieben.
                parsed.created = date(from: value)
            } else if let value = value(of: "pinned", in: line) {
                parsed.pinned = value.lowercased() == "true"
            } else {
                parsed.extraFrontmatter.append(String(line))
            }
        }
        return parsed
    }

    /// Schreibt Frontmatter und Text. `created` steht immer da, `pinned` nur,
    /// wenn die Notiz angeheftet ist; danach die fremden Felder in ihrer Reihenfolge.
    static func serialize(body: String, created: Date, pinned: Bool,
                          extraFrontmatter: [String], timeZone: TimeZone = .current) -> String {
        var lines = ["---", "created: " + string(from: created, timeZone: timeZone)]
        if pinned { lines.append("pinned: true") }
        lines += extraFrontmatter
        lines.append("---")
        return lines.joined(separator: "\n") + "\n" + body
    }

    /// Nur Felder am Zeilenanfang — eingerückte Zeilen gehören zu einer Liste darüber.
    private static func value(of key: String, in line: Substring) -> String? {
        guard line.hasPrefix(key + ":") else { return nil }
        return line.dropFirst(key.count + 1)
            .trimmingCharacters(in: .whitespaces)
            .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
    }

    // MARK: - Datum

    /// ISO 8601 mit Zeitzone, mit Sekundenbruchteilen, ohne Zeitzone oder als
    /// reines Datum — so, wie Obsidian und andere Programme es schreiben.
    static func date(from value: String) -> Date? {
        let varianten: [ISO8601DateFormatter.Options] = [
            [.withInternetDateTime],
            [.withInternetDateTime, .withFractionalSeconds],
            [.withFullDate, .withTime, .withColonSeparatorInTime, .withDashSeparatorInDate],
            [.withFullDate],
        ]
        for optionen in varianten {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = optionen
            formatter.timeZone = .current
            if let date = formatter.date(from: value) { return date }
        }
        return nil
    }

    static func string(from date: Date, timeZone: TimeZone = .current) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        formatter.timeZone = timeZone
        return formatter.string(from: date)
    }
}
```

- [ ] **Schritt 5: Test laufen lassen**

Testbefehl mit `-only-testing:ShoutTests/NoteFileTests`.
Erwartet: `Executed 11 tests, with 0 failures`.

- [ ] **Schritt 6: Commit**

```bash
cd /Users/liam/Developer/LIAM/flow-lokal && git add project.yml Sources/FlowLokal/Note.swift Sources/FlowLokal/NoteFile.swift Tests/ShoutTests/NoteFileTests.swift FlowLokal.xcodeproj && git commit -m "Notizen: Datentyp und Frontmatter (Obsidian-Felder bleiben erhalten)"
```

---

### Aufgabe 2: Titel und Dateinamen

**Dateien:**
- Ändern: `Sources/FlowLokal/NoteFile.swift` (neuer Abschnitt am Ende des `enum`)
- Neu: `Tests/ShoutTests/NoteTitleTests.swift`

**Schnittstellen:**
- Benutzt: `NoteFile.fileExtension`
- Liefert (alle `static` in `NoteFile`):
  - `maxTitleLength = 60`, `titleWordLimit = 5`, `fixedTitleWordCount = 3`
  - `deriveTitle(from body: String) -> String?`
  - `cleanLine(_ line: Substring) -> String`
  - `safeTitle(_ raw: String) -> String?`
  - `wordCount(_ body: String) -> Int`
  - `conflictTitle(_ title: String, suffix: String) -> String`
  - `placeholderTarget(_ name: String) -> String?`
  - `freeFileName(for title: String, in folder: URL, current: String? = nil, fileManager: FileManager = .default) -> String`

- [ ] **Schritt 1: Den fehlschlagenden Test schreiben**

`Tests/ShoutTests/NoteTitleTests.swift`:

```swift
import XCTest

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

    func testSechzigZeichen() throws {
        let titel = try XCTUnwrap(NoteFile.safeTitle(String(repeating: "a", count: 100)))
        XCTAssertEqual(titel.count, 60)
    }

    func testUmlauteBleiben() {
        XCTAssertEqual(NoteFile.safeTitle("Jahresgespräch Müller"), "Jahresgespräch Müller")
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
    /// „idee.md“ belegt also auch „Idee.md“.
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
}
```

- [ ] **Schritt 2: Test laufen lassen**

Testbefehl mit `-only-testing:ShoutTests/NoteTitleTests` (erst `xcodegen generate`,
weil die Testdatei neu ist).
Erwartet: Build-Fehler „type 'NoteFile' has no member 'deriveTitle'“.

- [ ] **Schritt 3: Titelregeln schreiben**

In `Sources/FlowLokal/NoteFile.swift` direkt vor der letzten schließenden
Klammer `}` des `enum NoteFile` einfügen:

```swift

    // MARK: - Titel und Dateinamen

    static let maxTitleLength = 60
    static let titleWordLimit = 5
    /// Ab so vielen Wörtern steht der Dateiname einer neuen Notiz fest.
    static let fixedTitleWordCount = 3

    /// Titel aus den ersten Wörtern der ersten Zeile mit Inhalt. Bildzeilen
    /// zählen nicht — ein Dateiname „![](Anhänge-…“ hilft niemandem.
    static func deriveTitle(from body: String) -> String? {
        let erste = body.split(separator: "\n")
            .map(cleanLine)
            .first { !$0.isEmpty && !$0.hasPrefix("![") }
        guard let erste else { return nil }
        let woerter = erste.split(whereSeparator: \.isWhitespace).prefix(titleWordLimit)
        return safeTitle(woerter.joined(separator: " "))
    }

    /// Markdown-Zeichen am Zeilenanfang und Hervorhebungen fallen weg: Aus
    /// „## **Wichtig**: Termin“ wird „Wichtig: Termin“.
    static func cleanLine(_ line: Substring) -> String {
        var text = line.trimmingCharacters(in: .whitespaces)
        let marker = ["[ ]", "[x]", "[X]", "#", "-", "*", "+", ">"]
        var weiter = true
        while weiter {
            weiter = false
            for zeichen in marker where text.hasPrefix(zeichen) {
                text = String(text.dropFirst(zeichen.count)).trimmingCharacters(in: .whitespaces)
                weiter = true
            }
        }
        text.removeAll { "*_`".contains($0) }
        return text
    }

    /// Ein Dateiname, der überall taugt: keine Pfadzeichen, nichts, was Windows
    /// oder Obsidian-Links ablehnen, kein führender Punkt (versteckte Datei),
    /// kein Punkt am Ende, höchstens 60 Zeichen.
    static func safeTitle(_ raw: String) -> String? {
        var text = raw.replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: "\\", with: "-")
        text.removeAll { ":*\"<>|?#^[]".contains($0) }
        text = text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        while text.hasPrefix(".") { text.removeFirst() }
        text = String(text.prefix(maxTitleLength)).trimmingCharacters(in: .whitespaces)
        while text.hasSuffix(".") { text.removeLast() }
        return text.isEmpty ? nil : text
    }

    /// Wörter mit mindestens einem Buchstaben oder einer Ziffer. „- [ ]“ zählt nicht.
    static func wordCount(_ body: String) -> Int {
        body.split(whereSeparator: \.isWhitespace)
            .filter { $0.contains { $0.isLetter || $0.isNumber } }
            .count
    }

    /// „Titel (Konflikt)“ — gekürzt so, dass der Zusatz immer ganz dasteht.
    static func conflictTitle(_ title: String, suffix: String) -> String {
        let platz = max(maxTitleLength - suffix.count - 1, 1)
        return String(title.prefix(platz)).trimmingCharacters(in: .whitespaces) + " " + suffix
    }

    /// iCloud lagert „Idee.md“ als „.Idee.md.icloud“ aus. Gibt den echten Namen
    /// zurück, wenn es ein ausgelagerter Notizname ist.
    static func placeholderTarget(_ name: String) -> String? {
        guard name.hasPrefix("."), name.hasSuffix(".icloud") else { return nil }
        let innen = String(name.dropFirst().dropLast(".icloud".count))
        return (innen as NSString).pathExtension.lowercased() == fileExtension ? innen : nil
    }

    /// Freier Dateiname: „Titel.md“, sonst „Titel 2.md“, „Titel 3.md“ …
    /// `current` ist die eigene Datei und zählt nicht als belegt. Verglichen wird
    /// ohne Groß-/Kleinschreibung, wie APFS es standardmäßig tut.
    static func freeFileName(for title: String, in folder: URL, current: String? = nil,
                             fileManager: FileManager = .default) -> String {
        let namen = (try? fileManager.contentsOfDirectory(atPath: folder.path)) ?? []
        var belegt = Set<String>()
        for name in namen {
            belegt.insert(name.lowercased())
            if let echt = placeholderTarget(name) { belegt.insert(echt.lowercased()) }
        }
        if let current { belegt.remove(current.lowercased()) }

        var kandidat = "\(title).\(fileExtension)"
        var zahl = 2
        while belegt.contains(kandidat.lowercased()) {
            kandidat = "\(title) \(zahl).\(fileExtension)"
            zahl += 1
        }
        return kandidat
    }
```

- [ ] **Schritt 4: Test laufen lassen**

Testbefehl mit `-only-testing:ShoutTests/NoteTitleTests`.
Erwartet: `Executed 14 tests, with 0 failures`.

- [ ] **Schritt 5: Commit**

```bash
cd /Users/liam/Developer/LIAM/flow-lokal && git add Sources/FlowLokal/NoteFile.swift Tests/ShoutTests/NoteTitleTests.swift FlowLokal.xcodeproj && git commit -m "Notizen: Titel aus dem Text, sichere Dateinamen, freie Namen"
```

---

### Aufgabe 3: Suche, Sortierung, Vorschau

**Dateien:**
- Neu: `Sources/FlowLokal/NoteSearch.swift`
- Neu: `Tests/ShoutTests/NoteSearchTests.swift`
- Ändern: `project.yml` (nach `- path: Sources/FlowLokal/NoteFile.swift`)

**Schnittstellen:**
- Benutzt: `Note`, `NoteFile.cleanLine`
- Liefert:
  - `enum NoteSearch` mit `struct Snippet: Equatable { before, match, after: String }`
  - `struct Result: Equatable, Identifiable { note: Note; snippet: Snippet?; id: UUID }`
  - `sorted(_ notes: [Note]) -> [Note]` (angeheftet zuerst, dann neueste Änderung, dann Titel)
  - `filter(_ notes: [Note], query: String) -> [Result]`
  - `snippet(in text: String, around range: Range<String.Index>) -> Snippet`
  - `preview(_ body: String) -> String`

- [ ] **Schritt 1: Den fehlschlagenden Test schreiben**

`Tests/ShoutTests/NoteSearchTests.swift`:

```swift
import XCTest

final class NoteSearchTests: XCTestCase {

    private func notiz(_ titel: String, _ text: String, angeheftet: Bool = false,
                       alter sekunden: TimeInterval = 0) -> Note {
        Note(id: UUID(), fileName: titel + ".md", body: text,
             created: Date(timeIntervalSince1970: 0),
             modified: Date(timeIntervalSince1970: 1_000_000 - sekunden),
             pinned: angeheftet, extraFrontmatter: [], titleIsFixed: true)
    }

    func testAngehefteteZuerstDannNeueste() {
        let a = notiz("A", "", alter: 10)
        let b = notiz("B", "", alter: 0)
        let c = notiz("C", "", angeheftet: true, alter: 100)
        XCTAssertEqual(NoteSearch.sorted([a, b, c]).map(\.title), ["C", "B", "A"])
    }

    func testGleicheZeitNachTitel() {
        let b = notiz("B", ""), a = notiz("a", "")
        XCTAssertEqual(NoteSearch.sorted([b, a]).map(\.title), ["a", "B"])
    }

    func testLeereSucheZeigtAlles() {
        let ergebnis = NoteSearch.filter([notiz("A", "x"), notiz("B", "y")], query: "  ")
        XCTAssertEqual(ergebnis.count, 2)
        XCTAssertNil(ergebnis[0].snippet)
    }

    /// Eine zusammenhängende Wortfolge, ohne Groß-/Kleinschreibung und ohne
    /// Akzente — „cafe“ findet „Café“, aber „und cafe“ findet „Café und“ nicht.
    func testWortfolgeOhneGrossKleinUndAkzente() {
        let n = notiz("Einkauf", "Heute Café und Brötchen holen")
        XCTAssertEqual(NoteSearch.filter([n], query: "cafe UND").count, 1)
        XCTAssertEqual(NoteSearch.filter([n], query: "und cafe").count, 0)
        XCTAssertEqual(NoteSearch.filter([n], query: "brotchen").count, 1)
    }

    func testTrefferNurImTitel() {
        let ergebnis = NoteSearch.filter([notiz("Projekt Phoenix", "nichts")], query: "phoenix")
        XCTAssertEqual(ergebnis.count, 1)
        XCTAssertNil(ergebnis[0].snippet)
    }

    func testAusschnittMitKontext() throws {
        let text = String(repeating: "x", count: 100) + " Treffer " + String(repeating: "y", count: 100)
        let s = try XCTUnwrap(NoteSearch.filter([notiz("A", text)], query: "treffer")[0].snippet)
        XCTAssertEqual(s.match, "Treffer")
        XCTAssertTrue(s.before.hasPrefix("…"))
        XCTAssertEqual(s.before.count, 41)       // „…“ + 40 Zeichen
        XCTAssertTrue(s.after.hasSuffix("…"))
    }

    func testAusschnittAmAnfang() throws {
        let s = try XCTUnwrap(NoteSearch.filter([notiz("A", "Treffer am Anfang")], query: "treffer")[0].snippet)
        XCTAssertEqual(s.before, "")
        XCTAssertEqual(s.after, " am Anfang")
    }

    func testZeilenumbruecheImAusschnitt() throws {
        let s = try XCTUnwrap(NoteSearch.filter([notiz("A", "eins\nTreffer\nzwei")], query: "treffer")[0].snippet)
        XCTAssertEqual(s.before, "eins ")
        XCTAssertEqual(s.after, " zwei")
    }

    func testVorschau() {
        XCTAssertEqual(NoteSearch.preview("# Titel\n\n- [ ] Milch\nBrot"), "Titel Milch Brot")
        XCTAssertEqual(NoteSearch.preview(String(repeating: "a", count: 300)).count, 120)
    }
}
```

- [ ] **Schritt 2: Eintragen und Test laufen lassen**

In `project.yml` nach `      - path: Sources/FlowLokal/NoteFile.swift`:

```yaml
      - path: Sources/FlowLokal/NoteSearch.swift
```

```bash
cd /Users/liam/Developer/LIAM/flow-lokal && touch Sources/FlowLokal/NoteSearch.swift && xcodegen generate
```

Testbefehl mit `-only-testing:ShoutTests/NoteSearchTests`.
Erwartet: Build-Fehler „cannot find 'NoteSearch' in scope“.

- [ ] **Schritt 3: `NoteSearch` schreiben**

`Sources/FlowLokal/NoteSearch.swift`:

```swift
import Foundation

/// Suche und Reihenfolge der Notizliste. Rein: dieselben Notizen und dieselbe
/// Suche ergeben immer dasselbe — im Panel (Plan 2) wie auf der Seite.
enum NoteSearch {

    struct Snippet: Equatable {
        let before: String
        let match: String
        let after: String
    }

    struct Result: Equatable, Identifiable {
        let note: Note
        let snippet: Snippet?
        var id: UUID { note.id }
    }

    static let options: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive]
    /// Zeichen Kontext vor und nach dem Treffer.
    static let context = 40

    /// Angeheftete zuerst, dann die zuletzt geänderte, bei Gleichstand nach Titel.
    static func sorted(_ notes: [Note]) -> [Note] {
        notes.sorted { a, b in
            if a.pinned != b.pinned { return a.pinned }
            if a.modified != b.modified { return a.modified > b.modified }
            return a.title.localizedStandardCompare(b.title) == .orderedAscending
        }
    }

    /// Treffer im Text bekommen einen Ausschnitt; Treffer nur im Titel nicht.
    static func filter(_ notes: [Note], query raw: String) -> [Result] {
        let query = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let ordered = sorted(notes)
        guard !query.isEmpty else { return ordered.map { Result(note: $0, snippet: nil) } }
        return ordered.compactMap { note in
            if let range = note.body.range(of: query, options: options) {
                return Result(note: note, snippet: snippet(in: note.body, around: range))
            }
            if note.title.range(of: query, options: options) != nil {
                return Result(note: note, snippet: nil)
            }
            return nil
        }
    }

    static func snippet(in text: String, around range: Range<String.Index>) -> Snippet {
        let start = text.index(range.lowerBound, offsetBy: -context, limitedBy: text.startIndex) ?? text.startIndex
        let end = text.index(range.upperBound, offsetBy: context, limitedBy: text.endIndex) ?? text.endIndex
        func flach(_ teil: Substring) -> String { teil.replacingOccurrences(of: "\n", with: " ") }
        return Snippet(
            before: (start > text.startIndex ? "…" : "") + flach(text[start..<range.lowerBound]),
            match: String(text[range]),
            after: flach(text[range.upperBound..<end]) + (end < text.endIndex ? "…" : ""))
    }

    /// Zeilen ohne Markdown-Zeichen, hintereinander, höchstens 120 Zeichen.
    static func preview(_ body: String) -> String {
        let text = body.split(separator: "\n")
            .map(NoteFile.cleanLine)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        return String(text.prefix(120))
    }
}
```

- [ ] **Schritt 4: Test laufen lassen**

Testbefehl mit `-only-testing:ShoutTests/NoteSearchTests`.
Erwartet: `Executed 9 tests, with 0 failures`.

- [ ] **Schritt 5: Commit**

```bash
cd /Users/liam/Developer/LIAM/flow-lokal && git add project.yml Sources/FlowLokal/NoteSearch.swift Tests/ShoutTests/NoteSearchTests.swift FlowLokal.xcodeproj && git commit -m "Notizen: Suche ohne Akzente, Ausschnitt, Sortierung"
```

---

### Aufgabe 4: Wo der Ordner liegt

**Dateien:**
- Neu: `Sources/FlowLokal/NotesFolder.swift`
- Neu: `Tests/ShoutTests/NotesFolderTests.swift`
- Ändern: `project.yml` (nach `- path: Sources/FlowLokal/NoteSearch.swift`)

**Schnittstellen:**
- Benutzt: `Loc.isGerman`
- Liefert (`@MainActor enum NotesFolder`):
  - `defaultsKey = "notesFolderPath"`
  - `defaultURL(german: Bool = Loc.isGerman, home: URL = …) -> URL`
  - `current(defaults: UserDefaults = .standard, german: Bool = Loc.isGerman, home: URL = …) -> URL`
  - `set(_ url: URL, defaults: UserDefaults = .standard)`
  - `isDefault(_ url: URL, home: URL = …) -> Bool`

- [ ] **Schritt 1: Den fehlschlagenden Test schreiben**

`Tests/ShoutTests/NotesFolderTests.swift`:

```swift
import XCTest

@MainActor
final class NotesFolderTests: XCTestCase {

    private var suite: String!
    private var defaults: UserDefaults!
    private let home = URL(fileURLWithPath: "/Users/test", isDirectory: true)

    override func setUp() {
        super.setUp()
        suite = "shout-notesfolder-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suite)
        super.tearDown()
    }

    func testVorgabe() {
        XCTAssertEqual(NotesFolder.defaultURL(german: true, home: home).path, "/Users/test/Documents/shout Notizen")
        XCTAssertEqual(NotesFolder.defaultURL(german: false, home: home).path, "/Users/test/Documents/shout Notes")
    }

    /// Die Vorgabe wird beim ersten Aufruf festgeschrieben. Sonst hieße der
    /// Ordner nach einem Sprachwechsel anders, und die Notizen wären scheinbar weg.
    func testErsterAufrufSchreibtVorgabeFest() {
        let deutsch = NotesFolder.current(defaults: defaults, german: true, home: home)
        let spaeter = NotesFolder.current(defaults: defaults, german: false, home: home)
        XCTAssertEqual(spaeter.path, deutsch.path)
        XCTAssertEqual(defaults.string(forKey: NotesFolder.defaultsKey), "/Users/test/Documents/shout Notizen")
    }

    func testGewaehlterOrdner() {
        NotesFolder.set(URL(fileURLWithPath: "/Volumes/Daten/Notizen", isDirectory: true), defaults: defaults)
        XCTAssertEqual(NotesFolder.current(defaults: defaults, home: home).path, "/Volumes/Daten/Notizen")
    }

    func testIstVorgabe() {
        XCTAssertTrue(NotesFolder.isDefault(NotesFolder.defaultURL(german: false, home: home), home: home))
        XCTAssertTrue(NotesFolder.isDefault(NotesFolder.defaultURL(german: true, home: home), home: home))
        XCTAssertFalse(NotesFolder.isDefault(URL(fileURLWithPath: "/Volumes/Daten/Notizen"), home: home))
    }
}
```

- [ ] **Schritt 2: Eintragen und Test laufen lassen**

In `project.yml` nach `      - path: Sources/FlowLokal/NoteSearch.swift`:

```yaml
      - path: Sources/FlowLokal/NotesFolder.swift
```

```bash
cd /Users/liam/Developer/LIAM/flow-lokal && touch Sources/FlowLokal/NotesFolder.swift && xcodegen generate
```

Testbefehl mit `-only-testing:ShoutTests/NotesFolderTests`.
Erwartet: Build-Fehler „cannot find 'NotesFolder' in scope“.

- [ ] **Schritt 3: `NotesFolder` schreiben**

`Sources/FlowLokal/NotesFolder.swift`:

```swift
import Foundation

/// Wo die Notizen liegen. Die Mac-App läuft ohne Sandbox, der Pfad steht als
/// Klartext in den UserDefaults — ein Security-scoped Bookmark ist nicht nötig.
@MainActor
enum NotesFolder {

    static let defaultsKey = "notesFolderPath"

    /// `~/Documents/shout Notizen` (im Finder „Dokumente“), bei englischer
    /// Oberfläche `shout Notes`.
    static func defaultURL(german: Bool = Loc.isGerman,
                           home: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL {
        home.appendingPathComponent("Documents", isDirectory: true)
            .appendingPathComponent(german ? "shout Notizen" : "shout Notes", isDirectory: true)
    }

    /// Der eingestellte Ordner. Beim allerersten Aufruf wird die Vorgabe
    /// festgeschrieben, damit ein späterer Sprachwechsel sie nicht verschiebt.
    static func current(defaults: UserDefaults = .standard,
                        german: Bool = Loc.isGerman,
                        home: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL {
        if let path = defaults.string(forKey: defaultsKey), !path.isEmpty {
            return URL(fileURLWithPath: path, isDirectory: true)
        }
        let vorgabe = defaultURL(german: german, home: home)
        defaults.set(vorgabe.path, forKey: defaultsKey)
        return vorgabe
    }

    static func set(_ url: URL, defaults: UserDefaults = .standard) {
        defaults.set(url.standardizedFileURL.path, forKey: defaultsKey)
    }

    /// Nur die Vorgabe darf der Store selbst anlegen. Ein gewählter Ordner, der
    /// fehlt, liegt vermutlich auf einem abgesteckten Laufwerk.
    static func isDefault(_ url: URL,
                          home: URL = FileManager.default.homeDirectoryForCurrentUser) -> Bool {
        let pfad = url.standardizedFileURL.path
        return [true, false].contains { defaultURL(german: $0, home: home).standardizedFileURL.path == pfad }
    }
}
```

- [ ] **Schritt 4: Test laufen lassen**

Testbefehl mit `-only-testing:ShoutTests/NotesFolderTests`.
Erwartet: `Executed 4 tests, with 0 failures`.

- [ ] **Schritt 5: Commit**

```bash
cd /Users/liam/Developer/LIAM/flow-lokal && git add project.yml Sources/FlowLokal/NotesFolder.swift Tests/ShoutTests/NotesFolderTests.swift FlowLokal.xcodeproj && git commit -m "Notizen: Ordner in den Einstellungen, Vorgabe in Dokumente"
```

---

### Aufgabe 5: Ordner beobachten

**Dateien:**
- Neu: `Sources/FlowLokal/NoteFolderWatcher.swift`
- Neu: `Tests/ShoutTests/NoteFolderWatcherTests.swift`
- Ändern: `project.yml` (nach `- path: Sources/FlowLokal/NotesFolder.swift`)

**Schnittstellen:**
- Benutzt: CoreServices (FSEvents)
- Liefert: `final class NoteFolderWatcher { init?(url: URL, latency: TimeInterval = 0.5, onChange: @escaping () -> Void) }` — ruft `onChange` auf der Hauptwarteschlange, gebündelt über `latency`; hört beim Freigeben auf.

- [ ] **Schritt 1: Den fehlschlagenden Test schreiben**

`Tests/ShoutTests/NoteFolderWatcherTests.swift`:

```swift
import XCTest

/// FSEvents statt `DispatchSource` auf den Ordner: Bearbeitet Obsidian oder vim
/// eine Datei an Ort und Stelle, ändert sich der Ordner selbst nicht — nur die
/// Datei darin. Genau das muss trotzdem gemeldet werden.
final class NoteFolderWatcherTests: XCTestCase {

    private var ordner: URL!

    override func setUpWithError() throws {
        ordner = FileManager.default.temporaryDirectory
            .appendingPathComponent("shout-watcher-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: ordner, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: ordner)
    }

    func testMeldetNeueDatei() throws {
        let gemeldet = expectation(description: "Änderung gemeldet")
        gemeldet.assertForOverFulfill = false
        let watcher = try XCTUnwrap(NoteFolderWatcher(url: ordner, latency: 0.1) { gemeldet.fulfill() })
        // FSEvents braucht einen Moment, bis der Strom läuft.
        let ziel = ordner.appendingPathComponent("a.md")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            try? Data("x".utf8).write(to: ziel)
        }
        wait(for: [gemeldet], timeout: 5)
        withExtendedLifetime(watcher) {}
    }

    func testMeldetAenderungAnOrtUndStelle() throws {
        let ziel = ordner.appendingPathComponent("a.md")
        try Data("alt".utf8).write(to: ziel)
        let gemeldet = expectation(description: "Änderung gemeldet")
        gemeldet.assertForOverFulfill = false
        let watcher = try XCTUnwrap(NoteFolderWatcher(url: ordner, latency: 0.1) { gemeldet.fulfill() })
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            guard let handle = try? FileHandle(forWritingTo: ziel) else { return }
            handle.seekToEndOfFile()
            handle.write(Data(" neu".utf8))
            try? handle.close()
        }
        wait(for: [gemeldet], timeout: 5)
        withExtendedLifetime(watcher) {}
    }
}
```

- [ ] **Schritt 2: Eintragen und Test laufen lassen**

In `project.yml` nach `      - path: Sources/FlowLokal/NotesFolder.swift`:

```yaml
      - path: Sources/FlowLokal/NoteFolderWatcher.swift
```

```bash
cd /Users/liam/Developer/LIAM/flow-lokal && touch Sources/FlowLokal/NoteFolderWatcher.swift && xcodegen generate
```

Testbefehl mit `-only-testing:ShoutTests/NoteFolderWatcherTests`.
Erwartet: Build-Fehler „cannot find 'NoteFolderWatcher' in scope“.

- [ ] **Schritt 3: `NoteFolderWatcher` schreiben**

`Sources/FlowLokal/NoteFolderWatcher.swift`:

```swift
import Foundation
import CoreServices

/// Meldet Änderungen im Notizordner über FSEvents — auch Bearbeitungen an Ort
/// und Stelle, die ein `DispatchSource` auf den Ordner nicht sähe. Die Meldungen
/// kommen gebündelt (`latency`) auf der Hauptwarteschlange; was sich geändert
/// hat, sagt der Watcher nicht — der Store liest dann einfach neu ein.
final class NoteFolderWatcher {

    private var stream: FSEventStreamRef?
    private let onChange: () -> Void

    init?(url: URL, latency: TimeInterval = 0.5, onChange: @escaping () -> Void) {
        self.onChange = onChange
        var context = FSEventStreamContext(version: 0, info: nil, retain: nil,
                                           release: nil, copyDescription: nil)
        context.info = Unmanaged.passUnretained(self).toOpaque()
        let callback: FSEventStreamCallback = { _, info, _, _, _, _ in
            guard let info else { return }
            Unmanaged<NoteFolderWatcher>.fromOpaque(info).takeUnretainedValue().onChange()
        }
        // Echte Pfade: Temp-Ordner liegen hinter dem Symlink /var → /private/var.
        let pfad = url.resolvingSymlinksInPath().path
        guard let stream = FSEventStreamCreate(
            nil, callback, &context, [pfad] as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow), latency,
            UInt32(kFSEventStreamCreateFlagFileEvents)) else { return nil }
        self.stream = stream
        FSEventStreamSetDispatchQueue(stream, .main)
        FSEventStreamStart(stream)
    }

    deinit {
        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
    }
}
```

- [ ] **Schritt 4: Test laufen lassen**

Testbefehl mit `-only-testing:ShoutTests/NoteFolderWatcherTests`.
Erwartet: `Executed 2 tests, with 0 failures`.

- [ ] **Schritt 5: Commit**

```bash
cd /Users/liam/Developer/LIAM/flow-lokal && git add project.yml Sources/FlowLokal/NoteFolderWatcher.swift Tests/ShoutTests/NoteFolderWatcherTests.swift FlowLokal.xcodeproj && git commit -m "Notizen: Ordner per FSEvents beobachten"
```

---

### Aufgabe 6: `NoteStore` — lesen, sichern, Titelregel, Puffer

**Dateien:**
- Neu: `Sources/FlowLokal/NoteStore.swift`
- Neu: `Tests/ShoutTests/NotizUmgebung.swift`
- Neu: `Tests/ShoutTests/NoteStoreTests.swift`
- Ändern: `project.yml` (nach `- path: Sources/FlowLokal/NoteFolderWatcher.swift`)

**Schnittstellen:**
- Benutzt: `Note`, `NoteFile.*`, `NoteSearch.sorted`, `NotesFolder.isDefault`, `NoteFolderWatcher`, `StoreIO.directory()`, `Loc.t`
- Liefert (`@MainActor final class NoteStore: ObservableObject`):
  - `init(folder: URL, bufferFolder: URL = …, fileManager: FileManager = .default, watch: Bool = true, createIfMissing: Bool? = nil, trash: ((URL) throws -> URL)? = nil)`
  - `@Published private(set) var notes: [Note]` (sortiert), `@Published private(set) var folderState: FolderState` (`.ok`, `.unreachable`), `private(set) var folder: URL`
  - `enum SaveResult: Equatable { case saved(Note), skippedEmpty, buffered(Note), conflict(external: Note, conflictFileName: String), missing }`
  - `reload()`, `setFolder(_:)`, `note(id:) -> Note?`, `url(for:) -> URL`, `@discardableResult save(_:) -> SaveResult`
  - private, von Aufgabe 7 und 8 im selben File benutzt: `cache`, `checkFolder(create:)`, `read(_:keepingID:)`, `write(_:to:)`, `writeToBuffer(_:)`, `move(_:to:)`, `modificationDate(of:)`, `publish()`, `trash`
- Test-Hilfe: `@MainActor final class NotizUmgebung` mit `ordner`, `puffer`, `papierkorb`, `store(ordner:createIfMissing:)`, `schreibe(_:_:zeit:)`, `lies(_:)`, `text(_:)`, `dateien()`, `aufraeumen()`

- [ ] **Schritt 1: Test-Umgebung schreiben**

`Tests/ShoutTests/NotizUmgebung.swift`:

```swift
import XCTest

/// Wegwerf-Umgebung für die Notiz-Tests: Notizordner, Puffer und ein eigener
/// Papierkorb unter einem Temp-Verzeichnis. Der echte Papierkorb bleibt sauber.
@MainActor
final class NotizUmgebung {
    let wurzel: URL
    let ordner: URL
    let puffer: URL
    let papierkorb: URL

    init() throws {
        wurzel = FileManager.default.temporaryDirectory
            .appendingPathComponent("shout-notizen-\(UUID().uuidString)", isDirectory: true)
        ordner = wurzel.appendingPathComponent("Notizen", isDirectory: true)
        puffer = wurzel.appendingPathComponent("Puffer", isDirectory: true)
        papierkorb = wurzel.appendingPathComponent("Papierkorb", isDirectory: true)
        for o in [ordner, papierkorb] {
            try FileManager.default.createDirectory(at: o, withIntermediateDirectories: true)
        }
    }

    func aufraeumen() { try? FileManager.default.removeItem(at: wurzel) }

    func store(ordner anderer: URL? = nil, createIfMissing: Bool = false) -> NoteStore {
        let korb = papierkorb
        return NoteStore(folder: anderer ?? ordner, bufferFolder: puffer, watch: false,
                         createIfMissing: createIfMissing) { url in
            let ziel = korb.appendingPathComponent(UUID().uuidString + "-" + url.lastPathComponent)
            try FileManager.default.moveItem(at: url, to: ziel)
            return ziel
        }
    }

    /// Schreibt eine Datei wie ein fremdes Programm. `zeit` setzt das mtime —
    /// so sind Änderungen „von außen“ sicher von der eigenen unterscheidbar.
    func schreibe(_ name: String, _ inhalt: String, zeit: Date? = nil) throws {
        let url = ordner.appendingPathComponent(name)
        try Data(inhalt.utf8).write(to: url)
        if let zeit {
            try FileManager.default.setAttributes([.modificationDate: zeit], ofItemAtPath: url.path)
        }
    }

    func lies(_ name: String) -> String? {
        try? String(contentsOf: ordner.appendingPathComponent(name), encoding: .utf8)
    }

    /// Nur der Text, ohne Frontmatter.
    func text(_ name: String) -> String? { lies(name).map { NoteFile.parse($0).body } }

    func dateien() -> [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: ordner.path)) ?? []).sorted()
    }
}
```

- [ ] **Schritt 2: Den fehlschlagenden Test schreiben**

`Tests/ShoutTests/NoteStoreTests.swift`:

```swift
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
}
```

- [ ] **Schritt 3: Eintragen und Test laufen lassen**

In `project.yml` nach `      - path: Sources/FlowLokal/NoteFolderWatcher.swift`:

```yaml
      - path: Sources/FlowLokal/NoteStore.swift
```

```bash
cd /Users/liam/Developer/LIAM/flow-lokal && touch Sources/FlowLokal/NoteStore.swift && xcodegen generate
```

Testbefehl mit `-only-testing:ShoutTests/NoteStoreTests`.
Erwartet: Build-Fehler „cannot find 'NoteStore' in scope“.

- [ ] **Schritt 4: `NoteStore` schreiben**

`Sources/FlowLokal/NoteStore.swift`:

```swift
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
            return .buffered(writeToBuffer(note))
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
            return .buffered(writeToBuffer(note))
        }
        note.modified = mtime
        if alt != note.fileName { cache[alt] = nil }
        cache[note.fileName] = note
        publish()
        return .saved(note)
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
        retryTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.reload() }
        }
    }

    // MARK: - Puffer

    /// Sichert in Application Support, solange der Ordner fehlt. Merkt sich, zu
    /// welcher Notiz die Datei gehört und wie die Datei im Ordner vorher aussah.
    func writeToBuffer(_ input: Note) -> Note {
        var note = input
        try? fileManager.createDirectory(at: bufferFolder, withIntermediateDirectories: true)
        if note.isNew {
            note.fileName = NoteFile.freeFileName(
                for: NoteFile.deriveTitle(from: note.body) ?? Loc.t("Unbenannt"),
                in: bufferFolder, fileManager: fileManager)
        } else if bufferedBase[note.fileName] == nil && bufferedIDs[note.fileName] == nil {
            bufferedBase[note.fileName] = input.modified
        }
        bufferedIDs[note.fileName] = note.id
        if let mtime = write(note, to: bufferFolder.appendingPathComponent(note.fileName)) {
            note.modified = mtime
        }
        return note
    }

    /// Bringt Gepuffertes zurück in den Ordner. Unverändertes Original: wird
    /// ersetzt. Verändertes oder unbekanntes: unsere Fassung wird Konfliktdatei.
    private func flushBuffer() {
        guard let namen = try? fileManager.contentsOfDirectory(atPath: bufferFolder.path) else { return }
        for name in namen where isNoteFile(name, in: bufferFolder) {
            let quelle = bufferFolder.appendingPathComponent(name)
            let ziel = folder.appendingPathComponent(name)
            do {
                if fileManager.fileExists(atPath: ziel.path) {
                    if let basis = bufferedBase[name], modificationDate(of: ziel) == basis {
                        _ = try fileManager.replaceItemAt(ziel, withItemAt: quelle)
                        if let id = bufferedIDs[name] { pendingIDs[name] = id }
                    } else {
                        let titel = NoteFile.conflictTitle((name as NSString).deletingPathExtension,
                                                           suffix: Loc.t("(Konflikt)"))
                        let konflikt = NoteFile.freeFileName(for: titel, in: folder, fileManager: fileManager)
                        try fileManager.moveItem(at: quelle, to: folder.appendingPathComponent(konflikt))
                        NSLog("shout: Gepufferte Notiz \(name) kollidiert — gesichert als \(konflikt)")
                    }
                } else {
                    try fileManager.moveItem(at: quelle, to: ziel)
                    if let id = bufferedIDs[name] { pendingIDs[name] = id }
                }
                bufferedIDs[name] = nil
                bufferedBase[name] = nil
            } catch {
                NSLog("shout: Gepufferte Notiz \(name) konnte nicht zurück: \(error)")
            }
        }
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
        guard let data = try? Data(contentsOf: url), let text = String(data: data, encoding: .utf8) else {
            NSLog("shout: Notiz \(name) ist nicht lesbar (kein UTF-8?) — übersprungen.")
            return nil
        }
        let parsed = NoteFile.parse(text)
        let werte = try? url.resourceValues(forKeys: [.contentModificationDateKey, .creationDateKey])
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
```

- [ ] **Schritt 5: Test laufen lassen**

Testbefehl mit `-only-testing:ShoutTests/NoteStoreTests`.
Erwartet: `Executed 14 tests, with 0 failures`.

Schlägt `testUnveraendertesOriginalWirdErsetzt` fehl, weil das mtime nach dem
Zurückschieben abweicht: nicht die Regel aufweichen, sondern melden — das
Verhalten bei abgesteckten Laufwerken hängt genau daran.

- [ ] **Schritt 6: Commit**

```bash
cd /Users/liam/Developer/LIAM/flow-lokal && git add project.yml Sources/FlowLokal/NoteStore.swift Tests/ShoutTests/NotizUmgebung.swift Tests/ShoutTests/NoteStoreTests.swift FlowLokal.xcodeproj && git commit -m "Notizen: Store liest und sichert, Titelregel, Puffer bei fehlendem Ordner"
```

---

### Aufgabe 7: Umbenennen, Anheften, Papierkorb, Wieder sichern

**Dateien:**
- Ändern: `Sources/FlowLokal/NoteStore.swift` (Erweiterung am Dateiende)
- Neu: `Tests/ShoutTests/NoteStoreAktionenTests.swift`

**Schnittstellen:**
- Benutzt: aus Aufgabe 6 `cache`, `folder`, `trash`, `checkFolder(create:)`, `move(_:to:)`, `write(_:to:)`, `writeToBuffer(_:)`, `modificationDate(of:)`, `publish()`, `reload()`
- Liefert (in `extension NoteStore`):
  - `struct DeletedNote: Equatable { let fileName: String; let trashURL: URL }`
  - `@discardableResult rename(_ id: UUID, to raw: String) -> Note?`
  - `@discardableResult setPinned(_ id: UUID, _ pinned: Bool) -> SaveResult?`
  - `delete(_ id: UUID) -> DeletedNote?`
  - `undoDelete(_ deleted: DeletedNote) -> Note?`
  - `restore(_ note: Note) -> SaveResult`

- [ ] **Schritt 1: Den fehlschlagenden Test schreiben**

`Tests/ShoutTests/NoteStoreAktionenTests.swift`:

```swift
import XCTest

@MainActor
final class NoteStoreAktionenTests: XCTestCase {

    private var u: NotizUmgebung!

    override func setUpWithError() throws {
        Loc.shared.apply("de")
        u = try NotizUmgebung()
    }

    override func tearDown() {
        u.aufraeumen()
        Loc.shared.apply("system")
        super.tearDown()
    }

    private func neu(_ s: NoteStore, _ text: String) throws -> Note {
        var n = Note.blank()
        n.body = text
        guard case .saved(let notiz) = s.save(n) else { XCTFail("nicht gesichert"); throw XCTSkip() }
        return notiz
    }

    func testUmbenennenHaeltDenTitelFest() throws {
        let s = u.store()
        let n = try neu(s, "Milch")
        let umbenannt = try XCTUnwrap(s.rename(n.id, to: "Einkauf: Samstag"))
        XCTAssertEqual(umbenannt.fileName, "Einkauf Samstag.md")
        XCTAssertTrue(umbenannt.titleIsFixed)
        XCTAssertEqual(umbenannt.id, n.id)
        XCTAssertEqual(u.dateien(), ["Einkauf Samstag.md"])
    }

    func testNurDieSchreibweiseAendern() throws {
        let s = u.store()
        let n = try neu(s, "idee eins zwei")
        XCTAssertEqual(s.rename(n.id, to: "Idee eins zwei")?.fileName, "Idee eins zwei.md")
        XCTAssertEqual(u.dateien(), ["Idee eins zwei.md"])
    }

    func testUmbenennenAufBelegtenNamen() throws {
        try u.schreibe("Idee.md", "andere")
        let s = u.store()
        let n = try neu(s, "Etwas ganz anderes")
        XCTAssertEqual(s.rename(n.id, to: "Idee")?.fileName, "Idee 2.md")
        XCTAssertEqual(u.text("Idee.md"), "andere")
    }

    func testLeererNameAendertNichts() throws {
        let s = u.store()
        let n = try neu(s, "Bleibt wie es ist")
        XCTAssertNil(s.rename(n.id, to: " / "))
        XCTAssertEqual(u.dateien(), ["Bleibt wie es ist.md"])
    }

    func testAnheftenSchreibtFrontmatterUndSortiert() throws {
        try u.schreibe("A.md", "a", zeit: Date().addingTimeInterval(-100))
        try u.schreibe("B.md", "b", zeit: Date())
        let s = u.store()
        XCTAssertEqual(s.notes.map(\.title), ["B", "A"])
        let a = try XCTUnwrap(s.notes.first { $0.title == "A" })
        _ = s.setPinned(a.id, true)
        XCTAssertEqual(s.notes.map(\.title), ["A", "B"])
        XCTAssertTrue(NoteFile.parse(try XCTUnwrap(u.lies("A.md"))).pinned)

        _ = s.setPinned(a.id, false)
        XCTAssertFalse(try XCTUnwrap(u.lies("A.md")).contains("pinned"))
    }

    func testLoeschenUndZurueckholen() throws {
        try u.schreibe("Weg.md", "weg damit")
        let s = u.store()
        let geloescht = try XCTUnwrap(s.delete(s.notes[0].id))
        XCTAssertEqual(s.notes, [])
        XCTAssertEqual(u.dateien(), [])

        let zurueck = try XCTUnwrap(s.undoDelete(geloescht))
        XCTAssertEqual(zurueck.title, "Weg")
        XCTAssertEqual(u.text("Weg.md"), "weg damit")
    }

    /// Ist der Name inzwischen neu vergeben, kommt die gelöschte Notiz als „Weg 2“ zurück.
    func testZurueckholenAufBelegtenNamen() throws {
        try u.schreibe("Weg.md", "alt")
        let s = u.store()
        let geloescht = try XCTUnwrap(s.delete(s.notes[0].id))
        try u.schreibe("Weg.md", "neu")
        s.reload()
        XCTAssertEqual(s.undoDelete(geloescht)?.fileName, "Weg 2.md")
        XCTAssertEqual(u.text("Weg.md"), "neu")
    }

    func testNeueNotizLaesstSichNichtLoeschen() {
        XCTAssertNil(u.store().delete(UUID()))
    }

    /// „Wieder sichern“: Die Datei wurde von außen entfernt, der Text lebt noch
    /// im Editor und wird unter seinem Titel neu angelegt.
    func testWiederSichern() throws {
        try u.schreibe("Verschwunden.md", "Text")
        let s = u.store()
        var n = s.notes[0]
        try FileManager.default.removeItem(at: u.ordner.appendingPathComponent("Verschwunden.md"))
        s.reload()
        n.body = "Text, noch im Editor"
        guard case .saved(let neu) = s.restore(n) else { return XCTFail("nicht gesichert") }
        XCTAssertEqual(neu.fileName, "Verschwunden.md")
        XCTAssertEqual(neu.id, n.id)
        XCTAssertEqual(u.text("Verschwunden.md"), "Text, noch im Editor")
    }
}
```

- [ ] **Schritt 2: Test laufen lassen**

`xcodegen generate`, dann Testbefehl mit `-only-testing:ShoutTests/NoteStoreAktionenTests`.
Erwartet: Build-Fehler „value of type 'NoteStore' has no member 'rename'“.

- [ ] **Schritt 3: Erweiterung schreiben**

Ans Ende von `Sources/FlowLokal/NoteStore.swift` anhängen:

```swift

// MARK: - Umbenennen, Anheften, Papierkorb

extension NoteStore {

    struct DeletedNote: Equatable {
        let fileName: String
        let trashURL: URL
    }

    /// Benennt um und hält den Titel danach fest. Gibt `nil` zurück, wenn der
    /// Name nach dem Säubern leer ist oder das Umbenennen scheitert.
    @discardableResult
    func rename(_ id: UUID, to raw: String) -> Note? {
        guard var note = note(id: id), !note.isPlaceholder,
              let titel = NoteFile.safeTitle(raw) else { return nil }
        let neu = NoteFile.freeFileName(for: titel, in: folder, current: note.fileName)
        if neu != note.fileName {
            guard move(note.fileName, to: neu) else { return nil }
            cache[note.fileName] = nil
            note.fileName = neu
            note.modified = modificationDate(of: folder.appendingPathComponent(neu))
        }
        note.titleIsFixed = true
        cache[note.fileName] = note
        publish()
        return note
    }

    /// Ändert nur `pinned` und sichert. Offene Sitzungen gehen über
    /// `NoteEditorSession.setPinned`, damit ungesicherter Text mitkommt.
    @discardableResult
    func setPinned(_ id: UUID, _ pinned: Bool) -> SaveResult? {
        guard var note = note(id: id) else { return nil }
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
            return DeletedNote(fileName: note.fileName, trashURL: imKorb)
        } catch {
            NSLog("shout: Notiz \(note.fileName) konnte nicht in den Papierkorb: \(error)")
            return nil
        }
    }

    /// Holt aus dem Papierkorb zurück — unter dem alten Namen oder, wenn der
    /// inzwischen vergeben ist, als „Name 2“.
    func undoDelete(_ deleted: DeletedNote) -> Note? {
        let titel = (deleted.fileName as NSString).deletingPathExtension
        let name = NoteFile.freeFileName(for: titel, in: folder)
        do {
            try FileManager.default.moveItem(at: deleted.trashURL, to: folder.appendingPathComponent(name))
        } catch {
            NSLog("shout: Notiz konnte nicht aus dem Papierkorb zurück: \(error)")
            return nil
        }
        reload()
        return cache[name]
    }

    /// Legt eine Notiz neu an, deren Datei von außen entfernt wurde. Behält ID
    /// und Titel; ist der Name belegt, wird es „Titel 2“.
    func restore(_ input: Note) -> SaveResult {
        var note = input
        guard checkFolder(create: true) == .ready else {
            note.fileName = ""
            return .buffered(writeToBuffer(note))
        }
        let titel = note.title.isEmpty ? (NoteFile.deriveTitle(from: note.body) ?? Loc.t("Unbenannt")) : note.title
        note.fileName = NoteFile.freeFileName(for: titel, in: folder)
        guard let mtime = write(note, to: folder.appendingPathComponent(note.fileName)) else {
            return .buffered(writeToBuffer(note))
        }
        note.modified = mtime
        note.titleIsFixed = true
        cache[note.fileName] = note
        publish()
        return .saved(note)
    }
}
```

`writeToBuffer` ist in Aufgabe 6 ohne `private` geschrieben; `cache`, `trash`,
`checkFolder`, `read`, `write`, `move`, `modificationDate` und `publish` ebenso.
Falls ein Bearbeiter sie dort `private` gemacht hat: auf `internal`
zurücksetzen (Swift erlaubt `private` in Erweiterungen nur, wenn die Erweiterung
in derselben Datei steht — das tut sie, beides geht also; wichtig ist nur, dass
es kompiliert).

- [ ] **Schritt 4: Test laufen lassen**

Testbefehl mit `-only-testing:ShoutTests/NoteStoreAktionenTests`.
Erwartet: `Executed 9 tests, with 0 failures`.

- [ ] **Schritt 5: Commit**

```bash
cd /Users/liam/Developer/LIAM/flow-lokal && git add Sources/FlowLokal/NoteStore.swift Tests/ShoutTests/NoteStoreAktionenTests.swift FlowLokal.xcodeproj && git commit -m "Notizen: umbenennen, anheften, Papierkorb mit Rückgängig, wieder sichern"
```

---

### Aufgabe 8: Konflikt und verschwundene Datei beim Sichern

**Dateien:**
- Ändern: `Sources/FlowLokal/NoteStore.swift` (`save(_:)` und neue Methode `resolveConflict`)
- Neu: `Tests/ShoutTests/NoteStoreKonfliktTests.swift`

**Schnittstellen:**
- Benutzt: `read(_:keepingID:)`, `write(_:to:)`, `reload()`, `note(id:)`
- Liefert: `save(_:)` gibt jetzt auch `.conflict(external:conflictFileName:)` und `.missing` zurück.

- [ ] **Schritt 1: Den fehlschlagenden Test schreiben**

`Tests/ShoutTests/NoteStoreKonfliktTests.swift`:

```swift
import XCTest

/// Zwei Seiten ändern dieselbe Notiz — hier im Editor, draußen in Obsidian oder
/// auf einem zweiten Mac über iCloud. Keine Fassung darf still gewinnen.
@MainActor
final class NoteStoreKonfliktTests: XCTestCase {

    private var u: NotizUmgebung!

    override func setUpWithError() throws {
        Loc.shared.apply("de")
        u = try NotizUmgebung()
    }

    override func tearDown() {
        u.aufraeumen()
        Loc.shared.apply("system")
        super.tearDown()
    }

    func testGleichzeitigeAenderungGibtKonfliktdatei() throws {
        try u.schreibe("X.md", "alt", zeit: Date().addingTimeInterval(-60))
        let s = u.store()
        var n = s.notes[0]
        try u.schreibe("X.md", "von außen", zeit: Date())
        n.body = "von innen"

        guard case .conflict(let extern, let name) = s.save(n) else { return XCTFail("kein Konflikt") }
        XCTAssertEqual(extern.body, "von außen")
        XCTAssertEqual(extern.id, n.id)
        XCTAssertEqual(name, "X (Konflikt).md")
        XCTAssertEqual(u.text("X.md"), "von außen")
        XCTAssertEqual(u.text("X (Konflikt).md"), "von innen")
        XCTAssertEqual(Set(s.notes.map(\.title)), ["X", "X (Konflikt)"])
    }

    /// Anderes mtime, aber derselbe Text (z. B. nur „berührt“): kein Konflikt.
    func testGleicherInhaltIstKeinKonflikt() throws {
        try u.schreibe("X.md", "gleich", zeit: Date().addingTimeInterval(-60))
        let s = u.store()
        var n = s.notes[0]
        try u.schreibe("X.md", "gleich", zeit: Date())
        n.pinned = true
        guard case .saved = s.save(n) else { return XCTFail("nicht gesichert") }
        XCTAssertEqual(u.dateien(), ["X.md"])
    }

    /// Von außen gelöscht: Der Store legt die Datei nicht stillschweigend neu
    /// an — die Sitzung zeigt „Nicht mehr im Ordner“ und bietet „Wieder sichern“.
    func testVonAussenGeloeschtMeldetFehlend() throws {
        try u.schreibe("X.md", "a")
        let s = u.store()
        var n = s.notes[0]
        try FileManager.default.removeItem(at: u.ordner.appendingPathComponent("X.md"))
        n.body = "b"
        XCTAssertEqual(s.save(n), .missing)
        XCTAssertEqual(u.dateien(), [])
    }

    /// Die eigene Sicherung zählt nicht als Änderung von außen.
    func testZweimalSichernIstKeinKonflikt() throws {
        let s = u.store()
        var n = Note.blank()
        n.body = "Erster Stand hier"
        guard case .saved(var a) = s.save(n) else { return XCTFail() }
        a.body = "Zweiter Stand hier"
        guard case .saved = s.save(a) else { return XCTFail("eigene Sicherung als Konflikt erkannt") }
    }
}
```

- [ ] **Schritt 2: Test laufen lassen**

`xcodegen generate`, dann Testbefehl mit `-only-testing:ShoutTests/NoteStoreKonfliktTests`.
Erwartet: `testGleichzeitigeAenderungGibtKonfliktdatei` und
`testVonAussenGeloeschtMeldetFehlend` schlagen fehl (es wird ohne Prüfung
überschrieben bzw. neu angelegt).

- [ ] **Schritt 3: Prüfung in `save(_:)` einbauen**

In `Sources/FlowLokal/NoteStore.swift`, in `save(_:)`, diese Stelle

```swift
        folderState = .ok
        startWatchingIfNeeded()
        flushBuffer()

        let alt = note.fileName
```

ersetzen durch:

```swift
        folderState = .ok
        startWatchingIfNeeded()
        flushBuffer()

        if !note.isNew {
            let url = url(for: note)
            guard fileManager.fileExists(atPath: url.path) else { return .missing }
            if modificationDate(of: url) != note.modified,
               let extern = read(note.fileName, keepingID: note.id),
               extern.body != note.body {
                return resolveConflict(mine: note, external: extern)
            }
        }

        let alt = note.fileName
```

Und direkt unter `save(_:)` (vor `private func targetFileName`) einfügen:

```swift
    /// Beide Seiten haben geändert. Die eigene Fassung wird daneben gesichert,
    /// die Datei behält die Fassung von außen — keine gewinnt still.
    private func resolveConflict(mine: Note, external: Note) -> SaveResult {
        let titel = NoteFile.conflictTitle(mine.title, suffix: Loc.t("(Konflikt)"))
        let name = NoteFile.freeFileName(for: titel, in: folder, fileManager: fileManager)
        _ = write(mine, to: folder.appendingPathComponent(name))
        reload()
        return .conflict(external: note(id: mine.id) ?? external, conflictFileName: name)
    }
```

- [ ] **Schritt 4: Alle Store-Tests laufen lassen**

Testbefehl mit `-only-testing:ShoutTests/NoteStoreKonfliktTests -only-testing:ShoutTests/NoteStoreTests -only-testing:ShoutTests/NoteStoreAktionenTests`.
Erwartet: `Executed 27 tests, with 0 failures`.

- [ ] **Schritt 5: Commit**

```bash
cd /Users/liam/Developer/LIAM/flow-lokal && git add Sources/FlowLokal/NoteStore.swift Tests/ShoutTests/NoteStoreKonfliktTests.swift FlowLokal.xcodeproj && git commit -m "Notizen: Konfliktdatei bei Änderung von außen, verschwundene Datei melden"
```

---

### Aufgabe 9: `NoteEditorSession`

**Dateien:**
- Neu: `Sources/FlowLokal/NoteEditorSession.swift`
- Neu: `Tests/ShoutTests/NoteEditorSessionTests.swift`
- Ändern: `project.yml` (nach `- path: Sources/FlowLokal/NoteStore.swift`)

**Schnittstellen:**
- Benutzt: `NoteStore` (`save`, `rename`, `restore`, `$notes`, `folderState`)
- Liefert (`@MainActor final class NoteEditorSession: ObservableObject, Identifiable`):
  - `init(note: Note, store: NoteStore, saveDelay: TimeInterval = 1.0)`
  - `let id: UUID`, `@Published private(set) var note: Note`, `status: Status` (`.clean`, `.dirty`, `.missing`, `.placeholder`), `externalRevision: Int`, `conflictNotice: String?`
  - `edit(_ text: String)`, `flush()`, `setPinned(_:)`, `rename(to:)`, `restoreMissing()`, `dismissNotice()`

- [ ] **Schritt 1: Den fehlschlagenden Test schreiben**

`Tests/ShoutTests/NoteEditorSessionTests.swift`:

```swift
import XCTest

@MainActor
final class NoteEditorSessionTests: XCTestCase {

    private var u: NotizUmgebung!

    override func setUpWithError() throws {
        Loc.shared.apply("de")
        u = try NotizUmgebung()
    }

    override func tearDown() {
        u.aufraeumen()
        Loc.shared.apply("system")
        super.tearDown()
    }

    func testEingabeSichertNachVerzoegerung() async throws {
        let s = u.store()
        let sitzung = NoteEditorSession(note: .blank(), store: s, saveDelay: 0.05)
        sitzung.edit("Erste Gedanken zum Projekt")
        XCTAssertEqual(sitzung.status, .dirty)
        XCTAssertEqual(u.dateien(), [])

        try await Task.sleep(for: .milliseconds(400))
        XCTAssertEqual(sitzung.status, .clean)
        XCTAssertEqual(sitzung.note.fileName, "Erste Gedanken zum Projekt.md")
        XCTAssertEqual(u.text("Erste Gedanken zum Projekt.md"), "Erste Gedanken zum Projekt")
    }

    func testFlushSichertSofort() {
        let s = u.store()
        let sitzung = NoteEditorSession(note: .blank(), store: s, saveDelay: 60)
        sitzung.edit("Sofort sichern bitte")
        sitzung.flush()
        XCTAssertEqual(sitzung.status, .clean)
        XCTAssertEqual(u.dateien(), ["Sofort sichern bitte.md"])
    }

    func testAenderungVonAussenWirdUebernommenWennSauber() throws {
        try u.schreibe("X.md", "alt", zeit: Date().addingTimeInterval(-60))
        let s = u.store()
        let sitzung = NoteEditorSession(note: s.notes[0], store: s)
        try u.schreibe("X.md", "neu", zeit: Date())
        s.reload()
        XCTAssertEqual(sitzung.note.body, "neu")
        XCTAssertEqual(sitzung.externalRevision, 1)
        XCTAssertEqual(sitzung.status, .clean)
    }

    /// Ungesicherter Text wird nicht überschrieben. Beim Sichern entsteht die
    /// Konfliktdatei, der Editor zeigt danach die Fassung von außen.
    func testUngesichertPlusAussenGibtKonflikt() throws {
        try u.schreibe("X.md", "alt", zeit: Date().addingTimeInterval(-60))
        let s = u.store()
        let sitzung = NoteEditorSession(note: s.notes[0], store: s, saveDelay: 60)
        sitzung.edit("meins")
        try u.schreibe("X.md", "neu", zeit: Date())
        s.reload()
        XCTAssertEqual(sitzung.note.body, "meins")

        sitzung.flush()
        XCTAssertEqual(sitzung.conflictNotice, "X (Konflikt).md")
        XCTAssertEqual(sitzung.note.body, "neu")
        XCTAssertEqual(sitzung.externalRevision, 1)
        XCTAssertEqual(u.text("X (Konflikt).md"), "meins")

        sitzung.dismissNotice()
        XCTAssertNil(sitzung.conflictNotice)
    }

    func testGeloeschteNotizWirdFehlendUndLaesstSichWiederSichern() throws {
        try u.schreibe("X.md", "Text")
        let s = u.store()
        let sitzung = NoteEditorSession(note: s.notes[0], store: s)
        try FileManager.default.removeItem(at: u.ordner.appendingPathComponent("X.md"))
        s.reload()
        XCTAssertEqual(sitzung.status, .missing)

        sitzung.edit("Text, weiter bearbeitet")
        XCTAssertEqual(sitzung.status, .missing)   // kein Sichern ins Leere
        sitzung.restoreMissing()
        XCTAssertEqual(sitzung.status, .clean)
        XCTAssertEqual(u.text("X.md"), "Text, weiter bearbeitet")
    }

    func testAnheftenNimmtUngesichertenTextMit() throws {
        try u.schreibe("X.md", "alt")
        let s = u.store()
        let sitzung = NoteEditorSession(note: s.notes[0], store: s, saveDelay: 60)
        sitzung.edit("neu getippt")
        sitzung.setPinned(true)
        let roh = try XCTUnwrap(u.lies("X.md"))
        XCTAssertTrue(NoteFile.parse(roh).pinned)
        XCTAssertEqual(NoteFile.parse(roh).body, "neu getippt")
    }

    func testUmbenennen() {
        let s = u.store()
        let sitzung = NoteEditorSession(note: .blank(), store: s, saveDelay: 60)
        sitzung.edit("eins zwei drei")
        sitzung.rename(to: "Neuer Name")
        XCTAssertEqual(sitzung.note.fileName, "Neuer Name.md")
        XCTAssertEqual(u.dateien(), ["Neuer Name.md"])
    }

    func testPlatzhalterIstGesperrt() throws {
        try u.schreibe(".Fern.md.icloud", "")
        let s = u.store()
        let sitzung = NoteEditorSession(note: s.notes[0], store: s)
        XCTAssertEqual(sitzung.status, .placeholder)
        sitzung.edit("darf nicht")
        XCTAssertEqual(sitzung.note.body, "")
    }
}
```

- [ ] **Schritt 2: Eintragen und Test laufen lassen**

In `project.yml` nach `      - path: Sources/FlowLokal/NoteStore.swift`:

```yaml
      - path: Sources/FlowLokal/NoteEditorSession.swift
```

```bash
cd /Users/liam/Developer/LIAM/flow-lokal && touch Sources/FlowLokal/NoteEditorSession.swift && xcodegen generate
```

Testbefehl mit `-only-testing:ShoutTests/NoteEditorSessionTests`.
Erwartet: Build-Fehler „cannot find 'NoteEditorSession' in scope“.

- [ ] **Schritt 3: `NoteEditorSession` schreiben**

`Sources/FlowLokal/NoteEditorSession.swift`:

```swift
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

    private let store: NoteStore
    private let saveDelay: TimeInterval
    private var saveTask: Task<Void, Never>?
    private var subscription: AnyCancellable?

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
        guard status != .missing else { return }
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

    func setPinned(_ pinned: Bool) {
        guard status != .placeholder else { return }
        note.pinned = pinned
        guard status != .missing else { return }
        status = .dirty
        flush()
    }

    func rename(to title: String) {
        flush()
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
            status = .clean
        case .skippedEmpty:
            status = .clean
        case .missing:
            status = .missing
        case .conflict(let extern, let dateiname):
            note = extern
            status = .clean
            conflictNotice = dateiname
            externalRevision += 1
        }
    }

    /// Die Liste des Stores hat sich geändert (eigene Sicherung, Neueinlesen,
    /// Umbenennen). Ungesicherter Text wird hier nie überschrieben — das
    /// entscheidet beim Sichern die Konfliktprüfung.
    private func storeChanged(_ notes: [Note]) {
        guard let frisch = notes.first(where: { $0.id == id }) else {
            // Nie gesicherte Notizen stehen nicht in der Liste; alle anderen fehlen jetzt.
            if !note.isNew, !note.isPlaceholder, store.folderState == .ok { status = .missing }
            return
        }
        if status == .dirty { return }
        guard frisch != note else { return }
        let textGeaendert = frisch.body != note.body
        note = frisch
        status = frisch.isPlaceholder ? .placeholder : .clean
        if textGeaendert { externalRevision += 1 }
    }
}
```

- [ ] **Schritt 4: Test laufen lassen**

Testbefehl mit `-only-testing:ShoutTests/NoteEditorSessionTests`.
Erwartet: `Executed 8 tests, with 0 failures`.

- [ ] **Schritt 5: Commit**

```bash
cd /Users/liam/Developer/LIAM/flow-lokal && git add project.yml Sources/FlowLokal/NoteEditorSession.swift Tests/ShoutTests/NoteEditorSessionTests.swift FlowLokal.xcodeproj && git commit -m "Notizen: Sitzung mit verzögertem Sichern und Übernahme von außen"
```

---

### Aufgabe 10: `NotesPageModel`

**Dateien:**
- Neu: `Sources/FlowLokal/NotesPageModel.swift`
- Neu: `Tests/ShoutTests/NotesPageModelTests.swift`
- Ändern: `project.yml` (nach `- path: Sources/FlowLokal/NoteEditorSession.swift`)

**Schnittstellen:**
- Benutzt: `NoteStore`, `NoteEditorSession`, `NoteSearch.filter`, `NotesFolder.set`
- Liefert (`@MainActor final class NotesPageModel: ObservableObject`):
  - `init(store: NoteStore, defaults: UserDefaults = .standard)`
  - `let store`, `@Published var query`, `@Published private(set) var session: NoteEditorSession?`, `@Published private(set) var lastDeleted: UndoDelete?`
  - `struct UndoDelete: Equatable { title: String; token: NoteStore.DeletedNote }`
  - `results: [NoteSearch.Result]`
  - `select(_:)`, `createNote()`, `moveSelection(by:)`, `togglePin(_:)`, `rename(_:to:)`, `delete(_:)`, `undoDelete()`, `dismissUndo()`, `changeFolder(to:)`, `flush()`

- [ ] **Schritt 1: Den fehlschlagenden Test schreiben**

`Tests/ShoutTests/NotesPageModelTests.swift`:

```swift
import XCTest

@MainActor
final class NotesPageModelTests: XCTestCase {

    private var u: NotizUmgebung!
    private var suite: String!
    private var defaults: UserDefaults!

    override func setUpWithError() throws {
        Loc.shared.apply("de")
        u = try NotizUmgebung()
        suite = "shout-notespage-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)
    }

    override func tearDown() {
        u.aufraeumen()
        defaults.removePersistentDomain(forName: suite)
        Loc.shared.apply("system")
        super.tearDown()
    }

    /// A ist die älteste, C die neueste — die Liste zeigt C, B, A.
    private func dreiNotizen() throws -> NotesPageModel {
        try u.schreibe("A.md", "eins", zeit: Date().addingTimeInterval(-30))
        try u.schreibe("B.md", "zwei", zeit: Date().addingTimeInterval(-20))
        try u.schreibe("C.md", "drei", zeit: Date().addingTimeInterval(-10))
        return NotesPageModel(store: u.store(), defaults: defaults)
    }

    private func id(_ m: NotesPageModel, _ titel: String) -> UUID {
        m.store.notes.first { $0.title == titel }!.id
    }

    func testNeueNotiz() {
        let m = NotesPageModel(store: u.store(), defaults: defaults)
        m.createNote()
        XCTAssertEqual(m.session?.note.isNew, true)
    }

    func testAuswahlwechselSichertVorher() throws {
        let m = try dreiNotizen()
        m.select(id(m, "A"))
        m.session?.edit("eins, geändert")
        m.select(id(m, "B"))
        XCTAssertEqual(u.text("A.md"), "eins, geändert")
        XCTAssertEqual(m.session?.note.title, "B")
    }

    func testSucheFiltert() throws {
        let m = try dreiNotizen()
        m.query = "zwei"
        XCTAssertEqual(m.results.map(\.note.title), ["B"])
    }

    func testPfeilnavigation() throws {
        let m = try dreiNotizen()
        m.moveSelection(by: 1)                      // nichts gewählt → erste
        XCTAssertEqual(m.session?.note.title, "C")
        m.moveSelection(by: 1)
        XCTAssertEqual(m.session?.note.title, "B")
        m.moveSelection(by: 5)                      // bleibt am Ende stehen
        XCTAssertEqual(m.session?.note.title, "A")
        m.moveSelection(by: -1)
        XCTAssertEqual(m.session?.note.title, "B")
    }

    func testLoeschenWaehltNachbarnUndRueckgaengig() throws {
        let m = try dreiNotizen()
        m.select(id(m, "B"))
        m.delete(id(m, "B"))
        XCTAssertEqual(m.session?.note.title, "A")
        XCTAssertEqual(m.lastDeleted?.title, "B")
        XCTAssertEqual(m.results.map(\.note.title), ["C", "A"])

        m.undoDelete()
        XCTAssertNil(m.lastDeleted)
        XCTAssertEqual(m.session?.note.title, "B")
        XCTAssertEqual(u.text("B.md"), "zwei")
    }

    /// Eine nie gesicherte Notiz hat keine Datei — „Löschen“ verwirft sie einfach.
    func testNeueNotizLoeschenVerwirft() {
        let m = NotesPageModel(store: u.store(), defaults: defaults)
        m.createNote()
        m.delete(m.session!.id)
        XCTAssertNil(m.session)
        XCTAssertNil(m.lastDeleted)
    }

    func testAnheftenUndUmbenennenUeberDieSitzung() throws {
        let m = try dreiNotizen()
        m.select(id(m, "A"))
        m.session?.edit("eins, ungesichert")
        m.togglePin(id(m, "A"))
        XCTAssertEqual(m.results.first?.note.title, "A")
        XCTAssertEqual(u.text("A.md"), "eins, ungesichert")

        m.rename(id(m, "A"), to: "Erste")
        XCTAssertEqual(m.session?.note.fileName, "Erste.md")
    }

    func testOrdnerwechsel() throws {
        let m = try dreiNotizen()
        m.select(id(m, "A"))
        let anderer = u.wurzel.appendingPathComponent("Anderer", isDirectory: true)
        try FileManager.default.createDirectory(at: anderer, withIntermediateDirectories: true)
        m.changeFolder(to: anderer)
        XCTAssertNil(m.session)
        XCTAssertEqual(m.store.notes, [])
        XCTAssertEqual(defaults.string(forKey: NotesFolder.defaultsKey), anderer.standardizedFileURL.path)
    }
}
```

- [ ] **Schritt 2: Eintragen und Test laufen lassen**

In `project.yml` nach `      - path: Sources/FlowLokal/NoteEditorSession.swift`:

```yaml
      - path: Sources/FlowLokal/NotesPageModel.swift
```

```bash
cd /Users/liam/Developer/LIAM/flow-lokal && touch Sources/FlowLokal/NotesPageModel.swift && xcodegen generate
```

Testbefehl mit `-only-testing:ShoutTests/NotesPageModelTests`.
Erwartet: Build-Fehler „cannot find 'NotesPageModel' in scope“.

- [ ] **Schritt 3: `NotesPageModel` schreiben**

`Sources/FlowLokal/NotesPageModel.swift`:

```swift
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

    func select(_ id: UUID) {
        guard session?.id != id, let note = store.note(id: id) else { return }
        session?.flush()
        session = NoteEditorSession(note: note, store: store)
    }

    func createNote() {
        session?.flush()
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

    func delete(_ id: UUID) {
        if let session, session.id == id, session.note.isNew {
            self.session = nil      // nie gesichert: keine Datei, nichts zurückzuholen
            return
        }
        let vorher = results
        let index = vorher.firstIndex { $0.id == id }
        if session?.id == id { session?.flush() }
        guard let titel = store.note(id: id)?.title, let token = store.delete(id) else { return }
        lastDeleted = UndoDelete(title: titel, token: token)

        guard session?.id == id else { return }
        session = nil
        let rest = results
        if let index, !rest.isEmpty { select(rest[min(index, rest.count - 1)].id) }
    }

    func undoDelete() {
        guard let geloescht = lastDeleted else { return }
        lastDeleted = nil
        guard let note = store.undoDelete(geloescht.token) else { return }
        session?.flush()
        session = nil
        select(note.id)
    }

    func dismissUndo() { lastDeleted = nil }

    func changeFolder(to url: URL) {
        flush()
        session = nil
        lastDeleted = nil
        NotesFolder.set(url, defaults: defaults)
        store.setFolder(url)
    }

    func flush() { session?.flush() }
}
```

- [ ] **Schritt 4: Test laufen lassen**

Testbefehl mit `-only-testing:ShoutTests/NotesPageModelTests`.
Erwartet: `Executed 8 tests, with 0 failures`.

- [ ] **Schritt 5: Commit**

```bash
cd /Users/liam/Developer/LIAM/flow-lokal && git add project.yml Sources/FlowLokal/NotesPageModel.swift Tests/ShoutTests/NotesPageModelTests.swift FlowLokal.xcodeproj && git commit -m "Notizen: Seitenmodell mit Auswahl, Suche, Löschen und Rückgängig"
```

---

### Aufgabe 11: `MarkdownHighlighter`

**Dateien:**
- Neu: `Sources/FlowLokal/MarkdownHighlighter.swift`
- Neu: `Tests/ShoutTests/MarkdownHighlighterTests.swift`
- Ändern: `project.yml` (nach `- path: Sources/FlowLokal/NotesPageModel.swift`)

**Schnittstellen:**
- Benutzt: AppKit
- Liefert:
  - `final class MarkdownHighlighter: NSObject, NSTextStorageDelegate` — als Delegate eines `NSTextStorage` gesetzt, gestaltet es nach jeder Zeichenänderung neu.
  - `static func apply(to storage: NSTextStorage)`
  - `enum Style` mit `bodySize`, `headingSizes`, `text`, `dim`, `accent`, `codeBackground`, `body`, `mono`, `paragraph`, `baseAttributes`

- [ ] **Schritt 1: Den fehlschlagenden Test schreiben**

`Tests/ShoutTests/MarkdownHighlighterTests.swift`:

```swift
import XCTest
import AppKit

/// Die Darstellung ändert nie den Text — die Datei bleibt Klartext.
final class MarkdownHighlighterTests: XCTestCase {

    private typealias Style = MarkdownHighlighter.Style

    private func gestaltet(_ text: String) -> NSTextStorage {
        let speicher = NSTextStorage(string: text)
        MarkdownHighlighter.apply(to: speicher)
        return speicher
    }

    private func schrift(_ s: NSTextStorage, _ i: Int) -> NSFont {
        s.attribute(.font, at: i, effectiveRange: nil) as! NSFont
    }

    private func farbe(_ s: NSTextStorage, _ i: Int) -> NSColor? {
        s.attribute(.foregroundColor, at: i, effectiveRange: nil) as? NSColor
    }

    private func fett(_ f: NSFont) -> Bool { NSFontManager.shared.traits(of: f).contains(.boldFontMask) }
    private func kursiv(_ f: NSFont) -> Bool { NSFontManager.shared.traits(of: f).contains(.italicFontMask) }
    private func mono(_ f: NSFont) -> Bool { f.fontDescriptor.symbolicTraits.contains(.monoSpace) }

    func testTextBleibtUnveraendert() {
        let text = "# Titel\n**fett** und *kursiv*\n- [x] erledigt\n`code`"
        XCTAssertEqual(gestaltet(text).string, text)
    }

    func testUeberschrift() {
        let s = gestaltet("# Titel\nText")
        XCTAssertTrue(fett(schrift(s, 3)))
        XCTAssertEqual(schrift(s, 3).pointSize, 22)
        XCTAssertEqual(farbe(s, 0), Style.dim)         // das # ist gedimmt
        XCTAssertFalse(fett(schrift(s, 9)))
        XCTAssertEqual(schrift(s, 9).pointSize, Style.bodySize)
    }

    func testUeberschriftEbeneDrei() {
        XCTAssertEqual(schrift(gestaltet("### Drei"), 5).pointSize, 17)
    }

    func testFett() {
        let s = gestaltet("**fett** normal")
        XCTAssertTrue(fett(schrift(s, 3)))
        XCTAssertEqual(farbe(s, 0), Style.dim)
        XCTAssertFalse(fett(schrift(s, 10)))
    }

    func testKursiv() {
        let s = gestaltet("ein *kursiv* Wort")
        XCTAssertTrue(kursiv(schrift(s, 6)))
        XCTAssertFalse(kursiv(schrift(s, 1)))
    }

    func testUnterstrichImWortIstKeinKursiv() {
        XCTAssertFalse(kursiv(schrift(gestaltet("snake_case_name"), 7)))
    }

    func testCode() {
        let s = gestaltet("nimm `make test` jetzt")
        XCTAssertTrue(mono(schrift(s, 7)))
        XCTAssertFalse(mono(schrift(s, 1)))
    }

    func testErledigteAufgabeDurchgestrichen() {
        XCTAssertNotNil(gestaltet("- [x] erledigt").attribute(.strikethroughStyle, at: 8, effectiveRange: nil))
        XCTAssertNil(gestaltet("- [ ] offen").attribute(.strikethroughStyle, at: 7, effectiveRange: nil))
    }

    func testListenzeichenInSignalfarbe() {
        XCTAssertEqual(farbe(gestaltet("- Punkt"), 0), Style.accent)
    }

    func testCodeblockOhneHervorhebung() {
        let s = gestaltet("```\n**nicht fett**\n```")
        XCTAssertFalse(fett(schrift(s, 7)))
        XCTAssertTrue(mono(schrift(s, 7)))
    }

    func testLeererText() {
        XCTAssertEqual(gestaltet("").length, 0)
    }
}
```

- [ ] **Schritt 2: Eintragen und Test laufen lassen**

In `project.yml` nach `      - path: Sources/FlowLokal/NotesPageModel.swift`:

```yaml
      - path: Sources/FlowLokal/MarkdownHighlighter.swift
```

```bash
cd /Users/liam/Developer/LIAM/flow-lokal && touch Sources/FlowLokal/MarkdownHighlighter.swift && xcodegen generate
```

Testbefehl mit `-only-testing:ShoutTests/MarkdownHighlighterTests`.
Erwartet: Build-Fehler „cannot find 'MarkdownHighlighter' in scope“.

- [ ] **Schritt 3: `MarkdownHighlighter` schreiben**

`Sources/FlowLokal/MarkdownHighlighter.swift`:

```swift
import AppKit

/// Hebt Markdown im Editor hervor, ohne den Text zu verändern: Die Datei bleibt
/// Klartext, nur die Darstellung bekommt Größen, Fett, Kursiv und gedimmte
/// Markierungszeichen. Als Delegate eines `NSTextStorage` gestaltet es nach
/// jeder Zeichenänderung den ganzen Text neu — bei Notizen von einigen tausend
/// Zeichen schneller als jede Buchführung über geänderte Bereiche, und
/// Codeblöcke über mehrere Zeilen werden nie halb erkannt.
final class MarkdownHighlighter: NSObject, NSTextStorageDelegate {

    enum Style {
        static let bodySize: CGFloat = 14
        static let headingSizes: [CGFloat] = [22, 19, 17, 15.5, 14.5, 14]
        static let text = NSColor(white: 0.90, alpha: 1)
        static let dim = NSColor(white: 0.42, alpha: 1)
        /// Wie `Color.shoutLive`.
        static let accent = NSColor(red: 1.0, green: 0.29, blue: 0.04, alpha: 1)
        static let codeBackground = NSColor(white: 1, alpha: 0.06)
        static let body = NSFont.systemFont(ofSize: bodySize)
        static let mono = NSFont.monospacedSystemFont(ofSize: bodySize - 1, weight: .regular)
        static let paragraph: NSParagraphStyle = {
            let stil = NSMutableParagraphStyle()
            stil.lineSpacing = 3
            stil.paragraphSpacing = 4
            return stil
        }()
        static var baseAttributes: [NSAttributedString.Key: Any] {
            [.font: body, .foregroundColor: text, .paragraphStyle: paragraph]
        }
    }

    func textStorage(_ textStorage: NSTextStorage, didProcessEditing editedMask: NSTextStorageEditActions,
                     range editedRange: NSRange, changeInLength delta: Int) {
        guard editedMask.contains(.editedCharacters) else { return }
        Self.apply(to: textStorage)
    }

    // MARK: - Regeln

    private static func muster(_ p: String) -> NSRegularExpression {
        try! NSRegularExpression(pattern: p, options: [.anchorsMatchLines])
    }

    private static let fence = muster("^```[^\\n]*\\n[\\s\\S]*?^```[^\\n]*$")
    private static let heading = muster("^(#{1,6})[ \\t]+\\S.*$")
    private static let bold = muster("(\\*\\*|__)(?=\\S)(.+?)(?<=\\S)\\1")
    private static let italic = muster("(?<![\\*\\w])([\\*_])(?=[^\\s\\*_])([^\\n]+?)(?<=[^\\s\\*_])\\1(?![\\*\\w])")
    private static let code = muster("`[^`\\n]+`")
    private static let listMarker = muster("^[ \\t]*([-*+]|\\d+[.)])[ \\t]")
    private static let checkbox = muster("^[ \\t]*[-*+][ \\t](\\[[ xX]\\])[ \\t]?(.*)$")
    private static let quote = muster("^>[ \\t]?.*$")
    private static let link = muster("!?\\[([^\\]\\n]*)\\]\\(([^)\\n]*)\\)")

    static func apply(to storage: NSTextStorage) {
        let ns = storage.string as NSString
        let ganz = NSRange(location: 0, length: ns.length)
        storage.setAttributes(Style.baseAttributes, range: ganz)
        guard ns.length > 0 else { return }
        let text = storage.string

        let bloecke = fence.matches(in: text, range: ganz).map(\.range)
        func ausserhalbCode(_ r: NSRange) -> Bool {
            !bloecke.contains { NSIntersectionRange($0, r).length > 0 }
        }
        func jeder(_ re: NSRegularExpression, _ tu: (NSTextCheckingResult) -> Void) {
            for treffer in re.matches(in: text, range: ganz) where ausserhalbCode(treffer.range) { tu(treffer) }
        }
        func dimmen(_ r: NSRange) { storage.addAttribute(.foregroundColor, value: Style.dim, range: r) }

        jeder(heading) { t in
            let ebene = t.range(at: 1).length
            storage.addAttribute(.font, value: NSFont.boldSystemFont(ofSize: Style.headingSizes[ebene - 1]), range: t.range)
            dimmen(t.range(at: 1))
        }
        jeder(quote) { t in
            dimmen(t.range)
            addTrait(.italicFontMask, in: t.range, of: storage)
        }
        jeder(listMarker) { t in
            storage.addAttribute(.foregroundColor, value: Style.accent, range: t.range(at: 1))
        }
        jeder(checkbox) { t in
            dimmen(t.range(at: 1))
            if ns.substring(with: t.range(at: 1)).lowercased() == "[x]" {
                storage.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: t.range(at: 2))
                dimmen(t.range(at: 2))
            }
        }
        jeder(bold) { t in
            addTrait(.boldFontMask, in: t.range(at: 2), of: storage)
            let n = t.range(at: 1).length
            dimmen(NSRange(location: t.range.location, length: n))
            dimmen(NSRange(location: NSMaxRange(t.range) - n, length: n))
        }
        jeder(italic) { t in
            addTrait(.italicFontMask, in: t.range(at: 2), of: storage)
            dimmen(NSRange(location: t.range.location, length: 1))
            dimmen(NSRange(location: NSMaxRange(t.range) - 1, length: 1))
        }
        jeder(link) { t in
            dimmen(t.range)
            storage.addAttribute(.foregroundColor, value: Style.accent, range: t.range(at: 1))
        }
        jeder(code) { t in
            storage.addAttributes([.font: Style.mono, .backgroundColor: Style.codeBackground], range: t.range)
        }
        for block in bloecke {
            storage.addAttributes([.font: Style.mono, .backgroundColor: Style.codeBackground,
                                   .foregroundColor: Style.text], range: block)
        }
    }

    /// Fügt Fett oder Kursiv hinzu, ohne Größe und vorhandene Merkmale zu verlieren
    /// (fett in einer Überschrift bleibt groß).
    private static func addTrait(_ trait: NSFontTraitMask, in range: NSRange, of storage: NSTextStorage) {
        guard range.length > 0 else { return }
        storage.enumerateAttribute(.font, in: range) { wert, teil, _ in
            let schrift = wert as? NSFont ?? Style.body
            var neu = NSFontManager.shared.convert(schrift, toHaveTrait: trait)
            if !NSFontManager.shared.traits(of: neu).contains(trait) {
                let merkmal: NSFontDescriptor.SymbolicTraits = trait == .boldFontMask ? .bold : .italic
                let beschreibung = schrift.fontDescriptor.withSymbolicTraits(
                    schrift.fontDescriptor.symbolicTraits.union(merkmal))
                neu = NSFont(descriptor: beschreibung, size: schrift.pointSize) ?? schrift
            }
            storage.addAttribute(.font, value: neu, range: teil)
        }
    }
}
```

- [ ] **Schritt 4: Test laufen lassen**

Testbefehl mit `-only-testing:ShoutTests/MarkdownHighlighterTests`.
Erwartet: `Executed 11 tests, with 0 failures`.

- [ ] **Schritt 5: Commit**

```bash
cd /Users/liam/Developer/LIAM/flow-lokal && git add project.yml Sources/FlowLokal/MarkdownHighlighter.swift Tests/ShoutTests/MarkdownHighlighterTests.swift FlowLokal.xcodeproj && git commit -m "Notizen: Markdown-Hervorhebung im Editor, Text bleibt Klartext"
```

---

### Aufgabe 12: Editor, Seite „Notizen“, Texte

**Dateien:**
- Neu: `Sources/FlowLokal/NoteEditorView.swift`
- Neu: `Sources/FlowLokal/NotesView.swift`
- Neu: `Tests/ShoutTests/LocalizationNotesTests.swift`
- Ändern: `Sources/FlowLokal/Localization.swift` (vor dem Ende des Literals, Z. 912–913)

**Schnittstellen:**
- Benutzt: `NoteEditorSession`, `NotesPageModel`, `NoteStore`, `NoteSearch`, `MarkdownHighlighter`, `ConsolePanel`, `FieldRow`, `ConsoleButtonStyle`, `Color.shoutLive`, `Color.shoutWindow`, `Loc`
- Liefert:
  - `struct NoteEditorView: NSViewRepresentable` — `init(session: NoteEditorSession, autofocus: Bool = false, focusRequest: Int = 0)`
  - `struct NotesView: View` — `init(model: NotesPageModel, store: NoteStore)`

- [ ] **Schritt 1: Den fehlschlagenden Test schreiben**

`Tests/ShoutTests/LocalizationNotesTests.swift`:

```swift
import XCTest

/// Alle neuen Texte der Seite „Notizen“. Ein doppelter Schlüssel bringt schon
/// diesen Test zum Absturz — genau das ist erwünscht, solange es hier passiert.
@MainActor
final class LocalizationNotesTests: XCTestCase {

    private let schluessel = [
        "Notizen",
        "Neue Notiz",
        "Ordner",
        "Jede Notiz ist eine Markdown-Datei in diesem Ordner. Liegt er in iCloud Drive oder einem Obsidian-Vault, findest du die Notizen auch dort.",
        "Im Finder zeigen",
        "Wählen …",
        "Der Ordner ist nicht erreichbar. Änderungen werden zwischengespeichert und landen dort, sobald er wieder da ist.",
        "Notizen durchsuchen",
        "Noch keine Notizen",
        "Keine Treffer",
        "Wähle links eine Notiz oder lege eine neue an.",
        "Diktiere oder tippe eine neue Notiz — sie landet als Datei in deinem Ordner.",
        "Anheften",
        "Lösen",
        "Umbenennen …",
        "Notiz umbenennen",
        "Titel",
        "„%@“ gelöscht",
        "Diese Notiz wurde auch anderswo geändert. Deine Fassung liegt als „%@“ daneben.",
        "Diese Notiz ist nicht mehr im Ordner.",
        "Wieder sichern",
        "Wird aus iCloud geladen …",
        "Unbenannt",
        "(Konflikt)",
        // schon vorhanden, hier mitgeprüft, weil die Seite sie benutzt
        "Löschen",
        "Rückgängig",
        "Umbenennen",
        "Abbrechen",
        "Wählen",
    ]

    override func setUp() {
        super.setUp()
        Loc.shared.apply("en")
    }

    override func tearDown() {
        Loc.shared.apply("system")
        super.tearDown()
    }

    func testAlleNotizTexteSindUebersetzt() {
        for text in schluessel {
            let englisch = Loc.t(text)
            XCTAssertFalse(englisch.isEmpty, "Leere Übersetzung für „\(text)“")
            XCTAssertNotEqual(englisch, text, "Keine englische Fassung für „\(text)“")
        }
    }
}
```

`xcodegen generate`, dann Testbefehl mit `-only-testing:ShoutTests/LocalizationNotesTests`.
Erwartet: FAIL mit „Keine englische Fassung für „Notizen““.

- [ ] **Schritt 2: Prüfen, dass keiner der neuen Schlüssel schon existiert**

```bash
cd /Users/liam/Developer/LIAM/flow-lokal && for k in "Notizen" "Neue Notiz" "Ordner" "Im Finder zeigen" "Wählen …" "Notizen durchsuchen" "Noch keine Notizen" "Keine Treffer" "Anheften" "Lösen" "Umbenennen …" "Notiz umbenennen" "Titel" "Wieder sichern" "Unbenannt" "(Konflikt)"; do printf '%s: ' "$k"; grep -c "^ *\"$k\":" Sources/FlowLokal/Localization.swift; done
```

Erwartet: überall `0`. Steht irgendwo `1`, diesen Schlüssel in Schritt 3
**weglassen** (ein doppelter Schlüssel stürzt ab).

- [ ] **Schritt 3: Englische Einträge einfügen**

In `Sources/FlowLokal/Localization.swift` diese Stelle

```swift
        "Wählen": "Choose",
    ]
}
```

ersetzen durch:

```swift
        "Wählen": "Choose",

        // MARK: - Notizen (Scratchpad)

        "Notizen": "Notes",
        "Neue Notiz": "New Note",
        "Ordner": "Folder",
        "Jede Notiz ist eine Markdown-Datei in diesem Ordner. Liegt er in iCloud Drive oder einem Obsidian-Vault, findest du die Notizen auch dort.":
            "Every note is a Markdown file in this folder. If it lives in iCloud Drive or an Obsidian vault, your notes show up there too.",
        "Im Finder zeigen": "Show in Finder",
        "Wählen …": "Choose…",
        "Der Ordner ist nicht erreichbar. Änderungen werden zwischengespeichert und landen dort, sobald er wieder da ist.":
            "The folder can’t be reached. Changes are kept aside and move there as soon as it’s back.",
        "Notizen durchsuchen": "Search notes",
        "Noch keine Notizen": "No notes yet",
        "Keine Treffer": "No matches",
        "Wähle links eine Notiz oder lege eine neue an.": "Pick a note on the left or create a new one.",
        "Diktiere oder tippe eine neue Notiz — sie landet als Datei in deinem Ordner.":
            "Dictate or type a new note — it’s saved as a file in your folder.",
        "Anheften": "Pin",
        "Lösen": "Unpin",
        "Umbenennen …": "Rename…",
        "Notiz umbenennen": "Rename Note",
        "Titel": "Title",
        "„%@“ gelöscht": "“%@” deleted",
        "Diese Notiz wurde auch anderswo geändert. Deine Fassung liegt als „%@“ daneben.":
            "This note was also changed elsewhere. Your version is saved next to it as “%@”.",
        "Diese Notiz ist nicht mehr im Ordner.": "This note is no longer in the folder.",
        "Wieder sichern": "Save again",
        "Wird aus iCloud geladen …": "Downloading from iCloud…",
        "Unbenannt": "Untitled",
        "(Konflikt)": "(Conflict)",
    ]
}
```

Testbefehl mit `-only-testing:ShoutTests/LocalizationNotesTests`.
Erwartet: `Executed 1 test, with 0 failures`.

- [ ] **Schritt 4: `NoteEditorView` schreiben**

`Sources/FlowLokal/NoteEditorView.swift`:

```swift
import SwiftUI
import AppKit

/// Der Editor einer Notiz: ein `NSTextView`, weil SwiftUIs `TextEditor` die
/// Cursorposition erst ab macOS 15 herausgibt — und das Diktat (Plan 2) genau
/// dorthin muss. Klartext, Markdown nur in der Darstellung.
struct NoteEditorView: NSViewRepresentable {
    @ObservedObject var session: NoteEditorSession
    /// Neue, leere Notiz: sofort hineinschreiben können.
    var autofocus = false
    /// Steigt, wenn die Seite den Fokus in den Editor holen will (⏎ in der Liste).
    var focusRequest = 0

    func makeCoordinator() -> Coordinator { Coordinator(session: session) }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSTextView.scrollableTextView()
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        let textView = scroll.documentView as! NSTextView
        Self.configure(textView)
        textView.delegate = context.coordinator
        textView.textStorage?.delegate = context.coordinator.highlighter
        textView.string = session.note.body
        textView.isEditable = session.status != .placeholder

        let c = context.coordinator
        c.textView = textView
        c.revision = session.externalRevision
        c.focusRequest = focusRequest
        if autofocus {
            DispatchQueue.main.async { textView.window?.makeFirstResponder(textView) }
        }
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        let c = context.coordinator
        guard let textView = c.textView else { return }
        if c.revision != session.externalRevision {
            c.revision = session.externalRevision
            c.replaceText(with: session.note.body)
        }
        textView.isEditable = session.status != .placeholder
        if c.focusRequest != focusRequest {
            c.focusRequest = focusRequest
            DispatchQueue.main.async { textView.window?.makeFirstResponder(textView) }
        }
    }

    private static func configure(_ tv: NSTextView) {
        typealias Style = MarkdownHighlighter.Style
        tv.isRichText = false
        tv.importsGraphics = false
        tv.allowsUndo = true
        // Markdown braucht gerade Anführungszeichen und echte Bindestriche.
        tv.isAutomaticQuoteSubstitutionEnabled = false
        tv.isAutomaticDashSubstitutionEnabled = false
        tv.isAutomaticTextReplacementEnabled = false
        tv.isContinuousSpellCheckingEnabled = true
        tv.usesFindBar = true
        tv.isIncrementalSearchingEnabled = true
        tv.drawsBackground = false
        tv.font = Style.body
        tv.textColor = Style.text
        tv.typingAttributes = Style.baseAttributes
        tv.insertionPointColor = Style.accent
        tv.selectedTextAttributes = [.backgroundColor: Style.accent.withAlphaComponent(0.30)]
        tv.textContainerInset = NSSize(width: 18, height: 16)
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        let session: NoteEditorSession
        let highlighter = MarkdownHighlighter()
        weak var textView: NSTextView?
        var revision = 0
        var focusRequest = 0

        init(session: NoteEditorSession) { self.session = session }

        func textDidChange(_ notification: Notification) {
            guard let tv = notification.object as? NSTextView else { return }
            session.edit(tv.string)
        }

        /// Übernimmt eine Fassung von außen als normale Bearbeitung — so holt ⌘Z
        /// die eigene Fassung zurück. Der Cursor bleibt, so gut es geht, stehen.
        func replaceText(with text: String) {
            guard let tv = textView, tv.string != text else { return }
            let ganz = NSRange(location: 0, length: (tv.string as NSString).length)
            let auswahl = tv.selectedRange()
            if tv.shouldChangeText(in: ganz, replacementString: text) {
                tv.textStorage?.replaceCharacters(in: ganz, with: text)
                tv.didChangeText()
            }
            let laenge = (text as NSString).length
            tv.setSelectedRange(NSRange(location: min(auswahl.location, laenge), length: 0))
        }
    }
}
```

- [ ] **Schritt 5: `NotesView` schreiben**

`Sources/FlowLokal/NotesView.swift`:

```swift
import SwiftUI
import AppKit

/// Seite „Notizen“: oben der Ordner, links die Liste mit Suche, rechts der Editor.
struct NotesView: View {
    @ObservedObject var model: NotesPageModel
    @ObservedObject var store: NoteStore

    @FocusState private var listFocused: Bool
    @FocusState private var searchFocused: Bool
    @State private var renaming: UUID?
    @State private var renameText = ""
    @State private var editorFocus = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            folderPanel
            if store.folderState == .unreachable {
                banner(Loc.t("Der Ordner ist nicht erreichbar. Änderungen werden zwischengespeichert und landen dort, sobald er wieder da ist."))
            }
            HStack(spacing: 0) {
                list.frame(width: 250)
                Rectangle().fill(Color.white.opacity(0.06)).frame(width: 1)
                editor.frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color(white: 0.135)))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.white.opacity(0.07)))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .padding(.horizontal, 28).padding(.top, 42).padding(.bottom, 20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.shoutWindow)
        .overlay(alignment: .bottom) { undoBar }
        .alert(Loc.t("Notiz umbenennen"), isPresented: renameBinding) {
            TextField(Loc.t("Titel"), text: $renameText)
            Button(Loc.t("Umbenennen")) {
                if let id = renaming { model.rename(id, to: renameText) }
                renaming = nil
            }
            Button(Loc.t("Abbrechen"), role: .cancel) { renaming = nil }
        }
        .onDisappear { model.flush() }
    }

    private var renameBinding: Binding<Bool> {
        Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })
    }

    // MARK: - Kopf und Ordner

    private var header: some View {
        HStack {
            Text(Loc.t("Notizen")).font(.system(size: 15, weight: .semibold)).foregroundStyle(Color(white: 0.92))
            Spacer()
            Button {
                model.createNote()
            } label: {
                Label(Loc.t("Neue Notiz"), systemImage: "square.and.pencil")
            }
            .buttonStyle(ConsoleButtonStyle())
            .keyboardShortcut("n", modifiers: .command)
        }
    }

    private var folderPanel: some View {
        ConsolePanel {
            FieldRow(title: Loc.t("Ordner"),
                     help: Loc.t("Jede Notiz ist eine Markdown-Datei in diesem Ordner. Liegt er in iCloud Drive oder einem Obsidian-Vault, findest du die Notizen auch dort.")) {
                HStack(spacing: 8) {
                    Text((store.folder.path as NSString).abbreviatingWithTildeInPath)
                        .font(.system(size: 12, design: .monospaced)).foregroundStyle(Color(white: 0.6))
                        .lineLimit(1).truncationMode(.middle)
                        .frame(maxWidth: 220, alignment: .trailing)
                        .help(store.folder.path)
                    Button(Loc.t("Im Finder zeigen")) { NSWorkspace.shared.open(store.folder) }
                        .buttonStyle(ConsoleButtonStyle())
                        .disabled(store.folderState == .unreachable
                                  || !FileManager.default.fileExists(atPath: store.folder.path))
                    Button(Loc.t("Wählen …")) {
                        if let url = chooseFolder() { model.changeFolder(to: url) }
                    }
                    .buttonStyle(ConsoleButtonStyle())
                }
            }
        }
    }

    private func chooseFolder() -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.prompt = Loc.t("Wählen")
        panel.directoryURL = store.folder
        return panel.runModal() == .OK ? panel.url : nil
    }

    // MARK: - Liste

    private var list: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").font(.system(size: 11)).foregroundStyle(Color(white: 0.45))
                TextField(Loc.t("Notizen durchsuchen"), text: $model.query)
                    .textFieldStyle(.plain).font(.system(size: 12.5))
                    .focused($searchFocused)
                    .onSubmit { listFocused = true; model.moveSelection(by: 0) }
                    .onKeyPress(.escape) { model.query = ""; listFocused = true; return .handled }
                    .onKeyPress(.downArrow) { listFocused = true; model.moveSelection(by: 0); return .handled }
            }
            .padding(.horizontal, 10).padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: 7).fill(Color(white: 0.10)))
            .padding(10)

            listBody
        }
    }

    /// Eigene Fokus-Einheit ohne das Suchfeld: Sonst landete jedes „j“ beim
    /// Tippen in der Suche als Pfeil nach unten.
    private var listBody: some View {
        let ergebnisse = model.results
        return ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 2) {
                    if ergebnisse.isEmpty {
                        Text(model.query.isEmpty ? Loc.t("Noch keine Notizen") : Loc.t("Keine Treffer"))
                            .font(.system(size: 12)).foregroundStyle(Color(white: 0.5)).padding(.top, 20)
                    }
                    ForEach(ergebnisse) { row($0) }
                }
                .padding(.horizontal, 6).padding(.bottom, 8)
            }
            .onChange(of: model.session?.id) { _, id in
                if let id { withAnimation(.easeOut(duration: 0.15)) { proxy.scrollTo(id) } }
            }
        }
        .focusable()
        .focused($listFocused)
        .focusEffectDisabled()
        .onKeyPress(keys: [.downArrow, .upArrow, .return]) { press in
            switch press.key {
            case .downArrow: model.moveSelection(by: 1)
            case .upArrow: model.moveSelection(by: -1)
            default: if model.session != nil { editorFocus += 1 }
            }
            return .handled
        }
        .onKeyPress(characters: CharacterSet(charactersIn: "jkc/f")) { press in
            switch press.characters {
            case "j": model.moveSelection(by: 1)
            case "k": model.moveSelection(by: -1)
            case "c": model.createNote()
            case "/": searchFocused = true
            case "f" where press.modifiers.contains(.command): searchFocused = true
            default: return .ignored
            }
            return .handled
        }
    }

    private func row(_ ergebnis: NoteSearch.Result) -> some View {
        let note = ergebnis.note
        let aktiv = model.session?.id == note.id
        return Button {
            model.select(note.id)
            listFocused = true
        } label: {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 5) {
                    if note.pinned {
                        Image(systemName: "pin.fill").font(.system(size: 9)).foregroundStyle(Color.shoutLive)
                    }
                    if note.isPlaceholder {
                        Image(systemName: "icloud.and.arrow.down").font(.system(size: 10)).foregroundStyle(Color(white: 0.5))
                    }
                    Text(note.title).font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Color(white: 0.92)).lineLimit(1)
                    Spacer(minLength: 4)
                    Text(Self.relative(note.modified)).font(.system(size: 10.5)).foregroundStyle(Color(white: 0.45))
                }
                snippetText(ergebnis)
                    .font(.system(size: 11.5)).foregroundStyle(Color(white: 0.55)).lineLimit(2)
            }
            .padding(.horizontal, 10).padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 8).fill(aktiv ? Color.shoutLive.opacity(0.16) : Color.clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .id(note.id)
        .contextMenu { menu(for: note) }
    }

    private func snippetText(_ ergebnis: NoteSearch.Result) -> Text {
        guard let s = ergebnis.snippet else { return Text(NoteSearch.preview(ergebnis.note.body)) }
        return Text(s.before) + Text(s.match).foregroundColor(Color.shoutLive).bold() + Text(s.after)
    }

    @ViewBuilder private func menu(for note: Note) -> some View {
        Button(note.pinned ? Loc.t("Lösen") : Loc.t("Anheften")) { model.togglePin(note.id) }
        Button(Loc.t("Umbenennen …")) { renameText = note.title; renaming = note.id }
        Button(Loc.t("Im Finder zeigen")) {
            NSWorkspace.shared.activateFileViewerSelecting([store.url(for: note)])
        }
        Divider()
        Button(Loc.t("Löschen"), role: .destructive) { model.delete(note.id) }
    }

    // MARK: - Editor

    @ViewBuilder private var editor: some View {
        if let session = model.session {
            NoteEditorPane(session: session, store: store, focusRequest: editorFocus,
                           onRename: { renameText = session.note.title; renaming = session.id },
                           onTogglePin: { model.togglePin(session.id) },
                           onDelete: { model.delete(session.id) })
                .id(session.id)
        } else {
            VStack(spacing: 10) {
                Image(systemName: "note.text").font(.system(size: 36, weight: .light)).foregroundStyle(Color(white: 0.4))
                Text(store.notes.isEmpty ? Loc.t("Noch keine Notizen") : Loc.t("Wähle links eine Notiz oder lege eine neue an."))
                    .font(.system(size: 14, weight: .medium)).foregroundStyle(Color(white: 0.75))
                if store.notes.isEmpty {
                    Text(Loc.t("Diktiere oder tippe eine neue Notiz — sie landet als Datei in deinem Ordner."))
                        .font(.system(size: 12)).foregroundStyle(Color(white: 0.55))
                        .multilineTextAlignment(.center).frame(maxWidth: 300)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: - Hinweise

    private func banner(_ text: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "externaldrive.badge.exclamationmark").foregroundStyle(Color.shoutLive)
            Text(text).font(.system(size: 12)).foregroundStyle(Color(white: 0.85))
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.shoutLive.opacity(0.10)))
    }

    @ViewBuilder private var undoBar: some View {
        if let geloescht = model.lastDeleted {
            HStack(spacing: 12) {
                Text(Loc.f("„%@“ gelöscht", geloescht.title))
                    .font(.system(size: 12.5)).foregroundStyle(Color(white: 0.9))
                Button(Loc.t("Rückgängig")) { model.undoDelete() }.buttonStyle(ConsoleButtonStyle())
            }
            .padding(.horizontal, 14).padding(.vertical, 9)
            .background(Capsule().fill(Color(white: 0.2)))
            .overlay(Capsule().strokeBorder(Color.white.opacity(0.08)))
            .padding(.bottom, 26)
            .task(id: geloescht) {
                try? await Task.sleep(for: .seconds(8))
                if model.lastDeleted == geloescht { model.dismissUndo() }
            }
        }
    }

    private static func relative(_ datum: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = Locale(identifier: Loc.isGerman ? "de_DE" : "en_US")
        formatter.unitsStyle = .short
        return formatter.localizedString(for: datum, relativeTo: Date())
    }
}

/// Kopfzeile, Hinweise und Editor einer geöffneten Notiz. Eigene View, damit sie
/// die Sitzung beobachtet — der Titel ändert sich beim ersten Sichern.
private struct NoteEditorPane: View {
    @ObservedObject var session: NoteEditorSession
    @ObservedObject var store: NoteStore
    let focusRequest: Int
    let onRename: () -> Void
    let onTogglePin: () -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Button(action: onRename) {
                    HStack(spacing: 6) {
                        Text(session.note.isNew ? Loc.t("Neue Notiz") : session.note.title)
                            .font(.system(size: 14, weight: .semibold)).foregroundStyle(Color(white: 0.92))
                            .lineLimit(1)
                        if !session.note.isNew {
                            Image(systemName: "pencil").font(.system(size: 10)).foregroundStyle(Color(white: 0.45))
                        }
                    }
                }
                .buttonStyle(.plain)
                .disabled(session.note.isNew)
                .help(Loc.t("Umbenennen …"))
                Spacer()
                Group {
                    Button(action: onTogglePin) { Image(systemName: session.note.pinned ? "pin.fill" : "pin") }
                        .help(session.note.pinned ? Loc.t("Lösen") : Loc.t("Anheften"))
                    Button {
                        NSWorkspace.shared.activateFileViewerSelecting([store.url(for: session.note)])
                    } label: { Image(systemName: "folder") }
                        .help(Loc.t("Im Finder zeigen"))
                        .disabled(session.note.isNew)
                    Button(action: onDelete) { Image(systemName: "trash") }
                        .help(Loc.t("Löschen"))
                }
                .buttonStyle(.borderless).foregroundStyle(Color(white: 0.55)).font(.system(size: 12))
            }
            .padding(.horizontal, 16).padding(.vertical, 10)
            Rectangle().fill(Color.white.opacity(0.06)).frame(height: 1)
            notices
            NoteEditorView(session: session,
                           autofocus: session.note.isNew && session.note.body.isEmpty,
                           focusRequest: focusRequest)
        }
    }

    @ViewBuilder private var notices: some View {
        if let name = session.conflictNotice {
            notice(Loc.f("Diese Notiz wurde auch anderswo geändert. Deine Fassung liegt als „%@“ daneben.",
                         (name as NSString).deletingPathExtension),
                   button: Loc.t("OK"), action: session.dismissNotice)
        }
        if session.status == .missing {
            notice(Loc.t("Diese Notiz ist nicht mehr im Ordner."),
                   button: Loc.t("Wieder sichern"), action: session.restoreMissing)
        }
        if session.status == .placeholder {
            notice(Loc.t("Wird aus iCloud geladen …"), button: nil, action: {})
        }
    }

    private func notice(_ text: String, button: String?, action: @escaping () -> Void) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Color.shoutLive).font(.system(size: 11))
            Text(text).font(.system(size: 12)).foregroundStyle(Color(white: 0.85))
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
            if let button { Button(button, action: action).buttonStyle(ConsoleButtonStyle()) }
        }
        .padding(.horizontal, 16).padding(.vertical, 8)
        .background(Color.shoutLive.opacity(0.10))
    }
}
```

- [ ] **Schritt 6: Projekt erzeugen und kompilieren**

```bash
cd /Users/liam/Developer/LIAM/flow-lokal && xcodegen generate
```

Dann den Kompilierlauf der App (siehe Globale Vorgaben).
Erwartet: `** BUILD SUCCEEDED **`. Die Seite ist noch nicht erreichbar — das
verdrahtet Aufgabe 13.

- [ ] **Schritt 7: Commit**

```bash
cd /Users/liam/Developer/LIAM/flow-lokal && git add Sources/FlowLokal/NoteEditorView.swift Sources/FlowLokal/NotesView.swift Sources/FlowLokal/Localization.swift Tests/ShoutTests/LocalizationNotesTests.swift FlowLokal.xcodeproj && git commit -m "Notizen: Editor und Seite, englische Texte"
```

---

### Aufgabe 13: Seite ins Dashboard hängen

**Dateien:**
- Ändern: `Sources/FlowLokal/DashboardView.swift` (Z. 6, nach Z. 50, nach Z. 127, im `switch` nach `case .dateien`)
- Ändern: `Sources/FlowLokal/AppDelegate.swift` (nach Z. 45, `openDashboard` Z. 719 ff., `windowWillClose` Z. 881 ff., `applicationWillTerminate` Z. 931 ff.)

**Schnittstellen:**
- Benutzt: `NotesPageModel(store:)`, `NoteStore(folder:)`, `NotesFolder.current()`, `NotesView(model:store:)`
- Liefert: `DashboardModel.Tab.notizen`; `DashboardView` bekommt den Parameter `notes: NotesPageModel` (direkt nach `meetingRecorder:`).

- [ ] **Schritt 1: Tab, Parameter, Seitenleiste, `switch`**

In `Sources/FlowLokal/DashboardView.swift`:

1. Z. 6 ersetzen:
```swift
    enum Tab: Hashable { case aufnahme, meeting, dateien, notizen, woerterbuch, verlauf, statistik, modelle, sync, unterstuetzen }
```

2. Nach `    @ObservedObject var meetingRecorder: MeetingRecorder` einfügen:
```swift
    /// Seite „Notizen“. Modell und Store leben beim AppDelegate, damit beim
    /// Schließen und Beenden gesichert wird.
    @ObservedObject var notes: NotesPageModel
```

3. Nach `            navRow(.dateien, Loc.t("Dateien"), "doc.text.below.ecg")` einfügen:
```swift
            navRow(.notizen, Loc.t("Notizen"), "note.text")
```

4. Im `switch model.tab` nach dem Block `case .dateien: … onCloseResult: onCloseResult)` einfügen:
```swift
        case .notizen:
            NotesView(model: notes, store: notes.store)
```

- [ ] **Schritt 2: AppDelegate**

In `Sources/FlowLokal/AppDelegate.swift`:

1. Nach `    private let sounds = SoundCues()` einfügen:
```swift
    /// Notizen. Erst beim ersten Öffnen des Dashboards angelegt; der Ordner in
    /// „Dokumente“ entsteht sogar erst mit der ersten gesicherten Notiz.
    private var notesPageStorage: NotesPageModel?
    private var notesPage: NotesPageModel {
        if let page = notesPageStorage { return page }
        let page = NotesPageModel(store: NoteStore(folder: NotesFolder.current()))
        notesPageStorage = page
        return page
    }
```

2. In `openDashboard(_:)`, im Aufruf `DashboardView(…)`, nach
`                meetingRecorder: meetingRecorder,` einfügen:
```swift
                notes: notesPage,
```

3. In `windowWillClose(_:)` nach
`        if closing === onboardingWindow { onboardingWindow = nil }` einfügen:
```swift
        if closing === dashboardWindow { notesPageStorage?.flush() }
```

4. In `applicationWillTerminate(_:)` als erste Zeile einfügen:
```swift
        notesPageStorage?.flush()    // ungesicherter Notiztext, höchstens eine Sekunde alt
```

- [ ] **Schritt 3: Kompilieren und alle Tests laufen lassen**

Kompilierlauf der App (Globale Vorgaben). Erwartet: `** BUILD SUCCEEDED **`.
Dann die ganze Testsuite. Erwartet: keine Fehler, und die neuen Klassen
(`NoteFileTests`, `NoteTitleTests`, `NoteSearchTests`, `NotesFolderTests`,
`NoteFolderWatcherTests`, `NoteStoreTests`, `NoteStoreAktionenTests`,
`NoteStoreKonfliktTests`, `NoteEditorSessionTests`, `NotesPageModelTests`,
`MarkdownHighlighterTests`, `LocalizationNotesTests`) stehen im Ergebnis.

- [ ] **Schritt 4: Commit**

```bash
cd /Users/liam/Developer/LIAM/flow-lokal && git add Sources/FlowLokal/DashboardView.swift Sources/FlowLokal/AppDelegate.swift && git commit -m "Notizen: Seite im Dashboard, Sichern beim Schließen und Beenden"
```

---

### Aufgabe 14: Offene Punkte und Prüfliste

**Dateien:**
- Ändern: `OFFEN.md` (Eintrag „Scratchpad am Mac“)

- [ ] **Schritt 1: `OFFEN.md` nachziehen**

Den Eintrag, der mit `- [ ] **Scratchpad am Mac**` beginnt, am Ende um diesen
Satz ergänzen (der Haken bleibt offen, Plan 2 und 3 fehlen noch):

```markdown
 **Teil 1 (Grundlage) gebaut:** Seite „Notizen“ mit Liste, Suche, Editor (Markdown-Hervorhebung), Anheften, Umbenennen, Papierkorb mit Rückgängig, Ordnerwahl; Konfliktdatei bei Änderung von außen, Puffer bei fehlendem Ordner, iCloud-Platzhalter. Plan: `docs/superpowers/plans/2026-10-05-scratchpad-1-grundlage.md`. **In der laufenden App noch nicht geprüft** (Prüfliste im Plan, Aufgabe 14).
```

- [ ] **Schritt 2: Commit**

```bash
cd /Users/liam/Developer/LIAM/flow-lokal && git add OFFEN.md && git commit -m "OFFEN: Scratchpad Teil 1 gebaut"
```

- [ ] **Schritt 3: Prüfliste für das nächste Release (nicht selbst ausführen)**

Die App wird hier nicht gestartet. Nach dem nächsten Release (aus
`/Applications`) prüft der Mensch:

- [ ] Seite „Notizen“ erscheint nach „Dateien“; ohne Notizen steht der leere Zustand da, und in „Dokumente“ ist noch **kein** Ordner entstanden.
- [ ] ⌘N, tippen: Nach etwa einer Sekunde steht die Datei im Ordner, der Titel in der Liste wandert bis zum dritten Wort mit und bleibt dann stehen.
- [ ] Überschrift, **fett**, *kursiv*, `code`, `- [x]` sehen im Editor richtig aus; die Datei im Finder/TextEdit ist reiner Text.
- [ ] Anführungszeichen bleiben gerade (`"`), `--` wird nicht zum Gedankenstrich.
- [ ] Suche findet „cafe“ in „Café“, der Treffer ist im Ausschnitt hervorgehoben.
- [ ] j/k, ↑/↓, ⏎ (in den Editor), c, / funktionieren in der Liste — und **nicht**, während im Suchfeld getippt wird.
- [ ] Anheften: Notiz springt nach oben, `pinned: true` steht in der Datei.
- [ ] Umbenennen über den Titel und über das Kontextmenü, auch nur Groß-/Kleinschreibung.
- [ ] Löschen → Datei im Papierkorb, „Rückgängig“ holt sie zurück; nach 8 s verschwindet der Balken.
- [ ] Datei in TextEdit ändern, während sie in shout. offen und gesichert ist → Editor übernimmt; während ungesichert getippt wird → „(Konflikt)“-Datei und Hinweis.
- [ ] Datei im Finder löschen, während sie offen ist → „Nicht mehr im Ordner“, „Wieder sichern“ legt sie neu an.
- [ ] Ordner auf einen Obsidian-Vault stellen: `tags` im Frontmatter überleben das Bearbeiten in shout.
- [ ] Ordner auf einem USB-Stick, Stick abziehen, weitertippen → Balken „nicht erreichbar“; Stick wieder anstecken → nach höchstens fünf Sekunden liegt die Notiz dort.
- [ ] Ordner in iCloud Drive mit „Mac-Speicher optimieren“: ausgelagerte Notiz zeigt die Wolke und „Wird aus iCloud geladen …“.
- [ ] Englische Oberfläche: alle Texte der Seite sind englisch.
- [ ] Beenden mit ⌘Q direkt nach dem Tippen → Text ist in der Datei.
