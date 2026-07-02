# Changelog

## 0.27.0

### Improvements

- **Modern and Metal UI now use a modern system font** — the retro low-fi bitmap font (Departure Mono) has been replaced throughout the Modern and Metal windows — Library tabs and headers, the main window, playlist, EQ, and spectrum — with the crisp macOS system font. Time and track digits stay monospaced so they don't jitter. Skins that ship their own custom font still render it as before.
- **License and branding terms clarified** — the project license notice and README now state GPL-3.0-only distribution terms and clarify that modified distributions must not reuse the NullPlayer name, icon, logo, bundle identity, or other branding without permission.
- **Balance control added to Playback menu** — the Playback options now include a Balance submenu with a slider and common left/center/right presets, giving modern UI and menu-only workflows access to stereo balance without adding more controls to the player face.

### Bug Fixes

- **Metal skin transport icons are now fully filled** — the previous/next (and eject) icons in the Metal finishes no longer show a stray light vertical line: the icon bars now draw in the same transport-button color as the rest of the glyph instead of the skin's light primary color.
- **Plex Artists no longer show duplicate same-name rows** — the Library Browser now groups Plex artist records with the same display name into one visible artist row in both classic and modern UI. Expanding, playing, or queueing that row still fans out across every underlying Plex `ratingKey`, so albums and tracks attached to duplicate server-side artist records remain accessible instead of being hidden.
- **Compact Mode art ratings fit the small UI** — the modern Library Browser's art-view rating stars now shrink in Compact Mode, preventing them from crowding or overlapping the source/library picker row.
- **Library window remembers where you put it** — after unlocking the connected windows and moving the Library/browser window, it now reopens at the exact position and size you left it — across closing and reopening it (via the menu or the red close button) and across full app restarts, even when it was closed at quit. First-ever opens still dock to the right of the window stack, shaded (collapsed) windows restore to their normal size, and the position survives Compact Mode. Playlist, EQ, and Spectrum still intentionally snap back into the column below the main window.

## 0.26.1

### Bug Fixes

- **App icon no longer renders as a square on fresh installs** — the Dock and Cmd-Tab app icon could appear as a hard square (with the rounded logo visible inside it) on Macs that hadn't already cached the icon, while staying correct on machines that had. The icon's rounded "squircle" shape is now baked into the build, so it looks right everywhere on a clean install.
- **Cue albums split correctly even when the audio file was renamed** — library split-on-import now locates the backing audio by its same-named sibling when a `.cue`'s internal `FILE` reference is stale (for example, when the `.cue` and its audio were renamed together), instead of importing the whole album as one track. Adding the backing audio file directly with **Add Files…** now triggers the split too.

## 0.26.0

### New Features

- **Compact Mode — a menu-bar mini player** — collapse NullPlayer into a single menu-bar app: the Dock icon and all the player windows disappear, and a status-bar item gives you one slim window — the Library Browser with a built-in player bar across the top (transport, seek and time, a scrolling title, and volume). Open it from the main window's right-click menu, the **Windows** menu, or the new **CP** button in the modern toolbar; click the status item to bring it back or exit. A playing video stays on screen, so you can keep watching while you browse. Works in both classic and modern UI.

- **Audio Analysis window** — a real-time, multi-pane analyzer (inspired by [Friture](https://friture.org)), opened from the **Window** menu, a right-click, or the new **AA** button in the modern toolbar. Switch between three views: a **Scope** oscilloscope of the live waveform, a **Levels** meter showing per-channel peak and RMS, and a scrolling **Spectrogram** waterfall. It docks and snaps with the other windows and remembers its position and selected view. Works in both classic and modern UI.

- **YouTube channels in the Radio tab** — add YouTube channel links and browse each channel's uploads right in the Radio tab — no account or API key needed. Double-click a video to download its audio (FLAC or MP3) or video (720p/1080p) ad-free into a folder you choose; downloads play locally and cast to Sonos, Chromecast, and DLNA like any other track, and get their own **YouTube** entry in the Data tab. Quality and the download folder are set in the **Library** menu. Works in both classic and modern UI.

- **Metal mode — hi-fi faceplate finishes** — a new metallic look, selectable from **Skins → Metal**, with seven finishes: Brushed Steel, Aluminum, Gunmetal, Anodized Black, Brass, Bronze, and Copper. Each finish restyles the whole player — chrome, panels, sliders, transport, and EQ — with a backlit-green LCD for the time and track displays and a spectrum analyzer matched to the finish.

- **Switch between Classic, Modern, and Metal instantly — no restart** — changing UI mode, or picking a skin from a different mode, now happens live and in place. Playback, casting, the open playlist, the current track, and your play position all continue uninterrupted while the windows rebuild in the new look, reappearing where you left them. (Classic Large UI still relaunches, since it's a size change rather than a mode switch.)

### Improvements

- **Visualization window renamed "Visualizations"** — the window that hosts the ProjectM, Geiss, Tripex, and Met Museum visualizers is now labeled **Visualizations** everywhere.
- **Tidier Library tabs (classic & modern)** — Library tab names now sit in rounded boxes sized to fit their labels, so every tab has room to breathe. The **Shows** tab is now **TV**, and the Radio and Search tabs have swapped places.
- **Modern toolbar refresh** — clearer toolbar buttons in the modern main window, including the visualizer (**VZ**) toggle and the new **AA** (Audio Analysis) and **CP** (Compact Mode) buttons.
- **Titled utility windows (classic)** — the Spectrum Analyzer, Waveform, Library, and Visualizations windows now show their names in the title bar.

### Bug Fixes

- **Visualizations window now loads on open instead of after a click** — opening the Visualizations window on top of an already-connected window cluster could leave it showing just its background color (with the connected-window drag tint) until you clicked a window. Opening/positioning windows no longer starts a phantom "drag" that stranded the visualization render-suspended; it now starts rendering immediately.
- **Library search now lands on the artist you picked (Plex)** — choosing an artist from Library search results reliably switches to the Artists tab and selects that artist, in both classic and modern UI.
- **Cleartext `http://` radio stations play again (#310)** — after 0.25.0, many `http://` Icecast/SHOUTcast stations connected but produced no sound (they sat stuck at `0:00`); they now play again. `https://` stations were unaffected.
- **"Test" button in Add Station no longer fails working stations (#310)** — the station test now connects the same way the player does, so it stops reporting errors for stations that play perfectly.
- **Sample-rate (kHz) display now shows for streams without a visualization open (#285)** — the classic skin's kHz readout stayed blank for some streaming tracks unless a visualization was open; it now appears as soon as playback starts.
- **Album-art mode no longer traps you after clearing the playlist (#283)** — clearing the playlist while viewing album art now returns you to the normal browser, in both classic and modern UI.
- **Album-art mode exits when you change tab or source** — switching Library tabs or sources now leaves the artwork view and restores the normal list, instead of leaving you stuck on the artwork.
- **Video no longer auto-casts in the classic UI** — playing a video in classic UI no longer silently sends it to a Chromecast/DLNA TV; it opens in the local video player unless you've chosen a cast device.
- **Casting to a just-rebooted Sonos speaker now works on the first try** — a Sonos cast that used to fail right after the speaker rebooted now recovers on its own and plays.
- **Sonos recovers when a speaker reboots mid-playback (#304)** — if a Sonos speaker rebooted while casting, NullPlayer could end up playing from both the Mac and the speaker at once; it now cleanly ends the dead session so playback resumes correctly.

## 0.25.0

### New Features

- **`.cue` sheet playback — virtual split (#273)** — opening a `.cue` file (via **File → Open**, drag-and-drop, or double-click), or opening an audio file that has a sibling `.cue` next to it, now plays the single backing file **virtually split** into its cue tracks: one row per track in the now-playing playlist, with the title, performer, and duration taken from the cue. Prev/Next move per cue track and seeking stays within the current track, while playback crosses track boundaries **gaplessly** — the backing file is scheduled as one continuous stream and a boundary detector advances the playlist row (updating title, seek bar, Now Playing, and history) without touching the audio. Gapless applies with shuffle and repeat-single off; in those modes boundaries still advance correctly but a small gap is expected. Nothing is written to disk and nothing is added to the Local Library; a missing/renamed backing file simply shows its rows as unplayable. The parser reads the first `FILE` entry (extra ones warn), prefers `INDEX 01` (falling back to `INDEX 00`), and is the exact inverse of the Stream Ripper's chapter-`.cue` writer, so a rip's own cue round-trips. `.cue` is now also offered in the File → Open panel's file-type filter.

- **Split `.cue` albums on import (library, off by default)** — a new **Library → Split .cue Albums on Import** toggle (default **off**) makes the Local Library scan physically split a single-file album into per-track files when it finds a `.cue` next to it. When **on**, each track is cut with `ffmpeg` and re-encoded to **FLAC** (re-encoding, not stream-copy, so cuts are sample-accurate) into a **per-album subfolder named from the source file's own `ALBUM`/`ARTIST` tags** (e.g. `Artist - Album/`), falling back to the cue's performer/title, then the cue filename. Each track inherits the source's metadata (date, genre, embedded cover art) with the title/track-number and album/album-artist set from the source tags; the split tracks are added to the library in the same scan and the original backing file is excluded. The split is **idempotent** (a re-scan does no work if the per-track files already exist) and filenames are sanitized and de-duplicated so they can't collide or escape the album folder. If `ffmpeg` isn't installed — or a write fails (permissions, read-only volume, out of space) — splitting is skipped with a one-time notice and the original file imports normally as a single track (it's only hidden once real split tracks exist). When the toggle is **off**, `.cue` files are ignored by the scan entirely and the backing file imports as one normal track. Direct-play (above) is unaffected by this toggle. Changing the toggle takes effect on the next scan.

- **Local library reads FLAC/M4A album-artist and track/disc numbers** — metadata parsing previously read album-artist and track/disc numbers only from MP3 ID3 frames (`TPE2`/`TRCK`/`TPOS`), so FLAC/OGG (Vorbis `ALBUMARTIST`/`TRACKNUMBER`/`DISCNUMBER`) and M4A (`aART`/`trkn`/`disk`) tracks came back without them — causing single albums to fragment by per-track artist and lose their track ordering. These tags are now read across all containers (handling the `1/10` track form).

- **Stream Ripper — download a URL to FLAC/MP3 or a video file** — a new **Output → Streaming → Rip URL…** action opens a dialog where you paste a URL (auto-filled from the clipboard when it holds a web link) and choose an output type: **Audio — FLAC (lossless)**, **Audio — MP3**, or video at a resolution/bitrate profile you pick (**720p/2.5 Mbps, 1080p/4 Mbps recommended, 1080p/8 Mbps high quality, 1440p/16 Mbps, 4K/35 Mbps, Full/50 Mbps max**). Ripping shells out to a system-installed `yt-dlp` (+`ffmpeg`); if either isn't found it shows an install hint (`brew install yt-dlp ffmpeg`) rather than failing silently. Quality is prioritized for audio (`bestaudio`, then lossless FLAC encode or top-VBR MP3). Video grabs the best source streams within the selected height cap (or no height cap for Full), then ffmpeg creates a playback-safe H.264/AAC MP4 with `yuv420p` pixels and fast-start metadata so the app and cast targets do not receive VLC-only files. The video source file is temporary (`[source]`) and is removed after the compatible MP4 is written; existing MP4s are not overwritten. Output is tagged with the source's metadata (title/artist/album/date) and, for audio, the thumbnail is embedded as cover art; the final file is named **`Artist - Title`** from that metadata into a folder you pick. If the source has **chapter timestamps** (common on album/mix uploads), a matching **`.cue` sheet** is written alongside the audio — one TRACK per chapter. Progress shows as a spinner + message band at the top of the main window for the duration of the rip (works in both classic and modern UI). When it finishes, a dialog offers **Play Now** (audio loads into the player; video opens in the video player window, cast-aware), **Reveal in Finder**, or **Done**.

- **Local `.m3u`/`.pls` playlists in the Plists tab (#269)** — the local library browser's **Plists** tab now lists `.m3u`, `.m3u8`, and `.pls` playlist files found on disk, matching what the Plex/Subsonic/Jellyfin/Emby sources already show there (previously the tab was always empty for the local source). Playlist files are discovered during the normal library scan and their *locations* persisted in a small `library_playlists` table — the track contents are not stored, but parsed lazily the first time you expand a playlist. Expanding shows each entry as a row: entries that match a file already in your library carry its metadata and duration, while unmatched paths still appear and remain playable. Double-clicking a playlist row loads and plays the whole list; double-clicking a single entry plays just that track; the disclosure triangle expands as usual. Removing a playlist file from disk drops it from the tab on the next scan, while a transiently unreachable network folder leaves the list intact (the same offline-volume safety guard used for tracks). Implemented identically in both the modern and classic library browsers. Pairs with the earlier "browse by folder structure" work under the same "organize by what's actually on disk" philosophy.

- **Remove Orphaned Entries (library maintenance)** — new Library → **Clear…** → **Remove Orphaned Entries…** action removes library entries whose files are no longer inside *any* watched folder. These orphans are typically left behind by an older buggy removal that deleted the watch folder but not its entries, so they can't be cleared by removing a folder (none owns them). The action previews the count, auto-creates a backup first, deletes from both memory and the SQLite store (tracks, movies, episodes, playlists), and never touches files on disk. Path matching uses the resolved `url.path` so it stays fast on large libraries.

- **Browse local library by folder structure** — the local library can now be browsed by its actual on-disk folder hierarchy instead of by Artist/Album/Playlist metadata. Rather than adding a ninth tab, the existing **Plists** tab slot doubles as a toggle: **double-click** it (local source only) to flip between *Plists* and *Folders*; single-click selects whichever the slot currently shows, and the choice persists across launches. The Folders view reflects what is actually on disk right now — including files that haven't been scanned into the library yet — read lazily one directory level at a time as folders are expanded; library metadata (title, duration) enriches a file row only when that file is in the database. Folders sort first, then files, case-insensitively; symlinked directories are skipped to avoid loops. Right-click a folder for Play / Play and Replace Queue / Play Next / Add to Queue / Show in Finder, which recursively collect every supported audio file beneath it. Filesystem enumeration and database lookups run off the main thread (with per-click cancellation and a loading spinner) so large network/NAS folders don't stall the UI. Implemented independently in both the modern and classic library browsers.

### Improvements

- **Keychain credentials hardened (#253)** — saved server credentials (Plex, Subsonic, Jellyfin, Emby) are now stored with the `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` accessibility class, so they are only readable while the Mac is unlocked and never sync off the device. The previous permissive per-item ACL has been removed. Entries written by earlier versions are upgraded automatically and lazily the first time each one is read.

### Bug Fixes

- **Modern spectrum profile now persists across relaunches (#260)** — launching in modern UI no longer lets the remembered classic skin overwrite both scoped `vis_classic` profiles with Purple Neon. A modern skin's configured profile is applied on first use and when explicitly changing skins, while a profile selected afterward by the user is preserved when restoring that skin on the next launch.
- **Main-window right-click menu simplified** — the main window context menu no longer shows **Sleep Timer** or **Remember State** controls. Those settings remain available from the macOS menu bar, keeping the right-click menu focused on playback/window actions.
- **Removing a watch folder now actually deletes its tracks and persists** — removing a watched folder removed its tracks/movies/episodes from the in-memory arrays but **never deleted the rows from the SQLite store**, and the folder row itself often failed to delete too. Because the library browser reads from the store (not the in-memory arrays), removed tracks kept appearing and never went away, and the "removed" folders reappeared on next launch. Two underlying bugs: (1) `removeWatchFolder(removeEntries:)` only updated memory and called `store.deleteWatchFolder` for the folder — it now also deletes the matching track/movie/episode rows via new chunked, transactional bulk deletes; (2) `MediaLibraryStore.deleteWatchFolder` reconstructed the folder URL with `URL(fileURLWithPath:)`, which on an **offline network volume** can't stat the path to add the trailing slash that stored *directory* URLs carry (`file:///Volumes/home/MUSIC/`), so the `WHERE` clause matched nothing — it now matches the trailing-slash, no-slash, and raw-path forms so offline folders delete correctly. (Pre-existing orphans left by the old behavior aren't retroactively removed by removing a folder — use the new **Remove Orphaned Entries…** action to clean them.)
- **Watch-folder removal confirmation was invisible** — the "Remove Watched Folder?" confirmation opened as a free-floating alert at the normal window level, *below* the Manage Watch Folders window (which sits at `.modalPanel` for issue #254) and below any always-on-top windows, so it was hidden off-screen-behind and could never be confirmed — clicking **Remove…** appeared to do nothing. It's now a window-modal **sheet** attached to the manager window: always visible, and it blocks the folder table beneath it (you can no longer select another row while it's open). This was the root cause behind "removing folders does nothing."
- **Removing a watch folder took ~20 seconds on large libraries** — `removalCountsForWatchFolder()` and `removeWatchFolder()` called `resolvingSymlinksInPath()` once per track to normalize paths — roughly one filesystem call per library item (~60k on a large library). They now compare `track.url.path` directly (already resolved at scan time), the same optimization `watchFolderSummaries()` received, making removal near-instant.
- **Removing a watch folder no longer beachballs the app** — in the Manage Watch Folders window, clicking **Remove…** ran `removalCountsForWatchFolder()` and `removeWatchFolder()` directly on the main thread. Both block on `MediaLibrary`'s internal `dataQueue.sync`, and a running import scan (e.g. right after adding/rescanning a folder) holds that queue for many seconds — so the app froze with a spinning beachball until the scan finished. These calls now run off the main thread (only the confirmation alert stays on main, where it must), matching the pattern the window's folder-list reload already used. Also hardened the modern Library Browser's **Folders** view, which made the same blocking `watchFolderSummaries()` call on the main thread just before handing off to its background walk — that snapshot now happens inside the background task.
- **Popup dialogs no longer hide behind always-on-top windows (#254)** — with **Always on Top** enabled, opening a popup dialog (e.g. *Add Radio Station*) appeared to do nothing: the dialog opened at the normal window level, *below* the main window which had been raised to the floating level, so it was completely obscured until the main window was dragged aside. These transient dialogs now open at the `.modalPanel` level so they always sit above the app's floating windows, matching the tag-editor and Plex link dialogs that already did this. Covers Add/Edit Radio Station, the Subsonic/Jellyfin/Emby link and server-list sheets, the watch-folder manager, and the auto-tag album candidate picker.
- **Non-Retina classic skin colors fixed (#256)** — removed the blanket blue→grayscale conversion in `SkinLoader.processForNonRetina()` that ran on 1× displays, converting every blue-dominant pixel to gray across all classic skin sprites and stripping legitimate blue tones from every skin. The conversion never ran on Retina, which had masked the bug.
- **Non-Retina Data tab text/chart blur fixed (#257)** — the modern Library Browser "Data" tab hosting view is now opaque (`isOpaque = true` with an opaque skin background, kept in sync on skin change). A clear, non-opaque layer had disabled AppKit font smoothing, blurring text and charts on 1× displays; it now mirrors the classic PlexBrowser twin.
- **Local library expand re-sort fixed (#262)** — with a column sort active, double-clicking an Artist or Album to expand it no longer reshuffles the top-level list. The list shown before expanding came from the in-memory column sort (`LibraryTextSorter`: diacritic-insensitive, numeric, leading-article-aware), but expanding a row rebuilt it from the store's SQLite `BINARY` collation order and skipped re-sorting once nested rows were present — so the order silently snapped to the raw store order, most visibly around names with special characters, mixed case, or leading articles. The local-library views in `ModernLibraryBrowserView` and `PlexBrowserView` now re-sort top-level groups (each leader plus its expanded children) with the same comparator, keeping visible order stable through expand/collapse.
- **HTTP-only internet radio streams now play (#255)** — adding a station whose stream URL is plain `http://` (e.g. many Icecast/SHOUTcast servers on custom ports) silently failed to play: it sat buffering forever and never started. Internet radio plays through the AudioStreaming library, which fetches over `URLSession`, but the app's App Transport Security config only declared `NSAllowsArbitraryLoadsForMedia` — a key that exempts *AVFoundation* media loads, **not** `URLSession` — so cleartext connections were blocked by ATS. The reported "`.mp3` links work, others don't" pattern was a coincidence: the working stations happened to be `https://`, and the real distinction was scheme, not file extension or audio format. `Info.plist` now sets `NSAllowsArbitraryLoads` so http stations connect.

## 0.24.0

### New Features

- **Reference Tuning** — Playback > Options > **Reference Tuning** can pitch-shift all local playback to a different reference frequency (e.g. retune A=440 content to A=432). Presets for Off, 432 Hz, 440 Hz, and a Custom… dialog accepting source/target Hz are exposed in the menu; settings persist across launches. Applies to local files and HTTP streaming (Plex/Subsonic/Jellyfin/Emby/radio) via `AVAudioUnitTimePitch` nodes inserted into the active local or streaming graph; the spectrum analyzer continues to display source (pre-pitch) frequencies. Not available while casting (Sonos / Chromecast / DLNA) because the remote renderer receives the stream URL directly with no local audio graph to insert the pitch shifter into. CLI flags `--tuning <off|Hz>`, `--tuning-source <Hz>`, and `--tuning-offset-cents <n>` provide session-only overrides.
- **Playback Speed** — Playback > Options > **Playback Speed** can adjust tempo from 0.25× to 4.0× while preserving pitch. Presets for 0.25×, 0.5×, 0.75×, 1.0×, 1.25×, 1.5×, 1.75×, 2.0×, 2.5×, 3.0×, 4.0×, plus a Custom… dialog are exposed in the menu; settings persist across launches. Applies to local files and HTTP streaming (Plex/Subsonic/Jellyfin/Emby/radio). Not available while casting (Sonos / Chromecast / DLNA) because the remote renderer receives the stream URL directly with no local audio graph to time-stretch.

### Improvements

- **Snow visualization is now dynamic** — fall speed is driven solely by tempo. While `BPMDetector` (aubio) converges, a progressive transient-interval estimator (75th-percentile of recent beat intervals, with octave-folding above 100 BPM to favor calm half-time interpretations) provides an immediate moving target so the snow isn't stuck at zero for the first few seconds of each track. Audio energy now also drives a master "storm level" that controls sky whiteout/fog, beat-driven flake bursts, treble sparkle, streak length and slant, and exposure — quiet passages produce light flurries, loud passages build toward a near-whiteout blizzard.
- **Data tab — genre artist drill-down** — selecting a genre in the Data tab now shows the artists that play in that genre with their play counts and listen time, mirroring the existing artist → tracks drill-down. The panel appears directly under the Genres chart and clears when the genre filter is removed. Works in both modern and classic library browsers.
- **EKG visualization rebuilt as a pure peak detector** — the EKG mode no longer depends on BPM or aubio tempo tracking. Each detected audio peak now fires one QRS complex at the scan head, with height scaled to the peak's *prominence* (rise above the preceding valley) so soft and loud transients both register with proportional, oscilloscope-style heights. Detection runs on raw RMS instead of the saturated perceptual level signal, so brick-walled / compressed material no longer flatlines. Wider vertical clamp and a perceptual loudness curve give a much larger dynamic range between faint blips and tall kicks. The embedded main-window EKG trace also scrolls its persistent history by whole physical pixels to avoid blur from repeated fractional texture resampling in the tiny in-skin display.
- **Classic secondary window chrome refined** — playlist-style windows now share the playlist close-widget artwork and scale, with matching companion circle controls and the small title bar line gap on Spectrum, Waveform, ProjectM, and classic browser chrome while leaving Main and EQ unchanged.
- **Windows menu coverage** — all primary toggleable app windows are now discoverable from the top-level Windows menu, including the standalone Spectrum Analyzer and the Video Player when a video window exists.
- **Visualizations menu parity** — the top-level Visuals > Visualizations menu now exposes the visualization window toggle, engine selection before the window is opened, and the live visualization window controls once available, matching the functionality previously only reachable from the visualization window context menu.
- **Visualizations menu cleanup** — projectM-only preset count, preset-folder, rescan, and bundled-preset Finder actions have been removed from the generic Visualizations menu.
- **Main-window spectrum can be disabled** — Visuals > Spectrum Analyzer > Main Window > Mode now includes **Off**, matching Winamp's blank main-display option so compatible skins can show their prepared artwork without an analyzer overlay.
- **Homebrew cask install** — NullPlayer can now be installed via a personal tap: `brew install --cask ad-repo/nullplayer/nullplayer`. The cask strips the quarantine attribute on install (the app is still ad-hoc signed; Developer ID notarization is on the roadmap). `scripts/build_dmg.sh` now prints the final DMG SHA256 for the per-release cask bump, and `docs/development-workflow.md` documents the release flow.

### Bug Fixes

- **Sonos cast session preserved on Stop and end-of-playlist** — pressing the player Stop button or reaching the end of a playlist now sends Stop to Sonos without disconnecting the active Sonos target or ungrouping rooms, so the next compatible track can resume on the same speaker/group. Chromecast and non-Sonos DLNA still use the existing full-disconnect behavior.
- **Library source switching from Radio fixed** — selecting a different source while the Library Browser is on the Radio tab now keeps the Radio tab active and loads that source's library-radio view instead of forcing the browser back to Artists. Fixed in both classic and modern library browsers.
- **Internet radio column sorting fixed** — radio station columns now sort correctly in both classic and modern library browsers, including rating-aware sorting without repeated rating-store lookups during comparisons.

## 0.23.0

### New Features

- **Met Museum Art visualization** — a new ProjectM-peer engine in the visualization window displays a slideshow of public-domain artwork from the Metropolitan Museum of Art's Open Access collection. Right-click and keyboard hotkeys (→ / ← advance, R random, F fullscreen) work in both classic and modern UI. The context menu exposes Department filtering, slideshow interval, transition style (Crossfade / Ken Burns / Beat Cut / Slide), transition duration, aspect ratio (Fit / Fill / Stretch), Audio-Modulated Effects, Beat-Triggered Changes, Show Artist & Title, and image-cache clearing. Downloaded images are persisted to an on-disk cache and the Met API client throttles requests to stay under the public-API rate limit.
- **Tripex visualization** — the ben-marsh/tripex Direct3D9 visualization is ported to OpenGL and integrated as another ProjectM-peer engine, selectable from the **Visualization Engine** submenu in both classic and modern UI. Audio is fed through a shared ring buffer; the engine port and renderer details are documented in the new `tripex-port` skill.

### Improvements

- **Library browser columns are configurable across UI modes** — classic and modern library browsers now share the same Artist, Album, and Track column inventories, with sectioned right-click header menus for Artists and Albums. Classic column visibility persists separately from Modern, and the Title column remains locked on.
- **Per-engine visualization preferences** — preferences for ProjectM, Geiss, Tripex, and Met Museum no longer share UserDefaults keys, so switching engines preserves each one's independent settings (active preset/effect/department, transition, aspect, audio-reactivity, etc.).
- **Data tab — artist track drill-down** — selecting an artist in the Data tab now shows that artist's individual tracks with play counts and listen time. Track details are cleared before each stats refresh to prevent stale entries from a previous selection bleeding through.
- **Data tab — unknown genres preserved** — tracks with missing or unknown genre metadata are now kept visible in the Data tab breakdown instead of being filtered out, with a reconcile tooltip explaining how unknown entries are grouped.
- **Data tab — sparse sections collapsed** — list sections in the Data tab now collapse when they contain few entries, keeping the overview compact when a category has little data.
- **Library source menu — local and radio separated** — the library source picker now lists local-library and internet-radio entries in distinct sections with a separator between them, matching the way casting and source contexts handle the two origins.
- **Sonos cast preserved on source switch** — switching between library sources (local, Plex, Subsonic, Jellyfin, Emby, radio) no longer tears down an active Sonos cast session. The cast keeps streaming the current track and picks up the next track from the newly selected source.

### Bug Fixes

- **Audio route-change exception guarded** — `AVAudioEngine` graph reconnects now catch Objective-C exceptions raised by `AVAudioEngine.connect(_:to:format:)` during route churn. A failed reconnect is deferred and retried through the existing audio graph recovery path instead of aborting the app.
- **Sonos network-change recovery** — Sonos casts now survive Wi-Fi network/interface changes. `UPnPManager` watches the active network interface and, when it changes, refreshes the embedded media server's bind address and re-resolves Sonos devices on the new network instead of leaving the cast pointed at a dead address.

## 0.22.0

### New Features

- **Geiss visualization** — a port of Ryan Geiss's classic Winamp visualization is available alongside ProjectM in both classic and modern UI. The right-click context menu exposes effect navigation plus runtime levers: Geiss Sensitivity, Gamma, Beat Detection, Sync Color to Sound, Slide Shift, Mode Lock, Palette Lock, Auto-Switch interval, Visualization Mode (Wave/Spectrum), and Randomize Palette. The visualization fills the window, reacts to audio state (paused/silent/playing), and all settings persist across launches.

### Improvements

- **Spectrum analyzer modes refined** — Ultra now uses a denser professional analyzer look with cropped sub-frequency mapping, controlled low-bass shaping, fast decay, and clean peak caps. Enhanced has the same cropped sub curve in a compact LED presentation. Classic keeps a low-fi skin-palette aesthetic with stepped bars and chunky peaks while sharing the cropped analyzer curve so the sub range no longer appears as a shelf or empty left gap.
- **Visualization menus aligned** — main-window and spectrum-window visualization menus now use the same user-facing order and labels, with Classic/Enhanced/Ultra first, visual effects next, and `vis_classic` last.

### Bug Fixes

- **Main window transparency after occlusion fixed** — the main window no longer renders partially transparent after being occluded, minimized, or hidden behind other windows. Returning to visibility now triggers a full redraw rather than relying on per-tick sub-region repaints.
- **Internet radio Sonos discovery and cast classification fixed** — internet radio is now correctly treated as non-local for cast logging and Sonos device discovery. A new explicit `isRadioOrigin` flag on `Track` ensures radio sessions are routed and reported correctly when casting.
- **Classic playlist / spectrum / waveform / projectM / library chrome rebuilt as a continuous U-shape border** — these windows now render with a visible 7px bottom strip matching the side borders' artwork, side borders that extend through the bottom-corner regions, and a continuous gold-trim outline that wraps left → bottom → right with no slits at the corners. The top-right corner is also fixed to mirror the leftCorner sprite (with the close/shade button icons re-drawn on top), eliminating the offset that previously left the interior content area wider under the title bar than below it. Tile destinations are pixel-snapped to prevent the sub-pixel blue seams that appear at fractional `Skin.scaleFactor` values.

## 0.21.1

### Bug Fixes

- **Audio route-change crash fixed** — local audio graph rebuilds are now deferred while Chromecast, Sonos, DLNA, AirPlay-style, Zoom, or Wi-Fi-backed route changes are still active. This prevents an `AVAudioEngineGraph::UpdateGraphAfterReconfig` crash when switching rooms or outputs during casting, and preserves queued local playback intents once the route stabilizes.

## 0.21.0

### New Features

- **Output device analytics** — play events now record which audio output device (or cast target) was active. A new Output Devices breakdown chart appears in the Data tab with the same filter-and-chip interaction as Source and Genre. Cast sessions record the Chromecast, Sonos, or DLNA device name instead of the local CoreAudio output.
- **EKG visualization mode** — the main window and spectrum window now include a BPM-synced EKG mode in both classic and modern UI paths. The persistent Metal trace preserves already-drawn history while the scan head renders new beats, peak height follows raw PCM amplitude, and EKG Style menus offer Clinical, Cyan, Amber, Neon, Crimson, and Ice palettes.
- **Classic library Data tab** — the classic library browser now has a Data tab with the same play-history analytics available in the modern UI, including time-range filtering and source/genre breakdowns.
- **Media-specific Data tab charts** — the Data tab overview now shows separate Top Movies and Top TV Shows sections alongside Top Artists. TV episode events are grouped by show name. Internet radio listen sessions appear in a dedicated Internet Radio section ranked by station plays and total listen time.
- **Internet radio play history** — internet radio sessions are now recorded in play history with pause-aware duration tracking, 30-minute checkpoints for long sessions, and app-quit flushing.

### Improvements

- **Modern marquee art padding balanced** — album artwork in the modern main window marquee now has equal padding on both sides.
- **Data tab section order refined** — the dedicated Internet Radio section now appears directly below Top TV Shows in both classic and modern library browsers.

### Bug Fixes

- **Dock icon size fixed** — the app icon is now correctly sized in the Dock, matching the visual weight of neighboring icons. The symbol cutout renders correctly on dark backgrounds.
- **Classic auxiliary window borders fixed** — the library browser now uses matching ProjectM-style side borders without reserving scrollbar space, its title bar border remains continuous with visible window controls, and the playlist bottom border matches the waveform, spectrum, ProjectM, and library windows.
- **Output device color overflow fixed** — the hash function used to assign colors to output devices no longer traps on `Int.min` overflow.
- **Classic ProjectM fullscreen fixed** — the classic ProjectM visualizer no longer snaps down below the notch/menu-bar safe area shortly after entering fullscreen.

## 0.20.0

### New Features

- **Sleep Timer** — stop playback automatically via **Playback > Sleep Timer**. Three modes: timed durations (5, 10, 15, 30, 45, 60, 90 minutes, or 2, 5, 8, 12 hours) with a 10-second volume fade-out before firing; end of current track; end of queue. The active preset shows a live countdown in the submenu. Selecting it again cancels. Volume is restored if cancelled mid-fade.
- **Modern marquee album art** — the modern main window marquee now shows album artwork alongside scrolling track metadata.
- **Installable `nullplayer` CLI launcher** — releases now include a `nullplayer` launcher script, an installer, and a double-click `.command` helper for installing it into `/usr/local/bin`.
- **Modern timer number system options** — the modern UI timer supports additional number system styles for its time display.

### Improvements

- **Classic window borders aligned** — the playlist, spectrum analyzer, and waveform windows use identical 12 px side borders from the skin's `pledit.bmp` tile sprites, so windows sit flush when docked.
- **Classic playlist uses system font** — classic playlist rows now render with the system font instead of the skin bitmap font, improving legibility across all skins.
- **Classic playlist scrolling smoothed** — trackpad scrolling uses precise deltas and redraws only the list area; overflowing track titles use a layer-backed marquee instead of timer-driven full redraws.
- **Preferred video cast device routing** — video-capable Chromecast and DLNA TV devices can be set as the preferred video cast target. Starting another video while a cast is active routes it to the active device; selecting a device in a non-video context no longer forces subsequent videos to cast.
- **Video and audio cast menus separated** — the output menu treats video and audio casting as independent contexts, keeping audio playback explicit while letting active video casts continue on the TV.
- **Spectrum bar jitter removed** — Classic and CPU Spectrum modes no longer stutter at startup or when cycling modes. `AudioEngine` now coalesces spectrum dispatches to the main thread the same way `StreamingAudioPlayer` already did.
- **Punch spectrum mode removed** — the Punch mode has been removed from both the spectrum window and the main window visualization cycle.
- **Plex models consolidated into core** — Plex models now live in `NullPlayerCore` with public initializers and smart-playlist content decoding, shared across the app, CLI, and tests.

### Bug Fixes

#### Casting — Chromecast

- **Cast notifications always delivered on main thread** — `ChromecastManager` and `UPnPManager` are not `@MainActor`, so their notification posts arrived on background threads. Any observer touching AppKit would crash (`NSWindow geometry should only be modified on the main thread`). All cast notifications (`sessionDidChange`, `playbackStateDidChange`, `devicesDidChange`) now post through `CastManager.postNotificationOnMain`, which dispatches asynchronously when called off main.
- **Chromecast IDLE race hardened** — the initial IDLE that Chromecast sends when a new media session is created is now ignored until active playback (`PLAYING` or `BUFFERING`) has been observed. The guard flag is reset before each `LOAD` call and at the top of `stopCasting()`, eliminating failures on second and subsequent casts and across video→audio transitions.
- **Duplicate Chromecast devices removed** — Chromecast discovery now keys devices by the stable Cast TXT `id` record, falling back to the Bonjour service name, and updates existing entries when the resolved address changes. This prevents refresh from showing the same device twice on Macs that resolve it through different address forms.
- **Audio cast controls and seek bar fixed** — play/pause/stop controls and seek bar position now work correctly during audio casts. The status handler was gated on `.casting` state but audio starts in `.loaded`; it now branches on `currentCast == .audio`. Position interpolation uses `activeSession.position` and `activeSession.playbackStartDate` updated from each status message, matching the video tracking pattern. The seek bar freezes correctly when paused or buffering.
- **Stop dismisses the cast from the TV screen** — stopping a cast now closes the Default Media Receiver app on the Chromecast (sends STOP to `receiver-0`), triggering HDMI-CEC to clear the cast overlay from the TV. A 200 ms flush delay between the media STOP and socket disconnect ensures the command is delivered before the connection closes.
- **Video cast cleanup always runs on stop** — `wasVideoCast` is now captured before `activeSession` is cleared, so `clearVideoTrackInfo()` on the main window fires reliably when stopping a video cast.
- **Video player closes automatically when switching to audio cast** — when casting audio while the video player is open from a video cast, the video player window closes without interrupting the new audio session. This prevents stale video controls from remaining active.
- **Chromecast video cast controls fixed** — main-window video controls (play/pause, seek, skip, stop, title, duration, playback state) now correctly follow `CastManager` video cast state when casting from the context menu or switching videos on an active session.
- **Generic video URL casting fixed** — local-library video entries and video playlist tracks now cast correctly through `CastManager.castVideoURL(...)`, including local-file registration through the embedded media server.

#### Casting — Sonos

- **Sonos seek bar and position tracking fixed** — `activeSession.position` and `activeSession.playbackStartDate` are now initialized at cast start and updated on each PLAYING poll, enabling correct time interpolation. The seek bar freezes correctly when paused.
- **Stop button ends the Sonos cast session** — the stop handler now calls `stopCasting()` for all device types; previously Sonos only called `stopPlayback()`, leaving the session alive.
- **Sonos format filtering fixed for extensionless streams** — streams without file extensions now use `Track.contentType` for format identification, normalize MIME parameters case-insensitively, fetch missing Plex sample rates for lossless tracks, and reject unsupported or high-resolution formats before sending them to Sonos.
- **Plex stream content type preserved** — Plex tracks retain enough MIME information on extensionless URLs for Sonos casting compatibility checks.

#### Windows and UI

- **Classic stack windows collapse when closed via X** — closing a stacked sub-window (EQ, Playlist, Spectrum, Waveform) using its close button now slides up windows below it and tightens the stack.
- **Remember State no longer auto-resumes on launch** — restoring a saved session selects the current track for display only; the app starts paused instead of immediately resuming.
- **Modern marquee video artwork fixed** — switching from music to movies or TV in modern mode now replaces stale music artwork with the active video artwork.
- **Window toggle crash fixed** — Playlist, Equalizer, Spectrum, and Waveform toggles no longer force-unwrap window frames when hiding visible windows.

## 0.19.3

### Bug Fixes

- **External monitor display-link crash fixed** — ProjectM and the spectrum visualizer no longer create or re-pin `CVDisplayLink` objects before their views are associated with a real display. This fixes a GPU kernel panic/crash path seen on Apple Silicon Macs with external monitors connected at launch or when the display topology changed.
- **ProjectM startup restored** — the display-link safety guard introduced for the monitor crash no longer blocks ProjectM from starting up normally.
- **Safer display re-pinning** — OpenGL display-link updates now use the window screen's direct display ID instead of the older CGL-context rebind path, avoiding another unsafe re-association window during screen changes.
- **Spectrum display-change resync fixed** — the spectrum layer now resynchronizes when displays change so visualization rendering stays aligned after moving windows between monitors or changing monitor configuration.

## 0.19.2

### New Features

- **Content type tracking in play history** — play history now records content type (music, movies, TV, radio) for each play event, enabling per-type analytics.
- **Expanded Now Playing info panel** — the right-click Now Playing panel now shows all available metadata. Local library tracks show album artist, year, track/disc number, composer, BPM, key, file size, play count, rating, last played, date added, comment, grouping, ISRC, copyright, and MusicBrainz/Discogs IDs. Non-library local files read additional tags (album artist, etc.) directly from AVAsset. Streaming sources (Subsonic, Jellyfin, Emby, Plex) now fetch full song detail asynchronously for display.

### Bug Fixes

- **Chromecast idle timer fix** — the main window timer no longer keeps running after Chromecast content ends and the device goes idle. Previously the IDLE status was treated as a pause, preventing auto-advance from firing.
- **Audio engine config change fix** — the audio engine now stops before rebuilding its processing graph when configuration changes, preventing invalid-state crashes.
- **Sonos volume/mute now controls the full group** — volume and mute now use `GroupRenderingControl` instead of `RenderingControl`. The old service only affected the coordinator speaker, so adjusting volume had no effect after adding rooms to a group.
- **Plex video library browsing fixed** — movie and TV show browsing now auto-resolves the correct library rather than always querying the current music library, which returned empty results. Both browser views also now automatically switch to the correct browse mode (artists/movies/shows) when a library is selected.
- **Jellyfin/Emby video play history attribution fixed** — video tracks played from Jellyfin and Emby playlists now record the correct server source in play history instead of being attributed to local playback.
- **Video play analytics source detection restored** — Plex, Jellyfin, and Emby video play events now correctly attribute their server source in analytics (was accidentally hardcoded to "local" after a prior revert).
- **Cast idle completion hardened** — cast track completion now correctly handles IDLE status transitions, preventing missed auto-advance events and stale analytics.
- **Database init order fix** — `MediaLibraryStore` now assigns the `db` handle only after schema setup succeeds, so a failed migration leaves the store in a safe nil state rather than pointing at an un-migrated schema.
- **Window resize grab zones widened** — bottom and side resize edges are now easier to grab (8→12 px on borderless windows, 12→14 px on resizable windows) without affecting top edges where docked-window dragging is sensitive.

### Cosmetic

- **Glass skin opacity increased** — BloodGlass, SeaGlass, and SmoothGlass bundled skins have higher element opacity for better readability.
- **Right-click context menu reorganized** — menu items are regrouped with clearer separators between display toggles, window actions, settings, and exit. Items renamed for clarity: "Now Playing…", "Remember State", "Minimize All".

## 0.19.1

### Bug Fixes

- **Audio distortion after long idle fixed** — removed the `AUDynamicsProcessor` limiter from the audio chain. The node caused intermittent heavy distortion after macOS put the audio hardware into a power-saving state: `AVAudioEngineConfigurationChange` would fire, reconnect the node, and reset it to Apple's aggressive defaults (threshold −20 dB, 2:1 expansion) with no way to recover without restarting the app. Signal chain is now `playerNode → mixerNode → eqNode → output`.
- **Play/radio history no longer lost on quit** — history writes and play-event inserts now complete synchronously before the process exits. Cast track completions also now record play events (previously missing). The MediaLibrary WAL is checkpointed and closed on `applicationWillTerminate` to flush any pending writes before shutdown.

### Security

- **Redact auth tokens from logs** — Subsonic credentials (`u`, `t`, `s`) and Plex tokens (`X-Plex-Token`) are now stripped from all NSLog output. A shared `URL.redacted` extension covers streaming playback, gapless queue, cast, and recovery log sites.

## 0.19.0

### Play History (modern UI)

- **Play History analytics window (modern UI)** — added a modern analytics window that records listening events and persists history data across launches.
- **Play History in Library Data tab** — embedded play-history analytics directly into the modern Library Browser Data tab.
- **Genre discovery for history events** — added genre enrichment for play-history events to improve genre-based insights.
- **Play time and source summaries** — added total listening-time summaries and source-level breakdowns in the Data tab.
- **Top artists limit raised to 250** — the Data tab top-artists list now shows up to 250 entries.
- **Various Artists history attribution** — play history entries now use the track artist rather than "Various Artists" for compilation tracks.

### 21-Band EQ (modern UI)

- **Real 21-band equalizer (modern UI)** — modern mode now runs a full 21-band EQ processing chain (local and streaming), with updated presets/state mapping and a matching 21-band UI.
- **EQ fader grid style** — replaced the harsh grid borders on EQ faders with subtle vertical dividers.

### Radio

- **Radio playlist controls** — added playlist-level controls for radio playback behavior.
- **Library radio loading spinner** — a spinner is now shown while a library radio playlist is being generated.
- **Library radio hardening** — improved library radio playlist generation reliability.

### Local Library

- **Offline watch folder volumes surfaced** — watch folder entries for network volumes that are currently offline are now visible in the library UI so users can see which folders are unavailable.

### Library Browser

- **Search input accepts spaces** — the library browser search field no longer drops space characters mid-input.
- **Duplicate search results eliminated** — search results no longer show duplicate artists, albums, or tracks across sections or Plex libraries.
- **Plex search deduplication** — Plex search results are deduplicated by content identity rather than raw rating key, preventing the same item from appearing multiple times.
- **Plex search session fix** — Plex search now uses the configured server session, fixing searches that previously failed to authenticate.
- **Enter-to-search** — pressing Enter in the library browser search field now triggers the search immediately.
- **Remote search debounce** — remote library searches are debounced to avoid flooding the server with a request per keystroke.

### Playback

- **NAS audio dropout fix** — local files on network-mounted volumes (SMB/NFS/AFP) are now copied to a local temp path before scheduling with AVAudioPlayerNode, eliminating dropouts caused by NAS latency spikes stalling the engine's pre-fetch thread.
- **Zero-duration display fix** — tracks added via drag-and-drop, local radio, or state restore that had no duration now resolve their duration from the MediaLibrary index (instant) or a background AVAudioFile read, and update the playlist display without blocking the UI.
- **Fast app launch with large NAS playlists** — playlist state restore no longer opens each local file via AVAudioFile/AVAsset on the main thread at launch; saved metadata is used directly, eliminating multi-minute hangs on large NAS playlists.
- **Shuffle algorithm rewrite** — the shuffle playback cycle now correctly visits every track exactly once before repeating, anchors the cycle at the selected track when the user picks a specific song, and generates a fresh non-repeating order on each new cycle when Repeat is enabled. Explicit track selection mid-shuffle resets the cycle around the chosen track. Covered by tests for full-cycle coverage, repeat-cycle transitions, range-anchored starts, and mid-cycle selection resets.
- **Shuffle load race fix** — shuffle state mutation is now deferred until track load succeeds, preventing a race where a failed load left shuffle order in an inconsistent state.
- **Waveform prerender and corrupt stream fix** — fixed waveform prerender extension logic and a loop condition triggered by corrupt or truncated stream data.

### Stability

- **EQPreset startup crash fix** — fixed a crash at launch caused by invalid hex characters in UUID strings read from EQ preset storage.
- **NAS library scan deadlock fix** — eliminated a deadlock where filesystem I/O inside the `dataQueue` lock during a library scan blocked the main thread when a library-change notification fired concurrently.

## 0.18.1

### Visualization

- **vis_classic decay consistency** — fixed decay divergence between the main window and spectrum window when they run at different frame rates.
- **Shared vis_classic core** — the main window and spectrum window now share a single vis_classic core instance, eliminating state duplication.
- **Classic spectrum width fix** — fixed the classic spectrum not filling the full width of the analyzer window.
- **Main spectrum redraw rect fix** — corrected a coordinate conversion error in the main window spectrum redraw rect.
- **vis_classic jerkiness fix** — restored synchronous process+draw per frame to eliminate jerkiness in the classic visualizer.

### Library Browser

- **Gold star ratings** — filled ★ characters now render in gold in rating list columns (classic browser) and all Rate context submenu items (both classic and modern browsers).
- **Local metadata editing flow** — expanded the modern library metadata editor for local tracks, albums, and videos with broader field coverage, improved form layout, and shared metadata form helpers.
- **Classic metadata editor parity** — the classic library browser now exposes local `Edit Tags`, `Edit Album Tags`, and video `Edit Tags` actions, reusing the shared metadata editors and reloading local browser state after saves to prevent stale rows.
- **Auto-tagging from Discogs and MusicBrainz** — local tracks and albums can now search Discogs/MusicBrainz candidates, preview the proposed metadata, and apply merged results back into the library.
- **Album candidate review panel** — album auto-tagging now includes a dedicated candidate selection window with per-track comparison so releases can be reviewed before applying changes.
- **Artwork metadata support** — metadata editors now load and preview artwork more consistently, including remote artwork URLs used during metadata editing.
- **Navidrome alphabet navigation fix** — fixed alphabet bar navigation in the Navidrome browser.
- **Typeahead search in classic browser** — added typeahead/search input to the classic library browser.

### Local Library

- **Metadata persistence expansion** — local library save/update paths now persist the new metadata fields used by the editor and auto-tagging flow, including external IDs and artwork-related values.
- **Library update propagation** — metadata edits now trigger the necessary shared-library refresh behavior so edited values appear correctly across the browser and related views.

### Playback

- **Sleep/wake timer freeze** — local playback time no longer accumulates while the Mac is asleep; the play clock resumes from the pre-sleep position on wake.
- **Explicit restore intent** — saved-state restore now explicitly uses the persisted `wasPlaying` flag to decide whether launch should end in playing or paused state, while preserving the current user-visible startup behavior.

### Casting

- **Chromecast disconnect crash fix** — connecting to a Chromecast device no longer risks a continuation-resume crash if the device goes offline immediately afterward.
- **Sonos radio handoff fix** — switching radio playback to Sonos no longer risks restarting the same stream locally while the cast session is still coming up.
- **Discovery refresh guard** — cast discovery refresh work is now skipped during local playback to avoid unnecessary churn while the user is listening locally.

### Resources

- **App icon format fix** — the app icon asset is now stored as a proper PNG.
- **Version bump** — `CFBundleShortVersionString` is now `0.18.1`.

### Documentation

- **Playback follow-up report** — captured the remaining architectural issues around playback clocks, restore semantics, and testability that are intentionally out of scope for the conservative fix.

## 0.18.0

### CLI Mode

- **Headless playback** — NullPlayer can now run without a UI via `--cli` flag, enabling scriptable playback from the terminal.
- **Full keyboard control** — play/pause, skip, seek, volume, shuffle, repeat, and quit all work from the terminal in CLI mode.
- **Auto-exit on queue end** — the process exits automatically when the queue finishes playing; guarded by a `hasStartedPlaying` flag to prevent premature exit during async startup.
- **Source resolution** — CLI mode resolves the same library sources (local files, Plex, Subsonic, Jellyfin, Emby) as the UI.

### Window System

- **Window layout lock** — a new lock mode prevents all windows from being moved or resized until unlocked, useful for fixed desktop setups.
- **Large UI improvements** — Large UI is now 1.5× scale with corrected text scaling and waveform scaling.
- **Minimize All Windows** — a "Minimize All Windows" item is now available in the Windows menu.
- **Stretch + session restore for spectrum and playlist** — the spectrum and playlist windows can now be freely resized horizontally, and their last-set size is restored on reopen.
- **Active window stays on top during bring-to-front** — the currently active window is no longer pushed behind peers when bringing a group to the front.
- **Library window group drag** — the library window now correctly activates and participates in connected-window group drags.

### ProjectM

- **Preset star ratings** — ProjectM presets can be rated 1–5 stars directly from the visualization overlay. Ratings persist across sessions.
- **Rating overlay** — a five-star overlay appears on mouse hover in ProjectM; Delete/Backspace clears the rating for the current preset.
- **Persistent default preset** — a preset can be set as the default and will be loaded on every launch.
- **Presets menu renamed** — the ProjectM presets menu is renamed for clarity, and preset list entries now show gold stars for rated presets.
- **Proportional drag and ratings zones** — the top quarter of the ProjectM window is the drag handle; the bottom three quarters show the ratings overlay on click. Applies to both classic and modern UI.

### Visualizations

- **Art mode effect picker** — a grouped effect picker is now available in both the modern and classic art mode context menus, with a "Set as Default" option to persist the preferred effect across sessions.
- **Library and ProjectM window highlights** — the Library Browser and ProjectM windows now show a connected-window highlight when docked, matching the behavior of other windows.
- **Media controls type fix** — `MPNowPlayingInfoPropertyMediaType` is now correctly set to audio, fixing incorrect type metadata in the system media controls overlay.

### Library Browser

- **Rating column** — a rating column with gold stars is now shown in the library track list and in art-only mode, for all connected sources (local, Plex, Subsonic, Jellyfin, Emby). The column appears as the first column in the artist view.
- **Live rating updates** — ratings changed via the context menu now immediately update in the library list without requiring a refresh.
- **Horizontal scroll** — the library browser now supports horizontal scrolling when columns overflow the visible width.

### Local Library

- **Multi-artist support** — artist tags are now parsed into individual artist entries via a new `track_artists` join table (schema v3). Artists joined by `;` or `feat.`/`ft.` are stored as separate rows, enabling accurate per-artist browsing and radio.
- **Artist split fix** — `/` is no longer treated as a multi-artist separator, so artist names like `AC/DC` are no longer incorrectly split.
- **Album grouping** — album queries now group exclusively by `album_artist`, removing a fallback to the `artist` tag that caused incorrect album grouping.
- **Art window rating fix** — rating a track in art mode no longer moves the art window.
- **Occlusion cache on resize** — the window occlusion cache is now cleared on resize, fixing stale border segments after window size changes.

### Modern Skins

- **Element-level color overrides** — skin.json now supports per-element color keys in the `elements` block: `play_controls`, `seek_fill`, `volume_fill`, `minicontrol_buttons`, `playlist_text`, `tab_outline`, and `tab_text`, each with a typed fallback chain to palette colors.
- **Spectrum transparent background** — `window.spectrumTransparentBackground` (bool) in skin.json sets the spectrum window transparent background, using the same mechanism as the in-app toggle.
- **Waveform window opacity** — `window.waveformWindowOpacity` (float 0–1) in skin.json independently controls the waveform window background opacity, separate from the global `window.opacity`.
- **Save State on Exit in Windows menu** — "Save State on Exit" is now available in the Windows menu bar menu for quick access to session state persistence.

### Bug Fixes

- Fixed waveform squashing on horizontal resize in the classic skin
- Fixed waveform returning to 1× from Large UI
- Fixed waveform frame resetting on show/hide (now only resets on full close/reopen)
- Fixed waveform transparency not restoring after switching between classic and modern UI modes
- Fixed waveform pre-rendering for streaming service tracks
- Fixed classic main-window accepting edge resize gestures while docked
- Fixed window snapping re-entrancy recursion crash
- Fixed drag-mode group highlight activating incorrectly on startup
- Fixed classic ProjectM drag-detach leaving visualization paused
- Fixed intermittent playlist text disappearance in classic and modern views
- Fixed classic playlist titlebar tiling at stretched widths
- Fixed modern HT main-window stretching incorrectly when the display panel expands
- Honored `marqueeSize` from skin definition on skin reload; bumped modern UI marquee size
- Cleared stale cover art when switching to a track with no embedded artwork
- Removed output device selection from main window context menu
- Updated app icon
- Fixed SSDP socket crash on UPnP scan teardown (closed fd immediately after async cancel, triggering a kevent-vanished SIGSEGV in libdispatch; now closed inside the cancel handler)
- Fixed ProjectM 1–5 star keycode mapping (key "5" was silently dropped; key "6" was accepted as 5 stars)
- Fixed side windows (ProjectM, Library Browser) opening at the edge of only the vertical stack instead of the full cluster of docked windows
- Fixed glass/modern skin appearing fully transparent on app reopen when a partial-dirty draw fired before the first full draw
- Fixed spectrum transparent-background preference not restoring on launch in vis_classic exact mode (bridge created in render path skipped preference restore when mode was already active at init)
- Fixed spectrum window width not being preserved during classic window-stack repair
- Fixed play clock stuck at 00:00 after app restart when a previous track was restored (seek-while-paused during state restore never notified the UI)

## 0.17.3

### Window System

- **Hold-to-group drag** — windows now use a time-based drag model instead of a distance threshold. A quick drag (< 400 ms hold) separates the grabbed window from its group; a longer hold (≥ 400 ms) moves all connected windows together.
- **Drag group preview** — connected peer windows show a subtle highlight overlay at mouseDown so it's clear which windows will move as a group before the drag begins.
- **Group screen-edge clamping** — when dragging a connected group, the entire group is clamped so no window is pushed off-screen at the top of the display.
- **ProjectM suspend during drag** — ProjectM rendering is suspended for the duration of a window drag to prevent WindowServer stalls on Apple Silicon.

## 0.17.2

### Waveform

- **Horizontal stretch** — the waveform window can now be resized horizontally to any width, not just the default fixed size.
- **Size preserved across sessions** — the waveform window no longer resets to its default size when reopened; the last user-set size is restored.

### Visualizations

- **Classic spectrum/waveform transparency** — the transparent-background setting for classic spectrum and waveform visualizations no longer resets to off on every launch.

## 0.17.1

### Local Library

- **Manage Folders window** — the watch-folder list is now a proper resizable window instead of an alert sheet, with full editing support on large network-volume libraries that previously appeared empty.
- **Manage Folders in context menu** — a direct "Manage Folders…" link is now available in the Local Library context menu.
- **Import pipeline optimized** — the scan-to-import handoff is restructured to reduce redundant work on large libraries and NAS volumes; scan signatures are no longer persisted for fast-track entries before enrichment completes.
- **NAS safety: skip cleanup on empty scan** — library cleanup is skipped when a NAS returns 0 files, preventing accidental removal of the entire library when the volume is temporarily unreachable.
- **Scanning animation fixes** — the progress animation no longer stops mid-import or persists after a scan is cancelled.
- **Library toolbar count** — the toolbar now shows the total track count instead of the paginated-page count.
- **Alphabet navigation** — letter-jump navigation now works across all pages in the local library, not just the first.
- **Library browser layering** — the library browser no longer appears behind main center-stack windows when they overlap.
- **Border gap fixed** — the classic library browser no longer shows a gap at the scan-animation border.
- **Context menu track count** — the library context menu now shows the correct track count; orphaned DB tracks that couldn't previously be cleared can now be removed.

### Async Local Track Transitions

- **Beachball-free auto-advance** — opening the next local file is now performed on a background I/O queue (`advanceToLocalTrackAsync`) so the main thread is never blocked during track transitions.
- **Beachball-free Sweet Fades** — crossfade file opens are also moved to the background I/O queue and guarded by a `crossfadeFileLoadToken` to prevent stale loads from arriving late.

### Visualizations

- **vis_classic crash fix** — resolved a data race between the CVDisplayLink callback thread and the main thread accessing the C++ vis_classic core.
- **Spectrum/waveform border fix** — the classic spectrum and waveform visualizations no longer occlude the left and right window borders.
- **Double Size crash fix** — toggling Double Size no longer crashes with a stack overflow; the animated window repositioning triggered infinite recursion in the docked-window movement loop.

## 0.17.0

### Window System

- **Hide Title Bars extended to all windows** — sub-windows (EQ, Playlist, Spectrum) now always hide their titlebars when docked. With Hide Title Bars enabled, all six windows hide titlebars unconditionally. Now defaults to on. The main window shrinks to fill the frame without a gap at the top.
- **Per-corner window sharpness** — corners automatically sharpen when a window is aligned against a screen edge or adjacent docked window, so the UI looks clean against boundaries without hard corners everywhere else.
- **XL mode** — the 2X double-size button is now XL at 1.5× scale, giving a more usable intermediate size. State buttons (shuffle, repeat, etc.) are reordered.
- **Docking fixes** — resolved nine window behavior issues: over-eager snapping, window shift on undock, stack collapse gaps, HT startup sizing, and more.
- **Menu bar parity** — key player actions are now available from the macOS menu bar with dynamically refreshed checkmarks/state (Windows, Skins, Playback, Visuals, Libraries, Output).

### Modern Glass Skins

- **Skin-configurable window opacity** — `window.opacity` in skin.json sets background transparency per-window. Sub-windows can inherit or override independently.
- **Per-area opacity controls** — skins can set opacity independently for each region (display panel, playlist area, EQ bands, etc.) without affecting the rest of the window.
- **Text-only opacity** — a separate opacity knob for display text vs background glass, enabling frosted-glass aesthetics where the text reads clearly against a blurred background.
- **Spectrum opacity override** — the spectrum visualization layer has its own opacity control, independent of window opacity, so glass skins can keep the spectrum vivid.
- **Glass seam/darkening stability** — improved seam clearing and glass compositing so docked stacks stay visually consistent during moves and resizes.
- **New bundled skins** — NeonWave (default), SeaGlass, SmoothGlass, BloodGlass, and BananaParty are included.

### Waveform

- **Dockable waveform window** — a new Waveform window can be shown/hidden like other sub-windows and docks into the main stack.
- **Skin-configurable appearance** — waveform supports transparent background styles in modern skins and integrates with modern UI controls.

### Internet Radio

- **Folder organization** — stations can be organized into an expandable folder tree, visible in both the modern and classic library browsers. Folders persist across sessions. Smart reassignment moves a station's history and ratings when it changes folders.
- **Station ratings** — rate any internet radio station 1–10 directly in the library. Ratings are stored in a local SQLite database keyed by station URL and survive station edits.
- **Station artwork** — album art now loads for internet radio stations in both the modern and classic library browsers.
- **Station search** — search internet radio by metadata (name/genre/region/URL) with click-to-play results.
- **Expanded built-in catalog** — full SomaFM channel list added as defaults and auto-merged for existing users. Regional stations, jazz stations, verified Boston and scanner feeds included.
- **Grouped radio history** — playback histories from all sources (Plex, Subsonic, Jellyfin, Emby, local) are now consolidated under a single Radio History menu instead of scattered per-source.

### vis_classic

- **Exact mode** — vis_classic now runs as a faithful Winamp-replica visualizer with full FFT, bar, and color fidelity matching the original Nullsoft implementation.
- **Scoped profiles** — the main window and spectrum window each maintain their own independent vis_classic profile and fit-to-width setting. Changing one doesn't affect the other.
- **Skin visualization defaults** — skins can declare a default visualization mode and vis_classic profile in skin.json. The bundled classic skin defaults to the Purple Neon profile.
- **Bundled profile pack** — a full set of classic vis_classic profiles are included by default for quick switching.
- **Transparent background controls** — skins can default vis_classic transparency per-window and control its opacity independently for main vs spectrum windows.

### New Visualizations

- **Snow mode** — a new Metal spectrum shader that renders the frequency spectrum as falling snow particles.

### Classic Library UI

- **Local album and artist ratings** — albums and artists in your local library can now be rated directly in the classic browser. Ratings appear in both list view and art view.
- **Art mode interactions** — single-click an item in art view to rate it; double-click to cycle through its available artwork.
- **Date sorting parity** — the classic library browser now sorts by date and year using the same logic as the modern UI, consistently across all connected sources.
- **Replace Queue in library menus** — the "Replace Queue" action was missing from classic library context menus; it is now present alongside Play and Add to Queue.
- **Source radio parity** — source radio tabs in the classic browser now match the modern UI's behavior including F5 refresh support.
- **Watch folder manager** — manage watched local-library folders (rescan, reveal in Finder, remove with counts) from a dedicated dialog.

### Modern EQ

- **Preset buttons rework** — the preset button row now stretches to fill the available width, buttons are always enabled regardless of whether the EQ is active, and double-clicking a band's label resets that band to 0 dB.

### Other

- **Natural numeric sorting** — library tracks, albums, and artists sort in natural order (Track 2 before Track 10) consistently across all sources.
- **Modern skin bundles** — portable modern skins can be imported as `.nsz` (ZIP) bundles via UI → Modern → Load Skin....
- **Skin import persistence** — imported skins persist and remain selectable in future sessions.
- **Get More Skins** — a link to the skins directory is now in the Classic UI skin menu.
- **Credential storage hardened** — server credentials are stored in the data-protection keychain with a reduced attack surface. Dev builds use UserDefaults to avoid repeated Keychain authorization prompts during development.
- **Licensing/provenance** — added third-party license notices and waveform provenance documentation for distribution.

### Bug Fixes

- Fixed a streaming crossfade deadlock between the crossfade timer and `AVAudioEngine.stop()`
- Fixed streaming playlist restore by refreshing service-backed track URLs when needed (Plex/Subsonic/Jellyfin/Emby)
- Fixed audio engine state desync when handing off from cast back to local playback
- Fixed radio-to-local playback handoff leaving the engine in a stopped state
- Fixed library multi-remove hanging on large selections; added scoped local library clear actions
- Fixed classic library browser rendering artifacts (server bar transparency and incorrect text colors)
- Fixed volume slider not responding to arrow keys in the modern UI
- Fixed waveform window click-through during async waveform loading
- Reduced idle CPU and GPU usage across all spectrum visualization modes and during window dragging
- Improved Jellyfin loading resilience for large libraries (smaller page sizes, duplicate-page guards, background album warming)
