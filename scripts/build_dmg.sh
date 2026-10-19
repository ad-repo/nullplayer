#!/bin/bash
# NullPlayer DMG Build Script
# Creates a distributable DMG from the Swift Package Manager build
#
# Usage: ./scripts/build_dmg.sh
#        ./scripts/build_dmg.sh --skip-build  (use existing release build)

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
CONTENTS_DIR="$APP_BUNDLE/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"

# Parse arguments
SKIP_BUILD=false
if [[ "${1:-}" == "--skip-build" ]]; then
    SKIP_BUILD=true
fi

# Notarizing needs a Developer ID signature; fail before the build rather than ship ad-hoc
if [[ -n "${NOTARY_PROFILE:-}" && -z "${DEVELOPER_ID:-}" ]]; then
    log_error "NOTARY_PROFILE is set but DEVELOPER_ID is not; notarization needs a Developer ID signature"
    exit 1
fi

# Release products directory, as SwiftPM reports it for the build system assemble_app uses
# (see scripts/lib/swiftpm.sh)
source "$(dirname "$0")/lib/swiftpm.sh"
BUILD_DIR=$(swiftpm_bin_path release 2>/dev/null)

echo ""
echo "======================================"
echo "  NullPlayer DMG Builder"
echo "======================================"
echo ""

# Source the app assembly helper
source "$(dirname "$0")/lib/assemble_app.sh"

# Assemble the app bundle (Steps 1-9: check, build, structure, copy, sign rpaths)
assemble_app "$APP_BUNDLE"

# Step 10: Code sign the bundle — ad-hoc by default; set DEVELOPER_ID (and NOTARY_PROFILE,
# a `notarytool store-credentials` profile) for a Gatekeeper-clean, notarized release
if [[ -n "${DEVELOPER_ID:-}" ]]; then
    log_info "Code signing app bundle as $DEVELOPER_ID (hardened runtime)..."
    sign_app_bundle "$APP_BUNDLE" --options runtime --timestamp --sign "$DEVELOPER_ID"
else
    log_info "Code signing app bundle (ad-hoc)..."
    sign_app_bundle "$APP_BUNDLE" --sign -
fi
log_success "Code signing complete"

log_success "App bundle created at $APP_BUNDLE"

# Step 11: Create DMG
log_info "Creating DMG..."

DMG_NAME="$APP_NAME-$VERSION.dmg"
DMG_PATH="$DIST_DIR/$DMG_NAME"
STABLE_DMG_NAME="$APP_NAME.dmg"
STABLE_DMG_PATH="$DIST_DIR/$STABLE_DMG_NAME"
STAGING_DIR="$DIST_DIR/dmg_staging"

# Create staging directory
rm -rf "$STAGING_DIR"
mkdir -p "$STAGING_DIR"

# Copy app to staging
cp -R "$APP_BUNDLE" "$STAGING_DIR/"

# Copy CLI launcher and install helper
cp "$REPO_ROOT/scripts/nullplayer" "$STAGING_DIR/"
cp "$REPO_ROOT/scripts/install_cli_launcher.sh" "$STAGING_DIR/"
cp "$REPO_ROOT/scripts/Install NullPlayer CLI.command" "$STAGING_DIR/"
chmod 755 \
    "$STAGING_DIR/nullplayer" \
    "$STAGING_DIR/install_cli_launcher.sh" \
    "$STAGING_DIR/Install NullPlayer CLI.command"

# Create Applications symlink for drag-and-drop install
ln -s /Applications "$STAGING_DIR/Applications"

# Set DMG volume icon if app icon exists
if [[ -f "$RESOURCES_DIR/AppIcon.icns" ]]; then
    cp "$RESOURCES_DIR/AppIcon.icns" "$STAGING_DIR/.VolumeIcon.icns"
    # SetFile -a C marks the folder to use custom icon
    SetFile -a C "$STAGING_DIR" 2>/dev/null || true
fi

# Create the DMG
rm -f "$DMG_PATH"
hdiutil create \
    -volname "$APP_NAME" \
    -srcfolder "$STAGING_DIR" \
    -ov \
    -format UDZO \
    "$DMG_PATH"

# Clean up staging
rm -rf "$STAGING_DIR"

log_success "DMG created at $DMG_PATH"

if [[ -n "${DEVELOPER_ID:-}" ]]; then
    codesign --force --timestamp --sign "$DEVELOPER_ID" "$DMG_PATH"
    if [[ -n "${NOTARY_PROFILE:-}" ]]; then
        log_info "Notarizing DMG (usually a few minutes)..."
        xcrun notarytool submit "$DMG_PATH" --keychain-profile "$NOTARY_PROFILE" --wait
        xcrun stapler staple "$DMG_PATH"
        spctl --assess --type open --context context:primary-signature -v "$DMG_PATH"
        log_success "DMG notarized and stapled"
    else
        log_warning "NOTARY_PROFILE not set — DMG is signed but not notarized"
    fi
fi

# Keep an immutable, versioned DMG for checksums/Homebrew and a stable filename
# for human-facing download links such as GitHub Releases' latest/download URL.
cp "$DMG_PATH" "$STABLE_DMG_PATH"
log_success "Stable DMG copy created at $STABLE_DMG_PATH"

# Summary
echo ""
echo "======================================"
log_success "Build complete!"
echo ""
echo "  App Bundle: $APP_BUNDLE"
echo "  DMG File:   $DMG_PATH"
echo "  Stable DMG: $STABLE_DMG_PATH"
echo "  Size:       $(du -h "$DMG_PATH" | cut -f1)"
echo "  SHA256:     $(shasum -a 256 "$DMG_PATH" | awk '{print $1}')"
echo "======================================"
echo ""
