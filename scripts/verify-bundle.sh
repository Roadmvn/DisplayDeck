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

# le DMG doit contenir l'app, le raccourci Applications et la mise en page (fond + .DS_Store)
mount="$(mktemp -d)"
hdiutil attach -nobrowse -readonly -mountpoint "$mount" build/DisplayDeck.dmg >/dev/null
trap 'hdiutil detach "$mount" >/dev/null 2>&1 || true' EXIT
[[ -d "$mount/DisplayDeck.app" ]]
[[ "$(readlink "$mount/Applications")" == "/Applications" ]]
[[ -f "$mount/.background.tiff" ]]
[[ -f "$mount/.DS_Store" ]]
hdiutil detach "$mount" >/dev/null
trap - EXIT

# l'icône doit être dans le bundle et déclarée dans le plist, sinon le Finder montre l'icône générique
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIconFile' "$plist")" == "AppIcon" ]]
file "$app/Contents/Resources/AppIcon.icns" | grep -q 'Mac OS X icon'

# la release doit livrer la version qu'elle annonce
if [[ -n "${VERSION:-}" ]]; then
    stamped="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$plist")"
    echo "Version : $stamped"
    [[ "$stamped" == "$VERSION" ]]
fi
