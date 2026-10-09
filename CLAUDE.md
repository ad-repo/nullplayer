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

- `ui-guide`: UI geometry/rendering; `audio-system`: playback/EQ; `app-state`: restoration and persistence; `user-guide`: features and menus
- `skin-subsystem-blueprint`: adding/extending a skin family — shared seams, isolation, harness, docs layout.
  `.wal` and `.wmz` are clean-room reverse engineering: a sweep diff there is unclassified, not a
  regression — it may be newly unlocked behaviour (Classic/Original diffs are always regressions)
- `original-skin-guide`: Original skins; `winamp-modern-skin-guide`: `.wal` support, a slim router over `reference/`; `wal-skin-report`: `/wal-skin-report <skin.wal>`
- `wmp-skin-guide`: Windows Media Player `.wmz`/`.wms` loading, rendering, scripting, menus, state, and WMP-owned windows
- `audion-face-guide`: Panic Audion faces — a FaceKit port with a FaceKit oracle, so a diff against the oracle is a defect
- `plex-integration`, `jellyfin-integration`, `subsonic-integration`, `emby-integration`: media servers
- `sonos-casting`, `chromecast-casting`: casting protocols and debugging
- `stream-ripper`: URL ripping; `youtube-source`: YouTube audio; `cue-sheets`: cue playback/splitting; `radio-streaming`: radio
- `visualizations`: visualizer router; `main-window-visualization`: inline vis; `spectrum-analyzer-window`: analyzer; `audio-analysis-window`: analysis panes
- `peppymeter`: analog VU; `cava`: bar spectrum; `flow`: network meter; `gpu-vis-modes`: shaders; `album-art-visualizer`: Art window
- `projectm-milkdrop`: MilkDrop; `metal-gotchas`: Metal rules
- `geiss-port`, `tripex-port`, `vis-classic-guide`: visualization ports and compatibility
- `app-control`: launching, configuring, driving and measuring the running app; test-data targets
- Backlogs live in `tasks/`: `WMP_TASKS.md` (`.wmz`), `WINAMP5_TASKS.md` (`.wal`), `AUDION_TASKS.md`
  (Audion faces), plus `docs/local-library/backlog.md` (library scanning and playlist playback)
- `live-ui-testing`: process skill for screen-only defects — instrument first, drive the app yourself, measure what is drawn
- `testing`: UI test workflows; `non-retina-fixes`: 1x display fixes; `local-library`: SQLite and scanning; `cli`: headless mode
- `skin-screenshots`: per-skin main-window captures across all skin systems, and slideshow GIFs
- `window-census`: every sub-window's default size and position, per skin or across the corpus
- `thermo-nuclear-code-quality-review`: the strict maintainability lens every code review uses

## Architecture

```text
Sources/NullPlayer/
├── App/, Windows/                         App lifecycle and UI
├── Audio/, Casting/                       Playback, EQ, and casting
├── StreamRipper/, Radio/                  Downloading and radio
├── Skin/, ModernSkin/, WinampModern/       Skin engines
├── Plex/, Subsonic/, Jellyfin/, Emby/      Server integrations
└── Visualization/, Cava/, PeppyMeter/, Waveform/, Models/  Visuals and models
```

## Key Source Files

- App: `App/WindowManager.swift`, `App/AppStateManager.swift`, `App/ContextMenuBuilder.swift`
- Classic skin: `Skin/SkinElements.swift`, `Skin/SkinRenderer.swift`, `Skin/SkinLoader.swift`
- Audio: `Audio/AudioEngine.swift`, `Audio/StreamingAudioPlayer.swift`
- Windows: `Windows/MainWindow/`, `Windows/ModernMainWindow/`, and sibling feature-window roots
- Models/local library: `Models/Track.swift`, `Models/Playlist.swift`, `Data/Models/MediaLibrary.swift`, `Utilities/LocalFileDiscovery.swift`

## Common Tasks

- Add context-menu items in `App/ContextMenuBuilder.swift`; add main-menu items in `App/AppDelegate.swift`.
- To add a window: create its `Windows/` folder, add its controller and view, register it in `WindowManager.swift`, and add an `App/` provider protocol when classic and modern implementations share behavior.
- For a NullPlayer-owned window that should inherit `.wal` chrome, use the hosted-window registry path; see `winamp-modern-skin-guide/reference/components.md`.

## Before Making UI Changes

1. Read `ui-guide`.
2. Check `Skin/SkinElements.swift` for classic sprite coordinates.
3. Test multiple UI sizes and skins.

## Writing Code

Settle the structure before writing; it is cheap now and expensive once review finds it.

- Put logic in the layer that already owns the concept and reuse its helpers; the owning skill names both.
- No special-case conditionals scattered through shared or busy paths; a mode or feature check belongs
  at the one seam where the paths split.
- No pass-through wrappers, near-duplicate helpers, or optionals and casts that paper over an unclear invariant.
- Don't add a new concern to a file already past ~1,000 lines; give it its own file.
- Keep the change to the task. A restructuring beyond it is proposed, not done — review is where
  the ambitious rework gets weighed, with `thermo-nuclear-code-quality-review` (vendored from
  cursor/plugins under MIT; user-invoked).

## Testing

Run `swift test`. For UI or playback work, manually exercise local and server playback, radio, multiple skins, docking, visualizations, casting, and relevant window sizes.

## Rules

- No Spotify, Apple Music, or Amazon Music integrations; they are explicitly not accepted.
- `ModernSkin/` and `Windows/Modern*/` must never import from `Skin/` or `Windows/MainWindow/`; see `original-skin-guide`.
- Winamp Modern (`.wal`) work must never change Classic or Original behavior. This binds shared
  code too — a change in `App/` that both modes run is gated on the mode, not justified by
  reasoning that it "should be a no-op"; see `winamp-modern-skin-guide`.
- Skin sprites use a top-left origin; macOS uses bottom-left. See `ui-guide`.
- Slicing `Data` preserves original indices; always use `data.startIndex`.
- Read the owning skill before changing a subsystem. Put new subsystem details in that skill, never here.
- For a defect that only reproduces on screen, read `live-ui-testing` before diagnosing, and
  `winamp-modern-skin-guide/reference/harness.md` § *Debugging a live defect* — the reference
  implementation of that workflow. Every subsystem skill must carry a *Debugging a live defect*
  section routing there; a new subsystem adds one on day one. See `skin-subsystem-blueprint`.
- Never diff against local `main` — it goes stale and silently sweeps other people's merged work
  into the result. Review and diff a branch against `origin/main` (`git fetch origin` first, then
  `git diff origin/main...HEAD`); for a PR, take the diff from `gh pr diff <N>`, which is
  authoritative about the base. A branch that merged main in makes a stale-base diff look like a
  huge legitimate changeset, so confirm the file list matches `gh pr view <N> --json files`.
