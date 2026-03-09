#!/bin/bash
# NullPlayer Build and Run Script
# Kills any running instance, builds, and runs the app

set -e

cd "$(dirname "$0")/.."

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

echo "🔨 Building NullPlayer (release mode)..."
swift build -c release

# Determine build directory based on architecture
BUILD_ARCH=$(uname -m)
if [[ "$BUILD_ARCH" == "x86_64" ]]; then
    BUILD_DIR=".build/x86_64-apple-macosx/release"
else
    BUILD_DIR=".build/arm64-apple-macosx/release"
fi

echo "🔏 Ad-hoc signing for keychain access..."
codesign --force --sign - --entitlements scripts/NullPlayer.entitlements "$BUILD_DIR/NullPlayer"

# Copy projectM library to build frameworks directory
echo "📦 Copying projectM libraries..."
mkdir -p "${BUILD_DIR%/release}/Frameworks"
cp -f Frameworks/libprojectM-4.dylib "${BUILD_DIR%/release}/Frameworks/" 2>/dev/null || true
cp -f Frameworks/libprojectM-4.4.dylib "${BUILD_DIR%/release}/Frameworks/" 2>/dev/null || true

echo "🚀 Launching NullPlayer..."
"$BUILD_DIR/NullPlayer" &

echo "✅ NullPlayer is running!"
