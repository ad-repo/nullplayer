# HeadAMP

An homage to the Windows Media Player "Headspace" skin by sambaneko (`winamp.spacecatsamba.com`), and
the skin that found B140. **Its NullPlayer-owned windows are framed correctly as of B140
(2026-09-05)**; before that they were chrome around a squashed, off-centre client.

## The shape of this skin

One container. `xml/player.xml` declares **`main` only** — a 760x394 `mode-main` layout with two
drawers (`leftDrawerToggle.maki`, `rightDrawerToggle.maki`) — and no component windows at all: no
`PLEdit`, no `MLibrary`, no `Video`, no `AVS_window`. Everything else it ships is the generic Wasabi
window furniture in `xml/window.xml`: `wasabi.titlebar`, `wasabi.frame.layout`, and the four standard
frames (`statusbar`, `nostatusbar`, `modal`, `static`, the last two inheriting `nostatusbar`).

So **every** window NullPlayer opens under this skin is one of ours in one of those frames, which is
what made it the reporting skin: a defect in the ordinary `content=` frame path has nothing else to
hide behind here.

## Traps this skin sets

- **Its client rect lives in a script `param`, and the two flavours disagree by 20 rows.**
  `wasabi.standardframe.statusbar` carries `param="25,28,-40,-70,0,0,1,1"` and `nostatusbar`
  `param="25,28,-40,-50,0,0,1,1"`. Nothing in the markup around the frame states where its client
  goes; read the script node's attribute. See
  [`../reference/components.md`](../reference/components.md) → *A frame that builds its own client
  still costs the window*.
- **The padding is asymmetric on both axes, and deliberately so.** 25 left against 15 right, 28 top
  against 22 (no-status) or 42 (status) bottom, where the artwork's own edges are 15 at the sides and
  25-tall bars top and bottom. The extra is the author's room for what Winamp's own components draw —
  the status frame's `LayoutStatus` sits at `x="40" y="-38" h="15"`, inside the bottom band. Our
  windows put nothing there, which is why they take the no-status frame and centre inside it.
- **The mat between the artwork and the client is the skin's own `component.basetexture`**
  (`window/window_bg.png`, dark green). It is not a gap or a missing layer; a window of ours that
  looks "matted" on this skin is drawing exactly what Winamp draws.
- **Its player is 760 wide**, so the player-width rule opens every hosted window at 760 — an aspect
  ratio no Winamp component window ever has, and the reason the frame's share of the window reads as
  much heavier here than the same numbers do elsewhere. Measure a hosted window at the *player's*
  width, not the layout default.
- **`scripts/standardframe.maki` is the stock 2002 build** (identical byte-count shape to the ones
  DashAmp and others ship). It runs without complaint when the frame it is attached to carries no
  `content=` — which is what our own windows now do — so nothing needs suppressing.

## Knowingly missing

- No `/wal-skin-report` run yet. Everything above was measured from the archive and from
  `WINAMP_MODERN_DRAG_HOSTED`; the player itself has only been looked at live.
