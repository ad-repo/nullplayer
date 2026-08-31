# WMP skin Phase 2 handoff

## Repository state at phase start

```text
pwd:    /Users/ad/Projects/nullplayer-wmp-skin-support
branch: feat/wmp-skin-support
status: clean
HEAD:   d127b2d3c6e6795c6e8ca8a4d0c15e522bd02c8d
```

## Delivered

- `WMPGeometry`: top-left value geometry, nesting, clipping, resize limits, and axis alignment/stretch.
- `WMPScene`: immutable stable-ID paint commands, resolved geometry, hit metadata, unresolved
  inventory, visible/dirty bounds, and deterministic dumps.
- `WMPSceneBuilder`: off-main literal-only layout. Expressions and bindings remain named
  diagnostics and never become fallback coordinates. Independently literal descendants can survive
  an unresolved container size without painting a fabricated container frame.
- `WMPImageStore`: off-main ImageIO metadata/decode for BMP/GIF/JPEG/PNG, Phase 0 dimension/pixel
  limits, decoded-byte checks, and a 64 MiB byte-bounded canonical-path/color-key LRU.
- `WMPColorKey`: exact un-premultiplied RGB masking while preserving all non-matching source alpha.
- `WMPRenderer`: Core Graphics top-left rendering, upright image/text counter-transforms, explicit
  interpolation, crops, tiling, clips, fills, text, and bounded 1x/2x surfaces.
- `WMPRenderDumpTests`: one untracked PNG per view and a sorted JSON report with canvas, counts,
  bounds, order, diagnostics, cache peak, scale, and render time.
- Synthetic coverage for upright BMP pixels, all four image formats, partial alpha, crops, color
  keys, nested offsets, stretch, clipping, z-order, LRU eviction, text placement, and backing scale.
- Phase 2 decision record with a **NO-GO for Phase 3** because literal-only `vPlayer` output is not
  recognizable.

Phase 2 implementation commit: `44e7dfb0` (`feat(wmp): add phase 2 static renderer`).

## Real-corpus decision evidence

Input was the user-supplied, untracked
`/Users/ad/Projects/nullplayer-wmp-skin-support/skins/9SeriesDefault.wmz`. The final disposable dump
is under `/private/tmp/wmp-phase2-final/`; neither input nor output is committed.

```text
vPlayer:  canvas 859x468, 15 resolved, 39 unresolved, 9 paint commands,
          visible x=250 y=0 339x266, peak cache 15,020 bytes, render 4.41 ms
viewTiny: canvas 596x468, 7 resolved, 2 unresolved, 6 paint commands,
          visible x=250 y=0 346x266, peak cache 456,772 bytes cumulative, render 4.89 ms
```

Both views rendered with no fatal diagnostic. Resolved art was upright, correctly keyed, and
ordered. `vPlayer` remained mostly empty because major container geometry depends on JScript and its
dependent layout; human review did not recognize it as the full player. The plan's required gate
therefore fails even though `viewTiny` shows a substantial partial outer frame.

## Off-main boundary

The public scene builder and renderer entry points immediately use detached WMP background work.
Tests invoke both from a main-actor test and assert `wasBuiltOnMainThread == false` and
`wasRenderedOnMainThread == false`. No `DispatchQueue.main.sync` or AppKit state was added.

## Change-boundary audit

Production and test implementation is confined to `Sources/NullPlayer/WMPSkin/` and WMP-prefixed
tests. No shared application source, UI mode, existing skin engine, controller, preference, or
installed state changed.

Paths outside the default implementation/test folders:

- `skills/wmp-skin-guide/SKILL.md`: necessary owning-skill documentation for the new scene/image
  contracts. It changes no runtime behavior.
- `docs/wmp-skin-integration-plan.md`: implementation mirror updated at the user's request to record
  the local untracked corpus and the prohibition on committing inputs/derived artifacts. The
  canonical planning-worktree copy was committed separately as `1f85a7aa`.

Before the Phase 2 commit, all three worktrees were audited. The implementation worktree contained
only the listed WMP changes plus the intentionally untracked `skins/` corpus. The planning worktree
contained only its canonical plan edit. The original `/Users/ad/Projects/nullplayer` checkout had
unrelated pre-existing Winamp Modern/user changes and received no WMP file or modification.

## Verification

```text
focused WMP suite: 31 passed, 2 expected opt-in skips, 0 failed (21.360 s)
synthetic Phase 2 suite: 7 passed, 1 expected opt-in skip, 0 failed
final 9SeriesDefault all-view dump: 1 passed, 0 failed
full swift test: 465 passed, 2 expected opt-in skips, 0 failed (30.382 s)
git diff --check: passed
```

The build retained existing non-fatal SQLite privacy-resource, deprecated OpenGL, and aubio minimum
deployment-version warnings.

## Next work

Do not start Phase 3. First amend/re-estimate the plan with a bounded initial-layout expression
slice, quantify the real corpus grammar/dependencies, decide whether evaluation belongs in a custom
dependency evaluator or the killable helper, and repeat the Phase 2 `vPlayer` visual gate. No
sample-specific coordinates or uninterruptible in-process JavaScript are acceptable.

## Repository state at phase end

```text
pwd:    /Users/ad/Projects/nullplayer-wmp-skin-support
branch: feat/wmp-skin-support
Phase 2 implementation HEAD: 44e7dfb0
status: only user-supplied skins/ remains untracked after committing this handoff
```
