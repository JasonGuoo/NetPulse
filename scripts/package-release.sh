#!/bin/bash
# Build and verify the app, then create the GitHub release artifacts.
set -euo pipefail
cd "$(dirname "$0")/.."

RELEASE_VERSION="${HOPGAUGE_VERSION:-$(tr -d '[:space:]' < VERSION)}"
if [[ ! "$RELEASE_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-beta\.[0-9]+)?$ ]]; then
    echo "Invalid HopGauge version: $RELEASE_VERSION" >&2
    exit 1
fi

APP="build/HopGauge.app"
APP_BINARY="$APP/Contents/MacOS/HopGauge"
ARTIFACT="HopGauge-${RELEASE_VERSION}-macOS-arm64"
ARCHIVE="build/${ARTIFACT}.zip"
CHECKSUM="${ARCHIVE}.sha256"

HOPGAUGE_VERSION="$RELEASE_VERSION" ./scripts/make-app.sh

/usr/bin/plutil -lint "$APP/Contents/Info.plist"
/usr/bin/codesign --verify --deep --strict "$APP"
test "$(/usr/bin/lipo -archs "$APP_BINARY")" = "arm64"
test "$(/usr/bin/plutil -extract HopGaugeReleaseVersion raw -o - "$APP/Contents/Info.plist")" = "$RELEASE_VERSION"
cmp -s LICENSE "$APP/Contents/Resources/LICENSE.txt"

rm -f "$ARCHIVE" "$CHECKSUM"
/usr/bin/ditto -c -k --keepParent --norsrc --noextattr --noqtn --noacl "$APP" "$ARCHIVE"
(
    cd build
    /usr/bin/shasum -a 256 "${ARTIFACT}.zip" > "${ARTIFACT}.zip.sha256"
)
/usr/bin/unzip -tq "$ARCHIVE"

echo ""
echo "Release artifacts:"
echo "  $ARCHIVE"
echo "  $CHECKSUM"
/usr/bin/shasum -a 256 "$ARCHIVE"
