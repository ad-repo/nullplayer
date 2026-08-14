---
name: podcast-source
description: Podcast directory search, subscriptions, RSS feeds, episode playback, persistence, downloads, playlist conversion, casting, and Library-browser integration. Use when changing NullPlayer's Podcasts source or Podcast Index behavior.
---

# Podcast Source

## Overview

NullPlayer exposes podcasts as a source in the existing Library Browser for both Classic and Modern UI modes. Both hosts embed the shared SwiftUI `PodcastBrowserView`; the theme is supplied by each host so Modern remains independent from Classic skin code.

Podcast directory discovery uses PodcastIndex.org. Authenticated API requests send `User-Agent`, `X-Auth-Key`, `X-Auth-Date`, and the Podcast Index SHA-1 authorization digest. Credentials are stored in the macOS Keychain. Search also supports Podcast Index's public search endpoint when no credentials are configured. Episode loading falls back to the podcast's RSS/Atom feed.

## Browser Integration and Navigation

The source is user-facing **Podcasts** everywhere. `Podcast Index` is the directory provider and may appear in search placeholders and credential settings, but it must not be used as the Library source or source-menu label. Both Classic and Modern source menus place a separator between YouTube and Podcasts.

`PodcastBrowserView` uses a search-led navigation model:

- The initial screen is the subscriptions shelf with one full-width directory search field.
- Submitting a non-empty query calls `PodcastStore.search`, closes an open feed, switches to `.discover`, and displays the result grid.
- Search mode shows a Back chevron beside the search field. Back clears the local query and calls `showSubscriptions()`, which cancels search work, closes feed detail, and restores `.subscriptions`.
- Selecting a feed opens episode detail; its own Back control closes the feed and returns to the current shelf or search results.
- Do not automatically load trending feeds during store startup or after saving credentials. Search mode should represent an explicit user query.
- Keep the podcast toolbar focused on search/navigation. Podcast Index credentials remain available through **Libraries > Podcasts > Podcast Index Settings**.

The shared view is hosted only when the Library source is Podcasts and the radio-slot browse mode is active. Compact Playlist mode must hide the podcast hosting view; otherwise its opaque background can remain beneath the translucent embedded playlist.

## Key Files

- `Sources/NullPlayer/Podcast/PodcastModels.swift`: feed, episode, subscription, and playback-state models
- `Sources/NullPlayer/Podcast/PodcastIndexClient.swift`: Podcast Index client and RSS/Atom parser
- `Sources/NullPlayer/Podcast/PodcastStore.swift`: subscriptions, downloads, favorites, progress, OPML, and Track conversion
- `Sources/NullPlayer/Podcast/PodcastBrowserView.swift`: shared cover-tile and episode interface
- `Sources/NullPlayer/Windows/PlexBrowser/PlexBrowserView.swift`: Classic host
- `Sources/NullPlayer/Windows/ModernLibraryBrowser/ModernLibraryBrowserView.swift`: Modern host

## Playback and Playlist Contract

Episodes become ordinary `Track` values and enter the shared `AudioEngine` through `playNow`, `insertTracksAfterCurrent`, or `appendTracks`. Audio episodes use `.audio`; video enclosures use `.video` and route through the shared video player. The content-type override is `podcast` or `video-podcast`, which prevents finite remote enclosures from being treated as live radio.

Keep `artworkThumb`, `contentType`, `mediaType`, and the podcast content-type override when changing playlist state persistence. These fields are required for artwork, video routing, and correct casting after an app restart.

## Storage

Subscriptions, known episodes, favorites, playback progress, and downloaded paths are stored in the shared SQLite `library.db` using `podcast_subscriptions`, `podcast_episodes`, and `podcast_episode_states`. Schema v9 migrates existing databases and `PodcastStore` performs a one-time import of the former `NullPlayer/Podcasts/library.json`, then archives that file with a `.migrated` suffix. Downloaded enclosures remain below `NullPlayer/Podcasts/Downloads`. Podcast Index API credentials must remain in Keychain and must not be added to SQLite or UserDefaults.

## Casting

Remote episode enclosure URLs cast directly. Downloaded episodes use `LocalMediaServer`. Generic remote cover URLs are passed as cast metadata. Video playlist tracks must use `castVideoTrack`, not the URL-only overload, so media type, artwork, and source metadata survive the route.

## Verification

Run `swift test` and `swift build`. Manual QA should cover:

- The source menu reads **Podcasts**, with a separator between YouTube and Podcasts, in Classic and Modern/Metal.
- The subscriptions shelf appears first; submitting search enters results and Back returns to subscriptions.
- Search works with and without Podcast Index credentials and does not preload trending results.
- Opening and closing feed detail preserves the expected shelf/search context.
- Compact Playlist mode does not leave the podcast host or its background visible beneath the queue.
- RSS addition, subscription/OPML management, audio and video playback, playlist restore, downloads, and Chromecast/DLNA casting continue to work through their remaining menu/action entry points.
