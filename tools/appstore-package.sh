#!/usr/bin/env bash
# Builds a signed .pkg for the Mac App Store.
#
# Needs, from an Apple Developer account:
#   APP_IDENTITY      "Apple Distribution: Your Name (TEAMID)"
#   INSTALLER_IDENTITY "3rd Party Mac Developer Installer: Your Name (TEAMID)"
#   PROVISION_PROFILE  path to the Mac App Store provisioning profile
#
# The profile has to match the bundle id (gg.lode.sketchy) and be created for
# "Mac App Store" distribution. App Store builds are signed with a distribution
# identity rather than Developer ID, and are not notarized — App Review does
# that side.
set -euo pipefail
cd "$(dirname "$0")/.."

: "${APP_IDENTITY:?set APP_IDENTITY}"
: "${INSTALLER_IDENTITY:?set INSTALLER_IDENTITY}"
: "${PROVISION_PROFILE:?set PROVISION_PROFILE}"

VERSION="$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" \
    Sources/Sketchy/Resources/Info.plist)"
APP="dist/Sketchy.app"
PKG="dist/Sketchy-${VERSION}.pkg"
ENTITLEMENTS="Sources/Sketchy/Resources/Sketchy.entitlements"

./build.sh release

# The profile ships inside the bundle; without it the App Store rejects the
# upload.
cp "$PROVISION_PROFILE" "$APP/Contents/embedded.provisionprofile"

codesign --force --deep --timestamp --options runtime \
    --entitlements "$ENTITLEMENTS" --sign "$APP_IDENTITY" "$APP"
codesign --verify --strict --verbose=2 "$APP"

rm -f "$PKG"
productbuild --component "$APP" /Applications --sign "$INSTALLER_IDENTITY" "$PKG"

echo "$PKG"
