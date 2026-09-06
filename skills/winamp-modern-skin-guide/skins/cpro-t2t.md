## cPro T2T (XPS) (`cPro_T2T-by-MAC.wal` + ClassicPro engine)

*Per-skin status. Index: [skins.md](../skins.md) · engine-wide surface: [compatibility.md](../compatibility.md) · how a section gets written: `/wal-skin-report <skin.wal>`.*

- **File:** `cPro_T2T-by-MAC.wal` · 686183 B · SHA-256 `e28a9e423f0389e6…`
- **Measured:** 2026-08-31 (B77; re-measured same day against the author's promo sheet) · engine: ClassicPro, family `one`
- **Grade: C (confidence: high)** — *downgraded from B.* B77 measured the skin at rest and against

**Known outstanding:**

- 15 bitmap id(s) it references do not resolve, leaving a visible gap: `custom.repeat.0`, `custom.shuffle.0`, `custom.winamp`, `player.o.bottom`, `player.o.bottomleft`, `player.o.bottomright`…
- unimplemented MAKI: `enumitem` ×4
- 12 object(s) a script hooks the mouse on that markup hit-testing rejects — they may not respond to a click
- 1 error-severity load finding(s)

  the engine, and graded it on that. The distributed archive folder ships
  `cPro-T2T-by_MAC-PROMO.jpg` (1185x853) **outside the `.wal`** — a full annotated reference sheet —
  and against it three declared user-facing features are dead. Every surface still routes and draws;
  the faults are all engine-level, so the other cPro skins are very likely to share them.

**Read [cpro-bento.md](cpro-bento.md) first.** These four skins are almost content-free — `skin.xml`
is a `<skininfo>` block plus `<include …/Plugins/classicPro/engine/load.xml"/>` — so everything
structural is the shared engine's and is documented there. This file records only what *differs*.

**Measured status** — `WINAMP_MODERN_RENDER_DUMP`, 2026-08-31:

```
arrangement=singleWindowSUI   catalog: playlist/equalizer/library/video all embedded
containers: main (player) · notifier · browserpro · widgets.manager
main/normal        500x500   174 nodes   min 495x324   declared 317x168   max 1920x1080
widgets.manager    313x400    52 nodes   min 313x400   declared 100x400
bitmaps main/normal: missing=beatvis.overlay custom.repeat.0 custom.shuffle.0 custom.winamp player.o.*
```

### What differs from cPro-Bento

- Ships a `custom-element-overide.xml` that re-cuts the **system-menu** button (`menu.1/2/3` at
  x=108) and the Winamp bolt — but **not** `window.titlebar.menu.*`, which is a different id. The
  presence of one override is not evidence the other was cut; check the ids.
- Its artwork lives under a `cPro_T2T-by-MAC/` folder inside the archive rather than at the root.
- The `custom.*.0` misses are the rest frames of its own ghost overlays and are **not** a defect —
  same as cPro-Bento's, see that file.

### The trap this skin sets

**Its titlebar menu bar is deliberately absent.** `buttons.png` carries the ClassicPro template's
`(255,0,128)` filler at the menu row (y=87, x=0/11/22) instead of cut artwork, and the engine's own
`mainmenu.maki` detects exactly that and hides the bar. That is correct behaviour, not a missing
feature — do not "fix" it by drawing the entries. cPro-Bento cut its slices and keeps its bar.
See [../reference/classicpro.md](../reference/classicpro.md).

Before B77 the bar drew as five magenta boxes, because `Map.loadMap` sampled the whole file rather
than the bitmap's declared sub-rect and the engine's self-check never fired. That is the fix, and the
absence of the bar is the intended outcome.

### Working

Everything cPro-Bento does, on the same engine: the SUI tab strip, the drawer and its page menu, the
embedded playlist/EQ/library/video, colour themes, and the Widgets Manager — which lists **BrowserPro
1.00** and **Now Playing 1.01** and opens at a sane 313x400 as of B77.

The **equalizer is a drawer page, not a window** — the engine declares no `<container id="EQ">`.
Reach it with the `^` chevron at the right of the tab strip (`tog.drawer`), or `alt+g`; the
drawer's `▤` button switches page. Its open/closed state is a **per-skin persisted `cfgattrib`**,
so a profile that has never opened it sees no equalizer anywhere — which is what "the equalizer is
hidden" turned out to be.

### The three faults the promo sheet exposed

All three are **engine-level capability gaps**, not this skin's artwork. Full evidence in the
report (§5); the short form:

1. **[FIXED B88] `<images>` was not implemented at all — the volume bar never filled.** The fill is a filmstrip
   picked by value, not a slider fill: `<images id="volume.images" source="volume"
   images="volume.bg2" imagesspacing="16"/>` over an 18-frame `volume_ani.png`
   (`engine/one/xml/player-normal.xml:98`). Nothing in `Sources/` reads the `images` element type,
   `images=`, `imagesspacing`, or a `source=` binding; the node lays out and draws nothing
   (`PROBE images#volume.images … bitmap=-`). The *readout* ("Volume: 39%") is fine — do not
   confuse the two.
2. **[WITHDRAWN — was a harness artifact] The tab strip is fine.** This said the fit pass never
   runs and four of seven tabs were unreachable. In the **app** all seven are present and abbreviated
   (LIB PLE VID VIS BRO BPR NOW). The pass hangs off `onResize`, which the app seeds and the render
   dump does not — `RENDER_EVENTS=onresize` reproduces the app. `reference/harness.md` already says
   "**`onresize` first** for any ClassicPro skin". One real, smaller thing survives: **B87**, the
   3-letter labels lose the right edge of their last glyph (`LIB`→`LIE`). **B89 is fixed
   (2026-08-31)**: the window floored at **500x290** (measured live, not the dump's 495x324) against
   a declared 317x168, so the compact classic-player form the promo sheet shows was unreachable. The
   oversized-tabs theory for that floor was **dead** — the tabs are 32px in the app and the floor was
   unchanged — and the live culprit was `group#beatvis`, which the protective minimum counted even
   though its parent clips it. All five cPro skins now reach **317x174**; see
   `compatibility/limits-and-policy.md` → *The protective minimum*. Tabs lay out at full label width (~567px inside a 234px
   `Cpro:Tabs`): tab 4 is clipped to 6px (`clip=(234,104,6,29)`) and BPR/BRO/NOW are off-strip.
   The abbreviating pass works — any resize proves it, turning the labels into the promo's
   `LIB PLE VIS VID BPR BRO NOW` and each tab into `w=32` — but it hangs off `onresize`, which
   initial layout never fires. `RENDER_SETTLE` does **not** cover this: settling pumps timers, not
   resizes.
   **The `MINIMUM` line measures the dump's scene, not the app's.** It named the tab objects
   (`MINIMUM main/normal below=494: grid#cpro.tab.grid text#l text#r togglebutton#cpro.tab.button`),
   giving 495x324, because the dump had not fired `onresize`. In the running app the culprit was
   `group#beatvis` and the floor was 500x290. Two instruments, two scenes — measure the app (B89).
3. **[FIXED B86] `parser_addCallback` path matching was too strict — the skin's 7 custom beat-vis
   animations never loaded.** It was **two** faults: the matcher, *and* `@SKINPATH@` carrying no
   trailing separator, so `getParam() + "ClassicPro.xml"` never resolved and every `myDoc.exists()`
   guard took its false branch. Fixing only the matcher changed nothing visible. `ClassicPro.xml` declares `<customvis name="T2T-01"/>` … `T2T-07`, backed by
   `beat_right2…7.png`. `beat.m` reads them with `parser_addCallback("BeatVis/*")` and
   `("ClassicPro/Visualization/BeatVis*")`; the real path is the **four**-component
   `ClassicPro/Visualization/BeatVis/customvis`, and our matcher
   (`WinampModernScriptRuntime.swift:4600`) requires an exact component count and treats `*` as
   exactly one whole component. Both patterns miss — one is a relative/suffix pattern, the other a
   trailing *prefix* wildcard inside a component. So `cusbeat_names` is empty, `customvis=false`,
   `setCustomVis()` never runs, and the right-click menu builds as `CLICK menu: Show Beat vis#1` —
   one item where the promo's "7 BEATVIS" panel wants eight.

   **Not the `enumitem` finding.** `List.enumItem` *is* implemented (`:4382`) and `parserStart`
   (`:4554`) hands the callback two populated lists. The diagnostics' `enumitem ×2` comes from
   `widgets-manager.xml` on a different receiver and is a separate, unchased question.

### The trap the *reference* sets

`screenshot.png` inside the `.wal` is a 178x75 **logo**, not a UI shot — which is why B77 recorded
that it had no reference and graded on the engine alone. The real reference ships beside the `.wal`
in the distributed folder (`cPro-T2T-by_MAC-PROMO.jpg`). Look outside the archive before concluding
a skin is unfalsifiable.

### Knowingly left

- The magenta filler above — per-skin artwork, won't-do.
- `WA5:Prefs` (Winamp's preferences dialog at a page number) — no host equivalent; both
  declarations are `dblclickaction` on status text, so the visible cost is low. Of the 24 distinct
  markup actions in `main/normal`, this is the *only* one reaching the action switch's `default:`.
- Whether the beat vis animates under playback is **not measured**: it is `autoplay=0` driven by a
  10ms timer off `getLeftVuMeter`/`getRightVuMeter` (both implemented), and every headless render
  shows the promo logo instead because `refreshView()` does that whenever the transport is stopped.
  Needs a live playing pass.
- **B78** the embedded playlist surface may overflow a small holder; **B82** a widget brought up
  mid-session is not told the current track, so Now Playing's three text lines stay blank until the
  next track change.
