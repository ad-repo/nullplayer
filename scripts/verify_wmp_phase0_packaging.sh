#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/.."

APP_BUNDLE="${1:-dist/NullPlayer.app}"
HELPER="$APP_BUNDLE/Contents/Helpers/WMPScriptIsolationHelper"
ENTITLEMENTS="Sources/WMPScriptIsolationHelper/WMPScriptIsolationHelper.entitlements"

if [[ ! -x "$HELPER" ]]; then
    echo "missing executable WMP helper: $HELPER" >&2
    exit 1
fi

codesign --verify --strict "$HELPER"
ACTUAL=$(mktemp "${TMPDIR:-/tmp}/nullplayer-wmp-helper-entitlements.XXXXXX")
trap 'rm -f "$ACTUAL"' EXIT
codesign -d --entitlements :- "$HELPER" > "$ACTUAL" 2>/dev/null

if [[ "$(/usr/libexec/PlistBuddy -c 'Print :com.apple.security.app-sandbox' "$ACTUAL" 2>/dev/null)" != "true" ]]; then
    echo "WMP helper is not app-sandboxed" >&2
    exit 1
fi
if /usr/libexec/PlistBuddy -c 'Print :com.apple.security.network.client' "$ACTUAL" >/dev/null 2>&1; then
    echo "WMP helper unexpectedly has network-client access" >&2
    exit 1
fi
if /usr/libexec/PlistBuddy -c 'Print :com.apple.security.network.server' "$ACTUAL" >/dev/null 2>&1; then
    echo "WMP helper unexpectedly has network-server access" >&2
    exit 1
fi

echo "WMP Phase 0 helper packaging verified: $HELPER"
