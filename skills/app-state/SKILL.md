---
name: app-state
description: NullPlayer session-state restoration, AppStateManager, AppPersistence edition scoping, and reset paths. Use when adding a persisted preference, changing launch restoration, or working on custom editions.
---

# App State

## Remember State On Quit

`AppStateManager` saves and restores session state (v2) for window visibility and layout, audio and EQ state, and playlist contents. It intentionally does not save or restore the selected or current track, seek position, or playing state, so launch starts paused with no track loaded solely because state was restored.

Restore state in two phases: settings first with `restoreSettingsState`, then the playlist with `restorePlaylistState`. Load streaming tracks as placeholder `Track` objects, then replace them asynchronously through `engine.replaceTrack(at:with:)`.

Restore UI scale and window frames only when the saved and running `PlayerUIMode` values match exactly. Modern and Metal do not match. On a mismatch, use 100% scale and default frames while still restoring non-geometry state.

`AppPersistence.key(_:)` scopes only `rememberStateEnabled`, `savedAppState`, and legacy `*WindowFrame` keys for custom editions. Other content preferences remain shared.

When adding state:

- Keep durable preferences in `UserDefaults`.
- Put quit-session state in the `AppState` struct and decode additions with `decodeIfPresent` defaults.
- Do not move every `UserDefaults` key into `AppState`.
- Expose a reset path for any durable preference that can trap users in a hard-to-recover state.

`Reset Saved State...` clears only the current edition's saved `AppState` blob. `VisualizationPreferences` owns visualization preference resets.
