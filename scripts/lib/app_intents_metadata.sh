#!/bin/bash
# Build Contents/Resources/Metadata.appintents for a NullPlayer .app bundle.
#
# Shortcuts discovers App Intents only from that folder. Xcode makes it in two steps: swiftc emits
# `.swiftconstvalues` (Package.swift passes -emit-const-values with the protocol list in
# app_intents_const_protocols.json), then appintentsmetadataprocessor turns them into the metadata.
# SwiftPM runs only the first step, so this script runs the second, with the arguments Xcode 26.2
# passes (AppIntentsMetadata.xcspec).
#
# Usage: app_intents_metadata.sh <swiftpm-build-dir> <app-bundle>
#   <swiftpm-build-dir>  e.g. .build/arm64-apple-macosx/release (the build the binary came from)
#   <app-bundle>         a bundle whose Contents/MacOS/NullPlayer and Contents/Info.plist are in place
#
# Fails when the processor writes nothing, or when any type the compiler saw conforming to
# AppIntent is missing from extract.actionsdata: an empty or partial result would otherwise ship
# silently and the actions would just not appear in Shortcuts.

set -euo pipefail

BUILD_DIR="${1:?usage: app_intents_metadata.sh <swiftpm-build-dir> <app-bundle>}"
APP_BUNDLE="${2:?usage: app_intents_metadata.sh <swiftpm-build-dir> <app-bundle>}"
MODULE="NullPlayer"
DEPLOYMENT_TARGET="14.0"

OBJ_DIR="$BUILD_DIR/$MODULE.build"
RESOURCES_DIR="$APP_BUNDLE/Contents/Resources"
BINARY="$APP_BUNDLE/Contents/MacOS/$MODULE"
METADATA_DIR="$RESOURCES_DIR/Metadata.appintents"

fail() { echo "app_intents_metadata: $*" >&2; exit 1; }

[[ -f "$OBJ_DIR/sources" ]] || fail "no SwiftPM source list at $OBJ_DIR/sources"
[[ -f "$BINARY" ]] || fail "no binary at $BINARY"
[[ -f "$APP_BUNDLE/Contents/Info.plist" ]] || fail "no Info.plist in $APP_BUNDLE"

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

# Debug builds write one <File>.swift.swiftconstvalues per source; whole-module release builds write
# one <Module>.swiftconstvalues. Take the per-file outputs of the current sources only, so a stale one
# left by a deleted file never reaches the processor, and fall back to the module's.
cp "$OBJ_DIR/sources" "$WORK/sources.list"
: > "$WORK/constvalues.list"
while IFS= read -r src; do
    cv="$OBJ_DIR/$(basename "$src").swiftconstvalues"
    [[ -f "$cv" ]] && echo "$cv" >> "$WORK/constvalues.list"
done < "$WORK/sources.list"
if [[ ! -s "$WORK/constvalues.list" && -f "$OBJ_DIR/$MODULE.swiftconstvalues" ]]; then
    echo "$OBJ_DIR/$MODULE.swiftconstvalues" > "$WORK/constvalues.list"
fi
[[ -s "$WORK/constvalues.list" ]] || fail "no .swiftconstvalues under $OBJ_DIR — is -emit-const-values in Package.swift?"
: > "$WORK/metadata.list"
: > "$WORK/static-metadata.list"

ARCH=$(basename "$(dirname "$BUILD_DIR")"); ARCH="${ARCH%%-*}"
BUNDLE_ID=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP_BUNDLE/Contents/Info.plist")
XCODE_BUILD=$(xcodebuild -version | awk '/Build version/ { print $3 }')
TOOLCHAIN_DIR="$(xcode-select -p)/Toolchains/XcodeDefault.xctoolchain"
SDK_ROOT=$(xcrun --sdk macosx --show-sdk-path)

rm -rf "$METADATA_DIR"
mkdir -p "$RESOURCES_DIR"
xcrun appintentsmetadataprocessor \
    --toolchain-dir "$TOOLCHAIN_DIR" \
    --module-name "$MODULE" \
    --sdk-root "$SDK_ROOT" \
    --xcode-version "$XCODE_BUILD" \
    --platform-family macOS \
    --deployment-target "$DEPLOYMENT_TARGET" \
    --bundle-identifier "$BUNDLE_ID" \
    --output "$RESOURCES_DIR" \
    --target-triple "$ARCH-apple-macos$DEPLOYMENT_TARGET" \
    --binary-file "$BINARY" \
    --source-file-list "$WORK/sources.list" \
    --metadata-file-list "$WORK/metadata.list" \
    --static-metadata-file-list "$WORK/static-metadata.list" \
    --swift-const-vals-list "$WORK/constvalues.list" \
    --compile-time-extraction \
    --deployment-aware-processing \
    --validate-assistant-intents \
    --no-app-shortcuts-localization \
    > "$WORK/processor.log" 2>&1 || { cat "$WORK/processor.log" >&2; fail "appintentsmetadataprocessor failed"; }

ACTIONS="$METADATA_DIR/extract.actionsdata"
[[ -s "$ACTIONS" ]] || { cat "$WORK/processor.log" >&2; fail "$ACTIONS was not written"; }

# Every AppIntent the compiler saw must be in the metadata.
python3 - "$ACTIONS" "$WORK/constvalues.list" <<'PY'
import json, sys
actions = json.load(open(sys.argv[1])).get("actions", {})
expected = set()
for path in open(sys.argv[2]).read().split("\n"):
    if not path:
        continue
    for entry in json.load(open(path)):
        if "AppIntents.AppIntent" in entry.get("conformances", []):
            expected.add(entry["typeName"].split(".")[-1])
if not expected:
    sys.exit("app_intents_metadata: no AppIntent types in the const values")
missing = sorted(expected - set(actions))
if missing:
    sys.exit("app_intents_metadata: missing from extract.actionsdata: " + ", ".join(missing))
print(f"app_intents_metadata: {len(actions)} action(s): " + ", ".join(sorted(actions)))
PY
