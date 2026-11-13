#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/.."

app="build/DisplayDeck.app"
# toujours reconstruire : un DMG fait à partir d'un ancien build passerait inaperçu
./scripts/build-app.sh

# dmgbuild écrit la mise en page de la fenêtre (fond, positions) sans piloter le Finder,
# donc ça marche aussi en CI
command -v dmgbuild >/dev/null || { echo "dmgbuild manquant : brew install pipx && pipx install dmgbuild" >&2; exit 1; }

# fond en 1x et 2x réunis dans un TIFF, pour rester net sur écran Retina
swift scripts/dmg-background.swift build/dmg-background.png build/dmg-background@2x.png
tiffutil -cathidpicheck build/dmg-background.png build/dmg-background@2x.png -out build/dmg-background.tiff

# nom sans version : le lien releases/latest/download/DisplayDeck.dmg du README reste valable d'une release à l'autre
dmg="build/DisplayDeck.dmg"
rm -f "$dmg"
dmgbuild -s scripts/dmg-layout.py -D app="$app" -D background=build/dmg-background.tiff DisplayDeck "$dmg" >/dev/null
shasum -a 256 "$dmg" | sed 's#build/##' > "$dmg.sha256"
echo "OK : $dmg"
