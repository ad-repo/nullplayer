# Winamp 5.x Modern Skins (`.wal`) — open backlog

This is the only live backlog for the Winamp Modern subsystem. A skin is a test case, not a
milestone. Closed entries move to
[`docs/winamp-modern/backlog-archive.md`](../docs/winamp-modern/backlog-archive.md) in the same change
that closes them. A row that is stale, a question rather than work, or self-described as not worth
doing moves to [`LOW_QUALITY_TASKS.md`](LOW_QUALITY_TASKS.md). This file holds tasks; how the engine
works belongs in `skills/winamp-modern-skin-guide/`.

**The work is the *Corpus plan queue* below, top down**, by the loop in
[`docs/winamp-modern/corpus-runner-plan.md`](../docs/winamp-modern/corpus-runner-plan.md):
implement, re-measure, close into the archive. No new instruments.

## Columns

Reach is corpus demand, not severity. Live-reported draw defects are kept in their own tier because a screenshot or runtime
observation is not comparable to a static declaration count.

Effort bands: **S** = one attribute/method/local draw fix; **M** = behavior spanning multiple files
without a seam change; **L** = a host seam, protocol change, or new fixture harness.

### Measured capability gaps

| Id | Item | Reach | Effort | Tier |
|---|---|---:|:---:|---|
| B213 | **No tooltip ever shows in Winamp Modern mode.** The view sets no `toolTip` and the host never builds the skin's tooltip window, so a control's `tooltip=` is never shown and the stock `tooltips.m` (`tipText.onTextChanged`, which places the tip with `getViewport*FromPoint`, B195) never runs. Found running B195's in-app check on Shield_Amp: hovering the play button for 2 s shows nothing. Winamp shows the skin's `wasabi.tooltip.group` (or its own default) at the pointer after a hover delay and sets its `tooltip.text`. Done when hovering Shield_Amp's play button shows its tip, drawn by the skin's group, on the pointer's display | `xml-attr '@tooltip$'`: gold 47/56, silver 47/54, bronze 740/827, quarantine 48/54 (manifest 9e68ffe0); the stock tooltip script, `maki-call '[.]getviewportleftfrompoint$'`: gold 13/56, silver 3/54, bronze 9/827, quarantine 4/54 | L | 2 |
| B215 | **A skin's own playlist-editor group is never built; the host's list fills the playlist component instead.** The Bio-Nid lineage defines `pledit.main.group` (the editor, the `pledit.poppler` splitter, the sidecar tab sheet, `scripts/playlisteditor.maki`), and the layout's content is the playlist component `guid:{45F3F7C1-A6F3-4ee6-A15E-125E92FC3F8D}`. In NullPlayer the component is the host's list, so the group, its script and the poppler never exist (venom: no `pledit.poppler` call in the trace with the playlist open). Bio-Nid itself pulls the group from `@DEFAULTSKINPATH@`, which no archive ships. Found running B182's and B198's in-app checks, which this blocks. First establish what Winamp's playlist component does with a skin-defined `pledit.main.group`, then decide whether the host instantiates it around its list | skins shipping `playlisteditor.maki` (zip listing): gold 3/56, silver 2/58, bronze 20/827 | L | 2 |
| B244 | **A layout hidden during a UI Size change never hears `onScale`.** B239 sends `onScale(newScale)` only to containers whose window is visible, so a container shown afterwards keeps whatever it sized from the old `getScale()` (a monitor-mode fill computed at 100% reopens 135% too big). Establish from Wasabi's `Layout::setRenderRatio` whether a hidden layout is told; then either dispatch to every live layout, or dispatch on show when the scale moved while it was hidden. Done when a test pins the hidden-layout case to Wasabi's answer and Nitrous monitor mode, hidden across a 100% → 135% change, fills the screen when shown again | `maki-event '[.]onscale$'`: gold 25/81, silver 5/29, bronze 100/827, quarantine 7/54 (manifest 9e68ffe0+dirty) | S | 2 |
| B245 | **NullPlayer's own playlist window runs off the screen when UI Size changes under a screen-filling skin.** Found verifying B239: Nitrous_Audio_CTI_2_Glass declares no playlist surface, so the classic playlist window is tiled under the player at the player's width (1800 at 100%). Windows → UI Size → 135% scales it by the ratio to 2455×196 while the player, re-fitted by its `onScale`, is back at 1800×1130 — the playlist hangs 655 pt past the right edge. Before B239 the player overflowed with it. Establish whether `applyDoubleSize`'s ratio scaling or `arrangeWinampModernScene` should size a hosted window against the player's *new* frame, then make it so. Done when the same 100% → 135% step on Nitrous leaves the playlist inside the screen and as wide as the player, and the window census is unchanged at 100% | live: Nitrous_Audio_CTI_2_Glass monitor mode at 135% (2026-10-22) | S | 2 |
| B267 | **The Media Library and hosted windows keep the active selection colours when their window loses focus.** #603 made the rows the renderer draws (playlist panel, colour-theme picker, `<list>`) swap in the skin's `wasabi.list.text.selected{,.background}.inactive` pair through `rowPalette` / `WasabiPalette.unfocused()` (`colour.md`). NullPlayer's AppKit surfaces get a `WinampModernSurfaceStyle` built from the plain `palette` once, on a palette change (`WinampModernLibrarySurfaceView.applyPalette`, `WinampModernMainView` `librarySurfaces`, hosted windows), and nothing re-applies it on key/resign, so the library next to a dimmed playlist panel stays in the active colours. Build each surface's style from its own window's focus (`palette.unfocused()` when not key), re-apply it from the existing key/resign observers, and make sure the style's selected-text guard measures the inactive bar. Done when, on iTunes Miniplayer, clicking away from the player dims the library's selection the same way it dims the playlist panel, and a skin that declares neither id is unchanged | zip scan of the archives' XML for either id (raw archive counts, duplicates included): gold 71/106, silver 26/33, bronze 391/802, quarantine 29/54 | M | 2 |
| B282 | **Silverskin_3's frame titles are wider than their windows, so centred they lose both ends.** Split from B275 (intake #4). `ctitlebar` is `<text align="center" font="sk3.component.font.tb">` in a group `x="30" w="-30" relatw="1"`; the bitmap font is `charwidth="23" hspacing="-3"`, a 20px advance, so `PLAYLIST EDITOR` is 300px in Pledit's 215px box at its 275 minimum and `SILVERSKIN3 HELP` is 320px in the help window's fixed 250 (box 190): `AYLIST EDITO`, `VERSKIN HE`. No rule can draw them whole inside the window; the open question is what Wasabi shows for centred text wider than its box (both ends cut, as now, or left-anchored), and whether the groupdef's `autowidthsource="titlebar"` beats the instance's `w`. `screenshot.png` shows only the player. Done when a reference (a gold skin's screenshot of a centred overflowing string, or the user's verdict at the UI round) settles the rule and the dump follows it, gold+silver otherwise unchanged | intake #4: Silverskin_3 (silver) | S | 2 |
| B277 | **MultiButtons_v0.02's equalizer shows no sliders, only a `0 0000000000` digit row.** Batch dump `eq/normal` against its `screenshot`. Probe `eq/normal` for the band sliders' bitmaps and visibility. Done when the dump draws the sliders the screenshot shows | intake #4 dump: MultiButtons_v0.02 (silver) | S | 2 |
| B278 | **WINyaMP3's thinger icons draw under its arrow art.** Batch dump against its `screenshot`: the thinger's icon strip is drawn below the arrow layer instead of over it. Establish the draw order the skin declares (group order vs the thinger component's own icons), then fix. Done when the dump's thinger matches the screenshot and no gold+silver render changes otherwise | intake #4 dump: WINyaMP3 (silver) | S | 2 |
| B241 | **`getXmlParam` after `resize()` answers the moved geometry; after a target animation it answers the declared one.** A target animation keeps the XML value in `WasabiObject.declaredXMLParams` (Alpha Media Player X5's levers, `scripting.md`, *A target animation moves the object, not its XML*), but `resize()` writes through `writeGeometry` and overwrites it, so what `getXmlParam("x"/"y"/"w"/"h")` answers depends on how the object moved. Establish from Wasabi's `GuiObject::resize` whether it writes the XML params, then make `resize()` agree (route it through `moveForTarget`'s bookkeeping, or document why it differs). Done when a test pins `getXmlParam("y")` after `resize()` to Wasabi's answer and Alpha's EQ and Mute levers still toggle | `maki-call '[.]resize$'`: gold 52/81, silver 18/29, bronze 294/827, quarantine 22/54; `maki-call '[.]getxmlparam$'`: gold 55/81, silver 20/29, bronze 264/827, quarantine 29/54 (manifest 23ad4485) | S | 2 |

### Corpus plan queue — work in progress

Order is the plan's S4 severity ladder, then its `skins × severity × visibility ÷ cost` within a
class. First, skin-dead: the quarantine's loader gaps (B173), most skins first. Then the MAKI demand
queue (B174), by priority, whose scoring is in B174's archive entry. Each severity rests on one or two
call sites, so re-check it when a row is taken.

| Id | Item | Reach | Effort | Tier |
|---|---|---:|:---:|---|
| B212 | **Run B41's in-app check, which needs a second display.** Load Big Bento Modern, move the player to the second display, open the right-side playlist and toggle **Enlarge Playlist**; the column must size against the player's display, with no 2x oversizing on Retina. Repeat back on the primary display. `winhelper screens` shows one display, so this waits on the hardware. The other twenty checks were run 2026-10-20 (archive, *B212*). Done when B41 has a pass, or a filed row for what it found | B41 | S | 2 |
| B216 | **The `.wal` tiler's last-resort placement now moves `.wmz` windows too, and nobody has looked.** `WindowManager.tiledOrigin(for:avoiding:)` is also WMP's placement (`WMPViewWindowMaterializer`, and the `hostsForeignSkin` branch of the sub-window opener), and the tiler behind it now weighs the region's corners and picks the least-covered candidate, with the player counted 4×, instead of rescuing the last slot. Run the window census over the `.wmz` corpus before and after that change (`window-census`), and file any window that moved onto the player or off its old spot for the worse. Done when the census diff is read and every moved window is either accepted or filed. **Deferred 2026-10-20**: the census is a multi-hour machine-takeover run, so it waits for the user's go-ahead. The cleanup that followed it is done: `WinampModernTiler` is a top-level struct in `App/WinampModernTiler.swift`, `leastCovered` weighs a named `player` rect and takes a non-empty candidate list | code health; no corpus demand | S | 3 |
| B247 | **Routing a film to a `.wal` skin does not know about a detached video window.** `hostVideoOutput()` sends an embedded-video skin's picture to the player, so `VideoPlayerWindowController` keeps its own `parkedHost` to bring a detached film back after fullscreen, which puts `.wal` state in a window that is not `.wal`'s. Every other route (a new film starting while detached, for one) goes through the player. Establish what a new film does in Winamp Single GUI while its `Video` window is open, then route `hostVideoOutput()` to the detached window when it is open and delete `parkedHost`. Done when fullscreen exit and the next play both land in the detached window while it is open, and `parkedHost` is gone | live: Winamp Single GUI (2026-10-23) | S | 3 |
| B265 | **Unverified — inferred from a CodeRabbit review of PR #604, never seen in the app. Before any work, triage whether this row belongs in `LOW_QUALITY_TASKS.md` instead.** **Windows → Video Player does nothing while the film is in a detached video window.** `toggleVideo()` calls `hideVideoSurfaceWindow()`, whose embedded branch asks the *player's* `skinView?.hostedVideoSurface`. The detached `Video` window's view holds the box, so the answer is nil and nothing is hidden. `toggleVideo()` ignores the `false` and returns `true`, so `WindowManager` does not fall back. CodeRabbit's fix, `setAuxiliaryWindow(visible: false)`, is the reattach: it would move the film into the player rather than hide it. Reproduce on Winamp Single GUI first (play a film, Detach, toggle the menu item). Done when the toggle's effect on a detached film is decided (hide or reattach) and a test pins it | code review only (PR #604); no live observation | S | 3 |
| B266 | **Unverified — inferred from a CodeRabbit review of PR #604, never seen in the app. Before any work, triage whether this row belongs in `LOW_QUALITY_TASKS.md` instead.** **Closing the detached video window can reopen it.** `setAuxiliaryWindow(visible: false)` on the detached `Video` window reattaches through `hostVideoOutputInPlayer()`. When the player has no holder to take the film (Single GUI shaded), that falls back to `openOwnVideoWindow()`, which reopens the same window, and the outer call then marks its scene hidden while it is on screen (and persists it with `record: true`). Reproduce on Winamp Single GUI first (detach a film, shade the player, close the `Video` window). Done when closing the window with no player holder leaves it closed and its scene state agrees | code review only (PR #604); no live observation | S | 3 |

## Agent-verifiable without user input

Triaged 2026-09-27 against the `app-control` tools: `launch.sh`, `winhelper`
(`click`/`dblclick`/`drag`/`move`/`scroll`/`clickdiff`/`capture`/`screens`), `menu.applescript`,
the window census and the render-dump harness.

**Hardware.** B212 (B41's check) needs a second display (`winhelper screens` shows one). Every
other in-app check is agent work: a contextual menu is `winhelper rclick` plus Accessibility, and a
script-built menu Accessibility does not expose is read with `capture-region` and clicked by position.

## Reach

A measured row's Reach is one query over the static feature index, pasted as printed:

```bash
scripts/wal_reach.sh <kind> <feature-regex>   # -> gold a/A, silver n/N, bronze m/M, quarantine q/Q (manifest <rev>)
```

The manifest rev is the denominator's identity: figures under different revs are not comparable. A
skin is its content, so the four silver re-adds of gold skins count once, as gold. The index is
`WinampModernCorpus/index/features.tsv`; rebuild it over every tier after an intake
(`harness.md` → *The static feature index*), and the script fails on an index the manifest has
outgrown. Code-health and corpus-scale rows have no corpus demand and say so instead. A row whose
Reach needs more than the query (a grep over an extract, a runtime count) keeps that command in its
cell, and the command moves into its archive entry when the row closes.

## Backlog hygiene check

Run before committing backlog changes:

```bash
scripts/validate_winamp_modern_backlog.sh WINAMP5_TASKS.md
```
