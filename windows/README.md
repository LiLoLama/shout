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

## Installieren

1. `shout-win-Setup.exe` aus dem neuesten
   [Windows-Release](https://github.com/LiLoLama/shout/releases?q=windows) laden.
2. Ausführen — **kein Administrator nötig** (installiert nach
   `%LOCALAPPDATA%\shout`), Verknüpfungen landen im Startmenü und auf dem
   Desktop. Fehlt die **.NET 8 Desktop Runtime**, installiert das Setup sie mit.
3. Beim ersten Start lädt shout. das empfohlene Whisper-Modell.

Wer nichts installieren möchte, nimmt `shout-win-Portable.zip` — dann gibt es
allerdings keine automatische Aktualisierung (siehe unten).

## Aktualisieren

Installierte Kopien halten sich selbst aktuell ([Velopack](https://velopack.io),
das Windows-Pendant zu Sparkle in der Mac-App): beim Start wird still gegen die
GitHub-Releases geprüft, eine neue Version im Hintergrund geladen und gemeldet,
sobald sie bereitliegt — ein Neustart über das Tray-Menü übernimmt sie. Manuell
geht es über **Tray-Menü → „Nach Aktualisierungen suchen …"** oder
**Einstellungen → Unterstützen → Aktualisierung**.

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

### Release erzeugen

```powershell
dotnet tool install -g vpk --version 1.2.0   # einmalig
cd windows
./release.ps1                                 # Version aus der csproj
```

Legt in `windows/release/` das Setup, die Portable-ZIP und den Update-Feed
(`releases.win.json`) ab. Veröffentlicht wird per Tag — der Workflow
[`windows-release.yml`](../.github/workflows/windows-release.yml) baut und
lädt dann selbst hoch:

```bash
git tag windows-v1.0.0 && git push origin windows-v1.0.0
```

Wichtig: `releases.win.json` und die `.nupkg` müssen mit ins Release, sonst
finden installierte Kopien keine Aktualisierung.

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

Während der Aufnahme erscheint die **Pille** am Bildschirmrand: eine
pegelreaktive Wellenform zwischen ✕ (verwerfen) und ✓ (einfügen). Sie lässt sich
mit der Maus frei verschieben; Ecke und „immer anzeigen" stehen in den
Einstellungen. Die Einstellungen öffnest du über das Tray-Menü — oder mit
`shout.exe --settings` (eine bereits laufende Instanz holt ihr Fenster nach vorn).

## Performance-Hinweise

- Standard ist das **CPU-Backend** — läuft überall, braucht keinen speziellen
  Treiber. Whisper Small ist damit auf modernen CPUs flott; Large v3 Turbo
  will einen kräftigen Rechner.
- Für NVIDIA-GPUs kann in `Shout.csproj` das Paket
  `Whisper.net.Runtime.Cuda` bzw. `LLamaSharp.Backend.Cuda12` ergänzt werden,
  für breite GPU-Unterstützung `Whisper.net.Runtime.Vulkan` — die Erkennung
  wird damit um ein Vielfaches schneller.

## Gestaltung

Die Oberfläche folgt derselben Gestaltung wie die Mac-App: Graphit-Seitenleiste
mit Wortmarke, flache Karten-Panels, warmes Vermillion als Signalfarbe. WinForms
bringt davon nichts mit, daher liegt in `UI/` ein eigenes, komplett
eigengezeichnetes Design-System (`Theme.cs` = Farben/Schriften/Geometrie,
`Icons.cs` = die SF-Symbols als GDI+-Vektoren, `Controls.cs` + `Widgets.cs` =
Karten, Schalter, Segment-Umschalter, Dropdowns, Chips, Listen).

## Status / bekannte Grenzen

- ✅ **Auf echtem Windows getestet** (Win 11 x64): Build/Publish, Modell-Download,
  Whisper-Transkription, Sprachbefehle, Diktat per Mikrofon inklusive Einfügen,
  Installation über das Setup und die Aktualisierungs-Prüfung.
- Das Setup ist **nicht signiert** — Windows SmartScreen zeigt daher beim ersten
  Start eine Warnung („Weitere Informationen" → „Trotzdem ausführen"). Ein
  Code-Signing-Zertifikat würde das beheben; `release.ps1` unterstützt dafür
  `vpk`-Signierparameter.
- Kein winget-Paket (geplant).
- Gegenüber der Mac-App fehlen noch: Onboarding-Assistent, „Dein Sprachprofil",
  die Hugging-Face-Live-Modellliste und der Kontakte-Import im Wörterbuch.
- Einfügen per Strg+V funktioniert nicht in Konsolen ohne Paste-Support und
  erhöht-privilegierten Fenstern (Windows-Sicherheitsgrenze).
