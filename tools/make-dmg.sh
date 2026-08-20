#!/usr/bin/env bash
# Packages dist/Sketchy.app into a drag-to-Applications disk image.
# Usage: tools/make-dmg.sh [version]
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${1:-$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" \
    Sources/Sketchy/Resources/Info.plist)}"
APP="dist/Sketchy.app"
DMG="dist/Sketchy-${VERSION}.dmg"
STAGE="$(mktemp -d)"

[ -d "$APP" ] || { echo "No $APP — run ./build.sh release first." >&2; exit 1; }

cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"

rm -f "$DMG"
hdiutil create -quiet -volname "Sketchy" -srcfolder "$STAGE" -ov -format UDZO "$DMG"
rm -rf "$STAGE"

echo "$DMG"
