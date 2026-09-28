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
| B157 | **A window opened from the menu can land well below the window above it.** Measured 2026-09-28 while closing B154, on Sony_Walkman at 100%. `tiledOrigin(for:avoiding:)` walks slots in the opening window's own height, starting under the player, and takes the first one clear of what is on screen. With the equalizer (164pt) open under the player, the playlist (145pt) tried y=399, then y=544, which still overlaps the equalizer, and landed at y=689: 126pt below the equalizer's bottom edge. With the playlist open first, the equalizer landed 19pt below it. The launch sweep and Snap To Default stack flush, because they tile every window in one pass; only a later open walks. A likely fix is to make the next candidate slot start at the bottom edge of whatever the last candidate hit, instead of stepping in the new window's own height. The walk is shared with `.wmz`. Reproduce with `WINAMP_MODERN_PLACE_TRACE=1 skills/app-control/scripts/launch.sh Sony_Walkman`: close every window, open Equalizer, then Playlist Editor from the Windows menu, and read `winhelper windows` | every `.wal` session that opens a window from the menu while another is open | S | Agent-measured |
| B156 | **An Itemskin script puts a tiled window back where it was, mostly below the screen.** Measured 2026-09-28 while closing B153. Itemskin (B69) pins a frame window over each component window. With the playlist, Media Library, Spectrum Analyzer and Waveform open, Windows → UI Size → 150% tiles the library at `{762, 258}`. The next line in the trace is `[place/script] o247 -> {0, -69} (was {762, 258})`: the skin's own `resize()` moves it to its pre-tile origin, with 69pt of its 206pt below the visible frame. Opening the Spectrum Analyzer from the menu at 100% does the same (`o337 -> {0, -74}`). The pinned pairs stay glued, so it is the pair that moves. Not established: whether the script is replaying a position it read before the tiler ran (compare the `onMove` write-back in `reference/scripting.md`) or doing its own arithmetic, and whether Winamp would park it there too. Reproduce with `WINAMP_MODERN_PLACE_TRACE=1 skills/app-control/scripts/launch.sh Itemskin`, toggle those windows from the Windows menu, set UI Size to 150%, and read `winhelper windows` | 1 skin measured | S | Agent-measured |

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

None open.

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
