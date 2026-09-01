# WMP skin Phase 5 handoff

## Repository state at phase start

```text
pwd:    /Users/ad/Projects/nullplayer-wmp-skin-support
branch: feat/wmp-skin-support
HEAD:   699a29bb47e280ff734bad5a1019d07b06e2275c
status: clean except for the user-supplied, untracked skins/ corpus
```

## Delivered

- A versioned JSON script protocol and `WMPJScriptRuntime`. Each evaluation batch creates a fresh
  `WMPScriptIsolationHelper` process, validates request/response size and cardinality, enforces a
  parent deadline, and never exports a Swift or Objective-C object.
- A checked WMP compatibility bootstrap for player controls/settings/media/playlist/network,
  element/view geometry, theme, EQ, visualization, popup, and metadata surfaces. Unsupported
  members return stable defaults and diagnostics. ActiveX, registry, shell, process, arbitrary URL,
  filesystem/network, modal UI, and native-object access remain unavailable.
- Dependency-read capture and a stable topological geometry transaction. Cycles, missing IDs,
  expression errors, non-finite results, negative sizes, and pass/depth limits cannot partially
  replace the visible scene. Resizes publish proposed view dimensions and keep drawing the last
  completed scene while helper/layout/render work remains off-main.
- One coalescing registry for `wmpprop:` and `wmpenabled:` with origin-based feedback prevention.
  Committed binding and script values survive fresh helper batches.
- Ordered script-file and inline-handler dispatch for load, host-state, mouse, click/change, and
  timer transactions. Host changes coalesce before dispatch; timers are host-owned and enforce the
  256-count / 8 ms Phase 0 limits.
- A typed command return path into the Phase 4 host for transport, scanning, seek, volume, balance,
  mute, shuffle, and repeat. Numeric values are validated and clamped at both protocol and host
  boundaries.
- SHA-256 skin-content preference namespaces with a 64 KiB value limit, 512-entry cap, isolation,
  and reset path.
- Synchronous process cancellation during UI teardown. Timeout, crash, allocation pressure,
  malformed protocol, or teardown kills/reaps active helpers, cancels timers, retains committed
  static scene state, disables script for the skin session, and emits one actionable diagnostic.
- `docs/wmp-skin/compatibility.md` as the checked object/member/event/denial source of truth and an
  updated owning skill contract.

## Security and runtime evidence

The production bridge repeated the Phase 0 gate against its real compatibility bootstrap:

- 100 consecutive fresh-realm transactions completed with deterministic results;
- infinite loops and allocation pressure terminated within the parent deadline;
- recursion and syntax errors remained bounded diagnostics;
- a 10,000-request timer storm returned exactly the 256-request cap at periods of at least 8 ms;
- a clean transaction succeeded immediately after every hostile failure;
- explicit teardown killed an already-running infinite loop synchronously in under 250 ms;
- protocol payloads remain bounded to 1 MiB per message and actors serialize per-skin in-flight work;
- transaction admission is capped at 120 batches per second.

## Corpus evidence

The opt-in `skins/9SeriesDefault.wmz` probe loaded registered scripts in deterministic order and ran
the production expression/session path at the view's minimum, default, and larger clamped sizes.
All three transactions produced renderable non-empty scenes without timeout or helper crash. The
archive, artwork, and any derived render output remain untracked.

## Shared-path audit

No shared/global application path changed. Product changes are confined to
`Sources/NullPlayer/WMPSkin/` and `Sources/NullPlayer/Windows/WMPSkin/`; tests and documentation are
confined to the WMP-owned paths and owning skill. `WMPHost` gained only WMP-local buffering/reception
snapshot fields. `WMPScriptIsolation` gained WMP-local active-process cancellation.

No file under Classic, Original, Winamp Modern, shared `App/`, or the audio engine changed. The
WMP-local scene-override and controller seams satisfied the phase, so no shared mode gate was
needed. The separate `/Users/ad/Projects/nullplayer` checkout retains its pre-existing unrelated
changes, and the planning worktree is clean.

## Verification

```text
swift build: passed
focused WMPPhase5Tests with 9SeriesDefault: 12 passed, 0 failed (6.149 s)
production helper replacement/security proof: 100 cycles plus hostile corpus passed
complete WMP suite: 68 executed, 5 expected opt-in skips, 0 failed (31.036 s)
full swift test after final input fix: 502 executed, 5 expected opt-in skips, 0 failed (37.475 s)
git diff --check: passed
```

The existing SQLite privacy-resource, deprecated OpenGL, aubio deployment-target, and other
pre-existing build warnings remain. No DMG was built, as requested by the owning skill.

## Remaining deliberate limitations

- Playlist item mutation, EQ write-through, visualization selection, popup UI, multiple views, and
  hosted video/effect surfaces remain Phase 6 capability slices. Their Phase 5 compatibility
  members return documented placeholders or warnings.
- The Phase 4 outside-release behavior still awaits the Phase 7 Windows reference confirmation.
- WMP remains DEBUG/feature-gated; this phase does not alter public exposure.

## Repository state before phase commit

```text
pwd:    /Users/ad/Projects/nullplayer-wmp-skin-support
branch: feat/wmp-skin-support
HEAD:   699a29bb47e280ff734bad5a1019d07b06e2275c
status: Phase 5 WMP-owned changes plus the user-supplied, untracked skins/ corpus
```

## Next work

Phase 6 completes widgets, multiple views, hosted surfaces, and WMP-owned chrome for native
auxiliary windows without widening the compatibility or controller-family boundaries established
here.
