# shout. — Offene Punkte

Stand: 2026-07-08. **Richtungsentscheidung: Open Source** (statt 150-€-Verkauf) —
kostenlos, quelloffen, freiwillige Unterstützung (Buy Me A Coffee). Lizenz-/
Trial-Code und Stripe-Worker sind entfernt (Git-Historie hat alles).

## 🔴 Open-Source-Release
- [ ] **Echte Links eintragen** in `SupportView.swift`: Buy-Me-A-Coffee-Konto anlegen (`donateURL`) + GitHub-Repo-URL (`githubURL`).
- [ ] **Lizenz wählen** (MIT = maximale Verbreitung, GPL-3.0 = keine proprietären Forks) → `LICENSE`-Datei.
- [ ] **GitHub-Repo anlegen**: README (Screenshots, Features, Systemvoraussetzungen macOS 14+/Apple Silicon, Build-Anleitung), Secrets-Check (`.license-signing/` NIE veröffentlichen — lokal löschen oder behalten, ist gitignored; Git-Historie enthält keine Secrets, aber vor Push einmal prüfen).
- [ ] **Release v1.0**: notarisiertes DMG als GitHub-Release-Asset (`release.sh` funktioniert unverändert).
- [ ] **Launch**: AITI-Newsletter (mit AITI absprechen — deren Kanal!), r/macapps, ggf. Hacker News/Product Hunt; später Homebrew-Cask.

## 🟠 Verteilung / Auslieferung
- [x] **Signierung + Notarisierung + DMG** — Pipeline steht und ist verifiziert (`release.sh`, notarisiertes shout-0.1.0.dmg erzeugt).
- [ ] **Auf einem fremden Mac testen** (sauberer Rechner, Modelle nicht gecacht, andere macOS-Version).
- [ ] **Sparkle-Auto-Update** (EdDSA-signierter Appcast) — auch für OSS sinnvoll; Alternative: schlichter Update-Hinweis, der das neueste GitHub-Release prüft.

## 🟡 Audio / Sound
- [ ] **Sound-Cues final abstimmen** (aktuell bei Codex): kurzes, sanftes, warmes „Klopf"-Geräusch — kein Ton, kein Metall. Datei: `SoundCues.swift`.
- [ ] **Optional: echtes Silero-VAD (CoreML)** als Upgrade über den adaptiven DSP-VAD (mehr Genauigkeit; separater Modell-Download, live zu testen).
- [ ] **Download-Fortschritt auch für ASR-Modelle** (aktuell nur Formatierungsmodelle; ASR zeigt nur Spinner).

## 🟢 Features (aus der Ideenliste, noch offen)
- [ ] **Diktat-Undo per Hotkey** (#9) — letzte Einfügung rückgängig.
- [ ] **Text-Snippets & Sprachbefehle erweitern** (#10) — z. B. „meine Signatur", eigene Bausteine.
- [ ] **Editierbare App-Profile / Diktier-Modi** (#11) — App→Modus→Prompt-Zusatz nutzerpflegbar.
- [ ] **Streaming-Transkription** (#13) — Live-Text während des Sprechens (großer „Wow"-Faktor, L-Aufwand).
- [ ] **Übersetzungs-Modus** (#14) — deutsch sprechen, englisch einfügen.
- [ ] **Barrierefreiheit** (#15) — VoiceOver-Labels, Menüleisten-Template-Icons (Sound-Feedback ist erledigt).

## 🪟 Windows (`windows/`)
- [x] **Erste Version gebaut** — C#/.NET-8-Tray-App: Hotkey → NAudio-Aufnahme (VAD-Port) → whisper.cpp (Whisper.net) → Sprachbefehle → optional llama.cpp (LLamaSharp, Qwen 2.5) → Wörterbuch-Korrekturen → Einfügen per Strg+V. Backup-Format kompatibel zu Mac/iOS.
- [x] **Auf echtem Windows getestet** (2026-07-27, Win 11 / Ryzen 5800X3D): Build, Publish (runtimes/ intakt), Modell-Download, Whisper-Transkription (TTS-Audio wortgenau), Sprachbefehle, Hotkey → Overlay-Pille → Verarbeitung → Idle, Stille-Handling. Dabei gefixt: SendInput-Struct war 48 statt 40 Bytes (Einfügen ging NIE — Fehler 87), Modell-Laden/Inferenz auf Threadpool statt UI-Thread, Download-Fortschritt gedrosselt, camelCase-Naming-Policy für settings.json, SplitterDistance-Klemmung.
- [x] **Diktat mit echtem Mikrofon getestet** — läuft: gesprochener Text wird transkribiert und eingefügt (im Verlauf nachweisbar).
- [x] **Gestaltung an die Mac-App angeglichen** — eigenes GDI+-Design-System (`UI/Theme.cs`, `UI/Controls.cs`, `UI/Widgets.cs`): Graphit-Seitenleiste mit Wortmarke, Karten-Panels, eigene Schalter/Segment-Umschalter/Dropdowns/Chips, SF-Symbols als Vektor-Icons, dunkle Titelleiste. Die Pille ist jetzt ein Layered Window mit pegelreaktiver Wellenform (✕ · Waveform · ✓) und laufender Welle beim Verarbeiten — textlos wie am Mac; frei verschiebbar, Anker wählbar, „immer anzeigen" möglich.
- [ ] **Standard-Hotkey überdenken**: Strg+Alt+Leertaste ist auf Rechnern mit Claude-Desktop-App belegt (globaler Claude-Shortcut) — Registrierung schlägt fehl, nur Balloon-Hinweis. Alternativen prüfen oder beim Fehlschlag automatisch Ausweich-Kombi anbieten.
- [x] **Installer + Auto-Update** (Velopack, Windows-Pendant zu Sparkle): `windows/release.ps1` erzeugt `shout-win-Setup.exe` (ohne Admin-Rechte, installiert bei Bedarf die .NET-Runtime mit), Portable-ZIP und den Update-Feed. Der Workflow `windows-release.yml` veröffentlicht bei einem Tag `windows-v*` automatisch als GitHub-Release. Installation und Aktualisierungs-Prüfung auf diesem Rechner verifiziert.
- [x] **Release 1.0.0 veröffentlicht** — Tag `windows-v1.0.0`, der Workflow lief durch, das [Release](https://github.com/LiLoLama/shout/releases/tag/windows-v1.0.0) enthält Setup, Portable-ZIP und Feed. Verifiziert: Velopack findet den Feed über die GitHub-API trotz des Tag-Schemas `windows-v*` (liefert `shout-1.0.0-full.nupkg`), Setup installiert ohne Admin, Portable-Variante startet.
- [x] **Auto-Update komplett durchgespielt** (1.0.0 → 1.0.1): die installierte 1.0.0 hat beim Start von selbst gegen GitHub geprüft, `shout-1.0.1-full.nupkg` geladen und die Übernahme lief durch — inklusive Prüfung der .NET-Voraussetzung und Aktualisierung der Verknüpfungen in Startmenü und Desktop. Damit ist der ganze Weg (Feed finden → laden → übernehmen) verifiziert.
- [ ] **Code-Signing-Zertifikat** für Windows — ohne Signatur warnt SmartScreen beim ersten Start. (`release.ps1` kann `vpk`-Signierparameter durchreichen.)
- [x] **Zweisprachig (Deutsch/Englisch)** — `Core/Localization.cs`: der deutsche Text ist der Schlüssel, ein fehlender Eintrag fällt harmlos auf Deutsch zurück. Standard ist die Windows-Anzeigesprache, umschaltbar unter „Aufnahme & Text → Sprache & Ton → Oberfläche"; der Wechsel baut Menü und Fenster sofort neu auf, ohne Neustart. Auch die Diktier-Sprache wird beim Erststart aus der Systemsprache belegt.
- [x] **Echtes Logo als Icon** — `windows/assets/shout.ico` wird von `make-icon.ps1` aus dem gemeinsamen App-Icon (`Resources/Assets.xcassets`) erzeugt; unter 48 px zeichnet das Skript eine vereinfachte Waveform, weil die feinen Balken des Originals dort (auch bei Apples 16-px-Asset) zu einem Klecks verschmelzen. Genutzt für Fenster, Taskleiste, Alt-Tab, Setup und Infobereich.
- [ ] **Noch nicht portiert**: „Dein Sprachprofil" (KI-Text auf der Statistik-Seite), Hugging-Face-Live-Liste in „Modelle", Onboarding-Assistent, Kontakte-Import im Wörterbuch (Windows hat keine entsprechende lokale Schnittstelle).
- [ ] **Später**: winget-Paket, GPU-Backends (CUDA/Vulkan) als Option.

## 🌍 Mehrsprachigkeit Mac + iOS (offen)
Die Windows-Version ist deutsch/englisch und folgt der Systemsprache. Für Mac und iOS steht das noch aus — bewusst nicht blind erledigt, weil sich Swift auf dem Windows-Rechner nicht kompilieren lässt und ein Fehler beide Apps unbaubar machen würde.

Der Weg, wenn es am Mac gemacht wird:
- [ ] **Kein automatischer SwiftUI-Mechanismus nutzbar**: `Text("…")` würde als `LocalizedStringKey` selbst übersetzen, aber die Titel und Hilfetexte laufen fast überall als `String`-Parameter durch (`FieldRow(title:help:)`, `navRow(_:_:_:)`, `ConsolePanel(title:)` …) — und `Text(String)` übersetzt NICHT. Es braucht also echte Änderungen an den Aufrufstellen.
- [ ] **Risikoarmer Weg**: eine globale Funktion `L(_ key: String) -> String` (gleiche Idee wie `Loc.T` unter Windows, deutscher Text als Schlüssel) plus die Übersetzungstabelle — dann an den Aufrufstellen `"Text"` → `L("Text")`. Keine Signaturänderung, also kein Typfehler-Risiko; die Tabelle aus `windows/src/Shout/Core/Localization.cs` deckt den Großteil der Texte schon ab.
- [ ] **Sprachauswahl**: „Wie das System / Deutsch / English" analog zu Windows; Umschalten über `AppleLanguages` in den UserDefaults wirkt erst nach einem Neustart — Hinweis in der Oberfläche einplanen.
- [ ] **Diktier-Sprache** beim Erststart aus `Locale.current` belegen statt fest „de" (Windows macht das jetzt so).

## 📱 iOS
- [x] **Native iOS-App** (`ShoutMobile`) — gleiche lokale Pipeline (WhisperKit + MLX), mobile UI, Modell-Empfehler, Onboarding, Verlauf/Wörterbuch/Statistik, Daten-Sync Mac↔iPhone.
- [x] **Diktier-Tastatur** (`ShoutKeyboard`, App-Extension) — „Diktieren" öffnet die App (shout://dictate), Ergebnis via App Group, „Einfügen" schreibt in beliebige App. Braucht Vollzugriff.
- [ ] **Am Gerät testen**: App-Group-Provisionierung (Automatic Signing muss die Group `group.com.inthezone.shout` registrieren), Vollzugriff-Flow, Öffnen-aus-Tastatur, Auto-Aufnahme, Rückkehr + Einfügen.
- [ ] **Feinschliff Tastatur** (nach Gerätetest): optional Auto-Einfügen bei Rückkehr statt Tipp, Live-Vorschau, Haptik.

## ✅ Erledigt
- **Audit-Runde 2** — behoben: Worker stellt Lizenz jetzt synchron aus und gibt bei Fehler 500 zurück (Stripe-Retry statt stiller Verlust); Worker prüft `payment_status == paid` + `async_payment_succeeded` (SEPA/Klarna); E-Mails im Log maskiert; verlorene Korrektur (fehlendes `save()`); Modell-Ladefehler zeigt Fehlerzustand + „erneut laden" (kein Endlos-Spinner mehr); Hotkey-Aufnahme verlangt Modifier (Escape bricht ab); Format-Modellwechsel mit Rollback; VAD-Data-Race geschlossen; Clipboard sichert alle Typen + Doppel-Diktat-Race; Sound-Cues überstehen Audio-Gerätewechsel; Monotonie-Anker wird laufend nachgeschrieben; Import validiert Hotkey; stale `Resources/Info.plist` entfernt.
- Kompletter Code-Audit (29 Funde) — alle gefixt (Modellwechsel-Races, Persistenz, Clipboard-Concealed, Lizenz-/VAD-Robustheit u. a.).
- Modell-Empfehler + Hardware-Erkennung + **Live-Hugging-Face-Liste** + High-End-Stufe.
- Onboarding-Assistent (Mikro/Bedienungshilfen/Modell/Probediktat).
- Verarbeiten-Animation zwischen Aufnahme und Einfügen.
- Sprachumschaltung Deutsch/English/Automatisch.
- Adaptiver VAD (Rausch-Boden + Stille-Trimmen).
- Download-Fortschritt für Formatierungsmodelle.
- Quick Wins: gesprochene Befehle, Wörterbuch-Import (CSV/Kontakte).
- Stripe-Fulfillment-Worker (`server/`) — Code fertig & signing-kompatibel verifiziert; nur noch Konten/Secrets/Deploy offen (siehe oben).
