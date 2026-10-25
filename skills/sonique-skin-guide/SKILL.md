---
name: sonique-skin-guide
description: Sonique 1.x (.sgf) skin family — public since Phase 2: the three modes, the navigator's screens and the drawer drawn and driven. The decoded .sgf container and skin.ini, the corpus and census, and the Wine-hosted Sonique 1.96 oracle that captures real Sonique drawing any skin. Use before starting Sonique skin work, when reading an .sgf, or when comparing against what Sonique itself drew.
---

# Sonique skins

Read this skill before starting Sonique (`.sgf`) skin work. The locked decisions are
`docs/sonique/phase-0-decision-record.md`; the backlog is `tasks/SONIQUE_TASKS.md`. The family
pattern every engine follows is `skin-subsystem-blueprint`.

**Status:** Phase 1 (the spike) closed 2026-10-17, Phase 2 2026-10-18; public since then
(decision record Amendment 5), behind `AppFeature.soniqueSkinMode` for editions only. `Sources/NullPlayer/SoniqueSkin/` holds the bounded loader and model,
`SoniqueSkinScene` (layout and hit-testing, drawn from one `SoniqueSkinScene.State` the window keeps; its
inputs in `SoniqueSkinSceneState.swift`, the visual mode screen's layout in `SoniqueSkinVisualScreen.swift`;
`skin.ini` geometry read through `SoniqueSkinSettings`' typed accessors, never a key string) and `SoniqueSkinRenderer` (the modes, the navigator's screens, Sonique's glyphs and its lettering, `SoniqueSkinText`, each in its own `SoniqueSkinRenderer*.swift`); `Windows/SoniqueSkin/` the
one window in three modes. `PlayerUIMode.sonique` routes it. The harness is a census, a render probe
and an oracle: real Sonique 1.96 under Wine, scripted to capture any skin in any mode
(`reference/harness.md`), and the oracle sweep measures every skin's render against it
(`docs/sonique/oracle-baseline.tsv`).

## The rule that outranks everything

**Sonique work must never change Classic, Original, `.wal`, `.wmz` or Audion behaviour.** A change in
shared code (`App/WindowManager.swift` above all) is gated on `controllerFamily == .sonique`, never
justified by reasoning that it "should be a no-op". A Classic or Original diff is a regression by
definition. `skin-subsystem-blueprint` § *The rule that outranks everything* is the worked version.

## What kind of engine this is

- **A fixed UI, re-textured.** No markup, no script. A skin supplies three mode pictures, lit button
  states, animation strips, pre-rasterised hit and window shapes, and ~25 colours. Sonique's own code
  draws the navigator's screens and the text; the skin only colours them (`reference/format.md`).
- **The oracle is a running Sonique, not source.** Sonique is closed source and no reimplementation
  exists. A capture from the oracle is what Sonique drew; a diff against it is evidence, as with
  Audion's FaceKit oracle, but it covers the default state of each mode only.
- **The oracle settles how it looks, never how it works.** Every control behaves as NullPlayer's does
  in every other skin: its range, units and steps are NullPlayer's (the pitch knob spans NullPlayer's
  0.25×–4×, not Sonique's 50–200 %). Never drive the oracle to measure a behaviour; decision record
  § *Decisions*.
- **The navigator's screens are not to be cloned pixel for pixel.** The menu keeps Sonique's layout
  and colours with NullPlayer's items; visual mode hosts the shared effects surface (S16); playlist and
  library are NullPlayer's windows beside the player; the drawer is the equaliser. **The other skin
  families are the template:** a surface the skin draws itself never gets a NullPlayer window too
  (NullPlayer's EQ window never opens here; WMP's `revealSkinSurface` is the model). What must look
  like Sonique is bounded: the menu screen, status line, progress rings, knob strips and the drawer.
  Locked in `docs/sonique/phase-0-decision-record.md` § *Decisions*; changing it means amending that
  record.

## Isolation boundary

| Rule | Where |
|---|---|
| Engine and model: pure, no AppKit windows | `Sources/NullPlayer/SoniqueSkin/` |
| AppKit: controller, windows, views | `Sources/NullPlayer/Windows/SoniqueSkin/` |
| Shared files | only through a gated seam, recorded in this skill |

- **The equaliser seam:** `SkinDrawnEqualizer` (`App/MainWindowProviding.swift`). Only
  `SoniqueSkinMainWindowController` conforms, so the conformance is the family gate: `WindowManager`
  sends every Equalizer show and toggle, and `isEqualizerVisible`, to the drawer
  (`routeSkinDrawnEqualizer`). A mode switch closes NullPlayer's EQ window, so none survives into
  the family.

- Never teach another family's types about `.sgf`; never share a loader with another family.
- Never use another family's artwork as a default. A skin that omits an entry falls back to that
  entry in NullPlayer's own default Sonique skin (S11), drawn on Sonique's default layout; Sonique's
  own default artwork lives in `Sonique.exe` and is never shipped.
- No Sonique or Lycos artwork, executables or docs in the repo, fixtures included. Fixtures are
  synthesised in the test that uses them.
- Parsing and JPEG decode run off the main thread; `MainActor` receives a completed immutable skin.

## Where everything lives

| Symptom or change | Read |
|---|---|
| an `.sgf` entry, a region, a `skin.ini` key, what a skin can change | [reference/format.md](reference/format.md) |
| a skin that will not load, an `SQ####` code, a limit | decision record § *Loading limits*; `SoniqueSkinPolicy` is its executable source |
| the corpus, the census, the oracle, capturing what Sonique drew | [reference/harness.md](reference/harness.md) |
| how far the renderer is from the oracle, per skin and mode; the committed ratchet | [reference/harness.md](reference/harness.md) § *The oracle sweep* |
| what to work on next | `tasks/SONIQUE_TASKS.md` |

## Debugging a live defect

Read **`skills/live-ui-testing`** before diagnosing anything that only reproduces on screen, and the
process section it points at — `winamp-modern-skin-guide/reference/harness.md`
§ *Debugging a live defect*. Launching, driving and capturing NullPlayer are `app-control`'s.

What is specific to this family:

1. **Capture the same skin and mode through the oracle first** (`reference/harness.md`). If Sonique
   draws it the same way, the report is about Sonique's behaviour, not a defect.
2. **Check `0x000000` before suspecting a shape.** Pure black is transparent in every picture, so a
   hole may be the artwork, not the region.
3. **A window edge off by a few pixels may be Wine's.** The oracle's outline passes through Wine's
   shape conversion, which moves runs that lie inside one byte (`reference/harness.md`
   § *Outline comparison*); compare against `wine_shape`, not the raw capture.
4. **A still capture proves the default state only.** The mode morph, the drawer slide and the
   progress rings filling need the live app beside a running oracle.
