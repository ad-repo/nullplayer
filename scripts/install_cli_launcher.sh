#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LAUNCHER_SOURCE="$SCRIPT_DIR/nullplayer"
APP_CANDIDATES=(
    "/Applications/NullPlayer.app"
    "$HOME/Applications/NullPlayer.app"
)

find_installed_app() {
    local app_path
    for app_path in "${APP_CANDIDATES[@]}"; do
        if [[ -x "$app_path/Contents/MacOS/NullPlayer" ]]; then
            printf '%s\n' "$app_path"
            return 0
        fi
    done
    return 1
}

if [[ ! -f "$LAUNCHER_SOURCE" ]]; then
    echo "Launcher template not found at $LAUNCHER_SOURCE" >&2
    exit 1
fi

if ! app_path="$(find_installed_app)"; then
    cat >&2 <<'EOF'
NullPlayer.app was not found.

Install it first in one of these locations:
  /Applications/NullPlayer.app
  ~/Applications/NullPlayer.app
EOF
    exit 1
fi

target_dir="/usr/local/bin"
mkdir_cmd=(mkdir -p "$target_dir")
install_cmd=(install -m 755 "$LAUNCHER_SOURCE" "$target_dir/nullplayer")

if [[ -w "$target_dir" ]] || { [[ ! -e "$target_dir" ]] && [[ -w "/usr/local" ]]; }; then
    "${mkdir_cmd[@]}"
    "${install_cmd[@]}"
else
    echo "Installing to $target_dir requires administrator privileges."
    sudo "${mkdir_cmd[@]}"
    sudo "${install_cmd[@]}"
fi

echo "Installed nullplayer to $target_dir/nullplayer"
echo "Using app bundle: $app_path"
echo "Run: nullplayer --cli --help"
