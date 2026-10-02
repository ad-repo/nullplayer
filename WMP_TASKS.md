# Windows Media Player (`.wmz`) — open backlog

The only live backlog for the WMP skin subsystem, and a list of open rows — nothing else. Read
`skills/wmp-skin-guide/SKILL.md` before picking anything up.

- `.wal` work goes in [`WINAMP5_TASKS.md`](WINAMP5_TASKS.md); the shared video path goes in
  [`docs/video-playback/backlog.md`](docs/video-playback/backlog.md) (read V1 before any `.wmz` video work);
  the local library and the playlist-playback path go in
  [`docs/local-library/backlog.md`](docs/local-library/backlog.md) (**read L1 before any report that a
  skin "won't play" something** — an unreadable track halts the playlist and says nothing in WMP mode).
- Closed rows move to [`docs/wmp-skin/wmp-backlog-archive.md`](docs/wmp-skin/wmp-backlog-archive.md)
  in the change that closes them. That file's § *Issuing a number* holds the next free number.
- A row with a defect in the row itself goes to [`LOW_QUALITY_TASKS.md`](LOW_QUALITY_TASKS.md);
  re-measure before reviving anything from it.
- Retired tier prose and post-mortems of closed rows:
  [`docs/wmp-skin/wmp-backlog-notes-archive.md`](docs/wmp-skin/wmp-backlog-notes-archive.md).

**Every Reach below is authored demand, not result, and several are stale — re-measure a row before
taking it**, especially one whose evidence predates a change to the same subsystem. `harness/instrument.md`
§ *Numbers that are void, and why* lists which classes of count must be re-derived; a corpus number
taken with bare `grep` is not a corpus number. Only a dumped PNG or a `SCRIPT-DIAG` line sees a
rendering defect, and no headless instrument here reaches a hover, drag, tab, scroll or playing
state — that work needs the live loop (`skills/live-ui-testing`, `harness.md` § *Debugging a live
defect*).

## Script runtime

| ID | Item | Reach | Notes |
|---|---|---|---|

Do not add a name to `handlerNames`/`supportedEvents` without its dispatch site — `object-model/classification.md`
§ *Recognising an event is not dispatching it*. Candidate gaps already disproved (incl. the author-typo
list) are in that file § *Verified **not** gaps*; `INERT` members are § *Recognised, answered, and
nothing behind them*.

## Drawing the skin's own controls

| ID | Item | Reach | Notes |
|---|---|---|---|
| W316 | A keyed window's outline is a hard 1-bit staircase with a pale fringe | **Reported live 2026-10-01** on `BlueCrush_MP7` while the skin-window drop shadow was in review ("the edges look rough still, do they need anti aliasing?"). Measured on a 2x screen capture of its left edge: the outline steps one skin pixel at a time (two device pixels), and the outermost kept pixel is the artist's anti-aliasing against a light background — `(247,235,244)` beside the body pink `(239,205,222)`. **The wide white ring seen in the same report was not this** — it was the shadow's own knockout clearing under the skin's faint alpha halo, fixed in `SkinWindowShadow.knockoutAlpha`; re-capture with that fix in before measuring the fringe. Every skin cut by `transparencyColor`/`clippingColor` is cut this way, so the reach is most of the corpus; **not counted** | Two causes, both in the render path, not the shadow. (1) The key is binary — a pixel is kept or removed — and keyed artwork is drawn with `interpolationQuality = .none` (`WMPRenderer.swift`), so the cut is aliased at skin resolution and then doubled at 2x. (2) The key matches only the exact key colour, so a one-pixel edge blended toward it stays opaque. Real WMP drew 1-bit window regions too; this is beyond-WMP polish, not a compatibility defect. **Direction:** after keying, feather the window's alpha about one skin pixel along the boundary only (interior untouched), and decontaminate those edge pixels toward their inner neighbour's colour so the fringe fades with them. **Expect a sweep diff on nearly every skin's outline**, so judge each against its artwork, and keep `WMPRenderer`'s alpha compare (`alphaChanged`, the effects silhouette) and the `SkinWindowShadow` binarized knockout consistent with the feathered alpha. **First step:** prototype on `BlueCrush_MP7` and `corona` and compare 2x captures of the edge before and after. |

## NullPlayer's own windows beside a skin

| ID | Item | Reach | Notes |
|---|---|---|---|

## Harness and tooling

Rows that make the harness cheaper to use or harder to misuse. Reach is agent effort and the
wrong-answer risk a script removes, not skins. Filed 2026-09-24 from the token-relief pass that split
`SKILL.md` into `reference/` and added `baseline_worktree.sh`, `wms_grep.py`, `png_diff.py`,
`wmp_corpus.py` and `winhelper raise|capture|capture-all`.

| ID | Item | Reach | Notes |
|---|---|---|---|

## Found during `.wmz` work, owned elsewhere

| ID | Item | Reach | Notes |
|---|---|---|---|
| W276 | A second NullPlayer instance stops a Sonos room it no longer owns | **Measured 2026-09-24** while investigating W271 (archived): with NullPlayer on another Mac still casting to **Dining Room**, a cast from this Mac stopped ~45 s in on every run — current build, the pre-main-merge build `32b20b85`, and the 2026-09-20 build `bf8d15f5` alike — and played through the moment the other Mac stopped casting. The other instance's log was not captured, so **what it sent and why always ~45 s in is unmeasured** | Not blocked, and **not a `.wmz` defect** — owned by `sonos-casting`. Nothing in `Casting/` notices that another controller has replaced its stream: `UPnPManager` never reads the renderer's `TrackURI`/`CurrentURI` back, so a displaced instance keeps its session and keeps acting on the room, and the displacing instance then reads the resulting `STOPPED` as "ended externally" and pauses. **Direction:** on each poll, compare the renderer's current URI with the one this session set; on a mismatch, drop the session quietly (return to a stopped local state, no SOAP to the room). **First step:** reproduce with two instances against one room and capture the *displaced* instance's log around the stop — that names the command. |

## Known hole

**The 2026-09-08 live-QA list was never captured** — the reporter drove Phase 5, reported "tons of
issues", and the list was lost, so every Phase 5 closure in the archive is harness-verified only.
Capture a reporter's list before ranking further Phase 5 work. What Phase 6 recovered is
`harness-history.md` § *After Phase 6*.
