# shout. — Neuigkeiten

Eine Version je Abschnitt, die neueste oben. Format:
`## <Version> — <JJJJ-MM-TT>`, dann `zeigen: ja|nein` (ja = erscheint einmal nach
dem Update im Fenster „Neu in shout.“), optional `video: <name>` (Animation in
`Resources/Explainers/<name>.html`), dann `### Deutsch` und `### English`.
Innerhalb der Sprachblöcke keine `###`-Überschriften — **fett** statt dessen.

## 1.14.0 — 2026-10-14
zeigen: nein

### Deutsch
**Neu: Aufbereitung über dein ChatGPT-Abo.** Unter **Modelle → Aufbereitung → Anbieter** gibt es jetzt **ChatGPT-Abo**. Statt eines API-Schlüssels meldest du dich mit deinem ChatGPT-Konto an (Plus oder Pro), und die Aufbereitung läuft über dein Abo – ohne Kosten pro Aufruf. Wie viel shout. davon nutzen darf, legst du in den ChatGPT-Einstellungen fest. Ist das Limit erreicht, fügt shout. den Rohtext ein. Die Spracherkennung läuft weiter wie bisher: OpenAI erlaubt über das Abo keine Transkription.

### English
**New: Cleanup through your ChatGPT plan.** Under **Models → Cleanup → Provider** there is now **ChatGPT plan**. Instead of an API key, you sign in with your ChatGPT account (Plus or Pro), and cleanup runs on your plan – with no cost per request. You decide in your ChatGPT settings how much of it shout. may use. When the limit is reached, shout. inserts the raw text. Speech recognition works as before: OpenAI doesn’t allow transcription through the plan.

## 1.13.6 — 2026-10-14
zeigen: nein

### Deutsch
**Behoben:** Die Seite **Notizen** ließ sich nicht scrollen. Bei offenen Einstellungen und kleinerem Fenster waren die Scratchpad-Einstellungen sowie Liste und Editor unten abgeschnitten. Die Seite scrollt jetzt.

### English
**Fixed:** The **Notes** page couldn’t be scrolled. With the settings open and a smaller window, the Scratchpad settings as well as the list and editor were cut off at the bottom. The page now scrolls.

## 1.13.5 — 2026-10-13
zeigen: nein

### Deutsch
**Behoben:** Beim Mitschnitt eines Meetings fehlte die eigene Stimme, wenn in macOS ein anderes Mikrofon als Standard eingestellt war als in shout. – etwa ein virtuelles Gerät wie Loopback. Der Mitschnitt nimmt jetzt dasselbe Mikrofon wie das Diktat. Kommt bei „Beides“ vom Mikrofon kein Ton an, sagt shout. das jetzt während der Aufnahme und nennt das Gerät.

### English
**Fixed:** When recording a meeting, your own voice was missing if macOS had a different default microphone than shout. – for example a virtual device like Loopback. The recording now uses the same microphone as dictation. If no sound arrives from the microphone with “Both”, shout. now tells you during the recording and names the device.

## 1.13.4 — 2026-10-12
zeigen: nein

### Deutsch
**Behoben:** Auf Intel-Macs schloss sich shout. nach dem Beenden einer Aufnahme, und das Diktat ging verloren. Die lokale Spracherkennung läuft auf Intel-Macs nicht zuverlässig; dort erkennt shout. Sprache jetzt über einen Anbieter, den du unter **Modelle** einrichtest. Ohne Anbieter sagt shout. das, bevor die Aufnahme beginnt.

### English
**Fixed:** On Intel Macs, shout. quit after you ended a recording, and the dictation was lost. Local speech recognition doesn’t run reliably on Intel Macs; there, shout. now recognizes speech through a provider you set up under **Models**. Without a provider, shout. tells you so before the recording starts.

## 1.13.3 — 2026-10-12
zeigen: nein

### Deutsch
**Neu: shout. läuft auch auf Intel-Macs.** Ein Download für alle Macs. Auf Intel-Macs erkennt shout. Sprache wie gewohnt lokal, nur etwas langsamer. Die automatische Text-Aufbereitung braucht einen Apple-Chip; auf Intel lässt sie sich über einen eigenen Anbieter einschalten (*Modelle → Anbieter*).

### English
**New: shout. now runs on Intel Macs too.** One download for every Mac. On Intel Macs, speech recognition stays local as usual, just a little slower. Automatic text cleanup needs Apple silicon; on Intel you can turn it on with a provider of your own (*Models → Provider*).

## 1.13.2 — 2026-10-07
zeigen: nein

### Deutsch
**Behoben:** Das Erklärvideo im Fenster „Neu in shout.“ und auf der Seite **Neuigkeiten** war zu klein. Es nutzt jetzt die volle Breite, das Fenster ist größer und lässt sich in der Größe ändern.

### English
**Fixed:** The explainer video in the “New in shout.” window and on the **What’s New** page was too small. It now uses the full width, and the window is larger and resizable.

## 1.13.1 — 2026-10-07
zeigen: nein

### Deutsch
**Neu: Neuigkeiten.** Nach einem Update zeigt shout. einmal, was neu ist — mit einer kurzen Animation, wenn sich ein Ablauf erst im Bewegtbild erschließt. Das Fenster lässt sich überspringen. Alle Versionen stehen jederzeit auf der Seite **Neuigkeiten** im Hauptfenster (auch über das Menü „Neuigkeiten …“).

### English
**New: What’s New.** After an update, shout. shows once what has changed — with a short animation when a workflow is easier to see than to read. You can skip the window. All versions are always available on the **What’s New** page in the main window (also via the “What’s New…” menu item).

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
