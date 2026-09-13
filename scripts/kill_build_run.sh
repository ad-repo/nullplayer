#!/bin/bash
# NullPlayer Build and Run Script
# Kills any running instance, builds, and runs the app

set -e

cd "$(dirname "$0")/.."

# Build configuration: release by default, debug with --debug/-d.
# A debug build is required to exercise #if DEBUG-only features such as the
# "Recreate Windows (Debug)" Window-menu action used for live-UI-switch QA.
#
# Everything after a bare `--` is passed through to the binary, so a scenario can be
# launched from the front door instead of a hand-rolled nohup line:
#   ./scripts/kill_build_run.sh --debug --log /tmp/np.log -- -uiMode wmp
CONFIG="release"
RUN_LOG=""
APP_ARGS=()
while [ $# -gt 0 ]; do
    case "$1" in
        --debug|-d) CONFIG="debug"; shift ;;
        --release|-r) CONFIG="release"; shift ;;
        --log) RUN_LOG="$2"; shift 2 ;;
        --) shift; APP_ARGS=("$@"); break ;;
        *) echo "Unknown option: $1 (use --debug, --release, --log <path>, or -- <app args>)"; exit 1 ;;
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
if [[ -n "$RUN_LOG" ]]; then
    : > "$RUN_LOG"
    "$BUILD_DIR/NullPlayer" "${APP_ARGS[@]}" > "$RUN_LOG" 2>&1 &
else
    "$BUILD_DIR/NullPlayer" "${APP_ARGS[@]}" &
fi
APP_PID=$!

# A binary launched from a script shell inherits background QoS: the UI throttles, timers
# defer, and animation stalls. Un-throttle so what is measured is the app, not the scheduler.
taskpolicy -B -p "$APP_PID" 2>/dev/null || true

echo "✅ NullPlayer is running! (pid $APP_PID)"
[[ -n "$RUN_LOG" ]] && echo "📝 Log: $RUN_LOG"
exit 0
