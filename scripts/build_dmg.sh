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
FRAMEWORKS_DIR="$CONTENTS_DIR/Frameworks"
RESOURCES_DIR="$CONTENTS_DIR/Resources"

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
echo "  NullPlayer DMG Builder"
echo "======================================"
echo ""

# Source the app assembly helper
source "$(dirname "$0")/lib/assemble_app.sh"

# Assemble the app bundle (Steps 1-9: check, build, structure, copy, sign rpaths)
assemble_app "$APP_BUNDLE"

# Step 10: Ad-hoc code sign the bundle
log_info "Code signing app bundle..."

# Sign all frameworks and dylibs first (inside-out signing order)
for framework in "$FRAMEWORKS_DIR/"*.framework; do
    if [[ -d "$framework" ]]; then
        codesign --force --sign - "$framework" 2>/dev/null || true
    fi
done

for dylib in "$FRAMEWORKS_DIR/"*.dylib; do
    if [[ -f "$dylib" && ! -L "$dylib" ]]; then
        codesign --force --sign - "$dylib" 2>/dev/null || true
    fi
done

# Sign optional YouTube→Sonos helper executables if present (before whole-app sign)
for helper in "$MACOS_DIR/yt-dlp" "$MACOS_DIR/ffmpeg"; do
    if [[ -f "$helper" ]]; then
        codesign --force --sign - "$helper" 2>/dev/null || true
    fi
done

# Sign the main executable and app bundle last
codesign --force --sign - "$APP_BUNDLE"
log_success "Code signing complete"

log_success "App bundle created at $APP_BUNDLE"

# Step 11: Create DMG
log_info "Creating DMG..."

DMG_NAME="$APP_NAME-$VERSION.dmg"
DMG_PATH="$DIST_DIR/$DMG_NAME"
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

# Summary
echo ""
echo "======================================"
log_success "Build complete!"
echo ""
echo "  App Bundle: $APP_BUNDLE"
echo "  DMG File:   $DMG_PATH"
echo "  Size:       $(du -h "$DMG_PATH" | cut -f1)"
echo "  SHA256:     $(shasum -a 256 "$DMG_PATH" | awk '{print $1}')"
echo "======================================"
echo ""
