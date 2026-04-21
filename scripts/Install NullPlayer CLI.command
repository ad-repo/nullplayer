#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
"$SCRIPT_DIR/install_cli_launcher.sh"

echo
read -r -p "Press Return to close this window..." _
