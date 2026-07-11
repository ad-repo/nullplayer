#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# Invoke via `bash` rather than executing directly: when this runs off a
# downloaded DMG the scripts carry macOS's quarantine flag, and a direct
# execve of a quarantined script is blocked by Gatekeeper. Passing the
# script to bash reads it as data and sidesteps that check.
bash "$SCRIPT_DIR/install_cli_launcher.sh"

echo
read -r -p "Press Return to close this window..." _
