# `Alienware Invader.wmz`

**Open work. This skin is the next hosted-frame row (W210) and its cause is already identified —
read § *The open defect* before starting, and do not re-derive it.**

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
`stretchedDownNodeIDs` existed for under the old assembler, and which the whole-view render answers
for free.

## The open defect (W210)

**Reported 2026-09-17**, and visible in any `WMP_HOSTED_FRAME_DUMP` of this skin: an alien head and
two empty boxes are painted over the left quarter of every NullPlayer window that borrows this
frame.

**The cause is a disagreement between two rules that each look right alone**, and it is measured,
not theorised. At the donor's floor (531x291):

- the client subview resolves to `134,34 374x221` — so the donor's own hole starts at **x=134**, and
  the three rack nodes at `18..134` are legitimately *outside* it. The furniture test in
  `ringRender` — a piece more than half inside the hole, touching no edge — therefore correctly
  does not fire on them.
- `WMPHostedFrameTemplate.reclaimingSideRacks` then decides a 134pt left margin against a 15pt right
  one is a **rack rather than a border** and hands that strip to our content, moving the reported
  left inset from 90pt to **27.8pt** at a 357-wide window.
- the frame is painted **over** the content (W209), so the strip our content was just given still
  has the donor's rack drawn on top of it.

So the hole is widened over the rack and the rack is painted anyway. Either half alone is right;
together they put an alien head on the library's rows.

Verify the numbers before changing anything:

```bash
WMP_SKIN=~/Library/Application\ Support/NullPlayer/WMPSkins/Alienware\ Invader.wmz \
  WMP_HOSTED_FRAME=357x238 WMP_HOSTED_FRAME_SCALE=2 \
  WMP_HOSTED_FRAME_DUMP=/tmp/awi swift test --filter WMPRenderDumpTests/testSweepsSkinOrCorpus
# HOSTED-FRAME … left=27.808 right=15.463 content=27.808,27.808 313.729x180.749 scaled=yes
```

**The shape of a fix**, untested: run the furniture test against the **reclaimed** content rect
rather than the raw client frame, so that whatever `reclaimingSideRacks` takes for our content is
also dropped from the artwork. The two rules then state one thing instead of two.

**What must be measured before believing it.** `reclaimingSideRacks` was written for `Ice`, whose
`plView` states a 157pt right rack; W207 records that growing a window by that raw margin put 157pt
of empty decorative artwork on every window's right edge. Any change here is a change to `Ice` too,
and to `Star Wars` (164 of 575pt to the right of its list). Check all three, and check that a
*corner bitmap* that legitimately dips into a reclaimed strip — `Halo 2`'s is 190pt on a 406pt
window — is not dropped with the racks.

## What is already ruled out

| Theory | Why it is wrong |
|---|---|
| The rack is painted into a corner bitmap and no node rule can reach it | False. Three separate subviews, listed above. `pl_top_left.png` is 99x60 and carries none of it |
| The old piece-selecting assembler handled this better | No — it showed the same rack *and* lost the right rail *and* tore the bottom bar. Compare `WMP_HOSTED_FRAME_WHOLE=0` against the default; the whole-view render is strictly better on this skin |
| Its rails needed the script-driven span (`stretchedDownNodeIDs`) | That was real under the assembler (0.231 of each side bare) and is moot now: drawing the view whole gives every piece its authored layout |
| The furniture test in `ringRender` is simply not firing | It is firing correctly. The rack is outside the donor's own hole; the hole is moved *afterwards* |

## Also true of this skin, from elsewhere in the guide

- It is one of the six archives holding the **`center` is not a margin** rule (`README.md`).
- It is one of three holding **`<EFFECTS>` and `<VIDEO>` rank last, never by paint order**
  (`README.md`).
