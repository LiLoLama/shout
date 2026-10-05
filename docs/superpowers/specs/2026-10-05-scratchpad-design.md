# Scratchpad: Notizen per Stimme, als Markdown-Dateien im eigenen Ordner

Stand: 2026-10-05 · Plattform: macOS (iOS und Windows später, je eigene Spec)

## Ziel

Ein schwebender Notizblock, in den man diktiert und tippt. Er dient zwei Zwecken
gleich oft:

- **Festhalten:** Ideen, To-dos, Merkzettel schnell loswerden. Die Notiz bleibt
  liegen, wird später gesucht oder in Obsidian weiterbearbeitet.
- **Ausformulieren:** einen längeren Text zusammendiktieren, überarbeiten und
  dann in die App bringen, aus der man kam.

Vorbild ist das Scratchpad von Wispr Flow (Option+S, schwebendes Panel, Tabs,
Notizliste, Sync über deren Cloud). shout. macht drei Dinge bewusst anders:

1. **Kein Konto, keine eigene Cloud.** Jede Notiz ist eine `.md`-Datei in einem
   Ordner, den der Mensch wählt. Liegt er in iCloud Drive oder Dropbox, synct es
   von selbst; liegt er in einem Obsidian-Vault, ist dort alles sofort lesbar.
   Wispr selbst nennt bei seinem Sync „occasional syncing issues“.
2. **Festhalten ohne Fenster.** Eine eigene Taste hängt ein Diktat an die
   Eingangs-Notiz, ein Toast bestätigt — kein Panel geht auf.
3. **Lokale Transforms im Panel** (Aufräumen, Als Mail, Zusammenfassen, To-dos,
   Ins Englische, eigene Prompts, Anweisung per Stimme) über das ohnehin
   geladene Textmodell.

## Nicht Teil dieser Spec

- iOS und Windows. Beide kommen als eigene Spec und stehen in `OFFEN.md`.
- Unterordner im Notizordner (werden beim Einlesen übersprungen).
- Echtes WYSIWYG: Markdown-Zeichen bleiben sichtbar, nur gedimmt.
- Sync-Logik jeder Art. Den Abgleich macht, wer den Ordner verwaltet.

## Was es schon gibt

| Baustein | Ort | Nutzen |
|---|---|---|
| Diktat-Pipeline | `AppDelegate.stopAndProcess()` (:1368) | einzige Stelle zwischen `final` (:1396) und `injector.paste` (:1410) — hier wird abgezweigt |
| Schwebendes Panel | `RecordingIndicator.swift` (:364), `MeetingPrompt.swift` (:160) | Rezept für nonactivating, alle Spaces, Ziehen |
| Speichern | `StoreIO` (atomares Schreiben, Umbenennen beschädigter Dateien) | wird für Versionen und Transforms übernommen |
| Textmodell | `TextEngine.respond`, `Formatter.respond` (privat, :279) | Grundlage für Transforms |
| Vorige App | `lastExternalApp`, `insertFromHistory` (:466) | Ziel fürs Ablegen |
| Namen säubern | `MeetingRecorder.rename` | Dateinamen und „Titel 2“ |
| Toast | `LearnedToast.swift` | „Im Eingang notiert“ |
| Seitenleiste | `DashboardModel.Tab` (`DashboardView.swift`:6) | neue Seite „Notizen“ |

Heute gibt es **keine** Notizfunktion, keinen iCloud-Code und keinen Hotkey, der
Tasten abfängt (nur `NSEvent`-Monitore).

## 1 · Datenmodell und Speicher

### Ordner

Voreinstellung `~/Documents/shout Notizen/` (im Finder „Dokumente“), änderbar
auf der Seite „Notizen“. Die Mac-App läuft ohne Sandbox, der Pfad steht als
String in den UserDefaults (`notesFolderPath`), ein Bookmark ist nicht nötig.

Eingelesen werden die `.md`-Dateien **direkt im Ordner**. Übersprungen werden
Unterordner, alles mit führendem Punkt und `Anhänge/`. Ein Ordnerwechsel
verschiebt nichts; die Liste zeigt dann den neuen Ordner.

### Eine Notiz ist eine Datei

```markdown
---
created: 2026-10-05T14:32:00+02:00
pinned: true
---
Text …
```

- Schlüssel englisch (`created`, `pinned`): Obsidian-Standard, Properties und
  Dataview erkennen sie.
- `pinned` steht nur da, wenn die Notiz angeheftet ist.
- Eine Datei **ohne** Frontmatter (aus Obsidian, von Hand angelegt) ist gültig;
  `created` fällt dann auf das Erstelldatum der Datei zurück und wird erst beim
  nächsten Speichern geschrieben.
- **Unbekannte Felder bleiben erhalten** (`tags`, `aliases` …), in ihrer
  Reihenfolge und wörtlich. Geparst werden nur `created` und `pinned`; der Rest
  wird als Rohzeilen mitgeführt.
- Zeilenenden: CRLF wird gelesen, geschrieben wird LF.
- Änderungsdatum = mtime der Datei. Erstelldatum steht im Frontmatter, weil
  Sync-Dienste das Dateidatum verfälschen.

Im Speicher:

```swift
struct Note: Identifiable, Equatable {
    let id: UUID            // nur zur Laufzeit, nicht in der Datei
    var fileName: String    // "Newsletter-Idee Oktober.md"
    var title: String       // fileName ohne .md
    var body: String        // ohne Frontmatter
    var created: Date
    var modified: Date
    var pinned: Bool
    var extraFrontmatter: [String]   // unbekannte Zeilen, unverändert
    var titleIsFixed: Bool  // siehe Titelregel
}
```

Die `id` ordnet Tabs und laufende Diktate einer Notiz zu, auch wenn die Datei
umbenannt wird. Über Neustarts hinweg identifiziert der Dateiname.

### Titelregel

- Der Titel ist der Dateiname.
- Neue Notiz ohne Text: wird nicht angelegt (auch keine leere Datei).
- Beim ersten Speichern: Titel aus den ersten bis zu fünf Wörtern der ersten
  nichtleeren Zeile, führende `#`, `-`, `*`, `>` und `[ ]` entfernt.
- **Solange der Text weniger als drei Wörter hat**, darf der Name bei jedem
  Speichern mitwandern. Ab drei Wörtern ist er fest (`titleIsFixed = true`) und
  ändert sich nur noch durch ausdrückliches Umbenennen.
- Notizen, die beim Start schon im Ordner liegen, gelten immer als fest.
- Säubern wie `MeetingRecorder.rename`: `/`, `:`, führende Punkte raus,
  höchstens 60 Zeichen, bei Namensgleichheit „Titel 2“, „Titel 3“. Der
  Vergleich ist **ohne Groß-/Kleinschreibung** (APFS ist es standardmäßig auch).
- Leerer Titel nach dem Säubern → „Unbenannt“.

### Eingangs-Notiz

`Eingang.md`, ein normaler Eintrag in der Liste (angeheftet beim ersten Anlegen).
Jedes Eingangs-Diktat wird **unten** angehängt, unter einer Tagesüberschrift im
eingestellten Sprachformat:

```markdown
## Sonntag, 5. Oktober 2026
- **14:32** Milch und Kaffee kaufen
- **15:10** Idee: Pille vertikal auch unter Windows
```

Fehlt die Überschrift des heutigen Tages am Ende der Datei, wird sie angelegt.
Mehrzeilige Diktate werden unter dem Spiegelstrich mit zwei Leerzeichen
eingerückt. Benennt der Mensch die Datei um, gilt der neue Name weiter als
Eingang (gemerkt in `inboxFileName`); wird sie gelöscht, entsteht beim nächsten
Eingangs-Diktat eine neue `Eingang.md`.

### Bilder

Eingefügt oder hineingezogen → Datei nach `Anhänge/` (PNG, Name
`2026-10-05-143210.png`, bei Gleichheit `-2`), in den Text
`![](Anhänge/2026-10-05-143210.png)` an den Cursor. Im Editor als Vorschau
(höchstens 320 pt breit) per `NSTextAttachment`; in der Datei steht nur der
Link. Größer als 10 MB → Meldung, nichts wird eingefügt.

### Versionen

Lokal, nicht im Notizordner (sonst bläht sich der Sync auf):
`~/Library/Application Support/shout/Notizversionen/<sha1 des Dateinamens>/<ISO-Zeit>.md`.

- Ein Stand wird gesichert **vor jedem Transform** und beim Bearbeiten
  **höchstens alle 10 Minuten** (vor dem ersten Speichern nach Ablauf der Frist).
- Höchstens 30 Stände pro Notiz, die ältesten fallen weg.
- Umbenennen nimmt den Versionsordner mit.
- Löschen der Notiz lässt die Versionen liegen (Papierkorb ist umkehrbar); sie
  werden nach 30 Tagen ohne zugehörige Datei beim Start aufgeräumt.

### Speichern

- 1 s nach der letzten Eingabe, beim Tab-Wechsel, beim Schließen des Tabs oder
  Panels und in `applicationWillTerminate`.
- Atomar (temporäre Datei + Umbenennen).
- Vor dem Schreiben wird das mtime der Datei mit dem zuletzt gelesenen
  verglichen (siehe Änderungen von außen).

### Änderungen von außen

Ein `DispatchSource` auf den Ordner (Schreib-, Lösch- und Umbenennungsereignisse)
löst ein Neueinlesen der Liste aus, gebündelt auf höchstens einmal pro 0,5 s.

- Offene Notiz von außen geändert, lokal nichts Ungesichertes → neu laden,
  Cursor so gut es geht erhalten.
- Offene Notiz von außen geändert **und** lokal ungesicherte Änderungen → die
  eigene Fassung wird als `Titel (Konflikt).md` gesichert, der Tab zeigt danach
  die Fassung von außen, ein Balken nennt die Konfliktdatei. Nichts gewinnt still.
- Offene Notiz von außen umbenannt oder gelöscht → Tab zeigt „Nicht mehr im
  Ordner“, Text bleibt im Speicher, Knopf „Wieder sichern“ legt die Datei neu an.

### Lokaler Zustand (nicht synchronisiert)

UserDefaults: offene Tabs (Dateinamen), aktiver Tab, Breite der Liste, ob die
Liste eingeklappt ist, Panel-Rahmen (als Anteil plus Bildschirm-Kennung wie bei
`PillPlacement`), Öffnen-Verhalten, Tasten, `inboxFileName`.

## 2 · Panel, Tabs und Tasten

### `ScratchpadPanel`

`NSPanel`-Unterklasse:

- Stil `[.titled, .closable, .resizable, .fullSizeContentView, .nonactivatingPanel]`,
  Titelleiste transparent, eigene Kopfzeile.
- `canBecomeKey = true`, `canBecomeMain = false`, `becomesKeyOnlyIfNeeded = true`.
- `level = .floating` (unter der Pille, die auf `.statusBar` steht),
  `hidesOnDeactivate = false`.
- `collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]`.
- Mindestgröße 360 × 260 pt, Voreinstellung 520 × 420 pt, oben rechts auf dem
  Bildschirm mit der Maus.

**Öffnen nimmt keinen Fokus:** `orderFrontRegardless()`, kein `makeKey`. Die
App davor bleibt aktiv. Erst ein Klick in das Panel macht es zum Key-Fenster;
weil es `nonactivating` ist, wird shout. dabei **nicht** aktiviert — kein
Dock-Symbol, keine Änderung der Aktivierungsrichtlinie, `windowWillClose` bleibt
unberührt, und `lastExternalApp` zeigt weiter auf die App davor.

### Aufbau

```
┌─────────────────────────────────────────────────────────┐
│ [Eingang] [Newsletter-Idee ×] [Unbenannt ×]  +       ⌘⇧L │
├──────────────┬──────────────────────────────────────────┤
│ 🔍 Suchen     │                                          │
│ 📌 Eingang    │  Editor (NoteEditorView)                 │
│ 📌 Projekt X  │                                          │
│ Newsletter …  │                                          │
│ Einkauf       │                                          │
├──────────────┴──────────────────────────────────────────┤
│ 🎙   🪄 ▾   📌             Ablegen in  ✉︎ Mail   ⌘⏎      │
└─────────────────────────────────────────────────────────┘
```

- **Tabs:** höchstens 5. Ist das Maximum erreicht, ersetzt eine weitere Notiz
  den aktiven Tab (vorher gesichert). Schließen eines Tabs sichert. Der letzte
  Tab lässt sich schließen; dann zeigt das Panel eine leere neue Notiz.
- **Liste links:** einklappbar, gleiche Suche und Sortierung wie die Seite
  „Notizen“ (Abschnitt 4), ein Klick öffnet die Notiz im aktiven Tab, ⌘-Klick
  in einem neuen.
- **Fußleiste:** Mikrofon (startet/stoppt ein Diktat in diesen Tab, pulsiert
  während der Aufnahme), Zauberstab (Transforms), Pin, Ablegen.

### Tastatur im Panel

| Taste | Wirkung |
|---|---|
| ⌘N | neuer Tab |
| ⌘W | Tab schließen |
| ⌘1 … ⌘5 | Tab wählen |
| ⌘⇧[ / ⌘⇧] | voriger / nächster Tab |
| ⌘⇧L | Liste ein/aus |
| ⌘F | Suche in der Notiz (Find-Bar des `NSTextView`) |
| ⌘⇧F | Suchfeld der Liste |
| ⌘⏎ | Ablegen |
| Esc | Panel ausblenden (sichert) |

### Globale Tasten

Zwei neue Tasten über `RegisterEventHotKey` (Carbon) statt `NSEvent`-Monitor:
Carbon fängt die Taste ab — sonst landete z. B. bei ⌥S ein „‚“ in der App
darunter — und braucht keine Bedienungshilfen-Berechtigung. Pressed- und
Released-Ereignisse kommen beide, damit ist Halten erkennbar.

| Taste | Voreinstellung | Antippen | Halten (≥ 0,35 s) |
|---|---|---|---|
| Scratchpad | ⌃⌥N | Panel ein-/ausblenden | Panel öffnen + Diktat in diesen Tab; hat der aktive Tab Text, in einen neuen. Loslassen beendet. |
| Eingang | ⌃⌥I | folgt dem Modus der Diktiertaste: bei „Umschalten“ und „Doppeltipp“ startet Antippen, erneutes Antippen stoppt | bei „Halten“: Loslassen beendet |

- Beide änderbar und abschaltbar; beide erzeugen in der Voreinstellung kein
  Zeichen.
- Die Unterscheidung Tippen/Halten ist eine reine Zustandsmaschine
  `HotkeyPressClassifier` (Muster `DoubleTapDetector`), testbar ohne Ereignisse.
- Die Tastenaufnahme (`beginHotkeyCapture`) wird auf mehrere Belegungen
  erweitert: ein Ziel-Parameter sagt, welche Belegung aufgenommen wird. Die
  Diktiertaste bleibt beim `NSEvent`-Weg (sie muss weiterhin reine
  Modifier-Tasten wie rechtes ⌥ können, was Carbon nicht kann).
- Die neuen Kombinationen kommen in `isReservedCombo`, damit sie nicht als
  Diktiertaste aufgenommen werden; umgekehrt lehnt die Aufnahme der neuen Tasten
  ⌥⌘C, ⌃⌘V und die aktuelle Diktiertaste ab.
- Schlägt `RegisterEventHotKey` fehl (`eventHotKeyExistsErr`), steht bei der
  Einstellung „Von einer anderen App belegt“.

### Routing des Diktats

```swift
enum DictationTarget: Equatable {
    case frontApp(bundleID: String?)
    case scratchpad(noteID: UUID)
    case inbox
}
```

Festgelegt **beim Start** der Aufnahme durch eine reine Funktion:

1. gestartet über die Eingangs-Taste → `.inbox`
2. gestartet über Halten der Scratchpad-Taste oder das Mikrofon im Panel →
   `.scratchpad(Tab-Notiz)`
3. Diktiertaste, während das Panel Key-Fenster ist → `.scratchpad(aktive Notiz)`
4. sonst → `.frontApp(targetBundleID)` (wie heute)

In `stopAndProcess()` wird aus dem fest eingebauten Einfügen
`deliver(final, raw:, to: target)`:

- `.frontApp` → wie heute (`injector.paste`, Kopieren ohne Berechtigung,
  `correctionWatcher.begin`).
- `.scratchpad` → `insertText` am **aktuellen** Cursor der Notiz (eine
  Undo-Gruppe, ⌘Z nimmt das ganze Diktat zurück). Steht vor dem Cursor kein
  Leerraum und beginnt das Diktat nicht mit Satzzeichen, wird ein Leerzeichen
  vorangestellt. Ist die Notiz inzwischen geschlossen oder gelöscht, entsteht
  eine neue Notiz im Panel mit dem Text — nichts geht verloren.
- `.inbox` → anhängen an die Eingangs-Notiz (Abschnitt 1), dann Toast „Im
  Eingang notiert“; Klick auf den Toast öffnet die Notiz im Panel.

Für `.scratchpad` und `.inbox` bekommt der Formatter `bundleID: nil` (neutraler
Ton), der `CorrectionWatcher` startet nicht (das Feld gehört uns). Verlauf und
Statistik zählen jedes Diktat, egal wohin.

## 3 · Ablegen und Transforms

### Ablegen (Knopf oder ⌘⏎)

- **Ziel:** `lastExternalApp` — die App, die zuletzt vorne war, bevor ins Panel
  geklickt wurde. Der Knopf zeigt Symbol und Namen. Gibt es keine, ist der Knopf
  aus.
- **Inhalt:** die Auswahl, ohne Auswahl die ganze Notiz (ohne Frontmatter).
- **Format:** zwei Typen in die Zwischenablage — Klartext (das Markdown
  unverändert) und RTF aus `AttributedString(markdown:)` mit
  `.inlineOnlyPreservingWhitespace` für Absätze plus eigener Umsetzung von
  Überschriften und Listen. Mail, Pages, Notion nehmen RTF und zeigen echte
  Formatierung, das Terminal nimmt Klartext. Bild-Links bleiben als Text.
- Umsetzung über `TextInjector.paste(markdown:keepInClipboard:)`; die App wird
  wie bei `insertFromHistory` erst aktiviert, dann ⌘V.
- Danach blendet sich das Panel aus. Die Notiz bleibt.
- Ohne Bedienungshilfen-Recht: nur kopieren, Hinweis wie beim Diktat.

### Transforms (Zauberstab)

Eingebaut:

| Name | Anweisung (sinngemäß) |
|---|---|
| Aufräumen | Füllwörter und Wiederholungen streichen, Grammatik korrigieren, sinnvolle Absätze; Inhalt und Ton bleiben |
| Als Mail | als E-Mail mit Anrede, Absätzen, Gruß; Sprache des Textes |
| Zusammenfassen | die wichtigsten Punkte als kurze Liste |
| To-do-Liste | jede Aufgabe als `- [ ] …`, sonst nichts |
| Ins Englische | ins Englische übersetzen, Formatierung erhalten |

**Eigene Transforms:** Name und Prompt, angelegt auf der Seite „Notizen“,
gespeichert in `~/Library/Application Support/shout/transforms.json`
(`[{id, name, prompt}]`), Teil des Backups.

**Per Sprache …:** Menüpunkt, der eine Anweisung per Diktat aufnimmt (Pille
wie immer, Ziel ist ein Anweisungsfeld statt der Notiz), sie einmalig anwendet
und im Menü als „Zuletzt: …“ anbietet. Ein eigener Knopf statt eines
Schlüsselsatzes im Diktat, damit ein diktiertes „mach daraus eine Mail“ nie
versehentlich einen Transform auslöst.

**Wirkt auf** die Auswahl, ohne Auswahl auf den ganzen Text der Notiz.

**Technik:** `Formatter.transform(_ text: String, instruction: String) async throws -> String`
über das vorhandene private `respond` (Wiederholung, Zeitlimit, lokal oder
Anbieter wie eingestellt). Systemprompt: Rolle „Du bearbeitest einen Text nach
einer Anweisung. Gib nur das Ergebnis zurück, ohne Vorrede, in Markdown.“, dann
die Anweisung; der Text kommt als Datenblock wie bei der Formatierung.
`FormattingGuard` greift **nicht** — eine abweichende Antwort ist hier gewollt.
Verworfen wird nur ein leeres Ergebnis; eine einleitende Zeile wie „Hier ist …:“
wird entfernt.

**Länge:** über 12 000 Zeichen → „Zu lang für das gewählte Modell“. Kein stilles
Kürzen.

**Ablauf:**

1. Versionsstand sichern.
2. Text gesperrt, dezente Fortschrittsanzeige, Esc bricht ab (Text unverändert).
3. Ergebnis ersetzt Auswahl bzw. Text in **einer** Undo-Gruppe.
4. Balken „Zusammengefasst · Rückgängig“ für 8 s.

**Ohne Textmodell** (Formatierung aus, kein Modell, kein Anbieter): Zauberstab
ausgegraut, Tooltip „Unter Modelle ein Textmodell wählen“.

## 4 · Seite „Notizen“ und Einstellungen

Neuer `DashboardModel.Tab.notizen`, in der Seitenleiste nach „Dateien“, Symbol
`note.text`.

### Aufbau

Zwei Spalten:

- **Liste links:** Suchfeld oben. Suche nach zusammenhängender Wortfolge in
  Titel und Text, ohne Groß-/Kleinschreibung und ohne Akzentunterschied
  (`.caseInsensitive, .diacriticInsensitive`), Treffer im Text mit
  hervorgehobenem Ausschnitt (±40 Zeichen). Angeheftete oben, dann nach
  Änderungsdatum. Zeile: Titel, erste Zeile Text, relatives Datum.
- **Editor rechts:** dieselbe `NoteEditorView` wie im Panel.
- **Aktionen** (Kontextmenü und Leiste): Im Panel öffnen · Anheften · Umbenennen ·
  Im Finder zeigen · Versionen … · Löschen.
- **Versionen …:** Blatt mit den Ständen (Zeit, erste Zeile), Vorschau,
  „Wiederherstellen“ (sichert vorher den aktuellen Stand als Version).
- **Löschen** geht in den Papierkorb (`NSWorkspace.recycle`), ohne Rückfrage,
  mit „Rückgängig“ im Balken (holt die Datei aus dem Papierkorb zurück).
- **Tastatur:** ↓/j, ↑/k · ⏎ öffnen · c oder ⌘N neue Notiz · / oder ⌘F Suche.

### Einstellungen (oben auf der Seite, einklappbar)

- *Scratchpad aktiv* — aus: beide Tasten abgemeldet, Panel geschlossen,
  Menüeintrag weg. Die Seite bleibt (die Dateien gibt es ja weiter).
- *Ordner* — Pfad · „Wählen …“ · „Im Finder zeigen“.
- *Tasten* — Aufnahmefelder für Scratchpad und Eingang, jeweils leer lassbar.
- *Beim Öffnen* — Letzte Notizen fortsetzen (Voreinstellung) · Immer neuer Tab ·
  Zuletzt benutzte angeheftete Notiz.
- *Eigene Transforms* — Liste, Hinzufügen, Bearbeiten, Löschen.

### Sonst

- Menü der Menüleiste: „Scratchpad“ mit angezeigter Taste.
- Erster Besuch der Seite: Hinweiskarte mit beiden Tasten und dem Ordner,
  wegklickbar. Onboarding unverändert.
- Backup: Transforms und alle neuen Einstellungen ja (Version des Bündels bleibt
  1, neue Felder optional), Notizen nein (sind schon Dateien).
- Alle Texte über `Loc.t`/`Loc.f` mit englischem Eintrag; keine doppelten
  Schlüssel, gerade Apostrophe in Schlüsseln.

## 5 · Komponenten

| Datei | Aufgabe | Hängt ab von |
|---|---|---|
| `NoteFile.swift` | Frontmatter lesen/schreiben, Titel ableiten, Namen säubern — reine Funktionen | — |
| `NoteStore.swift` | `ObservableObject`: Ordner einlesen, beobachten, sichern, umbenennen, anheften, Papierkorb, Eingang anhängen, Puffer | `NoteFile`, FileManager |
| `NoteSearch.swift` | Treffer und Ausschnitt — rein | `Note` |
| `NoteVersions.swift` | Stände sichern, begrenzen, auflisten, aufräumen | `StoreIO` |
| `NoteEditorView.swift` | `NSViewRepresentable` um `NSTextView`: Markdown-Hervorhebung, Bilder, `insert(dictation:)` am Cursor | `NoteStore` |
| `MarkdownHighlighter.swift` | `NSTextStorageDelegate`: Überschriften, fett, kursiv, Listen, Code, gedimmte Zeichen | — |
| `ScratchpadPanel.swift` | Panel, Tabs, Liste, Fußleiste, Tastatur | `NoteEditorView`, `NoteStore` |
| `ScratchpadHotkeys.swift` | Carbon-Registrierung, `HotkeyPressClassifier` | Carbon |
| `DictationTarget.swift` | Enum + reine Entscheidungsfunktion | — |
| `Transforms.swift` | eingebaute und eigene Transforms, `transforms.json` | `StoreIO` |
| `MarkdownPasteboard.swift` | Markdown → RTF + Klartext | Foundation |
| `NotesView.swift` | Seite „Notizen“ samt Einstellungen | alle oben |

Geändert: `AppDelegate` (`deliver`, Ziel beim Start, Panel und Tasten verdrahten,
Speichern beim Beenden), `Formatter` (`transform`), `TextInjector`
(`paste(markdown:)`), `DashboardView` (Tab, `navRow`, `switch`),
`Backup`, `Localization`, `LearnedToast` (Text und Klick-Aktion als Parameter,
falls nicht schon vorhanden).

## 6 · Fehlerfälle

Grundsatz: Kein Text geht still verloren.

| Fall | Verhalten |
|---|---|
| Ordner nicht erreichbar (Laufwerk ab, keine Rechte) | Balken im Panel und auf der Seite; gesichert wird in `Application Support/shout/Notizen-Puffer/`; sobald der Ordner wieder da ist, wandern die Dateien hinüber (bei Namensgleichheit als Konfliktdatei) |
| iCloud-Platzhalter (`.Name.md.icloud`) | wird als Notiz gelistet, `startDownloadingUbiquitousItem` angestoßen, Editor zeigt „wird geladen“ und ist bis dahin gesperrt |
| Zielnotiz eines Diktats zu/gelöscht | Text in neue Notiz im Panel |
| Offene Notiz von außen umbenannt/gelöscht | „Nicht mehr im Ordner“ + „Wieder sichern“ |
| Gleichzeitige Änderung innen und außen | Konfliktdatei, Balken |
| Taste belegt | Hinweis bei der Einstellung |
| Transform scheitert / Zeitlimit / Abbruch | Text unverändert, Meldung mit Grund |
| App wird beendet | ausstehende Änderungen schreiben |
| Bild > 10 MB oder nicht lesbar | Meldung, nichts eingefügt |
| Fremde Frontmatter-Felder | bleiben erhalten |

## 7 · Tests

In `Tests/ShoutTests`, schnell und ohne Modelle:

- `NoteFile`: Rundlauf mit/ohne Frontmatter, unbekannte Felder in Reihenfolge,
  CRLF, `pinned` fehlt/true/false, kaputtes Datum.
- Titel: Ableitung aus Markdown-Zeilen, Säubern, 60 Zeichen, „Titel 2“,
  Groß-/Kleinschreibung, Regel „unter drei Wörtern wandert der Name mit“.
- `NoteStore` auf Temp-Ordner: anlegen (leer → keine Datei), sichern, umbenennen,
  anheften, Papierkorb, Änderung von außen, Konfliktdatei, Puffer bei fehlendem
  Ordner und Rückwanderung.
- Eingang: Tagesüberschrift neu/vorhanden, mehrzeiliges Diktat, umbenannte
  Eingangs-Datei.
- `NoteSearch`: Wortfolge, Akzente, Ausschnitt am Anfang/Ende.
- `NoteVersions`: 10-Minuten-Abstand, Obergrenze 30, Umbenennen, Aufräumen.
- `DictationTarget`: alle vier Regeln.
- `HotkeyPressClassifier`: Tippen, Halten, Grenzfall 0,35 s.
- `MarkdownPasteboard`: Überschrift, fett, Liste, Checkbox, Klartext unverändert.
- `Formatter.transform` mit Fake-`TextEngine`: Prompt-Aufbau, Längengrenze,
  leeres Ergebnis verworfen, Vorrede entfernt.

**Prüfliste in der laufenden App** (über ein Release aus `/Applications`, keine
Debug-Builds starten):

- Panel öffnet ohne Fokusverlust der App davor; Tippen nach Klick; Esc gibt den
  Fokus zurück.
- Vollbild-App, zweiter Monitor, Abstecken des Monitors.
- Diktat per Diktiertaste landet am Cursor; Halten der Scratchpad-Taste;
  Eingangs-Taste mit Toast.
- Ablegen in Mail (formatiert) und Terminal (Klartext).
- Ordner in iCloud Drive (zweiter Mac oder iCloud.com) und in einem
  Obsidian-Vault (Frontmatter, Checkboxen, Bilder).
- Transforms lokal und mit einem Anbieter; Abbruch; Rückgängig.

## 8 · Umsetzung in drei Plänen

Jeder Plan ist für sich auslieferbar.

1. **Grundlage** — `NoteFile`, `NoteStore`, `NoteSearch`, `MarkdownHighlighter`,
   `NoteEditorView`, Seite „Notizen“ (ohne Transforms und Versionen), Ordnerwahl.
   Ergebnis: Notizen anlegen, bearbeiten, suchen, anheften, löschen — ohne Panel.
2. **Panel** — `ScratchpadPanel` mit Tabs und Liste, `ScratchpadHotkeys`,
   `DictationTarget` + `deliver`, Eingang mit Toast, Öffnen-Verhalten,
   Menüeintrag.
3. **Werkzeuge** — Ablegen mit RTF, Transforms (eingebaut, eigene, per Sprache),
   `NoteVersions` samt Blatt, Bilder.

Danach: Spec für iOS (gleicher Ordner über ein Security-scoped Bookmark,
App-Intent „In Notiz diktieren“ für den Action Button, Widget) und für Windows
(eigener C#-Port: `TrayContext.ProcessAsync`, `RecordingOverlay`,
`DashboardForm`). Beide als offene Punkte in `OFFEN.md`.
