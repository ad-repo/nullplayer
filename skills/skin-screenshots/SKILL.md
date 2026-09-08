---
name: skin-screenshots
description: Capture one centred main-window screenshot per skin across every skin system (Classic, Original, Original-Metal, Modern/.wal) and assemble them into a fixed-duration slideshow GIF. Use when producing marketing imagery, a skin gallery, or any before/after visual comparison across the skin corpus.
---

# Skin screenshot sweep

Photographs the **main window only**, one frame per skin, across all four skin systems, centres each
on an identical white frame, and builds a slideshow GIF whose cycle is exactly the length you ask for.

Everything is in `scripts/`. Run them in this order:

```bash
cd skills/skin-screenshots/scripts
./preflight.sh                                  # refuses states that silently produce bad frames
./enumerate_skins.sh > /tmp/skins.tsv           # reads the LIVE Skins menu
./capture.sh --list /tmp/skins.tsv --frame 800  # ~8s per skin; writes a manifest
./makegif.sh --seconds 30 --size 500 --order random
```

`capture.sh` with no `--list` enumerates for you. Both write to `~/Documents/shots` by default.

## The operator has to set the app up first

**Launch NullPlayer from a real terminal, never from the agent's shell.** A binary started with
`nohup` from an agent shell inherits background QoS and `nice > 0`; the UI throttles, timers defer,
skins take seconds longer to settle and the spectrum analyzer stops animating. `preflight.sh` hard-fails
on this because it cost hours once. See [[applescript-activate-launches-installed-app]] for the
related trap of raising the wrong build.

Then, **by looking at the screen**, confirm before starting:

- volume up and not muted
- a track playing (the display, time readout and spectrum are only alive during playback)
- spectrum analyzer on
- playlist loaded — skins with an embedded playlist pane photograph it

None of those four can be checked programmatically. Volume in particular lives in the state file,
written on quit: it is not in `UserDefaults`, cannot be read live, and the Up/Down volume keys are
handled only by the Classic main window (`Windows/MainWindow/MainWindowView.swift`), not the Modern
family. The `.wal` scroll wheel dispatches to the skin's own script, so a wheel notch means whatever
that skin decided.

## What each script does

| Script | Role |
|---|---|
| `preflight.sh` | Blocks a sweep in a known-bad state; prints the four checks only a human can make |
| `enumerate_skins.sh` | Reads the live Skins menu → `system / submenu / item / label` TSV, minus `../exclude.txt` |
| `capture.sh` | The sweep: mode switch, skin select, settle, capture, reframe, manifest |
| `reframe.sh` | Centres the visible artwork on the white frame; owns the two framing rules |
| `makegif.sh` | Assembles the GIF at an exact cycle length |
| `winhelper` | Window enumeration via `CGWindowListCopyWindowInfo`, and real `CGEvent` clicks and hovers (`move <x> <y> …`) |
| `menu.applescript` | The `mode` / `skin` / `list` / `closeaux` menu verbs |

`capture.sh` writes `manifest_<stamp>.tsv` next to the images recording, per skin: status, window
size, artwork size, which framing rule fired, and the output path. **Read the manifest rather than
the images to find bad frames** — it is the audit trail, and `--only <regex>` re-runs just the rows
that went wrong.

## The four rules that make this correct

Each one produced a batch of confident-looking wrong images before it was understood.

### 1. Selecting a skin does not switch skin *system*

Clicking a skin name changes the skin **within** the active system. Moving between Classic / Original
/ Original-Metal / Modern requires that submenu's **"Switch to …"** item, which is only present when
you are outside that system. Get it wrong and the sweep silently re-photographs the previous system's
window under the new system's names — 30 frames of Original-Metal labelled `modern_*`.

### 2. Window geometry is not a "skin loaded" signal

A heavy `.wal` leaves the previous window on screen, unchanged, for seconds while it loads. Waiting
for geometry to be *stable* therefore photographs the **old** skin, and reports its size. `Big Bento
Modern` measured 250×207 — Anexa's size, the skin before it — when it is really 1800×1169.

Wait for the geometry to **change** first (proof the new skin took), then for it to settle, then the
`--settle` pause. Where the app's log is reachable, `WinampModern surfaces [<file>.wal]` is the
authoritative per-skin load marker — see `winamp-modern-skin-guide/reference/harness.md`.

### 3. Centre the artwork, not the window rect

Many `.wal` windows carry large transparent margins: HeadAMP is 682px of artwork inside a 1520px
window at offset +414; Lobe's sits at +228+20. Centring the window rect makes the skin wander around
the frame between slides. Centre the alpha bounding box instead. 30 of 73 Modern skins were affected.

This also fixes bogus skips: judge the "too big for the frame" test on the **artwork**, not the
window, or you reject skins whose window is mostly empty.

### 4. Distrust a tiny trim box

Skins whose alpha is near-uniform return a degenerate bounding box — `3x4`, `5x2`, `0x318` — and
cropping to it yields a sliver instead of a skin. `reframe.sh` falls back to the whole window below
`MIN_FRACTION` (35%) of window area. **Re-shooting does not fix these**: it was never a timing
problem, and a second identical run is the evidence for that.

## A skin can mute playback

A `.wal` skin's own volume control may sit at zero and set the engine volume when it loads; the mute
then persists into **every skin loaded after it**, so the rest of the sweep is silent, flat-spectrum
frames. HeadAMP did exactly this, twice.

There is no outside fix (see the volume note above). When the operator reports the volume dropped,
the sweep log position names the culprit — restore the volume, then re-run from that skin with
`--only`. Excluding a repeat offender via `../exclude.txt` is reasonable.

## Frames that will not fit

At `--frame 800` seven Modern skins exceed the frame even after trimming: the four Big Bento variants
(1800×1169 / 1536×878), cPro Venus Alpha (1007×645), Diablo IV Skills V2 (1051×234) and
jvc.tape.v0.5 (1284×340). They are recorded as `skipped-too-big` in the manifest. Raise `--frame`
to include them — the frame is the GIF's canvas, so raising it shrinks every other skin within it.

`../exclude.txt` holds skins to skip outright; it currently carries the three `.wal` skins graded **F**
in `docs/winamp-modern/skin-compatibility.md`, which do not render.

## GIF timing

`makegif.sh` computes an integer centisecond delay per frame and spreads the remainder over the
leading frames, so 114 frames over 30s is exact rather than drifting. It verifies the assembled
duration and prints it. `--order random` interleaves the systems; `--order system` groups them
Classic → Original → Original-Metal → Modern.
