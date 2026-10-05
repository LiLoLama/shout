# Scratchpad, Teil 2: Panel — Umsetzungsplan

> **Für agentische Ausführung:** ERFORDERLICHER UNTER-SKILL: `superpowers:subagent-driven-development` (empfohlen) oder `superpowers:executing-plans`, Aufgabe für Aufgabe. Die Schritte nutzen Checkbox-Syntax (`- [ ]`).

Entwurf: `docs/superpowers/specs/2026-10-05-scratchpad-design.md` (Abschnitt 2, Teile von 4)
Vorgänger: `docs/superpowers/plans/2026-10-05-scratchpad-1-grundlage.md` (fertig, auf `main`).
Dies ist **Plan 2 von 3**.

**Ziel:** Ein schwebender Notizblock mit Tabs, der der App davor nicht den
Fokus nimmt; eine eigene Taste zum Ein-/Ausblenden und Hineindiktieren; eine
Eingangs-Taste, die ohne Fenster in `Eingang.md` diktiert; die normale
Diktiertaste schreibt an den Cursor, wenn das Panel den Fokus hat.

**Architektur:** Zuerst Vorarbeiten, die der Abschluss-Review von Teil 1
verlangt hat: Eine `NoteSessionRegistry` sorgt dafür, dass es pro Notiz genau
eine `NoteEditorSession` gibt (Seite und Panel teilen sie); die Sitzung bekommt
eine Einfüge-API für Diktate, mehrere Editoren bleiben synchron, jeder Editor
hat sein eigenes Rückgängig, und die Hervorhebung arbeitet absatzweise. Darauf
setzen reine Bausteine (`DictationInsertion`, `NoteInbox`, `HotkeyPressClassifier`,
`DictationTarget`, `PanelPlacement`) und das `ScratchpadModel` (Tabs) auf. Das
Panel (`ScratchpadPanel` + Controller + SwiftUI-Ansicht) und die Carbon-Tasten
(`GlobalHotkey`) werden zuletzt im `AppDelegate` verdrahtet.

**Technik:** Swift 5.10, SwiftUI + AppKit (`NSPanel`, `NSTextView`), Carbon
(`RegisterEventHotKey`), CoreServices (FSEvents), XCTest, XcodeGen. Keine neuen Pakete.

## Globale Vorgaben

- **Umlaute immer als echtes UTF-8** — `ä ö ü Ä Ö Ü ß`, nie `ae`/`oe`/`ue`/`ss`.
  Swift-Bezeichner in Tests folgen dem Projektbrauch (`testLoeschen…`).
- **Code, Kommentare, Commits und Oberfläche auf Deutsch.**
- **macOS 14** ist die Untergrenze; `SWIFT_VERSION` des App-Ziels ist **5.10**.
- **Kein Text geht still verloren.** Das ist die Hauptregel des Features. Wo
  ein Schritt sie nicht sicherstellt, ist es ein Fehler — melden, nicht umgehen.
- **Oberflächentexte gehen durch `Loc.t` / `Loc.f`** und brauchen einen Eintrag
  in `Localization.english` (`Sources/FlowLokal/Localization.swift`). Ein
  **doppelter Schlüssel stürzt zur Laufzeit ab** — vor dem Einfügen mit `grep`
  prüfen. Typografische Zeichen („…“, „ …“) im Schlüssel exakt wie im Aufruf.
  Neue Schlüssel kommen zusätzlich in die Liste in
  `Tests/ShoutTests/LocalizationNotesTests.swift`.
- **Jede getestete Datei aus `Sources/FlowLokal/` muss einzeln in die
  Quellenliste des Testziels** (`project.yml`, Abschnitt `ShoutTests:` ab
  Z. 327; die Notiz-Dateien stehen dort ab Z. 377). Danach `xcodegen generate`.
  `FlowLokal.xcodeproj` ist gitignored — `git add` darauf tut nichts.
- **Commits:** nur ausdrücklich genannte Pfade stagen, nie `git add -A`,
  `git add .` oder `git commit -a`. `Support/launch-video/` gehört dem Nutzer
  und wird nie committet, `.superpowers/` auch nicht. Jede Commit-Nachricht
  endet mit der Zeile `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`
  (zweites `-m`).
- **Die App wird nicht gestartet.** Geprüft wird über Tests und einen Kompilierlauf.
- Testbefehl (ganze Suite):
  ```bash
  cd /Users/liam/Developer/LIAM/flow-lokal && xcodebuild test -project FlowLokal.xcodeproj -scheme ShoutTests -destination 'platform=macOS,arch=arm64' -skipPackagePluginValidation -skipMacroValidation 2>&1 | tail -25
  ```
  Eine Klasse: denselben Befehl mit `-only-testing:ShoutTests/<Klasse>` vor `2>&1`.
- Kompilierlauf der App:
  ```bash
  cd /Users/liam/Developer/LIAM/flow-lokal && xcodebuild build -project FlowLokal.xcodeproj -scheme FlowLokal -configuration Debug -destination 'platform=macOS,arch=arm64' -skipPackagePluginValidation -skipMacroValidation CODE_SIGNING_ALLOWED=NO 2>&1 | tail -20
  ```
  Muss mit `** BUILD SUCCEEDED **` enden.

## Nicht in diesem Plan

Ablegen in die vorige App, Transforms, Versionen, Bilder, Backup der neuen
Einstellungen (Plan 3). **Ordner-I/O abseits des Hauptstrangs** ist bewusst
verschoben: Es betrifft nur hängende Netzlaufwerke, die nicht beworben werden,
und ein asynchrones Einlesen im Store ist ein eigener, riskanter Umbau. Hier
kommt nur der billige Teil: Der Watcher meldet nur noch Änderungen, die den
Notizordner selbst betreffen (Aufgabe 6).

---

## Dateiaufteilung

| Datei | Verantwortung |
|---|---|
| `Sources/FlowLokal/DictationInsertion.swift` (neu) | Rein: Leerzeichen vor einem Diktat am Cursor. |
| `Sources/FlowLokal/NoteInbox.swift` (neu) | Rein: Tagesüberschrift und Eintrag für die Eingangs-Notiz. |
| `Sources/FlowLokal/MarkdownHighlighter.swift` (ändern) | Absatzweise neu gestalten, ganz nur bei Codeblöcken. |
| `Sources/FlowLokal/NoteEditorSession.swift` (ändern) | Einfüge-API, Cursor, angehängte Editoren, `editRevision`. |
| `Sources/FlowLokal/NoteSessionRegistry.swift` (neu) | Eine Sitzung pro Notiz; Halter zählen; alle sichern; Rettungskopien. |
| `Sources/FlowLokal/NotesPageModel.swift` (ändern) | Sitzungen über die Registry; Ordnerwechsel für alle. |
| `Sources/FlowLokal/NoteEditorView.swift` (ändern) | Eigenes Rückgängig, Einfügen am Cursor, Abgleich zweier Editoren, Esc im Panel. |
| `Sources/FlowLokal/NoteNoticesView.swift` (neu) | Hinweise einer Sitzung (aus `NotesView` herausgelöst), für Seite und Panel. |
| `Sources/FlowLokal/NotesView.swift` (ändern) | Nutzt `NoteNoticesView`; später Einstellungen und Hinweiskarte. |
| `Sources/FlowLokal/NoteStore.swift` (ändern) | `create(title:body:pinned:)`, `onRename`, Watcher-Filter, Download nur einmal anstoßen. |
| `Sources/FlowLokal/NoteFolderWatcher.swift` (ändern) | Liefert die geänderten Pfade; reine Prüfung `concernsFolder`. |
| `Sources/FlowLokal/ScratchpadModel.swift` (neu) | Tabs, Öffnen-Verhalten, Diktat in Notiz, Eingang. |
| `Sources/FlowLokal/HotkeyCombo.swift` (neu) | Tastenkombination (NSEvent ↔ Carbon), Vorgaben, Anzeige. |
| `Sources/FlowLokal/HotkeyPressClassifier.swift` (neu) | Rein: Tippen oder Halten. |
| `Sources/FlowLokal/DictationTarget.swift` (neu) | Rein: Wohin ein Diktat geht. |
| `Sources/FlowLokal/ScratchpadSettings.swift` (neu) | Einstellungen: aktiv, Tasten, Öffnen-Verhalten, Prüfung. |
| `Sources/FlowLokal/GlobalHotkey.swift` (neu) | Carbon-`RegisterEventHotKey` mit Drücken/Loslassen. |
| `Sources/FlowLokal/PanelPlacement.swift` (neu) | Rein: Panel-Rahmen als Anteil des Bildschirms. |
| `Sources/FlowLokal/ScratchpadPanel.swift` (neu) | `NSPanel`-Unterklasse und Controller (Ein-/Ausblenden, Rahmen merken). |
| `Sources/FlowLokal/ScratchpadView.swift` (neu) | SwiftUI: Tabs, Liste, Editoren, Fußleiste, Tastenkürzel. |
| `Sources/FlowLokal/LearnedToast.swift` (ändern) | Zusätzlich ein schlichter Hinweis mit Aktion. |
| `Sources/FlowLokal/AppDelegate.swift` (ändern) | Verdrahtung: Tasten, Ziel, Zustellen, Eingang, Menü, Beenden. |
| `Sources/FlowLokal/Localization.swift` (ändern) | Englische Einträge. |
| Tests in `Tests/ShoutTests/` (neu): `DictationInsertionTests`, `NoteInboxTests`, `MarkdownHighlighterIncrementalTests`, `NoteEditorSessionInsertTests`, `NoteSessionRegistryTests`, `NoteStoreScratchpadTests`, `NoteFolderWatcherFilterTests`, `ScratchpadModelTests`, `HotkeyTests`, `PanelPlacementTests` | |

---

### Aufgabe 1: Reine Bausteine — Leerzeichen beim Einfügen, Eingangs-Notiz

**Dateien:**
- Neu: `Sources/FlowLokal/DictationInsertion.swift`, `Sources/FlowLokal/NoteInbox.swift`
- Neu: `Tests/ShoutTests/DictationInsertionTests.swift`, `Tests/ShoutTests/NoteInboxTests.swift`
- Ändern: `project.yml` (nach `- path: Sources/FlowLokal/MarkdownHighlighter.swift`)

**Schnittstellen:**
- Benutzt: nichts (nur Foundation)
- Liefert:
  - `enum DictationInsertion { static func text(_ text: String, after previous: Character?) -> String }`
  - `enum NoteInbox { static func dayHeading(for: Date, locale: Locale, timeZone: TimeZone = .current) -> String; static func appendix(to body: String, text: String, date: Date, locale: Locale, timeZone: TimeZone = .current) -> String; static func lastHeading(in body: String) -> String? }`

- [ ] **Schritt 1: Die fehlschlagenden Tests schreiben**

`Tests/ShoutTests/DictationInsertionTests.swift`:

```swift
import XCTest

/// Ein Diktat am Cursor darf nicht an das Wort davor kleben — und vor einem
/// Satzzeichen oder nach einer öffnenden Klammer steht kein Leerzeichen.
final class DictationInsertionTests: XCTestCase {

    func testAmAnfangOhneLeerzeichen() {
        XCTAssertEqual(DictationInsertion.text("Hallo", after: nil), "Hallo")
    }

    func testNachWortMitLeerzeichen() {
        XCTAssertEqual(DictationInsertion.text("Welt", after: "o"), " Welt")
    }

    func testNachLeerraumOhneLeerzeichen() {
        XCTAssertEqual(DictationInsertion.text("Welt", after: " "), "Welt")
        XCTAssertEqual(DictationInsertion.text("Welt", after: "\n"), "Welt")
    }

    func testVorSatzzeichenOhneLeerzeichen() {
        XCTAssertEqual(DictationInsertion.text(", und dann", after: "o"), ", und dann")
        XCTAssertEqual(DictationInsertion.text(".", after: "o"), ".")
    }

    func testNachOeffnenderKlammerOderAnfuehrungOhneLeerzeichen() {
        XCTAssertEqual(DictationInsertion.text("Welt", after: "("), "Welt")
        XCTAssertEqual(DictationInsertion.text("Welt", after: "„"), "Welt")
    }

    func testLeererTextBleibtLeer() {
        XCTAssertEqual(DictationInsertion.text("", after: "o"), "")
    }
}
```

`Tests/ShoutTests/NoteInboxTests.swift`:

```swift
import XCTest

/// Die Eingangs-Notiz: unten anhängen, eine Überschrift pro Tag.
final class NoteInboxTests: XCTestCase {

    private let de = Locale(identifier: "de_DE")
    private let en = Locale(identifier: "en_US")
    private let berlin = TimeZone(identifier: "Europe/Berlin")!

    /// UTC-Zeitpunkt; in Berlin (Sommerzeit) zwei Stunden später.
    private func utc(_ text: String) -> Date { ISO8601DateFormatter().date(from: text)! }

    func testUeberschriftDeutsch() {
        XCTAssertEqual(NoteInbox.dayHeading(for: utc("2026-10-05T12:32:00Z"), locale: de, timeZone: berlin),
                       "## Montag, 5. Oktober 2026")
    }

    func testUeberschriftEnglisch() {
        XCTAssertEqual(NoteInbox.dayHeading(for: utc("2026-10-05T12:32:00Z"), locale: en, timeZone: berlin),
                       "## Monday, October 5, 2026")
    }

    func testLeererEingang() {
        let anhang = NoteInbox.appendix(to: "", text: "Milch kaufen", date: utc("2026-10-05T12:32:00Z"),
                                        locale: de, timeZone: berlin)
        XCTAssertEqual(anhang, "## Montag, 5. Oktober 2026\n- **14:32** Milch kaufen\n")
    }

    func testGleicherTagOhneNeueUeberschrift() {
        let body = "## Montag, 5. Oktober 2026\n- **14:32** Milch kaufen\n"
        let anhang = NoteInbox.appendix(to: body, text: "Brot", date: utc("2026-10-05T13:10:00Z"),
                                        locale: de, timeZone: berlin)
        XCTAssertEqual(anhang, "- **15:10** Brot\n")
    }

    func testNeuerTagMitLeerzeileDavor() {
        let body = "## Montag, 5. Oktober 2026\n- **14:32** Milch kaufen\n"
        let anhang = NoteInbox.appendix(to: body, text: "Termin", date: utc("2026-10-06T07:00:00Z"),
                                        locale: de, timeZone: berlin)
        XCTAssertEqual(anhang, "\n## Dienstag, 6. Oktober 2026\n- **09:00** Termin\n")
    }

    func testTextOhneZeilenendeAmSchluss() {
        let anhang = NoteInbox.appendix(to: "Notiz", text: "x", date: utc("2026-10-05T12:32:00Z"),
                                        locale: de, timeZone: berlin)
        XCTAssertEqual(anhang, "\n\n## Montag, 5. Oktober 2026\n- **14:32** x\n")
    }

    func testMehrzeiligEingerueckt() {
        let anhang = NoteInbox.appendix(to: "", text: "Erste Zeile\nzweite Zeile", date: utc("2026-10-05T12:32:00Z"),
                                        locale: de, timeZone: berlin)
        XCTAssertEqual(anhang, "## Montag, 5. Oktober 2026\n- **14:32** Erste Zeile\n  zweite Zeile\n")
    }

    func testLetzteUeberschrift() {
        XCTAssertEqual(NoteInbox.lastHeading(in: "# Titel\n## A\ntext\n## B\n"), "## B")
        XCTAssertNil(NoteInbox.lastHeading(in: "nur Text"))
    }
}
```

- [ ] **Schritt 2: Eintragen und Tests laufen lassen**

In `project.yml` nach `      - path: Sources/FlowLokal/MarkdownHighlighter.swift`:

```yaml
      # Scratchpad, Teil 2
      - path: Sources/FlowLokal/DictationInsertion.swift
      - path: Sources/FlowLokal/NoteInbox.swift
```

```bash
cd /Users/liam/Developer/LIAM/flow-lokal && touch Sources/FlowLokal/DictationInsertion.swift Sources/FlowLokal/NoteInbox.swift && xcodegen generate
```

Testbefehl mit `-only-testing:ShoutTests/DictationInsertionTests -only-testing:ShoutTests/NoteInboxTests`.
Erwartet: Build-Fehler „cannot find 'DictationInsertion' in scope“.

- [ ] **Schritt 3: Implementieren**

`Sources/FlowLokal/DictationInsertion.swift`:

```swift
import Foundation

/// Wie ein Diktat an den Cursor anschließt: mit einem Leerzeichen, wenn es sonst
/// am Wort davor klebte; ohne, wenn davor schon Leerraum oder eine öffnende
/// Klammer/Anführung steht oder das Diktat mit einem Satzzeichen beginnt.
enum DictationInsertion {

    static func text(_ text: String, after previous: Character?) -> String {
        guard let previous, let erstes = text.first else { return text }
        if previous.isWhitespace { return text }
        if ",.;:!?)]}…".contains(erstes) { return text }
        if "([{\"„‚'“".contains(previous) { return text }
        return " " + text
    }
}
```

`Sources/FlowLokal/NoteInbox.swift`:

```swift
import Foundation

/// Die Eingangs-Notiz: Diktate der Eingangs-Taste werden unten angehängt, unter
/// einer Überschrift pro Tag. Rein — der Aufrufer hängt das Ergebnis ans Ende.
enum NoteInbox {

    /// „## Montag, 5. Oktober 2026“ bzw. „## Monday, October 5, 2026“.
    static func dayHeading(for date: Date, locale: Locale, timeZone: TimeZone = .current) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = timeZone
        formatter.setLocalizedDateFormatFromTemplate("EEEEdMMMMyyyy")
        return "## " + formatter.string(from: date)
    }

    /// Was ans Ende von `body` gehört: bei Bedarf eine Leerzeile und die neue
    /// Tagesüberschrift, dann „- **14:32** Diktat“. Weitere Zeilen eines
    /// Diktats stehen eingerückt unter dem Spiegelstrich.
    static func appendix(to body: String, text: String, date: Date, locale: Locale,
                         timeZone: TimeZone = .current) -> String {
        let ueberschrift = dayHeading(for: date, locale: locale, timeZone: timeZone)
        let uhr = DateFormatter()
        uhr.locale = Locale(identifier: "en_US_POSIX")
        uhr.timeZone = timeZone
        uhr.dateFormat = "HH:mm"

        let zeilen = text.trimmingCharacters(in: .whitespacesAndNewlines)
            .split(whereSeparator: \.isNewline)
            .map(String.init)
        var eintrag = "- **\(uhr.string(from: date))** " + (zeilen.first ?? "")
        for zeile in zeilen.dropFirst() { eintrag += "\n  " + zeile }

        let leer = body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        var ergebnis = ""
        if !leer && !body.hasSuffix("\n") { ergebnis += "\n" }
        if lastHeading(in: body) != ueberschrift {
            if !leer { ergebnis += "\n" }
            ergebnis += ueberschrift + "\n"
        }
        return ergebnis + eintrag + "\n"
    }

    /// Die letzte „## “-Überschrift im Text.
    static func lastHeading(in body: String) -> String? {
        body.split(whereSeparator: \.isNewline)
            .last { $0.hasPrefix("## ") }
            .map { String($0).trimmingCharacters(in: .whitespaces) }
    }
}
```

- [ ] **Schritt 4: Tests laufen lassen**

Erwartet: `Executed 14 tests, with 0 failures`.

- [ ] **Schritt 5: Commit**

```bash
cd /Users/liam/Developer/LIAM/flow-lokal && git add project.yml Sources/FlowLokal/DictationInsertion.swift Sources/FlowLokal/NoteInbox.swift Tests/ShoutTests/DictationInsertionTests.swift Tests/ShoutTests/NoteInboxTests.swift && git commit -m "Scratchpad: Leerzeichen beim Einfügen, Eingangs-Notiz mit Tagesüberschrift" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Aufgabe 2: Hervorhebung absatzweise

Die Eingangs-Notiz wächst ohne Ende; heute gestaltet jede Taste den ganzen Text
neu (gemessen ≈ 50 ms pro Taste bei 50 000 Zeichen). Alle Regeln außer dem
Codeblock-Zaun sind zeilengebunden — ohne Zaun reicht der Absatz um die
Änderung. Mit Zaun (oder wenn gerade einer verschwand) bleibt es beim ganzen Text.

**Dateien:**
- Ändern: `Sources/FlowLokal/MarkdownHighlighter.swift`
- Neu: `Tests/ShoutTests/MarkdownHighlighterIncrementalTests.swift`

**Schnittstellen:**
- Benutzt: die bestehenden Regeln und `Style`
- Liefert: `static func apply(to: NSTextStorage)` (unverändert, ganzer Text), neu
  `static func apply(to: NSTextStorage, in: NSRange)`. Der Delegate gestaltet nur
  noch den Absatz um `editedRange` neu, außer ein Zaun ist (oder war) im Text.

- [ ] **Schritt 1: Den fehlschlagenden Test schreiben**

`Tests/ShoutTests/MarkdownHighlighterIncrementalTests.swift`:

```swift
import XCTest
import AppKit

/// Absatzweise gestaltet muss genau dasselbe herauskommen wie ganz gestaltet.
final class MarkdownHighlighterIncrementalTests: XCTestCase {

    /// Vergleicht die Attribute Zeichen für Zeichen.
    private func gleicheAttribute(_ a: NSTextStorage, _ b: NSTextStorage) -> Bool {
        guard a.string == b.string else { return false }
        for i in 0..<a.length {
            let x = a.attributes(at: i, effectiveRange: nil) as NSDictionary
            let y = b.attributes(at: i, effectiveRange: nil) as NSDictionary
            if x != y { return false }
        }
        return true
    }

    private func pruefe(_ s: NSTextStorage, _ hinweis: String, file: StaticString = #filePath, line: UInt = #line) {
        let vergleich = NSTextStorage(string: s.string)
        MarkdownHighlighter.apply(to: vergleich)
        XCTAssertTrue(gleicheAttribute(s, vergleich), "\(hinweis): \(s.string.debugDescription)", file: file, line: line)
    }

    func testBearbeitungenWieGanzGestaltet() {
        let hervorhebung = MarkdownHighlighter()
        let s = NSTextStorage(string: "# Titel\nText mit **fett** und *kursiv*\n- [ ] offen\n- [x] erledigt\n> Zitat\n[Link](https://x.de)\n")
        s.delegate = hervorhebung
        MarkdownHighlighter.apply(to: s)

        // (Anteil der Länge als Ort, Länge des ersetzten Bereichs, neuer Text)
        let bearbeitungen: [(Double, Int, String)] = [
            (0.3, 0, "Neu "),
            (0.0, 2, ""),
            (0.5, 3, "\n## Zwei\n"),
            (0.8, 0, "**x**"),
            (0.2, 5, "`code` "),
            (0.6, 1, ""),
            (1.0, 0, "\n```\nblock **nicht fett**\n```\n"),
            (0.97, 0, "nach dem Block"),
        ]
        for (anteil, laenge, text) in bearbeitungen {
            let ort = Int(Double(s.length) * anteil)
            s.replaceCharacters(in: NSRange(location: ort, length: min(laenge, s.length - ort)), with: text)
            pruefe(s, "nach Bearbeitung bei \(ort)")
        }
    }

    /// Verschwindet der letzte Zaun, muss der frühere Codeblock wieder normal aussehen.
    func testEntfernterZaunGestaltetAllesNeu() {
        let hervorhebung = MarkdownHighlighter()
        let s = NSTextStorage(string: "Vorher\n```\n**fett?**\n```\nNachher")
        s.delegate = hervorhebung
        MarkdownHighlighter.apply(to: s)
        let zaun = (s.string as NSString).range(of: "```")
        s.replaceCharacters(in: zaun, with: "")
        pruefe(s, "nach Entfernen des Zauns")
    }

    func testBereichGestaltetNurDiesenAbsatz() {
        let s = NSTextStorage(string: "**eins**\n**zwei**")
        let zweite = (s.string as NSString).range(of: "**zwei**")
        MarkdownHighlighter.apply(to: s, in: zweite)
        let fett = { (i: Int) in NSFontManager.shared.traits(of: s.attribute(.font, at: i, effectiveRange: nil) as! NSFont).contains(.boldFontMask) }
        XCTAssertTrue(fett(zweite.location + 3))
        XCTAssertFalse(fett(3))
    }
}
```

- [ ] **Schritt 2: Test laufen lassen**

`xcodegen generate`, Testbefehl mit `-only-testing:ShoutTests/MarkdownHighlighterIncrementalTests`.
Erwartet: Build-Fehler „extra argument 'in' in call“ (es gibt `apply(to:in:)` noch nicht).

- [ ] **Schritt 3: Umbauen**

In `Sources/FlowLokal/MarkdownHighlighter.swift`:

1. Den Delegate ersetzen. Alt:

```swift
    func textStorage(_ textStorage: NSTextStorage, didProcessEditing editedMask: NSTextStorageEditActions,
                     range editedRange: NSRange, changeInLength delta: Int) {
        guard editedMask.contains(.editedCharacters), shouldSkip?() != true else { return }
        Self.apply(to: textStorage)
    }
```

Neu:

```swift
    /// Stand vor der letzten Änderung: Gab es einen Codeblock-Zaun? Verschwindet
    /// er, muss der ganze Text neu, sonst blieben frühere Blockzeilen monospace.
    private var hatteZaun = false

    func textStorage(_ textStorage: NSTextStorage, didProcessEditing editedMask: NSTextStorageEditActions,
                     range editedRange: NSRange, changeInLength delta: Int) {
        guard editedMask.contains(.editedCharacters), shouldSkip?() != true else { return }
        let ns = textStorage.string as NSString
        let hatZaun = ns.range(of: "```").location != NSNotFound
        defer { hatteZaun = hatZaun }
        // Ein Zaun verändert die Darstellung bis zum nächsten — dann alles.
        if hatZaun || hatteZaun {
            Self.apply(to: textStorage)
            return
        }
        let start = min(editedRange.location, ns.length)
        let ende = min(NSMaxRange(editedRange), ns.length)
        Self.apply(to: textStorage, in: ns.paragraphRange(for: NSRange(location: start, length: ende - start)))
    }
```

2. Die bisherige `static func apply(to storage: NSTextStorage)` aufteilen. Ihr
Kopf lautet heute:

```swift
    static func apply(to storage: NSTextStorage) {
        let ns = storage.string as NSString
        let ganz = NSRange(location: 0, length: ns.length)
        storage.setAttributes(Style.baseAttributes, range: ganz)
        guard ns.length > 0 else { return }
        let text = storage.string
```

Ersetzen durch:

```swift
    /// Gestaltet den ganzen Text.
    static func apply(to storage: NSTextStorage) {
        apply(to: storage, in: NSRange(location: 0, length: (storage.string as NSString).length))
    }

    /// Gestaltet nur `bereich`. Der Bereich muss an Absatzgrenzen beginnen und
    /// enden — alle Regeln außer dem Zaun sind zeilengebunden.
    static func apply(to storage: NSTextStorage, in bereich: NSRange) {
        let ns = storage.string as NSString
        let ganz = NSIntersectionRange(bereich, NSRange(location: 0, length: ns.length))
        storage.setAttributes(Style.baseAttributes, range: ganz)
        guard ganz.length > 0 else { return }
        let text = storage.string
```

Der Rest der Funktion bleibt **unverändert** — er verwendet schon überall `ganz`
(`fence.matches(in: text, range: ganz)`, `re.matches(in: text, range: ganz)`).

- [ ] **Schritt 4: Alle Hervorhebungs-Tests laufen lassen**

Testbefehl mit `-only-testing:ShoutTests/MarkdownHighlighterIncrementalTests -only-testing:ShoutTests/MarkdownHighlighterTests`.
Erwartet: 0 Fehler (3 neue + die bestehenden).

- [ ] **Schritt 5: Commit**

```bash
cd /Users/liam/Developer/LIAM/flow-lokal && git add Sources/FlowLokal/MarkdownHighlighter.swift Tests/ShoutTests/MarkdownHighlighterIncrementalTests.swift && git commit -m "Notizen: Hervorhebung nur noch für den bearbeiteten Absatz" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Aufgabe 3: Sitzung — Einfügen am Cursor, mehrere Editoren

**Dateien:**
- Ändern: `Sources/FlowLokal/NoteEditorSession.swift`
- Neu: `Tests/ShoutTests/NoteEditorSessionInsertTests.swift`
- Ändern: `project.yml` (`DictationInsertion.swift` steht schon im Testziel)

**Schnittstellen:**
- Benutzt: `DictationInsertion.text(_:after:)`
- Liefert (in `NoteEditorSession.swift`):
  - `@MainActor protocol NoteTextEditing: AnyObject { func insertText(_ text: String, at point: NoteEditorSession.InsertionPoint) -> Bool }`
  - `NoteEditorSession.InsertionPoint` (`.cursor`, `.end`)
  - `@Published private(set) var editRevision: Int`, `private(set) weak var lastEditSource: AnyObject?`,
    `private(set) weak var editor: NoteTextEditing?`, `private(set) var lastSelection: NSRange`
  - `func edit(_ text: String, from source: AnyObject? = nil)` (ersetzt `edit(_:)`; alte Aufrufe kompilieren weiter)
  - `func attach(editor: NoteTextEditing)`, `func detach(editor: NoteTextEditing)`, `func selectionChanged(_ range: NSRange)`
  - `@discardableResult func insert(_ text: String, at point: InsertionPoint) -> Bool`

- [ ] **Schritt 1: Den fehlschlagenden Test schreiben**

`Tests/ShoutTests/NoteEditorSessionInsertTests.swift`:

```swift
import XCTest

@MainActor
final class NoteEditorSessionInsertTests: XCTestCase {

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

    /// Ein Editor-Ersatz, der nur festhält, was ihm zum Einfügen gegeben wurde.
    private final class FakeEditor: NoteTextEditing {
        var aufrufe: [(String, NoteEditorSession.InsertionPoint)] = []
        var nimmtAn = true
        func insertText(_ text: String, at point: NoteEditorSession.InsertionPoint) -> Bool {
            aufrufe.append((text, point))
            return nimmtAn
        }
    }

    private func sitzung(_ text: String) throws -> NoteEditorSession {
        try u.schreibe("X.md", text)
        let s = u.store()
        return NoteEditorSession(note: s.notes[0], store: s, saveDelay: 60)
    }

    func testOhneEditorAmCursorMitLeerzeichen() throws {
        let s = try sitzung("Hallo Welt")
        s.selectionChanged(NSRange(location: 5, length: 0))
        XCTAssertTrue(s.insert("schöne", at: .cursor))
        XCTAssertEqual(s.note.body, "Hallo schöne Welt")
        XCTAssertEqual(s.status, .dirty)
        XCTAssertEqual(s.lastSelection, NSRange(location: 12, length: 0))
        XCTAssertEqual(s.editRevision, 1)
        XCTAssertNil(s.lastEditSource)
    }

    func testOhneEditorAmEnde() throws {
        let s = try sitzung("a")
        s.selectionChanged(NSRange(location: 0, length: 0))
        s.insert("\n- b", at: .end)
        XCTAssertEqual(s.note.body, "a\n- b")
    }

    /// Ein gemeldeter Cursor hinter dem Textende (Text wurde inzwischen kürzer) wird geklemmt.
    func testCursorWirdGeklemmt() throws {
        let s = try sitzung("ab")
        s.selectionChanged(NSRange(location: 99, length: 0))
        s.insert("c", at: .cursor)
        XCTAssertEqual(s.note.body, "ab c")
    }

    func testMitEditorGehtEsAnDenEditor() throws {
        let s = try sitzung("Text")
        let editor = FakeEditor()
        s.attach(editor: editor)
        XCTAssertTrue(s.insert("neu", at: .cursor))
        XCTAssertEqual(editor.aufrufe.count, 1)
        XCTAssertEqual(editor.aufrufe.first?.0, "neu")
        XCTAssertEqual(s.note.body, "Text")    // der Editor meldet die Änderung selbst über edit
    }

    /// Kann der Editor nicht annehmen, fügt die Sitzung selbst ein — nichts geht verloren.
    func testEditorNimmtNichtAnDannSelbst() throws {
        let s = try sitzung("Text")
        let editor = FakeEditor()
        editor.nimmtAn = false
        s.attach(editor: editor)
        s.selectionChanged(NSRange(location: 4, length: 0))
        s.insert("neu", at: .cursor)
        XCTAssertEqual(s.note.body, "Text neu")
    }

    func testAbgehaengterEditorBekommtNichts() throws {
        let s = try sitzung("Text")
        let editor = FakeEditor()
        s.attach(editor: editor)
        s.detach(editor: editor)
        s.insert("neu", at: .end)
        XCTAssertTrue(editor.aufrufe.isEmpty)
        XCTAssertEqual(s.note.body, "Textneu")
    }

    func testEingabeMerktSichDieQuelle() throws {
        let s = try sitzung("a")
        let quelle = FakeEditor()
        s.edit("ab", from: quelle)
        XCTAssertTrue(s.lastEditSource === quelle)
        XCTAssertEqual(s.editRevision, 1)
    }

    func testPlatzhalterNimmtNichts() throws {
        try u.schreibe(".Fern.md.icloud", "")
        let s = u.store()
        let sitzung = NoteEditorSession(note: s.notes[0], store: s)
        XCTAssertFalse(sitzung.insert("x", at: .end))
        XCTAssertEqual(sitzung.note.body, "")
    }

    /// Fehlt die Datei, wird eingefügt und als ungesichert festgehalten.
    func testBeiFehlenderDateiUngesichert() throws {
        let s = try sitzung("a")
        try FileManager.default.removeItem(at: u.ordner.appendingPathComponent("X.md"))
        s.edit("a b")        // macht dirty …
        s.flush()            // … Sichern meldet .missing
        XCTAssertEqual(s.status, .missing)
        s.insert("c", at: .end)
        XCTAssertTrue(s.hasUnsavedText)
        XCTAssertEqual(s.note.body, "a bc")
    }
}
```

- [ ] **Schritt 2: Test laufen lassen**

`xcodegen generate`, Testbefehl mit `-only-testing:ShoutTests/NoteEditorSessionInsertTests`.
Erwartet: Build-Fehler „cannot find type 'NoteTextEditing' in scope“.

- [ ] **Schritt 3: Implementieren**

In `Sources/FlowLokal/NoteEditorSession.swift`:

1. Über `@MainActor final class NoteEditorSession` einfügen:

```swift
/// Ein Editor, in den die Sitzung Text einfügen kann — so landet ein Diktat am
/// Cursor und lässt sich mit ⌘Z in einem Schritt zurücknehmen.
@MainActor
protocol NoteTextEditing: AnyObject {
    /// `false`, wenn der Editor gerade nichts annehmen kann; dann fügt die Sitzung selbst ein.
    func insertText(_ text: String, at point: NoteEditorSession.InsertionPoint) -> Bool
}
```

2. In der Klasse nach dem `enum Status { … }` einfügen:

```swift
    /// Wo eingefügter Text landet.
    enum InsertionPoint: Equatable {
        case cursor
        case end
    }
```

3. Nach `@Published private(set) var saveFailed = false` einfügen:

```swift
    /// Steigt bei jeder Eingabe. Zeigen zwei Editoren dieselbe Notiz (Seite und
    /// Panel), lädt der jeweils andere daran neu.
    @Published private(set) var editRevision = 0
    /// Der Editor, von dem die letzte Eingabe kam; `nil`, wenn ohne Editor eingefügt wurde.
    private(set) weak var lastEditSource: AnyObject?
    /// Der zuletzt benutzte Editor — dorthin geht ein Diktat.
    private(set) weak var editor: NoteTextEditing?
    /// Cursor bzw. Auswahl, zuletzt vom Editor gemeldet (UTF-16, wie `NSTextView`).
    private(set) var lastSelection = NSRange(location: 0, length: 0)
```

4. `func edit(_ text: String)` ersetzen durch:

```swift
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
        if let editor, editor.insertText(text, at: point) { return true }
        let ns = note.body as NSString
        let ort = point == .end ? ns.length : min(lastSelection.location, ns.length)
        let vorher: Character? = ort > 0
            ? ns.substring(with: ns.rangeOfComposedCharacterSequence(at: ort - 1)).last
            : nil
        let einfuegen = point == .end ? text : DictationInsertion.text(text, after: vorher)
        let neu = ns.replacingCharacters(in: NSRange(location: ort, length: 0), with: einfuegen)
        if point == .cursor {
            lastSelection = NSRange(location: ort + (einfuegen as NSString).length, length: 0)
        }
        edit(neu)
        return true
    }
```

- [ ] **Schritt 4: Alle Sitzungs-Tests laufen lassen**

Testbefehl mit `-only-testing:ShoutTests/NoteEditorSessionInsertTests -only-testing:ShoutTests/NoteEditorSessionTests`.
Erwartet: 0 Fehler. Danach den Kompilierlauf der App: `** BUILD SUCCEEDED **`
(der Editor ruft `edit(_:)` weiter ohne Quelle, das bleibt gültig).

- [ ] **Schritt 5: Commit**

```bash
cd /Users/liam/Developer/LIAM/flow-lokal && git add Sources/FlowLokal/NoteEditorSession.swift Tests/ShoutTests/NoteEditorSessionInsertTests.swift && git commit -m "Notizen: Sitzung fügt am Cursor ein und kennt ihre Editoren" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Aufgabe 4: Eine Sitzung pro Notiz — `NoteSessionRegistry`

Zwei Sitzungen auf derselben Notiz (Seite und Panel-Tab) hielten die Sicherung
der jeweils anderen für eine Änderung von außen und erzeugten Konfliktdateien.
Die Registry gibt für eine Notiz-ID immer dieselbe Sitzung heraus und zählt die
Halter. Gibt der letzte Halter sie ab, wird gesichert; bleibt Text ungesichert,
behält die Registry die Sitzung, damit das Beenden sie noch rettet.

**Dateien:**
- Neu: `Sources/FlowLokal/NoteSessionRegistry.swift`
- Ändern: `Sources/FlowLokal/NotesPageModel.swift`
- Neu: `Tests/ShoutTests/NoteSessionRegistryTests.swift`
- Ändern: `project.yml` (nach `- path: Sources/FlowLokal/NoteInbox.swift`)

**Schnittstellen:**
- Benutzt: `NoteEditorSession`, `NoteStore`, `NoteFile`, `Loc`
- Liefert (`@MainActor final class NoteSessionRegistry`):
  - `init(store: NoteStore, saveDelay: TimeInterval = 1.0)`, `let store`
  - `func acquire(_ note: Note) -> NoteEditorSession`, `func acquireNew() -> NoteEditorSession`
  - `func release(_ session: NoteEditorSession)`, `func discard(_ session: NoteEditorSession)`
  - `func session(id: UUID) -> NoteEditorSession?`, `var sessions: [NoteEditorSession]`, `var unsavedSessions: [NoteEditorSession]`
  - `@discardableResult func flushAll() -> [NoteEditorSession]` (die danach noch ungesicherten)
  - `func removeAll()`
  - `func onDiscard(_ handler: @escaping (UUID) -> Void)`
  - `@discardableResult func writeRescueCopy(for: NoteEditorSession, in: URL) -> URL?`
  - `func writeRescueCopies(in: URL) -> (written: [URL], failed: [NoteEditorSession])`
- `NotesPageModel`: `init(store:registry:defaults:rescueDirectory:)` mit `registry: NoteSessionRegistry? = nil`; `let registry`; `var onFolderChanged: (() -> Void)?`. Alle anderen Signaturen bleiben.

- [ ] **Schritt 1: Den fehlschlagenden Test schreiben**

`Tests/ShoutTests/NoteSessionRegistryTests.swift`:

```swift
import XCTest

@MainActor
final class NoteSessionRegistryTests: XCTestCase {

    private var u: NotizUmgebung!
    private var suite: String!
    private var defaults: UserDefaults!

    override func setUpWithError() throws {
        Loc.shared.apply("de")
        u = try NotizUmgebung()
        suite = "shout-registry-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)
    }

    override func tearDown() {
        u.aufraeumen()
        defaults.removePersistentDomain(forName: suite)
        Loc.shared.apply("system")
        super.tearDown()
    }

    /// Macht das nächste Sichern von `X.md` unmöglich: eine fremde, nicht lesbare
    /// Änderung mit neuerem mtime. Der Store liefert dann `.failed`.
    private func machSichernUnmoeglich() throws {
        let url = u.ordner.appendingPathComponent("X.md")
        try Data([0x47, 0xFC, 0x6E]).write(to: url)
        try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(60)], ofItemAtPath: url.path)
    }

    func testGleicheNotizGleicheSitzung() throws {
        try u.schreibe("X.md", "a")
        let store = u.store()
        let r = NoteSessionRegistry(store: store, saveDelay: 60)
        let eins = r.acquire(store.notes[0])
        let zwei = r.acquire(store.notes[0])
        XCTAssertTrue(eins === zwei)
    }

    func testLetzterHalterSichertUndGibtFrei() throws {
        try u.schreibe("X.md", "a")
        let store = u.store()
        let r = NoteSessionRegistry(store: store, saveDelay: 60)
        let s = r.acquire(store.notes[0])
        _ = r.acquire(store.notes[0])
        s.edit("a b")
        r.release(s)
        XCTAssertNotNil(r.session(id: s.id))          // ein Halter übrig
        r.release(s)
        XCTAssertNil(r.session(id: s.id))
        XCTAssertEqual(u.text("X.md"), "a b")
    }

    /// Bleibt Text ungesichert, behält die Registry die Sitzung — sonst wäre er beim Beenden weg.
    func testUngesichertBleibtNachFreigabe() throws {
        try u.schreibe("X.md", "a")
        let store = u.store()
        let r = NoteSessionRegistry(store: store, saveDelay: 60)
        let s = r.acquire(store.notes[0])
        s.edit("neu")
        try machSichernUnmoeglich()
        r.release(s)
        XCTAssertTrue(r.session(id: s.id) === s)
        XCTAssertEqual(r.unsavedSessions.map(\.id), [s.id])
        // Wer sie wieder öffnet, bekommt dieselbe Sitzung mit ihrem Text.
        XCTAssertEqual(r.acquire(store.notes[0]).note.body, "neu")
    }

    func testFlushAllMeldetUngesicherte() throws {
        try u.schreibe("X.md", "a")
        try u.schreibe("Y.md", "b")
        let store = u.store()
        let r = NoteSessionRegistry(store: store, saveDelay: 60)
        let x = r.acquire(store.notes.first { $0.title == "X" }!)
        let y = r.acquire(store.notes.first { $0.title == "Y" }!)
        x.edit("x neu")
        y.edit("y neu")
        try machSichernUnmoeglich()
        let offen = r.flushAll()
        XCTAssertEqual(offen.map(\.id), [x.id])
        XCTAssertEqual(u.text("Y.md"), "y neu")
    }

    func testVerwerfenMeldetAlleHalter() throws {
        try u.schreibe("X.md", "a")
        let store = u.store()
        let r = NoteSessionRegistry(store: store, saveDelay: 60)
        var gemeldet: [UUID] = []
        r.onDiscard { gemeldet.append($0) }
        let s = r.acquire(store.notes[0])
        r.discard(s)
        XCTAssertNil(r.session(id: s.id))
        XCTAssertEqual(gemeldet, [s.id])
    }

    func testRettungskopienFuerAlleUngesicherten() throws {
        try u.schreibe("X.md", "a")
        let store = u.store()
        let r = NoteSessionRegistry(store: store, saveDelay: 60)
        let s = r.acquire(store.notes[0])
        s.edit("gerettet")
        try machSichernUnmoeglich()
        r.flushAll()
        let rettung = u.wurzel.appendingPathComponent("Rettung", isDirectory: true)
        let ergebnis = r.writeRescueCopies(in: rettung)
        XCTAssertEqual(ergebnis.written.count, 1)
        XCTAssertTrue(ergebnis.failed.isEmpty)
        let inhalt = try String(contentsOf: ergebnis.written[0], encoding: .utf8)
        XCTAssertTrue(inhalt.contains("gerettet"))
        // Ein zweiter Versuch mit demselben Text schreibt keine zweite Kopie.
        XCTAssertEqual(r.writeRescueCopies(in: rettung).written, ergebnis.written)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: rettung.path).count, 1)
    }

    /// Seite und Registry teilen sich die Sitzung: Was die Seite öffnet, findet das Panel wieder.
    func testSeiteNutztDieRegistry() throws {
        try u.schreibe("X.md", "a")
        let store = u.store()
        let r = NoteSessionRegistry(store: store, saveDelay: 60)
        let seite = NotesPageModel(store: store, registry: r, defaults: defaults)
        seite.select(store.notes[0].id)
        XCTAssertTrue(seite.session === r.session(id: store.notes[0].id))
    }

    /// Der Ordnerwechsel prüft ALLE Sitzungen, nicht nur die der Seite.
    func testOrdnerwechselScheitertAnUngesichertemPanelText() throws {
        try u.schreibe("X.md", "a")
        let store = u.store()
        let r = NoteSessionRegistry(store: store, saveDelay: 60)
        let seite = NotesPageModel(store: store, registry: r, defaults: defaults)
        let panelSitzung = r.acquire(store.notes[0])
        panelSitzung.edit("im Panel getippt")
        try machSichernUnmoeglich()
        let anderer = u.wurzel.appendingPathComponent("Anderer", isDirectory: true)
        try FileManager.default.createDirectory(at: anderer, withIntermediateDirectories: true)
        XCTAssertFalse(seite.changeFolder(to: anderer))
        XCTAssertEqual(store.folder.standardizedFileURL.path, u.ordner.standardizedFileURL.path)
    }

    func testOrdnerwechselMeldetSich() throws {
        let store = u.store()
        let r = NoteSessionRegistry(store: store, saveDelay: 60)
        let seite = NotesPageModel(store: store, registry: r, defaults: defaults)
        var gemeldet = false
        seite.onFolderChanged = { gemeldet = true }
        let anderer = u.wurzel.appendingPathComponent("Anderer", isDirectory: true)
        try FileManager.default.createDirectory(at: anderer, withIntermediateDirectories: true)
        XCTAssertTrue(seite.changeFolder(to: anderer))
        XCTAssertTrue(gemeldet)
    }
}
```

- [ ] **Schritt 2: Eintragen und Test laufen lassen**

In `project.yml` nach `      - path: Sources/FlowLokal/NoteInbox.swift`:

```yaml
      - path: Sources/FlowLokal/NoteSessionRegistry.swift
```

```bash
cd /Users/liam/Developer/LIAM/flow-lokal && touch Sources/FlowLokal/NoteSessionRegistry.swift && xcodegen generate
```

Testbefehl mit `-only-testing:ShoutTests/NoteSessionRegistryTests`.
Erwartet: Build-Fehler „cannot find 'NoteSessionRegistry' in scope“.

- [ ] **Schritt 3: `NoteSessionRegistry` schreiben**

`Sources/FlowLokal/NoteSessionRegistry.swift`:

```swift
import Foundation

/// Gibt für jede Notiz genau eine `NoteEditorSession` heraus — Seite und Panel
/// teilen sie. Zwei Sitzungen auf derselben Datei hielten sonst die Sicherung
/// der jeweils anderen für eine Änderung von außen.
///
/// Halter zählen: Wer eine Sitzung holt (`acquire`), gibt sie wieder ab
/// (`release`). Beim letzten Abgeben wird gesichert. Bleibt Text ungesichert,
/// behält die Registry die Sitzung trotzdem — sonst wäre er beim Beenden weg.
@MainActor
final class NoteSessionRegistry {

    private struct Eintrag {
        let session: NoteEditorSession
        var halter: Int
    }

    let store: NoteStore
    private let saveDelay: TimeInterval
    private var eintraege: [UUID: Eintrag] = [:]
    private var verwerfenMelden: [(UUID) -> Void] = []
    /// Text und Datei der letzten Rettungskopie je Sitzung: Wird das Beenden
    /// abgebrochen und erneut versucht, entsteht für denselben Text keine zweite.
    private var letzteRettung: [UUID: (body: String, url: URL)] = [:]

    init(store: NoteStore, saveDelay: TimeInterval = 1.0) {
        self.store = store
        self.saveDelay = saveDelay
    }

    func session(id: UUID) -> NoteEditorSession? { eintraege[id]?.session }

    var sessions: [NoteEditorSession] { eintraege.values.map(\.session) }

    var unsavedSessions: [NoteEditorSession] { sessions.filter(\.hasUnsavedText) }

    func acquire(_ note: Note) -> NoteEditorSession {
        if var eintrag = eintraege[note.id] {
            eintrag.halter += 1
            eintraege[note.id] = eintrag
            return eintrag.session
        }
        let neu = NoteEditorSession(note: note, store: store, saveDelay: saveDelay)
        eintraege[note.id] = Eintrag(session: neu, halter: 1)
        return neu
    }

    func acquireNew() -> NoteEditorSession { acquire(.blank()) }

    func release(_ session: NoteEditorSession) {
        guard var eintrag = eintraege[session.id], eintrag.session === session else { return }
        eintrag.halter = max(eintrag.halter - 1, 0)
        guard eintrag.halter == 0 else {
            eintraege[session.id] = eintrag
            return
        }
        session.flush()
        if session.hasUnsavedText {
            eintraege[session.id] = eintrag     // ohne Halter, aber nicht vergessen
        } else {
            eintraege[session.id] = nil
            letzteRettung[session.id] = nil
        }
    }

    /// Wirft die Sitzung weg, ohne zu sichern (nach Rückfrage im Hinweis, oder
    /// weil ihre Datei in den Papierkorb ging). Alle, die sie halten, erfahren es.
    func discard(_ session: NoteEditorSession) {
        guard eintraege[session.id]?.session === session else { return }
        eintraege[session.id] = nil
        letzteRettung[session.id] = nil
        for melden in verwerfenMelden { melden(session.id) }
    }

    func onDiscard(_ handler: @escaping (UUID) -> Void) {
        verwerfenMelden.append(handler)
    }

    /// Sichert alle. Gibt die zurück, deren Text danach noch nicht gesichert ist.
    @discardableResult
    func flushAll() -> [NoteEditorSession] {
        for session in sessions { session.flush() }
        for (id, eintrag) in eintraege where eintrag.halter == 0 && !eintrag.session.hasUnsavedText {
            eintraege[id] = nil
            letzteRettung[id] = nil
        }
        return unsavedSessions
    }

    /// Nach einem Ordnerwechsel: Die Sitzungen gehören zum alten Ordner. Der
    /// Aufrufer hat vorher mit `flushAll()` sichergestellt, dass nichts offen ist.
    func removeAll() {
        eintraege = [:]
        letzteRettung = [:]
    }

    @discardableResult
    func writeRescueCopy(for session: NoteEditorSession, in directory: URL) -> URL? {
        // RUMPF: aus NotesPageModel.writeRescueCopyIfNeeded(in:) übernommen, siehe Schritt 4.
        nil
    }

    func writeRescueCopies(in directory: URL) -> (written: [URL], failed: [NoteEditorSession]) {
        var geschrieben: [URL] = []
        var gescheitert: [NoteEditorSession] = []
        for session in unsavedSessions {
            if let url = writeRescueCopy(for: session, in: directory) {
                geschrieben.append(url)
            } else {
                gescheitert.append(session)
            }
        }
        return (geschrieben, gescheitert)
    }
}
```

- [ ] **Schritt 4: Rettungskopie umziehen und Seitenmodell umstellen**

1. **Rumpf von `writeRescueCopy(for:in:)`:** Den Rumpf von
`NotesPageModel.writeRescueCopyIfNeeded(in:)` **wörtlich** hierher verschieben
und nur zwei Dinge anpassen: `guard let session, session.hasUnsavedText` wird
`guard session.hasUnsavedText`, und jedes `lastRescue` wird
`letzteRettung[session.id]`. Das Dateiformat und die Namensbildung bleiben
genau wie heute. Die Platzhalterzeile `nil` und den Kommentar `RUMPF: …` entfernen.

2. **`NotesPageModel`** (`Sources/FlowLokal/NotesPageModel.swift`):

- Eigenschaften ergänzen und `lastRescue` entfernen:

```swift
    /// Teilt die Sitzungen mit dem Panel: eine pro Notiz.
    let registry: NoteSessionRegistry
    /// Nach einem Ordnerwechsel — das Panel räumt dann seine Tabs ab.
    var onFolderChanged: (() -> Void)?
```

- `init` erweitern (die Reihenfolge der Parameter so, dass bestehende Aufrufe
  `NotesPageModel(store:defaults:)` weiter kompilieren):

```swift
    init(store: NoteStore, registry: NoteSessionRegistry? = nil, defaults: UserDefaults = .standard,
         rescueDirectory: URL = StoreIO.directory().appendingPathComponent("Notizen-Rettung", isDirectory: true)) {
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
```

- `leaveSession()` gibt die Sitzung an die Registry zurück:

```swift
    private func leaveSession() -> Bool {
        guard let session else { return true }
        session.flush()
        guard !session.hasUnsavedText else { return false }
        registry.release(session)
        self.session = nil
        return true
    }
```

- In `select(_:)` die Zeile `session = NoteEditorSession(note: note, store: store)`
  ersetzen durch `session = registry.acquire(note)`.
- In `createNote()` die Zeile `session = NoteEditorSession(note: .blank(), store: store)`
  ersetzen durch `session = registry.acquireNew()`.
- In `delete(_:)`: Beide Stellen, an denen die offene Sitzung weggeworfen wird
  (`session = nil` im Zweig „nie gesichert und leer“ und `session = nil` nach dem
  erfolgreichen Löschen), werden zu:

```swift
            if let offen = session { registry.discard(offen) }
            session = nil
```

- `changeFolder(to:)` prüft alle Sitzungen:

```swift
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
```

- `discardSession()`:

```swift
    func discardSession() {
        if let offen = session { registry.discard(offen) }
        session = nil
    }
```

- `writeRescueCopyIfNeeded(in:)` wird ein Durchreicher:

```swift
    @discardableResult
    func writeRescueCopyIfNeeded(in directory: URL) -> URL? {
        guard let session else { return nil }
        return registry.writeRescueCopy(for: session, in: directory)
    }
```

- [ ] **Schritt 5: Tests laufen lassen**

Testbefehl mit `-only-testing:ShoutTests/NoteSessionRegistryTests -only-testing:ShoutTests/NotesPageModelTests`.
Erwartet: 0 Fehler. Danach die ganze Suite und der Kompilierlauf der App
(`AppDelegate` erzeugt das Seitenmodell weiter mit `NotesPageModel(store:)`).

- [ ] **Schritt 6: Commit**

```bash
cd /Users/liam/Developer/LIAM/flow-lokal && git add project.yml Sources/FlowLokal/NoteSessionRegistry.swift Sources/FlowLokal/NotesPageModel.swift Tests/ShoutTests/NoteSessionRegistryTests.swift && git commit -m "Notizen: eine Sitzung pro Notiz, gemeinsam für Seite und Panel" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---
### Aufgabe 5: Editor — eigenes Rückgängig, Einfügen, zwei Editoren, Hinweise herauslösen

**Dateien:**
- Ändern: `Sources/FlowLokal/NoteEditorView.swift` (ganz ersetzen)
- Neu: `Sources/FlowLokal/NoteNoticesView.swift`
- Ändern: `Sources/FlowLokal/NotesView.swift` (`NoteEditorPane`)
- Neu: `Tests/ShoutTests/NoteEditorCoordinatorTests.swift`
- Ändern: `project.yml` (nach `- path: Sources/FlowLokal/NoteSessionRegistry.swift`)

**Schnittstellen:**
- Benutzt: `NoteEditorSession` (`edit(_:from:)`, `editRevision`, `lastEditSource`, `attach/detach`, `selectionChanged`, `lastSelection`), `NoteTextEditing`, `DictationInsertion`, `MarkdownHighlighter`
- Liefert:
  - `@MainActor protocol HidesOnEscape: AnyObject { func hideOnEscape() }` (das Panel aus Aufgabe 9 erfüllt es)
  - `NoteEditorView.Coordinator: NoteTextEditing` mit `let undo: UndoManager`, `func insertText(_:at:) -> Bool`, `func replaceText(with:)`, `func mirror(_:)`
  - `struct NoteNoticesView: View { init(session: NoteEditorSession, onDiscard: @escaping () -> Void) }`

- [ ] **Schritt 1: Den fehlschlagenden Test schreiben**

`Tests/ShoutTests/NoteEditorCoordinatorTests.swift`:

```swift
import XCTest
import AppKit

/// Der Coordinator mit einem echten NSTextView, ohne SwiftUI drumherum.
@MainActor
final class NoteEditorCoordinatorTests: XCTestCase {

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

    private func editor(_ session: NoteEditorSession) -> (NoteEditorView.Coordinator, NSTextView) {
        let c = NoteEditorView.Coordinator(session: session)
        let tv = NSTextView(frame: NSRect(x: 0, y: 0, width: 300, height: 200))
        tv.isRichText = false
        tv.allowsUndo = true
        tv.delegate = c
        tv.string = session.note.body
        c.textView = tv
        c.editRevision = session.editRevision
        session.attach(editor: c)
        return (c, tv)
    }

    private func sitzung(_ text: String) throws -> NoteEditorSession {
        try u.schreibe("X.md", text)
        let s = u.store()
        return NoteEditorSession(note: s.notes[0], store: s, saveDelay: 60)
    }

    func testDiktatAmCursorUndEinSchrittZurueck() throws {
        let s = try sitzung("Hallo Welt")
        let (c, tv) = editor(s)
        tv.setSelectedRange(NSRange(location: 5, length: 0))
        XCTAssertTrue(s.insert("schöne", at: .cursor))
        XCTAssertEqual(tv.string, "Hallo schöne Welt")
        XCTAssertEqual(s.note.body, "Hallo schöne Welt")
        XCTAssertEqual(tv.selectedRange(), NSRange(location: 12, length: 0))
        // Gruppen schließt der UndoManager am Ende eines Laufschleifen-Durchgangs.
        RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        c.undo.undo()
        XCTAssertEqual(tv.string, "Hallo Welt")
    }

    func testAnhaengenLaesstDenCursorStehen() throws {
        let s = try sitzung("a")
        let (_, tv) = editor(s)
        tv.setSelectedRange(NSRange(location: 0, length: 0))
        s.insert("\nb", at: .end)
        XCTAssertEqual(tv.string, "a\nb")
        XCTAssertEqual(tv.selectedRange(), NSRange(location: 0, length: 0))
    }

    func testGesperrterEditorNimmtNichtsAn() throws {
        let s = try sitzung("a")
        let (c, tv) = editor(s)
        tv.isEditable = false
        XCTAssertFalse(c.insertText("x", at: .end))
    }

    /// Zwei Editoren auf derselben Sitzung: Der zweite gleicht an, ohne dem
    /// ersten das Diktat-Ziel wegzunehmen.
    func testAngleichenStiehltNichtDasDiktatZiel() throws {
        let s = try sitzung("a")
        // Beide Coordinators festhalten: `NSTextView.delegate` ist schwach.
        let (zweiter, zweiterTV) = editor(s)
        let (erster, ersterTV) = editor(s)     // zuletzt angehängt
        ersterTV.setSelectedRange(NSRange(location: 1, length: 0))
        XCTAssertTrue(s.editor === erster)
        ersterTV.insertText("b", replacementRange: ersterTV.selectedRange())
        XCTAssertEqual(s.note.body, "ab")
        XCTAssertTrue(s.lastEditSource === erster)
        zweiter.mirror(s.note.body)
        XCTAssertEqual(zweiterTV.string, "ab")
        XCTAssertTrue(s.editor === erster)
    }

    func testJederEditorHatEigenesRueckgaengig() throws {
        let s = try sitzung("a")
        let (eins, tv1) = editor(s)
        let (zwei, _) = editor(s)
        XCTAssertFalse(eins.undo === zwei.undo)
        XCTAssertTrue(tv1.undoManager === eins.undo)
    }
}
```

- [ ] **Schritt 2: Eintragen und Test laufen lassen**

In `project.yml` nach `      - path: Sources/FlowLokal/NoteSessionRegistry.swift`:

```yaml
      - path: Sources/FlowLokal/NoteEditorView.swift
```

`xcodegen generate`, Testbefehl mit `-only-testing:ShoutTests/NoteEditorCoordinatorTests`.
Erwartet: Build-Fehler (`undo` bzw. `mirror` fehlen am Coordinator).

- [ ] **Schritt 3: `NoteEditorView.swift` ersetzen**

```swift
import SwiftUI
import AppKit

/// Ein Fenster, das sich mit Esc ausblenden lässt (das Panel). Im Editor öffnet
/// Esc sonst die Wortvervollständigung.
@MainActor
protocol HidesOnEscape: AnyObject {
    func hideOnEscape()
}

/// Der Editor einer Notiz: ein `NSTextView`, weil SwiftUIs `TextEditor` die
/// Cursorposition erst ab macOS 15 herausgibt — und das Diktat genau dorthin
/// muss. Klartext, Markdown nur in der Darstellung.
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
        // `NSTextStorage.delegate` ist schwach; der Coordinator hält die Hervorhebung.
        let highlighter = context.coordinator.highlighter
        // Während markierter Text entsteht (Option+U …), nicht neu gestalten.
        highlighter.shouldSkip = { [weak textView] in
            MainActor.assumeIsolated { textView?.hasMarkedText() ?? false }
        }
        textView.textStorage?.delegate = highlighter
        textView.string = session.note.body
        textView.isEditable = session.status != .placeholder

        let c = context.coordinator
        c.textView = textView
        c.revision = session.externalRevision
        c.editRevision = session.editRevision
        c.focusRequest = focusRequest
        // Den zuletzt gemeldeten Cursor übernehmen (geklemmt) — ein neuer Editor
        // derselben Notiz setzt dort fort.
        let laenge = (textView.string as NSString).length
        c.setztSelbst = true
        textView.setSelectedRange(NSRange(location: min(session.lastSelection.location, laenge), length: 0))
        c.setztSelbst = false
        session.attach(editor: c)
        if autofocus {
            DispatchQueue.main.async { textView.window?.makeFirstResponder(textView) }
        }
        return scroll
    }

    static func dismantleNSView(_ nsView: NSScrollView, coordinator: Coordinator) {
        coordinator.session.detach(editor: coordinator)
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        let c = context.coordinator
        guard let textView = c.textView else { return }
        // Erst freigeben, dann ersetzen: Kommt eine Notiz aus iCloud an, wechseln
        // Text und Sperre im selben Durchlauf — ein gesperrter Editor nähme den
        // Text sonst nicht an.
        textView.isEditable = session.status != .placeholder
        if c.revision != session.externalRevision {
            c.revision = session.externalRevision
            c.editRevision = session.editRevision
            c.replaceText(with: session.note.body)
        } else if c.editRevision != session.editRevision {
            c.editRevision = session.editRevision
            // Die Eingabe kam aus einem anderen Editor (oder ohne Editor): angleichen.
            if session.lastEditSource !== c { c.mirror(session.note.body) }
        }
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
    final class Coordinator: NSObject, NSTextViewDelegate, NoteTextEditing {
        let session: NoteEditorSession
        let highlighter = MarkdownHighlighter()
        /// Eigenes Rückgängig je Editor. Das Fenster teilt sonst eines für alle
        /// Tabs, und ⌘Z in einem Tab träfe Schritte eines anderen.
        let undo = UndoManager()
        weak var textView: NSTextView?
        var revision = 0
        var editRevision = 0
        var focusRequest = 0
        /// Während der Editor selbst Text oder Auswahl setzt (Angleichen, Ersetzen),
        /// ist eine Auswahländerung keine Handlung des Nutzers.
        var setztSelbst = false

        init(session: NoteEditorSession) { self.session = session }

        func undoManager(for view: NSTextView) -> UndoManager? { undo }

        func textDidChange(_ notification: Notification) {
            guard let tv = notification.object as? NSTextView else { return }
            session.edit(tv.string, from: self)
            editRevision = session.editRevision
        }

        /// Ein Klick oder Pfeil im Editor: Dorthin geht das nächste Diktat.
        func textViewDidChangeSelection(_ notification: Notification) {
            guard !setztSelbst, let tv = notification.object as? NSTextView else { return }
            session.selectionChanged(tv.selectedRange())
            session.attach(editor: self)
        }

        /// Esc im Panel blendet es aus, statt die Wortvervollständigung zu öffnen.
        func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            guard commandSelector == #selector(NSResponder.cancelOperation(_:)),
                  let fenster = textView.window as? HidesOnEscape else { return false }
            fenster.hideOnEscape()
            return true
        }

        // MARK: NoteTextEditing

        /// Fügt als ein Rückgängig-Schritt ein. `.cursor` ersetzt die Auswahl und
        /// setzt den Cursor dahinter; `.end` hängt an und lässt den Cursor stehen.
        func insertText(_ text: String, at point: NoteEditorSession.InsertionPoint) -> Bool {
            guard let tv = textView, tv.isEditable else { return false }
            let ns = tv.string as NSString
            let ziel = point == .end ? NSRange(location: ns.length, length: 0) : tv.selectedRange()
            let vorher: Character? = ziel.location > 0
                ? ns.substring(with: ns.rangeOfComposedCharacterSequence(at: ziel.location - 1)).last
                : nil
            let einfuegen = point == .end ? text : DictationInsertion.text(text, after: vorher)
            let auswahlVorher = tv.selectedRange()
            tv.breakUndoCoalescing()
            guard tv.shouldChangeText(in: ziel, replacementString: einfuegen) else { return false }
            tv.textStorage?.replaceCharacters(in: ziel, with: einfuegen)
            tv.didChangeText()
            tv.breakUndoCoalescing()
            if point == .cursor {
                let danach = NSRange(location: ziel.location + (einfuegen as NSString).length, length: 0)
                tv.setSelectedRange(danach)
                tv.scrollRangeToVisible(danach)
            } else {
                setztSelbst = true
                tv.setSelectedRange(auswahlVorher)
                setztSelbst = false
            }
            return true
        }

        /// Übernimmt eine Fassung von außen als normale Bearbeitung — so holt ⌘Z
        /// die eigene Fassung zurück. Der Cursor bleibt, so gut es geht, stehen.
        func replaceText(with text: String) {
            guard let tv = textView, tv.string != text else { return }
            let ganz = NSRange(location: 0, length: (tv.string as NSString).length)
            let auswahl = tv.selectedRange()
            setztSelbst = true
            defer { setztSelbst = false }
            if tv.shouldChangeText(in: ganz, replacementString: text) {
                tv.textStorage?.replaceCharacters(in: ganz, with: text)
                tv.didChangeText()
            } else {
                // Gesperrt (Platzhalter): ohne Rückgängig, aber der Editor zeigt,
                // was die Sitzung hält — sonst klafften beide still auseinander.
                tv.textStorage?.replaceCharacters(in: ganz, with: text)
            }
            let laenge = (text as NSString).length
            tv.setSelectedRange(NSRange(location: min(auswahl.location, laenge), length: 0))
        }

        /// Gleicht an einen anderen Editor derselben Notiz an: ohne Rückgängig-
        /// Schritt, und die eigenen Schritte passen danach nicht mehr zum Text.
        func mirror(_ text: String) {
            guard let tv = textView, tv.string != text else { return }
            let auswahl = tv.selectedRange()
            setztSelbst = true
            defer { setztSelbst = false }
            tv.textStorage?.replaceCharacters(in: NSRange(location: 0, length: (tv.string as NSString).length), with: text)
            undo.removeAllActions()
            let laenge = (text as NSString).length
            tv.setSelectedRange(NSRange(location: min(auswahl.location, laenge), length: 0))
        }
    }
}
```

- [ ] **Schritt 4: Hinweise herauslösen**

`Sources/FlowLokal/NoteNoticesView.swift` neu anlegen. Inhalt: die Hinweise aus
`NoteEditorPane` in `NotesView.swift`, **unverändert im Verhalten**, als eigene View:

```swift
import SwiftUI
import AppKit

/// Die Hinweise einer geöffneten Notiz — Konflikt, fehlende Datei, iCloud,
/// gescheitertes Sichern mit Ausweg. Auf der Seite und im Panel gleich.
struct NoteNoticesView: View {
    @ObservedObject var session: NoteEditorSession
    /// Schließt die Sitzung, ohne zu sichern (nach Rückfrage).
    let onDiscard: () -> Void

    @State private var confirmDiscard = false

    var body: some View {
        VStack(spacing: 0) { notices }
            .alert(Loc.t("Ungesicherten Text verwerfen?"), isPresented: $confirmDiscard) {
                Button(Loc.t("Verwerfen"), role: .destructive, action: onDiscard)
                Button(Loc.t("Abbrechen"), role: .cancel) {}
            } message: {
                Text(Loc.t("Der Text dieser Notiz ist nirgends gesichert. Kopiere ihn vorher, wenn du ihn behalten willst."))
            }
    }
}
```

Dann aus `NoteEditorPane` (in `NotesView.swift`) die vier Mitglieder
`notices`, `saveFailedNotice`, `escapeNotice(_:retry:action:)` und
`notice(_:button:action:)` **wörtlich** in eine `private extension NoteNoticesView`
in der neuen Datei verschieben (ihr Rumpf benutzt nur `session` und
`confirmDiscard`, beides gibt es dort). In `NoteEditorPane`:
- `@State private var confirmDiscard = false` entfernen,
- den Modifier `.alert(Loc.t("Ungesicherten Text verwerfen?"), …) { … } message: { … }` entfernen,
- die Zeile `notices` im `VStack` ersetzen durch
  `NoteNoticesView(session: session, onDiscard: onDiscard)`.

- [ ] **Schritt 5: Tests und Kompilierlauf**

Testbefehl mit `-only-testing:ShoutTests/NoteEditorCoordinatorTests`. Erwartet: 5 Tests, 0 Fehler.
Dann die ganze Suite und der Kompilierlauf der App (`** BUILD SUCCEEDED **`).

- [ ] **Schritt 6: Commit**

```bash
cd /Users/liam/Developer/LIAM/flow-lokal && git add project.yml Sources/FlowLokal/NoteEditorView.swift Sources/FlowLokal/NoteNoticesView.swift Sources/FlowLokal/NotesView.swift Tests/ShoutTests/NoteEditorCoordinatorTests.swift && git commit -m "Notizen: Editor mit eigenem Rückgängig, Einfügen am Cursor, zwei Editoren synchron" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Aufgabe 6: Store — feste Titel, Umbenennen melden, Watcher filtern

**Dateien:**
- Ändern: `Sources/FlowLokal/NoteStore.swift`, `Sources/FlowLokal/NoteFolderWatcher.swift`
- Neu: `Tests/ShoutTests/NoteStoreScratchpadTests.swift`, `Tests/ShoutTests/NoteFolderWatcherFilterTests.swift`

**Schnittstellen:**
- Liefert:
  - `NoteStore.create(title: String, body: String, pinned: Bool) -> SaveResult` (`.saved` oder `.failed`)
  - `NoteStore.onRename: ((String, String) -> Void)?` — alter und neuer Dateiname, nach jedem `rename(_:to:)`
  - `NoteFolderWatcher.init?(url:latency:onPaths: @escaping ([String]) -> Void)` und weiter `init?(url:latency:onChange: @escaping () -> Void)`
  - `static func NoteFolderWatcher.concernsFolder(_ paths: [String], folder: URL) -> Bool`

- [ ] **Schritt 1: Die fehlschlagenden Tests schreiben**

`Tests/ShoutTests/NoteStoreScratchpadTests.swift`:

```swift
import XCTest

@MainActor
final class NoteStoreScratchpadTests: XCTestCase {

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

    func testAnlegenMitFestemTitelUndLeeremText() throws {
        let s = u.store()
        guard case .saved(let notiz) = s.create(title: "Eingang", body: "", pinned: true) else {
            return XCTFail("nicht angelegt")
        }
        XCTAssertEqual(notiz.fileName, "Eingang.md")
        XCTAssertTrue(notiz.pinned)
        XCTAssertTrue(notiz.titleIsFixed)
        XCTAssertEqual(s.notes.map(\.id), [notiz.id])
        XCTAssertTrue(NoteFile.parse(try XCTUnwrap(u.lies("Eingang.md"))).pinned)
    }

    func testAnlegenAufBelegtenNamen() throws {
        try u.schreibe("Eingang.md", "fremd")
        let s = u.store()
        guard case .saved(let notiz) = s.create(title: "Eingang", body: "", pinned: true) else {
            return XCTFail("nicht angelegt")
        }
        XCTAssertEqual(notiz.fileName, "Eingang 2.md")
        XCTAssertEqual(u.text("Eingang.md"), "fremd")
    }

    func testAnlegenOhneOrdnerScheitert() {
        let s = u.store(ordner: u.wurzel.appendingPathComponent("fehlt", isDirectory: true))
        XCTAssertEqual(s.create(title: "Eingang", body: "", pinned: true), .failed)
    }

    func testUmbenennenWirdGemeldet() throws {
        try u.schreibe("Eingang.md", "x")
        let s = u.store()
        var gemeldet: [(String, String)] = []
        s.onRename = { gemeldet.append(($0, $1)) }
        s.rename(s.notes[0].id, to: "Sammelstelle")
        XCTAssertEqual(gemeldet.count, 1)
        XCTAssertEqual(gemeldet.first?.0, "Eingang.md")
        XCTAssertEqual(gemeldet.first?.1, "Sammelstelle.md")
    }
}
```

`Tests/ShoutTests/NoteFolderWatcherFilterTests.swift`:

```swift
import XCTest

/// Obsidian schreibt ständig in `.obsidian/`, Bilder liegen in `Anhänge/` — beides
/// betrifft die Notizliste nicht und soll kein Neueinlesen auslösen.
final class NoteFolderWatcherFilterTests: XCTestCase {

    private let ordner = URL(fileURLWithPath: "/tmp/notizen-filter", isDirectory: true)

    func testDateiDirektImOrdner() {
        XCTAssertTrue(NoteFolderWatcher.concernsFolder(["/tmp/notizen-filter/Idee.md"], folder: ordner))
    }

    func testDerOrdnerSelbst() {
        XCTAssertTrue(NoteFolderWatcher.concernsFolder(["/tmp/notizen-filter"], folder: ordner))
    }

    func testUnterordnerNicht() {
        XCTAssertFalse(NoteFolderWatcher.concernsFolder(["/tmp/notizen-filter/.obsidian/workspace.json"], folder: ordner))
        XCTAssertFalse(NoteFolderWatcher.concernsFolder(["/tmp/notizen-filter/Anhänge/bild.png"], folder: ordner))
    }

    func testVersteckteDateiNicht() {
        XCTAssertFalse(NoteFolderWatcher.concernsFolder(["/tmp/notizen-filter/.DS_Store"], folder: ordner))
    }

    /// Ausgelagerte iCloud-Dateien beginnen mit einem Punkt, betreffen die Liste aber sehr wohl.
    func testICloudPlatzhalterSchon() {
        XCTAssertTrue(NoteFolderWatcher.concernsFolder(["/tmp/notizen-filter/.Idee.md.icloud"], folder: ordner))
    }

    /// Ohne Pfade (zusammengefasste Meldung) lieber neu einlesen.
    func testOhnePfadeSicherheitshalberJa() {
        XCTAssertTrue(NoteFolderWatcher.concernsFolder([], folder: ordner))
    }

    func testMehrerePfadeEinTrefferReicht() {
        XCTAssertTrue(NoteFolderWatcher.concernsFolder(
            ["/tmp/notizen-filter/.obsidian/a.json", "/tmp/notizen-filter/B.md"], folder: ordner))
    }
}
```

- [ ] **Schritt 2: Test laufen lassen**

`xcodegen generate`, Testbefehl mit `-only-testing:ShoutTests/NoteStoreScratchpadTests -only-testing:ShoutTests/NoteFolderWatcherFilterTests`.
Erwartet: Build-Fehler (`create`, `onRename`, `concernsFolder` fehlen).

- [ ] **Schritt 3: Store erweitern**

In `Sources/FlowLokal/NoteStore.swift`:

1. Nach `@Published private(set) var folderState: FolderState = .ok` einfügen:

```swift
    /// Nach jedem Umbenennen über `rename(_:to:)`: alter und neuer Dateiname.
    /// Das Panel folgt so der umbenannten Eingangs-Notiz.
    var onRename: ((String, String) -> Void)?
    /// Für diese Platzhalter wurde der iCloud-Download schon angestoßen.
    private var angestosseneDownloads = Set<String>()
```

2. In der Erweiterung „Umbenennen, Anheften, Papierkorb“ direkt nach `rename(_:to:)` einfügen:

```swift
    /// Legt eine Notiz unter einem festen Titel an (die Eingangs-Notiz). Ist der
    /// Name belegt, wird es „Titel 2“. Ein leerer Text ist hier erlaubt.
    /// `.failed`, wenn der Ordner fehlt oder das Schreiben scheitert.
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
        note.fileName = NoteFile.freeFileName(for: titel, in: folder)
        guard let mtime = write(note, to: folder.appendingPathComponent(note.fileName)) else { return .failed }
        note.modified = mtime
        cache[note.fileName] = note
        publish()
        return .saved(note)
    }
```

3. In `rename(_:to:)`: Den alten Namen vor dem Verschieben festhalten
(`let alterName = note.fileName`) und nach erfolgreichem Umbenennen — direkt vor
`return note` — melden:

```swift
        if alterName != note.fileName { onRename?(alterName, note.fileName) }
```

4. In `placeholder(fileName:)` den Download nur einmal anstoßen. Die Zeile
`try? fileManager.startDownloadingUbiquitousItem(at: url)` ersetzen durch:

```swift
        if angestosseneDownloads.insert(fileName).inserted {
            try? fileManager.startDownloadingUbiquitousItem(at: url)
        }
```

5. In `startWatchingIfNeeded()` den Watcher mit Pfaden anlegen:

```swift
        watcher = NoteFolderWatcher(url: folder, onPaths: { [weak self] pfade in
            MainActor.assumeIsolated {
                guard let self, NoteFolderWatcher.concernsFolder(pfade, folder: self.folder) else { return }
                self.reload()
            }
        })
```

- [ ] **Schritt 4: Watcher erweitern**

In `Sources/FlowLokal/NoteFolderWatcher.swift`:

1. Die gespeicherte Rückmeldung wird `private let onChange: ([String]) -> Void`.
2. Den bestehenden Initialisierer umbenennen in
   `init?(url: URL, latency: TimeInterval = 0.5, onPaths: @escaping ([String]) -> Void)`,
   `self.onChange = onPaths` setzen und die Flags auf
   `UInt32(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagUseCFTypes)`
   erweitern. Im C-Rückruf die Pfade auslesen und weitergeben (mit `UseCFTypes`
   kommen sie als `CFArray` von `CFString`):

```swift
            let pfade = (Unmanaged<CFArray>.fromOpaque(eventPaths).takeUnretainedValue() as NSArray) as? [String] ?? []
```

   (`eventPaths` ist der vierte Parameter des Rückrufs; er heißt im bestehenden
   Code `_` und bekommt jetzt diesen Namen.) Der Aufruf geht wie bisher über
   den schwachen Kasten an den Watcher, jetzt mit `pfade`.

3. Einen bequemen Initialisierer für Aufrufer ohne Pfade ergänzen (die
   bestehenden Tests benutzen ihn):

```swift
    convenience init?(url: URL, latency: TimeInterval = 0.5, onChange: @escaping () -> Void) {
        self.init(url: url, latency: latency, onPaths: { _ in onChange() })
    }
```

4. Die reine Prüfung ergänzen:

```swift
    /// Betreffen die gemeldeten Pfade die Notizliste? Nur Dateien direkt im
    /// Ordner (oder der Ordner selbst). Unterordner (`.obsidian/`, `Anhänge/`)
    /// und versteckte Dateien nicht — ausgelagerte iCloud-Notizen (`.X.md.icloud`)
    /// schon. Ohne Pfade sicherheitshalber ja.
    static func concernsFolder(_ paths: [String], folder: URL) -> Bool {
        guard !paths.isEmpty else { return true }
        let ordner = folder.resolvingSymlinksInPath().standardizedFileURL.path
        return paths.contains { pfad in
            let datei = URL(fileURLWithPath: pfad).standardizedFileURL
            if datei.path == ordner { return true }
            guard datei.deletingLastPathComponent().path == ordner else { return false }
            let name = datei.lastPathComponent
            return !name.hasPrefix(".") || NoteFile.placeholderTarget(name) != nil
        }
    }
```

- [ ] **Schritt 5: Tests laufen lassen**

Testbefehl mit `-only-testing:ShoutTests/NoteStoreScratchpadTests -only-testing:ShoutTests/NoteFolderWatcherFilterTests -only-testing:ShoutTests/NoteFolderWatcherTests -only-testing:ShoutTests/NoteStoreTests`.
Erwartet: 0 Fehler. Dann die ganze Suite.

- [ ] **Schritt 6: Commit**

```bash
cd /Users/liam/Developer/LIAM/flow-lokal && git add Sources/FlowLokal/NoteStore.swift Sources/FlowLokal/NoteFolderWatcher.swift Tests/ShoutTests/NoteStoreScratchpadTests.swift Tests/ShoutTests/NoteFolderWatcherFilterTests.swift && git commit -m "Notizen: Notiz mit festem Titel anlegen, Umbenennen melden, Watcher nur für den Ordner selbst" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Aufgabe 7: `ScratchpadModel` — Tabs, Diktat in Notiz, Eingang

**Dateien:**
- Neu: `Sources/FlowLokal/ScratchpadModel.swift`
- Neu: `Tests/ShoutTests/ScratchpadModelTests.swift`
- Ändern: `project.yml` (nach `- path: Sources/FlowLokal/NoteEditorView.swift`)

**Schnittstellen:**
- Benutzt: `NoteSessionRegistry` (`acquire`, `acquireNew`, `release`, `discard`, `session(id:)`, `onDiscard`), `NoteStore` (`notes`, `note(id:)`, `create`, `onRename`), `NoteEditorSession` (`insert`, `flush`, `hasUnsavedText`), `NoteInbox.appendix`, `NoteSearch.filter`, `Loc`
- Liefert (`@MainActor final class ScratchpadModel: ObservableObject`):
  - `enum OpenBehavior: String, CaseIterable { case resume, newTab, lastPinned }`, `static let maxTabs = 5`
  - `init(store:registry:defaults:)`, `let store`, `let registry`
  - `@Published private(set) var tabs: [NoteEditorSession]`, `activeIndex: Int?`, `@Published var showsList: Bool`, `@Published var query: String`
  - `var active: NoteEditorSession?`, `var results: [NoteSearch.Result]`
  - `func restoreTabs()`, `func prepareForShowing(behavior:)`, `@discardableResult func newTab() -> NoteEditorSession?`
  - `func open(_ id: UUID, inNewTab: Bool)`, `func select(_ index: Int)`, `func selectNext(_ offset: Int)`, `func close(_ index: Int)`
  - `func flushAll()`, `func resetTabs()`, `func discard(_ session: NoteEditorSession)`
  - `func tabForDictation(newIfActiveHasText: Bool) -> NoteEditorSession?`
  - `func insertDictation(_ text: String, into id: UUID) -> Bool`
  - `var inboxFileName: String`, `func appendToInbox(_ text: String, now: Date = Date(), locale: Locale? = nil) -> Bool`, `func openInbox()`

- [ ] **Schritt 1: Den fehlschlagenden Test schreiben**

`Tests/ShoutTests/ScratchpadModelTests.swift`:

```swift
import XCTest

@MainActor
final class ScratchpadModelTests: XCTestCase {

    private var u: NotizUmgebung!
    private var suite: String!
    private var defaults: UserDefaults!

    override func setUpWithError() throws {
        Loc.shared.apply("de")
        u = try NotizUmgebung()
        suite = "shout-scratchpad-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)
    }

    override func tearDown() {
        u.aufraeumen()
        defaults.removePersistentDomain(forName: suite)
        Loc.shared.apply("system")
        super.tearDown()
    }

    private func modell(_ store: NoteStore? = nil) -> ScratchpadModel {
        let s = store ?? u.store()
        return ScratchpadModel(store: s, registry: NoteSessionRegistry(store: s, saveDelay: 60), defaults: defaults)
    }

    private func id(_ m: ScratchpadModel, _ titel: String) -> UUID {
        m.store.notes.first { $0.title == titel }!.id
    }

    func testBisFuenfTabsDannWirdDerAktiveErsetzt() {
        let m = modell()
        for _ in 0..<5 { XCTAssertNotNil(m.newTab()) }
        XCTAssertEqual(m.tabs.count, 5)
        let sechster = m.newTab()
        XCTAssertEqual(m.tabs.count, 5)
        XCTAssertEqual(m.activeIndex, 4)
        XCTAssertTrue(m.tabs[4] === sechster)
    }

    func testOeffnenWaehltVorhandenenTab() throws {
        try u.schreibe("A.md", "a")
        try u.schreibe("B.md", "b")
        let m = modell()
        m.open(id(m, "A"), inNewTab: true)
        m.open(id(m, "B"), inNewTab: true)
        m.open(id(m, "A"), inNewTab: true)
        XCTAssertEqual(m.tabs.count, 2)
        XCTAssertEqual(m.activeIndex, 0)
    }

    func testSchliessenRuecktDieAuswahl() {
        let m = modell()
        m.newTab(); m.newTab(); m.newTab()
        XCTAssertEqual(m.activeIndex, 2)
        m.close(0)
        XCTAssertEqual(m.activeIndex, 1)
        m.close(1)
        XCTAssertEqual(m.activeIndex, 0)
        m.close(0)
        XCTAssertNil(m.activeIndex)
        XCTAssertTrue(m.tabs.isEmpty)
    }

    func testTabsUeberlebenDenNeustart() throws {
        try u.schreibe("A.md", "a")
        try u.schreibe("B.md", "b")
        let store = u.store()
        let m = modell(store)
        m.open(id(m, "A"), inNewTab: true)
        m.open(id(m, "B"), inNewTab: true)
        m.select(0)
        let zweites = modell(store)
        zweites.restoreTabs()
        XCTAssertEqual(zweites.tabs.map(\.note.title), ["A", "B"])
        XCTAssertEqual(zweites.activeIndex, 0)
    }

    func testOeffnenVerhaltenNeuerTab() throws {
        try u.schreibe("A.md", "Text")
        let m = modell()
        m.open(id(m, "A"), inNewTab: true)
        m.prepareForShowing(behavior: .newTab)
        XCTAssertEqual(m.tabs.count, 2)
        m.prepareForShowing(behavior: .newTab)      // vorderer Tab ist leer: kein dritter
        XCTAssertEqual(m.tabs.count, 2)
    }

    func testOeffnenVerhaltenAngeheftet() throws {
        try u.schreibe("A.md", "---\npinned: true\n---\nangeheftet")
        try u.schreibe("B.md", "b")
        let m = modell()
        m.prepareForShowing(behavior: .lastPinned)
        XCTAssertEqual(m.active?.note.title, "A")
    }

    func testOeffnenVerhaltenFortsetzenOhneTabs() {
        let m = modell()
        m.prepareForShowing(behavior: .resume)
        XCTAssertEqual(m.tabs.count, 1)
        XCTAssertEqual(m.active?.note.isNew, true)
    }

    func testDiktatTabNeuWennDerAktiveTextHat() throws {
        try u.schreibe("A.md", "Text")
        let m = modell()
        m.open(id(m, "A"), inNewTab: true)
        let neu = m.tabForDictation(newIfActiveHasText: true)
        XCTAssertEqual(neu?.note.isNew, true)
        XCTAssertTrue(m.tabForDictation(newIfActiveHasText: false) === neu)
    }

    func testDiktatLandetAmCursor() {
        let m = modell()
        let s = m.newTab()!
        s.edit("Hallo")
        s.selectionChanged(NSRange(location: 5, length: 0))
        XCTAssertTrue(m.insertDictation("Welt", into: s.id))
        XCTAssertEqual(s.note.body, "Hallo Welt")
    }

    /// Ist die Zielnotiz nicht mehr offen, entsteht ein neuer Tab — das Diktat geht nicht verloren.
    func testDiktatOhneZielInNeuenTab() {
        let m = modell()
        XCTAssertTrue(m.insertDictation("Gedanke", into: UUID()))
        XCTAssertEqual(m.active?.note.body, "Gedanke")
    }

    func testEingangWirdAngelegtUndAngehaengt() throws {
        let m = modell()
        let mittag = ISO8601DateFormatter().date(from: "2026-10-05T12:32:00Z")!
        XCTAssertTrue(m.appendToInbox("Milch kaufen", now: mittag, locale: Locale(identifier: "de_DE")))
        XCTAssertTrue(m.appendToInbox("Brot", now: mittag.addingTimeInterval(600), locale: Locale(identifier: "de_DE")))
        let roh = try XCTUnwrap(u.lies("Eingang.md"))
        let geparst = NoteFile.parse(roh)
        XCTAssertTrue(geparst.pinned)
        XCTAssertEqual(geparst.body.components(separatedBy: "## ").count - 1, 1)   // eine Tagesüberschrift
        XCTAssertTrue(geparst.body.contains("Milch kaufen"))
        XCTAssertTrue(geparst.body.contains("Brot"))
    }

    func testEingangFolgtDerUmbenennung() throws {
        let m = modell()
        XCTAssertTrue(m.appendToInbox("eins"))
        let eingang = try XCTUnwrap(m.store.notes.first { $0.fileName == "Eingang.md" })
        m.store.rename(eingang.id, to: "Sammelstelle")
        XCTAssertEqual(m.inboxFileName, "Sammelstelle.md")
        XCTAssertTrue(m.appendToInbox("zwei"))
        XCTAssertEqual(u.dateien(), ["Sammelstelle.md"])
        XCTAssertTrue(try XCTUnwrap(u.text("Sammelstelle.md")).contains("zwei"))
    }

    func testVerworfeneSitzungVerschwindetAusDenTabs() {
        let m = modell()
        let s = m.newTab()!
        m.discard(s)
        XCTAssertTrue(m.tabs.isEmpty)
        XCTAssertNil(m.activeIndex)
    }
}
```

- [ ] **Schritt 2: Eintragen und Test laufen lassen**

In `project.yml` nach `      - path: Sources/FlowLokal/NoteEditorView.swift`:

```yaml
      - path: Sources/FlowLokal/ScratchpadModel.swift
```

```bash
cd /Users/liam/Developer/LIAM/flow-lokal && touch Sources/FlowLokal/ScratchpadModel.swift && xcodegen generate
```

Testbefehl mit `-only-testing:ShoutTests/ScratchpadModelTests`.
Erwartet: Build-Fehler „cannot find 'ScratchpadModel' in scope“.

- [ ] **Schritt 3: `ScratchpadModel` schreiben**

`Sources/FlowLokal/ScratchpadModel.swift`:

```swift
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

    private enum K {
        static let tabs = "scratchpad.tabs"
        static let aktiv = "scratchpad.activeTab"
        static let liste = "scratchpad.showsList"
        static let angeheftet = "scratchpad.lastPinned"
        static let eingang = "scratchpad.inboxFileName"
    }

    init(store: NoteStore, registry: NoteSessionRegistry, defaults: UserDefaults = .standard) {
        self.store = store
        self.registry = registry
        self.defaults = defaults
        showsList = defaults.object(forKey: K.liste) as? Bool ?? true
        registry.onDiscard { [weak self] id in self?.dropTab(id) }
        store.onRename = { [weak self] alt, neu in
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
            guard let note = store.notes.first(where: { $0.fileName == name }) else { continue }
            tabs.append(registry.acquire(note))
        }
        activeIndex = tabs.isEmpty ? nil : min(max(defaults.integer(forKey: K.aktiv), 0), tabs.count - 1)
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

    /// ⌘⇧[ und ⌘⇧] — rundherum.
    func selectNext(_ offset: Int) {
        guard !tabs.isEmpty else { return }
        let jetzt = activeIndex ?? 0
        select(((jetzt + offset) % tabs.count + tabs.count) % tabs.count)
    }

    /// Schließt einen Tab. Gesichert wird beim Abgeben an die Registry.
    func close(_ index: Int) {
        guard tabs.indices.contains(index) else { return }
        let weg = tabs.remove(at: index)
        rueckeAuswahl(nachEntfernen: index)
        registry.release(weg)
        persist()
    }

    /// Beim Ausblenden: alle Tabs sichern, die Tabs bleiben.
    func flushAll() {
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
        return !session.hasUnsavedText
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
        defaults.set(activeIndex ?? 0, forKey: K.aktiv)
    }
}
```

- [ ] **Schritt 4: Tests laufen lassen**

Testbefehl mit `-only-testing:ShoutTests/ScratchpadModelTests`. Erwartet: 13 Tests, 0 Fehler.

- [ ] **Schritt 5: Commit**

```bash
cd /Users/liam/Developer/LIAM/flow-lokal && git add project.yml Sources/FlowLokal/ScratchpadModel.swift Tests/ShoutTests/ScratchpadModelTests.swift && git commit -m "Scratchpad: Tabs, Diktat in die offene Notiz, Eingangs-Notiz" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Aufgabe 8: Tasten und Ziel — Bausteine

**Dateien:**
- Neu: `Sources/FlowLokal/HotkeyCombo.swift`, `Sources/FlowLokal/HotkeyPressClassifier.swift`, `Sources/FlowLokal/DictationTarget.swift`, `Sources/FlowLokal/ScratchpadSettings.swift`, `Sources/FlowLokal/GlobalHotkey.swift`
- Neu: `Tests/ShoutTests/HotkeyTests.swift`
- Ändern: `project.yml` (nach `- path: Sources/FlowLokal/ScratchpadModel.swift`; dazu `RecordingSettings.swift`, das die Tastennamen liefert)

**Schnittstellen:**
- Liefert:
  - `struct HotkeyCombo: Codable, Equatable { keyCode: UInt16; modifiers: UInt; init(keyCode:flags:); var flags; var carbonModifiers: UInt32; static let scratchpadDefault (⌃⌥N), inboxDefault (⌃⌥I); @MainActor var display: String }`
  - `struct HotkeyPressClassifier { static let holdThreshold = 0.35; enum Outcome { tap, holdBegan, holdEnded }; mutating press(at:), tick(at:) -> Outcome?, release(at:) -> Outcome? }`
  - `enum DictationTarget: Equatable { frontApp(bundleID: String?), scratchpad(noteID: UUID), inbox; static func forDictationKey(panelIsKey:activeNote:frontBundleID:); var formatterBundleID: String?; var isFrontApp: Bool }`
  - `@MainActor final class ScratchpadSettings: ObservableObject` mit `enum Role { scratchpad, inbox }`, `isEnabled`, `openBehavior`, `combo(for:)`, `setCombo(_:for:)`, `registrationProblems`, `capturing`, `captureHint`, `onChange`, `rejection(for:role:dictationKey:)`
  - `@MainActor final class GlobalHotkey { var onPress, onRelease; func register(_ combo: HotkeyCombo) throws; func unregister() }` mit `enum RegistrationError: Error { case taken, failed(OSStatus) }`

- [ ] **Schritt 1: Den fehlschlagenden Test schreiben**

`Tests/ShoutTests/HotkeyTests.swift`:

```swift
import XCTest
import AppKit
import Carbon.HIToolbox

@MainActor
final class HotkeyTests: XCTestCase {

    // MARK: - Tippen oder Halten

    func testKurzesDrueckenIstTippen() {
        var k = HotkeyPressClassifier()
        k.press(at: 0)
        XCTAssertNil(k.tick(at: 0.1))
        XCTAssertEqual(k.release(at: 0.2), .tap)
    }

    func testHaltenBeginntUndEndet() {
        var k = HotkeyPressClassifier()
        k.press(at: 0)
        XCTAssertEqual(k.tick(at: 0.35), .holdBegan)
        XCTAssertNil(k.tick(at: 0.5))                 // nur einmal
        XCTAssertEqual(k.release(at: 2), .holdEnded)
    }

    func testLoslassenOhneDrueckenIstNichts() {
        var k = HotkeyPressClassifier()
        XCTAssertNil(k.release(at: 1))
    }

    /// Kam der Zeitgeber zu spät (Hauptstrang beschäftigt), gilt das Loslassen als Tippen.
    func testLangesDrueckenOhneZeitgeberIstTippen() {
        var k = HotkeyPressClassifier()
        k.press(at: 0)
        XCTAssertEqual(k.release(at: 1), .tap)
    }

    // MARK: - Kombination

    func testCarbonModifier() {
        let c = HotkeyCombo(keyCode: 45, flags: [.control, .option, .function])
        XCTAssertEqual(c.flags, [.control, .option])
        XCTAssertEqual(c.carbonModifiers, UInt32(controlKey) | UInt32(optionKey))
    }

    func testVorgabenUndAnzeige() {
        XCTAssertEqual(HotkeyCombo.scratchpadDefault.display, "⌃⌥N")
        XCTAssertEqual(HotkeyCombo.inboxDefault.display, "⌃⌥I")
    }

    // MARK: - Ziel

    func testZielFuerDieDiktiertaste() {
        let id = UUID()
        XCTAssertEqual(DictationTarget.forDictationKey(panelIsKey: true, activeNote: id, frontBundleID: "com.apple.mail"),
                       .scratchpad(noteID: id))
        XCTAssertEqual(DictationTarget.forDictationKey(panelIsKey: false, activeNote: id, frontBundleID: "com.apple.mail"),
                       .frontApp(bundleID: "com.apple.mail"))
        XCTAssertEqual(DictationTarget.forDictationKey(panelIsKey: true, activeNote: nil, frontBundleID: nil),
                       .frontApp(bundleID: nil))
    }

    func testFormatierungNurFuerFremdeApp() {
        XCTAssertEqual(DictationTarget.frontApp(bundleID: "x").formatterBundleID, "x")
        XCTAssertNil(DictationTarget.inbox.formatterBundleID)
        XCTAssertNil(DictationTarget.scratchpad(noteID: UUID()).formatterBundleID)
        XCTAssertTrue(DictationTarget.frontApp(bundleID: nil).isFrontApp)
        XCTAssertFalse(DictationTarget.inbox.isFrontApp)
    }

    // MARK: - Einstellungen

    private func einstellungen() -> (ScratchpadSettings, UserDefaults, String) {
        let suite = "shout-hotkeys-\(UUID().uuidString)"
        let d = UserDefaults(suiteName: suite)!
        return (ScratchpadSettings(defaults: d), d, suite)
    }

    func testVorgabenOhneGespeichertes() {
        let (s, d, suite) = einstellungen()
        defer { d.removePersistentDomain(forName: suite) }
        XCTAssertTrue(s.isEnabled)
        XCTAssertEqual(s.openBehavior, .resume)
        XCTAssertEqual(s.combo(for: .scratchpad), .scratchpadDefault)
        XCTAssertEqual(s.combo(for: .inbox), .inboxDefault)
    }

    func testGespeichertUndGeleert() {
        let (s, d, suite) = einstellungen()
        defer { d.removePersistentDomain(forName: suite) }
        let neu = HotkeyCombo(keyCode: 1, flags: [.control, .option])     // ⌃⌥S
        s.setCombo(neu, for: .scratchpad)
        s.setCombo(nil, for: .inbox)
        let wieder = ScratchpadSettings(defaults: d)
        XCTAssertEqual(wieder.combo(for: .scratchpad), neu)
        XCTAssertNil(wieder.combo(for: .inbox))      // bewusst „Keine“, nicht die Vorgabe
    }

    func testAenderungWirdGemeldet() {
        let (s, d, suite) = einstellungen()
        defer { d.removePersistentDomain(forName: suite) }
        var gemeldet = 0
        s.onChange = { gemeldet += 1 }
        s.setCombo(nil, for: .inbox)
        s.isEnabled = false
        XCTAssertEqual(gemeldet, 2)
    }

    func testPruefungDerKombination() {
        let (s, d, suite) = einstellungen()
        defer { d.removePersistentDomain(forName: suite) }
        let diktat: (keyCode: UInt16, modifiers: UInt, isModifierOnly: Bool) = (61, 0, true)
        // Ohne ⌃ oder ⌥ würde die Taste Kürzel anderer Apps abfangen.
        XCTAssertNotNil(s.rejection(for: HotkeyCombo(keyCode: 45, flags: [.command]), role: .scratchpad, dictationKey: diktat))
        // Feste Kürzel von shout.
        XCTAssertNotNil(s.rejection(for: HotkeyCombo(keyCode: 8, flags: [.command, .option]), role: .scratchpad, dictationKey: diktat))
        // Schon von der anderen Rolle belegt.
        XCTAssertNotNil(s.rejection(for: .inboxDefault, role: .scratchpad, dictationKey: diktat))
        // Die Diktiertaste selbst.
        let diktatKombi: (keyCode: UInt16, modifiers: UInt, isModifierOnly: Bool) =
            (1, NSEvent.ModifierFlags([.control, .option]).rawValue, false)
        XCTAssertNotNil(s.rejection(for: HotkeyCombo(keyCode: 1, flags: [.control, .option]), role: .scratchpad, dictationKey: diktatKombi))
        // Gültig.
        XCTAssertNil(s.rejection(for: HotkeyCombo(keyCode: 1, flags: [.control, .option]), role: .scratchpad, dictationKey: diktat))
        // Die eigene, unveränderte Belegung ist kein Konflikt mit sich selbst.
        XCTAssertNil(s.rejection(for: .scratchpadDefault, role: .scratchpad, dictationKey: diktat))
    }
}
```

- [ ] **Schritt 2: Eintragen und Test laufen lassen**

In `project.yml` nach `      - path: Sources/FlowLokal/ScratchpadModel.swift`:

```yaml
      - path: Sources/FlowLokal/RecordingSettings.swift
      - path: Sources/FlowLokal/HotkeyCombo.swift
      - path: Sources/FlowLokal/HotkeyPressClassifier.swift
      - path: Sources/FlowLokal/DictationTarget.swift
      - path: Sources/FlowLokal/ScratchpadSettings.swift
      - path: Sources/FlowLokal/GlobalHotkey.swift
```

```bash
cd /Users/liam/Developer/LIAM/flow-lokal && touch Sources/FlowLokal/HotkeyCombo.swift Sources/FlowLokal/HotkeyPressClassifier.swift Sources/FlowLokal/DictationTarget.swift Sources/FlowLokal/ScratchpadSettings.swift Sources/FlowLokal/GlobalHotkey.swift && xcodegen generate
```

Testbefehl mit `-only-testing:ShoutTests/HotkeyTests`.
Erwartet: Build-Fehler „cannot find 'HotkeyPressClassifier' in scope“.
(Kompiliert `RecordingSettings.swift` im Testziel nicht, weil es etwas aus dem
App-Ziel braucht: das melden — nicht kopieren.)

- [ ] **Schritt 3: Implementieren**

`Sources/FlowLokal/HotkeyCombo.swift`:

```swift
import AppKit
import Carbon.HIToolbox

/// Eine Tastenkombination für die globalen Tasten des Scratchpads. Gespeichert
/// in NSEvent-Form (wie die Diktiertaste), umgerechnet für Carbon.
struct HotkeyCombo: Codable, Equatable {
    var keyCode: UInt16
    /// `NSEvent.ModifierFlags.rawValue`, nur ⌘ ⌥ ⌃ ⇧.
    var modifiers: UInt

    init(keyCode: UInt16, flags: NSEvent.ModifierFlags) {
        self.keyCode = keyCode
        modifiers = flags.intersection([.command, .option, .control, .shift]).rawValue
    }

    var flags: NSEvent.ModifierFlags { NSEvent.ModifierFlags(rawValue: modifiers) }

    var carbonModifiers: UInt32 {
        var ergebnis: UInt32 = 0
        if flags.contains(.command) { ergebnis |= UInt32(cmdKey) }
        if flags.contains(.option) { ergebnis |= UInt32(optionKey) }
        if flags.contains(.control) { ergebnis |= UInt32(controlKey) }
        if flags.contains(.shift) { ergebnis |= UInt32(shiftKey) }
        return ergebnis
    }

    /// ⌃⌥N — erzeugt in keiner üblichen Belegung ein Zeichen.
    static let scratchpadDefault = HotkeyCombo(keyCode: 45, flags: [.control, .option])
    /// ⌃⌥I
    static let inboxDefault = HotkeyCombo(keyCode: 34, flags: [.control, .option])

    /// „⌃⌥N“
    @MainActor
    var display: String {
        var text = ""
        if flags.contains(.control) { text += "⌃" }
        if flags.contains(.option) { text += "⌥" }
        if flags.contains(.shift) { text += "⇧" }
        if flags.contains(.command) { text += "⌘" }
        return text + RecordingSettings.keyName(forKeyCode: keyCode)
    }
}
```

`Sources/FlowLokal/HotkeyPressClassifier.swift`:

```swift
import Foundation

/// Tippen oder Halten der Scratchpad-Taste. Rein: Der Aufrufer meldet Drücken,
/// Loslassen und — per Zeitgeber nach `holdThreshold` — einen Zwischenstand.
struct HotkeyPressClassifier {

    static let holdThreshold: TimeInterval = 0.35

    enum Outcome: Equatable {
        case tap
        case holdBegan
        case holdEnded
    }

    private var gedruecktSeit: TimeInterval?
    private var haelt = false

    mutating func press(at zeit: TimeInterval) {
        gedruecktSeit = zeit
        haelt = false
    }

    /// Vom Zeitgeber. Liefert `.holdBegan` genau einmal, wenn die Taste lange genug unten ist.
    mutating func tick(at zeit: TimeInterval) -> Outcome? {
        // Kleine Toleranz: Zeitgeber feuern gelegentlich minimal zu früh.
        guard let seit = gedruecktSeit, !haelt, zeit - seit >= Self.holdThreshold - 0.02 else { return nil }
        haelt = true
        return .holdBegan
    }

    mutating func release(at zeit: TimeInterval) -> Outcome? {
        guard gedruecktSeit != nil else { return nil }
        defer {
            gedruecktSeit = nil
            haelt = false
        }
        return haelt ? .holdEnded : .tap
    }
}
```

`Sources/FlowLokal/DictationTarget.swift`:

```swift
import Foundation

/// Wohin ein Diktat geht. Festgelegt beim Start der Aufnahme — späteres Klicken
/// ändert es nicht.
enum DictationTarget: Equatable {
    /// Wie bisher: Einfügen in die App, die beim Start vorne war.
    case frontApp(bundleID: String?)
    /// An den Cursor einer Notiz im Panel.
    case scratchpad(noteID: UUID)
    /// Angehängt an die Eingangs-Notiz.
    case inbox

    /// Ziel der normalen Diktiertaste: ins Panel, wenn es den Tastatur-Fokus hat
    /// und eine Notiz offen ist; sonst in die App davor.
    static func forDictationKey(panelIsKey: Bool, activeNote: UUID?, frontBundleID: String?) -> DictationTarget {
        if panelIsKey, let activeNote { return .scratchpad(noteID: activeNote) }
        return .frontApp(bundleID: frontBundleID)
    }

    /// Für den Ton der Aufbereitung. Notizen bekommen den neutralen.
    var formatterBundleID: String? {
        if case .frontApp(let id) = self { return id }
        return nil
    }

    var isFrontApp: Bool {
        if case .frontApp = self { return true }
        return false
    }
}
```

`Sources/FlowLokal/ScratchpadSettings.swift`:

```swift
import AppKit
import Combine

/// Einstellungen des Scratchpads: an/aus, die zwei globalen Tasten, das
/// Verhalten beim Öffnen. In den UserDefaults.
@MainActor
final class ScratchpadSettings: ObservableObject {

    enum Role: String, CaseIterable {
        case scratchpad
        case inbox
    }

    @Published var isEnabled: Bool {
        didSet { d.set(isEnabled, forKey: K.aktiv); onChange?() }
    }
    @Published var openBehavior: ScratchpadModel.OpenBehavior {
        didSet { d.set(openBehavior.rawValue, forKey: K.oeffnen) }
    }
    @Published private(set) var combos: [Role: HotkeyCombo] = [:]
    /// „Von einer anderen App belegt“ je Rolle, gesetzt beim Registrieren.
    @Published var registrationProblems: [Role: String] = [:]
    /// Welche Taste gerade aufgenommen wird (Oberflächenzustand).
    @Published var capturing: Role?
    @Published var captureHint: String?
    /// Tasten oder an/aus geändert — der AppDelegate registriert neu.
    var onChange: (() -> Void)?

    private let d: UserDefaults
    private enum K {
        static let aktiv = "scratchpad.enabled"
        static let oeffnen = "scratchpad.openBehavior"
        static func kombi(_ rolle: Role) -> String { "scratchpad.combo.\(rolle.rawValue)" }
    }

    init(defaults: UserDefaults = .standard) {
        d = defaults
        isEnabled = defaults.object(forKey: K.aktiv) as? Bool ?? true
        openBehavior = ScratchpadModel.OpenBehavior(rawValue: defaults.string(forKey: K.oeffnen) ?? "") ?? .resume
        for rolle in Role.allCases {
            if let daten = defaults.data(forKey: K.kombi(rolle)) {
                // Leere Daten: bewusst „Keine“.
                combos[rolle] = try? JSONDecoder().decode(HotkeyCombo.self, from: daten)
            } else {
                combos[rolle] = rolle == .scratchpad ? .scratchpadDefault : .inboxDefault
            }
        }
    }

    func combo(for rolle: Role) -> HotkeyCombo? { combos[rolle] }

    func setCombo(_ kombi: HotkeyCombo?, for rolle: Role) {
        combos[rolle] = kombi
        d.set(kombi.flatMap { try? JSONEncoder().encode($0) } ?? Data(), forKey: K.kombi(rolle))
        onChange?()
    }

    /// Feste Kürzel von shout.
    static let reserved: [HotkeyCombo] = [
        HotkeyCombo(keyCode: 8, flags: [.command, .option]),     // ⌥⌘C Korrektur
        HotkeyCombo(keyCode: 9, flags: [.command, .control]),    // ⌃⌘V zuletzt Gesprochenes
    ]

    /// Warum eine Kombination für `rolle` nicht taugt — oder `nil`.
    func rejection(for kombi: HotkeyCombo, role rolle: Role,
                   dictationKey: (keyCode: UInt16, modifiers: UInt, isModifierOnly: Bool)) -> String? {
        // Ohne ⌃ oder ⌥ finge die Taste Kürzel anderer Apps ab (⌘N, ⌘⇧N …).
        guard !kombi.flags.intersection([.control, .option]).isEmpty else {
            return Loc.t("Mit ⌃ oder ⌥ kombinieren")
        }
        if Self.reserved.contains(kombi) { return Loc.t("Schon belegt") }
        for andere in Role.allCases where andere != rolle && combos[andere] == kombi {
            return Loc.t("Schon belegt")
        }
        let maske = NSEvent.ModifierFlags([.command, .option, .control, .shift]).rawValue
        if !dictationKey.isModifierOnly, dictationKey.keyCode == kombi.keyCode,
           dictationKey.modifiers & maske == kombi.modifiers {
            return Loc.t("Schon belegt")
        }
        return nil
    }
}
```

`Sources/FlowLokal/GlobalHotkey.swift`:

```swift
import AppKit
import Carbon.HIToolbox

/// Eine globale Taste über Carbon (`RegisterEventHotKey`). Anders als ein
/// `NSEvent`-Monitor fängt sie die Taste ab — in der App darunter landet kein
/// Zeichen — und braucht keine Bedienungshilfen-Berechtigung. Drücken und
/// Loslassen kommen beide, damit ist Halten erkennbar.
@MainActor
final class GlobalHotkey {

    enum RegistrationError: Error, Equatable {
        /// Eine andere App hat die Kombination schon.
        case taken
        case failed(OSStatus)
    }

    var onPress: () -> Void = {}
    var onRelease: () -> Void = {}

    private let kennung: UInt32
    private var ref: EventHotKeyRef?

    private static var naechsteKennung: UInt32 = 1
    private static var registriert: [UInt32: GlobalHotkey] = [:]
    private static var handlerInstalliert = false
    /// „shou“
    private static let signatur = OSType(0x7368_6F75)

    init() {
        kennung = Self.naechsteKennung
        Self.naechsteKennung += 1
    }

    func register(_ kombi: HotkeyCombo) throws {
        unregister()
        Self.installiereHandler()
        var neu: EventHotKeyRef?
        let status = RegisterEventHotKey(UInt32(kombi.keyCode), kombi.carbonModifiers,
                                         EventHotKeyID(signature: Self.signatur, id: kennung),
                                         GetApplicationEventTarget(), 0, &neu)
        if status == OSStatus(eventHotKeyExistsErr) { throw RegistrationError.taken }
        guard status == noErr, let neu else { throw RegistrationError.failed(status) }
        ref = neu
        Self.registriert[kennung] = self
    }

    func unregister() {
        if let ref { UnregisterEventHotKey(ref) }
        ref = nil
        Self.registriert[kennung] = nil
    }

    private static func installiereHandler() {
        guard !handlerInstalliert else { return }
        var typen = [
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased)),
        ]
        let status = InstallEventHandler(GetApplicationEventTarget(), { _, ereignis, _ in
            guard let ereignis else { return OSStatus(eventNotHandledErr) }
            var id = EventHotKeyID()
            GetEventParameter(ereignis, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                              nil, MemoryLayout<EventHotKeyID>.size, nil, &id)
            let gedrueckt = GetEventKind(ereignis) == UInt32(kEventHotKeyPressed)
            // Carbon liefert auf dem Hauptstrang.
            MainActor.assumeIsolated {
                guard let taste = GlobalHotkey.registriert[id.id] else { return }
                if gedrueckt { taste.onPress() } else { taste.onRelease() }
            }
            return noErr
        }, typen.count, &typen, nil, nil)
        handlerInstalliert = status == noErr
    }
}
```

- [ ] **Schritt 4: Tests laufen lassen**

Testbefehl mit `-only-testing:ShoutTests/HotkeyTests`. Erwartet: 12 Tests, 0 Fehler.
Dann der Kompilierlauf der App (`GlobalHotkey` wird noch nicht benutzt, muss aber bauen).

- [ ] **Schritt 5: Commit**

```bash
cd /Users/liam/Developer/LIAM/flow-lokal && git add project.yml Sources/FlowLokal/HotkeyCombo.swift Sources/FlowLokal/HotkeyPressClassifier.swift Sources/FlowLokal/DictationTarget.swift Sources/FlowLokal/ScratchpadSettings.swift Sources/FlowLokal/GlobalHotkey.swift Tests/ShoutTests/HotkeyTests.swift && git commit -m "Scratchpad: globale Tasten über Carbon, Tippen oder Halten, Diktat-Ziel, Einstellungen" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---
### Aufgabe 9: Das Panel — Fenster, Controller, Ansicht

**Dateien:**
- Neu: `Sources/FlowLokal/PanelPlacement.swift`, `Sources/FlowLokal/ScratchpadPanel.swift`, `Sources/FlowLokal/ScratchpadView.swift`
- Neu: `Tests/ShoutTests/PanelPlacementTests.swift`
- Ändern: `project.yml` (nach `- path: Sources/FlowLokal/GlobalHotkey.swift`: nur `PanelPlacement.swift`)

**Schnittstellen:**
- Benutzt: `ScratchpadModel`, `ScratchpadSettings.openBehavior`, `NoteEditorView`, `NoteNoticesView`, `HidesOnEscape`, `NoteStore`, `Color.shoutWindow`, `Color.shoutLive`
- Liefert:
  - `enum PanelPlacement { struct Saved: Codable, Equatable; static func save(_:in:screen:) -> Saved; static func restore(_:in:minSize:) -> CGRect; static func initial(in:size:margin:) -> CGRect }`
  - `@MainActor final class ScratchpadMicState: ObservableObject { @Published var isRecording }`
  - `final class ScratchpadPanel: NSPanel, HidesOnEscape { var onHide: (() -> Void)? }`
  - `@MainActor final class ScratchpadPanelController: NSObject, NSWindowDelegate { init(model:settings:mic:defaults:onMic:); var isVisible; var isKey; func show(focus:); func hide(); func toggle() }`
  - `struct ScratchpadView: View { init(model:store:mic:onMic:) }`

- [ ] **Schritt 1: Den fehlschlagenden Test schreiben**

`Tests/ShoutTests/PanelPlacementTests.swift`:

```swift
import XCTest

/// Der Panel-Rahmen als Anteil der sichtbaren Fläche: Er übersteht das Umstecken
/// auf einen anderen Bildschirm und bleibt immer ganz sichtbar.
final class PanelPlacementTests: XCTestCase {

    private let gross = CGRect(x: 0, y: 0, width: 1000, height: 800)
    private let minimum = CGSize(width: 360, height: 260)

    func testRundlaufAufDemselbenBildschirm() {
        let rahmen = CGRect(x: 400, y: 300, width: 500, height: 400)
        let gesichert = PanelPlacement.save(rahmen, in: gross, screen: "1")
        XCTAssertEqual(PanelPlacement.restore(gesichert, in: gross, minSize: minimum), rahmen)
        XCTAssertEqual(gesichert.screen, "1")
    }

    func testKleinererBildschirmBleibtSichtbarUndMindestgross() {
        let gesichert = PanelPlacement.save(CGRect(x: 400, y: 300, width: 500, height: 400), in: gross, screen: nil)
        let klein = CGRect(x: 0, y: 0, width: 500, height: 400)
        XCTAssertEqual(PanelPlacement.restore(gesichert, in: klein, minSize: minimum),
                       CGRect(x: 140, y: 140, width: 360, height: 260))
    }

    func testVersetzterBildschirm() {
        let rechts = CGRect(x: 1000, y: 100, width: 1000, height: 800)
        let rahmen = CGRect(x: 1500, y: 500, width: 400, height: 300)
        let gesichert = PanelPlacement.save(rahmen, in: rechts, screen: nil)
        XCTAssertEqual(PanelPlacement.restore(gesichert, in: rechts, minSize: minimum), rahmen)
    }

    func testErsterStartObenRechts() {
        XCTAssertEqual(PanelPlacement.initial(in: gross, size: CGSize(width: 520, height: 420)),
                       CGRect(x: 464, y: 364, width: 520, height: 420))
    }
}
```

- [ ] **Schritt 2: Eintragen und Test laufen lassen**

In `project.yml` nach `      - path: Sources/FlowLokal/GlobalHotkey.swift`:

```yaml
      - path: Sources/FlowLokal/PanelPlacement.swift
```

```bash
cd /Users/liam/Developer/LIAM/flow-lokal && touch Sources/FlowLokal/PanelPlacement.swift && xcodegen generate
```

Testbefehl mit `-only-testing:ShoutTests/PanelPlacementTests`.
Erwartet: Build-Fehler „cannot find 'PanelPlacement' in scope“.

- [ ] **Schritt 3: `PanelPlacement` schreiben**

`Sources/FlowLokal/PanelPlacement.swift`:

```swift
import CoreGraphics

/// Wo das Panel steht — als Anteil der sichtbaren Bildschirmfläche plus
/// Bildschirm-Kennung, wie bei der Pille. So übersteht es das Abstecken eines
/// großen Bildschirms und bleibt immer ganz sichtbar.
enum PanelPlacement {

    struct Saved: Codable, Equatable {
        var x: Double
        var y: Double
        var width: Double
        var height: Double
        var screen: String?
    }

    static func save(_ rahmen: CGRect, in sichtbar: CGRect, screen: String?) -> Saved {
        Saved(x: (rahmen.minX - sichtbar.minX) / sichtbar.width,
              y: (rahmen.minY - sichtbar.minY) / sichtbar.height,
              width: rahmen.width / sichtbar.width,
              height: rahmen.height / sichtbar.height,
              screen: screen)
    }

    /// Größe zwischen `minSize` und der sichtbaren Fläche, Lage ganz darin.
    static func restore(_ gesichert: Saved, in sichtbar: CGRect, minSize: CGSize) -> CGRect {
        let breite = min(max(gesichert.width * sichtbar.width, minSize.width), sichtbar.width)
        let hoehe = min(max(gesichert.height * sichtbar.height, minSize.height), sichtbar.height)
        let x = min(max(sichtbar.minX + gesichert.x * sichtbar.width, sichtbar.minX), sichtbar.maxX - breite)
        let y = min(max(sichtbar.minY + gesichert.y * sichtbar.height, sichtbar.minY), sichtbar.maxY - hoehe)
        return CGRect(x: x, y: y, width: breite, height: hoehe)
    }

    /// Erster Start: oben rechts mit etwas Abstand zum Rand.
    static func initial(in sichtbar: CGRect, size: CGSize, margin: CGFloat = 16) -> CGRect {
        let breite = min(size.width, sichtbar.width)
        let hoehe = min(size.height, sichtbar.height)
        return CGRect(x: max(sichtbar.maxX - breite - margin, sichtbar.minX),
                      y: max(sichtbar.maxY - hoehe - margin, sichtbar.minY),
                      width: breite, height: hoehe)
    }
}
```

Testbefehl mit `-only-testing:ShoutTests/PanelPlacementTests`. Erwartet: 4 Tests, 0 Fehler.

- [ ] **Schritt 4: Fenster und Controller**

`Sources/FlowLokal/ScratchpadPanel.swift`:

```swift
import AppKit
import SwiftUI

/// Ob gerade ins Panel diktiert wird — für den Mikrofon-Knopf.
@MainActor
final class ScratchpadMicState: ObservableObject {
    @Published var isRecording = false
}

/// Das schwebende Fenster. Nicht aktivierend: Es nimmt der App davor den Fokus
/// nicht; erst ein Klick in den Text macht es zum Key-Fenster — ohne dass
/// shout. aktiv wird (kein Dock-Symbol, „vorige App“ bleibt die App davor).
final class ScratchpadPanel: NSPanel, HidesOnEscape {
    var onHide: (() -> Void)?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    override func cancelOperation(_ sender: Any?) { onHide?() }
    func hideOnEscape() { onHide?() }
}

/// Ein- und Ausblenden, Rahmen merken. Beim Ausblenden wird gesichert.
@MainActor
final class ScratchpadPanelController: NSObject, NSWindowDelegate {

    static let minSize = CGSize(width: 360, height: 260)
    static let defaultSize = CGSize(width: 520, height: 420)
    private static let rahmenKey = "scratchpad.frame"

    private let model: ScratchpadModel
    private let settings: ScratchpadSettings
    private let mic: ScratchpadMicState
    private let defaults: UserDefaults
    private let onMic: () -> Void
    private var panel: ScratchpadPanel?

    init(model: ScratchpadModel, settings: ScratchpadSettings, mic: ScratchpadMicState,
         defaults: UserDefaults = .standard, onMic: @escaping () -> Void) {
        self.model = model
        self.settings = settings
        self.mic = mic
        self.defaults = defaults
        self.onMic = onMic
    }

    var isVisible: Bool { panel?.isVisible == true }
    /// Hat das Panel den Tastatur-Fokus? Dann schreibt die Diktiertaste hinein.
    var isKey: Bool { panel?.isKeyWindow == true }

    func toggle() {
        if isVisible { hide() } else { show(focus: false) }
    }

    /// Blendet ein, ohne den Fokus zu nehmen — außer `focus` (Klick auf den Toast).
    func show(focus: Bool) {
        let fenster = panel ?? baue()
        if !fenster.isVisible {
            model.prepareForShowing(behavior: settings.openBehavior)
            fenster.setFrame(gespeicherterRahmen(), display: false)
            fenster.orderFrontRegardless()
        }
        if focus { fenster.makeKey() }
    }

    func hide() {
        guard let fenster = panel, fenster.isVisible else { return }
        model.flushAll()
        merke(fenster)
        fenster.orderOut(nil)
    }

    // MARK: NSWindowDelegate

    /// Der Schließen-Knopf blendet aus (das Fenster bleibt bestehen).
    func windowWillClose(_ notification: Notification) {
        model.flushAll()
        if let fenster = panel { merke(fenster) }
    }

    func windowDidMove(_ notification: Notification) {
        if let fenster = panel { merke(fenster) }
    }

    func windowDidEndLiveResize(_ notification: Notification) {
        if let fenster = panel { merke(fenster) }
    }

    // MARK: Intern

    private func baue() -> ScratchpadPanel {
        let fenster = ScratchpadPanel(
            contentRect: NSRect(origin: .zero, size: Self.defaultSize),
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered, defer: false)
        fenster.titlebarAppearsTransparent = true
        fenster.titleVisibility = .hidden
        fenster.isFloatingPanel = true
        fenster.level = .floating
        fenster.hidesOnDeactivate = false
        fenster.becomesKeyOnlyIfNeeded = true
        fenster.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        fenster.minSize = NSSize(width: Self.minSize.width, height: Self.minSize.height)
        fenster.isReleasedWhenClosed = false
        fenster.appearance = NSAppearance(named: .darkAqua)
        fenster.backgroundColor = NSColor(Color.shoutWindow)
        fenster.delegate = self
        fenster.onHide = { [weak self] in self?.hide() }
        fenster.contentView = NSHostingView(rootView: ScratchpadView(model: model, store: model.store, mic: mic, onMic: onMic))
        panel = fenster
        return fenster
    }

    private static func kennung(_ bildschirm: NSScreen) -> String? {
        (bildschirm.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.stringValue
    }

    private func gesichert() -> PanelPlacement.Saved? {
        defaults.data(forKey: Self.rahmenKey).flatMap { try? JSONDecoder().decode(PanelPlacement.Saved.self, from: $0) }
    }

    /// Der gemerkte Bildschirm, sonst der mit dem Mauszeiger, sonst der Hauptbildschirm.
    private func bildschirm(fuer gemerkt: PanelPlacement.Saved?) -> NSScreen? {
        if let kennung = gemerkt?.screen,
           let treffer = NSScreen.screens.first(where: { Self.kennung($0) == kennung }) {
            return treffer
        }
        let maus = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(maus, $0.frame, false) } ?? NSScreen.main
    }

    private func gespeicherterRahmen() -> NSRect {
        let gemerkt = gesichert()
        guard let sichtbar = bildschirm(fuer: gemerkt)?.visibleFrame else {
            return NSRect(origin: .zero, size: Self.defaultSize)
        }
        if let gemerkt { return PanelPlacement.restore(gemerkt, in: sichtbar, minSize: Self.minSize) }
        return PanelPlacement.initial(in: sichtbar, size: Self.defaultSize)
    }

    private func merke(_ fenster: NSWindow) {
        guard let bildschirm = fenster.screen ?? NSScreen.main else { return }
        let stand = PanelPlacement.save(fenster.frame, in: bildschirm.visibleFrame, screen: Self.kennung(bildschirm))
        if let daten = try? JSONEncoder().encode(stand) { defaults.set(daten, forKey: Self.rahmenKey) }
    }
}
```

- [ ] **Schritt 5: Die Ansicht**

`Sources/FlowLokal/ScratchpadView.swift`:

```swift
import SwiftUI
import AppKit

/// Inhalt des Panels: Tabs oben, optional die Liste links, der Editor, unten
/// Mikrofon und Anheften. Die Tastenkürzel wirken, sobald das Panel den Fokus hat.
struct ScratchpadView: View {
    @ObservedObject var model: ScratchpadModel
    @ObservedObject var store: NoteStore
    @ObservedObject var mic: ScratchpadMicState
    let onMic: () -> Void

    @FocusState private var searchFocused: Bool
    /// Fokus-Anstoß je Tab: Wird ein Tab vorne, bekommt sein Editor den Fokus —
    /// sonst tippte man unsichtbar in den vorigen.
    @State private var fokus: [UUID: Int] = [:]

    var body: some View {
        VStack(spacing: 0) {
            tabBar
            Rectangle().fill(Color.white.opacity(0.06)).frame(height: 1)
            HStack(spacing: 0) {
                if model.showsList {
                    list.frame(width: 200)
                    Rectangle().fill(Color.white.opacity(0.06)).frame(width: 1)
                }
                editors.frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            Rectangle().fill(Color.white.opacity(0.06)).frame(height: 1)
            footer
        }
        .background(Color.shoutWindow)
        .background(shortcuts)
        .preferredColorScheme(.dark)
        .onChange(of: model.active?.id) { _, id in
            if let id { fokus[id, default: 0] += 1 }
        }
    }

    // MARK: Tabs

    private var tabBar: some View {
        HStack(spacing: 4) {
            ForEach(Array(model.tabs.enumerated()), id: \.element.id) { index, tab in
                TabChip(session: tab, active: index == model.activeIndex,
                        onSelect: { model.select(index) }, onClose: { model.close(index) })
            }
            Button { model.newTab() } label: { Image(systemName: "plus") }
                .buttonStyle(.borderless).foregroundStyle(Color(white: 0.6))
                .help(Loc.t("Neuer Tab"))
            Spacer(minLength: 0)
            Button { model.showsList.toggle() } label: { Image(systemName: "sidebar.left") }
                .buttonStyle(.borderless).foregroundStyle(Color(white: 0.6))
                .help(Loc.t("Liste ein/aus"))
        }
        // Platz für die Fensterknöpfe (Titelleiste liegt über dem Inhalt).
        .padding(.leading, 78).padding(.trailing, 10).padding(.vertical, 8)
    }

    // MARK: Liste

    private var list: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").font(.system(size: 10)).foregroundStyle(Color(white: 0.45))
                TextField(Loc.t("Notizen durchsuchen"), text: $model.query)
                    .textFieldStyle(.plain).font(.system(size: 12))
                    .focused($searchFocused)
            }
            .padding(.horizontal, 8).padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 7).fill(Color(white: 0.10)))
            .padding(8)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 1) {
                    ForEach(model.results) { ergebnis in row(ergebnis.note) }
                }
                .padding(.horizontal, 6).padding(.bottom, 6)
            }
        }
    }

    private func row(_ note: Note) -> some View {
        let vorne = model.active?.id == note.id
        return Button {
            // ⌘-Klick: in einem neuen Tab.
            model.open(note.id, inNewTab: NSEvent.modifierFlags.contains(.command))
        } label: {
            HStack(spacing: 5) {
                if note.pinned {
                    Image(systemName: "pin.fill").font(.system(size: 8)).foregroundStyle(Color.shoutLive)
                }
                Text(note.title).font(.system(size: 12)).lineLimit(1)
                Spacer(minLength: 0)
            }
            .foregroundStyle(vorne ? Color.white : Color(white: 0.7))
            .padding(.horizontal, 10).padding(.vertical, 5)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 6).fill(vorne ? Color.shoutLive.opacity(0.14) : Color.clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: Editoren

    /// Jeder Tab behält seinen Editor (und damit sein Rückgängig); sichtbar und
    /// klickbar ist nur der vordere.
    @ViewBuilder private var editors: some View {
        if model.tabs.isEmpty {
            VStack(spacing: 8) {
                Image(systemName: "note.text").font(.system(size: 28, weight: .light)).foregroundStyle(Color(white: 0.4))
                Text(Loc.t("Noch keine Notiz offen. ⌘N legt eine neue an."))
                    .font(.system(size: 12)).foregroundStyle(Color(white: 0.6))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ZStack {
                ForEach(model.tabs, id: \.id) { tab in
                    let vorne = tab === model.active
                    VStack(spacing: 0) {
                        NoteNoticesView(session: tab, onDiscard: { model.discard(tab) })
                        NoteEditorView(session: tab, focusRequest: fokus[tab.id] ?? 0)
                            .id(ObjectIdentifier(tab))
                    }
                    .opacity(vorne ? 1 : 0)
                    .allowsHitTesting(vorne)
                    .accessibilityHidden(!vorne)
                }
            }
        }
    }

    // MARK: Fußleiste

    private var footer: some View {
        HStack(spacing: 12) {
            Button(action: onMic) {
                Image(systemName: mic.isRecording ? "mic.fill" : "mic")
                    .font(.system(size: 13))
                    .foregroundStyle(mic.isRecording ? Color.shoutLive : Color(white: 0.7))
                    .symbolEffect(.pulse, isActive: mic.isRecording)
            }
            .buttonStyle(.borderless)
            .help(mic.isRecording ? Loc.t("Diktat beenden") : Loc.t("In diese Notiz diktieren"))
            if let vorne = model.active { PinButton(session: vorne) }
            Spacer()
        }
        .padding(.horizontal, 12).padding(.vertical, 7)
    }

    // MARK: Tastenkürzel

    /// Unsichtbare Knöpfe tragen die Kürzel; sie wirken, sobald das Panel Key-Fenster ist.
    private var shortcuts: some View {
        ZStack {
            Button("") { model.newTab() }.keyboardShortcut("n", modifiers: .command)
            Button("") { if let i = model.activeIndex { model.close(i) } }.keyboardShortcut("w", modifiers: .command)
            ForEach(0..<ScratchpadModel.maxTabs, id: \.self) { i in
                Button("") { model.select(i) }.keyboardShortcut(KeyEquivalent(Character("\(i + 1)")), modifiers: .command)
            }
            Button("") { model.selectNext(-1) }.keyboardShortcut("[", modifiers: [.command, .shift])
            Button("") { model.selectNext(1) }.keyboardShortcut("]", modifiers: [.command, .shift])
            Button("") { model.showsList.toggle() }.keyboardShortcut("l", modifiers: [.command, .shift])
            Button("") {
                model.showsList = true
                searchFocused = true
            }
            .keyboardShortcut("f", modifiers: [.command, .shift])
        }
        .opacity(0)
        .frame(width: 0, height: 0)
        .accessibilityHidden(true)
    }
}

/// Ein Tab-Reiter. Eigene View, damit er seine Sitzung beobachtet — der Titel
/// ändert sich beim ersten Sichern, der Punkt zeigt Ungesichertes.
private struct TabChip: View {
    @ObservedObject var session: NoteEditorSession
    let active: Bool
    let onSelect: () -> Void
    let onClose: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Text(session.note.isNew ? Loc.t("Neue Notiz") : session.note.title)
                .font(.system(size: 12, weight: active ? .semibold : .regular))
                .lineLimit(1)
                .frame(maxWidth: 120)
            if session.hasUnsavedText {
                Circle().fill(Color.shoutLive).frame(width: 5, height: 5)
            }
            Button(action: onClose) { Image(systemName: "xmark").font(.system(size: 8, weight: .bold)) }
                .buttonStyle(.borderless)
                .help(Loc.t("Tab schließen"))
        }
        .foregroundStyle(active ? Color.white : Color(white: 0.6))
        .padding(.horizontal, 10).padding(.vertical, 5)
        .background(RoundedRectangle(cornerRadius: 7).fill(active ? Color.shoutLive.opacity(0.18) : Color.white.opacity(0.04)))
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
    }
}

/// Anheften der vorderen Notiz — über die Sitzung, damit ungesicherter Text mitkommt.
private struct PinButton: View {
    @ObservedObject var session: NoteEditorSession

    var body: some View {
        Button { session.setPinned(!session.note.pinned) } label: {
            Image(systemName: session.note.pinned ? "pin.fill" : "pin").font(.system(size: 12))
        }
        .buttonStyle(.borderless)
        .foregroundStyle(session.note.pinned ? Color.shoutLive : Color(white: 0.7))
        .help(session.note.pinned ? Loc.t("Lösen") : Loc.t("Anheften"))
    }
}
```

- [ ] **Schritt 6: Projekt erzeugen und kompilieren**

```bash
cd /Users/liam/Developer/LIAM/flow-lokal && xcodegen generate
```

Dann den Kompilierlauf der App. Erwartet: `** BUILD SUCCEEDED **`. Das Panel ist
noch nicht erreichbar — das verdrahtet Aufgabe 10. Die neuen Texte bekommen
ihre englischen Einträge in Aufgabe 11.

- [ ] **Schritt 7: Commit**

```bash
cd /Users/liam/Developer/LIAM/flow-lokal && git add project.yml Sources/FlowLokal/PanelPlacement.swift Sources/FlowLokal/ScratchpadPanel.swift Sources/FlowLokal/ScratchpadView.swift Tests/ShoutTests/PanelPlacementTests.swift && git commit -m "Scratchpad: schwebendes Panel mit Tabs, Liste, Editoren und Tastenkürzeln" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Aufgabe 10: Verdrahtung im AppDelegate

**Dateien:**
- Ändern: `Sources/FlowLokal/AppDelegate.swift`, `Sources/FlowLokal/LearnedToast.swift`

**Schnittstellen:**
- Benutzt: alles aus den Aufgaben 4–9
- Liefert: `LearnedToast.showInfo(_ message: String, actionTitle: String? = nil, action: (() -> Void)? = nil)`;
  im AppDelegate `func beginScratchpadCapture(_ rolle: ScratchpadSettings.Role)` (für Aufgabe 11),
  `scratchpadSettings` (für Aufgabe 11).

- [ ] **Schritt 1: Hinweis-Toast**

`Sources/FlowLokal/LearnedToast.swift` ganz ersetzen:

```swift
import AppKit
import SwiftUI

/// Kleines, kurz eingeblendetes Panel oben rechts: „Gelernt: falsch → richtig"
/// mit Rückgängig, oder ein schlichter Hinweis mit einer Aktion. Verschwindet
/// nach ein paar Sekunden von selbst.
@MainActor
final class LearnedToast {

    private var panel: NSPanel?
    private var dismissTimer: Timer?

    func show(wrong: String, right: String, onUndo: @escaping () -> Void) {
        dismiss()
        present(NSHostingView(rootView: LearnedToastView(
            wrong: wrong,
            right: right,
            onUndo: { [weak self] in onUndo(); self?.dismiss() }
        )))
    }

    /// Ein Hinweis (z. B. „Im Eingang notiert“), optional mit einem Knopf.
    func showInfo(_ message: String, actionTitle: String? = nil, action: (() -> Void)? = nil) {
        dismiss()
        present(NSHostingView(rootView: InfoToastView(
            message: message,
            actionTitle: actionTitle,
            onAction: { [weak self] in action?(); self?.dismiss() }
        )))
    }

    func dismiss() {
        dismissTimer?.invalidate()
        dismissTimer = nil
        panel?.orderOut(nil)
        panel = nil
    }

    private func present<V: View>(_ hosting: NSHostingView<V>) {
        let size = hosting.fittingSize
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered, defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.contentView = hosting

        if let screen = NSScreen.main {
            let vf = screen.visibleFrame
            panel.setFrameOrigin(NSPoint(x: vf.maxX - size.width - 16, y: vf.maxY - size.height - 16))
        }
        panel.orderFrontRegardless()
        self.panel = panel

        dismissTimer = Timer.scheduledTimer(withTimeInterval: 6, repeats: false) { [weak self] _ in
            Task { @MainActor in self?.dismiss() }
        }
    }
}

private struct LearnedToastView: View {
    let wrong: String
    let right: String
    let onUndo: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .font(.title3)
            VStack(alignment: .leading, spacing: 2) {
                Text(Loc.t("Ins Wörterbuch gelernt"))
                    .font(.caption).foregroundStyle(.secondary)
                Text("\(wrong)  →  \(right)")
                    .font(.callout).fontWeight(.semibold)
                    .lineLimit(1)
            }
            Button(Loc.t("Rückgängig"), action: onUndo)
                .buttonStyle(.borderless)
                .foregroundStyle(.blue)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: 360)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }
}

private struct InfoToastView: View {
    let message: String
    let actionTitle: String?
    let onAction: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "note.text")
                .foregroundStyle(Color.shoutLive)
                .font(.title3)
            Text(message)
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
            if let actionTitle {
                Button(actionTitle, action: onAction)
                    .buttonStyle(.borderless)
                    .foregroundStyle(.blue)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: 360)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }
}
```

Kompilierlauf: `** BUILD SUCCEEDED **` (der bestehende Aufruf `toast.show(wrong:right:onUndo:)` bleibt gleich).

- [ ] **Schritt 2: Eigenschaften und Aufbau**

In `Sources/FlowLokal/AppDelegate.swift` den Block um `notesPageStorage`
(von `private var notesPageStorage: NotesPageModel?` bis zum Ende der berechneten
Eigenschaft `notesPage`) ersetzen durch:

```swift
    // MARK: - Notizen und Scratchpad
    //
    // Alles entsteht erst beim ersten Zugriff. Der Ordner in „Dokumente“ entsteht
    // sogar erst mit der ersten gesicherten Notiz.

    private var notesStoreStorage: NoteStore?
    private var noteStore: NoteStore {
        if let store = notesStoreStorage { return store }
        let store = NoteStore(folder: NotesFolder.current())
        notesStoreStorage = store
        return store
    }

    /// Eine Sitzung pro Notiz — Seite und Panel teilen sie.
    private var noteRegistryStorage: NoteSessionRegistry?
    private var noteRegistry: NoteSessionRegistry {
        if let registry = noteRegistryStorage { return registry }
        let registry = NoteSessionRegistry(store: noteStore)
        noteRegistryStorage = registry
        return registry
    }

    private var notesPageStorage: NotesPageModel?
    private var notesPage: NotesPageModel {
        if let page = notesPageStorage { return page }
        let page = NotesPageModel(store: noteStore, registry: noteRegistry)
        page.onFolderChanged = { [weak self] in self?.scratchpadStorage?.resetTabs() }
        notesPageStorage = page
        return page
    }

    private var scratchpadStorage: ScratchpadModel?
    private var scratchpad: ScratchpadModel {
        if let model = scratchpadStorage { return model }
        let model = ScratchpadModel(store: noteStore, registry: noteRegistry)
        scratchpadStorage = model
        return model
    }

    private var scratchpadPanelStorage: ScratchpadPanelController?
    private var scratchpadPanel: ScratchpadPanelController {
        if let controller = scratchpadPanelStorage { return controller }
        let controller = ScratchpadPanelController(model: scratchpad, settings: scratchpadSettings, mic: scratchpadMic,
                                                   onMic: { [weak self] in self?.toggleScratchpadMic() })
        scratchpadPanelStorage = controller
        return controller
    }

    let scratchpadSettings = ScratchpadSettings()
    private let scratchpadMic = ScratchpadMicState()
    private let scratchpadKey = GlobalHotkey()
    private let inboxKey = GlobalHotkey()
    private var scratchpadPress = HotkeyPressClassifier()
    private var scratchpadHoldTimer: Timer?
    private var scratchpadMenuItem: NSMenuItem?
    /// Wohin das laufende Diktat geht — festgelegt beim Start der Aufnahme.
    private var dictationTarget: DictationTarget = .frontApp(bundleID: nil)
```

In `applicationDidFinishLaunching(_:)` direkt nach `installHotkeyMonitors()`:

```swift
        setupScratchpad()
```

- [ ] **Schritt 3: Tasten**

Neue Methoden (z. B. unter dem Abschnitt `// MARK: - Hotkey aufnehmen (aus den Einstellungen)`):

```swift
    // MARK: - Scratchpad-Tasten

    private func setupScratchpad() {
        scratchpadKey.onPress = { [weak self] in self?.scratchpadKeyDown() }
        scratchpadKey.onRelease = { [weak self] in self?.scratchpadKeyUp() }
        inboxKey.onPress = { [weak self] in self?.inboxKeyDown() }
        inboxKey.onRelease = { [weak self] in self?.inboxKeyUp() }
        scratchpadSettings.onChange = { [weak self] in self?.applyScratchpadHotkeys() }
        applyScratchpadHotkeys()
    }

    /// Meldet beide Tasten neu an. Während eine aufgenommen wird, bleiben sie
    /// abgemeldet — sonst finge Carbon die alte Kombination ab.
    private func applyScratchpadHotkeys() {
        scratchpadKey.unregister()
        inboxKey.unregister()
        var probleme: [ScratchpadSettings.Role: String] = [:]
        if scratchpadSettings.isEnabled, scratchpadSettings.capturing == nil {
            for (rolle, taste) in [(ScratchpadSettings.Role.scratchpad, scratchpadKey), (.inbox, inboxKey)] {
                guard let kombi = scratchpadSettings.combo(for: rolle) else { continue }
                do {
                    try taste.register(kombi)
                } catch {
                    probleme[rolle] = Loc.t("Von einer anderen App belegt")
                }
            }
        }
        if !scratchpadSettings.isEnabled { scratchpadPanelStorage?.hide() }
        scratchpadSettings.registrationProblems = probleme
        updateScratchpadMenuItem()
    }

    private func scratchpadKeyDown() {
        scratchpadPress.press(at: ProcessInfo.processInfo.systemUptime)
        scratchpadHoldTimer?.invalidate()
        scratchpadHoldTimer = Timer.scheduledTimer(withTimeInterval: HotkeyPressClassifier.holdThreshold,
                                                   repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                if self.scratchpadPress.tick(at: ProcessInfo.processInfo.systemUptime) == .holdBegan {
                    self.beginScratchpadDictation()
                }
            }
        }
    }

    private func scratchpadKeyUp() {
        scratchpadHoldTimer?.invalidate()
        scratchpadHoldTimer = nil
        switch scratchpadPress.release(at: ProcessInfo.processInfo.systemUptime) {
        case .tap:
            scratchpadPanel.toggle()
        case .holdEnded:
            if state == .recording, case .scratchpad = dictationTarget { stopAndProcess() }
        case .holdBegan, nil:
            break
        }
    }

    /// Halten der Scratchpad-Taste: Panel auf, Diktat in den vorderen Tab — oder
    /// in einen neuen, wenn der vordere schon Text hat.
    private func beginScratchpadDictation() {
        guard state == .idle else { return }
        scratchpadPanel.show(focus: false)
        guard let tab = scratchpad.tabForDictation(newIfActiveHasText: true) else { return }
        startRecording(target: .scratchpad(noteID: tab.id))
    }

    /// Mikrofon-Knopf im Panel: in den vorderen Tab diktieren bzw. das Diktat beenden.
    private func toggleScratchpadMic() {
        if state == .recording, case .scratchpad = dictationTarget {
            stopAndProcess()
            return
        }
        guard state == .idle, let tab = scratchpad.tabForDictation(newIfActiveHasText: false) else { return }
        startRecording(target: .scratchpad(noteID: tab.id))
    }

    /// Eingangs-Taste: folgt dem Modus der Diktiertaste. Doppeltipp gibt es für
    /// Carbon-Tasten nicht; dort gilt wie bei „Umschalten“: Tippen startet, erneutes Tippen stoppt.
    private func inboxKeyDown() {
        switch settings.mode {
        case .hold:
            if state == .idle { startRecording(target: .inbox) }
        case .toggle, .doubleTap:
            if state == .idle {
                startRecording(target: .inbox)
            } else if state == .recording, dictationTarget == .inbox {
                stopAndProcess()
            }
        }
    }

    private func inboxKeyUp() {
        guard settings.mode == .hold, state == .recording, dictationTarget == .inbox else { return }
        stopAndProcess()
    }

    // MARK: - Scratchpad-Tasten aufnehmen (aus den Einstellungen)

    func beginScratchpadCapture(_ rolle: ScratchpadSettings.Role) {
        scratchpadSettings.capturing = rolle
        scratchpadSettings.captureHint = nil
        applyScratchpadHotkeys()
    }

    private func endScratchpadCapture() {
        scratchpadSettings.capturing = nil
        scratchpadSettings.captureHint = nil
        applyScratchpadHotkeys()
    }

    private func captureScratchpadKey(_ event: NSEvent, rolle: ScratchpadSettings.Role) {
        let mods = event.modifierFlags.intersection([.command, .option, .control, .shift])
        if event.keyCode == 53, mods.isEmpty {    // Esc bricht ab
            endScratchpadCapture()
            return
        }
        let kombi = HotkeyCombo(keyCode: event.keyCode, flags: mods)
        let diktat = (keyCode: settings.keyCode, modifiers: settings.modifiers, isModifierOnly: settings.isModifierOnly)
        if let grund = scratchpadSettings.rejection(for: kombi, role: rolle, dictationKey: diktat) {
            scratchpadSettings.captureHint = grund
            return
        }
        scratchpadSettings.capturing = nil
        scratchpadSettings.captureHint = nil
        scratchpadSettings.setCombo(kombi, for: rolle)     // meldet über onChange neu an
    }

    // MARK: - Menüeintrag

    @objc private func toggleScratchpadFromMenu() { scratchpadPanel.toggle() }

    private func updateScratchpadMenuItem() {
        guard let eintrag = scratchpadMenuItem else { return }
        eintrag.isHidden = !scratchpadSettings.isEnabled
        let name = scratchpadSettings.combo(for: .scratchpad).map { RecordingSettings.keyName(forKeyCode: $0.keyCode) } ?? ""
        if let kombi = scratchpadSettings.combo(for: .scratchpad), name.count == 1 {
            eintrag.keyEquivalent = name.lowercased()
            eintrag.keyEquivalentModifierMask = kombi.flags
        } else {
            eintrag.keyEquivalent = ""
        }
    }
```

In `handleKeyDown(_:)` direkt nach `guard !event.isARepeat else { return }` einfügen:

```swift
        if let rolle = scratchpadSettings.capturing {
            captureScratchpadKey(event, rolle: rolle)
            return
        }
```

In `isReservedCombo(keyCode:mods:)` vor `return false` einfügen:

```swift
        let echte = mods.intersection([.command, .option, .control, .shift])
        for rolle in ScratchpadSettings.Role.allCases {
            if let kombi = scratchpadSettings.combo(for: rolle), kombi.keyCode == keyCode, kombi.flags == echte {
                return true
            }
        }
```

In `buildStatusMenu()` direkt nach `menu.addItem(pasteLastItem)`:

```swift
        let padItem = NSMenuItem(title: Loc.t("Scratchpad"), action: #selector(toggleScratchpadFromMenu), keyEquivalent: "")
        padItem.target = self
        menu.addItem(padItem)
        scratchpadMenuItem = padItem
        updateScratchpadMenuItem()
```

- [ ] **Schritt 4: Ziel festlegen und zustellen**

`startRecording()` bekommt einen Parameter. Kopf und erste Zeilen ersetzen:

```swift
    private func startRecording(target explizit: DictationTarget? = nil) {
        disarmPill()
        // Ziel-App merken, solange sie noch im Vordergrund ist. Das Panel ist
        // nicht aktivierend — hat es den Fokus, ist die App davor trotzdem vorne.
        let vorne = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        targetBundleID = vorne
        dictationTarget = explizit ?? DictationTarget.forDictationKey(
            panelIsKey: scratchpadPanelStorage?.isKey == true,
            activeNote: scratchpadStorage?.active?.id,
            frontBundleID: vorne)
```

(Die bisherige Zeile `targetBundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier`
entfällt dadurch.) Im `do`-Block nach `recIndicator.show()` einfügen:

```swift
            if case .scratchpad = dictationTarget { scratchpadMic.isRecording = true }
```

In `cancelRecording()` und am Anfang von `stopAndProcess()` jeweils ergänzen:

```swift
        scratchpadMic.isRecording = false
```

In `stopAndProcess()`:
- `let bundleID = targetBundleID` ersetzen durch

```swift
        let ziel = dictationTarget
        // Notizen bekommen den neutralen Ton der Aufbereitung.
        let bundleID = ziel.formatterBundleID
```

- Im `do`-Block alles **ab** dem Kommentar `// Ohne Bedienungshilfen-Freigabe kommt das synthetische ⌘V`
  **bis zum Ende** des `correctionWatcher`-Blocks (die schließende Klammer von
  `if UserDefaults.standard.object(forKey: "autoLearnCorrections") …`) ersetzen durch:

```swift
                deliver(final, raw: raw, to: ziel, seconds: Double(samples.count) / 16_000.0)
```

Neue Methode (neben `stopAndProcess`):

```swift
    /// Bringt ein fertiges Diktat an sein Ziel. Verlauf und Statistik zählen jedes.
    private func deliver(_ final: String, raw: String, to ziel: DictationTarget, seconds: Double) {
        switch ziel {
        case .frontApp:
            // HIER: der bisherige Block aus stopAndProcess (siehe unten), wörtlich.
            break
        case .scratchpad(let id):
            if scratchpad.insertDictation(final, into: id) {
                sounds.play(.done)
            } else {
                injector.copyConcealed(final)
                sounds.play(.error)
                toast.showInfo(Loc.t("Die Notiz nimmt gerade nichts an. Der Text liegt in der Zwischenablage."))
            }
            recordDelivered(final, raw: raw, seconds: seconds)
        case .inbox:
            if scratchpad.appendToInbox(final) {
                sounds.play(.done)
                toast.showInfo(Loc.t("Im Eingang notiert"), actionTitle: Loc.t("Öffnen")) { [weak self] in
                    guard let self else { return }
                    self.scratchpadPanel.show(focus: true)
                    self.scratchpad.openInbox()
                }
            } else {
                injector.copyConcealed(final)
                sounds.play(.error)
                toast.showInfo(Loc.t("Der Eingang ist gerade nicht erreichbar. Der Text liegt in der Zwischenablage."))
            }
            recordDelivered(final, raw: raw, seconds: seconds)
        }
    }

    private func recordDelivered(_ final: String, raw: String, seconds: Double) {
        lastInsertedText = final
        history.add(final, raw: raw)
        let woerter = final.split(whereSeparator: { $0 == " " || $0 == "\n" || $0 == "\t" }).count
        stats.record(words: woerter, seconds: seconds)
    }
```

Im Fall `.frontApp` die Zeile `// HIER: …` und das `break` durch den Block
ersetzen, der in `stopAndProcess()` eben herausgenommen wurde — **wörtlich**,
mit genau zwei Anpassungen: `Double(samples.count) / 16_000.0` wird `seconds`,
und ein `return` darin bleibt ein `return` (es beendet jetzt `deliver`). Nichts
an AX-Prüfung, Einfügen, Ton, Verlauf, Statistik oder `correctionWatcher` ändert sich.

- [ ] **Schritt 5: Beenden mit allen Sitzungen**

In `applicationShouldTerminate(_:)` den Block `if let notes = notesPageStorage { … }`
ersetzen durch:

```swift
        if let registry = noteRegistryStorage {
            registry.flushAll()
            let rettung = StoreIO.directory().appendingPathComponent("Notizen-Rettung", isDirectory: true)
            let ergebnis = registry.writeRescueCopies(in: rettung)
            if !ergebnis.failed.isEmpty {
                let alert = NSAlert()
                alert.messageText = Loc.t("Eine Notiz konnte nicht gesichert werden.")
                alert.informativeText = Loc.t("Weder im Notizordner noch als Rettungskopie war Platz. Der Text geht beim Beenden verloren.")
                alert.addButton(withTitle: Loc.t("Text kopieren und beenden"))
                alert.addButton(withTitle: Loc.t("Abbrechen"))
                NSApp.setActivationPolicy(.regular)
                NSApp.activate(ignoringOtherApps: true)
                guard alert.runModal() == .alertFirstButtonReturn else { return .terminateCancel }
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(ergebnis.failed.map(\.note.body).joined(separator: "\n\n---\n\n"),
                                               forType: .string)
            }
        }
```

Den Kommentar darüber anpassen: „alle offenen Notizen (Seite und Panel)“. In
`applicationWillTerminate(_:)` die Zeile `notesPageStorage?.flush()` ersetzen durch:

```swift
        noteRegistryStorage?.flushAll()    // Seite und Panel, höchstens eine Sekunde alt
        scratchpadKey.unregister()
        inboxKey.unregister()
```

- [ ] **Schritt 6: Kompilieren und alle Tests**

Kompilierlauf (`** BUILD SUCCEEDED **`), dann die ganze Suite. Erwartet: 0 Fehler.

- [ ] **Schritt 7: Commit**

```bash
cd /Users/liam/Developer/LIAM/flow-lokal && git add Sources/FlowLokal/AppDelegate.swift Sources/FlowLokal/LearnedToast.swift && git commit -m "Scratchpad: Tasten, Diktat ins Panel und in den Eingang, Menüeintrag, Beenden für alle Notizen" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Aufgabe 11: Einstellungen, Hinweiskarte, Texte

**Dateien:**
- Ändern: `Sources/FlowLokal/NotesView.swift`, `Sources/FlowLokal/DashboardView.swift`, `Sources/FlowLokal/AppDelegate.swift` (`openDashboard`), `Sources/FlowLokal/Localization.swift`
- Ändern: `Tests/ShoutTests/LocalizationNotesTests.swift`

**Schnittstellen:**
- Benutzt: `ScratchpadSettings`, `AppDelegate.beginScratchpadCapture(_:)`, `ConsolePanel`, `FieldRow`, `ConsoleDivider`, `ConsoleSegmented`, `Keycap`, `ConsoleButtonStyle`
- Liefert: `NotesView(model:store:scratchpadSettings:onScratchpadCapture:)`; `DashboardView` bekommt
  `@ObservedObject var scratchpadSettings: ScratchpadSettings` und
  `var onScratchpadCapture: (ScratchpadSettings.Role) -> Void = { _ in }` (direkt nach `notes`).

- [ ] **Schritt 1: Die neuen Texte in den Test**

In `Tests/ShoutTests/LocalizationNotesTests.swift` die Liste `schluessel` um diese
Einträge ergänzen:

```swift
        "Eingang.md",
        "Neuer Tab",
        "Tab schließen",
        "Liste ein/aus",
        "Noch keine Notiz offen. ⌘N legt eine neue an.",
        "Diktat beenden",
        "In diese Notiz diktieren",
        "Die Notiz nimmt gerade nichts an. Der Text liegt in der Zwischenablage.",
        "Im Eingang notiert",
        "Der Eingang ist gerade nicht erreichbar. Der Text liegt in der Zwischenablage.",
        "Von einer anderen App belegt",
        "Mit ⌃ oder ⌥ kombinieren",
        "Schon belegt",
        "Scratchpad aktiv",
        "Schwebender Notizblock mit eigenen Tasten.",
        "Scratchpad-Taste",
        "Antippen blendet ein und aus, Halten diktiert hinein.",
        "Eingangs-Taste",
        "Diktiert in die Eingangs-Notiz, ohne ein Fenster zu öffnen.",
        "Beim Öffnen",
        "Letzte Notizen",
        "Angeheftete",
        "Drücke die Tastenkombination … (Esc bricht ab)",
        "Keine",
        "Neu: das Scratchpad",
        "%@ antippen blendet einen schwebenden Notizblock ein, halten diktiert hinein. %@ diktiert in die Eingangs-Notiz, ohne ein Fenster zu öffnen.",
        "Einstellungen",
        "Ändern",
        "Entfernen",
        "Verstanden",
        "Öffnen",
```

(„Scratchpad“ selbst ist auch englisch „Scratchpad“ und kann deshalb nicht in
diese Liste — der Test prüft, dass sich der englische Text unterscheidet.)

Testbefehl mit `-only-testing:ShoutTests/LocalizationNotesTests`. Erwartet: FAIL
(„Keine englische Fassung für „Eingang.md““).

- [ ] **Schritt 2: Englische Einträge**

Zuerst prüfen, welche schon existieren:

```bash
cd /Users/liam/Developer/LIAM/flow-lokal && for k in "Eingang.md" "Neuer Tab" "Tab schließen" "Liste ein/aus" "Diktat beenden" "In diese Notiz diktieren" "Im Eingang notiert" "Von einer anderen App belegt" "Schon belegt" "Scratchpad" "Scratchpad aktiv" "Scratchpad-Taste" "Eingangs-Taste" "Beim Öffnen" "Letzte Notizen" "Angeheftete" "Keine" "Neu: das Scratchpad"; do printf '%s: ' "$k"; grep -c "^ *\"$k\":" Sources/FlowLokal/Localization.swift; done
```

Erwartet: überall `0` („Einstellungen“, „Ändern“, „Entfernen“, „Verstanden“,
„Öffnen“ gibt es schon und werden nicht erneut eingetragen). Steht irgendwo `1`,
diesen Schlüssel weglassen.

Dann im Wörterbuch-Literal von `Localization.swift` hinter dem Abschnitt
`// MARK: - Notizen (Scratchpad)` (vor dem schließenden `]`) einfügen:

```swift
        // MARK: - Scratchpad-Panel

        "Eingang.md": "Inbox.md",
        "Scratchpad": "Scratchpad",
        "Neuer Tab": "New Tab",
        "Tab schließen": "Close Tab",
        "Liste ein/aus": "Show/Hide List",
        "Noch keine Notiz offen. ⌘N legt eine neue an.": "No note open. ⌘N creates one.",
        "Diktat beenden": "Stop dictation",
        "In diese Notiz diktieren": "Dictate into this note",
        "Die Notiz nimmt gerade nichts an. Der Text liegt in der Zwischenablage.":
            "The note can’t take text right now. It’s on the clipboard.",
        "Im Eingang notiert": "Added to Inbox",
        "Der Eingang ist gerade nicht erreichbar. Der Text liegt in der Zwischenablage.":
            "The inbox can’t be reached right now. The text is on the clipboard.",
        "Von einer anderen App belegt": "Taken by another app",
        "Mit ⌃ oder ⌥ kombinieren": "Combine with ⌃ or ⌥",
        "Schon belegt": "Already in use",
        "Scratchpad aktiv": "Scratchpad on",
        "Schwebender Notizblock mit eigenen Tasten.": "A floating notepad with its own keys.",
        "Scratchpad-Taste": "Scratchpad key",
        "Antippen blendet ein und aus, Halten diktiert hinein.": "Tap to show or hide, hold to dictate into it.",
        "Eingangs-Taste": "Inbox key",
        "Diktiert in die Eingangs-Notiz, ohne ein Fenster zu öffnen.": "Dictates into the inbox note without opening a window.",
        "Beim Öffnen": "When opening",
        "Letzte Notizen": "Last notes",
        "Angeheftete": "Pinned",
        "Drücke die Tastenkombination … (Esc bricht ab)": "Press the key combination… (Esc cancels)",
        "Keine": "None",
        "Neu: das Scratchpad": "New: the Scratchpad",
        "%@ antippen blendet einen schwebenden Notizblock ein, halten diktiert hinein. %@ diktiert in die Eingangs-Notiz, ohne ein Fenster zu öffnen.":
            "Tap %@ to show a floating notepad, hold it to dictate into it. %@ dictates into the inbox note without opening a window.",
```

Testbefehl mit `-only-testing:ShoutTests/LocalizationNotesTests`. Erwartet: 0 Fehler.

- [ ] **Schritt 3: Einstellungen auf der Seite „Notizen“**

In `Sources/FlowLokal/NotesView.swift`:

1. Neue Eigenschaften in `NotesView`:

```swift
    @ObservedObject var scratchpadSettings: ScratchpadSettings
    var onScratchpadCapture: (ScratchpadSettings.Role) -> Void = { _ in }
    @AppStorage("notes.settingsExpanded") private var einstellungenOffen = true
    @AppStorage("scratchpad.hintSeen") private var hinweisGesehen = false
```

2. Im `body` die Zeile `folderPanel` ersetzen durch:

```swift
            if !hinweisGesehen && scratchpadSettings.isEnabled { hintCard }
            settingsHeader
            if einstellungenOffen {
                folderPanel
                ScratchpadSettingsSection(settings: scratchpadSettings, onCapture: onScratchpadCapture)
            }
```

3. Neue Mitglieder in `NotesView`:

```swift
    /// Die Einstellungen sind einklappbar — sonst bliebe für Liste und Editor wenig Platz.
    private var settingsHeader: some View {
        Button { einstellungenOffen.toggle() } label: {
            HStack(spacing: 6) {
                Image(systemName: einstellungenOffen ? "chevron.down" : "chevron.right")
                    .font(.system(size: 9, weight: .semibold))
                Text(Loc.t("Einstellungen")).font(.system(size: 11, weight: .semibold)).tracking(0.8)
            }
            .foregroundStyle(Color(white: 0.5))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var hintCard: some View {
        let scratch = scratchpadSettings.combo(for: .scratchpad)?.display ?? Loc.t("Keine")
        let eingang = scratchpadSettings.combo(for: .inbox)?.display ?? Loc.t("Keine")
        return HStack(alignment: .top, spacing: 12) {
            Image(systemName: "rectangle.on.rectangle").foregroundStyle(Color.shoutLive)
            VStack(alignment: .leading, spacing: 4) {
                Text(Loc.t("Neu: das Scratchpad")).font(.system(size: 13, weight: .semibold)).foregroundStyle(Color(white: 0.92))
                Text(Loc.f("%@ antippen blendet einen schwebenden Notizblock ein, halten diktiert hinein. %@ diktiert in die Eingangs-Notiz, ohne ein Fenster zu öffnen.", scratch, eingang))
                    .font(.system(size: 12)).foregroundStyle(Color(white: 0.75))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            Button(Loc.t("Verstanden")) { hinweisGesehen = true }.buttonStyle(ConsoleButtonStyle())
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.shoutLive.opacity(0.10)))
    }
```

4. Am Dateiende (außerhalb von `NotesView`) die Einstellungs-Gruppe:

```swift
/// Scratchpad an/aus, die zwei globalen Tasten, das Verhalten beim Öffnen.
private struct ScratchpadSettingsSection: View {
    @ObservedObject var settings: ScratchpadSettings
    let onCapture: (ScratchpadSettings.Role) -> Void

    var body: some View {
        ConsolePanel(title: Loc.t("Scratchpad")) {
            FieldRow(title: Loc.t("Scratchpad aktiv"), help: Loc.t("Schwebender Notizblock mit eigenen Tasten.")) {
                Toggle("", isOn: $settings.isEnabled).labelsHidden().toggleStyle(.switch)
            }
            if settings.isEnabled {
                ConsoleDivider()
                tastenZeile(.scratchpad, titel: Loc.t("Scratchpad-Taste"),
                            hilfe: Loc.t("Antippen blendet ein und aus, Halten diktiert hinein."))
                ConsoleDivider()
                tastenZeile(.inbox, titel: Loc.t("Eingangs-Taste"),
                            hilfe: Loc.t("Diktiert in die Eingangs-Notiz, ohne ein Fenster zu öffnen."))
                ConsoleDivider()
                FieldRow(title: Loc.t("Beim Öffnen")) {
                    ConsoleSegmented(selection: $settings.openBehavior, options: [
                        (.resume, Loc.t("Letzte Notizen")),
                        (.newTab, Loc.t("Neuer Tab")),
                        (.lastPinned, Loc.t("Angeheftete")),
                    ])
                }
            }
        }
    }

    private func tastenZeile(_ rolle: ScratchpadSettings.Role, titel: String, hilfe: String) -> some View {
        let nimmtAuf = settings.capturing == rolle
        let zeile = settings.registrationProblems[rolle]
            ?? (nimmtAuf ? (settings.captureHint ?? Loc.t("Drücke die Tastenkombination … (Esc bricht ab)")) : hilfe)
        return FieldRow(title: titel, help: zeile) {
            HStack(spacing: 8) {
                if nimmtAuf {
                    Keycap(text: "…")
                } else if let kombi = settings.combo(for: rolle) {
                    Keycap(text: kombi.display)
                } else {
                    Text(Loc.t("Keine")).font(.system(size: 12)).foregroundStyle(Color(white: 0.5))
                }
                Button(Loc.t("Ändern")) { onCapture(rolle) }.buttonStyle(ConsoleButtonStyle())
                if settings.combo(for: rolle) != nil && !nimmtAuf {
                    Button(Loc.t("Entfernen")) { settings.setCombo(nil, for: rolle) }.buttonStyle(ConsoleButtonStyle())
                }
            }
        }
    }
}
```

5. **`DashboardView`**: nach `@ObservedObject var notes: NotesPageModel` einfügen

```swift
    @ObservedObject var scratchpadSettings: ScratchpadSettings
    var onScratchpadCapture: (ScratchpadSettings.Role) -> Void = { _ in }
```

und im `switch` den Fall `.notizen` ersetzen durch

```swift
        case .notizen:
            NotesView(model: notes, store: notes.store, scratchpadSettings: scratchpadSettings,
                      onScratchpadCapture: onScratchpadCapture)
```

6. **`AppDelegate.openDashboard(_:)`**: im Aufruf `DashboardView(…)` nach `notes: notesPage,` einfügen

```swift
                scratchpadSettings: scratchpadSettings,
                onScratchpadCapture: { [weak self] rolle in self?.beginScratchpadCapture(rolle) },
```

- [ ] **Schritt 4: Kompilieren und alle Tests**

Kompilierlauf (`** BUILD SUCCEEDED **`), dann die ganze Suite. Erwartet: 0 Fehler.

- [ ] **Schritt 5: Commit**

```bash
cd /Users/liam/Developer/LIAM/flow-lokal && git add Sources/FlowLokal/NotesView.swift Sources/FlowLokal/DashboardView.swift Sources/FlowLokal/AppDelegate.swift Sources/FlowLokal/Localization.swift Tests/ShoutTests/LocalizationNotesTests.swift && git commit -m "Scratchpad: Einstellungen auf der Seite Notizen, Hinweiskarte, englische Texte" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Aufgabe 12: Offene Punkte und Prüfliste

**Dateien:**
- Ändern: `OFFEN.md` (Eintrag „Scratchpad am Mac“)

- [ ] **Schritt 1: `OFFEN.md` nachziehen**

Den Eintrag, der mit `- [ ] **Scratchpad am Mac**` beginnt, am Ende um diesen
Satz ergänzen (der Haken bleibt offen, Plan 3 fehlt noch):

```markdown
 **Teil 2 (Panel) gebaut:** schwebendes Panel mit bis zu fünf Tabs, Liste, eigenem Rückgängig je Tab; Scratchpad-Taste (⌃⌥N antippen/halten) und Eingangs-Taste (⌃⌥I) über Carbon, änderbar und abschaltbar; Diktiertaste schreibt an den Cursor, wenn das Panel den Fokus hat; Eingangs-Notiz mit Tagesüberschrift und Toast; eine Sitzung pro Notiz für Seite und Panel; Hervorhebung absatzweise. Plan: `docs/superpowers/plans/2026-10-05-scratchpad-2-panel.md`. **In der laufenden App noch nicht geprüft** (Prüfliste im Plan, Aufgabe 12). Bewusst verschoben: Ordner-I/O abseits des Hauptstrangs.
```

- [ ] **Schritt 2: Commit**

```bash
cd /Users/liam/Developer/LIAM/flow-lokal && git add OFFEN.md && git commit -m "OFFEN: Scratchpad Teil 2 gebaut" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

- [ ] **Schritt 3: Prüfliste für das nächste Release (nicht selbst ausführen)**

Nach dem nächsten Release (aus `/Applications`) prüft der Mensch:

- [ ] ⌃⌥N in Mail antippen: Panel erscheint oben rechts, Mail behält den Fokus (Tippen geht weiter in Mail). Nochmal antippen: Panel weg.
- [ ] In der App darunter erscheint beim Drücken von ⌃⌥N **kein** Zeichen.
- [ ] ⌃⌥N halten und sprechen: Panel geht auf, Text landet im vorderen Tab; hatte der schon Text, in einem neuen.
- [ ] Ins Panel klicken, Cursor mitten in einen Satz setzen, normale Diktiertaste: Text landet genau dort, mit Leerzeichen; ⌘Z nimmt das ganze Diktat in einem Schritt zurück.
- [ ] Panel sichtbar, aber Fokus in Mail: die normale Diktiertaste fügt wie bisher in Mail ein.
- [ ] ⌃⌥I in einer beliebigen App: kein Fenster, Toast „Im Eingang notiert“; `Eingang.md` ist angeheftet, hat die Tagesüberschrift und den Eintrag mit Uhrzeit. „Öffnen“ im Toast zeigt sie im Panel.
- [ ] Eingangs-Taste im Modus „Halten“ und im Modus „Umschalten“ ausprobieren.
- [ ] ⌘N, ⌘W, ⌘1…5, ⌘⇧[ ], ⌘⇧L, ⌘⇧F im Panel; Esc blendet aus; ⌘W schließt den Tab, **nicht** das Panel.
- [ ] Sechster Tab ersetzt den vorderen; der Punkt am Reiter zeigt Ungesichertes.
- [ ] Dieselbe Notiz auf der Seite „Notizen“ und im Panel offen: Tippen im einen erscheint im anderen; keine Konfliktdatei entsteht.
- [ ] Panel auf dem zweiten Monitor, Monitor abstecken: Panel erscheint ganz sichtbar auf dem verbleibenden.
- [ ] Vollbild-App (z. B. Safari im Vollbild): Panel erscheint darüber.
- [ ] Einstellungen: Tasten ändern (⌘ allein wird abgelehnt, ⌥⌘C abgelehnt), „Entfernen“, Scratchpad aus → Tasten wirken nicht, Menüeintrag weg.
- [ ] Eine von einer anderen App belegte Kombination zeigt „Von einer anderen App belegt“.
- [ ] Notiz im Panel umbenennen bzw. `Eingang.md` auf der Seite umbenennen → das nächste Eingangs-Diktat geht in die umbenannte Datei.
- [ ] Ordner wechseln, während im Panel ungesicherter Text steht (Platte voll simuliert ist schwer) — mindestens: Ordnerwechsel mit offenem Panel räumt die Tabs ab.
- [ ] Beenden mit ⌘Q direkt nach dem Tippen im Panel → Text ist in der Datei.
- [ ] Eine lange `Eingang.md` (mehrere tausend Zeilen): Tippen bleibt flüssig.
- [ ] Englische Oberfläche: Panel, Einstellungen, Toasts sind englisch; die Eingangs-Notiz heißt `Inbox.md`.
- [ ] Rechte ⌥ als Diktiertaste: ⌃⌥N bzw. ⌃⌥I mit der **rechten** ⌥ drücken (Fokus in einer App **und** im Panel, Modus Halten/Umschalten/Doppeltipp): es startet keine zusätzliche Aufnahme, das Mikrofon bleibt nicht offen.
- [ ] Ins Panel klicken, dann in TextEdit klicken, Diktiertaste: der Text landet in TextEdit, nicht in der Notiz.
- [ ] Tastenaufnahme in den Einstellungen starten, dann Einstellungen zuklappen bzw. Seite wechseln: ⌃⌥N und ⌃⌥I wirken danach wieder.
- [ ] ⌘Q, während ein Diktat ins Panel oder in den Eingang noch verarbeitet wird: shout. wartet, der Text landet am Ziel, erst dann endet die App. Ein zweites ⌘Q während des Wartens bringt keinen Absturz und keine zweite Abfrage.
- [ ] Update über Sparkle, während ein Diktat läuft: der Text geht nicht verloren.
