## intellidesign (`intellidesign.wal`)

*Per-skin notes, not a graded report. Index: [skins.md](../skins.md) · a full report: `/wal-skin-report <skin.wal>`.*

- **Seen live:** 2026-10-25, debug build, playing (intake #3).
- **The visualizer is off on a first run, and that is the skin's own bytecode.** `vis.maki` reads the
  private int `vismode` twice with different defaults: `onScriptLoaded` asks with **1** (shows
  `player.vis`, `setMode(1)`), then `System.onShowLayout`, which Winamp sends after the scripts load,
  asks with **0** and turns it off and hides it. Its `onScriptUnloading` saves whatever the state is,
  so a quit stores 0. The skin's "Normal Vis" menu turns it on, and that choice is then saved.
  Located with `TRACE_MAKI=1` (`MAKI enter player-normal.xml @258`) and `RENDER_DISASM=@player-normal`
  (`--- onshowlayout ---` at 258). The skin's `screenshot.png` shows the vis running, which is the
  author's configured install, not a first run.
- **The EQ is a drawer.** `eq.maki` slides `player.eq` from y=118 (under `layer#Body`) to y=207 on
  `eqtoggle`; the crossfade +/- buttons inside it are reachable only open.
