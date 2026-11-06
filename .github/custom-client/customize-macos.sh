#!/usr/bin/env bash
# Repackage the base .dmg as a custom client.
#   customize-macos.sh <target> <bundle_dir> <base_dmg> <out_dir>
#
# The client reads custom.txt from RustDesk.app/Contents/Resources and loads logos
# from the Flutter asset directory at runtime. Modifying the bundle invalidates any
# signature, so the result is ad-hoc signed. Without an Apple Developer ID the
# build is not notarized and Gatekeeper will warn on first launch.
set -euo pipefail

target="$1" bundle="$2" base_dmg="$3" out="$4"
manifest="$bundle/manifest.json"
app_name=$(jq -r '.app_name // ""' "$manifest")
file_name=$(jq -r '.file_name' "$manifest")

work=$(mktemp -d)
mnt="$work/mnt"
mkdir -p "$mnt" "$work/stage"
hdiutil attach "$base_dmg" -mountpoint "$mnt" -nobrowse -readonly -quiet
src_app=$(find "$mnt" -maxdepth 1 -name '*.app' | head -n1)
test -n "$src_app" || { echo "no .app in base dmg" >&2; exit 1; }
ditto "$src_app" "$work/stage/RustDesk.app"
hdiutil detach "$mnt" -quiet

app="$work/stage/RustDesk.app"
plist="$app/Contents/Info.plist"

install -m 0644 "$bundle/custom.txt" "$app/Contents/Resources/custom.txt"

assets=$(find "$app/Contents/Frameworks/App.framework" -type d -path '*flutter_assets/assets' | head -n1)
test -n "$assets" || { echo "flutter assets dir not found" >&2; exit 1; }
for f in icon.png logo.png logo_light.png logo_dark.png; do
  if [ -f "$bundle/$f" ]; then install -m 0644 "$bundle/$f" "$assets/$f"; fi
done

if [ -f "$bundle/icon_512.png" ]; then
  iconset="$work/AppIcon.iconset"
  mkdir -p "$iconset"
  for n in 16 32 128 256 512; do
    cp "$bundle/icon_${n}.png" "$iconset/icon_${n}x${n}.png"
    double=$((n * 2))
    if [ -f "$bundle/icon_${double}.png" ]; then
      cp "$bundle/icon_${double}.png" "$iconset/icon_${n}x${n}@2x.png"
    fi
  done
  icns_name=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIconFile' "$plist")
  case "$icns_name" in *.icns) ;; *) icns_name="${icns_name}.icns" ;; esac
  iconutil -c icns "$iconset" -o "$app/Contents/Resources/$icns_name"
fi

final_app="$app"
if [ -n "$app_name" ]; then
  /usr/libexec/PlistBuddy -c "Set :CFBundleName $app_name" "$plist"
  /usr/libexec/PlistBuddy -c "Delete :CFBundleDisplayName" "$plist" 2>/dev/null || true
  /usr/libexec/PlistBuddy -c "Add :CFBundleDisplayName string $app_name" "$plist"
  final_app="$work/stage/${app_name}.app"
  mv "$app" "$final_app"
fi

codesign --force --deep --sign - "$final_app"

ln -s /Applications "$work/stage/Applications"
mkdir -p "$out"
volname="${app_name:-RustDesk}"
hdiutil create -volname "$volname" -srcfolder "$work/stage" -ov -format UDZO \
  "$out/${file_name}-${target}.dmg" -quiet
rm -rf "$work"
ls -l "$out"
