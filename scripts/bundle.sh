#!/bin/bash
# Build MacRing and assemble a signed .app bundle in dist/.
set -euo pipefail
cd "$(dirname "$0")/.."

CONFIG="${1:-release}"
swift build -c "$CONFIG"

BIN=".build/$CONFIG/MacRing"
APP="dist/MacRing.app"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp Resources/Info.plist "$APP/Contents/"
cp "$BIN" "$APP/Contents/MacOS/MacRing"

# App icon (generated, cached)
if [ ! -f dist/AppIcon.icns ]; then
    swift scripts/make-icon.swift dist/AppIcon.iconset
    iconutil -c icns dist/AppIcon.iconset -o dist/AppIcon.icns
    rm -rf dist/AppIcon.iconset
fi
cp dist/AppIcon.icns "$APP/Contents/Resources/"

codesign --force --deep --sign - "$APP"
echo "Built $APP"
