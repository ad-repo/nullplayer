# Track History for Plex Radio

## Phase 1 — Core Database Layer
- [x] Create `Sources/NullPlayer/Plex/PlexRadioHistory.swift` with SQLite schema, CRUD, HTML generation

## Phase 2 — Recording Hooks
- [x] Modify `AudioEngine.swift` — add `recordTrackPlayed` calls in `trackDidFinish`, `completeCrossfade`, `completeStreamingCrossfade`

## Phase 3 — Radio Filtering
- [x] Modify `PlexManager.swift` — add `applyRadioFilters` helper, replace all `filterForArtistVariety` calls (12 calls + 3 early-return paths)

## Phase 4 — Menu UI
- [x] Modify `ContextMenuBuilder.swift` — add Plex Radio History submenu + `MenuActions` methods

## Phase 5 — Web Server Routes
- [x] Modify `LocalMediaServer.swift` — add `GET /radio-history` and `POST /radio-history/delete/*` routes

## Phase 6 — Build Verification
- [x] Run `swift build -c release` and confirm clean compile
