# Audion face format

**Stub (Phase 0).** Read `../SKILL.md` first; its isolation rule binds every section here.

This file will own the face format as NullPlayer implements it: every `index.json` key and how
`AudionFaceDocument` decodes it, sprite and PICT naming, rect semantics, text colour/font/style
resolution, and the meaning of the files FaceKit ignores once Phase 1 confirms it.

Until Phase 1 lands, the specification is `docs/audion-face/phase-0-decision-record.md`
§ *Format specification*, and the authority behind it is FaceKit `AudionFace.swift` at `5b7c847`.
Phase 1 moves the spec here and leaves the decision record pointing at it.

## Sections to come

- *Keys* — the 74 `index.json` keys, grouped by element, with presence counts from the census.
- *Rects* — top-left, exclusive edges, zero means absent, buttons sized by sprite.
- *Sprites and PICT ranges* — button states, indicators, the 10- and 11-frame digit rule, animations.
- *Text* — Txtr-then-Face colour, font fallback, the all-or-nothing style rule, XOR mode.
- *Files FaceKit ignores* — `window.png`, `drag.png`, `inactive.png`, `active-alpha.png`, `about.png`.
