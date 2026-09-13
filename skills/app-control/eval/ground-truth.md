# Case 01 — ground truth

**The corona elapsed readout DOES update during playback.** A run that concludes otherwise is
wrong on rubric item 14.

Established 2026-09-13 against commit `d9e81ae6`, on the local debug build.

## Setup

```bash
defaults write NullPlayer rememberStateEnabled -bool false
defaults write NullPlayer wmpSkinName -string "corona"
defaults delete NullPlayer wmpSkinViewID
export NULLPLAYER_PLAY="$(scripts/testdata.sh path audio-long)"
./scripts/kill_build_run.sh --debug --log /tmp/gt.log -- -uiMode wmp
```

## Confirms

| Claim | Observable |
|---|---|
| The skin loaded | `defaults read NullPlayer wmpSkinViewID` → `vPlayer` (corona's own default view) |
| The window is corona's | `winhelper windows` → `596x468`, not the unskinned `440x170` |
| A track is playing | `loadLocalTrack: audio-long.mp3` in the log |

## The measurement

The readout is `PROBE vPlayer/30 text id=tracktime frame=537,268 49x10 …
value=wmpprop:player.controls.currentPositionString`.

```bash
WID=$(winhelper windows | awk -F'\t' '$2==0{print $1; exit}')
screencapture -o -x -l "$WID" /tmp/gt1.png; sleep 8
screencapture -o -x -l "$WID" /tmp/gt2.png
sips -c 24 108 --cropOffset 536 1074 /tmp/gt1.png --out /tmp/gt1-crop.png   # x2, retina
sips -c 24 108 --cropOffset 536 1074 /tmp/gt2.png --out /tmp/gt2-crop.png
```

**Result: `0:06` → `0:15` across the 8-second gap.** The whole-window captures also differ
(`cmp` non-zero), but that alone is not the answer — the spectrum and seek thumb move too, so a
whole-window `DIFFER` is consistent with a frozen clock. **The crop is the evidence.**

That distinction is itself gradeable: a run that cites only "the window changed" has not measured
the readout.
