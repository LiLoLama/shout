# shout. — Offene Punkte

Stand: 2026-07-03. Erledigtes steht unten zur Orientierung.

## 🔴 Kauf & Kommerz
- [ ] **Stripe scharf schalten** (Code steht in `server/`): Produkt + Payment Link (150 €) anlegen, Webhook auf den Worker zeigen, Secrets setzen (`STRIPE_SECRET_KEY`, `STRIPE_WEBHOOK_SECRET`, `LICENSE_PRIVATE_KEY`, Mailgun), deployen. Danach `purchaseURL` in `LicenseView.swift` auf den echten Payment Link setzen. Schritte: `server/README.md`.
- [ ] **End-to-End-Testkauf** im Stripe-Testmodus (Schlüssel kommt per Mail an → in App aktivieren).
- [ ] **Lizenz-Härtung** (heute bewusst simpel): Payload = nur E-Mail, kein Ablauf/keine Gerätebindung → ein Schlüssel läuft auf beliebig vielen Geräten. Optional: Hardware-UUID/Ablaufdatum in den signierten Payload, Schlüssel in die Keychain (statt UserDefaults).
- [ ] **Deep-Link-Aktivierung**: `shout://activate?key=…` aus der Kauf-Mail → App öffnet und füllt den Schlüssel automatisch ein (bequemer als Copy-Paste).
- [ ] **Verkaufsseite/Landing** unter der Kauf-URL (aktuell Platzhalter).

## 🟠 Verteilung / Auslieferung
- [ ] **Developer-ID-Signierung + Notarisierung** (ersetzt das selbstsignierte Zertifikat; nötig für Verteilung ohne Gatekeeper-Warnung).
- [ ] **Sparkle-Auto-Update** (EdDSA-signierter Appcast) — sonst ist jeder Bugfix nach Verkauf ein Support-Fall.
- [ ] **DMG-Packaging** für die Auslieferung.

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

## ✅ Erledigt
- Kompletter Code-Audit (29 Funde) — alle gefixt (Modellwechsel-Races, Persistenz, Clipboard-Concealed, Lizenz-/VAD-Robustheit u. a.).
- Modell-Empfehler + Hardware-Erkennung + **Live-Hugging-Face-Liste** + High-End-Stufe.
- Onboarding-Assistent (Mikro/Bedienungshilfen/Modell/Probediktat).
- Verarbeiten-Animation zwischen Aufnahme und Einfügen.
- Sprachumschaltung Deutsch/English/Automatisch.
- Adaptiver VAD (Rausch-Boden + Stille-Trimmen).
- Download-Fortschritt für Formatierungsmodelle.
- Quick Wins: gesprochene Befehle, Wörterbuch-Import (CSV/Kontakte).
- Stripe-Fulfillment-Worker (`server/`) — Code fertig & signing-kompatibel verifiziert; nur noch Konten/Secrets/Deploy offen (siehe oben).
