#!/bin/bash
# Builds TouchBarStatus.app into ./build/
set -euo pipefail
cd "$(dirname "$0")"

APP="build/TouchBarStatus.app"
SDK="$(xcrun --show-sdk-path)"

rm -rf build
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

# Universal: most Touch Bar Macs are Intel, so ship both slices.
ARCHS="-arch arm64 -arch x86_64"

clang -fobjc-arc -O2 -mmacosx-version-min=11.0 $ARCHS \
  -framework Cocoa \
  -F"$SDK/System/Library/PrivateFrameworks" -framework DFRFoundation \
  -o "$APP/Contents/MacOS/TouchBarStatus" \
  src/main.m

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key><string>TouchBarStatus</string>
  <key>CFBundleIdentifier</key><string>com.tarik.touchbarstatus</string>
  <key>CFBundleName</key><string>TouchBarStatus</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>11.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
</dict>
PLIST
echo '</plist>' >> "$APP/Contents/Info.plist"

codesign --force --sign - "$APP"
echo "Built: $APP"
lipo -archs "$APP/Contents/MacOS/TouchBarStatus" | sed 's/^/Architectures: /' 
