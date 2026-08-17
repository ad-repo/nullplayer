# Winamp Modern (`.wal`) — Phase 17 Handoff

**For:** the agent picking up Winamp Modern work after Phase 17

**From:** Phase 17 (the MMD3 defect sweep)

**Date:** 2026-08-16

Read first:

- `skills/winamp-modern-skin-guide/SKILL.md` — the durable versions of all four findings live in
  "A bitmap font's `file=` is an id **or** a path", "What a `<text>` shows", "Hit testing: who owns a
  point", and "`<vis mode>`"
- `skills/winamp-modern-skin-guide/compatibility.md` — supported surface for text content, `vis mode`,
  and the hit-test region rule; the oscilloscope's approximation is in *Not supported / degraded*
- `skills/winamp-modern-skin-guide/manual-qa-checklist.md` §1 — three new MMD3 lines, **the open gate**
- `TASKS.md` §17 (local, gitignored) — the step list with the measured root causes

## 1. What Phase 17 was

A GUI bug report against `mmd3.wal`, four symptoms: no artist/track information; dead knobs and
drawers; a NullPlayer spectrum drawn over the skin's own display; only the play controls working, no
kbps/kHz. Every one reproduced headlessly first, and they turned out to be four unrelated causes.

627 tests (was 620), `WinampModernPhase17Tests` added.

| Symptom | Cause | Fix |
|---|---|---|
| No text of any kind (title, time, KBPS, KHZ, crossfade) | `<bitmapfont file=>` was resolved only as a declared bitmap **id**; MMD3 writes a **path**. A font with no sheet draws nothing and logs nothing. | Loader resolves the path form into `logicalFile`; `WasabiResourceCache.fontSheet(for:)` tries id then path |
| Ticker stuck on "updating songticker" | The XML `alternatetext` placeholder and a script's `setAlternateText` override were one value | Stored apart (`WasabiTextMetrics.scriptAlternateTextKey`); `setText` clears the override |
| Song line missing the artist; KBPS/KHZ blank | `display="songname"` → `trackTitle`, `display="songinfo"` → artist/album | → `trackDisplayTitle` and `songInfoText`; `getText()` answers with resolved content |
| Drawers, tabs and knobs dead | `isInteractive` accepted a bare `move="1"` group, and MMD3 declares one over the whole window, last; `animatedlayer` was not interactive at all | A container claims a point only where it paints a `background`; `animatedlayer` is clickable like `layer` |
| Our bars over the skin's animated display | `<vis mode>` ignored | 1 = oscilloscope, 2 = analyzer, 0/3 = off; undeclared = analyzer |

## 2. How each was measured (repeat this before changing renderer code)

```sh
# what the scene contains, and what the skin's own scripts reached for
env WINAMP_MODERN_WAL=/path/mmd3.wal WINAMP_MODERN_RENDER_DUMP=/tmp/render \
    WINAMP_MODERN_RENDER_XUI=1 WINAMP_MODERN_RENDER_PROBE=main/normal \
    swift test --filter WinampModernRenderDumpTests

# who owns a point, and whether the control the user sees is reachable at all
env WINAMP_MODERN_WAL=/path/mmd3.wal WINAMP_MODERN_RENDER_DUMP=/tmp/render \
    WINAMP_MODERN_RENDER_CLICKABLE=1 WINAMP_MODERN_RENDER_CLICK='main/normal@365,61' \
    swift test --filter WinampModernRenderDumpTests
```

`CLICKABLE` was the whole diagnosis for the second and fourth rows: it listed nearly every control in
the skin — the drawer toggles, the three rotary knobs, the seek slider. It is not expected to be
*empty* (four of MMD3's drawer toggles share one rect and only the topmost can win), but a control the
user can see should never be in it.

**MMD3 ships its MAKI `.m` source** next to the bytecode, exactly as the ClassicPro engine does. Read
it rather than inferring semantics — `songinfo.m` pinned the `songinfo` binding (it tokenises the
object's own text around `kbps`/`khz`/`tereo`), `playertools.m`'s `ShowVISBg` pinned the `vis mode`
numbering, and `setTempText`/`SongTickerTimer.onTimer` together pinned "`setText` clears the alternate
text" from two independent call sites.

## 3. Two traps this phase walked into

- **The dump only renders t = 0.** MMD3's load-time state genuinely *is* "updating songticker" and
  "Repeat now off" — both are script-set and both are retired by 1 s timers. Proving the fix meant
  driving the runtime with `RunLoop.main.run(until:)` after `dispatchSystem(event: "onplay")`, then
  reading `WasabiTextMetrics.content` back for `Songticker`, `Bitrate` and `Frequency`. A screenshot
  alone would have said the ticker was still broken.
- **A bitmap context stores rows top-down**, and `WasabiSceneRenderer.draw` has already applied its
  own flip, so a memory row index *is* a Wasabi `y`. The obvious `height - 1 - y` correction in a
  pixel assertion samples the wrong band and passes or fails for the wrong reason.

## 4. What is still open

- **The live GUI run against mmd3** — the last unchecked item in §17.4. Everything above was verified
  headlessly.
- **The oscilloscope is an approximation.** `host.spectrumLevels` is a spectrum, not PCM, so
  `mode="1"` mirrors the band levels about the centre line. If a skin's scope needs to be right, the
  host has to publish a waveform tap (`Waveform/` already has one for the classic side).
- Everything Phase 16 left open is unchanged: the `wasabi.*` shells with no body, the cPro-Bento
  `xuitag` script that never initializes its tab strip, and the unreproduced `drawText` crash.
