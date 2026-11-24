#!/bin/bash
# What a Finder open does, per skin family. Sends real `odoc` Apple Events (`open -a`, the event
# Finder sends to a default app) to a bundle of the current debug build, and judges each row from
# the log, the playback snapshot, the frontmost process and the window list. Usage:
#
#   skills/app-control/scripts/finder-open-matrix.sh [--family f[,f…]] [--scenario n[,n…]]
#                                                    [--out <dir>] [--no-build] [--keep]
#
# Families: classic modern metal wal wmz audion sonique (default: all).
# Scenarios:
#   0  registry: which registered com.nullplayer.app copy LaunchServices launches (nothing is launched)
#   1  cold open, Remember State on, a different session saved
#   2  cold open, -rememberStateEnabled NO
#   3  warm open while playing: 3a another app frontmost, 3b main window closed
#   4  warm multi-file open (mp3 flac m4a): all queued, the first playing
#   5  type matrix (m4a flac ogg opus wav cue m3u pls): accepted, and a declared document type
#   6  video (mp4 mov mkv): cold, warm, mixed with an mp3, and a declared document type
#   7  cold into Compact Mode, then Compact Window
# Default: classic 0-7; modern and metal 1 3 6 7; wal wmz audion sonique 1 3 6. An explicit
# --scenario applies to every selected family (0 runs once).
#
# Prints `PASS|FAIL <family> <row>: <evidence>` per row and `FINDER-OPEN MATRIX PASS|FAIL (p/n)`;
# exits 1 on any FAIL. A row's PASS is the behaviour a Mac user expects from a default app, so
# rows that record a known gap FAIL until it is fixed. Rows go to <out>/rows.tsv, window captures to
# <out>/shots/, each cold launch's NSLog output to <out>/logs/ (the unified log redacts it).
#
# The bundle's CFBundleIdentifier is `NullPlayer`, the debug build's own defaults domain, so the
# user's com.nullplayer.app preferences are never read or written. That domain is saved first and
# put back before every cold launch and on exit. The bundle is registered with LaunchServices only
# while the matrix runs (a trap unregisters and deletes it). Launching quits any running debug
# NullPlayer; the installed app is never launched or killed.
set -o pipefail
cd "$(dirname "$0")/../../.."
REPO=$PWD
SCRIPTS=$REPO/skills/app-control/scripts
WH=$SCRIPTS/winhelper
LSR=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
D=NullPlayer

FAMILIES="classic modern metal wal wmz audion sonique"
SCEN=""; OUT=""; BUILD=1; KEEP=0
while [ $# -gt 0 ]; do
  case "$1" in
    --family)   FAMILIES=$(echo "$2" | tr ',' ' '); shift 2 ;;
    --scenario) SCEN=$(echo "$2" | tr ',' ' '); shift 2 ;;
    --out)      OUT="$2"; shift 2 ;;
    --no-build) BUILD=0; shift ;;
    --keep)     KEEP=1; shift ;;
    *) echo "finder-open-matrix: unknown option $1" >&2; exit 2 ;;
  esac
done
OUT=${OUT:-/tmp/np-finder-open/$(date +%Y%m%d-%H%M%S)}
mkdir -p "$OUT/shots" "$OUT/media" "$OUT/logs"
OUT=$(cd "$OUT" && pwd -P)            # LaunchServices and pgrep see /private/tmp, not /tmp
APP=$OUT/NullPlayer.app
APP_EXE=$APP/Contents/MacOS/NullPlayer
LOG=/dev/null; LAUNCHES=0     # each cold launch's stderr (the app's NSLog) goes to its own <out>/logs file
M=$OUT/media
: > "$OUT/rows.tsv"
NPASS=0; NFAIL=0

# --- helpers ---------------------------------------------------------------------------------
wait_until() {   # wait_until <seconds> <command string>: polls every 0.25 s
  local n=$(( $1 * 4 )); shift
  while [ $n -gt 0 ]; do eval "$1" && return 0; sleep 0.25; n=$((n - 1)); done
  return 1
}
pid_of()     { pgrep -f "^$APP_EXE( |\$)" | head -1; }
# System Events' `first process whose frontmost is true` errors on macOS 27; LaunchServices answers.
front_pid()  { lsappinfo info -only pid "$(lsappinfo front)" | sed -n 's/.*pid = \([0-9]*\).*/\1/p'; }
win_count()  { "$WH" windows --pid "$PID" 2>/dev/null | awk -F'\t' '$2==0{n++} END{print n+0}'; }
log_mark()   { MARK=$(wc -l < "$LOG" | tr -d ' '); }
since_mark() { tail -n +"$((MARK + 1))" "$LOG"; }
logged()     { since_mark | grep -qF "$1"; }
snap()       { SNAP=$("$SCRIPTS/playback-snapshot.sh" "$PID" 2>/dev/null | grep '^engine state=' | sed 's/ time=.*//'); }
playing()    {   # playing <title or ''> <count>: the snapshot shows that title playing in a queue of that size
  snap
  case "$SNAP" in *"state=playing track='$1"*"/$2") return 0 ;; esac
  return 1
}
kill_app() {
  local p; p=$(pid_of)
  [ -n "$p" ] && kill -9 "$p" 2>/dev/null
  pkill -9 -f '\.build/.*/debug/NullPlayer' 2>/dev/null    # another debug instance would share the domain
  wait_until 10 '[ -z "$(pid_of)" ]'
  PID=""
}
quit_app() {     # a real quit, so Remember State saves the session
  [ -n "$PID" ] || return 0
  osascript -e 'with timeout of 15 seconds' -e "tell application \"$APP\" to quit" -e 'end timeout' >/dev/null 2>&1
  wait_until 20 '! kill -0 '"$PID"' 2>/dev/null' || kill -9 "$PID"
  PID=""
}
restore_defaults() { defaults delete $D 2>/dev/null; defaults import $D "$OUT/defaults-baseline.plist"; }
other_app_front() {
  osascript -e 'tell application "Finder" to activate' >/dev/null 2>&1
  wait_until 5 '[ "$(front_pid)" != "$PID" ]'
}
shot() { "$WH" capture-all "$OUT/shots/$FAM-$1" --pid "$PID" >/dev/null 2>&1; }
state() {        # the evidence every row carries, read now
  [ -n "$PID" ] || { echo "no process"; return; }
  local f="no"; [ "$(front_pid)" = "$PID" ] && f="yes"
  snap; echo "${SNAP:-no snapshot} front=$f windows=$(win_count)"
}
row() {          # row PASS|FAIL <name> <evidence…>
  local res=$1 name=$2; shift 2
  echo "$res $FAM $name: $*"
  printf '%s\t%s\t%s\t%s\n' "$res" "$FAM" "$name" "$*" >> "$OUT/rows.tsv"
  if [ "$res" = PASS ]; then NPASS=$((NPASS + 1)); else NFAIL=$((NFAIL + 1)); fi
}
judge() { if eval "$2"; then row PASS "$1" "$3"; else row FAIL "$1" "$3"; fi; }

# Is the file's type one the bundle declares (CFBundleDocumentTypes), and who opens it by default?
# Computed from the bundle's own Info.plist, not LaunchServices' Open With list, which leaves out a
# bundle in a temp directory. Nothing is launched.
declared() {     # declared <file>: "declared=yes|no uti=<uti> default=<app>"
  osascript -l JavaScript - "$1" "$APP" <<'EOF' 2>/dev/null
ObjC.import('AppKit')
function run(argv) {
  const ws = $.NSWorkspace.sharedWorkspace, path = argv[0], ext = path.split('.').pop().toLowerCase()
  const uti = ObjC.unwrap(ws.typeOfFileError(path, null))
  const info = ObjC.deepUnwrap($.NSDictionary.dictionaryWithContentsOfFile(argv[1] + '/Contents/Info.plist'))
  const ok = (info.CFBundleDocumentTypes || []).some(d =>
    (d.LSItemContentTypes || []).some(t => ws.typeConformsToType(uti, t)) ||
    (d.CFBundleTypeExtensions || []).map(e => e.toLowerCase()).includes(ext))
  const def = ws.URLForApplicationToOpenURL($.NSURL.fileURLWithPath(path))
  return 'declared=' + (ok ? 'yes' : 'no') + ' uti=' + uti +
         ' default=' + (def.isNil() ? 'none' : def.path.js.split('/').pop())
}
EOF
}

# --- families --------------------------------------------------------------------------------
SUPPORT="$HOME/Library/Application Support/NullPlayer"
family_setup() { # sets UIMODE, FAM_ENV, FAM_ARGS; writes what launch.sh writes, after restore_defaults
  FAM_ENV=(); FAM_ARGS=()
  case "$FAM" in
    classic) UIMODE=classic; SKINFILE="$SUPPORT/Skins/aquamp.wsz"
             defaults delete $D lastClassicSkinPath 2>/dev/null; FAM_ENV=(NULLPLAYER_SKIN="$SKINFILE") ;;
    modern)  UIMODE=modern; defaults write $D modernSkinName -string NeonWave ;;
    metal)   UIMODE=metal;  defaults write $D metalSkinName -string "Brushed Steel" ;;
    wal)     UIMODE=winampModern; SKINFILE="$SUPPORT/WinampModernCorpus/gold/2222-cPro__Bento.wal"
             FAM_ARGS=(-winampModernSkinPath "$SKINFILE") ;;
    wmz)     UIMODE=wmp; defaults write $D wmpSkinName -string corona; defaults delete $D wmpSkinViewID 2>/dev/null ;;
    audion)  UIMODE=audion; FAM_ARGS=(-audionFacePath "$SUPPORT/AudionFaces/Black Bar") ;;
    sonique) UIMODE=sonique; defaults write $D soniqueSkinName -string BlueEyes ;;
    *) echo "finder-open-matrix: unknown family $FAM" >&2; exit 2 ;;
  esac
}
family_confirmed() { # the skin-loaded evidence launch.sh's PASS table names
  case "$FAM" in
    classic) [ "$(defaults read $D lastClassicSkinPath 2>/dev/null)" = "$SKINFILE" ] ;;
    modern)  since_mark | grep -F "ModernSkinLoader: Loaded skin '" | grep -qF "/NeonWave" ;;
    metal)   logged "Loaded built-in metal skin 'Brushed Steel'" ;;
    wal)     logged "WinampModern surfaces [2222-cPro__Bento.wal]" ;;
    wmz)     [ "$(defaults read $D wmpSkinName 2>/dev/null)" = corona ] && defaults read $D wmpSkinViewID >/dev/null 2>&1 ;;
    audion)  logged "AudionFace: loaded 'Black Bar'" ;;
    sonique) logged "SoniqueSkin: loaded 'BlueEyes.sgf'" ;;
  esac
}
default_scenarios() {
  case "$FAM" in
    classic) echo 1 2 3 4 5 6 7 ;;
    modern|metal) echo 1 3 6 7 ;;
    *) echo 1 3 6 ;;
  esac
}

# cold [restore]: quit, optionally put the baseline defaults back, then a cold `open -a` with
# FILES, XENV and XARGS. Sets PID, OPEN_RC and MARK (the log line count before the open).
cold() {
  kill_app
  [ "${1:-1}" = 1 ] && restore_defaults
  family_setup
  local cmd=(open -a "$APP") e
  for e in ${FAM_ENV[@]+"${FAM_ENV[@]}"} ${XENV[@]+"${XENV[@]}"}; do cmd+=(--env "$e"); done
  LAUNCHES=$((LAUNCHES + 1)); LOG=$OUT/logs/$LAUNCHES-$FAM-$ROW.log
  cmd+=(--stderr "$LOG" ${FILES[@]+"${FILES[@]}"} --args -uiMode "$UIMODE" ${FAM_ARGS[@]+"${FAM_ARGS[@]}"} ${XARGS[@]+"${XARGS[@]}"})
  : > "$LOG"; MARK=0
  "${cmd[@]}" 2>"$OUT/open.err"; OPEN_RC=$?
  wait_until 15 'PID=$(pid_of); [ -n "$PID" ]' || { PID=""; return 1; }
  taskpolicy -B -p "$PID" 2>/dev/null
  wait_until 30 family_confirmed || return 2
}
cold_or_skip() { # cold, or a FAIL row saying the launch itself failed
  cold "$@"; local rc=$?
  [ $rc = 0 ] && return 0
  row FAIL "$ROW" "launch failed ($([ $rc = 1 ] && echo 'no process' || echo 'skin not confirmed')) open_rc=$OPEN_RC $(head -c 200 "$OUT/open.err")"
  return 1
}
warm_open() {    # warm_open <files…>: an `open -a` to the running app
  log_mark
  open -a "$APP" "$@" 2>"$OUT/open.err"; OPEN_RC=$?
}
ensure_warm() {  # a running session playing fo-a, fo-b, fo-e
  [ -n "$PID" ] && kill -0 "$PID" 2>/dev/null && return 0
  FILES=(); XENV=(NULLPLAYER_PLAY="$M/fo-a.mp3:$M/fo-b.mp3:$M/fo-e.mp3"); XARGS=(-rememberStateEnabled NO)
  cold_or_skip || return 1
  wait_until 20 'playing fo-a 3' || { row FAIL "$ROW" "warm session never played: $(state)"; return 1; }
}

# --- scenarios -------------------------------------------------------------------------------
scenario_0() {
  ROW=0-registry
  local r
  r=$(osascript -l JavaScript <<'EOF' 2>/dev/null
ObjC.import('AppKit')
const ws = $.NSWorkspace.sharedWorkspace
const all = ws.URLsForApplicationsWithBundleIdentifier('com.nullplayer.app').js.map(u => u.path.js)
const launch = ws.URLForApplicationWithBundleIdentifier('com.nullplayer.app')
const ver = p => { const b = $.NSBundle.bundleWithPath(p); return b.isNil() ? '?' : ObjC.unwrap(b.objectForInfoDictionaryKey('CFBundleShortVersionString')) }
`count=${all.length} launches=${launch.isNil() ? 'none' : launch.path.js} (${launch.isNil() ? '' : ver(launch.path.js)}) all=` +
  all.map(p => p + ' (' + ver(p) + ')').join('; ')
EOF
)
  judge "$ROW" 'case "$r" in count=1\ *) true ;; *) false ;; esac' "$r"
}

scenario_1() {
  ROW=1-cold-restore
  FILES=(); XENV=(NULLPLAYER_PLAY="$M/fo-b.mp3"); XARGS=(-rememberStateEnabled YES)
  cold_or_skip || return
  wait_until 20 'playing fo-b 1' || { row FAIL $ROW "seed session never played: $(state)"; return; }
  quit_app
  logged "Saved state - playlist: 1 tracks" || { row FAIL $ROW "seed session was not saved"; return; }
  FILES=("$M/fo-a.mp3"); XENV=(); XARGS=(-rememberStateEnabled YES)
  cold_or_skip 0 || return
  # The settings restore runs asynchronously after launch; judge only once it has applied.
  wait_until 15 'logged "AppStateManager: Restoring settings state"'; local restored=$?
  wait_until 15 'playing fo-a 1'; local ok=$?
  judge $ROW '[ $ok = 0 ] && [ "$(front_pid)" = "$PID" ] && [ "$(win_count)" -gt 0 ]' \
    "$(state) settingsRestored=$([ $restored = 0 ] && echo yes || echo no)"
  shot $ROW
}

scenario_2() {
  ROW=2-cold-norestore
  FILES=("$M/fo-a.mp3"); XENV=(); XARGS=(-rememberStateEnabled NO)
  cold_or_skip || return
  wait_until 20 'playing fo-a 1'; local ok=$?
  judge $ROW '[ $ok = 0 ] && [ "$(front_pid)" = "$PID" ] && [ "$(win_count)" -gt 0 ]' "$(state)"
  shot $ROW
}

scenario_3() {
  ROW=3a-warm-replace
  kill_app; ensure_warm || return
  other_app_front
  warm_open "$M/fo-c.mp3"
  wait_until 15 'playing fo-c 1'; local ok=$?
  judge $ROW '[ $ok = 0 ] && [ "$(front_pid)" = "$PID" ] && [ "$(win_count)" -gt 0 ]' "$(state)"
  shot $ROW

  ROW=3b-warm-main-closed
  osascript -e "tell application \"System Events\" to tell (first process whose unix id is $PID) to perform action \"AXPress\" of menu item \"Main Window\" of menu \"Windows\" of menu bar item \"Windows\" of menu bar 1" >/dev/null 2>&1
  if ! wait_until 5 '[ "$(win_count)" = 0 ]'; then
    row FAIL $ROW "setup: Windows > Main Window did not leave zero windows ($(win_count) on screen)"; return
  fi
  other_app_front
  warm_open "$M/fo-d.mp3"
  wait_until 15 'playing fo-d 1'; ok=$?
  judge $ROW '[ $ok = 0 ] && [ "$(front_pid)" = "$PID" ] && wait_until 5 "[ \$(win_count) -gt 0 ]"' "$(state)"
  shot $ROW
}

scenario_4() {
  ROW=4-warm-multi
  ensure_warm || return
  warm_open "$M/fo-e.mp3" "$M/fo-flac.flac" "$M/fo-m4a.m4a"
  wait_until 15 'playing fo-e 3'; local ok=$?
  judge $ROW '[ $ok = 0 ] && case "$SNAP" in *index=0/3) true ;; *) false ;; esac' \
    "$(state) $(since_mark | grep -o 'loadTracks: [0-9]* tracks' | head -1)"
}

scenario_5() {
  ensure_warm || return
  local spec ext file title count lw
  # ext file title count — each expectation differs from the state the row before leaves.
  for spec in "m4a fo-m4a.m4a fo-m4a 1" "flac fo-flac.flac fo-flac 1" "ogg fo-ogg.ogg fo-ogg 1" \
              "opus fo-opus.opus fo-opus 1" "wav fo-wav.wav fo-wav 1" "m3u fo-m3u.m3u fo-a 2" \
              "cue cue/album.cue '' 3" "pls fo-pls.pls fo-c 1"; do
    set -- $spec; ext=$1; file=$M/$2; title=$3; count=$4
    [ "$title" = "''" ] && title=""
    ROW=5-type-$ext
    lw=$(declared "$file")
    warm_open "$file"
    local acc=no; wait_until 8 "playing '$title' $count" && acc=yes
    judge $ROW '[ $acc = yes ] && case "$lw" in declared=yes*) true ;; *) false ;; esac' \
      "accepted=$acc $lw open_rc=$OPEN_RC $(state)"
  done
}

scenario_6() {
  local ext lw
  ROW=6-video-cold-mp4
  FILES=("$M/fo-mp4.mp4"); XENV=(); XARGS=(-rememberStateEnabled NO)
  if cold_or_skip; then
    lw=$(declared "$M/fo-mp4.mp4")
    local v=no; wait_until 10 'logged "VideoPlayerView: Playing"' && v=yes
    judge $ROW '[ $v = yes ] && case "$lw" in declared=yes*) true ;; *) false ;; esac' "video=$v $lw $(state)"
    shot $ROW
  fi
  kill_app; ensure_warm || return
  for ext in mp4 mov mkv; do
    ROW=6-video-warm-$ext
    lw=$(declared "$M/fo-$ext.$ext")
    local before; before=$(win_count)
    warm_open "$M/fo-$ext.$ext"
    local v=no; wait_until 10 'logged "VideoPlayerView: Playing"' && v=yes
    judge $ROW '[ $v = yes ] && case "$lw" in declared=yes*) true ;; *) false ;; esac' \
      "video=$v $lw windows_before=$before $(state)"
    [ $v = yes ] && shot $ROW
  done
  ROW=6-video-mixed
  warm_open "$M/fo-c.mp3" "$M/fo-mp4.mp4"
  wait_until 15 'playing fo-c 2'; local ok=$?
  judge $ROW '[ $ok = 0 ]' "$(state) $(since_mark | grep -o 'loadTracks: [0-9]* tracks' | head -1)"
}

scenario_7() {
  ROW=7-compact-mode
  FILES=("$M/fo-a.mp3"); XENV=(); XARGS=(-rememberStateEnabled NO -compactModeEnabled YES)
  if cold_or_skip; then
    wait_until 20 'playing fo-a 1'; local ok=$?
    judge $ROW '[ $ok = 0 ]' "$(state)"   # Compact Mode is menu-bar only by design: playing is the test
  fi
  ROW=7-compact-window
  FILES=("$M/fo-a.mp3"); XENV=(); XARGS=(-rememberStateEnabled NO -compactWindowEnabled YES)
  if cold_or_skip; then
    wait_until 20 'playing fo-a 1'; ok=$?
    judge $ROW '[ $ok = 0 ] && wait_until 5 "[ \$(win_count) -gt 0 ]"' "$(state)"
    shot $ROW
  fi
}

# --- setup -----------------------------------------------------------------------------------
USER_PREFS_BEFORE=$(defaults read com.nullplayer.app uiMode 2>/dev/null)/$(defaults read com.nullplayer.app rememberStateEnabled 2>/dev/null)
defaults export $D "$OUT/defaults-baseline.plist" || { echo "finder-open-matrix: cannot save the $D domain" >&2; exit 2; }
cleanup() {
  kill_app
  restore_defaults
  if [ -d "$APP" ]; then
    "$LSR" -u "$APP" 2>/dev/null
    [ $KEEP = 1 ] || rm -rf "$APP"
  fi
  local after
  after=$(defaults read com.nullplayer.app uiMode 2>/dev/null)/$(defaults read com.nullplayer.app rememberStateEnabled 2>/dev/null)
  [ "$after" = "$USER_PREFS_BEFORE" ] || echo "WARNING: com.nullplayer.app uiMode/rememberStateEnabled changed: $USER_PREFS_BEFORE -> $after"
}
trap cleanup EXIT
trap 'exit 130' INT TERM

source scripts/lib/swiftpm.sh
if [ $BUILD = 1 ]; then
  pgrep -f 'swift-build' >/dev/null && { echo "finder-open-matrix: another swift build is running" >&2; exit 2; }
  swift build ${SWIFTPM_ARGS[@]+"${SWIFTPM_ARGS[@]}"} >"$OUT/build.log" 2>&1 \
    || { echo "FINDER-OPEN MATRIX FAIL: build failed — $OUT/build.log"; exit 1; }
fi
(
  REPO_ROOT=$REPO; BUILD_DIR=$(swiftpm_bin_path debug 2>/dev/null); SKIP_BUILD=true
  log_info() { :; }; log_success() { :; }; log_warning() { echo "assemble: $*" >&2; }; log_error() { echo "assemble: $*" >&2; }
  source scripts/lib/assemble_app.sh
  assemble_app "$APP"
  /usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $D" "$APP/Contents/Info.plist"
  sign_app_bundle "$APP" --sign -
) >"$OUT/assemble.log" 2>&1 || { echo "FINDER-OPEN MATRIX FAIL: bundle assembly failed — $OUT/assemble.log"; exit 1; }
"$LSR" -f "$APP"

# Test media, titled after their file names so the snapshot's track names them.
T=$REPO/tmp/testdata
scripts/testdata.sh ensure >/dev/null
ff() { ffmpeg -nostdin -loglevel error -y "$@"; }
for pair in "a 01-hackbeat" "b 02-volatile-reaction" "c 03-funkorama" "d 05-pixelland" "e 04-local-forecast-elevator"; do
  set -- $pair; ff -i "$T/music/$2.mp3" -map 0:a -c copy -metadata title="fo-$1" "$M/fo-$1.mp3"
done
# Long enough that no clip ends while a later row is still being judged.
S6="$T/music/06-sneaky-snitch.mp3"
ff -i "$S6" -map 0:a -c:a aac -metadata title=fo-m4a "$M/fo-m4a.m4a"
ff -i "$S6" -map 0:a -c:a flac -metadata title=fo-flac "$M/fo-flac.flac"
ff -i "$S6" -map 0:a -ac 2 -c:a vorbis -strict -2 -metadata title=fo-ogg "$M/fo-ogg.ogg"
ff -i "$S6" -map 0:a -c:a libopus -metadata title=fo-opus "$M/fo-opus.opus"
ff -i "$S6" -map 0:a -c:a pcm_s16le -metadata title=fo-wav "$M/fo-wav.wav"
ff -i "$T/video-short.mp4" -c copy "$M/fo-mp4.mp4"
ff -i "$T/video-short.mp4" -c copy "$M/fo-mov.mov"
ff -i "$T/video-short.mp4" -c copy "$M/fo-mkv.mkv"
rm -rf "$M/cue"; cp -R "$T/cue" "$M/cue"
printf '#EXTM3U\n%s\n%s\n' "$M/fo-a.mp3" "$M/fo-b.mp3" > "$M/fo-m3u.m3u"
printf '[playlist]\nFile1=%s\nNumberOfEntries=1\nVersion=2\n' "$M/fo-c.mp3" > "$M/fo-pls.pls"
[ -f "$M/cue/album.cue" ] || { echo "FINDER-OPEN MATRIX FAIL: no album.cue in $T/cue"; exit 1; }


# --- run -------------------------------------------------------------------------------------
RAN0=0
for FAM in $FAMILIES; do
  PID=""
  for s in ${SCEN:-$(default_scenarios)}; do
    if [ "$s" = 0 ]; then
      [ $RAN0 = 1 ] && continue
      RAN0=1; F0=$FAM; FAM=all; scenario_0; FAM=$F0; continue
    fi
    "scenario_$s"
  done
  kill_app
done
NPASS=$(grep -c '^PASS' "$OUT/rows.tsv"); NFAIL=$(grep -c '^FAIL' "$OUT/rows.tsv")
TOTAL=$((NPASS + NFAIL))
if [ "$NFAIL" = 0 ]; then echo "FINDER-OPEN MATRIX PASS ($NPASS/$TOTAL)  out $OUT"; exit 0; fi
echo "FINDER-OPEN MATRIX FAIL ($NPASS/$TOTAL)  out $OUT"; exit 1
