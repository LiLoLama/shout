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
- [ ] **Diktat mit echtem Mikrofon testen** (einziger offener Testschritt — Einfügen in verschiedene Ziel-Apps gleich mitprüfen; Komponenten sind einzeln verifiziert).
- [ ] **Standard-Hotkey überdenken**: Strg+Alt+Leertaste ist auf Rechnern mit Claude-Desktop-App belegt (globaler Claude-Shortcut) — Registrierung schlägt fehl, nur Balloon-Hinweis. Alternativen prüfen oder beim Fehlschlag automatisch Ausweich-Kombi anbieten.
- [ ] **Später**: Installer/winget, Auto-Update, Mikrofon-Auswahl, GPU-Backends (CUDA/Vulkan) als Option, Onboarding.

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
