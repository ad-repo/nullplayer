#### How a colour resolves (BB2a, 2026-08-25)

Everything a skin colours — a `<rect color=…>`, a `<vis colorband1=…>`, and the `WasabiPalette` roles
NullPlayer's own surfaces draw with — goes through `resolvedColor` / `objectColor`. A colour that
fails to resolve does not disappear; it becomes a **fallback**, and the two fallbacks are loud:
`unparseableColor` is **white** and `contentBackground`'s literal is **black**. So the symptom to
recognise is *"a white slab"* or *"a black rectangle"* where the skin plainly names a colour — not a
subtly wrong shade.

Three ways a declared colour used to be lost, all fixed and all worth knowing because each has a
different signature:

1. **A colour resource may name another colour resource.** `<color id="wasabi.list.text"
   value="color.display"/>` — the value is an *id*, not a triple. Big Bento Modern writes nearly its
   whole palette this way. The walk to the literal is bounded and cycle-guarded, and the **referring**
   declaration's `gammagroup` wins where it has one, so the channels are tinted once, by the group the
   id that was asked for names.
2. **Bitmaps and colours are different tables.** Wasabi keeps them apart, and skins rely on it: Big
   Bento declares `wasabi.list.background` as a `<color>` in `system-colors.xml` *and* as a tiled
   `<bitmap>` in `system-elements.xml`. A single flat registry let the bitmap win, and a colour lookup
   then found an image with no `color=` — which the palette chain skips, landing on black.
   `WalResourceRegistry.resolvedColorDefinition` indexes the colour-carrying declarations separately;
   `resolvedDefinition` still answers the bitmap, so tiling that image is unaffected. A `$solid` /
   `$gradient` bitmap counts as colour-carrying, because its pixels *are* its `color=` attribute.
   **Within that colour table a real `<color>` outranks a generated bitmap**, whichever is declared
   last — Ebonite_2_1 declares the same id as a `<color>` at 70,70,70 ("lists/trees item background")
   and a `$solid` at 237,237,237 ("Tree background bitmap (tile)"), the tile last, and its list text
   is white: taking the tile painted white on near-white. Two `<color>`s of one id keep ordinary
   last-wins; the ranking is about *kind*, not order.
3. **`#rrggbb` is a literal.** Enkera declares its entire palette in hex; Sony_Walkman its analyzer
   (`colorband1="#808589"`), Big Bento its 22 analyzer bands. The parse is deliberately strict — only
   a `#`-prefixed token — so a bare `abcdef` stays a resource id, which is what the caller already
   tried it as.

`WINAMP_MODERN_RENDER_PALETTE=1` prints every role, every link of its chain, and why each link
answered or did not. **Use it before changing a colour path**: it distinguishes "the skin never
declared it" from "a colour theme crushed it" from "the chain skipped a bitmap", which look identical
on screen. See `harness.md`.

#### A resolved colour is not yet a *readable* one (B48, 2026-08-25)

Every role resolves from its **own** id chain, and nothing in Wasabi checks that a foreground and the
background it lands on can be seen together. A skin declaring two colour families therefore hands us
a mongrel pairing that neither family's author intended. Winamp never hits this: its Media Library is
a native Win32 list, so the OS guarantees a legible selection. We draw those rows ourselves, so the
guarantee has to be ours.

**Measured across all 36 installed skins:** 23 drew an unreadable selected row (< 1.5:1), **nine of
them at exactly 1.00:1** — text and highlight the same colour — and 5 an unreadable window title,
with 22 more weak (< 3:1). Big Bento is the type specimen: highlight from
`studio.list.item.selected` (orange `color.selected.active`), row text from
`wasabi.list.text.selected` (pale blue-grey `color.display`) — **1.06:1**; and a *current* row over
that same bar is orange on orange at **1.00:1**.

The guarantee lives in `WinampModernSurfaceStyle`, which already *derives* roles by blending rather
than inventing, and which is **nil in classic mode** — so classic cannot be reached by it:

- `legible(preferring:on:)` returns the **first of the skin's own colours** that clears
  `minimumContrast` (3.0, WCAG's large-text bar), and only falls back to black or white — whichever
  is further from the background — when every one of them would be invisible. That fallback always
  clears: for any background, one extreme is at least ~4.5:1 away. **Ordering is the policy**: a skin
  that gives us anything usable is never overridden.
- `selectedText` is the stored role for a highlighted row: `currentText` → `selectionText` →
  `listText` → `contentBackground`, judged against `selectionBackground`.
- `legibleDimText(on:)` is for inactive titles and hints. `dimText` is a 40% blend toward the
  background, so a naive guard fails it almost everywhere and would snap every inactive title to full
  strength — erasing the active/inactive distinction corpus-wide to fix five skins. It backs the
  blend off in stages (40% → 25% → 12% → full) instead.
- `composited(_:over:)` flattens a translucent fill first. `PlexBrowserView`'s focused search field
  draws over a **half-alpha** highlight; judging the written colour rather than the composited one
  leaves that one state unreadable while the opaque row beside it is fixed.

**Two draw paths need it, and missing the second is the easy mistake.** NullPlayer's AppKit surfaces
go through the style (`PlexBrowserView`'s four selection sites and its title, `WinampModernChrome`,
`PlaylistView`, `EQView`). But the skin's **own** playlist panel and `<ColorThemes:List>` are drawn by
`WasabiRenderer` straight from `WasabiPalette`, never touching a style — that is
`WasabiRenderer.legibleRowColor`, and it was the half that live QA caught after the first pass looked
complete on the library panel.

**Where it deliberately stops: text the skin declares for its own controls.** Formamp's window
background is `(0,0,0,206)` — translucent by design, never opaque anywhere — and its `<text>` objects
name `color=80,80,80` (title), `120,120,120` (artist), `100,100,100` (timer). Over a bright desktop
that composites to black-on-black, and it is still not ours to change: guarding a colour an author
spelled out is overruling the design, not fixing our legibility. Closed as won't-do. The same reading
applies to any quiet-by-design skin — Lobe, micro.

`PlaylistColors.selectedText` (declared **twice**, `Skin/Skin.swift` and
`NullPlayerCore/Skin/SkinTypes.swift` — out of step is a build error, not a silent regression)
defaults to `currentText`, which is exactly what the draw sites read before it existed. Classic `.wsz`
skins are a zero-pixel change by construction and `SkinLoader` needed no edit.

#### Colour themes (`gammaset` / `gammagroup`)

A theme is a set of per-channel adjustments keyed by `gammagroup` id, which bitmaps and `<color>`
resources opt into with `gammagroup="…"`. Three rules:

- The value triplet is a per-channel **amount** normalized to −1…1 (`v / 4096`); 0 means "leave this
  channel alone" under either model below.
- **`boost` picks the model, and the skin is the authority.** There is no single right answer here —
  picking one globally always breaks the other half of the corpus:
  - `boost="0"` or the attribute omitted → **multiply**, `channel × (1 + amount)`. Tints real artwork
    without washing it out. Every group in **Anexa** is `boost="0"`, as are MMD3's `Backgrounds` /
    `Display` / `Buttons` (which carry no `boost` at all) — forcing those additive pushes midtones
    toward white and renders MMD3's amber display as washed-out pastel.
  - `boost` non-zero → **add**, `channel + amount`. This is how a skin recolours a black template.
    **Anaheim Player 01** marks 57 of its 65 groups `boost="1"`; its themed bitmaps
    (`MiniControlWheel.png`, `MiniTickerBtns.png`, `MiniBodyBtn.png`) are pure black with only an
    alpha mask, and every `<color>` in its `studio-colors.xml` is `value="0,0,0"`. Multiplied, 0 stays
    0 — black text on black sub-windows and hover controls that never appear.

  Stock `winampmodern566` draws the same line inside one skin: `boost="0"` on `Backgrounds`,
  `boost="1"` on exactly the groups whose source colour is `0,0,0` (`wasabi.button.text`,
  `wasabi.list.column.text`, `drawer.color.text.dark`) plus the hover-glow bitmaps.

  `boost` is a mode, not a flag — MMD3 and Itemskin ship `boost="2"` alongside `boost="1"`, on the
  same label groups. Its exact difference from `1` is **unknown**; it is treated as additive, which is
  strictly closer than multiplying, and a spot-check of MMD3 (2026-08-23) turned up nothing visibly
  wrong. Do not re-derive the probe if this comes up again:

  - MMD3's heaviest `boost="2"` user is `MainLabel` → `label11.png`, the **"MMD3 / WINAMP-PLAYER"
    wordmark** at the top of the main window (`player-normal.xml` `mslabel11`, x=156 y=4), in 51 of
    83 themes. It proves nothing: the value there is `-4000,-4000,-4000` on a stencil that is already
    black, so both models render it black.
  - The **only clean A/B** is `CoverLabel` at value `3000,3000,3000`, identical `gray`, differing only
    in boost: `silver1 | xblue` is `boost="1"`, the `xbox | orange`/`blue`/`pink`/`red`/`yellow`
    family is `boost="2"`. It draws the drawer headings — `label7` "EQualizer MMD3" (EQ drawer),
    `label9` "VISualization MMD3" (VIS drawer), `label10` "COLORThemes" (ColorThemes drawer), all
    pure-black stencils. Open a drawer, switch between those two themes: we render both at the same
    mid-grey, so a brightness difference in real Winamp is the tell.
  - Secondary probe: `DisplayLabel` under `silver3 | slategray`/`slateblue`/`skyblue` or `xbox | blue`
    — `displaylabels.png` (the STEREO/MONO and play/pause/stop glyphs in the main display) is the one
    `boost="2"` target that is bright artwork (avg RGB 200), where the two models diverge most.
- The **default** theme is the first gammaset in the document (skins name it freely — "clean | orange
  (default)"), not the alphabetically first name.

`WasabiColorThemeCatalog` reads the gammasets straight from the document, so `gammagroup` is
deliberately *not* registered as a resource: its id is scoped to its gammaset, and registering it made
each of MMD3's 83 themes "replace" the previous one's groups (1404 bogus duplicate-id warnings).

##### The picker: `<ColorThemes:List>` and the `colorthemes_*` actions (Phase 32)

The catalog is only half the feature. The screen a user picks a theme from is
`<ColorThemes:List>` — an **unregistered XUI tag**, because in real Winamp the widget lives inside
Winamp and only the tag appears in the `.wal`. Until Phase 32 it expanded to a leaf object with no
bitmap, which `isRenderable` and `isInteractive` both rejected, so every colour-theme screen in every
skin was an empty box that could not be clicked.

- The renderer draws the rows (`drawColorThemeList`), from `themeNames` in catalog order, through the
  same `drawSurfaceText` path the embedded playlist uses — the skin's list font, the skin's list
  colours, the skin's active gamma. The **selected** row (`selectionBackground`/`selectionText`) and
  the **applied** one (`currentText`) are drawn differently, as Winamp draws them: "the row I am
  pointing at" and "the theme the window is wearing" are different facts.
- Per-object state (`WasabiColorThemeListState`, keyed by `WasabiObjectID`) holds the selection and
  the scroll, so a skin with a list in its player *and* in a standalone window — mmd3 has both — keeps
  them independent. The first draw **seeds the selection to the applied theme and scrolls it into
  view**; with 82 themes a list that always opened at row 0 could not answer "which one am I on?".
- A single click selects; a **double-click** applies. The skin's own `Switch` button is what a single
  click is waiting for.
- **No scrollbar.** The renderer has no scrollbar support at all, so a `<Wasabi:Scrollbar>` a skin
  places beside its list is inert and the wheel is the only way down the list. Scrolling the applied
  theme into view is the mitigation; growing scrollbar support is a separate piece of work.

The three host actions live in `WinampModernMainView.performAction`:

| Action | What it does |
|---|---|
| `colorthemes_switch` | applies the selection of the list its `action_target` names |
| `colorthemes_next` / `_previous` | steps the **applied** theme, wrapping, and drags every list's selection along |

`action_target="<id>"` is resolved with Wasabi's **wide** semantics, the ones `findObject` uses: the
button's own container subtree first, then the whole graph. The wide half is load-bearing — mmd3's
`ctsbig` window names `main.colorthemes.list`, which lives in another container. A button whose target
resolves to nothing falls back to the only list in the scene, and failing that to a **popup menu** of
the theme names. (multipass was the worked example of that fallback until Phase 33; it is not one. Its
`player.colorthemes` lives in a groupdef that only `System.newGroupAsLayout` instantiates, and that
method was refused — so the target was missing for a reason the skin had nothing to do with. It
resolves now, and the buttons act on a real 58-row list.) `action="TOGGLE"` with Winamp's Color-Themes preferences GUID
`{53DE6284-7E88-4c62-9F93-22ED68E6A024}` opens that same popup.

Skins that define themes and ship **no** picker at all (measured: Anexa, micro, T800, ZDL, Itemskin,
Overdrive_2) are covered by the host **Color Themes** submenu in the Winamp Modern menu, which is the
preferences dialog we do not otherwise have. It is gated on more than one theme.

