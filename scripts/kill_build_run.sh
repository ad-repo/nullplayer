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
#
# --bundle wraps the build in a registered dev bundle, dist/dev/NullPlayer.app, and opens that
# instead of the bare binary. Shortcuts and Siri only see App Intents in a registered .app, so this
# is the loop for testing them. The bundle ID is com.nullplayer.app.dev, so it never competes with an
# installed /Applications/NullPlayer.app; its defaults domain is seeded once from the bare binary's.
CONFIG="release"
RUN_LOG=""
BUNDLE=false
APP_ARGS=()
while [ $# -gt 0 ]; do
    case "$1" in
        --debug|-d) CONFIG="debug"; shift ;;
        --release|-r) CONFIG="release"; shift ;;
        --bundle|-b) BUNDLE=true; shift ;;
        --log) RUN_LOG="$2"; shift 2 ;;
        --) shift; APP_ARGS=("$@"); break ;;
        *) echo "Unknown option: $1 (use --debug, --release, --bundle, --log <path>, or -- <app args>)"; exit 1 ;;
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

if [[ "$BUNDLE" == true ]]; then
    DEV_APP="dist/dev/NullPlayer.app"
    DEV_ID="com.nullplayer.app.dev"
    STAGED_FRAMEWORKS="$PWD/${BUILD_DIR%/$CONFIG}/Frameworks"
    echo "📦 Assembling dev bundle $DEV_APP..."
    rm -rf "$DEV_APP"
    mkdir -p "$DEV_APP/Contents/MacOS" "$DEV_APP/Contents/Resources"
    cp "$BUILD_DIR/NullPlayer" "$DEV_APP/Contents/MacOS/"
    # Load the frameworks from where the build left them rather than copying the ~600 MB VLCKit:
    # absolute rpaths to the staged VLCKit/projectM and to SwiftPM's ogg/vorbis, which the bare binary
    # finds beside itself through @loader_path. Not symlinks in Contents/Frameworks: a symlink leaving
    # the bundle fails strict signature validation, and linkd then refuses the app's App Intents
    # connection ("requiresValidatedBundle"). Resources need nothing: Bundle.module falls back to the
    # build path.
    install_name_tool -add_rpath "$STAGED_FRAMEWORKS" -add_rpath "$PWD/$BUILD_DIR" \
        "$DEV_APP/Contents/MacOS/NullPlayer" 2>/dev/null
    cp Sources/NullPlayer/Resources/Info.plist "$DEV_APP/Contents/"
    /usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $DEV_ID" "$DEV_APP/Contents/Info.plist"
    ./scripts/lib/app_intents_metadata.sh "$BUILD_DIR" "$DEV_APP"
    # Shortcuts only talks to an app whose signature carries a Team ID: linkd rejects an ad-hoc one
    # ("Unable to get teamId" … "requiresValidatedBundle"). Sign with NULLPLAYER_SIGN_IDENTITY, else
    # the first Apple Development identity in the keychain (the free personal-team one works for
    # this), else ad-hoc, where the actions are listed in Shortcuts but fail to run.
    SIGN_IDENTITY="${NULLPLAYER_SIGN_IDENTITY:-$(security find-identity -v -p codesigning \
        | awk -F'"' '/Apple Development/ { print $2; exit }')}"
    if [[ -n "$SIGN_IDENTITY" ]]; then
        echo "   Signing with $SIGN_IDENTITY"
        codesign --force --sign "$SIGN_IDENTITY" "$DEV_APP"
    else
        echo "⚠️  No Apple Development identity: signing ad-hoc. Shortcuts will list the actions but"
        echo "   cannot run them. Add one in Xcode → Settings → Accounts → Manage Certificates."
        codesign --force --sign - "$DEV_APP"
    fi
    # linkd rejects an app whose bundle fails strict validation; catch it here, not in Shortcuts.
    codesign --verify --strict "$DEV_APP"
    /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$DEV_APP"

    # Seed the dev defaults domain once, so the dev bundle starts with the bare binary's settings.
    if ! defaults read "$DEV_ID" >/dev/null 2>&1 && defaults read NullPlayer >/dev/null 2>&1; then
        echo "   Seeding $DEV_ID defaults from the NullPlayer domain..."
        defaults export NullPlayer - | defaults import "$DEV_ID" -
    fi

    echo "🚀 Launching $DEV_APP..."
    OPEN_ARGS=(-n "$DEV_APP")
    if [[ -n "$RUN_LOG" ]]; then
        : > "$RUN_LOG"
        OPEN_ARGS+=(--stdout "$RUN_LOG" --stderr "$RUN_LOG")
    fi
    [[ ${#APP_ARGS[@]} -gt 0 ]] && OPEN_ARGS+=(--args "${APP_ARGS[@]}")
    open "${OPEN_ARGS[@]}"
    APP_PID=""
    for _ in $(seq 1 40); do
        APP_PID=$(pgrep -nf "$DEV_APP/Contents/MacOS/NullPlayer" || true)
        [[ -n "$APP_PID" ]] && break
        sleep 0.25
    done
    [[ -n "$APP_PID" ]] || { echo "❌ The dev bundle did not start"; exit 1; }
    echo "✅ NullPlayer dev bundle is running! (pid $APP_PID)"
    [[ -n "$RUN_LOG" ]] && echo "📝 Log: $RUN_LOG"
    exit 0
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
