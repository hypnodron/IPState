#!/bin/bash
set -euo pipefail

project_dir="$(cd "$(dirname "$0")/.." && pwd)"
icon_source="$project_dir/Support/AppIcon.icon"
output_dir="$project_dir/build/AppIcon"

mkdir -p "$output_dir"
xcrun actool \
    --compile "$output_dir" \
    --output-format human-readable-text \
    --notices --warnings --errors \
    --platform macosx \
    --target-device mac \
    --minimum-deployment-target 14.0 \
    --app-icon AppIcon \
    --output-partial-info-plist "$output_dir/partial.plist" \
    --lightweight-asset-runtime-mode enabled \
    "$icon_source"

test -s "$output_dir/Assets.car"
test -s "$output_dir/AppIcon.icns"
printf '%s\n' "$output_dir"
