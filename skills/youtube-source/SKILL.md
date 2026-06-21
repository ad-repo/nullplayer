---
name: youtube-source
description: YouTube channel uploads in the Radio tab — browse channels, download audio (FLAC / MP3) ad-free, store in a user folder, and play/cast locally. Use when working on YouTube source UI, channel/video listing, downloads, manifest tracking, or quality settings.
---

# YouTube Source

Subscribe to YouTube channels in the **Radio tab** and browse their uploads. Double-click a video to **download its audio** (ad-free, via `yt-dlp`) and play immediately. Downloads are stored in a **user-chosen folder** (reachability checked before downloading), organized per channel as `<Channel Name>/<Title> [<videoId>].<ext>` and tracked in a manifest; a **quality setting** (FLAC / MP3 High / MP3 Low) is in the Library menu. Downloaded files are local `file://` tracks, so they play locally and cast to Sonos, Chromecast, DLNA like any other track.

## Quick Start (user)

1. **Radio tab** → **+ Add YouTube Channel**
2. Paste a YouTube channel URL (e.g., `https://www.youtube.com/@channel_name`)
3. Channel appears as a folder; expand to see uploads
4. Double-click a video to download its audio and play
5. **Library → Set Download Folder…** to choose where downloads live
6. **Library → YouTube Quality** to pick FLAC, MP3 High, or MP3 Low

## Architecture

```text
Sources/NullPlayer/
├── YouTube/
│   ├── YouTubeModels.swift          # Channel, Video, Download, Quality data models
│   └── YouTubeManager.swift         # Singleton: channels, video listing, downloads, manifest (youtube_downloads.json), all in one file
├── Windows/ModernLibraryBrowser/
│   └── ModernLibraryBrowserView.swift # YouTube folder tree integration
└── Windows/PlexBrowser/
    └── PlexBrowserView.swift        # YouTube folder tree integration (classic UI)
```

### YouTubeManager

Singleton (`YouTubeManager.shared`) that manages:
- Channel list (persisted in UserDefaults under `YouTubeChannels`)
- Video listing per channel (via yt-dlp)
- Download root folder (user-selected via Library menu, persisted under `YouTubeDownloadRoot`)
- Download manifest (`youtube_downloads.json` in the download root)

**Key Properties:**
```swift
private(set) var channels: [YouTubeChannel]  // All subscribed channels
var downloadRoot: URL                        // User-chosen folder (reachability checked before download)
var quality: YouTubeQuality                  // .flac / .mp3High / .mp3Low (persisted under "YouTubeQuality")
```

**Notifications:**
- `YouTubeManager.youtubeChannelsDidChangeNotification` — Channel list modified (the only notification)

### Data Models

```swift
struct YouTubeChannel: Codable, Identifiable, Hashable {
    let id: String       // Normalized channel key (handle or channel ID)
    let title: String
    let url: URL         // Base channel URL (e.g. https://www.youtube.com/@handle)
    let dateAdded: Date
}

struct YouTubeVideo: Codable, Identifiable, Hashable {
    let videoId: String
    let title: String
    let channelId: String
    let duration: TimeInterval?
    let uploadDate: String?
    var id: String { videoId }      // Identifiable
    var watchURL: URL { ... }       // https://www.youtube.com/watch?v=<videoId>
}

struct YouTubeDownload: Codable {
    let videoId: String
    let title: String
    let channelId: String
    let fileName: String            // Path relative to downloadRoot (channel/file)
}
```

### Manifest (`youtube_downloads.json`)

Stored inside `downloadRoot`, tracks downloaded files (the in-memory form is a `[videoId: YouTubeDownload]` dictionary; serialized JSON shape below):

A JSON dictionary keyed by `videoId`, each value a `YouTubeDownload`. `fileName` is a path **relative to `downloadRoot`** (`<Channel Name>/<Title> [<videoId>].<ext>`):

```json
{
  "dQw4w9WgXcQ": {
    "videoId": "dQw4w9WgXcQ",
    "title": "Video Title",
    "channelId": "channel_handle",
    "fileName": "Channel Name/Video Title [dQw4w9WgXcQ].flac"
  }
}
```

### Channel / Video Listing

Both `ModernLibraryBrowserView` and `PlexBrowserView` (classic UI) integrate YouTube as a **source branch** alongside internet radio stations. Channels appear as expandable folders; expanding a channel calls `YouTubeManager.videos(forChannel:limit:)` which shells out to `yt-dlp --flat-playlist` with no API key:

```bash
yt-dlp --flat-playlist -J --playlist-end 50 \
  "https://www.youtube.com/@channel_name/videos"
```

`-J` dumps a single JSON object; `parseFlatPlaylist` decodes its `entries` (each `id`/`title`/`duration`/`upload_date`) into `YouTubeVideo`s. Channel title on add comes from a separate `--playlist-end 1` fetch (`fetchChannelTitle`).

Videos appear as indented child rows. Double-clicking a video triggers `YouTubeManager.downloadAudio(video:)` (then the browser loads the returned local file into the audio engine and plays it).

#### Column rendering (Channels tab)

Video (leaf) rows render through the **established resizable-column path** (`drawColumnRow`), not the simple list path, so a long title truncates inside its column instead of printing over the time. The column set is:

```swift
static let youtubeColumns: [ModernBrowserColumn] = [.title, .duration]  // .duration is titled "Time"
```

- A dedicated **`.youtube` case in `LibraryColumnVisibilityGroup`** namespaces the persisted widths (`youtube:title`, `youtube:duration`) so they survive `migrateColumnWidths`. This is why the internet-radio column path can't be reused: `internetRadioColumns` are deliberately **non-resizable** (`hitTestColumnResize` early-returns when `hasInternetRadioColumns`), and the requirement here is a movable Time column like the library tabs.
- **Channel (parent) rows stay on the simple-list path** so they keep their ▶/▼ expand arrows; only video rows use columns — mirroring radio folders vs. stations.
- Column headers appear only once a channel is expanded (video rows exist), gated by `hasYouTubeColumns` (`radioSlotShowingChannels` + any `.youtubeVideo` in `displayItems`).
- Clicking a header sorts via **`applyYouTubeColumnSort`** — an in-place sort of each contiguous run of video rows (leaving channel leaders put), mirroring `applyInternetRadioColumnSort`.
- Plumbing touched: `columnGroup(for:)`, `currentColumnGroup()`, `columnsForItem`, `currentVisibleColumns`, `headerColumnsForCurrentContent`, `columnValue`, plus the four `allColumns`/`defaultColumnIds`/`visibleColumnIds`/`setVisibleColumnIds` group switches. Adding the `.youtube` enum case also forces the exhaustive switches in classic `PlexBrowserView` to handle it (return empty / no-op — YouTube is modern-UI only).

### Download Flow

1. **Reachability Check**: Verify `downloadRoot` is accessible (mounted NAS, etc.)
2. **Download**: `YouTubeManager.downloadAudio(video:)` builds the format/output args and delegates to `StreamRipper.downloadAudio(from:formatArgs:outputTemplate:)` to download the video's best audio
3. **Channel folder + readable name**: Save under a per-channel subfolder as `<Channel Name>/<Title> [<videoId>].<ext>` (yt-dlp sanitizes the title and picks the extension; the bracketed video ID keeps names unique). The manifest stores this as a `fileName` path relative to `downloadRoot`.
4. **Manifest Update**: Append entry to `youtube_downloads.json`
5. **Track Creation**: Construct a local `Track(url:)` from the manifest entry
6. **Playback**: Load the track into the audio engine and play

### Library Menu Integration

Both menus are built in `ContextMenuBuilder.swift` (`setYouTubeQuality(_:)`, `setYouTubeDownloadFolder`).

**Library → YouTube Quality**
- Three-way FLAC / MP3 High / MP3 Low setting, persisted in UserDefaults under `YouTubeQuality`
- Consulted before each download (`quality.ytdlpArgs`); shapes the format args passed to `StreamRipper.downloadAudio`

**Library → Set Download Folder…**
- Opens `NSOpenPanel` for directory selection
- Validates reachability before storing
- `youtube_downloads.json` is written lazily on the first recorded download, not on folder selection
- Persists in UserDefaults under `YouTubeDownloadRoot` (the folder path)

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
- **Download folder reachability**: `isDownloadFolderReachable()` checks `FileManager.fileExists` + `URL.checkResourceIsReachable()` before downloading; a disconnected mount throws `downloadFolderNotReachable` instead of writing into a stale path
- **Manifest is line-of-business**: Direct JSON file writes; no SQLite. Corruption or missing entries are rare but unrecoverable (keep off user-visible data)
- **Quality setting is global**: One `quality` setting applies to all future downloads; past downloads retain their own `quality` field in the manifest
- **Streaming playback not offered**: YouTube streams (live, members-only, age-restricted) may fail silently if yt-dlp can't extract them; only downloadable videos are listed
- **Video titles from yt-dlp**: Source of truth is yt-dlp's title extraction; titles are not synced with YouTube's API and may differ from what the web UI shows
- **Channels tab uses the `.youtube` column group, not the radio column path**: Don't route YouTube videos through `internetRadioColumns` — those columns are fixed-width by design. Video rows use `youtubeColumns` (`[.title, .duration]`) via the resizable `LibraryColumnVisibilityGroup.youtube` group; adding/changing that enum requires updating every exhaustive `switch group` in both `ModernLibraryBrowserView` and `PlexBrowserView`
