#!/bin/bash
# The one way to launch the debug build on a given skin. Prints one verified line and exits
# 0 (PASS) or 1 (FAIL). Usage:
#
#   skills/app-control/scripts/launch.sh <skin> [--no-play] [--restore] [--log <path>] [-- <extra app args>]
#
#   <skin>  a path or bare installed name:   corona   aquamp   "2222-cPro__Bento"   /abs/x.wmz
#           or a bundled family skin:        modern:NeonWave   metal:"Brushed Steel"
#
# The family (and so -uiMode) comes from the extension: .wsz/.whsz classic, .wal winampModern,
# .wmz wmp. Nothing needs restoring afterwards: restoration is disabled with a *launch argument*
# (NSArgumentDomain), never a `defaults write`, so the user's saved Remember State is untouched.
# NULLPLAYER_PLAY set by the caller replaces the default audio-long track.
# --restore leaves session restoration to the saved setting — only for testing restoration itself,
# and restoration may then put the saved skin back, which the confirm below will catch.
set -euo pipefail
cd "$(dirname "$0")/../../.."

SKIN="${1:?usage: launch.sh <skin> [--no-play] [--restore] [--log <path>] [-- <app args>]}"; shift
PLAY=1; RESTORE=0; LOG=/tmp/np.log; EXTRA=()
while [ $# -gt 0 ]; do
  case "$1" in
    --no-play) PLAY=0; shift ;;
    --restore) RESTORE=1; shift ;;
    --log) LOG="$2"; shift 2 ;;
    --) shift; EXTRA=("$@"); break ;;
    *) echo "launch.sh: unknown option $1" >&2; exit 2 ;;
  esac
done

SUPPORT="$HOME/Library/Application Support/NullPlayer"
D=NullPlayer   # the debug build's defaults domain; never com.nullplayer.app

# --- resolve <skin> to a family and a file --------------------------------------------------
FAMILY=""; FILE=""; NAME=""
case "$SKIN" in
  modern:*) FAMILY=modern; NAME="${SKIN#modern:}" ;;
  metal:*)  FAMILY=metal;  NAME="${SKIN#metal:}" ;;
  /*)       FILE="$SKIN" ;;
  *)  # "corona" matches any family; "corona.wmz" pins one. Never guess between families.
      case "$SKIN" in *.wsz|*.whsz|*.wal|*.wmz|*.WSZ|*.WAL|*.WMZ) PAT="$SKIN" ;; *) PAT="$SKIN.*" ;; esac
      MATCHES=$(find "$SUPPORT/Skins" "$SUPPORT/WinampModernSkins" "$SUPPORT/WMPSkins" \
                  -maxdepth 1 -type f -iname "$PAT" 2>/dev/null)
      if [ "$(printf '%s' "$MATCHES" | grep -c .)" -gt 1 ]; then
        echo "LAUNCH FAIL: '$SKIN' is ambiguous — add the extension or pass the path:"
        printf '  %s\n' "$MATCHES"; exit 1
      fi
      FILE="$MATCHES" ;;
esac
if [ -z "$FAMILY" ]; then
  [ -f "$FILE" ] || { echo "LAUNCH FAIL: no installed skin matches '$SKIN'"; exit 1; }
  case "$(echo "${FILE##*.}" | tr '[:upper:]' '[:lower:]')" in
    wsz|whsz) FAMILY=classic ;;
    wal)      FAMILY=winampModern ;;
    wmz)      FAMILY=wmp ;;
    *) echo "LAUNCH FAIL: unknown skin extension: $FILE"; exit 1 ;;
  esac
  NAME=$(basename "${FILE%.*}")
fi

# --- quit first, THEN write: a running instance can write its own skin back ------------------
pkill -x NullPlayer 2>/dev/null || true
while pgrep -x NullPlayer >/dev/null; do sleep 0.3; done

ARGS=(-uiMode "$FAMILY")
[ "$RESTORE" = 1 ] || ARGS+=(-rememberStateEnabled NO)
ENVS=()
case "$FAMILY" in
  classic)
    defaults delete $D lastClassicSkinPath 2>/dev/null || true
    ENVS+=(NULLPLAYER_SKIN="$FILE") ;;
  winampModern)
    ARGS+=(-winampModernSkinPath "$FILE") ;;
  wmp)
    if [ "$(dirname "$FILE")" = "$SUPPORT/WMPSkins" ]; then
      defaults write $D wmpSkinName -string "$NAME"
    else
      ARGS+=(-wmpSkinPath "$FILE")        # not installed yet: import it
    fi
    defaults delete $D wmpSkinViewID 2>/dev/null || true ;;   # the app rewrites it once the skin renders
  modern|metal)
    defaults write $D "${FAMILY}SkinName" -string "$NAME" ;;
esac

if [ "$PLAY" = 1 ] && [ -z "${NULLPLAYER_PLAY:-}" ]; then   # a caller's own file (e.g. a .cue) wins
  scripts/testdata.sh ensure >/dev/null
  ENVS+=(NULLPLAYER_PLAY="$(scripts/testdata.sh path audio-long)")
fi

# --- build + launch the debug build through the front door ------------------------------------
env ${ENVS[@]+"${ENVS[@]}"} ./scripts/kill_build_run.sh --debug --log "$LOG" \
  -- "${ARGS[@]}" ${EXTRA[@]+"${EXTRA[@]}"} >"$LOG.build" 2>&1 \
  || { echo "LAUNCH FAIL: build failed — tail $LOG.build"; tail -5 "$LOG.build"; exit 1; }
PID=$(pgrep -x NullPlayer | head -1)

# --- confirm the skin actually loaded (every one of these fails silently otherwise) -----------
confirmed() {
  case "$FAMILY" in
    classic)      [ "$(defaults read $D lastClassicSkinPath 2>/dev/null)" = "$FILE" ] ;;
    winampModern) grep -qF "WinampModern surfaces [$(basename "$FILE")]" "$LOG" ;;
    wmp)          [ "$(defaults read $D wmpSkinName 2>/dev/null)" = "$NAME" ] \
                    && defaults read $D wmpSkinViewID >/dev/null 2>&1 ;;
    modern)       grep -qF "ModernSkinLoader: Loaded skin '$NAME'" "$LOG" ;;
    metal)        grep -qF "Loaded built-in metal skin '$NAME'" "$LOG" ;;
  esac
}
for _ in $(seq 60); do
  pgrep -x NullPlayer >/dev/null || { echo "LAUNCH FAIL: app exited — see $LOG"; exit 1; }
  if confirmed; then
    echo "LAUNCH PASS: $FAMILY skin '$NAME'  pid $PID  log $LOG"
    exit 0
  fi
  sleep 0.5
done
echo "LAUNCH FAIL: $FAMILY skin '$NAME' not confirmed after 30s  pid $PID  log $LOG"
exit 1
