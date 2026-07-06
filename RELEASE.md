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

Das Skript: baut Release (arm64, Hardened Runtime) → signiert mit Developer ID
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

## Hinweis Intel-Macs
Der Build ist **arm64-only** (MLX/WhisperKit brauchen Apple Silicon). Auf
Intel-Macs startet macOS die App gar nicht erst — bewusst so, statt beim
Modell-Laden abzustürzen. In den Systemvoraussetzungen klar kommunizieren.
