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
