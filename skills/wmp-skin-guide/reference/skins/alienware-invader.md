# `Alienware Invader.wmz`

**W210 and the open-resize defect are closed (2026-09-17); W212 is open** — the borrowed frame still
paints three white blocks and a grey column over NullPlayer's own windows. Read § *What is still
open* before starting, and the `W212` row's three reverted fixes before proposing one.

Part of the six-archive Alienware/ALX family that already holds two counter-evidence rows (see
[`alienmorph.md`](alienmorph.md) and the `center`-is-not-a-margin row in
[`README.md`](README.md)). This file is about `plView` as a **frame donor**, which is a different
question from anything in those.

## What it is

Eight views (`previewView`, `controlView`, `mainView`, `metaView`, `eqView`, `plView`, `visView`,
`videoView`). `plView` is authored 331x277 with `minWidth="531" minHeight="291"` — a declared floor
well above its own authored size, as in [`back-to-the-future-trilogy.md`](back-to-the-future-trilogy.md).

```bash
unzip -p ~/Library/Application\ Support/NullPlayer/WMPSkins/Alienware\ Invader.wmz awi.wms \
  | python3 -c "import sys;sys.stdout.write(sys.stdin.buffer.read().decode('utf-16'))" > /tmp/awi.wms
sed -n '/<view id="plView"/,/<view id="visView"/p' /tmp/awi.wms
```

## What it exercises that little else does

**A donor whose left border is a furnished column, not a border.** `plView` puts an album-art well,
a search field and the top of a list rack in that margin, as three ordinary decorated subviews at
`left="18"`:

| node | bitmap | size | position |
|---|---|---|---|
| album well + search box + rack top | `pl_top_left2.png` | 116x160 | `left=18 top=32` |
| rack body | `pl_left_tile3.png` | 116x23, tiled | `left=18 top=192`, `verticalAlignment=stretch` |
| rack foot | `pl_bot_left2.png` | 116x28 | `left=18 top=view.height-62`, bottom-aligned |

They are **nodes, not pixels** — an earlier handoff recorded them as "baked into one 190pt corner
bitmap", and that is wrong; `pl_top_left.png` is 99x60 and carries none of it. A node rule *can*
reach them. That correction is the main reason this file exists.

It also states its rails in three pieces per side and sizes the lower ones in its own
`onResize="resizeListBox();onPlResize();"`, which the frame build never runs — the defect that
`stretchedDownNodeIDs` existed for under the old assembler. **The whole-view render does not answer
this for free, and an earlier version of this file said it did.** A view drawn whole cannot come
*apart*, but it can still be drawn *short*: the frame build is a private builder outside the script
runtime, so the tile `onPlResize()` sizes is still one bitmap tall and the borrowed frame carries the
same 20.1% bare run down each side that the skin's own window had before the open-resize fix
(`gaps=0.000/0.201/0.000/0.201`). Reviving the repair pass to close it is one of the three dead ends
in the `W212` row.

## W210, closed 2026-09-17 — the rack no longer reaches our windows

The defect was two correct rules disagreeing. At the donor's floor (531x291) the client subview
resolves to `134,34 374x221`, so the three rack nodes at `18..134` are legitimately *outside* the
hole and `ringRender`'s furniture test was right not to fire on them;
`WMPHostedFrameTemplate.reclaimingSideRacks` then judged a 134pt left margin against a 15pt right one
to be a rack and handed that strip to our content; and the frame is painted **over** the content
(W209), so the rack landed on the library's rows.

**The fix the row proposed does not work, and the reason is worth keeping.** Running the furniture
test against the *reclaimed* rect alone removes this rack and takes `Ice`'s right rail with it
(`Vid-righttile.bmp`, `431..468` of the 157pt margin the same rule reclaims): its left gap went
`0.082` → `0.595` and the inner right border vanished from the frame. Both pieces sit in the
reclaimed strip, touch no edge, and are more than half inside the widened hole — position alone
cannot separate them.

**What separates them is paint order**, which is the donor's own answer to the same question: a piece
drawn *before* the client subview is behind the skin's own list — a rail, a bezel, a background — and
is behind ours for the same reason; a piece drawn *after* it is over the skin's content, and over
ours. `Ice` paints its rail at `zIndex=5` under a `zIndex=50` list; this skin paints its racks at
`zIndex=10` over a list with no `zIndex` at all. Read off `scene.commands` (the render order), never
off `zIndex`, which `WMPScene` documents as ordered among siblings only.

Measured at 357x238 scale 2: the corpus sweep over 185 archives moves **one** line
(`LostPlanet whole=no → yes`); the rule reaches 7 archives, of which `Alienware Invader`,
`Batman Begins` and `LostPlanet` change pixels and `livin_it_skate`, `STALKER`, `Star Wars` and `WoW`
are byte-identical — their dropped nodes are AppKit widgets with no paint command. `Ice`, `Star Wars`
and `Halo 2` are untouched, line and frame both.

## The open-resize defect, closed 2026-09-17 — this skin's *own* playlist window

Not a borrowed-frame defect at all, and reported separately: a 58pt band of bare window through both
side rails of `plView` itself.

`plView` is authored 331x277 with `minWidth="531" minHeight="291"`, and states each rail in three
pieces — a top, a centred piece, and a tile whose height only `onPlResize()` ever sets
(`plLeftStretch.height = view.height / 2`). The window opens at the floor, the app's view-open path
raised no `onResize` there, and that tile kept its bitmap's own 51pt. Left column covered `0..173.5`
and `232..291`; bare `173.5..232`.

Proof, before any change: the open path printed `RESIZE plView: 531x291 -> 531x291, handlers=0`,
while a harness pass that *does* resize (`WMP_RENDER_SIZE=560x320`, `handlers=1`) drew both rails
continuous.

**The rule:** a view laid out at a size it was never authored at has already been resized, and its
`onResize` runs before anyone sees it — `WMPMainWindowController.opensResized`, applied on both the
player-view and auxiliary-view open paths. The before-layout is the authored one with the floor
lifted (`unclampedOverrides`), so `resizeEvent`'s existing rule decides the dispatch exactly as it
does on a user drag. Gated on the view declaring an `onResize`, so the 161 of 180 archives that do
not still open on one scene build. Only the overrides are taken from that transaction: the load's own
host commands and timer set are what the open path applies, and a second transaction's empty
`timerRequests` would cancel the timers `onLoad` had just registered.

**Reach: 14 views in 11 archives** — scan the corpus for a view that declares `onResize` and whose
authored `width`/`height` is below its own `minWidth`/`minHeight`:

| archive | view | authored | floor |
|---|---|---|---|
| `ALXMorph`, `ALXVortex` | `infoView` | 389x247 | 389x317 |
| `AlienMorph`, `AlienwareTeleport` | `infoView` | 389x247 | 389x366 |
| `Alienware Invader` | `plView` | 331x277 | 531x291 |
| `Alienware Invader` | `videoView` | 331x432 | 341x412 |
| `Batman Begins` | `plView` | 358x239 | 468x239 |
| `Frostbite` | `plView` | 194x259 | 300x290 |
| `LostPlanet` | `plView` | 376x216 | 565x310 |
| `Project Gotham Racing 2 (1)` | `videoView` | 348x464 | 410x464 |
| `Star Wars` | `plView` | 472x256 | 500x256 |
| `T3-Skynet_Media_Player` | `upgradeView`, `plView`, `infoView` | 279x245 | 414x237 / 461x302 |

`Batman Begins`, `LostPlanet` and `Frostbite` playlists were opened live and are intact.
**The harness cannot express this pass**: its first build already clamps to the floor, so
`WMP_RENDER_SIZE` at the floor prints `handlers=0` and compares a no-op against a no-op. Check it in
the running app, or not at all.

## What is still open — W212

The borrowed frame still puts **three white blocks and a grey column** on every NullPlayer window
that wears it. Both halves, the measurements, and three reverted fixes are the `W212` row in
[`WMP_TASKS.md`](../../../../WMP_TASKS.md). The short of it: the white is not a hole — this skin's
border bitmaps carry its interior colour baked in (`f_top_right.png` is a silver band over opaque
`(255,255,255,255)`, and so are `f_right_tile.png` and `pl_bot_left.png`) — and the grey column is
the donor's genuine 99pt left rail, under which `reclaimingSideRacks` lays our content by reclaiming
the left inset to 34.

**`gaps=0.000/0.000/0.000/0.000` on the `HOSTED-FRAME` line while the window is visibly wrong**: the
field samples a 6pt band at the very edge and can see none of this. Dump the frame and read its
**alpha** — opaque white and transparency are the same picture in a PNG viewer, which cost two wrong
diagnoses in one session.

## What is already ruled out

| Theory | Why it is wrong |
|---|---|
| The rack is painted into a corner bitmap and no node rule can reach it | False. Three separate subviews, listed above. `pl_top_left.png` is 99x60 and carries none of it |
| The old piece-selecting assembler handled this better | No — it showed the same rack *and* lost the right rail *and* tore the bottom bar. Compare `WMP_HOSTED_FRAME_WHOLE=0` against the default; the whole-view render is strictly better on this skin |
| Its rails needed the script-driven span (`stretchedDownNodeIDs`) | Half right, and the half that is wrong was recorded here as settled. The *skin's own* window is fixed, and by the open-resize rule above rather than by a span override. The **borrowed frame** still has the bare run — the frame build runs no script — and `stretchedDownNodeIDs` is unreachable under the whole-view render. Reviving it re-admits the rack (`W212`, dead end (a)) |
| The furniture test in `ringRender` is simply not firing | It is firing correctly. The rack is outside the donor's own hole; the hole is moved *afterwards* |

## Also true of this skin, from elsewhere in the guide

- It is one of the six archives holding the **`center` is not a margin** rule (`README.md`).
- It is one of three holding **`<EFFECTS>` and `<VIDEO>` rank last, never by paint order**
  (`README.md`).
