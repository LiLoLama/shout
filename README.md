# Flow Lokal

Ein voll-lokaler Wispr-Flow-Klon für macOS (Apple Silicon). Diktieren per
Hotkey, Transkription und Formatierung laufen komplett on-device — kein Cloud,
keine Netzwerkabhängigkeit, volle Privatsphäre.

**Status: v2** — Diktat + In-Process-Formatting laufen:

```
Rechte ⌥-Taste halten → Aufnahme → WhisperKit (large-v3-turbo, ANE)
→ lokales Gemma-4 (MLX, in-process) formatiert → Text an Cursor
```

Drin: ASR (de), Formatting-Layer (Füllwörter raus, Interpunktion, nummerierte
Listen, app-abhängiges Register), Menu-Bar-Toggles (Formatierung, Autostart).
Noch nicht: VAD/Auto-Stop, Personal Dictionary, gelernte Stil-Edits.

## Bauen (WICHTIG: xcodebuild, nicht `swift build`)

MLX kompiliert seine Metal-Shader nur über `xcodebuild`. `swift build` (CLI)
erzeugt keine `metallib` → App crasht beim Modell-Laden. Deshalb:

```bash
./build.sh          # xcodegen generate + xcodebuild, signiert mit "Flow Lokal Self-Signed"
```

Einmalige Voraussetzung: `brew install xcodegen` und die Metal-Toolchain
(`xcodebuild -downloadComponent MetalToolchain`). Die App liegt danach unter
`build/Build/Products/Debug/Flow Lokal.app`.

## Architektur (Zielbild)

| Stufe | v0 | später |
|-------|----|--------|
| Trigger | Push-to-talk (⌥ halten) | + Toggle, konfigurierbarer Hotkey |
| VAD/Endpointing | — (Tastendruck = Grenze) | Silero VAD, Auto-Stop bei Stille |
| ASR | whisper-large-v3-turbo (WhisperKit/ANE), Sprache `de` | Personal-Dictionary-Biasing im `initial_prompt` |
| Formatting | — (Rohtext) | lokales LLM (Qwen2.5-32B / Llama-3.3-70B via MLX/Ollama) |
| Kontext | — | Accessibility-API: Text um Cursor + aktive App |
| Injection | Pasteboard + synthetisches ⌘V | direktes Tippen als Option |

## Voraussetzungen

- macOS 14+ auf Apple Silicon
- Xcode 26 / Swift 5.10+ Toolchain

## Bauen & Starten

```bash
./build.sh
open "build/Flow Lokal.app"
```

Beim ersten Start:

1. **Mikrofon** erlauben (Dialog erscheint automatisch).
2. **Bedienungshilfen** (Accessibility) erlauben: Systemeinstellungen →
   Datenschutz & Sicherheit → Bedienungshilfen → „Flow Lokal" aktivieren.
   Nötig für globales Tasten-Monitoring und das Einfügen via ⌘V.
3. Beim allerersten Start lädt WhisperKit das Modell einmalig herunter
   (einige hundert MB) und cached es danach lokal — das kann einen Moment dauern
   (Menu-Bar-Icon zeigt ⏳).

## Bedienung

- Menu-Bar-Icon zeigt den Zustand: ⏳ lädt · 🎙️ bereit · 🔴 Aufnahme · ✍️ transkribiert
- **Rechte ⌥-Taste halten**, sprechen, loslassen → Text erscheint am Cursor.

## Projektstruktur

```
Sources/FlowLokal/
├── main.swift          App-Start (Menu-Bar-only)
├── AppDelegate.swift   Zustandsmaschine, Hotkey, Verdrahtung
├── AudioRecorder.swift Mikrofon → 16-kHz-Mono-Float (AVAudioConverter)
├── Transcriber.swift   WhisperKit-Hülle (Modell laden, transkribieren)
└── TextInjector.swift  Pasteboard + ⌘V
Resources/Info.plist    Bundle-Config (LSUIElement, Mikrofon-Text)
build.sh                Build → signierte .app
```

## Modellwechsel

In `Transcriber.swift` die Konstante `modelName` anpassen:

- `large-v3-v20240930_turbo` — Standard, schnell (ANE)
- `large-v3-v20240930_626MB` — kompakter
- `large-v3` — volle Qualität, langsamer
