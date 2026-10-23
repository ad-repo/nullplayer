# What the automated checks miss, and traps that look like defects

Reference for `skin-triage`.

## What the automated checks miss

A green automated check is a **regression** result, not a correctness result: the sweep compares the
engine against its own last output, and the census rating is structural. Intake #1's in-app finds
sort into five groups the automated checks did not cover. Each has a check that does cover it:

| Missed because | Intake #1 examples | The check that catches it |
|---|---|---|
| **Nobody looked at the dump PNG** — a wrong render that matches its baseline diffs as identical | Azenis2's blank buttons, Simple's group-id labels, NEO_CLASSIC's font sheet, Anunaki's empty LCD, Prakrit's see-through body, 1010's bunched EQ and gapped colons | Phase 2 step 5: **open every PNG** and judge it against the artwork/reference; grep dumped text for ids and `@TOKEN@` |
| **The harness has no windows or screen** — tiler, screen size, menu bar, `setScale` | Panther/New_Night clamped library, CopperdeckII 178px offset and 2147-wide video, 1010 taller than the screen, Alpha X5 past both edges, Vortex strip, machina's stray video window | Phase 7: `window-census.sh` + `window-interaction-matrix.sh` on every skin |
| **No host data** — no component host, no cover art, no playing clock | Symplicipod's doubled blank library, cover windows that never showed a cover, JRS's missing playlist command bar | Phase 7 live with playback on a track that has cover art; open every hosted window |
| **State not driven** | the 135% UI Size rows, CopperdeckII's 1px shade, Nitrous monitor mode | the capped state matrix, headless and live |
| **"Works" counted any change** — the interaction verdict passes a control that acts but draws wrong, and the click harness was mis-converting points until mid-pass | Alpha X5's sliders and EQ/Mute switches, Dronev11's undraggable player | Phase 3: look at the after-PNG of each `works` row, and the drag probe (`WINAMP_MODERN_DRAG_PROBE`) per skin |

A check that has never caught anything has not been shown to work. Prove it on one known defect
before trusting its silence.

## Traps that look like defects

| You see | It is usually | Check |
|---|---|---|
| A click changes nothing, trace silent | the click missed, or `clickCount == 0` | probe frame centre; `winhelper click` |
| No menu after a synthetic right-click | the tool | right-click by hand |
| The skin looks unskinned or tiny | the launch picked no skin | `LAUNCH PASS`, `menu.applescript family` |
| A blank pane in a dump | no component host in the harness | the live window |
| A whole window blank in a dump | a timer-driven fade not yet run | re-dump with a settle |
| Every control in a skin dead | its startup handler aborted | the script report — Phase 2 step 4 |
| A green sweep, user says broken | non-default state | Phase 3 states |
| A capture shows your terminal | `-R` photographs the screen | `-l <windowid>` |
| Raising the app launched another copy | activation by name | `winhelper raise <pid>` |
| The trace says shown, screen says hidden | a trace is the script's write | pixels answer visibility |
| A reference diff everywhere by a few px | scale or crop mismatch | crop to the window at 1x first |
| A number improved, report persists | a second fault on the same screen | the reporter's own steps |
