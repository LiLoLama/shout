# Datei-Transkription (macOS) — Umsetzungsplan

> **Für agentische Bearbeiter:** ERFORDERLICHE UNTER-SKILL: `superpowers:subagent-driven-development` (empfohlen) oder `superpowers:executing-plans`, um diesen Plan Aufgabe für Aufgabe umzusetzen. Die Schritte nutzen Checkbox-Syntax (`- [ ]`) zur Nachverfolgung.

**Ziel:** Audio- und Videodateien in shout. auf macOS lokal transkribieren — Ergebnis im Fenster anzeigen, als `.txt` und als Untertitel (`.srt`) sichern.

**Architektur:** Eine neue Seite „Dateien" im Dashboard füttert eine serielle Warteschlange. Pro Datei liest ein `MediaDecoder` (actor, `AVAssetReader`) die Tonspur in ~2-Minuten-Blöcken zu 16 kHz Mono; jeder Block geht durch den vorhandenen `Transcriber` und liefert Segmente mit Zeitmarken. Aus den Rohsegmenten entsteht die `.srt`, aus dem verbundenen Text optional über abschnittsweise LLM-Aufbereitung der angezeigte Text.

**Tech-Stack:** Swift 5.10, SwiftUI, AVFoundation, WhisperKit (ASR), MLX/Gemma (Aufbereitung), XcodeGen + xcodebuild, XCTest.

**Spezifikation:** `docs/superpowers/specs/2026-08-02-datei-transkription-design.md`

## Globale Randbedingungen

- **Sprache im Code:** Kommentare und Dokumentation auf Deutsch, mit echten Umlauten (ä, ö, ü, Ä, Ö, Ü, ß) — nie ASCII-Ersatz.
- **Oberflächentexte** laufen ausnahmslos über `Loc.t(...)` / `Loc.f(...)`. Der **deutsche Text ist der Schlüssel**; jeder neue Schlüssel bekommt einen Eintrag in `Localization.swift` unter `english`. Doppelte Schlüssel im Dictionary sind ein Compilerfehler — vor dem Einfügen prüfen, ob der Schlüssel schon existiert. Typografische Anführungszeichen („…") im Schlüssel müssen zwischen Aufruf und Dictionary **zeichengleich** sein, sonst fällt der Eintrag still auf Deutsch zurück.
- **Plattform:** macOS 14+, nur Apple Silicon (`ARCHS: arm64`). Diese Umsetzung betrifft ausschließlich das Target `FlowLokal`. Windows und iOS bleiben unangetastet.
- **Neue UserDefaults-Schlüssel:** `fileFormattingEnabled` (Standard `true`), `fileSpeechCommandsEnabled` (Standard `false`). Die Diktat-Schlüssel `formattingEnabled` und `speechCommandsEnabled` werden **nicht** wiederverwendet.
- **Kein Debug-Build starten.** `./build.sh Debug` ist die Kompilier-Prüfung; die gebaute App nicht mit `open` starten (zwei Instanzen registrieren dieselben globalen Hotkeys). Auslieferung an den Nutzer läuft über ein echtes Release.
- **Keine neuen Abhängigkeiten.** Kein FFmpeg, keine neuen SwiftPM-Pakete.
- **Datenfluss:** Nichts wird automatisch auf die Platte geschrieben. `DictationHistory` und `StatsStore` werden von dieser Funktion **nicht** angefasst.
- **Farben/Bausteine:** `Color.shoutLive`, `Color.shoutWindow`, `ConsolePanel`, `FieldRow`, `ConsoleDivider`, `ConsoleButtonStyle`, `Keycap` aus `ConsoleUI.swift` wiederverwenden — keine neuen Design-Bausteine erfinden.

## Dateiübersicht

**Neu:**

| Datei | Verantwortung |
|---|---|
| `Sources/FlowLokal/TranscriptSegment.swift` | Wertetyp: Text + Start/Ende in Sekunden. Ohne WhisperKit-Abhängigkeit. |
| `Sources/FlowLokal/SubtitleWriter.swift` | Segmente → SRT-Text. Reine Funktionen. |
| `Sources/FlowLokal/TextChunker.swift` | Text an Satzgrenzen in Abschnitte teilen. Reine Funktionen. |
| `Sources/FlowLokal/MediaDecoder.swift` | `actor`: Datei → Folge von 16-kHz-Mono-Blöcken. |
| `Sources/FlowLokal/FileTranscriptionQueue.swift` | Auftrag + serielle Warteschlange (`FileTranscriptionJob`, `FileTranscriptionQueue`). |
| `Sources/FlowLokal/FilesView.swift` | Die Seite „Dateien". |
| `Tests/ShoutTests/SubtitleWriterTests.swift` | Tests für `SubtitleWriter`. |
| `Tests/ShoutTests/TextChunkerTests.swift` | Tests für `TextChunker`. |
| `Tests/ShoutTests/MediaDecoderTests.swift` | Tests für `MediaDecoder`. |

**Geändert:** `Sources/FlowLokal/Transcriber.swift`, `Sources/FlowLokal/Formatter.swift`, `Sources/FlowLokal/DashboardView.swift`, `Sources/FlowLokal/AppDelegate.swift`, `Sources/FlowLokal/Localization.swift`, `project.yml`, `README.md`, `OFFEN.md`.

## Abweichungen von der Spezifikation

Zwei Präzisierungen, die sich beim Ausformulieren ergeben haben — die Spezifikation wird in Aufgabe 8 entsprechend nachgezogen:

1. **`TranscriptSegment` ist ein eigener Typ auf oberster Ebene**, nicht `Transcriber.Segment`. Sonst könnten `SubtitleWriter` und die Tests nicht ohne WhisperKit kompiliert werden — und genau das macht das schlanke Test-Target erst möglich.
2. **`MediaDecoder` ist ein `actor` mit Pull-Schnittstelle** (`open()` / `next()`) statt einer Callback-Schleife. Die Arbeit läuft dadurch garantiert außerhalb des Main-Actors, ohne dass Closures über Actor-Grenzen gereicht werden müssen.
3. **Der Schnitt an der leisesten Stelle** findet immer ein Minimum (es gibt in jedem Suchfenster ein leisestes 0,5-s-Fenster). Der in der Spezifikation beschriebene „harte Schnitt bei 120 s" greift nur, wenn der Suchbereich leer ist.

---

### Aufgabe 1: Test-Target, `TranscriptSegment` und `SubtitleWriter`

Das Projekt hat bisher kein Test-Target. Diese Aufgabe legt es an und liefert als ersten Nutzen den SRT-Schreiber.

**Dateien:**
- Anlegen: `Sources/FlowLokal/TranscriptSegment.swift`
- Anlegen: `Sources/FlowLokal/SubtitleWriter.swift`
- Anlegen: `Tests/ShoutTests/SubtitleWriterTests.swift`
- Ändern: `project.yml` (neues Target `ShoutTests` + Schema)

**Schnittstellen:**
- Liefert: `struct TranscriptSegment: Sendable, Equatable { let text: String; let start: Double; let end: Double }` mit `func offset(by: Double) -> TranscriptSegment`
- Liefert: `enum SubtitleWriter` mit `static func srt(from: [TranscriptSegment]) -> String` und `static func timecode(_ seconds: Double) -> String`

- [ ] **Schritt 1: Test-Target in `project.yml` anlegen**

Ans Ende des `schemes:`-Blocks (nach dem `ShoutMobile`-Schema, vor `packages:`) einfügen:

```yaml
  ShoutTests:
    build:
      targets:
        ShoutTests: [test]
    test:
      config: Debug
      targets:
        - ShoutTests
```

Ans Ende der Datei (nach dem `ShoutKeyboard`-Target) anfügen:

```yaml
  # Reine Logik-Tests: kompiliert NUR die abhängigkeitsfreien Dateien mit, damit
  # die Tests ohne WhisperKit/MLX in Sekunden laufen (und ohne Host-App).
  ShoutTests:
    type: bundle.unit-test
    platform: macOS
    sources:
      - path: Tests/ShoutTests
      - path: Sources/FlowLokal/TranscriptSegment.swift
      - path: Sources/FlowLokal/SubtitleWriter.swift
      - path: Sources/FlowLokal/TextChunker.swift
      - path: Sources/FlowLokal/MediaDecoder.swift
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: com.inthezone.shout.tests
        PRODUCT_NAME: ShoutTests
        GENERATE_INFOPLIST_FILE: YES
        ARCHS: arm64
        ONLY_ACTIVE_ARCH: NO
        SWIFT_VERSION: "5.10"
        CODE_SIGN_IDENTITY: "-"
        CODE_SIGN_STYLE: Manual
```

`TextChunker.swift` und `MediaDecoder.swift` stehen hier schon drin, obwohl sie erst in Aufgabe 2 und 3 entstehen — deshalb legt Schritt 2 sie sofort als leere Hüllen an, sonst schlägt `xcodegen generate` fehl.

- [ ] **Schritt 2: Platzhalter für die späteren Aufgaben anlegen**

`Sources/FlowLokal/TextChunker.swift`:

```swift
import Foundation

/// Wird in Aufgabe 2 gefüllt.
enum TextChunker {}
```

`Sources/FlowLokal/MediaDecoder.swift`:

```swift
import Foundation

/// Wird in Aufgabe 3 gefüllt.
enum MediaDecoderPlaceholder {}
```

- [ ] **Schritt 3: `TranscriptSegment` anlegen**

`Sources/FlowLokal/TranscriptSegment.swift`:

```swift
import Foundation

/// Ein Abschnitt eines Transkripts mit Zeitmarken in Sekunden ab Dateibeginn.
///
/// Bewusst ein eigener Typ statt WhisperKits `TranscriptionSegment`: So kommen
/// `SubtitleWriter` und die Tests ohne den Modell-Stack aus, und die Zeitmarken
/// lassen sich beim blockweisen Lesen verschieben, ohne WhisperKit-Typen zu kopieren.
struct TranscriptSegment: Sendable, Equatable {
    let text: String
    let start: Double
    let end: Double

    /// Verschiebt die Zeitmarken um den Startzeitpunkt des Blocks, aus dem das
    /// Segment stammt — aus „Sekunde 3 im Block" wird „Sekunde 123 in der Datei".
    func offset(by seconds: Double) -> TranscriptSegment {
        TranscriptSegment(text: text, start: start + seconds, end: end + seconds)
    }
}
```

- [ ] **Schritt 4: Den fehlschlagenden Test schreiben**

`Tests/ShoutTests/SubtitleWriterTests.swift`:

```swift
import XCTest

final class SubtitleWriterTests: XCTestCase {

    // MARK: - Zeitmarken

    func testZeitmarkeAmAnfang() {
        XCTAssertEqual(SubtitleWriter.timecode(0), "00:00:00,000")
    }

    func testZeitmarkeMitMillisekunden() {
        XCTAssertEqual(SubtitleWriter.timecode(83.456), "00:01:23,456")
    }

    func testZeitmarkeUeberEineStunde() {
        XCTAssertEqual(SubtitleWriter.timecode(3661.5), "01:01:01,500")
    }

    /// Negative Werte dürfen kein „-00:00:01" erzeugen — das liest kein Abspieler.
    func testZeitmarkeNegativWirdAufNullGeklemmt() {
        XCTAssertEqual(SubtitleWriter.timecode(-2), "00:00:00,000")
    }

    // MARK: - SRT

    func testSrtNummeriertUndTrenntMitLeerzeile() {
        let segments = [
            TranscriptSegment(text: "Erster Satz.", start: 0, end: 1.5),
            TranscriptSegment(text: "Zweiter Satz.", start: 1.5, end: 3),
        ]
        let expected = """
        1
        00:00:00,000 --> 00:00:01,500
        Erster Satz.

        2
        00:00:01,500 --> 00:00:03,000
        Zweiter Satz.


        """
        XCTAssertEqual(SubtitleWriter.srt(from: segments), expected)
    }

    /// Leere Segmente kommen von Whisper regelmäßig (Stille). Sie fliegen raus,
    /// die Nummerierung bleibt trotzdem lückenlos.
    func testSrtUeberspringtLeereSegmenteOhneLuecke() {
        let segments = [
            TranscriptSegment(text: "Eins", start: 0, end: 1),
            TranscriptSegment(text: "   ", start: 1, end: 2),
            TranscriptSegment(text: "Zwei", start: 2, end: 3),
        ]
        let srt = SubtitleWriter.srt(from: segments)
        XCTAssertTrue(srt.contains("1\n00:00:00,000 --> 00:00:01,000\nEins"))
        XCTAssertTrue(srt.contains("2\n00:00:02,000 --> 00:00:03,000\nZwei"))
        XCTAssertFalse(srt.contains("3"))
    }

    func testSrtOhneSegmenteIstLeer() {
        XCTAssertEqual(SubtitleWriter.srt(from: []), "")
    }

    /// Whisper liefert gelegentlich ein Ende vor dem Anfang. Ein rückwärts
    /// laufender Zeitbereich bringt Abspieler durcheinander.
    func testSrtKlemmtEndeAufMindestensStart() {
        let segments = [TranscriptSegment(text: "Kaputt", start: 5, end: 3)]
        XCTAssertTrue(SubtitleWriter.srt(from: segments).contains("00:00:05,000 --> 00:00:05,000"))
    }

    // MARK: - Zeitversatz

    func testOffsetVerschiebtBeideZeitmarken() {
        let segment = TranscriptSegment(text: "Text", start: 1, end: 2).offset(by: 120)
        XCTAssertEqual(segment, TranscriptSegment(text: "Text", start: 121, end: 122))
    }
}
```

- [ ] **Schritt 5: Test laufen lassen und Fehlschlag prüfen**

```bash
cd /Users/liam/Developer/LIAM/flow-lokal && xcodegen generate && xcodebuild test -project FlowLokal.xcodeproj -scheme ShoutTests -destination 'platform=macOS,arch=arm64' -skipPackagePluginValidation -skipMacroValidation 2>&1 | tail -25
```

Erwartet: Kompilierfehler „cannot find 'SubtitleWriter' in scope".

- [ ] **Schritt 6: `SubtitleWriter` schreiben**

`Sources/FlowLokal/SubtitleWriter.swift`:

```swift
import Foundation

/// Schreibt Transkript-Abschnitte als SubRip-Untertitel (.srt).
///
/// Die Untertitel entstehen IMMER aus dem Rohtranskript. Sobald das Formatierungs-
/// Modell Füllwörter entfernt und Sätze umbaut, passt der Wortlaut nicht mehr zu
/// den Zeitmarken — dann wären die Untertitel schlicht falsch.
enum SubtitleWriter {

    /// SRT-Text für die Segmente. Leere Segmente werden übersprungen; die
    /// Nummerierung bleibt trotzdem lückenlos, weil manche Abspieler bei Lücken
    /// die restliche Datei verwerfen.
    static func srt(from segments: [TranscriptSegment]) -> String {
        var out = ""
        var index = 1
        for segment in segments {
            let text = segment.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { continue }
            out += "\(index)\n"
            out += "\(timecode(segment.start)) --> \(timecode(max(segment.end, segment.start)))\n"
            out += "\(text)\n\n"
            index += 1
        }
        return out
    }

    /// „HH:MM:SS,mmm" — Millisekunden mit Komma, wie SubRip es verlangt (ein
    /// Punkt statt des Kommas ist der häufigste Grund, warum eine .srt stumm bleibt).
    static func timecode(_ seconds: Double) -> String {
        let totalMs = Int((max(0, seconds) * 1000).rounded())
        let ms = totalMs % 1000
        let total = totalMs / 1000
        return String(format: "%02d:%02d:%02d,%03d", total / 3600, (total % 3600) / 60, total % 60, ms)
    }
}
```

- [ ] **Schritt 7: Tests laufen lassen und Erfolg prüfen**

```bash
cd /Users/liam/Developer/LIAM/flow-lokal && xcodebuild test -project FlowLokal.xcodeproj -scheme ShoutTests -destination 'platform=macOS,arch=arm64' -skipPackagePluginValidation -skipMacroValidation 2>&1 | tail -15
```

Erwartet: `** TEST SUCCEEDED **`, 8 Tests bestanden.

- [ ] **Schritt 8: Commit**

```bash
cd /Users/liam/Developer/LIAM/flow-lokal && git add project.yml Sources/FlowLokal/TranscriptSegment.swift Sources/FlowLokal/SubtitleWriter.swift Sources/FlowLokal/TextChunker.swift Sources/FlowLokal/MediaDecoder.swift Tests/ShoutTests/SubtitleWriterTests.swift && git commit -m "Test-Target und SRT-Schreiber

Erstes Test-Target im Projekt: kompiliert nur die abhängigkeitsfreien
Dateien mit, läuft dadurch ohne WhisperKit/MLX in Sekunden."
```

---

### Aufgabe 2: `TextChunker`

Teilt langen Text in Abschnitte, die einzeln durchs Formatierungs-Modell passen.

**Dateien:**
- Ändern: `Sources/FlowLokal/TextChunker.swift` (Hülle aus Aufgabe 1 füllen)
- Anlegen: `Tests/ShoutTests/TextChunkerTests.swift`

**Schnittstellen:**
- Nutzt: nichts aus früheren Aufgaben
- Liefert: `TextChunker.chunks(of: String, targetLength: Int = 1500, minLength: Int = 1000) -> [String]`

- [ ] **Schritt 1: Den fehlschlagenden Test schreiben**

`Tests/ShoutTests/TextChunkerTests.swift`:

```swift
import XCTest

final class TextChunkerTests: XCTestCase {

    /// Baut Text aus gleich langen Sätzen, damit die Länge vorhersagbar ist.
    private func saetze(_ count: Int) -> String {
        (1...count).map { "Das ist der Satz Nummer \($0) in diesem Text." }.joined(separator: " ")
    }

    func testLeererTextGibtLeeresErgebnis() {
        XCTAssertEqual(TextChunker.chunks(of: ""), [])
        XCTAssertEqual(TextChunker.chunks(of: "   \n  "), [])
    }

    func testKurzerTextBleibtEinAbschnitt() {
        let text = "Ein kurzer Satz."
        XCTAssertEqual(TextChunker.chunks(of: text), [text])
    }

    func testLangerTextWirdGeteilt() {
        let text = saetze(200)   // deutlich über 1500 Zeichen
        let parts = TextChunker.chunks(of: text)
        XCTAssertGreaterThan(parts.count, 1)
    }

    /// Der Inhalt darf beim Teilen nicht verloren gehen — Wortfolge bleibt gleich.
    func testTeilungVerliertKeinenInhalt() {
        let text = saetze(200)
        let parts = TextChunker.chunks(of: text)
        XCTAssertEqual(parts.joined(separator: " ").split(separator: " "),
                       text.split(separator: " "))
    }

    func testAbschnitteEndenAufSatzzeichen() {
        let parts = TextChunker.chunks(of: saetze(200))
        for part in parts.dropLast() {
            XCTAssertTrue(part.hasSuffix(".") || part.hasSuffix("!") || part.hasSuffix("?"),
                          "Abschnitt endet mitten im Satz: …\(part.suffix(40))")
        }
    }

    /// Ohne jedes Satzzeichen darf die Teilung nicht in eine Endlosschleife laufen,
    /// sondern schneidet hart am Zielmaß.
    func testTextOhneSatzzeichenWirdHartGeteilt() {
        let text = String(repeating: "wort ", count: 1000)
        let parts = TextChunker.chunks(of: text, targetLength: 200, minLength: 120)
        XCTAssertGreaterThan(parts.count, 1)
        for part in parts { XCTAssertLessThanOrEqual(part.count, 200) }
    }

    /// „z. B." ist kein Satzende. Ein Fehlschnitt dort ist zwar harmlos (er ändert
    /// keinen Wortlaut), setzt aber einen Absatz mitten in den Satz.
    func testAbkuerzungGiltNichtAlsSatzende() {
        let vorne = String(repeating: "Fülltext hier. ", count: 8)   // ~120 Zeichen
        let text = vorne + "Wir nehmen z. B. Das hier ist ein Test und es geht weiter."
        let parts = TextChunker.chunks(of: text, targetLength: 150, minLength: 100)
        XCTAssertFalse(parts.contains { $0.hasSuffix("z. B.") },
                       "Abschnitt endet auf einer Abkürzung: \(parts)")
    }

    func testEinzelneGrosseAbkuerzungWirdErkannt() {
        let vorne = String(repeating: "Fülltext hier. ", count: 8)
        let text = vorne + "Wir treffen Dr. Meier und dann fahren wir gemeinsam weiter."
        let parts = TextChunker.chunks(of: text, targetLength: 150, minLength: 100)
        XCTAssertFalse(parts.contains { $0.hasSuffix("Dr.") })
    }
}
```

- [ ] **Schritt 2: Test laufen lassen und Fehlschlag prüfen**

```bash
cd /Users/liam/Developer/LIAM/flow-lokal && xcodebuild test -project FlowLokal.xcodeproj -scheme ShoutTests -destination 'platform=macOS,arch=arm64' -skipPackagePluginValidation -skipMacroValidation 2>&1 | tail -25
```

Erwartet: Kompilierfehler „type 'TextChunker' has no member 'chunks'".

- [ ] **Schritt 3: `TextChunker` schreiben**

`Sources/FlowLokal/TextChunker.swift` vollständig ersetzen:

```swift
import Foundation

/// Teilt langen Text in Abschnitte, die einzeln durchs Formatierungs-Modell passen.
///
/// Ein einstündiges Transkript in einem Rutsch ans Modell zu geben, sprengt das
/// Kontextfenster des kleinen quantisierten Modells. Geschnitten wird an
/// Satzgrenzen, damit die Aufbereitung nicht mitten im Satz neu ansetzt.
///
/// Die Satzgrenze ist eine Heuristik: „.!?" gefolgt von Leerraum und einem
/// Großbuchstaben, wobei bekannte Abkürzungen und einzelne Buchstaben davor
/// ausgeschlossen sind („z. B.", „Dr."). Sie kann danebenliegen — schlimmstenfalls
/// steht ein Absatzumbruch an einer unschönen Stelle. Am Wortlaut ändert sich nichts.
enum TextChunker {

    /// Wörter, nach denen ein Punkt kein Satzende ist. Einzelne Buchstaben werden
    /// separat behandelt (deckt „z. B.", „u. a." und Initialen ab).
    private static let abbreviations: Set<String> = [
        "ca", "bzw", "usw", "etc", "vgl", "ggf", "inkl", "evtl", "sog", "bspw",
        "dr", "prof", "nr", "abb", "bzgl", "mr", "mrs", "st", "vs", "approx"
    ]

    /// Zerlegt den Text. Abschnitte werden so nah wie möglich am Zielmaß
    /// geschnitten, aber nie kürzer als `minLength` — sonst zerfiele ein Text mit
    /// vielen kurzen Sätzen in lauter Schnipsel.
    static func chunks(of text: String, targetLength: Int = 1500, minLength: Int = 1000) -> [String] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        guard trimmed.count > targetLength else { return [trimmed] }

        var result: [String] = []
        var rest = Substring(trimmed)
        while rest.count > targetLength {
            let limit = rest.index(rest.startIndex, offsetBy: targetLength)
            let floor = rest.index(rest.startIndex, offsetBy: min(minLength, targetLength))
            let cut = sentenceBreak(in: rest, before: limit, notBefore: floor) ?? limit
            let piece = rest[rest.startIndex..<cut].trimmingCharacters(in: .whitespacesAndNewlines)
            if !piece.isEmpty { result.append(piece) }
            rest = rest[cut...]
        }
        let tail = rest.trimmingCharacters(in: .whitespacesAndNewlines)
        if !tail.isEmpty { result.append(tail) }
        return result
    }

    /// Letzte Satzgrenze im Bereich [notBefore, before). Zurück kommt der Index des
    /// ersten Zeichens des FOLGENDEN Satzes — der Leerraum dazwischen fällt weg.
    private static func sentenceBreak(in text: Substring, before limit: Substring.Index,
                                      notBefore floor: Substring.Index) -> Substring.Index? {
        var i = limit
        while i > floor {
            i = text.index(before: i)
            guard ".!?".contains(text[i]) else { continue }
            guard !isAbbreviation(in: text, periodAt: i) else { continue }
            var j = text.index(after: i)
            guard j < text.endIndex, text[j].isWhitespace else { continue }
            while j < text.endIndex, text[j].isWhitespace { j = text.index(after: j) }
            guard j < text.endIndex, text[j].isUppercase else { continue }
            return j
        }
        return nil
    }

    /// Prüft das Wort unmittelbar vor dem Punkt. Ein einzelner Buchstabe („z.", „B.")
    /// oder eine bekannte Abkürzung („Dr.") beendet keinen Satz.
    private static func isAbbreviation(in text: Substring, periodAt index: Substring.Index) -> Bool {
        guard text[index] == "." else { return false }
        var start = index
        var word = ""
        while start > text.startIndex {
            let previous = text.index(before: start)
            guard text[previous].isLetter else { break }
            word.insert(text[previous], at: word.startIndex)
            start = previous
        }
        guard !word.isEmpty else { return false }
        return word.count == 1 || abbreviations.contains(word.lowercased())
    }
}
```

- [ ] **Schritt 4: Tests laufen lassen und Erfolg prüfen**

```bash
cd /Users/liam/Developer/LIAM/flow-lokal && xcodebuild test -project FlowLokal.xcodeproj -scheme ShoutTests -destination 'platform=macOS,arch=arm64' -skipPackagePluginValidation -skipMacroValidation 2>&1 | tail -15
```

Erwartet: `** TEST SUCCEEDED **`, 16 Tests bestanden.

- [ ] **Schritt 5: Commit**

```bash
cd /Users/liam/Developer/LIAM/flow-lokal && git add Sources/FlowLokal/TextChunker.swift Tests/ShoutTests/TextChunkerTests.swift && git commit -m "TextChunker: langen Text an Satzgrenzen teilen

Erkennt Satzenden über „.!?“ + Leerraum + Großbuchstabe und schließt
einzelne Buchstaben sowie bekannte Abkürzungen aus."
```

---

### Aufgabe 3: `MediaDecoder`

Liest Audio- und Videodateien blockweise als 16-kHz-Mono-Samples.

**Dateien:**
- Ändern: `Sources/FlowLokal/MediaDecoder.swift` (Hülle aus Aufgabe 1 ersetzen)
- Anlegen: `Tests/ShoutTests/MediaDecoderTests.swift`

**Schnittstellen:**
- Nutzt: nichts aus früheren Aufgaben
- Liefert:
  - `struct MediaBlock: Sendable { let samples: [Float]; let startTime: Double }`
  - `enum MediaDecoderError: LocalizedError { case noAudioTrack, unreadable(String) }`
  - `actor MediaDecoder`, `init(url: URL, blockSeconds: Double = 120, searchSeconds: Double = 30)`,
    `func open() async throws -> Double` (liefert die Dauer in Sekunden),
    `func next() throws -> MediaBlock?` (nil = fertig),
    `static func cutIndex(in: [Float], blockSamples: Int, searchSamples: Int, windowSamples: Int) -> Int`,
    `static let sampleRate: Double = 16_000`

- [ ] **Schritt 1: Den fehlschlagenden Test schreiben**

`Tests/ShoutTests/MediaDecoderTests.swift`:

```swift
import AVFoundation
import XCTest

final class MediaDecoderTests: XCTestCase {

    // MARK: - Hilfsmittel

    /// Schreibt eine WAV-Datei: Sinuston, unterbrochen von einer Stille-Lücke.
    /// `silence` ist der Bereich in Sekunden, der stumm bleibt.
    private func writeWAV(seconds: Double, sampleRate: Double = 44_100,
                          silence: ClosedRange<Double>? = nil) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("mediadecoder-\(UUID().uuidString).wav")
        let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: sampleRate,
                                   channels: 1, interleaved: false)!
        let file = try AVAudioFile(forWriting: url, settings: format.settings,
                                   commonFormat: .pcmFormatFloat32, interleaved: false)
        let total = AVAudioFrameCount(seconds * sampleRate)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: total)!
        buffer.frameLength = total
        let channel = buffer.floatChannelData![0]
        for frame in 0..<Int(total) {
            let t = Double(frame) / sampleRate
            let quiet = silence?.contains(t) ?? false
            channel[frame] = quiet ? 0 : Float(sin(2 * Double.pi * 440 * t)) * 0.5
        }
        try file.write(from: buffer)
        return url
    }

    // MARK: - Schnitt an der leisesten Stelle

    func testSchnittLandetInDerStilleLuecke() {
        // 10 Blöcke à 1000 Samples: laut, außer Block 8 (Index 8000…8999).
        var samples = [Float](repeating: 0.5, count: 10_000)
        for i in 8_000..<9_000 { samples[i] = 0 }
        let cut = MediaDecoder.cutIndex(in: samples, blockSamples: 10_000,
                                        searchSamples: 4_000, windowSamples: 1_000)
        XCTAssertGreaterThanOrEqual(cut, 8_000)
        XCTAssertLessThanOrEqual(cut, 9_500)
    }

    func testZuKurzerPufferWirdNichtGeschnitten() {
        let samples = [Float](repeating: 0.5, count: 500)
        XCTAssertEqual(MediaDecoder.cutIndex(in: samples, blockSamples: 10_000,
                                             searchSamples: 4_000, windowSamples: 1_000), 500)
    }

    func testSchnittLiegtImmerImSuchbereich() {
        let samples = [Float](repeating: 0.5, count: 10_000)   // gleichmäßig laut
        let cut = MediaDecoder.cutIndex(in: samples, blockSamples: 10_000,
                                        searchSamples: 4_000, windowSamples: 1_000)
        XCTAssertGreaterThanOrEqual(cut, 6_000)
        XCTAssertLessThanOrEqual(cut, 10_000)
    }

    // MARK: - Dekodieren

    func testDauerUndAbtastrate() async throws {
        let url = try writeWAV(seconds: 3)
        defer { try? FileManager.default.removeItem(at: url) }

        let decoder = MediaDecoder(url: url, blockSeconds: 10, searchSeconds: 1)
        let duration = try await decoder.open()
        XCTAssertEqual(duration, 3, accuracy: 0.1)

        var total = 0
        while let block = try await decoder.next() { total += block.samples.count }
        // 3 s bei 16 kHz — Umrechnung darf ein paar Puffer Toleranz haben.
        XCTAssertEqual(Double(total) / MediaDecoder.sampleRate, 3, accuracy: 0.2)
    }

    func testBlockgrenzenUndStartzeiten() async throws {
        let url = try writeWAV(seconds: 5)
        defer { try? FileManager.default.removeItem(at: url) }

        let decoder = MediaDecoder(url: url, blockSeconds: 1, searchSeconds: 0.25)
        _ = try await decoder.open()

        var blocks: [MediaBlock] = []
        while let block = try await decoder.next() { blocks.append(block) }

        XCTAssertGreaterThanOrEqual(blocks.count, 4, "5 s bei 1-s-Blöcken → mindestens 4 Blöcke")
        // Startzeiten laufen lückenlos: jede Startzeit = Summe der bisherigen Längen.
        var expected = 0.0
        for block in blocks {
            XCTAssertEqual(block.startTime, expected, accuracy: 0.001)
            expected += Double(block.samples.count) / MediaDecoder.sampleRate
        }
    }

    func testDateiOhneTonspurWirftFehler() async throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("kein-audio-\(UUID().uuidString).txt")
        try "kein Audio".write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }

        let decoder = MediaDecoder(url: url)
        do {
            _ = try await decoder.open()
            XCTFail("Erwartet: Fehler für eine Datei ohne Tonspur")
        } catch {
            // erwartet
        }
    }
}
```

- [ ] **Schritt 2: Test laufen lassen und Fehlschlag prüfen**

```bash
cd /Users/liam/Developer/LIAM/flow-lokal && xcodebuild test -project FlowLokal.xcodeproj -scheme ShoutTests -destination 'platform=macOS,arch=arm64' -skipPackagePluginValidation -skipMacroValidation 2>&1 | tail -25
```

Erwartet: Kompilierfehler „cannot find 'MediaDecoder' in scope".

- [ ] **Schritt 3: `MediaDecoder` schreiben**

`Sources/FlowLokal/MediaDecoder.swift` vollständig ersetzen:

```swift
import AVFoundation
import Foundation

/// Ein Block dekodierter Samples mit seiner Startzeit in der Datei.
struct MediaBlock: Sendable {
    let samples: [Float]
    let startTime: Double
}

/// Bewusst ohne `LocalizedError`: `Loc` ist an den Main-Actor gebunden, dieser
/// Fehler entsteht aber im Decoder-actor. Übersetzt wird erst dort, wo der Text
/// angezeigt wird (`FileTranscriptionQueue.message(for:)`).
enum MediaDecoderError: Error {
    case noAudioTrack
    case unreadable(String)
}

/// Liest eine Audio- oder Videodatei als Folge von 16-kHz-Mono-Blöcken.
///
/// Bewusst blockweise statt „ganze Datei in den Speicher": Eine Stunde Audio wären
/// 230 MB als `[Float]`, und WhisperKits eigene Zerlegung legt eine zweite Kopie
/// daneben. Wichtiger noch — der `Transcriber` ist ein actor, ein Diktat per Hotkey
/// muss also auf den laufenden Aufruf warten. Bei Blöcken von zwei Minuten sind das
/// Sekunden statt der ganzen Datei.
///
/// `AVAssetReader` statt `AVAudioFile`: nur so kommt auch die Tonspur aus
/// Videodateien (MP4, MOV) heraus.
actor MediaDecoder {

    static let sampleRate: Double = 16_000

    private let url: URL
    private let blockSamples: Int
    private let searchSamples: Int

    private var reader: AVAssetReader?
    private var output: AVAssetReaderTrackOutput?
    /// Noch nicht ausgegebene Samples (Rest des letzten Blocks + neu gelesene).
    private var pending: [Float] = []
    /// Bereits ausgegebene Samples — daraus entsteht die Startzeit des nächsten Blocks.
    private var emitted = 0
    private var finished = false

    init(url: URL, blockSeconds: Double = 120, searchSeconds: Double = 30) {
        self.url = url
        self.blockSamples = Int(blockSeconds * Self.sampleRate)
        self.searchSamples = Int(searchSeconds * Self.sampleRate)
    }

    /// Öffnet die Datei und liefert ihre Dauer in Sekunden.
    func open() async throws -> Double {
        let asset = AVURLAsset(url: url)
        let duration: Double
        do {
            duration = try await CMTimeGetSeconds(asset.load(.duration))
        } catch {
            throw MediaDecoderError.unreadable(error.localizedDescription)
        }
        let tracks: [AVAssetTrack]
        do {
            tracks = try await asset.loadTracks(withMediaType: .audio)
        } catch {
            throw MediaDecoderError.unreadable(error.localizedDescription)
        }
        guard let track = tracks.first else { throw MediaDecoderError.noAudioTrack }

        let reader: AVAssetReader
        do {
            reader = try AVAssetReader(asset: asset)
        } catch {
            throw MediaDecoderError.unreadable(error.localizedDescription)
        }
        // AVAssetReaderTrackOutput rechnet beim Lesen auf das Zielformat um —
        // Abtastrate, Kanalzahl und Float-Format in einem Schritt.
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: Self.sampleRate,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false,
        ]
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: settings)
        output.alwaysCopiesSampleData = false
        guard reader.canAdd(output) else {
            throw MediaDecoderError.unreadable("Format nicht unterstützt")
        }
        reader.add(output)
        guard reader.startReading() else {
            throw MediaDecoderError.unreadable(reader.error?.localizedDescription ?? "unbekannt")
        }
        self.reader = reader
        self.output = output
        return duration.isFinite ? max(0, duration) : 0
    }

    /// Nächster Block — `nil`, wenn die Datei zu Ende ist.
    func next() throws -> MediaBlock? {
        guard let reader, let output, !finished else { return nil }

        while pending.count < blockSamples, let buffer = output.copyNextSampleBuffer() {
            pending.append(contentsOf: Self.floats(from: buffer))
        }
        if reader.status == .failed {
            throw MediaDecoderError.unreadable(reader.error?.localizedDescription ?? "unbekannt")
        }

        guard !pending.isEmpty else { finished = true; return nil }

        let cut = pending.count >= blockSamples
            ? Self.cutIndex(in: pending, blockSamples: blockSamples,
                            searchSamples: searchSamples, windowSamples: Int(0.5 * Self.sampleRate))
            : pending.count
        let block = MediaBlock(samples: Array(pending[0..<cut]),
                               startTime: Double(emitted) / Self.sampleRate)
        emitted += cut
        pending.removeFirst(cut)
        if pending.isEmpty, reader.status == .completed { finished = true }
        return block
    }

    // MARK: - Rechnen

    /// Schnittstelle für einen vollen Block: die Mitte des leisesten Fensters im
    /// hinteren Bereich. So fällt die Blockgrenze auf eine Sprechpause statt mitten
    /// in ein Wort. Ist der Puffer kürzer als ein Block, wird gar nicht geschnitten.
    static func cutIndex(in samples: [Float], blockSamples: Int,
                         searchSamples: Int, windowSamples: Int) -> Int {
        guard samples.count >= blockSamples, windowSamples > 1 else { return samples.count }
        let searchStart = max(0, blockSamples - searchSamples)
        guard searchStart + windowSamples <= blockSamples else { return blockSamples }

        var bestIndex = -1
        var bestRMS = Float.greatestFiniteMagnitude
        var i = searchStart
        let step = max(1, windowSamples / 2)      // 50 % Überlappung
        while i + windowSamples <= blockSamples {
            var sum: Float = 0
            for j in i..<(i + windowSamples) { sum += samples[j] * samples[j] }
            let rms = (sum / Float(windowSamples)).squareRoot()
            if rms < bestRMS { bestRMS = rms; bestIndex = i }
            i += step
        }
        guard bestIndex >= 0 else { return blockSamples }
        return min(blockSamples, bestIndex + windowSamples / 2)
    }

    /// Samples aus einem CMSampleBuffer holen (Float32, mono, wie oben angefordert).
    private static func floats(from buffer: CMSampleBuffer) -> [Float] {
        guard let block = CMSampleBufferGetDataBuffer(buffer) else { return [] }
        var length = 0
        var pointer: UnsafeMutablePointer<Int8>?
        guard CMBlockBufferGetDataPointer(block, atOffset: 0, lengthAtOffsetOut: nil,
                                          totalLengthOut: &length,
                                          dataPointerOut: &pointer) == kCMBlockBufferNoErr,
              let pointer, length > 0 else { return [] }
        let count = length / MemoryLayout<Float>.size
        return pointer.withMemoryRebound(to: Float.self, capacity: count) {
            Array(UnsafeBufferPointer(start: $0, count: count))
        }
    }
}
```

- [ ] **Schritt 4: Tests laufen lassen und Erfolg prüfen**

```bash
cd /Users/liam/Developer/LIAM/flow-lokal && xcodebuild test -project FlowLokal.xcodeproj -scheme ShoutTests -destination 'platform=macOS,arch=arm64' -skipPackagePluginValidation -skipMacroValidation 2>&1 | tail -15
```

Erwartet: `** TEST SUCCEEDED **`, 22 Tests bestanden.

Schlägt das Schreiben der Test-WAV fehl („cannot create file"), liegt es am
Float32-Format: dann in `writeWAV` `commonFormat: .pcmFormatInt16` verwenden und
`channel` über `buffer.int16ChannelData` füllen. Die Prüfungen selbst bleiben gleich.

- [ ] **Schritt 5: Commit**

```bash
cd /Users/liam/Developer/LIAM/flow-lokal && git add Sources/FlowLokal/MediaDecoder.swift Tests/ShoutTests/MediaDecoderTests.swift && git commit -m "MediaDecoder: Audio und Video blockweise zu 16-kHz-Mono

AVAssetReader statt AVAudioFile, damit auch die Tonspur aus Videodateien
herauskommt. Blockgrenze fällt auf das leiseste Fenster im hinteren
Bereich, damit kein Wort zerschnitten wird."
```

---

### Aufgabe 4: Segmente aus dem `Transcriber`, lange Texte im `Formatter`

**Dateien:**
- Ändern: `Sources/FlowLokal/Transcriber.swift`
- Ändern: `Sources/FlowLokal/Formatter.swift`

**Schnittstellen:**
- Nutzt: `TranscriptSegment` (Aufgabe 1), `TextChunker.chunks` (Aufgabe 2)
- Liefert:
  - `Transcriber.transcribeSegments(_ samples: [Float], biasTerms: [String] = []) async throws -> [TranscriptSegment]`
  - `Formatter.formatLong(_ raw: String, termHint: String? = nil, onProgress: (@Sendable (Double) -> Void)? = nil) async -> String`

Diese Aufgabe hat keine Unit-Tests: beide Methoden brauchen ein geladenes Multi-GB-Modell. Geprüft wird über die Kompilierung und in Aufgabe 8 in der laufenden App.

- [ ] **Schritt 1: `run` im `Transcriber` aufteilen**

In `Sources/FlowLokal/Transcriber.swift` die Methode `private func run(samples:biasTerms:)` umbauen: der bestehende Rumpf wandert nach `runResults` und liefert die Ergebnisse statt eines Strings. `run` selbst fügt wie bisher zusammen.

Ersetze die Zeile

```swift
    private func run(samples: [Float], biasTerms: [String]) async throws -> String {
        guard let pipe else { throw TranscriberError.notLoaded }
```

durch

```swift
    private func run(samples: [Float], biasTerms: [String]) async throws -> String {
        let results = try await runResults(samples: samples, biasTerms: biasTerms)
        return results.map(\.text).joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func runResults(samples: [Float], biasTerms: [String]) async throws -> [TranscriptionResult] {
        guard let pipe else { throw TranscriberError.notLoaded }
```

und ersetze die beiden Schlusszeilen derselben Methode

```swift
        let results = try await pipe.transcribe(audioArray: samples, decodeOptions: options)
        return results.map(\.text).joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
```

durch

```swift
        return try await pipe.transcribe(audioArray: samples, decodeOptions: options)
```

- [ ] **Schritt 2: `transcribeSegments` ergänzen**

Direkt nach der bestehenden Methode `transcribe(_:biasTerms:)` einfügen:

```swift
    /// Wie `transcribe`, liefert aber die Abschnitte mit Zeitmarken — Grundlage für
    /// Untertitel bei der Datei-Transkription.
    ///
    /// Ohne die Plausibilitätsprüfung aus `transcribe`: Die vergleicht Textlänge mit
    /// Audiolänge und zieht im Verdachtsfall einen zweiten Durchgang nach. Bei einem
    /// Diktat ist das billig, bei einer Datei würde es die Laufzeit verdoppeln — und
    /// eine Aufnahme mit langen Sprechpausen sieht dort regelmäßig „verdächtig" aus.
    func transcribeSegments(_ samples: [Float], biasTerms: [String] = []) async throws -> [TranscriptSegment] {
        guard pipe != nil else { throw TranscriberError.notLoaded }
        let results = try await runResults(samples: samples, biasTerms: biasTerms)
        return results.flatMap(\.segments).map {
            TranscriptSegment(text: $0.text.trimmingCharacters(in: .whitespacesAndNewlines),
                              start: Double($0.start),
                              end: Double($0.end))
        }
    }
```

- [ ] **Schritt 3: `formatLong` im `Formatter` ergänzen**

In `Sources/FlowLokal/Formatter.swift` direkt nach der Methode `format(_:bundleID:termHint:)` einfügen:

```swift
    /// Bereitet einen langen Text abschnittsweise auf (Datei-Transkription).
    ///
    /// Der ganze Text auf einmal würde das Kontextfenster des kleinen quantisierten
    /// Modells sprengen. Angenehmer Nebeneffekt der Teilung: Der Kürzungs-Schutz in
    /// `format` greift pro Abschnitt und rettet damit nur den betroffenen Abschnitt
    /// statt den ganzen Text zu verwerfen.
    ///
    /// `bundleID` ist `nil` — bei einer Datei gibt es keine Ziel-App, deren Tonfall
    /// man treffen könnte.
    func formatLong(_ raw: String, termHint: String? = nil,
                    onProgress: (@Sendable (Double) -> Void)? = nil) async -> String {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isReady, !text.isEmpty else { return text }

        let parts = TextChunker.chunks(of: text)
        guard parts.count > 1 else {
            onProgress?(1)
            return await format(text, bundleID: nil, termHint: termHint)
        }

        var out: [String] = []
        out.reserveCapacity(parts.count)
        for (i, part) in parts.enumerated() {
            out.append(await format(part, bundleID: nil, termHint: termHint))
            onProgress?(Double(i + 1) / Double(parts.count))
        }
        // Absatz je Abschnitt: Ein einstündiges Transkript als eine Textwand ist
        // unlesbar, und geteilt wurde ohnehin an einer Satzgrenze.
        return out.joined(separator: "\n\n")
    }
```

- [ ] **Schritt 4: Kompilierung prüfen**

```bash
cd /Users/liam/Developer/LIAM/flow-lokal && ./build.sh Debug 2>&1 | tail -5
```

Erwartet: `✅ Fertig: build/Build/Products/Debug/shout.app`. **Die App nicht starten.**

- [ ] **Schritt 5: Bestehende Tests laufen lassen (Regression)**

```bash
cd /Users/liam/Developer/LIAM/flow-lokal && xcodebuild test -project FlowLokal.xcodeproj -scheme ShoutTests -destination 'platform=macOS,arch=arm64' -skipPackagePluginValidation -skipMacroValidation 2>&1 | tail -10
```

Erwartet: `** TEST SUCCEEDED **`, 22 Tests.

- [ ] **Schritt 6: Commit**

```bash
cd /Users/liam/Developer/LIAM/flow-lokal && git add Sources/FlowLokal/Transcriber.swift Sources/FlowLokal/Formatter.swift && git commit -m "Transcriber: Segmente mit Zeitmarken, Formatter: lange Texte

transcribeSegments liefert die Whisper-Abschnitte samt Start/Ende;
das bestehende transcribe bleibt Wort für Wort gleich. formatLong
schickt lange Texte abschnittsweise durchs Modell."
```

---

### Aufgabe 5: Auftrag und Warteschlange

**Dateien:**
- Anlegen: `Sources/FlowLokal/FileTranscriptionQueue.swift`

**Schnittstellen:**
- Nutzt: `MediaDecoder`, `MediaBlock`, `MediaDecoderError` (Aufgabe 3); `TranscriptSegment` (Aufgabe 1); `Transcriber.transcribeSegments`, `Formatter.formatLong` (Aufgabe 4); `PersonalDictionary.contents.terms`, `.applyCorrections(to:)`, `.termHint`; `SpeechCommands.apply(to:)`
- Liefert:
  - `@MainActor final class FileTranscriptionJob: ObservableObject, Identifiable` mit `id`, `url`, `name`, `state`, `duration`, `segments`, `rawText`, `formattedText`, `displayText`, `wordCount`
  - `enum FileTranscriptionJob.State: Equatable { case queued, transcribing(Double), formatting(Double), done, failed(String), cancelled }`
  - `@MainActor final class FileTranscriptionQueue: ObservableObject` mit `init(transcriber:formatter:dictionary:)`, `jobs`, `selectedJobID`, `isRunning`, `add(_:)`, `cancel(_:)`, `cancelAll()`, `remove(_:)`

- [ ] **Schritt 1: Datei anlegen**

`Sources/FlowLokal/FileTranscriptionQueue.swift`:

```swift
import Foundation
import Combine

/// Ein Transkriptions-Auftrag: eine Datei, ihr Zustand und ihr Ergebnis.
///
/// Ergebnisse leben nur zur Laufzeit. Gesichert wird ausschließlich, was der
/// Nutzer über den Sichern-Dialog selbst ablegt — und weder Verlauf noch
/// Statistiken werden angefasst: Die Statistik misst, wie schnell DU diktierst,
/// eine Stunde fremdes Audio würde diesen Wert bedeutungslos machen.
@MainActor
final class FileTranscriptionJob: ObservableObject, Identifiable {

    enum State: Equatable {
        case queued
        case transcribing(progress: Double)
        case formatting(progress: Double)
        case done
        case failed(String)
        case cancelled
    }

    let id = UUID()
    let url: URL

    @Published var state: State = .queued
    @Published var duration: Double = 0
    /// Rohsegmente mit Zeitmarken — Grundlage der .srt-Datei.
    @Published var segments: [TranscriptSegment] = []
    /// Rohtranskript (Segmente verbunden).
    @Published var rawText = ""
    /// Aufbereiteter Text; leer, wenn nicht aufbereitet wurde.
    @Published var formattedText = ""

    init(url: URL) { self.url = url }

    var name: String { url.lastPathComponent }

    /// Was angezeigt und als .txt gesichert wird.
    var displayText: String { formattedText.isEmpty ? rawText : formattedText }

    var wordCount: Int {
        displayText.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).count
    }

    var isFinished: Bool {
        switch state {
        case .done, .failed, .cancelled: return true
        case .queued, .transcribing, .formatting: return false
        }
    }
}

/// Arbeitet Datei-Aufträge nacheinander ab.
///
/// Seriell und nicht parallel, weil ohnehin nur ein Whisper-Modell im Speicher
/// liegt: Zwei Aufträge gleichzeitig würden sich am `Transcriber`-actor
/// gegenseitig blockieren und nur die Fortschrittsanzeige unehrlich machen.
@MainActor
final class FileTranscriptionQueue: ObservableObject {

    @Published private(set) var jobs: [FileTranscriptionJob] = []
    @Published var selectedJobID: UUID?

    private let transcriber: Transcriber
    private let formatter: Formatter
    private let dictionary: PersonalDictionary

    private var runTask: Task<Void, Never>?
    /// Aufträge, die der Nutzer abgebrochen hat. Wird zwischen den Blöcken geprüft.
    private var cancelled: Set<UUID> = []

    init(transcriber: Transcriber, formatter: Formatter, dictionary: PersonalDictionary) {
        self.transcriber = transcriber
        self.formatter = formatter
        self.dictionary = dictionary
    }

    /// Läuft gerade ein Auftrag? Blockiert unter anderem den Modellwechsel.
    var isRunning: Bool { runTask != nil }

    var hasUnfinishedJobs: Bool { jobs.contains { !$0.isFinished } }

    // MARK: - Steuerung

    func add(_ urls: [URL]) {
        for url in urls {
            let job = FileTranscriptionJob(url: url)
            jobs.append(job)
            if selectedJobID == nil { selectedJobID = job.id }
        }
        startIfNeeded()
    }

    func cancel(_ job: FileTranscriptionJob) {
        cancelled.insert(job.id)
        // Wartende Aufträge sofort abräumen; der laufende merkt es beim nächsten Block.
        if case .queued = job.state { job.state = .cancelled }
    }

    func cancelAll() {
        for job in jobs where !job.isFinished { cancel(job) }
    }

    func remove(_ job: FileTranscriptionJob) {
        cancel(job)
        jobs.removeAll { $0.id == job.id }
        if selectedJobID == job.id { selectedJobID = jobs.first(where: \.isFinished)?.id }
    }

    // MARK: - Abarbeitung

    private func startIfNeeded() {
        guard runTask == nil else { return }
        runTask = Task { [weak self] in
            while let job = self?.nextJob() {
                await self?.process(job)
            }
            self?.runTask = nil
        }
    }

    private func nextJob() -> FileTranscriptionJob? {
        jobs.first { if case .queued = $0.state { return true } else { return false } }
    }

    private func process(_ job: FileTranscriptionJob) async {
        guard !cancelled.contains(job.id) else { job.state = .cancelled; return }

        let useCommands = UserDefaults.standard.bool(forKey: "fileSpeechCommandsEnabled")
        let useFormatting = UserDefaults.standard.object(forKey: "fileFormattingEnabled") as? Bool ?? true
        let bias = dictionary.contents.terms

        job.state = .transcribing(progress: 0)

        let decoder = MediaDecoder(url: job.url)
        var collected: [TranscriptSegment] = []
        do {
            let duration = try await decoder.open()
            job.duration = duration

            while let block = try await decoder.next() {
                if cancelled.contains(job.id) { job.state = .cancelled; return }

                let raw = try await transcriber.transcribeSegments(block.samples, biasTerms: bias)
                for segment in raw {
                    var text = segment.text.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !text.isEmpty else { continue }
                    // Sprachbefehle und Korrekturen PRO SEGMENT — sonst passt der Text
                    // der .srt nicht mehr zu dem, was im Fenster steht.
                    if useCommands { text = SpeechCommands.apply(to: text) }
                    text = dictionary.applyCorrections(to: text)
                    guard !text.isEmpty else { continue }
                    collected.append(TranscriptSegment(text: text,
                                                       start: segment.start + block.startTime,
                                                       end: segment.end + block.startTime))
                }

                job.segments = collected
                job.rawText = collected.map(\.text).joined(separator: " ")
                let processed = block.startTime + Double(block.samples.count) / MediaDecoder.sampleRate
                job.state = .transcribing(progress: duration > 0 ? min(1, processed / duration) : 0)
            }
        } catch let error as MediaDecoderError {
            job.state = .failed(Self.message(for: error))
            return
        } catch {
            job.state = .failed(error.localizedDescription)
            return
        }

        if cancelled.contains(job.id) { job.state = .cancelled; return }

        guard !job.rawText.isEmpty else {
            job.state = .done
            return
        }

        if useFormatting {
            job.state = .formatting(progress: 0)
            let hint = dictionary.termHint
            let jobRef = job
            let cleaned = await formatter.formatLong(job.rawText, termHint: hint) { fraction in
                Task { @MainActor in
                    if case .formatting = jobRef.state { jobRef.state = .formatting(progress: fraction) }
                }
            }
            if cancelled.contains(job.id) { job.state = .cancelled; return }
            job.formattedText = cleaned
        }

        job.state = .done
        if selectedJobID == nil { selectedJobID = job.id }
    }

    /// Übersetzt die Decoder-Fehler. Hier statt im `MediaDecoder`, weil `Loc` an den
    /// Main-Actor gebunden ist und der Decoder auf seinem eigenen läuft.
    private static func message(for error: MediaDecoderError) -> String {
        switch error {
        case .noAudioTrack:
            return Loc.t("Diese Datei enthält keine Tonspur.")
        case .unreadable(let detail):
            return Loc.f("Diese Datei kann nicht gelesen werden (%@).", detail)
        }
    }
}
```

- [ ] **Schritt 2: Kompilierung prüfen**

```bash
cd /Users/liam/Developer/LIAM/flow-lokal && ./build.sh Debug 2>&1 | tail -5
```

Erwartet: `✅ Fertig: …`. **Die App nicht starten.**

- [ ] **Schritt 3: Commit**

```bash
cd /Users/liam/Developer/LIAM/flow-lokal && git add Sources/FlowLokal/FileTranscriptionQueue.swift && git commit -m "Warteschlange für Datei-Transkriptionen

Serielle Abarbeitung, Fortschritt pro Block, Abbrechen zwischen den
Blöcken. Sprachbefehle und Wörterbuch-Korrekturen greifen pro Segment,
damit .srt und angezeigter Text denselben Wortlaut haben."
```

---

### Aufgabe 6: Die Seite „Dateien"

**Dateien:**
- Anlegen: `Sources/FlowLokal/FilesView.swift`
- Ändern: `Sources/FlowLokal/DashboardView.swift`
- Ändern: `Sources/FlowLokal/Localization.swift`

**Schnittstellen:**
- Nutzt: `FileTranscriptionQueue`, `FileTranscriptionJob` (Aufgabe 5); `SubtitleWriter.srt` (Aufgabe 1); `ConsolePanel`, `FieldRow`, `ConsoleDivider`, `ConsoleButtonStyle` aus `ConsoleUI.swift`
- Liefert: `struct FilesView: View` mit `init(queue:modelReady:)`; `DashboardModel.Tab.dateien`

- [ ] **Schritt 1: `FilesView` anlegen**

`Sources/FlowLokal/FilesView.swift`:

```swift
import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// „Dateien" — fertige Audio- und Videodateien lokal transkribieren.
struct FilesView: View {
    @ObservedObject var queue: FileTranscriptionQueue
    /// Ist das Transkriptions-Modell geladen? Ohne Modell wäre jeder Knopf hier
    /// eine Lüge, deshalb steht dann nur ein Hinweis da.
    let modelReady: Bool

    @AppStorage("fileFormattingEnabled") private var formattingEnabled = true
    @AppStorage("fileSpeechCommandsEnabled") private var speechCommands = false
    @State private var isTargeted = false
    @State private var status = ""

    private var selectedJob: FileTranscriptionJob? {
        queue.jobs.first { $0.id == queue.selectedJobID && $0.isFinished }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                Text(Loc.t("Dateien"))
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color(white: 0.92))

                if modelReady {
                    dropZone
                    optionsPanel
                    if !queue.jobs.isEmpty { jobsPanel }
                    if let job = selectedJob { resultPanel(job) }
                } else {
                    ConsolePanel {
                        Text(Loc.t("Zum Transkribieren wird das Sprachmodell gebraucht. Lade es unter „Modelle“ herunter — danach geht es hier weiter."))
                            .font(.system(size: 13))
                            .foregroundStyle(Color(white: 0.62))
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(16)
                    }
                }

                Text(Loc.t("Die Datei wird auf diesem Gerät gelesen — nichts wird hochgeladen. Ergebnisse werden nicht automatisch gespeichert und tauchen weder im Verlauf noch in den Statistiken auf."))
                    .font(.system(size: 11)).foregroundStyle(Color(white: 0.5))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: 640).frame(maxWidth: .infinity)
            .padding(.horizontal, 28).padding(.top, 42).padding(.bottom, 28)
        }
        .background(Color.shoutWindow)
        .scrollContentBackground(.hidden)
    }

    // MARK: - Ablagefläche

    private var dropZone: some View {
        VStack(spacing: 10) {
            Image(systemName: "waveform.badge.plus")
                .font(.system(size: 26)).foregroundStyle(Color.shoutLive)
            Text(Loc.t("Audio- oder Videodateien hierher ziehen"))
                .font(.system(size: 13)).foregroundStyle(Color(white: 0.75))
            Text(Loc.t("MP3, M4A, WAV, MP4, MOV und alles, was macOS abspielen kann"))
                .font(.system(size: 11)).foregroundStyle(Color(white: 0.5))
            Button(Loc.t("Auswählen …"), action: chooseFiles).buttonStyle(ConsoleButtonStyle())
        }
        .frame(maxWidth: .infinity).padding(.vertical, 30)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(white: 0.13)))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(isTargeted ? Color.shoutLive : Color.white.opacity(0.12),
                              style: StrokeStyle(lineWidth: isTargeted ? 2 : 1, dash: [6, 4]))
        )
        .onDrop(of: [.fileURL], isTargeted: $isTargeted) { providers in
            load(providers)
            return true
        }
    }

    private var optionsPanel: some View {
        ConsolePanel(title: Loc.t("Verarbeitung")) {
            FieldRow(title: Loc.t("Text aufbereiten"),
                     help: Loc.t("Füllwörter entfernen, Satzzeichen setzen — abschnittsweise durch das lokale Sprachmodell.")) {
                Toggle("", isOn: $formattingEnabled).labelsHidden().toggleStyle(.switch).tint(Color.shoutLive)
            }
            ConsoleDivider()
            FieldRow(title: Loc.t("Sprachbefehle anwenden"),
                     help: Loc.t("Standardmäßig aus: In einer Aufzeichnung ist „Punkt“ meist ein normales Wort und kein Satzzeichen.")) {
                Toggle("", isOn: $speechCommands).labelsHidden().toggleStyle(.switch).tint(Color.shoutLive)
            }
        }
    }

    // MARK: - Aufträge

    private var jobsPanel: some View {
        ConsolePanel(title: Loc.t("Aufträge")) {
            VStack(spacing: 0) {
                ForEach(Array(queue.jobs.enumerated()), id: \.element.id) { index, job in
                    JobRow(job: job,
                           selected: job.id == queue.selectedJobID,
                           onSelect: { if job.isFinished { queue.selectedJobID = job.id } },
                           onCancel: { queue.cancel(job) },
                           onRemove: { queue.remove(job) })
                    if index < queue.jobs.count - 1 { ConsoleDivider() }
                }
            }
        }
    }

    // MARK: - Ergebnis

    private func resultPanel(_ job: FileTranscriptionJob) -> some View {
        ConsolePanel(title: Loc.t("Ergebnis")) {
            VStack(alignment: .leading, spacing: 12) {
                if job.displayText.isEmpty {
                    Text(Loc.t("Kein gesprochener Inhalt erkannt."))
                        .font(.system(size: 13)).foregroundStyle(Color(white: 0.62))
                } else {
                    ScrollView {
                        Text(job.displayText)
                            .font(.system(size: 12.5))
                            .foregroundStyle(Color(white: 0.88))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(10)
                    }
                    .frame(height: 220)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color(white: 0.11)))

                    HStack(spacing: 10) {
                        Button(Loc.t("Kopieren")) {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(job.displayText, forType: .string)
                            status = Loc.t("In die Zwischenablage kopiert.")
                        }.buttonStyle(ConsoleButtonStyle())
                        Button(Loc.t("Als Text sichern …")) { save(job, asSubtitles: false) }
                            .buttonStyle(ConsoleButtonStyle())
                        Button(Loc.t("Untertitel sichern …")) { save(job, asSubtitles: true) }
                            .buttonStyle(ConsoleButtonStyle())
                            .disabled(job.segments.isEmpty)
                    }
                    Text(Loc.t("Untertitel enthalten immer das Rohtranskript — nur so passen die Zeitmarken zum Wortlaut."))
                        .font(.system(size: 11)).foregroundStyle(Color(white: 0.5))
                        .fixedSize(horizontal: false, vertical: true)
                    if !status.isEmpty {
                        Text(status).font(.system(size: 12)).foregroundStyle(Color.shoutLive)
                    }
                }
            }
            .padding(16)
        }
    }

    // MARK: - Dateien annehmen und sichern

    private func chooseFiles() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        // .audio und .movie decken MP3, M4A, WAV, AIFF, MP4, MOV und alles Weitere ab,
        // was AVFoundation lesen kann — eine längere Liste wäre nur redundant.
        panel.allowedContentTypes = [.audio, .movie]
        guard panel.runModal() == .OK else { return }
        status = ""
        queue.add(panel.urls)
    }

    private func load(_ providers: [NSItemProvider]) {
        for provider in providers {
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                guard let url else { return }
                Task { @MainActor in
                    status = ""
                    queue.add([url])
                }
            }
        }
    }

    private func save(_ job: FileTranscriptionJob, asSubtitles: Bool) {
        let panel = NSSavePanel()
        let base = job.url.deletingPathExtension().lastPathComponent
        panel.nameFieldStringValue = base + (asSubtitles ? ".srt" : ".txt")
        panel.allowedContentTypes = asSubtitles ? [] : [.plainText]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let content = asSubtitles ? SubtitleWriter.srt(from: job.segments) : job.displayText
        do {
            try content.write(to: url, atomically: true, encoding: .utf8)
            status = Loc.f("Gesichert: %@", url.lastPathComponent)
        } catch {
            status = Loc.f("Sichern fehlgeschlagen: %@", error.localizedDescription)
        }
    }
}

/// Eine Zeile der Auftragsliste.
private struct JobRow: View {
    @ObservedObject var job: FileTranscriptionJob
    let selected: Bool
    let onSelect: () -> Void
    let onCancel: () -> Void
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon).font(.system(size: 14))
                .foregroundStyle(color).frame(width: 20)
            VStack(alignment: .leading, spacing: 3) {
                Text(job.name).font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color(white: 0.9)).lineLimit(1).truncationMode(.middle)
                Text(subtitle).font(.system(size: 11)).foregroundStyle(Color(white: 0.55))
                    .lineLimit(2).fixedSize(horizontal: false, vertical: true)
                if let fraction = progress {
                    ProgressView(value: fraction).progressViewStyle(.linear)
                        .tint(Color.shoutLive).frame(maxWidth: 220)
                }
            }
            Spacer(minLength: 8)
            Button(action: job.isFinished ? onRemove : onCancel) {
                Image(systemName: "xmark").font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Color(white: 0.6))
            }
            .buttonStyle(.plain)
            .help(job.isFinished ? Loc.t("Aus der Liste entfernen") : Loc.t("Abbrechen"))
        }
        .padding(.horizontal, 15).padding(.vertical, 12)
        .background(selected ? Color.shoutLive.opacity(0.10) : Color.clear)
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
    }

    private var progress: Double? {
        switch job.state {
        case .transcribing(let p), .formatting(let p): return p
        default: return nil
        }
    }

    private var icon: String {
        switch job.state {
        case .queued: return "clock"
        case .transcribing, .formatting: return "waveform"
        case .done: return "checkmark.circle.fill"
        case .failed: return "exclamationmark.triangle.fill"
        case .cancelled: return "slash.circle"
        }
    }

    private var color: Color {
        switch job.state {
        case .done: return Color.shoutLive
        case .failed: return Color(red: 0.95, green: 0.7, blue: 0.2)
        default: return Color(white: 0.6)
        }
    }

    private var subtitle: String {
        switch job.state {
        case .queued: return Loc.t("Wartet")
        case .transcribing: return Loc.t("Wird transkribiert …")
        case .formatting: return Loc.t("Text wird aufbereitet …")
        case .done: return Loc.f("Fertig · %d Wörter", job.wordCount)
        case .failed(let reason): return reason
        case .cancelled: return Loc.t("Abgebrochen")
        }
    }
}
```

- [ ] **Schritt 2: Tab im Dashboard eintragen**

In `Sources/FlowLokal/DashboardView.swift`:

1. Im Enum `Tab` `dateien` ergänzen:

```swift
    enum Tab: Hashable { case aufnahme, dateien, woerterbuch, verlauf, statistik, modelle, sync, unterstuetzen }
```

2. In `DashboardView` die neue Eigenschaft **direkt nach** `var onPillPositionChanged: () -> Void = {}` einfügen. Die Stelle ist nicht beliebig: `files` hat keinen Standardwert und muss in der memberwise-Init vor `updates` stehen, weil der Aufruf im `AppDelegate` (Aufgabe 7) `files:` vor `updates:` übergibt. Endgültige Reihenfolge der Eigenschaften ab `onPersistentPillChanged`:

```swift
    var onPersistentPillChanged: (Bool) -> Void = { _ in }
    var onPillPositionChanged: () -> Void = {}
    @ObservedObject var files: FileTranscriptionQueue
    var updates: UpdateBridge = .disabled
```

3. In `sidebar` nach der Zeile für `.aufnahme` einfügen:

```swift
            navRow(.dateien, Loc.t("Dateien"), "doc.text.below.ecg")
```

4. In `detail` einen Fall ergänzen:

```swift
        case .dateien:
            FilesView(queue: files, modelReady: model.transcriberReady)
```

- [ ] **Schritt 3: Englische Texte ergänzen**

In `Sources/FlowLokal/Localization.swift` vor der Schlusszeile `]` des `english`-Dictionaries einfügen:

```swift
        // MARK: - Dateien

        "Dateien": "Files",
        "Audio- oder Videodateien hierher ziehen": "Drag audio or video files here",
        "MP3, M4A, WAV, MP4, MOV und alles, was macOS abspielen kann": "MP3, M4A, WAV, MP4, MOV and anything macOS can play",
        "Auswählen …": "Choose…",
        "Verarbeitung": "Processing",
        "Text aufbereiten": "Clean up text",
        "Füllwörter entfernen, Satzzeichen setzen — abschnittsweise durch das lokale Sprachmodell.": "Remove filler words, add punctuation — section by section through the local language model.",
        "Sprachbefehle anwenden": "Apply spoken commands",
        "Standardmäßig aus: In einer Aufzeichnung ist „Punkt“ meist ein normales Wort und kein Satzzeichen.": "Off by default: in a recording, “period” is usually just a word, not punctuation.",
        "Aufträge": "Jobs",
        "Ergebnis": "Result",
        "Kein gesprochener Inhalt erkannt.": "No speech detected.",
        "Als Text sichern …": "Save as text…",
        "Untertitel sichern …": "Save subtitles…",
        "Untertitel enthalten immer das Rohtranskript — nur so passen die Zeitmarken zum Wortlaut.": "Subtitles always contain the raw transcript — only then do the timestamps match the wording.",
        "In die Zwischenablage kopiert.": "Copied to the clipboard.",
        "Gesichert: %@": "Saved: %@",
        "Sichern fehlgeschlagen: %@": "Saving failed: %@",
        "Aus der Liste entfernen": "Remove from list",
        "Abbrechen": "Cancel",
        "Wartet": "Waiting",
        "Wird transkribiert …": "Transcribing…",
        "Text wird aufbereitet …": "Cleaning up text…",
        "Fertig · %d Wörter": "Done · %d words",
        "Abgebrochen": "Cancelled",
        "Zum Transkribieren wird das Sprachmodell gebraucht. Lade es unter „Modelle“ herunter — danach geht es hier weiter.": "Transcribing needs the speech model. Download it under “Models” — then come back here.",
        "Die Datei wird auf diesem Gerät gelesen — nichts wird hochgeladen. Ergebnisse werden nicht automatisch gespeichert und tauchen weder im Verlauf noch in den Statistiken auf.": "The file is read on this device — nothing is uploaded. Results are not saved automatically and appear neither in the history nor in the statistics.",
        "Diese Datei enthält keine Tonspur.": "This file has no audio track.",
        "Diese Datei kann nicht gelesen werden (%@).": "This file cannot be read (%@).",
        "Transkription läuft — Modellwechsel ist erst danach möglich.": "Transcription running — you can switch models afterwards.",
        "Es läuft noch eine Datei-Transkription.": "A file transcription is still running.",
        "Wirklich beenden? Der laufende Auftrag geht verloren.": "Quit anyway? The running job will be lost.",
        "Trotzdem beenden": "Quit anyway",
```

**Wichtig:** `"Abbrechen"` und `"Kopieren"` existieren womöglich schon im Dictionary. Vor dem Einfügen prüfen:

```bash
cd /Users/liam/Developer/LIAM/flow-lokal && grep -n '"Abbrechen"\|"Kopieren"\|"Ergebnis"\|"Dateien"' Sources/FlowLokal/Localization.swift
```

Jeden Schlüssel, der schon existiert, aus dem neuen Block **streichen** — ein doppelter Schlüssel in einem Swift-Dictionary-Literal ist ein Laufzeitabsturz beim Aufbau der Tabelle.

- [ ] **Schritt 4: Kompilierung prüfen**

```bash
cd /Users/liam/Developer/LIAM/flow-lokal && xcodegen generate && ./build.sh Debug 2>&1 | tail -5
```

Erwartet: `✅ Fertig: …`. Der Build schlägt fehl, solange `AppDelegate` das neue `files:`-Argument nicht übergibt — das ist Aufgabe 7. Wenn der Fehler ausschließlich „missing argument for parameter 'files'" in `AppDelegate.swift` lautet, ist dieser Schritt bestanden.

- [ ] **Schritt 5: Commit**

```bash
cd /Users/liam/Developer/LIAM/flow-lokal && git add Sources/FlowLokal/FilesView.swift Sources/FlowLokal/DashboardView.swift Sources/FlowLokal/Localization.swift && git commit -m "Seite „Dateien“ mit Ablagefläche, Auftragsliste und Ergebnis

Ablegen per Drag & Drop oder Auswahl, zwei Schalter für Aufbereitung und
Sprachbefehle, Ergebnis kopieren oder als .txt/.srt sichern."
```

---

### Aufgabe 7: Verdrahtung im `AppDelegate`

**Dateien:**
- Ändern: `Sources/FlowLokal/AppDelegate.swift`

**Schnittstellen:**
- Nutzt: `FileTranscriptionQueue` (Aufgabe 5), `DashboardView(files:)` (Aufgabe 6)
- Liefert: nichts für spätere Aufgaben

- [ ] **Schritt 1: Warteschlange anlegen**

In `Sources/FlowLokal/AppDelegate.swift` nach der Zeile `private let sounds = SoundCues()` einfügen:

```swift

    /// Datei-Transkription: eigene Warteschlange, teilt sich Modelle und Wörterbuch
    /// mit dem Diktat. Serialisiert wird über den Transcriber-actor.
    private lazy var fileQueue = FileTranscriptionQueue(
        transcriber: transcriber, formatter: formatter, dictionary: dictionary)
```

- [ ] **Schritt 2: An das Dashboard durchreichen**

In `openDashboard(_:)` im `DashboardView(...)`-Aufruf vor `updates: updateBridge` einfügen:

```swift
                files: fileQueue,
```

- [ ] **Schritt 3: Modellwechsel während eines Auftrags sperren**

In `switchASRModel(to:)` die bestehende `guard`-Bedingung erweitern. Ersetze:

```swift
        guard state == .idle || state == .failed else {
            dashboardModel.modelNote = Loc.t("Modellwechsel ist nur möglich, wenn gerade nicht aufgenommen oder verarbeitet wird.")
            return
        }
```

durch:

```swift
        guard state == .idle || state == .failed else {
            dashboardModel.modelNote = Loc.t("Modellwechsel ist nur möglich, wenn gerade nicht aufgenommen oder verarbeitet wird.")
            return
        }
        // Ein Wechsel mitten in einer Datei-Transkription würde das Modell unter dem
        // laufenden Auftrag wegziehen.
        guard !fileQueue.isRunning else {
            dashboardModel.modelNote = Loc.t("Transkription läuft — Modellwechsel ist erst danach möglich.")
            return
        }
```

Dieselben zwei zusätzlichen Zeilen in `switchFormatModel(to:)` direkt nach dessen `guard state == .idle || state == .failed else { … }`-Block einfügen.

- [ ] **Schritt 4: Nachfrage beim Beenden**

Direkt vor `func applicationWillTerminate(_ notification: Notification)` einfügen:

```swift
    /// Läuft noch ein Datei-Auftrag, wird nachgefragt — sonst ist die Arbeit von
    /// vielleicht einer halben Stunde stillschweigend weg.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard fileQueue.hasUnfinishedJobs else { return .terminateNow }
        let alert = NSAlert()
        alert.messageText = Loc.t("Es läuft noch eine Datei-Transkription.")
        alert.informativeText = Loc.t("Wirklich beenden? Der laufende Auftrag geht verloren.")
        alert.addButton(withTitle: Loc.t("Trotzdem beenden"))
        alert.addButton(withTitle: Loc.t("Abbrechen"))
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        return alert.runModal() == .alertFirstButtonReturn ? .terminateNow : .terminateCancel
    }

```

- [ ] **Schritt 5: Laufende Aufträge beim Beenden abbrechen**

In `applicationWillTerminate(_:)` als erste Zeile einfügen:

```swift
        fileQueue.cancelAll()
```

- [ ] **Schritt 6: Kompilierung prüfen**

```bash
cd /Users/liam/Developer/LIAM/flow-lokal && ./build.sh Debug 2>&1 | tail -5
```

Erwartet: `✅ Fertig: build/Build/Products/Debug/shout.app`. **Die App nicht starten.**

- [ ] **Schritt 7: Tests laufen lassen (Regression)**

```bash
cd /Users/liam/Developer/LIAM/flow-lokal && xcodebuild test -project FlowLokal.xcodeproj -scheme ShoutTests -destination 'platform=macOS,arch=arm64' -skipPackagePluginValidation -skipMacroValidation 2>&1 | tail -10
```

Erwartet: `** TEST SUCCEEDED **`, 22 Tests.

- [ ] **Schritt 8: Commit**

```bash
cd /Users/liam/Developer/LIAM/flow-lokal && git add Sources/FlowLokal/AppDelegate.swift && git commit -m "Datei-Warteschlange im AppDelegate verdrahtet

Warteschlange teilt Modelle und Wörterbuch mit dem Diktat, Modellwechsel
ist während eines Auftrags gesperrt, Beenden fragt nach."
```

---

### Aufgabe 8: Prüfung in der laufenden App und Dokumentation

**Dateien:**
- Ändern: `README.md`
- Ändern: `OFFEN.md`
- Ändern: `docs/superpowers/specs/2026-08-02-datei-transkription-design.md`

- [ ] **Schritt 1: Testdateien erzeugen**

```bash
cd /private/tmp && say -o /tmp/shout-test-kurz.m4a "Dies ist ein kurzer Test für die Datei-Transkription. Er dauert nur wenige Sekunden." && afinfo /tmp/shout-test-kurz.m4a | head -5
```

Für eine Videodatei mit Tonspur:

```bash
cd /private/tmp && say -o /tmp/shout-ton.aiff "Dies ist die Tonspur einer Videodatei zum Testen der Transkription." && ffmpeg -f lavfi -i color=c=black:s=320x240:d=8 -i /tmp/shout-ton.aiff -shortest -y /tmp/shout-test-video.mp4 2>&1 | tail -3
```

Ist `ffmpeg` nicht installiert, entfällt der Videotest an dieser Stelle und wird stattdessen mit einer echten Videodatei des Nutzers geprüft (Bildschirmaufnahme über ⇧⌘5 erzeugt eine `.mov` mit Tonspur, wenn ein Mikrofon gewählt ist).

- [ ] **Schritt 2: Prüfliste in der laufenden App abarbeiten**

Die Prüfung läuft in einer **installierten** App (`/Applications/shout.app`), nicht im Debug-Build — zwei Instanzen würden dieselben globalen Hotkeys registrieren. Der Weg dorthin steht in `RELEASE.md`.

Abzuhaken:

1. Kurze Audiodatei ablegen → Auftrag läuft, Fortschritt bewegt sich, Ergebnis erscheint.
2. „Kopieren" → Text landet in der Zwischenablage.
3. „Als Text sichern …" → `.txt` liegt am gewählten Ort und enthält den angezeigten Text.
4. „Untertitel sichern …" → `.srt` in VLC oder QuickTime zur Datei laden; Zeitmarken passen zum Gesprochenen.
5. Lange Datei (> 30 Minuten): mehrere Blöcke, an den Übergängen fehlen keine Wörter und nichts steht doppelt.
6. Videodatei mit Tonspur → wird transkribiert.
7. Datei ohne Tonspur (z. B. eine `.txt` umbenannt) → Auftrag zeigt „Diese Datei enthält keine Tonspur.", die übrigen laufen weiter.
8. Mehrere Dateien gleichzeitig ablegen → werden nacheinander abgearbeitet.
9. Abbrechen mitten im Lauf → Auftrag geht auf „Abgebrochen", der nächste startet.
10. Diktat per Hotkey während eines laufenden Auftrags → funktioniert, wartet höchstens einen Block.
11. Modellwechsel während eines Auftrags → Hinweis erscheint, Modell wechselt nicht.
12. Beenden bei laufendem Auftrag → Nachfrage erscheint.
13. Schalter „Text aufbereiten" aus → Rohtranskript erscheint, deutlich schneller.
14. Oberflächensprache auf Englisch umschalten → alle Texte der Seite sind übersetzt.
15. Verlauf und Statistiken prüfen → unverändert, keine neuen Einträge.

- [ ] **Schritt 3: `README.md` ergänzen**

In der Feature-Liste nach dem Punkt „**Adaptive silence detection** …" einfügen:

```markdown
- **Transcribe files** (macOS) — drop audio or video files into the app and get
  the transcript as text, `.txt` or `.srt` subtitles. Same local pipeline as
  dictation, nothing is uploaded.
```

- [ ] **Schritt 4: `OFFEN.md` ergänzen**

Unter „🟢 Features (aus der Ideenliste, noch offen)" einfügen:

```markdown
- [x] **Datei-Transkription am Mac** — Seite „Dateien": Audio und Video per Drag & Drop oder Auswahl, serielle Warteschlange, Ergebnis als Text, `.txt` oder `.srt`. Blockweises Lesen über `AVAssetReader` (2-Minuten-Blöcke, Schnitt an der leisesten Stelle), damit der Speicher gedeckelt bleibt und ein Diktat per Hotkey höchstens einen Block warten muss. Untertitel entstehen immer aus dem Rohtranskript, weil die Zeitmarken sonst nicht zum aufbereiteten Wortlaut passen.
- [ ] **Datei-Transkription auf Windows nachziehen** — die Kette ist identisch (`TranscribeAsync(float[])` steht), neu sind Dekoder und Oberfläche. Für Video braucht es dort FFmpeg oder die Media Foundation; NAudio liest keine Videocontainer.
- [ ] **Datei-Transkription auf iOS nachziehen** — Auswahl über `UIDocumentPicker`; offen ist weniger die Technik als Laufzeit, Hintergrund-Ausführung und Wärme bei langen Dateien.
```

- [ ] **Schritt 5: Spezifikation nachziehen**

In `docs/superpowers/specs/2026-08-02-datei-transkription-design.md` die drei unter „Abweichungen von der Spezifikation" (oben in diesem Plan) genannten Punkte einarbeiten: `TranscriptSegment` als eigener Typ, `MediaDecoder` als actor mit `open()`/`next()`, und die Beschreibung des Schnitts an der leisesten Stelle.

- [ ] **Schritt 6: Commit**

```bash
cd /Users/liam/Developer/LIAM/flow-lokal && git add README.md OFFEN.md docs/ && git commit -m "Doku: Datei-Transkription in README, OFFEN und Spezifikation"
```
