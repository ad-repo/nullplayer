---
name: app-control
description: Launch, configure, drive, screenshot and measure the running NullPlayer app. Use when asked to run / launch / start the app, click or drag a control, reproduce a defect on screen, "open skin X", "show me it working", set up a test scenario, capture a window, or hand the user a loaded interactive session. Covers every skin family (Classic, Original, Original-Metal, Winamp Modern .wal, Windows Media Player .wmz) and names the canonical test-data targets.
---

# Controlling the app

## Rule zero: the app under test is the local debug build, always

**`./scripts/kill_build_run.sh --debug` is the build-and-run command.** It is the only one this
skill uses, and every recipe here assumes it. Not `swift build`, not Xcode, not a release build.

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
   never read or written, so the `defaults write` recipes below cannot damage the user's real
   preferences. The restore trap in Route D keeps *successive agent runs* deterministic; that is
   its whole job, and it is not optional for being cosmetic.

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

Applies when you need the app running in a specific mode, skin and playback state. Clicking
through menus to reach a state a launch flag already sets is the most common wasted launch.

Answer three questions before reading the matrix:

1. **Which binary?** The local debug build, by path. (Rule zero. There is no other answer.)
2. **Therefore which defaults domain?** `NullPlayer`.
3. **Therefore are `NULLPLAYER_*` live?** Yes, because it is a debug build.

Then:

1. `defaults write NullPlayer rememberStateEnabled -bool false` — restoration overwrites the skin
   keys before the window opens.
2. Set the mode and skin rows you need.
3. Launch through the front door, passing app arguments after `--`.
4. Read the Confirm column. **Every row on this surface fails silently.**

```bash
defaults write NullPlayer rememberStateEnabled -bool false
defaults write NullPlayer wmpSkinName -string "corona"
defaults delete NullPlayer wmpSkinViewID
export NULLPLAYER_PLAY="$(scripts/testdata.sh path audio-long)"
./scripts/kill_build_run.sh --debug --log /tmp/np.log -- -uiMode wmp
```

| Want | Set | Confirm it took |
|---|---|---|
| UI mode | `-uiMode classic\|modern\|metal\|winampModern\|wmp` | `winhelper windows` title: `NullPlayer — Windows Media Player`, `— Winamp Modern`, else bare `NullPlayer` |
| A classic `.wsz` | `NULLPLAYER_SKIN=/abs/x.wsz` (DEBUG only) | `defaults delete NullPlayer lastClassicSkinPath` first, then read it back — it names the loaded `.wsz`, and stays **absent** if the load failed |
| A `.wal` | `-winampModernSkinPath /abs/x.wal` | log line `WinampModern surfaces [<file>.wal]:` names the file |
| A `.wmz` | `defaults write NullPlayer wmpSkinName "<name>"` + `defaults delete NullPlayer wmpSkinViewID` — **`NULLPLAYER_SKIN` does not work for `.wmz`** | `defaults read NullPlayer wmpSkinViewID` is rewritten to the skin's own view (corona → `vPlayer`), and the window is not the unskinned 440x170 |
| A modern skin | `defaults write NullPlayer modernSkinName "<name>"` (bundled: `NeonWave`) | log line `ModernSkinLoader: Loaded skin '<name>'` |
| A metal skin | `defaults write NullPlayer metalSkinName "<name>"` (bundled: `Brushed Steel`) | log line `ModernSkinEngine: Loaded built-in metal skin '<name>'` |
| A track playing | `NULLPLAYER_PLAY="$(scripts/testdata.sh path audio-long)"` (DEBUG only) | log line `loadLocalTrack: <file>`; elapsed readout advancing across two captures |
| A deterministic start | `defaults write NullPlayer rememberStateEnabled -bool false` | no `AppStateManager: Restoring` lines; the skin key survives to window open |
| Servers / radio / casting | do not launch the GUI — `"$BIN" --cli …` | `--json` output non-empty |

**The mode names do not match the menu.** `-uiMode modern` is the **Original** submenu;
`-uiMode winampModern` is the **Modern** submenu (`App/PlayerUIMode.swift:33-39`). Getting this
backwards silently tests the wrong family.

**`NULLPLAYER_PLAY` takes audio and `.cue` only** — `mp3 m4a aac wav aiff aif flac ogg alac`
(`App/AppDelegate.swift:340,357`). An `.m3u` or `.mp4` there is dropped with no log line and reads
exactly like a playback bug. See `reference/test-data.md`.

Four launch rules:

- **Redirect, never pipe.** `kill_build_run.sh --log <path>` writes the log; a pipe keeps the
  script attached. Live traces write to stderr, and a redirected `print` is block-buffered.
- **The front door un-throttles for you** (`taskpolicy -B`). A hand-rolled `nohup` does not: the
  app inherits background QoS, timers defer and animation stalls. Confirm with `ps -o nice= -p <pid>`.
- **The domain is `NullPlayer`.** Never `com.nullplayer.app`.
- **Restore what you wrote**, with a `trap`, so the next run starts clean.

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
read -r WID _ X Y W H _ < <("$WH" windows | head -1)
PID=$(pgrep -x NullPlayer | head -1)
osascript -e "tell application \"System Events\" to tell (first process whose unix id is $PID) to set frontmost to true"
"$WH" click  $((X+320)) $((Y+291))                       # throwaway: activates the window
"$WH" drag   $((X+320)) $((Y+291)) $((X+400)) $((Y+291)) $((X+500)) $((Y+291))
```

| Verb | What it posts |
|---|---|
| `winhelper windows` | `id layer x y w h alpha title`, on-screen windows owned by NullPlayer |
| `winhelper click <x> <y>` | `mouseMoved`, then down/up **with `mouseEventClickState = 1`** |
| `winhelper dblclick <x> <y>` | two clicks, the second at `clickState = 2` |
| `winhelper move <x> <y> …` | `mouseMoved` through the path, 250 ms apart |
| `winhelper drag <x> <y> …` | press, `leftMouseDragged` through the path, release at the last point |
| `osascript menu.applescript mode\|skin\|list\|closeaux <pid> …` | the Skins / Windows menu verbs |

- **`clickState` is why clicks used to do nothing.** An event posted without it arrives
  `clickCount == 0`: any handler gating on `clickCount == 1` ignores it while the window still
  highlights. Both `click` and `drag` set it.
- **A hover is not a click with the buttons left out.** `onMouseOver`/`onMouseOut` fire on the
  *edges* between controls, so the path is the test — and the app must be frontmost, or a
  borderless window gets no `mouseMoved` at all.
- **`menu.applescript` requires a pid** and resolves `first process whose unix id is <pid>`. There
  is no name fallback: `process "NullPlayer"` is ambiguous whenever the installed build is also
  running, which is how it gets driven by accident.
- **A contextual menu is not drivable. That is Route D.**

**Confirm it took:** the subsystem's live trace shows the gesture. A `WMP_SEEK_TRACE=1` drag prints
one `performSlider` per point and **exactly one** commit; a commit per move is the W156 regression.

## Route D — hand the user a loaded session

Applies to judgment ("does it look right"), contextual menus, and anything a synthetic gesture
cannot do. **The agent owns the process and the log; the user owns the mouse.**

1. Copy `scripts/qa-session-template.sh` to your scratchpad and fill in the scenario.
2. Hand the user **one short line**: `! <path>/qa-session.sh`. A long quoted one-liner is what
   fails to parse.
3. **End your turn.** Do not block, do not sleep, do not background a watcher.
4. Mark the log's line count. On the user's next message, read from that mark, answer, re-mark,
   end the turn.

```bash
cp skills/app-control/scripts/qa-session-template.sh "$SCRATCH/qa-session.sh"
# …edit the SCENARIO block…
echo "Run:  ! $SCRATCH/qa-session.sh"
```

The template — not the prose — carries the restore trap.

**Confirm it took:** the user reports the window is up, or the log has the Route B Confirm line.

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
- **Mark the log before acting and read from the mark.** The startup log is thousands of lines of
  server chatter; `grep -o "^[^{]*"` strips the JSON bodies.
- **Take a control.** One capture of a thing that should change proves nothing.

**Confirm it took:** you can name the two artefacts your conclusion rests on.

## Test data

`scripts/testdata.sh ensure | path <name> | list | servers`. Per-row route validity is in
`reference/test-data.md`. **`audio-long` is the default for anything timed** — a 5-second file
ends mid-diagnosis and the `stop()` reads as the bug.

## Debugging a live defect

Read `live-ui-testing` for the epistemics — instrument first, what a green sweep cannot see — then
come back here for the mechanics. The reference implementation of the whole workflow is
`winamp-modern-skin-guide/reference/harness.md` § *Debugging a live defect*.
