#!/usr/bin/env python3
"""Pause a server stream in its last seconds, seek back while paused, resume, and check the
audio really moved: the track must keep playing for about as long as the seek put back.

Drives the headless CLI (`--cli --verbose`) through a pty with its own keys (Space, arrows),
so it never touches a running GUI. Reads position from the CLI's `m:ss / m:ss` progress line.
Prints one line, `STREAM-PAUSE-SEEK PASS|FAIL|ABORT: ...`, exit 0 / 1 / 2.
Builds the debug binary first (scripts/lib/swiftpm.sh), so it never runs a stale one.

Pick the target from `scripts/testdata.sh servers`: an album whose first track (or the
--track match) runs well past --lead seconds. With --fades it crossfades into the next one.

    S=skills/app-control/scripts/stream-pause-seek-test.py
    $S --library AD-FLAC --artist "Dead Meadow" --album "Dead Meadow" --track Lady
    $S --library AD-FLAC --artist "Dead Meadow" --album "Dead Meadow" --track la --fades
    $S ... --no-pause                                    # control: seek while playing

ABORT means the run proved nothing (build failed, the track changed before the pause — the
FLAC rapid-seek parse error — or the stream never reached EOF before the pause). Rerun it.
"""
import argparse, os, pty, re, select, subprocess, sys, time

REPO = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", ".."))
RIGHT, LEFT = "\x1b[C", "\x1b[D"
PROGRESS = re.compile(r"(\d+):(\d\d) / (\d+):(\d\d)")

ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
ap.add_argument("--source", default="plex")
ap.add_argument("--library", required=True)
ap.add_argument("--artist", required=True)
ap.add_argument("--album", required=True)
ap.add_argument("--track", help="--track substring filter (default: the whole album, from its first track)")
ap.add_argument("--fades", action="store_true", help="Sweet Fades on (5 s); the pause lands mid-crossfade")
ap.add_argument("--pause-at", type=float, default=2.5, help="seconds before the end to pause (default 2.5)")
ap.add_argument("--lead", type=float, default=100, help="seconds of natural playback before the pause; must be long enough for the download to reach EOF (default 100)")
ap.add_argument("--seek-gap", type=float, default=2.0, help="seconds between the +10 s seeks that get there; rapid seeks trip a FLAC parse error (default 2)")
ap.add_argument("--back", type=int, default=2, help="number of -10 s seeks while paused (default 2)")
ap.add_argument("--no-pause", action="store_true", help="control: same seeks while playing")
ap.add_argument("--log", default="/tmp/np-stream-pause-seek.log")
ap.add_argument("app_args", nargs="*", help="extra app arguments (after --)")
o = ap.parse_args()

def verdict(kind, msg, code):
    print(f"STREAM-PAUSE-SEEK {kind}: {msg}  (log {o.log})")
    sys.exit(code)

SWIFTPM = 'source scripts/lib/swiftpm.sh && '
build = subprocess.run(["bash", "-c", SWIFTPM + 'swift build -c debug ${SWIFTPM_ARGS[@]+"${SWIFTPM_ARGS[@]}"}'],
                       cwd=REPO, capture_output=True, text=True)
if build.returncode != 0:
    verdict("ABORT", "debug build failed:\n" + (build.stdout + build.stderr)[-2000:], 2)
BIN = os.path.join(subprocess.run(["bash", "-c", SWIFTPM + "swiftpm_bin_path debug"], cwd=REPO,
                                  capture_output=True, text=True, check=True).stdout.strip(), "NullPlayer")

args = [BIN, "--cli", "--verbose", "--source", o.source, "--library", o.library,
        "--artist", o.artist, "--album", o.album] + (["--track", o.track] if o.track else []) + \
       ["-sweetFadeEnabled", "YES" if o.fades else "NO", "-sweetFadeDuration", "5"] + o.app_args

master, slave = pty.openpty()
proc = subprocess.Popen(args, stdin=slave, stdout=slave, stderr=slave, close_fds=True)
os.close(slave)
buf, t0 = "", time.time()
log = open(o.log, "w")

def pump(secs):
    global buf
    end = time.time() + secs
    while time.time() < end:
        if select.select([master], [], [], 0.05)[0]:
            try:
                d = os.read(master, 65536).decode("utf-8", "replace")
            except OSError:
                return
            buf += d
            log.writelines(f"[{time.time()-t0:7.2f}] {l}\n" for l in d.splitlines())
            log.flush()

def mark(msg):
    log.write(f"[{time.time()-t0:7.2f}] DRIVER {msg}\n"); log.flush()

def send(keys, what):
    mark(what)
    try:
        os.write(master, keys.encode())
    except OSError:
        verdict("ABORT", f"app exited before '{what}'", 2)

def position():
    m = PROGRESS.findall(buf)
    if not m:
        return None
    a, b, c, d = map(int, m[-1])
    return a * 60 + b, c * 60 + d

def finish(kind, msg, code):
    try:
        os.write(master, b"q")
    except OSError:
        pass
    pump(1.5); proc.kill()
    verdict(kind, msg, code)

for _ in range(300):
    pump(0.1)
    if position():
        break
else:
    finish("ABORT", "playback never started", 2)
pump(4)
send(RIGHT, "seek +10 (probe duration)"); pump(1.2)
pos, dur = position()
t_pos = time.time()
while pos < dur - o.lead:
    send(RIGHT, "seek +10"); pump(o.seek_gap)
    pos, d2 = position()
    t_pos = time.time()
    if d2 != dur:
        finish("ABORT", f"track changed before the pause ({d2} s != {dur} s) — the rapid-seek parse error; rerun", 2)
pump(max(0, (dur - o.pause_at) - (pos + time.time() - t_pos)))
eof_before_pause = "Finished buffering entry" in buf
if not o.no_pause:
    send(" ", "PAUSE"); pump(1.5)
for _ in range(o.back):
    send(LEFT, "seek -10"); pump(0.6)
pump(0.9)
if not o.no_pause:
    send(" ", "RESUME")
t_resume = time.time()
pump(1.5)
shown = position()[0]
while time.time() - t_resume < 60 and proc.poll() is None:
    pump(1)
    p, d = position()
    if d != dur or p < 5:
        break
played = time.time() - t_resume
expected = dur - shown  # what the clock promised after the seek
mark(f"shown {shown}/{dur} after resume; track ended {played:.1f} s after resume; expected ~{expected} s")
if not eof_before_pause and not o.no_pause:
    finish("ABORT", f"download had not reached EOF before the pause (the bug needs it); raise --lead", 2)
desc = f"{'fades on' if o.fades else 'fades off'}, {'no pause' if o.no_pause else 'paused'} at -{o.pause_at:g} s, " \
       f"clock showed {shown // 60}:{shown % 60:02d}, played {played:.1f} s of ~{expected} s"
if played >= 0.6 * expected:
    finish("PASS", desc, 0)
finish("FAIL", desc + " — the seek moved the clock but not the audio", 1)
