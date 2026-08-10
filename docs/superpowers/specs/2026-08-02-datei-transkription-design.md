# Datei-Transkription (macOS)

Stand: 2026-08-02 · Status: entworfen, noch nicht umgesetzt

## Ziel

shout. kann bisher nur live diktieren: Hotkey drücken, sprechen, Text landet am
Cursor. Diese Erweiterung öffnet dieselbe Kette für **fertige Dateien** —
Audio- und Videodateien werden ausgewählt oder ins Fenster gezogen, lokal
transkribiert und als Text, `.txt` oder Untertitel-Datei (`.srt`) ausgegeben.
Alles bleibt auf dem Gerät; es kommt keine neue Abhängigkeit dazu, die ins Netz
telefoniert.

Der Kern ist bereits vorhanden: `Transcriber.transcribe(_ samples: [Float])`
nimmt fertige 16-kHz-Mono-Samples entgegen. Datei-Transkription heißt im Kern
also „Datei dekodieren statt Mikrofon aufnehmen"; Wörterbuch-Bias, Sprachbefehle
und LLM-Aufbereitung existieren unverändert weiter.

## Umfang

**Enthalten**

- Neue Seite „Dateien" in der Seitenleiste des Dashboards.
- Warteschlange: mehrere Dateien auswählen oder per Drag & Drop ablegen, serielle
  Abarbeitung, Abbrechen einzeln und gesamt.
- Audio **und** Video (Tonspur wird gezogen).
- Ausgabe: Text im Fenster (kopierbar), Speichern als `.txt`, Speichern als `.srt`
  mit Zeitmarken.
- LLM-Aufbereitung abschnittsweise, per Schalter abschaltbar.
- Zweisprachig (Deutsch/Englisch) über den bestehenden `Loc`-Mechanismus.

**Bewusst nicht enthalten**

- **Windows und iOS.** Erst am Mac fertigstellen und testen, dann nachziehen —
  wie bei Onboarding und Halten-Modus. Der Abschnitt „Portierung" hält fest, was
  dabei plattformspezifisch neu gebaut werden muss.
- **Einfügen an der Cursor-Position.** Bei einer Stunde Transkript unbrauchbar;
  Kopieren und Speichern decken den Fall ab.
- **Verlauf und Statistiken.** Begründung unten unter „Bewusste Auslassungen".
- **Sprecher-Trennung (Diarisierung).** Weder WhisperKit noch das Formatierungs-
  Modell können das; ein eigenes Modell dafür ist ein eigenes Vorhaben.
- **Finder-Integration** („Öffnen mit", Dienste-Menü, Drop aufs Dock-Icon). Lässt
  sich später ergänzen, ohne am Kern etwas zu ändern.

## Entscheidungen und ihre Gründe

### Eigene Seite statt eigenes Fenster

Die Funktion lebt als Seite **„Dateien"** in der bestehenden Seitenleiste
(`DashboardModel.Tab`), eingeordnet zwischen „Verlauf" und „Statistiken".
Alternativen wären ein separates Fenster aus der Menüleiste oder der Einstieg
über den Finder. Beides bricht mit dem Aufbau der App, in der alles im
Mischpult-Fenster liegt, und bräuchte eigene Fenster-Verwaltung. Zusätzlich
nimmt das Fenster Dateien per Drag & Drop entgegen.

### Blockweises Dekodieren statt „ganze Datei in den Speicher"

`MediaDecoder` liest die Datei mit `AVAssetReader` in **Blöcken von rund zwei
Minuten**, direkt nach 16 kHz Mono Float konvertiert. Drei Gründe:

1. **Speicher.** Eine Stunde Audio als `[Float]` sind 230 MB, drei Stunden fast
   ein Gigabyte — und WhisperKits eigene VAD-Zerlegung legt eine zweite Kopie
   daneben. Blockweise liegt der Bedarf bei rund 8 MB.
2. **Der `Transcriber` ist ein `actor`.** Ein Diktat per Hotkey während eines
   laufenden Datei-Auftrags wird serialisiert und muss warten. Bei
   2-Minuten-Blöcken sind das wenige Sekunden statt der ganzen Datei.
3. **Fortschritt und Abbrechen** werden dadurch ohne Kunstgriffe möglich: nach
   jedem Block wird der Fortschritt gemeldet und auf Abbruch geprüft.

Der Genauigkeitsverlust ist vernachlässigbar: Whisper arbeitet ohnehin in
30-Sekunden-Fenstern und trägt über die Fenstergrenze hinweg keinen inhaltlichen
Kontext mit (die Prompt-Konditionierung ist in `Transcriber.run` bewusst auf die
Wörterbuch-Begriffe begrenzt).

### Schnitt an der leisesten Stelle

Damit Blockgrenzen keine Sätze zerschneiden, sucht der Dekoder in den **letzten
30 Sekunden** eines vollen Blocks das 0,5-Sekunden-Fenster mit der geringsten
Energie (RMS) und schneidet in dessen Mitte. Der Rest wandert als Anfang in den
nächsten Block. Die Energie-Berechnung entspricht der aus
`AudioRecorder.trimSilence` und wird nicht neu erfunden. Bei durchgehend gleichem
Pegel gewinnt schlicht das erste Fenster des Suchbereichs — dann ist eine Stelle
so gut wie die andere, und ein Fehler alle zwei Minuten betrifft höchstens ein
Wort. Hart bei 120 Sekunden geschnitten wird nur, wenn der Suchbereich kleiner
ist als ein Fenster (sehr kurze Blöcke, wie in den Tests).

### Untertitel entstehen immer aus dem Rohtranskript

Sobald das LLM Füllwörter entfernt und Sätze umbaut, passt der Wortlaut nicht
mehr zu den Zeitmarken der Whisper-Segmente. Deshalb:

- **`.srt`** wird **immer** aus den Rohsegmenten geschrieben, unabhängig davon,
  ob die Aufbereitung an ist.
- **Anzeige und `.txt`** zeigen den aufbereiteten Text, wenn der Schalter an ist,
  sonst das Rohtranskript.

Beides gleichzeitig ist nicht ehrlich machbar; die Oberfläche sagt das in einer
Fußnote unter dem Untertitel-Knopf auch so.

### Sprachbefehle sind für Dateien standardmäßig AUS

Beim Diktat ist es gewollt, dass ein gesprochenes „Komma" zu `,` wird. In einer
Meeting-Aufzeichnung oder einem Interview ist es falsch — dort ist „Punkt" ein
normales Wort. Der Schalter existiert auf der Seite, steht aber standardmäßig
auf aus und ist unabhängig von der Diktat-Einstellung
(`speechCommandsEnabled` bleibt unangetastet; die Datei-Seite bekommt den
eigenen Schlüssel `fileSpeechCommandsEnabled`).

### Abschnittsweise LLM-Aufbereitung

Der Rohtext wird an Satzgrenzen in Abschnitte von rund 1500 Zeichen geteilt und
jeder Abschnitt einzeln durch das bestehende `Formatter.format` geschickt. Der
ganze Text in einem Rutsch würde bei einer Stunde Audio das Kontextfenster des
kleinen quantisierten Modells sprengen. Angenehmer Nebeneffekt: der eingebaute
Kürzungs-Schutz in `Formatter.format` (Ausgabe unter 55 % der Eingabe-Wörter →
Rohtext gewinnt) greift pro Abschnitt statt einmal über eine Stunde Text und
rettet damit nur den betroffenen Abschnitt statt alles.

## Architektur

### Neue Dateien

Alle unter `Sources/FlowLokal/`.

| Datei | Verantwortung | Abhängig von |
|---|---|---|
| `TranscriptSegment.swift` | Wertetyp: Text + Start/Ende in Sekunden. Eigener Typ statt WhisperKits `TranscriptionSegment` — nur so kommen `SubtitleWriter` und die Tests ohne den Modell-Stack aus. | Foundation |
| `MediaDecoder.swift` | `actor`: `AVAssetReader` → Folge von Blöcken (`samples: [Float]`, `startTime: Double`). Pull-Schnittstelle: `open()` liefert die Dauer, `next()` den nächsten Block, `nil` am Ende. Als actor läuft die Arbeit garantiert außerhalb des Main-Actors, ohne Closures über Actor-Grenzen zu reichen. | AVFoundation |
| `SubtitleWriter.swift` | Segmente → SRT-Text. Reine Funktion. | Foundation |
| `TextChunker.swift` | Text an Satzgrenzen in Abschnitte teilen. Reine Funktion. | Foundation |
| `TranscriptExport.swift` | Vorgeschlagene Dateinamen für den Sichern-Dialog. Reine Funktion. | Foundation |
| `FileTranscriptionQueue.swift` | `FileTranscriptionJob` (ein Auftrag: Zustand, Fortschritt, Ergebnis) und `FileTranscriptionQueue`, die sie seriell abarbeitet. Beide zusammen in einer Datei, weil sie nur miteinander Sinn ergeben. | Transcriber, Formatter, PersonalDictionary |
| `FilesView.swift` | Die Seite. | SwiftUI, FileTranscriptionQueue |
| `TranscriptWindowView.swift` | Inhalt des Ergebnisfensters. | SwiftUI, FileTranscriptionJob |

`TextChunker` arbeitet nach einer bewusst einfachen Regel: vom Zielmaß (1500
Zeichen) aus rückwärts die letzte Stelle suchen, an der auf `.`, `!` oder `?` ein
Leerraum und ein Großbuchstabe folgt. Zusätzlich ausgeschlossen sind einzelne
Buchstaben und eine kurze Liste von Abkürzungen davor („z. B.", „Dr."). Findet
sich keine solche Stelle, wird am Zielmaß hart geteilt.

### Änderungen an bestehenden Dateien

- **`Transcriber.swift`** — neue Methode
  `transcribeSegments(_ samples: [Float], biasTerms: [String]) async throws -> [TranscriptSegment]`.
  Sie kapselt den WhisperKit-Aufruf und liefert `TranscriptionSegment.start/.end`
  (Sekunden, `Float` → `Double`) durch. Das bestehende `transcribe(_:biasTerms:)`
  bleibt in Signatur und Verhalten unverändert — inklusive der
  Plausibilitätsprüfung gegen den Bias-Prompt, die nur für Diktate sinnvoll ist
  (kurze Aufnahme, ein Durchgang) und für Dateien deshalb nicht gilt.
- **`Formatter.swift`** — neue Methode
  `formatLong(_ raw: String, termHint: String?) async -> String`: teilt über
  `TextChunker`, ruft je Abschnitt `format(_:bundleID: nil, termHint:)` auf,
  fügt mit `\n\n` zusammen. `bundleID` ist `nil`, weil es bei einer Datei keine
  Ziel-App gibt, deren Tonfall man treffen könnte. Der Absatzumbruch an der
  Abschnittsgrenze ist gewollt: ein einstündiges Transkript als eine einzige
  Textwand ist unlesbar, und alle 1500 Zeichen ein Absatz an einer Satzgrenze
  trifft es näher als gar keine Gliederung.
- **`DashboardView.swift`** — `Tab.dateien` im Enum, Zeile in der Seitenleiste
  (Symbol `doc.text.below.ecg`), Verzweigung im `detail`-Block.
- **`AppDelegate.swift`** — hält die `FileTranscriptionQueue`, reicht sie ans
  Dashboard durch, blockiert Modellwechsel bei laufender Warteschlange (siehe
  „Zusammenspiel"), fragt beim Beenden nach und verwaltet die Ergebnisfenster
  (`[UUID: NSWindow]`).
- **`Localization.swift`** — englische Entsprechungen für die neuen Texte.
- **`project.yml`** — neues Test-Target (siehe „Tests").

### Datenfluss

```
Datei
  │
  ├─ MediaDecoder: AVAssetReader → 16 kHz Mono Float,
  │                Blöcke à ~120 s, Schnitt an der leisesten Stelle
  │
  ├─ pro Block: Transcriber.transcribeSegments(biasTerms: Wörterbuch)
  │             → Segmente mit Zeitmarken, um die Blockstartzeit versetzt
  │
  ├─ pro Segment: optional Sprachbefehle → Wörterbuch-Korrekturen
  │               ⇒ ergibt die Rohsegmente (Grundlage für .srt)
  │
  ├─ Rohsegmente verbunden ⇒ Rohtranskript
  │
  └─ optional: Formatter.formatLong(Rohtranskript) ⇒ aufbereiteter Text
```

Sprachbefehle und Wörterbuch-Korrekturen werden **pro Segment** angewandt, nicht
auf den zusammengefügten Text. Sonst würden die Segment-Texte der `.srt` nicht
mehr zu dem passen, was in der Anzeige steht.

### Zustand eines Auftrags

```swift
enum JobState {
    case queued
    case decoding(progress: Double)   // 0…1, aus verarbeiteter/gesamter Dauer
    case formatting(progress: Double) // LLM-Abschnitte
    case done
    case failed(String)               // Klartext-Grund für die Oberfläche
    case cancelled
}
```

Ergebnisse (`segments`, `rawText`, `formattedText`) leben nur zur Laufzeit im
Auftrag. Nichts wird automatisch auf die Platte geschrieben — Speichern ist
immer eine bewusste Handlung über `NSSavePanel`.

### Zusammenspiel mit dem Diktat

- **Diktat während eines Datei-Auftrags** ist erlaubt. Der `Transcriber`-Actor
  serialisiert; das Diktat wartet höchstens einen Block (Größenordnung Sekunden
  auf Apple Silicon). Die Warteschlange läuft danach weiter.
- **Modellwechsel während eines Datei-Auftrags** wird abgelehnt — wie bei
  Aufnahme und Verarbeitung. `switchASRModel` und `switchFormatModel` prüfen
  zusätzlich `queue.isRunning` und setzen denselben Hinweis in
  `dashboardModel.modelNote`. Ohne diese Sperre lägen bei einem Wechsel des
  Formatierungsmodells zwei Multi-GB-Modelle gleichzeitig im Unified Memory.
- **Kein Transkriptionsmodell geladen** → die Seite zeigt denselben Hinweis wie
  das Onboarding statt eines Knopfs, der nichts tut
  (`dashboardModel.transcriberReady`).

## Oberfläche

Karten-Look wie die übrigen Seiten (`Color.shoutPanel`, `Color.shoutInset`,
Akzent `Color.shoutLive`).

**Kopfbereich — Ablagefläche.** Gestrichelter Rahmen, „Dateien hierher ziehen"
plus Knopf „Auswählen …" (`NSOpenPanel`, Mehrfachauswahl,
`allowedContentTypes: [.audio, .movie]` — die konkreten Formate wie MP3, WAV,
M4A, MP4 und MOV entsprechen diesen beiden Obertypen, eine längere Liste wäre
nur redundant). Beim Ziehen über das Fenster hebt sich der Rahmen in der
Akzentfarbe hervor.

**Zwei Schalter.**

- „Text aufbereiten" — Standard **an**; ausgegraut mit erklärendem Hinweis, wenn
  kein Formatierungsmodell geladen ist. Schlüssel: `fileFormattingEnabled`.
- „Sprachbefehle anwenden" — Standard **aus**, mit kurzem Hinweistext, warum
  (siehe Entscheidung oben). Schlüssel: `fileSpeechCommandsEnabled`.

**Auftragsliste.** Pro Zeile: Dateiname, Dauer, Zustand. Bei laufendem Auftrag
ein Fortschrittsbalken und ein Abbrechen-Kreuz; bei Fehlern der Grund in
Klartext; bei Erfolg die Wortzahl und ein Knopf „Öffnen". Ab zwei offenen
Aufträgen zusätzlich „Alle abbrechen".

Ein **Ergebnisbereich auf der Seite selbst gibt es nicht.** Ein Textfeld von
220 Punkt Höhe trägt bei einem einstündigen Transkript nicht; man scrollt darin
herum, statt zu lesen. Das Ergebnis lebt stattdessen in einem eigenen Fenster
(nächster Abschnitt). Damit ist die Seite genau eine Sache: Dateien annehmen,
Verarbeitung einstellen, Warteschlange verfolgen.

Alle Texte laufen über `Loc.t` / `Loc.f`; die Seite hängt wie das übrige
Dashboard am `.id(loc.language)`-Neuaufbau.

## Das Ergebnisfenster

Ein eigenes Fenster pro Auftrag (`TranscriptWindowView`), geöffnet per Doppelklick
auf die Zeile oder über den Knopf „Öffnen". Der `AppDelegate` hält die Fenster in
einem `[UUID: NSWindow]`: Ein zweiter Doppelklick holt das bestehende Fenster nach
vorn statt ein zweites zu öffnen, beim Schließen fliegt es aus dem Verzeichnis,
und wer den Auftrag aus der Liste entfernt, schließt damit auch sein Fenster.
Mehrere Fenster staffeln sich versetzt. Größe 820 × 620, frei veränderbar,
Mindestmaß 620 × 420. Titel: „shout. — Interview.m4a".

**Zwei Fassungen, eine aktive.** Oben ein Segment-Umschalter „Aufbereitet |
Rohtext". Die dort gewählte Fassung ist die **aktive**: sie füllt das Fenster, sie
ist bearbeitbar, und die Export-Knöpfe beziehen sich auf genau sie. Der Knopf
„Vergleichen" blendet die jeweils andere Fassung als zweite Spalte ein — **nur
lesbar**. Diese Asymmetrie ist Absicht: Wären beide Spalten bearbeitbar, wäre bei
jedem Klick auf „Sichern" unklar, welcher der beiden Texte gemeint ist. Zum
Bearbeiten der anderen Fassung legt man den Umschalter um; dann tauschen die
Spalten ihre Rollen.

Wurde nicht aufbereitet (Schalter aus oder kein Formatierungsmodell geladen), gibt
es nur eine Fassung: Umschalter und „Vergleichen" entfallen, darüber steht „Rohtext".

**Bearbeiten.** Beide Fassungen sind echte Textfelder; Änderungen schreiben direkt
in `job.rawText` bzw. `job.formattedText` und gelten für alles Weitere — Kopieren,
Sichern, die Wortzahl in der Auftragszeile. Sie überleben das Schließen des
Fensters, aber nicht das Beenden der App (wie alle Ergebnisse, siehe „Bewusste
Auslassungen").

**Die Untertitel bleiben von Änderungen unberührt.** Die `.srt` entsteht weiterhin
aus `job.segments` mit ihren Zeitmarken, nicht aus dem bearbeiteten Text. Alles
andere hieße, jeden Tastendruck einer Zeitmarke zuzuordnen — ein eigenes Vorhaben.
Der Hinweis unter dem Knopf sagt das.

**Export unten im Fenster.**

- „Kopieren" — die aktive Fassung in die Zwischenablage.
- „Als Text sichern …" — `NSSavePanel`. Der vorgeschlagene Name trägt die Fassung
  mit: `Interview.txt` für die aufbereitete, `Interview-roh.txt` (englisch
  `-raw`) für den Rohtext. Ohne diesen Zusatz überschriebe das zweite Sichern
  stillschweigend die erste Datei. Der Zusatz entfällt, wenn es ohnehin nur eine
  Fassung gibt.
- „Untertitel sichern …" — `Interview.srt`, immer aus den Segmenten; ausgegraut,
  wenn keine vorliegen.
- Statuszeile darunter („Gesichert: …", „Sichern fehlgeschlagen: …").

Die Namensbildung steckt in `TranscriptExport` — eine reine Funktion, damit sie
ohne Fenster testbar ist.

## Fehlerbehandlung

| Fall | Verhalten |
|---|---|
| Datei ohne Tonspur | Auftrag → `failed("Diese Datei enthält keine Tonspur.")`, übrige laufen weiter |
| DRM-geschützt / nicht lesbar | `failed` mit dem Systemfehler in Klartext |
| Format von AVFoundation nicht unterstützt | `failed("Dieses Format kann nicht gelesen werden.")` |
| Tonspur ist reine Stille | `done` mit leerem Transkript und Hinweis „Kein gesprochener Inhalt erkannt." |
| Transkription wirft | `failed`, Warteschlange läuft weiter |
| LLM-Aufbereitung wirft | Rohtranskript gewinnt (Verhalten von `Formatter.format`), Auftrag bleibt `done` |
| Abbrechen | Nach dem laufenden Block; Teilergebnisse werden verworfen |
| App-Beenden bei laufender Warteschlange | Nachfrage über `applicationShouldTerminate` |
| Speichern schlägt fehl | Warnhinweis, Ergebnis bleibt im Fenster erhalten |

Die App ist nicht sandboxed; trotzdem kommt der Lesezugriff ausschließlich aus
der Dateiauswahl oder dem Drop, und Schreibzugriff ausschließlich aus dem
`NSSavePanel` — damit bleibt der Weg auch dann gangbar, wenn die App später in
die Sandbox wandert.

## Tests

Das Projekt hat bisher kein Test-Target. Diese Erweiterung bringt das erste mit:
ein eigenständiges Unit-Test-Bundle in `project.yml`, das **keine Host-App**
braucht und nur die reinen Dateien mitkompiliert (`TranscriptSegment.swift`,
`SubtitleWriter.swift`, `TextChunker.swift`, `TranscriptExport.swift`,
`MediaDecoder.swift`) — damit hängt es weder an WhisperKit noch an MLX und läuft
in Sekunden. `Package.swift` bleibt unverändert, weil der echte Build ohnehin
über XcodeGen und `xcodebuild` läuft (MLX kompiliert seine Metal-Shader nur so).

**Automatisiert**

- `SubtitleWriter`: Zeitformat `00:01:23,456`, laufende Nummerierung ab 1,
  Leerzeile zwischen Einträgen, Segmente ohne Text werden übersprungen,
  Segmente über eine Stunde, Zeitversatz durch die Blockstartzeit.
- `TextChunker`: Teilung an Satzgrenzen, Text ohne jedes Satzzeichen (harte
  Teilung statt Endlosschleife), Text kürzer als ein Abschnitt, leerer Text,
  Abkürzungen mit Punkt lösen keine Teilung mitten im Satz aus.
- `MediaDecoder`: Schnitt landet in der Stille-Lücke, zu kurzer Puffer wird nicht
  geschnitten, Dauer und Abtastrate einer echt geschriebenen WAV, lückenlose
  Startzeiten über mehrere Blöcke, Tonspur aus einer `.mov` mit H.264-Bild- und
  AAC-Tonspur, Datei ohne Tonspur wirft.
- `TranscriptExport`: Name mit und ohne Rohtext-Zusatz, Quelldatei ohne Endung,
  Quelldatei mit Punkten im Namen, Untertitel-Endung.

**Von Hand in der laufenden App** (aus `/Applications`, kein Debug-Build)

- Kurze Audiodatei, lange Audiodatei (> 30 Minuten), Videodatei mit Tonspur,
  Videodatei ohne Tonspur, defekte Datei.
- Blockgrenzen: ein durchgehend gesprochener Text über mehrere Blöcke ergibt an
  den Übergängen keine verlorenen oder doppelten Wörter.
- Abbrechen mitten im Lauf, Abbrechen der ganzen Warteschlange.
- Diktat per Hotkey während eines laufenden Datei-Auftrags.
- `.srt` in einem Videoschnitt-Programm oder VLC laden — Zeitmarken sitzen.
- Oberflächensprache umschalten, während die Seite offen ist.
- Ergebnisfenster: Doppelklick und „Öffnen" führen zum selben Fenster, ein
  zweiter Doppelklick öffnet kein zweites; Umschalter und Vergleichsspalte;
  Bearbeiten wirkt sich auf Kopieren, Sichern und die Wortzahl in der Zeile aus,
  aber nicht auf die `.srt`; Auftrag entfernen schließt sein Fenster.

## Portierung (später, eigene Runde)

- **Windows** — die Kette ist identisch (`TranscribeAsync(float[])` existiert),
  neu sind nur der Dekoder und die Oberfläche. Für Video braucht es dort
  FFmpeg oder die Media Foundation; NAudio allein liest keine Videocontainer.
  Whisper.net liefert Segmente mit Zeitmarken, `.srt` ist also möglich.
- **iOS** — Dateiauswahl über `UIDocumentPicker`; die Frage ist weniger die
  Technik als die Laufzeit: eine Stunde Audio auf dem iPhone dauert spürbar und
  braucht Nachdenken über Hintergrund-Ausführung und Wärme.

Beide Punkte gehören nach der Umsetzung in `OFFEN.md`, damit der Versatz
zwischen den Plattformen sichtbar bleibt.

## Bewusste Auslassungen

**Verlauf und Statistiken bleiben außen vor.** `StatsStore.record` rechnet aus
Wörtern und Sekunden die durchschnittlichen Wörter pro Minute und pflegt die
„aktiven Tage" für den Streak. Eine Stunde fremdes Audio wirft beide Zahlen um:
Der Wert misst, wie schnell **du** diktierst, und ein Streak-Tag steht für „heute
diktiert", nicht „heute eine Datei geöffnet". Der Verlauf wiederum ist auf 300
Einträge gedeckelt, wandert in die Backup-Datei und hat als Hauptfunktion
„nochmal einfügen" — ein 40.000 Zeichen langes Transkript würde ihn verstopfen
und die Sicherung aufblähen.

**Kein Zwischenspeichern von Ergebnissen.** Wer die App schließt, verliert nicht
gesicherte Transkripte. Das ist eine bewusste Abwägung gegen einen zweiten
Speicherort mit eigener Verwaltung, Größenbegrenzung und Aufräum-Logik. Sollte
sich das im Gebrauch als Ärgernis zeigen, ist es eine kleine, saubere
Nachrüstung: Ergebnis und Segmente eines Auftrags sind schlichte Werte, die sich
über den vorhandenen `StoreIO` sichern ließen.
