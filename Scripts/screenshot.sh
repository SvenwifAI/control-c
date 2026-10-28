#!/bin/zsh
# Makes the README images in docs/ (English, and Dutch with .nl) from sample data.
# Your own clipboard history is never read. Run ./build.sh first.
set -euo pipefail
cd "$(dirname "$0")/.."

TMP=$(mktemp -d)
# A copy of the built app with the demo binary inside, so translations load as in the real app.
cp -R build/ControlC.app "$TMP/"
BIN="$TMP/ControlC.app/Contents/MacOS/ControlC"
swiftc -O -swift-version 5 -target "$(uname -m)-apple-macos26.0" -D DEMO Sources/*.swift -o "$BIN" 2>/dev/null
codesign --force --sign - "$TMP/ControlC.app" 2>/dev/null
mkdir -p docs

was_running=$(pgrep -x ControlC >/dev/null && echo 1 || echo 0)
pkill -x ControlC 2>/dev/null || true
restore() {
  [ "$was_running" = 1 ] && open /Applications/ControlC.app
  rm -rf "$TMP"
}
trap restore EXIT

shoot() {
  rm -f "$TMP/crop"
  DEMO_EXPANDED=$1 DEMO_CROP_FILE="$TMP/crop" "$BIN" -AppleLanguages "($3)" & pid=$!
  for _ in {1..50}; do [ -s "$TMP/crop" ] && break; sleep 0.2; done
  sleep 0.8
  screencapture -x "$TMP/full.png"
  kill $pid
  read -r h w y x < "$TMP/crop" || true  # the file has no trailing newline
  sips -c "$h" "$w" --cropOffset "$y" "$x" "$TMP/full.png" --out "docs/$2" >/dev/null
  echo "docs/$2"
}

shoot 0 screenshot-compact.png en
shoot 1 screenshot-expanded.png en
shoot 0 screenshot-compact.nl.png nl
shoot 1 screenshot-expanded.nl.png nl
