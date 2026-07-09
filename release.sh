#!/usr/bin/env bash
#
# Baut, SIGNIERT (Developer ID + Hardened Runtime), NOTARISIERT, stapelt und
# verpackt shout. als verteilbares DMG.
#
# Einmalige Voraussetzungen (siehe RELEASE.md):
#   - Apple Developer Program + "Developer ID Application"-Zertifikat im Schlüsselbund
#   - Notar-Zugang als Schlüsselbund-Profil hinterlegt:
#       xcrun notarytool store-credentials "shout-notary" \
#           --apple-id "<deine-apple-id>" --team-id "<TEAMID>" --password "<app-spez.-passwort>"
#
# Aufruf:
#   DEV_ID_APP="Developer ID Application: Dein Name (TEAMID)" \
#   TEAM_ID="TEAMID" NOTARY_PROFILE="shout-notary" ./release.sh
#
set -euo pipefail
cd "$(dirname "$0")"

: "${DEV_ID_APP:?Bitte DEV_ID_APP setzen, z. B. 'Developer ID Application: Dein Name (TEAMID)'}"
: "${TEAM_ID:?Bitte TEAM_ID setzen (10-stellige Apple Team-ID)}"
: "${NOTARY_PROFILE:?Bitte NOTARY_PROFILE setzen (Name aus 'notarytool store-credentials')}"

CONFIG="Release"
DERIVED="build"
# Entitlements hängen target-spezifisch am App-Target (project.yml), NICHT hier —
# global übergeben würden sie sonst fälschlich auch für die SwiftPM-Pakete gelten.

echo "▶ Generiere Xcode-Projekt …"
xcodegen generate

echo "▶ Baue & signiere ($CONFIG, Developer ID, Hardened Runtime) …"
xcodebuild \
    -project FlowLokal.xcodeproj \
    -scheme FlowLokal \
    -configuration "$CONFIG" \
    -derivedDataPath "$DERIVED" \
    -skipPackagePluginValidation \
    -skipMacroValidation \
    CODE_SIGN_STYLE=Manual \
    CODE_SIGN_IDENTITY="$DEV_ID_APP" \
    DEVELOPMENT_TEAM="$TEAM_ID" \
    ENABLE_HARDENED_RUNTIME=YES \
    CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO \
    OTHER_CODE_SIGN_FLAGS="--timestamp" \
    build

APP="$DERIVED/Build/Products/$CONFIG/shout.app"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")"

# ── Sparkle-Helfer neu signieren ────────────────────────────────────────────
# xcodebuild signiert die verschachtelten Sparkle-Binaries (Updater.app,
# Autoupdate, XPC-Services) NICHT mit unserer Developer ID + Zeitstempel neu —
# Apples Notarisierung lehnt sie sonst ab. Von innen nach außen neu signieren,
# danach die App erneut (damit der äußere Siegel die neuen Signaturen abdeckt).
SPK="$APP/Contents/Frameworks/Sparkle.framework"
if [ -d "$SPK" ]; then
    echo "▶ Signiere Sparkle-Helfer neu …"
    for xpc in "$SPK"/Versions/B/XPCServices/*.xpc; do
        [ -e "$xpc" ] && codesign -f -o runtime --timestamp -s "$DEV_ID_APP" "$xpc"
    done
    for helper in "$SPK/Versions/B/Autoupdate" "$SPK/Versions/B/Updater.app"; do
        [ -e "$helper" ] && codesign -f -o runtime --timestamp -s "$DEV_ID_APP" "$helper"
    done
    codesign -f -o runtime --timestamp -s "$DEV_ID_APP" "$SPK"
    # App erneut signieren (mit unseren Entitlements), damit das Siegel passt.
    codesign -f -o runtime --timestamp \
        --entitlements Release/shout.entitlements -s "$DEV_ID_APP" "$APP"
fi

echo "▶ Prüfe Signatur …"
codesign --verify --deep --strict --verbose=2 "$APP"

echo "▶ Notarisiere (kann ein paar Minuten dauern) …"
ZIP="$DERIVED/shout-notarize.zip"
rm -f "$ZIP"
/usr/bin/ditto -c -k --keepParent "$APP" "$ZIP"
xcrun notarytool submit "$ZIP" --keychain-profile "$NOTARY_PROFILE" --wait

echo "▶ Stapel Notar-Ticket an die App …"
xcrun stapler staple "$APP"
# Gatekeeper-Gegenprobe (sollte "accepted / Notarized Developer ID" melden):
spctl -a -vvv --type execute "$APP" || true

echo "▶ Baue DMG …"
DMG="shout-$VERSION.dmg"
STAGING="$(mktemp -d)"
cp -R "$APP" "$STAGING/"
ln -s /Applications "$STAGING/Applications"
rm -f "$DMG"
hdiutil create -volname "shout." -srcfolder "$STAGING" -ov -format UDZO "$DMG"
rm -rf "$STAGING"

# ── Sparkle-Appcast erzeugen (EdDSA-signiert, mit dem privaten Key aus dem
#    Schlüsselbund) ────────────────────────────────────────────────────────────
# generate_appcast scannt den dist/-Ordner, signiert die DMGs und schreibt
# appcast.xml. Die Download-URLs zeigen auf das GitHub-Release dieser Version.
GENAPPCAST=".sparkle-tools/bin/generate_appcast"
if [ -x "$GENAPPCAST" ]; then
    echo "▶ Erzeuge signierten Appcast …"
    mkdir -p dist
    cp -f "$DMG" dist/
    "$GENAPPCAST" dist \
        --download-url-prefix "https://github.com/LiLoLama/shout/releases/download/v$VERSION/" \
        --link "https://github.com/LiLoLama/shout"
    cp -f dist/appcast.xml appcast.xml
    echo "   appcast.xml aktualisiert."
else
    echo "⚠︎  .sparkle-tools/bin/generate_appcast fehlt — Appcast nicht erzeugt."
    echo "    (Tools laden: siehe RELEASE.md → Sparkle.)"
fi

echo "✅ Fertig: $DMG (notarisiert & gestapelt, Version $VERSION)"
echo "   Nächste Schritte: DMG als GitHub-Release v$VERSION hochladen UND"
echo "   die aktualisierte appcast.xml committen+pushen (sonst sehen Nutzer kein Update)."
echo "   Zum Verteilen einfach dieses DMG weitergeben."
