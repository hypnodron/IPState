#!/bin/bash
set -euo pipefail

project_dir="$(cd "$(dirname "$0")/.." && pwd)"
export CLANG_MODULE_CACHE_PATH="$project_dir/.build/clang-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$project_dir/.build/swift-cache"
cd "$project_dir"

command_name="${1:?Usage: bash Scripts/swift.sh test|build [options]}"
shift
if [[ "$command_name" == "test" ]]; then
    # Keep native rendering from consuming other tests' bounded async deadlines.
    set -- --no-parallel "$@"
fi
exec swift "$command_name" --disable-sandbox \
    --cache-path "$project_dir/.build/cache" \
    --config-path "$project_dir/.build/config" \
    --security-path "$project_dir/.build/security" "$@"
