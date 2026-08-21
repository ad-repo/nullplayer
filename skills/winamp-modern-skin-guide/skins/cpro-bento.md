## cPro-Bento (`2222-cPro__Bento.wal` + ClassicPro 2.01)

*Per-skin status. Index: [skins.md](../skins.md) · engine-wide surface: [compatibility.md](../compatibility.md) · how a section gets written: `/wal-skin-report <skin.wal>`.*

**Fixture note:** the archive ships `screenshot.png` — 178×75, the author's own reference render.
Small, but it settles the questions that cost the most time here: the tab pills are **framed** and sit
*inset* inside the strip, the SUI sheet and playlist box have drawn borders, and the tab labels are the
long names at that window's width. The ClassicPro engine is user-supplied and imported separately
(`ClassicProEngineStore`); the skin is inert without it.

**Measured status** — `WINAMP_MODERN_RENDER_DUMP`, 2026-08-17 (Phase 24), engine ClassicPro 2.01:

```
arrangement=singleWindowSUI  catalog: playlist=embedded equalizer=embedded library=embedded
containers: main (player) · notifier · browserpro · widgets.manager
main/normal    500×500   158 nodes   min 446×201   declared 317×168   max 1920×1080
main/shade     500×23     24 nodes   min 317×23    declared 317×23    max 16384×23
notifier       128×80     13 nodes  (normal + desktopalpha layouts)
browserpro     200×200     4 nodes
compatibility  degraded — 46 findings, all warnings: 0 errors, 0 unsupported methods at startup
               resources 12 · groups 34
bitmaps        main/normal: 57 resolved, 3 unresolved
               (beatvis.overlay, custom.repeat., custom.shuffle. — declared, never shipped)
```

The 46 warnings are duplicate ids (the skin's own `custom-element-overide.xml` and `colors.xml`
deliberately override engine art, plus the engine overriding itself) and optional missing bitmaps
(`mainframe_lr/tb/title.png`, `vis_overlay.png`, `volume_ani.png`, `window/scrollgrips.png`, two
Reader icons). None is functional — Winamp tolerates all of them the same way.

**Shape of the skin:** single-window SUI — one `main` container, everything embedded, nothing
synthesized and nothing left to the classic fallback.

### Working

- **The framed surfaces** — `<grid>` nine-slice (Phase 24). The tab pills, the SUI sheet, the playlist
  box, the mini-view strip and the seek track are all grids; before this they drew *nothing* and read
  as flat black holes. 49 of them in this skin's include graph.
- **The tab strip is live** — clicking Media Library / Playlist / Video / Visualization / Browser
  activates the tab and switches the sheet, through the skin's own message chain: the tab button's
  script → `CproTabs` → `CentroSUI.onAction("show_tab")`. It re-lays itself out on resize and drops to
  short labels (`LIB`/`PLE`/…) when the sheet is narrower than 50px per tab, which is its own
  behaviour, not a defect. Phase 24; see the trap below about §15.6.
- **The Video tab plays video** (B23) — the skin embeds the video component in its tab sheet
  (`centro.windowholder.video`) and collapses its standalone `Video` container to a 1×1 stub, so
  until the embedded-video route existed the tab was an empty box and every film opened NullPlayer's
  own window beside it. Playing with the tab closed switches to it; switching away mid-film hands the
  picture back to our window.
- **The beat visualization** in the middle of the display, centred on the window and surviving play /
  pause / resume, with its VU timer started and stopped by the transitions. Double-clicking it cycles
  the animations (and **re-centres** them — `beat.m` centres only inside `onResize`, and showing or
  hiding a group is a geometry change, so this depends on the settle); right-clicking it offers the
  animation list.
- **Closing and reopening the playlist column** from the side-view arrows. The close button collapses
  the pane and the skin swaps in its *open* button, which ships `visible="0"` — so this only works
  because `onResize` is dispatched when a script moves something, and because hidden objects are still
  laid out. Without either, closing the playlist was a one-way door.
- **The playlist column and its splitters** — both dividers drag (`centro.mainframe` vertical,
  `centro.plframe` horizontal), and the mini view opens and closes.
- Transport, volume, mute, the kbps/kHz/stereo readouts, the clock, the menu bar, the drawer, the
  embedded library browser, the embedded EQ, and the colour themes.
- **The script-built menus placed at a computed point** (`popAtXY`, 6 call sites, with
  `clientToScreenX/Y` behind it). Right-clicking a tab opens its `Show Status Bar` / `Auto Close Tab`
  menu under the tab — measured with `RENDER_CLICK`, which prints the point the menu is placed at
  (`CLICK menu at 10,130` for the first tab, whose own frame is `(10, 104, 35, 29)`). Phase 24.

- **Colour themes** (Phase 32) — the engine's own `<ColorThemes:List id="colorthemes">` (in
  `player-normal-group.xml` / `xui/CentroSUI/_v2/drawer.xml`) populates with the six themes, and the
  drawer's switch / previous / next buttons all resolve it through `action_target`.

### Not implemented or knowingly wrong

- **Guilist-backed widgets** — `getItemLabel`, `getItemFocused`, `setSubItem`, `getAttributeName`: the
  skin lists (skin switcher, tag viewer fields) draw empty.
- **`XmlDoc` callback parsing** (`parser_addCallback`/`parser_start`/`parser_destroy`, 4–5 sites) —
  ClassicPro's optional `classicpro.xml` extras (custom beat-vis names, songticker antialiasing) are
  never read; every caller is behind `if (myDoc.exists())` and takes its skip path.
- **`enqueueFile` / `playTrack` / `clear`** — the playlist surface is NullPlayer's, driven by the app,
  not by the skin's script.
- The full unimplemented-method tally is in [compatibility.md](../compatibility.md).

### Traps this skin sets

- **The top-right damage came from the *playlist* column, not the volume slider.** `centro.plframe`'s
  collapsed top pane (`centro.playlist.directory`, the closed mini view) is **correctly** 6px tall, but
  its children are anchored for the 27px strip it has when open, so they resolved 21px *above* it —
  over `Volume`, `mute` and the `fileinfo` readouts, with `comp.goto` left floating as a stray `▭≡` on
  the display. A `Wasabi:Frame` pane is a window and always clips; that is the whole fix (Phase 24.2).
  The escaped children still *have* frames at y=79 — check their **clip**, not their frame.
- **`NULL` is an integer, and an object-typed variable has to be told that.** MAKI has no null literal of its own: `lastActiveT = NULL;` compiles to a plain integer 0, and storing that in an object variable left it comparing equal to null and reading as false while *not being* null — so `if (lastActiveT)` skipped it correctly and `lastActiveT.ID` (a different instruction, which fails closed on a non-object owner) took the whole handler down. `CproTabs`' `ON_TAB_ACTIVATED` opens with an unguarded `closeTab(lastActiveT)` whose first line is that read, so on the first tab activation of a session the handler died before its `sendAction("show_tab")` and before `alignByResize()`. The fix is one line in `MakiValue.coerced` (integer 0 / boolean false → `.null` for an object-typed target), not a special case in the member instruction. Probe it with `RENDER_CLICK` + `RENDER_CLICK_EVENTS=onleftbuttondown,onleftbuttonup`: the chain shows `CproTabs.xml.onaction!FAILED` before, and `CLICK action: show_tab` after.
- **A tab this skin closes is not a surface this skin destroyed.** The library, video and
  visualization surfaces are owned by the component bridge, one per skin, and re-served when their
  holder comes back; the tab strip removes and restores those holders all session long. Tearing a
  surface down when its holder goes made the *third* tab switch leave the browser on screen over every
  other tab (B24) — the repro is **Media Library → Playlist → Media Library → Playlist**, and the
  first two switches look perfect, which is why it reads as intermittent. `WINAMP_MODERN_DEBUG_HOLDERS=1`
  is the probe: `holders=[…]` without the matching entry in `subviews=[…]` is the bug, in one line.

- **`WINAMP_MODERN_RENDER_XUI`'s `onscriptloaded=false` is not evidence a script did not run.** It
  reports per-object *bindings*, and it says `false` for every object in this skin including
  `layout id=normal`, whose scripts demonstrably run. TASKS §15.6 concluded the tab strip's script
  never initialized from exactly that reading; the real cause was `Group.init(parent)` being a no-op
  (see below). Use `WINAMP_MODERN_RENDER_SCRIPTS`, which observes execution.
- **`newGroup` is only half of Wasabi's two-step.** `newGroup(id)` creates a group, `init(parent)` puts
  it where the script wants it — and the new subtree's own scripts must start **after** the second, or
  they look around from the wrong parent. Both tab defects (dead clicks, pills 4px out of place) were
  this one gap.
- **`getWidth()` must answer the *resolved* width.** The tab strip is `w="-4" relatw="1"`; answered
  from the attribute it is −4, and `CproTabs.m` compares that against the space its tabs need and
  squeezes every one of them to its 20px floor. Nearly all of this skin's geometry is relative.
- **A colour resource may be declared as a `<bitmap file="$solid" color="…">`.** This skin declares
  `wasabi.list.background` as both a `<color>` and a `$solid` bitmap, and the bitmap wins the registry
  — so a lookup insisting on `kind == "color"` fell through to the literal parser and became **white**,
  painting a white slab across the tab strip of a near-black skin.
- **The promo art double-centres itself — corrected by the engine's one skin quirk.** `beat.m` shows
  either the beat visualization or a ClassicPro logo in the same slot, swapped by a double-click. The
  beat visualization is centred at every width; the logo was out by exactly its own offset *inside* its
  300-wide box, because the box is placed at `centre − artWidth/2` (already centring the picture) and
  the picture is then offset inside the box as well. Measured against the display centre
  `143 + (w−317)/2`:

  | canvas | centre | beat vis | promo (before) | promo (after) |
  |---|---|---|---|---|
  | 700 | 334.5 | 334 | 334 ✓ | 334 ✓ |
  | 560 | 264.5 | 264 | 314 ✗ | 264 ✓ |
  | 500 | 234.5 | 234 | 384.5 ✗ | 234.5 ✓ |

  `WasabiSkinQuirks.correctedFrame` shifts the box back by the picture's in-box offset. Exact at all
  three branches and a **no-op** at offset 0 — the branch that was already correct, and the evidence
  that our `resize()`/`getWidth()` semantics are right and the skin's arithmetic is what is off. Read
  that file before adding a second entry; the bar is deliberately high.

- **The beat visualization is only ever enabled inside `frameGroup.onResize`.** `beat.m` assigns
  `showBeat`/`showPromo` nowhere else, and `System.onPlay()` → `refreshView()` → `showGroup(0)` hides
  both display groups first. Without an `onResize` having fired, pressing play made the visualization
  disappear for good. Any new window/scene must seed a resize after `scripts.start()`.

### Role in the implementation

**North-star.** Full 40-file include graph expands, graph builds, scripts bind and run, topology
yields exactly one SUI window; **renders** its frame, titlebar, menu bar, display, transport,
sliders, and — since the `Wasabi:Frame` splitter builds them — the SUI's tab strip, playlist pane
and album-art area. Since Phase 13 the Media Library tab hosts the **real library browser** and the
playlist pane draws the live queue; all three surfaces resolve inside the skin with no classic
window
