# Video playback — open backlog

The two existing backlogs in this repo are skin engines: [`WMP_TASKS.md`](../../WMP_TASKS.md) for
`.wmz` and [`WINAMP5_TASKS.md`](../../WINAMP5_TASKS.md) for `.wal`, and each says a foreign entry
does not belong in it. This file is for defects in the **shared video path** — `Windows/VideoPlayer/`
and the browsers that feed it — which belong to neither and were previously getting lost in
conversation. Owning skills: `plex-integration` for the browser, `ui-guide` for the window.

Same conventions as the skin backlogs: one row per reproducible defect, the evidence it was ranked
on, and **what is measured kept separate from what is inferred**. A closed row moves out with the
change that closes it.

## Open

| ID | Item | Evidence | Notes |
|---|---|---|---|
| V1 | A playing film is silently re-opened from the start, and the reload hangs | **Two occurrences in one 6-minute session**, 2026-09-10, log `WMP_TRACE_INPUT=1` run against `Cablemusic` + a Plex movie | **The reporter performed no action in the Plex Browser, saw no reload, and describes the result as the video being "just hung" / "stuck on reloading".** The log disagrees with the *appearance* and not with the report: at 12:06:59 and again at 12:09:36, `PlexBrowserView.playMovie` logged `Playing movie: Airplane!`, `PlexVideoPlaybackReporter` logged `Video stopped at 1455.5s (finished: no)` and `at 2286.5s (finished: no)`, the same Plex URL was re-opened, and the reporter posted `state 'playing' at 0ms`. So the film really is torn down and restarted from zero — **24 and 38 minutes of position discarded** — while the user sees only a picture that stops. There is no visible reload because the teardown and re-open happen behind a video surface that does not repaint, which is exactly why this went unreported for so long and was first misread (by me) as VLC buffering. **What is measured:** the restart, its source symbol, and the discarded positions. **What is not:** what invoked it. `playMovie` is `private` to `PlexBrowserView` with three callers — `contextMenuPlayMovie`, `contextMenuPlayMovieAndReplace`, and the `case .movie(let movie): playMovie(movie)` arm of the row-activation switch — so a **row activation is firing without a user gesture** and that is the thing to find. First suspects are an `NSTableView` double-action or activation arm reached by a programmatic selection or a list refresh while a row is selected; the browser was open with `Airplane!` selected throughout. **Instrument first**: log `Thread.callStackSymbols` at `playMovie` entry and reproduce — the caller ends this in one line, and everything above it is inference. **Ruled out:** play/pause and window dragging. A clean session drove six consecutive play/pause toggles and a full window drag with **one** `Playing movie:` and no spurious restart. **Do not fold this into W124** (`videoend` without `videostart`): W124 is about the skin's own state after a legitimate media change, and would still be a defect if this row never happened. |
