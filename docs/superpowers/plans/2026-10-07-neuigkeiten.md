# Neuigkeiten — Umsetzungsplan

> **Für agentische Ausführung:** ERFORDERLICHER UNTER-SKILL: `superpowers:subagent-driven-development` (empfohlen) oder `superpowers:executing-plans`, Aufgabe für Aufgabe. Die Schritte nutzen Checkbox-Syntax (`- [ ]`).

Entwurf: `docs/superpowers/specs/2026-10-07-neuigkeiten-design.md`

**Ziel:** Ein Update-Log (`CHANGELOG.md`) als eine Quelle für App und GitHub; nach
einem Update einmal ein überspringbares Fenster „Neu in shout.“ mit Erklär-Animation;
eine Seite „Neuigkeiten“ mit allen Versionen.

**Architektur:** Reine, getestete Bausteine (`AppVersion`, `ChangelogParser`,
`WhatsNewDecider`, `WhatsNewState`) entscheiden, was gezeigt wird. Die Animation ist
eine einzelne HTML-Datei im Bundle, die ein `WKWebView` abspielt und ein Node-Skript
zu MP4 rendert. Fenster, Seite und Auslöser kommen zuletzt in den `AppDelegate`.

**Technik:** Swift 5.10, SwiftUI + AppKit, WebKit (`WKWebView`), Canvas/WebAudio,
Node + `playwright-core` + ffmpeg fürs MP4, Bash/awk fürs Release, XCTest, XcodeGen.

## Globale Vorgaben

- **Umlaute immer als echtes UTF-8**, nie `ae`/`oe`/`ue`/`ss`. Code, Kommentare, Commits und Oberfläche auf Deutsch.
- **macOS 14**, `SWIFT_VERSION` 5.10 (keine nackten Regex-Literale `/…/`).
- **Oberflächentexte über `Loc.t`/`Loc.f`** mit englischem Eintrag in
  `Sources/FlowLokal/Localization.swift`. Doppelte Schlüssel stürzen ab: vor dem
  Einfügen `grep -n '"<Text>"' Sources/FlowLokal/Localization.swift`; danach muss
  `grep -oE '^\s*"[^"]+":' Sources/FlowLokal/Localization.swift | sort | uniq -d` leer sein.
  Neue Schlüssel in `Tests/ShoutTests/LocalizationNotesTests.swift` aufnehmen (außer gleichlautende).
- **Getestete Dateien aus `Sources/FlowLokal/` einzeln ins Testziel** (`project.yml`,
  `ShoutTests:`; neuer Block `# Neuigkeiten` am Ende der Quellenliste), dann `xcodegen generate`.
- **Kein Netz in der App.** Alles liegt im Bundle.
- **Commits:** nur genannte Pfade stagen; nie `Support/launch-video/` oder `.superpowers/`;
  Nachricht endet mit `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>` (zweites `-m`).
- **Die App wird nicht gestartet.** Tests, Kompilierlauf, Einzelbilder der Animation.
- Testbefehl: `cd /Users/liam/Developer/LIAM/flow-lokal && xcodebuild test -project FlowLokal.xcodeproj -scheme ShoutTests -destination 'platform=macOS,arch=arm64' -skipPackagePluginValidation -skipMacroValidation 2>&1 | tail -25` (eine Klasse: `-only-testing:ShoutTests/<Klasse>` vor `2>&1`).
- Kompilierlauf: `xcodebuild build -project FlowLokal.xcodeproj -scheme FlowLokal -configuration Debug -destination 'platform=macOS,arch=arm64' -skipPackagePluginValidation -skipMacroValidation CODE_SIGNING_ALLOWED=NO 2>&1 | tail -20` → `** BUILD SUCCEEDED **`.

---

### Aufgabe 1: `AppVersion` und `ChangelogParser`

**Dateien:** Neu `Sources/FlowLokal/Changelog.swift`, `Tests/ShoutTests/ChangelogParserTests.swift`; `project.yml` (Testziel).

**Schnittstellen (erzeugt):**
- `struct AppVersion: Comparable, Hashable, CustomStringConvertible { init?(_ string: String); let parts: [Int] }`
- `struct ChangelogEntry: Equatable, Identifiable { version: AppVersion; date: String; highlight: Bool; video: String?; german: String; english: String; var id: String; func text(german: Bool) -> String }`
- `enum ChangelogParser { static func parse(_ text: String) -> [ChangelogEntry]; static func loadBundled(_ bundle: Bundle = .main) -> [ChangelogEntry]? }`

- [ ] **Schritt 1: Test** — `Tests/ShoutTests/ChangelogParserTests.swift`:

```swift
import XCTest

final class ChangelogParserTests: XCTestCase {

    private let beispiel = """
    # shout. — Neuigkeiten

    Vorspann, wird ignoriert.

    ## 1.13.0 — 2026-10-07
    zeigen: ja
    video: scratchpad

    ### Deutsch
    **Neu: das Scratchpad.**
    - ⌃⌥N blendet ein.

    ### English
    **New: the Scratchpad.**
    - ⌃⌥N shows it.

    ## 1.12.0 - 2026-09-21
    zeigen: nein

    ### Deutsch
    Meeting-Erkennung.

    ### English
    Meeting detection.
    """

    func testZweiEintraegeNeuesteZuerst() throws {
        let e = ChangelogParser.parse(beispiel)
        XCTAssertEqual(e.map(\.version.description), ["1.13.0", "1.12.0"])
        let neu = try XCTUnwrap(e.first)
        XCTAssertTrue(neu.highlight)
        XCTAssertEqual(neu.video, "scratchpad")
        XCTAssertEqual(neu.date, "2026-10-07")
        XCTAssertEqual(neu.german, "**Neu: das Scratchpad.**\n- ⌃⌥N blendet ein.")
        XCTAssertEqual(neu.english, "**New: the Scratchpad.**\n- ⌃⌥N shows it.")
        XCTAssertFalse(e[1].highlight)
        XCTAssertNil(e[1].video)
        XCTAssertEqual(neu.text(german: false), neu.english)
    }

    func testFehlendesZeigenUeberspringtNurDiesenAbschnitt() {
        let text = beispiel.replacingOccurrences(of: "zeigen: nein\n", with: "")
        XCTAssertEqual(ChangelogParser.parse(text).map(\.version.description), ["1.13.0"])
    }

    func testFehlenderSprachblockUeberspringt() {
        let text = beispiel.replacingOccurrences(of: "### English\nMeeting detection.", with: "")
        XCTAssertEqual(ChangelogParser.parse(text).map(\.version.description), ["1.13.0"])
    }

    func testLeererSprachblockUeberspringt() {
        let text = beispiel.replacingOccurrences(of: "Meeting detection.", with: "   ")
        XCTAssertEqual(ChangelogParser.parse(text).count, 1)
    }

    func testKaputteKopfzeileUeberspringt() {
        let text = beispiel.replacingOccurrences(of: "## 1.12.0 - 2026-09-21", with: "## eins — gestern")
        XCTAssertEqual(ChangelogParser.parse(text).count, 1)
    }

    func testUnbekannterZeigenWertUeberspringt() {
        let text = beispiel.replacingOccurrences(of: "zeigen: nein", with: "zeigen: vielleicht")
        XCTAssertEqual(ChangelogParser.parse(text).count, 1)
    }

    func testVideonameNurBuchstabenZiffernBindestrich() {
        let text = beispiel.replacingOccurrences(of: "video: scratchpad", with: "video: ../geheim")
        XCTAssertEqual(ChangelogParser.parse(text).count, 1, "ungültiger Videoname → Abschnitt übersprungen")
    }

    func testDoppelteVersionDerErsteGewinnt() {
        let text = beispiel + "\n\n## 1.13.0 — 2026-10-08\nzeigen: nein\n\n### Deutsch\nx\n\n### English\ny\n"
        let e = ChangelogParser.parse(text)
        XCTAssertEqual(e.count, 2)
        XCTAssertTrue(e[0].highlight)
    }

    func testCRLF() {
        XCTAssertEqual(ChangelogParser.parse(beispiel.replacingOccurrences(of: "\n", with: "\r\n")).count, 2)
    }

    func testVersionen() throws {
        XCTAssertEqual(AppVersion("1.13"), AppVersion("1.13.0"))
        XCTAssertGreaterThan(try XCTUnwrap(AppVersion("1.13.10")), try XCTUnwrap(AppVersion("1.13.9")))
        XCTAssertLessThan(try XCTUnwrap(AppVersion("1.9")), try XCTUnwrap(AppVersion("1.12.0")))
        XCTAssertNil(AppVersion(""))
        XCTAssertNil(AppVersion("1.x"))
        XCTAssertNil(AppVersion("1..2"))
        XCTAssertEqual(Set([AppVersion("2")!, AppVersion("2.0.0")!]).count, 1)
        XCTAssertEqual(AppVersion("1.13.0")?.description, "1.13.0")
    }
}
```

- [ ] **Schritt 2:** `project.yml`, Testziel, am Ende der Quellenliste:

```yaml
      # Neuigkeiten
      - path: Sources/FlowLokal/Changelog.swift
```

`xcodegen generate`; Klasse laufen lassen → Kompilierfehler.

- [ ] **Schritt 3: Umsetzen** — `Sources/FlowLokal/Changelog.swift`:

```swift
import Foundation

/// Versionsnummer wie „1.13.0“ — verglichen Stelle für Stelle als Zahl;
/// fehlende Stellen gelten als 0 (1.13 == 1.13.0).
struct AppVersion: Comparable, Hashable, CustomStringConvertible {
    let parts: [Int]

    init?(_ string: String) {
        let teile = string.trimmingCharacters(in: .whitespaces)
            .split(separator: ".", omittingEmptySubsequences: false)
        guard !teile.isEmpty, teile.count <= 4 else { return nil }
        var zahlen: [Int] = []
        for teil in teile {
            guard !teil.isEmpty, teil.allSatisfy({ $0.isASCII && $0.isNumber }), let zahl = Int(teil) else { return nil }
            zahlen.append(zahl)
        }
        parts = zahlen
    }

    private var normalized: [Int] {
        var p = parts
        while p.count > 1, p.last == 0 { p.removeLast() }
        return p
    }

    static func == (a: AppVersion, b: AppVersion) -> Bool { a.normalized == b.normalized }

    static func < (a: AppVersion, b: AppVersion) -> Bool {
        let n = max(a.parts.count, b.parts.count)
        let x = a.parts + Array(repeating: 0, count: n - a.parts.count)
        let y = b.parts + Array(repeating: 0, count: n - b.parts.count)
        return x.lexicographicallyPrecedes(y)
    }

    func hash(into hasher: inout Hasher) { hasher.combine(normalized) }

    var description: String { parts.map(String.init).joined(separator: ".") }
}

/// Eine Version aus `CHANGELOG.md`.
struct ChangelogEntry: Equatable, Identifiable {
    let version: AppVersion
    let date: String
    /// `zeigen: ja` — erscheint einmal im Fenster „Neu in shout.“.
    let highlight: Bool
    /// Name einer Animation in `Explainers/<name>.html`.
    let video: String?
    let german: String
    let english: String

    var id: String { version.description }

    func text(german isGerman: Bool) -> String { isGerman ? german : english }
}

/// Liest `CHANGELOG.md`. Ein fehlerhafter Abschnitt wird übersprungen (und
/// geloggt) — der Rest bleibt lesbar, die App stürzt nie an der Datei ab.
enum ChangelogParser {

    static func parse(_ text: String) -> [ChangelogEntry] {
        let zeilen = text.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
        var abschnitte: [[String]] = []
        for zeile in zeilen {
            if zeile.hasPrefix("## ") {
                abschnitte.append([zeile])
            } else if !abschnitte.isEmpty {
                abschnitte[abschnitte.count - 1].append(zeile)
            }
        }
        var ergebnis: [ChangelogEntry] = []
        var gesehen = Set<AppVersion>()
        for abschnitt in abschnitte {
            guard let eintrag = entry(abschnitt) else {
                NSLog("shout: Abschnitt im Update-Log übersprungen: \(abschnitt.first ?? "")")
                continue
            }
            guard gesehen.insert(eintrag.version).inserted else { continue }
            ergebnis.append(eintrag)
        }
        return ergebnis.sorted { $0.version > $1.version }
    }

    /// Die mitgelieferte Datei. `nil`, wenn sie fehlt oder nicht lesbar ist.
    static func loadBundled(_ bundle: Bundle = .main) -> [ChangelogEntry]? {
        guard let url = bundle.url(forResource: "CHANGELOG", withExtension: "md"),
              let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        return parse(text)
    }

    // MARK: - Intern

    private static func entry(_ zeilen: [String]) -> ChangelogEntry? {
        let kopf = zeilen[0].dropFirst(3).trimmingCharacters(in: .whitespaces)
        var teile = kopf.components(separatedBy: " — ")
        if teile.count != 2 { teile = kopf.components(separatedBy: " - ") }
        guard teile.count == 2, let version = AppVersion(teile[0]), isDate(teile[1]) else { return nil }

        var highlight: Bool?
        var video: String?
        var videoUngueltig = false
        var bloecke: [String: [String]] = [:]
        var aktuell: String?
        for zeile in zeilen.dropFirst() {
            if zeile.hasPrefix("### ") {
                let name = zeile.dropFirst(4).trimmingCharacters(in: .whitespaces)
                aktuell = name
                bloecke[name] = []
                continue
            }
            if let aktuell {
                bloecke[aktuell, default: []].append(zeile)
                continue
            }
            let t = zeile.trimmingCharacters(in: .whitespaces)
            if t.hasPrefix("zeigen:") {
                switch t.dropFirst(7).trimmingCharacters(in: .whitespaces).lowercased() {
                case "ja": highlight = true
                case "nein": highlight = false
                default: highlight = nil
                }
            } else if t.hasPrefix("video:") {
                let name = t.dropFirst(6).trimmingCharacters(in: .whitespaces)
                if name.isEmpty {
                    video = nil
                } else if name.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-") }) {
                    video = name
                } else {
                    videoUngueltig = true
                }
            }
        }
        guard let highlight, !videoUngueltig,
              let deutsch = block(bloecke["Deutsch"]), let englisch = block(bloecke["English"]) else { return nil }
        return ChangelogEntry(version: version, date: teile[1].trimmingCharacters(in: .whitespaces),
                              highlight: highlight, video: video, german: deutsch, english: englisch)
    }

    private static func block(_ zeilen: [String]?) -> String? {
        guard let zeilen else { return nil }
        let text = zeilen.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }

    /// „JJJJ-MM-TT“.
    private static func isDate(_ s: String) -> Bool {
        let t = Array(s.trimmingCharacters(in: .whitespaces))
        guard t.count == 10, t[4] == "-", t[7] == "-" else { return false }
        return t.enumerated().allSatisfy { i, c in i == 4 || i == 7 || (c.isASCII && c.isNumber) }
    }
}
```

- [ ] **Schritt 4:** Klasse grün (`Executed 10 tests, with 0 failures`).

- [ ] **Schritt 5: Commit**

```bash
cd /Users/liam/Developer/LIAM/flow-lokal && git add Sources/FlowLokal/Changelog.swift Tests/ShoutTests/ChangelogParserTests.swift project.yml && git commit -m "Neuigkeiten: Versionsnummern und Update-Log lesen" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Aufgabe 2: `WhatsNewDecider` und `WhatsNewState`

**Dateien:** Neu `Sources/FlowLokal/WhatsNew.swift`, `Tests/ShoutTests/WhatsNewDeciderTests.swift`; `project.yml` (Testziel).

**Schnittstellen:**
- Verbraucht: `AppVersion`, `ChangelogEntry` (Aufgabe 1).
- Erzeugt: `enum WhatsNewDecider { static let baseline: AppVersion; static func entriesToShow(all:lastSeen:current:onboardingDone:) -> [ChangelogEntry] }`,
  `struct WhatsNewState { init(defaults: UserDefaults = .standard); var lastSeen: AppVersion? { get }; func markSeen(_ version: AppVersion); static let key = "whatsNew.lastSeenVersion" }`,
  `extension AppVersion { static var running: AppVersion? }` (aus `CFBundleShortVersionString`).

- [ ] **Schritt 1: Test** — `Tests/ShoutTests/WhatsNewDeciderTests.swift`:

```swift
import XCTest

final class WhatsNewDeciderTests: XCTestCase {

    private func e(_ v: String, _ zeigen: Bool) -> ChangelogEntry {
        ChangelogEntry(version: AppVersion(v)!, date: "2026-10-07", highlight: zeigen, video: nil, german: "d", english: "e")
    }

    private lazy var alle = [e("1.15.0", true), e("1.14.1", false), e("1.14.0", true), e("1.13.0", true), e("1.12.0", true)]

    private func zeige(_ lastSeen: String?, _ current: String, onboarding: Bool = true) -> [String] {
        WhatsNewDecider.entriesToShow(all: alle, lastSeen: lastSeen.flatMap(AppVersion.init),
                                      current: AppVersion(current)!, onboardingDone: onboarding)
            .map(\.version.description)
    }

    func testNeuinstallationZeigtNichts() {
        XCTAssertEqual(zeige(nil, "1.15.0", onboarding: false), [])
    }

    func testOhneGemerkteVersionGiltDieBasislinie() {
        XCTAssertEqual(WhatsNewDecider.baseline, AppVersion("1.12.0"))
        XCTAssertEqual(zeige(nil, "1.13.0"), ["1.13.0"])
    }

    func testUebersprungeneVersionenZusammen() {
        XCTAssertEqual(zeige("1.13.0", "1.15.0"), ["1.15.0", "1.14.0"])
    }

    func testNurMarkierteUndNichtsUeberDerLaufenden() {
        XCTAssertEqual(zeige("1.14.0", "1.14.1"), [])
        XCTAssertEqual(zeige("1.13.0", "1.14.1"), ["1.14.0"])
    }

    func testSchonGesehen() {
        XCTAssertEqual(zeige("1.15.0", "1.15.0"), [])
    }

    func testZustandMerktSich() {
        let name = "shout-whatsnew-\(UUID().uuidString)"
        let d = UserDefaults(suiteName: name)!
        defer { d.removePersistentDomain(forName: name) }
        let s = WhatsNewState(defaults: d)
        XCTAssertNil(s.lastSeen)
        s.markSeen(AppVersion("1.13.0")!)
        XCTAssertEqual(WhatsNewState(defaults: d).lastSeen, AppVersion("1.13.0"))
        d.set("kaputt", forKey: WhatsNewState.key)
        XCTAssertNil(WhatsNewState(defaults: d).lastSeen)
    }
}
```

- [ ] **Schritt 2:** `project.yml` (Block `# Neuigkeiten`): `      - path: Sources/FlowLokal/WhatsNew.swift`; `xcodegen generate`; rot.

- [ ] **Schritt 3: Umsetzen** — `Sources/FlowLokal/WhatsNew.swift`:

```swift
import Foundation

/// Was das Fenster „Neu in shout.“ zeigt.
enum WhatsNewDecider {
    /// Die letzte Version vor diesem Fenster. Wer von dort (oder früher)
    /// aktualisiert, hat sich noch nichts gemerkt — für ihn gilt diese.
    static let baseline = AppVersion("1.12.0")!

    static func entriesToShow(all: [ChangelogEntry], lastSeen: AppVersion?,
                              current: AppVersion, onboardingDone: Bool) -> [ChangelogEntry] {
        // Neuinstallation: Das Onboarding stellt alles vor.
        guard onboardingDone else { return [] }
        let ab = lastSeen ?? baseline
        return all.filter { $0.highlight && $0.version > ab && $0.version <= current }
            .sorted { $0.version > $1.version }
    }
}

/// Die zuletzt gesehene Version, in den UserDefaults.
struct WhatsNewState {
    static let key = "whatsNew.lastSeenVersion"
    let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    var lastSeen: AppVersion? { defaults.string(forKey: Self.key).flatMap(AppVersion.init) }

    func markSeen(_ version: AppVersion) { defaults.set(version.description, forKey: Self.key) }
}

extension AppVersion {
    /// Die Version dieser App (`CFBundleShortVersionString`).
    static var running: AppVersion? {
        (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String).flatMap(AppVersion.init)
    }
}
```

- [ ] **Schritt 4:** grün (`Executed 6 tests, with 0 failures`).

- [ ] **Schritt 5: Commit**

```bash
cd /Users/liam/Developer/LIAM/flow-lokal && git add Sources/FlowLokal/WhatsNew.swift Tests/ShoutTests/WhatsNewDeciderTests.swift project.yml && git commit -m "Neuigkeiten: entscheiden, was nach dem Update erscheint" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Aufgabe 3: `CHANGELOG.md`, Bundle, Release-Notes und Release-Prüfung

**Dateien:** Neu `CHANGELOG.md`, `Support/release-notes.sh`, `Tests/ShoutTests/ChangelogRepoTests.swift`; Ändern `project.yml` (App-Ressource), `release.sh`, `RELEASE.md`.

**Schnittstellen:** Verbraucht `ChangelogParser`, `AppVersion`. Erzeugt die Ressource `CHANGELOG.md` im App-Bundle und `Support/release-notes.sh [--check] <version>` (liest `$CHANGELOG`, Vorgabe `CHANGELOG.md` im Repo).

- [ ] **Schritt 1: `CHANGELOG.md`** (Repo-Wurzel, genau so):

````markdown
# shout. — Neuigkeiten

Eine Version je Abschnitt, die neueste oben. Format:
`## <Version> — <JJJJ-MM-TT>`, dann `zeigen: ja|nein` (ja = erscheint einmal nach
dem Update im Fenster „Neu in shout.“), optional `video: <name>` (Animation in
`Resources/Explainers/<name>.html`), dann `### Deutsch` und `### English`.
Innerhalb der Sprachblöcke keine `###`-Überschriften — **fett** statt dessen.

## 1.13.0 — 2026-10-07
zeigen: ja
video: scratchpad

### Deutsch
**Neu: das Scratchpad.** Ein schwebender Notizblock zum Diktieren und Tippen. Jede Notiz ist eine Markdown-Datei in einem Ordner deiner Wahl — iCloud Drive oder ein Obsidian-Vault funktionieren direkt.

- **⌃⌥N** antippen blendet das Panel ein und aus, halten diktiert hinein. Hat das Panel den Fokus, schreibt die normale Diktiertaste an den Cursor.
- **⌃⌥I** diktiert ohne Fenster in die Eingangs-Notiz.
- **⌘⏎** legt die Auswahl oder die Notiz formatiert in die App davor — Mail bekommt echte Formatierung, das Terminal den Klartext.
- **Zauberstab:** Aufräumen, Als Mail, Zusammenfassen, To-do-Liste, Ins Englische, eigene Transforms und Anweisung per Sprache. Ein Schritt zurück mit ⌘Z.
- **Versionen:** frühere Stände einer Notiz ansehen und wiederherstellen.
- **Bilder** einfügen oder hineinziehen, mit Vorschau im Editor.
- Alles Weitere auf der Seite **Notizen** im Hauptfenster, samt Einstellungen.

### English
**New: the Scratchpad.** A floating notepad for dictating and typing. Every note is a Markdown file in a folder of your choice — iCloud Drive or an Obsidian vault work right away.

- Tap **⌃⌥N** to show or hide the panel, hold it to dictate into it. When the panel has focus, the regular dictation key types at the cursor.
- **⌃⌥I** dictates into the inbox note without opening a window.
- **⌘⏎** sends the selection or the note, formatted, to the app you came from — Mail gets real formatting, Terminal gets plain text.
- **Magic wand:** Clean up, As email, Summarize, To-do list, To English, your own transforms and spoken instructions. One step back with ⌘Z.
- **Versions:** view and restore earlier states of a note.
- **Images:** paste or drag them in, with a preview in the editor.
- Everything else lives on the **Notes** page in the main window, including the settings.

## 1.12.0 — 2026-09-21
zeigen: nein

### Deutsch
**Meeting-Erkennung.** Läuft ein Online-Meeting (Zoom, Teams, Webex, Skype, FaceTime, Discord, Slack, Jitsi), fragt shout., ob es mitgeschnitten werden soll — erkannt am Ton der Konferenz-App, nicht am Mikrofon. Einstellbar unter *Meeting → Meeting erkennen*.

- **Wörterbuch:** neuer Schalter „Ausbesserungen von selbst lernen“; überlange Einträge sind nicht mehr möglich.
- **Behoben:** Ohne Bedienungshilfen-Freigabe geht ein Diktat nicht mehr verloren — es landet in der Zwischenablage und im Verlauf.

### English
**Meeting detection.** When an online meeting is running (Zoom, Teams, Webex, Skype, FaceTime, Discord, Slack, Jitsi), shout. asks whether to record it — detected from the conferencing app's audio, not the microphone. Set it under *Meeting → Detect meetings*.

- **Dictionary:** new switch “Learn corrections automatically”; overlong entries are no longer possible.
- **Fixed:** Without the Accessibility permission a dictation is no longer lost — it goes to the clipboard and the history.

## 1.11.1 — 2026-09-15
zeigen: nein

### Deutsch
**Gefundene Modelle lassen sich auswählen.** Neuer Abschnitt „Auf diesem Rechner gefunden“ auf der Modelle-Seite: Modelle aus durchsuchten Ordnern (etwa LM Studio) stehen dort zur Auswahl und werden ohne Download geladen.

### English
**Found models can be selected.** A new section “Found on this Mac” on the Models page lists models from scanned folders (e.g. LM Studio); choosing one loads it from there, without a download.

## 1.11.0 — 2026-09-15
zeigen: nein

### Deutsch
**Eigenes Modellverzeichnis.** Unter „Modelle“ lässt sich der Basisordner für Sprach- und Textmodelle wählen, etwa auf einer externen Platte. Vorhandene Modelle (z. B. aus LM Studio) werden aus durchsuchten Ordnern mitbenutzt statt erneut geladen. Für bestehende Installationen ändert sich nichts.

### English
**Your own model folder.** Under “Models” you can choose the base folder for speech and text models, e.g. on an external drive. Existing models (e.g. from LM Studio) are reused from scanned folders instead of being downloaded again. Nothing changes for existing installations.
````

- [ ] **Schritt 2: Test** — `Tests/ShoutTests/ChangelogRepoTests.swift`:

```swift
import XCTest

/// Die echte `CHANGELOG.md` und das Release-Skript des Repos.
final class ChangelogRepoTests: XCTestCase {

    private var wurzel: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    }

    private func text(_ datei: String) throws -> String {
        try String(contentsOf: wurzel.appendingPathComponent(datei), encoding: .utf8)
    }

    func testAlleAbschnitteGueltig() throws {
        let roh = try text("CHANGELOG.md")
        let abschnitte = roh.components(separatedBy: "\n").filter { $0.hasPrefix("## ") }.count
        XCTAssertEqual(ChangelogParser.parse(roh).count, abschnitte, "ein Abschnitt wurde übersprungen")
    }

    func testEintragFuerDieAktuelleVersion() throws {
        let yml = try text("project.yml")
        let zeile = try XCTUnwrap(yml.components(separatedBy: "\n").first { $0.contains("MARKETING_VERSION:") })
        let version = try XCTUnwrap(zeile.components(separatedBy: "\"").dropFirst().first)
        let eintraege = ChangelogParser.parse(try text("CHANGELOG.md"))
        XCTAssertTrue(eintraege.contains { $0.version == AppVersion(version) }, "kein Abschnitt für \(version)")
    }

    func testVideosGibtEsAuch() throws {
        for e in ChangelogParser.parse(try text("CHANGELOG.md")) {
            guard let v = e.video else { continue }
            XCTAssertTrue(FileManager.default.fileExists(atPath: wurzel.appendingPathComponent("Resources/Explainers/\(v).html").path),
                          "Animation \(v) fehlt")
        }
    }

    private func skript(_ args: [String], changelog: String? = nil) throws -> (code: Int32, out: String) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/bash")
        p.arguments = [wurzel.appendingPathComponent("Support/release-notes.sh").path] + args
        var env = ProcessInfo.processInfo.environment
        if let changelog { env["SHOUT_CHANGELOG"] = changelog }
        p.environment = env
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = Pipe()
        try p.run()
        p.waitUntilExit()
        return (p.terminationStatus, String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self))
    }

    func testReleaseNotesHabenBeideSprachenOhneSteuerzeilen() throws {
        let r = try skript(["1.13.0"])
        XCTAssertEqual(r.code, 0)
        XCTAssertTrue(r.out.hasPrefix("**Neu: das Scratchpad.**"))
        XCTAssertTrue(r.out.contains("\n---\n"))
        XCTAssertTrue(r.out.contains("**New: the Scratchpad.**"))
        XCTAssertFalse(r.out.contains("zeigen:"))
        XCTAssertFalse(r.out.contains("video:"))
        XCTAssertFalse(r.out.contains("### "))
    }

    func testPruefungScheitertOhneAbschnitt() throws {
        XCTAssertEqual(try skript(["--check", "1.13.0"]).code, 0)
        XCTAssertNotEqual(try skript(["--check", "9.9.9"]).code, 0)
        let kaputt = FileManager.default.temporaryDirectory.appendingPathComponent("shout-changelog-\(UUID().uuidString).md")
        try "## 2.0.0 — 2026-12-01\nzeigen: ja\n\n### Deutsch\nx\n".write(to: kaputt, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: kaputt) }
        XCTAssertNotEqual(try skript(["--check", "2.0.0"], changelog: kaputt.path).code, 0, "English fehlt")
    }
}
```

Bis Aufgabe 4 fehlt `Resources/Explainers/scratchpad.html`: In diesem Schritt eine Platzhalterdatei anlegen,
die Aufgabe 4 ersetzt — genau dieser Inhalt:

```html
<!doctype html><meta charset="utf-8"><title>scratchpad</title>
<script>window.explainer = { ready: true, duration: 0, play(){}, pause(){}, restart(){}, setMuted(){} };</script>
```

- [ ] **Schritt 3: `Support/release-notes.sh`** (ausführbar, `chmod +x`):

```bash
#!/usr/bin/env bash
# Release-Notes einer Version aus CHANGELOG.md — für
#   gh release create v1.13.0 … --notes-file <(Support/release-notes.sh 1.13.0)
#   Support/release-notes.sh --check 1.13.0   → Exit 0 nur mit gültigem Abschnitt
# SHOUT_CHANGELOG=<pfad> liest eine andere Datei (Tests).
set -euo pipefail
cd "$(dirname "$0")/.."

check=0
if [[ "${1:-}" == "--check" ]]; then check=1; shift; fi
version="${1:?Version fehlt, z. B. 1.13.0}"
datei="${SHOUT_CHANGELOG:-CHANGELOG.md}"
[[ -f "$datei" ]] || { echo "$datei fehlt" >&2; exit 1; }

# Der Abschnitt ohne seine Kopfzeile.
abschnitt=$(awk -v v="$version" '/^## /{ drin = ($2 == v); next } drin { print }' "$datei")
[[ -n "$abschnitt" ]] || { echo "Kein Abschnitt für $version in $datei" >&2; exit 1; }

block() {
  printf '%s\n' "$abschnitt" | awk -v name="$1" '
    /^### /{ drin = ($0 == "### " name); next }
    drin { z[++n] = $0 }
    END {
      a = 1; while (a <= n && z[a] ~ /^[[:space:]]*$/) a++
      e = n; while (e >= a && z[e] ~ /^[[:space:]]*$/) e--
      for (i = a; i <= e; i++) print z[i]
    }'
}

deutsch=$(block "Deutsch")
englisch=$(block "English")
printf '%s\n' "$abschnitt" | grep -Eq '^zeigen:[[:space:]]*(ja|nein)[[:space:]]*$' \
  || { echo "$version: Zeile „zeigen: ja|nein“ fehlt" >&2; exit 1; }
[[ -n "$deutsch" ]] || { echo "$version: Block „### Deutsch“ fehlt oder ist leer" >&2; exit 1; }
[[ -n "$englisch" ]] || { echo "$version: Block „### English“ fehlt oder ist leer" >&2; exit 1; }

(( check )) && exit 0
printf '%s\n\n---\n\n%s\n' "$deutsch" "$englisch"
```

- [ ] **Schritt 4: Bundle** — `project.yml`, Ziel `FlowLokal`, `sources:` (nach dem Audio-Eintrag):

```yaml
      # Update-Log fürs Fenster „Neu in shout.“ und die Seite „Neuigkeiten“.
      - path: CHANGELOG.md
        buildPhase: resources
      # Erklär-Animationen (HTML, im WKWebView abgespielt).
      - path: Resources/Explainers
        type: folder
```

`ChangelogRepoTests` in den Block `# Neuigkeiten`? — Nein, Testdateien kommen über den Ordner. `xcodegen generate`.
Nach dem Kompilierlauf prüfen:
`ls build/Build/Products/Debug/shout.app/Contents/Resources/ | grep -E "CHANGELOG.md|Explainers"` (Pfad des Debug-Produkts ggf. mit `-showBuildSettings` ermitteln) → beide da.

- [ ] **Schritt 5: `release.sh`** — direkt nach `cd "$(dirname "$0")"`:

```bash
VERSION=$(awk -F'"' '/MARKETING_VERSION:/ { print $2; exit }' project.yml)
echo "▶ Prüfe CHANGELOG.md für $VERSION …"
Support/release-notes.sh --check "$VERSION" \
  || { echo "✗ CHANGELOG.md braucht einen gültigen Abschnitt für $VERSION (siehe Kopf der Datei)."; exit 1; }
```

(Gibt es in `release.sh` schon eine Variable für die Version, diese benutzen statt einer zweiten.)
Am Ende der Ausgabe von `release.sh`, bei „Nächste Schritte“, die Zeile ergänzen:
`gh release create v$VERSION … --notes-file <(Support/release-notes.sh $VERSION)`.

`RELEASE.md`: kurzer Abschnitt „Update-Log“ — vor jedem Release einen Abschnitt in
`CHANGELOG.md` anlegen; `zeigen: ja` nur bei Neuerungen, die man sehen soll; Release-Notes
kommen aus `Support/release-notes.sh`.

- [ ] **Schritt 6:** `ChangelogRepoTests` grün (`Executed 5 tests, with 0 failures`), ganze Suite, Kompilierlauf, Ressourcen im Bundle.

- [ ] **Schritt 7: Commit**

```bash
cd /Users/liam/Developer/LIAM/flow-lokal && git add CHANGELOG.md Support/release-notes.sh Tests/ShoutTests/ChangelogRepoTests.swift Resources/Explainers/scratchpad.html project.yml release.sh RELEASE.md && git commit -m "Neuigkeiten: CHANGELOG.md als eine Quelle für App und GitHub, Release prüft den Eintrag" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Aufgabe 4: Erklär-Animation „Scratchpad“ und MP4-Renderer

**Dateien:** Ersetzen `Resources/Explainers/scratchpad.html`; neu `Support/explainer-video/package.json`,
`Support/explainer-video/render.mjs`, `Support/explainer-video/.gitignore` (`node_modules/`, `out/`, `stills/`).

**Schnittstelle (erzeugt, für Aufgabe 5 bindend):**

```js
window.explainer = {
  ready: true,              // nach dem Laden
  duration: 40,             // Sekunden (± 2)
  play(), pause(), restart(),
  setMuted(bool),
  frame(t, quality) → string,   // JPEG-Base64 des Bilds bei t (für den Renderer)
  renderAudio() → Promise<string> // WAV-Base64 der ganzen Tonspur (für den Renderer)
};
// Meldungen an die App (nur wenn vorhanden):
window.webkit?.messageHandlers?.explainer?.postMessage({ type: "state", playing, muted, t });
window.webkit?.messageHandlers?.explainer?.postMessage({ type: "ended" });
```

URL-Parameter: `lang=de|en` (Vorgabe de), `muted=1|0` (Vorgabe 1), `autoplay=1|0` (Vorgabe 1),
`keys=<Scratchpad>,<Eingang>` (URL-kodiert; leer oder fehlend → `⌃⌥N`,`⌃⌥I`), `export` (feste
Bühne 1600 × 1000, Gerätefaktor 1, kein Autoplay — der Renderer ruft `frame(t)`).

**Vorgaben:**
- **Eine Datei**, alles inline (CSS, JS), **kein Netz**: keine Google Fonts, keine CDN.
  Schrift: `-apple-system, "SF Pro Text", system-ui, sans-serif`; Mono: `ui-monospace, "SF Mono", Menlo`.
- **Canvas 16:10**, Bühne 1600 × 1000, skaliert auf die Fenstergröße (Gerätepixel beachten),
  Hintergrund `#0B0B0E`, Paneele `#16161A`, Text `#F3F0EC`, gedämpft `#8E8B94`, Akzent `#FF4A0A`,
  Linien `rgba(255,255,255,0.10)` — die Werte aus `Support/launch-video/shout-launch.html` (dort
  steht auch das bewährte Muster: deterministisches `render(t)`, Uhr über `performance.now()` bzw.
  `AudioContext`, `requestAnimationFrame`, WebAudio-Synthese; als Vorlage lesen, nicht kopieren).
- **Deterministisch:** `render(t)` hängt nur von `t` ab (kein `Math.random` ohne festen Samen).
- **Keine eigenen Bedienelemente** auf der Seite (die App hat eine native Leiste); am Ende bleibt
  das letzte Bild stehen und `ended` wird gemeldet. Klick auf die Bühne tut nichts.
- **Texte** in einem Objekt `{ de: {...}, en: {...} }`; Tasten aus `keys`.
- **Szenen (~40 s)** genau wie in der Spec, Abschnitt 3:
  1. 0–3 s Titel „Neu: das Scratchpad“ / „New: the Scratchpad“.
  2. 3–12 s Schreibtisch mit Mail-Fenster im Hintergrund; Tastenkappe ⌃⌥N antippen → Panel gleitet
     oben rechts herein (Tabs, Editor, Fußleiste wie im echten Panel); dann gehalten → Pille mit
     Pegel unten mittig, Text erscheint Wort für Wort im Panel („Ideen fürs Team-Meeting: …“ /
     „Ideas for the team meeting: …“). Unterschrift: „Antippen blendet ein · Halten diktiert hinein“ /
     „Tap to show · Hold to dictate“.
  3. 12–18 s Tastenkappe ⌃⌥I, kein Fenster; Toast oben rechts „Im Eingang notiert“ / „Added to
     Inbox“. Unterschrift „Schnell festhalten – ohne Fenster“ / „Capture quickly – no window“.
  4. 18–27 s Zauberstab im Panel → Menü (Aufräumen, Als Mail, …) → „Als Mail“ → dezenter
     Fortschritt → Text wird zur Mail (Anrede, Absätze, Gruß); Balken „Als Mail umgeschrieben ·
     Rückgängig“. Unterschrift „Umarbeiten mit deinem Textmodell“ / „Rework with your text model“.
  5. 27–34 s Tastenkappe ⌘⏎ → Panel blendet aus, der formatierte Text erscheint im Mail-Fenster.
     Unterschrift „⌘⏎ legt formatiert in die App davor ab“ / „⌘⏎ sends it, formatted, to the app you came from“.
  6. 34–40 s Ordneransicht mit `Ideen Team-Meeting.md`, `Eingang.md`; daneben dieselbe Notiz in
     einer Obsidian-artigen Ansicht. Unterschrift „Jede Notiz ist eine Markdown-Datei – in iCloud oder
     Obsidian“ / „Every note is a Markdown file – in iCloud or Obsidian“. Schlusskarte mit den drei Tasten.
- **Ton** per WebAudio synthetisiert: weicher Tastenklick bei jeder Tastenkappe, kurzer Zweiklang beim
  Start des Diktats, „Ping“ beim Ablegen, leiser Abschluss. `setMuted(true)` schaltet sofort stumm,
  `setMuted(false)` setzt ab der aktuellen Stelle ein. `renderAudio()` erzeugt dieselbe Spur per
  `OfflineAudioContext`.
- **Bewegung:** ruhig, `ease`-Kurven, keine Wackler; Tastenkappen erscheinen unten links groß.
- `?autoplay=0` zeigt das erste Bild (Titel) und spielt nicht.

**Renderer** `Support/explainer-video/render.mjs`: wie `Support/launch-video/render.mjs`
(Chromium aus dem Playwright-Cache oder `CHROME=`, ffmpeg), aber für
`../../Resources/Explainers/scratchpad.html?export&lang=<de|en>&muted=0`; Ausgabe
`out/scratchpad-<lang>.mp4` (1600 × 1000, 30 fps, H.264 CRF 18, AAC). Optionen `--lang de|en`,
`--fps`, `--stills 1,7,15,22,30,37` → JPEGs nach `stills/`. `package.json` mit `playwright-core`
als devDependency und Skripten `render`, `stills`.

- [ ] **Schritt 1:** `cd Support/explainer-video && npm install` (holt nur `playwright-core`).
- [ ] **Schritt 2:** Animation schreiben.
- [ ] **Schritt 3: Einzelbilder prüfen** — `node render.mjs --stills 1,5,9,14,20,24,30,37 --lang de` und
  `--lang en`; **jedes Bild ansehen** (Read-Werkzeug auf die JPEGs): Text lesbar, nichts abgeschnitten,
  Umlaute korrekt, Szenen wie beschrieben. Keine Seitenfehler in der Konsole.
- [ ] **Schritt 4: MP4** — `node render.mjs --lang de` und `--lang en`; `ffprobe` zeigt ~40 s,
  1600 × 1000, Video + Audio.
- [ ] **Schritt 5:** `ChangelogRepoTests` grün (die echte Animation existiert).
- [ ] **Schritt 6: Commit** (ohne `node_modules`, `out`, `stills`):

```bash
cd /Users/liam/Developer/LIAM/flow-lokal && git add Resources/Explainers/scratchpad.html Support/explainer-video/package.json Support/explainer-video/package-lock.json Support/explainer-video/render.mjs Support/explainer-video/.gitignore && git commit -m "Neuigkeiten: Erklär-Animation zum Scratchpad, als MP4 renderbar" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Aufgabe 5: Player und Seite „Neuigkeiten“

**Dateien:** Neu `Sources/FlowLokal/ExplainerView.swift`, `Sources/FlowLokal/NewsView.swift`;
Ändern `Sources/FlowLokal/DashboardView.swift`, `Sources/FlowLokal/AppDelegate.swift`,
`Sources/FlowLokal/Localization.swift`, `Tests/ShoutTests/LocalizationNotesTests.swift`.

**Schnittstellen:**
- Verbraucht: `ChangelogEntry`, `ChangelogParser.loadBundled()`, die JS-Schnittstelle aus Aufgabe 4.
- Erzeugt:
  - `@MainActor final class ExplainerController: NSObject, ObservableObject` mit
    `init?(name: String, german: Bool, keys: [String], autoplay: Bool)` (nil, wenn die Datei fehlt),
    `@Published private(set) var isPlaying, isMuted, ended: Bool`, `let webView: WKWebView`,
    `togglePlay()`, `restart()`, `toggleMute()`, `static func url(for name: String) -> URL?`.
  - `struct ExplainerView: View { init(controller: ExplainerController) }` — Bühne 16:10 + native Leiste.
  - `struct ChangelogText: View { init(_ markdown: String) }` — Absätze und `- `-Listen, inline-Markdown.
  - `struct NewsView: View { init(entries: [ChangelogEntry], keys: [String]) }`.
  - `DashboardModel.Tab.neuigkeiten`; `DashboardView`-Parameter `changelog: [ChangelogEntry]`,
    `explainerKeys: [String]`.
  - `AppDelegate.changelog: [ChangelogEntry]` (lazy, `ChangelogParser.loadBundled() ?? []`),
    `AppDelegate.explainerKeys: [String]` (Anzeige der aktuellen Scratchpad- und Eingangs-Taste, leerer
    String für „Keine“).

**Vorgaben:**
- `WKWebView` mit `loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())`;
  URL-Parameter wie in Aufgabe 4 (`lang`, `muted=1`, `autoplay`, `keys`). Konfiguration:
  `mediaTypesRequiringUserActionForPlayback = []`, Hintergrund transparent (`setValue(false, forKey: "drawsBackground")`).
- `WKNavigationDelegate`: nur `file`-URLs innerhalb des Explainers-Ordners zulassen, alles andere `.cancel`.
  Lädt die Seite nicht (`didFail…`), setzt der Controller `failed = true`; die Ansicht blendet den Player dann aus.
- `WKScriptMessageHandler` über einen schwachen Proxy (sonst hält `userContentController` den Controller fest);
  Meldungen `state` und `ended` setzen die `@Published`-Werte.
- Leiste: Abspielen/Pause (`play.fill`/`pause.fill`), Neustart (`arrow.counterclockwise`),
  Ton (`speaker.slash.fill`/`speaker.wave.2.fill`), jeweils mit `.help(Loc.t(…))`. Aufrufe per
  `evaluateJavaScript("window.explainer.play()")` usw.
- „Bewegung reduzieren“ (`NSWorkspace.shared.accessibilityDisplayShouldReduceMotion`) → `autoplay=0`.
- `ChangelogText`: Text an Leerzeilen in Absätze teilen; Zeilen mit `- ` als Liste mit „•“; jeder
  Textteil per `AttributedString(markdown:options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))`
  (bei Fehler Klartext). Schrift wie die übrigen Seiten (12–13 pt, `Color(white: 0.85)`).
- `NewsView`: Kopf „Neuigkeiten“, dann je Eintrag Version (fett) · Datum (gedämpft), `ChangelogText` in der
  Sprache von `Loc.isGerman`, bei Video ein Knopf „Video ansehen“ → `.sheet` mit `ExplainerView` (720 breit)
  und „Schließen“. Leere Liste → „Keine Neuigkeiten gefunden.“
- Seitenleiste: `navRow(.neuigkeiten, Loc.t("Neuigkeiten"), "sparkles")` als letzter Eintrag; `case .neuigkeiten:`
  → `NewsView(entries: changelog, keys: explainerKeys)`. Alle `switch` über `Tab` ergänzen.
- `AppDelegate`: `changelog` und `explainerKeys` an `DashboardView(…)` übergeben; Menüpunkt
  „Neuigkeiten …“ im App-Menü (bei „Über shout.“) → `openDashboard(.neuigkeiten)`.
- Texte (vorher `grep`): „Neuigkeiten“ → „What’s New“, „Neuigkeiten …“ → „What’s New…“,
  „Video ansehen“ → „Watch video“, „Keine Neuigkeiten gefunden.“ → „No news found.“,
  „Abspielen“ → „Play“, „Pause“ (gleichlautend, nicht in die Testliste), „Neu starten“ → „Restart“,
  „Ton an“ → „Sound on“, „Ton aus“ → „Sound off“, „Schließen“ (existiert womöglich).

- [ ] **Schritt 1:** Umsetzen wie oben.
- [ ] **Schritt 2:** ganze Suite, Kompilierlauf, Duplikat-Prüfung leer.
- [ ] **Schritt 3: Commit** (genannte Pfade).

---

### Aufgabe 6: Fenster „Neu in shout.“ und Auslöser

**Dateien:** Neu `Sources/FlowLokal/WhatsNewView.swift`; Ändern `Sources/FlowLokal/AppDelegate.swift`,
`Sources/FlowLokal/Localization.swift`, `Tests/ShoutTests/LocalizationNotesTests.swift`.

**Schnittstellen:**
- Verbraucht: `WhatsNewDecider`, `WhatsNewState`, `AppVersion.running` (Aufgabe 2), `ExplainerController`,
  `ExplainerView`, `ChangelogText` (Aufgabe 5), `AppDelegate.changelog`, `explainerKeys`.
- Erzeugt: `struct WhatsNewView: View { init(entries: [ChangelogEntry], keys: [String], onClose: @escaping () -> Void) }`;
  `AppDelegate.showWhatsNewIfNeeded()`.

**Vorgaben:**
- `WhatsNewView`: Seite je Eintrag (neueste zuerst), Kopf `Loc.f("Neu in shout. %@", version)`, darunter
  `ExplainerView` (falls `video` und die Datei existiert; neuer Controller je Seite, Autoplay außer bei
  „Bewegung reduzieren“), darunter `ChangelogText` in einer `ScrollView`. Unten links „Überspringen“
  (`.keyboardShortcut(.cancelAction)`, ruft `onClose`), rechts „Weiter“ (nächste Seite) bzw. auf der
  letzten Seite „Fertig“ (`.keyboardShortcut(.defaultAction)`, ruft `onClose`). Stil wie das Onboarding
  (`Color.shoutWindow`, `ConsoleButtonStyle`).
- Fenster wie `openOnboarding()`: titelloses `NSWindow` (`.titled, .closable, .fullSizeContentView`),
  760 × 580, mittig, `isReleasedWhenClosed = false`, Delegat: `windowWillClose` → wie „Überspringen“.
  `NSApp.activate(ignoringOtherApps: true)` beim Zeigen.
- `onClose` (einmal): `WhatsNewState().markSeen(current)`, Fenster schließen und vergessen.
- `showWhatsNewIfNeeded()`:
  1. `guard let current = AppVersion.running` sonst nichts tun (Zustand unverändert).
  2. `guard onboardingWindow == nil`, `guard whatsNewWindow == nil`.
  3. Läuft eine Aufnahme oder Verarbeitung (`state != .idle`): `whatsNewPending = true`, zurück.
  4. `let zeigen = WhatsNewDecider.entriesToShow(all: changelog, lastSeen: WhatsNewState().lastSeen, current: current, onboardingDone: UserDefaults.standard.bool(forKey: "didCompleteOnboarding"))`.
  5. Leer → `WhatsNewState().markSeen(current)` (nur wenn das Onboarding erledigt ist), fertig. Sonst Fenster öffnen.
- Auslöser: in `applicationDidFinishLaunching` nach der Onboarding-Entscheidung
  `DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in self?.showWhatsNewIfNeeded() }`.
  Wo `state` wieder `.idle` wird (nach Zustellung, Abbruch, Fehler — die Stelle(n) suchen): `if whatsNewPending { whatsNewPending = false; showWhatsNewIfNeeded() }`.
- `finishOnboarding`: zusätzlich `if let v = AppVersion.running { WhatsNewState().markSeen(v) }`.
- Texte (vorher `grep`): „Neu in shout. %@“ → „New in shout. %@“, „Überspringen“ → „Skip“, „Weiter“ → „Next“,
  „Fertig“ → „Done“ (die drei letzten gibt es womöglich schon aus dem Onboarding).

- [ ] **Schritt 1:** Umsetzen.
- [ ] **Schritt 2:** ganze Suite, Kompilierlauf, Duplikat-Prüfung leer.
- [ ] **Schritt 3: Commit** (genannte Pfade).

---

### Aufgabe 7: Offene Punkte und Prüfliste

**Dateien:** `OFFEN.md`

- [ ] **Schritt 1:** In `OFFEN.md` eintragen:
  - `- [ ] **Neuigkeiten am Gerät prüfen** — Fenster „Neu in shout.“ nach dem nächsten Update (einmal, überspringbar), Seite „Neuigkeiten“, Animation mit Ton, Englisch. Plan: `docs/superpowers/plans/2026-10-07-neuigkeiten.md`.`
  - `- [ ] **Neuigkeiten für iOS und Windows** — eigene Versionsnummern und Auslieferwege; `CHANGELOG.md` gilt bisher nur für den Mac.`
- [ ] **Schritt 2: Commit** `git add OFFEN.md && git commit -m "OFFEN: Neuigkeiten" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"`
- [ ] **Schritt 3: Prüfliste (nach dem nächsten Release, nicht selbst ausführen)**
  - [ ] Update von 1.13.0 auf die neue Version: das Fenster erscheint etwa 2 s nach dem Start, zeigt
        die Scratchpad-Animation stumm und den Text; „Überspringen“ schließt; nach einem Neustart kommt es nicht wieder.
  - [ ] Ton an: Klicks und „Ping“ hörbar; Pause/Neustart funktionieren; am Ende bleibt das letzte Bild stehen.
  - [ ] Seite „Neuigkeiten“: alle Versionen, „Video ansehen“ öffnet den Player.
  - [ ] Englische Oberfläche: Fenster, Seite und Animation englisch.
  - [ ] „Bewegung reduzieren“ an: Animation startet nicht von selbst.
  - [ ] Während eines Diktats starten (Aufnahme läuft): Fenster erst danach.
  - [ ] Eigene Tasten eingestellt: die Animation zeigt sie.
  - [ ] Nach dem Update sofort in einer anderen App tippen: das Fenster wartet, bis 3 s nicht getippt wurde; ein ⏎ in der ersten Sekunde schließt es nicht.
  - [ ] Esc und ⏎, während der Player (Web-Ansicht) den Fokus hat: Esc überspringt, ⏎ geht weiter.
