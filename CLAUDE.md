# Agent Guide

## Quick Start

```bash
./scripts/bootstrap.sh      # Download frameworks (first time)
./scripts/kill_build_run.sh # Build and run
skills/app-control/scripts/launch.sh <skin>  # Debug build on a given skin, verified — agents always use this
./scripts/build_dmg.sh      # Build distributable DMG
swift test                  # Run unit tests
```

See `docs/development-workflow.md` for build details, log monitoring, and versioning.

## Skills

Technical documentation lives in `skills/`. Read the owning skill before changing a subsystem.

- `ui-guide`: UI geometry/rendering; `audio-system`: playback/EQ; `eq-profiles`: EQ Profiles, the Equalizer Studio and EQ Cast; `app-state`: restoration and persistence; `user-guide`: features and menus
- `skin-triage`: the canonical order for triaging, fixing and verifying one reported skin defect in any family, with a fill-in record
- `skin-intake`: runs a corpus intake batch (admit → triage → promote → PR), owns its progress ledger (`scripts/wal_intake_status.sh`) and is the only route to editing `corpus-runner-plan.md`
- `skin-subsystem-blueprint`: adding/extending a skin family — shared seams, isolation, harness, docs layout.
  `.wal` and `.wmz` are clean-room reverse engineering: a sweep diff there is unclassified, not a
  regression — it may be newly unlocked behaviour (Classic, Original, Audion and Sonique have a
  fixed reference, so a diff there is a defect)
- `original-skin-guide`: Original skins; `winamp-modern-skin-guide`: `.wal` support, a slim router over `reference/`; `wal-skin-report`: `/wal-skin-report <skin.wal>`
- `wmp-skin-guide`: Windows Media Player `.wmz`/`.wms` loading, rendering, scripting, menus, state, and WMP-owned windows
- `audion-face-guide`: Panic Audion faces — a FaceKit port with a FaceKit oracle, so a diff against the oracle is a defect
- `sonique-skin-guide`: Sonique `.sgf` skins — the decoded format, the corpus, and real Sonique under Wine as the oracle
- `plex-integration`, `jellyfin-integration`, `subsonic-integration`, `emby-integration`: media servers
- `sonos-casting`, `chromecast-casting`: casting protocols and debugging; `cast-testing`: live CLI casting checks against the LAN's TVs
- `stream-ripper`: URL ripping; `youtube-source`: YouTube audio; `cue-sheets`: cue playback/splitting; `radio-streaming`: radio; `video-playback`: the shared video path and window
- `visualizations`: visualizer router; `main-window-visualization`: inline vis; `spectrum-analyzer-window`: analyzer; `audio-analysis-window`: analysis panes
- `peppymeter`: analog VU; `cava`: bar spectrum; `flow`: network meter; `gpu-vis-modes`: shaders; `album-art-visualizer`: Art window
- `projectm-milkdrop`: MilkDrop; `metal-gotchas`: Metal rules
- `geiss-port`, `tripex-port`, `vis-classic-guide`: visualization ports and compatibility
- `app-control`: launching, configuring, driving and measuring the running app; test-data targets
- `live-ui-testing`: process skill for screen-only defects — instrument first, drive the app yourself, measure what is drawn
- `testing`: UI test workflows; `non-retina-fixes`: 1x display fixes; `local-library`: SQLite and scanning; `cli`: headless mode; `nullplayer-release`: cutting a release
- `skin-screenshots`: per-skin main-window captures across all skin systems, and slideshow GIFs
- `window-census`: every sub-window's default size and position, per skin or across the corpus
- `thermo-nuclear-code-quality-review`: the strict maintainability lens every code review uses

## Logging Issues

`tasks/` is where agents log defects, gaps and follow-ups they find: a row in the owning backlog,
never a new file, a code comment, or prose handed back. (GitHub issues are for users and for the
issue a PR must link; see `CONTRIBUTING.md`.)

- `WMP_TASKS.md` (`.wmz`), `WINAMP5_TASKS.md` (`.wal`), `AUDION_TASKS.md` (Audion faces),
  `SONIQUE_TASKS.md` (`.sgf`), and `MISC_TASKS.md` for everything else, including the local library.
  Classic and Original have no backlog of their own; their rows go in `MISC_TASKS.md`.
- Read the file's header before adding a row: it says how a row is numbered and laid out, and where
  closed rows go (usually that family's archive, in the change that closes them).
- A row is reproducible work with measured evidence. A one-off that stops reproducing goes in the
  owning skill; a row with a defect in the row itself goes to `LOW_QUALITY_TASKS.md`.

## Architecture

```text
Sources/NullPlayer/
├── App/, Windows/                         App lifecycle and UI
├── Audio/, Casting/                       Playback, EQ, and casting
├── StreamRipper/, Radio/                  Downloading and radio
├── Skin/, ModernSkin/, WinampModern/, WMPSkin/, AudionFace/, SoniqueSkin/  Skin engines
├── Plex/, Subsonic/, Jellyfin/, Emby/      Server integrations
├── Visualization/, Cava/, PeppyMeter/, Waveform/  Visuals
└── Data/Models/, Utilities/               Models and local library
```

## Key Source Files

- App: `App/WindowManager.swift`, `App/AppStateManager.swift`, `App/ContextMenuBuilder.swift` (context menus), `App/AppDelegate.swift` (main menu)
- Classic skin: `Skin/SkinElements.swift`, `Skin/SkinRenderer.swift`, `Skin/SkinLoader.swift`
- Audio: `Audio/AudioEngine.swift`, `Audio/StreamingAudioPlayer.swift`
- Windows: `Windows/MainWindow/`, `Windows/ModernMainWindow/`, and sibling feature-window roots
- Models/local library: `Data/Models/Track.swift`, `Data/Models/Playlist.swift`, `Data/Models/MediaLibrary.swift`, `Utilities/LocalFileDiscovery.swift`

## Before Making UI Changes

1. Read `ui-guide`.
2. Check `Skin/SkinElements.swift` for classic sprite coordinates.

## Writing Code

Settle the structure before writing; it is cheap now and expensive once review finds it.

- Put logic in the layer that already owns the concept and reuse its helpers; the owning skill names both.
- No special-case conditionals scattered through shared or busy paths; a mode or feature check belongs
  at the one seam where the paths split.
- No pass-through wrappers, near-duplicate helpers, or optionals and casts that paper over an unclear invariant.
- Don't add a new concern to a file already past ~1,000 lines; give it its own file.
- Keep the change to the task. A restructuring beyond it is proposed, not done — review is where
  the ambitious rework gets weighed, with `thermo-nuclear-code-quality-review`.

## Before a PR

Every PR is preceded by a `thermo-nuclear-code-quality-review` of the whole branch (against
`origin/main`, plus uncommitted changes), run by a fresh agent (new subagent or session, never a
fork), never the author agent; the user accepts or rejects each finding before any is fixed. The
skill's *Invoking the Pre-PR Review* has the procedure and what the PR description's **Code quality
review** section lists. A PR without that section is not ready to open; `CONTRIBUTING.md` carries
the same requirement for outside contributors.

## Testing

For UI or playback work, in addition to `swift test`, manually exercise local and server playback, radio, multiple skins, docking, visualizations, casting, and relevant window sizes.

## Rules

- No Spotify, Apple Music, or Amazon Music integrations; they are explicitly not accepted.
- **Never look at Winamp, Wasabi or Windows Media Player source code** — leaked, "released",
  mirrored or quoted, on GitHub or anywhere else — and never download it. Skin support is clean-room:
  the evidence is the skin's own files, its screenshots, and observed behaviour. If a search turns
  up such source, do not open it; if any was fetched, delete it and say so.
  AVS (grandchild/vis_avs, BSD-3) is a vendored visualizer, not skin code, and is exempt.
- `ModernSkin/` and `Windows/Modern*/` must never import from `Skin/` or `Windows/MainWindow/`; see `original-skin-guide`.
- A fix for one skin family (Classic, Original, `.wal`, `.wmz`, Audion, Sonique) must not
  unintentionally change another. This binds shared code too — a change in `App/` that every
  family runs is gated on `controllerFamily`, not justified by reasoning that it "should be a
  no-op"; see `skin-subsystem-blueprint`. A change that deliberately affects more than one family
  (a shared bug fix, a shared-code refactor) needs the user's explicit permission first: name the
  families and what changes for each, then wait.
- Skin sprites use a top-left origin; macOS uses bottom-left. See `ui-guide`.
- Slicing `Data` preserves original indices; always use `data.startIndex`.
- Put new subsystem details in the owning skill, never here.
- For a defect that only reproduces on screen, read `live-ui-testing` before diagnosing, and
  `winamp-modern-skin-guide/reference/harness.md` § *Debugging a live defect* — the reference
  implementation of that workflow. A new subsystem skill carries a *Debugging a live defect*
  section routing there from day one; see `skin-subsystem-blueprint`.
- Never diff against local `main` — it goes stale and silently sweeps other people's merged work
  into the result. Review and diff a branch against `origin/main` (`git fetch origin` first, then
  `git diff origin/main...HEAD`); for a PR, take the diff from `gh pr diff <N>`, which is
  authoritative about the base. A branch that merged main in makes a stale-base diff look like a
  huge legitimate changeset, so confirm the file list matches `gh pr view <N> --json files`.
