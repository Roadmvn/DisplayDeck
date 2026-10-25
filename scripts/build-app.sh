#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/.."

swift build -c release
binary="$(swift build -c release --show-bin-path)/DisplayDeck"
app="build/DisplayDeck.app"

rm -rf "$app"
mkdir -p "$app/Contents/MacOS"
cp "$binary" "$app/Contents/MacOS/DisplayDeck"
cp Resources/Info.plist "$app/Contents/Info.plist"

codesign --force --sign - --deep "$app"
echo "OK : $app"
