#!/bin/bash
set -e

echo "Building NotchCode..."
swift build -c release 2>&1

BINARY=".build/release/NotchCode"
APP_DIR="NotchCode.app/Contents/MacOS"
RES_DIR="NotchCode.app/Contents"

mkdir -p "$APP_DIR" "$RES_DIR/Resources"
cp "$BINARY" "$APP_DIR/NotchCode"

cat > "$RES_DIR/Info.plist" << 'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key><string>NotchCode</string>
    <key>CFBundleIdentifier</key><string>com.notchcode.app</string>
    <key>CFBundleName</key><string>NotchCode</string>
    <key>CFBundleVersion</key><string>1.0.0</string>
    <key>CFBundleShortVersionString</key><string>1.0.0</string>
    <key>LSUIElement</key><true/>
    <key>LSMinimumSystemVersion</key><string>13.0</string>
    <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

if [ -f "Resources/AppIcon.icns" ]; then
    cp "Resources/AppIcon.icns" "$RES_DIR/Resources/"
fi

echo "Installing to /Applications..."
if [ -d "/Applications/NotchCode.app" ]; then
    pkill -f "NotchCode.app" 2>/dev/null || true
    sleep 1
    rm -rf "/Applications/NotchCode.app"
fi
cp -R "NotchCode.app" "/Applications/"

echo "Launching NotchCode..."
open "/Applications/NotchCode.app"

echo ""
echo "NotchCode installed! Look for the </> icon in your menu bar."
echo "Toggle with ⌘⇧N. Install hooks from the menu bar to start monitoring."
