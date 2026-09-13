#!/bin/bash
# Route D — hand the user a loaded session.
#
# Copy this to your scratchpad, fill in the SCENARIO block, and hand the user ONE line:
#   ! /path/to/qa-session.sh
# Then end your turn. The user drives the mouse; you own the process and the log.
#
# Rule zero: this builds and runs the LOCAL DEBUG BUILD. It never touches the installed
# /Applications app, and it only ever writes the `NullPlayer` defaults domain.
set -euo pipefail

cd "$(dirname "$0")"
REPO="${REPO:-$HOME/Projects/nullplayer}"
cd "$REPO"

LOG="${LOG:-/tmp/nullplayer-qa.log}"

# --- restore trap -------------------------------------------------------------------
# Every `defaults write` below is undone on exit, so the NEXT run starts from a known
# state rather than from whatever this one left behind. This is not cosmetic: a stale
# wmpSkinName is a launch that silently comes up on the wrong skin.
SAVED=$(mktemp)
save() { # save <key>
  if v=$(defaults read NullPlayer "$1" 2>/dev/null); then
    # Restore the ORIGINAL type. Writing a bool back as -string leaves the key readable
    # but re-typed, which is a silent change to the user's preferences.
    case "$(defaults read-type NullPlayer "$1" 2>/dev/null)" in
      # `defaults read` prints a bool as 1/0, but `defaults write -bool` only accepts
      # true|false|yes|no — feeding 1 back is a usage error and the key is NOT restored.
      *boolean*) flag="-bool"; [ "$v" = "1" ] && v=true || v=false ;;
      *integer*) flag="-int" ;;
      *float*)   flag="-float" ;;
      *)         flag="-string" ;;
    esac
    printf 'defaults write NullPlayer %q %s %q\n' "$1" "$flag" "$v" >> "$SAVED"
  else
    printf 'defaults delete NullPlayer %q 2>/dev/null || true\n' "$1" >> "$SAVED"
  fi
}
restore() { bash "$SAVED" 2>/dev/null || true; rm -f "$SAVED"; }
trap restore EXIT

# --- SCENARIO ------------------------------------------------------------------------
# Edit this block only. Every row's "Confirm it took" is in app-control/SKILL.md Route B.

UI_MODE="wmp"                       # classic | modern | metal | winampModern | wmp
                                    # NB: `modern` is the Original submenu;
                                    #     `winampModern` is the Modern submenu.

save rememberStateEnabled
defaults write NullPlayer rememberStateEnabled -bool false

# A .wmz skin:
save wmpSkinName
save wmpSkinViewID
defaults write NullPlayer wmpSkinName -string "corona"
defaults delete NullPlayer wmpSkinViewID 2>/dev/null || true

# A .wal skin instead:   APP_ARGS+=(-winampModernSkinPath "/abs/Skin.wal")
# A classic .wsz:        export NULLPLAYER_SKIN="/abs/Skin.wsz"
# A modern/metal skin:   save modernSkinName; defaults write NullPlayer modernSkinName -string "NeonWave"

# Playback. audio-long is 20 minutes on purpose: a short file ends mid-session and the
# stop() reads as the defect being investigated.
./scripts/testdata.sh ensure >/dev/null
export NULLPLAYER_PLAY="$(./scripts/testdata.sh path audio-long)"

# Live traces for this session, e.g.:
# export WMP_SEEK_TRACE=1
# export WMP_PLACE_TRACE=1

APP_ARGS=(-uiMode "$UI_MODE")
# --- end SCENARIO --------------------------------------------------------------------

./scripts/kill_build_run.sh --debug --log "$LOG" -- "${APP_ARGS[@]}"

PID=$(pgrep -x NullPlayer | head -1)
cat <<INFO

  Session is up.   pid $PID   log $LOG
  Mode $UI_MODE, playing $(basename "$NULLPLAYER_PLAY").

  Drive it by hand. Defaults are restored when you close this script's shell.
  Quit the app when you are done and press Enter here.

INFO
read -r _
