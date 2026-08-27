# Winamp Modern (`.wal`) — Wasabi XML / XUI surface

Part of [compatibility.md](../compatibility.md). What the markup layer supports and what it does not.

## Wasabi XML / XUI

**Supported**

- Multiple document roots and raw ampersands (real skins contain both) — but tags must balance
- `groupdef` with `inherit_group` inheritance; `xuitag` custom tag registration
- `notify="key,value"` on a group instance delivers `onSetXuiParam("key", "value")` to the group's
  scripts, even when the instance tag is `<group>` rather than the XUI tag name. This is how Lobe
  passes `content` to its standard frame without using `<Wasabi:StandardFrame:Status content="…">`
- `instanceid` on a group instance **renames the expanded object**: it answers to the instance id
  instead of the groupdef's id, which is the only way a skin can address one of several instantiations
  of one definition — from `sendparams group="…"` and from a script's `findObject`. Winamp Modern's
  titlebar instantiates `wasabi.titlebar.streak` twice this way (Phase 24)
- Group template expansion during object creation, resolved **in document order**: an id defined
  twice serves each `<group>` the version written above it, the way Winamp's streaming parser does
  (T800 gives `player.main.cms` one body for its full player and another for its shade layout).
  A reference with no document position of its own — `System.newGroup`, a synthesized node — takes
  the newest version, and one written before every definition of its id takes the first
- Window dragging from the layout background, from a bare `move="1"` group, and from an `action`-less
  layer; `move="0"` opts a piece out (a layer whose own script owns the press)
- Button actions: `PLAY` / `PAUSE` / `STOP` / `PREV` / `NEXT` / `EJECT` / `SEEK` / `SWITCH` /
  `TOGGLE guid:…` / `EQ_TOGGLE` / `EQ_AUTO` / `EQ_BAND` / `EQ_PREAMP` / `MENU presets` /
  `MINIMIZE` / `CLOSE` / `VOLUME` / `COLORTHEMES_SWITCH` / `_NEXT` / `_PREVIOUS` /
  **`SYSMENU` / `CONTROLMENU` / bare `MENU`** (Phase 33 — the "≡" main-menu button at the top-left of
  a skin's title bar; it opens NullPlayer's own context menu, which is what Winamp's menu there is.
  Measured: `SYSMENU` in multipass, CornerAmp, Overdrive_2, winampmodern566, ZDL; `CONTROLMENU` in
  multipass, mmd3, Overdrive_2, ZDL — every one of them inert until then)
- **`dblclickaction=` / `rightclickaction=`** (Phase 36) — the second and third action attributes an
  object may carry, independent of `action=`. Both are read on any object, and an object carrying only
  one of them is hit-tested for it (a `<text>` song title is otherwise not an interactive type);
  `ghost="1"` still outranks them. The parameter is either the `;`-separated tail of the action
  (`SWITCH;shade`) or a sibling `dblclickparam=`/`rightclickparam=`, the explicit one winning. The
  tail split applies to `action=` too, so `action="SWITCHTO;<group>"` decodes. Measured: 62 uses in 9
  of the 17 skins — every skin's winshade switch is one
- **`TRACKINFO` / `TRACKMENU`** (Phase 36) — the two song-title commands, reached through those
  attributes. `TRACKINFO` opens a File Info **sheet** for the playing track (never a modal run loop:
  the action is script-reachable); `TRACKMENU` opens a track menu — File Info / Copy Title / Reveal in
  Finder — at the pointer. Distinct from `SYSMENU`, which is the host's main menu
- **`PAN`** (Phase 37) — the balance slider, 8 declarations in 7 of the 17 skins (multipass ships a
  real slider and a ghosted LED twin over the same rect). The drag writes `AudioEngine`'s balance and
  the thumb is **drawn from it**, not from the object's `value=`, so a balance changed anywhere else
  moves the skin's slider and two stacked balance sliders cannot show different positions.
  `WinampModernPanAction` owns both directions of the −1…+1 ↔ 0…1 conversion. Balance is deliberately
  not persisted, so the slider starts centred each launch
- **`cfgattrib` with no `action`** (Phase 45, B32) — the binding *is* the command, on a togglebutton
  and on a slider alike. Four of these address **host state** rather than skin storage and go through
  `WinampModernConfigBridge` to `WinampModernHost`: `{45F3F7C1-…};Shuffle` and `;Repeat`,
  `{FC3EAF78-…};Enable crossfading`, `{F1239F09-…};Crossfade time` (the last two are Sweet Fades, the
  seconds clamped into the range the app's own Fade Duration menu offers). By a wide margin the most
  common bindings in the corpus — 52 / 50 / 32 / 12 declarations across the 30 installed skins.
  A bound control keeps **no state of its own**: `getActivated()` and `getPosition()` both answer
  from the binding, the drag writes it in the control's own `low…high`, and the thumb and the
  `activeimage` are drawn from it — so shuffle changed from the menu bar and the skin's own lamp can
  never disagree. Everything the bridge does not name stays in the skin's namespace, and a skin that
  binds nothing but names its button `Shuffle`/`Repeat` (boom) still works off the id
- **`VIS_*` / `PE_*` / `VID_*`** (Phase 39) — the host-action families a skin puts on a toolbar
  button. Measured: **108 declarations in 11 of the 17 skins** (`VIS_*` 27 in 5, `PE_*` 39 in 7,
  `VID_*` 28 in 5, `CB_*` 14 in 4). Decoded in one place, `WinampModernHostAction`:
  - `VIS_NEXT` / `VIS_PREV` step **the visualization the user is looking at**: the visualization
    window's presets when it is open, otherwise the mode of the skin's own `<vis>` boxes (analyzer →
    oscilloscope → off, Winamp's order), written to every `<vis>` in the graph so the skin's other
    layouts do not disagree. `VIS_MENU` is that mode list plus the host's **Visualizations** menu;
    `VIS_CFG` is the options *of* the current one (the visualization window's own live menu, else the
    analyzer's `bandwidth`); `VIS_FS` opens the visualization window fullscreen
  - `PE_ADD` / `PE_REM` / `PE_SEL` / `PE_MISC` / `PE_LIST` are Winamp's five playlist menus, against
    the shared `AudioEngine` — the same calls the classic playlist window's buttons make.
    `PE_LISTOFLISTS` opens the same menu as `PE_LIST`. `PE_SEL`/`PE_REM` need a **multi-row
    selection**, so the host seam gained `playlistSetSelection` / `playlistRemoveRows` and the
    snapshot a `selectedRows` set; `selectedIndex` is still the anchor a click and the Delete key
    mean, and both default in the protocol extension so a host without a selection model still works
  - `VID_FS` and `VID_MISC` drive the video window: fullscreen, and **its own context menu** (audio
    and subtitle tracks included), popped under the skin's button. Both are inert with no video
    window, because there is nothing to make fullscreen
- Button actions **accepted and inert**, each recorded once in the skin's diagnostics with its reason
  (Phase 39): `VID_1X`/`VID_2X` (NullPlayer's video window has no native-size sizing to scale from —
  backlog **B20**, hosting the player in the skin's own video window, is what would give it one),
  `VID_TV` (no internet-TV source); `WA5:Prefs` (winampmodern566 — a Winamp preferences page, and
  there is no dialog to open)
  - `CB_NEXT`/`CB_PREV`/`CB_NEXTPAGE`/`CB_PREVPAGE` **left this list in B34**: the engine publishes an
    icon set for the thinger now, so the arrows scroll it by an icon and by a page
- Containers, layouts, layers, sprite regions, buttons/toggles with state images, sliders (horizontal
  and vertical), text, `clipchildren` parent clipping
- Bitmap fonts and TTF fonts (Core Text, not installed globally), colors, gamma groups. A
  `<bitmapfont file=…>` may name either a declared `<bitmap>` (Winamp Modern's form) or a path inside
  the archive (MMD3's form); both resolve, and the glyph sheet carries the font's own `gammagroup`
- `<text>` content: a script's `setAlternateText` overrides while set (`setText` clears it), then the
  `display=` binding (`time`, `songname` → "Artist - Title", `songinfo` → the stream-info line a
  `songinfo.maki` tokenises), then `text`/`default`, then the XML `alternatetext` as the
  nothing-to-show placeholder. `getText()` answers with the same resolved string
- Text placement: `align` (`left`/`center`/`right`) and, from Phase 38, **`valign`**
  (`top`/`center`/`bottom`, default `center` as in Wasabi) — 63 declarations across 9 of the 17
  skins, 54 of them `top`. Both draw paths honour it: the Core Text path insets the string inside its
  own rect (clamped, so a string taller than its box starts at the box's top rather than above it),
  and the bitmap-font sheet path offsets the whole run — that path used to be **pinned to the box's
  top edge**, which is `valign="top"` and nothing else, including for the rows NullPlayer draws into
  a skin's own playlist. `valign` on a `<layer>` (mmd3, ZDL) is inert here, as it is in Wasabi
- `<vis mode>`: `1` = **spectrum analyzer**, `2` = **oscilloscope**, `0`/`3` = off (a skin uses "off"
  when it fills the box with its own animated layer); an undeclared mode is the analyzer. `setMode`
  switches it. A skin's menu script is the proof of the pairing (`bandwidth` + `setMode(1)` vs
  `oscstyle` + `setMode(2)`)
- `<grid>`: nine-slice chrome — `topleft top topright left middle right bottomleft bottom
  bottomright`, corners at their art's natural size, edges stretched (or tiled with `tile="1"`) along
  one axis, `middle` filling the centre, all at the object's `alpha`. Every part is optional, and a
  grid that declares a single row or column is a **three-slice** whose one row/column takes the whole
  extent (cPro's tab pills carry only `top*`; the ClassicPro seek track only `left/middle/right`).
  Edges that together exceed the box shrink rather than overlap. Phase 24
- `<rect>`: a flat fill (`filled="1"`) or a 1px outline, in the resolved `color` at the object's
  `alpha`, with the object's own `gammagroup` applied. Phase 24
- `<gradient mode="linear">`: normalized `gradient_x1/y1/x2/y2` across the object's own rect and
  `points="0.0=R,G,B,A;1.0=R,G,B,A"`, per-stop alpha preserved, multiplied by the object's `alpha` and
  passed through its `gammagroup`. This is the exact form ClassicPro ships (a fade mask over a
  reflection). Any other `mode`, or fewer than two parseable stops, draws **nothing** and records a
  bounded diagnostic rather than inventing a colour. Phase 24
- A colour reference resolves from a `<color value="r,g,b">` **or** from a generated solid bitmap
  (`<bitmap file="$solid" color="r,g,b">`) — a skin may declare the same id as both, and the bitmap can
  win the registry. Phase 24
- `<ProgressGrid>`: `left`/`middle`/`right` over the filled span, growing from `orientation`'s edge,
  valued from the sibling `<slider>` that carries the `action`. Skins pair the two and make the thumb
  invisible (a 1×1 pixel), so the grid is the only position indicator they draw
- `<text>` metrics: `fontsize` is a **pixel height** (em ≈ 0.8 ×), `font=` resolves a declared
  `<truetypefont>`, an archive path, **or** an installed family name, `bold`/`italic` are honoured, the
  string is centred in its box unless `valign` says otherwise (`top`/`center`/`bottom`; a spelling
  Wasabi does not know reads as `top`, and only an absent attribute centres), `forcefixed` gives
  fixed-pitch cells, and a **time display is laid out as a run of fields** with the colon in the cell
  `timecolonwidth` sizes, room held for a two-digit minute, and clearance from the edge it aligns
  against (BB33)
- Script-built menus: `PopupMenu` with `addCommand`/`addSeparator`/`addSubMenu`/`checkCommand`/
  `popAtMouse`/`popAtXY`, shown as a real `NSMenu` at the mouse or at a computed point; both block and
  answer the picked id
- Hit testing follows Wasabi's region rule: a `group`/`layout` claims a point only where it paints a
  `background` — a bare container declared over the whole window does not swallow clicks meant for
  what is beneath it — and `animatedlayer` takes clicks like `layer` (MMD3's rotary knobs)
- Colour themes: a `<gammagroup value="r,g,b">` is a per-channel **multiplier**, `(4096 + v) / 4096`
  (0 = unchanged, +4096 = doubled, −4096 = zeroed), applied to bitmaps and to `<color>` resources;
  `gray` is a mode (any non-zero desaturates). The default theme is the **first gammaset in the
  document**, and the theme list keeps document order. A `gammagroup` id is scoped to its gammaset,
  not to the global resource namespace.
- `<ColorThemes:List>`: **supported** (Phase 32). Winamp's own colour-theme picker, an unregistered
  XUI tag the renderer draws itself — the catalog's names in document order, the applied theme and the
  selected row coloured apart, wheel-scrolled, single click to select and double click to apply. The
  host actions `colorthemes_switch` / `_next` / `_previous` are implemented, including `action_target`
  with `findObject`'s wide lookup; a button whose target resolves to nothing falls back to a popup of
  the theme names, as does `TOGGLE` on the Color-Themes preferences GUID. **No scrollbar** — a
  `<Wasabi:Scrollbar>` beside the list stays inert
- A `<Wasabi:Button text="…">` that resolves no artwork is drawn as a bordered label (Phase 32). No
  `.wal` ships `wasabi.button.*` art; it lives inside Winamp
- **Hidden objects are still laid out.** They are not painted and take no clicks, but their geometry
  resolves, they receive `onResize`, and `getWidth()` answers for them — Wasabi lays a hidden window out
  too, and a skin that hides a pane can only bring it back from its own `onResize` seeing the pane grow
  (cPro-Bento's side view). Phase 24
- An object whose frame is **entirely outside its parent** is culled with its subtree — skins park
  objects off-layout to hide them, and their art must not leak into the window
- Animated, N-state, ticker, album-art, and visualization elements
- Layout/shade switching, resize constraints, alpha-shaped window regions
- Namespaced per-skin configuration persistence, including the state the **engine** owns rather than
  the skin (`WinampModernSkinState`, B44/B44a): a splitter's divider offset, which layout a container
  is on (so a window left shaded comes back shaded), and whether one of the skin's own windows is
  open. Every one is written from a **user gesture only** — a script's `setPosition`/`switchToLayout`/
  `hide()` is the author's default and is never recorded
- Aliases and meta-commands
- `<Wasabi:Frame>` / `<frame>` splitters: the frame instantiates the groups named by
  `left`/`right` (vertical divider) or `top`/`bottom` (horizontal) and lays them out either side of
  an 8px divider placed `width`/`height` pixels from the `from` edge. On a frame,
  `getPosition`/`setPosition` are that offset. The divider is **draggable**: its grab strip takes the
  resize cursor and a drag rewrites `position`, bounded by `minwidth`/`maxwidth` (which skins spell
  that way for both orientations, and which are measured from the far edge when negative —
  ClassicPro's `maxwidth="-224"` means "always leave 224px for the other pane"). **A divider the user
  drags is remembered across launches** (B44) under `@nullplayer.frames` / `container-id/frame-id` in
  the skin's own namespace; a divider only the *skin* moved is not, so an author's default layout still opens as
  written. Restored in `scriptsDidStart()` and re-asserted once at 1.0s, because the skin's own
  `setPosition` may come from a timer
- Auto-sizing from text: a group with `autowidthsource="<id>"` takes the width of the descendant it
  names, and a `<text>` with no `w` takes its own content's width. `getAutoWidth()` measures with the
  object's real font (bitmap-font pitch or Core Text) plus `leftpadding`/`rightpadding`, so a skin
  that sizes its own boxes from that number gets boxes that fit
- `alpha` is honoured for **every** object, not only bitmap-backed ones: it is set once per node
  before the type-specific drawing, so a `<text alpha="0">` is invisible. Skins stack readouts in one
  slot and show one at a time by moving their alphas (Defix's Kbps / KHz / Channels), so text that
  ignores it prints every variant on top of the others. Phase 25
- A `<script param="…">` carries Winamp's macros, not a path: `@HAVE_LIBRARY@` expands to `1` (we host
  a library surface). A skin reads it with `getParam()` and lays itself out from the answer — Defix
  drops the Media Library tab out of its SUI tab strip when told there is none. An unrecognized macro
  is passed through unchanged. Phase 25
- `windowholder hold="guid:…"` component embedding, and `<componentbucket>` — Winamp's **thinger**:
  the five hostable components drawn as icons, clicked to open, scrolled by `CB_*`, and named by the
  `<text display="componentbucket">` beside it (B34; see
  [../reference/components.md](../reference/components.md) — *The component bucket*)
- The curated predefined `wasabi.*` standard-library base groups (`registerWasabiStandardLibrary`),
  including a clean-room text-only `Wasabi:TitleBar` that draws the window's own name
- `wasabi.panel` and `wasabi.objectframe.group` bodies. Winamp supplies their structure while the
  skin supplies conventional artwork ids, so each shell expands to a tiled nine-slice `<grid>`:
  `wasabi.panel.*` with `wasabi.panel.tint` in the middle, or `wasabi.objectframe.*` with
  `wasabi.objectframe.center`. Missing parts remain empty and a skin's own groupdef still wins. B15

**Not supported / degraded**

- Most remaining **`wasabi.*` shells are structure-free**, so a widget that has no body of its own
  draws nothing. Unresolved conventional *tags* — `<Wasabi:Button>` (CornerAmp and mmd3 colour-theme
  dialogs) and `<Wasabi:TabSheet>` (mmd3's winshade sidecar) — become inert nodes the same way.
- A base group outside the curated set warns and is dropped.
- A missing **optional** bitmap or cursor is a warning, not an error (Winamp-compatible).
- `file="$solid"` / `file="$gradient"` predefined bitmaps generate no **pixels**, so a layer that
  names one draws nothing. Their `color` is read where one is used as a colour resource (above), which
  is how skins mostly use them.
- `embed_xui` is retained as metadata only — it is **not** an inheritance edge.
- A splitter's `jump` (snap-to-detent) is parsed but not honoured — a drag is continuous.
- **`<vis>` attributes read: `mode`, `bandwidth` (`thin` is the full comb, `wide` Winamp's fat
  blocks), `oscstyle` (`Solid`/`Dots`/`Lines`), `coloring` (`Normal`/`Fire`/`Line`), `peaks`,
  `falloff`, `peakfalloff`, `colorband1`…`16`, `colorallbands`, `colorbandpeak`, `colorosc1`…`5`,
  `alpha`, `fliph`/`flipv`.** So a skin's own visualization settings page works — Big Bento Modern's
  and Love is War Miku's both write these. **Still ignored: `fps`** (a per-box frame rate; the scene
  has one clock, see `reference/performance.md`).
- `falloff` / `peakfalloff` are **0…4**, Slower…Faster, and are applied **per second**, not per draw.
  Measured, not assumed — they are written by MAKI at runtime and no markup in the corpus states
  them; `WINAMP_MODERN_RENDER_DISASM=@player-normal-group` on Big Bento shows its menu checkmarking
  `value == 0` … `value == 4`. The same listing is where `peaks` being `"0"`/`"1"` and `coloring`
  being words rather than numbers comes from.
- `<vis mode="2">` (oscilloscope) is drawn from **real PCM** — Winamp's own 576-sample `visdata`
  waveform, `UInt8` centred on 128, left channel only (the mirrored second box is the skin's job via
  `fliph`, not ours). It was a spectrum-derived zigzag until B51; the premise that the host publishes
  no PCM was simply wrong.
- Auxiliary container windows render and take input but do **not** drive per-container MAKI layout
  switching; the main window owns the scripted scene. (cPro-Bento is single-window, so this is
  invisible there.)
- Pixel-exact fidelity against real Winamp has never been verified for any target.

**Skin-script corrections.** The engine runs a skin's scripts and draws what they compute; it does not
second-guess them. There is exactly **one** exception, in `WasabiSkinQuirks`: ClassicPro's promo art
double-centres itself, so it jumped sideways whenever a double-click swapped it in for the beat
visualization. The bar for a second entry is in that file's doc comment — the correct placement must be
derivable from the skin's own numbers, exact at every size, and a provable no-op wherever the skin
already lands correctly.

Duplicate resource/group/XUI definitions **replace** earlier ones and warn — this is intentional
override behavior, not an error.
