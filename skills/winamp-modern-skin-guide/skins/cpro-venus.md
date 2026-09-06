# cPro — Venus ALPHA Port

`cPro_Venus_Alpha_port_by_Victhor_v1.3.1.wal`, v1.31 — RPeterClark's Venus brought onto the
ClassicPro engine by Victhor. A **ClassicPro `engine="one"`** skin, so it needs the engine imported;
without it the archive is inert markup. The skin that found B142.

## The shape of this skin

`skin.xml` includes `groups.xml`, `colors.xml`, a 146KB `colorthemes.xml`, `custom/custom_load.xml`,
`overwrites.xml` and `shadow/load.xml`, then leaves the *windows* to the engine — `custom/` supplies
its own `player-normal.xml`, `player-normal-group.xml` and a private copy of `CentroSUI` (`_v1`), and
the engine supplies everything under `@WINAMPPATH@\Plugins\classicPro\engine\one\`. Its own scripts
are five small ones in `scripts/`: `cbuttonsc` (centre the transport cluster), `customvis`,
`display_bg_toggler`, `sendparams`, `snapadjust`.

Rendered: `main/normal` + `main/shade`, `widgets.manager`, `browserpro`, `searchresults`, the
notifier (normal + desktopalpha), the two shadow containers and the About page. The player's declared
floor is 317x205.

**92 colour themes**, one `<ColorThemes:List>`, three `colorthemes_*` actions — the largest gammaset
count in the corpus after mmd3 and Big Bento. Names run `*Default`, `*Venus Original`, the Heavy /
Juiced / Pale / Greyscale families, `= Winamp MAC …`, `+ Drone …`.

## Traps this skin sets

- **Its transport buttons are centred by a script, not by the markup.** The whole cluster —
  `cbuttons.bg` plate, five buttons, the venus wordmark — lives in
  `<group id="c.buttons.centered" x="20" y="-20" fitparent="1" sysregion="1"/>`, and `cbuttonsc.maki`
  is three lines: `g.onResize` writes `setXmlParam("x", integerToString(w/2-112))`. A `fitparent`
  reading that pins the origin leaves the cluster at the left edge at every width (B142). See
  [`../reference/loading.md`](../reference/loading.md) → *`fitparent="1"` is a size, not a box*.
- **Its `<ModernSongticker>` carries the geometry, the `<SongTicker>` inside it carries `fitparent`.**
  `custom/player-normal.xml:47` writes `x="25" y="78" h="20" w="-53" relatw="1"` on the XUI tag; the
  engine's `xui/ModernSongticker/ModernSongticker.xml` declares the ticker itself as bare
  `fitparent="1"`. `ModernSongticker.maki` forwards every param it does not recognise onto that
  ticker, so a host that delivers geometry as a XUI param applies the group's box **twice** and the
  song title lands a display's width down and to the right, over the playback buttons. Geometry is a
  `GuiObject`'s own business and never reaches the script (B142).
- **The Color Themes control is in the drawer, and the drawer has a height floor.**
  `CentroSUI.m`'s `setDrawer()` opens with
  `if (xuiGroup.getHeight() < drawer.getHeight() + 90) { onOff = false; }`. The drawer is 119 tall,
  so the SUI area must be ≥209, and Venus sizes its SUI `h="-218" relath="1"` — **the main window has
  to be at least ~427px tall or the drawer toggle is a silent no-op.** Winamp behaves the same way.
  Route: drawer toggle (top-right of the component pane) → the *Select Drawer* button at the drawer's
  bottom-right → **Color Themes** → pick a row, then the middle **SET** button; ← / → step the applied
  theme without needing SET. The host's own **Skins → Modern → Color Themes** is the other route and
  drives the same state.
- **It ships a filename our `unzip` chokes on.** `What's new v1.31.txt` carries a non-UTF-8
  apostrophe; extracting the archive by hand needs `-x "What*"` or it aborts mid-file. The loader
  itself is unaffected.
- **Two seek sliders, by design.** `seeker2` (`ghost="1"`) sits under `seeker` at the same rect, and
  the SEEK and VOLUME thumbs are the same pill artwork — a screenshot showing "two seek buttons" is
  the volume thumb, not a duplicate (checked, 2026-09-06).

## Knowingly missing

- `enumItem` is unimplemented for the receiver `xml/widgets-manager.xml`'s script calls it on (×2),
  so the **Widgets Manager** list is short. The drawer's own page menu is unaffected — it builds in
  full (`*Equalizer, File Info, Stored Playlists, Color Themes, Playlist, Video, Visualization, …`).
- The drawer's *user widget* section reports "No widgets found for this view!" (`numUserWidgets == 0`
  off the `componentbucket`); the seven internal pages are all there.
- No `/wal-skin-report` run yet. Everything above was measured from the archive, the render sweep and
  `WINAMP_MODERN_RENDER_CLICK`.
