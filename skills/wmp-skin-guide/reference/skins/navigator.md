# `Navigator`

A 2000 SkinWerkz build (`Vendicator`): a 340x200 winged player whose lower screen is six `screen`
plates that slide down by `moveTo` to frame a 120x96 display. The display switches between four
panes — the visualizer/video (`visual`), configuration (`eq`, with `vidset` behind a drawer arrow),
playlist (`pl`) and links (`lnk`) — through four tabs at the bottom of `config`.

## What it exercises that little else does

- **A `<SUBVIEW id="eq">`**, not an `<EQUALIZERSETTINGS>` — its equaliser is `equal`. Every
  `eq.visible` write is to that panel, and until W309 each one died on the host equaliser.
- **Negative-`zIndex` panes inside unkeyed artwork** — `config`'s `screenback.bmp` over four
  `zIndex="-2"` panes. One of three such containers in the corpus (W310).
- **A pane hidden while a child it holds was shown earlier** — `visual` and `vis` (W311).
- **A `<VIDEO>` ground with no artwork under it** at launch (W312).

## Defects it found

All from one report on 2026-09-25, after W309 made its handlers run to the end.

- *"i cant get the eq to show on navigator"* — the panes sat behind `config`'s opaque artwork. W310,
  closed.
- The visualizer keeps drawing over the EQ, playlist and links panes — W263's escape through the
  hidden `visual`. `visual` is authored visible, so W309's `closesSubtree` did not reach it; the
  escape now honours the order of the writes (`visibleWriteOrder`): `vis` was shown before `visual`
  was hidden, so it goes with the pane. W311, closed.
- *"this skin also opens with the panel open, it should not"* — the grey box is `vid`'s
  `backgroundColor="#404040"` below the wing, painted with nothing behind it. W312, open.

## What was ruled out

- **The grey box is not the playlist and not the hosted video surface.** The `<playlist>` has the
  same `#404040`, which is why it looks like one; `WMP_RENDER_PROBE` puts the box at `vid`'s frame,
  and `WMPVideoSurface` only hosts while `hasVideo`, so it is scene paint. It is in the pre-W309
  baseline too.
- **The EQ's handler.** `[wmp/dispatch] click targetID=conf … showconf()` with no handler error
  after W309; the write landed and the pane was drawn, behind the artwork.

## How to drive it

Window-local coordinates. The screen toggle is `dn1bd.bmp` at 139,84 (the arrow left of the LCD).
With the screen open, the tabs sit on the display's bottom edge: view 146,179, config 160,179,
playlist 174,179, links 188,179. `WMP_CLICK_TRACE=1` names each as `button#view`/`conf`/`list`/`link`.
