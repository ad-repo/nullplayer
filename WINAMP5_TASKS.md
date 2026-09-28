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
| B153 | **The `.wal` tiler's right-edge clamp pulls a window onto the player.** Measured 2026-09-28 on Sony_Walkman (player centred at x=762 on an 1800pt display, playlist, analyzer and library open). At 125% UI Size the library (688pt wide) gets column 2 at x=1192. That runs past the edge, so `WinampModernTiler.nextSlot` clamps it to x=1112, 69pt over the player and the playlist. At 150% it is 290×159 over the player. Launch, Snap To Default and the B56a UI-Size re-layout all produce the same result. The clamp was chosen over windows placed wholly off-screen (see the comment in `nextSlot`). Covering the player is worse than overhanging the edge, though: a window with most of its width still on screen is reachable and hides nothing. The likely fix is to clamp only as far as reachability needs, or to try the space left of the player first. The tiler is shared with `.wmz` through `tiledOrigin`. Reproduce with `launch.sh Sony_Walkman`, open those three from the Windows menu, then Windows → UI Size → 125% | any `.wal` session with a wide window and a centred player at a large UI Size | M | Agent-measured |
| B154 | **Sony_Walkman's equalizer reopens on top of the playlist.** Seen 2026-09-28 in 3 of 4 debug launches while closing B56a. The launch sweep logs `[place/tile] eq … -> {{762, 606}, …}`, so the skin's declared `eq` container is visible during load, but the Windows menu shows Equalizer unchecked once launch settles. Open Playlist Editor and then Equalizer from the Windows menu: the playlist takes the first slot under the player (top-left y=399), and the EQ comes back at the slot the launch sweep gave it (also y=399), 335×146 over the playlist. It keeps that slot because `reopensWhereLeft` counts the launch placement as a user placement. Not confirmed: what hides the EQ (a skin script or the host), and whether a window that was only visible during load should count as placed at all. Reproduce with `WINAMP_MODERN_PLACE_TRACE=1 skills/app-control/scripts/launch.sh Sony_Walkman`, then toggle the items with `menu.applescript toggle` and read `winhelper windows` | 1 skin measured; the reopen rule is engine-wide | S | Agent-measured |

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
