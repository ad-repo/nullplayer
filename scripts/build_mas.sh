#!/bin/bash
# NullPlayer Mac App Store Build Script
# Creates a signed app bundle and installer package for MAS submission
#
# Requires environment variables:
#   MAS_APP_IDENTITY      - Code signing identity (e.g., "3rd Party Mac Developer Application: ...")
#   MAS_INSTALLER_IDENTITY - Installer signing identity (e.g., "3rd Party Mac Developer Installer: ...")
#   MAS_PROVISION_PROFILE - Path to MAS provisioning profile (*.provisionprofile)
#
# Usage: ./scripts/build_mas.sh
#        ./scripts/build_mas.sh --skip-build  (use existing release build)

set -eo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}ℹ${NC} $1"; }
log_success() { echo -e "${GREEN}✓${NC} $1"; }
log_warning() { echo -e "${YELLOW}⚠${NC} $1"; }
log_error() { echo -e "${RED}✗${NC} $1" >&2; }

identity_team_id() {
    local identity="$1"
    if [[ "$identity" =~ \(([A-Z0-9]+)\)$ ]]; then
        echo "${BASH_REMATCH[1]}"
    fi
}

# Change to repo root
cd "$(dirname "$0")/.."
REPO_ROOT=$(pwd)

# Configuration
APP_NAME="NullPlayer"
BUNDLE_ID="com.nullplayer.app"
INFO_PLIST="$REPO_ROOT/Sources/NullPlayer/Resources/Info.plist"

# Read version from Info.plist (single source of truth)
VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" "$INFO_PLIST")
BUILD_NUMBER=$(/usr/libexec/PlistBuddy -c "Print CFBundleVersion" "$INFO_PLIST")

# Directories
DIST_DIR="$REPO_ROOT/dist"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"

# Parse arguments
SKIP_BUILD=false
if [[ "${1:-}" == "--skip-build" ]]; then
    SKIP_BUILD=true
fi

# Detect architecture
BUILD_ARCH=$(uname -m)
if [[ "$BUILD_ARCH" == "x86_64" ]]; then
    BUILD_DIR="$REPO_ROOT/.build/x86_64-apple-macosx/release"
else
    BUILD_DIR="$REPO_ROOT/.build/arm64-apple-macosx/release"
fi

echo ""
echo "======================================"
echo "  NullPlayer MAS Builder"
echo "======================================"
echo ""

# Validate required environment variables
log_info "Validating MAS configuration..."
if [[ -z "${MAS_APP_IDENTITY:-}" ]]; then
    log_error "MAS_APP_IDENTITY not set"
    log_error "Example: export MAS_APP_IDENTITY='3rd Party Mac Developer Application: Name (TEAMID)'"
    exit 1
fi

if [[ -z "${MAS_INSTALLER_IDENTITY:-}" ]]; then
    log_error "MAS_INSTALLER_IDENTITY not set"
    log_error "Example: export MAS_INSTALLER_IDENTITY='3rd Party Mac Developer Installer: Name (TEAMID)'"
    exit 1
fi

if [[ -z "${MAS_PROVISION_PROFILE:-}" ]]; then
    log_error "MAS_PROVISION_PROFILE not set"
    log_error "Example: export MAS_PROVISION_PROFILE=\$HOME/Library/MobileDevice/Provisioning\ Profiles/NullPlayer.provisionprofile"
    exit 1
fi

if [[ ! -f "$MAS_PROVISION_PROFILE" ]]; then
    log_error "Provisioning profile not found: $MAS_PROVISION_PROFILE"
    exit 1
fi

PROFILE_PLIST=$(mktemp "${TMPDIR:-/tmp}/nullplayer_mas_profile.XXXXXX")
cleanup() {
    rm -f "$PROFILE_PLIST"
}
trap cleanup EXIT

log_success "MAS_APP_IDENTITY set"
log_success "MAS_INSTALLER_IDENTITY set"
log_success "MAS_PROVISION_PROFILE found: $(basename "$MAS_PROVISION_PROFILE")"

# Validate provisioning profile before doing expensive bundle assembly.
log_info "Checking provisioning profile validity..."
if ! security cms -D -i "$MAS_PROVISION_PROFILE" > "$PROFILE_PLIST"; then
    log_error "Could not decode provisioning profile: $MAS_PROVISION_PROFILE"
    exit 1
fi

EXPIRATION_DATE=$(plutil -extract ExpirationDate raw -o - "$PROFILE_PLIST" 2>/dev/null || true)
EXPIRATION_EPOCH=""
if [[ -n "$EXPIRATION_DATE" ]]; then
    EXPIRATION_EPOCH=$(date -j -u -f "%Y-%m-%dT%H:%M:%SZ" "$EXPIRATION_DATE" "+%s" 2>/dev/null || true)
fi
if [[ -z "$EXPIRATION_EPOCH" ]]; then
    log_error "Could not read provisioning profile ExpirationDate"
    exit 1
fi
if (( EXPIRATION_EPOCH <= $(date -u "+%s") )); then
    log_error "Provisioning profile is expired: $EXPIRATION_DATE"
    exit 1
fi

PROFILE_TEAM=$(/usr/libexec/PlistBuddy -c "Print :TeamIdentifier:0" "$PROFILE_PLIST" 2>/dev/null || true)
APP_IDENTIFIER=$(/usr/libexec/PlistBuddy -c "Print :Entitlements:com.apple.application-identifier" "$PROFILE_PLIST" 2>/dev/null || true)
APP_TEAM=$(identity_team_id "$MAS_APP_IDENTITY")
INSTALLER_TEAM=$(identity_team_id "$MAS_INSTALLER_IDENTITY")
EXPECTED_APP_IDENTIFIER="$PROFILE_TEAM.$BUNDLE_ID"

if [[ -z "$PROFILE_TEAM" || -z "$APP_IDENTIFIER" ]]; then
    log_error "Provisioning profile is missing TeamIdentifier or application identifier"
    exit 1
fi
if [[ "$APP_IDENTIFIER" != "$EXPECTED_APP_IDENTIFIER" ]]; then
    log_error "Provisioning profile app identifier mismatch: expected $EXPECTED_APP_IDENTIFIER, found $APP_IDENTIFIER"
    exit 1
fi
if [[ -n "$APP_TEAM" && "$APP_TEAM" != "$PROFILE_TEAM" ]]; then
    log_error "Application signing identity team ($APP_TEAM) does not match profile team ($PROFILE_TEAM)"
    exit 1
fi
if [[ -n "$INSTALLER_TEAM" && "$INSTALLER_TEAM" != "$PROFILE_TEAM" ]]; then
    log_error "Installer signing identity team ($INSTALLER_TEAM) does not match profile team ($PROFILE_TEAM)"
    exit 1
fi

log_success "Provisioning profile is valid for $APP_IDENTIFIER and expires $EXPIRATION_DATE"

# Source the app assembly helper
source "$(dirname "$0")/lib/assemble_app.sh"

# Assemble the app bundle
assemble_app "$APP_BUNDLE"

# Copy provisioning profile to the bundle (BEFORE signing)
log_info "Embedding provisioning profile..."
FRAMEWORKS_DIR="$APP_BUNDLE/Contents/Frameworks"
cp "$MAS_PROVISION_PROFILE" "$APP_BUNDLE/Contents/embedded.provisionprofile"
log_success "Provisioning profile embedded"

# Sign frameworks and dylibs (inside-out order)
log_info "Code signing frameworks and dylibs..."
for framework in "$FRAMEWORKS_DIR"/*.framework; do
    if [[ -d "$framework" ]]; then
        log_info "  Signing framework: $(basename "$framework")"
        codesign --force --sign "$MAS_APP_IDENTITY" --timestamp "$framework"
    fi
done

for dylib in "$FRAMEWORKS_DIR"/*.dylib; do
    if [[ -f "$dylib" && ! -L "$dylib" ]]; then
        log_info "  Signing dylib: $(basename "$dylib")"
        codesign --force --sign "$MAS_APP_IDENTITY" --timestamp "$dylib"
    fi
done

# Sign app bundle WITH entitlements
log_info "Code signing app bundle with entitlements..."
codesign --force --sign "$MAS_APP_IDENTITY" --timestamp --entitlements "$REPO_ROOT/Sources/NullPlayer/Resources/NullPlayer.entitlements" "$APP_BUNDLE"
log_success "Code signing complete"

log_info "Verifying code signature..."
codesign --verify --deep --strict "$APP_BUNDLE"
log_success "Code signature verified"

# Create the installer package
log_info "Creating installer package..."
PKG_NAME="NullPlayer-$VERSION.pkg"
PKG_PATH="$DIST_DIR/$PKG_NAME"
rm -f "$PKG_PATH"

productbuild --component "$APP_BUNDLE" /Applications --sign "$MAS_INSTALLER_IDENTITY" "$PKG_PATH"
log_success "Installer package created: $PKG_NAME"

# Summary and verification instructions
echo ""
echo "======================================"
log_success "MAS build complete!"
echo ""
echo "  App Bundle: $APP_BUNDLE"
echo "  Installer:  $PKG_PATH"
echo "  Size:       $(du -h "$PKG_PATH" | cut -f1)"
echo "  SHA256:     $(shasum -a 256 "$PKG_PATH" | awk '{print $1}')"
echo "======================================"
echo ""
log_info "Verification commands:"
echo "  codesign --verify --deep --strict \"$APP_BUNDLE\""
echo "  pkgutil --check-signature \"$PKG_PATH\""
echo ""
log_info "Upload via:"
echo "  - Transporter.app (recommended)"
echo "  - xcrun altool --upload-app --type macos --file \"$PKG_PATH\" --bundle-id \"$BUNDLE_ID\""
echo "  (MAS builds are uploaded to App Store Connect, not notarized with notarytool.)"
echo ""
log_warning "Important: CFBundleVersion ($BUILD_NUMBER) must increase on each submission"
log_warning "Note: Update Info.plist and rebuild to increment version"
echo ""
