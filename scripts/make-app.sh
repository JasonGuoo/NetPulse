#!/bin/bash
# Build, assemble, and ad-hoc sign the Apple Silicon app bundle.
set -euo pipefail
cd "$(dirname "$0")/.."

APP="build/NetPulse.app"
BIN=".build/release/NetPulse"

echo "==> Building the arm64 release binary"
swift build -c release --arch arm64

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
    <key>CFBundleVersion</key><string>1</string>
    <key>CFBundleShortVersionString</key><string>1.0.0</string>
    <key>CFBundleExecutable</key><string>NetPulse</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>LSApplicationCategoryType</key><string>public.app-category.utilities</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>NSHumanReadableCopyright</key><string>Copyright © 2026 Jason Guo. Licensed under 0BSD.</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSSupportsAutomaticGraphicsSwitching</key><true/>
</dict>
</plist>
PLIST

echo "==> Applying an ad-hoc signature"
codesign --force --sign - "$APP"

echo ""
echo "Done: $APP"
echo "The bundle is ad-hoc signed and is not notarized by Apple."
echo "On another Mac, the first launch may require Control-clicking the app and choosing Open."
