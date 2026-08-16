# Winamp Modern (`.wal`) — Manual QA Checklist

Everything in this checklist requires a **GUI session** and **user-supplied skin fixtures**, which is
why none of it was executed during implementation (Phases 3–7 all deferred it). The automated suite
covers the headless side; this is the gap.

Run this before treating the experimental label as removable.

## Setup

You supply the fixtures — nothing third-party is committed:

- `CornerAmp_Redux.wal`
- `WinampModern.wal`
- `cPro-Bento.wal` **+** `ClassicPro_2.01.exe`

```sh
./scripts/kill_build_run.sh
```

Then **Winamp Modern (Experimental)** → **Import .wal Skin…**, and for cPro-Bento also
**Import ClassicPro Engine…**. In a DEBUG build you can bypass the picker:

```sh
./.build/debug/NullPlayer -uiMode winampModern -winampModernSkinPath /abs/path/Skin.wal
```

Watch the log for the compatibility report — DEBUG builds log it after script start whenever the level
is not `.full`. **Capture that report for each fixture**; its `unsupportedMethods` bucket is the
measured list of MAKI methods to implement next, and collecting it is the point of this pass.

## 1. Load and render

For each of the three fixtures:

- [ ] Skin loads without an error alert
- [ ] Main window appears at the skin's own canvas size (CornerAmp 246×228, Winamp Modern 354×280)
- [ ] Window is correctly alpha-shaped — no opaque rectangle, no black corners
- [ ] Artwork, fonts, colors, and gamma look like the skin's intent
- [ ] Record which widgets draw empty (expected for `wasabi.*`-backed ones) with a screenshot
- [ ] cPro-Bento: the SUI expands to exactly **one** window, not a scattering of stubs
- [ ] Capture a reference screenshot per fixture into `docs/winamp-modern/screenshots/`

## 2. Input and transport

- [ ] Buttons respond to hover, press, and release with the right state images
- [ ] Play / Pause / Stop / Previous / Next / Eject all work
- [ ] Clicks **outside** the alpha region fall through (do not activate the window)
- [ ] Dragging the window body moves it; dragging a control does not
- [ ] Right-click opens the expected menu
- [ ] Seek slider scrubs, and the position display tracks it
- [ ] Volume slider changes output level and is clamped at both ends
- [ ] Repeat and shuffle toggles reflect and change real state
- [ ] Ticker/marquee and elapsed-time text update during playback

## 3. Playback (never verified from a `.wal` skin)

- [ ] Local file plays to completion and auto-advances
- [ ] Streaming source (Plex / Jellyfin / Subsonic / Emby) plays
- [ ] Internet radio plays and metadata updates
- [ ] Visualization area animates in time with audio
- [ ] Pausing freezes the visualization; resuming restarts it
- [ ] No audio glitch or dropout attributable to skin repaint

## 4. Hosted components

- [ ] Playlist renders inside its holder frame with rows, selection, and now-playing marker
- [ ] Click selects; double-click plays; scroll wheel scrolls and stays bounded
- [ ] EQ shows preamp + 10 bands; dragging a band audibly changes output
- [ ] EQ enabled/auto toggles work; presets load
- [ ] EQ gains survive a switch to Classic and back
- [ ] Library toggle falls back to the classic library window (expected)
- [ ] `TOGGLE` for eq/pl/ml/video routes to the embedded component where the skin provides one

## 5. Mode switching and lifecycle

- [ ] Switch Classic → Modern → Metal → Winamp Modern → Classic; correct UI each time, no crash
- [ ] **Switch modes while audio is playing** — playback continues uninterrupted across every switch
- [ ] Switch modes while **casting** (Sonos and Chromecast) — the cast survives
- [ ] Swap between installed `.wal` skins live
- [ ] Quit with Remember State on; relaunch returns to Winamp Modern with the same skin
- [ ] Enter and exit Compact Mode
- [ ] Change UI Size
- [ ] Window docking/snapping behaves (Winamp Modern routes through the classic geometry path)
- [ ] Memory does not climb across ~20 load/teardown cycles (Instruments or Activity Monitor)

## 6. Failure handling

- [ ] Importing a non-`.wal` file shows a clear error, no crash
- [ ] Importing a truncated/corrupt `.wal` shows a clear error, no crash
- [ ] cPro-Bento **without** the engine imported degrades with a diagnostic rather than hanging
- [ ] Importing a non-NSIS-2 `.exe` as the engine gives an actionable message
- [ ] No error path leaks a real filesystem path into user-visible text

## 7. Release hygiene

- [ ] `swift test` fully green
- [ ] `./scripts/validate_notices.sh` passes
- [ ] Release build (`-c release`) compiles — the menu is no longer `#if DEBUG`, so release is the
      configuration that actually exercises this code path
- [ ] The Winamp Modern menu is labeled **Experimental**
- [ ] Fixtures used are recorded in the QA notes; none were committed

## Reporting

File anything that fails as a normal issue. For each fixture, attach the compatibility report and the
reference screenshot — together they are the input to the next round of demand-driven API work.
