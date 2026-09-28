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

| Id | Item | Reach | Effort | Tier |
|---|---|---:|:---:|---|
| B155 | **A layout that declares no `desktopalpha` keeps per-pixel alpha, which is probably not Winamp's default.** The renderer applies the B114 region rule (painted pixels opaque over black, alpha-0 pixels outside the window) only to `desktopalpha="0"` (`WasabiRenderer.layoutWantsOpaqueBacking`). Winamp most likely gives every layout without `desktopalpha="1"` a region instead of per-pixel alpha, so soft edges and translucent sheens there land on black. B151 met this and scoped around it: its standard-frame backing runs in undeclared layouts, but the alpha promotion does not. Making undeclared mean `0` moves the renders listed at [M34], and none of them has been classified. Some will be fixes (translucent panels floating on the desktop). Some may be regressions, where the corpus relies on the soft edges it has today: drop shadows and anti-aliased silhouettes turning into black fringes. The first job is to confirm Winamp's default from a primary source or a skin's shipped screenshot, then classify the sweep against each skin's own artwork | 92 of 671 renders, 44 skins [M34] | M | Measured |

### Live-reported draw defects

| Id | Item | Reach | Effort | Tier |
|---|---|---:|:---:|---|
| B147 | **The library window follows the main window's height in a `.wal` session.** `toggleHideTitleBars` (`App/WindowManager.swift:511`) resizes the side-docked library and projectM windows by the main window's height delta — Original centre-stack behaviour. Its guard `isRunningModernUI` (`:390`) does not name `WinampModernMainWindowController`, so `.wal` falls through to the stale `isModernUIEnabled` preference. **Gate the resize itself on the mode; do not add the controller to the predicate**, whose other callers would all inherit the answer. Classic and Original byte-identical. The `.wmz` half is W237 in [`WMP_TASKS.md`](WMP_TASKS.md) | every `.wal` session with the library open | S | Live-reported |
| B158 | **Closing a `.wal` hosted window slides the window below it up, and the closed one reopens on top of it.** Measured 2026-09-28 while closing B156, on Itemskin at 100%. With the Spectrum Analyzer tiled at top-left y=704 and the Waveform under it at y=915, closing the analyzer from the Windows menu moves the Waveform up to y=704. Reopening the analyzer puts it back at its remembered y=704, exactly over the Waveform. The move is the host's: `hostedWindowVisibilityDidChange` (`App/WindowManager.swift:1826`) calls `slideUpWindowsBelow` on every hosted close, although `handleCenterStackWindowWillClose` skips it for `.wal` and `.wmz` because those windows reopen where they were left (`components.md`). B154's slot release does not help, because the slide is not a placement and never calls `releaseClosedWindowSlots(under:)`. Whether the fix is to skip the slide for `.wal` or to release the slot the slide gives away is not decided. Reproduce with `WINAMP_MODERN_PLACE_TRACE=1 skills/app-control/scripts/launch.sh Itemskin`: open Spectrum Analyzer then Waveform, close Spectrum Analyzer, reopen it, and read `winhelper windows` | every `.wal` session that closes a hosted window with another under it | S | Agent-measured |

### Awaiting manual QA

| Id | Item | Remaining check |
|---|---|---|
| B41 | `getMonitorWidth` / `getMonitorHeight` | Needs a second display. Load Big Bento Modern, move the player to it, open the right-side playlist and toggle **Enlarge Playlist**; the column must size against the player's display, with no 2x oversizing on Retina. Repeat back on the primary display |
| B85 | The Widgets Manager's three place buttons | On a cPro skin: drawer menu -> *Widgets Manager*, then **show in main / drawer / side** on a row. Uninstall and support are expected to stay inert |
| B66 | The Wasabi drop-down's persistence | On Styx's Config, pick a `Position` drop-down entry, reopen the window, confirm the pick survived |
| B110 | Ebonite's frame overlay windows ([record](docs/winamp-modern/backlog-archive.md#b110--a-skins-window-frame-can-be-a-second-window--implementation-record)) | Reporter's confirmation that Ebonite's frames draw, stay glued and stack correctly |

## Agent-verifiable without user input

Triaged 2026-09-27 against the `app-control` tools: `launch.sh`, `winhelper`
(`click`/`dblclick`/`drag`/`move`/`scroll`/`clickdiff`/`capture`/`screens`), `menu.applescript`,
the window census and the render-dump harness. The ranking above still sets the order.

B158: the repro is the Windows menu and `winhelper windows`, and both halves of the fix read back
from `[place]` lines.

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

- <a id="m34"></a>**M34:** in `WasabiRenderer.layoutWantsOpaqueBacking`, temporarily return `true`
  when `desktopalpha` is absent, then run `scripts/wal_render_sweep.sh capture <curr> --allow-dirty`
  and `compare` it against a capture of the unmodified tree. Leave out the four byte-identical
  re-adds. Measured 2026-09-28 at `7331c363`: **92 of 671 images in 44 skins** changed. Diablo has 6;
  PokemonDS, jvc.tape.v0.5 and Core-X5 have 5 each; Wiimote has 4. The rest are spread thin,
  including 13 cPro skins' main, shade and notifier windows. Anexa's 3 include its analog clock,
  which differs from run to run.


## Backlog hygiene check

Run before committing backlog changes:

```bash
scripts/validate_winamp_modern_backlog.sh WINAMP5_TASKS.md
```
