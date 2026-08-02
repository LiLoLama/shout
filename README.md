# shout.

**Local, private dictation — on your Mac, your PC and your iPhone.** Press a
hotkey, speak, and your words are typed wherever your cursor is — transcribed and
cleaned up entirely **on your own device**. No cloud, no account, no data ever
leaves the machine. Inspired by Wispr Flow, built to be fully offline and open
source.

```
Hotkey → record → Whisper (speech → text) → optional local LLM cleans the text
       → pasted at the cursor
```

![The shout. window on macOS, showing the recording and text settings: how to
record, the dictation hotkey, automatic text cleanup, and the language settings
with separate pickers for the dictation language and the interface
language.](Resources/Screenshots/App.webp)

<!-- TODO: noch ergänzen — schwebende Pille beim Diktieren (am besten als GIF), Onboarding -->

## Platforms

| | macOS | Windows | iOS |
|---|---|---|---|
| Speech recognition | WhisperKit (Neural Engine) | whisper.cpp ([Whisper.net](https://github.com/sandrohanea/whisper.net)) | WhisperKit |
| Text cleanup | MLX (Gemma) | llama.cpp ([LLamaSharp](https://github.com/SciSharp/LLamaSharp), Qwen 2.5) | MLX |
| Insert at cursor | Accessibility paste | clipboard + simulated Ctrl+V | dictation keyboard |
| Hotkey | Carbon hotkey / event tap | `RegisterHotKey` (toggle), keyboard hook (hold) | in-app / keyboard |
| Auto-update | Sparkle | [Velopack](https://velopack.io) | App Store / Xcode |
| Source | [`Sources/FlowLokal`](Sources/FlowLokal) | [`windows/`](windows/README.md) | [`Sources/ShoutMobile`](Sources/ShoutMobile) |

All three keep your dictionary, history and statistics in a **compatible backup
file**, so you can move them between devices (no cloud involved).

## Features

- **On-device transcription** — German, English, or auto-detect.
- **Local LLM cleanup**: removes filler words, adds punctuation, builds numbered
  lists, adapts tone to the target app.
- **Learning dictionary** — teach names/terms; it also auto-learns your corrections.
- **Spoken commands** — “Komma”, “Punkt”, “neue Zeile”, … become real punctuation.
- **Floating pill** with a level-reactive waveform — draggable anywhere, optional
  always-on; click to start, ✕ to cancel, ✓ to insert.
- **Model picker** — detects your hardware, recommends a model, shows download
  progress; switch freely.
- **Adaptive silence detection** with trimming, gentle sound cues, history & stats,
  and local file-based backup/sync.
- **Transcribe files** (macOS) — drop audio or video files into the app and get the
  transcript as text, `.txt` or `.srt` subtitles. Same local pipeline as dictation,
  nothing is uploaded.

- **Onboarding assistant** on first launch — permissions or microphone check,
  hotkey, model download and a test dictation, on all three platforms.
- **Two recording styles**: hold the keys (push-to-talk) or press once to start
  and again to stop.

One extra exists on macOS only for now: importing terms from Contacts (Windows
has no comparable local interface for desktop apps; it imports CSV/TXT instead).
The live Hugging Face model list is on both, but on Windows it lists Qwen models
only, because llama.cpp loads a single file and the cleanup model’s chat template
is built for that family.

## Install

### macOS

1. Download the latest `shout-x.y.z.dmg` from [Releases](https://github.com/LiLoLama/shout/releases).
2. Open it and drag **shout.** to your Applications folder.
3. Launch it — the onboarding guides you through the microphone + accessibility
   permissions and the one-time model download.

Requires **macOS 14+** on **Apple Silicon** (M1 or newer; MLX/WhisperKit need it).
Signed with a Developer ID and notarized, so it opens without Gatekeeper
warnings. Updates arrive automatically via Sparkle.

### Windows

1. Download `shout-win-Setup.exe` from the latest
   [Windows release](https://github.com/LiLoLama/shout/releases?q=windows).
2. Run it — no administrator required; the .NET 8 Desktop Runtime is installed
   if missing. The installer is not code-signed yet, so SmartScreen shows a
   warning on first run (“More info” → “Run anyway”).
3. On first launch an assistant walks you through the microphone check, the
   hotkey and the one-time model download.
4. Press **Ctrl + Alt + Space** (configurable) to dictate. If another program
   already owns that combination, shout. picks a free one and tells you.

Requires **Windows 10/11 (x64)**. Installed copies keep themselves up to date;
see [`windows/README.md`](windows/README.md) for details.

### iOS

Not on the App Store, and there is no public beta. The app runs on a real device
(tested via TestFlight on an iPhone 15 Pro Max); to use it, build it yourself from
this repo (see below) and run it from Xcode. It includes a **dictation keyboard**
extension so you can dictate into any app; it needs “Full Access” in the keyboard
settings.

## Build from source

### macOS and iOS

Needs Xcode and [XcodeGen](https://github.com/yonaskolb/XcodeGen)
(`brew install xcodegen`).

```bash
git clone https://github.com/LiLoLama/shout.git
cd shout
./build.sh Release        # → build/Build/Products/Release/shout.app
```

> **Note:** MLX compiles its Metal shaders only through `xcodebuild`, not
> `swift build` — always use `build.sh`. For a signed & notarized DMG see
> `release.sh` and `RELEASE.md` (requires an Apple Developer ID). The iOS targets
> (`ShoutMobile`, `ShoutKeyboard`) come from the same generated Xcode project.

### Windows

Needs the [.NET 8 SDK](https://dotnet.microsoft.com/download/dotnet/8.0); no
Visual Studio required.

```powershell
cd windows
dotnet run --project src/Shout
```

See [`windows/README.md`](windows/README.md) for the release build (installer,
update feed) and the design notes.

## Language

The **dictation language** — German, English or auto-detect — is set in the app
on every platform.

The **interface language** is available in German and English on **all three
platforms**, independently of the dictation language: it follows the system
display language by default and can be switched in the app — on Windows and
macOS under *Recording & text → Language & sound → Interface*, on iOS under
*Settings → Dictation → Interface*. Switching takes effect immediately, no
restart.

## Privacy

Everything runs locally. There is **no telemetry and no account.** The only time
shout. touches the network is the **one-time model download** from Hugging Face
(and, optionally, when you open the model picker to browse available models) plus
the update check. Your audio and transcripts never leave your device.

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
