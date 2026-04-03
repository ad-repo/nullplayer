# Playback Flows and Integrations

This document covers shuffle playback behavior, Plex Radio/Mix, Subsonic/Jellyfin streaming details, and Now Playing integration.

## Shuffle Playback

Shuffle behavior is centralized in `AudioEngine` and is intentionally stateful.

### Stable Shuffle Cycle

NullPlayer does not pick a new random index on every natural advance anymore. Instead it builds a shuffle cycle:

1. `shufflePlaybackOrder` stores a full permutation of playlist indices
2. `shufflePlaybackPosition` tracks the current position inside that order
3. Natural playback advance, gapless prep, crossfade transitions, cast auto-advance, and manual next/previous all consult the same cycle state

This guarantees that a track is not repeated during shuffle until the cycle is exhausted.

### Repeat + Shuffle

When `repeatEnabled` and `shuffleEnabled` are both on:

- The current cycle still runs to completion before a new order is used
- The next cycle is reshuffled only after the current one is exhausted
- The reshuffle avoids immediately repeating the just-finished track when possible

### Explicit Track Selection Under Shuffle

Choosing a specific track while shuffle is enabled resets the active cycle around that selection instead of preserving the old order. This prevents a stale order from making playback appear to "walk backward" from a manually chosen last track.

### Queue Replacement and Queue Insertion

The shuffle entry points have slightly different rules:

- `loadTracks(_:)` builds a new shuffle cycle for the replaced playlist and starts from the selected shuffled index
- `playNow(_:)` and empty-queue `insertTracksAfterCurrent(_:)` start from a shuffled track inside the inserted range, not index `0`
- Preferred inserted indices are exhausted before older queue entries when those APIs seed shuffle with a preferred range

This is what the library/browser actions such as "Play Album and Replace Queue" and "Play Now" rely on.

## Plex Radio/Mix

NullPlayer supports Plex radio features, allowing you to generate dynamic playlists based on a seed track, album, or artist.

### Accessing Radio Features

Right-click on any Plex track, album, or artist in the browser:

| Item Type | Menu Option | Description |
|-----------|-------------|-------------|
| Track | "Start Track Radio" | Plays sonically similar tracks based on the seed track |
| Album | "Start Album Radio" | Plays tracks from sonically similar albums |
| Artist | "Start Artist Radio" | Plays tracks from sonically similar artists |

### How It Works

Uses Plex's sonic analysis API to find similar content:

1. **Track Radio**: Uses `track.sonicallySimilar={trackID}` filter with random sorting
2. **Album Radio**: Fetches sonically similar albums, then gets tracks from each
3. **Artist Radio**: Fetches sonically similar artists, then gets tracks from each

### Technical Requirements

Full radio functionality requires:

- **Plex Pass** subscription (for sonic analysis features)
- **Plex Media Server v1.24.0+** (64-bit)
- **Sonic analysis enabled** on the server for the music library

Tracks with sonic analysis have a `musicAnalysisVersion` attribute in their metadata.

### API Endpoints

| Endpoint | Purpose |
|----------|---------|
| `/library/sections/{libraryID}/all?type=10&track.sonicallySimilar={id}` | Fetch sonically similar tracks |
| `/library/sections/{libraryID}/all?type=9&album.sonicallySimilar={id}` | Fetch sonically similar albums |
| `/library/sections/{libraryID}/all?type=8&artist.sonicallySimilar={id}` | Fetch sonically similar artists |

### Radio Playlist Size

By default, radio playlists include up to 100 tracks with `sort=random` for variety.

## Subsonic/Navidrome Streaming

NullPlayer supports streaming music from Subsonic-compatible servers (including Navidrome). This uses the same HTTP streaming pipeline as Plex.

### SubsonicManager

The `SubsonicManager` singleton handles:
- Server connection management (multiple servers supported)
- Library content caching (artists, albums, playlists)
- Track conversion to AudioEngine-compatible format
- Credential storage via KeychainHelper

### SubsonicServerClient

Handles all Subsonic REST API communication:
- **Token authentication**: `md5(password + salt)` per request
- **API version**: 1.16.1 (widely compatible)
- **Endpoints**: getArtists, getAlbum, stream, search3, playlists, star/unstar, scrobble

### Scrobbling

The `SubsonicPlaybackReporter` reports playback activity to the Subsonic server:

| Event | Report Type | Description |
|-------|-------------|-------------|
| Track starts | `submission=false` | "Now playing" indicator |
| 50% played OR 4 minutes | `submission=true` | Track marked as played |

Standard scrobbling rules: track is scrobbled when played 50% or 4 minutes, whichever comes first.

### Track Model Integration

Subsonic items include identifiers in the Track model:

```swift
struct Track {
    // ... other properties ...
    let subsonicId: String?       // Song ID for scrobbling (nil for non-Subsonic)
    let subsonicServerId: String? // Which server the track belongs to
}
```

### Stream URLs

Stream URLs include authentication parameters:
```
http://server/rest/stream?id=SONG_ID&u=USERNAME&t=TOKEN&s=SALT&v=1.16.1&c=NullPlayer
```

**Note:** The `f=json` parameter is intentionally omitted from stream URLs. It should only be used for REST API calls that return JSON - stream endpoints return binary audio data.

### Casting to Sonos

When casting Subsonic content to Sonos speakers, streams are proxied through LocalMediaServer:

1. Sonos has issues with URLs containing query parameters (authentication tokens)
2. Navidrome may be bound to localhost, unreachable by Sonos speakers
3. The proxy provides a clean URL: `http://{mac-ip}:8765/stream/{token}`
4. LocalMediaServer fetches from Navidrome and streams to Sonos (no transcoding)

### API Endpoints

| Endpoint | Purpose |
|----------|---------|
| `ping` | Test server connection |
| `getArtists` | Fetch artist list (indexed A-Z) |
| `getArtist` | Get artist details + albums |
| `getAlbum` | Get album details + tracks |
| `getAlbumList2` | Browse albums (various sorts) |
| `search3` | Full-text search |
| `stream` | Get audio stream for a track |
| `getCoverArt` | Get artwork image |
| `getPlaylists` / `getPlaylist` | Playlist management |
| `star` / `unstar` | Favorite items |
| `getStarred2` | Get all favorites |
| `scrobble` | Report playback |

## Jellyfin Integration

### JellyfinPlaybackReporter

The `JellyfinPlaybackReporter` reports playback activity to the Jellyfin server using the Sessions API:

| Event | Endpoint | Description |
|-------|----------|-------------|
| Track starts | `POST /Sessions/Playing` | "Now playing" indicator |
| Position updates | `POST /Sessions/Playing/Progress` | Periodic progress reports |
| 50% played OR 4 minutes | `POST /Users/{userId}/PlayedItems/{itemId}` | Track marked as played |
| Track stops | `POST /Sessions/Playing/Stopped` | Playback ended |

Same scrobbling rules as Subsonic. Jellyfin uses ticks for position (1 tick = 10,000 nanoseconds).

### Track Model Integration

Jellyfin items include identifiers in the Track model:

```swift
struct Track {
    // ... other properties ...
    let jellyfinId: String?       // Item ID for scrobbling (nil for non-Jellyfin)
    let jellyfinServerId: String? // Which Jellyfin server the track belongs to
}
```

## Plex Play Statistics

When playing Plex content, NullPlayer reports playback activity back to the Plex server. This enables:

- **Play count tracking** - Tracks are marked as "played" and count increments
- **Last played date** - Server records when you last listened/watched
- **Now Playing** - Shows what's playing in other Plex clients
- **Continue watching** - Resume playback where you left off (videos)

### PlexPlaybackReporter

The `PlexPlaybackReporter` singleton manages all Plex reporting:

```swift
// Automatic integration - no manual calls needed
// AudioEngine calls the reporter at appropriate playback events:
- trackDidStart()    // When a Plex track begins playing
- trackDidPause()    // When playback is paused
- trackDidResume()   // When playback resumes
- trackDidStop()     // When playback stops or track finishes
- updatePosition()   // Called every 100ms for progress tracking
```

### Timeline Updates

Periodic updates are sent to Plex every **10 seconds** during playback:
- Current playback position
- Playing/paused/stopped state
- Enables "Now Playing" in Plex dashboard

### Scrobbling

A track is marked as "played" (scrobbled) when:
1. Track reaches **90% completion**, OR
2. Track finishes naturally (reaches the end)

**AND** at least **30 seconds** have been played (prevents accidental scrobbles from quick skips).

### API Endpoints

| Endpoint | Purpose |
|----------|---------|
| `/:/timeline` | Report playback state and position |
| `/:/scrobble` | Mark item as played |
| `/:/unscrobble` | Mark item as unplayed |
| `/:/progress` | Update resume position |

### Track Model Integration

Plex items include a `plexRatingKey` property in the Track model:

```swift
struct Track {
    // ... other properties ...
    let plexRatingKey: String?  // nil for local files
}
```

The reporter checks for this key and only reports for Plex content.

### PlexVideoPlaybackReporter

The `PlexVideoPlaybackReporter` singleton manages Plex reporting for **video content** (movies and TV episodes):

```swift
// Automatic integration - VideoPlayerWindowController calls the reporter:
- movieDidStart()      // When a Plex movie begins playing
- episodeDidStart()    // When a Plex episode begins playing
- videoDidPause()      // When video playback is paused
- videoDidResume()     // When video playback resumes
- videoDidStop()       // When video playback stops or finishes
- updatePosition()     // Called during playback for progress tracking
```

**Video Scrobbling Rules:**
- Video is marked as "watched" when reaching **90% completion** or finishing naturally
- Minimum **60 seconds** of playback required (prevents accidental scrobbles)
- Reports `type: "movie"` or `type: "episode"` to distinguish video from audio

**Video Integration:**
- `VideoPlayerWindowController.play(movie:)` - Starts tracking for movies
- `VideoPlayerWindowController.play(episode:)` - Starts tracking for TV episodes
- Non-Plex videos (local files) are not reported

## Now Playing Integration

NullPlayer reports playback information to macOS via `MPNowPlayingInfoCenter`, enabling:
- Discord Music Presence (https://github.com/ungive/discord-music-presence)
- macOS Control Center media controls
- Touch Bar controls
- Bluetooth headphone controls (AirPods, etc.)

The integration is managed by `NowPlayingManager` in `Sources/NullPlayer/App/NowPlayingManager.swift`.

### Reported Metadata
- Title, Artist, Album
- Duration and elapsed time
- Album artwork (loaded asynchronously)
- Playback state (playing/paused/stopped)

### Remote Commands Supported
- Play, Pause, Toggle Play/Pause
- Next Track, Previous Track
- Seek to position (scrubbing)
