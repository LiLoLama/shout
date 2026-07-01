#!/usr/bin/env bash
#
# Baut FlowLokal und bündelt es zu einer signierten .app mit Info.plist.
# Ein echtes .app-Bundle ist nötig, damit macOS die Mikrofon- und
# Accessibility-Berechtigungen sauber vergeben kann.
#
set -euo pipefail
cd "$(dirname "$0")"

CONFIG="${1:-release}"
APP_NAME="Flow Lokal"
APP="build/${APP_NAME}.app"
BIN="FlowLokal"

echo "▶ Kompiliere ($CONFIG) …"
swift build -c "$CONFIG"

BUILD_BIN="$(swift build -c "$CONFIG" --show-bin-path)/$BIN"

echo "▶ Bündle $APP …"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BUILD_BIN" "$APP/Contents/MacOS/$BIN"
cp Resources/Info.plist "$APP/Contents/Info.plist"

echo "▶ Signiere (ad-hoc) …"
codesign --force --deep --sign - "$APP"

echo "✅ Fertig: $APP"
echo "   Starten mit:  open \"$APP\""
