#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/.."

app="build/DisplayDeck.app"
# toujours reconstruire : un DMG fait à partir d'un ancien build passerait inaperçu
./scripts/build-app.sh

version="$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$app/Contents/Info.plist")"
dmg="build/DisplayDeck-$version.dmg"
staging="$(mktemp -d)"
trap 'rm -rf "$staging"' EXIT

cp -R "$app" "$staging/"
# raccourci vers /Applications : l'installation se fait par simple glisser-déposer dans la fenêtre du DMG
ln -s /Applications "$staging/Applications"

rm -f "$dmg"
hdiutil create -volname "DisplayDeck" -srcfolder "$staging" -fs HFS+ -format UDZO -ov "$dmg" >/dev/null
shasum -a 256 "$dmg" | sed 's#build/##' > "$dmg.sha256"
echo "OK : $dmg"
