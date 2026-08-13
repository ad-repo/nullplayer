# Podcast Player Handoff

## Branch

- Local branch: `feat/podcast-player`
- Base: `origin/main` at `cd18ea6fa0e8ddc2c9bf6f86202473de3379ebbb`
- The branch was created directly from the fetched remote main branch.

## Scope Implemented

- Added Podcasts as a first-class Library source in the classic and modern browsers.
- Added Podcast Index discovery, search, trending feeds, credentials, and direct RSS feed support.
- Added cover-tile browsing, subscriptions, refresh, auto-download, favorites, played state, resume progress, downloads, OPML import/export, and a sleep timer.
- Added audio and video podcast playback through the existing audio/video paths.
- Added podcast episodes to Play Next, playlists, restored playlists, Now Playing metadata, and casting.
- Added Libraries > Podcasts commands for opening Podcasts and Podcast Index settings.
- Used semantic classic and modern skin colors throughout the shared podcast browser.
- Avoided ellipsis characters in podcast command names and followed the existing source/model naming conventions.

## Persistence

Podcast library data is stored in the shared `library.db` at schema version 9:

- `podcast_subscriptions`
- `podcast_episodes`
- `podcast_episode_states`

The previous podcast JSON snapshot is imported once when the database contains no podcast data, then archived with a `.migrated` suffix. Podcast Index credentials remain in Keychain. Downloaded enclosure media remains in Application Support rather than being stored as database blobs.

`PodcastEpisode.persistedID` and `persistedFeedID` preserve stable identities during database round trips. `Track.podcastEpisodeID` preserves the episode identity through playback and application-state playlist restoration.

## CPU Regression and Main-Thread Constraint

An earlier implementation put podcast work in the global 10 Hz audio-time callback. It initialized `PodcastStore`, scanned the known episode catalog, published state, and could write SQLite even when ordinary music was playing. The original schema v9 migration also rebuilt the entire `play_events` table to change its source constraint. Both paths could affect users who had never opened Podcasts.

The current implementation removes those behaviors:

- Ordinary non-podcast playback performs only an optional `podcastEpisodeID` check and does not initialize any podcast singleton.
- Podcast progress uses the stable episode ID and never scans the catalog.
- Progress submissions are throttled before work is queued.
- Podcast schema setup, database loading, legacy JSON migration, snapshot writes, progress writes, OPML file I/O, and download file operations run off the main actor.
- `PodcastPersistenceCoordinator` serializes persistence on a utility queue.
- Progress updates modify only playback-owned columns, preserving favorite and downloaded-file state.
- Snapshot saves merge the latest queued playback progress so a UI action cannot overwrite newer resume data.
- Schema v9 only creates the podcast tables. It does not rebuild `play_events`.
- Podcast analytics use source `local` with `content_type` set to `podcast` or `video-podcast`, avoiding a play-history constraint migration.

The UI model remains `@MainActor`, as required by AppKit/SwiftUI, but no podcast database or filesystem operation is performed there.

## Primary Files

- `Sources/NullPlayer/Podcast/PodcastBrowserView.swift`
- `Sources/NullPlayer/Podcast/PodcastIndexClient.swift`
- `Sources/NullPlayer/Podcast/PodcastModels.swift`
- `Sources/NullPlayer/Podcast/PodcastPersistenceCoordinator.swift`
- `Sources/NullPlayer/Podcast/PodcastStore.swift`
- `Sources/NullPlayer/Data/Models/MediaLibraryStore.swift`
- `Sources/NullPlayer/Data/Models/Track.swift`
- `Sources/NullPlayer/App/AppStateManager.swift`
- `Sources/NullPlayer/App/ContextMenuBuilder.swift`
- `Sources/NullPlayer/Windows/ModernLibraryBrowser/ModernLibraryBrowserView.swift`
- `Sources/NullPlayer/Windows/PlexBrowser/PlexBrowserView.swift`
- `Tests/NullPlayerAppTests/PodcastTests.swift`
- `skills/podcast-source/SKILL.md`

## Validation Status

Completed before the final small persistence cleanup:

- `swift build` passed.
- The complete test suite passed: 437 tests, 0 failures.
- Podcast tests passed: 7 tests, 0 failures.
- Media-library migration tests passed: 3 tests, 0 failures.

Afterward, two small changes ensured database initialization for restored podcast playback and removed an unused state-save method. A targeted test rerun was interrupted because compilation caused unacceptable CPU load. Per user direction, no further build, test, or app launch was performed. The exact committed tree therefore still needs one final low-impact validation pass in an appropriate environment.

Static verification completed on the committed tree:

- `git diff --check` passed.
- No NullPlayer, Astral, Swift compiler, or test-runner process was left running.

## Recommended Follow-up

1. Validate the exact commit in CI or another environment where a Swift rebuild will not disrupt the workstation.
2. Manually verify first launch from a schema v8 database with a large `play_events` table; migration should create only the three podcast tables and return quickly.
3. Play ordinary local and streaming music while confirming no podcast persistence work appears.
4. Verify audio/video podcast playback, resume progress, playlist restore, downloads, and Chromecast/Sonos/DLNA behavior.
5. Check several classic and modern skins for semantic text/background contrast.

