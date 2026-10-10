# Changelog

## Unreleased

- **Classic skins default the main window to the Classic analyzer** — the main window's
  visualizer now starts on Classic instead of vis_classic, and launching or picking a Classic
  skin no longer resets a mode you chose. A visualization reset still restores Classic.
- **Classic skins with 32-bit bitmaps no longer click through to the desktop** — skins such as
  Donkey Kong Handheld, whose images are saved as 32-bit BMPs, drew normally but let every click
  on the main window fall through to whatever was behind it. NullPlayer read the bitmap's unused
  fourth byte as transparency; it now ignores it, as Winamp does.
- **Classic skins no longer show placeholder paint beside the display** — skins such as Large
  Image showed bright green bars at the clutterbar and behind the cast indicator; the main
  window now draws the skin's clutterbar strip and the mono slot's background, as Winamp does.

## 0.32.1

- **Audion faces no longer draw a hard outline around their shadow** — faces that paint their
  own soft drop shadow, such as BBX • MERCURY™ m2 and Audion XP 1, showed a thin dark line
  around the outer edge of that shadow, because macOS traced it as the window's outline. Faces
  now cast NullPlayer's own shadow, taken from the face's pixels, with no outline.
- **One drop shadow for every skin, under one switch** — Classic, Original, Audion faces and
  every NullPlayer window beside them (playlist, equalizer, Library Browser, the visualizers,
  video) now cast the same soft shadow `.wal` and `.wmz` skins already had, and **Window
  Shadows** in the right-click menu turns it on or off in every skin family.
- **A seamless Original stack casts one shadow** — windows docked together in a seamless skin
  such as NeonWave floated with no shadow at all. The stack now casts one shadow around its
  combined outline, with nothing along the seams, and a window pulled off gets its own back.
- **About window links to nullplayer.fyi** — a new website button sits above GitHub, LinkedIn
  and Reddit, which now carry their logos; the button text and the GitHub star line are no
  longer dark-on-dark.

## 0.32.0

### New features

**Audion faces**
- Support for **Panic Audion** faces. Skins › Audion Faces › Get More Faces... downloads Panic's
  archive; **Load Face...** installs a face folder or `.zip`. Rendered by a port of Panic's
  FaceKit viewer, at any UI Size.
- All face buttons are wired, including ones Panic's viewer left inert: menu → playlist, mode →
  Library Browser, eject → open files, info → track/face credits, volume and clock → sliders.
- Playlist, EQ, Library Browser and visualizer windows take the face's colours and dock to it.
  See `skills/audion-face-guide/reference/user-guide.md`.

**Art window**
- The Library Browser's ART view is now a standalone **Art** window (Windows → Art, or **AR** on
  Original). Follows the playing track, docks under the player, sizes to the cover.
- Click to rate, double-click to cycle embedded pictures, **V** for the 30 audio-reactive effects
  (formerly VIS), **F** for fullscreen. Persists across launches; framed by Winamp Modern skins.
- Radio station logos show as station art, including in Control Center.

**Library Browser**
- View switcher in the source bar: **List**, **Flow** (Cover Flow) and **Tiles**. Tiles is an art
  grid with keyboard navigation, the row context menu, and a **‹ Back** tile. Movies, shows and
  seasons use poster-shaped tiles. Selection is kept when switching; the choice persists.
- A–Z index works in Flow and Tiles.
- Album screen from Flow/Tiles: cover, metadata, review (Plex/Jellyfin/Emby), **▶ Play** and the
  track list over the artist image.
- Round art thumbnails on every row for every source and skin, with a hover preview. Thumbnails
  prefetch ahead of scrolling and are cached on disk.
- Movies, episodes, seasons and shows get **Play / Play and Replace Queue / Play Next / Add to
  Queue** (Plex, Jellyfin, Emby, local). Seasons and shows queue episodes in order.

**YouTube**
- The **Search** tab searches YouTube channels by name (@handle, subscriber count, upload preview,
  subscribe on double-click). Already-followed channels are marked ✓.
- **Art** column with video thumbnails, channel avatars, and art behind the list. Downloads embed a
  square-cropped thumbnail as cover art (video downloads had none before).
- Per-video **Audio** and **Video** submenus. The chosen form downloads on demand, then plays or
  queues. Both forms can coexist; **Show in Finder** / **Remove Audio File** / **Remove Video
  File** manage them. Replaces "Download & Play".
- Format setting split in two. Audio: FLAC, ALAC, MP3 320/256/192/128, AAC 256/192/128, or the
  original AAC/Opus stream with no re-encode. Video: 360p through 2160p, or Best Available (VP9/AV1
  above 1080p). Old settings migrate (MP3 High → 320, MP3 Low → 128).
- Local search includes a **YouTube** section (matching subscribed channels and downloaded videos),
  without querying YouTube. Downloads already listed under Tracks or an expanded channel are not
  duplicated.

**Branding**
- New app icon by Allan Nyholm Nielsen ([#488](https://github.com/ad-repo/nullplayer/issues/488)).

### Changes

- **Unified play menu.** Tracks, albums, artists, playlists, playlist entries and local folders
  offer **Play**, **Play and Replace Queue**, **Play Next** and **Add to Queue** on every source.
  **Add to Playlist** is removed (including from YouTube and Plex video menus); **Add to Queue**
  starts playback on an empty queue. **Shift+Enter** / **Option+Enter** match Play Next / Add to
  Queue. Artists play album by album, oldest first; a newer Play supersedes a pending server fetch.
- **Remember State on Quit** is on by default. Session state is also autosaved every few seconds
  and before sleep, so it survives crashes, kills and power loss.
- Classic (10-band) and Original/Metal (21-band) EQs persist separately. Switching between them no
  longer degrades the curve.
- Double-clicking a movie or episode inserts it into the playlist after the current track instead
  of playing standalone. Casts keep show name and artwork. About Playing on Plex films lists IMDB
  and TMDB ids.
- Playlist videos use the ▶ glyph instead of "[V]" (Classic, Original, Metal).
- YouTube rows mark downloaded forms as ♫ (audio) and/or ▶ (video) instead of ⬇. Sorting, A–Z and
  type-to-find ignore the marks.
- YouTube channel upload lists are cached (memory and disk) and refetched after an hour, on a larger
  **Videos per Channel**, or on **Refresh**.
- Double-clicking a YouTube video plays it when exactly one form is downloaded; otherwise it opens
  the Audio/Video menu.
- Item count moved into the source bar label ("Lib: Music (1110 items)"). Original/Metal browsers
  get an F5 refresh button styled like the view icons.
- Library Browser column headings follow expansion (artist → album → track columns), values align
  under the right headings, and the column menu lists only visible columns. Emby/Jellyfin artists
  show real album counts and genres; Emby/Jellyfin albums show genres.
- Plex smart playlists over a deleted library report that the library is gone instead of
  *Server error: 404*.

### Fixes

**Video playback**
- Videos on Retina screens could render in the bottom-left quarter or show only a cropped corner.
- With Sweet Fades or Gapless on, a video following a song played audio-only.
- The playlist stalled after a video ended (except in WMP skins). It now advances, and stops at the
  end with Repeat off.
- Double-clicking a song while a video played closed the video and played nothing.
- Playlist videos opened twice, sending Plex a spurious stop at 0:00.
- Unopenable films left a black window at 0:00. They are now skipped with a marquee message; a
  missing folder stops playback.
- A film after a song or station inherited that track's elapsed time.
- Pausing a film and pressing ←/→ twice moved only 10 s instead of 20 s.
- Video keys (Space, ←/→, F, Esc) didn't reach the video window in Classic, Original and Metal,
  or films embedded in WMP and Winamp Modern skins. Esc no longer stops a film in WMP skins.
- WMP skins: Return replayed a film from the start because focus stayed on the Library Browser.
- WMP and Winamp Modern skins lost keyboard focus after leaving film fullscreen.
- Winamp Modern **Add Files** / **Add Directory** / **Load Playlist** rejected video files.

**Playback and streaming**
- A server or radio stream started after a Sweet Fades crossfade played over the previous local
  song; Play Now during a stream crossfade was overridden when the fade finished.
- Starting a local file over a stream left the player showing stopped at 0:00.
- Double-clicking a video while music played also started the next song in the background.
- CLI: `--source radio --station … --cast …` played locally instead of casting. Quitting a CLI cast
  (`q`, Ctrl-C, kill) now stops the device.

**Media servers**
- Emby rejected all now-playing and progress reports.
- Emby/Jellyfin films opened a second, audio now-playing session.
- Plex stop reports carried the wrong (or no) duration when switching films or tracks.
- Plex songs cast to TV/DLNA now send artwork.
- Queued episodes repeated the show name, and queued Plex movies were prefixed with the studio.

**Library Browser**
- The last row was hidden below the list when a column header was shown (and behind the offline
  banner in Original skins). Clicking that banner no longer selects the row under it.
- Return/Esc on the album screen needed an extra click before keys worked.
- Local search titles for YouTube videos varied when audio and video were saved under different
  titles.
- In the classic browser, **Play Movie** / **Play Episode** on local videos did nothing.
- Library Browser F5 sat 50pt in from the edge in Audion, WMP and Winamp Modern frames.

**Skins**
- Art window ratings were lost on Esc, close, or a track change within 0.5 s, and offered stars
  for files outside the library. With **Hide Title Bars** or in WMP skins it opened with a black
  band.
- Selected playlist row drew white-on-white in light Winamp Modern and WMP skins.

### Build and internals

- Build scripts support Swift 6.4: they use SwiftPM's native build system when available and query
  SwiftPM for the product path instead of assuming it.
- Shader lookup is unified, fixing the missing Original skin glow under Swift 6.4's default build
  system (release builds were unaffected).
- All Library Browsers read per-tab sort from one shared, persisted store.
- Plex artists (browser) and movies/TV (CLI) use the same pager as albums.

**Media servers**
- Emby and Jellyfin songs showed no cover art when the art was on the album rather than the track,
  including after a restored session. They now show the album's cover in Control Center, skins,
  playlists, casts and the CLI.
- An Emby album with no cover of its own showed none in the Library Browser. It now shows the
  track picture Emby uses for it, and both Library Browsers resolve every server thumbnail the same
  way as the rest of the app.

**Skins**
- Beside an Audion face or a WMP skin, the playlist could not be resized to the player's width: it
  stepped in 25-pixel increments and stopped at the Classic minimum. It now resizes freely.

## 0.31.4

- **Each library tab keeps its own sort** — choosing a sort in the Library Browser, from the Sort
  menu or by clicking a column header, used to re-sort every tab: "Recently Added" on Albums also
  re-ordered Artists and Playlists. Each tab now remembers its own sort, across launches too, in
  every skin family. Tabs start from the sort you had before.
- **Plex Albums tab sorts the whole library** — opening the Library Browser straight onto Albums
  loaded only the first 500 Plex albums, so "Recently Added" showed the newest of an alphabetical
  slice until you visited Artists and came back. Albums, Movies and TV now load every item, however
  large the library.
- **Search lists every album by the artist you searched for** — searching a Plex, Subsonic,
  Jellyfin or Emby library for an artist showed only some of their albums: 34 of 53 on Plex, 19 of
  74 on Subsonic, 5 of 54 on Emby. Search now lists the same albums as the artist's own row for
  the first ten artists it matches. On Plex, music results stay in the library you are browsing
  instead of filling up with copies from your other libraries, and separate releases that share a
  title are no longer merged. Local search also finds albums whose tracks have no album-artist tag.
- **Jellyfin connects again on newer servers** — the Jellyfin source showed a connection error even
  though **Test** in the server manager succeeded, because newer Jellyfin servers reject the older
  way NullPlayer sent its sign-in token. The token now goes the way Jellyfin expects, so libraries
  load and play again.

## 0.31.3

- **Classic main window no longer smears when resized** — dragging the Classic main window by its
  edge left the old picture in place: the time, visualizer and position bar repainted at the new
  size over it, so the window trailed copies of itself and the position bar stretched across them.
  It now redraws in full at every size.

## 0.31.2

- **Drop shadows for Windows Media Player and Modern skins** — `.wmz` and `.wal` skin windows had no
  shadow at all, so they looked cut out and flat next to the rest of the app. Every skin window now
  casts a soft macOS-style shadow that follows the skin's own shape, including drawers, panes and
  layout switches, and stays put while you drag. Animated parts such as Anaheim's flapping ears do
  not leave a ghost behind. **Windows > Window Shadows** turns it off. Classic and Original windows
  are unchanged.
- **Picking a skin always switches to its family** — choosing a skin from any family's list in the
  Skins menu, or loading one with that family's **Load Skin...**, now switches to that family
  straight away, whatever is on screen. Before, a Classic skin picked while a Media Player or
  Modern skin was showing, or any Modern skin picked from another family, was only remembered
  until **Switch to …** was used. **Switch to …** stays as the one-click way back to a family's
  last skin.
- **Smoother edges on shaped Windows Media Player skins** — a skin cut out by a colour key no
  longer has a stair-stepped outline. Its edge is now traced and smoothed along its length, so
  curves and slopes are antialiased on Retina and non-Retina screens alike. Thin lines, small gaps
  and square corners keep their shape exactly, and the skin's own artwork is left as drawn.
- **The library no longer opens in a tiny window on some Modern skins** — skins such as Anaheim
  Player 01 and Itemskin opened the Library Browser 260–330 wide, too narrow for its tabs and
  columns. A Modern skin's library window now has a minimum width that fits the browser, whether
  the skin declares a smaller size or its own script shrinks the window. Other windows, and
  Classic and Original skins, are unchanged.
- **Docked windows drag smoothly** — in every skin family, a quick drag of the player with a
  window docked to it moved in jerky 16 pt jumps, because the player kept snapping to the docked
  window riding along with it. It now follows the pointer. On Modern skins that draw a window's
  border as a separate window, such as Pure Inspired and Itemskin, the border no longer pulls away
  from the window's contents while you drag, and dragging such a window on its own is smooth too.
  Skin window shadows also cost less on every drag step.
- **Switching Modern skins no longer shows the spinning cursor** — changing from one `.wal` skin to
  another froze the app for two to three seconds, long enough for macOS to show the beachball
  under the loading animation. The switch now takes about half the time or less: switching to
  cPro Bento went from 2 seconds to half a second, and to Big Bento Modern from 3 seconds to
  1.5. Classic, Original and Media Player skins are unchanged.

## 0.31.1

- **Sonos group volume keeps each room's level** — after changing one room's volume in a multi-room
  cast, the main window's volume control put the rooms back to their old balance. It now keeps the
  new balance and moves every room from there.
- **Classic windows close again on macOS 27** — the close button in the top-right corner of a
  Classic window (and of the Classic-style windows a `.wal` or `.wmz` skin opens beside it) showed
  a resize cursor and ignored the click, because macOS 27 took the press for its own window resize.
  These windows now do all edge resizing themselves, on the same edges and margins as before, and
  library-browser fullscreen still fills the screen.

## 0.31.0

- **Windows Media Player `.wmz` skins** — a new Windows Media Player mode that runs real WMP 9-12 era
  skins natively on macOS. Skins look and behave like themselves: their own artwork, shaped windows,
  animations, hover and pressed states, tooltips, fonts, drawers and multiple views, with the skin's
  own JScript running in a sandboxed session so its buttons, sliders, timers, keyboard shortcuts and
  readouts work the way they do in Windows.
- **SRS audio enhancements for every skin** — the WOW Effect, TruBass and Headphones settings that
  came with Windows Media Player skins are now global playback options under **Playback Options ▸
  SRS**, work in every skin, and are remembered across launches. A `.wmz` skin's own SRS controls
  drive the same settings.
  - **WOW Effect** widens the stereo image, pushing sound out beyond the speakers while leaving
    centred vocals and deep bass where they are.
  - **TruBass** adds a fuller, deeper low end by enhancing the bass already in the music, without
    simply turning up the lowest frequencies.
  - **Headphones** tunes TruBass for headphones instead of speakers.
- **Sonos Rooms window with per-room volume** — a new dockable **Sonos Rooms** window lists every
  Sonos room NullPlayer has discovered, with a checkbox to include it in the cast and its own volume
  slider, so each room can be set independently instead of only through the group volume. The list
  scrolls for any number of rooms, with **Refresh** and **Start/Stop Casting** always visible at the
  bottom. Open it from **Windows → Sonos Rooms** or **Output → Sonos → Sonos Rooms…**; the existing
  Sonos submenu still works as before and shares the same room selection. The window docks, resizes
  and restores like the other windows, follows Compact Mode, and is skinned in Classic, Original,
  Original-Metal and Winamp Modern (`.wal`) skins. The player's main volume slider still controls
  the whole group.
- **Server credentials no longer appear in logs** — playback, artwork, radio and casting diagnostics
  could record access tokens in full URLs and error messages (for example a Plex `X-Plex-Token`, or
  a Jellyfin or Emby `api_key` when playing video). Credentials are now redacted from logs across
  Plex, Subsonic/Navidrome, Jellyfin, Emby, radio and casting, and casting failure alerts no longer
  show raw error details.
- **Local playback recovers after a long idle** — after the Mac sat idle for a long time, local
  playback could get stuck, silently retrying a broken audio engine every quarter-second. NullPlayer
  now rebuilds the audio engine instead, restoring your output device (falling back to the system
  default if it is gone), EQ and pitch settings, and resuming the loaded track where it was. Retries
  back off and stop after six attempts; pressing Play or changing the output device tries again.
  Pausing or stopping during recovery is respected, and streaming playback is unaffected.
- **One unreadable file no longer stops the playlist** — playback skips past it to the next track,
  and the error now appears in the Modern and Winamp Modern main windows, not only Classic. A track
  on a disconnected NAS still stops playback, as before, instead of starting some other track.
- **Sonos no longer receives audio above its 48 kHz limit** — the compatibility gate now rejects
  any track with a known or resolved sample rate above 48 kHz, even when its URL extension or MIME
  type is unrecognized. Local files with unusual extensions are probed before casting, and Plex
  tracks with missing rate metadata are resolved from the server (GH #422).
- **Local library copes with moved folders and missing files** — **Library → Find Missing Files…**
  finds a watch folder that has moved (for example when iCloud Drive is turned off and its files
  land in `~/iCloud Drive (Archive)`), shows where it went, and re-points it on your say-so, keeping
  play counts and ratings. It then offers to forget tracks whose files are genuinely deleted;
  anything on a disconnected drive or unmounted share is always left alone.
- **Playlists with relative paths play again** — `.m3u` and `.pls` entries written as bare file
  names or paths next to the playlist were being read as web addresses and could not play.
- **Waveforms appear much sooner** — the waveform window builds a track's waveform about 20 times
  faster the first time it is opened, so a long local track or a Plex track that used to take up to
  half a minute now shows almost at once (a server track still has to download first). Switching
  skins or reopening the window while a waveform is still being built no longer starts it again.
- **Download your complete Play History as a CSV** — the Library Data and Play History views now
  include a download button that exports every recorded event, including older and skipped plays,
  rather than only the 200 recent entries visible in the table. Available in every UI mode.
- **Minimize All minimizes every window** — **Windows → Minimize All Windows** and Classic's
  minimize button left any window not docked to the player on screen, and Sonos Rooms (and every
  Original-skin side window) never minimized even when docked. Every open window now goes to the
  Dock, in every skin mode, and restoring the player brings them all back.
- **Windows reopen where you left them** — the library browser and the visualizer window once again
  come back where you moved them when closed and reopened, instead of snapping back beside the player.
  In Windows Media Player and Winamp Modern skins, the spectrum and audio analyzers, PeppyMeter, Flow,
  Cava, waveform, Sonos Rooms and the fallback playlist and equalizer do the same, and closing one no
  longer moves the others. Classic and Original keep their stacked layout.
- **Visualizations take their colours from Winamp Modern and Windows Media Player skins** — with a
  `.wal` or `.wmz` skin, the Cava, Spectrum Analyzer and Waveform windows now take their default
  colours from the skin, as they already do in Classic and Original. So does Cava in a Windows Media
  Player skin's visualization area. A colour preset you pick still wins, and **Match Skin** goes back
  to the skin's colours. In the Waveform window the playhead now always stands out from the played
  part.
- **vis_classic profiles show their real colours** — every bundled vis_classic profile was being
  drawn with red and blue swapped, so "Flames" came out blue and "Default Red & Yellow" blue and
  cyan. They now look as their authors intended, in every skin; the Metal profiles look the same as
  before. This changes the look of Classic's default, "Purple Neon".
- **vis_classic picks a profile to suit the skin** — in Winamp Modern and Windows Media Player skins,
  vis_classic in the Spectrum Analyzer, in a `.wal` skin's own visualizer and in a `.wmz` skin's
  visualization area now starts on the bundled profile whose colours are closest to the skin's,
  instead of Classic's "Purple Neon". A profile you choose yourself is kept until you switch skins,
  and resetting visualizations goes back to the skin's match. The first launch after updating
  replaces your current vis_classic profile in these skins once.
- **The listening heatmap matches your skin** — the heatmap in the library's Data tab now takes its
  colours from the current skin in every skin mode instead of always using GitHub green, and follows
  a Winamp Modern or Windows Media Player skin's colour theme when you switch it. Switching colour
  theme now recolours the rest of the Data tab too.
- **One layout for every skin menu** — every skin family's menu now puts its options first and its
  skins after a single divider. The options open with **Load Skin...**, **Get More Skins...** and
  **Open Skins Folder...** in the same wording everywhere, followed by **Remove “name”...**, which
  every family now has: it moves the current skin to the Trash (Windows Media Player deletes its
  installed copy, never your download) and falls back to the built-in skin. Windows Media Player
  gains a **Get More Skins...** link to the Internet Archive's WMP skins collection, and Classic gains
  **Open Skins Folder...**. The separate **Default Skin** entries and Windows Media Player's **Save
  Compatibility Report...** are gone.
- **Winamp Modern skins with hidden windows use far less CPU** — a skin's closed windows no longer redraw in the background. The WMP11-BlueVU skin's VU meters had been animating unseen, costing about a third of the app's main thread while music played.
- **Winamp Modern VU needles use less CPU and look sharper** — skins that rotate artwork, such as the swinging needles in WMP11-BlueVU's VU Meters, now draw it in a single step instead of recalculating every pixel, which roughly halves the app's main-thread load while the meters are open.
- **Winamp Modern skins with an animated level meter use less CPU** — a skin that steps an animated meter many times a second (WMP11-BlueVU's beat display) now redraws just that meter instead of the whole player window.
- **Glossy frames for Winamp Modern fallback windows** — when a Winamp Modern (`.wal`) skin has no
  window frame of its own for NullPlayer's windows (the analyzers, Cava, Flow, PeppyMeter, waveform,
  library, playlist, equalizer and Sonos Rooms), they now wear the same glossy, title-bar-free frame
  in the skin's colours that Windows Media Player skins use, with the close button in the top-right
  corner. Skins that supply their own frames are unchanged. ClassicPro skins whose frame is only
  borrowed tooltip artwork (the cream box with `~` and `x`) now count as having no frame, so their
  windows match the player too.
- **Clicking any Winamp Modern window brings them all forward** — clicking one `.wal` window now
  raises every one of the skin's windows and NullPlayer's own, even when you click in from another
  app, the way Windows Media Player skins already did.
- **Winamp Modern windows no longer pile up when you change UI Size** — changing the UI size with a `.wal` skin left its windows on top of each other: the equalizer slid up into the player, and the playlist sat over the equalizer. The windows are now laid out again around the player after every UI Size change, the same way Snap To Default arranges them.
- **Winamp Modern windows no longer reopen on top of each other** — in a `.wal` skin, closing a window such as the equalizer and then opening another could put the new one in the closed window's place. Reopening the first window then covered it completely. A reopened window now keeps its old position only if nothing has been put there since, and otherwise finds a free spot. A window you moved yourself still reopens where you left it.
- **Winamp Modern windows no longer open on top of the player when the screen runs out** — with a large UI Size and the player in the middle of the screen, a wide window such as the library had no room on the player's right, so it was pulled back over the player. It now goes into the empty space to the player's left. If it fits on neither side, it is placed where it covers the least.
- **Closing a Winamp Modern window no longer moves the one below it** — in a `.wal` skin, closing a window such as the Spectrum Analyzer from the Windows menu slid the window under it up into its place. Reopening the first window then put it right on top. The other windows now stay where they are.
- **Winamp Modern windows open right under the one above** — in a `.wal` skin, opening a window from the Windows menu while another was open under the player could leave a large empty gap between them. On Sony_Walkman, the playlist opened well below the equalizer. It now opens directly beneath it. Windows Media Player skins get the same fix.
- **The library stays docked to a Winamp Modern player** — in the `.wal` skins that use NullPlayer's own library window, such as Sony_Walkman and Winamp 3.0 Default, opening a window such as Cava could push the library a few pixels away from the player, leaving a gap. The library now stays where it is. Classic and Original skins are unchanged: there, the library still grows and shrinks with the windows stacked under the player.
- **No more unreadable library text in Winamp Modern skins** — NullPlayer's own library and windows
  inside a Winamp Modern skin now always draw their text in a colour that can be read on the
  background. cPro-Bento's Bafana theme drew the source name, item count and selected tab black on
  black; 19 skins in all get more readable text, using the skin's own colours wherever one works.
  Colours you set yourself in Skin Colors are still drawn as chosen.
- **Winamp Modern skins without a transparency setting now draw as Winamp does** — a skin window that doesn't ask for see-through edges now gets a solid shape: its outline is cut from the artwork and the translucent parts inside are drawn over black. Before, those parts let the desktop show through. You'll see this mostly in notification pop-ups and a few shaped players such as Wiimote and PokemonDS. Skins that ask for soft edges, including every one with a drop shadow, look the same as before.
- **No more hairline seams in Winamp Modern skins at in-between UI sizes** — at UI sizes such as 105% or 125% on a Retina display, thin light lines could show where the pieces of a skin's frame and panels meet. The pieces now meet exactly, so the lines are gone. Sliders, knobs and progress bars placed between whole pixels now also sit on a whole pixel.
- **No more see-through gaps inside Winamp Modern skin windows** — in the WMP11-BlueVU skin, a thin band of desktop showed between the VU Meters' artwork and the window frame. The About and library windows had the same problem across larger areas. Empty space inside a skin's standard window frame is now filled black, as it is in Winamp.
- **Drag a Winamp Modern player by its library or video** — in skins that show the media library or
  a video inside the player, dragging the empty space below the library's list, or the video
  picture itself, now moves the window.
- **Cover Flow stays inside the library window** — the stacked covers at either side of the
  carousel no longer spill over the library browser's border, in every skin mode.
- **New "Red" vis_classic profile** — a single-colour red to go with "Green".
- **Big Bento Modern's small visualizer plays** — with the Multi Content View's mini visualization
  pane turned on, the pane now shows the visualization as soon as the player opens, instead of
  staying black.
- **Song titles show in more Winamp Modern skins** — Shield Amp and Ebonite now show the playing
  track's title in their song display, which was blank. A skin script that divides by zero now
  carries on instead of stopping, as it would in Winamp.
- **Song tickers scroll in Shield Amp and Ebonite** — a long title now scrolls across the song
  display at Winamp's speed instead of standing still, and stays inside the display instead of
  running over the rest of the player.
- **ClassicPro track info shows up** — in ClassicPro-based Winamp Modern skins such as cPro2 Dark
  Aluminum, the track-info panel under the library now lists the playing track's title, artist,
  rating, decoder, file size, filename and format instead of staying empty.
- **ClassicPro's Now Playing widget shows the song straight away** — opening the Now Playing
  widget while a track plays now shows its title, artist and album at once, instead of staying
  blank until the next track.
- **Itemskin's volume control works** — in the Itemskin Winamp Modern skin, clicking or dragging the volume bar did nothing, so a volume stuck at zero could not be raised and the skin played silently. The bar now responds anywhere along its length, and the seek bar shows the song's progress instead of the volume. BLAKK's seek bars and Bio-Nid's volume knob also respond to clicks now.
- **Itemskin's windows stay where they are placed** — in the Itemskin Winamp Modern skin, opening the Spectrum Analyzer or Waveform put it mostly below the bottom of the screen, and changing the UI Size could pull the playlist, library or a visualizer window back to where it had been, on top of its neighbours. Each window now opens in its own free spot and keeps it, with the skin's frame drawn around it.
- **No black bar on Itemskin's NullPlayer windows** — in the Itemskin Winamp Modern skin, windows such as the Spectrum Analyzer and Waveform had an empty black bar across the top of the frame, left where the skin's own visualizer buttons go. The bar is gone and the windows are that much shorter.
- **Defix's detached visualizer can be reattached** — in the Defix Hi-END 200 Winamp Modern skin,
  the detached visualizer window's **Reattach Visualizer** and **Random** buttons now work. The
  window's button bar shows while the window is focused and hides otherwise, as the skin intends.
  The same fix stops S7Reflex drawing its stereo and mono indicators on top of each other, and
  lines up the titlebar streaks in winampmodern566.
- **Winamp Modern 5.66's menu bar works** — File, Play, Options, View and Help in the
  winampmodern566 skin now open their menus when clicked; before, clicking them did nothing.
- **winampmodern566's menu bar lights up** — in the winampmodern566 Winamp Modern skin, pointing at
  File, Play, Options, View or Help now highlights the entry, and it shows as pressed while its menu
  is open.
- **winampmodern566's Album Art window can be reopened** — the skin's album art window is now
  listed in the **Windows** menu. Once it was closed, the skin's own Alt+A shortcut was the only
  way to bring it back.
- **Developer tooling: window census** — a new script,
  `skills/app-control/scripts/window-census.sh`, measures where each of NullPlayer's windows opens
  and how big it is for every installed skin (Classic, Original, Metal, Winamp Modern and Windows
  Media Player), and writes the results to spreadsheet-ready tables. Each skin is measured from the
  same saved settings, so one skin's window sizes do not carry over to the next. The app itself is
  unchanged.
- **Windows Media Player skins: no more gaps in window borders** — NullPlayer's own windows (the
  library, PeppyMeter, the analyzers and the rest) could show see-through seams in the border they
  borrow from a `.wmz` skin: a widening column in Crimson Skies' and T3 Skynet's top and bottom bars,
  a broken top edge and missing right side in WALL-E's white theme, and a strip under the bottom
  edge in Kids. Those borders now close. A one-pixel seam down both bars of Crimson Skies' own
  playlist on Retina displays is gone too.
- **Library tracks play on double-click, once** — in the Classic and Windows Media Player library,
  a single click played a track and a double-click played it three times, leaving three copies in
  the playlist. A single click now selects and a double-click plays, as in the Original library.
- **A track that can't be played now says so** — double-clicking a track whose file has been moved
  or deleted, or whose drive is disconnected, looked like nothing happened. It now shows an alert
  naming the file, in every skin mode, and no longer leaves a dead copy in the playlist on every
  try. Windows Media Player skins also show the failure in their status line and title, as the
  other modes already did in their marquee.
- **Playing locally after a cast** — after Stop Casting, pressing Play on a local file ran the
  clock with no sound; it now plays from the start, as after Stop, and a track picked during the
  cast is the one that plays. If the Mac's audio output changed during the cast, a Play Now right
  after it ended could leave nothing playing or resume the track from before the cast; it now plays
  the track you picked, and if that file can't be opened it is reported and taken back out of the
  playlist instead of the next queued track starting.
- **Cue tracks keep their place** — connecting headphones or switching the output device while a
  cue-sheet track played jumped into the album's first track at the same time, and Stop sent a cue
  track back to the start of the whole file; both now stay within the track.
- **Quieter logs** — the cast-device discovery refresh no longer writes to the log every few
  seconds; set `NULLPLAYER_CAST_DISCOVERY_LOG` to bring it back.
- **Developer tooling: playback snapshot** — `skills/app-control/scripts/playback-snapshot.sh`
  prints what a running debug build's player, audio output and cast session are doing, including
  a measured output level, so a silent-playback report can be diagnosed without a rebuild. Debug
  builds only; the app itself is unchanged.
- **Winamp Modern: framed windows resize by their frame** — on skins that draw a window's frame
  separately from its contents (Itemskin, MoonLight, K-jr, Pure Inspired, Ebonite), dragging the
  frame's edge or corner either snapped straight back or stretched the frame and left the contents
  behind, and on Itemskin worked only while a second window such as PeppyMeter was open. The frame
  and its contents now resize together, and dragging a top edge moves the top edge. A window
  resized while nothing is playing also re-lays out at once (ClassicPro's logo, tabs and equalizer
  stayed where they were).
- **Winamp Modern: resizing a window no longer resizes its text** — with Text Size on Auto, the
  embedded playlist and library text grew and shrank with the window. Auto now picks the size
  from the size the skin designed the window at and keeps it; use Text Size to change it.
- **Winamp Modern: framed windows keep their size at every UI Size** — at a UI Size such as 105%,
  115% or 125%, a window whose frame is drawn separately (Ebonite, Itemskin, K-jr, Pure Inspired)
  settled a point wider or taller than its own frame, shrank by itself after being dragged, and
  came back smaller after a trip through the UI Size menu. Frame and contents now stay the same
  size, and a window returns to the size it left at.

## 0.30.0

### New Features

- **Winamp 5.x "Modern" skins now run in NullPlayer** — a fourth skin family, alongside Classic,
  Original and Original-Metal. NullPlayer now loads and runs real Winamp 5.x modern skins — the
  `.wal` files people have been making since the mid-2000s — natively on macOS, with no Winamp
  install, plugin, or original application asset involved. Choose one from **Skins → Modern**, or
  add your own with **Skins → Modern → Import .wal Skin…**.

  A `.wal` skin is much more than artwork: it ships its own window layouts, its own scripted
  behaviour, and its own idea of where everything belongs. NullPlayer runs that, rather than an
  approximation of it. You get the skin's own frames, buttons, sliders, animations and colour
  themes; its playlist, equalizer, library and video surfaces drawn where the skin puts them,
  embedded in the player instead of in separate NullPlayer windows; its tabs, drawers, config
  screens and right-click menus, driven by the skin's own scripts; its About page; and its
  visualization box, which can show an oscilloscope, the spectrum analyzer, Cava or vis_classic.
  Skins resize and dock like any other NullPlayer window, and per-skin settings — text size, colour
  theme, waveform seeker — are remembered separately for each skin.

  Skins built on the **ClassicPro** engine work too: point NullPlayer at the ClassicPro plugin
  installer once, with **Skins → Modern → Import ClassicPro Engine…**, and it unpacks what it needs
  internally.

  Some skins reach for features that do not exist on macOS, or that NullPlayer does not implement
  yet. A skin that does degrades to a sensible fallback rather than refusing to load.

- **Cover Flow in the Library browser** — a new **FLOW** toggle in the source bar turns the current library list into a 3D, horizontally-scrolling wall of artwork, available in all three skin families (Original, Original-Metal, Classic) and across music, Movies, and TV Shows. It's a visual lens over whatever you're browsing: scroll or use the arrow keys to flip through covers, the centered item's name stays directly beneath the carousel, and a wider window fans out more covers. Clicking a **container** enters it and shows its contents, with a **‹ Back** cover to step out — folder/subfolder, artist→album, and show→season→episode navigation all work to any depth. Clicking an **album** plays the whole album; clicking a **track**, **movie**, or **episode** plays it. In Original/Original-Metal the covers float above the Library window's Cava/art backdrop, honoring whatever backdrop mode you've set.
- **Compact window can now show the playlist** — a Library | Playlist toggle at the bottom of the Compact window switches its content between the library browser and the current playlist, so you can view and edit what's playing without opening the full Playlist window. Double-click a track to play it; selection, scrolling, and live now-playing highlight all work in place. The choice is remembered across launches and is available in all three skin families (Original, Original-Metal, Classic). In Original/Original-Metal the playlist is translucent so the Cava/art backdrop shows through it just like the library list.

### Bug Fixes

- **A film watched to the end is now marked watched on Plex, Jellyfin and Emby** — and a queued
  video playlist moves on to the next film by itself. The video engine reports a film running out as
  a pause rather than as an ending, and NullPlayer was taking it at its word: the server was told the
  film had been *paused* at 100% and never that it had been finished, so it stayed unwatched, nothing
  was recorded, and a queued film simply sat there instead of starting the next one. This affected
  every video, local or streamed.

- **The transport resets when a film finishes** — in every skin mode. A film that had played to its
  end went on counting as the thing the player was playing: the readout kept its title, the position
  bar stayed parked at the end, and the play, stop and seek controls went on driving a film that was
  over, so the player could not be handed back to your music without closing the video window. The
  picture stays where it is, on its last frame, and can be played again from the start.

- **Switching skin family no longer leaves the player at the old skin's size** — going from a Winamp
  5.x modern skin to a Classic one left the classic player squeezed into the outgoing skin's window,
  drawing its artwork shrunk inside a box the wrong shape ("the main window is tiny in classic mode").
  Every skin family sizes the player from its own layout, so the rebuilt window now takes the incoming
  skin's own size instead of inheriting the outgoing one's, in every direction between every pair of
  modes. The window stays where you left it — its top-left corner does not move.

- **Compact Mode no longer leaves the Library Cava backdrop running against a hidden window** — entering Compact Mode orders the Library browser window out, but that doesn't reliably post an occlusion change, so the Library backdrop's 60 Hz Cava analyzer kept running as a second, wasted DSP queue alongside the visible Compact backdrop. The presenter is now reconciled to the window's hidden state on entry and restarted on exit.

- **Fixed a large memory leak while casting audio (grew unbounded over a long session)** — the cast status poll calls `AudioEngine.updateCastPosition` roughly once per second and reassigned the playback `state` every time, even when it hadn't changed. Because `state`'s observer posts a change notification on every assignment, this fired a Now Playing update storm — the system Now Playing info was re-pushed tens of thousands of times, and remote (Plex) artwork was re-fetched over a fresh network connection on each update, piling up network/dispatch objects into the gigabytes and never reclaiming them after the cast ended. `updateCastPosition` now only reassigns `state` on a real transition, and `NowPlayingManager` no longer re-fetches artwork that already failed for the current track.

- **Fixed a large memory leak that grew unbounded while a visualization window stayed open** — the Spectrum Analyzer (Metal) and OpenGL visualization views render from a `CVDisplayLink` callback, which runs on a dedicated thread with no run loop and therefore no autorelease pool draining between frames. Every frame's autoreleased objects — the Metal `nextDrawable()`, command buffers, and encoders, along with their backing textures — accumulated forever, so a window left open would climb into multiple gigabytes over hours/days of use. Each display-link frame now runs inside its own `autoreleasepool`, so per-frame objects are freed immediately.

- **Sonos volume no longer jumps around during a fast slider drag** — each volume change fired its own SOAP command, and on a rapid drag those requests could reach the speaker out of order, leaving it stuck on a stale value. Volume commands are now coalesced into a single in-flight request with latest-value-wins, so the speaker tracks the slider monotonically and settles exactly where you release it (GH #414).

- **Sonos playlists now advance to the next track** — when a track finished on Sonos the app saw the speaker report STOPPED and paused, halting the playlist after one song. A track that stops at or near its end is now recognized as a natural finish and auto-advances, while an external pause from the Sonos app, an explicit Stop near the end of a track, and genuinely short tracks all still behave correctly (GH #415).

- **Added diagnostics for a Sonos cast clock that occasionally starts stuck at zero** — when a Sonos position poll fails (often from SOAP contention while the volume slider is moving at cast start), the app previously applied a position of 0 and re-anchored the clock silently, freezing the elapsed time. It now logs the failed `GetPositionInfo`, the resulting clock reset, and the surrounding volume-command timeline so the intermittent case can be captured. No behavior change yet — instrumentation only.

- **Restored local videos play again instead of erroring** — a video file left in the playlist from a previous session was rebuilt on launch as an audio track (the saved state doesn't record media type), so playing it routed to the audio engine and failed to decode the video container. Restored local files now re-derive their media type from the file extension, so videos correctly open in the video player.

- **Exiting Compact Mode restores the menu bar** — leaving Compact Mode (including when the app launches straight into it and you exit for the first time) could leave the system menu bar owned by whatever app was frontmost before, with none of NullPlayer's menus. Because NullPlayer stays the active app across the whole transition, macOS never rebuilt the menu bar for it. NullPlayer now forces that rebuild on exit, so the full menu bar (and the correct Dock icon) return every time.

- **Quitting from Compact Mode no longer loses your settings** — Compact Mode has no menu bar or Dock icon, and the status-item menu had no Quit, so the only way to quit was force-quitting from Activity Monitor — which skipped the normal save-on-quit and discarded that session's changes (for example, the skin reverted on the next launch). The compact status-item menu now has a **Quit nullPlayer** item that quits cleanly and saves state.

### Changes

- **Modern and Metal skins are now named Original and Original-Metal** — the new names appear throughout the skin menus and documentation, while existing preferences, skin folders, and custom `.nsz` bundles remain compatible. The **Modern** name now belongs to the new Winamp 5.x `.wal` skin family.
- **Removed the Met Museum Art visualization** — the rotating public-domain artwork engine has been retired and no longer appears in the visualization engine picker. Any saved preference for it falls back to the default engine.

## 0.29.8

### Bug Fixes

- **Video playback no longer freezes on startup, and starts at the right volume** — writing the audio volume after the media was assigned but before the player started could enter libVLC's configuration lock while its event thread held the opposing lock, permanently hanging the main thread. The volume is now applied once the audio pipeline exists (as soon as the player begins buffering, before the first sample renders), so playback starts reliably and at the user's volume instead of briefly blasting at full volume. Dragging the volume slider during playback now writes only the volume, without re-running audio-track selection or unmuting on every tick.

## 0.29.7

### Bug Fixes

- **Adding and dragging local video files now works everywhere** — Dropping a video onto the main player window (Modern or Classic skin) now starts it in the video player; dropping a video onto the Library window adds it to Movies and switches to that tab; and **Add Video Files…** jumps to the Movies tab so the import is actually visible, with a file picker that no longer greys out `.mkv`/`.avi`/`.webm`/`.ts`. Local video is now recognized by file extension as well as by probing the container, so formats AVFoundation cannot parse (`.mkv`, `.avi`, `.webm`) are no longer misrouted to the audio engine and silently dropped.
- **Casting large local media no longer crashes the app** — the built-in media server served files by reading the entire file into memory, so casting a multi-gigabyte movie (a Chromecast requests the whole file up front) exhausted memory and the process was killed the instant playback started. Local files are now streamed to cast devices in bounded 256 KB chunks for both full and range (seek) requests, so memory stays flat regardless of file size.

## 0.29.6

### New Features

- **Library and Compact windows add visual backdrops (#410)** — Modern and Metal users can independently choose **Off**, **Cava**, **Art**, or **Cava + Art** for each browser surface from the Visuals menu or its context menu. Cava renders beneath the translucent browser with separate Library and Compact settings and lifecycle; artwork keeps its established list-area layout. Both surfaces default to Cava + Art with 64 bars, using Mono in Library and Stereo with Smooth tuning in Compact, while saved choices remain authoritative.

### Bug Fixes

- **Waveform generation no longer crashes on malformed or unsupported audio (#409)** — AVFoundation waveform decoding now catches Objective-C exceptions and reports a recoverable failure, while interrupted waveform prerenders, skin extractions, and rips are reclaimed safely on launch without deleting active work.
- **Video playback no longer silently starts on a remembered Chromecast** — a saved video-cast device is now used only as the default for an explicit cast action. Local files, streaming URLs, and server-backed video open in the local player unless a video cast session is already active, restoring the player window, video metadata, and local stop/playback controls.
- **Interrupted rips no longer leave multi-gigabyte temp folders behind** — a rip (YouTube/URL download or radio stream capture) stages into a temporary folder and only cleans it up when the rip finishes. Quitting, crashing, or sleeping mid-rip orphaned that folder in the system temp directory, where macOS rarely purges it, so failed rips could silently pile up gigabytes of hidden files. NullPlayer now sweeps orphaned rip staging folders on launch, deleting only those no active rip has touched in the last several minutes so a rip running in another instance is never disturbed.
- **Changing skin families preserves detached auxiliary-window positions** — switching between Classic, Modern, and Metal no longer moves floating windows into a stack. With the regular main window open, only windows docked to its connected layout are repositioned for the incoming skin; with Compact Window active, every visible auxiliary stays at its exact screen position.

## 0.29.5

### New Features

- **GitHub-style listening activity heatmap in the Library Data tab** — the **Data > Overview** tab now opens with a contribution-graph–style grid of the trailing year: one cell per day, shaded by minutes listened (relative to your busiest day), with month labels across the top, Mon/Wed/Fri row labels, a total-hours heading, and a Less→More legend. Hovering a cell shows the exact minutes and date. It always covers the last ~year regardless of the Overview time-range filter and appears in both the Library Data tab and the standalone Stats window.

### Improvements

- **Downstream editions can isolate UI state without changing shared preferences (#404, #405)** — forced-mode builds can now declare their required UI and a preference namespace through one edition policy seam. They ignore conflicting saved or command-line UI modes, initialize the correct EQ layout without consulting the shared legacy mode mirror, cannot switch into an unsupported controller family, and keep Remember State and legacy window geometry separate while still sharing accounts, servers, and media data intentionally.

### Bug Fixes

- **Remember State no longer distorts windows across UI modes (#403)** — UI Size and window frames now restore only when the saved and running modes match exactly, including treating Modern and Metal as distinct. A mismatched launch stays at 100% with valid default main and Library dimensions while audio, EQ, and playlist state continue to restore.
- **Fixed a crash when the audio graph rebuilt after casting ended during an output-device change** — when a Sonos/AirPlay/Chromecast route was torn down and the system output device changed at the same time, rebuilding the local audio graph could raise an Objective-C `NSException` from `AVAudioEngine.disconnectNodeOutput` (route-change reconfig state) that Swift `do/catch` cannot catch, aborting the app. The graph-teardown phase is now guarded exactly like the reconnect phase, so such a route-change exception defers the rebuild and retries instead of crashing.

## 0.29.4

### Bug Fixes

- **Audio Analyzer Spectrogram no longer freezes the app** — scrolling the waterfall now shifts each history row with one bounded memory move instead of triggering a full copy-on-write buffer copy for every pixel. The analyzer stays responsive in debug and release builds, including while streaming audio with the Cava window open.

## 0.29.3

### Improvements

- **Modern and Metal skins now default the main-window visualizer to Cava** — every bundled modern skin and built-in Metal finish starts with its palette-matched Cava analyzer. Classic UI continues to default to `vis_classic`; modern/Metal `vis_classic` profile mappings remain available when selected manually, and the dedicated Spectrum window remains unchanged.

## 0.29.2

### Bug Fixes

- **Switching between classic and modern/metal skins no longer carries the previous skin's analyzer colors or transparency across** — the `vis_classic` analyzer profile is stored per window (main vs Spectrum) and shared across the classic, modern, and metal UIs. Switching UI families used to *preserve* the outgoing skin's profile instead of applying the incoming skin's own default, so classic's "Purple Neon" could bleed into a modern skin, and a modern skin's profile ("Lavender Pink Tips") could persist back into classic — in the main window and the dedicated Spectrum window. Glass/metal transparency and opacity could likewise survive into an opaque skin whose sparse config omitted those fields. A UI switch is now treated as a skin change: each family applies a complete analyzer appearance, and the shared analyzer engines are fully re-synced so no window keeps the previous skin's profile, fit, or renderer transparency (even when a window isn't visible at the moment of the switch).
- **"Reset All Visualization Preferences" now restores the correct default in the classic UI** — while classic was active, the reset resolved defaults from the modern skin engine and applied the modern *default* skin's profile (e.g. NeonWave's "Lavender Pink Tips") instead of classic's "Purple Neon". Reset now resolves defaults from the active UI: classic restores its own analyzer default, while modern and metal restore the active finish's.
- **"Reset All Visualization Preferences" now also resets the standalone Cava window** — the separate Cava spectrum window's color, bar count, smoothing, and bass-tilt settings were left untouched by the global reset. They are now cleared with everything else, and the open Cava window updates immediately, falling back to the active skin's default gradient.
- **The standalone Cava window's custom colors no longer follow you from modern into classic** — picking non-default Cava colors in a modern/metal skin and then switching to a classic skin kept the modern colors instead of reverting to the classic default (Winamp green). Switching UI families now clears the shared "custom colors" flag on entry to classic, matching the existing behavior when entering modern/metal.

## 0.29.1

### Bug Fixes

- **Plex library no longer freezes on first launch** — on a fresh launch, a background content preload could finish midway through the first library load and supersede it, leaving the artist album-count index unbuilt. The browser then re-parsed every album for every artist on the main thread on each click, freezing all windows until relaunch. The index is now always built before artist rows render, and the per-artist rescan fallback was removed, so the library stays responsive.

## 0.29.0

### New Features

- **Cava spectrum analyzer window** — a bar-based spectrum visualizer modeled on [cava](https://github.com/karlstav/cava), opened from the **Windows** menu or main-window right-click menu, in classic, modern, and metal skins. Shows log-spaced frequency bars with gravity/falloff, in **mono** or mirrored **stereo** (double-click to toggle). Right-click to set colors (gradient presets and metallics, following the skin palette by default), bar count, smoothing, bass tilt, and a modern-only transparent background. Docks in the center stack and stays idle when closed.
- **Cava in the main-window visualization display** — the main-window analyzer area can render a mono Cava spectrum following the active skin palette, with its own color, bar count, smoothing, and bass tilt under **Visuals > Main Window** (independent of the standalone window). The **Visuals** menu is now organized into **Main Window**, **Spectrum Window**, and **Visualizations** submenus.

### Improvements

- **ProjectM upgraded to 4.1.7, fixing preset crashes at the source** — the bundled libprojectM was updated from 4.1.6 to 4.1.7, which fixes a null-texture dereference (`Renderer::Texture::Empty()`) that crashed the app when rendering presets containing a commented-out `sampler` declaration in a shader (upstream #958), along with other preset crash and rendering fixes. Presets that previously had to be caught-and-disabled — like the bundled *suksma - dotes hostile undertake - offx - flacc* — now render normally. (The crash-detection safety net above remains for any future bad preset.)

  **If your visualizations have gone missing or thinned out over time, restore them:** open **Visuals > Visualizations > Restore Disabled ProjectM Presets**. The number next to it is how many presets are currently disabled — the earlier blacklisting bug may have quietly turned off many (or all) of your presets, and now that these crashes are fixed it's safe to bring them all back. Choosing it re-enables every disabled preset immediately.
  
- **Video playback now uses the LGPL VLCKit engine** — the video player and cast-source decoding moved from KSPlayer/FFmpegKit (GPL-3.0) to the vendored VLCKit/libVLC (LGPL-2.1+). Play/pause, seek, skip, volume, and audio/subtitle track selection carry over, including a subtitle **Off** and subtitle-delay control.
- **Accurate third-party attribution for the Cava and Flow visualizers** — NullPlayer's Cava spectrum analyzer and Flow network meter are clean-room Swift reimplementations of the [cava](https://github.com/karlstav/cava) (C) and [flow](https://github.com/programmersd21/flow) (Go terminal app) projects — not ports of their source code. Their bundled third-party notices now credit them as algorithm/design references (no upstream code is included) rather than reproducing licenses as though their source shipped in the app.
- **Modern/Metal main window: quick Cava toggle** — the first button in the modern/metal main-window button row now opens the Cava spectrum window (labeled **CV**) instead of toggling Compact Mode. Compact Mode remains available from the main-window right-click menu.
- **ART tab rating uses emoji stars** — in Modern and Metal skins, the star rating shown at the top of the Library Browser's ART view now renders as ⭐/☆ emoji, matching the visualization menus. Star sizing and click-to-rate behavior are unchanged.

### Bug Fixes

- **Fixed the app refusing to launch on macOS 14–25** — the bundled audio libraries (`libaubio` and its `libsndfile`/`FLAC`/`vorbis`/`ogg`/`opus`/`mpg123`/`lame` dependencies) were built requiring macOS 26, so on any earlier system the whole app would fail to start. They are now built/packaged targeting macOS 14, matching the rest of the app.
- **Classic Library text now follows UI Size** — changing **UI Size** in classic mode scales Library Browser row text, headers, labels, and search text, matching Modern and Metal. Stretching the window still only adds browsing space.
- **Long-track timers stay readable** — elapsed and remaining times of 100 minutes or more no longer corrupt classic digits or overrun the Modern/Metal time panels; negative long times shift the status icon to make room for the minus sign.
- **Dragged-in tracks can now cast to Sonos** — dragged lossless files (FLAC/WAV) whose sample rate wasn't detected at drop time were wrongly rejected as unsupported. They are now re-probed before the Sonos check; genuine high-resolution files above 48 kHz remain rejected.
- **Modern/metal alphabet picker clicks land correctly** — in the modern library browser, the offline-volume banner shifts the alphabet strip up, but click hit-testing ignored that offset, so clicking a letter could jump to the wrong one or do nothing. Drawing and hit-testing now share one geometry.
- **Modern PeppyMeter and Flow windows no longer show a seam on their outer edges** — a ~1-pixel gap could show the desktop through the left, right, and bottom edges on non-Retina displays. Those content edges are now aligned to the backing pixel grid.
- **Docked ProjectM, Library, and Plex-browser windows can size to align in a center stack** — these windows had a hardcoded 480-pixel minimum width, so when docked top or bottom in a center stack they couldn't be narrowed to match the stack. Their minimum width now floors at the spectrum/center-stack width instead, so they align cleanly.
- **Narrow Library headers stay readable and clickable** — the server controls and browse tabs in both classic and modern/metal Library windows now shrink together as the window narrows, preventing labels and controls from overlapping while keeping their click targets aligned with what is drawn.
- **Rips and YouTube downloads to a NAS no longer fail with "Bad file descriptor"** — yt-dlp's `.part`/`fsync`/rename and ffmpeg `+faststart` patterns are rejected by SMB/AFP volumes. Downloads and transcodes now run in a local staging folder, and only the finished file is copied to the destination.
- **Playlist stays on the now-playing track when the skin changes** — changing skins during playback made the playlist jump to the top and lose the now-playing highlight. Both classic and modern playlists now restore the selection and re-center on the playing track after a reload.
- **ProjectM presets no longer get blacklisted by mistake** — a preset is now disabled only if it *actually* crashes the app (detected by a SIGSEGV/SIGBUS handler) while it is on screen, at any point in its lifetime. Previously the crash marker was written the moment a preset loaded and only cleared on a clean quit, so any other shutdown — a force quit, an unrelated crash, or a dev build script's SIGKILL — blamed whatever preset was displayed and disabled it on the next launch; over many launches this silently disabled healthy presets, for some users all of them. Normal quits, force quits, and kills no longer disable anything, while genuine crashes (including late texture-related ones) are still caught. Existing installs have their erroneously accumulated list cleared once on upgrade, and **Visuals > Visualizations** now has a **Restore Disabled ProjectM Presets** command (showing the disabled count) to bring back any presets disabled by mistake.

  **If your visualizations have gone missing or thinned out over time, restore them:** open **Visuals > Visualizations > Restore Disabled ProjectM Presets**. The number next to it is how many presets are currently disabled — the earlier blacklisting bug may have quietly turned off many (or all) of your presets, and now that these crashes are fixed it's safe to bring them all back. Choosing it re-enables every disabled preset immediately.

## 0.28.2

### Improvements

- **Saved state and visualization preferences now have explicit reset controls** — the app menu exposes **Reset Saved State...** next to Remember State so users can clear only the launch-restore snapshot without touching durable preferences. Visualization menus now include reset actions for the main-window analyzer, Spectrum window, standalone Visualizations window, and all visualization preferences, restoring skin/app defaults while preserving unrelated preferences such as custom ProjectM folders, library columns, accounts, and compact mode.

### Bug Fixes

- **Modern skin visualization choices persist across app relaunches** — modern/metal skin visualization defaults now act as first-use defaults on launch instead of overwriting user-selected modes and options. Main-window Fire/Lightning/Matrix choices, Fire intensity, Spectrum-window mode/style settings, and scoped `vis_classic` options still reset when explicitly changing skins or using skin reset, but no longer revert just because the app reopened.
- **Waveform window frame now saves with Remember State** — the Waveform window's frame was included in the AppState schema but was serialized as `nil`, so it could not restore to the prior position. It now saves through `WindowManager.waveformWindowFrame` like the other remembered utility windows.
- **Classic 16-color skins and themed EQ art render correctly** — packed 1-bit/4-bit BMP rows now use the BMP bit stride instead of treating every pixel as a byte, fixing scrambled transport buttons, numbers, and playlist art in skins such as `ascii.wsz`. The classic EQ also draws its slider tracks and graph curve from each skin's `eqmain.bmp`, so non-default skins such as `Purple_Glow.wsz` no longer fall back to hardcoded green/yellow/red art.
- **Docked PeppyMeter and Flow windows no longer show a thin seam under the main window** — dragging the PeppyMeter or Flow window to dock it below the main window could leave a roughly 1-pixel line where the desktop showed through the join, most visible on standard-resolution (non-Retina) displays. Classic skins left a sub-pixel gap between the two window frames, and modern translucent skins exposed a strip of window background at the shared edge. Both now dock flush with no gap, matching the seamless docking that Metal skins already had.
- **App no longer freezes when Play is pressed rapidly with a VU or Audio Analysis window open** — quickly re-triggering track loads while the PeppyMeter/VU meter or the Audio Analysis Scope/Octave panes were open could deadlock the app. Those windows subscribed to realtime audio-tap notifications with main-thread delivery, which blocked the audio tap thread while the main thread was tearing the tap down during a track load. The affected windows now receive tap updates without blocking the audio thread.

## 0.28.1

### Bug Fixes

- **Command-line tool installer no longer blocked by Gatekeeper** — installing the optional `nullplayer` command-line launcher from the DMG previously failed with a Gatekeeper "unidentified developer" error (`-128`), because the bundled installer scripts inherit macOS's download quarantine flag and a quarantined script cannot be launched directly. The `Install NullPlayer CLI.command` helper now runs its inner installer through `bash` (which reads the script as data rather than executing the quarantined file), and clears the quarantine flag on the installed `/usr/local/bin/nullplayer` launcher so the `nullplayer` command runs afterward.

## 0.28.0

### New Features

- **CLI can cast videos to Chromecast and DLNA TVs** — headless `--cli` mode now accepts `--file <path>` for local audio/video files plus `--movie`, `--show`, `--episode`, `--season`, and `--number` for Plex, Jellyfin, and Emby video libraries. Video casts require `--cast` and route through Chromecast or DLNA TV targets with keyboard pause/resume, seek, progress display, and clean terminal restore on exit. Sonos is rejected for video because it is audio-only; DLNA video casts currently require `q` to stop the CLI because the UPnP path does not provide a reliable end-of-stream signal.
- **UI Size adds discrete scale choices** — the old **Large UI** toggle is now a live **UI Size** submenu with percentage choices from **50%** to **200%**, remembered across launches and UI-mode switches.
- **Flow network monitor window** — a new **Flow** entry in the Windows menu and main-window context menu opens a live network throughput meter in both classic and modern UI. It docks in the center window stack at the normal single-window height, shows either download or upload throughput with a scrolling history graph, and tracks the selected network interface. Double-click the window or use its right-click menu to switch between download and upload views; the chosen view persists across launches.
- **PeppyMeter analog VU meter window** — a new **PeppyMeter** entry in the Windows menu and main-window context menu opens a skinnable analog VU meter (a port of PeppyMeter) in both classic and modern UI. Left/right levels drive rotating **needle** meters or **bar** meters composited from bundled image templates (25 meters, including `vintage`, `bar`, `compass`, `chillout`, and `big-bang`). Right-click the window to pick a meter or enable **Random**, which auto-switches meters on an interval. It docks and snaps in the window stack, remembers its position across launches, supports fullscreen mode with sharper high-resolution templates when available, and consumes the shared stereo audio tap so it stays idle when closed. Bundled meter artwork is GPL-3.0 (see the third-party notices).
- **Modern main-window button row updated** — the main toggle row now starts with **CP** for Compact Mode, **VZ** for Visualizations, **FL** for Flow, and **PM** for PeppyMeter, followed by the existing EQ/PL/SP/AA/WV/LB window toggles.

### Bug Fixes

- **Center-stack windows keep docking below the main window after detaches** — opening Spectrum, Flow, PeppyMeter, Audio Analysis, EQ, Playlist, or Waveform now ignores visible center-stack windows that were detached and moved aside. New stack windows again dock directly under the main window or fill real gaps in the docked stack instead of drifting downward below floating windows.
- **Audio Analyzer and Flow windows drag consistently from their faces** — in both classic and modern UI, clicking and dragging the body of the Audio Analyzer or Flow window now moves the window just like Spectrum and the other center-stack windows. Close buttons, Flow's double-click download/upload toggle, right-click menus, and interactive controls on other windows keep their existing behavior.
- **Large NAS-hosted local files seek smoothly** — local tracks on network-mounted volumes are now staged to a temp file based on available disk space instead of a hard 300 MB cap, so very large files avoid SMB/NFS reads during playback and seeking. NullPlayer also cleans up its staged playback temp files on launch after a crash or force-quit.
- **Docked side windows resize to the current center stack** — reopening a docked Library/browser or Visualizations window now recomputes its height from the current main/EQ/playlist/spectrum/waveform/audio-analysis/PeppyMeter stack instead of replaying a stale remembered height. Detached side windows still reopen at the exact position and size where you left them.
- **Sweet Fades local crossfades pause and time correctly** — after a completed local-file crossfade, Pause/Play now control the active audio node instead of the silent original node. The elapsed time also stays aligned with the incoming track's audible position after the handoff, so later Sweet Fades trigger with a real fade tail. End-of-queue or otherwise declined Sweet Fades are latched per queue boundary so the console logs the reason once instead of every timer tick.
- **CLI server queries no longer return empty results at launch** — headless `--cli` queries and playback against Plex, Jellyfin, and Emby (`--list-artists`, `--list-albums`, `--list-tracks`, `--artist`, `--search`, `--radio`, etc.) now wait for the background server connection before running, instead of racing it and silently returning nothing (which surfaced as "artist not found" / "0 artist(s)"). When the restored current library is a non-music section — a Plex Movies/TV library, or a Jellyfin/Emby "Playlists", "Video", "Movies", or "TV shows" view — the CLI now auto-selects a music library for every music operation (queries, `--search`, and server `--radio`), or prints the available music libraries and asks you to pick one with `--library` instead of returning empty. `--search` also honors an explicit `--library`. `--list-sources` shows configured Subsonic/Navidrome, Jellyfin, and Emby servers as **Connected** instead of momentarily "Not configured", and now returns promptly because the CLI waits only for the connection, not for the full background library preload.
- **Play button no longer rewinds the clock during local playback** — pressing ▶ while a local file was already playing snapped the progress bar and the elapsed-time display backward (by a fraction of a second, or all the way to the start), making the track look like it ended early even though the audio kept playing uninterrupted. The play button now preserves the true playback position on a redundant press. Streaming and cast playback were never affected.

### Documentation

- **Non-affiliation disclaimer now names the full Winamp Group** — the README disclaimer previously listed only Winamp, Nullsoft, and Radionomy Group. It now enumerates the entire Winamp Group SA family — Winamp Group SA, Llama Group (former name), Jamendo, Hotmix, Bridger, and SHOUTcast — alongside the existing Sonos and Plex mentions, and clarifies the project is "not affiliated with, endorsed by, or connected to" those parties.

## 0.27.0

### New Features

- **Compact Window adds a free-floating mini player** — the Windows menu and main-window context menu now include **Compact Window**, which uses the same compact Library Browser mini-player as Compact Mode but keeps NullPlayer as a regular Dock/menu-bar app. It hides only the main window, leaves Playlist/EQ/Spectrum/Library/visualization windows where they are, uses normal window level unless Always on Top is enabled, can be dragged from both the player bar and browser area, remembers its frame, and restores across launches.
- **Balance control added to Playback menu** — the Playback options now include a Balance submenu with a slider and common left/center/right presets, giving modern UI and menu-only workflows access to stereo balance without adding more controls to the player face.

### Improvements

- **Modern and Metal UI now use a modern system font** — the retro low-fi bitmap font (Departure Mono) has been replaced throughout the Modern and Metal windows — Library tabs and headers, the main window, playlist, EQ, and spectrum — with the crisp macOS system font. Time and track digits stay monospaced so they don't jitter. Skins that ship their own custom font still render it as before.
- **License and branding terms clarified** — the project license notice and README now state GPL-3.0-only distribution terms and clarify that modified distributions must not reuse the NullPlayer name, icon, logo, bundle identity, or other branding without permission.
- **Compact Mode player bar reads like the main window** — in Modern and Metal, the Compact Mode display now splits into two distinct LCD "windows" with a padded gap: a single elapsed/remaining time counter on the left and the scrolling track title on the right (previously the title sat left with a cramped "elapsed / total" reading pinned to the right). The counter matches the title's size and weight, and the transport buttons are slightly larger.
- **Larger Library tab and control fonts** — the Library Browser's tab labels and control text render at a slightly larger size in non-compact mode for better legibility. Compact Mode is unchanged.

### Changes

- **Window shade mode removed** — double-clicking a window's title bar no longer collapses it to a title-bar-only strip ("windowshade"). This legacy Winamp feature was the source of recurring layout glitches when combined with Large UI, Compact Mode, and live UI-mode switching; removing it makes window sizing and position memory behave consistently across every window in Classic, Modern, and Metal.
- **Library source menu lists only sources** — the Library Browser's source picker no longer injects local-library settings ("Manage Folders…" and the "Clear Local Library" submenu) when the local source is active. Those are settings, not sources, and already live in the Library menu-bar item, so the source menu now lists sources only.

### Bug Fixes

- **Metal skin transport icons are now fully filled** — the previous/next (and eject) icons in the Metal finishes no longer show a stray light vertical line: the icon bars now draw in the same transport-button color as the rest of the glyph instead of the skin's light primary color.
- **Plex Artists no longer show duplicate same-name rows** — the Library Browser now groups Plex artist records with the same display name into one visible artist row in both classic and modern UI. Expanding, playing, or queueing that row still fans out across every underlying Plex `ratingKey`, so albums and tracks attached to duplicate server-side artist records remain accessible instead of being hidden.
- **Compact Mode art ratings fit the small UI** — the modern Library Browser's art-view rating stars now shrink in Compact Mode, preventing them from crowding or overlapping the source/library picker row.
- **Compact Window no longer reopens the main window after Space switches** — returning from another desktop or fullscreen app now focuses the floating compact mini-player instead of treating the hidden main window as something to restore, so Compact Window stays a one-window main-player replacement until you exit it.
- **Library window remembers where you put it** — after unlocking the connected windows and moving the Library/browser window, it now reopens at the exact position and size you left it — across closing and reopening it (via the menu or the red close button) and across full app restarts, even when it was closed at quit. First-ever opens still dock to the right of the window stack, and the position survives Compact Mode. Playlist, EQ, and Spectrum still intentionally snap back into the column below the main window.
- **Classic Large UI toggles instantly — no restart** — turning Large UI on or off in the classic skin now resizes the windows in place, matching the modern UI, instead of asking you to relaunch. The player, EQ, playlist, and other windows redraw crisply at the new size (no leftover "ghost" of the old size), and switching between Classic, Modern, and Metal while Large UI is on no longer distorts the new look.
- **ProjectM visualizer recovers from a preset that crashes mid-playback** — a rare bug inside the MilkDrop preset engine could crash the app while a preset was on screen — including minutes into a track, not just when the preset first appeared. The crash-guard now watches a preset for its entire time on screen (previously only its first frame), so the offending preset is automatically skipped on the next launch and the crash never recurs. Normal quits never flag a good preset.
- **Metal playlist and Library highlights are now clearly visible** — in Metal skins, the playlist's now-playing track and the Library Browser's selected/expanded row were indicated by text color alone, which several metal finishes render nearly identical to normal rows, so the active row was easy to miss. Both now draw a translucent green backlit-LCD highlight bar (matching the hi-fi display panels) as the cue. The metal playlist's row text is also unified at the Library window's brightness — previously it was dimmer — and the current track no longer recolors to the accent tone that clashed with the new highlight.

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

- **Switch between Classic, Modern, and Metal instantly — no restart** — changing UI mode, or picking a skin from a different mode, now happens live and in place. Playback, casting, the open playlist, the current track, and your play position all continue uninterrupted while the windows rebuild in the new look, reappearing where you left them.

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
