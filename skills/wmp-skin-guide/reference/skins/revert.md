# `Revert.wmz` / `Revert (1).wmz`

**Four unrelated engine defects (W74, W252, W254, W255), three of them in one session, and not one
of the four was visible to any headless probe in its default state.** Two of the four could not have
been found in any order but the one they were found in: W252 kept the `<VIDEO>` hidden, so nothing
had ever parked a window over it, so W254 had never happened — and the clean sweep said nothing was
wrong throughout.

## What it is

A compact, late-Windows-XP player: a 256x130 `vwPlayer` in silver WMP chrome, with a separate
256x130 `vwEQ` and a 256x260 `vwPL`. Three files carry it — `netgen.wms`, `netgen.js`, and string
and text resources pulled from `res://-/RT_STRING/…`. The player is deliberately small: a metadata
block on the left, a 92x67 combined video/visualizer pane on the right, a seek slider, and a
`<BUTTONGROUP>` transport under both.

**`Revert` and `Revert (1)` are the same markup.** They are separate archives and both are kept
(`harness/corpus.md` § *The corpus*), but for every defect below they are one test case, not two. Any reach
figure that counts them as two skins is counting one skin twice — W255's census did, and the honest
number there is **one**.

## What it exercises that little else does

- **A `<VIDEO>` and an `<EFFECTS>` sharing one pane, arbitrated entirely in script.**
  `vwPlayer_SelectVideoOrVis()` sets `ctrlVis.visible = !fVideo; ctrlVideo.visible = fVideo` and is
  raised from exactly two places — `onLoad` and `<PLAYER openstatechange=…>`. Nothing else re-runs
  it, so **every question this skin asks about video it asks once**, which is what made it the
  corpus's sharpest instrument for the media-open sequence (W252).
- **A fixed view with a video box far narrower than the command bar.** `vwPlayer` is
  `resizable="false"` with a 92pt box against a 395pt bar, which is the exact pair of conditions
  `WMPSceneBuilder.videoBarShortfall` cannot resolve (W254).
- **A control that mirrors `visible` onto its own `enabled`** —
  `<slider id="seek" enabled="wmpenabled:player.controls.seek" visible="wmpprop:seek.enabled">`.
  This turns any unanswered `wmpenabled:` path into a *deleted node* rather than a greyed-out one
  (W255).
- **A geometry expression reaching past its container**, `height="jscript:view.height-top-3"` with
  `top=0` inside a group at `top=14` — the corpus's ground truth for widget clipping, and the only
  `outside=` `WMP_RENDER_APPKIT` reports besides this skin's own second release (W74).
- **A 9-second `alphaBlendTo` in `onLoad`** (`Revert (1)` only), which is W253's clean case and
  still open.

## Defects it found

| Reported words | Cause | Row |
|---|---|---|
| — (ranked from `WMP_RENDER_APPKIT`) | `ctrlPlaylist`'s overlay was placed from the raw authored frame, not frame ∩ clip ∩ bounds, covering the bottom bevel of `pl_b.bmp` | W74 |
| *"a video plays with no picture in the skin"* | `player.openState` answered `osMediaOpen` the instant the playlist was non-empty, so the one `openstatechange` a video raises landed at `imageSourceWidth == 0` and the handler latched the visualizer on for good | W252 |
| *"lok at the fuckign black box sticking out"* | The parked video window carried the command bar, whose required constraints give it a 395pt minimum; a fixed view can never be widened to match, so `setFrame` to 92pt was silently refused | W254 |
| *"there are no seek controls for the movie"* | `wmpenabled:player.controls.seek` was unanswered and defaulted false; the slider mirrors `visible` onto its own `enabled`, so the node was deleted outright — for music as well as film | W255 |

## What was ruled out

- **W252 is not in the hosted surface.** The `<VIDEO>` widget resolves correctly at
  `frame=161,17 92x67` in every probe, before and after. The gate was the skin's own, and the fix is
  in the open-state sequence, not in anything that draws.
- **`vwPlayer_fVizOpened` is not the gate.** It is declared `false` at the top of `netgen.js` and
  **never assigned anywhere**, so the `if (!vwPlayer_fVizOpened)` arm is always taken. It reads like
  a live latch and is dead.
- **W255 is not video-specific and never was.** The slider was absent with music playing too. A
  report that arrives while a film is on screen is not thereby a video defect — check the same
  control with audio before ranking it.
- **The `13 -> 12 -> 13` round trip is not a hazard here**, because the open-state derivation gates
  on the *latched* `videoEvent` and not the live `video`: a media that has ever reported a size stays
  open across a VLC output rebuild. Pinned by `WMPHostEventEdgeTests`.

## How to drive it

Canvas `256x130`, so pick the window row by size, never by `head -1`:
`$WH windows | awk -F'\t' '$5==256 && $6==130 {print; exit}'`.

| Target | Authored rect (view coords) |
|---|---|
| `ctrlVideo` (`<VIDEO>`) | `161,17 92x67` — inside `svwKewlPane` at `left=3 top=17` |
| `ctrlVis` (`<EFFECTS>`) | `164,17 89x67` |
| `seek` (`<SLIDER>`) | `7,86 242x13`; thumb `17x8`; `width="jscript:view.width-2*left"` |
| `btnPause` | `14,97 32x32` |
| `ctrlAlbumArt` | `253,22 75x75`, `zindex=90000` |

Video needs a real film and never goes through `NULLPLAYER_PLAY` — Windows → **Library Browser** →
MOVIES tab, then `winhelper dblclick` the row (`app-control` Route C). The live instrument for
anything in the open sequence is `WMP_VIDEO_TRACE=1`; the headless one for the pane and the slider is
`WMP_RENDER_PROBE=vwPlayer` with `WMP_RENDER_HOST='playing,video=2560x1440'`, which is what showed
`vwPlayer` building **12 nodes with no slider among them** and 13 afterwards.

**Read `VideoPlayerWindowController`'s hosted-frame diagnostic before theorising about the picture.**
`WinampModern video: box {W, H} refused, window took {W', H'}` is printed on every hosted layout
pass, in a DEBUG build, with no flag at all, and it named W254 exactly — ten times a second, for as
long as the path had existed, unread.
