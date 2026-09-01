# Externe Anbieter — Umsetzungsplan

> **Für agentische Bearbeitung:** Dieser Plan wird inline in der Sitzung
> abgearbeitet (`superpowers:executing-plans`), nicht mit Subagenten — so
> gewünscht. Schritte sind als Checkboxen geführt.

**Ziel:** Aufbereitung und Transkription je einzeln umschaltbar zwischen „auf
diesem Gerät" und einem selbst gewählten OpenAI-kompatiblen Anbieter.

**Architektur:** `Formatter` und `Transcriber` bleiben die Fassaden, die alle
Aufrufer kennen, und werden zu Routern. Darunter je zwei austauschbare Engines
hinter einem winzigen Protokoll. Alles Anbieterunabhängige (Prompts, Chunking,
`FormattingGuard`, Plausibilitätsprüfung, Protokoll-Erzeugung) bleibt im Router
und gilt damit für lokal wie extern.

**Technik:** Swift 6, Actors, `URLSession`, Keychain (`kSecClassGenericPassword`),
MLX/WhisperKit unverändert hinter den lokalen Engines.

**Entwurf:** `docs/superpowers/specs/2026-09-01-externe-anbieter-design.md` —
gilt vollständig; dieser Plan wiederholt ihn nicht, sondern setzt ihn um.

## Globale Vorgaben

- Alle Oberflächentexte über `Loc.t("deutscher Text")`, deutscher Text als
  Schlüssel. **Keine Schlüssel doppeln** (doppelte Schlüssel lassen die App beim
  Start abstürzen), typografische Apostrophe (`'`) exakt übernehmen.
- Echte UTF-8-Umlaute, niemals ASCII-Ersatz.
- Jede neue Datei in `Sources/FlowLokal/` muss **einzeln** in die
  `ShoutMobile`-Quellenliste in `project.yml` (der iOS-Abschnitt listet
  FlowLokal-Dateien explizit) — sonst bricht der iOS-Build.
- Testbare, plattformneutrale neue Dateien zusätzlich in die
  `ShoutTests`-Quellenliste in `project.yml`.
- Kein `Date()`/`Date.now` in Testpfaden ohne Injektion.
- Der API-Schlüssel darf **nie** in `UserDefaults`, `BackupBundle`, `NSLog` oder
  in die Oberfläche (nur `sk-…4f2a`).
- Lokal bleibt Voreinstellung. Es gibt keinen automatischen Wechsel nach außen.
- Build: `./build.sh Debug`. Tests:
  `xcodebuild -project FlowLokal.xcodeproj -scheme ShoutTests -configuration Debug -derivedDataPath build -skipPackagePluginValidation -skipMacroValidation test`
- Ausgangswert vor Beginn: **130 Tests, 0 Fehler.** Diese Zahl darf nie sinken.
- Die App wird nicht aus `build/` gestartet (nur aus `/Applications`); geprüft
  wird über Tests und den Build, ausgeliefert über ein echtes Release.

---

# Stufe 1 — Engine-Extraktion ohne Verhaltensänderung

**Ziel dieser Stufe:** Nach Abschluss verhält sich die App exakt wie vorher. Das
ist die Probe darauf, dass der Schnitt sitzt. Nebengewinn: `Formatter` und
`Transcriber` enthalten danach keinen MLX-/WhisperKit-Bezug mehr und können
erstmals ins Testziel — heute sind beide ungetestet.

### Aufgabe 1: Textprotokoll und Attrappe

**Dateien:**
- Anlegen: `Sources/FlowLokal/TextEngine.swift`
- Anlegen: `Tests/ShoutTests/StubTextEngine.swift`
- Ändern: `project.yml` (beide Dateien in `ShoutTests`, `TextEngine.swift` auch in `ShoutMobile`)

**Schnittstelle (produziert):**

```swift
/// Ein Textmodell, das genau eine Operation beherrscht: auf eine Anweisung
/// antworten. Ob das lokal in-process (MLX) oder über HTTP passiert, weiß nur
/// die Implementierung.
protocol TextEngine: Actor {
    var isReady: Bool { get }
    var isLoading: Bool { get }
    /// Für die Oberfläche, z. B. „Gemma 4 · E4B" oder „GPT-5 mini · OpenRouter".
    var displayName: String { get }
    /// Wie groß die Abschnitte sein dürfen, die die Engine verträgt.
    var chunkTargetLength: Int { get }
    var chunkMinLength: Int { get }
    func prepare(reset: Bool, onProgress: (@Sendable (Double) -> Void)?) async
    func warmUp() async
    func respond(system: String, user: String, temperature: Float) async throws -> String
}
```

- [ ] **Schritt 1:** `TextEngine.swift` mit obigem Protokoll anlegen (keine Importe außer `Foundation`).
- [ ] **Schritt 2:** `StubTextEngine` im Testziel anlegen: Actor mit einstellbarer Antwort, Fehler-Wurf, Aufruf-Protokollierung (`recordedPrompts`), konfigurierbaren Chunk-Längen.
- [ ] **Schritt 3:** `project.yml` ergänzen, `xcodegen generate`.
- [ ] **Schritt 4:** Tests laufen lassen — 130 Tests, 0 Fehler (nichts Neues getestet, nur Kompilierfähigkeit).
- [ ] **Schritt 5:** Committen.

### Aufgabe 2: `LocalTextEngine` herausziehen

**Dateien:**
- Anlegen: `Sources/FlowLokal/LocalTextEngine.swift`
- Ändern: `Sources/FlowLokal/Formatter.swift` (MLX-Teile entfernen)
- Anlegen: `Sources/FlowLokal/EngineFactory.swift`
- Ändern: `project.yml`

**Umzug nach `LocalTextEngine`** (unverändert übernehmen, nur verschoben):
`ModelContainer`, `modelID` aus `UserDefaults["formatModel"]`, `loadChain`-freie
`performLoad`-Logik inklusive der Abkürzung „schon das richtige Modell geladen",
`warmUp`, und der `ChatSession`-Aufruf aus `respond`.

**Bleibt in `Formatter`:** `format`, `formatChunk`, `minutes`, `summarize`,
`sectionPrompt`, `respond` (nun delegierend), `describeVoice`, `stripArtifacts`,
`headings`, `loadChain` (die Serialisierung der Ladevorgänge gehört zum Router,
weil er auch den Engine-Tausch bewacht).

**`EngineFactory`** (bewusst **nicht** im Testziel, weil sie die konkreten
Engines kennt):

```swift
enum EngineFactory {
    static func text() -> any TextEngine { LocalTextEngine() }
    static func speech() -> any SpeechEngine { LocalSpeechEngine() }
}
```

`Formatter.init(makeEngine:)` nimmt die Fabrik als Closure — dadurch bleibt
`Formatter.swift` frei von MLX und wird testbar. Kein Standardwert, sonst käme
der Bezug zurück; es gibt nur zwei Aufrufstellen.

- [ ] **Schritt 1:** `LocalTextEngine.swift` anlegen, MLX-Code aus `Formatter` übernehmen, `TextEngine` erfüllen. `chunkTargetLength = 1500`, `chunkMinLength = 1000` (die heutigen `TextChunker`-Standardwerte — Verhalten bleibt identisch).
- [ ] **Schritt 2:** `Formatter` umbauen: `private let makeEngine: @Sendable () -> any TextEngine`, `private var engine: (any TextEngine)?`; `load`/`reload` erzeugen bei Bedarf eine Engine und rufen `prepare`; `respond` delegiert; `activeModelName` liefert `displayName`. Alle MLX-Importe entfernen.
- [ ] **Schritt 3:** `format` benutzt `TextChunker.chunks(of:targetLength:minLength:)` mit den Werten der Engine statt der Standardwerte.
- [ ] **Schritt 4:** `EngineFactory.swift` anlegen; `AppDelegate.swift:37` und `MobileEngine.swift:55` auf `Formatter(makeEngine: EngineFactory.text)` umstellen.
- [ ] **Schritt 5:** `project.yml`: `LocalTextEngine.swift` und `EngineFactory.swift` nach `ShoutMobile`; `Formatter.swift`, `FormatterPrompt.swift` (bereits drin) und `TextChunker.swift` (bereits drin) nach `ShoutTests`.
- [ ] **Schritt 6:** `./build.sh Debug` — muss durchlaufen.
- [ ] **Schritt 7:** Tests — 130 Tests, 0 Fehler.
- [ ] **Schritt 8:** Committen.

### Aufgabe 3: Erste echte Tests für den Router

**Dateien:**
- Anlegen: `Tests/ShoutTests/FormatterRouterTests.swift`

Das ist der Ertrag der Extraktion: Verhalten, das bisher nicht prüfbar war.

- [ ] **Schritt 1:** Test schreiben: kurzes Diktat (< 40 Zeichen) geht **ohne** Engine-Aufruf durch (`recordedPrompts.isEmpty`).
- [ ] **Schritt 2:** Test: wirft die Engine, kommt der Rohtext zurück.
- [ ] **Schritt 3:** Test: antwortet die Engine mit etwas Fremdem, greift `FormattingGuard` und der Rohtext kommt zurück.
- [ ] **Schritt 4:** Test: liefert die Engine eine leere Antwort, kommt der Rohtext des Abschnitts zurück.
- [ ] **Schritt 5:** Test: `minutes` liefert `nil`, wenn die Engine nicht bereit ist.
- [ ] **Schritt 6:** Tests laufen lassen — müssen zuerst **fehlschlagen**, wo das Verhalten noch nicht stimmt, sonst grün sein.
- [ ] **Schritt 7:** Committen.

### Aufgabe 4: `LocalSpeechEngine` herausziehen

**Dateien:**
- Anlegen: `Sources/FlowLokal/SpeechEngine.swift`
- Anlegen: `Sources/FlowLokal/LocalSpeechEngine.swift`
- Anlegen: `Tests/ShoutTests/StubSpeechEngine.swift`
- Ändern: `Sources/FlowLokal/Transcriber.swift`, `project.yml`

**Schnittstelle (produziert):**

```swift
/// Ergebnis einer Erkennung. `text` ist die fertige Fassung, wie sie das
/// Diktat einfügt; `segments` sind die Abschnitte mit Zeitmarken für Untertitel.
/// Beide getrennt, weil sie NICHT dasselbe sind: WhisperKit filtert die
/// Steuermarken in `TranscriptionResult.text` anders als in den Segmenten, und
/// manche Anbieter liefern gar keine Zeitmarken.
struct SpeechResult: Sendable {
    let text: String
    let segments: [TranscriptSegment]
}

protocol SpeechEngine: Actor {
    var isReady: Bool { get }
    var displayName: String { get }
    func prepare(reset: Bool, onProgress: (@Sendable (Double) -> Void)?) async throws
    func warmUp() async
    /// `language`: `nil` bedeutet automatische Erkennung.
    func transcribe(samples: [Float], language: String?) async throws -> SpeechResult
}
```

**Wichtig:** `SpeechResult.text` wird in `LocalSpeechEngine` genau wie heute aus
`results.map(\.text).joined(separator: " ")` gebildet, **nicht** aus den
Segmenten — sonst ändert sich das Diktat-Ergebnis.

**Bleibt in `Transcriber`:** die Sprachwahl aus
`UserDefaults["transcriptionLanguage"]` (der Router entscheidet, die Engine
führt aus), der `TranscriptPlausibility`-Wachhund samt Logger-Ausgaben, und die
Unterscheidung, dass `transcribeSegments` den Wachhund **nicht** anwendet.

- [ ] **Schritt 1:** `SpeechEngine.swift` mit Protokoll und `SpeechResult` anlegen.
- [ ] **Schritt 2:** `LocalSpeechEngine.swift` anlegen: `pipe`, iOS-Zweischritt-Download, `warmUp`, `runResults` mit den unveränderten `DecodingOptions` (inklusive `usePrefillCache = false`, `skipSpecialTokens = true` und **ohne** Wörterbuch-Prompt — der Kommentar dazu wandert mit).
- [ ] **Schritt 3:** `Transcriber` umbauen: `makeEngine`-Closure, Sprachwahl im Router, Wachhund im Router.
- [ ] **Schritt 4:** `StubSpeechEngine` anlegen.
- [ ] **Schritt 5:** Aufrufstellen von `Transcriber()` auf `Transcriber(makeEngine: EngineFactory.speech)` umstellen.
- [ ] **Schritt 6:** `project.yml` ergänzen (`ShoutMobile` **und** `ShoutTests`).
- [ ] **Schritt 7:** `./build.sh Debug`.
- [ ] **Schritt 8:** Tests + neue Router-Tests: Wachhund schlägt bei verdächtigem Transkript an, `transcribeSegments` löst ihn nicht aus, Sprache `auto` kommt als `nil` bei der Engine an.
- [ ] **Schritt 9:** Committen.

---

# Stufe 2 — Text extern

### Aufgabe 5: Anbieter-Katalog und Konfiguration

**Dateien:** Anlegen `Sources/FlowLokal/RemoteProvider.swift`,
`Tests/ShoutTests/RemoteProviderTests.swift`; ändern `project.yml`.

**Produziert:** `ProviderTemplate` (`id`, `name`, `baseURL`, `keyURL`,
`chatModels: [String]`, `audioModels: [String]`, `needsKey: Bool`, `note`),
`ProviderCatalog.all: [ProviderTemplate]`, `RemoteConfig` (`templateID`,
`baseURL`, `model`), `RemoteConfig.load(purpose:)`/`save(purpose:)` gegen
`UserDefaults`, `enum EnginePurpose { case text, audio }`,
`RemoteProviderError` mit Klartext-Beschreibungen.

Vorlagen laut Entwurf. **Bestätigt:** EURouter `https://api.eurouter.ai/v1`,
xAI `https://api.x.ai/v1`. Alle übrigen Basis-URLs vor dem Ausliefern gegen die
Dokumentation des Anbieters prüfen (eigener Schritt unten).

- [ ] Test zuerst: `RemoteConfig.chatURL` fügt korrekt zusammen — Basis mit `/v1`, ohne `/v1`, mit und ohne Schrägstrich am Ende, alles ergibt genau eine `/chat/completions`-Adresse ohne Doppel-Schrägstrich. Das ist der häufigste Tippfehler.
- [ ] Test: `audioURL` analog.
- [ ] Implementieren, Tests grün, committen.
- [ ] Eigener Schritt: **Basis-URLs und Modell-IDs aller Vorlagen** gegen die Anbieter-Dokumentation prüfen und im Katalog-Kommentar mit Prüfdatum vermerken.

### Aufgabe 6: Keychain

**Dateien:** Anlegen `Sources/FlowLokal/ProviderKeychain.swift`,
`Tests/ShoutTests/ProviderKeychainTests.swift`.

**Produziert:** `ProviderKeychain.store(_ key: String, for templateID: String) throws`,
`read(for:) -> String?`, `delete(for:) throws`, `masked(for:) -> String?`
(liefert `sk-…4f2a`).

- [ ] Test: schreiben, lesen, überschreiben, löschen, `masked` kürzt korrekt (auch bei sehr kurzen Schlüsseln, ohne den ganzen Wert zu zeigen).
- [ ] `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`, Service `com.inthezone.flowlokal.provider`, Konto = Vorlagen-ID. Tests nutzen eine eigene Service-Kennung, um die echte Keychain nicht zu verschmutzen.
- [ ] Committen.

### Aufgabe 7: `RemoteTextEngine`

**Dateien:** Anlegen `Sources/FlowLokal/RemoteTextEngine.swift`,
`Tests/ShoutTests/RemoteTextEngineTests.swift`.

**Produziert:** `actor RemoteTextEngine: TextEngine` mit
`init(config: RemoteConfig, key: String?, session: URLSession = .shared, timeout: TimeInterval)`.
`chunkTargetLength = 6000`, `chunkMinLength = 4000` beim Diktat.

- [ ] Test mit `URLProtocol`-Attrappe: gültige Antwort wird ausgepackt; `usage` wird gemeldet; HTTP 401 ergibt „Schlüssel abgelehnt"; 429 mit `Retry-After` wird als solches erkannt; Zeitüberschreitung wirft; Antwort ohne `choices` wirft statt abzustürzen.
- [ ] Test: der `Authorization`-Header ist gesetzt und taucht in keiner Fehlerbeschreibung auf.
- [ ] Implementieren, Tests grün, committen.

### Aufgabe 8: Zeitgrenzen im Router

- [ ] Test: überschreitet die Engine beim Diktat 15 s, kommt der Rohtext (Attrappen-Engine mit künstlicher Verzögerung, Testuhr injiziert).
- [ ] Test: bei `minutes` gilt die längere Grenze und **ein** Wiederholungsversuch.
- [ ] `EngineFactory.text()` liest nun `formatEngine` und baut lokal oder extern.
- [ ] Committen.

### Aufgabe 9: Oberfläche Text (macOS + iOS)

**Dateien:** Anlegen `ProviderPanel.swift` (macOS) und
`MobileProviderSection.swift` (iOS); ändern `ModelsView.swift`,
`MobileSettingsView.swift`, `Localization.swift`.

- [ ] Umschalter „Auf diesem Gerät" / „Anbieter" im Aufbereitungs-Panel beider Plattformen.
- [ ] Vorlagen-Auswahl, Schlüsselfeld mit „Ersetzen"/„Entfernen", Modellfeld mit freier Eingabe, „Verbindung testen" mit Klartext-Ergebnis, letzter Fehler.
- [ ] Bei `needsKey == false` Adressfeld mit vorbelegtem Port statt Schlüsselfeld.
- [ ] Neue `Loc.t`-Schlüssel eintragen — **vor dem Build auf Dopplung prüfen** (`grep`), sonst Startabsturz.
- [ ] Build beide Plattformen, Tests, committen.

---

# Stufe 3 — Audio extern

### Aufgabe 10: `WAVEncoder`

**Dateien:** Anlegen `Sources/FlowLokal/WAVEncoder.swift`, `Tests/ShoutTests/WAVEncoderTests.swift`.

**Produziert:** `WAVEncoder.data(from samples: [Float], sampleRate: Int = 16_000) -> Data`.

- [ ] Test: `RIFF`/`WAVE`-Kennung, `fmt `-Block, 1 Kanal, 16 kHz, 16 bit, Datenlänge = `samples.count * 2`, Gesamtlänge = 44 + Daten.
- [ ] Test: Werte werden auf −1…1 begrenzt (kein Überlauf bei übersteuerten Samples).
- [ ] Implementieren, Tests grün, committen.

### Aufgabe 11: Fensterung langer Aufnahmen

**Dateien:** Anlegen `Sources/FlowLokal/AudioWindows.swift`, `Tests/ShoutTests/AudioWindowsTests.swift`.

**Produziert:** `AudioWindows.split(samples:sampleRate:maxSeconds:overlapSeconds:) -> [(range: Range<Int>, offset: Double)]`.

Begründung im Entwurf: 25-MB-Grenze ≈ 13 Minuten bei WAV 16 kHz Mono.
Fenster 10 Minuten, 2 s Überlappung, Schnitt an der leisesten Stelle der
letzten 15 s des Fensters.

- [ ] Test: kurze Aufnahme ergibt genau ein Fenster mit Versatz 0.
- [ ] Test: 25 Minuten ergeben drei Fenster; die Versätze steigen; kein Sample fehlt.
- [ ] Test: der Schnitt liegt in der leisesten Stelle, wenn eine klare Pause vorhanden ist.
- [ ] Test: Zeitmarken werden um den Versatz verschoben; Segmente aus dem Überlappungsbereich entfallen.
- [ ] Implementieren, Tests grün, committen.

### Aufgabe 12: `RemoteSpeechEngine`

**Dateien:** Anlegen `Sources/FlowLokal/RemoteSpeechEngine.swift`, `Tests/ShoutTests/RemoteSpeechEngineTests.swift`.

- [ ] Test mit `URLProtocol`-Attrappe: `verbose_json` wird zu `SpeechResult` mit Segmenten; reine Textantwort ergibt **ein** Ersatzsegment über die Gesamtlänge; Multipart-Rumpf enthält Dateinamen, `model` und `language`; mehrere Fenster laufen der Reihe nach und werden zusammengesetzt.
- [ ] Test: ein dauerhaft scheiterndes Fenster lässt den ganzen Aufruf scheitern (keine stille Lücke).
- [ ] Implementieren, Tests grün, committen.

### Aufgabe 13: Rückfall bei Audio-Fehlern

- [ ] Test: scheitert die Fern-Erkennung und liegt ein lokales Modell vor, übernimmt es.
- [ ] Test: liegt keines vor, landet die Aufnahme als Auftrag in `FileTranscriptionQueue` statt verworfen zu werden.
- [ ] Test: der umgekehrte Weg (lokal → extern) findet **nie** automatisch statt.
- [ ] Oberfläche: Umschalter im Transkriptions-Panel beider Plattformen; Vorlagen ohne Audio-Fähigkeit sagen das hin.
- [ ] Committen.

---

# Stufe 4 — Kosten, Preise, Onboarding, Versprechen

### Aufgabe 14: Kostenzählung

**Dateien:** Anlegen `Sources/FlowLokal/ProviderCosts.swift`,
`Tests/ShoutTests/ProviderCostsTests.swift`; ändern `StatsStore.swift`,
`StatisticsView.swift`.

- [ ] Test: neue Felder in `StatsStore.Data` sind **optional**, alte Backups lesen sich unverändert ein, `BackupBundle.version` bleibt 1.
- [ ] Test: Token- und Sekundenzähler summieren pro Monat, Anbieter und Modell; Monatswechsel setzt zurück, ohne die Historie zu verlieren.
- [ ] Test: Preisrechnung ergibt bei bekannter Tabelle den erwarteten Betrag; bei unbekanntem Modell wird **keine** Zahl erfunden, sondern „Preis unbekannt" gemeldet.
- [ ] Anzeige in USD, Vorab-Schätzung im Modell-Wähler, keine Kostenanzeige bei Ollama/LM Studio/eigenem Endpunkt.
- [ ] Committen.

### Aufgabe 15: Preistabelle auf Knopfdruck

**Dateien:** Anlegen `Sources/FlowLokal/ProviderCatalogFetch.swift`, `Resources/preise.json`; Test dazu.

- [ ] Test: mitgelieferte JSON-Datei wird gelesen; Abruf ersetzt sie; misslungener Abruf lässt die vorhandene Tabelle unberührt.
- [ ] `/v1/models` je Anbieter auf Knopfdruck; Stand des letzten Abrufs wird angezeigt.
- [ ] Beschriftung „Näherung — abgerechnet wird beim Anbieter".
- [ ] Committen.

### Aufgabe 16: Onboarding-Zeile

- [ ] Je eine Zeile im Modell-Download-Schritt von `OnboardingView` und `MobileOnboardingView`: „Rechner zu schwach? Du kannst stattdessen einen eigenen Anbieter verbinden →", verlinkt auf die Modell-Ansicht. Kein zusätzlicher Schritt, kein Dialog.
- [ ] Committen.

### Aufgabe 17: Versprechen anpassen

**Dateien:** Ändern `Support/Info-iOS.plist`, `README.md`, `OFFEN.md`.

- [ ] `NSMicrophoneUsageDescription` auf den im Entwurf ausformulierten Wortlaut ändern. **Diesen Text liest die App-Store-Prüfung** — er darf zum Einreichungszeitpunkt in keine Richtung falsch sein.
- [ ] `README.md`: Einstiegsversprechen auf „by default" präzisieren, Abschnitt „Optional: bring your own provider" ergänzen, der ausdrücklich den Ollama-/LM-Studio-Fall nennt (kräftiger Rechner im eigenen Netz).
- [ ] `OFFEN.md`: Funktionsversatz zu Windows festhalten.
- [ ] Committen.

---

# Danach (nicht Teil dieses Plans)

- **Windows-Portierung** — eigener Durchgang, siehe Entwurf, Abschnitt „Portierung".
- **Agent-CLI als Engine** (`codex exec`, `claude -p`) — zurückgestellt, Begründung im Entwurf, Abschnitt „Abo-Anmeldung".
