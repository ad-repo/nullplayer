## cPro Insomnis v2 (`cPro_Insomnis_v2_by_zrco.wal` + ClassicPro engine)

*Per-skin status. Index: [skins.md](../skins.md) · engine-wide surface: [compatibility.md](../compatibility.md) · how a section gets written: `/wal-skin-report <skin.wal>`.*

- **File:** `cPro_Insomnis_v2_by_zrco.wal` · 157315 B · SHA-256 `0202fe99e823c810…`
- **Measured:** 2026-08-31 (B77) · engine: ClassicPro, family `one`
- **Grade: B (confidence: medium)** — every surface routes and draws; what is left is this skin's own uncut artwork and two engine-wide backlog items, not anything specific to it.

**Read [cpro-bento.md](cpro-bento.md) first.** These four skins are almost content-free — `skin.xml`
is a `<skininfo>` block plus `<include …/Plugins/classicPro/engine/load.xml"/>` — so everything
structural is the shared engine's and is documented there. This file records only what *differs*.

**Measured status** — `WINAMP_MODERN_RENDER_DUMP`, 2026-08-31:

```
arrangement=singleWindowSUI   catalog: playlist/equalizer/library/video all embedded
containers: main (player) · notifier · browserpro · widgets.manager
main/normal        500x500   169 nodes   min 495x324   declared 317x168   max 1920x1080
widgets.manager    313x400    52 nodes   min 313x400   declared 100x400
bitmaps main/normal: missing=beatvis.overlay
```

### What differs from cPro-Bento

- The cleanest of the four: one missing bitmap in the whole player.
- Ships colour themes, so the drawer's *Color Themes* page is live.
- 14,301 pixels of its 332x198 `buttons.png` are template filler.

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

### Knowingly left

- The magenta filler above — per-skin artwork, won't-do.
- **B78** the embedded playlist surface may overflow a small holder; **B82** a widget brought up
  mid-session is not told the current track, so Now Playing's three text lines stay blank until the
  next track change; **B83** `isVisible()` answers true for the closed Widgets Manager, so its menu
  row shows ticked.
