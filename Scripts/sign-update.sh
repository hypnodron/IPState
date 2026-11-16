#!/bin/bash
set -euo pipefail

project_dir="$(cd "$(dirname "$0")/.." && pwd)"
if [[ $# -ne 1 ]]; then
    printf '%s\n' 'Usage: bash Scripts/sign-update.sh archive.zip' >&2
    exit 2
fi
archive="${1:?Usage: bash Scripts/sign-update.sh archive.zip}"
signer="$project_dir/.build/artifacts/sparkle/Sparkle/bin/sign_update"
signature_file="$(mktemp)"
trap 'rm -f "$signature_file"' EXIT
if [[ -n "${SPARKLE_PRIVATE_KEY:-}" ]]; then
    printf '%s' "$SPARKLE_PRIVATE_KEY" | "$signer" --ed-key-file - "$archive" > "$signature_file"
else
    "$signer" --account com.hypnodron.IPState "$archive" > "$signature_file"
fi
public_key="$(/usr/libexec/PlistBuddy -c 'Print :SUPublicEDKey' "$project_dir/Support/Info.plist")"
xcrun swift -module-cache-path "$project_dir/.build/update-verification-cache" \
    "$project_dir/Scripts/verify-update.swift" "$archive" "$signature_file" "$public_key"
python3 "$project_dir/Scripts/update-feed.py" manifest --archive "$archive" \
    --signature-file "$signature_file" --output "$(dirname "$archive")/update.json"
