# shout. für Windows

Die Windows-Version von [shout.](https://github.com/LiLoLama/shout) — vollständig
lokale, private Diktier-App. Gleiches Prinzip wie am Mac: Hotkey drücken,
sprechen, fertig formatierter Text landet im aktiven Fenster. Nichts verlässt
den Rechner.

## Tech-Stack (bewusst anders als am Mac)

| Baustein | macOS | Windows |
|---|---|---|
| App | Swift/AppKit-Menüleisten-App | C# / .NET 8 Tray-App (WinForms) |
| Spracherkennung | WhisperKit (ANE) | **whisper.cpp** via [Whisper.net](https://github.com/sandrohanea/whisper.net) |
| KI-Formatierung | MLX (Gemma) | **llama.cpp** via [LLamaSharp](https://github.com/SciSharp/LLamaSharp) (Qwen 2.5) |
| Einfügen | CGEvent-Paste | Zwischenablage + simuliertes Strg+V |
| Hotkey | Carbon-Hotkey | `RegisterHotKey` |

Whisper-Modelle (ggml) und LLMs (GGUF) werden beim ersten Start automatisch von
Hugging Face geladen und unter `%LOCALAPPDATA%\shout\models\` gecached.
Nutzerdaten (Wörterbuch, Verlauf, Statistik, Einstellungen) liegen als JSON
unter `%APPDATA%\shout\`.

**Backups sind plattformübergreifend kompatibel:** Die Datei `shout-backup.json`
aus der Mac-/iOS-App lässt sich hier importieren (und umgekehrt) — Wörterbuch,
Verlauf, Statistiken und geteilte Einstellungen wandern mit.

## Bauen

Voraussetzungen: [.NET 8 SDK](https://dotnet.microsoft.com/download/dotnet/8.0)
(oder neuer). Kein Visual Studio nötig.

```powershell
cd windows
dotnet run --project src/Shout          # Entwicklung
dotnet publish src/Shout -c Release
# → verteilbarer Ordner unter src/Shout/bin/Release/net8.0-windows/publish/
```

Zum Ausführen braucht der Zielrechner die **.NET 8 Desktop Runtime**
(einmaliger ~55-MB-Download; Windows bietet ihn beim ersten Start automatisch an).

Hinweis: Bewusst OHNE `-r win-x64 --self-contained` und OHNE
`PublishSingleFile` — beides plättet den `runtimes/`-Ordner, und das
LLamaSharp-CPU-Backend braucht seine AVX-Varianten (avx/avx2/avx512/noavx)
als Unterordner, weil llama.cpp die passende erst zur Laufzeit wählt
(NETSDK1152-Konflikt).

Hinweis: Auf macOS/Linux lässt sich das Projekt mit
`dotnet build -p:EnableWindowsTargeting=true` kompilieren (reiner
Compile-Check) — ausführen kann es nur Windows.

## Erste Schritte

1. App starten → oranger Ring erscheint im Infobereich (System-Tray).
2. Beim ersten Start lädt shout. das empfohlene Whisper-Modell (Empfehlung
   richtet sich nach dem Arbeitsspeicher).
3. **Strg + Alt + Leertaste** (änderbar) startet/stoppt das Diktat. Alternativ
   Doppelklick auf das Tray-Icon.
   > ⚠️ Die Claude-Desktop-App belegt diese Kombination systemweit — läuft sie,
   > schlägt die Registrierung fehl (kurzer Hinweis erscheint). Dann in den
   > Einstellungen einfach eine andere Kombination wählen (z. B. Strg+Alt+F10).
4. Der erkannte Text wird ins aktive Fenster eingefügt und liegt zusätzlich in
   der Zwischenablage.

## Performance-Hinweise

- Standard ist das **CPU-Backend** — läuft überall, braucht keinen speziellen
  Treiber. Whisper Small ist damit auf modernen CPUs flott; Large v3 Turbo
  will einen kräftigen Rechner.
- Für NVIDIA-GPUs kann in `Shout.csproj` das Paket
  `Whisper.net.Runtime.Cuda` bzw. `LLamaSharp.Backend.Cuda12` ergänzt werden,
  für breite GPU-Unterstützung `Whisper.net.Runtime.Vulkan` — die Erkennung
  wird damit um ein Vielfaches schneller.

## Status / bekannte Grenzen

- ✅ **Auf echtem Windows getestet** (Win 11 x64): Build/Publish, Modell-Download,
  Whisper-Transkription, Sprachbefehle, Hotkey → Aufnahme-Overlay → Verarbeitung.
  Noch offen: Diktat mit echtem Mikrofon quer durch verschiedene Ziel-Apps.
- Kein Installer/Auto-Update (v1: einfache EXE). Geplant: winget/Installer.
- Kein Overlay-Klick-Through-Feintuning, keine Mikrofon-Auswahl (nimmt das
  Standard-Eingabegerät), kein Onboarding-Assistent.
- Einfügen per Strg+V funktioniert nicht in Konsolen ohne Paste-Support und
  erhöht-privilegierten Fenstern (Windows-Sicherheitsgrenze).
