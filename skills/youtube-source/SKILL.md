---
name: youtube-source
description: YouTube channel uploads in the Radio tab — browse channels, download a video's audio (FLAC, ALAC, MP3, AAC, or the original stream) and/or its video (360p–4K) ad-free, store in a user folder, and play/cast locally. Use when working on YouTube source UI, channel/video listing, the video row menu, downloads, manifest tracking, or format settings.
---

# YouTube Source

Subscribe to YouTube channels in the **Radio tab** and browse their uploads. A video row's menu offers **Audio ▸** and **Video ▸**, each with the library's track verbs; the chosen form is **downloaded** (ad-free, via `yt-dlp`) when it isn't on disk yet, then played or queued. A video's audio and video downloads can coexist. Downloads are stored in a **user-chosen folder** (reachability checked before downloading), organized per channel as `<Channel Name>/<Title> [<videoId>].<ext>` and tracked in a manifest; **Audio Format** and **Video Quality** settings are in the Library menu. Downloaded audio files are local `file://` tracks that play locally and cast to Sonos, Chromecast, DLNA; downloaded videos open in the video player window.

## Quick Start (user)

1. **Radio tab** → **+ Add YouTube Channel**
2. Paste a YouTube channel URL (e.g., `https://www.youtube.com/@channel_name`) — or find one by
   name: **Search** tab, type, press Enter, then double-click a result (or right-click →
   **Subscribe**). Results show `@handle · followers`; a ✓ marks channels already subscribed
3. Channel appears as a folder; expand to see uploads
4. Right-click a video → **Audio ▸** or **Video ▸** → Play, Play and Replace Queue, Add to Playlist,
   Play Next or Add to Queue. That form downloads first if it isn't on disk; the row shows a spinner
   meanwhile and a `⬇ ` once a file is there. Double-click / Enter plays the one form on disk, and
   otherwise (both forms, or neither) pops the same menu
5. **Library → YouTube → Set Download Folder…** to choose where downloads live
6. **Library → YouTube → Audio Format** and **Video Quality** to pick what those downloads are
7. **Library → YouTube → Videos per Channel** to pick how many recent uploads to list (50 / 100 / 200 / 500)

## Architecture

```text
Sources/NullPlayer/
├── YouTube/
│   ├── YouTubeModels.swift          # Channel, ChannelSearchResult, Video, Download, MediaKind, AudioFormat, VideoQuality
│   ├── YouTubeManager.swift         # Singleton: channels, channel search, video listing, downloads, manifest (youtube_downloads.json)
│   ├── YouTubeVideoActions.swift    # A video row's Audio ▸ / Video ▸ menu and its downloads (both browsers)
│   ├── YouTubeRows.swift            # Every YouTube list row (Channels tab, channel search, Local search), both browsers
│   └── YouTubeChannelSearch.swift   # The Search tab's channel search (both browsers)
├── Utilities/
│   ├── LibraryRowThumbnails.swift   # Round list-row thumbnails for every library row (see ui-guide)
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
var audioFormat: YouTubeAudioFormat          // persisted under "YouTubeAudioFormat"
var videoQuality: YouTubeVideoQuality        // persisted under "YouTubeVideoQuality"
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
    let kind: YouTubeMediaKind      // .audio / .video; inferred from the extension for older entries
    struct Key: Hashable { let videoId: String; let kind: YouTubeMediaKind }
    var key: Key
}

enum YouTubeAudioFormat: Hashable {     // the Audio Format setting
    case flac, alac, mp3(kbps: Int), aac(kbps: Int), originalAAC, originalOpus
    static let sections: [[Self]]       // the menu's choices — the only list of them
}

enum YouTubeVideoQuality: Hashable {    // the Video Quality setting
    case height(Int), best              // 360…2160, or no cap
    static let sections: [[Self]]
}
```

### Manifest (`youtube_downloads.json`)

Stored inside `downloadRoot`, tracks downloaded files. In memory it is `[YouTubeDownload.Key: YouTubeDownload]`, so one video can have an audio and a video entry. On disk it is a JSON dictionary keyed `"<videoId>.<kind>"`, each value a `YouTubeDownload`; the loader re-keys from the values, so the key string is cosmetic and a manifest written by an older build (keyed by the bare `videoId`, no `kind`) still loads, its kind inferred from the file extension. `fileName` is a path **relative to `downloadRoot`** (`<Channel Name>/<Title> [<videoId>].<ext>`):

```json
{
  "dQw4w9WgXcQ.audio": {
    "videoId": "dQw4w9WgXcQ",
    "title": "Video Title",
    "channelId": "channel_handle",
    "fileName": "Channel Name/Video Title [dQw4w9WgXcQ].flac",
    "kind": "audio"
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

Videos appear as indented child rows. Their menu, and double-click / Enter, come from `YouTubeVideoActions` (see *Video row menu* below).

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
  (`download(video:kind:channelTitle:)`, given `YouTubeChannelSearch.channelTitle(forVideo:)`), not a bare ID.

### Thumbnails and Avatars

- **Art column**: `youtubeColumns` is `[.thumbnail, .title, .youtubeDate, .duration]` in both
  browsers; `drawColumnRow` draws the `thumbnail` column as a round image, and a header click on it
  does not sort. Channel rows are not column rows (they keep the ▶ arrow), so their avatar is drawn
  round, inline before the title. Both are ordinary library row thumbnails —
  `LibraryRowThumbnails.Source.video` / `.channel` through `rowThumbnailSource(for:)`; loading,
  caching, preload and the hover preview are in `ui-guide` § *Library row thumbnails*. A channel
  fetches its avatar once at 320 px (`avatarURL(side:)`) and both renditions are cut from it.
- **Selection art** (the faint backdrop behind the list): `loadArtworkForSelection` handles
  `.youtubeVideo` (embedded art of either download — both carry the same square thumbnail — else `thumbnailURL`) and `.youtubeChannel`
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

### Video row menu (`YouTubeVideoActions`)

One `@MainActor` instance per browser view (`youtubeVideoActions`, like `youtubeSearch`) owns the
whole per-video flow, so both browsers' YouTube-video branches are one call each.

- `addMenuItems(for:to:)` builds **Audio ▸** / **Video ▸** (each with the library's track verbs —
  `App/TrackVerb.swift`: Play, Play and Replace Queue, Add to Playlist, Play Next, Add to Queue —
  mapped to the same engine calls the library's local-track handlers make), then, for whatever is
  on disk, **Show in Finder** (selects every file of the video) and **Remove Audio File** /
  **Remove Video File**.
  `activate(_:in:)` is double-click and Enter: a video with exactly one form on disk plays it
  (`TrackVerb.play`); with both, or neither, it pops the same items at the mouse (so Enter also
  pops at the cursor, not the row). Nothing is fetched or picked without a choice.
- A verb on a form that is on disk runs now. Otherwise it awaits that form's download:
  `fetches[Key]` is the single in-flight state, and a repeat request for the same video + kind
  awaits the running download instead of starting a second yt-dlp onto the same file. A waiting
  verb is not a stored task: it captures two counters and checks them when its file lands. Every
  Play / Play and Replace Queue bumps `playEpoch`, so a newer one supersedes a still-waiting one and
  a stale result never starts playing; queue verbs apply when their file lands. `cancel()` (view
  teardown) bumps `epoch`, dropping every waiting verb but not the download — yt-dlp is not killed,
  and a finished file is still recorded.
- `isFetching(_:)` / `hasFetchesInFlight` drive each view's row spinner and loading timer.
  `onFetchesChanged` (a download started or finished) updates the spinner; `onFilesChanged` (a file
  landed or was removed) makes the view rebuild its rows.
- A row's art is `YouTubeManager.coverArtFile(for:)` — the audio download's embedded art, else the
  video's — before falling back to the thumbnail.

### Local search (YouTube section)

The **Local** source's Search tab ends with a **YouTube (N)** section after Artists, Albums and
Tracks, in both browsers. `YouTubeManager.localSearch(query:excluding:)` decides what matches and
`YouTubeRowBuilder.localSearch` shapes the rows (see *Row builder* below). No network: it reads the
subscriptions and the manifest.

- **Channels**: subscriptions whose title contains the query, as `.youtubeChannel` rows at indent 1
  that expand in place (uploads at indent 2) and share `expandedYouTubeChannels` with the Channels
  tab. Expanding fetches uploads, as on that tab.
- **Downloads**: manifest entries whose title contains the query, one `.youtubeVideo` row per video
  (`YouTubeVideo(download:)` — no duration, date or thumbnail URL, so those columns are blank), A–Z,
  row ids `youtube-download-<videoId>`. Matching is `localizedStandardContains` (case- and
  accent-insensitive) on a trimmed query. A video whose audio and video entries carry different
  titles takes the audio entry's (as `coverArtFile` prefers the audio file).
- **No double listing**: the download folder may also be a watch folder, so `.mp3`/`.flac`
  downloads can already be under Tracks. The view passes the Tracks section's file URLs; a video is
  dropped when `Set(downloadedFiles(for:).values).isSubset(of: listed)` — which also drops a video
  with nothing on disk (the empty set). Compared as `standardizedFileURL`. A download already shown
  as an upload under an expanded matching channel is dropped too, and N counts only rows shown.
- **Column header**: these rows carry their own columns (`.youtube` group) but the Local search draws
  no header for them. Hit tests must ask `hasColumnHeader` (= `headerColumnsForCurrentContent() !=
  nil`, what drawing asks), never "does any row have columns" — with only YouTube results that
  shifted every click one row up onto the section header. MISC_TASKS M8 makes one layout function
  per view so the two cannot disagree.

### Row builder (`YouTubeRows.swift`)

Every YouTube list row in both browsers comes from `YouTubeRowBuilder`, built per rebuild from the
view's `expandedYouTubeChannels` and `youtubeChannelVideos`: `channels(_:)` (Channels tab),
`channelSearch(_:)` (the YouTube source's Search tab) and `localSearch(query:excluding:)`. It
returns view-independent `YouTubeRow`s, and each view maps them with a ten-line
`ModernDisplayItem(_:)` / `PlexDisplayItem(_:)`. Row ids, titles, indents, the `⬇ ` marker and the
section headers are decided there only, so a change to YouTube rows is made once, not per browser.

### Download Flow

1. **Reachability Check**: Verify `downloadRoot` is accessible (mounted NAS, etc.)
2. **Download**: `YouTubeManager.download(video:kind:channelTitle:)` switches on `kind`. `.audio`
   passes `audioFormat.formatSelector` (the one `-f`) and `audioFormat.ytdlpArgs` to
   `StreamRipper.downloadAudio(from:formatSelector:formatArgs:outputTemplate:)`;
   `.video` calls `StreamRipper.downloadVideo(from:maxHeight:outputTemplate:extraArgs:)` with
   `videoQuality.maxHeight` (nil = no cap). Up to 1080p the video is H.264 only; above that it is
   VP9 / AV1 (YouTube's H.264 stops at 1080p), still preferring H.264 on a tie, merged with AAC
   audio into an `.mp4`
3. **Channel folder + readable name**: Save under a per-channel subfolder as `<Channel Name>/<Title> [<videoId>].<ext>` (yt-dlp sanitizes the title and picks the extension; the bracketed video ID keeps names unique). The manifest stores this as a `fileName` path relative to `downloadRoot`.
4. **Manifest Update**: Record the entry under its video + kind in `youtube_downloads.json`
5. **Verb**: `YouTubeVideoActions` makes a `Track(url:isYouTubeOrigin: true)` from the file and runs the chosen verb

### Library Menu Integration

All items live under a single **Library → YouTube** submenu, built in `ContextMenuBuilder.buildYouTubeMenuItem()` (actions `setYouTubeDownloadFolder`, `setYouTubeAudioFormat(_:)`, `setYouTubeVideoQuality(_:)`, `setYouTubeVideoLimit(_:)`). The three radio-style submenus share one local `choiceSubmenu` builder, with a separator between sections. The submenu reads current values at build time, so checkmarks update whenever the menu is rebuilt on open.

**Library → YouTube → Set Download Folder…**
- Opens `NSOpenPanel` for directory selection
- Validates reachability before storing
- `youtube_downloads.json` is written lazily on the first recorded download, not on folder selection
- Persists in UserDefaults under `YouTubeDownloadRoot` (the folder path)

**Library → YouTube → Audio Format** (`YouTubeAudioFormat`, persisted under `YouTubeAudioFormat`)
- FLAC, ALAC · MP3 320 / 256 / 192 / 128 kbps (constant bitrate) · AAC 256 / 192 / 128 kbps ·
  Original AAC, Original Opus (no re-encode). Default FLAC
- YouTube's best audio is ~130–160 kbps Opus or 128 kbps AAC, so everything but the originals is a
  re-encode of that; FLAC/ALAC/320 add size, not quality
- yt-dlp details: `--audio-format alac` silently writes AAC, so ALAC adds
  `--ppa "ExtractAudio+ffmpeg_o:-c:a alac"`; `--audio-format m4a` *copies* an AAC source, so the AAC
  bitrates select the Opus stream (`-f bestaudio[acodec=opus]/bestaudio`) to actually encode
- `.opus` plays in the audio engine (AVAudioFile reads Ogg Opus on current macOS) but is not in
  `AudioFileValidator.supportedExtensions`, so a library scan skips it and a playlist drop refuses it

**Library → YouTube → Video Quality** (`YouTubeVideoQuality`, persisted under `YouTubeVideoQuality`)
- 360p · 480p · 720p · 1080p · 1440p · 2160p (4K) · Best Available. Default 1080p

**Migration**: `YouTubeManager.resolveFormats` (pure) reads the old single `YouTubeQuality` setting
when a new key is absent — `flac` → FLAC, `mp3High` → MP3 320, `mp3Low` → MP3 128, `video720` /
`video1080` → that height; the other axis takes its default.

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
- **Format settings are global, the choice is per video**: Audio Format and Video Quality apply to every future download of that kind; whether a video gets its audio or its video is chosen in its row menu. Past downloads keep their files; the manifest records only their kind
- **Streaming playback not offered**: YouTube streams (live, members-only, age-restricted) may fail silently if yt-dlp can't extract them; only downloadable videos are listed
- **Video titles from yt-dlp**: Source of truth is yt-dlp's title extraction; titles are not synced with YouTube's API and may differ from what the web UI shows
- **YouTube has its own session sort (default date order)**: The channels tab must NOT inherit the persisted library column sort (`columnSortId`, saved per tab by `LibraryBrowserTabSortStore`), or every rebuild — including after a download — re-sorts videos to A–Z. Both views keep session-only `youtubeColumnSortId`/`youtubeColumnSortAscending` (default nil = yt-dlp's newest-first order), read through `activeColumnSortId`/`activeColumnSortAscending` by every sort/header-draw path. A header click in the YouTube tab sets the session sort only; it never writes the library sort. This state resets to date order on relaunch (intended).
- **Downloaded marker is rebuild-driven**: A downloading video draws a per-row spinner gated on `youtubeVideoActions.isFetching`; the **`⬇ ` prefix** (either form on disk) is added by `YouTubeRowBuilder` from `isDownloaded`. `onFilesChanged` fires when the download lands, and the view's handler calls `rebuildCurrentModeItems()` (adds the marker; the spinner is gone because the fetch left `fetches`) — so the spinner→icon transition only works because the row stays put, which is why the session-sort fix above matters (an A–Z re-sort would relocate the row mid-transition).
- **Channels tab uses the `.youtube` column group, not the radio column path**: Don't route YouTube videos through `internetRadioColumns` — those columns are fixed-width by design. Video rows use `youtubeColumns` (`[.thumbnail, .title, .youtubeDate, .duration]`) via the resizable `LibraryColumnVisibilityGroup.youtube` group; adding/changing that enum requires updating every exhaustive `switch group` in both `ModernLibraryBrowserView` and `PlexBrowserView`
