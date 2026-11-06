#!/usr/bin/env bash
# Repackage the base .deb as a custom client.
#   customize-linux.sh <target> <bundle_dir> <base_deb> <out_dir>
#
# The client reads custom.txt from the directory of its executable
# (/usr/share/rustdesk) and loads logos from flutter_assets at runtime, so no
# recompilation is needed. The Debian package name stays "rustdesk": renaming it
# would mean rewriting every install path and maintainer script.
set -euo pipefail

target="$1" bundle="$2" base_deb="$3" out="$4"
manifest="$bundle/manifest.json"
app_name=$(jq -r '.app_name // ""' "$manifest")
file_name=$(jq -r '.file_name' "$manifest")

work=$(mktemp -d)
pkg="$work/pkg"
dpkg-deb -R "$base_deb" "$pkg"

share="$pkg/usr/share/rustdesk"
test -x "$share/rustdesk" || { echo "unexpected deb layout: $share/rustdesk missing" >&2; exit 1; }

install -m 0644 "$bundle/custom.txt" "$share/custom.txt"

assets="$share/data/flutter_assets/assets"
mkdir -p "$assets"
for f in icon.png logo.png logo_light.png logo_dark.png; do
  if [ -f "$bundle/$f" ]; then install -m 0644 "$bundle/$f" "$assets/$f"; fi
done

# Desktop/menu icons: replace each hicolor PNG with the matching size from the
# bundle and drop the scalable SVG so the PNGs win.
if [ -f "$bundle/icon_256.png" ]; then
  while IFS= read -r png; do
    size=$(basename "$(dirname "$(dirname "$png")")")   # e.g. 256x256 or 256x256@2
    n=${size%%x*}
    case "$size" in *@2) n=$((n * 2)) ;; esac
    if [ -f "$bundle/icon_${n}.png" ]; then cp "$bundle/icon_${n}.png" "$png"; fi
  done < <(find "$pkg/usr/share/icons" -type f -name 'rustdesk*.png' 2>/dev/null)
  find "$pkg/usr/share/icons" -type f -name 'rustdesk*.svg' -delete 2>/dev/null || true
fi

# app_name is restricted server-side to [A-Za-z0-9 ._-], so it is safe in sed.
# Only the first Name= (the [Desktop Entry] one) is replaced; action names stay.
if [ -n "$app_name" ]; then
  desktop="$pkg/usr/share/applications/rustdesk.desktop"
  if [ -f "$desktop" ]; then
    sed -i "0,/^Name=.*/s//Name=${app_name}/" "$desktop"
  fi
fi

mkdir -p "$out"
dpkg-deb -b --root-owner-group "$pkg" "$out/${file_name}-${target}.deb"
rm -rf "$work"
ls -l "$out"
