# `Disney_Mix_Central`

## What it is

A Skins Factory build from the WMP11 era — a 619x328 blue lozenge with a Mickey-shaped transport
cluster, an LCD panel and a four-button web strip down its right edge. Six views
(`previewView`, `controlView`, `mainView`, `eqView`, `visView`, `videoView`), one 2,200-line
`disney.js`, and **three modes inside `mainView` alone**: the player, a mini mode and the playlist,
switched by `togglePlaylist()`/`onViewTimer()` moving the transport, seek and metadata subviews to a
second set of coordinates rather than by opening a window.

Two things about it are structural and both cost a session:

- **It opens on a 31-frame intro.** `mainBack` is authored `visible="false"` and every other piece
  hangs off `wmpprop:mainBack.visible`; `onViewTimer` waits the view's authored 3,000 ms, drops
  `view.timerInterval` to 50, plays `intro_f1..f31.png` through `animLayer`, and only at frame 32
  sets `mainBack.visible = true` and reveals the player. **Frame 0 is a banner and nothing else.**
- **Its `controlView` is the windowless Skins Factory dispatcher (W89)** and it is the family
  boilerplate with views deleted: `onLoadSkin` and `checkRemoteViewStatus` call
  `theme.openView('plView')`, `'infoView'`, `'metaView'` and `'vidRemoteView'`, **none of which this
  skin declares.** The names that do work are `eqView`, `visView` and `videoView`.

## What it exercises that little else does

| Thing | Number | How it was measured |
|---|---|---|
| A `<TEXT>` string constant: a literal `value`, no `left`/`top`/`width`/`height`, no alignment | **246 nodes across 42 of 185 archives**; this skin declares 5 | decoded markup scan of every `<text>` tag over `~/Library/Application Support/NullPlayer/WMPSkins` (UTF-16 / cp1252 / UTF-8 as `WMPTextDecoder` does) |
| A view that reaches `0 hits` purely by being on frame 0 of its own intro | 3 in the corpus — this, `Batman Begins`, `Alienware Invader` | `starved.tsv` rows settled one by one; `WMP_RENDER_SETTLE` |
| A script that writes its own resize floor | **3 of 185 archives** — `Compact`, this, `NVIDIA` | the W196 scan; `onLoadPl` ends `view.minWidth = 639; view.minHeight = 336` |
| A playlist that is a **mode of the player**, not a view | `NVIDIA` family; this skin has no `plView` at all | `<VIEW` split of the decoded `.wms` |

**Its `mainView` renders at 639x336, not the 619x328 it declares, and that is the skin.**
`onLoadMain` → `onLoadPl` → `autoSizeView('plWidth','plHeight')` restores the *playlist's* saved
size, and `onClosePl` saves the current size under those same two keys — so main mode wears whatever
the playlist last measured, and `view.minWidth = 639` holds the floor there. Do not read the 20x8
difference as a layout defect.

## Defects it found

| Reported as | Cause | Row |
|---|---|---|
| ranked by `starved.tsv` as *"draws its banner and five widgets and answers no click anywhere"* | **Not a defect.** Frame 0 of the 31-frame intro. `WMP_RENDER_SETTLE=6` gives `39 nodes, 24 commands, 14 hits`, and `WMP_RENDER_CLICK` dispatches play, prev, next, the time readout and `toggleLibrary` | W68 |
| the five widgets themselves — never reported by a user, found by dumping the PNG | The second Skins Factory string subview carries a literal `value`, so `intrinsicTextSize` measured the glyphs and all five of WMP's rip-CD sentences drew stacked at `0,0` over the artwork | **W232** |
| *"when you go to the playlist you get trapped … if you close the playlist you do not return to the main window … when you bring the playlist back into focus the playlist is frozen"* | The playlist's X writes `exitView`; the windowless dispatcher reads it back and posts `view.close()`, which closes the **player**. The window survives its presentation, so re-showing it revealed a corpse — zero presents afterwards | **W233** |

## What was ruled out

- **The starvation the ranking named.** Its 3 remaining unresolved nodes are the two string
  subviews' own parents and a `<controls>`; none of them is a missing pixel. W231.
- **AppKit.** `hits == 0` was the column W68 pointed at, and `WMP_RENDER_OCCLUDED` reports
  `recovered=0 lost=0 unreachable-either-way=0` on every view of this skin at every settle value.
  Nothing here is occluded and nothing is an overlay defect.
- **The 639x336 canvas.** Its own script asks for it (above).
- **The playlist's "Return To Main Mode" button.** It works, first click, every time — it was only
  ever dead *after* the window had been closed and revived, which is W233 and not that button.

## How to drive it

Scene coordinates, `mainView`, at its own 639x336. Add the window origin to reach the screen.

| Control | Where | Note |
|---|---|---|
| playlist toggle | `340,144` | `m_bot` group at `293,134`, mapping `#0066ff` at `(47,10)` in `m_bot_map.png` |
| library | `336,31` | `m_top` group at `303,23`, `#0066ff` |
| play | `80,101` | `m_transport` group at `32,52`, `#0099ff` at `(48,49)`; prev `56,101`, next `96,101` |
| playlist "Return To Main Mode" | `556,24` | `pl_top` group, `#0000ff` — the subview is `left="jscript:view.width-83" top="16"` |
| playlist **close** (the W233 trap) | `604,24` | same group, `#0099ff`. It closes the **player**, not the playlist |

```bash
WMP_SKIN=~/Library/Application\ Support/NullPlayer/WMPSkins/Disney_Mix_Central.wmz \
WMP_RENDER_SETTLE=6 WMP_RENDER_PROBE=mainView WMP_RENDER_OCCLUDED=1 \
  swift test --filter WMPRenderDumpTests/testSweepsSkinOrCorpus > /tmp/wmp/disney.txt 2>&1
```

**`WMP_RENDER_SETTLE=6` is the minimum that reaches the player** — 3 s of authored `timerInterval`
plus 31 frames at 50 ms. Anything less measures the intro, and the intro measures as a starved view.
Its markup is UTF-16 (`iconv -f UTF-16LE`), its script likewise.
