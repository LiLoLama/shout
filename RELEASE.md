# shout. — Release & Verteilung

Wie du eine verteilbare, notarisierte App baust (für Testversionen an Bekannte
und für den Verkauf). Selbstsignierte Builds (`build.sh`) laufen **nur auf
deinem Rechner** — für andere Macs ist Notarisierung Pflicht.

## Einmalige Einrichtung

### 1. Apple Developer Program
- Mitgliedschaft (99 €/Jahr) unter developer.apple.com.
- Im **Xcode → Settings → Accounts** deinen Apple-Account hinzufügen.
- **Developer-ID-Zertifikat** erstellen: „Manage Certificates" → **+** →
  **Developer ID Application**. Es landet im Schlüsselbund. Den vollen Namen
  brauchst du gleich, z. B. `Developer ID Application: Liam Schmid (AB12CD34EF)`.
  (Anzeigen: `security find-identity -v -p codesigning`.)

### 2. Notar-Zugang hinterlegen
- Auf appleid.apple.com ein **app-spezifisches Passwort** erstellen.
- Als Schlüsselbund-Profil speichern (einmalig):
  ```bash
  xcrun notarytool store-credentials "shout-notary" \
      --apple-id "deine@apple-id.de" \
      --team-id "AB12CD34EF" \
      --password "xxxx-xxxx-xxxx-xxxx"
  ```

## Release bauen

```bash
DEV_ID_APP="Developer ID Application: Liam Schmid (AB12CD34EF)" \
TEAM_ID="AB12CD34EF" \
NOTARY_PROFILE="shout-notary" \
./release.sh
```

Das Skript: baut Release (Universal: arm64 + x86_64, Hardened Runtime) → signiert mit Developer ID
→ notarisiert (`notarytool --wait`) → stapelt das Ticket an die App → baut
`shout-<version>.dmg`. Dieses DMG kannst du direkt weitergeben.

## Verifizieren (auf einem FREMDEN Mac)
- DMG öffnen, `shout.app` nach „Programme" ziehen, starten → **kein**
  Gatekeeper-Fehler mehr (bei korrekt notarisiertem Build).
- Erststart: Onboarding führt durch Mikrofon- + Bedienungshilfen-Freigabe und
  den einmaligen Modell-Download (mehrere GB).

## Wenn die Notarisierung fehlschlägt
- Log ansehen: `xcrun notarytool log <submission-id> --keychain-profile "shout-notary"`.
- Häufigste Ursache: eine eingebettete Binärdatei ohne gültige Signatur/Timestamp.
- Sollte MLX zur Laufzeit unter Hardened Runtime abstürzen: in
  `Release/shout.entitlements` ggf. `com.apple.security.cs.disable-library-validation`
  ergänzen und neu bauen.

## Version erhöhen
Vor jedem Release in `project.yml` `MARKETING_VERSION` (und ggf.
`CURRENT_PROJECT_VERSION`) hochzählen — sonst kollidieren spätere Sparkle-Updates.

## Update-Log
Vor jedem Release in `CHANGELOG.md` einen Abschnitt für die neue Version anlegen
(Format steht im Kopf der Datei; `release.sh` bricht sonst ab). `zeigen: ja` nur
bei Neuerungen, die man nach dem Update sehen soll; sonst `zeigen: nein`. Die
GitHub-Release-Notes kommen aus derselben Datei:

```bash
gh release create v1.13.0 shout-1.13.0.dmg --notes-file <(Support/release-notes.sh 1.13.0)
```

## Hinweis Intel-Macs
Seit 1.13.3 ist der Build **universal** (arm64 + x86_64). Auf Intel laufen die
lokalen Modelle nicht (`Hardware.lokaleModelle`): MLX braucht die GPU von Apple
Silicon, und WhisperKit beschreibt seine Float16-Puffer auf Intel mit 4-Byte-
Floats und stürzt beim ersten Erkennen ab (bis mindestens WhisperKit 1.1.1;
nachstellbar mit `whisperkit-cli`, für x86_64 gebaut und unter Rosetta
gestartet). Erkennung und Aufbereitung gehen dort nur über einen Anbieter; ohne
Anbieter startet shout. keine Aufnahme, sondern zeigt einen Hinweis. Die Appcast-Einträge bis 1.13.2 tragen
`sparkle:hardwareRequirements arm64`; Intel-Macs sehen deshalb nur Updates ab
1.13.3. Dieses Element setzt `generate_appcast` selbst, sobald ein DMG nur arm64
enthält — beim Universal-Build fehlt es, und genau das soll so sein.

## Windows

Die Windows-Fassung hat einen eigenen Weg (Velopack statt Sparkle, kein
Notarisieren, dafür bisher ohne Signatur): siehe
[`windows/README.md`](windows/README.md) → „Release erzeugen". Ausgelöst wird sie
über einen Tag `windows-v<version>` — oder ganz ohne lokales Repo über
**Actions → Windows-Release → Run workflow** mit gesetztem Haken
„Veröffentlichen". Gebaut und hochgeladen wird beides vom Workflow
[`windows-release.yml`](.github/workflows/windows-release.yml).
