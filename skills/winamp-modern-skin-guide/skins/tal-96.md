## TAL_96 (`TAL_96.wal`)

*Per-skin notes, not a graded report. Index: [skins.md](../skins.md) · a full report: `/wal-skin-report <skin.wal>`.*

- **Seen:** 2026-10-25, headless (intake #3).
- **The glass is on top, and not a ghost, by the skin's own markup.** Every player layout ends with
  `<layer id="glass" ghost="0">` (shade: no `ghost` at all) over the songticker and the timer. The
  songticker is `nograb="1"` and no script hooks a press on it, so nothing is lost there.
- **The timer is reachable through the clear part of the glass.** `oldtimer.m` (ThePlague's drop-in,
  "NO xml changes needed") toggles elapsed/remaining from `Timer.onLeftButtonDown`. The glass is fully
  clear over 219 of the timer's 660 pixels in `jeans`/`leather` and 290 of 700 in shade, so a click
  there reaches it (headless: `main/jeans@105,161` sets `Minus` 1, `@110,167` back to 0). The
  `RENDER_CLICKABLE` probe samples only the centre, which in shade is a glass pixel, so it lists the
  shade timer.
