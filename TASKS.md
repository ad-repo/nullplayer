# Library Keyboard Navigation (Issue #114)

## Phase 1 — keyDown Handler Additions
- [x] Add Right Arrow (124): expand item or move to first child
- [x] Add Left Arrow (123): collapse item or jump to parent
- [x] Add Tab (48) / Shift+Tab: cycle browse tabs
- [x] Add Space (49): play/pause

## Phase 2 — Playlist Support in Shift+Enter / Option+Enter
- [x] Add .subsonicPlaylist, .jellyfinPlaylist, .embyPlaylist, .plexPlaylist to playNextSelected()
- [x] Add .subsonicPlaylist, .jellyfinPlaylist, .embyPlaylist, .plexPlaylist to addSelectedToQueue()

## Phase 3 — Remove Auto-Play on Empty Playlist Enqueue
- [x] Remove wasEmpty / playTrack(at: 0) from all cases in addSelectedToQueue()

## Phase 4 — Album Sort by Year When Enqueueing Artist
- [x] Sort albums by year (asc) in artist cases of playNextSelected()
- [x] Sort albums by year (asc) in artist cases of addSelectedToQueue()

## Phase 5 — Type-Ahead Search
- [x] Add typeAheadQuery and typeAheadTimer properties
- [x] Handle alphanumeric input in non-search tabs (jump to first match)
- [x] Handle Backspace and Escape for type-ahead buffer

## Phase 6 — Build Verification
- [x] Run swift build -c release and confirm clean compile
