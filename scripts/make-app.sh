#!/bin/bash
# Build, assemble, and ad-hoc sign the Apple Silicon app bundle.
set -euo pipefail
cd "$(dirname "$0")/.."

APP="build/NetPulse.app"
RELEASE_VERSION="${NETPULSE_VERSION:-$(tr -d '[:space:]' < VERSION)}"
VERSION_PATTERN='^([0-9]+)\.([0-9]+)\.([0-9]+)(-beta\.([0-9]+))?$'

if [[ ! "$RELEASE_VERSION" =~ $VERSION_PATTERN ]]; then
    echo "Invalid NetPulse version: $RELEASE_VERSION" >&2
    exit 1
fi

MARKETING_VERSION="${BASH_REMATCH[1]}.${BASH_REMATCH[2]}.${BASH_REMATCH[3]}"
BUILD_NUMBER="${NETPULSE_BUILD_NUMBER:-${BASH_REMATCH[5]:-1}}"
if [[ ! "$BUILD_NUMBER" =~ ^[1-9][0-9]*$ ]]; then
    echo "Invalid build number: $BUILD_NUMBER" >&2
    exit 1
fi

echo "==> Building NetPulse $RELEASE_VERSION ($BUILD_NUMBER) for arm64"
swift build -c release --arch arm64
BIN_DIR="$(swift build -c release --arch arm64 --show-bin-path)"
BIN="$BIN_DIR/NetPulse"

echo "==> Assembling the app bundle"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/NetPulse"
cp "Sources/NetPulse/Resources/NetPulseIcon.png" "$APP/Contents/Resources/NetPulseIcon.png"
cp "LICENSE" "$APP/Contents/Resources/LICENSE.txt"

echo "==> Generating the app icon"
ICONSET="$APP/Contents/Resources/AppIcon.iconset"
"$BIN" --make-icon "$ICONSET"
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
rm -rf "$ICONSET"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>NetPulse</string>
    <key>CFBundleDisplayName</key><string>NetPulse</string>
    <key>CFBundleDevelopmentRegion</key><string>en</string>
    <key>CFBundleIdentifier</key><string>com.jason.netpulse</string>
    <key>CFBundleVersion</key><string>0</string>
    <key>CFBundleShortVersionString</key><string>0.0.0</string>
    <key>CFBundleExecutable</key><string>NetPulse</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>LSApplicationCategoryType</key><string>public.app-category.utilities</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>NSHumanReadableCopyright</key><string>Copyright © 2026 Jason Guo. Licensed under 0BSD.</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSSupportsAutomaticGraphicsSwitching</key><true/>
    <key>NetPulseReleaseVersion</key><string>0.0.0</string>
</dict>
</plist>
PLIST

/usr/bin/plutil -replace CFBundleVersion -string "$BUILD_NUMBER" "$APP/Contents/Info.plist"
/usr/bin/plutil -replace CFBundleShortVersionString -string "$MARKETING_VERSION" "$APP/Contents/Info.plist"
/usr/bin/plutil -replace NetPulseReleaseVersion -string "$RELEASE_VERSION" "$APP/Contents/Info.plist"

echo "==> Applying an ad-hoc signature"
codesign --force --sign - "$APP"

echo ""
echo "Done: $APP"
echo "Version: $RELEASE_VERSION ($BUILD_NUMBER)"
echo "The bundle is ad-hoc signed and is not notarized by Apple."
echo "On another Mac, the first launch may require Control-clicking the app and choosing Open."
