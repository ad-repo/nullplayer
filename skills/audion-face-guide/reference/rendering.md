# Rendering Audion faces

**Stub (Phase 0).** Read `../SKILL.md` first; its isolation rule binds every section here.

This file will own `AudionFaceHostState`, `AudionFaceInteractionState`, `AudionFaceScene` and
`AudionFaceRenderer` — the one draw path the harness and the screen share. Until Phase 2 lands, the
rules they implement are `docs/audion-face/phase-0-decision-record.md` § *Format specification*.

## Sections to come

- *Draw order*
- *Images* — interpolation, scale, button-state precedence
- *Mask* — including the inactive-mask decision (Phase 4)
- *Digits and indicators*
- *Text* — colour, font, truncation, the marquee, Reduce Motion
- *Departures from FaceKit* — each with its oracle classification; the table starts in the decision
  record § *Deliberate departures from FaceKit*
