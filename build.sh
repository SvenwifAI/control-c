#!/bin/zsh
# Builds Control+C into /Applications/ControlC.app and (re)starts it.
set -euo pipefail
cd "$(dirname "$0")"

APP="build/ControlC.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"

if ! command -v swiftc >/dev/null; then
  echo "swiftc niet gevonden. Installeer eerst de Command Line Tools: xcode-select --install"
  exit 1
fi

swiftc -O -swift-version 5 -target "$(uname -m)-apple-macos26.0" \
  Sources/main.swift -o "$APP/Contents/MacOS/ControlC"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleIdentifier</key><string>com.svenvanrooijen.controlc</string>
  <key>CFBundleName</key><string>Control+C</string>
  <key>CFBundleDisplayName</key><string>Control+C</string>
  <key>CFBundleExecutable</key><string>ControlC</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>26.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

# A fixed self-signed identity keeps the Accessibility permission valid across rebuilds;
# ad-hoc signing (-) would make macOS forget it every time.
IDENTITY="Control+C Signing"
security find-certificate -c "$IDENTITY" >/dev/null 2>&1 || IDENTITY="-"
codesign --force --sign "$IDENTITY" --identifier com.svenvanrooijen.controlc "$APP"

pkill -x ControlC 2>/dev/null || true
rm -rf /Applications/ControlC.app
cp -R "$APP" /Applications/
open /Applications/ControlC.app
echo "Control+C draait. Druk ⌘↩."
