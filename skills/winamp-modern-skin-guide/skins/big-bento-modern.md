# Big Bento Modern (all four variants)

**Archives:** `Big Bento Modern.wal`, `Big Bento Modern Light.wal`,
`Big Bento Modern Windows 10 edition.wal`, `Big Bento Modern Windows 10 edition Light.wal`
**Author:** Victhor, over Taber Buhl's work and the original Wasabi development
**Arrangement:** `singleWindowSUI` — playlist, library and video are all embedded tabs
**Layouts:** `main/normal` 814×530 declared, 1186×597 minimum, capped at the 1920×1080 screen box;
`main/shade` 565×42. Plus `searchresults`, `Hsearchresults`, `browserpro`, `main.aerosnap`,
`query.pathurl`, `welcomessage` and `notifier` containers.

## Status

| Feature | Status | Notes |
|---------|--------|-------|
| Loading | **Fixed (B35)** | All four failed outright before B35 — see the three root causes below |
| Rendering | **Fixed (B36/B37)** | 80–82 bitmaps resolve in `main/normal`, 19–20 in `main/shade`; 38 scenes across the four |
| Menu bar | **Fixed (B36)** | File/Play/Options/View/Help are placed by `mainmenu.maki`, not by a widget rule |
| Display readouts | **Fixed (B37)** | `TIMEELAPSED` / `SONGLENGTH` / `SONGTITLE` / `SONGSAMPLERATE` are bound |
| SUI tab strip | **Fixed (B37)** | `offsetx` on the captions is honoured, so icons-only mode clips them away |
| Overlay (`Light`) palette | **Works** | The Light editions render in their own light palette against the base skin's artwork |
| Album-art panel (W10 edition) | **Degrades** | Its `window/no_alb_art_shade.png` is zero bytes; that one placeholder draws nothing |
| Config pages + EQ tab | **Fixed (BB7)** | `GroupList.instantiate` builds them; `getApplicationPath` was the domino behind it |
| Seek bar (base editions) | **Fixed (BB12)** | `hold="none"` was painting an inert-component slab over it. Confirmed live |
| Seeking | **Fixed (BB16)** | `seek.maki` hides its own only seek slider on mouse-up; the stranded-control rule undoes it |
| Settings-page scrolling | **Fixed (BB19)** | Seven stacked faults — see below. Confirmed live |
| Seek bar (W10 editions) | **Blank** | The skin's own `waveseeker.rounder.bg` covers it; cause unmeasured |
| Scripts | **Partial** | No handler in the skin aborts any more, and the level is `degraded` rather than `unsupported` |

## The family is two skins and two overlays

`Big Bento Modern` and `Big Bento Modern Windows 10 edition` are complete skins (273 files each).
The two `Light` editions are **overlays**: 138 files, and 6 of the 8 includes in their `skin.xml`
come out of the base archive by name —

```xml
<script  file="@SKINSPATH@\Big Bento Modern\scripts\loadattribs.maki" param="bbmlight"/>
<include file="@SKINSPATH@\Big Bento Modern Light\xml\color-presets.xml"/>   <!-- its own -->
<include file="@SKINSPATH@\Big Bento Modern Light\xml\system-colors.xml"/>   <!-- its own -->
<include file="@SKINSPATH@\Big Bento Modern\xml\system-elements.xml"/>       <!-- the base's -->
… standardframe.xml, window-overrides.xml, player.xml, notifier.xml, about.xml
```

so **the base must be installed, under its own name**, or the Light edition cannot load. That is
what `missingRequiredMount` says, by name. `@SKINSPATH@` usage: base 159, W10 165, each Light 48.

## Why all four failed before B35

1. **`@SKINSPATH@` was undefined** — a hard `unresolvedPathVariable` on the first include
   (`xml/player-normal.xml` / `xml/player.xml`, or `skin.xml:32-33` for the overlays). It is the
   skins *collection* root; every loaded skin is mounted at `/Skins/<name>`, so it is `/Skins`.
2. **The overlays reach into a sibling archive**, which the VFS had no way to mount. It now does,
   lazily and bounded — `reference/loading.md` → *Sibling skin mounts*.
3. **The Windows 10 edition ships a zero-byte `window/no_alb_art_shade.png`**, and one undecodable
   PNG failed the whole skin. An undecodable image now degrades to a warning.

Three independent causes with one symptom: *this skin does not load at all*. Fixing any one of them
alone would have left two of the four still dead.

## BB8 — the 77-theme colour picker

The Color Themes config page lists all 77 of the skin's `<gammaset>`s as buttons; each reads its own
label and runs `ColorMgr.getGammaSet(label).apply()`. None of `ColorMgr`, `getGammaSet` or `apply`
existed, so all 77 handlers aborted and the page did nothing. Confirmed live 2026-08-24.

Two facts worth keeping:

- **`ColorMgr` is a second system-flagged global beside `System`**, with its own class GUID, and it is
  bound by class the way `PlEdit` is. The mechanics — and the four ways to get a class binding wrong —
  are in `reference/scripting.md` → *Binding a host singleton by class GUID*.
- **This is not Bento-only.** Ebonite_2_1 reaches the theme catalog through `ColorMgr` too, which is
  why the surface fact lives in `compatibility/maki-surface.md` rather than here. Whether Ebonite's
  own picker now works is **unmeasured**.

## BB12 — the seek bar was a solid black bar

`wdh.waveseeker` is a `<windowholder … autoopen="0" hold="none"/>` the skin reserves for WACUP's
integrated Waveform Seeker, and it sits directly on top of the seek bar's grid and progress fill.
`hold="none"` was read as an *unknown component*, which is the `.other` branch — an opaque fill of
the palette's content colour across the holder's whole rect. `RENDER_PROBE=main/normal` named it in
one line, `HOLDERS main/normal: other@wdh.waveseeker(16, 123, 414, 34)`, against a black slab
measured at exactly that rect. The rule is in `reference/components.md`; the corpus scan says this
holder is the only `hold="none"` in the 36 installed skins.

Making the bar visible immediately exposed **BB16**: one press-release on it runs
`seeker.ghost.hide()` from `seek.maki`'s `onLeftButtonUp`, whose `onSetVisible` mirror then hides
`progressbar` and `player.seek.bg` too — and with the slider invisible nothing over the bar is
hit-testable, so seeking stopped working until a track change re-showed it. That defect is **older
than this fix** (it reproduces at `HEAD`); the slab was hiding the bar in both states. Fixed by the
stranded-control rule in `reference/scripting.md` → *A layout must not be left with no way to seek*.

**Do not "fix" the duplicate `findObject` by reading it as a skin bug and special-casing this
family.** Defix Hi-END runs the identical script and is fine; the difference is that Big Bento
declares its fallback `<Slider id="seeker">` as `visible="0" ghost="1"` while Defix leaves its
visible. The rule keys on that — whether the layout still has a visible carrier for the action.

Two things to know before re-measuring this area:

- **The header renders correctly headlessly**, and the titlebar art really is a flat four-colour
  dark gradient — the hamburger, the bolt, the WINAMP logo and all five menu items draw and are
  placed. Whatever the live report is about, it is not a missing bitmap in the dump. BB4's rule
  applies: measure it in the running app.
- **The Windows 10 editions' seek bar is still blank, and for a different reason.** They ship
  `<layer id="waveseeker.rounder.bg" image="songticker.background.center2" … visible="1"/>`
  (the base ships the same layer `visible="0"`), an opaque wash over the whole bar. `seek.maki` —
  `owner=group#player.layout`, the handler set `onenterarea,onleavearea,onleftbuttondown,`
  `onleftbuttonup,onscriptloaded,onsetfinalposition,onsetposition,onsetvisible` — runs its
  `onScriptLoaded` **clean** (`failed=-`) and does not hide it. Cause unmeasured; do not guess one.
  This is why the fix above changed only the two base variants' images in the corpus sweep.

## BB19 — the settings pages could not be scrolled

Seven independent faults, stacked, each hiding the next. Recorded in full because the *shape* is the
lesson: five of them were found and fixed one at a time, each looking like "the" fix, and the page
stayed dead until the last one landed.

| # | Fault | Where the rule now lives |
|---|---|---|
| 1 | The wheel was never dispatched to any skin | `reference/scripting.md` → *The mouse wheel is a layout event* |
| 2 | `scrollToPercent` was an accepted no-op | `reference/scripting.md` → *Scrolling* |
| 3 | Value events did not cross the `embed_xui` seam | `reference/scripting.md` → *`embed_xui`* |
| 4 | The wrapper's `low`/`high` never reached the embedded slider (so it ran 0…255) | same |
| 5 | `setPosition` did not clamp, so the up button walked past `high` for ever | same |
| 6 | **`orientation="v"` was read as horizontal** — the drag took its value from the pointer's *x* across a 16px bar | `reference/rendering.md` → *A skin spells the axis two ways* |
| 7 | The wrapper and its embedded slider kept **two** values, so the page read `0` whatever the bar did | `reference/scripting.md` → *`embed_xui`* |

Fault 6 is the one that made the bar undraggable, and it reaches **8 skins** — Anexa, Enkera, Lobe
and The_Nokia_5220 as well. Their equalizers could never draw a curve; ten band sliders all slid
sideways inside their own columns.

Two things to know before touching this area again:

- **The pages are only scrollable at small window sizes.** Each carries a `scrollbars.param` text
  (400, 650, 1980 …) that the script compares against the available height, showing its scrollbar
  only when the page needs one. At 1536×878 most pages fit and `travel` is genuinely `0`; use
  `WINAMP_MODERN_RENDER_GEOMETRY=grplst` with `RENDER_SIZE` to see a real one.
- **`getPosition()` on `vscroll` is the number everything hangs off.** The page computes
  `scrollToPercent(99 - position)`, so `position = 0` means *scroll to the bottom* — which is why a
  slider that starts un-set opens every page at its own end.

## Traps

- **There are *three* `winamp.albumart*` objects, and only one pair is the duplicate.** The Multi
  Content View holds the real cover plus an oversized dimmed backdrop behind the panel
  (`info.component.albumbg`, `xml/player-normal-mcv.xml:920`, `relatw="2" relath="2" alpha="100"`) —
  that pair was B42. The third, `winamp.albumart2` in `info.component.cover2`, is the **SUI playlist
  tab's** cover and is entirely legitimate. Do not read it as a fourth copy.

- **`@SKINPATH@` and `@SKINSPATH@` mean different things here, and the skin uses both on purpose.**
  Base XML that an overlay is meant to *override* is pulled with `@SKINPATH@` — the **loaded** skin's
  mount — so `player-normal-sui.xml`'s `<include file="@SKINPATH@\xml\config.xml">` picks up the
  Light edition's `config.xml`, not the base's. Shared XML is pulled with
  `@SKINSPATH@\Big Bento Modern\…`, an absolute name. Reading either as the other inverts which
  edition's markup wins.
- **The base's 159 `@SKINSPATH@\Big Bento Modern\…` references are *self*-references.** They resolve
  through the mount the skin already has and must never reach the sibling resolver.
- **Bitmap overrides do not currently win** (measured 2026-08-23, follow-up filed). The Light
  editions ship light versions of the *same* `window/*.png` the base declares (`frames.png`,
  `equalizer.png`, `no_alb_art_*.png`, 30-odd files), but a `<bitmap file="window/frames.png">`
  declared in base XML resolves relative to that XML first, so it loads the **base's** artwork; only
  the `@SKINPATH@` fallback would reach the overlay's copy. The Light editions still read as light
  because their palette comes from `color-presets.xml` / `system-colors.xml` and the gamma model.
  Do not "fix" this by flipping `resolveSkinResource`'s order without a full corpus sweep — the
  relative-first order exists for authored subfolders.
- **The compatibility level is about MAKI, not loading.** Until BB7 the level read `unsupported`
  purely because `instantiate` was recorded as an error; the skin loaded and drew regardless. It is
  `degraded` now, on warnings alone.
- **`searchresults/normal` draws 0 nodes, and that is correct.** Before B37 it painted the author's
  placeholder banner ("Results found: 22 items") because `playlistpro.maki` aborted before it could
  hide the panel. The container is `default_visible="0"` and only appears on a playlist search.
- `main/normal`'s missing-bitmap list is mostly deliberate placeholder ids (`none`, `null`,
  `player.button.pause.normal.null`, `window.background.hidden`, `show.sui.tabs.invisible`) — the
  skin's own way of drawing nothing. They are not a defect.

## B36/B37 — why five separate symptoms had one cause

Five things were reported wrong on screen after B35 made the skin loadable: the menu bar drew its
five items on top of each other, the album-art panel was black, the two time readouts were empty
(a lone `/` between them), a WACUP logo was drawn over the Winamp one in shade mode, and the search
panel showed a placeholder banner. All five were the same failure.

`RENDER_SCRIPTS=1` reports it in one line per script:

```
SCRIPT player-normal-group.xml owner=group#player.titlebar … ran=onscriptloaded
  failed=onscriptloaded: Winamp Modern runtime does not support method 'getsettingspath'.
```

**23 of the skin's `onScriptLoaded` handlers aborted on `System.getSettingsPath()`** — the skin
builds `<settings>/WACUP_Tools/koopa.ini` and probes for it to decide whether it is running under
WACUP, and it does this near the top of nearly every script. Each abort took the rest of that
handler with it, and the rest of the handler is where the widgets get placed.

The menu bar is the clearest case, and the one that misled the first diagnosis. `player.mainmenu`'s
own comment says it:

```xml
<!-- Note: Most of the items in this group are placed by script -->
```

`mainmenu.maki` measures each label with `getAutoWidth()` and lays the five `<Menu>` objects out
left to right. Nothing in the `Menu` widget self-sizes, and nothing needs to — B36's proposed
`prev`/`next` chain-placement rule would have been the wrong fix for a working script that never
ran. Once `getSettingsPath` answered, the five went to x = 190 / 231 / 277 / 350 / 400 on their own.

Implementing it surfaced three more methods that had been masked behind it — `getAutoHeight`,
`getGuid` and `scrollToPercent` — each aborting a further handler. Expect that cascade.

The readouts were a second, independent cause: the `display=` table knew only `time` / `songname` /
`songinfo` / `PE_Info`, and this skin asks for `TIMEELAPSED`, `SONGLENGTH`, `SONGTITLE` and
`SONGSAMPLERATE`. Unmapped bindings fell through to the literal `text=`, which is empty here.

The SUI tab captions were a third: they are `offsetx="35"`, which we ignored, so every caption drew
over its own icon instead of being clipped away by the 40px icons-only strip.

## B38 — what live QA found that no probe could

Three of these do not reproduce in the render harness at all, and two were diagnosed purely from the
app's own `#if DEBUG` logging. Worth knowing before reaching for `RENDER_PROBE` on this skin again.

- **Undraggable after shade → normal.** The titlebar is `<grid … move="1">` over
  `<rect id="vic_mover" move="1" fitparent="1">`, and we honoured `move="1"` on `<group>` only, so
  the window was draggable by accident — wherever bare background happened to be topmost — and shade
  mode changed which object that was. See `reference/rendering.md` → *Dragging the window*.
- **Playlist and media library drawn on top of each other at launch.** The skin's script opens its
  tab on its own timer, ~0.6 s *after* our reveals, so a reveal-time exclusivity check can never see
  the page it needs to yield to. See `reference/components.md` → *Revealing an embedded surface*.
  `WINAMP_MODERN_DEBUG_HOLDERS=1` is the only probe that shows it.
- **`getTextWidth`** aborted `onTextChanged` — the handler that runs on every track change. Only two
  objects in the skin declare it, both `display="PE_Info"`, so it is invisible headlessly until the
  harness has a queue: `WINAMP_MODERN_RENDER_TEXT=1 WINAMP_MODERN_RENDER_PLAYLIST=6`.

- **The visualization box drawn black over the album art (B38.4)** — and with it every other thing
  `mcvcore` was supposed to do. It *does* reproduce headlessly. The skin decides between the two
  panes from four config attributes it registers itself (`{6A619628-…}` *File Info* / *Playlist Info*
  / *Visualization&nbsp;&nbsp;* / *Multi-tools*, then `{8D3829F9-…}` *Visualization&nbsp;* /
  *Album Art*), and at the defaults it takes the album-art-only branch and hides
  `info.component.vis`. That branch is in `mcvcore`'s **first** `System.onScriptLoaded()`, and the
  script declares a **second** one — so the "keep the last binding per (object, event)" rule shadowed
  it and none of it ran. See `reference/scripting.md` → *Two handlers for one event*. The same fix
  restores the rest of the Multi Content View: `info.component.infodisplay` is laid out (it had been
  sitting at its markup `x=80 w=0`), and `info.component.coverflow` — full-window-width and also
  meant to be hidden — leaves the scene.
- **The file-info panel then stayed empty**, because its `onSetVisible` — which fills every line of it
  — aborted on **`getDecoderName`**, and behind that on `getPath`, `getIdealVideoWidth` and
  `removePath` in turn. Four methods, one handler, the cascade B36/B37 warned to expect. This is the
  rest of B38.3: implementing `getTextWidth` unblocked `onTextChanged`, and unblocking `mcvcore`
  exposed the next handler in the same panel.

**B38.5 is not a defect.** `player.mainframe.big` is `from="left"`, so the divider is anchored to the
left edge and the right pane absorbs every extra pixel — which is what Wasabi's `from` means, what
the skin's own `maxwidth="-300"` ("always leave 300 for the other pane") is written for, and what the
skin's script asks for when it calls `setPosition(434)` against its `minwidth="434"`. The window is
wide because the layout declares `w="1536" h="878"` as its **default** size. cPro-Bento's
`centro.mainframe` is the same attribute the other way round (`from="right" width="200"`, its
playlist column fixed and the left side growing) and confirms the reading. The oversized song title
is the skin's own `fontsize="48"` in a 237px `InfoDisplay`; nothing in the corpus writes `fontsize`
except `playlistpro.maki`, so no script is meant to shrink it.

## BB7 — the nine config pages and the equalizer tab were never built

`config_vscrollbars.maki` is declared **nine** times (`config.xml` ×8, `player-normal-sui.xml` ×1),
each with its own `param="part1;part2;<height>"`, and it contains the skin's only two `instantiate`
call sites. Every one of those nine pages is an empty `<GroupList>` plus a scrollbar in XML; all of
the actual options live in `…part1` / `…part2` groupdefs the script expands into the list. Without
the method the handler aborted at its first call and the pages had no content — and that single
recorded error is the whole reason all four variants reported `unsupported` while drawing fine.

Three things the first reading of this got wrong, all settled from the bytecode (and from the
author's own comment, `Group g1 = grplst.instantiate(param, 1); // "1" here is the amount of times`):
the second argument is a **count**, not an index; the receiver is a `GroupList`, not a plain group;
and the "nine call sites" are nine *declarations of one script*, not nine calls. The engine already
did the hard part — `instantiateGroup` / `pendingRuntimeGroups`, built for `newGroup` — so what was
missing was the list-side method and the vertical stacking a groupdef cannot carry. See
`reference/scripting.md` → *`GroupList.instantiate`*.

Behind it, the cascade this skin always produces: with the pages finally built, the Localization
page's own script ran for the first time and aborted on **`getApplicationPath`**, which it uses to
probe for Winamp's `/Lang/*.wlz` language packs. Implemented; the probes correctly find nothing.

Compatibility level after: **degraded**, on warnings alone, with no failing handler anywhere in the
skin. Neither surface is a hidden-window question a probe can answer — both are **tabs**, so no
headless dump renders them and live QA is the only instrument.

**The equalizer tab was confirmed live (2026-08-23), and its symptom is worth keeping** as the clean
signature of this defect: `info.component.eq` declares the EQ-ON / AUTO / PRESETS bar directly in
markup, and *everything above it* — the spline, the ten bands, preamp, balance, crossfade — is the
`GroupList`. So the tab drew **a preset picker and nothing else**. A skin whose surface is one strip
of real controls over an empty expanse is the shape to look for. (It is also why "I don't see a way
to show the EQ" and "I see the EQ icon" describe the same thing here: an SUI skin has no separate
equalizer *window*.)

**The config pages were confirmed live in the same pass.** They are the **Skin Settings** tab, the
bottom button of the same left strip as the Equalizer, and its left-hand menu has ten entries plus
*About the skin*. All eight `instantiate`-built pages have their content and stack without overlap.
Worth knowing before re-measuring: **three of the eleven pages are declared inline and never used
this mechanism** — Songticker, Visualization and Playlist — so they are a free control group for any
future defect in this area. Two things on those pages that are *not* BB7: the Color Themes list will
not switch a theme (**BB8**, `ColorMgr` unbound), and the Multi Content View page is where BB9's
unreachable visualization switch lives.
