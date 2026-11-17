#!/bin/bash
set -euo pipefail

if [[ $# -ne 2 ]]; then
    printf '%s\n' 'Usage: bash Scripts/package-dmg.sh app.app output.dmg' >&2
    exit 2
fi
app_dir="$1"
destination="$2"
if [[ ! -d "$app_dir" || "$app_dir" != *.app ]]; then
    printf '%s\n' 'The disk image requires an existing app bundle.' >&2
    exit 2
fi

project_dir="$(cd "$(dirname "$0")/.." && pwd)"
mkdir -p "$project_dir/build" "$(dirname "$destination")"
environment_dir="$project_dir/.build/dmg-venv"
if [[ ! -x "$environment_dir/bin/python3" ]]; then
    python3 -m venv "$environment_dir"
fi
PIP_CACHE_DIR="$project_dir/.build/pip-cache" "$environment_dir/bin/python3" -m pip install \
    --quiet --disable-pip-version-check --no-input --only-binary=:all: --require-hashes \
    -r "$project_dir/Scripts/requirements-dmg.txt"
temporary="$(mktemp -d "$project_dir/build/dmg.XXXXXX")"
cleanup() {
    python3 - "$temporary" <<'PY'
import shutil
import sys
shutil.rmtree(sys.argv[1])
PY
}
trap cleanup EXIT

export CLANG_MODULE_CACHE_PATH="$project_dir/.build/clang-cache"
xcrun swift -module-cache-path "$project_dir/.build/dmg-swift-cache" \
    "$project_dir/Support/DMG/background.swift" "$temporary/background.tiff"
TMPDIR="$temporary" "$environment_dir/bin/python3" -m dmgbuild \
    -s "$project_dir/Support/DMG/settings.py" -D "app=$app_dir" \
    -D "background=$temporary/background.tiff" 'IP State' "$temporary/image.dmg"
/usr/bin/hdiutil verify "$temporary/image.dmg"
mv -f "$temporary/image.dmg" "$destination"
printf '%s\n' "$destination"
