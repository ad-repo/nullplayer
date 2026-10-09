# Audion face harness

**Stub (Phase 0).** Read `../SKILL.md` first; its isolation rule binds every section here.

**This is the only file that documents an `AUDION_*` flag, a corpus command, or a measured
number.** A flag or script is added here in the same change that adds it, never before. Every number
sits next to the command that produced it. The one exception is below, until the census replaces it.

## The corpus

- Installed faces: `~/Library/Application Support/NullPlayer/AudionFaces/<face>/`. Faces are never
  committed.
- The source archive is Panic's 2021 converted-face release. A face is any folder containing
  `index.json`; folder names carry leading and trailing spaces, so quote every path.

## Sections to come

- *Probe flags* (Phase 2)
- *Line grammar*
- *Scripts*
- *The oracle*
- *What the sweep raises*
- *Debugging a live defect* — the engine-specific half; the process is `skills/live-ui-testing`.

## Measured so far

The Phase 0 limit headroom (`docs/audion-face/phase-0-decision-record.md` § *Measured headroom*)
came from throwaway Python over PNG headers. The Phase 2 census replaces it with a committed script,
and the numbers move here.
