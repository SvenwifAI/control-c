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
  Sources/*.swift -o "$APP/Contents/MacOS/ControlC"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleIdentifier</key><string>com.svenvanrooijen.controlc</string>
  <key>CFBundleName</key><string>Control+C</string>
  <key>CFBundleDisplayName</key><string>Control+C</string>
  <key>CFBundleExecutable</key><string>ControlC</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundleDevelopmentRegion</key><string>en</string>
  <key>CFBundleLocalizations</key><array><string>en</string><string>nl</string></array>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>26.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

mkdir -p "$APP/Contents/Resources"
cp -R Resources/AppIcon.icns Resources/*.lproj "$APP/Contents/Resources/"

# A fixed self-signed identity keeps the Keychain's trust in the app across rebuilds;
# with ad-hoc signing (-) macOS asks again after every build whether it may use its key.
IDENTITY="Control+C Signing"
# Read the list first: `grep -q` stops early, and with pipefail that would fail this check.
IDENTITIES=$(security find-identity -p codesigning 2>/dev/null || true)
[[ "$IDENTITIES" == *"\"$IDENTITY\""* ]] || IDENTITY="-"
# Hardened runtime: blocks DYLD_INSERT_LIBRARIES and similar injection, so no other process can
# borrow its Keychain key. No exception entitlements.
codesign --force --options runtime --sign "$IDENTITY" --identifier com.svenvanrooijen.controlc "$APP"

pkill -x ControlC 2>/dev/null || true
rm -rf /Applications/ControlC.app
cp -R "$APP" /Applications/
open /Applications/ControlC.app
echo "Control+C draait. Druk ⌘↩."
