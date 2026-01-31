#!/bin/bash
# AdAmp DMG Build Script
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
APP_NAME="AdAmp"
BUNDLE_ID="com.adamp.player"
INFO_PLIST="$REPO_ROOT/Sources/AdAmp/Resources/Info.plist"

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
echo "  AdAmp DMG Builder"
echo "======================================"
echo ""

# Step 1: Check frameworks exist
log_info "Checking required frameworks..."
if [[ ! -d "$REPO_ROOT/Frameworks/VLCKit.framework" ]] || [[ ! -f "$REPO_ROOT/Frameworks/libprojectM-4.dylib" ]]; then
    log_error "Required frameworks not found. Run ./scripts/bootstrap.sh first."
    exit 1
fi
log_success "Frameworks found"

# Step 2: Build release binary
if [[ "$SKIP_BUILD" == false ]]; then
    log_info "Building release binary..."
    swift build -c release
    log_success "Build complete"
else
    log_info "Skipping build (--skip-build)"
    if [[ ! -f "$BUILD_DIR/AdAmp" ]]; then
        log_error "No release build found at $BUILD_DIR/AdAmp"
        exit 1
    fi
fi

# Step 3: Clean and create app bundle structure
log_info "Creating app bundle structure..."
rm -rf "$APP_BUNDLE"
mkdir -p "$MACOS_DIR"
mkdir -p "$FRAMEWORKS_DIR"
mkdir -p "$RESOURCES_DIR"

# Step 4: Copy executable
log_info "Copying executable..."
cp "$BUILD_DIR/AdAmp" "$MACOS_DIR/"

# Step 5: Copy frameworks
log_info "Copying frameworks..."
cp -R "$REPO_ROOT/Frameworks/VLCKit.framework" "$FRAMEWORKS_DIR/"
cp "$REPO_ROOT/Frameworks/libprojectM-4.dylib" "$FRAMEWORKS_DIR/"
ln -sf "libprojectM-4.dylib" "$FRAMEWORKS_DIR/libprojectM-4.4.dylib"

# Copy ogg and vorbis frameworks from xcframework artifacts
OGG_FRAMEWORK="$REPO_ROOT/.build/artifacts/ogg-binary-xcframework/ogg/ogg.xcframework/macos-arm64_x86_64/ogg.framework"
VORBIS_FRAMEWORK="$REPO_ROOT/.build/artifacts/vorbis-binary-xcframework/vorbis/vorbis.xcframework/macos-arm64_x86_64/vorbis.framework"

if [[ -d "$OGG_FRAMEWORK" ]]; then
    cp -R "$OGG_FRAMEWORK" "$FRAMEWORKS_DIR/"
else
    log_warning "ogg.framework not found - app may not run"
fi

if [[ -d "$VORBIS_FRAMEWORK" ]]; then
    cp -R "$VORBIS_FRAMEWORK" "$FRAMEWORKS_DIR/"
else
    log_warning "vorbis.framework not found - app may not run"
fi

# Step 6: Copy resources from the build output
log_info "Copying resources..."
# The swift build puts resources in AdAmp_AdAmp.bundle/Resources
BUNDLE_RESOURCES="$BUILD_DIR/AdAmp_AdAmp.bundle/Resources"
if [[ -d "$BUNDLE_RESOURCES" ]]; then
    cp -R "$BUNDLE_RESOURCES/"* "$RESOURCES_DIR/" 2>/dev/null || true
    log_success "Resources copied (Presets, Textures, etc.)"
else
    log_warning "No resources found at $BUNDLE_RESOURCES"
fi

# Also copy Info.plist from source
cp "$REPO_ROOT/Sources/AdAmp/Resources/Info.plist" "$CONTENTS_DIR/"

# Step 7: Create app icon from AppIcon.png
APP_ICON_PNG="$REPO_ROOT/Sources/AdAmp/Resources/AppIcon.png"
if [[ -f "$APP_ICON_PNG" ]]; then
    log_info "Creating app icon..."
    ICONSET_DIR="$DIST_DIR/AppIcon.iconset"
    rm -rf "$ICONSET_DIR"
    mkdir -p "$ICONSET_DIR"
    
    # Generate all required icon sizes
    sips -z 16 16     "$APP_ICON_PNG" --out "$ICONSET_DIR/icon_16x16.png" >/dev/null
    sips -z 32 32     "$APP_ICON_PNG" --out "$ICONSET_DIR/icon_16x16@2x.png" >/dev/null
    sips -z 32 32     "$APP_ICON_PNG" --out "$ICONSET_DIR/icon_32x32.png" >/dev/null
    sips -z 64 64     "$APP_ICON_PNG" --out "$ICONSET_DIR/icon_32x32@2x.png" >/dev/null
    sips -z 128 128   "$APP_ICON_PNG" --out "$ICONSET_DIR/icon_128x128.png" >/dev/null
    sips -z 256 256   "$APP_ICON_PNG" --out "$ICONSET_DIR/icon_128x128@2x.png" >/dev/null
    sips -z 256 256   "$APP_ICON_PNG" --out "$ICONSET_DIR/icon_256x256.png" >/dev/null
    sips -z 512 512   "$APP_ICON_PNG" --out "$ICONSET_DIR/icon_256x256@2x.png" >/dev/null
    sips -z 512 512   "$APP_ICON_PNG" --out "$ICONSET_DIR/icon_512x512.png" >/dev/null
    sips -z 1024 1024 "$APP_ICON_PNG" --out "$ICONSET_DIR/icon_512x512@2x.png" >/dev/null
    
    # Create .icns file
    iconutil -c icns "$ICONSET_DIR" -o "$RESOURCES_DIR/AppIcon.icns"
    rm -rf "$ICONSET_DIR"
    log_success "App icon created"
else
    log_warning "AppIcon.png not found, skipping icon creation"
fi

# Step 9: Fix library rpaths
log_info "Fixing library paths..."

# Add rpath to executable if not already present
install_name_tool -add_rpath "@executable_path/../Frameworks" "$MACOS_DIR/AdAmp" 2>/dev/null || true

# Fix libprojectM reference in executable
install_name_tool -change "@rpath/libprojectM-4.4.dylib" "@executable_path/../Frameworks/libprojectM-4.4.dylib" "$MACOS_DIR/AdAmp" 2>/dev/null || true

# Update libprojectM's own install name
install_name_tool -id "@executable_path/../Frameworks/libprojectM-4.dylib" "$FRAMEWORKS_DIR/libprojectM-4.dylib" 2>/dev/null || true

log_success "App bundle created at $APP_BUNDLE"

# Step 10: Create DMG
log_info "Creating DMG..."

DMG_NAME="$APP_NAME-$VERSION.dmg"
DMG_PATH="$DIST_DIR/$DMG_NAME"
STAGING_DIR="$DIST_DIR/dmg_staging"

# Create staging directory
rm -rf "$STAGING_DIR"
mkdir -p "$STAGING_DIR"

# Copy app to staging
cp -R "$APP_BUNDLE" "$STAGING_DIR/"

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
echo "======================================"
echo ""
