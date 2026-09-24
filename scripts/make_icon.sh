#!/usr/bin/env bash
# Regenerates Resources/logo-white.png (from lephor_logo_white.png if present, else logo.png)
# and Resources/AppIcon.icns.
set -euo pipefail
cd "$(dirname "$0")/.."
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# Prefer the hand-made white logo; otherwise derive one from the blue logo.
if [ -f Resources/lephor_logo_white.png ]; then
  swiftc -o "$TMP/crop_logo" scripts/crop_logo.swift
  "$TMP/crop_logo" Resources/lephor_logo_white.png Resources/logo-white.png
else
  swiftc -o "$TMP/make_white_logo" scripts/make_white_logo.swift
  "$TMP/make_white_logo" Resources/logo.png Resources/logo-white.png
fi

swiftc -parse-as-library -o "$TMP/make_icon" scripts/make_icon.swift
"$TMP/make_icon" Resources/logo-white.png "$TMP/icon_1024.png"

SET="$TMP/AppIcon.iconset"
mkdir -p "$SET"
for size in 16 32 128 256 512; do
  sips -z $size $size "$TMP/icon_1024.png" --out "$SET/icon_${size}x${size}.png" >/dev/null
  sips -z $((size * 2)) $((size * 2)) "$TMP/icon_1024.png" --out "$SET/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$SET" -o Resources/AppIcon.icns
cp "$TMP/icon_1024.png" Resources/AppIcon.png
echo "Wrote Resources/AppIcon.icns"
