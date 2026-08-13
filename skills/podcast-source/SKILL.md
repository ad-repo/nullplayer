# Podcast Source

## Overview

NullPlayer exposes podcasts as a source in the existing Library Browser for both Classic and Modern UI modes. Both hosts embed the shared SwiftUI `PodcastBrowserView`; the theme is supplied by each host so Modern remains independent from Classic skin code.

Podcast directory discovery uses PodcastIndex.org. Authenticated API requests send `User-Agent`, `X-Auth-Key`, `X-Auth-Date`, and the Podcast Index SHA-1 authorization digest. Credentials are stored in the macOS Keychain. Search also supports Podcast Index's public search endpoint when no credentials are configured. Episode loading falls back to the podcast's RSS/Atom feed.

## Key Files

- `Sources/NullPlayer/Podcast/PodcastModels.swift`: feed, episode, subscription, and playback-state models
- `Sources/NullPlayer/Podcast/PodcastIndexClient.swift`: Podcast Index client and RSS/Atom parser
- `Sources/NullPlayer/Podcast/PodcastStore.swift`: subscriptions, downloads, favorites, progress, OPML, and Track conversion
- `Sources/NullPlayer/Podcast/PodcastBrowserView.swift`: shared cover-tile and episode interface
- `Windows/PlexBrowser/PlexBrowserView.swift`: Classic host
- `Windows/ModernLibraryBrowser/ModernLibraryBrowserView.swift`: Modern host

## Playback and Playlist Contract

Episodes become ordinary `Track` values and enter the shared `AudioEngine` through `playNow`, `insertTracksAfterCurrent`, or `appendTracks`. Audio episodes use `.audio`; video enclosures use `.video` and route through the shared video player. The content-type override is `podcast` or `video-podcast`, which prevents finite remote enclosures from being treated as live radio.

Keep `artworkThumb`, `contentType`, `mediaType`, and the podcast content-type override when changing playlist state persistence. These fields are required for artwork, video routing, and correct casting after an app restart.

## Storage

Subscriptions, known episodes, favorites, playback progress, and downloaded paths are stored in the shared SQLite `library.db` using `podcast_subscriptions`, `podcast_episodes`, and `podcast_episode_states`. Schema v9 migrates existing databases and `PodcastStore` performs a one-time import of the former `NullPlayer/Podcasts/library.json`, then archives that file with a `.migrated` suffix. Downloaded enclosures remain below `NullPlayer/Podcasts/Downloads`. Podcast Index API credentials must remain in Keychain and must not be added to SQLite or UserDefaults.

## Casting

Remote episode enclosure URLs cast directly. Downloaded episodes use `LocalMediaServer`. Generic remote cover URLs are passed as cast metadata. Video playlist tracks must use `castVideoTrack`, not the URL-only overload, so media type, artwork, and source metadata survive the route.

## Verification

Run `swift test` and `swift build`. Manual QA should cover search with and without Podcast Index credentials, RSS addition, subscription/OPML management, audio and video playback, playlist restore, downloads, and Chromecast/DLNA casting.
