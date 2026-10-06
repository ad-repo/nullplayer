#!/bin/bash
# Pin SwiftPM to the native build system wherever the toolchain still offers it.
# Source this file, then pass SWIFTPM_ARGS to every `swift build` / `swift test`:
#
#   source "$(dirname "$0")/lib/swiftpm.sh"
#   swift build -c debug ${SWIFTPM_ARGS[@]+"${SWIFTPM_ARGS[@]}"}
#   BUILD_DIR=$(swiftpm_bin_path debug)
#
# Why: Swift 6.4 made `swiftbuild` the default. It writes products to
# .build/out/Products/<Config>/ instead of .build/<arch>-apple-macosx/<config>/, lays out
# resource bundles differently, and does not hand the app target's `-F Frameworks` to the
# test target (`swift test` fails: "unable to resolve module dependency: 'VLCKit'"). These
# scripts assume the native layout, and one that builds one way and runs the other
# launches (or packages) a stale binary without any error.
#
# Backwards compatible: a toolchain without `--build-system`, or one that does not list
# `native` under it, gets no flag and builds with its own default, which on those
# toolchains is native. The `native` check reads the help text rather than a version
# number, so it covers both help formats ("native  - ..." and "(values: native, ...)").
SWIFTPM_ARGS=()
if swift build --help 2>/dev/null | grep -A8 -- '--build-system' | grep -qw 'native'; then
    SWIFTPM_ARGS=(--build-system native)
fi

# swiftpm_bin_path <config>: where `swift build -c <config>` with SWIFTPM_ARGS puts its
# products. Ask SwiftPM rather than hard-code the directory, so this stays right on any
# layout. Empty-array expansion is written for macOS's bash 3.2 under `set -u`.
swiftpm_bin_path() {
    swift build -c "$1" ${SWIFTPM_ARGS[@]+"${SWIFTPM_ARGS[@]}"} --show-bin-path
}
