---
name: eq-profiles
description: EQ Profiles — per-track/album/artist stereo curves: the Equalizer Studio (session, audition, hosts, faceplates, RTA), EQ Cast (rendered FLACs for Chromecast/Sonos), graph placement, EQProfileController/Store/Resolver, the eq_profiles.db schema, scopes, Assign EQ Profile menu, queue/library ∿ markers, launch prune, and the DSP (31-band accurate cascade + parametric strip). Use when working on EQ profiles, the Equalizer Studio, EQ Cast, EQProfileMenu, or the profile audio unit.
---

# EQ Profiles

Per-content stereo curves made in the Equalizer Studio (`Windows/EqualizerStudio/`) and
assigned per track, album or artist (user-facing behaviour: `user-guide` § *EQ Profiles*). A curve is
two stages in series, both always heard: 31 graphic bands, then a 4-band parametric strip.

## Graph placement

- Local: `mixerNode → profileNode → localPitchNode → eqNode → WOW → mainMixerNode`. The spectrum and
  full-stereo taps on `mixerNode` are therefore **pre-profile**.
- Streaming: `player.attach(nodes: [balanceNode, profileNode, pitchNode, eqNode, wowNode])` — the
  local order, since AudioStreaming chains in attach order; the profile node is handed in like
  `pitchNode`/`wowNode`. AudioStreaming's `frameFiltering` reads `engine.mainMixerNode`, so the
  streaming feeds are **post-profile, post-EQ, post-SRS**.
- Casting and video have no local graph, so no profile. EQ Cast casts a render of the track with its
  profile instead (*EQ Cast*, below).

The Studio's analyser (`StudioRTA`, on `.audioStereoPCMFullDataUpdated`) follows from that: for a
local file it adds the auditioned curve to the pre-profile feed; for a stream it shows the feed as
is, labelled `OUTPUT`. Adding the curve to a stream would count it twice.

## Ownership

### Controller

`EQProfileController` (`Audio/EQProfileController.swift`) holds its nodes in an `AudioUnitFanout`
(`Audio/AudioUnitFanout.swift`, shared with SRS's `WMPWOWController`): the local node, replaced by
`replaceLocalNode()` in `replaceFailedAudioGraph` as `PitchTuningController` replaces its pitch node
(SRS never replaces its own), and weak streaming nodes from `makeStreamingNode()`, each configured as
it is made and again on `configureAll()`. Every node follows `currentTrack` (`trackDidChange` from the
`currentTrack` didSet); a Sweet Fades overlap hears the incoming track's profile on both sides.
`audition` (non-nil while the Studio is open) overrides resolution and the global toggle.

The local graph is `AudioEngine.localEffectChain`, in signal order; setup, rebuild, disconnect and
replacement all walk it (`attachLocalGraph`, `connectLocalGraph`), so a new local stage is one entry
there.

### Store and schema

`EQProfileStore` (`Audio/EQProfileStore.swift`, which also holds `EQCurve` and the scope types) is
storage only: the profiles and their assignments, in SQLite
(`~/Library/Application Support/NullPlayer/eq_profiles.db`, set up like `RadioStationRatingsStore`),
and the global toggle (`eqProfilesEnabled`, default on, in the `UserDefaults` it is given). Reads go
to the database; each change writes only its rows, bumps `revision` and posts `.eqProfilesDidChange`:
the controller re-resolves, and `WindowManager` runs `redrawPlaylistViews()`, which repaints every
queue's row marker — Classic, Modern, the `.wal` playlist and a `.wmz` `<PLAYLIST>` (its host
snapshot is refreshed first, since the marker rides on it). One connection per thread: `shared` is
the main thread's. EQ Cast's cache opens its own with `busyTimeout:`, since a read that hits a
main-thread write would otherwise fail and read as Inherit.

| Table | Columns | Notes |
|---|---|---|
| `eq_profiles` | `id` (UUID text, key), `name`, `curve` | `curve` is `EQCurve` as JSON, clamped on read; an undecodable one reads flat and is logged |
| `eq_profile_assignments` | `level`, `source`, `scope_key` (together the key), `profile_id` | NULL `profile_id` is **Off**; `ON DELETE CASCADE` from `eq_profiles` (the connection sets `PRAGMA foreign_keys = ON`), so deleting a profile drops its assignments |

A database that cannot be opened (an unreadable file, no Application Support) is logged as
`[eqprofile] database unavailable: …` and leaves the store empty: nothing is written or announced,
so the file on disk is never replaced. `init(path: nil)` is an in-memory database.

### Resolver, scopes and markers

`EQProfileResolver` (`Audio/EQProfileResolver.swift`, `.shared` over `EQProfileStore.shared`) is
everything above storage: the `Track` scope keys, `resolve`, `assign(level:tracks:)`, the queue
marker (`appliesProfile(to:)`, cached per track id until the store's `revision` moves) and the
strings — `setting`, `fileInfoLine`, and `queueTitle`, the one place the `∿` marker is put before a
queue row's title. Classic and Modern call `queueTitle(for:)`; the `.wal` and `.wmz` rows carry
`hasEQProfile` (`WinampModernPlaylistRow`, `WMPPlaylistItemSnapshot`) and call
`queueTitle(_:marked:)`. `WMPPlaylistItemSnapshot` leaves `hasEQProfile` out of equality, hashing and
coding: a marker change is not a queue change (`WMPObjectModel.queueGeneration`) and no script reads it.
`Track.playlistTitle` does not consult profiles.

Scopes (`Track.eqProfileScopes`, in the resolver's file; an `EQProfileScope` per level), most specific first, names
lower-cased and trimmed, a level omitted when its names are empty. `source` is `plex:<serverId>`
etc., `local`, `youtube` or `radio`. `key` is: at track level the service id (file path plus
`@cueStartOffset` for a cue track; the stream URL for radio, which has only this scope); at album
level `<artist>|<album>` (the artist is in it because `Track` has no album artist or album id); at
artist level the artist. Album level assigns every distinct (artist, album) pair among the row's
tracks, so a compilation is covered whole.

A **Library row** draws `∿` the same way (`LibraryBrowserListPainter` → `queueTitle(_:marked:)`) when a
profile is active on every one of its items (`appliesProfile(toRow:)`). Its scopes come from
`LibraryBrowserActions.eqProfileScopes(for:)`: a play row's `LibraryPlayable.eqProfileScopes` (the
menu's own, so the tick and the marker agree), a station's track, and a YouTube video's
`EQProfileScope.youtubeTrack(audioFile:)`, keyed on the audio download its row found on disk when
it was built, never by opening the file while drawing. `isEQMarked` caches each row's marker by row id in
`LibraryBrowserModel.eqMarkers` (`LibraryRowEQMarkers`), dropped when the rows are replaced or the
store's `revision` moves, so a paint reads no store; `.eqProfilesDidChange` repaints the browser
beside the queues.

### Assign EQ Profile

**Assign EQ Profile ▸** is `EQProfileMenu` (`App/EQProfileMenu.swift`). It ticks from each item's
scopes, most specific first: `assignment` at the menu's level, and `setting(of:)` over the scopes from
that level down for the *Inherited* line. Rows with tracks in hand pass `Track.eqProfileScopes`. A
library row passes `LibraryPlayable.eqProfileScopes`, read from the row without fetching or touching the disk: a track
row's converted tracks (a local track its own file, no cue lookup, so a cue-backed file's track
level shows unticked), a local album's stored tracks, and for a server album or any artist row
`EQProfileScope.containers(source:artist:album:)`, the same builder `Track.eqProfileScopes` uses
(normalisation and the `<artist>|<album>` key in one place). The row's album artist can differ from
the track artists a compilation's assignment was keyed on; such a row shows nothing ticked. Playlists
and folders pass nil, which ticks nothing. A pick still fetches the row's tracks and assigns to their
scopes. **Every write is a menu pick**: nothing else writes assignments except the launch prune, so a
track-level row nobody chose came from a menu acting on more rows than the user meant.

The set it acts on is the queue view's selection: Classic, Original and WMP right-click through
`PlaylistMenuBuilder.menu(target:clickedRow:state:)`, which selects a clicked row outside the
selection first, and `.wal` Misc ▸ Assign uses the bridge's selection. Every queue change re-bases
that selection onto the playing row, and an assignment only repaints (`.eqProfilesDidChange` →
`redrawPlaylistViews`, `MainWindowProviding.playlistMarkersDidChange()`), so the selection survives
it. The re-base itself is the queue views': `winamp-modern-skin-guide/reference/components.md`,
`wmp-skin-guide/reference/windows/native-windows.md`.

**Playback ▸ EQ Profiles ▸** (`EQProfileMenu.playbackOptionsItem`) holds the other two writes, both
by profile rather than by scope: **Unassign Profile ▸** lists each profile with assignment rows
(`assignmentCounts()`, Off rows not counted) and `unassign(_:)` deletes every row naming it, at
every level and source, as Inherit would; **Remove All Assignments…** runs `removeAllAssignments()`,
which deletes every row, Off included, so a leftover Off cannot block a later assignment below it.
Both ask first and keep the profiles.

At launch `pruneMissingLocalTracks()` drops `local` track-level assignments whose file is gone (a
cue key's `@<offset>` stripped), checking files off the main thread; a path under an unmounted
`/Volumes/<name>` is kept, and server, radio and YouTube rows are never touched. Local tracks stay
keyed by path rather than library id: a queue track opened from Finder has no library id, so a
moved file loses its profile.

### Curve

`EQCurve` is the stored curve: per channel (`left`, `right`, `curve[channel]`) a `Channel` of 31
`bands`, a `parametric` strip and a `preamp`. `EQProfileDesign.sections(for:sampleRate:)` (the
faders) memoises recent designs by (faders, rate), so one edit is designed once per sample rate
however many nodes and Studio views ask for it; `sections(for:channel:sampleRate:)` is what a channel
runs — those 31, then the strip's.

`EQParametric` (`Audio/EQParametric.swift`) is the strip: a 12 dB/octave high-pass (on/off,
20–500 Hz) and LF, LMF, HMF, HF bands, each frequency (overlapping ranges, SSL-style), gain (±12 dB)
and Q (0.4–8); LF and HF switch to shelves. Bells are the matched peaking section at the band's Q;
shelves and the high-pass are RBJ at Butterworth Q, so shelves have no Q dial. `sections` always
returns `EQParametric.sectionCount` (5) slots, identity where off or at 0 dB, so each keeps its slot —
and its filter state across a change. The kernel runs `EQProfileCoefficients.sectionCount` (36) slots per
channel: the faders' 31, then the strip's 5. A curve saved before the strip decodes it flat
(`EQCurve.Channel.init(from:)`).

## Equalizer Studio

The one place profiles are made and edited (`Windows/EqualizerStudio/`; what the user sees:
`user-guide` § *EQ Profiles*).

- **Session** (`EqualizerStudioSession.shared`) owns the edit: the profile loaded (`profileID`,
  `name`, `edit`), LINK, per-channel BYPASS, the mode, the faceplate kind and the analyser levels. It
  posts `didChangeNotification` on every change a view draws. It opens when a host is shown,
  loading the playing track's resolved profile, or *New EQ Profile* (flat) when nothing resolves.
  It closes only if neither host shows the Studio a turn later (`hostVisibilityDidChange`), so a
  skin or family switch keeps the edit. A skin teardown reports neither, so the session outlives it.
- **Audition.** Every edit runs `pushAudition`, which sets `EQProfileController.audition` to the
  edit with bypassed channels flattened. Close sets it to nil, and an unsaved edit is discarded
  (M46 in `tasks/MISC_TASKS.md`). Save / Save As / Rename / Delete / Revert go through `EQProfileStore`.
  `isDirty` compares against the stored curve.
- **LINK** applies an edit to the other channel *by the same amount*: a fader moves by the same dB
  and a dial by the same travel, so channels that differ keep their difference. A switch, FLAT,
  BYPASS and a fader reset set both channels to the clicked one's new state. HEADROOM sets each
  preamp so that channel's response peak is 0 dB. Responses and peaks are drawn at 48 kHz (`displayRate`).
- **Hosts.** `EqualizerStudioWindowController` is the standalone window: borderless and resizable,
  never below `EqualizerStudioView.designSize` plus the chrome, in the running family's
  `AuxiliaryWindowChrome`. It snaps, docks and group-drags, but is not a centre-stack window. A
  `.wal` skin that lends a frame hosts its own `EqualizerStudioView`
  (`configureForHostedSurface`) instead, through `routeWinampModernHostedWindow(.equalizerStudio)`.
  The two are never up at once. `WindowManager.showEqualizerStudio` / `toggleEqualizerStudio`
  route between them, and `isEqualizerStudioVisible` / `equalizerStudioWindowFrame` (what
  `AppState` saves) read whichever is shown.
- **View** (`EqualizerStudioView`): header, toolbar, and two channel panels (L above R). Each panel
  is an analyser over 31 faders, or in parametric mode a response graph over the strip's dials
  (`StudioStrip`), plus a preamp. A double-click resets a fader or dial. An empty-area press moves
  the window. The GRAPHIC / PARAMETRIC button picks which stage's controls are shown; it is a view
  setting (`equalizerStudioMode`), not part of the profile. Every curve drawn is both stages, and a
  band fader's cap is drawn at its own value plus the strip's response at its centre
  (`ChannelResponse.stripAtCentres`), so the faders sit on the curve; dragging changes only the
  fader's own value.
- **Faceplate** (`StudioFaceplate`): Console or Boutique (`equalizerStudioFaceplate`). Both are drawn
  in the hosting skin's surface style, or Classic's / Original's surface roles. Meter colours come
  from the skin (an Original skin's EQ colours, or a Classic skin's `viscolor.txt`). Boutique on a dark
  skin draws through the Metal bloom (`StudioBloom` → `BloomPostProcessor`). Buttons are the
  Library's tabs, drawn by the same code (`ModernLibraryTab`, `ClassicLibraryTab`).
- **Analyser** (`StudioRTA`): per-channel 31-band dBFS from `.audioStereoPCMFullDataUpdated`
  (consumer `equalizerStudio`, gated while open). An 8192-sample ring per channel and a Hann FFT run
  on a serial queue, so only finished levels reach main. For what is added on top per pipeline, see
  *Graph placement*.

## DSP

`EQProfileDesign` + `EQProfileKernel`, built to these rules — `EQProfileTests` pins each:

- **Accurate cascade** (Välimäki & Liski 2017): the 31×31 band-interaction matrix is inverted once
  per sample rate; fader dB → section dB through it, then refinement passes against the exact
  cascade response with the same inverse until every centre is within 0.01 dB. Target ±0.5 dB.
- **Matched peaking sections** (Vicanek 2016), so 16 and 20 kHz keep their shape at 44.1 kHz. Bands
  above 0.45 fs are not designed (low-rate streams).
- **Bandwidth 0.4 octave, section gains limited to ±24 dB.** ½ octave (the octave design's 1.5×)
  interacts too much: alternating ±12 dB missed by 3–4 dB. ⅓ octave dips 1.5 dB more between
  centres on a flat +12.
- Double precision, Direct Form I; sections within 0.001 dB of 0 are skipped.
- A new coefficient set crossfades over 10 ms against the running one (state carried for every
  section the old set ran); a set arriving mid-fade waits, only the latest kept. Render takes the
  lock only with `withLockIfAvailable`.
- No profile, flat, profiles off, or BYPASS: the render returns without touching the samples.

## EQ Cast

Receivers play the raw file, so a track's EQ profile is lost when it is cast. EQ Cast (**Output ▸
EQ Cast**, one global toggle, all device types) renders the track with its resolved profile into a
FLAC in a user-picked folder and casts that instead. Only the profile is rendered — not the
Equalizer window's EQ or other local DSP. User-facing behaviour: `user-guide` § *EQ Cast*. Casting itself: `chromecast-casting`, `sonos-casting`.

**Seam.** `CastManager.castTrack` and `castNewTrack` call
`EQCast.castableFile(for:device:generation:)` before their URL block; a non-nil file skips the
http/proxy branch, is registered with `LocalMediaServer` like any local file, and is cast as
`audio/flac`. `castNewTrack` passes `{ myGeneration == self.castTrackGeneration }`, so a superseded
request does not start a render; its existing `currentGen1` guard covers the wait. A render holds
the inflight queue, so a next/prev press waits behind at most one render, under its row in the
activity panel (`ActivityCenter`, id `eqcast-render`; see **ui-guide**). `castableFile` only answers; only a
successful cast calls `EQCast.didCast(_:from:device:)`, which records the render being cast (the
file Delete Cache keeps — a superseded or failed request must not replace it) and pre-renders the
first 3 of `AudioEngine.upcomingIndices` (the rest of the list or shuffle order; repeat without
shuffle is repeat-one, so just the current track, which re-renders after a profile edit; shuffle
with repeat draws a new order at the wrap and so stops at the end; it never realigns the shuffle
order). A render waiting out an older curve's render returns nil if `stop()` ran meanwhile, and
`castTrack` drops a cast superseded during its render. `stopCasting` and
`stopCastingSync` stop the pre-render; `_stopCastingAndAwaitTeardownCore` does not, because the
video-track switch runs it.

**Cache** (`actor EQCastCache`). Settings are UserDefaults `eqCastEnabled` and `eqCastFolder`.
`cached(_:device:)` checks, cheapest first: enabled, folder set, audio, not radio, not a cue
sub-track; then `EQProfileResolver.activeProfile(for:)` (nil → `.skip`, nothing deleted); then, for
Sonos only, `isSonosCompatible` with `resolveSonosSampleRate`, so an excluded file is never
pre-rendered. A file lives at `<folder>/<eqProfileSource>/<artist>/<album>/<Title> [<hash8>].flac`
(components through `YouTubeManager.sanitizedPathComponent`; `hash8` is SHA-256 of
`source \0 track key`, since `Track` has no track number and `hashValue` is per launch). The album
folder's `eqcast.json` maps file name → `{source, key, profileID, curve}`: a profile's curve is
edited in place under the same id, so a render is reused only while the whole curve matches.

**Threading.** The actor resolves on its own `EQProfileStore(busyTimeout: 2)` connection — never the
main thread's `shared` — so pre-rendering does no SQLite reads on main; without the
busy timeout a read during a main-thread write would fail and read as Inherit. CastManager reads the
engine on main and hands the actor tracks; UI updates (activity panel, `EQCast.usageBytes`) are
fire-and-forget pushes to main. `eqcast.json` is read and written on the actor, so two renders in
one folder cannot race on it.

**Render.** A server track is downloaded first (`URLSession.download`, from
`PlexManager.getCastableStreamURL ?? track.url`, into a temp file in the cache root). `AVAudioFile`
decodes; more than two channels or an undecodable source (e.g. Opus) fails, and a failure casts the
original. `EQProfileKernel` runs the curve in 32k-frame chunks at the source's own rate, then the
samples are hard-clipped at ±1.0 and quantised to Int16 — Core Audio writes 16-bit FLAC only from an
Int16 client format (Float32 gives 24-bit), and Sonos S1 decodes only 16-bit FLAC. The file is
written as `<name>.part.flac` (`AVAudioFile` takes the type from the extension) and renamed into
place. Callers for the same file and curve share one render (`inFlight` holds the entry with the
task); a request for a newer curve waits for the older render to finish, never joins it, so a profile
edited mid-render is not cast with its old curve. Progress is reported per 5% step and only ever
climbs. Delete Cache keeps the file being cast, because `LocalMediaServer` serves it by path.

**Logs:** `[eqcast]` — rendering, rendered, reusing, and why a render failed.

## Key Files

`Audio/EQProfileAudioUnit.swift`, `Audio/EQParametric.swift`, `Audio/EQProfileController.swift`,
`Audio/EQProfileStore.swift`, `Audio/EQProfileResolver.swift`, `Audio/AudioUnitFanout.swift`,
`App/EQProfileMenu.swift`, `Windows/EqualizerStudio/`; tests in `Tests/NullPlayerAppTests/EQProfileTests.swift`.
EQ Cast: `Casting/EQCastCache.swift` (the cache and its `EQCast` seam), `App/EQCastMenu.swift`
(**Output ▸ EQ Cast ▸**); tests in `Tests/NullPlayerAppTests/EQCastCacheTests.swift`.

## Debugging a live defect

Read `skills/live-ui-testing/SKILL.md` and `skills/winamp-modern-skin-guide/reference/harness.md`
§ *Debugging a live defect*, and take a playback snapshot as in `audio-system` § *Debugging a live defect*.

`[eqprofile] <title> → <profile> (track|album|artist)` is logged each time a profile is
applied to the playing track (track change, assignment change, toggle) — nothing is logged for a
track with none, `Off`, or profiles disabled, so a missing line *is* the answer. Whether the node is
processing: open the Studio, raise a preamp to +12, and the snapshot's `mainMixerPeak` should rise
×3.98; BYPASS returns it exactly. `[eqprofile] pruned <n> assignment(s) for missing files` is the
launch prune; silent when nothing was gone. `[eqprofile] assign <Inherit|Off|profile> at <level>
level to <n> scope(s) from <n> track(s): <first titles>` is every Assign pick, in release builds
too; `[eqprofile] unassign <menu item title> from all scopes` and `[eqprofile] remove all assignments` are
the Playback ▸ EQ Profiles writes. A count above one at track level from a single click is a menu acting on a whole selection. To
drive a pick without the user, use `winhelper rclick` and Accessibility (`app-control`, Route C).
