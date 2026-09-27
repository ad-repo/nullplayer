---
name: app-control
description: Launch, configure, drive, screenshot and measure the running NullPlayer app. Use when asked to run / launch / start the app, click or drag a control, reproduce a defect on screen, "open skin X", "show me it working", set up a test scenario, capture a window, or hand the user a loaded interactive session. Covers every skin family (Classic, Original, Original-Metal, Winamp Modern .wal, Windows Media Player .wmz) and names the canonical test-data targets.
---

# Controlling the app

## Rule zero: the app under test is the local debug build, always

**`skills/app-control/scripts/launch.sh <skin>` is the launch command** (Route B); it runs
`./scripts/kill_build_run.sh --debug`, which is the build-and-run command for a launch with no skin
to pin. Not `swift build`, not Xcode, not a release build.

Everything here then operates on the binary it produced:

```bash
BIN=.build/arm64-apple-macosx/debug/NullPlayer     # Intel: .build/x86_64-apple-macosx/debug/…
```

**Never invoke the installed app.** Not `nullplayer`, not `open -a NullPlayer`, not
`/Applications/NullPlayer.app/Contents/MacOS/NullPlayer`, not `activate application "NullPlayer"`.
Its version is unknown, it is not what you changed, and a clean result from it is worthless.

This has teeth:

- `/usr/local/bin/nullplayer` is a shim that `exec`s `/Applications/NullPlayer.app`. Every
  `nullplayer --cli …` line in `cli` therefore runs the installed build. Read that skill's flags;
  ignore its invocations.
- The installed app's defaults domain is `com.nullplayer.app`; the debug binary's is `NullPlayer`.
  Both exist on this machine with divergent contents.
- `NULLPLAYER_SKIN` and `NULLPLAYER_PLAY` are `#if DEBUG` only (`App/AppDelegate.swift:56,66`). A
  release or installed binary ignores them silently.

Two consequences, stated as facts:

1. A recipe that builds any other way is a bug in the recipe. Release exists only for a deliberate
   profiling measurement, which is out of scope here.
2. **There is exactly one defaults domain in this skill: `NullPlayer`.** `com.nullplayer.app` is
   never read or written, so nothing here can damage the user's real preferences.

## Routing

| Route | Use when | Cost |
|---|---|---|
| **A — Don't launch the GUI** | The question is about a skin's scene, geometry, hit map, script, or any pure logic | seconds |
| **B — Launch preconfigured, don't click** | You need the running app in a specific mode / skin / playback state | one launch |
| **C — Drive it yourself** | The defect needs a click, drag, hover, or a view switch | one launch + CGEvents |
| **D — Hand the user a loaded session** | Judgment ("does it look right"), contextual menus, anything a synthetic right-click cannot do | interactive |
| **E — Measure** | Always. Every route ends here | — |

**Not this skill:** `skin-screenshots` is the gallery GIF sweep and nothing else.
`live-ui-testing` is how not to fool yourself about what you measured. `testing` is `swift test`.
`cli` is the headless command surface — read its flags, ignore its invocations (Rule zero).

## Route A — don't launch the GUI

Applies when the answer is in a skin's scene, geometry, hit map or script rather than on screen.

1. Pick the headless entry point for the family.
2. Set the probe flag for the question you are asking.
3. Read the named line type out of the output.

```bash
WMP_SKIN="$HOME/Library/Application Support/NullPlayer/WMPSkins/corona.wmz" \
  WMP_RENDER_PROBE=all WMP_RENDER_HOST=playing \
  swift test --filter WMPRenderDumpTests/testSweepsSkinOrCorpus 2>&1 | grep '^PROBE'
```

| Family | Entry point | Day-one flags | Full flag table |
|---|---|---|---|
| `.wmz` | `WMP_SKIN=<file or dir> swift test --filter WMPRenderDumpTests/testSweepsSkinOrCorpus` | `WMP_RENDER_PROBE`, `WMP_RENDER_CLICK`, `WMP_RENDER_HOST=playing` | `wmp-skin-guide/reference/harness.md` |
| `.wal` | `WINAMP_MODERN_WAL=<file> swift test --filter WinampModernRenderDumpTests` | `WINAMP_MODERN_RENDER_PROBE` | `winamp-modern-skin-guide/reference/harness.md` |
| anything else | `swift test` | — | `testing` |

`WMP_SKIN` takes a file **or** a directory, so one command sweeps the whole corpus. The probe
flags are not copied here; go to the owning reference.

The CLI is also Route A — servers, radio, casting and library queries need no GUI:

```bash
BIN=.build/arm64-apple-macosx/debug/NullPlayer     # never `nullplayer`
"$BIN" --cli --list-libraries --source plex --json
```

**Confirm it took:** the probe printed the line type you asked for (`PROBE`, `CLICK`, `HOVER`), or
`--json` returned a non-empty array. A probe that prints nothing ran against nothing.

## Route B — launch preconfigured, don't click

**One command launches the debug build on any skin, playing, and verifies it:**

```bash
skills/app-control/scripts/launch.sh corona                 # .wmz   → -uiMode wmp
skills/app-control/scripts/launch.sh aquamp                 # .wsz   → -uiMode classic
skills/app-control/scripts/launch.sh 2222-cPro__Bento       # .wal   → -uiMode winampModern
skills/app-control/scripts/launch.sh modern:NeonWave        # Original submenu
skills/app-control/scripts/launch.sh "metal:Brushed Steel"  # Original-Metal submenu
```

It prints one line — `LAUNCH PASS: wmp skin 'corona'  pid … log /tmp/np.log` — or `LAUNCH FAIL: …`
and exits 1. **Trust that line and nothing else; do not hand-roll a skin launch.** Every other
way of doing it (`defaults write` recipes, `NULLPLAYER_SKIN` for a `.wmz`, a bare
`./.build/debug/NullPlayer`, `kill_build_run.sh` without `--debug`) has launched the wrong skin in
a past session, silently.

- `<skin>` is a bare installed name (searched across `Skins/`, `WinampModernSkins/`, `WMPSkins/`),
  `name.ext` to pin a family, or an absolute path. A name found in two families **fails and lists
  both** rather than guessing. A `.wmz` path outside `WMPSkins/` is imported via `-wmpSkinPath`.
- `--no-play` skips `NULLPLAYER_PLAY` (default: `audio-long` playing; an exported
  `NULLPLAYER_PLAY` replaces it). `--log <path>` (default
  `/tmp/np.log`). App arguments go after `--`; trace env vars are simply exported in front:
  `WMP_SEEK_TRACE=1 skills/app-control/scripts/launch.sh corona -- -winampModernShowVisualization 1`.
- It quits any running NullPlayer first — including another session's. Say so before using it
  while someone else's run is up.
- **Nothing to restore afterwards.** Session restoration is disabled with the *launch argument*
  `-rememberStateEnabled NO`, never a `defaults write`, so the saved Remember State is untouched
  and there is no restore trap to race. (The old recipes' trap ran the instant a non-interactive
  `read </dev/tty` failed — restoring the previous skin and `rememberStateEnabled=1` while the app
  was still starting. That was the wrong-skin bug.)

Why each family is selected the way it is — only needed when changing `launch.sh`:

| Family | Mechanism | PASS means |
|---|---|---|
| `.wsz`/`.whsz` | `NULLPLAYER_SKIN=<path>` (DEBUG only) | `lastClassicSkinPath` rewritten to that path (deleted first) |
| `.wal` | `-winampModernSkinPath <path>` (DEBUG only) | log `WinampModern surfaces [<file>.wal]:` |
| `.wmz` installed | `defaults write wmpSkinName`, `wmpSkinViewID` deleted | `wmpSkinName` is the name **and** the app re-wrote `wmpSkinViewID` (it only does once a scene renders) |
| `.wmz` elsewhere | `-wmpSkinPath <path>` (imports it) | same |
| modern / metal | `defaults write modernSkinName\|metalSkinName` | a `ModernSkinLoader: Loaded skin` log line whose path ends in the `<name>` folder (the quoted name is `skin.json`'s `meta.name`, which differs for `Bubblegum Retro`, `EmeraldForge`, `Sakura Minimal`) / `Loaded built-in metal skin '<name>'` |

`NULLPLAYER_SKIN` is the classic loader: a `.wmz` there loads nothing and comes up unskinned
(440x170). Restoration, if left on, rewrites `wmpSkinName` from the saved state before the window
opens. `launch.sh` exists so neither has to be remembered.

**Deleting `wmpSkinViewID` makes every `.wmz` launch a first launch.** The user's second launch
onward starts the view walk at the persisted player and skips the views ahead of it, so a defect
that only shows "after a relaunch" never reproduces through `launch.sh` — W299 measured fine on nine
launches that way. Reproduce it by killing the app and relaunching the debug binary with
`wmpSkinViewID` left in place (`./scripts/kill_build_run.sh --debug -- -uiMode wmp
-rememberStateEnabled NO`, with `NULLPLAYER_PLAY` set if the skin needs playback).

**The mode names do not match the menu.** `-uiMode modern` is the **Original** submenu;
`-uiMode winampModern` is the **Modern** submenu (`App/PlayerUIMode.swift:33-39`).

**`NULLPLAYER_PLAY` takes audio and `.cue` only** — `mp3 m4a aac wav aiff aif flac ogg alac`
(`App/AppDelegate.swift:340,357`). An `.m3u` or `.mp4` there is dropped with no log line and reads
exactly like a playback bug. **Video never goes through it**, and **Windows → Video Player is
inert** until a video has been opened from a browser (`App/WindowManager.swift:3205`). Media
recipes (audio/video × local/streaming) are in `reference/launch-recipes.md`.

Launch rules that still apply to anything `launch.sh` does not cover:

- **Redirect, never pipe.** `kill_build_run.sh --log <path>` writes the log; a pipe keeps the
  script attached. Live traces write to stderr, and a redirected `print` is block-buffered.
- **The front door un-throttles for you** (`taskpolicy -B`). A hand-rolled `nohup` does not: the
  app inherits background QoS, timers defer and animation stalls. Confirm with `ps -o nice= -p <pid>`.
- **The domain is `NullPlayer`.** Never `com.nullplayer.app`.
- Servers / radio / casting: don't launch the GUI — `"$BIN" --cli …` (Route A).

## Route C — drive it yourself

Applies when the defect needs a click, drag, hover or a view switch. Build the tools once:
`skills/app-control/scripts/build.sh`.

1. Launch via Route B.
2. Get the window id and origin from `winhelper windows`.
3. Get the control's coordinates **from the subsystem's probe** (Route A), never from a screenshot.
4. Raise the app and drive one throwaway gesture — the first click on an inactive window is
   consumed activating it.
5. Mark the log, act, read from the mark.

```bash
WH=skills/app-control/scripts/winhelper
PID=$(pgrep -x NullPlayer | head -1)
read -r WID _ X Y W H _ < <("$WH" windows --pid "$PID" --size 289x283)   # the skin's own canvas
"$WH" raise "$PID"                                        # exits non-zero unless it is frontmost
"$WH" click  $((X+320)) $((Y+291))                       # throwaway: activates the window
"$WH" drag   $((X+320)) $((Y+291)) $((X+400)) $((Y+291)) $((X+500)) $((Y+291))
```

- **Match the window by its size, never by `head -1`.** A `.wmz` window list can carry a second,
  transient row for the same app — a different id at a different origin — and a click computed from
  it lands on the desktop: the gesture posts, the log shows the hover/down repaints of *nothing*,
  and it reads exactly like a dead control. Two measurement runs on 2026-09-17 were thrown away to
  it, one of them a "0 redraws" rate that was really a pane that never opened. Pick the row whose
  `w`/`h` are the skin's own canvas (`$WH windows --size 289x283`, and `--pid` so the installed
  app's rows never match), and **confirm the state you think you set** from the subsystem's own
  trace before measuring anything against it.

| Verb | What it posts |
|---|---|
| `winhelper windows [--pid <n>] [--size <w>x<h>]` | `id layer x y w h alpha title`, on-screen windows owned by NullPlayer, front to back |
| `winhelper raise <pid>` | frontmost via System Events **by unix id**; exits non-zero unless that pid is frontmost afterwards |
| `winhelper park <pid> <title> <x> <y>` | moves the window with that title to a top-left screen point and raises it, then reads the position back; non-zero if no window has that title or it landed elsewhere — use it before `capture` on a window that runs off the screen |
| `winhelper capture <id> <out.png> [--pid <n>]` | the window's own content (`screencapture -l`), size-checked — see below |
| `winhelper capture-all <outdir> [--pid <n>] [--size <w>x<h>]` | `capture` for every matching window, one PNG each; non-zero if any is refused |
| `winhelper click <x> <y>` | `mouseMoved`, then down/up **with `mouseEventClickState = 1`** |
| `winhelper dblclick <x> <y>` | two clicks, the second at `clickState = 2` |
| `winhelper clickdiff <x> <y> [--pid <n>] [--size <w>x<h>] [--settle <s>]` | the window-frame check: `before` rows, a `click`, a wait (1 s default), `after` rows, then one `changed`/`gone`/`new` line per window; **exits 2 when nothing changed**. `dblclickdiff` is the same with `dblclick`. `--size` filters only the *before* listing |
| `winhelper scroll <x> <y> <count> <delta> [line\|precise]` | `count` wheel events at one point; `precise` is a trackpad (points), `line` (the default) a mouse wheel (lines) |
| `winhelper move <x> <y> …` | `mouseMoved` through the path, 250 ms apart |
| `winhelper drag <x> <y> …` | press, `leftMouseDragged` through the path, release at the last point |
| `osascript menu.applescript mode\|skin\|list\|closeaux <pid> …` | the Skins / Windows menu verbs |
| `osascript menu.applescript windowitems <pid>` | one `index\|name\|enabled\|checked` line per Windows-menu window toggle — block 1 minus Main Window, Debug Console and Recreate Windows (Debug), plus a `.wal` skin's own windows |
| `osascript menu.applescript toggle <pid> <index> <name>` | clicks Windows item `index`, erroring (exit non-zero, nothing clicked) if its name is no longer `name` |
| `winhelper screens` | each display's `visibleFrame` as `x y w h scale`, in the same top-left points as `windows` |

- **A press lands only on NullPlayer.** `click`, `dblclick`, `clickdiff`, `scroll` and the first
  point of `drag` exit 1 and post nothing unless the frontmost window under that point belongs to
  NullPlayer. An empty lookup reads as 0 in shell arithmetic: on 2026-09-27 an unchecked
  `read … < <(winhelper windows | grep …)` clicked the menu bar and dragged from the screen's
  top-left corner, and hung Finder and the Dock. Check the lookup anyway (`[ -n "$X" ] || exit 1`).
- **`clickState` is why clicks used to do nothing.** An event posted without it arrives
  `clickCount == 0`: any handler gating on `clickCount == 1` ignores it while the window still
  highlights. Both `click` and `drag` set it. Measured A/B on the same browser row: the pre-fix
  tool's two rapid clicks opened **0** windows and logged nothing; `dblclick` at the identical
  point opened the video window and logged `VideoPlayerView: Playing`.
- **A hover is not a click with the buttons left out.** `onMouseOver`/`onMouseOut` fire on the
  *edges* between controls, so the path is the test — and the app must be frontmost, or a
  borderless window gets no `mouseMoved` at all.
- **`menu.applescript` closes menus through Accessibility (`AXCancel`), never with Escape.**
  `key code 53` goes to the *frontmost* app, so a menu opened on the background debug build stayed
  up, held it in menu tracking, and every later toggle silently did nothing; a verb that errors
  half-way closes its menus too. A NullPlayer row at a layer other than 0 in `winhelper windows`
  is an open menu — nothing driven while one is up can be trusted.
- **`menu.applescript` requires a pid** and resolves `first process whose unix id is <pid>`. There
  is no name fallback: `process "NullPlayer"` is ambiguous whenever the installed build is also
  running, which is how it gets driven by accident.
- **A contextual menu is not drivable. That is Route D.**
- **`capture` refuses a picture that is not the window.** `screencapture -l` returns a
  **full-screen** image for an off-screen or stale id, and the **whole docked group** for a window
  with attached windows (a 197x194 pt `.wmz` pane came back 950x890 pt, it plus two docked
  neighbours, 2026-09-24). `capture` checks the pixel size against the window's points × scale;
  a group-sized image is cropped to the window and marked `cropped-from-group`; anything else exits
  non-zero. It retries three times, 400 ms apart, because a pane that is fading in or resizing
  changes size between the listing and the shot. `-l` sees the window regardless of occlusion,
  unlike `-R`, which photographs the screen.
- **A wheel gesture has two devices and a surface may read only one (W246).** `.line` events carry
  a line count and `.pixel` events a precise, continuous delta in points — the trackpad's, and the
  only one `hasPreciseScrollingDeltas` is true for. A list that advances one row per event however
  hard you flick is reading the delta's *sign*; one that ignores a flick entirely may be reading
  the other unit. Post both before concluding anything, and remember a scroll is **state the
  screen holds, not a log line** — capture the window, do not grep for it.
- **A scroll position can be undone faster than you can capture it.** WMP's playlist was pulled
  back onto the playing track by every host refresh, ~12 a second, so the gesture *did* land and
  the picture 80 ms later showed it had not. If a gesture seems not to take, capture immediately
  after it **and** again a second later: two different pictures mean something is fighting you,
  not that the event missed.

**Confirm it took:** the subsystem's live trace shows the gesture. A `WMP_SEEK_TRACE=1` drag prints
one `performSlider` per point and **exactly one** commit; a commit per move is the W156 regression.

## Route D — hand the user a loaded session

Applies to judgment ("does it look right"), contextual menus, and anything a synthetic gesture
cannot do. **The agent owns the process and the log; the user owns the mouse.**

1. Launch it yourself with `launch.sh` (Route B) and wait for `LAUNCH PASS`. The user runs nothing.
2. Tell the user it is up, on which skin, and what to look at.
3. **End your turn.** Do not block, do not sleep, do not background a watcher.
4. Mark the log's line count. On the user's next message, read from that mark, answer, re-mark,
   end the turn.

**Confirm it took:** the `LAUNCH PASS` line.

## Route E — measure

Every route ends here.

1. `winhelper windows` for the window id and geometry.
2. Capture **the window**, not the screen.
3. Two captures separated in time, compared, for anything that should be changing.

```bash
WID=$("$WH" windows | awk -F'\t' '$2==0{print $1; exit}')
screencapture -o -x -l "$WID" /tmp/t1.png; sleep 6
screencapture -o -x -l "$WID" /tmp/t2.png
cmp -s /tmp/t1.png /tmp/t2.png && echo "IDENTICAL" || echo "DIFFER"
```

- **`-l <windowid>` captures the window's own content. `-R <rect>` captures whatever is on top**,
  which is routinely your terminal. A conclusion drawn from a `-R` capture is worthless.
- **On a docked window, `-l` returns the whole docked group**, not the window you named. The
  image spans the union of every docked member, and its origin is the group's, not the window's
  — so a coordinate read off that capture is wrong by however far the window sits into the
  group. **Check both dimensions**: a stack docked vertically has the group's height and the
  window's width, so a width-only check passes while the capture is still the group and every
  `y` you read is wrong. Divide each capture dimension by 2 (retina) and compare with the row
  `winhelper windows` gives for that id; if **either** disagrees, map back through the group
  origin — the smallest `x` and `y` among the docked rows, which is not necessarily one
  window's corner:

  ```bash
  "$WH" windows | awk -F'\t' '$2==0 {if(gx==""||$3<gx)gx=$3; if(gy==""||$4<gy)gy=$4} END{print gx,gy}'
  # screen point for a capture pixel (px,py):  x = gx + px/2 ,  y = gy + py/2
  ```

  Measured: main + Playlist docked, `winhelper` reports the Playlist as `344x145`, the capture
  comes back `688x580` — 344 wide (agrees) and 290 tall (the group).
- **Mark the log before acting and read from the mark.** The startup log is thousands of lines of
  server chatter; `grep -o "^[^{]*"` strips the JSON bodies.
- **Take a control.** One capture of a thing that should change proves nothing.

**Confirm it took:** you can name the two artefacts your conclusion rests on.

### Skin window-size isolation (user-level regression test)

`skills/app-control/scripts/size-isolation-test.sh [<wmz A> <wmz B>]` (default `Ice anemone`) checks
that no skin inherits another's window sizes, through the menus and real resizes. Steps: resize the
analyser under A, switch to B in place, back to A, then switch mode to Classic and back. One
PASS/FAIL line per check, then `SIZE-ISOLATION PASS|FAIL`, with a matching exit status. It takes the
machine for about two minutes and saves and restores the debug defaults domain. Run it after any
change to `HostedWindowBorderLayout`, the mode-switch rebuild, or a native window's default size.

`skills/app-control/scripts/skin-mode-switch-test.sh "<window>" [--expected <census windows.tsv>…]`
is the cross-mode form. The window stays **open** through a chain that enters every mode from
another (Classic, Original, Metal, `.wal`, `.wmz`) and switches skin within each. It is resized
before every switch, and after each one:
- the window must still be open;
- it must not keep the previous size (a leak);
- back in a `.wmz` skin, it must have that skin's own size;
- in Classic, it must be at the classic default;
- with `--expected`, a switch into a new mode must land on that skin's fresh-launch census size.

Within Classic, and within Original/Metal (one family in the code), an open window keeps the user's
stretch across a skin change, as it always has. Pick windows by how their size is decided:
`Spectrum Analyzer` (stack), `Visualizations` (side window), `Sonos Rooms` (own show path). About
3–4 minutes each.

### Window census

Where each Windows-menu window opens and how big it is, per skin, in one command. **To run one for
a user, go through the `window-census` skill**, which covers what to confirm first, the worker
hand-off and what to report. This section is the instrument.

```bash
skills/app-control/scripts/window-census.sh aquamp corona 2222-cPro__Bento modern:NeonWave "metal:Brushed Steel" [--shots] [--out <dir>] [--no-play]
skills/app-control/scripts/window-census.sh --all wal,wmz          # every installed skin of those families
skills/app-control/scripts/window-census.sh --list all             # print the skin list, launch nothing
```

Families are `classic`, `original`, `metal`, `wal`, `wmz` and `all`. Classic, `.wal` and `.wmz`
skins come from the `Application Support/NullPlayer` skin folders as `name.ext`, so the extension
pins the family. Original skins are the bundled `Resources/Skins/*` plus user `ModernSkins/`
folders, and Metal skins are `builtInMetalSkinNames` plus user `MetalSkins/`.

It launches each skin with `launch.sh` (playing, so the vis windows have signal), closes every
auxiliary window, records that **baseline**, then for each `windowitems` line toggles the item
on, waits for a stable listing, records the diff, and toggles it off again. **Every item is
measured on its own from the same baseline**, so a row does not depend on the order and two runs
give the same rows apart from window ids. A stable listing is two identical `winhelper windows`
reads 250 ms apart, **alpha excluded** (a `.wmz` pane fades in), capped at 4 s. Stdout is one
`CENSUS <skin>: main WxH, N opened, N no-window, N unreachable, N residue` line per skin. A corpus
run takes about a minute per skin, so hand it to a worker and run it in the foreground.

**Skins are isolated from each other.** The app saves window sizes in its defaults, and some of
those keys are shared by every skin (`hostedInteriorSize2.*`; see
`~/.claude/plans/skin-window-size-isolation.md`), so without protection a skin opens at sizes the
previous one left. The census saves the debug `NullPlayer` domain once to
`<out>/defaults-baseline.plist`. Before every skin it quits the debug build (never the installed
app) and puts that copy back, and it does the same on exit. The restore is `defaults delete` and
then `defaults import`, because `defaults import` alone *merges*. Rows are therefore comparable
within a census. They are not factory sizes while the baseline still holds shared size keys.

Output (default `/tmp/np-window-census/<timestamp>/`). Every TSV has one header row, no comment
lines and one value per column:

| File | One row per | Columns |
|---|---|---|
| `windows.tsv` | window: the baseline windows (`role` `main`/`baseline`), then each item's (`role=item`); an item that opens several windows gets several rows, largest first, and a window-less item one row with empty geometry | `run skin family role item status enabled win_id x y w h title reachable overlap_main residue shot notes` |
| `skins.tsv` | skin, including launch failures (`launch_ok=0`, `error`) | `run skin family launch_ok main_w main_h max_w max_h max_item items opened no_window other unreachable residue error` |
| `meta.tsv` | setting | `key value`: screens' visible frames and scale, UI size, the defaults baseline |

`report.md` is rebuilt from the three files on every run. `--shots` adds `shots/<skin>/<item>.png`
(one `winhelper capture` per opened window, `unavailable` when capture refuses) and `shots.zip`.
**Resume:** pointing `--out` at an existing census appends to it, skips skins already in
`skins.tsv` (including failed ones) and reuses the same defaults baseline. If the app exits
mid-skin, the remaining items read `app-exited`.

- Coordinates and sizes are **top-left global points**, the same as `winhelper windows`.
- The Windows-menu items read exclude Main Window, Debug Console and Recreate Windows (Debug).
- `status` is what the click did, from the id diff:
  - `opened`: new visible rows. The largest one fills the row, and any others go in `side_effects`.
  - `open-at-baseline`: the only effect was a `gone` row, so the item was already open.
  - `skin-view`: the item replaced or changed an existing window without opening one, which is how
    a `.wmz` skin shows its own panel. A view that doesn't switch back is noted, not counted as
    residue.
  - `no-window`: no window changed. This includes a panel drawn inside the skin's own window
    without changing its frame. `2222-cPro__Bento`'s Equalizer, Playlist Editor and Library
    Browser read this way.
  - `transient`: a window flashed up at alpha 0 or vanished before the listing settled.
  - `menu-changed`: the item's name no longer matched its index.
- `residue` is `1` on an item whose second toggle didn't bring back the baseline's geometry.
- `reachable` is `WindowPlacement.isReachable` recomputed over `winhelper screens`: `1` when the
  top-left corner is inside some `visibleFrame`, with the left and top edges inclusive. A window
  parked past the bottom or right edge is placed, not stranded. `overlap_main` (pt²) is for
  information only, because the app deliberately prefers overlapping a window to hiding it.
- **The enabled flag is trustworthy.** `buildMenuBarWindowsMenu` sets `autoenablesItems = false`,
  so a disabled item (Video Player with no video, EQ and Playlist under `.wmz`) really is disabled.
  The census records it as `no-window` without clicking it.

## Test data

`scripts/testdata.sh ensure | path <name> | list | servers`. Per-row route validity is in
`reference/test-data.md`. **`audio-long` is the default for anything timed** — a 5-second file
ends mid-diagnosis and the `stop()` reads as the bug.

## Debugging a live defect

Read `live-ui-testing` for the epistemics — instrument first, what a green sweep cannot see — then
come back here for the mechanics. The reference implementation of the whole workflow is
`winamp-modern-skin-guide/reference/harness.md` § *Debugging a live defect*.
