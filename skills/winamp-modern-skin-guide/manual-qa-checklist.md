# Winamp Modern (`.wal`) — Manual QA Checklist

Everything in this checklist requires a **GUI session** and **user-supplied skin fixtures**, which is
why none of it was executed during implementation (Phases 3–7 all deferred it). The automated suite
covers the headless side; this is the gap.

Run this before treating the experimental label as removable.

Since Phase 13 the playlist, equalizer, and library are skin-owned surfaces rather than classic
windows, so **§4 is the section that changed most** — run it against all four fixtures.

## Setup

You supply the fixtures — nothing third-party is committed:

- `CornerAmp_Redux.wal`
- `WinampModern.wal`
- `mmd3.wal`
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
- [ ] cPro-Bento: beat visualization, spectrum, and the kbps/kHz/stereo readouts are all alive, and
      the window frame has no holes in its edges (each was a Phase 11 symptom)
- [ ] cPro-Bento: leave it open and **use** it for several minutes — clicking, opening drawers,
      switching colour themes, changing UI Size. A live run crashed in text drawing on 2026-08-16
      that no headless harness reproduces; if it recurs, record what you did immediately before.
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

Run this section against **all four** skins — they exercise different arrangements (see the table in
`compatibility.md`): cPro-Bento embeds all three surfaces, mmd3 declares a playlist window and needs a
synthesized library, CornerAmp declares playlist + EQ, Winamp Modern declares playlist + library.

**Where each surface opens**

- [ ] Open the playlist, equalizer, and library from the **Windows menu** and from the **skin's own
      control**, and confirm both reach the *same* place
- [ ] cPro-Bento stays a single window throughout — no classic `.wsz` window and no duplicate
      synthetic window appears for a surface the skin already shows
- [ ] mmd3 / CornerAmp: the synthesized library window is drawn with **the skin's own frame** (its
      title bar, borders, and buttons), not NullPlayer chrome
- [ ] A surface with no home falls back to the classic window, and the DEBUG log names the reason

**Playlist**

- [ ] Renders inside its holder with rows, selection, and now-playing marker, in the skin's colours
- [ ] Click selects; double-click plays; scroll wheel scrolls and stays bounded
- [ ] Select a row, press **Delete** — that row is removed, and selection/scroll stay in range
- [ ] Press Delete with the *player* focused (no row clicked): nothing is removed
- [ ] The `PE_Info` status line shows item count and total time, and updates as the queue changes
- [ ] ADD / REM / SEL / MISC buttons draw and hover but do nothing (documented limitation)

**Equalizer**

- [ ] Preamp and all 10 bands drag, and band 1 and band 10 audibly change output
- [ ] The EQ **on/off** button turns processing on and off (it must not open or close a window)
- [ ] The Auto button toggles auto mode, and both buttons' lit state follows the engine
- [ ] The presets button opens the preset list; applying one moves the sliders *and* changes the sound
- [ ] Change the EQ from the menu bar or the classic window — the skin's sliders follow
- [ ] `<eqvis>` (where the skin has one) tracks the current curve
- [ ] EQ gains survive a switch to Classic and back

**Library**

- [ ] The real browser appears inside the skin (cPro's Media Library tab; mmd3/CornerAmp's synthesized
      window; Winamp Modern's `MLibrary` window) — **not** a classic library window
- [ ] Browse local files and every configured remote source; artwork, tabs, and search all work
- [ ] Link a new server from the embedded browser; the sheet attaches to the `.wal` window
- [ ] CoverFlow and history hosting behave as they do in the classic window
- [ ] Switch tabs/layouts away and back — the browser is torn down and rebuilt without leaking tasks
- [ ] Browse mode is remembered across a quit and relaunch

**Themes and sizing**

- [ ] Switch colour theme: main chrome, auxiliary windows, playlist, EQ, and the library all recolour
- [ ] Resize every native `.wal` window; each obeys its **own** layout minimum
- [ ] Exercise every UI Size level, including clicking inside the embedded library at 200%
- [ ] Restore a session whose saved frame is below the layout minimum: the window clamps up and keeps
      its saved top-left corner

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
