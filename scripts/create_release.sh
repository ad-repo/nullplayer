#!/bin/bash
# Create or update a GitHub release with human-friendly download assets.
#
# Usage: ./scripts/create_release.sh [--skip-build] [--draft] [--prerelease] [--dry-run] [--replace-versioned]

set -eo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}ℹ${NC} $1"; }
log_success() { echo -e "${GREEN}✓${NC} $1"; }
log_warning() { echo -e "${YELLOW}⚠${NC} $1"; }
log_error() { echo -e "${RED}✗${NC} $1" >&2; }

cd "$(dirname "$0")/.."
REPO_ROOT=$(pwd)

INFO_PLIST="$REPO_ROOT/Sources/NullPlayer/Resources/Info.plist"
RELEASE_TEMPLATE="$REPO_ROOT/.github/release_template.md"
CHANGELOG="$REPO_ROOT/CHANGELOG.md"
DIST_DIR="$REPO_ROOT/dist"

VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" "$INFO_PLIST")
TAG="$VERSION"
VERSIONED_DMG="$DIST_DIR/NullPlayer-$VERSION.dmg"
STABLE_DMG="$DIST_DIR/NullPlayer.dmg"
NOTES_FILE=$(mktemp "${TMPDIR:-/tmp}/nullplayer-release-$VERSION.XXXXXX")
CHANGELOG_FILE=$(mktemp "${TMPDIR:-/tmp}/nullplayer-changelog-$VERSION.XXXXXX")

SKIP_BUILD=false
DRY_RUN=false
REPLACE_VERSIONED=false
RELEASE_FLAGS=()

cleanup() {
    rm -f "$NOTES_FILE" "$CHANGELOG_FILE"
}
trap cleanup EXIT

for arg in "$@"; do
    case "$arg" in
        --skip-build)
            SKIP_BUILD=true
            ;;
        --draft)
            RELEASE_FLAGS+=(--draft)
            ;;
        --prerelease)
            RELEASE_FLAGS+=(--prerelease)
            ;;
        --dry-run)
            DRY_RUN=true
            ;;
        --replace-versioned)
            REPLACE_VERSIONED=true
            ;;
        *)
            log_error "Unknown argument: $arg"
            exit 1
            ;;
    esac
done

if [[ ! -f "$RELEASE_TEMPLATE" ]]; then
    log_error "Missing release template: $RELEASE_TEMPLATE"
    exit 1
fi

if [[ "$SKIP_BUILD" == true ]]; then
    log_info "Using existing DMG build"
    if [[ ! -f "$VERSIONED_DMG" ]]; then
        log_error "Missing versioned DMG: $VERSIONED_DMG"
        exit 1
    fi
    cp "$VERSIONED_DMG" "$STABLE_DMG"
else
    log_info "Building release DMG"
    ./scripts/build_dmg.sh
fi

if [[ ! -f "$VERSIONED_DMG" || ! -f "$STABLE_DMG" ]]; then
    log_error "Expected release assets were not created"
    exit 1
fi

awk -v version="$VERSION" '
    $0 == "## " version { found = 1; next }
    found && /^## / { exit }
    found { print }
' "$CHANGELOG" | sed '/./,$!d' > "$CHANGELOG_FILE"

if [[ ! -s "$CHANGELOG_FILE" ]]; then
    log_warning "No CHANGELOG.md section found for $VERSION; release notes will use a placeholder"
    echo "- Release notes pending." > "$CHANGELOG_FILE"
fi

awk -v changelog_file="$CHANGELOG_FILE" '
    $0 == "{{CHANGELOG}}" {
        while ((getline line < changelog_file) > 0) {
            print line
        }
        close(changelog_file)
        next
    }
    { print }
' "$RELEASE_TEMPLATE" > "$NOTES_FILE"

log_info "Release tag: $TAG"
log_info "Versioned asset: $VERSIONED_DMG"
log_info "Stable asset: $STABLE_DMG"
log_info "Release notes: $NOTES_FILE"

if [[ "$DRY_RUN" == true ]]; then
    log_info "Dry run requested; not calling GitHub"
    echo ""
    cat "$NOTES_FILE"
    exit 0
fi

if ! command -v gh >/dev/null 2>&1; then
    log_error "GitHub CLI not found. Install gh or create the release manually."
    exit 1
fi

release_asset_exists() {
    local tag="$1"
    local asset_name="$2"

    gh release view "$tag" --json assets --jq '.assets[].name' | grep -Fxq "$asset_name"
}

if gh release view "$TAG" >/dev/null 2>&1; then
    log_info "Updating existing GitHub release $TAG"
    gh release edit "$TAG" --title "$VERSION" --notes-file "$NOTES_FILE" "${RELEASE_FLAGS[@]}"

    gh release upload "$TAG" "$STABLE_DMG#Download for macOS" --clobber

    if [[ "$REPLACE_VERSIONED" == true ]]; then
        log_warning "Replacing versioned release asset; update Homebrew if the SHA256 changed"
        gh release upload "$TAG" "$VERSIONED_DMG#Versioned archive / Homebrew" --clobber
    elif release_asset_exists "$TAG" "NullPlayer-$VERSION.dmg"; then
        log_info "Versioned asset already exists; leaving it unchanged"
    else
        gh release upload "$TAG" "$VERSIONED_DMG#Versioned archive / Homebrew"
    fi
else
    log_info "Creating GitHub release $TAG"
    gh release create "$TAG" \
        "$STABLE_DMG#Download for macOS" \
        "$VERSIONED_DMG#Versioned archive / Homebrew" \
        --title "$VERSION" \
        --notes-file "$NOTES_FILE" \
        "${RELEASE_FLAGS[@]}"
fi

log_success "Release $TAG is ready"
