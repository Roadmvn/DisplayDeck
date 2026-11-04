#!/bin/bash
set -euo pipefail

# Contrôles communs à la CI et à la release : signature, plist, binaire universel, checksum du DMG.

cd "$(dirname "$0")/.."

app="build/DisplayDeck.app"
plist="$app/Contents/Info.plist"

codesign --verify --strict "$app"
plutil -lint "$plist"

archs="$(lipo -archs "$app/Contents/MacOS/DisplayDeck")"
echo "Architectures : $archs"
[[ "$archs" == *arm64* && "$archs" == *x86_64* ]]

(cd build && shasum -a 256 -c DisplayDeck.dmg.sha256)

# la release doit livrer la version qu'elle annonce
if [[ -n "${VERSION:-}" ]]; then
    stamped="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$plist")"
    echo "Version : $stamped"
    [[ "$stamped" == "$VERSION" ]]
fi
