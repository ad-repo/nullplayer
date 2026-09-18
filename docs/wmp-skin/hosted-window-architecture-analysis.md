# WMP native hosted windows: architecture and verification analysis

Date: 2026-09-18. Reviewed revision: `49f644425fe923a6ec4977793d0d59cfdc783eca`.

Status: proposed implementation contract, revised after source review. The APIs, state rules,
test targets, and limits below are design decisions to implement, not claims about existing code.
The work can begin in the staged order below. Migration beyond Cava and AudioAnalysis is gated
on their live composition prototype passing; script-layout execution remains a separate experiment.

## Recommendation

Keep the current whole-donor rendering approach, but stop making each native window responsible for integrating it correctly. Introduce one WMP-owned host that owns frame composition, content placement, asynchronous frame transitions, and chrome hit testing. Pair that with automated **all-skin frame testing across sizes** and **all-window integration testing against a small, deliberately difficult set of frames**.

This addresses two different sources of repeated work:

1. A donor extraction correction should improve every window wearing that donor.
2. A composition or lifecycle correction should improve every donor on every hosted window.

The first is substantially present already. The second still depends on repeated implementation in individual views. Testing every skin against every window manually is compensating for that incomplete boundary.

This is an incremental architecture and test strategy, not a recommendation to replace the WMP engine, discard the skin's artwork, or claim every arbitrary `.wmz` can yield a perfect reusable frame.

## Scope and evidence limits

The requested windows are Flow (`NetworkMonitorView`), PeppyMeter, media library (`PlexBrowserView`), Spectrum, AudioAnalysis, and Cava. They belong to a larger family that also includes waveform and ProjectM. Playlist and equalizer share some chrome machinery but are explicitly excluded from the current border-growth registry because their layout uses classic sprite geometry.

This review inspected repository documentation, recent commit messages and selected diffs, frame derivation/provider code, shared geometry/chrome code, window call sites, and existing tests/probes. It did not launch the app, run a new corpus sweep, or benchmark performance. Historical counts and visual outcomes below are attributed to the commits or documentation that recorded them; they are not fresh measurements. No implementation changes accompany this document.

## What the recent fixes establish

| Change | What it corrected | Architectural lesson |
|---|---|---|
| `ca6791b6`, September 12 | Introduced borrowed WMP window rings on native windows. | A common frame representation is already the right seam. |
| `984d5e02`, September 14; `e6f36b69`, September 15 | Corrected library frame/background treatment and borrowed-frame placement. | The library has its own composition path; shared artwork does not guarantee shared composition. |
| `9265ceb5` and `24419105`, September 15 | Revised caption treatment, ultimately leaving borrowed artwork alone and using a corner close hit area. | More pixel inference does not necessarily provide more reliable semantics. |
| `ea0489aa` and `a67aa53c`, September 16 | Added fixed-panel donors and centralized growth around preserved interior size. | Different donor classes need different resize policies; content size and outer size must be separate. |
| `da42618c`, September 17 | Replaced selected-piece assembly by rendering the donor whole and subtracting its content/controls. | Reusing the real renderer eliminated a broad class of reconstruction errors. The commit reports 88 rings at 357×238, previously 67, and removal of 21 open-ring refusals in a 185-archive run. |
| `d0edc76e`, `61d1027c`, September 17 | Refined furniture removal, rail preservation, and repair of script-sized frame pieces. | Whole-view rendering still needs a reliable distinction between reusable frame, donor content, and donor furniture. |
| `3b1e1606`, September 17 | Fixed TheUnit rails/grips, inverted ground coordinates, and missing relayout after asynchronous frame arrival. | One report contained independent extraction, coordinate, and lifecycle failures. Several fixes required edits across native views. |
| `bc1b777f`, September 18 | Repaired Alienware Invader's approximately 107-point bare rail at tall library sizes by adding an absolute-length criterion. | A defect visible in only one window can still be a shared frame defect caused by size. Window identity alone is an unreliable classifier. |

These are mostly general mechanism fixes rather than filename exceptions. The opportunity is to preserve that approach while making the contracts and test coverage stronger. The history does not support starting over with another bitmap-piece selector.

## Current architecture: strong extraction seam, incomplete hosting seam

The current path is:

```text
WMPLoadedSkin
  → WMPHostedFrameTemplate: choose donor, remove donor-owned content, compose frame
  → WMPHostedFrameProvider: asynchronous render/cache at requested size
  → SkinnedSurfaceFrameArtwork: image, content rect, metrics, overlay policy
  → WindowManager: family-gated access
  → individual native views: layout, background, frame, repaint, hit testing

HostedWindowBorderLayout separately observes window/style events and preserves interiors.
```

Useful foundations already exist:

- `WMPSceneBuilder` and `WMPRenderer` render the whole donor, preserving authored layout rather than reconstructing it with a second renderer.
- Ring and panel paths are distinct. Panels use a nine-slice; rings honor the donor floor during rendering without forcing all windows to that floor.
- `HostedWindowBorderLayout` centralizes growth, user-resize tracking, and persisted interior sizes.
- The provider builds asynchronously, guards completed results by generation, caches 12 sizes, and remembers refusals.
- Family-gated accessors prevent other skin engines from borrowing WMP frame behavior.
- Existing frame probes, PNG dumps, corpus scripts, regression fixtures, and counter-evidence dossiers are a substantial testing foundation.

The remaining integration work is spread out. The guide's nine-step new-window checklist requires each view to relayout when artwork arrives, fill the correct ground, honor overlays, avoid animation shortcuts that erase chrome, use the correct metrics, and participate in growth. Flow, Cava, and PeppyMeter each implement the borrowed-frame fast-path guard. The library separately implements borrowed-image fill/clip/draw logic. A rule can be centralized as a helper yet remain optional at every call site.

The guide records this failure directly: frame dumps were correct while live native subviews still occupied old rectangles or animation repaints erased the frame. These are integration failures that a donor-only probe cannot detect.

## Proposed ownership boundary

### One WMP host around content

Introduce a WMP-owned host, conceptually `WMPHostedSurfaceContainer`, through the existing family gate. Its responsibilities should be:

- One conversion between top-left donor coordinates and the host view's coordinates.
- Background fill confined to the content region.
- A content container with explicit clipping and layout.
- A frame overlay above content, including independently rendered native/SwiftUI/GPU children.
- Shared close/drag/resize hit regions, with the decorative overlay passing content input through appropriately.
- Application of one consistent frame/layout state, followed by content relayout and display invalidation.

The six native windows should provide content and content requirements, not reproduce WMP chrome policy. Start with one immediately drawn animated view (Cava) and one native-subview case (AudioAnalysis); then migrate Flow, PeppyMeter, Spectrum, and the library. Keep the other modes on their existing code paths. The library is a valuable migration checkpoint because its separate painter will reveal whether the abstraction actually covers a second implementation style.

An overlay could let content animate without redrawing static chrome on every tick. That is a performance hypothesis, not an established saving: AppKit/Metal/OpenGL ordering, clipping, and invalidation must be proven on the actual window stack. If a backend cannot support the chosen layer arrangement, the host should own the necessary full-composition fallback. Individual visualizers should not rediscover the rule.

This should be a small hosting contract, not a new cross-engine window framework. Reuse family-neutral value types where useful; keep WMP inference and WMP policy in WMP-owned code.

### Concrete host/content contract

Put the container, provider protocol, and adapters under `Windows/WMPSkin/Hosted/`. Keep immutable
donor plans under `WMPSkin/`. The following is an interface sketch; supporting value types are
specified by the tables below. It is not a drop-in implementation.

```swift
@MainActor protocol WMPHostedContent: AnyObject {
    var view: NSView { get }
    var requirements: WMPHostedContentRequirements { get }
    func mount(context: WMPHostedContentContext)
    func apply(layout: WMPHostedContentLayout, style: SkinnedSurfaceStyle)
    func unmount()
}

@MainActor protocol WMPHostedPresentationSource: AnyObject {
    func request(_ request: WMPHostedFrameRequest,
                 receive: @escaping @MainActor (WMPHostedPresentation) -> Void)
    func detach(consumerID: UUID)
}
```

`requirements` contains minimum interior size, the content's flipped-coordinate convention,
render backend (`appKit`, `swiftUI`, or `gpu`), and whether unhandled body drags move the window.
`context` supplies close and docking-aware drag callbacks plus content invalidation; it exposes
no skin runtime. `layout` contains local content bounds, backing scale, and presentation revision.
The view is sized in points, never scaled to accommodate a thick border. Existing presenters,
models, audio consumers, and selection state remain owned by their controllers/views.

Use this hierarchy for the first prototype:

```text
existing NSWindow (same identity, controller, accessibility ID, and delegate)
  WMPHostedSurfaceContainer — unflipped, sole consumer of presentation state
    contentClipView — masks children to the resolved rectangular content region
      adapter.view — native coordinates, local origin zero
    frameOverlayView — transparent sibling above content, never a content hit target
```

The container fills the content ground. It draws frame artwork below the clipped content when
`paintsOverContent` is false and in the overlay when true. Its hit-test implementation handles
chrome before delegating to children; the overlay itself always returns nil from hit testing.
Convert donor top-left geometry once to container coordinates using insets. Adapt child coordinates
through AppKit view conversion, not a second donor transform.

Each migrated view gets an explicitly installed content-only mode, separate from its existing
Winamp Modern hosted context. In that mode its content rect is local bounds, its own chrome,
chrome metrics queries, chrome observers, and close/title dragging are bypassed, and its normal
content drawing, native children, menus, scrolling, and keyboard actions remain active. A wrapper
that leaves the old view painting a second border does not satisfy this contract. Prefer small
content-layout/drawing extractions over parallel copies of an entire view.

| Concern | Owner and rule |
|---|---|
| Installation | Existing auxiliary controller installs the adapter/container only when the controller family is `.wmp` and its window is in the migrated allow-list. `WindowManager` supplies that gated decision. Never reuse the `.wal` hosted context. |
| Content input | Native controls receive their existing events. Cava retains double-click mode switching. Adapters request body dragging only after their content actions decline the event; the container does not intercept every body click. |
| Chrome input | Borrowed close region retains the current capped 40×26-point top-right rule, with no added glyph/title. Palette fallback uses its existing close/title metrics. Resize handling keeps each window's existing permitted edges and minimums; do not infer active grips from decorative pixels. |
| Dragging/docking | Call the existing `windowWillStartDragging`, `windowWillMove`, and `windowDidFinishDragging` hooks, with title/body origin distinguished. Keep the window delegate and current resize mechanism. Only one participant handles a drag sequence. |
| Hidden title bars | Preserve each window's current hide-title-bars result, characterized before migration, including chrome translation and hit regions. Encode it in a host layout policy; no per-view WMP adjustment remains after migration. Compact library mode suspends the host and uses its existing compact path. |
| Accessibility/focus | Preserve content identifiers and responder state; expose a labeled close accessibility action for the invisible borrowed close target. Decorative artwork is not an accessibility control. |
| Closing | Detach the consumer and stop host-owned observation. Follow existing controller behavior for stopping content consumers; closing must not create a replacement content model. Reopen uses a new consumer token. |
| Leaving WMP | Detach before replacing/reparenting views, restore the controller's original content root and content mode, remove host observers, and let the existing family path lay out. Late completions cannot reattach a host. |

Use a layer-backed transparent overlay first. Prove AudioAnalysis's Metal panes and Cava animation
remain below it on screen at both scales. If a backend fails, do not assume an extra `needsDisplay`
fixes GPU ordering: prototype a host-owned composition path with the backend's completed frame,
or retain that window's existing WMP path until such a path passes. No blanket GPU readback is
authorized by this design. Record the selected strategy and its cost before migrating the other four.

`HostedWindowBorderLayout` remains the only owner of outer size, minimum size, anchoring, and
interior persistence. The container never calls `setFrame` to settle artwork. The layout owner
receives the container's applied presentation rather than independently asking the provider for
another answer. Existing behavior for unmigrated windows remains behind its current path.

### Publish an explicit presentation state

Today `artwork(for:)` may return exact artwork, a scaled previous frame, or nil while also scheduling work. Nil can mean pending, unavailable, or refused. Geometry, rendering, persistence, and hit testing separately query this state, and one global style notification signals both palette changes and completed frame sizes.

Publish an immutable presentation result containing:

| Field | Purpose |
|---|---|
| Skin identity and generation | Reject stale results and distinguish different archives with structurally similar templates. |
| Requested point size and backing scale | Make render identity explicit. |
| Readiness: pending / provisional / exact / unavailable / failed | Separate transitions from permanent policy decisions. |
| Image and resolved content geometry | Ensure layout and paint consume the same answer. |
| Coordinate-space declaration or inset-based adapter | Prevent a raw top-left rect reaching a bottom-left fill. |
| Donor class, scaling policy, and overlay policy | Avoid re-inferring behavior in each view. |
| Diagnostic reasons and revision | Explain why a donor was selected, repaired, or refused. |

Persist user interior changes only against an appropriate resolved state. Keep the current generation protection, but test late completion after switching skins and out-of-order size completions explicitly.

The provider currently keys its cache by rounded width/height and obtains scale from `NSScreen.main`. It also keeps one `mostRecent` frame across requests, with a 15% size guard for panels. Those are concrete audit targets: use the destination window's scale, include it in render identity, and associate provisional results with a request/window lineage rather than an unrelated window's most recent completion. These are design risks identified from code, not claims of newly reproduced defects.

Have the host consume geometry and artwork together. Do not add an unbounded resize-to-fit feedback loop: below-floor rings intentionally scale, so reference donor insets and final rendered insets can differ. Represent that policy explicitly, allow bounded settling, and verify interior preservation within a documented tolerance.

### Request identity, state transitions, and resource ownership

Use two identities: a render key shared by identical renders, and a consumer request token that
controls delivery. The render key is `(archive SHA-256, presented player view ID, donor-plan
revision, renderer policy revision, canonical point size, destination backing scale)`. Hash archive
bytes off the main thread during loading; do not equate skins by template structure alone. Include
diagnostic rendering switches in the policy identity when enabled. Canonicalize dimensions to the
destination pixel grid (`round(points * scale) / scale`), reject non-finite/non-positive inputs,
and retain both requested and canonical dimensions in diagnostics.

The consumer token is `(consumer UUID, skin generation, request sequence)`. Sequence advances on
size, scale, donor, and layout-policy changes. An exact cache hit may be shared across windows;
provisional artwork may come only from the same consumer and skin/donor generation. Retain the
existing panel 0.85–1.15 per-axis provisional guard. A ring may scale its own last exact frame.
Never scale a provisional frame repeatedly or borrow another consumer's last completion.

| State | Visible geometry and paint | Completion/retry behavior | Persistence |
|---|---|---|---|
| `pending` | Current WMP palette chrome and its fallback metrics; no old-skin image. | One request outstanding; no reschedule from paint/hit testing. | No write. |
| `provisional` | Same-consumer last exact image scaled once to target; image and scaled geometry form one snapshot. | Exact work outstanding. Scale-only transitions may reuse the image temporarily at its old pixel density. | No write. |
| `exact` | Image and resolved geometry for the current render key. | Stable until a new request or palette/layout revision. | Eligible after user resize completion and settling. |
| `unavailable` | WMP palette chrome. Reason distinguishes no donor, donor-wide refusal, and size-specific refusal. | No donor/donor-wide refusal waits for a new donor generation; size refusal retries only at a different render key. | Eligible only after fallback growth/settling finishes. |
| `failed` | WMP palette chrome with diagnostic error, not a silently reused old image. | No automatic same-key retry; explicit retry or a new key may retry. | No write; retain last committed interior. |

A geometry-only reference-insets result is a separate generation-tagged provider event used by
border layout; it is not `exact` artwork. Palette changes update the same immutable presentation
with a new revision without rerendering unchanged artwork. On receipt, the container checks all
token fields, stores the snapshot, lays out children and hit regions, then invalidates display in
one MainActor transaction. Cached stale-size completions may remain useful, but cannot replace the
current presentation. A new skin invalidates reference insets, provisional history, refusals, and
consumer requests even if its derived template compares equal.

Observe the destination window's backing-property changes. Detached windows defer rendering until
they have a screen; test requests provide scale explicitly. A screen move with a scale change
creates a new request. All scene builds, expressions, rendering, hashing, and image analysis remain
on the WMP background executor. MainActor handles only requests, immutable delivery, and AppKit.

Keep the 12-entry exact cache initially. Coalesce identical in-flight render keys and keep at most
one queued latest request per consumer; superseded queued work is discarded. Serialize access to
the provider-owned builder/image store until their concurrency contract is proven. Detaching drops
callbacks and queued work; active work may finish into the cache without touching the closed window.
Record cache bytes, queue length, and render duration during the prototype. Do not add permanent
failure entries without a scope/reason, or allow an unbounded live-resize task backlog.

### Interior preservation and bounded settling

Keep `hostedInteriorSize2.<accessibilityID>` semantics and keys during migration. An interior is the
user's nominal borderless size. Donor reference insets determine outer growth; resolved per-size
insets determine the actual content rectangle. Below-floor rings can make those differ. Preserve
the nominal interior exactly (within backing-grid rounding); do not claim the visible hole is
identical or force the donor floor. Record both sizes and the below-floor/extent scaling reason.

1. At first attachment, read saved interior or derive it from the controller's initial outer size
   and original fallback metrics, before any donor growth. Read the original minimum at the same
   time. Never derive these from a window already grown by a different frame.
2. When reference insets arrive or the donor changes, compute `nominalInterior + referenceInsets`
   once, with the existing top-left anchor and screen-position clamp. No outer-size adjustment is
   triggered solely by the arrival of exact per-size artwork. A donor-wide refusal returns to
   fallback chrome once. A size refusal may return to fallback once; latch that refusal for the
   current growth transaction so shrinking to fallback does not immediately retry donor growth.
3. Allow at most one corrective `setFrame` after the initial growth for backing-grid/docking
   settlement. Retain the existing 1.5-point application slack and 2-point settling classification.
   If still outside 2 points after correction, report `geometry-unsettled`, stop corrections, and
   retain the prior persisted interior. A new user resize or donor change begins a new transaction.
4. During user resizing, capture the nominal interior at gesture start. For borrowed chrome,
   update that interior by the user's outer-size delta, excluding programmatic growth/docking
   corrections; this avoids reading provisional or below-floor border differences into saved
   preferences. For stable palette chrome, subtract fallback metrics. Clamp to the stored nominal
   minimum. Track programmatic changes with transaction IDs, not just a transient boolean.
5. Commit at end of live resize only after the final request is `exact` or settled `unavailable`.
   If pending, retain the candidate in memory until that same request settles. Superseding skin,
   scale, size, or close events cancel the deferred write. Tests must cover custom resize handlers
   as well as AppKit live-resize notifications; route both through begin/update/end callbacks.

For a same-skin resize, the outer size chosen by the user remains authoritative; exact artwork does
not cause another growth pass. Border layout uses the resulting nominal interior on the next skin
change. Moving or closing a window without resizing never rewrites its interior. No migration of
old defaults is required unless implementation deliberately changes these semantics, in which case
that migration must be specified and tested separately.

### Make donor inference inspectable before adding more rules

`WMPHostedFrameTemplate.swift` is 1,776 lines at the reviewed revision and combines selection, classification, rendering, cropping, repair, pixel measurement, fill removal, and panel slicing. Splitting files alone will not improve compatibility. Split responsibilities around testable outputs:

1. **Donor selection:** candidate list, score, selected client region, rejection reasons.
2. **Frame plan:** retained/subtracted node IDs, resize policy, panel slice lines, structural evidence.
3. **Composition:** render and apply bounded repairs using the existing engine.
4. **Validation:** geometry and paint diagnostics, provenance, fallback reason.

Keep successful behavior during the extraction. The old assembly and unclamped whole-view comparison switches are still useful historical controls, but should be clearly marked as diagnostic variants rather than equal production strategies.

Do not turn a new confidence score into an automatic palette fallback for frames currently accepted. Expose confidence/reasons for triage first; any new fallback policy requires measured visual review. The existing requirement is to wear the skin where it can be themed, and the history includes rejected attempts that removed borders from windows.

## The harder question: should donor layout execute skin scripts?

The current frame builder is outside the live script runtime. It evaluates scene layout but does not run the donor's full resize handler. Alienware Invader's missing rail length is a direct example of authored behavior the borrowing path has to repair.

There is a potentially broader fix here: derive a reusable frame from a **resolved donor presentation**, including the layout mutations the donor itself requests. However, merely invoking `onResize` is not sufficient. Handlers can depend on initialization, other views, timers, preferences, and player state. Running them against the user's live runtime to synthesize every hosted size could mutate the actual player or cause reentrancy.

Treat this as a bounded experiment after the hosting/test work:

- Use an isolated runtime with controlled initial state and intercepted host commands; never resize the real donor to harvest its frame.
- Execute the necessary lifecycle sequence and export an immutable geometry/paint plan.
- Reuse existing resource limits, and provide process-level timeout recovery if script execution cannot be safely interrupted. A timeout that merely stops awaiting a stuck queue is insufficient.
- Compare against the existing path on script-sized donors and their counterexamples at several dimensions.
- Promote the approach only if it eliminates repair rules and increases verified coverage without introducing state instability or unacceptable cost.

A single captured live snapshot is not a general solution either: geometry captured at one size need not express how it changes at another. A universal nine-slice of every donor would similarly lose authored layout, overlaps, and behavior. Retain the proven panel-specific slice path.

## Reduce the test matrix by separating the axes

The expensive manual matrix is approximately skins × windows × dimensions × lifecycle states. Separate those axes where the contract permits it, then retain deliberate cross-axis spot checks.

### A. All-skin donor sweep, no native-window multiplication

Extend the existing hosted-frame probe to accept a size/scale matrix in one corpus invocation, reusing loaded archives and build products. Existing `WMP_HOSTED_FRAME` accepts a single size. Cover:

- Actual initial and minimum sizes collected by the isolated controller inventory described below;
  the current registry supplies only optional live windows and fallback metrics, not size metadata.
- Short/wide analyzer geometry and tall library geometry; keep 357×238, 550×464, and 710×810 as historical comparison points, not permanent substitutes for current defaults.
- Points immediately below/at/above a donor floor or panel feasibility boundary.
- A small deterministic sample of unusual aspect ratios and both 1× and 2× backing scales.

Emit machine-readable records and PNGs indexed by archive hash, donor ID, dimensions, scale, and renderer revision. The current frame dump uses `<view>-frame.png`; a multi-skin/multi-size runner must namespace it to prevent silent overwrites.

**Size inventory.** For the first implementation, instantiate all eight growth participants in an
isolated test app/profile with no saved window frames or interior preferences. Capture controller
initial dimensions, original `minSize`, fallback metrics, and the main-window/UI-size inputs before
enabling border growth. Also capture the default-opening placement pass: several controllers adapt
their size to the main window, so constructor size alone is insufficient. Enumerate supported UI-size
settings and retain distinct outputs. Convert these records to nominal interiors by subtracting their
fallback metrics. Generate donor outer-size cases from those interiors plus resolved reference
insets, while retaining the historical fixed-size cases. Tag every sample as constructor, first-open,
minimum, or donor-grown; a live window's already-modified `minSize` is not a source default.

Store a versioned JSON inventory artifact with controller revision and inputs. A test asserts eight
distinct registered windows were instantiated; nil registry entries fail inventory generation rather
than silently reducing coverage. A later pure metadata registry is optional, not a prerequisite.

**Donor-selection parity.** Today the probe chooses authored startup view (then document order),
while `publishSurfacePalette` passes the actually presented player view to `configure`. Add an
optional explicit player-view input to the probe and record both selection input and resulting
donor ID/plan signature in every JSON record. The default stays compatible with the current probe.
For each live representative capture, export its presented player-view ID and rerun the corresponding
probe case with that input; assert donor ID and plan signature match before comparing pixels.
Include a skin whose startup candidate cannot open and a synthetic pair of eligible donors whose
ranking changes with player-view selection. A mismatch is a selection failure, not an image diff
to waive. General corpus records must state that they cover startup selection, not every runtime view.

**Matrix interface.** Add proposed `WMP_HOSTED_FRAME_MATRIX=<json-file>` alongside the existing
single-size flag; specifying both is an error. The JSON carries a schema version and cases with
`widthPoints`, `heightPoints`, `backingScale` (initially 1 or 2), and optional `playerViewID`.
Reject malformed/non-finite/non-positive dimensions, unknown explicit view IDs, and duplicate case
IDs before rendering. Add a dedicated corpus wrapper `scripts/wmp_hosted_frame_sweep.sh` reusing
the existing exclusion list and build/test discovery. Load each archive once per invocation and
reuse its private builder/store serially across cases. Preserve the existing one-size text output.

Each JSONL result includes archive hash, player input, donor ID or absence reason, case ID, point
and pixel dimensions, scale, policy/revision identity, status, insets, gaps, and artifact paths. Use
`<archive-hash>/<player-input-hash>/<case-id>/<policy-revision>/frame.png`; include a run manifest
mapping opaque hashes to readable names. Emit a record for refused/failed cases too. Fail the run
on missing records, duplicate paths, or PNG write errors. Register new flags and commands in the
owning harness reference in the same implementation change.

Record gap lengths in points **and** fractions, content geometry, alpha coverage, overlay mode, selected/rejected repairs, and provenance. Check finite geometry and valid usable regions; flag violations for review rather than silently clipping them to make the test pass. Track known violations explicitly.

Add property-style checks where the donor policy supports them: panel border thickness remains stable; repair leaves the accepted content rect unchanged; coordinate conversion round-trips; requested-size ordering does not alter the final exact result. Do not assert that every ring keeps constant borders below its floor, or that every transparent notch is a defect.

### B. Every native window against a few synthetic difficult frames

Build small owned fixtures that isolate integration hazards: strongly asymmetric top/bottom insets, transparent outer corners, a bezel protruding into the client region, a deep side rail, a thick sliced panel, and palette-only fallback. They provide reliable expectations without relying on commercial artwork.

Run all six requested windows against these fixtures through the real host. Include initial opening, delayed frame arrival, multiple animation frames, resizing, skin switching, closing/reopening, and restored interior sizes. Check native subview placement as well as final visible composition. Force delayed and out-of-order completions deterministically.

Deliver this in two stages: first characterize the existing six views using their current
composition paths; then run the same expectations through the new container as each window migrates.
The first stage needs no new host. Introduce a WMP-gated test presentation source at the existing
artwork/style boundary, with restoration in test teardown. The production source remains the default.
The container later receives `WMPHostedPresentationSource` by initializer injection. A manual fake
retains callbacks by consumer/request token and exposes explicit `complete`, `refuse`, and `fail`
operations. Tests choose delivery order; no sleeps or probabilistic task scheduling simulate races.

Use an isolated defaults suite for unit tests. Live tests use a disposable app profile and record its
location; if app-wide defaults cannot yet be redirected, implement that test seam before automation.
Never clear the user's standard defaults to establish a baseline.

### Test targets, readiness, and release gates

Proposed XCTest classes below belong to the existing `NullPlayerAppTests` target. These names and
commands describe deliverables to add, not tests already present:

| Test class | Required assertions |
|---|---|
| `WMPHostedPresentationTests` | Late old-skin/closed-consumer results ignored; equal templates from different archives cannot share identity; exact output independent of request order; same-consumer provisional rule; refusal scope; backing-scale transition; bounded queue/cache; failed requests do not spin. |
| `WMPHostedBorderLifecycleTests` | Delayed reference insets, exact/provisional transitions, panel refusal, below-floor rings, two-point docking settlement, exhausted correction budget, user resize during pending work, close/reopen, mode switch, and unchanged persisted interiors unless a settled user resize commits. |
| `WMPHostedContainerTests` | Synthetic ground, clipping, overlay order, flipped/unflipped child placement, hit regions, focus, accessibility, palette updates, and detach behavior. Cava and AudioAnalysis are the first actual-view adapters. |
| `WMPHostedWindowIntegrationTests` | All six real views; body/title dragging and docking; content double-click/menu/scroll actions; close target; resize minimums; title-bar visibility; library compact enter/exit; restoration. Include both scales and scale changes. |

Run each as `swift test --filter <ClassName>` during its implementation, then `swift test` before
landing. Existing hosted panel/ring/surface tests remain required. Static XCTest snapshots are not
the GPU acceptance gate: add `scripts/wmp_hosted_window_capture.sh` for the live isolated app, using
the existing app-control capture mechanism and accessibility identifiers. Document its exact CLI
in the harness when implemented. It must exit nonzero for timeout, missing/wrong-sized captures,
selection mismatch, or an unexplained failed visual assertion.

Publish a DEBUG readiness record per window containing consumer/request token, applied revision,
readiness state, donor signature, scale, content bounds, geometry-settling status, and completed
content frame count. Capture only after the latest requested presentation is applied, layout is
complete, geometry has settled, and at least two content frames have completed since application.
For static content, count completed display passes instead. A 10-second deadline fails that case;
it is a harness timeout, not permission to capture an unsettled window or a production rendering
deadline. Advance synthetic animation through at least 120 frames and compare the chrome mask at
frames 1, 2, 60, and 120. Live GPU captures use backend completion/presentation signals and a window
server capture after that signal, with request identity rechecked afterwards.

Initial measurable acceptance thresholds:

- Synthetic coordinate round trips: absolute error at most `1e-6` point. Pixel-aligned child/frame
  bounds: at most one backing pixel. Outer placement after docking: at most 2 points as specified
  above. Nominal interior drift across 20 skin switches without user resize: at most one backing
  pixel, with no preference writes. Visible below-floor content differences are reported separately.
- Synthetic solid-color/alpha fixtures: exact expected RGBA values away from a one-pixel raster
  edge band. Test edge geometry separately within one pixel; never exclude an entire narrow rail.
  Across animation frames, static chrome pixels must remain identical.
- Same-machine/same-scale extraction-only corpus changes: unchanged plans produce identical image
  hashes and geometry records. Changed records require an attributed rule and reviewed before/after
  artifacts. No universal percentage-of-different-pixels pass threshold for real skins; baseline
  exceptions name the archive hash, case, reason, and supporting evidence.
- Live capture dimensions must match expected backing pixels after the capture tool's documented
  shadow/crop treatment. A wrong-size or occluded capture is invalid evidence. Every synthetic fixture
  must detect its corresponding intentionally injected ground inversion, omitted relayout, or
  overwritten overlay before that test is accepted as regression protection.

Compatibility coverage is wider than the migration list. Run waveform and ProjectM through their
unchanged WMP integration with the changed provider, including late artwork and ProjectM animation.
Exercise playlist/EQ routing plus their native fallbacks; assert they never join border growth.
For Classic, Original, Original-Metal, and Winamp Modern, assert no WMP host is installed, then
compare representative layouts, close/drag behavior, and restoration with the pre-change baseline.
Test entering and leaving WMP with windows already open. Shared code changes must retain explicit
family gates; screenshot stability alone does not establish that lifecycle side effects are absent.

This is where the TheUnit ground inversion and late-layout failures should become automatic regressions. A correct frame PNG cannot substitute for this suite. A plain bitmap snapshot may also omit GPU or independently composited children; keep a real on-screen capture route for those backends.

### C. Representative real-skin integration pack

Choose by exercised mechanism, not popularity or filename count. Start with these documented cases and prune only after recording coverage:

| Mechanism | Candidate evidence |
|---|---|
| Ordinary ring and large transparent corner assets | Halo 2 |
| Fixed, initially hidden/off-canvas panel | anemone |
| Inner rail, no dominant fill, asymmetric insets, geometry grips | TheUnit |
| Script-sized rail, tall-window boundary, furniture reclaim | Alienware Invader |
| Below-floor layout and intruding bezel | Back to the Future Trilogy |
| Donor floor and reclaimed rack | Ice |
| Rack-reclaim counterexamples | Star Wars, STALKER, WoW, Halloween |
| Repair must not move the content hole | KungFuChaos, The_Last_Samurai |
| Pictorial interior versus removable solid fill | Scooby Doo |
| Baked-in controls and ambiguous panel suitability | Gorillaz |

Select a no-donor fallback from the current census as well. These are seed candidates, not a claim that this list is the minimal complete set. Generate feature signatures from frame plans, group shared structures, and use a coverage table to choose representatives. Keep materially different bitmap/alpha variants even when markup matches.

Automate opening and capturing each window alone using stable accessibility identifiers. Validate capture dimensions and frame readiness; avoid assuming a fixed sleep proves settlement. Preserve the harness's warning that off-screen captures can silently return the wrong image and transparent windows can show windows behind them. Restore user placement or use an isolated test profile.

### D. Human review of exceptions, not every cell

Produce a contact sheet/report grouped by changed frame plan and failure signature. Show before/after images on both checkerboard and solid backgrounds, alpha differences, content outlines, and the affected window sizes. Human review should focus on changed clusters, new structural signatures, borderline inference, and rotating real-skin spot checks.

Keep automated full-corpus comparisons for shared engine changes. A stable image only proves no change; it does not establish correctness. Every reported defect should add its triggering case and at least one counterexample that would fail under an overly broad fix.

Illustratively, 185 skins × 6 windows is 1,110 live combinations before adding states. A 10-skin representative pack × 6 windows is 60 live combinations, while the full 185-skin size sweep remains automated. This is an illustration of reduced **live review**, not a measured runtime saving or a guaranteed coverage ratio. Periodic broader live sampling remains necessary for interactions the factorization misses.

## Implementation order and acceptance criteria

| Priority | Deliverable | Acceptance criterion |
|---|---|---|
| 1 | Size inventory, selection parity, multi-size output, uniquely named artifacts | Eight growth participants inventoried before growth; live/probe donor identity matches; historical tall-rail cases recorded; no overwritten/missing captures. |
| 2 | Synthetic characterization fixtures against current window paths | Covers six windows without depending on a new host; deterministic injection works; deliberately introduced composition faults are detected. |
| 3 | Explicit presentation state/provider identity and border lifecycle | State/geometry tests pass; stale delivery cannot apply; no provisional persistence; scale changes obtain correct artwork; queued work is bounded. Preserve legacy consumers through a compatibility facade until migrated. |
| 4 | Cava/AudioAnalysis container prototype | Actual animated/SwiftUI/Metal composition, input, docking, and both scales pass the live gate. Record backend strategy and cost; if it fails, resolve it here before wider migration. |
| 5 | Flow, PeppyMeter, Spectrum, library migration, one at a time | All six use the host contract; each passes integration and live captures before advancing; unmigrated WMP consumers and other families pass compatibility checks. |
| 6 | Inspectable donor plans and representative selection | Each inference has a reason and regression coverage; every changed rule identifies affected corpus signatures. Selection signatures needed for parity are introduced in stage 1; full extraction waits until here. |
| 7 | Isolated script-layout experiment, separate proposal | Demonstrably removes repair dependence across a measured class; otherwise remains an experiment. Not required to finish the hosting migration. |

Track changes in distinct failure classes, windows requiring duplicate edits, invalid geometry, unexplained visual changes, manual captures reviewed, render/cache cost, and time to resolve reports. Count both numerator and eligible population when claiming corpus impact. More accepted frames or fewer diff pixels alone are not quality metrics.

## Documentation audit — resolved 2026-09-18

The original audit identified D1–D20 against the reviewed revision. All listed corrections have
now been applied to operational documentation and source comments. This completion record replaces
the stale imperative findings; the proposed hosting implementation above remains unimplemented.
No runtime behavior changed as part of this documentation cleanup.

| ID | Resolution |
|---|---|
| D1 | [Compatibility](compatibility.md#phase-6-tags-and-native-surfaces) now describes available native windows, WMP palette/borrowed-frame theming, playlist/EQ routing and growth exceptions, and unskinned windows. |
| D2 | [User guide](user-guide.md#supported-format-and-deliberate-limitations) lists available windows and fallback behavior; removed the obsolete switch-mode instruction. |
| D3 | [Harness](../../skills/wmp-skin-guide/reference/harness.md#the-probe-flags) now gives `gaps` in emitted order: top, left, bottom, right. |
| D4 | [Capture guidance](../../skills/wmp-skin-guide/reference/harness.md#capturing-the-hosted-windows-one-at-a-time) compares donor, dimensions, scale, readiness, and geometry before attributing a symptom to one window. Retains the requirement to capture every affected window. |
| D5 | Deleted the obsolete caption-scaling paragraph and nonexistent `drawBorrowedCaption` guidance from the owning skill. Retained the current no-added-title/glyph rule and useful rejected-approach history. |
| D6 | [Current hosting contract](../../skills/wmp-skin-guide/SKILL.md#current-hosting-contract) names the eight border-growth participants and playlist/EQ exceptions; the checklist now scopes its growth step accordingly. |
| D7 | Skill scaling guidance distinguishes exact panel slicing, ring floor/extent scaling, and provisional scaling. `wasScaledToFit` is not a readiness or exclusively below-floor flag. |
| D8 | [Dossier index](../../skills/wmp-skin-guide/reference/skins/README.md) marks W210/W212/W228 and the open-resize defect closed, and distinguishes rack removal from rail preservation. |
| D9 | Harness distinguishes default whole-view repair gating from diagnostic assembler rejection; whole-view rendering is no longer claimed to guarantee complete rails. |
| D10 | Added a dedicated existing `WMP_HOSTED_FRAME_SCALE` entry, documenting parsing/default, valid-use guidance, point dimensions, and actual raster/cropped PNG dimensions. The original absence claim was incorrect; the flag had been described inside the larger frame entry. |
| D11 | Harness labels test-probe versus app-only execution contexts instead of claiming every flag is read by the test. |
| D12 | Skill now scopes the animation blind spot to the current static frame probe and requires live-host, multi-frame verification. |
| D13 | [Frame-template comments](../../Sources/NullPlayer/WMPSkin/WMPHostedFrameTemplate.swift) describe whole-donor rings and sliced panels; `ringNodeIDs` is no longer documented as the default paint whitelist. Also corrected the stale floor-bypass comment. |
| D14 | Template and [frame-value comments](../../Sources/NullPlayer/App/Skinning/SkinnedSurfaceFrameArtwork.swift) classify corner width as legacy metadata, not the active close inset. |
| D15 | Frame-value comments describe extent/provisional scaling and the caption band's geometry/hit-area role. Corrected the related assumption that every image is target size times backing scale. |
| D16 | [Provider refusal comment](../../Sources/NullPlayer/Windows/WMPSkin/WMPHostedFrameProvider.swift) identifies the diagnostic assembler's donor-drop policy without claiming all sizes fail. |
| D17 | [Library painter comments](../../Sources/NullPlayer/Windows/PlexBrowser/PlexBrowserView.swift) distinguish palette fallback from WMP borrowed geometry and explain conditional client-hole clipping. |
| D18 | [Notification declaration](../../Sources/NullPlayer/App/WindowManager.swift) documents repaint, relayout, border growth, and readiness limits; the palette accessor refers to that contract. |
| D19 | [Phase 3](phase-3-handoff.md), [Phase 5](phase-5-handoff.md), and [Phase 6](phase-6-handoff.md) carry historical/superseded banners linking to the current hosting contract. Their historical outcomes remain intact. |
| D20 | User guide describes the persistent in-process script context on its serial queue and removes the killable-helper/deadline-recovery claim. |

### What should not be “corrected” without evidence

The reported populations of 180, 184, and 185 archives, or 32 versus 40 panels, are not inherently contradictory when they refer to different dates, sizes, or derivation stages. Keep their original measurement context and add a current census separately. Likewise, W210's historical paint-order explanation and W212's later rail analysis address distinct stages; retain the reasoning while making their boundaries clear. The phase-7 release-gating claim is already explicitly challenged by the owning skill, but it is outside this hosted-window review's independently verified findings.

Keep future operational changes in the owning skill's current contract and retire superseded instructions in the same change. Historical measurements and rejected approaches remain useful when their scope and date are explicit.

## Source map

- [WMP owning skill](../../skills/wmp-skin-guide/SKILL.md): hosted-window rules and onboarding checklist.
- [Harness reference](../../skills/wmp-skin-guide/reference/harness.md): probes, captures, limitations, corpus comparisons.
- [Skin dossiers and counter-evidence](../../skills/wmp-skin-guide/reference/skins/README.md), especially [TheUnit](../../skills/wmp-skin-guide/reference/skins/the-unit.md), [Alienware Invader](../../skills/wmp-skin-guide/reference/skins/alienware-invader.md), and [Back to the Future Trilogy](../../skills/wmp-skin-guide/reference/skins/back-to-the-future-trilogy.md).
- [Frame template](../../Sources/NullPlayer/WMPSkin/WMPHostedFrameTemplate.swift): `derive`, `artwork`, `composeRing`, `ringRender`, `borderInsets`, and pixel/repair policy.
- [Frame provider](../../Sources/NullPlayer/Windows/WMPSkin/WMPHostedFrameProvider.swift): cache, provisional artwork, generation guards, notifications.
- [Border layout](../../Sources/NullPlayer/App/Skinning/HostedWindowBorderLayout.swift), [frame value](../../Sources/NullPlayer/App/Skinning/SkinnedSurfaceFrameArtwork.swift), and [chrome](../../Sources/NullPlayer/App/Skinning/SkinnedSurfaceChrome.swift).
- [WindowManager](../../Sources/NullPlayer/App/WindowManager.swift): `hostedSurfaceFrameArtwork`, `hostedSurfaceBorderInsets`, `hostedBorderWindows`.
- [Library painter](../../Sources/NullPlayer/Windows/PlexBrowser/PlexBrowserView.swift): `drawWinampModernChrome` and hosted-frame layout; despite its historical name this also handles WMP borrowed artwork.
- [Render probe](../../Tests/NullPlayerAppTests/WMPRenderDumpTests.swift): `hostedFrameLine`; [panel tests](../../Tests/NullPlayerAppTests/WMPHostedPanelFrameTests.swift); [rail threshold tests](../../Tests/NullPlayerAppTests/WMPHostedRingSpanTests.swift).
- [Corpus sweep](../../scripts/wmp_render_sweep.sh) and [subsystem blueprint](../../skills/skin-subsystem-blueprint/SKILL.md).

Commit identifiers in the evidence table are local repository references, inspectable with `git show <hash>`.
