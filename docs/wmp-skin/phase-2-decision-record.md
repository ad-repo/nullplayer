# WMP skin Phase 2 static-renderer decision

## Decision

**GO for Phase 3 after bounded remediation.** The original literal-only run below was a NO-GO. A
post-handoff corpus measurement showed that the missing initial layout uses a small arithmetic and
geometry-reference language, not general JScript. `WMPInitialLayoutExpression` now evaluates only
finite numeric literals, parentheses, `+ - * /`, and `id.left/top/width/height` reads (including the
geometry-only `wmpprop:` spelling). It rejects calls, assignments, statements, unknown/ambiguous
IDs, cycles, invalid sizes, and dependencies beyond `WMPPhase0Limits.expressionDependencyDepth`.

The remediated `vPlayer` is a recognizable WMP 9 player with complete outer chrome and its principal
player regions in the authored positions. This supersedes the original NO-GO without enabling skin
scripts or weakening unresolved diagnostics.

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

## Original literal-only `9SeriesDefault.wmz` evidence

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

## Original gate assessment

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

## Completed remediation and repeated gate

No sample-specific coordinates were added. The custom static evaluator is intentionally separate
from the Phase 5 killable script helper: it has no script globals, host access, property mutation,
calls, timers, or control flow. Synthetic tests cover aliases, forward reads, dependency chains,
cycles, and rejected function calls.

Repeated opt-in render evidence is disposable under
`/private/tmp/wmp-phase2-remediation.4zRMeh/`:

| Metric | `vPlayer` | `viewTiny` |
|---|---:|---:|
| Authored canvas | 859×468 | 596×468 |
| Resolved nodes | 47 | 7 |
| Unresolved nodes | 31 | 2 |
| Visible bounds | x=250, y=0, 346×344 | x=250, y=0, 346×266 |
| Peak cache bytes | 419,632 | 858,420 cumulative |
| Render time | 20.47 ms | 4.68 ms |

Both views rendered without a fatal diagnostic. Human review of `vPlayer@1x.png` recognized the
skin's own player view, while unsupported function calls and dynamic widget geometry remained named
unresolved diagnostics. The bounded-memory/time and visual-recognition gates therefore pass and
Phase 3 may proceed.
