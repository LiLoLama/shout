# shout.

Ein voll-lokales Diktier-Tool für macOS (Apple Silicon) — angelehnt an Wispr Flow,
aber komplett on-device: **kein Cloud, keine Netzwerkabhängigkeit, volle Privatsphäre.**

```
Hotkey (Standard: rechte ⌥) → Aufnahme → WhisperKit (large-v3-turbo, ANE)
→ lokales Gemma-4 (MLX, in-process) räumt Text auf → Einfügen am Cursor
```

## Funktionen

- **Transkription** on-device via WhisperKit (Deutsch), mit Wörterbuch-Biasing.
- **Formatierung** über ein lokales LLM (Gemma-4, MLX): Füllwörter raus,
  Interpunktion, nummerierte Listen, app-abhängiges Register.
- **Persönliches Wörterbuch:** Begriffe + Korrekturen (falsch→richtig), manuell
  pflegbar **und** automatisch lernend (beobachtet Korrekturen im Zielfeld über
  die Accessibility-API); universelles Nachlernen per **⌃⌘V**.
- **Aufnahme-Modi:** Halten (Push-to-talk) oder Umschalten, frei wählbarer Hotkey,
  optionaler Auto-Stopp bei Sprechpause.
- **Mikrofon-Auswahl**, Autostart bei Login.
- **Schwebender, textloser Aufnahme-Hinweis** unten am Bildschirm, der auf den
  Live-Pegel reagiert.
- **Dashboard-Fenster** im flachen Graphit-Look (Aufnahme & Text, Wörterbuch,
  Platzhalter für künftige Pro-Funktionen).

## Bauen (WICHTIG: `xcodebuild`, nicht `swift build`)

MLX kompiliert seine Metal-Shader nur über `xcodebuild`; `swift build` (CLI) erzeugt
keine `metallib` → die App crasht beim Modell-Laden. Der Build läuft daher über ein
per **xcodegen** generiertes Xcode-Projekt:

```bash
./build.sh          # xcodegen generate + xcodebuild (Debug), signiert mit "Flow Lokal Self-Signed"
./build.sh Release  # Release-Build
```

Einmalige Voraussetzungen:
- `brew install xcodegen`
- Metal-Toolchain: `xcodebuild -downloadComponent MetalToolchain`
- Selbstsigniertes Zertifikat „Flow Lokal Self-Signed" in der Login-Keychain
  (für stabile Accessibility-Freigabe über Rebuilds hinweg).

App liegt danach unter `build/Build/Products/<Config>/shout.app`.
Installation: `cp -R build/Build/Products/Release/shout.app /Applications/`.

## Erster Start

1. **Mikrofon** erlauben (Dialog erscheint automatisch).
2. **Bedienungshilfen** (Accessibility) für `shout.app` aktivieren:
   Systemeinstellungen → Datenschutz & Sicherheit → Bedienungshilfen.
   Nötig für globalen Hotkey **und** das Einfügen via ⌘V.
3. Beim allerersten Start werden WhisperKit- und Gemma-Modell einmalig geladen
   (einige GB) und lokal gecached.

## Bedienung

- Menu-Bar-Icon zeigt den Zustand: ⏳ lädt · 🎙️ bereit · 🔴 Aufnahme · ✍️ verarbeitet
- **Rechte ⌥ halten**, sprechen, loslassen → Text erscheint am Cursor.
- **⌃⌘V** — zuletzt Gesprochenes erneut einfügen.
- **⌥⌘C** — letztes Diktat korrigieren (lernt die Korrektur).
- **⌘,** — Fenster öffnen.

## Projektstruktur

```
Sources/FlowLokal/
├── main.swift            App-Start (Menu-Bar + Fenster)
├── AppDelegate.swift     Zustandsmaschine, Hotkeys, Menü, Fenster, Verdrahtung
├── AudioRecorder.swift   Mikrofon → 16-kHz-Mono-Float, Live-Pegel, Auto-Stopp
├── Transcriber.swift     WhisperKit-Hülle (+ Wörterbuch-Biasing, Retry)
├── Formatter.swift       Gemma-4 (MLX) Formatting-Layer
├── TextInjector.swift    Pasteboard + ⌘V (mit Delay & Clipboard-Wiederherstellung)
├── PersonalDictionary.swift  Begriffe + Korrekturen (JSON in Application Support)
├── CorrectionWatcher.swift   Auto-Lernen aus Korrekturen (Accessibility)
├── RecordingIndicator.swift  Schwebende, pegel-reaktive Aufnahme-Pille
├── RecordingSettings.swift   Modus, Hotkey, Auto-Stopp (UserDefaults)
├── AudioDevices.swift    Mikrofon-Enumeration (Core Audio)
├── DashboardView / SettingsView / DictionaryView / ConsoleUI  UI (flacher Look)
└── Theme.swift           Farben (Graphit + „live"-Orange)
project.yml               xcodegen-Projektdefinition
build.sh                  xcodegen + xcodebuild → signierte .app
```

## Modellwechsel

- ASR: `modelName` in `Transcriber.swift` (`large-v3-v20240930_turbo` u. a.).
- Formatting: `modelID` in `Formatter.swift` (`mlx-community/gemma-4-e4b-it-4bit`).
