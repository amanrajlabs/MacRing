#!/bin/bash
# Build MacRing and assemble a signed .app bundle in dist/.
#
#   ./scripts/bundle.sh              debug build, host architecture only
#   ./scripts/bundle.sh release      release build, host architecture only
#   ./scripts/bundle.sh universal    release build, arm64 + x86_64 (for release zips)
set -euo pipefail
cd "$(dirname "$0")/.."

MODE="${1:-debug}"
APP="dist/MacRing.app"

case "$MODE" in
    universal)
        # --arch puts the fat binary under .build/apple/Products, not .build/<config>.
        swift build -c release --arch arm64 --arch x86_64
        BIN=".build/apple/Products/Release/MacRing"
        ;;
    *)
        swift build -c "$MODE"
        BIN=".build/$MODE/MacRing"
        ;;
esac

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
echo "Built $APP ($(lipo -archs "$APP/Contents/MacOS/MacRing"))"
