# Sonique Skins Phase 0 decision record

**Status:** locked 2026-10-11 by the user's sign-off (§ *Signed off*).
**Date:** 2026-10-11
**Implementation branch:** `feat/sonique-skins`
**Implementation base:** `8b8d4190` (`origin/main`)
**Product exposure:** public since Phase 2 closed (Amendment 5); an edition can still turn it off
(`AppFeature.soniqueSkinMode`).

Sonique skins are the sixth skin family, beside Classic, Original, Winamp Modern (`.wal`), Windows
Media Player (`.wmz`) and Audion faces. The format is `skills/sonique-skin-guide/reference/format.md`;
the ranked work is `tasks/SONIQUE_TASKS.md`.

## Decisions

- **A clean-room engine with a running oracle.** Sonique is closed source and nothing reimplements
  it. Real Sonique 1.96 under Wine is the oracle (`reference/harness.md`): a diff against its capture
  of a mode's default state is evidence, as with Audion's FaceKit, but animation and every non-default
  state are unmeasured until a probe exists for them.
- **The target is Sonique 1.96**, the last release, which reads skin spec versions 100 and 105.
- **The navigator's screens, as the user decided them 2026-10-18 (amends the first draft).** The
  menu screen keeps Sonique's layout and colours (`format.md` § *The navigator's menu screen*) with
  NullPlayer's items in it (§ *Control mapping*) and NullPlayer's wordmark where Lycos's logo sits,
  in the skin's `LogoColor` and `LogoRingColor`; the logo itself is never extracted or shipped, as no
  family ships the original player's own artwork. Only two screens stay inside the display: the menu
  and visual mode, which hosts the effects surface WMP's `<EFFECTS>` uses (Spikes, Bars, Ambience,
  Cava, vis_classic), extracted to a shared component. Playlist and library open NullPlayer's own
  windows beside the player. Audio controls is the drawer. **The other skin families are the
  template:** whatever the skin draws itself, NullPlayer never opens a window of its own for — the
  drawer is Sonique's equaliser, so NullPlayer's EQ window never opens in this family (the same
  routing WMP's `revealSkinSurface` does). What must match the oracle stays the menu screen's layout,
  the status line, the progress rings, the knob strips and the drawer.
- **No new behaviour for a skin.** Every control maps to an existing NullPlayer action
  (§ *Control mapping*); a Sonique feature NullPlayer lacks stays inert rather than being built here.
- **The oracle settles looks, never behaviour.** A control works the way NullPlayer's works in every
  other skin: its range, units and steps are NullPlayer's, not measured from Sonique (the user's ruling,
  2026-10-18, on the pitch knob).
- **Skins install as single `.sgf` files**, by Open/drag like the other families. No `.zip` import:
  Sonique distributed bare `.sgf` files, and none of the corpus came zipped.
- **The loading limits below are locked**, and never relaxed to make one skin load. A limit found to
  be mis-specified against its own threat model is amended here, argued about the threat.

## Provenance

| Item | Value |
|---|---|
| Format authority | Lycos's skinpack docs (`misc.txt`, `how-to-make-skins-1.09.txt`), kept outside the repo |
| Reference build | Sonique 1.96 portable, archive.org item `sonique_media_player` |
| Code | written from scratch; nothing adapted, so no notice row |

- **No Sonique or Lycos artwork, executable or text is committed or bundled**, fixtures included.
  That rules out shipping Sonique's default skin, which lives inside `Sonique.exe`; NullPlayer draws
  its own (§ *Omitted entries and the default skin*).
- **Oracle output is never committed.**

## Threat model

A user-supplied `.sgf` is a hostile binary file: attacker-controlled entry count, names, offsets,
sizes, JPEG headers and payloads, and INI text. It has no paths that reach the filesystem (entry
names are looked up, never written), no compression and no script surface.

1. The file size is checked before it is read.
2. The entry table is bounds-checked as a whole before any entry is read, and every entry's payload
   range against the file before it is sliced.
3. A region's byte length must equal `10 + 8 × count` before any rectangle is read.
4. Every JPEG's dimensions are read from its SOF header, and the per-image and per-skin pixel budgets
   checked, **before any image is decoded**.
5. Parsing and decoding run off the main thread. `MainActor` receives only a completed immutable
   skin.

## Loading limits

`SoniqueSkinPolicy` is the executable source of truth from S2. Codes are stable identifiers.

| Code | Condition | Outcome |
|---|---|---|
| `SQ0001` | not a `DAF\0` file, or the entry table does not fit in the file | fatal |
| `SQ0002` | file larger than 16 MB | fatal |
| `SQ0003` | more than 256 entries | fatal |
| `SQ0004` | an entry's payload range outside the file | fatal |
| `SQ0005` | a JPEG larger than 16,384 px on a side | fatal |
| `SQ0006` | more than 64 Mpx across the skin's JPEGs, summed from headers | fatal |
| `SQ0007` | `/skin.ini` larger than 256 KB | fatal |
| `SQ0008` | a JPEG that does not decode, or a region whose length is not `10 + 8 × count` | warning; entry treated as absent |
| `SQ0009` | a mode's picture absent, or its `Touch…Mode` is 0 (Amendment 1) | warning; that mode draws the default skin (§ *Omitted entries and the default skin*) |
| `SQ0010` | a region extending past its mode picture, small mode's drawers excepted (Amendment 1) | warning; clipped to the picture |
| `SQ0011` | an INI value that does not parse | warning; the key's default |

### Measured headroom (2026-10-11, the 524 skins in `SoniqueSkins/`)

| Limit | Bound | Corpus maximum | Skin |
|---|---:|---:|---|
| `SQ0002` file | 16 MB | 1,376,591 B | BoneKnot |
| `SQ0003` entries | 256 | 69 | Phos (P205) |
| `SQ0005` side | 16,384 px | 9,241 px | Eletro (`/jpeg/smallknob`, 9241×21) |
| `SQ0006` pixels | 64 Mpx | 5,724,136 px | RedWood_Update |
| `SQ0007` INI | 256 KB | 28,434 B | project_arms |
| region rectangles | u16 by format | 3,977 | Heaven&Hell (`/rgn/mid/frame`) |

The tightest margin is `SQ0005` at 1.8×; the knob strips are long and thin, so the pixel budget, not
the side, is the real decode bound. 819 of the JPEGs are progressive; ImageIO decodes them.
`SQ0010` fires on 11 regions: four frames one pixel wider or taller than their picture, and seven
buttons. Every row but the region count is reproduced by `scripts/sonique_census.sh`
(`skills/sonique-skin-guide/reference/harness.md` § *The census*); the entry count is raw table
entries, which is what `SQ0003` bounds, and a planning-session figure of 55 had collapsed duplicate
names.

### Amendment 1 (S2, 2026-10-11)

Two code rows contradicted the record's own rules once the loader ran over the corpus; neither change
makes a skin load that did not, and no fatal code moved.

- **`SQ0009` no longer fires on a missing frame.** The row said a missing frame put the whole mode
  on the default skin, while § *Omitted entries and the default skin* says omission is per entry and
  lists `/rgn/small/frame` (38 skins) as an ordinary per-entry fallback. The table is the decision;
  the row now matches it. With the row as written, 27 skins' small mode was discarded for want of a
  shape the default skin supplies.
- **`SQ0010` exempts small mode's drawers.** `/rgn/small/extratop` and `extrabottom` are the drawers
  that slide out above and below the bar, so they lie past the bar's picture by design: 429 of the
  440 regions the row first clipped were drawers.

## Omitted entries and the default skin

276 of 524 skins omit at least one entry, which in Sonique means "use the default skin's". The
skinpack tells authors to do exactly that (*"If you don't change something from the default skin,
don't make another one"*), so omission is per entry, not per mode: a skin can supply its own
navigator picture and still rely on the default drawer, knobs and lit states.

**NullPlayer ships its own default Sonique skin** (user decision, 2026-10-11), and every omitted
entry falls back to that skin's entry of the same name:

| Omitted | Skins |
|---|---:|
| `/jpeg/smallknob` | 134 |
| `/jpeg/shuttle`, `/rgn/mid/shuttle` | 109, 16 |
| `/rgn/nav/drawer`, `/jpeg/extra` | 79, 15 |
| `/rgn/mid/eq` | 54 |
| `/rgn/small/frame` | 38 |
| `/jpeg/volumeknob` | 13 |
| a mode's picture (`Touch…Mode = 0` counts as all of that mode's entries omitted) | nav 5, mid 2, small 11; the six skins with `Touch…Mode = 0` also omit the picture |

Rules for the default skin:

- **Its artwork is NullPlayer's own.** Never Sonique's (it is inside `Sonique.exe`) and never
  another family's.
- **Its layout is Sonique's default layout.** A skin that omits its drawer region expects the drawer
  where Sonique's default put it, so the default skin's frames, hit regions and `[misc locations]`
  must sit where Sonique's do. The positions come from `misc.txt`'s defaults; the shapes are measured
  from the oracle with no skin loaded and from the skinpack's `*_default.bmp` masks, used as
  measurements, never committed.
- **Its colours are `misc.txt`'s `[sonique colors]` defaults.**
- **It is a real `.sgf`-shaped skin**, loaded through the same model as any other, so the fallback is
  one lookup and not a second code path. It is also the family's unskinned fallback, which
  `skin-subsystem-blueprint` requires.
- **It is designed, not generated:** S11 is an artwork task and needs the user's eye.

## INI rules

- **Keys and sections are case-insensitive.** **The first `[skin]` section wins** when there are
  several (15 skins), matching Win32 `GetPrivateProfileString`. It decides those 15 skins' spec
  version: each writes `version=105` (or 100) in its second `[skin]`, so under this rule they read
  as version 100. Checked in S4 (Amendment 2): it changes nothing drawn.
- **Colours** are `0x` hex; the alpha byte is ignored (Sonique's own file mixes `0xFF…` and 6-digit
  values).
- **Numbers** read as their leading integer, as C's `atoi` does: `33.5` is 33, `69 (Repeat Green)`
  is 69, `0v` is 0. An empty value counts as unwritten (Amendment 2).
- **Expressions:** `NAME`, `NAME + n` and `NAME - n`, where `NAME` is another key in the same
  section, are supported; 200 values are a bare `NAME`, and 6 skins write `BIGON_DOWN_y = BIGUP_y + n`.
  Anything else is `SQ0011`, and the key takes its default.

### Amendment 2 (S4, 2026-10-11)

Measured through the oracle; `SoniqueSkinSettings` is the executable source.

- **Sonique reads `skin.ini` through the Win32 profile API.** `Sonique.exe` imports
  `GetPrivateProfileStringA` and `GetPrivateProfileIntA` and names a `tmpsskin.ini`: it writes the
  entry to a file and reads it per key, so the first section of a name is the one read, on Windows
  and under Wine alike. No visible check of the second `[skin]` exists: in 1.96, `version` gates
  none of what a still capture shows. Skins with no version draw their `NAV_*` lit-state positions
  (MintE, superman), their `/jpeg/nav_volumeknob` (CHRONIQUE1-0, day_of_defeat, CougarKW), and
  `DRAWER_POS` over `MISC_DRAWER_POS` (BlueEyes is 105 and does the same). The 15 skins' second
  sections hold only `version`, `Touch…Mode = 1` (the default) and logo URLs (inert), so the rule
  changes nothing they draw.
- **A number is its leading integer.** ChromeTech's `MISC_DRAWER_POS_x=33.5` puts the oracle's
  drawer at 33: the outline is exact there, 9 px off at 34 and 36 px off at the default 29. The
  record had made such a value `SQ0011`.
- **A bare `NAME` resolves.** corrosion's `NAV_CYANON_x=CYANON_x` draws from `CYANON`'s position,
  not from 0.
- **An empty value is unwritten** (8 skins). Unverified: no empty key is visible in a still
  capture. It is what Wine's `GetPrivateProfileIntA` returns, and it keeps a blank line from moving
  a button to 0.

`SQ0011` now fires on 3 values in the corpus, all colours: BoneKnot's `&H00FFFFFF&` (twice) and
OnePlayer's `verde`.

### Amendment 3 (S5, 2026-10-17)

- **`BlueBallsColor` defaults to `SystemColor_1`, not `misc.txt`'s `SystemColor_2`.** k2 writes no
  `BlueBallsColor`, `SystemColor_1 = 0xa80060` and `SystemColor_2 = 0xffffff`; the oracle draws its
  navigation balls magenta. The default skin's balls are cyan, `SystemColor_1`'s default, where
  `SystemColor_2`'s would be yellow. The default skin's other colours stay `misc.txt`'s.

### Amendment 4 (S16, 2026-10-18)

- **The drawer's amp, balance and pitch knobs are disabled** (the user's call). They set the
  preamp, balance and playback speed with no readout anywhere in the family, and a skin may draw
  them as anything — Pokemon's are 20 numbered buttons — so a stray drag leaves a bad setting the
  user never notices. They are chassis (`SoniqueSkinControl.isActionable`): a press drags the
  window. They still draw the engine's values, so a preamp, balance or speed set elsewhere shows.
  The EQ sliders and the volume knob are unchanged.

### Amendment 5 (Phase 2, 2026-10-18)

- **The family is public.** Phase 2 closed with S16 and S17, and the user asked for the feature to
  be made release-ready. `AppFeature.soniqueSkinMode` is no longer DEBUG-only; the DEBUG-only
  mechanism (`AppFeature.isDebugOnly`) had no other user and is removed. The census, render probe
  and oracle sweep stay DEBUG/test harness.

### Amendment 6 (2026-10-19)

- **`LogoColor` defaults to `SystemColor_2`, not `misc.txt`'s `SystemColor_1`.** The sonique skin's
  `skin.ini` has a `[skin]` section and no colours, so everything the oracle draws for it is
  Sonique's own default; its menu screen's logo is yellow, `SystemColor_2`'s default and the colour
  of the quick links heading beside it, where `SystemColor_1`'s would be cyan. With Amendment 3
  this is `misc.txt` swapping `LogoColor` and `BlueBallsColor`. Of 517 corpus skins, 502 write a
  `LogoColor` of their own.

## Control mapping

| Skin control | NullPlayer action |
|---|---|
| play / pause / stop / prev / next | the same |
| eject | Open Files… |
| shuffle | shuffle |
| repeat | NullPlayer's repeat on/off. Sonique's third state, loop one, is unreachable: NullPlayer's GUI has no repeat-one |
| volume knob | volume |
| drawer amp / bal / pitch knobs | **disabled** (Amendment 4); they draw the preamp / balance / playback speed. Formerly: preamp / balance / playback speed (`AudioEngine.setPlaybackSpeed`, the Playback Speed menu's control), centre detent 1.0×. The pitch knob spans NullPlayer's own speed range (`PitchTuningController`, 0.25×–4×, the menu's) on a log scale, and keeps NullPlayer's pitch-preserving speed. Sonique's own knob reads "Pitch Tempo" over 50–200 %, which is not copied |
| nav up / down rocker | on the visual mode screen, the previous / next effect; elsewhere, a page up / down in the Playlist Editor when it is open; otherwise nothing (S17, the user's call). Sonique pages the display with it (`pathdesc.txt`: "page up arrow", "page down arrow"); the earlier "moves the menu selection" was not Sonique's |
| menu: visual mode | the visual mode screen: the shared effects surface in the display |
| menu: playlist editor | the Playlist Editor window (`WindowManager.togglePlaylist`) |
| menu: find music | the Library Browser (`WindowManager.toggleMediaLibrary`) |
| menu: setup options | NullPlayer's right-click options menu, popped up at the item (NullPlayer has no Preferences window) |
| menu: audio controls | opens the navigator's drawer |
| menu: quick links (4 lines) | Spectrum Analyzer, PeppyMeter, Art, Waveform windows (`toggleSpectrum`, `togglePeppyMeter`, `toggleArt`, `toggleWaveform`) |
| menu: my sonique (skins, plugins, help, about) | the Sonique skin picker menu; Play History (`showLibraryHistory`); the About panel |
| mid `top` / `bottom` (song / list) | navigator visual mode screen / the Playlist Editor window |
| window balls (minimise, close, help, mode up/down) | minimise / quit / NullPlayer help / switch mode |
| `logohref` | nothing: a skin never opens a URL |

## Auxiliary-window policy

- **Sonique has no windows of its own besides its one window in three modes.** Its equaliser is the
  drawer and its visual mode a screen, so "ask what the skin provides first" answers: the Equalizer
  menu item opens the drawer (switching to navigator mode), and NullPlayer's EQ window never opens.
  The playlist is NullPlayer's Playlist Editor window (§ *Decisions*).
- **NullPlayer windows Sonique has no screen for** (library browser, spectrum, waveform, analysis,
  PeppyMeter, Cava, Flow) use the shared controllers painted through `WindowManager.hostedSurfaceStyle`
  from a `SkinnedSurfaceStyle` built directly from the skin's `[sonique colors]` (no sampling needed),
  every foreground through `SkinnedSurfaceStyle.legible`. Never another family's chrome.
- **Route to a track from S5:** eject (Open Files…) and the navigator playlist screen.
- **Placement and docking:** the shared tiler, placed once, with a `SONIQUE_PLACE_TRACE` flag in the
  first commit that places a window; the window is a snap target, not a centre-stack member.
- **Mode switches resize one window**, which keeps its top-left fixed, matching the oracle.
  Unverified: S5 checks it.

## Phase order

The S-rows in `tasks/SONIQUE_TASKS.md` run in order. S2–S6 are the spike; it stops at S6 for a
go/no-go against the oracle for the 12-skin sample before S7 starts.

## Signed off

1. **Pitch knob:** playback speed (§ *Control mapping*).
2. **Repeat:** NullPlayer's on/off only; Sonique's loop-one state is unreachable.
3. **Omitted entries:** NullPlayer's own default skin (§ *Omitted entries and the default skin*).
4. **Navigator screens:** the menu and visual mode in the display, playlist and library as windows, the drawer as the equaliser (§ *Decisions*, amended 2026-10-18).
5. **Exposure:** DEBUG-only until the spike passes and a later phase makes it public. Made public
   when Phase 2 closed (Amendment 5).
