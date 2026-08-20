#!/bin/bash
# Builds Sketchy and assembles a runnable .app bundle (no Xcode required).
set -euo pipefail
cd "$(dirname "$0")"

CONFIG="${1:-release}"
APP="dist/Sketchy.app"

# Only the app: SketchySelfTest uses @testable, which needs a debug build.
swift build -c "$CONFIG" --product Sketchy
BIN="$(swift build -c "$CONFIG" --show-bin-path)/Sketchy"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Sketchy"
cp Sources/Sketchy/Resources/Info.plist "$APP/Contents/Info.plist"
if [ -f Sources/Sketchy/Resources/AppIcon.icns ]; then
  cp Sources/Sketchy/Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
fi
codesign --force --deep --sign - "$APP" >/dev/null 2>&1 || true
echo "Built $APP"

# `./build.sh release install` also installs into /Applications and registers
# the bundle with LaunchServices, which is what file associations point at.
if [ "${2:-}" = "install" ]; then
  DEST="/Applications/Sketchy.app"
  [ -w /Applications ] || DEST="$HOME/Applications/Sketchy.app"
  mkdir -p "$(dirname "$DEST")"
  rm -rf "$DEST"
  cp -R "$APP" "$DEST"
  LSREG=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
  "$LSREG" -f "$DEST" >/dev/null 2>&1 || true
  echo "Installed $DEST"
fi
