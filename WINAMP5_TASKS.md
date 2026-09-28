# Winamp 5.x Modern Skins (`.wal`) — ranked open backlog

This is the only live backlog for the Winamp Modern subsystem. A skin is a test case, not a
milestone: take measured capability work from the top down. Closed entries move to
[`docs/winamp-modern/backlog-archive.md`](docs/winamp-modern/backlog-archive.md) in the same change
that closes them. A row that is stale, a question rather than work, or self-described as not worth
doing moves to [`LOW_QUALITY_TASKS.md`](LOW_QUALITY_TASKS.md). This file holds tasks; how the engine
works belongs in `skills/winamp-modern-skin-guide/`.

## Ranking

Measured items are ordered by reach, with effort as an advisory tiebreaker. Reach is corpus demand,
not severity. Live-reported draw defects are kept in their own tier because a screenshot or runtime
observation is not comparable to a static declaration count.

Effort bands: **S** = one attribute/method/local draw fix; **M** = behavior spanning multiple files
without a seam change; **L** = a host seam, protocol change, or new fixture harness.

### Measured capability gaps

None open.

### Live-reported draw defects

| Id | Item | Reach | Effort | Tier |
|---|---|---:|:---:|---|
| B152 | **WMP11-BlueVU still costs ~10 points more main thread than cPro-Bento, all of it the VU needle warp.** Release, *VU Meters Large* open, music playing: 42.0% busy against cPro-Bento's 31.8%, with `drawWarped` at 18.0%. The visible meter re-warps both needles at the skin's own ~100 Hz, under the 120 Hz display. The main window's whole-window repaint is fixed (2026-09-28, `gotoframe` repaints the layer's own rect; the player now paints 25% of its area instead of 100%). What is left is making the warp cheaper per frame. Throttling it below the skin's cadence would give up visible smoothness, so that is a decision for the user, not a fix. Method: [`performance.md`](skills/winamp-modern-skin-guide/reference/performance.md) *A beat meter repainted the whole player* | 1 skin measured | M | Live-reported |
| B147 | **The library window follows the main window's height in a `.wal` session.** `toggleHideTitleBars` (`App/WindowManager.swift:511`) resizes the side-docked library and projectM windows by the main window's height delta — Original centre-stack behaviour. Its guard `isRunningModernUI` (`:390`) does not name `WinampModernMainWindowController`, so `.wal` falls through to the stale `isModernUIEnabled` preference. **Gate the resize itself on the mode; do not add the controller to the predicate**, whose other callers would all inherit the answer. Classic and Original byte-identical. The `.wmz` half is W237 in [`WMP_TASKS.md`](WMP_TASKS.md) | every `.wal` session with the library open | S | Live-reported |
| B151 | **A gap between the VU face and the frame in WMP11-BlueVU's VU Meters window.** Reported 2026-09-28 from the live session. With *VU Meters Large* open (`Meter`, 438x207), a light band shows between the meter artwork (`scale` at 10,27 and the needles) and the window's `Wasabi:StandardFrame:NoStatus`, most visible along the top and left edges. The meter should sit flush against the frame. The likely cause is the frame's client area and the layer's absolute x/y disagreeing, or the frame drawing an inset the skin does not expect. Not yet measured. Reproduce with `WINAMP_MODERN_SHOW_WINDOWS=Meter`, or headlessly with `RENDER_SHOW=Meter`, and compare against the skin's `vuscreenshot.png` | 1 skin reported | S | Live-reported |
| B80 | **Horizontal seams at fractional UI Sizes.** Hairlines along band boundaries on cPro at 105%. Affects exactly the sizes fractional at 2x backing (90/105/110/115/125/135/175). See [detail](#b80) | 7 of 13 UI Sizes; every skin ([M25]) | M | Live-reported |

### Awaiting manual QA

| Id | Item | Remaining check |
|---|---|---|
| B41 | `getMonitorWidth` / `getMonitorHeight` | Needs a second display. Load Big Bento Modern, move the player to it, open the right-side playlist and toggle **Enlarge Playlist**; the column must size against the player's display, with no 2x oversizing on Retina. Repeat back on the primary display |
| B85 | The Widgets Manager's three place buttons | On a cPro skin: drawer menu -> *Widgets Manager*, then **show in main / drawer / side** on a row. Uninstall and support are expected to stay inert |
| B66 | The Wasabi drop-down's persistence | On Styx's Config, pick a `Position` drop-down entry, reopen the window, confirm the pick survived |
| B110 | Ebonite's frame overlay windows ([record](docs/winamp-modern/backlog-archive.md#b110--a-skins-window-frame-can-be-a-second-window--implementation-record)) | Reporter's confirmation that Ebonite's frames draw, stay glued and stack correctly |
| B111 | Itemskin's silenced audio ([record](docs/winamp-modern/backlog-archive.md#b111--an-unchanged-setactivated-dispatched-ontoggle--implementation-record)) | The persisted volume is `0.00` residue: raise it once, confirm it holds through a drag and a relaunch, and that playback is audible |
| B56a | Window tiling follow-ups | A skin whose playlist is a classic fallback; a Classic/Original regression pass; the arrangement after a live UI-Size change (expect `arrangeWindows()` to need re-running) |

## Agent-verifiable without user input

Triaged 2026-09-27 against the `app-control` tools: `launch.sh`, `winhelper`
(`click`/`dblclick`/`drag`/`move`/`scroll`/`clickdiff`/`capture`/`screens`), `menu.applescript`,
the window census and the render-dump harness. The ranking above still sets the order.

| Id | What the agent can do alone | How it is verified |
|---|---|---|
| B80 | Add a partial-repaint mode to the harness, then fix the seam | Count partial-alpha rows at a fractional scale; live: set UI Size from the menu, `move` over controls, `capture` |
| B152 | Make `drawWarped` cheaper per frame at the same rate | Hands-off release `sample` of WMP11-BlueVU against cPro-Bento, recipe in `harness.md` *Driving a release run without the reporter* |
| B111 | Drag the volume up, relaunch | Persisted volume ≠ 0 after relaunch, and the log shows no `setvolume(0)` cascade (audibility is not checked) |
| B56a | The three tiling checks | `windows` geometry before and after a UI-Size change from the menu bar; Classic/Original census rows unchanged |

**Partly verifiable.** B147: the fix is autonomous, but *Hide Title Bars* is only in the context
menu, so the live toggle is Route D. B66 and B85: the drop-down and the drawer menu may be
contextual menus; if a synthetic press does not open them, they are Route D.

**Needs the user.** B41 needs a second display (`winhelper screens` shows one). B110 waits on the
reporter's confirmation.

## Reproducible reach commands

All commands use the directories extracted with `7zz` from
`~/Library/Application Support/NullPlayer/WinampModernSkins/` (excluding `ClassicProEngine`). Set
`corpus=/path/to/the/extracted/root`.

**The corpus is 80 `.wal` archives as of 2026-09-27**, so an `[M##]` measured against an earlier
count is not comparable to a new one. **Four are byte-identical re-adds** of installed skins —
`pure_inspired_for_winamp_by_marisa85_d35ix2r` = `Pure Inspired`,
`k_jr_winamp_skin_by_marisa85_d329ymw` = `K-jr`, and the two `dewytears_v2_5_by_dewytear_d2yn025_*`
= `DewyTears_{Pink,Black}GlassV2.5` — so exclude them from any per-skin count.

A command lives here only while an open item cites it; closing the item moves the command into its
archive entry.

- <a id="m25"></a>**M25:** device scale is UI Size x the display's backing factor, so on a 2x panel the fractional stops are 90, 105, 110, 115, 125, 135 and 175 % — 7 of the 13 `UIScaleLevel` cases. To check a *full* draw, `WINAMP_MODERN_RENDER_SCALE=<factor> WINAMP_MODERN_RENDER_DUMP=/tmp/s WINAMP_MODERN_WAL=<skin> swift test --filter WinampModernRenderDumpTests`, then count rows whose alpha is strictly between transparent and opaque.

## Item detail

### B80

- [ ] **B80. Horizontal seams at fractional UI Sizes.** A *full* draw is clean at 2.0 and 2.1 device
      scale (zero partially-transparent rows), so the defect is the **targeted-repaint** path:
      `draw(_:)` clears `dirtyRect` and redraws clipped to it, and a partly-cleared boundary row keeps
      a hairline until a full repaint. Backing-aligning the invalidation rect in `setNeedsDisplay(_:)`
      was tried and did not cure it. Suspect the hosted surfaces, which are real `NSView` subviews
      with their own invalidation. The cPro2 "clicking recolours a region" report was a different
      defect (closed); do not re-chase the region-scale probe. The harness has no partial-repaint
      mode, which is most of this task ([M25]).

## Backlog hygiene check

Run before committing backlog changes:

```bash
scripts/validate_winamp_modern_backlog.sh WINAMP5_TASKS.md
```
