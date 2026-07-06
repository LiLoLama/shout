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
ENTITLEMENTS="Release/shout.entitlements"

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
    CODE_SIGN_ENTITLEMENTS="$ENTITLEMENTS" \
    ENABLE_HARDENED_RUNTIME=YES \
    OTHER_CODE_SIGN_FLAGS="--timestamp" \
    build

APP="$DERIVED/Build/Products/$CONFIG/shout.app"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")"

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

echo "✅ Fertig: $DMG (notarisiert & gestapelt, Version $VERSION)"
echo "   Zum Verteilen einfach dieses DMG weitergeben."
