---
name: skin-screenshots
description: Capture one centred main-window screenshot per skin across every skin system (Classic, Original, Original-Metal, Modern/.wal, Media Player/.wmz, Audion Faces, Sonique/.sgf) and assemble them into a fixed-duration slideshow GIF. Use when producing marketing imagery, a skin gallery, or any before/after visual comparison across the skin corpus.
---

# Skin screenshot sweep

> **Scope.** This skill produces a **gallery GIF** and nothing else. It sweeps seven skin
> families — Classic, Original, Original-Metal, Modern, Media Player (`.wmz`), Audion Faces and
> Sonique (`.sgf`): `enumerate_skins.sh` emits every skin in those seven Skins submenus, and
> `capture.sh` photographs each entry it emits. To launch, configure, drive,
> screenshot or test the running app — for any reason other than assembling that GIF — see
> **`app-control`**. It owns `winhelper` and `menu.applescript`, which this sweep only borrows.

Photographs the **main window only**, one frame per skin, across all seven skin systems, centres each
on an identical white frame, and builds a slideshow GIF whose cycle is exactly the length you ask for.

Everything is in `scripts/`. Run them in this order:

```bash
cd skills/skin-screenshots/scripts
./preflight.sh                                  # refuses states that silently produce bad frames
./enumerate_skins.sh > /tmp/skins.tsv           # reads the LIVE Skins menu
./capture.sh --list /tmp/skins.tsv --frame 800  # ~8s per skin; writes a manifest
./makegif.sh --seconds 30 --size 500 --order random
```

`makegif.sh --delay CS` fixes the per-frame delay (in centiseconds) instead of the cycle length, and
`--feature FILE:N` (repeatable) makes one frame appear N times in total, spread through the sequence.

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
| `enumerate_skins.sh` | Reads the live Skins menu → `system / submenu / item / label` TSV, minus `../exclude.txt`. So its `.wal` set is the user's installs in `WinampModernSkins/`, not the `.wal` test corpus (`WinampModernCorpus/`, see `winamp-modern-skin-guide/reference/harness.md`) |
| `capture.sh` | The sweep: mode switch, skin select, settle, capture, reframe, manifest |
| `reframe.sh` | Centres the visible artwork on the white frame; owns the two framing rules |
| `makegif.sh` | Assembles the GIF at an exact cycle length |
| `../../app-control/scripts/winhelper` | Window enumeration, and real `CGEvent` clicks, hovers and drags. Owned by `app-control` |
| `../../app-control/scripts/menu.applescript` | The `mode` / `skin` / `list` / `current` / `family` / `closeaux` menu verbs, addressed by pid. Owned by `app-control` |

`capture.sh` writes `manifest_<stamp>.tsv` next to the images recording, per skin: status, window
size, artwork size, which framing rule fired, and the output path. **Read the manifest rather than
the images to find bad frames** — it is the audit trail, and `--only <regex>` re-runs just the rows
that went wrong.

## The four rules that make this correct

Each one produced a batch of confident-looking wrong images before it was understood.

### 1. Confirm the skin system before photographing

Clicking a skin name switches into that skin's system when another is on screen, in every family.
Before 0.31.2 Classic switched only from Original/Metal and Modern never did, and the sweep silently
re-photographed the previous system's window under the new system's names — 30 frames of
Original-Metal labelled `modern_*`. Check `menu.applescript family <pid>` names the system you meant
before capturing.

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

Artwork larger than `--frame` is shot anyway: `reframe.sh` grows the canvas to hold it and scales it
down with every other skin, so nothing is `skipped-too-big` any more. The full-size shot is always
kept in `<out>/raw/<label>.png`; use that, not the framed PNG, as a site source.

`../exclude.txt` holds skins to skip outright, one fixed string per line (no comments). It lists
`211786-Cpro_Winamp_Modern`: that `.wal` pegs the app's main thread at ~100% CPU, so every menu call
the sweep makes times out and it restores on the next launch too (2026-10-11).

## Main-window guard

`capture.sh` matches the main window by its **exact** title for the family (`main_title`), never by
prefix: `NullPlayer Analyzer`, `NullPlayer Art` and the WMP view windows all start with `NullPlayer`.
Per row it records `no-main`, `ambiguous` (two windows with the title) or `extra-windows` (anything
else still on screen after `closeaux`) and does not shoot; the manifest carries the title and window
id of every row. "Loaded" is the Skins menu naming the skin as checked, plus the log's
`WinampModern surfaces [...]` line for `.wal` and `SoniqueSkin: loaded` for `.sgf` (`--log`, default `$NULLPLAYER_LOG` or `/tmp/np.log`).
`capture.sh` reads `skinWindowShadows` before every shot, records it in the manifest, and **stops the run**
with `shadows-off` rather than shoot without a shadow. (`closeaux` used to click Window Shadows off
because it is a checked item in the Windows menu; it now closes window toggles only.)
Settle after that is per family (0.5 s; Sonique 0 — it does not animate; WMP 15 s; Winamp Modern 15 s), `--settle` overrides it and
`settle.tsv` (skin, seconds) overrides both for long-intro skins.

**Skins with an accessory window.** A few skins leave a second window on screen by design (2026-10-11:
`wmp_Jewel` → `remoteView`, `wmp_livin_it_skate` → `displayView`, `modern_Shield_Amp` → a 20x20
untitled window). `capture.sh` refuses them as `extra-windows`; `--allow-extra REGEX` shoots the main
window alone (framing gains `+extra-ignored`), and `scripts/groupshot.py <pid> <submenu> <item> <label>
<settle> <outdir>` shoots the main window plus every accessory, composited at their true positions.

## GIF timing

`makegif.sh` computes an integer centisecond delay per frame and spreads the remainder over the
leading frames, so 114 frames over 30s is exact rather than drifting. It verifies the assembled
duration and prints it. `--order random` interleaves the systems; `--order system` groups them
Classic → Original → Original-Metal → Modern → Media Player → Audion Faces → Sonique.

## Audion faces

Panic's archive is 856 faces, so a whole-menu sweep is about two hours of Audion alone; pick a set
with `--only` or `../exclude.txt`. Past 40 faces the menu is grouped into A–Z submenus, which
`menu.applescript` `list`, `current` and `skin` read in place. Face names can start or end with a
space (five do), so `list` prints one name per line and `enumerate_skins.sh` never trims: trimming
made those rows `MENU-FAIL`.

## Sonique skins

Each skin is shot in the mode the window is in — navigator, mid or small — so pick it before the
sweep with **Skins ▸ Sonique ▸ Mode**, or launch with `launch.sh sonique:<skin> -- -soniqueSkinMode
mid|small`; navigator is the default. `enumerate_skins.sh` drops the `Mode` submenu, and the corpus's
524 skins sit in A–Z submenus that `menu.applescript` reads in place, as for Audion. The menu ticks
before an `.sgf` has loaded, so `capture.sh` waits for the log's next `SoniqueSkin:` line. A skin
that fails logs its error there and the default skin stands in, so any line but `loaded` is
recorded as `load-failed` and not shot under that skin's name. A whole-corpus sweep is about an
hour; pick a set with `--only`.
