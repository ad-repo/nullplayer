---
name: youtube-source
description: YouTube channel uploads in the Radio tab — browse channels, download audio (FLAC / MP3) ad-free, store in a user folder, and play/cast locally. Use when working on YouTube source UI, channel/video listing, download scheduling, manifest tracking, or quality settings.
---

# YouTube Source

Subscribe to YouTube channels in the **Radio tab** and browse their uploads. Double-click a video to **download its audio** (ad-free, via `yt-dlp`) and play immediately. Downloads are stored in a **user-chosen folder** (reachability checked before downloading) as deterministic `<videoId>.<ext>` files, tracked in a manifest; a **quality setting** (FLAC / MP3 High / MP3 Low) is in the Library menu. Downloaded files are local `file://` tracks, so they play locally and cast to Sonos, Chromecast, DLNA like any other track.

## Quick Start (user)

1. **Radio tab** → **+ Add YouTube Channel**
2. Paste a YouTube channel URL (e.g., `https://www.youtube.com/@channel_name`)
3. Channel appears as a folder; expand to see uploads
4. Double-click a video to download its audio and play
5. **Library → Set Download Folder…** to choose where downloads live
6. **Library → YouTube Quality** to pick FLAC, MP3 High, or MP3 Low

## Architecture

```
Sources/NullPlayer/
├── YouTube/
│   ├── YouTubeModels.swift          # Channel, Video data models
│   ├── YouTubeManager.swift         # Singleton managing channels and manifest
│   ├── YouTubeManifestStore.swift   # youtube_downloads.json tracking
│   └── YouTubeDownloader.swift      # Download via StreamRipper.downloadAudio
├── Windows/ModernLibraryBrowser/
│   └── ModernLibraryBrowserView.swift # YouTube folder tree integration
└── Windows/PlexBrowser/
    └── PlexBrowserView.swift        # YouTube folder tree integration (classic UI)
```

### YouTubeManager

Singleton (`YouTubeManager.shared`) that manages:
- Channel list (persisted in the manifest)
- Current playable state (expanded channels + video list)
- Download root folder (user-selected via Library menu)
- Active downloads queue
- Manifest synchronization

**Key Properties:**
```swift
var channels: [YouTubeChannel]       // All subscribed channels
var downloadRootURL: URL?             // User-chosen folder (checked for reachability)
var qualitySetting: Quality           // FLAC / MP3 High / MP3 Low
var activeDownloads: Set<String>      // Video IDs currently downloading
```

**Notifications:**
- `channelsDidChangeNotification` — Channel list modified
- `downloadDidCompleteNotification` — Video download finished
- `downloadRootDidChangeNotification` — Download folder changed

### Data Models

```swift
struct YouTubeChannel: Identifiable, Codable {
    let id: String                    // Channel ID from URL
    var name: String
    var channelURL: URL
    var lastFetched: Date?
    var videoCount: Int?
}

struct YouTubeVideo: Identifiable, Codable {
    let id: String                    // Video ID
    var title: String
    var channelId: String
    var duration: TimeInterval?
}
```

### Manifest (`youtube_downloads.json`)

Stored inside `downloadRootURL`, tracks downloaded files:

```json
{
  "version": 1,
  "channels": [
    {
      "id": "UCxxx",
      "name": "Channel Name",
      "channelURL": "https://www.youtube.com/@channel_name",
      "lastFetched": "2026-06-20T15:30:00Z"
    }
  ],
  "downloads": [
    {
      "videoId": "dQw4w9WgXcQ",
      "title": "Video Title",
      "localPath": "file:///path/to/dQw4w9WgXcQ.flac",
      "downloadedAt": "2026-06-20T15:25:00Z",
      "quality": "flac"
    }
  ]
}
```

### Channel / Video Listing

Both `ModernLibraryBrowserView` and `PlexBrowserView` (classic UI) integrate YouTube as a **source branch** alongside internet radio stations. Channels appear as expandable folders; expanding a channel calls `YouTubeManager.fetchUploads(channel:)` which shells out to `yt-dlp --flat-playlist` with no API key:

```bash
yt-dlp --flat-playlist --print-json "id" "title" "duration" \
  "https://www.youtube.com/@channel_name/videos"
```

Videos appear as indented child rows. Double-clicking a video triggers `YouTubeDownloader.downloadAndPlay(video:)`.

### Download Flow

1. **Reachability Check**: Verify `downloadRootURL` is accessible (mounted NAS, etc.)
2. **Download**: Reuse `StreamRipper.downloadAudio(videoURL:quality:)` (via `resolveTool`) to download the video's best audio
3. **Deterministic Naming**: Save as `<videoId>.<ext>` (extension from yt-dlp output)
4. **Manifest Update**: Append entry to `youtube_downloads.json`
5. **Track Creation**: Construct a local `Track(url:)` from the manifest entry
6. **Playback**: Load the track into the audio engine and play

### Library Menu Integration

**Library → YouTube Quality**
- Off-by-one FLAC / MP3 High / MP3 Low setting stored in UserDefaults
- Consulted before each download; affects `StreamRipper.downloadAudio` format argument

**Library → Set Download Folder…**
- Opens `NSOpenPanel` for directory selection
- Validates reachability before storing
- Creates `youtube_downloads.json` on first write
- Persists in UserDefaults as `youtubeDownloadRootURL`

### UI Mode Support

YouTube channels appear identically in:
- **Modern LibraryBrowserView** (right-side tree, expandable channel folders + indented video rows)
- **Classic PlexBrowserView** (left sidebar + table view, same folder/row structure as radio stations)

Both reuse existing `BrowserSource` / `ModernBrowserSource` enum routing.

### Casting

Downloaded files are local `file://` tracks. After download completes, the `Track` object is passed to the audio engine's normal playback path:
- **Local playback**: Direct file read
- **Sonos**: Track wrapped as a playable item (local file URL → proxy URL if needed)
- **Chromecast / DLNA**: URL is reachable from the remote renderer via local HTTP server (FlyingFox)

## Gotchas

- **No API key / YouTube account required**: Uses `yt-dlp --flat-playlist` which scrapes the public channel uploads page (no authentication)
- **Video list is flat**: `--flat-playlist` does not recurse; it only lists the channel's uploads. Playlists, live streams, and videos from other channels are not included unless explicitly in the uploads view
- **Download folder reachability**: NAS-aware check via `URLResourceValues.volumeIdentifier` before queuing; a disconnected mount fails gracefully without blocking the UI
- **Manifest is line-of-business**: Direct JSON file writes; no SQLite. Corruption or missing entries are rare but unrecoverable (keep off user-visible data)
- **Quality setting is global**: One `quality` setting applies to all future downloads; past downloads retain their own `quality` field in the manifest
- **Streaming playback not offered**: YouTube streams (live, members-only, age-restricted) may fail silently if yt-dlp can't extract them; only downloadable videos are listed
- **Video titles from yt-dlp**: Source of truth is yt-dlp's title extraction; titles are not synced with YouTube's API and may differ from what the web UI shows
