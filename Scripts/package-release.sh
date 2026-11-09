#!/bin/bash
set -euo pipefail

project_dir="$(cd "$(dirname "$0")/.." && pwd)"
bash "$project_dir/Scripts/build-app.sh" --universal

app_dir="$project_dir/build/IP State.app"
version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app_dir/Contents/Info.plist")"
if [[ ! "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    printf 'The app version must have the form X.Y.Z.\n' >&2
    exit 1
fi

for architecture in arm64 x86_64; do
    /usr/bin/lipo "$app_dir/Contents/MacOS/IPState" -verify_arch "$architecture"
done
/usr/bin/codesign --verify --deep --strict "$app_dir"

output_dir="$project_dir/build/release"
archive_name="IPState-${version}-universal-macos.zip"
mkdir -p "$output_dir"
/usr/bin/ditto -c -k --keepParent "$app_dir" "$output_dir/$archive_name"
(
    cd "$output_dir"
    /usr/bin/shasum -a 256 "$archive_name" > "$archive_name.sha256"
)

printf '%s\n' "$output_dir/$archive_name" "$output_dir/$archive_name.sha256"
