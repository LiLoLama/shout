#!/usr/bin/env bash
#
# Baut Flow Lokal als echtes Xcode-App-Bundle via xcodebuild.
#
# WICHTIG: MLX (mlx-swift) kompiliert seine Metal-Shader NUR über xcodebuild,
# nicht über `swift build` (CLI). Deshalb ist der Xcode-Weg zwingend — sonst
# fehlt die default.metallib und die App crasht beim Modell-Laden.
#
set -euo pipefail
cd "$(dirname "$0")"

CONFIG="${1:-Debug}"
DERIVED="build"

echo "▶ Generiere Xcode-Projekt …"
xcodegen generate

echo "▶ Baue ($CONFIG) via xcodebuild …"
# -skipPackagePluginValidation: mlx-swift nutzt das Build-Tool-Plugin "CudaBuild"
# -skipMacroValidation: mlx-swift-lm nutzt swift-syntax-Macros
# Beide würden sonst eine interaktive Freigabe verlangen, die headless fehlt.
xcodebuild \
    -project FlowLokal.xcodeproj \
    -scheme FlowLokal \
    -configuration "$CONFIG" \
    -derivedDataPath "$DERIVED" \
    -skipPackagePluginValidation \
    -skipMacroValidation \
    build

APP="$DERIVED/Build/Products/$CONFIG/Flow Lokal.app"
echo "✅ Fertig: $APP"
echo "   Starten mit:  open \"$APP\""
