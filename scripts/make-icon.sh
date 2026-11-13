#!/bin/bash
set -euo pipefail

# Resources/AppIcon.png (artwork plein cadre 1024 px) -> build/AppIcon.icns, avec les seuls
# outils de macOS : mask-icon.swift applique le gabarit arrondi, sips décline les tailles,
# iconutil assemble l'icns.

cd "$(dirname "$0")/.."

out="build/AppIcon.icns"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

master="$work/AppIcon.png"
swift scripts/mask-icon.swift Resources/AppIcon.png "$master"

iconset="$work/AppIcon.iconset"
mkdir "$iconset"
for size in 16 32 128 256 512; do
    sips -z "$size" "$size" "$master" --out "$iconset/icon_${size}x${size}.png" >/dev/null
    sips -z "$((size * 2))" "$((size * 2))" "$master" --out "$iconset/icon_${size}x${size}@2x.png" >/dev/null
done

mkdir -p build
iconutil -c icns "$iconset" -o "$out"
echo "OK : $out"
