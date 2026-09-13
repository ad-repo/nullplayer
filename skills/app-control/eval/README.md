# app-control eval

A canned case for grading several agents against the same task.

## Running it

1. **Fresh session per agent.** Context from a previous run is the thing being measured.
2. Reset the domain between runs:

   ```bash
   defaults delete NullPlayer wmpSkinName
   defaults delete NullPlayer wmpSkinViewID
   defaults delete NullPlayer rememberStateEnabled
   ```

   Save the user's real values first if they matter — `app-control/scripts/qa-session-template.sh`
   has the save/restore helper.
3. Paste the prompt from `case-01-wmp-elapsed-readout.md` **verbatim**. Do not add hints; the
   omissions are the test.
4. Score against `rubric.md`. Block 0 first — it is a gate.
5. Only then read `ground-truth.md`, to grade item 14.

## What the case is testing

Not whether the agent can read a clock. Whether it reaches the running app **in the right state**
without being told how, and whether it can tell a measurement from an assumption. Every one of the
five silent failures in the case description produces a confident, wrong, plausible-looking report.

## Files

| File | |
|---|---|
| `case-01-wmp-elapsed-readout.md` | the prompt, why it discriminates, and the route the guide gives |
| `rubric.md` | Block 0 gate, Block 1 route /10, Block 2 evidence /6 |
| `ground-truth.md` | the answer, how it was established, and the commit it was established at |
