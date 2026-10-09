# Audion face harness

**Stub (Phase 0).** Read `../SKILL.md` first; its isolation rule binds every section here.

**This is the only file that documents an `AUDION_*` flag, a corpus command, or a measured
number.** A flag is added here in the same change that adds it. Every number sits next to the
command that produced it.

## The corpus

- Installed faces: `~/Library/Application Support/NullPlayer/AudionFaces/<face>/`, overridden by
  `AUDION_CORPUS_PATH`. Faces are never committed.
- The source archive is Panic's 2021 converted-face release. A face is any folder containing
  `index.json`; folder names carry leading and trailing spaces, so quote every path.

## Sections to come

- *Probe flags* (Phase 2) — `AUDION_FACE`, `AUDION_RENDER_DUMP`, `AUDION_RENDER_STATE`,
  `AUDION_RENDER_CLOCK`, `AUDION_RENDER_HOVER`, `AUDION_RENDER_CLICK`, `AUDION_RENDER_SCALE`,
  `AUDION_RENDER_PROBE`; from Phase 5, `AUDION_PLACE_TRACE`. All `#if DEBUG`, read once at start.
- *Line grammar* — `HARNESS`, `FACE`, `LOAD`, `FINDING`, `ELEMENTS`, `RENDER-DUMP`, `PNG`, one fact
  per line through a locked `write(2)` emitter.
- *Scripts* — `scripts/audion_face_census.sh`, `scripts/audion_render_sweep.sh`,
  `scripts/audion_corpus_baseline.py`, `scripts/audion_facekit_reference.sh`,
  `scripts/audion_oracle_compare.py`.
- *The oracle* — FaceKit at `5b7c847`, cloned outside the repo; the canonical states; the match
  numbers and the command that produced them.
- *What the sweep raises* — which host states and interactions a number came from.
- *Debugging a live defect* — the engine-specific half; the process is `skills/live-ui-testing`.

## Measured so far

The Phase 0 limit headroom (`docs/audion-face/phase-0-decision-record.md` § *Measured headroom*)
came from throwaway Python over PNG headers. The Phase 2 census replaces it with a committed script,
and the numbers move here.
