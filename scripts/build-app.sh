#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/.."

# binaire universel : le DDC exige Apple Silicon, mais le reste de l'app tourne aussi sur Intel
arch_flags=(--arch arm64 --arch x86_64)
swift build -c release "${arch_flags[@]}"
binary="$(swift build -c release "${arch_flags[@]}" --show-bin-path)/DisplayDeck"
app="build/DisplayDeck.app"

rm -rf "$app"
mkdir -p "$app/Contents/MacOS"
cp "$binary" "$app/Contents/MacOS/DisplayDeck"
cp Resources/Info.plist "$app/Contents/Info.plist"

# la release injecte la version du tag ; en local, celle de Resources/Info.plist reste la référence
if [[ -n "${VERSION:-}" ]]; then
    /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$app/Contents/Info.plist"
fi

codesign --force --sign - --deep "$app"
echo "OK : $app"
