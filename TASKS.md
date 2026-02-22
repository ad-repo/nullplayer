# Artist in search → navigate to Artists tab

## Completed
- [x] Add `pendingScrollToArtistId` property and `navigateToArtistFromSearch` helper
- [x] Single-click on artist in search navigates to Artists tab (handleListClick early-exit)
- [x] Add `applyPendingArtistScroll()` hooked into all 5 artist build functions (Plex/Subsonic/Jellyfin/Emby/Local)
- [x] Fix: `.localArtist` added to handleListClick search-mode early-exit
- [x] Fix: name fallback + case-insensitive match in applyPendingArtistScroll
- [x] Fix: don't clear pending state on failed lookup (attempt counter, give up after 3)
- [x] Fix: clear view-level artist caches to force fresh fetch on navigation
- [x] Fix: add `pendingArtistLoadUnfiltered` flag — when navigating from search, bypass folder/library filter
  - Added `fetchArtistsUnfiltered()` to SubsonicManager, JellyfinManager, EmbyManager
  - Plex: bypasses preload cache, calls fetchArtists() fresh (uses currentLibrary)
  - Subsonic: fetches all artists across all music folders (musicFolderId: nil)
  - Jellyfin: fetches all artists across all music libraries (libraryId: nil)
  - Emby: fetches all artists across all music libraries (libraryId: nil)
- [x] Build verified — no compile errors
