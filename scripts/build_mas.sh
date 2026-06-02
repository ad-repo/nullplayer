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

log_success "MAS_APP_IDENTITY set"
log_success "MAS_INSTALLER_IDENTITY set"
log_success "MAS_PROVISION_PROFILE found: $(basename "$MAS_PROVISION_PROFILE")"

# Attempt to surface profile expiry (best-effort, non-fatal)
log_info "Checking provisioning profile validity..."
if security cms -D -i "$MAS_PROVISION_PROFILE" 2>/dev/null | grep -q "ExpirationDate"; then
    log_success "Provisioning profile is valid"
else
    log_warning "Could not verify provisioning profile expiry"
fi

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
        codesign --force --sign "$MAS_APP_IDENTITY" --timestamp "$framework" 2>/dev/null || true
    fi
done

for dylib in "$FRAMEWORKS_DIR"/*.dylib; do
    if [[ -f "$dylib" && ! -L "$dylib" ]]; then
        log_info "  Signing dylib: $(basename "$dylib")"
        codesign --force --sign "$MAS_APP_IDENTITY" --timestamp "$dylib" 2>/dev/null || true
    fi
done

# Sign app bundle WITH entitlements
log_info "Code signing app bundle with entitlements..."
codesign --force --sign "$MAS_APP_IDENTITY" --timestamp --entitlements "$REPO_ROOT/Sources/NullPlayer/Resources/NullPlayer.entitlements" "$APP_BUNDLE"
log_success "Code signing complete"

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
echo "  - xcrun notarytool submit --wait \"$PKG_PATH\""
echo ""
log_warning "Important: CFBundleVersion ($BUILD_NUMBER) must increase on each submission"
log_warning "Note: Update Info.plist and rebuild to increment version"
echo ""
