---
name: youtube-source
description: YouTube channel uploads in the Radio tab — browse channels, download audio (FLAC / MP3) or video (720p / 1080p) ad-free, store in a user folder, and play/cast locally. Use when working on YouTube source UI, channel/video listing, downloads, manifest tracking, or format settings.
---

# YouTube Source

Subscribe to YouTube channels in the **Radio tab** and browse their uploads. Double-click a video to **download its audio or video** (ad-free, via `yt-dlp`) and play immediately. Downloads are stored in a **user-chosen folder** (reachability checked before downloading), organized per channel as `<Channel Name>/<Title> [<videoId>].<ext>` and tracked in a manifest; a **format setting** (FLAC / MP3 High / MP3 Low / Video 720p / Video 1080p) is in the Library menu. Downloaded audio files are local `file://` tracks that play locally and cast to Sonos, Chromecast, DLNA; downloaded videos open in the video player window.

## Quick Start (user)

1. **Radio tab** → **+ Add YouTube Channel**
2. Paste a YouTube channel URL (e.g., `https://www.youtube.com/@channel_name`) — or find one by
   name: **Search** tab, type, press Enter, then double-click a result (or right-click →
   **Subscribe**). Results show `@handle · followers`; a ✓ marks channels already subscribed
3. Channel appears as a folder; expand to see uploads
4. Double-click a video to download its audio or video and play
5. **Library → YouTube → Set Download Folder…** to choose where downloads live
6. **Library → YouTube → Format** to pick FLAC, MP3 High, MP3 Low, Video 720p, or Video 1080p
7. **Library → YouTube → Videos per Channel** to pick how many recent uploads to list (50 / 100 / 200 / 500)

## Architecture

```text
Sources/NullPlayer/
├── YouTube/
│   ├── YouTubeModels.swift          # Channel, ChannelSearchResult, Video, Download, Quality data models
│   ├── YouTubeManager.swift         # Singleton: channels, channel search, video listing, downloads, manifest (youtube_downloads.json)
│   └── YouTubeRowThumbnails.swift   # Shared loader/cache for list-row thumbnails and avatars (both browsers)
├── Utilities/
│   └── NSImage+SquareCrop.swift     # squareCenterCropped() — 16:9 thumbnails as square art
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
var quality: YouTubeQuality                  // .flac / .mp3High / .mp3Low / .video720 / .video1080 (persisted under "YouTubeQuality")
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
    var avatarURL: URL?  // square avatar; optional so channels saved before it still decode
}

struct YouTubeChannelSearchResult: Hashable {   // a search hit, not necessarily subscribed
    let channelId: String       // UC…
    let handle: String?         // "@handle", nil for e.g. "- Topic" channels
    let title: String
    let followerCount: Int?
    let description: String?
    let avatarURL: URL?
    var asChannel: YouTubeChannel   // keyed via normalizeChannelURL, exactly like a pasted URL
}

struct YouTubeVideo: Codable, Identifiable, Hashable {
    let videoId: String
    let title: String
    let channelId: String
    let duration: TimeInterval?
    let publishedAt: Date?          // approximate upload date (see "Approximate dates" below)
    var thumbnailURL: URL?          // 16:9 hq720 thumbnail (optional, older data decodes)
    var id: String { videoId }      // Identifiable
    var watchURL: URL { ... }       // https://www.youtube.com/watch?v=<videoId>
    var formattedDate: String?      // "MMM d, yyyy", nil when publishedAt is nil
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
yt-dlp --flat-playlist -J --playlist-end 200 \
  --extractor-args "youtubetab:approximate_date" \
  "https://www.youtube.com/@channel_name/videos"
```

`-J` dumps a single JSON object; `parseFlatPlaylist` decodes its `entries` (each `id`/`title`/`duration`/`timestamp`) into `YouTubeVideo`s. The `limit` defaults to `YouTubeManager.videoLimit` (a user setting, **default 200**, persisted under `YouTubeVideoLimit`, chosen via **Library → YouTube → Videos per Channel**: 50/100/200/500). Changing it posts `youtubeVideoLimitDidChangeNotification`; both browser views drop their cached `youtubeChannelVideos` and re-fetch expanded channels (`reloadExpandedYouTubeChannels`) so it applies without a restart. Channel title on add comes from a separate `--playlist-end 1` fetch (`fetchChannelTitle`, no extractor arg).

**Approximate dates**: plain `--flat-playlist` returns **no** `upload_date`/`timestamp` — the channel grid only exposes relative dates ("3 weeks ago"). The `youtubetab:approximate_date` extractor arg (passed via `fetchYtDlpJSON(…, approximateDate: true)`, videos call only) makes yt-dlp populate each entry's `timestamp` with an **estimated** epoch, decoded into `YouTubeVideo.publishedAt`. Accurate to the day for recent uploads, coarsening for older ones (older videos can share a timestamp). Unsupported/old yt-dlp just omits it → `publishedAt` nil → empty Date column, natural newest-first order preserved.

Videos appear as indented child rows. Double-clicking a video triggers `YouTubeManager.download(video:)` (audio or video MP4 depending on the current Quality setting; then the browser loads the returned local file and plays it).

### Channel Search (Search tab)

Under the YouTube source the **Search** tab searches YouTube for channels (it used to list
internet-radio stations — leftover behaviour). `YouTubeManager.searchChannels(query:limit:)` runs a
channels-only results page through the same `fetchYtDlpJSON`, no API key:

```bash
yt-dlp --flat-playlist -J --playlist-end 20 \
  "https://www.youtube.com/results?search_query=<q>&sp=EgIQAg%3D%3D"   # sp = "Type: Channel" filter
```

- `channelSearchURL(query:)` percent-encodes the query down to RFC 3986 unreserved characters (so
  `&`, `+`, `#` survive); `parseChannelSearch` (pure) reads each entry's `channel_id`,
  `uploader_id` (`@handle`, **may be null**), `channel_follower_count`, `description`, and avatar.
  yt-dlp reports Topic channels with a follower count of 1.
- **Submit-only**: a search is a network call, so it runs on Enter, never per keystroke. The classic
  browser otherwise searches as you type — for the YouTube source its key handler only edits the
  query. Once a query has run, Enter acts on the selected row; Refresh re-runs the query; returning
  to the tab reuses results of an unchanged query (`youtubeSearchQuery`).
- Results build as a `.header` "Channels (N)" plus one **`.youtubeChannel(result.asChannel)`** row
  each, so expand/preview/download reuse the Channels-tab paths (`expandedYouTubeChannels`,
  `youtubeChannelVideos`). `hasYouTubeColumns` and `applyYouTubeColumnSort` accept the search view
  (`isYouTubeChannelSearch`); the latter returns true with no video rows so the header isn't sorted
  into the channels.
- **Subscribe**: double-click / Enter on an unsubscribed result, or the context-menu **Subscribe**,
  calls `YouTubeManager.subscribe(to:)` (same ffmpeg + duplicate checks as `addChannel(url:)`, which
  now calls it after its title fetch). `isSubscribed(_:)` matches on the normalized key
  (case-insensitive — handles are) **or** the UC channel ID, so a channel added by `/channel/UC…`
  URL still shows ✓. Search rows carry no Refresh/Remove.
- A preview video downloaded before subscribing is foldered under the search result's title
  (`download(video:channelTitle:)`), not a bare ID.

### Thumbnails and Avatars

- **Art column**: `youtubeColumns` is `[.thumbnail, .title, .youtubeDate, .duration]` in both
  browsers; `drawColumnRow` draws the `thumbnail` column as an image (square crop, rounded corners),
  and a header click on it does not sort. Channel rows are not column rows (they keep the ▶ arrow),
  so their avatar is drawn round, inline before the title. Images come from
  `YouTubeRowThumbnails.shared` (fetch on first draw, 64 px square cache, failures not retried,
  `didLoadNotification` → redraw). The classic browser draws them inside its text counter-flip
  (y-up there) centred on the row, so the flip leaves the rect unchanged and the image upright.
- **Selection art** (the faint backdrop behind the list): `loadArtworkForSelection` handles
  `.youtubeVideo` (embedded art of a download, else `thumbnailURL`) and `.youtubeChannel`
  (`avatarURL`), center-cropped square.
- **Sources** (yt-dlp `thumbnails[]`): video entries carry `hq720.jpg` (16:9, no bars — avoid
  `hqdefault.jpg`, 4:3 letterboxed); rows use `mqdefault.jpg`. Channel listings carry a 900×900
  square avatar (`avatarURL(from:)` takes the largest square, else `avatar_uncropped`); search
  entries carry `=s176-` avatars, some protocol-relative (`//yt3…`) — rewritten to `https:` and
  `=s512-`.
- **Back-fill**: `addChannel` stores the avatar from its title fetch. Subscriptions saved earlier get
  it from `backfillMissingAvatars()` (called when the Channels tab loads; one `--playlist-end 1`
  listing per channel, once per session) or from their first `videos(forChannel:)`;
  `updateAvatar(channelId:url:)` writes it back.
- **Embedded art is square**: both download paths add `squareThumbnailArgs` — `--embed-thumbnail
  --convert-thumbnails jpg` plus a `--ppa ThumbnailsConvertor+FFmpeg_o:` crop, passed as one
  Process argument (yt-dlp shlex-splits it). MP4 downloads get them through
  `StreamRipper.downloadVideo(…, extraArgs:)`; the stream-ripper's own URL-rip path is unchanged.
  Files downloaded earlier keep 16:9 art.

#### Column rendering (Channels tab)

Video (leaf) rows render through the **established resizable-column path** (`drawColumnRow`), not the simple list path, so a long title truncates inside its column instead of printing over the time. The column set is:

```swift
static let youtubeColumns: [ModernBrowserColumn] = [.thumbnail, .title, .youtubeDate, .duration]  // "Art", "Title", "Date", "Time"
```

- A dedicated **`.youtube` case in `LibraryColumnVisibilityGroup`** namespaces the persisted widths (`youtube:title`, `youtube:youtubeDate`, `youtube:duration`) so they survive `migrateColumnWidths`. This is why the internet-radio column path can't be reused: `internetRadioColumns` are deliberately **non-resizable** (`hitTestColumnResize` early-returns when `hasInternetRadioColumns`), and the requirement here is a movable Time column like the library tabs.
- The **`youtubeDate`** column shows `video.formattedDate`; sorting it goes through the **raw-`Date` branch** of `columnSortAreInOrder` (via `columnDateValue`, alongside `dateAdded`/`lastPlayed`), not string compare, so it orders by actual date.
- **Channel (parent) rows stay on the simple-list path** so they keep their ▶/▼ expand arrows; only video rows use columns — mirroring radio folders vs. stations.
- Column headers appear only once a channel is expanded (video rows exist), gated by `hasYouTubeColumns` (`radioSlotShowingChannels` + any `.youtubeVideo` in `displayItems`).
- Clicking a header sorts via **`applyYouTubeColumnSort`** — an in-place sort of each contiguous run of video rows (leaving channel leaders put), mirroring `applyInternetRadioColumnSort`.
- Plumbing touched: `columnGroup(for:)`, `currentColumnGroup()`, `columnsForItem`, `currentVisibleColumns`, `headerColumnsForCurrentContent`, `columnValue`, plus the four `allColumns`/`defaultColumnIds`/`visibleColumnIds`/`setVisibleColumnIds` group switches.
- **Both UIs implement this independently**: the classic `PlexBrowserView` mirrors the whole column set (its own `BrowserColumn.youtubeColumns`, `columnValue`, `columnDateValue`, `applyYouTubeColumnSort`, session sort, etc.). Any change to YouTube columns/sorting must be made in **both** `ModernLibraryBrowserView` and `PlexBrowserView` — they share no code.

### Download Flow

1. **Reachability Check**: Verify `downloadRoot` is accessible (mounted NAS, etc.)
2. **Download**: `YouTubeManager.download(video:)` builds the format/output args and, for audio qualities, delegates to `StreamRipper.downloadAudio(from:formatArgs:outputTemplate:)` to download the video's best audio. For video qualities (`quality.isVideo`) it instead delegates to `StreamRipper.downloadVideo(from:maxHeight:outputTemplate:)` to download an MP4 capped at `quality.videoMaxHeight` (720/1080)
3. **Channel folder + readable name**: Save under a per-channel subfolder as `<Channel Name>/<Title> [<videoId>].<ext>` (yt-dlp sanitizes the title and picks the extension; the bracketed video ID keeps names unique). The manifest stores this as a `fileName` path relative to `downloadRoot`.
4. **Manifest Update**: Append entry to `youtube_downloads.json`
5. **Track Creation**: Construct a local `Track(url:)` from the manifest entry
6. **Playback**: Load the track into the audio engine and play

### Library Menu Integration

All items live under a single **Library → YouTube** submenu, built in `ContextMenuBuilder.buildYouTubeMenuItem()` (actions `setYouTubeDownloadFolder`, `setYouTubeQuality(_:)`, `setYouTubeVideoLimit(_:)`). The submenu reads current values at build time, so checkmarks update whenever the menu is rebuilt on open.

**Library → YouTube → Set Download Folder…**
- Opens `NSOpenPanel` for directory selection
- Validates reachability before storing
- `youtube_downloads.json` is written lazily on the first recorded download, not on folder selection
- Persists in UserDefaults under `YouTubeDownloadRoot` (the folder path)

**Library → YouTube → Quality**
- Five-way FLAC / MP3 High / MP3 Low / Video (720p) / Video (1080p) setting (`YouTubeQuality`), persisted in UserDefaults under `YouTubeQuality`
- Consulted before each download in `YouTubeManager.download(video:)`: audio qualities pass `quality.ytdlpArgs` to `StreamRipper.downloadAudio`; video qualities (`quality.isVideo`) route to `StreamRipper.downloadVideo` with `quality.videoMaxHeight`

**Library → YouTube → Videos per Channel**
- How many recent uploads to list per channel (`--playlist-end`); presets `YouTubeManager.videoLimitChoices` = 50/100/200/500, default 200, persisted under `YouTubeVideoLimit`
- `videos(forChannel:limit:)` defaults `limit` to `videoLimit`
- Changing it posts `youtubeVideoLimitDidChangeNotification`; both browser views clear `youtubeChannelVideos` and re-fetch expanded channels (`reloadExpandedYouTubeChannels`) so it applies live (no restart)

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
- **YouTube has its own session sort (default date order)**: The channels tab must NOT inherit the persisted library column sort (`columnSortId`, saved per tab by `LibraryBrowserTabSortStore`), or every rebuild — including after a download — re-sorts videos to A–Z. Both views keep session-only `youtubeColumnSortId`/`youtubeColumnSortAscending` (default nil = yt-dlp's newest-first order), read through `activeColumnSortId`/`activeColumnSortAscending` by every sort/header-draw path. A header click in the YouTube tab sets the session sort only; it never writes the library sort. This state resets to date order on relaunch (intended).
- **Downloaded marker is rebuild-driven**: A downloading video draws a per-row spinner gated on `downloadingVideoIds`; the **`⬇ ` prefix** for a finished download is added in `buildYouTubeChannelItems` from `isDownloaded`. The download handler calls `rebuildCurrentModeItems()` on success (adds the marker) and a `defer` clears `downloadingVideoIds` (drops the spinner) — so the spinner→icon transition only works because the row stays put, which is why the session-sort fix above matters (an A–Z re-sort would relocate the row mid-transition).
- **Channels tab uses the `.youtube` column group, not the radio column path**: Don't route YouTube videos through `internetRadioColumns` — those columns are fixed-width by design. Video rows use `youtubeColumns` (`[.thumbnail, .title, .youtubeDate, .duration]`) via the resizable `LibraryColumnVisibilityGroup.youtube` group; adding/changing that enum requires updating every exhaustive `switch group` in both `ModernLibraryBrowserView` and `PlexBrowserView`
