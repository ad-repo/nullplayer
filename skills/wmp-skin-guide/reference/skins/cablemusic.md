# `Cablemusic.wmz`

*Cablemusic Player 1.09, © 2000 Cablemusic Networks — one view, `mainview`, 593x600.*

A promotional player for a defunct internet-radio service, and the single most productive test case
this engine has had: **nine unrelated engine defects across two reports**, four of which no headless
probe could see. It is worth opening after any change to layout, text, button groups, tweens or the
view root.

## What it is

One `<VIEW id="mainview">` holding two complete player shells — `mainPlayer` (593x600,
`clippingPlayer.bmp`) and `smallPlayer` (`collapsedClipping.gif`, 391x372) — plus three sliding
drawers (`subPrograms`, `subPresets`, `subPlayList`), a settings drawer with ten EQ sliders, and a
25 KB `cablemusic.js` that lays almost all of it out at runtime. Its markup declares geometry for
very little; `Init()` positions the readouts and both 17-row station lists by hand.

## What it exercises that little else does

| Thing | Detail |
|---|---|
| Script-driven layout | `Init()` writes `top`/`left`/`width`/`fontSize`/`value` on 44 `<TEXT>` nodes that author none of them. Its two drawers are 17 rows each, laid out entirely by `InitPrograms()` |
| Six `<BUTTONGROUP>`s with **no normal `image`** | presets, stop, close/minimize/effect/shrink, bandwidth, and one tab per drawer — every one is `mappingImage` + `hoverImage` + `downImage` and nothing else |
| A compact mode built from `view.width`/`view.height` | `SwitchSmall()` writes 475x373, hides `mainPlayer`, shows `smallPlayer`; `SwitchBig()` reverses it |
| Reading a position back after moving it | `onClick="PlayListMove();HidePlist();"` — the second call reads `subPlayList.left` to decide what the first one just did |
| Duplicate authored ids | Eight `<TEXT>` ids are declared **twice**. The second wins and the first is never written |
| A duplicate `mappingColor` | `bnpb6` and `bnpb7` are both `#00C0FF` — one preset too many for the eight regions in `map.gif` |
| No geometry expressions at all | Zero `JScript:` attributes, which is why it was the case that killed the expression-cascade theory (W68) |

## Defects it found

Reported 2026-09-09 as *"broken all over — most buttons don't work, there is no track display"*, then
*"still many problems"*, then *"when you mouse over the compact button there is a huge overlay"*.
Every row is closed; the detail is in `docs/wmp-skin/wmp-backlog-archive.md` § *Phase 14*.

| W | Reported as | Cause |
|---|---|---|
| W107 | "there is no track display" | `<TEXT>` had no intrinsic size, so a readout the script sizes with `top`/`left`/`width` and no `height` never drew |
| W108 | "most buttons don't work" | A `<BUTTONGROUP>` had no intrinsic size, so it registered no hit target while the artwork beneath still drew the buttons |
| W109 | (same) | `<PLAYBUTTON>`, `<NEXTBUTTON>`, `<PREVBUTTON>` and peers were not element kinds. An unknown kind still paints its `image`, so the button drew and did nothing and the pointer fell through — a click on Play answered `hit=ffw` |
| W110 | (same) | An origin the markup never stated could not be written by script, so all 34 station rows drew stacked in the corner of their drawer at the right width |
| W112 | "the playlist is always showing" | `moveTo` applied its endpoint inside the call, so `HidePlist()`'s `if (subPlayList.left == 373)` read the destination instead of the origin |
| W113 | "when you click the compact button there is a large overlay" | Three things: the view root read its markup size ahead of the script's; the assigned size wrongly replaced the alignment baseline; and it was committed in the *cancellable* half of the transaction, so with a track playing the resize was thrown away and the compact layout was not |
| W114 | "the track text is shifted up too high" | A script's `fontSize` never reached the drawing (labels measured *and* drawn at 10 pt instead of 7, running "Copyright:" off the left edge of the LCD), and the baseline formula sat 4 px above a box sized by its own glyphs |
| W115 | "the track information does not appear" | `player.network.bitRate` aborted `handlePlayStateChange`, and `player.currentMedia.sourceURL` aborted the function behind it. Both sit before the payload in the same handler |
| W116 | "when you mouse over the compact button there is a huge overlay" | A `BUTTONGROUP` with no normal `image` painted its whole 593x600 hover sheet — dark green surround and all — over the window |

**Two of those were latent traps that only fired once W108 gave the groups a frame**: the duplicate
`mappingColor` (`Dictionary(uniqueKeysWithValues:)` trapped the process — a *crash on load*) and
W116. Budget for that shape whenever a row turns a class of nodes from unresolved into drawn.

## What was ruled out

- **Geometry expressions.** This view declares none, and it carried 63 unresolved nodes anyway. That
  is what ended the expression-cascade theory corpus-wide; see `../harness.md` § *After the cascade*.
- **AppKit and compositing.** Every defect here was scene-side or app-path. No overlay ever painted
  outside its own widget frame on this skin.
- **Missing artwork.** `BITMAPS mainview: resolved=21 missing=` — it has never been missing a file.
- **The remaining 8 unresolved nodes are not a defect.** They are the first of the eight
  duplicate-id `<TEXT>` pairs; the second declaration wins the id and the first is never written,
  which is WMP's own outcome. Do not chase the count to zero.
- **The presets do nothing, and that is not this engine.** A preset reaches `stop` and then the
  skin's own handler, which dies on `player.url` — the stations are cablemusic.com streams from
  2000 that no longer exist.

## How to drive it

`BUTTONELEMENT`s have no frame of their own; decode the `mappingColor` out of the group's bitmap and
add the group's origin. These are already decoded, in `mainview` scene coordinates:

| Control | Scene point | From |
|---|---|---|
| Play | `124,465` | `playButton`'s own frame |
| Shrink (to compact) | `20,436` | `map.gif` `#2eb81c` |
| Expand (from compact) | `21,205` | `Cmap.gif` `#2eb81c` |
| Close / Minimize | `375,105` / — | `map.gif` `#FF0000` |
| Preset 3 (`bnpb2`) | `154,430` | `map.gif` `#FCFF00` |
| Stop | `122,494` | `map.gif` `#7C0000` |
| Presets drawer tab | `384,320` | mapped region of `subProgramsMap.gif` |
| Playlist drawer tab | `384,390` | mapped region of `subPlayListMap.gif` |

```bash
WMP_SKIN=~/Library/Application\ Support/NullPlayer/WMPSkins/Cablemusic.wmz \
  WMP_RENDER_UNRESOLVED=1 WMP_RENDER_CLICK='mainview@124,465' \
  swift test --filter WMPRenderDumpTests/testSweepsSkinOrCorpus
```

**The stations drawer tab is only clickable in the 3 px gaps between the presets drawer's rows.**
Both drawers sit at `178,133` with markup `zIndex="-2"`, so document order puts `subPresets`'
17 `<TEXT>` rows over `subPrograms`' tab, and those rows are hit targets. WMP resolves it the same
way; the skin's own `updateZ()` re-stacks them once a drawer has moved. Not a defect — do not "fix"
it without a screen to point at.

**Live QA on this skin needs a track playing.** Two of its nine defects appear only in the
`psPlaying` branch, and one (W113) appears only when a `status_onchange` transaction is landing five
times a second and cancelling the click's task. A live pass without playback is a different test and
it passed while both were still broken.
