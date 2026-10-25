# The `.sgf` format

What a Sonique 1.x skin is, as measured on the corpus. The authoring-side spec is Lycos's own
`misc.txt` (the `skin.ini` keys and defaults, "from the Sonique source code") and
`how-to-make-skins-1.09.txt`, both under `SoniqueOracle/docs/` (`harness.md` § *Where things are*).
They are Lycos's text and are never committed.

## What a skin can and cannot change

A skin re-textures a fixed UI; it adds no behaviour.

| Mode | Skin controls | Sonique draws, skin only recolours |
|---|---|---|
| navigator (`nav`) | frame picture and shape, button pictures and hit shapes, drawer, volume knob | the screen: menu, playlist, visual mode, setup, about, audio controls, search, status line |
| mid (`mid`, `msm`) | frame picture and shape, every button, the display placement, the progress rings | track number and time, the vis |
| small (`small`) | the bar picture | the shape (effectively fixed: the drawers depend on it), track and time text |

The skinpack's own words: *"You cannot change anything inside of the screens except color scheme"*,
and resizing a screen *"probably won't work"*. Mid mode is the exception in practice: corpus skins
reshape it freely (Trigun is a cross, MintE a swirl), see the sample captures.

**`0x000000` is transparent** in every picture, but inside the window Sonique paints black under
it: only the outline is see-through. The key still matters for what is drawn over a picture (lit
states, knob frames) and for the closed drawer under the navigator's. Authors use a near-black. Measured by the oracle sweep:
filling the outline black first took shape-exact captures from 86/93/146 to 512/519/492 of 524.

## Container

Little-endian, uncompressed. Every file in the corpus starts with `DAF\0LIST`.

| Offset | Field |
|---|---|
| `0x00` | `DAF\0` magic, then `LIST` |
| `0x08` | u32: offset of the first payload |
| `0x14` | `sgf\0`, the root name |
| `0x64` | u32: total file size |
| `0x68` | u32: entry count |
| `0x70` | the entry table: `count` entries of `0x64` bytes each |

An entry is a NUL-terminated name in a `0x54`-byte field (bytes after the NUL are garbage, not
zero), then u32 payload offset, u32 payload size, then 8 bytes of padding. The padding is zero in
every entry but the last, whose final 4 bytes are the start of the first payload: the table is 4
bytes shorter than `count × 0x64`, so read entries by stride and payloads by their own offsets.
Payloads are raw:

- **`/skin.ini`**: Windows INI text, CRLF, latin-1.
- **`/jpeg/<name>`**: a complete JFIF JPEG.
- **`/rgn/<mode>/<control>`**: a region, already rasterised by Skinmaker from the author's mask:
  u16 rectangle count, u16 `left, top, right, bottom` bounds, then `count` × u16
  `left, top, right, bottom`. Size is always `10 + 8 × count`; the census checks every region
  against that. **`right` and `bottom` are exclusive** (Win32 `RECT`): with it every mid and small
  outline of the oracle sample is exact once Wine's own distortion is accounted for (`harness.md`
  § *Outline comparison*).

**A repeated entry name reads its last copy.** 70 skins repeat a name (`/rgn/nav/drawer` in 59,
`/jpeg/skinthumb` in 24, `/rgn/nav/logohref` in 3), 18 of them with differing drawers; the oracle
draws the last drawer in all four measured (8C8-HQ, Danzig, skreen, `_cut_in11`).

## Window outline

| Mode | Outline |
|---|---|
| navigator | `/rgn/nav/frame` ∪ the closed drawer: `/rgn/nav/drawer` with its (0,0) at `DRAWER_POS` in `[misc locations]`, else `MISC_DRAWER_POS` in `[misc values]`, else 29,229 |
| mid | `/rgn/mid/frame` |
| small | `/rgn/small/frame`. The drawers add nothing while closed |

- **`DRAWER_POS` wins whenever it is written**, whatever the spec version: BlueEyes (version 105)
  and corrosion write both and the oracle draws `DRAWER_POS`. `misc.txt` says 105 skins use
  `MISC_DRAWER_POS`; Sonique reads it only when `DRAWER_POS` is absent (Trigun, Danzig).
- **`MISC_DRAWER_POS` of 0,0 is unwritten**: Barrels and winson99 write it and the oracle draws their
  drawers at 29,229. One zero is honoured (QTOSX's 0,230, blou_aple's `DRAWER_POS` 499,0).
- A skin with no `/rgn/nav/drawer` gets the default skin's drawer at 29,229, and one with no frame
  the default skin's frame. Sonique's default small frame is the one Pino, Splash and dm-candella
  carry.

## Entries

| Entry | Meaning |
|---|---|
| `/jpeg/navigator`, `/jpeg/midsonique`, `/jpeg/smallstate` | the three mode pictures, buttons drawn unlit |
| `/jpeg/misc` | every lit button state and the drawer; positions in `[misc locations]` |
| `/jpeg/extra` | the drawer screen (audio enhancement) |
| `/jpeg/volumeknob`, `/jpeg/smallknob`, `/jpeg/shuttle`, `/jpeg/nav_volumeknob` | horizontal animation strips; frame width and count in `[misc values]` (volume: 18px × 37) |
| `/jpeg/skinthumb`, `/jpeg/skinthumbmask` | the thumbnail Sonique's skin browser shows |
| `/rgn/<mode>/frame` | the window shape |
| `/rgn/nav/*`, `/rgn/mid/*` | hit shapes: `play`, `pause`, `prev`, `next`, `eject`, `repeat`, `shuffle`, `volume`, `up`, `down`, `display`, `drawer*`, `dknob*`, `shuttle`, `eq`, `top`, `bottom`, `songposring`, `listposring`, `logohref` |
| `/rgn/small/extratop`, `/rgn/small/extrabottom` | the small-mode drawers |

An entry absent from a skin means "Sonique's default" (Skinmaker writes `= #` for it). The default
skin's artwork is inside `Sonique.exe`, not in any `.sgf`, so a skin that omits an entry needs an
app-authored default: `SoniqueSkin.image(_:)` and `region(_:)` fall back to `SoniqueSkin.defaultSkin`
(a placeholder with no entries until S11), and `source(for:)` hands a mode left to the default skin
(`SQ0009`) to that skin whole, settings included.

## `skin.ini`

| Section | Holds |
|---|---|
| `[skin]` | author, title, url, `version` (100, or 105 for the extra 1.05 features), `TouchNavMode` / `TouchMidMode` / `TouchSmallMode` (0 leaves that mode on the default skin), `nav_logo_href` / `mid_logo_href` |
| `[sonique colors]` | ~25 `0xAARRGGBB` colours: `SystemColor_1..3`, `SystemBkColor_1..2`, `PlayListColor_*`, `ProgressColor_1..3`, `ProgressBkColor`, `StatusBar*`, `*KnobColor`, `Logo*`, `BlueBallsColor`, `InternalVis*` (105) |
| `[misc locations]` | `<NAME>_x` / `<NAME>_y`: top-left of each lit state in `/jpeg/misc`; `NAV_*` variants let nav and mid differ |
| `[misc values]` | drawer geometry, knob strip frame width and count, `NC_BB_DIST_FROM_RIGHT`, `mid_playlistmode` (270° or 360° ring) |
| `[msm locations]` | end positions of the mid-mode window-control balls (`MSM_SINGLEUP`, `MSM_HELP`, `MSM_MINIMIZE`, `MSM_CLOSE`, …) |
| `[preferences]` | Skinmaker's own font settings; ignore |

Only values that differ from the default are written, so every key needs its default from
`misc.txt`; `SoniqueSkinDefaults` holds them, and `SoniqueSkinSettings` resolves every key Sonique
reads at load. Some defaults are names (`NAV_PREV_y = PREV_y`, `LogoColor = SystemColor_2`), so they
follow the skin's value of that name. How a value reads (leading integer, `NAME ± n`, empty) is the
decision record's § *INI rules*.

- **`version` gates nothing a still capture shows** in 1.96: `NAV_*` lit positions,
  `/jpeg/nav_volumeknob` and `DRAWER_POS` are honoured with no version at all (decision record
  Amendment 2). `misc.txt` calls them 1.05 features; Sonique does not check.
- 15 skins carry more than one `[skin]` section: Skinmaker writes the first (author, title), and an
  author following `misc.txt` adds a second holding `version=105`. Only the first is read.
- A key written in the wrong section is not read. `NC_BB_DIST_FROM_RIGHT` is the common one (8 skins
  put it in `[misc locations]`, 3 in `[msm locations]`); whether Sonique looks there is unmeasured.

## Mid mode's song window

Sonique draws it itself, at fixed offsets from `/rgn/mid/bottom`'s top-left whatever the region's
size (identical in sonique, sTek2k, musicman, k2 and carrot, 86 to 94 px wide), cut to the region:

| Part | Where (from the region's top-left) | Colour |
|---|---|---|
| tab, open at the top, 3 px sides and bottom, rounded below | x 13–81, y 0–31 | edge `BorderColor`, inside `SystemBkColor_2`; pure black is not drawn (k2, BlueEyes, Stargate's inside) |
| track number, `000` with nothing loaded | digits y 5–15, centred on x 47 | `SystemColor_1` |
| elapsed time, `mm:ss.hh` | digits y 19–25 | `SystemColor_1` |
| status line: the title, `Sonique 1.96` when idle (NullPlayer writes its own name) | y 35–42 | `SystemColor_1` |

- About 37 skins have a song window too small for that, and Sonique lays them out tighter: Trigun
  (74×26) shows the time alone, centred; CougarKW (59×30) drops the hundredths. Not reproduced: they
  get the full layout cut to the region.
- In some skins Sonique also draws a `◀ vis ▶` tab at the bottom of `/rgn/mid/top` (sTek2k). Not
  reproduced.
- **The progress rings** (`songposring`, `listposring`) are the picture while empty, as every
  stopped capture shows; a flat `ProgressBkColor` there made 239 captures worse. How they fill
  (start angle, colour, `mid_playlistmode`'s 270° against 360°) needs a playing oracle, which the
  prefix cannot give: it has no sound device.
- **The shuttle at rest is the strip's first frame**: 258 mid captures closer than the middle frame.

## The navigator's status line

Sonique draws it on every screen along `/rgn/nav/display`'s bottom edge: a 13-row band in
`StatusBarBgColor` with a 2 px dot grid in `StatusBarFgColor`, cut to the display, and the title
(`Sonique 1.96` when idle) in `StatusBarTextColor`, centred 7 px left of the middle of the display's
span on that row, baseline 3 px above the edge. Trigun, Danzig and sonique all centre so; over the
corpus it took nav `colour` from 12.03 to 11.08 %.

## The navigator's menu screen

Sonique's own screen, the one it opens on (oracle captures of sonique, k2, BlueEyes, Trigun,
metrobin, bluehorizon and Danzig, 2026-10-18; `harness.md` § *The oracle* says how to reach it). Its
layout is the same on every skin, placed from the display's top-left; a skin changes only its
colours:

| Part | Colour |
|---|---|
| left column: three large items with a one-line subtitle and a boxed icon (visual mode, playlist editor, find music), then two small two-line items (setup options, audio controls) | titles, subtitles and icons `SystemColor_3` |
| right column: two headings (quick links, my sonique) of four links each | headings `SystemColor_2`, links `SystemColor_3` |
| the version (`1.96`) bottom centre, above the status line | `SystemColor_2` |
| Lycos's *sonique* logo top left | `LogoColor`, `LogoRingColor` |

The logo, the icons and the quick links are Lycos's and are not copied (decision record
§ *Decisions*). NullPlayer draws the layout with its own items (`SoniqueSkinMenu`, measured on k2), and its own
wordmark in the logo's place and colours: a 12 pt *null* where *LYCOS* is (x 27, baseline 25, raised clear of the word's *l*), and
*player* filled black and edged thinly in `LogoColor` from x 27 on baseline 48, in Arial Black widened
1.35× and leaning 0.21 so it has Sonique's 17 px x-height and 23 px letter pitch, over Sonique's
swoosh in `LogoRingColor`: a crescent between two ellipses leaning 13° clockwise, a line across the
top that swells to 4 px under the word, y 21–63 and x 52–158, fitted to k2's capture (2026-10-19;
`SoniqueSkinMenu.Logo`). The hole is held 1.2 px inside at the top and 2 px at the ends: Sonique's
own ends are thinner, and fitted that thin they broke up on screen. Nothing is extracted from `Sonique.exe`. The rest:
icon boxes 21 px at x 45, y 74/104/134 with titles (14 pt) at x 75 on icon top + 11 and subtitles
(8 pt) on + 20; the small pair's 19 px icons at x 21 and 117, y 169, two 11 pt lines on 177 and 186;
headings (11 pt, letter-spaced) at x 206 on 38 and 110, 8 px left of Sonique's 214 so *my nullplayer*
fits 496 of 516 skins' displays; links (9 pt, letter-spaced) at x 210, 11 px apart from 51 and 124; the version at x 191 on 209. Off the menu screen a back ball sits 12 px left
of the other five and returns to it (Sonique's playlist, visual mode, audio controls and search
screens show it).

## The navigator's drawer

The *audio enhancement* drawer hangs under (or over) the console at `DRAWER_POS` and slides
`MISC_DRAWER_DISTANCE_TOSLIDE` px to open: 75 down by default, negative for up (Trigun's `-71`).
Its art is `/jpeg/misc` from `DRAWER_x`/`DRAWER_y`, its own (0,0) at the drawer's; its parts are
in the drawer's own pixels, moved with it:

| Part | From |
|---|---|
| 20 EQ sliders | tracks `MISC_DRAWER_SLIDER_SIZE` at `…_ARRAY_POS`, `…_PITCH` apart; the handle is `/jpeg/misc` at `SLIDEROFF` (`SLIDERON` while held), `MISC_DRAWER_SLIDER_HANDLE_SIZE`, centred across its track (BlueEyes: 11 px on 13) |
| amp, bal, pitch knobs | `/rgn/nav/dknobamp`, `dknobbal`, `dknobpitch`; frames of `/jpeg/smallknob` (`MISC_SMALL_KNOB`), grey, multiplied by `AmpKnobColor`, `BalKnobColor`, `PitchKnobColor` |
| the tab that opens and closes it | `/rgn/nav/drawertop` |

The window keeps room for the drawer open, as small mode's does for its drawers. NullPlayer maps the
sliders to its 10 or 21 EQ bands by share, amp to the preamp, bal to balance and pitch to playback
speed over NullPlayer's own range (`SoniqueSkinAudioEngineHost.setDial`; decision record § *Control
mapping*).

Measured against the oracle's screen 6 (S14, sonique, BlueEyes, k2): the open drawer's outline is
exact, and Sonique draws two things the art alone does not say.

- **A slider handle is see-through by its darkness**: each pixel's opacity is its luminance over 128,
  so the handle's near-black frame vanishes, its mid-grey rim is half there and its face is solid
  (sonique's handle within 1 level, BlueEyes' blue ball within 5; opaque, or keyed below 64, are 9–48
  levels off).
- **A knob is opaque**: its pure black is drawn black, not the drawer under it. That holds for the
  volume knobs too (257 corpus captures closer), but not the mid shuttle (26 worse), whose black stays
  transparent.
- **A drawer knob sweeps 250° of a full-turn strip**, centred on its middle frame: frame
  `round((n − 1) × (0.5 + (value − 0.5) × 250/360))` of `n`. Measured at both ends (S15): frames 5–30
  of sonique's 36 on all three knobs, 3–16 of metrobin's 20, 2–8 of bluehorizon's 11; sonique's and
  bluehorizon's knobs then match the oracle pixel for pixel. Not the volume knob, which rests on
  frame 0 (`harness.md` § *The render probe*). BlueEyes' knob region shows only a part of its dial
  that no frame changes. A saturated tint reads off in a capture (metrobin's `00ff00` comes back
  near `73ff48`): that is the capture's colour management, not the multiply.
