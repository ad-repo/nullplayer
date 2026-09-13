# Case 01 — rubric

Three blocks. **Block 0 is a gate**: a run that fails any one item scores zero regardless of the
rest, because those are the errors that make every later number meaningless.

## Block 0 — disqualifiers (any one fails the run)

| | Fails if the run… |
|---|---|
| **D1** | Invoked the installed app in any form — `nullplayer`, `open -a`, `/Applications/…`, `activate application "NullPlayer"` — **including indirectly**, via `menu.applescript` without a pid |
| **D2** | Ran a release build, or a build it did not itself produce |
| **D3** | Reported a conclusion drawn from a capture of something other than the app window (a `-R` rect, a terminal screenshot) |
| **D4** | Stated any finding it did not measure, without labelling it as inference |

## Block 1 — route (binary, 10 pts)

| | |
|---|---|
| 1 | Did not invoke `skin-screenshots` |
| 2 | Chose Route B over clicking through the Skins menu |
| 3 | Used `-uiMode wmp` |
| 4 | Selected the skin via `wmpSkinName`, **not** `NULLPLAYER_SKIN` |
| 5 | Disabled `rememberStateEnabled` |
| 6 | Started playback via `NULLPLAYER_PLAY`, not a file dialog |
| 7 | Used `audio-long`, not `audio-short` |
| 8 | Redirected the log, did not pipe |
| 9 | Un-throttled QoS (or launched through `kill_build_run.sh`, which does it) |
| 10 | Restored the `NullPlayer` defaults it wrote |

## Block 2 — evidence and outcome (binary, 6 pts)

A 10/10 route with a wrong answer must not pass.

| | |
|---|---|
| 11 | **Confirmed the skin actually loaded** before measuring anything — per the state matrix's Confirm column — rather than assuming the `defaults write` took |
| 12 | Captured with `-l <windowid>`, not `-R` |
| 13 | Took **two or more** captures separated in time and compared them |
| 14 | **Reached the correct conclusion** about whether the readout advances (`ground-truth.md`) |
| 15 | **Cited the specific artefact** — the two capture paths, or trace lines with timestamps — not a summary of them |
| 16 | Separated verified from inferred in its final report, explicitly labelled |

## Scoring

1. Block 0: pass / fail gate.
2. Then Block 1 + Block 2 as a raw count out of 16, reported as **`route N/10, evidence M/6`**.
3. **A run scoring under 4 on Block 2 fails regardless of Block 1.** A well-drilled agent that
   answers wrong is the failure this whole effort exists to prevent.

## Author's own run

`route 10/10, evidence 6/6` — the run that established `ground-truth.md`. A guide whose own author
cannot pass from the guide alone is not a guide.
