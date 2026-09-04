# Agent Guide

## Quick Start

```bash
./scripts/bootstrap.sh      # Download frameworks (first time)
./scripts/kill_build_run.sh # Build and run
./scripts/build_dmg.sh      # Build distributable DMG
swift test                  # Run unit tests
```

See `docs/development-workflow.md` for build details, log monitoring, and versioning.

## Skills

Technical documentation lives in `skills/`. Read the owning skill before changing a subsystem.

- `ui-guide`: UI geometry/rendering; `audio-system`: playback/EQ; `app-state`: restoration and persistence; `user-guide`: features and menus
- `original-skin-guide`: Original skins; `winamp-modern-skin-guide`: `.wal` support, a slim router over `reference/`; `wal-skin-report`: `/wal-skin-report <skin.wal>`
- `plex-integration`, `jellyfin-integration`, `subsonic-integration`, `emby-integration`: media servers
- `sonos-casting`, `chromecast-casting`: casting protocols and debugging
- `stream-ripper`: URL ripping; `youtube-source`: YouTube audio; `cue-sheets`: cue playback/splitting; `radio-streaming`: radio
- `visualizations`: visualizer router; `main-window-visualization`: inline vis; `spectrum-analyzer-window`: analyzer; `audio-analysis-window`: analysis panes
- `peppymeter`: analog VU; `cava`: bar spectrum; `flow`: network meter; `gpu-vis-modes`: shaders; `album-art-visualizer`: ART effects
- `projectm-milkdrop`: MilkDrop; `metal-gotchas`: Metal rules
- `geiss-port`, `tripex-port`, `vis-classic-guide`: visualization ports and compatibility
- `testing`: UI test workflows; `non-retina-fixes`: 1x display fixes; `local-library`: SQLite and scanning; `cli`: headless mode

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

<!-- dgc-policy-v11 -->
# Dual-Graph Context Policy

This project uses a local dual-graph MCP server for efficient context retrieval.

## MANDATORY: Always follow this order

1. **Call `graph_continue` first** — before any file exploration, grep, or code reading.

2. **If `graph_continue` returns `needs_project=true`**: call `graph_scan` with the
   current project directory (`pwd`). Do NOT ask the user.

3. **If `graph_continue` returns `skip=true`**: project has fewer than 5 files.
   Do NOT do broad or recursive exploration. Read only specific files if their names
   are mentioned, or ask the user what to work on.

4. **Read `recommended_files`** using `graph_read` — **one call per file**.
   - `graph_read` accepts a single `file` parameter (string). Call it separately for each
     recommended file. Do NOT pass an array or batch multiple files into one call.
   - `recommended_files` may contain `file::symbol` entries (e.g. `src/auth.ts::handleLogin`).
     Pass them verbatim to `graph_read(file: "src/auth.ts::handleLogin")` — it reads only
     that symbol's lines, not the full file.
   - Example: if `recommended_files` is `["src/auth.ts::handleLogin", "src/db.ts"]`,
     call `graph_read(file: "src/auth.ts::handleLogin")` and `graph_read(file: "src/db.ts")`
     as two separate calls (they can be parallel).

5. **Check `confidence` and obey the caps strictly:**
   - `confidence=high` -> Stop. Do NOT grep or explore further.
   - `confidence=medium` -> If recommended files are insufficient, call `fallback_rg`
     at most `max_supplementary_greps` time(s) with specific terms, then `graph_read`
     at most `max_supplementary_files` additional file(s). Then stop.
   - `confidence=low` -> Call `fallback_rg` at most `max_supplementary_greps` time(s),
     then `graph_read` at most `max_supplementary_files` file(s). Then stop.

## Token Usage

A `token-counter` MCP is available for tracking live token usage.

- To check how many tokens a large file or text will cost **before** reading it:
  `count_tokens({text: "<content>"})`
- To log actual usage after a task completes (if the user asks):
  `log_usage({input_tokens: <est>, output_tokens: <est>, description: "<task>"})`
- To show the user their running session cost:
  `get_session_stats()`

Live dashboard URL is printed at startup next to "Token usage".

## Rules

- Do NOT use `rg`, `grep`, or bash file exploration before calling `graph_continue`.
- Do NOT do broad/recursive exploration at any confidence level.
- `max_supplementary_greps` and `max_supplementary_files` are hard caps - never exceed them.
- Do NOT dump full chat history.
- Do NOT call `graph_retrieve` more than once per turn.
- After edits, call `graph_register_edit` with the changed files. Use `file::symbol` notation (e.g. `src/auth.ts::handleLogin`) when the edit targets a specific function, class, or hook.

## Context Store

Whenever you make a decision, identify a task, note a next step, fact, or blocker during a conversation, call `graph_add_memory`.

**To add an entry:**
```
graph_add_memory(type="decision|task|next|fact|blocker", content="one sentence max 15 words", tags=["topic"], files=["relevant/file.ts"])
```

**Do NOT write context-store.json directly** — always use `graph_add_memory`. It applies pruning and keeps the store healthy.

**Rules:**
- Only log things worth remembering across sessions (not every minor detail)
- `content` must be under 15 words
- `files` lists the files this decision/task relates to (can be empty)
- Log immediately when the item arises — not at session end

## Session End

When the user signals they are done (e.g. "bye", "done", "wrap up", "end session"), proactively update `CONTEXT.md` in the project root with:
- **Current Task**: one sentence on what was being worked on
- **Key Decisions**: bullet list, max 3 items
- **Next Steps**: bullet list, max 3 items

Keep `CONTEXT.md` under 20 lines total. Do NOT summarize the full conversation — only what's needed to resume next session.
