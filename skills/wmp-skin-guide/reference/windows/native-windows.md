# `.wmz` windows: NullPlayer's own windows beside a skin

Moved verbatim from `reference/windows.md` on 2026-09-25; that file is the router. Read it first.

### Adding a NullPlayer-native window in WMP mode

The windows inside the rule today: playlist, library, equalizer, visualizations, spectrum, Cava,
Flow, PeppyMeter, audio analyzer, waveform, Sonos Rooms. The growth subset is the nine windows listed in the
current contract; playlist/EQ are explicit exceptions to step 8. A new metrics-based hosted window
wires every applicable step in the same change; each prevents a previously reported defect.

1. **Route before you host.** Ask `WMPSkinSurfaces` whether the skin declares this surface itself
   (§ *Ask what the skin provides before opening a window of your own*). A routing case added before
   the surface is hosted trades a duplicate window for an empty drawer.
2. **Colour** — nothing to do; `WindowManager.hostedSurfaceStyle` already answers for the family.
   Take the roles from there, never a hard-coded pair.
3. **Layout and hit testing** — `SkinnedSurfaceChrome.metrics(for:fallback:)`. The close control is
   a **hit area in the borrowed frame's top-right corner**, not a glyph of ours; nothing of ours is
   drawn over a borrowed frame. **Relayout on `hostedSurfaceStyleDidChange`, not just repaint**
   (W220) — the frame arrives after your first layout pass, and a subview framed for the old hole
   covers the ring. With no frame lent the window is titleless (`windows/hosting.md` § *Current hosting contract*): read
   the fallback through `SkinnedSurfaceChrome.paletteMetrics`, and make sure the corner close hit
   area wins over any subview under it.
4. **Chrome** — `WindowManager.hostedSurfaceFrameArtwork(for:)`.
5. **Paint the ground as `hostedGroundRect`, never `bounds`.** A `bounds.fill()` turns a shaped
   frame into a black box with the skin drawn inside it.
6. **Honour `paintsOverContent`** — draw your content, then the frame on top. The frame is not a
   border around a rectangle any more; it overlaps.
7. **If the view has an animation fast path, disable it whenever a skin lent a frame.** A 60 Hz
   content-only redraw erases overlapping chrome. The current static frame probe cannot exercise
   that redraw path; verify it with live-host, multi-frame captures.
8. **Grow, don't shrink** — `HostedWindowBorderLayout` adds the border around the interior off
   `WMPHostedFrameProvider.donorInsets` for registered metrics-based windows. Playlist/EQ remain
   excluded because their layout uses classic sprite geometry. Never scale content to make room.
9. **Verify on screen.** The `HOSTED-FRAME` line reports piece counts and rects; it cannot see a
   wrong bitmap, an erased bezel or a borrowed glyph. `WMP_HOSTED_FRAME_DUMP` and a
   `screencapture` of the live window are the instruments — `SKILL.md` § *Debugging a live defect*.

## NullPlayer's own windows beside a skin

Landed 2026-09-09. **This section is the *colour and content* half; the *shape* half — which donor
view is borrowed, how it is drawn and what is subtracted from it — is `windows/hosting.md` § *Every NullPlayer window in
WMP mode is the skin's or is themed* in `windows/hosting.md`, and that section is the authority. Read it first.** What
follows was written when colour was all a `.wmz` could lend, and the palette work below is unchanged
by W207/W209: a window still takes the palette, and takes a borrowed frame *as well* where the skin
lends one.

Four things carry the palette, and the last two were found by looking at the screen rather than by
reasoning.

- **The seam is family-neutral, and it is the one `.wal` already had.** `SkinnedSurfaceStyle` /
  `SkinnedSurfaceChrome` (in `App/Skinning/`, formerly `WinampModernSurfaceStyle`/`Chrome`) are built
  from `SkinnedSurfaceRoles` — seven colours and nothing else — so neither engine knows the other's
  markup. `.wal` derives the roles from a `WasabiPalette`, `.wmz` from `WMPSurfacePalette`, and both
  reach the views through **one** property, `WindowManager.hostedSurfaceStyle`, a `switch` on the
  controller family. The `.wal` names survive as typealiases, so no `.wal` call site moved.
- **The palette is declaration-first and then measured off the artwork.**
  `PLAYLIST` (`backgroundColor`, `foregroundColor`, `itemPlayingColor`,
  `itemPlayingBackgroundColor`) → `VIEW`/`SUBVIEW` background plus `TEXT` foreground → the **dominant
  opaque colour of the presented view's own rendered bitmap** → an app-authored WMP-neutral pair.
  The sampling step is not a nicety: measured over the 177 readable archives on 2026-09-11, **165
  declare a background colour and 171 a foreground** now that the parser accepts the SDK's named
  colours as well as `#RRGGBB`. Counts per role are in `WMPSurfacePalette`'s own doc
  comment, next to the scan that produced them.
- **Every foreground goes through the legibility guard, against the ground it is actually drawn on.**
  `SkinnedSurfaceStyle.legible`, the same WCAG 3.0:1 bar `.wal` uses — but it is load-bearing here in
  a way it is not there, because a `.wms` declares colour per *element*: the ground can come from a
  `VIEW` and the lettering from a `PLAYLIST` three levels down that was never drawn on it, and a
  sampled ground is one no author ever chose text against. Guard each role separately: the playing
  row's text sits on the window background until the row is *also* selected, the selection's text on
  the highlight. Guarding both against one background leaves an unreadable current track, which is
  what the reporter saw.
- **A skin-owned `PLAYLIST` is an AppKit overlay, so it needs the WMP palette directly.**
  `WMPMainWindowController` sets `WMPMainView.surfaceStyle` before installing native widgets and
  `WMPPlaylistSurfaceView` uses it for its ground, selected row, current row, and all three text
  roles. Leaving its historical hard-coded black/white colours produced a foreign black rectangle
  in Cerulean even though `ITEMSPLAYLIST backgroundColor="#9AACDB"` was declared. Do not route this
  through Classic or Winamp Modern state; it is WMP-owned surface state.
- **The playlist highlight is ours, not the skin's, and it follows the playing track.** No `.wmz`
  draws its own rows: `WMPMainView` substitutes `WMPPlaylistSurfaceView` for the skin's `PLAYLIST`
  element and the skin contributes only the palette above, so one row renderer serves all 170
  archives that declare one — a defect here is never one skin's. `WMPPlaylistSurfaceView` carries two
  distinct marks: the highlight bar is `selectedRows` (the user's selection; `selectedIndex` is only the
  arrow-key cursor inside it — see W272 below) and the `▶` prefix plus
  `currentText` colour is `snapshot.playlistIndex` (the playing track). Seeding `selectedIndex` from
  `playlistIndex` once, at first update, left the bar parked on row 1 for the whole session while the
  marker walked down on its own — reported 2026-09-16 against `nvidia`, but visible in every skin.
  `update(_:)` now re-homes the highlight whenever `playlistIndex` changes (a click or an arrow key
  still moves it; the next track change takes it back, as WMP's own playlist does) and
  `scrollSelectionIntoView()` pulls `firstVisibleIndex` the minimum distance to keep that row on
  screen, so a playing track past the visible rows no longer scrolls away. This surface has no
  `NSScrollView` — `firstVisibleIndex` and the wheel handler are the whole of its scrolling.
- **Scrolling to the selection is an event, not a state, and a host refresh is not one (W246).**
  `scrollSelectionIntoView()` does not merely *scroll*: it clamps `firstVisibleIndex` into
  `selected - visibleRows + 1 ... selected`. Calling it from `update(_:)` — which a host refresh
  enters ~12 times a second whether or not anything moved — therefore pinned the list to the
  playing track permanently: a wheel gesture moved it and the next refresh put it back within
  ~85 ms. Reported live 2026-09-20 on `Xbox Live Skin` as *"a large playlist cannot be scrolled
  properly"*, and it was not a rate defect but a total one — with a 200-row playlist, **70 wheel
  events down reached row 19 and stopped and 40 back up reached row 2 and stopped**, because the
  playing row was pinned first to the top and then to the bottom of an 11-row window. Rows 20-200
  could not be reached at all. A refresh now runs `clampScroll()` alone (the half that keeps the
  position inside the list, which is what a shrinking playlist still needs); a **track change** and
  a **keystroke** are what scroll. The wheel also read only the *sign* of `scrollingDeltaY`, so a
  trackpad flick carrying hundreds of points moved one row: precise deltas now accumulate in points
  with a fractional remainder kept, line deltas move a row each and carry the system's own
  acceleration. **This is one view shared by 174 of the 182 measured archives** — 161 declare
  `PLAYLIST`, 13 declare `ITEMSPLAYLIST` and none of those 13 declares a `PLAYLIST` beside it
  (`scripts/wmp_markup_census.sh`, 2026-09-20) — so it was every skin's playlist, not one skin's.
  `WMPPlaylistScrollTests` holds all of it down; six of its ten cases fail against the old code and
  the other four are the invariants the fix deliberately keeps. **What is still missing is a
  scrollbar**: the corpus authors no thumb of its own against a hosted `<PLAYLIST>` and this
  surface offers none, so there is no page scroll and no drag-to-position — and the `columns`
  attribute (`Title;Artist;Album;Type;Length` on `Xbox Live Skin`) is still drawn as title and
  artist. Neither was the report.
- **The pane's right-click is NullPlayer's own playlist menu, because no skin authors one (W272).**
  WMP skins left queue management to WMP's own menus, so the corpus draws no Remove/Sort/Clear
  controls against a `<PLAYLIST>`. `WMPPlaylistSurfaceView.menu(for:)` returns
  `PlaylistMenuBuilder`'s menu (`App/PlaylistMenuBuilder.swift`), the one the Modern playlist shows —
  lifted into `App/` because this engine may not reach into `ModernPlaylistView`, and the Modern
  view now builds its menu there too. Queue edits go straight to `WindowManager.shared.audioEngine`,
  as the Modern playlist's do; the next host refresh redraws the rows. Four rules hold it:
  - **The selection is a set.** `selectedRows` takes Shift-click (a range from `selectionAnchor`),
    Cmd-click (toggle) and Shift+↑/↓, so Remove, Crop and Invert act on more than one row; Delete
    removes every selected row, highest index first. `selectedIndex` stays the cursor.
  - **One highlighted row follows the playing track; several do not.** The `nvidia` rule above
    re-homes a selection of one row on a track change. A selection of several is the user's and
    survives it — otherwise the next track change would shrink it to one before the menu acted.
    An empty selection (Select None) is not re-seeded by a refresh either: only a cursor of `-1`
    (first load, a new library list) seeds from the playing row.
  - **A library preview is read-only (W136).** While the pane shows a library playlist every row that
    edits the queue is disabled; Play and the selection rows still apply to what the pane shows.
  - **The pane's menu sets `autoenablesItems = false`; the Modern playlist's keeps the default.**
    Neither view validates these rows, so under AppKit's default every row with an implemented action
    is enabled and `isEnabled` is ignored — which is how the Modern playlist has always behaved, and
    the builder keeps it. The pane needs its disabled rows to hold, so it opts out.
  A right-click on an unselected row selects that row alone first; on a selected row it keeps the
  selection. Verified live 2026-09-24; `WMPPlaylistMenuTests`. **A contextual menu cannot be driven
  synthetically** (`app-control` Route D), so verify a change here with the user driving.
- **A `.wmz` main window's width is not a zoom.** `playlistChromeScale` is
  `mainWindow.width / Skin.baseMainSize.width` — true of a *classic* player, whose 275px grid means
  its width is the size the user chose. A `.wmz` main window is the skin's own canvas: Corona's is
  596px, so our playlist drew its title and every row at 2.2x and the reporter's words were "the
  windows and title fonts are huge". It now falls back to the app's own scale in WMP mode, and
  `PlaylistView.scaleFactor` and the playlist's snapped default width route through that same
  property so the three cannot drift apart.
- **NullPlayer's playlist width is free beside a `.wmz` player.** The classic playlist steps its
  width in 25px PLEDIT tiles and stops at 275px; the gloss frame draws neither, and both kept the
  playlist off the player's width (Classic.wmz is 285 pt). `PlaylistWindowController.freeWidthMinimum`
  (24 pt, shared with Audion) turns off the step and replaces the minimum, including on a UI Size change.

### Ask what the skin provides before opening a window of your own

**The corpus declares six surfaces and this engine hosts two.** Measured 2026-09-09 over the 179
archives and their 595 views — `views` counts views declaring the surface, `own view` counts skins
that put it somewhere other than the view they open on:

| Surface | views | skins | own view | Hosted |
|---|---:|---:|---:|---|
| `<VIDEO>` / `<WMPVIDEO>` | 268 | 170 | 165 | no (W9 removed the opaque placeholder; W102 is the row) |
| `<EFFECTS>` / `<WMPEFFECTS>` | 178 | 171 | 144 | yes — this player's own visuals in the authored rect (W101) |
| `<PLAYLIST>` family | 175 | 170 | 162 | yes |
| `<EQUALIZERSETTINGS>` | 170 | 163 | 147 | yes — the skin's own bound sliders are the equaliser |
| `<VIDEOSETTINGS>` | 94 | 94 | 93 | no (W103) |
| `<NETWORK>` | 6 | 4 | 4 | object-only, and correctly so (W104) |

**`WMPSkinSurface` models the playlist and the equaliser, and its doc comment used to claim there
was nothing else to model.** There is: the visualizer and the video window are surfaces this app has
its own window for and 170 skins declare themselves, so the menu toggles for those open ours over
the skin's own — the same defect W93 opened for the playlist. **Adding a routing case before the
surface is hosted trades a duplicate window for an empty drawer**, which is why the routing row
(W105) is ranked behind the hosting rows and not with them. W101 has landed, so `.visualization` is
the case that may now be added; `.video` still waits on W102.

**A `.wmz` also authors windows this player has no content for at all**, and they are not defects:
`infoView` (45 `openView` calls across the corpus) is the skin's own about/links/gallery panel,
`contentView` (24) a promotional content viewer, `vidRemoteView`/`remoteView` a floating remote, and
`previewView` (16 skins), `mediaSwitcherView` (21) and `versionView`/`upgradeView` are opened by the
*host*, not the user — a skin-chooser thumbnail, a media-type switch, and a "you need a newer
player" notice. `controlView` (24 skins) is the windowless dispatcher described above. None of these
wants NullPlayer content mapped into it; leave them to the skin.

**171 of the 180 corpus skins declare a playlist and 164 an equaliser** (164 declare both), so for
those two surfaces NullPlayer's window is the *fallback*, not the default — opening it
unconditionally puts a second, differently-styled playlist over nearly every skin in the corpus.
`WMPSkinSurfaces` reads what the skin declares and `WindowManager.routeWMPSkinSurface` takes the
toggle first, exactly as `routeWinampModernSurface` does for `.wal`. Three shapes, and routing has to
answer all three — the corpus splits almost evenly between the first two (87 / 84):

| The skin declares it… | What the toggle does |
|---|---|
| in the view on screen (Corona's drawer) | nothing opens; the menu item is checked and inert, because the thing it names is already there |
| in another view (WoW's `plView`) | opens that view, the way the skin's own button does through `theme.openView` |
| nowhere (9 skins for playlist, 16 for EQ) | NullPlayer's window opens, in the palette chrome above |

**Match on the authored tag, not only on `WMPElementKind`.** `ITEMSPLAYLIST` is a playlist the object
model does not model yet — Corona's drawer is one — so a kind-only test reports that skin as owning
no playlist and opens ours on top of it. What decides this routing is what the skin *declares*, not
how much of it this engine hosts today.

The restore path passes `switchingViews: false`: a saved session must never move the user to a
different view at launch.
