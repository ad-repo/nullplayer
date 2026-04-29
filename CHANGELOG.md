# Changelog

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

- **Playback follow-up report** — added `docs/playback-state-followups.md` to capture the remaining architectural issues around playback clocks, restore semantics, and testability that are intentionally out of scope for the conservative fix.

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
