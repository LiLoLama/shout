# Neuigkeiten: Update-Log, „Neu in shout.“-Fenster und Erklär-Animation

Stand: 2026-10-07 · Plattform: macOS (iOS und Windows später, siehe unten)

## Ziel

Nach einem Update erfährt man einmal, was neu ist — mit einer kurzen Animation,
wenn sich ein Ablauf erst im Bewegtbild erschließt (zuerst: das Scratchpad aus
1.13.0). Das Fenster lässt sich überspringen. Alle Versionen bleiben auf einer
Seite „Neuigkeiten“ nachlesbar, und dieselbe Quelle liefert die Release-Notes auf
GitHub.

## Nicht Teil dieser Spec

- iOS und Windows (eigene Versionsnummern, eigener Auslieferweg). Als offener
  Punkt in `OFFEN.md`.
- Inhalte aus dem Netz. Alles liegt im App-Bundle.
- Ein Punkt oder Zähler in der Seitenleiste.

## 1 · Quelle und Ablauf

### `CHANGELOG.md` (Repo-Wurzel, neueste Version oben)

```markdown
# shout. — Neuigkeiten

## 1.13.0 — 2026-10-07
zeigen: ja
video: scratchpad

### Deutsch
**Neu: das Scratchpad.** Ein schwebender Notizblock …
- ⌃⌥N blendet ihn ein, halten diktiert hinein.

### English
**New: the Scratchpad.** A floating notepad …
- Tap ⌃⌥N to show it, hold it to dictate into it.
```

- Kopfzeile `## <Version> — <JJJJ-MM-TT>` (Gedankenstrich U+2014, auch `-` wird angenommen).
- Pflichtzeile `zeigen: ja|nein`. Optional `video: <name>` (Name einer Animation in
  `Resources/Explainers/<name>.html`).
- Pflichtblöcke `### Deutsch` und `### English`, jeweils Markdown (Absätze, `**fett**`,
  Listen mit `- `). Alles bis zur nächsten `###`- bzw. `##`-Zeile gehört zum Block.
- Text vor der ersten `##`-Zeile ist Vorspann und wird ignoriert.
- Die Datei wird als Ressource ins App-Bundle kopiert.

### `ChangelogParser` (rein, Foundation)

`static func parse(_ text: String) -> [ChangelogEntry]` mit
`ChangelogEntry { version: AppVersion, date: String, highlight: Bool, video: String?, german: String, english: String }`.
Ein fehlerhafter Abschnitt (Kopfzeile kaputt, `zeigen` fehlt, ein Sprachblock fehlt
oder ist leer) wird übersprungen und per `NSLog` gemeldet. Nie ein Absturz.
Ergebnis nach Version absteigend sortiert, doppelte Versionen: der erste gewinnt.

### `AppVersion` (rein)

`init?(_ string: String)` aus „1.13.0“, „1.13“ oder „2“; Vergleich komponentenweise
numerisch, fehlende Stellen gelten als 0 (1.13 == 1.13.0, 1.13.10 > 1.13.9).

### `WhatsNewDecider` (rein)

`static func entriesToShow(all: [ChangelogEntry], lastSeen: AppVersion?, current: AppVersion, onboardingDone: Bool) -> [ChangelogEntry]`

- `onboardingDone == false` → leer (Neuinstallation; das Onboarding zeigt alles).
- `lastSeen == nil` und Onboarding erledigt → `lastSeen` gilt als **1.12.0**
  (`WhatsNewDecider.baseline`): die letzte Version vor diesem Feature.
- Sonst alle Einträge mit `highlight`, `version > lastSeen` und `version <= current`,
  neueste zuerst.

### Zustand

UserDefaults `whatsNew.lastSeenVersion` (String). Gesetzt auf die laufende Version:
- am Ende des Onboardings (Neuinstallation),
- beim Schließen des Fensters (gelesen, übersprungen, Esc, Schließen-Knopf),
- wenn der Decider nichts zu zeigen hat (damit die Basislinie nicht später greift).

### Release

- `release.sh` prüft vor dem Bauen mit `Support/release-notes.sh --check <version>`,
  dass `CHANGELOG.md` einen gültigen Abschnitt für `MARKETING_VERSION` hat; sonst Abbruch.
- `Support/release-notes.sh <version>` gibt die Release-Notes für `gh release create
  --notes-file -` aus: deutscher Block, Trennlinie, englischer Block (ohne die
  Steuerzeilen `zeigen:`/`video:`).
- Rückwirkend eingetragen: 1.13.0 (Scratchpad, `zeigen: ja`, `video: scratchpad`),
  1.12.0, 1.11.1, 1.11.0 (`zeigen: nein`, Text aus den GitHub-Releases).

## 2 · Oberfläche

### Fenster „Neu in shout.“ (`WhatsNewWindow` + `WhatsNewView`)

- Eigenes Fenster wie das Onboarding, mittig, etwa 760 × 580, dunkler App-Stil.
- Kopf: „Neu in shout. <Version>“. Darunter, falls der Eintrag ein Video hat, der
  Player (16:10); darunter der Text des Eintrags (Markdown, scrollbar).
- Mehrere Einträge: eine Seite je Version, neueste zuerst; rechts „Weiter“, auf der
  letzten Seite „Fertig“. Links immer „Überspringen“ (schließt alles). Esc und der
  Schließen-Knopf wirken wie „Überspringen“.
- Zeitpunkt: 2 s nach dem Start, wenn kein Onboarding offen ist und keine Aufnahme
  läuft; sonst wird nach Ende der Aufnahme erneut geprüft. Das Fenster holt shout.
  nach vorn (die App ist ein Menüleisten-Programm).
- Menüpunkt „Neuigkeiten …“ im App-Menü öffnet die Seite „Neuigkeiten“.

### Seite „Neuigkeiten“ (`DashboardModel.Tab.neuigkeiten`)

- Letzter Eintrag der Seitenleiste, Symbol `sparkles`.
- Alle Einträge untereinander, neueste oben: Version, Datum, Text. Einträge mit
  Video: Knopf „Video ansehen“ öffnet den Player in einem Blatt.

### Player (`ExplainerView`)

- `NSViewRepresentable` um `WKWebView`; lädt `Resources/Explainers/<name>.html`
  per `loadFileURL` mit Lesezugriff nur auf diesen Ordner. Navigation nach außen
  wird abgelehnt; kein Netz.
- Parameter in der URL: `lang=de|en` (aus `Loc`), `muted=1`, `keys=<Scratchpad>,<Eingang>`
  (die aktuell eingestellten Tasten als Anzeige-Text; leer → Vorgabe).
- Native Steuerleiste darunter (SwiftUI): Abspielen/Pause, Neustart, Ton an/aus.
  Aufrufe per `evaluateJavaScript` an `window.explainer.{play,pause,restart,setMuted}`;
  die Seite meldet `ended` und `state` über `window.webkit.messageHandlers.explainer`.
- Startet von selbst stumm. Mit „Bewegung reduzieren“ startet es nicht, sondern
  zeigt das erste Bild mit Abspiel-Knopf.
- Fehlt die Datei oder lädt sie nicht: der Player fällt weg, der Text bleibt.

## 3 · Die Animation „Scratchpad“

Eine einzelne HTML-Datei `Resources/Explainers/scratchpad.html` — Canvas, ohne
Netz, ohne externe Schriften (Systemschrift), deterministisch über `render(t)`.
Dieselbe Datei läuft in der App (Echtzeit) und wird für GitHub/Social zu MP4
gerendert (`Support/explainer-video/render.mjs`, Muster wie `Support/launch-video`).

**Länge ~40 s, 1600 × 1000 Bühne, Stil wie die App (Graphit, Akzent #FF4A0A).**
Jede Szene hat eine Bildunterschrift (DE/EN), Tasten erscheinen als Tastenkappen.

1. 0–3 s · Titel „Neu: das Scratchpad“.
2. 3–12 s · Ein angedeuteter Schreibtisch mit Mail im Hintergrund. Tastenkappe ⌃⌥N
   (angetippt) → das Panel gleitet oben rechts herein. Dann gehalten → Pille mit
   Pegel, Text erscheint Wort für Wort im Panel. Unterschrift: „Antippen blendet
   ein · Halten diktiert hinein“.
3. 12–18 s · Tastenkappe ⌃⌥I, kein Fenster, Toast „Im Eingang notiert“ oben rechts.
   Unterschrift: „Schnell festhalten – ohne Fenster“.
4. 18–27 s · Zauberstab-Menü → „Als Mail“ → Fortschritt → der Text wird zur Mail
   (Anrede, Absätze, Gruß); Balken „Als Mail umgeschrieben · Rückgängig“.
   Unterschrift: „Umarbeiten mit deinem Textmodell“.
5. 27–34 s · Tastenkappe ⌘⏎ → Panel blendet aus, der formatierte Text erscheint im
   Mail-Fenster. Unterschrift: „⌘⏎ legt formatiert in die App davor ab“.
6. 34–40 s · Ordner mit `Ideen Team-Meeting.md`, `Eingang.md`, daneben dieselbe
   Notiz in einer Obsidian-artigen Ansicht. Unterschrift: „Jede Notiz ist eine
   Markdown-Datei – in iCloud oder Obsidian“. Schlusskarte mit den drei Tasten.

**Ton:** per WebAudio erzeugt (Tastenklick, Mikrofon-Signal, kurzer „Ping“ beim
Ablegen). In der App anfangs stumm; im MP4 an.

**Schnittstelle der Seite:** `window.explainer = { ready, duration, play(), pause(),
restart(), setMuted(bool), frame(t, quality) → JPEG-Base64, renderAudio() → WAV-Base64 }`.
`?export` schaltet auf feste Bühnengröße ohne eigene Bedienelemente.

## 4 · Fehlerfälle

| Fall | Verhalten |
|---|---|
| `CHANGELOG.md` fehlt im Bundle | Seite zeigt „Keine Neuigkeiten gefunden.“, kein Fenster |
| Abschnitt fehlerhaft | übersprungen, Log-Eintrag; übrige Einträge normal |
| Animation fehlt/lädt nicht | Player entfällt, Text bleibt |
| Version im Bundle nicht lesbar | kein Fenster, `lastSeen` bleibt unverändert |
| Aufnahme läuft beim Start | Fenster erst nach der Aufnahme |

## 5 · Tests

- `ChangelogParser`: gültiger Abschnitt, Vorspann, beide Gedankenstrich-Formen,
  fehlendes `zeigen`, fehlender Sprachblock, leerer Block, `video` optional,
  Sortierung, doppelte Version, Markdown im Block bleibt unverändert.
- `AppVersion`: Parsen, 1.13 == 1.13.0, 1.13.10 > 1.13.9, ungültig → nil.
- `WhatsNewDecider`: Neuinstallation leer, fehlendes `lastSeen` → Basislinie 1.12.0,
  übersprungene Versionen zusammengefasst, nur `zeigen: ja`, nichts über `current`.
- Die echte `CHANGELOG.md` des Repos parst ohne übersprungene Abschnitte, und für
  die `MARKETING_VERSION` aus `project.yml` gibt es einen Eintrag (Test liest die Datei
  über einen Pfad relativ zur Testdatei).
- `release-notes.sh`: `--check` scheitert bei fehlender Version; Ausgabe enthält
  beide Blöcke und keine Steuerzeilen (Shell-Aufruf aus einem XCTest heraus).
- Animation: Einzelbilder per `render.mjs --stills` für jede Szene ansehen; kein
  Seitenfehler in der Konsole; `duration` ≈ 40 s.
- Prüfliste am Gerät (Release aus `/Applications`): Fenster erscheint einmal nach dem
  Update, Überspringen merkt sich das, Seite „Neuigkeiten“, Video mit Ton, Englisch.
