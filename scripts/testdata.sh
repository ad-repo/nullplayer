#!/bin/bash
# Deterministic local test media for driving and measuring the running app.
#
#   testdata.sh ensure            generate anything missing (idempotent)
#   testdata.sh path <name>       absolute path to one target, or exit 1
#   testdata.sh list              the manifest
#   testdata.sh servers           what the configured media servers hold
#
# Everything is synthesized into tmp/testdata/ (gitignored), so nothing large is
# committed and every agent gets byte-identical inputs.
#
# Rule zero: the app under test is the local debug build. `servers` shells out to
# .build/<arch>-apple-macosx/debug/NullPlayer by path and never to the `nullplayer`
# shim, which execs the installed /Applications build.
#
# Route validity per target is in skills/app-control/reference/test-data.md.
set -eu

cd "$(dirname "$0")/.."
ROOT="$(pwd)"
DIR="$ROOT/tmp/testdata"

FFMPEG="${FFMPEG:-/opt/homebrew/bin/ffmpeg}"
[ -x "$FFMPEG" ] || FFMPEG="$(command -v ffmpeg 2>/dev/null || true)"

# name <TAB> relative path <TAB> description
manifest() {
  cat <<'ROWS'
audio-short	audio-short.m4a	5 s 440 Hz tone, AAC — fast start/stop only
music	music	6 real tracks, ~20 min, MP3 (Kevin MacLeod, CC BY 4.0) — the default: spectrum, seek, next/prev, any timed session
audio-lossless	audio-lossless.flac	30 s sweep, FLAC — the lossless path; host for the cue row
audio-gapless	gapless/01-gapless.flac	first of two 10 s tracks that meet at a phase boundary
audio-gapless-2	gapless/02-gapless.flac	second of the gapless pair
audio-tagged	audio-tagged.mp3	60 s tone with title/artist/album/track/year and embedded cover art
audio-untagged	audio-untagged.mp3	the same audio with no tags and no art — fallback rendering
video-short	video-short.mp4	10 s H.264 + AAC, 640x360 — video window and cast targets
playlist-m3u	playlist.m3u8	extended M3U over the audio rows, absolute paths
cue-flac	cue/album.flac	7 min FLAC with a 3-index album.cue beside it
cue-sheet	cue/album.cue	the cue sheet for the row above
library-dir	library	a folder of tagged tracks for a local-library scan
ROWS
}

die() { echo "testdata.sh: $*" >&2; exit 1; }

have_ffmpeg() { [ -n "$FFMPEG" ] && [ -x "$FFMPEG" ]; }

require_ffmpeg() {
  have_ffmpeg && return 0
  die "this target needs ffmpeg (tags, cover art, MP3 or video). Install it:  brew install ffmpeg"
}

# Encode beside the destination, preserving its extension for format detection.
# Failed/interrupted encodes never become fixtures that ensure would later skip.
ENCODE_TMP=""
cleanup_encode() { [ -z "$ENCODE_TMP" ] || rm -f "$ENCODE_TMP"; }
trap cleanup_encode EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
ff() {
  local output="${!#}"
  local args=("$@")
  ENCODE_TMP="${output%.*}.partial.$$.${output##*.}"
  args[${#args[@]}-1]="$ENCODE_TMP"
  "$FFMPEG" -y -loglevel error "${args[@]}" || die "encoding failed for $output"
  [ -s "$ENCODE_TMP" ] || die "encoder produced no data for $output"
  mv -f "$ENCODE_TMP" "$output" || die "cannot publish $output"
  ENCODE_TMP=""
}

# --- afconvert fallback, for the plain audio rows only ------------------------------
# afconvert cannot synthesize, so the waveform comes from python3's stdlib `wave` and
# afconvert encodes it. This covers audio-short, audio-lossless and the gapless pair on
# a machine with no ffmpeg; every other row needs ffmpeg and says so.
tone_wav() { # $1 out.wav  $2 seconds  $3 hz
  python3 - "$1" "$2" "$3" <<'PYW'
import math, struct, sys, wave
out, secs, hz = sys.argv[1], float(sys.argv[2]), float(sys.argv[3])
rate = 44100
with wave.open(out, "wb") as w:
    w.setnchannels(1); w.setsampwidth(2); w.setframerate(rate)
    w.writeframes(b"".join(
        struct.pack("<h", int(20000 * math.sin(2 * math.pi * hz * n / rate)))
        for n in range(int(rate * secs))))
PYW
}

# $1 out  $2 seconds  $3 hz  $4 afconvert format (m4af|flac)  $5 afconvert data format
plain_audio() {
  if have_ffmpeg; then return 1; fi          # caller uses its own ffmpeg recipe
  command -v afconvert >/dev/null 2>&1 || \
    die "neither ffmpeg nor afconvert is available. Install ffmpeg:  brew install ffmpeg"
  tmp="$DIR/.tone.wav"
  tone_wav "$tmp" "$2" "$3"
  ENCODE_TMP="${1%.*}.partial.$$.${1##*.}"
  afconvert -f "$4" -d "$5" "$tmp" "$ENCODE_TMP" >/dev/null || die "afconvert failed for $1"
  [ -s "$ENCODE_TMP" ] || die "afconvert produced no data for $1"
  mv -f "$ENCODE_TMP" "$1" || die "cannot publish $1"
  ENCODE_TMP=""
  rm -f "$tmp"
  return 0
}

# file <TAB> sha256 <TAB> url. Kevin MacLeod (incompetech.com), CC BY 4.0. Varied on purpose:
# beats, rock, funk, jazz, chiptune (bright treble), and a short one for end-of-track.
music_rows() {
  local base=https://incompetech.com/music/royalty-free/mp3-royaltyfree
  cat <<ROWS
01-hackbeat.mp3	be06327a3578250c84c189ad89c9e6c2f8b326bf342a701775824e9cbedfea64	$base/Hackbeat.mp3
02-volatile-reaction.mp3	ced1148df201a6c69062a96b7ef49c49924572ca5023c2ac5a2d6c5828ecb218	$base/Volatile%20Reaction.mp3
03-funkorama.mp3	6be229815d85a0b99382b944d31098b882702c04ac7ad899e44ab7f8ba89b5ad	$base/Funkorama.mp3
04-local-forecast-elevator.mp3	8c46b44e65324bc339fbbc3e770611d671f6c74a40f3ec8dd50332c082b25cc9	$base/Local%20Forecast%20-%20Elevator.mp3
05-pixelland.mp3	889fd6f06fd077689d512d4169a0efc4a61b717af73ac64ecca361eb5a4c4b7d	$base/Pixelland.mp3
06-sneaky-snitch.mp3	db1710333d68a215277f77e4e17e1a64bf4ed38f87c70f8d0f56b16b6aa4f884	$base/Sneaky%20Snitch.mp3
ROWS
}

# A tone/sweep source. $1 duration, $2 the lavfi expression.
gen_ensure() {
  mkdir -p "$DIR" "$DIR/gapless" "$DIR/cue" "$DIR/library"

  if [ ! -s "$DIR/audio-short.m4a" ]; then
    plain_audio "$DIR/audio-short.m4a" 5 440 m4af aac ||
      ff -f lavfi -i "sine=frequency=440:duration=5" -c:a aac -b:a 128k "$DIR/audio-short.m4a"
    echo "made audio-short.m4a"
  fi

  # Real music, because a sine sweep is one steady bar: a spectrum, a VU or a peak cap
  # cannot be judged on it. Several tracks, so next/previous and end-of-track are exercised
  # too. Downloaded rather than synthesized, and pinned by sha256 so every agent gets the
  # same bytes.
  mkdir -p "$DIR/music"
  while IFS=$'\t' read -r file sha url; do
    out="$DIR/music/$file"
    [ -s "$out" ] && continue
    ENCODE_TMP="$out.partial.$$"
    curl -sfL -o "$ENCODE_TMP" "$url" || die "cannot download $url (offline?)"
    [ "$(shasum -a 256 "$ENCODE_TMP" | cut -c1-64)" = "$sha" ] || die "checksum mismatch for $url"
    mv -f "$ENCODE_TMP" "$out"; ENCODE_TMP=""
    echo "made music/$file"
  done < <(music_rows)

  if [ ! -s "$DIR/audio-lossless.flac" ]; then
    plain_audio "$DIR/audio-lossless.flac" 30 440 flac flac ||
      ff -f lavfi -i "sine=frequency=440:duration=30" -c:a flac "$DIR/audio-lossless.flac"
    echo "made audio-lossless.flac"
  fi

  # The pair meets at a zero crossing of the same continuous tone: a gap is audible
  # as a click, and a gapless transition is not.
  for i in 1 2; do
    output="$DIR/gapless/0$i-gapless.flac"
    if [ ! -s "$output" ]; then
      if ! have_ffmpeg; then
        plain_audio "$output" 10 440 flac flac
      else
        ff -f lavfi -i "sine=frequency=440:duration=10" -c:a flac \
           -metadata title="Gapless $i" -metadata album="Gapless Test" -metadata track="$i" \
           "$output"
      fi
      echo "made gapless/0$i-gapless.flac"
    fi
  done

  if [ ! -s "$DIR/cover.png" ]; then
    require_ffmpeg
    ff -f lavfi -i "testsrc=size=600x600:duration=1:rate=1" -frames:v 1 "$DIR/cover.png"
  fi

  if [ ! -s "$DIR/audio-tagged.mp3" ]; then
    require_ffmpeg
    ff -f lavfi -i "sine=frequency=330:duration=60" -i "$DIR/cover.png" \
       -map 0:a -map 1:v -c:a libmp3lame -b:a 192k -c:v copy -id3v2_version 3 \
       -metadata:s:v title="Album cover" -metadata:s:v comment="Cover (front)" \
       -metadata title="Tagged Test Track" -metadata artist="NullPlayer Testdata" \
       -metadata album="Testdata Vol. 1" -metadata track="3/9" -metadata date="2026" \
       -metadata genre="Electronic" \
       "$DIR/audio-tagged.mp3"
    echo "made audio-tagged.mp3"
  fi

  if [ ! -s "$DIR/audio-untagged.mp3" ]; then
    require_ffmpeg
    ff -f lavfi -i "sine=frequency=330:duration=60" -c:a libmp3lame -b:a 192k \
       -map_metadata -1 -write_xing 0 "$DIR/audio-untagged.mp3"
    echo "made audio-untagged.mp3"
  fi

  if [ ! -s "$DIR/video-short.mp4" ]; then
    require_ffmpeg
    ff -f lavfi -i "testsrc=size=640x360:duration=10:rate=30" \
       -f lavfi -i "sine=frequency=440:duration=10" \
       -c:v libx264 -pix_fmt yuv420p -c:a aac -b:a 128k -shortest "$DIR/video-short.mp4"
    echo "made video-short.mp4"
  fi

  # A 7-minute FLAC cut into three indexed tracks by album.cue.
  if [ ! -s "$DIR/cue/album.flac" ]; then
    require_ffmpeg
    ff -f lavfi -i "sine=frequency=220:duration=420" -c:a flac "$DIR/cue/album.flac"
    echo "made cue/album.flac"
  fi
  if [ ! -s "$DIR/cue/album.cue" ]; then
    cat > "$DIR/cue/album.cue" <<'CUE'
PERFORMER "NullPlayer Testdata"
TITLE "Cue Test Album"
FILE "album.flac" WAVE
  TRACK 01 AUDIO
    TITLE "First Index"
    PERFORMER "NullPlayer Testdata"
    INDEX 01 00:00:00
  TRACK 02 AUDIO
    TITLE "Second Index"
    PERFORMER "NullPlayer Testdata"
    INDEX 01 02:20:00
  TRACK 03 AUDIO
    TITLE "Third Index"
    PERFORMER "NullPlayer Testdata"
    INDEX 01 04:40:00
CUE
    echo "made cue/album.cue"
  fi

  # A scannable folder: distinct artist/album/track tags, so a scan produces rows a
  # browser can sort rather than one undifferentiated blob.
  i=1
  for spec in "first:Alpha Artist:Alpha Album:220" \
              "second:Alpha Artist:Alpha Album:280" \
              "third:Beta Artist:Beta Album:340"; do
    IFS=: read -r slug artist album freq <<<"$spec"
    if [ ! -s "$DIR/library/0$i-$slug.mp3" ]; then
      require_ffmpeg
      ff -f lavfi -i "sine=frequency=$freq:duration=20" -c:a libmp3lame -b:a 160k \
       -metadata title="$(echo "$slug" | tr '[:lower:]' '[:upper:]')" \
       -metadata artist="$artist" -metadata album="$album" -metadata track="$i" \
       -metadata date="2026" "$DIR/library/0$i-$slug.mp3"
      echo "made library/0$i-$slug.mp3"
    fi
    i=$((i + 1))
  done

  # Written last: it holds absolute paths, so it is only correct once the rows exist.
  {
    echo "#EXTM3U"
    echo "#EXTINF:5,testdata.sh - audio-short"
    echo "$DIR/audio-short.m4a"
    echo "#EXTINF:60,NullPlayer Testdata - Tagged Test Track"
    echo "$DIR/audio-tagged.mp3"
    echo "#EXTINF:30,testdata.sh - audio-lossless"
    echo "$DIR/audio-lossless.flac"
    for f in "$DIR"/music/*.mp3; do
      echo "#EXTINF:-1,Kevin MacLeod - $(basename "$f" .mp3)"
      echo "$f"
    done
  } > "$DIR/playlist.m3u8"
}

cmd_path() {
  [ $# -eq 1 ] || die "usage: testdata.sh path <name>   (see: testdata.sh list)"
  rel=$(manifest | awk -F'\t' -v n="$1" '$1 == n { print $2 }')
  [ -n "$rel" ] || die "unknown target '$1'. Known targets:$(manifest | awk -F'\t' '{printf " %s", $1}')"
  [ -e "$DIR/$rel" ] || die "'$1' has not been generated yet — run: scripts/testdata.sh ensure"
  echo "$DIR/$rel"
}

cmd_list() {
  printf '%-16s %-12s %s\n' NAME STATE DESCRIPTION
  manifest | while IFS=$'\t' read -r name rel desc; do
    [ -e "$DIR/$rel" ] && state=present || state=missing
    printf '%-16s %-12s %s\n' "$name" "$state" "$desc"
  done
  echo
  echo "Root: $DIR"
  echo "Network targets (not synthesizable) and per-row route validity:"
  echo "  skills/app-control/reference/test-data.md"
}

cmd_servers() {
  arch=$(uname -m)
  case "$arch" in
    x86_64) bin="$ROOT/.build/x86_64-apple-macosx/debug/NullPlayer" ;;
    *)      bin="$ROOT/.build/arm64-apple-macosx/debug/NullPlayer" ;;
  esac
  if [ ! -x "$bin" ]; then
    echo "testdata.sh: no debug binary at $bin" >&2
    echo "Build it first:  ./scripts/kill_build_run.sh --debug" >&2
    echo "There is no fallback: the installed /Applications build is a different, unknown" >&2
    echo "version with its own preferences, and a result from it says nothing about your tree." >&2
    exit 1
  fi
  for source in plex jellyfin emby subsonic; do
    echo "=== $source ==="
    "$bin" --cli --list-libraries --source "$source" --json 2>/dev/null || echo "  (unavailable)"
  done
  echo "=== cast devices ==="
  "$bin" --cli --list-devices --json 2>/dev/null || echo "  (unavailable)"
}

case "${1:-}" in
  ensure)  gen_ensure ;;
  path)    shift; cmd_path "$@" ;;
  list)    cmd_list ;;
  servers) cmd_servers ;;
  *) echo "usage: testdata.sh ensure|path <name>|list|servers" >&2; exit 2 ;;
esac
