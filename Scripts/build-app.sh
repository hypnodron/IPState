#!/bin/bash
set -euo pipefail

project_dir="$(cd "$(dirname "$0")/.." && pwd)"
build_arguments=(-c release --product IPState)
if [[ $# -gt 1 ]]; then
    printf 'Usage: bash Scripts/build-app.sh [--universal]\n' >&2
    exit 2
fi
case "${1:-}" in
    "") ;;
    --universal) build_arguments+=(--arch arm64 --arch x86_64) ;;
    *)
        printf 'Usage: bash Scripts/build-app.sh [--universal]\n' >&2
        exit 2
        ;;
esac
bash "$project_dir/Scripts/swift.sh" build "${build_arguments[@]}"
binary_dir="$(bash "$project_dir/Scripts/swift.sh" build "${build_arguments[@]}" --show-bin-path)"
if [[ "${1:-}" == --universal ]]; then
    for architecture in arm64 x86_64; do
        /usr/bin/lipo "$binary_dir/IPState" -verify_arch "$architecture"
    done
fi
app_dir="$project_dir/build/IP State.app"
mkdir -p "$app_dir/Contents/MacOS" "$app_dir/Contents/Resources"
bash "$project_dir/Scripts/build-icon.sh"
cp "$project_dir/build/AppIcon/AppIcon.icns" "$app_dir/Contents/Resources/AppIcon.icns"
cp "$project_dir/build/AppIcon/Assets.car" "$app_dir/Contents/Resources/Assets.car"
cp "$project_dir/LICENSE" "$app_dir/Contents/Resources/LICENSE.txt"
# Replace the executable by rename so an open app keeps its existing mapped file.
cp "$binary_dir/IPState" "$app_dir/Contents/MacOS/IPState.next"
mv -f "$app_dir/Contents/MacOS/IPState.next" "$app_dir/Contents/MacOS/IPState"
cp "$project_dir/Support/Info.plist" "$app_dir/Contents/Info.plist"
/usr/bin/codesign --force --sign - --identifier com.hypnodron.IPState "$app_dir"
# Notify Finder and icon services after updating the bundle in place.
/usr/bin/touch "$app_dir"
printf '%s\n' "$app_dir"
