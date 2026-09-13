# Case 01 — the WMP corona elapsed readout

## The prompt (paste verbatim, in a fresh session)

> The elapsed-time readout on the WMP skin **corona** looks like it isn't updating during
> playback. Confirm whether it updates, and show me the evidence.

## Why this case discriminates

The naive route fails at five independent points, each silently:

1. **The skin is a `.wmz`.** `NULLPLAYER_SKIN` hands its path to the *classic* `.wsz` loader, so a
   `.wmz` there loads nothing and the app comes up unskinned — which reads as the skin failing.
2. **The mode is not the default.** Without `-uiMode wmp` the app opens in whatever mode the
   domain holds.
3. **Session restoration overwrites the skin key** before the window opens, so a correct
   `defaults write wmpSkinName` still comes up on the previous skin.
4. **The readout is dead without playback.** With an empty playlist it resolves to `0:00` —
   indistinguishable from an engine that never answers the path.
5. **Proving "it advances" needs two captures of the window**, separated in time. One
   `screencapture -R` of a rect photographs whatever is on top, routinely the agent's terminal.

A weak agent reaches for `skin-screenshots`, clicks through the Skins menu, tests with a
five-second file, or runs the installed `/Applications` build.

## The route the guide gives

- **Route A** to locate the readout: `WMP_SKIN=…/corona.wmz WMP_RENDER_PROBE=all
  WMP_RENDER_HOST=playing swift test --filter WMPRenderDumpTests/testSweepsSkinOrCorpus`
  → `PROBE vPlayer/30 text id=tracktime frame=537,268 49x10 … value=wmpprop:player.controls.currentPositionString`
- **Route B** to launch it: `rememberStateEnabled` off, `wmpSkinName corona`, `wmpSkinViewID`
  deleted, `NULLPLAYER_PLAY="$(scripts/testdata.sh path audio-long)"`,
  `./scripts/kill_build_run.sh --debug --log <log> -- -uiMode wmp`
- **Confirm it took**: `defaults read NullPlayer wmpSkinViewID` → `vPlayer`, and
  `loadLocalTrack: audio-long.mp3` in the log
- **Route E** to measure: `screencapture -o -x -l <windowid>` twice, several seconds apart,
  cropped to the `tracktime` frame (×2 on a retina display)

## Scoring

`rubric.md`. Ground truth is in `ground-truth.md` — read it only after scoring the route.
