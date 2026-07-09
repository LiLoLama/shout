# shout.

**Local, private dictation for macOS.** Press a hotkey, speak, and your words are
typed wherever your cursor is — transcribed and cleaned up entirely **on your Mac**.
No cloud, no account, no data ever leaves the device. Inspired by Wispr Flow,
built to be fully offline and open source.

```
Hotkey (default: right ⌥) → record → Whisper (large-v3-turbo, on the Neural Engine)
→ optional local LLM (Gemma, MLX, in-process) cleans the text → pasted at the cursor
```

<!-- TODO: Screenshots einfügen (Dashboard, schwebende Pille, Onboarding) -->

## Features

- **On-device transcription** via WhisperKit — German, English, or auto-detect.
- **Local LLM cleanup** (Gemma via MLX, runs in-process): removes filler words,
  adds punctuation, builds numbered lists, adapts tone to the target app.
- **Learning dictionary** — teach names/terms; it also auto-learns your corrections.
- **Spoken commands** — “Komma”, “Punkt”, “neue Zeile”, … become real punctuation.
- **Floating pill** — draggable anywhere, optional always-on; click to start,
  ✕ to cancel, ✓ to insert.
- **Model picker** — detects your hardware, recommends a model, shows a live list
  from Hugging Face with download progress; switch freely.
- **Adaptive silence detection** with trimming, gentle sound cues, history & stats
  (incl. a “your voice” profile), and local file-based backup/sync (no cloud).

## Requirements

- **macOS 14+**
- **Apple Silicon** (M1 or newer) — the app is arm64-only; MLX/WhisperKit need it.
- A few GB of free disk for the speech model (downloaded once on first launch).
- Microphone and Accessibility permissions (the onboarding walks you through it).

Also in this repo: a native **iOS app** (incl. a dictation keyboard) built from
the same Xcode project, and an early **Windows version** (C#/.NET 8 +
whisper.cpp/llama.cpp) under [`windows/`](windows/README.md).

## Install

1. Download the latest `shout-x.y.z.dmg` from [Releases](https://github.com/LiLoLama/shout/releases).
2. Open it and drag **shout.** to your Applications folder.
3. Launch it — the onboarding guides you through the microphone + accessibility
   permissions and the one-time model download.

The app is signed with a Developer ID and notarized by Apple, so it opens without
Gatekeeper warnings.

## Build from source

Needs Xcode and [XcodeGen](https://github.com/yonaskolb/XcodeGen)
(`brew install xcodegen`).

```bash
git clone https://github.com/LiLoLama/shout.git
cd shout
./build.sh Release        # → build/Build/Products/Release/shout.app
```

> **Note:** MLX compiles its Metal shaders only through `xcodebuild`, not
> `swift build` — always use `build.sh`. For a signed & notarized DMG see
> `release.sh` and `RELEASE.md` (requires an Apple Developer ID).

## Privacy

Everything runs locally. There is **no telemetry and no account.** The only time
shout. touches the network is the **one-time model download** from Hugging Face
(and, optionally, when you open the model picker to browse available models).
Your audio and transcripts never leave your Mac.

## Contributing

Issues and pull requests are welcome. shout. is a spare-time project — I try to keep
it maintained, improved and extended, but please be patient. 🙏

## Support

shout. is free and open source. If it helps you and you’d like to support the
development, you can — entirely optional:

- ☕ [Ko-fi](https://ko-fi.com/lilolama)
- 💖 [GitHub Sponsors](https://github.com/sponsors/LiLoLama)

## License

[GPL-3.0](LICENSE) — free to use, modify and share; derivatives must stay open
source under the same license.
