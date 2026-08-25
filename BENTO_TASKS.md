# Big Bento Modern (`.wal`) — backlog

The four variants: `Big Bento Modern`, `Big Bento Modern Light`,
`Big Bento Modern Windows 10 edition`, `Big Bento Modern Windows 10 edition Light`.

Split out of `TASKS.md` on 2026-08-23, which had accumulated four Bento sections (B35–B38) and
carries the rest of the `.wal` engine backlog. **Both files are tracked in git.** Anything here that
turns out not to be Bento-specific belongs back in `TASKS.md`; anything durable that is learned here
belongs in the skill —
`skills/winamp-modern-skin-guide/skins/big-bento-modern.md` for facts about this skin, the
`reference/` file that owns the concept for anything wider.

Skill: [skins/big-bento-modern.md](skills/winamp-modern-skin-guide/skins/big-bento-modern.md).

---

## Open

- [x] **BB1. `instantiate` — superseded by BB7, which corrects it.** Read **BB7** instead. This entry
      described the method as `instantiate(groupdef_id, index)` with "nine call sites" and called it
      a real engine capability rather than an arity question. The MAKI source says otherwise on all
      three counts (2026-08-23), and the engine already does the part this entry assumed was
      missing. The number is kept, not reused, so the correction is traceable. Closed with BB7.

- [ ] **BB2. The embedded library tab is unstyled** (was B37.5). The SUI tab below the player shows
      NullPlayer's own source bar and monospace tab row (`Source: Local Files`,
      Artists/Albums/Folders/…) rather than anything drawn in the skin's palette. **Not started**:
      this is a host-surface styling question, not a skin-script one, and it does not reproduce
      headlessly (the harness sets no component host). Compare against how cPro-Bento and Defix host
      the same surface before deciding whether it is a Bento-specific gap or the general fallback.

- [ ] **BB3. Bitmap overrides in the two Light overlays do not win.** Measured 2026-08-23 and
      recorded as a trap in the skill, never filed here. The Light editions ship light versions of
      ~30 of the *same* `window/*.png` the base declares (`frames.png`, `equalizer.png`,
      `no_alb_art_*.png`), but a `<bitmap file="window/frames.png">` declared in **base** XML
      resolves relative to that XML first, so it loads the **base's** artwork; only the `@SKINPATH@`
      fallback would reach the overlay's copy. The editions still read as light because their
      palette comes from `color-presets.xml` / `system-colors.xml` and the gamma model, so this is
      cosmetic today. **Do not** fix it by flipping `resolveSkinResource`'s order without a full
      corpus sweep — the relative-first order exists for authored subfolders.

- [ ] **BB4. Live QA of B38.4 / the rest of B38.3 — RAN, AND IT FAILED (2026-08-23).** B38.1 and
      B38.2 were confirmed on screen by the user; the B38.4 dispatch-binding fix and the four methods
      behind it were verified only headlessly and by a 300-image pixel diff. They do **not** hold in
      the running app. The user's screenshot of the header is timestamped 19:10 and the debug build
      it came from is 18:53 — the same working tree that contains every B37/B38 change — so this is
      not a stale binary. Still wrong on screen: a full-width cover-flow strip crosses the panel, the
      details column is squashed rather than laid out, and the album art is drawn twice (**BB6**).
      What *did* hold: the file-info panel fills its lines, though with the wrong content (**B39**).
      Re-measure **live**, not headlessly — B38 already established that three of its five defects
      never reproduced in the harness — with `WINAMP_MODERN_DEBUG_HOLDERS=1` and
      `WINAMP_MODERN_DEBUG_CLICK` + `WINAMP_MODERN_CALL_TRACE=1`. Treat the headless pass as
      necessary and not sufficient for anything in this panel.

- [ ] **BB5. `@HAVE_LIBRARY@`** — carried over from B36's follow-up because it is not Bento-only.
      A second unresolved token, never used as a path so the VFS never sees it
      (`<script … param="@HAVE_LIBRARY@">` here; `default_visible="@HAVE_LIBRARY@"` on the
      media-library container in Styx, Shield_Amp, S7Reflex, Defix). Winamp substitutes `1`; doing so
      is a *behaviour* change — four skins would start opening a library window — and needs its own
      live QA. **If this is picked up, move it to `TASKS.md` first**: four of the five skins it
      affects are not Bento.

---

## Open — the header / Multi Content View and the settings surface (filed 2026-08-23)

Research pass over the four variants' **top area** and their **customization surfaces**, prompted by
live QA of the header. Plan: `~/.claude/plans/abundant-pondering-hamster.md`. Every finding below was
verified against source; where something is unmeasured it says so.

**Three findings from this pass are engine-wide and live in `TASKS.md`, not here** — the `B*` series,
so the numbers do not collide: **B39** (`setText` vs `display=` — the repeated song title),
**B40** (`navigateUrl` policy and `ML_SendTo` — the dead lyrics/video buttons), and
**B41** (`getMonitorWidth`/`getMonitorHeight`). Two more were added on 2026-08-24 from the header
analyzer discovery below: **B43** (`fliph`/`flipv` ignored engine-wide) and **B44** (skin-scoped
persistence of skin config, whose first slice — the divider position — is now done). Bento is only
where they were found. The `BB`
numbers below run contiguously `BB6`–`BB15`; the plan file used a different provisional numbering for
the same items, so cite these, not the plan's.

**One thing to read before starting any of these:** the user's summary was *"enabling the settings
might be the key to understand what this skin can do."* That is right. These are **WACUP-era** skins,
not stock Winamp, and most of what they can do is switched on from a config surface that is inert
today. **BB7** is the item that unlocks it.

**The WebKit sequencing gate is satisfied (2026-08-23).** Browser windows and tabs now host a real,
ephemeral `WKWebView`, with a visible search/address field, policy-gated navigation, `url=`/`home=`
initialization and VFS-only local resources. This gives `B40` and the reader's `browser_search` an
internal destination, but their global/action routing remains separate work. Big Bento declares a genuine
`<Browser id="browserpro.browser" … url=""/>` in `reader.xml:90`, with a `reader.mode` two-state
button toggling *Web Reader ↔ Internet Browser*, an *Open in Default Browser* button, and a
`browserpro` provider-list container. The remaining reader gap is its list/action machinery, not the
web surface itself. cPro-Bento's engine-one SUI also has a reachable v1 Browser tab whose
`<Winamp:Browser home="http://www.skinconsortium.com/">` now initializes correctly; that historical
server currently returns an empty reply, which the surface reports as *Page unavailable*.
`BB11`'s `getItemLabel` is the same reader's list, so it may fall out of that work rather than this
backlog.

### Tier 1 — reported defects

- [x] **BB7. `GroupList.instantiate(groupdef, count)` — supersedes and corrects BB1. Done
      2026-08-23.** Built the config window's option pages and the SUI equalizer tab, which drew empty
      because the skin declares them as empty `<GroupList>`s and inserts their content by script.
      `getApplicationPath` was the domino behind it. Took the four variants from `unsupported` to
      `degraded`. **Confirmed live** — the EQ tab and all eight `instantiate`-built pages.
      Durable detail: `reference/scripting.md` → *`GroupList.instantiate`*,
      `compatibility/maki-surface.md`, and the skin's own file (which records the arity correction,
      the two call sites, and the three inline pages that make a control group).

- [x] **BB8. `ColorMgr.getGammaSet(name).apply()` — the 77-theme colour picker. Done 2026-08-24.**
      Bound by class GUID, not by method name; verified end to end against the real skin before any
      test. Not Bento-only — Ebonite_2_1 reaches the catalog the same way, so the surface fact lives
      in `compatibility/maki-surface.md` and the binding mechanics in `reference/scripting.md` →
      *Binding a host singleton by class GUID*. **Not verified live** — the page has content (BB7)
      but has not been clicked in the running app.

- [x] **BB6. The album art is drawn twice. Fixed 2026-08-24 — as `B42` in `TASKS.md`, because it
      is not a Bento defect.** The cause was `relatw`/`relath` greater than 1 falling back to absolute
      geometry, so the oversized dimmed backdrop drew at its literal `99×100` as a small crisp second
      copy. Reached 5 skins beyond this family. Rule: `reference/loading.md` → the `relat*` flags are
      `atoi(value) != 0`. The three-`albumart` trap this entry warned about is in the skin's own file.
      **Not yet confirmed live** (BB4's lesson): check the backdrop is now a dimmed wash behind the
      panel with one crisp cover.

- [ ] **BB9. The Multi Content View's three visualization placements. Partly done 2026-08-24 —
      routing and the analyzer landed; the overlap at launch is still open. Rewritten again; the
      entry this replaces was wrong on every count and cost a session.**
      **What the user wants:** the *stretched* pane (`info.component.vis.full`) is a **spectrum
      analyzer**; the *Visualization tab* (`wdh.vis.object`) and the *mini* pane
      (`info.component.vis`, album-art sized) are **NullPlayer's visualization** — ProjectM / Geiss /
      Tripex. Chosen 2026-08-24 when asked: with all three ticked they should sit **side by side**
      (`cover | viz | spectrum`), not replace each other.
      **Done.** `{0000000A-…}` is Winamp's visualization *plugin host*, whose default content is
      Winamp's own analyzer; we mounted the engine over every such holder unconditionally and
      `VisualizationEngineType` has no analyzer in it, so an analyzer there was unreachable by
      construction. `WinampModernVisualizationHolder` now routes on the **box** — a holder at or above
      3:1 is a letterbox strip and never takes the engine; of the rest the largest does; every other
      holder draws the analyzer instead of sitting black. `drawVisualizationBars` is a real analyzer
      now (band count from the box, `WasabiPalette` colours, peak caps) rather than 64 flat green
      bars, and deliberately borrows nothing from a nearby `<vis>` — `bandwidth="wide"` is 19 bands
      and 19 bands across a 1400px pane is a row of slabs. Rules:
      `reference/components.md` → *`{0000000A}` is a plugin host*; `reference/rendering.md` → *The
      analyzer a `<component>` box draws*. `swift test` 1104 pass (7 new,
      `WinampModernPhase60Tests`).
      **Still open — the overlap at launch.** Reported again 2026-08-24 after the session's revert:
      on reload the stretched pane and the file-info panes are all visible and drawn over each other.
      Cause is measured and is the skin's own: `mcvcore` declares `System.onScriptLoaded()` **twice**,
      and the second body starts a 700 ms one-shot whose `onTimer` shows the file-info panes back
      unconditionally, with no reference to which MCV page is current — so at launch it is the last
      word. Detail and the two dead ends in `skins/big-bento-modern.md` → *BB9*. **Do not fix it by
      running only the first `onScriptLoaded` body** — that was tried and reverted; the second body is
      where the panel's width layout lives, so it takes the sizing out (177 nodes and no
      `set_maxwidth`, against 188 with both). The corpus sweep was clean and it still broke the skin.
      **Next step is the side-by-side layout, which supersedes the exclusivity question**: the skin
      never lays all three out (`info.component.vis.full` is `w="0" relatw="1"` and its routine hides
      the others), so this is a NullPlayer-side layout override. The narrow version is to narrow that
      holder to the span its visible siblings leave — Bento already places `mini vis | cover | file
      info` correctly at `x=3` / `x=195` / `x=370` when both are ticked. Open question recorded when
      the choice was made: with **Show file info** still ticked the track text would sit over the
      bars, unless the spectrum takes only what is left after it.
      **A fourth placement exists, and nobody knew — found live by the user 2026-08-24.** Widening the
      player pane reveals `main.vis.group` in the **header**, beside the transport buttons: a
      288×60 group of four `<vis>` boxes at `x=436`, declared in `player-normal-group.xml:255`. It is
      not one of BB9's three `{0000000A}` holders and is not routed by
      `WinampModernVisualizationHolder` at all — these are real `<vis>` elements the renderer draws
      itself. Two things came out of it, both engine-wide and both in `TASKS.md`: **B43**
      (`fliph`/`flipv` were ignored, so the intended mirrored butterfly drew as two identical blocks
      with a seam) and **B44** (the divider position was not persisted, which is the only reason this
      went undiscovered for the whole B35–BB22 run; a dragged divider now survives a relaunch, though
      the skin's own narrow default still hides the group until the first drag).
      `visualizer.maki` also registers an **`Alt Visualizer`** setting that swaps the pair for
      `main.vis.group.alt` — a single 252px analyzer plus reflection — along with `Visualizer Mode`,
      `Show Peaks`, `Visualizer show Lines` and the two falloff speeds. Both groups are placed with no
      `visible=`, and the script hides whichever is not chosen; that hide is running correctly. So the
      header's own visualization has a settings surface already, which is BB7/BB10 territory rather
      than new work here. **Do not fold the header into BB9's side-by-side layout question** — it is a
      separate placement with its own script and its own config.
      **Corrections to what this entry used to say:** the defaults *are* reachable and the plumbing
      *does* work; an embedded `<component>` in the player body **does** get a surface — that question
      is closed; BB7 and B40 are not involved; and **the skin ships no `.m` sources at all**, so the
      `mcvcore.m:256` / `:266–267` citations refer to nothing in the archive.

- [x] **BB12. The header strip and the seek bar — measured 2026-08-24. The seek bar is fixed; the
      header did not reproduce.** The seek bar was a solid black bar because `wdh.waveseeker` — a
      `<windowholder … hold="none"/>` sitting on top of it — was read as an *unknown* component and
      painted an inert slab. `none` means the holder holds nothing. Rule: `reference/components.md` →
      *Component hosting*; the skin's own file records the rect and the corpus scan.
      **The header did not reproduce headlessly** — the dump draws the hamburger, bolt, WINAMP logo
      and all five menu items, and the titlebar art really is a flat four-colour gradient. Neither
      BB3 nor an unresolved frame bitmap is involved. **This half stays open as a live question**:
      re-measure in the running app before filing any cause.
      **The Windows 10 editions' seek bar is still blank, separately** — they ship
      `waveseeker.rounder.bg` as `visible="1"` where the base ships it `visible="0"`, an opaque wash,
      and `seek.maki` runs clean without hiding it. Cause unmeasured; do not guess one.
      `swift test` 1074 pass (7 new, `WinampModernPhase57Tests`); 288-image sweep, 285 identical.
      **Confirmed live by the user, 2026-08-24.**

- [x] **BB16. One click on the seek bar hid it, and then it could not be clicked again. Fixed
      2026-08-24.** Reported live right after BB12 made the bar visible. **Pre-existing, not caused by
      BB12** — it reproduces identically at `HEAD`; the slab had been hiding the bar in *both* states.
      `seek.maki` hides its own only seek slider on mouse-up and mirrors the trough and fill to it, so
      one press-release took the whole bar out — and an invisible object is not hit-testable, so
      seeking stopped working until a track change.
      Fixed by a **stranded-control rule** that keys on the layout, not the skin: a `hide()` leaving a
      layout with no visible control for a positional host action is undone when the event settles.
      Defix runs the identical script and does not trip it. Rule, its three deliberate properties, and
      why stock Winamp Modern is unaffected: `reference/scripting.md` → *A layout must not be left
      with no way to seek*. A second gap fixed in the same path — `Timer.onTimer()` called as a method
      — is in the same file → *An event handler is also a method, on every kind of receiver*.
      `swift test` 1082 pass (8 new, `WinampModernPhase58Tests`); 288-image sweep, 287 identical.
      **Confirmed live by the user, 2026-08-24.**

- [x] **BB17. Should there be a "WACUP skin" concept with its own engine branching? Measured
      2026-08-24 — no.** Closed rather than left open so it is not re-proposed. The finding is durable
      and lives in the skill: **[reference/wacup.md](skills/winamp-modern-skin-guide/reference/wacup.md)**
      — how a skin probes for WACUP, why we answer truthfully, what the 69 references in this family
      actually gate (branding), and why the WACUP-only *surfaces* are gated on ordinary settings
      rather than on the dialect.

- [ ] **BB18. Host a real waveform seeker at `wdh.waveseeker`.** Blocked by the skin, not by us:
      `Use integrated Waveform Seeker` is never registered on a non-WACUP host, so a surface hosted
      there is inert. Needs a design for offering the capability without impersonating WACUP.
      Detail — the setting, the driving script, the measurement, and what NullPlayer already has to
      host it — in **[reference/wacup.md](skills/winamp-modern-skin-guide/reference/wacup.md)** →
      *The trap*.

- [x] **BB19. The settings pages could not be scrolled. Fixed 2026-08-24, confirmed live.**
      **Seven independent faults, stacked** — the table and the durable rules are in the skin's own
      file (`skins/big-bento-modern.md` → *BB19*) and in `reference/scripting.md` /
      `reference/rendering.md`. In short: the wheel never reached a skin; `scrollToPercent` was a
      no-op; the `embed_xui` seam carried neither the value events nor the declared range; the wrapper
      and its embedded slider kept two separate values; `setPosition` never clamped; and
      **`orientation="v"` was read as horizontal**, so a drag took its value from the pointer's *x*
      across a 16px bar.
      **That last one reaches 8 skins** — Anexa, Enkera, Lobe and The_Nokia_5220 as well as this
      family — whose equalizers could never draw a curve. Verified by driving a −120…+120 sweep
      through `RENDER_EQ`: the thumbs now trace it.
      New probe: `WINAMP_MODERN_RENDER_GEOMETRY=<id>` — the resolved box of a named object and its
      children *including hidden ones*, with content/box/travel. The settings pages live in a closed
      tab, so no existing probe could see them at all.
      `swift test` 1096 pass (15 new across `WinampModernPhase59Tests`); 288-image corpus sweep — 284
      identical, 3 changed and inspected (Anexa's and Lobe's equalizers, cPro-Bento's widget manager,
      all now drawing their vertical sliders on the right axis), plus Anexa's nondeterministic
      `main-shade`.
      **The method lesson is the durable one and it is in `reference/harness.md` → *Ask for the live
      trace first, not fourth*:** five rebuild-and-retest rounds were spent reasoning about which hop
      might be broken, and one `CALL-TRACE` histogram named the cause immediately.


- [x] **BB20. The dump harness answers markup for every geometry read inside `onScriptLoaded`. Fixed 2026-08-24.**
      The harness now builds a renderer per container *before* `try runtime.start()` and installs a
      `resolvedGeometryRequested` that asks each in turn — the app's own wiring — and the dump loop
      reuses those same instances. Rule: `reference/harness.md` → *The harness answers geometry from
      before `start()`*. 288-image sweep taken across the change; the images that moved are recorded
      under BB22 below.
      <details><summary>original entry</summary>

      Found while measuring BB9, and **not Bento-only** — it affects every skin in the corpus.
      `WinampModernRenderDumpTests` installs `runtime.resolvedGeometryRequested` inside its
      per-container loop, long after `try runtime.start()`. Skins do nearly all of their layout in
      `onScriptLoaded`, so during it `getWidth`/`getLeft`/`getGuiW` fall back to `object.geometry` —
      `0` for a `w="0" relatw="1"` group. Big Bento's visualizer measured `getwidth() -> 0` headlessly
      against `346` in the app; both hide the analyzer, so **the harness agreed with the symptom for
      the wrong reason**. The app is the model: `wireContainerCallbacks` installs the closure *before*
      `scripts.start()` and consults every container's renderer. **Expect the 288-image sweep to
      change** — that is the point, so budget for inspecting the diff. Detail:
      [BENTO_VIS_HANDOFF.md](BENTO_VIS_HANDOFF.md) §3.8.
      </details>

- [x] **BB21. Bento's header `<vis>` analyzer is behind a splitter that cannot be dragged. Fixed
      2026-08-24, confirmed live.** The divider claimed a press only when nothing interactive sat under
      it, and this skin covers every pixel with `<layer id="player.resizer.disable" move="1"
      alpha="0">` plus four alpha-0 mousetraps on the seam — so the cursor promised a resize and every
      press dragged the window. `renderer.objectOverridingDivider(at:)` is the rule: on a splitter's
      own grab strip an **invisible** object (`alpha="0"`) and a bare **`move="1"`** window-drag
      surface do not outrank it; a button, a slider or anything carrying an action still does. Scoped
      to the grab rect, so cPro's tab strip crossing its seam is unaffected. The skin's own
      `mousetrap3`/`mousetrap4` are `alpha="255"` and sit above and below the strip, and keep their
      claim. Rule: `reference/rendering.md` → *What outranks a splitter on its own grab strip*.
      **This also unblocked the header analyzer** — `visualizer.maki` shows `main.vis.group` only
      above 730px of player width, which is this divider.
      <details><summary>original entry</summary>

      Separate from BB9's panes. Six `<vis>` boxes in `main.vis.group` are shown only when
      `visualizer.maki`'s `onResize` reports more than 730px of player width; that width is the
      `player.mainframe.big` divider, clamped to `minwidth="434"` at load. The divider cannot be
      grabbed: `mouseDown` claims a seam only when `renderer.object(at:) == nil`, and Bento covers
      every pixel with `<layer id="player.resizer.disable" … move="1" alpha="0">` plus four alpha-0
      mousetraps on the seam itself — so every press drags the window while the resize cursor promises
      otherwise. An unconfirmed patch keying the rule on *interactivity* is at
      `scratchpad/bb9-revert.patch`; **it was never verified on screen**, so re-derive rather than
      trust it. Also unestablished: whether Winamp starts Bento with a narrow player pane at all — if
      not, the defect is the divider's *position*, not its draggability.
      [BENTO_VIS_HANDOFF.md](BENTO_VIS_HANDOFF.md) §3.7.
      </details>

- [x] **BB22. The `.wal` window ran at a few frames a second. Fixed 2026-08-24, confirmed live
      ("it looks better").** Six independent costs, none of them the analyzer that was blamed. Four in
      the renderer, measured at `RENDER_TIME_SCALE=2` on `main/normal`: **238 → 37 ms/frame** —
      fully-transparent objects were composited rather than skipped (`player.resizer.disable` alone,
      a window-sized `alpha="0"` mousetrap, cost **42.8 ms/frame** and `focus.dummy` another 42.0);
      the prescale cache's per-entry cap (4 M px) was smaller than a window background at Retina
      (5.3 M) so the entries that matter missed it and were `.high`-resampled every frame
      (`grid#-` 60.5 → 7.0 ms); `drawTiled` blitted up to 8192 tiles per frame instead of one
      `draw(_:in:byTiling:)`; and `updateSpectrum` invalidated at the audio block rate (~75 Hz).
      Two more found by `sample`-ing the process, which is the durable method lesson — `RENDER_TIME`
      measures `renderer.draw` and nothing else, and neither of these was in it:
      `WasabiObjectGraph.objects(xmlID:)` scanned and sorted every object per call **on the playback
      tick** (~10% of the app's busy time in one lookup), and `layoutNodes()` had no cache at all
      while `resolvedGeometry` — every script `getWidth`/`getLeft` — goes through it.
      Rules: `reference/performance.md` → *Profile the process, don't reason about the frame* and
      *Four ways to pay full price for nothing*; `reference/harness.md` → *Profiling the running app*.
      `swift test` 1104 pass (7 new, `WinampModernPhase60Tests`); 288-image sweep 287 identical for
      the graph caches, and 12 images differing by **maxdelta = 1** for the tiling rewrite (one LSB,
      from a single native tiling pass rounding differently than N individually-rounded blits).
      **Still the biggest thing inside `draw`, and unfixed:** text — `drawText` was 339 of 1148 draw
      samples, with `font(identifier:size:traits:)` alone at 96.

- [x] **BB23. The play/pause button stuck in *paused*. Fixed 2026-08-24.** Reported as *"the 4 bento
      skins the play pause button gets stuck in paused if used"*. The transport is two overlapping
      buttons (`play.track` / `pause.track`, both `.null`-imaged) plus the `animation.play.pause`
      morph, and `animbutton.maki` swaps them at the end of each handler. Every handler aborted
      three calls earlier: `setAutoReplay` had no signature in the method table, and dispatch fails
      closed on a missing signature, so `play.show(); pause.hide()` never ran and `pause.track` — the
      one declared second — stayed on top for ever. One method (`setautoreplay`, arity 1, written to
      the same `autoreplay` attribute the markup carries) also un-aborts `animbutton_main.maki` (the
      display ring) and `notif_playtopause.maki`. Verified on all four variants headlessly:
      `RENDER_EVENTS=onpause` now leaves `play.track visible=1`, `onresume` puts `pause.track` back.
      `swift test` 732 pass. Skill: `skins/big-bento-modern.md` → BB23,
      `compatibility/maki-surface.md` → *Animated layers*, `reference/harness.md` → the blind-spot
      table (`RENDER_SCRIPTS`'s `failed=` is load-time only).

- [x] **BB24. The SUI tab icons were stretched vertically. Fixed 2026-08-24, confirmed live.**
      Reported as *"on the 4 bento skins, the icons (browser, library, settings, visualizations,
      playlist) on the vertical tab are vertically stretched"*. Not a renderer defect:
      `tabcontrol.maki` sizes each tab to `4 * label.y + label.getAutoHeight()`, and `getAutoHeight()`
      answered the label's **declared** `h="60"` rather than its font, so every tab came out
      `36 + 60 = 96` — the tab's own height fed back into its own sizing. The 258×58 icon is drawn to
      the tab, hence the 1.66× stretch, and the script's `y + h + 1` stacking drifted the strip 37px
      per tab. Two parts: `getAutoWidth`/`getAutoHeight` now measure before falling back to the
      declared `w`/`h` for `text`/`songticker` (a group still answers from its declared size), and
      `lineHeight(of:)` is `fontsize` — the pixel cell height Winamp hands GDI — rather than a
      CoreText line height, which answered 25 and left the tabs 61 tall and still creeping. Measured
      on all four variants: `RENDER_GEOMETRY=sui.tabs` prints `h=60` at `y=4,65,126,187,248,309`
      against `h=96` at `y=4,101,198,295,392,489` before. `swift test` 1184 pass; the Phase 53
      assertion that `getAutoHeight` prefers the declared height was the assumption this corrects, and
      is rewritten. Skill: `skins/big-bento-modern.md` → BB24, `reference/scripting.md` →
      *`getAutoWidth()` / `getAutoHeight()` measure the string*, `SKILL.md` routing table.
      **Corpus sweep not run** — the change reaches any skin whose scripts measure a text object, and
      the 37-skin before/after is the check that has not been taken.

### Tier 2 — the settings surfaces themselves

- [ ] **BB10. The gear (host **Skin Settings**) window renders two widget kinds, and hides some
      settings entirely.** Reported by the user as *"most items in the gear settings menu don't work
      or are blank."*
      `Windows/WinampModern/WinampModernSkinSettingsWindowController.swift` (208 lines) builds its
      list from `runtime.presentableSettings` and renders a checkbox when the current value is
      exactly `"0"` or `"1"` (`isToggle`, line 29) and otherwise a bare `NSTextField` (line 126).
      There is no enum, slider, range or colour widget, because `RegisteredSetting` carries no type
      metadata — only section, name and default. Separately, `presentableSettings` filters out every
      setting whose *current value* looks like a GUID (`namesAnItem`), which is right for Winamp's
      config-tree navigation nodes and also hides any legitimately GUID-valued option.
      Decide in this order: **(a)** does this window stay a *fallback* for options no skin control
      binds, once BB7 makes the skin's own nine pages work? It and `config.xml` read and write the
      same store, so BB7 may make it largely redundant for this family and the answer changes how
      much (b) is worth. **(b)** extend `RegisteredSetting` with type/range metadata so an enum is a
      popup and a bounded int is a slider. **(c)** revisit the GUID filter.
      Start by dumping what this skin actually registers: `WINAMP_MODERN_RENDER_SETTINGS=1`.

- [ ] **BB11. List accessors: `getItemLabel(i)`, `getItemFocused()`, `setSubItem()`.** All absent from
      the runtime. Called from `reader/main.m` (the skin's own news reader) and `playlistpro.m`.
      Scope which of those lists are actually reachable in our host before implementing any of it —
      the reader may not be.


### Tier 3 — real gaps, no reported symptom

- [ ] **BB13. `setClipboardText()`** — absent, so copy-title and copy-path from the skin's own menus
      are inert. Three call sites.
- [ ] **BB14. Animated layout and tab transitions, and easing beyond linear.** Our layout and tab
      switches are instant visibility swaps. Sprite `<AnimatedLayer>`, the
      `setTarget*`/`setTargetSpeed`/`gotoTarget`/`cancelTarget`/`onTargetReached` tween machine and
      timers are all implemented and are what Bento's own animations are built from, so **nothing in
      this family depends on this**. Filed so the absence is recorded rather than rediscovered.
- [ ] **BB15. `parser_*` (XmlDoc) and `shutdown()`** — inert, no measured demand in this family.

**Not open, and not a defect:**

- The Windows 10 edition's zero-byte `window/no_alb_art_shade.png` is the skin's own bug. It degrades
  to a warning and that one placeholder draws nothing, which is the correct outcome.
- The wide-window pane split (B38.5). `from="left"` anchors the divider to the left edge and the right
  pane absorbs the extra width — see B38 below.

---

## Closed

### B35 — The four Big Bento Modern variants fail to load

Plan: `~/.claude/plans/contineu-purring-dove.md`. Three independent root causes: `@SKINSPATH@` is an
undefined path variable (hard `.unresolvedPathVariable`); the two *Light* editions are overlays that
pull six of their eight includes out of the **base** skin's directory through that token; and the
Windows 10 edition ships a zero-byte `window/no_alb_art_shade.png` whose `.invalidImageResource`
fails the entire skin.

- [x] **B35.1 `@SKINSPATH@` → `/Skins`** — define it in `WalVirtualFileSystem.init()` alongside
      `WINAMPPATH` / `DEFAULTSKINPATH` (it is a fixed collection root, not skin-derived).
- [x] **B35.2 Lazy sibling mounts** — `siblingMountResolver` closure + `mountSiblingIfNeeded(for:)`
      on the VFS, consulted **only** when no mount already owns the path, from
      `canonicalExistingPath` (retry once after a mount) and from `expand` (before filtering
      `allLogicalPaths()`). Memoize misses in `failedSiblingNames`; cap at 4 mounts per load.
- [x] **B35.3 Loader supplies the resolver** — `WinampModernSkinLoader.load(from:additionalMounts:)`
      searches the archive's own directory, then `WinampModernSkinImporter.defaultDestinationDirectory()`,
      matching `safeMountName(basename)` case-insensitively; opens each hit with the same
      `archiveLimits`.
- [x] **B35.4 Name the missing base** — new `WalDiagnosticCode.missingRequiredMount`, thrown with
      "This skin requires the skin '<name>' to be installed." so it bypasses the two
      `.resourceMissing` tolerance blocks (`WalXML` include warning, `resolveSkinResource`'s
      `@SKINPATH@` fallback). Categorize as `resources` in `WinampModernCompatibilityReport`.
- [x] **B35.5 Undecodable images degrade** — in `registerResources`, tolerate `.invalidImageResource`
      exactly like `.resourceMissing` for `bitmap`/`cursor`/`bitmapfont`: register without
      `logicalFile` and warn. `.imageDimensionsExceeded` stays fatal.
- [x] **B35.6 Tests** — Phase 2: `@SKINSPATH@` resolves; own-name self-reference needs no resolver;
      sibling `<include>` expands from a `.wal` next door; absent sibling throws
      `.missingRequiredMount` naming it; 4-mount cap; a repeated miss does not re-scan. Phase 7:
      zero-byte bitmap degrades to a warning (tighten
      `testMalformedImageResourceDegradesInsteadOfCrashing`); oversized still throws.
- [x] **B35.7 Verify** — `swift test`, goldens, render-dump per variant with
      `WINAMP_MODERN_RENDER_BITMAPS=1`, then the corpus sweep diffed **by pixels** against a
      pre-change run.
- [x] **B35.8 Land the findings** — `reference/loading.md` (VFS mounts table + *Sibling skin mounts*),
      `compatibility.md`, `skins.md` + new `skins/big-bento-modern.md`, `CHANGELOG`.
- [x] **B35.9 Live QA, 2026-08-23** — done by the user. The skins come up in the running app; the
      window is large because the layout declares `w="1536" h="878"` and the UI was at 150% scale,
      not a defect. Found live: the SUI menu bar draws its five items on top of each other → **B36**.

### B36 — The `<Menu>` XUI does not self-size — **wrong diagnosis; closed 2026-08-23**

The measurement was right and the conclusion was not. All five `Menu` objects did report
`frame=(190, 6, 0, 32)`, but not because the widget fails to self-size: `player.mainmenu` carries the
comment *"Note: Most of the items in this group are placed by script"*, and `mainmenu.maki` measures
each label with `getAutoWidth()` and lays the five out left to right. That script was aborting on
`getSettingsPath` before it reached the layout code. With the method implemented the five place
themselves at x = 190 / 231 / 277 / 350 / 400 with no widget change at all.

- [x] **B36.1/B36.2** Not implemented, and deliberately so — adding label-measuring and `prev`-chain
      placement to the `Menu` widget would have fought a working script. If a skin ever turns up that
      declares `<Menu prev=…>` with no placement script, that is when to build it.
- [x] **B36.3** Corpus check done: `<Menu>` with `prev`/`next` and no geometry appears only in this
      family. Pixel-diffed render sweep clean apart from the intended changes (see B37).

Follow-up, **not** in this change: `@HAVE_LIBRARY@` — carried to **BB5** above.

### B37 — Big Bento Modern renders wrong in the app (live, 2026-08-23) — **done 2026-08-23**

B35 made all four variants **load**; this was the list of what was wrong once they were on screen.
Five separately reported symptoms, and **one cause behind four of them**: 23 of the skin's
`onScriptLoaded` handlers aborted on `System.getSettingsPath()` (the skin probes
`<settings>/WACUP_Tools/koopa.ini` to sniff for WACUP near the top of nearly every script), so the
layout work in the rest of each handler never ran. `RENDER_SCRIPTS=1`'s `failed=` column says this in
one line per script and should have been the first probe, not `RENDER_PROBE`.

- [x] **B37.1 The menu bar items overlap** — fixed by `getSettingsPath`; see **B36**, whose proposed
      widget rule was the wrong fix.
- [x] **B37.2 The song ticker overruns its box** — `InfoDisplay` is clipped to its own 237px box, and
      always was (`drawText` does `context.clip(to: frame)`). What the screenshot showed was the box
      *empty of a time readout beside it*, plus the title drawn full-size across a display panel that
      had nothing else in it. With B37.3 fixed the panel reads `1:13` / `1:13 / 4:05` / title, and the
      title stops at the panel edge. No renderer change was needed.
- [x] **B37.3 The two display panels left of the ticker are empty** — the `display=` binding table
      knew only `time` / `songname` / `songinfo` / `PE_Info`. This skin asks for `TIMEELAPSED`,
      `SONGLENGTH`, `SONGTITLE` and `SONGSAMPLERATE`, which fell through to the literal `text=`.
      Added those plus `songartist` / `songalbum` / `songbitrate` / `artistname` (the whole corpus
      census) and `timerhours`. Also fixed, unreported: Ebonite_2_1 and Enkera's KBPS/KHZ readouts
      and mmd3's playlist-shade song length, all blank for the same reason.
- [x] **B37.4 The album-art panel is a solid black square** — the cover script aborted on
      `getAutoHeight` (masked behind `getSettingsPath`); it now draws its `no_alb_art` placeholder.
- **B37.5 The embedded library is unstyled** — the one item of B37 that did not close. It is
  **BB2** in *Open* above; do not track it here.

Two further fixes fell out, neither on the original list:

- **`offsetx`/`offsety` on a `<text>` were ignored.** They shift the string inside its own box without
  moving the box, and Big Bento's SUI tab captions are `offsetx="35"` — which is what puts them clear
  of the icon in icons+text mode and *outside the clip* in the 40px icons-only mode. Unblocking the
  tab script made every caption draw over its own icon until this was honoured. Six declarations in
  the whole corpus, all in this family.
- **The shade titlebar drew "WACUP" over "WINAMP".** Same `getSettingsPath` cause: the probe now
  answers "not WACUP" and the logo stays hidden.

Verified: `swift test` (1022, 0 failures, 13 new in `WinampModernPhase53Tests`) and the 30-skin,
289-image render sweep pixel-diffed against a pre-change build — 19 images changed, all four Bento
variants (intended), Ebonite_2_1 / Enkera / mmd3 (the readout fixes above, inspected), and Anexa's
`main-shade`, which differs between two runs of the *same* binary. Live QA on the four variants is
still outstanding.

**Follow-up, not in this change: `instantiate`** — carried to **BB1** above.

### B38 — Big Bento Modern, live defects found in QA (2026-08-23) — **closed**

Found by the user driving the app after B36/B37 landed. Neither of the first two reproduces in the
render harness, so both were diagnosed from the app's own `#if DEBUG` logging.

- [x] **B38.1 The window goes undraggable after shade → normal.** `shouldDragWindow(from:)` honoured
      `move="1"` on `<group>` only — 421 of the **981** declarations across the 30 installed skins,
      on 14 element types (`rect` 233, `layer` 151, `text` 66, `grid` 36, `grouplist` 34). Big
      Bento's titlebar is `<grid … move="1">` over `<rect id="vic_mover" move="1" fitparent="1">`, so
      the window could only be dragged wherever a bare background happened to be topmost, and a trip
      through shade changed which object that was. Now honoured on any non-control element; controls
      are excluded (17 declarations) because a button that both acts and drags eats its own click.
      Confirmed fixed live.
- [x] **B38.2 The playlist and the media library draw on top of each other at launch.** Two causes,
      one behind the other:
      1. `openHolders` — the `autoopen` fallback — forces a holder's hidden ancestors visible without
         knowing the other six tab pages exist (`sui.components` holds seven `<group visible="0">`).
         A restored session with both a playlist and a library window revealed both. It now reverts
         what it previously forced.
      2. That alone was not enough, and the log said why: **the skin's script opens its tab on its
         own timer, ~0.6s after our reveals.** All four launch reveals legitimately fell through to
         the fallback (the tab genuinely was not open *yet*), we forced the library page, and then
         `suicore.maki` opened the playlist it had decided on all along — with no idea a second page
         was open. So exclusivity is re-checked on every layout pass and always resolves the same
         way: **the page we forced yields to the page the skin opened.** Confirmed fixed live.
- [x] **B38.3 `getTextWidth` unsupported.** It aborted `onTextChanged` — the one handler that runs on
      every track change. (Distinct from `getAutoWidth`: how wide the string *draws*, not how wide
      the object wants to be. Skins compare the two to decide whether a caption fits.) **The rest of
      it**, found when B38.4 let the Multi Content View run: the file-info panel's `onSetVisible` —
      the handler that fills every line of it — then aborted on **`getDecoderName`**, and behind that
      on `getPath`, `getIdealVideoWidth` and `removePath` in turn. All four implemented; the panel
      now fills. `getDecoderName` answers the codec NullPlayer is decoding, `getPath`/`removePath`
      are pure string splits of a path the host already handed out, and the video pair answer 0 for
      the same reason `hasVideoSupport` is false. `getPlayItemMetaDataString("filename")` — which
      those splits are called on — now answers the playing item's location.
      *The harness could not see any of this*: `onTextChanged` is polled by the window controller, so
      `WINAMP_MODERN_RENDER_TEXT=1` was added to drive it (with `RENDER_PLAYLIST`, since both of this
      skin's bound text objects are `PE_Info` feeds).
- [x] **B38.4 The visualization box draws black over the album art.** The skin picks between the two
      panes from config attributes it registers itself, and at the defaults hides
      `info.component.vis`. That branch is in `mcvcore`'s **first** `System.onScriptLoaded()` — and
      the script declares a **second** one, so the "keep the last binding per (object, event)" rule
      introduced for Defix in Phase 42 shadowed it and *none* of `mcvcore` ran. The rule now drops
      only a binding whose **body repeats** an earlier one for the same pair (compared with jump targets relative to the
      entry point and variable slots renumbered, because the compiler gives each copy its own
      temporaries); two different bodies are two real handlers and both run. Defix's duplicated
      `ConfBT2.onLeftClick` still runs once, so its toggle does not flash.
      Three more things came back with it in the sweep, all previously recorded as fixed and all in
      fact still broken at HEAD: the Multi Content View's info display is laid out instead of sitting
      at its markup `x=80 w=0`, the full-width `info.component.coverflow` leaves the scene, and shade
      mode stops drawing **WACUP** over **WINAMP**.
- [x] **B38.5 The playlist-info panel takes half the top bar — not a defect.** `from="left"` anchors
      the divider to the left edge, so the right pane absorbs the extra width. That is what Wasabi's
      `from` means, what the skin's own `maxwidth="-300"` ("always leave 300 for the other pane") is
      written for, and what its script asks for with `setPosition(434)` against `minwidth="434"`. The
      window is wide because the layout declares `w="1536" h="878"` as its **default**. cPro-Bento's
      `centro.mainframe` is the same attribute the other way round (`from="right" width="200"`, its
      playlist column fixed and the left side growing), which confirms the reading. The huge song
      title is the skin's `fontsize="48"` in a 237px `InfoDisplay`; nothing in the corpus writes
      `fontsize` except `playlistpro.maki`, so no script is meant to shrink it.

Verified: `swift test` 1028 pass; 300-image corpus sweep across all 36 installed skins pixel-diffed
against a build of `HEAD`. 281 identical, 19 changed: the four Bento variants' `main-normal`,
`main-shade` and `searchresults-normal` (all four inspected — the Multi Content View fills, the
WACUP logo goes, and `searchresults` draws the 0 nodes the skin index says it should), Ebonite_2_1 /
Enkera / mmd3 (B38.3's readouts, already inspected in the previous pass) and Anexa's `main-shade`,
which differs between two runs of the same binary. B38.1 and B38.2 confirmed live by the user.
