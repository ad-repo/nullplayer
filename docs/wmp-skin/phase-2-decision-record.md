# WMP skin Phase 2 static-renderer decision

## Decision

**NO-GO for Phase 3.** The static engine is safe and deterministic enough to retain, but the
required `vPlayer` investment gate is not visually recognizable with expressions and scripts
disabled. Do not add the WMP app mode until the plan is amended with a bounded approach to the
layout-expression dependency demonstrated here.

This does not reverse Phase 0's separate GO decision for the killable helper architecture. It says
only that product integration cannot proceed before static layout can place enough of a real player
view to justify the remaining investment.

## Evaluated input and provenance

- User-supplied, untracked input:
  `/Users/ad/Projects/nullplayer-wmp-skin-support/skins/9SeriesDefault.wmz`.
- The local `skins/` directory contains a broader reference corpus. It and all generated images,
  screenshots, JSON reports, and derived artwork remain outside Git.
- Durable tests use only original synthetic inputs generated in the WMP test suite.
- Decision artifacts were written under `/private/tmp/wmp-phase2-9series-all/` and are disposable.

## Implemented static pipeline

- Top-left nested geometry with z-order, clipping, resize limits, and leading/center/trailing/stretch
  alignment.
- Immutable scene snapshots containing stable IDs, paint commands, hit metadata, geometry reused by
  drawing/hit testing/invalidation, unresolved inventory, visible bounds, and dirty bounds.
- Literal-only scene construction. Authored JScript and bindings are never evaluated or converted to
  zero. A container with an unresolved size is not painted; independently literal descendants may
  retain a known literal origin without acquiring a fabricated parent frame.
- Off-main ImageIO metadata/decode for BMP, GIF, JPEG, and PNG with the Phase 0 dimension/pixel limits,
  decoded-byte checks, and a 64 MiB byte-bounded LRU.
- Exact un-premultiplied RGB color-key comparison that preserves non-matching source alpha.
- Core Graphics rendering in top-left coordinates with explicit low interpolation and separate image
  and text counter-transforms.
- A headless dump path that writes one PNG per view plus deterministic JSON metrics. Synthetic tests
  cover upright BMP pixels, crops, color keys, nested offsets, stretch, clipping, z-order, text
  placement, and 1x/2x backing scales.

## `9SeriesDefault.wmz` evidence

The loader and renderer reported no fatal diagnostics. Both views produced PNGs.

| Metric | `vPlayer` | `viewTiny` |
|---|---:|---:|
| Authored canvas | 859×468 | 596×468 |
| Resolved nodes | 15 | 7 |
| Unresolved nodes | 39 | 2 |
| Paint commands | 9 | 6 |
| Visible bounds | x=250, y=0, 339×266 | x=250, y=0, 346×266 |
| Peak cache bytes | 15,020 | 456,772 cumulative |
| Render time | 4.41 ms | 4.89 ms |

The exact timings are one debug-run observation, not a benchmark. Memory and time are comfortably
bounded for this input.

The unresolved inventory is explicit. It is dominated by `JScript:` widths/heights/positions and
their dependent containers; it also includes `wmpprop:` layout values. The renderer retains loader
warnings for unsupported `res://` resources, optional missing cursor resources, and duplicate IDs.
None was fatal.

## Gate assessment

| Required gate | Result |
|---|---|
| Authored 859×468 `vPlayer` root | PASS |
| Literal chrome/controls in expected relative positions | PARTIAL |
| Upright, keyed, ordered assets | PASS for every resolved asset |
| Unresolved geometry enumerated without fallback values | PASS |
| No fatal diagnostic; bounded memory/time | PASS |
| Human review recognizes the skin's own player view | **FAIL** |

The `vPlayer` image contains a small top control strip and isolated vertical chrome fragments on a
mostly empty canvas. Although those resolved pixels are upright and correctly keyed, the result is
not recognizable as the authored player. `viewTiny` produces a more substantial outer chrome frame,
but the locked decision gate names `vPlayer`; it cannot substitute for that failure.

## Required re-estimation before product integration

Do not add sample-specific coordinates or weaken the unresolved diagnostics. Before Phase 3, amend
the plan with a bounded, tested layout-expression slice. At minimum, quantify the expression grammar
and dependency graph needed for initial geometry, decide whether that slice belongs in a custom
non-script evaluator or the killable helper, and repeat this Phase 2 visual gate with strict
dependency-depth/pass/time/message bounds. Phase 3 remains blocked until a revised gate passes or the
product scope is explicitly changed.
