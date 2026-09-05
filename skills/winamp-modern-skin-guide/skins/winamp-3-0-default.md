# Winamp 3.0 Default

`Winamp 3.0 Default.wal` — Nullsoft's own **Winamp3 Base Skin** (`skin.xml`: *"Please feel free to use
this skin as a reference point to build your new Winamp3 skins"*, Steve Gedikian). 84 KB, the smallest
archive in the corpus: 48 files, of which **nine are PNGs**.

It is the reference case for one thing above all: **this skin's windows are not in this skin.**

## The trap: the frame is Winamp's, not the author's

Every full-size layout is a bare `<Wasabi:StandardFrame:NoStatus>` or `:Status` wrapped round a
`content=` group, and the archive declares **zero** `wasabi.*` bitmaps. Measured:

| | count |
|---|---|
| `<bitmap>` declarations | 105 — every one `player.*`, `pledit.*` or `video.*` |
| `<bitmap id="wasabi.…">` declarations | **0** |
| distinct `wasabi.*` ids **referenced** | 30 — `wasabi.panel`, `wasabi.titlebar.{left,center,right}.{active,inactive}`, `wasabi.window`, `wasabi.objectframe.group`, `wasabi.tooltip`, `wasabi.font.default`, and the fourteen `wasabi.button.*` |
| `id="wasabi.…"` occurrences | 9, and every one is a `<group>` **instance** — the skin dropping itself into a Wasabi base group, never defining one |
| `<color>` declarations | 0 — so the palette is `WasabiPalette.fallback`, green on black |
| `wasabi.standardframe.*` groupdefs | **0** — with `jvc.tape.v0.5` and `Overdrive_2`, one of only three corpus skins that ship none |

In real Winamp the bevelled olive frame, the hatched title bar and the panel plate resolved out of the
base skin. We have no equivalent, so **anything you see around this skin's content is chrome NullPlayer
painted**. Do not go looking in the archive for artwork that would explain it, and do not read a
difference from the author's screenshot as a rendering bug: `screenshot.png` (275×116, shipped in the
archive) is Winamp's frame round the skin's content, and only the content half is reproducible from
what the `.wal` contains.

The two halves of "the skin ships none of it" were closed separately and the same way — draw a known
control rather than invent a bitmap; see
[reference/rendering.md](../reference/rendering.md) → *Window-chrome buttons with no artwork* (B95) and
*A standard frame whose artwork stayed in Winamp* (B121).

## State

Renders and drives. Nine layouts across five containers: `main` (normal, shade), `eq` (normal,
advanced, shade), `Pledit` (normal, shade), `Video` (normal), `thinger` (normal). The windowshade
layouts are plain groups over `player-winshade/background.png` and have always drawn correctly — it is
only the full-size ones that were frameless.

- **B95, 2026-09-01** — the frame's `content=` group entered the graph (Winamp's `standardframe.maki`
  instantiates it and this skin ships neither the groupdef nor the script), and its titlebar buttons
  got glyphs. Before that every full-size layout was a blank 275×116.
- **B121, 2026-09-04** — the frame's own chrome. Reported as *"winamp 3.0 skin has many problems with
  missing window borders and backgrounds"*. All six full-size layouts gained a plate, a title strip and
  a border; the equalizer's `PREAMP` / `60`…`16K` band labels became legible for the first time (they
  were being drawn on nothing).

## Knowingly missing

- **The Winamp3 frame *look*** — bevelled olive plate, hatched rules either side of the centred title.
  That is Nullsoft's base-skin artwork; NullPlayer draws a flat palette-derived frame instead, and the
  reporter accepted it as-is on 2026-09-04 rather than have the bevel approximated. Revisit only on a
  fresh request.
- `wasabi.titlebar.{left,center,right}.{active,inactive}` — ten `image=` references in
  `eq-shade-group.xml`, undeclared. The EQ windowshade draws without them.
- `skin.xml` includes `xml/gamma-presets.xml`, which the archive does not ship; the include is skipped
  with a `resourceMissing` warning and the gammasets it wanted are in `xml/color-presets.xml` anyway.
  This is why the skin's compatibility level reads `degraded` and it is not a defect.
- Not measured with `/wal-skin-report`; the numbers above are from the render dump and direct reads of
  the archive.
