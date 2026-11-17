#!/bin/bash
# Renders Resources/AppIcon.svg (with Chrome, for the system ⌘ glyph) to
# Resources/AppIcon.icns and the website icons in docs/img.
set -euo pipefail
cd "$(dirname "$0")/.."
CHROME="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

"$CHROME" --headless=new --disable-gpu --hide-scrollbars --default-background-color=00000000 \
    --window-size=1024,1024 --screenshot="$TMP/icon.png" "file://$PWD/Resources/AppIcon.svg" 2>/dev/null

ICONSET="$TMP/AppIcon.iconset"
mkdir "$ICONSET"
for size in 16 32 128 256 512; do
    sips -z $size $size "$TMP/icon.png" --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
    sips -z $((size * 2)) $((size * 2)) "$TMP/icon.png" --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o Resources/AppIcon.icns

sips -z 256 256 "$TMP/icon.png" --out docs/img/icon.png >/dev/null
sips -z 180 180 "$TMP/icon.png" --out docs/img/apple-touch-icon.png >/dev/null
echo "Generated Resources/AppIcon.icns and docs/img icons"
