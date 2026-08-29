#!/bin/bash
# 打包 NetPulse.app：release 构建 → 组装 bundle → icns 图标 → ad-hoc 签名
set -euo pipefail
cd "$(dirname "$0")/.."

APP="build/NetPulse.app"
BIN=".build/release/NetPulse"

echo "==> Release 构建（首次约 1-2 分钟）"
swift build -c release

echo "==> 组装 .app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/NetPulse"
cp "Sources/NetPulse/Resources/NetPulseIcon.png" "$APP/Contents/Resources/NetPulseIcon.png"

echo "==> 生成图标"
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
    <key>CFBundleIdentifier</key><string>com.jason.netpulse</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>CFBundleShortVersionString</key><string>1.0.0</string>
    <key>CFBundleExecutable</key><string>NetPulse</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSSupportsAutomaticGraphicsSwitching</key><true/>
</dict>
</plist>
PLIST

echo "==> ad-hoc 签名"
codesign --force --sign - "$APP"

echo ""
echo "✅ 完成: $APP"
echo "   双击即可运行；分发给他人时压缩成 zip 发送即可。"
echo "   若对方首次打开提示「无法验证开发者」：右键 App → 打开 → 再点「打开」。"
