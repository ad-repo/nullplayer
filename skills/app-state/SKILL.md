---
name: app-state
description: NullPlayer session-state restoration, AppStateManager, AppPersistence edition scoping, and reset paths. Use when adding a persisted preference, changing launch restoration, or working on custom editions.
---

# App State

## Remember State On Quit

`AppStateManager` saves and restores session state (v2) for window visibility and layout, audio and EQ state, and playlist contents. It intentionally does not save or restore the selected or current track, seek position, or playing state, so launch starts paused with no track loaded solely because state was restored.

Remember State is **on by default** (`register(defaults:)`; an explicit menu choice wins). Saving is not
only on quit: power loss, a crash or a force quit never reach `applicationWillTerminate`, so the
launch calls `startAutosave` from the `restoreSettingsState` completion in `AppDelegate`, once both
restores have applied — every 10 s, plus before system sleep and power-off. Never start it earlier: it
would overwrite the saved session with the empty launch state.

`saveState` only *captures* the session on the main thread: the playlist and radio stations are
copied as value-type arrays, so that part costs the same however long the playlist is (~2 ms in a
debug build at 1,000 or 20,000 tracks). Turning tracks into `SavedTrack`s, encoding, comparing and
writing run on the serial `saveQueue` — encoding 20,000 tracks is ~33 ms in debug, which used to run
on the main thread every tick. `SavedTrack.from` therefore takes the radio stations instead of reading
`RadioManager`. Quit, sleep and power-off use `saveStateAndWait`, because the process may not run
again. The write happens, and is logged, only when the encoded state changed (`.sortedKeys`, or
dictionary order defeats the check), so idle ticks write nothing. `clearSavedState` runs on
`saveQueue` after any queued save, and forgets the last-written copy so the next save writes.

EQ is saved per band layout (`eqBandsByLayout`, the engine's `canonicalGains`: `classic10` for Classic,
`.wal` and `.wmz`, `modern21` for Original and Metal) and restored through
`AudioEngine.restoreEQGains`, so each family keeps its exact curve across a relaunch in the other.
`canonicalGains` is the source of truth for the live node, not a cache: `programEQNode` records the
curve it applies, so the active layout always has an entry, and `setEQBand` writes both. Never read
gains back from `eqNode` to save them. `eqBands` (the active layout only, copied from the same
dictionary) is still written because older builds decode it as required; a state without
`eqBandsByLayout` is upgraded on decode from `eqBands`. The layouts a session can hold are
`EQConfiguration.persistedLayouts`.

Restore state in two phases: settings first with `restoreSettingsState`, then the playlist with `restorePlaylistState`. Load streaming tracks as placeholder `Track` objects, then replace them asynchronously through `engine.replaceTrack(at:with:)`.

Restore UI scale and window frames only when the saved and running `PlayerUIMode` values match exactly. Modern and Metal do not match. On a mismatch, use 100% scale and default frames while still restoring non-geometry state.

`AppPersistence.key(_:)` scopes only `rememberStateEnabled`, `savedAppState`, and legacy `*WindowFrame` keys for custom editions. Other content preferences remain shared.

When adding state:

- Keep durable preferences in `UserDefaults`.
- Put quit-session state in the `AppState` struct and decode additions with `decodeIfPresent` defaults.
- Do not move every `UserDefaults` key into `AppState`.
- Expose a reset path for any durable preference that can trap users in a hard-to-recover state.

`Reset Saved State...` clears only the current edition's saved `AppState` blob. `VisualizationPreferences` owns visualization preference resets.

## A restored main-window *size* the skin cannot render is discarded

Restoration runs several seconds after a `.wal` skin has already sized the player to its own layout,
so it overwrites the skin. `mainFrameForRestore` guards the case where the frame was saved under a
**different** skin — but a frame saved under the *same* skin, in a session where that skin failed to
load, is trusted, and restoring it is what the next save records. It perpetuates itself.

cPro2 Dark Aluminum is the measured case: it graded *did not load* until B93 (2026-09-01), so every
frame it ever persisted is the unskinned 275×116 default, and the player reopened in a 275×200 box
over the skin's own 800×600 on every launch.

The signal is already being computed. If `clampRestoredFrame` has to change the saved **size** to make
it legal for the current skin, that size was never one this skin had — so keep the window's own size
and honour only the saved position. Gated on `uiMode == .winampModern`: the Classic and Original
windows are not sized by a skin's layout, so the signal does not exist there and their behaviour is
untouched. Self-healing — the first good frame saved is used from then on.

When a skin's own layout owns a window's size, treat "the saved value needed correcting" as evidence
the value is stale, not as something to clamp and use.
