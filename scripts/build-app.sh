#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/.."

# binaire universel : le DDC exige Apple Silicon, mais le reste de l'app tourne aussi sur Intel.
# Un `swift build` par architecture plutôt que `--arch a --arch b` en un seul appel : le mode
# multi-arch passe par xcbuild, absent sans Xcode complet, alors que ceci marche avec les
# Command Line Tools seuls.
slices=()
for arch in arm64 x86_64; do
    swift build -c release --arch "$arch"
    slices+=("$(swift build -c release --arch "$arch" --show-bin-path)/DisplayDeck")
done
app="build/DisplayDeck.app"

rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
lipo -create "${slices[@]}" -output "$app/Contents/MacOS/DisplayDeck"
cp Resources/Info.plist "$app/Contents/Info.plist"

./scripts/make-icon.sh
cp build/AppIcon.icns "$app/Contents/Resources/"

# la release injecte la version du tag ; en local, celle de Resources/Info.plist reste la référence
if [[ -n "${VERSION:-}" ]]; then
    /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$app/Contents/Info.plist"
fi

codesign --force --sign - --deep "$app"
echo "OK : $app"
