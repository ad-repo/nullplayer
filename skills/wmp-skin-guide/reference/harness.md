# The `.wmz` harness — canonical probe reference

**This file is the only place a `.wmz` probe flag or corpus command is documented.** Every other
file, comment and handoff points here and never restates a command. When you add a flag, add it
here in the same change.

Everything below runs headlessly through `swift test`. Nothing here is compiled into the app.

---

## Why the harness exists

Structural and load-time cleanliness measure almost nothing. The `.wal` subsystem paid for that
first: *a vertical-flip and a wrong crop origin survived 490+ green tests because nothing ever
rendered a frame.* `.wmz` reached 6,044 lines of engine with every real-skin test `XCTSkip`ped, so
`swift test` stayed green while 4 of 14 corpus archives were being rejected outright.

So: **you cannot rank work you cannot measure**, and a probe is not trusted about an absence until
it has been shown reporting a presence.

---

## Where the rest of the harness lives

Split out of this file by topic on 2026-09-25, sections moved verbatim. A reference to
`harness.md` § *<section>* names a section that now lives in the file this table gives for it.

| File | Sections it holds |
|---|---|
| [`harness/corpus.md`](harness/corpus.md) | *The corpus*: what is measured, why a `grep` count is not a corpus number, counting a tag |
| [`harness/probe-flags.md`](harness/probe-flags.md) | *The probe flags* the test probe reads (`WMP_SKIN`, `WMP_RENDER_*`, `WMP_CALL_TRACE`, `WMP_HOSTED_FRAME*`) |
| [`harness/app-flags.md`](harness/app-flags.md) | The rest of that table: DEBUG-app traces (`WMP_CLICK_TRACE`, `WMP_SCRIPT_TRACE`, `WMP_RESIZE_TRACE`, …) and the A/B kill switches |
| [`harness/app-probes.md`](harness/app-probes.md) | *The probes that are not in the test binary* |
| [`harness/live-loop.md`](harness/live-loop.md) | *Driving the app*: capturing hosted windows, auditing a control corpus-wide, a live pass as a frame, numbering transactions, measuring reach |
| [`harness/sweep-limits.md`](harness/sweep-limits.md) | Per-frame cost, tweens, GIF entry, a stopped player, named skins, `OCCLUDED` residue, absences, repros, flat dumps, `gaps=`, the sweep as arbiter, nondeterminism, attributing a report, baseline worktrees |
| [`harness/line-grammar.md`](harness/line-grammar.md) | *The line grammar*, *Input and tooltips the markup authors* |
| [`harness/scripts.md`](harness/scripts.md) | *The committed scripts* (census, markup census, `wms_grep`, control audit, `png_diff`, baseline worktree, exclusions, slider-drag, implicit key, handler scope, render sweep) and *Traps the scripts enforce* |
| [`harness/instrument.md`](harness/instrument.md) | Driving the GUI yourself, why an instrument gap outranks a skin defect, *Numbers that are void, and why*, *Proving the instrument* |

## Flag index

Every flag in the probe-flag table, by the file that holds its row. Probes outside the test binary are in [`harness/app-probes.md`](harness/app-probes.md).

- [`harness/probe-flags.md`](harness/probe-flags.md): `WMP_SKIN`, `WMP_RENDER_DUMP`, `WMP_RENDER_PROBE`, `WMP_RENDER_BITMAPS`, `WMP_RENDER_OCCLUDED`, `WMP_RENDER_UNRESOLVED`, `WMP_RENDER_LIMITS`, `WMP_RENDER_SCRIPTS`, `WMP_RENDER_EXPR`, `WMP_CALL_TRACE`, `WMP_RENDER_CLICK`, `WMP_RENDER_HOVER`, `WMP_RENDER_APPKIT`, `WMP_RENDER_SETTLE`, `WMP_RENDER_CLOCK`, `WMP_RENDER_HOST`, `WMP_RENDER_SIZE`, `WMP_HOSTED_FRAME`, `WMP_HOSTED_FRAME_SCALE`
- [`harness/app-flags.md`](harness/app-flags.md): `WMP_CLICK_TRACE`, `WMP_SCRIPT_TRACE`, `WMP_RESIZE_TRACE`, `WMP_BORDER_TRACE`, `WMP_VIDEO_TRACE`, `WMP_TWEEN_TRACE`, `WMP_VIEW_SCRIPT_SCOPE`, `WMP_LOAD_TWEENS`, `WMP_FRAME_TRACE`, `WMP_FRAME_APPEARANCE`, `WMP_STRIP_TRACE`, `WMP_HOSTED_FRAME_DUMP`, `WMP_FRAME_PRIME`, `WMP_HOSTED_PREWARM`, `WMP_HOSTED_PRESIZE`, `WMP_FRAME_STANDIN`, `WMP_FRAME_LIVE_RESIZE`, `WMP_HOSTED_HOLD`, `WMP_HOSTED_HOLD_MS`

## Past measurements

The dated corpus measurements — what each phase and each class closure measured, rev by rev, from
*What the harness measured on 2026-09-07* to *The transport audit* — are in
[harness-history.md](harness-history.md). They are the baseline a later claim is checked against,
not instructions; read the one a backlog row or a dossier cites.
