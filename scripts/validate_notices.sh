#!/bin/bash
# Validate that third-party license notices ship inside the app bundle and that
# every bundled framework / dylib is covered by the notices manifest.
#
# Checks:
#   1. Forward  — every component in scripts/third_party_components.tsv has its
#      required license text present under the app's Resources/ directory, and
#      the aggregated ThirdPartyNotices.txt is present, non-empty, and current.
#   2. Package  — every Package.resolved pin has a manifest entry whose key
#      matches the package identity.
#   3. Reverse  — every real framework/dylib in Contents/Frameworks matches at
#      least one manifest bundle_glob (i.e. no bundled binary ships without a
#      notice).
#
# Usage:
#   ./scripts/validate_notices.sh <RESOURCES_DIR> <FRAMEWORKS_DIR>
#
# Exits non-zero on any missing notice or uncovered bundled binary.

set -eo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
log_ok()   { echo -e "${GREEN}✓${NC} $1"; }
log_warn() { echo -e "${YELLOW}⚠${NC} $1"; }
log_err()  { echo -e "${RED}✗${NC} $1" >&2; }

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
MANIFEST="$REPO_ROOT/scripts/third_party_components.tsv"

RESOURCES_DIR="${1:-}"
FRAMEWORKS_DIR="${2:-}"

if [[ -z "$RESOURCES_DIR" || -z "$FRAMEWORKS_DIR" ]]; then
    log_err "Usage: $0 <RESOURCES_DIR> <FRAMEWORKS_DIR>"
    exit 2
fi
if [[ ! -f "$MANIFEST" ]]; then
    log_err "Manifest not found: $MANIFEST"
    exit 2
fi

errors=0

# Collect bundle globs as we go, for the reverse check.
globs=()
manifest_keys=()

# --- Forward check: every manifest notice ships --------------------------------
while IFS=$'\t' read -r key name spdx copyright url version license_text bundle_glob; do
    [[ "$key" =~ ^#.*$ || -z "$key" ]] && continue
    manifest_keys+=("$key")

    if [[ -f "$RESOURCES_DIR/$license_text" ]]; then
        log_ok "Notice present: $name ($license_text)"
    else
        log_err "Missing notice for '$name': expected $RESOURCES_DIR/$license_text"
        errors=$((errors + 1))
    fi

    [[ "$bundle_glob" != "-" ]] && globs+=("$bundle_glob")
done < "$MANIFEST"

has_manifest_key() {
    local wanted="$1"
    local manifest_key
    for manifest_key in "${manifest_keys[@]}"; do
        if [[ "$manifest_key" == "$wanted" ]]; then
            return 0
        fi
    done
    return 1
}

# --- Package.resolved pins must be represented in the manifest -----------------
PACKAGE_RESOLVED="$REPO_ROOT/Package.resolved"
if [[ -f "$PACKAGE_RESOLVED" ]]; then
    while IFS= read -r identity; do
        [[ -n "$identity" ]] || continue
        if has_manifest_key "$identity"; then
            log_ok "Package pin covered: $identity"
        else
            log_err "Package.resolved pin has NO notice in manifest: $identity"
            log_err "Add a scripts/third_party_components.tsv row whose key is '$identity'."
            errors=$((errors + 1))
        fi
    done < <(
        plutil -extract pins json -o - "$PACKAGE_RESOLVED" \
            | grep -o '"identity":"[^"]*"' \
            | sed 's/"identity":"//; s/"$//'
    )
else
    log_warn "Package.resolved not found ($PACKAGE_RESOLVED) — skipping package pin coverage check"
fi

# --- Aggregated artifact must ship and be non-empty ----------------------------
NOTICES_TXT="$RESOURCES_DIR/ThirdPartyLicenses/ThirdPartyNotices.txt"
if [[ -s "$NOTICES_TXT" ]]; then
    log_ok "Aggregated notices present: ThirdPartyLicenses/ThirdPartyNotices.txt"
else
    log_err "Missing or empty aggregated notices: $NOTICES_TXT"
    log_err "Run scripts/generate_third_party_notices.sh and commit the result."
    errors=$((errors + 1))
fi

# The aggregate is generated from the manifest, so non-empty is not enough: a
# dependency bump or license edit must fail validation until the generated file
# is refreshed.
if [[ -s "$NOTICES_TXT" ]]; then
    expected_notices="$(mktemp)"
    "$REPO_ROOT/scripts/generate_third_party_notices.sh" --output "$expected_notices" >/dev/null
    if cmp -s "$expected_notices" "$NOTICES_TXT"; then
        log_ok "Aggregated notices are current"
    else
        log_err "Aggregated notices are stale: $NOTICES_TXT"
        log_err "Run scripts/generate_third_party_notices.sh and commit the result."
        errors=$((errors + 1))
    fi
    rm -f "$expected_notices"
fi

# --- Reverse check: every bundled framework/dylib is covered -------------------
if [[ -d "$FRAMEWORKS_DIR" ]]; then
    for path in "$FRAMEWORKS_DIR"/*; do
        [[ -e "$path" ]] || continue
        base="$(basename "$path")"
        # Skip symlinks (e.g. libaubio.dylib -> libaubio.5.dylib): the real
        # file is validated on its own iteration.
        [[ -L "$path" ]] && continue
        # Only frameworks and dylibs need notices.
        case "$base" in
            *.framework|*.dylib) ;;
            *) continue ;;
        esac

        covered=false
        for g in "${globs[@]}"; do
            # shellcheck disable=SC2053
            if [[ "$base" == $g ]]; then
                covered=true
                break
            fi
        done

        if [[ "$covered" == true ]]; then
            log_ok "Bundled binary covered: $base"
        else
            log_err "Bundled binary has NO notice in manifest: $base"
            log_err "Add an entry to scripts/third_party_components.tsv with a matching bundle_glob."
            errors=$((errors + 1))
        fi
    done
else
    log_warn "Frameworks dir not found ($FRAMEWORKS_DIR) — skipping reverse coverage check"
fi

echo ""
if [[ "$errors" -gt 0 ]]; then
    log_err "Third-party notice validation FAILED with $errors problem(s)."
    exit 1
fi
log_ok "Third-party notice validation passed."
