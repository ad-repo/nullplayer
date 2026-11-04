---
name: aimp-skin-guide
description: AIMP skin family (.acs5, .acs4, .acs3, .acs4proj, AIMP 2's .acs) — the decoded containers, ACLIMG32/ASEIMG32 images and AIMP 2's bitmaps, SXML/BXML documents, layout and binding rules, FastScript scripts, the test-target harness and load gate, and the backlog. Use before AIMP skin work, when an AIMP skin looks or behaves wrong, or when reading an AIMP skin.
---

# AIMP skins

Read this before AIMP skin work. The family pattern is `skin-subsystem-blueprint`; the phase order
for testing and fixing one skin is `skin-triage`; the backlog is `tasks/AIMP_TASKS.md`.
`skin-triage`'s per-family tables have no AIMP row (shared docs stay as upstream has them); for
AIMP read them as: evidence is the skin's own artwork, markup and scripts and its catalog
screenshot, so a diff is unclassified; the sweeps are `AIMPRenderDumpTests` and
`AIMPCorpusLoadTests`; the inventory dump is `AIMP_RENDER_ITEMS=1` and `AIMP_RENDER_TARGETS=1`;
controls are driven by `AIMP_RENDER_LIVE=1`, then `AIMP_RENDER_CLICK`, `AIMP_RENDER_WHEEL`,
`AIMP_RENDER_HOVER` and `AIMP_RENDER_PAGES`/`COUNTERS` per state (`reference/harness.md`).

- **Engine:** loader, model, scripts and renderer in `Sources/NullPlayer/AIMPSkin/`. Forms are read
  once into typed items and controls (`AIMPSkinIndex`); each frame is laid out (`AIMPSkinLayout`),
  then painted (`AIMPSkinPainter`), and its click targets are read from the layout
  (`reference/layout.md` § *How a frame is made*).
- **Window:** `Sources/NullPlayer/Windows/AIMPSkin/`; `PlayerUIMode.aimp` routes it.
  - One `AIMPSkinRuntime` per skin owns its state, its one clock (30 fps while playing and seen)
    and each window's eased gauges (`AIMPSkinGauges`): a tick runs the scripts on main on one
    `AIMPSkinScript.Engine` (one budget; an event gets its own), then each form's view draws its frame on a background queue
    (`AIMPSkinFrameScheduler`: one frame at a time; requests made meanwhile wait as one, the
    latest, measuring if any asked to) and shows it when ready. A frame is taken by the view's
    `Generation` (its skin, and which change of what shows), not the skin's name; the content stays
    to be measured until a measured frame of the latest change shows. The level meter runs with the
    clock; while the clock runs, a change waits for its next tick. A skin switch stops the outgoing
    runtime and closes its windows before the incoming one is installed and its load scripts run.
    The probe sets the scheduler's timing to
    `.probe(clock:)`: it draws synchronously, at its own clock. Everything a frame reaches is
    declared `Sendable`, so the compiler checks that boundary; the skin's caches keep their state
    behind an `OSAllocatedUnfairLock` (the pixel budget, whose one lock spans every picture, says
    why it cannot), and make a value outside it (`AIMPSkinCache`).
  - Each form's `AIMPSkinMainView` draws and takes the pointer; its state is in collaborators: the
    press under way (`AIMPSkinPress`: held target, drag hand-over, hold timer), the form's size and
    the user's sizing (`AIMPSkinSizing`), and the quick search's text field (`AIMPSkinSearchField`).
    What it hovers and holds, and each gauge it eases, is keyed by the control's identity
    (`AIMPSkinControl.ID`, numbered by the index), never its name. The skin's other windows are
    `AIMPSkinCompanionWindows` (made, shown by the skin's state, placed once, fitted as the deck is);
    the controller presents skins and wires them. Popup menus are `AIMPSkinPopup`.
  - One `AIMPSkinAudioEngineHost` per window controller maps AIMP actions and providers to the
    player and is stopped with the mode. Its `snapshot` only reads (`AIMPSkinPlayerSnapshot`); track
    starts and finishes are counted, and background fetches begun, on the engine's events. Its
    `AIMPSkinLibrarySource` builds the skin's library window's `AIMPSkinLibrary` (NullPlayer's
    `LibraryTrack`s, sorted by `LibraryTextSorter`) off main; plays and menus look tracks up in
    that build by id.
  - A frame reads `AIMPSkinHostState`: the player's snapshot (the runtime's latest), the drawing
    window's feedback (`AIMPSkinFrameFeedback`: clock, meters, pointer, last frame's rows and
    gauges) and the quick search's matches (the runtime's cache). A script run outside a frame (a
    click's handler) reads no window's feedback. The runtime compares snapshots by value, the
    playlist by its build (`Playlist.generation`).
  - What a press, drag or wheel notch does is the target's (`AIMPSkinTarget`): `Kind.isDraggable`,
    `Kind.passesDragsThrough`, and `AIMPSkinStep`, a counter key's or tab selector's `Expression`
    compiled once and sorted by what the wheel does with it (`ScrollDelta` is the notches, a click one). The
    view's mouse code (`AIMPSkinMainView+Mouse.swift`) dispatches on them; it reads no expression text.
  - The skin's own playlist and library windows answer the app's (`SkinDrawnLists`, AIMP's one
    routing hook in `WindowManager`; NullPlayer's EQ window serves beside every skin); its other
    windows join docking and snapping (`SkinAuxiliaryWindows`). Whether they are open is the
    session's, carried across a skin switch in one step of `present`; a launch's restore waits for
    the first skin (`deferUntilSkinLoads`).
- **Skins:** Skins › AIMP lists `Application Support/NullPlayer/AIMPSkins` (`AIMPSkinImporter`,
  selection key `aimpSkinName`). A `.zip` is bounded before it is written (`AIMPSkinZipLimits`,
  `AM0012`). A name is one skin: installing `X.acs4` replaces `X.acs5`, of two left from before
  `.acs5` lists, and removing the name removes every file of it.

## Shared code

AIMP keeps its own copies of helpers other families have, rather than sharing them: the owner's
choice, so that AIMP stays apart from shared code and Classic, Original, `.wal`, `.wmz`, Audion
and Sonique stay exactly as upstream has them. They are `AIMPSkinArtworkLoader` (WMP's
`WMPArtworkLoader`), the EQ preset apply in `AIMPSkinMainWindowController+Menus` (WMP's
`eq.currentPreset`), `AIMPSkinMenuItem`, `AIMPSkinDroppedMedia` (the classic and Modern windows'
drop handlers) and `AIMPSkinImporter`'s catalogue (Sonique's importer). Outside AIMP's folders the
branch adds only what the family cannot run without: its `PlayerUIMode`/`PlayerUIControllerFamily`
case in the exhaustive switches, its menu entries, and the `SkinDrawnLists`/`SkinAuxiliaryWindows`
hook in `MainWindowProviding` and `WindowManager`. Merging any copy with the other families' is
offered to the maintainer as a follow-up, not done here.

## The rule that outranks everything

**AIMP work must never change Classic, Original, `.wal`, `.wmz`, Audion or Sonique behaviour.**
Shared code gates on `controllerFamily == .aimp`. `skin-subsystem-blueprint` § *The rule that
outranks everything*.

## What kind of engine this is

- **Markup plus script, reverse-engineered.** Forms are trees of layout items and controls; behaviour
  is bindings with expressions, providers, and FastScript (Pascal) scripts.
- **Bitmap skins** (tape decks) are layout and state; **modern skins** (Soot) depend on scripts,
  `AutoHide` and cover art.
- **No oracle.** AIMP is Windows-only. The reference is the skin's catalog screenshot; a diff against
  it is evidence, not ground truth (blueprint § *A sweep diff is unclassified*).

## Symptom → file

| Symptom | Read |
|---|---|
| A skin fails to load, or an `AM####` code | `reference/loading.md` |
| A container, image or document decodes wrong | `reference/format.md` |
| Something drawn in the wrong place or not at all | `reference/layout.md` |
| Any measurement: a probe flag, the load gate, the census | `reference/harness.md` |
| An engine-wide change, or a named skin | `reference/skins/README.md` |
| What to build next | `tasks/AIMP_TASKS.md` |

## Debugging a live defect

Applies to anything that only reproduces on screen. Route to `skills/live-ui-testing` for the
method and `skills/app-control` for the mechanics; this is the AIMP half.

1. Reproduce it headless first: the window draws exactly what the probe renders
   (`AIMPSkinRenderer.frame`). A defect that shows in the probe's PNG is a renderer defect.
2. A key, timer or script that seems to do nothing: run the app with `AIMP_ACTION_TRACE=1` and read
   whether the action reached the player. An unmapped one logs
   `AIMPSkin: no NullPlayer action for '<action>'` once.
3. A loop or flood only the window shows: `AIMP_RENDER_LIVE=1` (`reference/harness.md`).
4. Launch the debug build on the skin:

```bash
skills/app-control/scripts/launch.sh aimp:28_Kenwood_KX-800 --no-play
```

**Confirm it took:** `LAUNCH PASS: aimp skin '<name>'`. The launcher writes `aimpSkinName` in the
debug domain (`NullPlayer`); it quits any running `NullPlayer` first, the installed app included.
