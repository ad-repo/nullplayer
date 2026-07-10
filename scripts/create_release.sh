#!/bin/bash
# Create or update a GitHub release with human-friendly download assets.
#
# Usage: ./scripts/create_release.sh [--skip-build] [--draft] [--prerelease] [--dry-run] [--replace-versioned] [--skip-tap]

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

# Homebrew tap (a separate repo, not cloned locally — edited via the GitHub API).
TAP_REPO="ad-repo/homebrew-nullplayer"
CASK_PATH="Casks/nullplayer.rb"

VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" "$INFO_PLIST")
TAG="$VERSION"
VERSIONED_DMG="$DIST_DIR/NullPlayer-$VERSION.dmg"
STABLE_DMG="$DIST_DIR/NullPlayer.dmg"
NOTES_FILE=$(mktemp "${TMPDIR:-/tmp}/nullplayer-release-$VERSION.XXXXXX")
CHANGELOG_FILE=$(mktemp "${TMPDIR:-/tmp}/nullplayer-changelog-$VERSION.XXXXXX")

SKIP_BUILD=false
DRY_RUN=false
REPLACE_VERSIONED=false
SKIP_TAP=false
DRAFT_OR_PRERELEASE=false
VERSIONED_PUBLISHED=false
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
            DRAFT_OR_PRERELEASE=true
            ;;
        --prerelease)
            RELEASE_FLAGS+=(--prerelease)
            DRAFT_OR_PRERELEASE=true
            ;;
        --dry-run)
            DRY_RUN=true
            ;;
        --replace-versioned)
            REPLACE_VERSIONED=true
            ;;
        --skip-tap)
            SKIP_TAP=true
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
        log_warning "Replacing versioned release asset; the Homebrew cask SHA256 may change"
        gh release upload "$TAG" "$VERSIONED_DMG#Versioned archive / Homebrew" --clobber
        VERSIONED_PUBLISHED=true
    elif release_asset_exists "$TAG" "NullPlayer-$VERSION.dmg"; then
        log_info "Versioned asset already exists; leaving it unchanged"
    else
        gh release upload "$TAG" "$VERSIONED_DMG#Versioned archive / Homebrew"
        VERSIONED_PUBLISHED=true
    fi
else
    log_info "Creating GitHub release $TAG"
    gh release create "$TAG" \
        "$STABLE_DMG#Download for macOS" \
        "$VERSIONED_DMG#Versioned archive / Homebrew" \
        --title "$VERSION" \
        --notes-file "$NOTES_FILE" \
        "${RELEASE_FLAGS[@]}"
    VERSIONED_PUBLISHED=true
fi

log_success "Release $TAG is ready"

# Point the Homebrew tap at the versioned DMG we just published. Only run when
# the versioned asset actually changed (a full release, a fresh upload, or an
# explicit --replace-versioned) so brew users on an untouched asset aren't
# disturbed, and never for drafts/prereleases whose download URL isn't live yet.
update_homebrew_tap() {
    local sha old_content blob_sha new_content commit_url cask_file
    cask_file=$(mktemp "${TMPDIR:-/tmp}/nullplayer-cask-$VERSION.XXXXXX")

    log_info "Updating Homebrew cask $CASK_PATH in $TAP_REPO"

    sha=$(shasum -a 256 "$VERSIONED_DMG" | awk '{print $1}')

    # Fetch the blob sha and content from one API response. Two separate calls
    # could race a concurrent edit to the tap and PUT a newer sha with older
    # content, silently clobbering the intervening change. gsub flattens the
    # base64 (GitHub wraps it in newlines) so it reads back as a single line.
    local cask_meta content_b64
    if ! cask_meta=$(gh api "repos/$TAP_REPO/contents/$CASK_PATH" --jq '.sha, (.content | gsub("\n"; ""))'); then
        log_error "Could not read $CASK_PATH from $TAP_REPO; update the cask manually"
        rm -f "$cask_file"
        return 1
    fi
    blob_sha=${cask_meta%%$'\n'*}
    content_b64=${cask_meta#*$'\n'}
    old_content=$(base64 -d <<<"$content_b64")

    printf '%s\n' "$old_content" > "$cask_file"

    # Only version and sha256 change; the cask url is templated on #{version}.
    sed -i '' -E "s/version \"[^\"]*\"/version \"$VERSION\"/" "$cask_file"
    sed -i '' -E "s/sha256 \"[^\"]*\"/sha256 \"$sha\"/" "$cask_file"

    if ! grep -q "version \"$VERSION\"" "$cask_file" || ! grep -q "sha256 \"$sha\"" "$cask_file"; then
        log_error "Could not rewrite version/sha256 in $CASK_PATH; leaving the tap untouched"
        rm -f "$cask_file"
        return 1
    fi

    new_content=$(cat "$cask_file")
    if [[ "$new_content" == "$old_content" ]]; then
        log_info "Homebrew cask already at $VERSION with a matching sha256; nothing to update"
        rm -f "$cask_file"
        return 0
    fi

    commit_url=$(gh api -X PUT "repos/$TAP_REPO/contents/$CASK_PATH" \
        -f message="Update NullPlayer to $VERSION" \
        -f content="$(base64 -i "$cask_file")" \
        -f sha="$blob_sha" -q '.commit.html_url')

    rm -f "$cask_file"
    log_success "Homebrew cask updated: $commit_url"
    log_info "brew upgrade --cask ad-repo/nullplayer/nullplayer now pulls $VERSION"
}

if [[ "$SKIP_TAP" == true ]]; then
    log_info "Skipping Homebrew tap update (--skip-tap)"
elif [[ "$DRAFT_OR_PRERELEASE" == true ]]; then
    log_info "Draft/prerelease build; leaving the Homebrew cask on the current release"
elif [[ "$VERSIONED_PUBLISHED" != true ]]; then
    log_info "Versioned asset unchanged; leaving the Homebrew cask as-is"
else
    update_homebrew_tap
fi
