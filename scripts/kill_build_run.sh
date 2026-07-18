#!/bin/bash
# NullPlayer Build and Run Script
# Kills any running instance, builds, and runs the app

set -e

cd "$(dirname "$0")/.."

# Build configuration: release by default, debug with --debug/-d.
# A debug build is required to exercise #if DEBUG-only features such as the
# "Recreate Windows (Debug)" Window-menu action used for live-UI-switch QA.
CONFIG="release"
for arg in "$@"; do
    case "$arg" in
        --debug|-d) CONFIG="debug" ;;
        --release|-r) CONFIG="release" ;;
        *) echo "Unknown option: $arg (use --debug or --release)"; exit 1 ;;
    esac
done

# Check if frameworks are installed, run bootstrap if not
if [[ ! -d "Frameworks/VLCKit.framework" ]] || [[ ! -f "Frameworks/libprojectM-4.dylib" ]]; then
    echo "⚠️  Frameworks not found. Running bootstrap..."
    ./scripts/bootstrap.sh
    echo ""
fi

echo "🔄 Stopping any running NullPlayer instances..."
# Kill only the NullPlayer binary, not processes with nullplayer in path
pkill -9 -x NullPlayer 2>/dev/null || true
sleep 1

# Wait for any lingering processes to fully terminate
while pgrep -x NullPlayer > /dev/null 2>&1; do
    echo "⏳ Waiting for previous instance to terminate..."
    sleep 0.5
done

echo "🔨 Building NullPlayer (${CONFIG} mode)..."
swift build -c "$CONFIG"

# Determine build directory based on architecture
BUILD_ARCH=$(uname -m)
if [[ "$BUILD_ARCH" == "x86_64" ]]; then
    BUILD_DIR=".build/x86_64-apple-macosx/${CONFIG}"
else
    BUILD_DIR=".build/arm64-apple-macosx/${CONFIG}"
fi

# Copy vendored frameworks to the build frameworks directory so the app's
# @executable_path/../Frameworks rpath resolves them at runtime.
echo "📦 Copying vendored frameworks..."
mkdir -p "${BUILD_DIR%/$CONFIG}/Frameworks"
cp -f Frameworks/libprojectM-4.dylib "${BUILD_DIR%/$CONFIG}/Frameworks/" 2>/dev/null || true
cp -f Frameworks/libprojectM-4.4.dylib "${BUILD_DIR%/$CONFIG}/Frameworks/" 2>/dev/null || true
# VLCKit.framework (LGPL video engine) is self-contained; copy the whole bundle.
# The vendored framework ships with an invalid ad-hoc signature, so re-sign it
# ad-hoc (matching build_dmg.sh) — otherwise dyld kills the app with a
# CODESIGNING "Invalid Page" fault when it maps the framework at launch.
# Staging + re-signing the ~600 MB bundle is slow, so only do it when the copy
# is missing or its signature doesn't verify.
VLCKIT_DEST="${BUILD_DIR%/$CONFIG}/Frameworks/VLCKit.framework"
if [[ ! -d "$VLCKIT_DEST" ]] || ! codesign --verify "$VLCKIT_DEST" 2>/dev/null; then
    echo "   Staging + re-signing VLCKit.framework..."
    rm -rf "$VLCKIT_DEST"
    cp -R Frameworks/VLCKit.framework "${BUILD_DIR%/$CONFIG}/Frameworks/"
    codesign --force --sign - "$VLCKIT_DEST" 2>/dev/null || true
fi

echo "🚀 Launching NullPlayer..."
"$BUILD_DIR/NullPlayer" &

echo "✅ NullPlayer is running!"
