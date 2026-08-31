# Windows Media Player (`.wmz`) skin support — phased integration plan

**Status:** proposed implementation plan; no WMP production code has been written.

**Research input:** `/Users/ad/Projects/nullplayer/docs/wmp-skin-support-spike.md`, supplied from a
separate unmerged branch and used as analysis only.

**Plan date:** 2026-08-31.

**Planning branch:** `plan/wmp-skin-integration`.

**Planning worktree:** `/Users/ad/Projects/nullplayer-wmp-skin-integration`.

**Planning baseline:** `origin/main` at `56c198ec` when the worktree was rebased. The WMP design
must use only architecture present on remote main plus changes introduced explicitly by this plan.

## 1. Target and locked boundaries

Build Windows Media Player skin support as a fourth `PlayerUIMode`, internally named `wmp`. It must
load user-supplied `.wmz` archives and render their `.wms` views without changing Classic, Original,
or Original-Metal behavior.

- Engine/model code lives in `Sources/NullPlayer/WMPSkin/`; AppKit code lives in
  `Sources/NullPlayer/Windows/WMPSkin/`.
- Introduce `PlayerUIControllerFamily` with `.classic`, `.nullPlayerModern`, and `.wmp`, then add a
  `.wmp` mode. Do not extend the current `usesModernControllers` Boolean into another ambiguous
  fallback.
- Give WMP its own importer, installed-skin store, preference keys, diagnostics, and `WMPSkins/`
  support directory.
- Reuse Original window/provider conventions as patterns only. Do not express `.wms` as `skin.json`.
- Build the bounded archive, retained graph, renderer, host bridge, reporting, and teardown as
  independent WMP types. Do not plan against subsystems that are absent from remote main.
- Real Microsoft/community skins remain user-supplied and untracked. Commit only small original
  synthetic fixtures generated or authored for NullPlayer tests.
- WMP video/effect elements initially host a safe NullPlayer surface or a documented placeholder.
  Never load WMP plug-ins, ActiveX, registry data, DLL resources, or shell integrations.

The spike's JavaScript watchdog proposal needs a new proof. The current macOS 26.2 SDK headers do
not expose `JSContextGroupSetExecutionTimeLimit`; a main-process `JSContext` therefore cannot be
accepted for untrusted scripts merely because it runs on another thread.

## 2. Worktree and branch discipline

This plan was created only in the planning worktree named above. The dirty source checkout at
`/Users/ad/Projects/nullplayer` is not used for WMP changes.

After approval, implementation uses this dedicated integration checkout:

```text
branch:   feat/wmp-skin-support
worktree: /Users/ad/Projects/nullplayer-wmp-skin-support
base:     accepted plan commit on the then-current origin/main
```

Create it from a clean committed base. Do not copy uncommitted files from the original checkout and
do not implement on the planning branch. Every build, generated artifact, live run, and phase commit
runs from the implementation worktree. Record these at the start and end of every phase handoff:

```bash
pwd
git branch --show-current
git status --short
git rev-parse HEAD
```

Each phase ends in a reviewable commit and `docs/wmp-skin/phase-N-handoff.md`. If the base branch
changes shared mode plumbing, rebase in the dedicated worktree and rerun the complete mode/lifecycle
gate before continuing.

## 3. Target architecture

```text
user-supplied .wmz
        |
        v
bounded archive -----------> typed diagnostics / compatibility report
        |
        v
resource provider -> text decoder -> bounded XML -> retained WMP graph
        |                                           |
        +------------> image cache ----------------+----> layout/scene -> AppKit renderer
                                                    |
isolated script realm <---- bounded bridge <--------+----> bindings/events
                                                    |
                                                    v
                                               typed WMP host
                                                    |
                                                    v
                                               AudioEngine
```

Key contracts:

- Archive/XML/image work is headless and independent of an app mode.
- Layout produces an immutable scene snapshot. AppKit drawing does not own the source graph.
- Scripts exchange plain bounded values and typed commands, never Swift objects, selectors,
  filesystem URLs, network handles, or `AudioEngine`.
- The renderer retains the last valid static scene if script evaluation fails or is terminated.
- Teardown stops script work, timers, bindings, image tasks, and audio consumers before releasing
  graph/resources.

## 4. Relevant NullPlayer Studio precedent

NullPlayer Studio was reviewed at private repository revision
`8f1b9efc2231be15859d586bea0d0a6a8fd62636`: [`PlayerBridge.swift`](https://github.com/ad-repo/nullplayer-studio/blob/8f1b9efc2231be15859d586bea0d0a6a8fd62636/Sources/NullPlayer/Windows/WebSkinMainWindow/PlayerBridge.swift),
[`WebSkinMainWindowController.swift`](https://github.com/ad-repo/nullplayer-studio/blob/8f1b9efc2231be15859d586bea0d0a6a8fd62636/Sources/NullPlayer/Windows/WebSkinMainWindow/WebSkinMainWindowController.swift),
and [`PlayerBridgeTests.swift`](https://github.com/ad-repo/nullplayer-studio/blob/8f1b9efc2231be15859d586bea0d0a6a8fd62636/Tests/NullPlayerAppTests/PlayerBridgeTests.swift).
Its WebKit bridge is relevant and should be reused as a design reference, not copied wholesale:

- `PlayerBridge` exposes a narrow action vocabulary, capability allowlist, typed argument parsing,
  clamping, main-thread dispatch, outbound JSON events, request IDs/timeouts, and a 120-message/sec
  inbound rate limit.
- `WebSkinMainWindowController` uses a nonpersistent `WKWebsiteDataStore`, disables automatic JS
  windows, confines navigation/read access to the skin root, and performs idempotent teardown by
  stopping loads, removing message handlers/scripts, and clearing delegates.
- The injected shim implements state/event delivery, declarative bindings, and window-drag messages
  while CSP disables network connections and object content.
- Tests cover capabilities, clamps, rate limiting, navigation containment, handler latency, and
  teardown.

For WMP, the most promising Phase 0 candidate is a dedicated, non-visible `WKWebView` loaded with an
app-authored locked-down document—not a skin-authored HTML page. It would evaluate the `.wms` JScript
in WebKit's content process and use a WMP-specific typed message protocol. WMP rendering remains Core
Graphics; WebKit is a script realm only.

Studio does **not** prove deterministic termination of `while (true) {}`. `stopLoading()` and handler
removal are teardown tools, not a documented evaluation deadline. Phase 0 must measure whether a
dedicated `WKProcessPool`/view can be discarded and replaced within a hard deadline while a script is
spinning. If it cannot, use a bundled helper process or a bounded custom interpreter. Never fall back
to an uninterruptible in-process `JSContext`.

## 5. Phase map

| Phase | Result | Product exposure |
|---|---|---|
| 0 | Decisions, fixtures, limits, and killable-script proof | none |
| 1 | Bounded `.wmz` loader and deterministic graph | none |
| 2 | Static renderer and feasibility decision | test harness only |
| 3 | Isolated WMP app mode, importer, lifecycle | DEBUG/feature-gated |
| 4 | Mapping-image input and playable transport slice | DEBUG/feature-gated |
| 5 | Expressions, bindings, scripts, and events | DEBUG/feature-gated |
| 6 | Remaining widgets, views, hosted surfaces | opt-in beta |
| 7 | Corpus, fuzzing, performance, accessibility | release candidate |
| 8 | Public exposure, user/agent docs, upgrade policy | public |

Phase 2 is the investment gate from the spike. Phase 0 adds an earlier security gate: static
experimentation may continue if no killable runtime is found, but scripted product support may not.

## 6. Phase 0 — contracts, fixtures, and script isolation

### Deliverables

Create `docs/wmp-skin/phase-0-decision-record.md` containing the threat model, exact limits,
provenance rules, sample inventory, selected script architecture, measured timeout/teardown evidence,
packaging implications, and separate GO/NO-GO decisions for Phase 1 and Phase 5.

Create original synthetic fixtures under `Tests/NullPlayerAppTests/Fixtures/WMPSkin/`:

- UTF-8, UTF-16LE, and UTF-16BE `.wms` files;
- wrapper-directory archive and two-view skin;
- nested subview, text, image, ordinary button, mapping-image button group, and slider;
- normal-return, host-read/write, syntax-error, recursion, timer-storm, allocation-pressure, and
  infinite-loop scripts;
- traversal, absolute/drive path, case collision, symlink, excess entry/ratio/bytes, deep XML,
  oversized image, and oversized script archives.

Start with these conservative limits unless corpus evidence amends the decision record:

| Area | Initial limit |
|---|---:|
| Archive entries | 4,096 |
| Entry / archive uncompressed bytes | 32 MiB / 128 MiB |
| Per-entry compression ratio | 200:1 |
| Wrapper directories | zero or one |
| XML depth / expanded nodes | 256 / 100,000 |
| Image bounds | 8,192×8,192 and 32 Mpx |
| Script file | 4 MiB |
| Expression dependency depth / passes | 128 / 256 |
| Active timers / minimum period | 256 / 8 ms (120 Hz effective max) |
| Preference value | 64 KiB, namespaced per skin hash |
| Script message / in-flight bytes | 1 MiB / 16 MiB |

Paths are case-insensitive after normalizing Windows/POSIX separators. Reject absolute paths, drive
prefixes, `..` escape, symlinks, and case collisions. All resources use a read-only provider. Missing
optional images or `res://` localization are warnings; escape, corruption, and bounds violations are
hard failures.

### Script-runtime comparison

Prototype only enough to compare two candidates:

1. **Studio-derived WebKit realm (first choice):** app-authored blank document; nonpersistent store;
   dedicated process pool; no file read grant; `default-src 'none'`, `connect-src 'none'`,
   `object-src 'none'`; blocked navigation/new windows/downloads; WMP-specific capability/action
   allowlist; typed/clamped messages; inbound rate and payload limits; explicit handler removal.
2. **Bundled helper fallback:** JavaScriptCore owned by a helper executable/XPC service with a
   length-prefixed bounded protocol and no filesystem/network/UI/native-object access. App-side
   deadline terminates and replaces the helper.

Both proofs must run normal expressions, peer reads, assignment, callback, syntax error, recursion,
allocation pressure, timer storm, and infinite loop. For the infinite loop, prove that NullPlayer/test
runner stays responsive, CPU/process count returns to baseline within a fixed deadline, a clean realm
can evaluate next, and no prior state survives. Repeat at least 100 kill/restart cycles.

Also prove DMG and MAS packaging. WebKit should avoid a new bundled executable, but only measured
hard termination makes it acceptable. If neither public-API design passes, Phase 5 is blocked and a
bounded custom interpreter needs a new estimate.

### Exit gate

- Fixture provenance is recorded; no third-party skin is tracked.
- Malicious archives fail with typed diagnostics and no partial install.
- One script design passes hard-stop, restart, memory/process, teardown, and packaging checks.
- The decision record explains why Studio mechanisms were reused or rejected individually.

## 7. Phase 1 — bounded loader and typed graph

Add independent types under `Sources/NullPlayer/WMPSkin/`:

- `WMPDiagnostics.swift`: stable codes, severity, source location, typed failures.
- `WMPArchive.swift`: `.wmz` validation and `WMPResourceProviding`.
- `WMPTextDecoder.swift`: BOM-aware decoding; no shelling out to `iconv`.
- `WMPXML.swift`: bounded parse preserving spelling, path, and source location.
- `WMPNode.swift`: closed `WMPElementKind` plus retained `.unknown` nodes for reporting.
- `WMPAttributeValue.swift`: literal, `JScript:`, `wmpprop:`, `wmpenabled:`, handler, color,
  resource, and unsupported forms, parsed without execution.
- `WMPSkinLoader.swift`: deterministic view/resource/script registries and `WMPLoadedSkin`.
- `WMPCompatibilityReport.swift`: tag/attribute/resource/script/member/event inventories.

Accept a `.wms` at root or beneath one wrapper directory. Fail ambiguous candidates unless a
documented WMP rule selects one. Resolve resources relative to the declaring file, then skin root,
always inside the provider.

Implement `WMPArchive` directly over the ZIPFoundation dependency already present on remote main.
Do not widen the classic `.wsz` loader: WMP needs stricter entry-count, byte, compression-ratio,
case-collision, symlink, root-shape, and CRC contracts. A neutral bounded ZIP utility may be extracted
later only if a separately planned classic migration preserves its behavior; it is not a WMP phase
dependency.

Tests: `WMPArchiveTests`, `WMPTextDecoderTests`, `WMPXMLTests`, `WMPGraphTests`, and
`WMPCompatibilityReportTests`. Cover every rejection, BOM/surrogate/NUL behavior, deterministic order,
duplicate IDs, unknown retention, prefix classification, resource lookup, ambiguous roots, `res://`
warnings, and 50 load/teardown cycles. An opt-in
`WMP_TEST_WMZ=/absolute/path/9SeriesDefault.wmz` test must reproduce the spike's two views, element
counts, 115 BMPs, expressions, bindings, and script list.

**Exit:** deterministic graph dump and compatibility report succeed; malformed input cannot escape
the provider or alter installed state; full `swift test` and classic/Original skin regressions pass.

## 8. Phase 2 — static layout, image pipeline, renderer, and decision gate

Add:

- `WMPGeometry.swift`: top-left coordinates, nesting, z-index, clipping, resize limits, and
  horizontal/vertical alignment/stretch.
- `WMPScene.swift`: immutable paint commands, stable IDs, hit metadata, and dirty bounds.
- `WMPSceneBuilder.swift`: resolve literal geometry only. Expression geometry remains unresolved
  with a diagnostic; do not silently convert authored code to zero.
- `WMPImageStore.swift`: ImageIO decoding for BMP/GIF/JPEG/PNG, dimension/decoded-byte checks, LRU.
- `WMPColorKey.swift`: exact RGB color-key masking while retaining real source alpha.
- `WMPRenderer.swift`: Core Graphics paint in top-left coordinates, text counter-transform, explicit
  interpolation policy.

Keep platform image/cache state out of the retained graph. Compute scene bounds once per layout
transaction and reuse them for drawing, later hit testing, and targeted invalidation.

Create a headless `WMPRenderDumpTests` path:

```bash
WMP_TEST_WMZ=/path/to/9SeriesDefault.wmz \
  swift test --filter WMPRenderDumpTests
```

It writes untracked output containing one PNG per view, resolved/unresolved counts, visible bounds,
draw order, diagnostics, peak cache bytes, and render time. Add original pixel fixtures for upright
BMPs, crops, color keys, nested offsets, stretch, clipping, z-order, and 1x/2x backing scales.

### P0/P1 decision gate

Review `vPlayer` with expressions/scripts disabled. GO requires:

- authored 859×468 root geometry;
- literal-geometry chrome/controls in expected relative positions;
- upright, correctly keyed, correctly ordered assets;
- all unresolved geometry enumerated, not hidden by fallback values;
- no fatal loader/renderer diagnostic and bounded memory/time;
- human review judges the image recognizably derived from the skin's own player view.

Record metrics, diagnostics, and GO/NO-GO in `docs/wmp-skin/phase-2-decision-record.md` without
committing Microsoft artwork. If not recognizable, stop and re-estimate JScript/layout coupling
before adding an app mode. Do not add sample-specific coordinates.

## 9. Phase 3 — isolated app mode, importer, window shell, lifecycle

Integrate the static engine behind an experimental capability gate.

### Mode and capability plumbing

- `App/PlayerUIMode.swift`: introduce the explicit three-way controller-family enum, add `.wmp`,
  display name `Windows Media Player`,
  `usesModernControllers == false`, 10-band EQ, no `ModernSkinFamily`.
- `App/AppCapabilities.swift`: add `wmpSkinMode`, initially DEBUG/experimental.
- `App/WindowManager.swift`: explicit WMP factory, reload, teardown, frame, compact-mode, visibility,
  and provider branches. All shared changes are gated on `.wmp`; existing families retain their
  previous paths.
- `App/AppDelegate.swift`: DEBUG launch hook
  `-uiMode wmp -wmpSkinPath /absolute/path/skin.wmz`.
- `App/ContextMenuBuilder.swift`: distinct WMP family submenu/actions only when capability is exposed;
  build new action-bearing menu items rather than copying them.

### WMP-owned import and state

`WMPSkinImporter.swift` owns:

- `~/Library/Application Support/NullPlayer/WMPSkins/`;
- `.wmz` validation, installed enumeration, `wmpSkinName`, and Open Skins Folder;
- complete validation before atomic replacement;
- typed actionable failures and no partial install.

Extend `AppStateManager` with `decodeIfPresent` defaults. Save `wmpSkinName` only in `.wmp`; restore
window size only for the same WMP skin/view identity while preserving safe top-left position; skip
geometry/UI scale on all mode mismatches; preserve mode-independent audio/playlist state; provide a
reset/recovery path when a selected skin fails.

### Window/controller

Add `WMPMainWindowController.swift` and `WMPMainView.swift`:

- borderless window sized/ranged by the active WMP view;
- shared top-left render and hit-coordinate conversion;
- WindowManager-mediated drag/docking fallthrough;
- safe close/minimize actions;
- synchronous idempotent teardown and a static error/fallback view.

Do not reuse a classic/Original controller as the WMP main window.
Auxiliary provider fallbacks must be explicit and WMP-gated.

Tests cover mode persistence, old-state decoding, exact-mode geometry, capability/menu visibility,
import atomicity, factory routing, and teardown. Run at least 20 cycles of
`classic → modern → metal → wmp → classic`, including failed load. Launch the sample,
resize, switch, quit/relaunch, and measure final frames through Accessibility. Smoke Compact Mode and
Compact Window; hide/disable them in WMP if unsupported rather than entering broken state.

**Exit:** WMP can display, resize, restore, switch away, and tear down repeatedly without changing
another mode or leaving workers/resources alive.

## 10. Phase 4 — mapping-image input and playable transport slice

Add:

- `WMPMappingImage.swift`: canonical non-premultiplied RGB buffer, `mappingColor → node`, per-node
  bounds, transparent/no-hit color.
- `WMPHitTester.swift`: reverse z-order, visibility/enabled/clipping, rectangular fallback, exact
  skin-coordinate pixel sample.
- `WMPInteractionState.swift`: hover, pressed, captured node, focus, sticky/down, disabled.
- normal/hover/down/disabled scene selection with targeted dirty rects.

A press remains captured by the original target until mouse-up/cancel. Determine inside/outside
release semantics from a reference run. Window dragging is the final fallthrough only after
interactive hit testing.

Add a narrow `WMPHost` and `WMPAudioEngineHost` for play/pause/stop, previous/next, seek,
fast-forward/reverse start/stop, volume/balance/mute, shuffle/repeat, time/duration strings,
command-enabled state, media metadata, and playlist index/count. Clamp inputs; keep UI mutations on
main; never expose `AudioEngine`. Do not observe realtime audio-tap notifications on `queue: .main`.

Implement semantic transport tags and literal `BUTTONELEMENT` actions needed by original fixtures.
JScript handlers remain disabled until Phase 5.

Tests cover map channel order, BMP padding/origin, scaling, transparent/unknown colors, z-order,
clipping, cache bounds, enter/exit, capture/drag/release, disabled/sticky state, teardown during
capture, typed host conversions, and accessibility children. Use real local and streaming playback
for integration.

**Exit:** the sample is clickable and plays for all non-script-dependent controls; mapped shapes do
not respond in transparent pixels; switching mode during playback preserves engine state.

## 11. Phase 5 — bounded JScript, expressions, bindings, events

Start only if Phase 0's production runtime gate is green.

### Versioned script protocol

Support create/destroy realm, register IDs/properties, evaluate an expression with dependency-read
capture, load ordered script files/inline handlers, dispatch events, apply state transactions, and
return mutations, host commands, preferences, timer requests, diagnostics, and repaint hints.

Expose a checked compatibility table for `player`, controls, settings, media, playlist, network,
`eq`, `vis`, `theme`, `view`, playlist widgets, popup presets, metadata, and element objects. Do not
dynamically bridge Objective-C. Safe unsupported members return documented defaults/warnings; deny
ActiveX, registry, shell, arbitrary URL, host file/network, modal UI, and process APIs.

When using the Studio-derived WebKit realm:

- load only an app-authored locked document, never `.wmz` HTML;
- inject the WMP compatibility object before skin scripts;
- validate every inbound body/action again in Swift even if JavaScript generated it;
- use per-skin capability sets, payload/rate/deadline checks, nonpersistent data, blocked navigation,
  and a dedicated realm/process boundary;
- retain Studio's teardown ordering but add the Phase 0-proven forced realm replacement path.

### Layout/dependency engine

Compile/cache expressions. Capture reads such as `svStub.width` and `view.width`, build a dependency
graph, and evaluate dirty nodes in stable topological order. Detect cycles, missing IDs, non-finite
values, depth/pass overflow, and cross-view reads. Commit each transaction atomically.

Resize sequence:

1. publish proposed view dimensions;
2. dirty dependent expressions;
3. evaluate under deadline;
4. validate/clamp numeric geometry;
5. resolve alignment/stretch/descendants;
6. build and atomically swap one scene;
7. publish final read-only geometry for later events.

Never block AppKit drawing on JavaScript. Keep drawing the last valid scene while a transaction is in
flight.

### Bindings, events, failure policy

Use one observable property registry for `wmpprop:` and `wmpenabled:`. Coalesce host changes on main,
send one transaction, tag origins to prevent feedback, and repaint changed nodes only. Dispatch load,
close, timer, open/play/status/mode/buffering/reception changes, click, and change in measured order.
Host-owned timers obey Phase 0 caps.

On timeout/crash: terminate the realm, cancel its timers/messages, retain the static scene, disable
scripts for that skin session, emit one actionable diagnostic, and keep skin change/mode switch/quit
functional. Preferences use a stable skin-hash namespace, bounded values/count, and reset action.

Tests cover dependency order/cycles/missing IDs, dirty propagation, numeric validation, resize
coalescing, feedback prevention, event order, preference isolation, every protocol bound, hostile
loop/crash/allocation/timer behavior during resize and teardown, and every supported/unsupported
object-model member.

**Exit:** the sample scripts load in order and run their exercised path, geometry resolves at minimum,
default, and larger sizes, bindings follow live playback, and hostile script cannot hang the app.

## 12. Phase 6 — widget completion, multiple views, hosted surfaces

Implement by capability across a small user-supplied corpus, never with sample-name conditionals.
Maintain `docs/wmp-skin/compatibility.md` as the source of truth for tags, attributes, bindings,
members, events, and deliberate limitations.

Suggested independently tested slices:

1. `TEXT`, images/subviews, focus/tab order, tooltips, accessible labels.
2. `SLIDER`, `VOLUMESLIDER`, `SEEKSLIDER`, `BALANCESLIDER`, keyboard adjustment, change events.
3. `PLAYLIST`/`DROPDOWNPLAYLIST` backed by the live playlist: selection, scroll, play, mutation.
4. `EQUALIZERSETTINGS` mapped to 10-band EQ/preamp; verify 10↔21-band mode remapping.
5. `POPUP`/preset lists through safe host menus; no arbitrary script modal UI.
6. `WMPEFFECTS` hosting a NullPlayer visualizer with correctly gated audio consumers.
7. `VIDEO`/`WMPVIDEO` as documented placeholder or existing safe NullPlayer surface.
8. Multiple views and `theme.currentViewID`, including `viewTiny`, size-range changes,
   accessibility replacement, and frame persistence per skin/view identity.

View switching is a controlled transaction: cancel input capture, stop outgoing timers, resolve the
incoming view, preserve safe top-left, apply size limits, swap scene/accessibility tree, then deliver
the view event. Bound runtime-created views/windows.

**Exit:** every sample tag is supported, compatibility-defaulted, or deliberately unsupported; full
and tiny views switch repeatedly; playlist/EQ/visualizer surfaces use live data; no consumer/timer
survives a hidden view or teardown.

## 13. Phase 7 — corpus, security, performance, regression hardening

Build an opt-in user-supplied corpus across WMP versions/styles. A report harness emits archive
facts, tag/attribute/member/event demand, unknowns, diagnostics, render metrics, and confidence.
Prioritize cross-skin capabilities. A skin is a test case, not a milestone.

Never commit corpus archives or third-party screenshots. Keep local reports outside the repository
unless explicitly approved; durable engine facts belong in compatibility docs.

Required work:

- Fuzz archive metadata, text, XML, colors, images, mapping buffers, bridge messages, and runtime
  lifecycle. Outcomes are success or typed failure, never trap/hang/unbounded allocation.
- Stress 100 rapid loads, views, modes, resize/timer storms, and realm restarts. Assert bounded
  workers, processes, file descriptors, memory, audio consumers, and cache.
- Benchmark cold/warm load, resize, hit test, steady playback CPU, and repaint area.
- Add goldens only from original fixtures; use opt-in local diffs for real skins.
- Exercise 1x/2x, multiple displays, minimize/occlusion, sleep/wake, route change, state restore.
- Audit script-realm process isolation, message authentication/validation, crash handling, and DMG/MAS
  behavior.
- Rerun Classic/Original skin and UI smoke tests after shared changes.

Release-candidate gate:

- clean-worktree `swift test` and `git diff --check` pass;
- DMG and MAS builds launch the selected script runtime, or WMP stays unavailable in that product by
  an explicit decision;
- four-mode lifecycle/restoration harness passes;
- local/stream/radio, EQ, playlist, views, docking, menus, accessibility, and recovery pass manually;
- no Phase 0 limit is weakened without amended rationale and adversarial test;
- known unsupported behavior appears in compatibility reporting and degrades safely.

## 14. Phase 8 — public exposure and support handoff

Only after Phase 7:

- enable `AppCapabilities.wmpSkinMode` in the full edition;
- remove DEBUG-only menu exposure but keep the CLI path as a diagnostic hook;
- document import/select/remove, supported versions, reset/recovery, view switching, and reports;
- add `skills/wmp-skin-guide/SKILL.md` as the technical router and update AGENTS routing;
- update release notes, packaging, support diagnostics, and third-party notices if concrete reference
  material was derived;
- document user-supplied skins and unsupported ActiveX/registry/shell/DLL/plugin behavior;
- test install/upgrade from the previous release, old state decoding, and missing/invalid selected skin.

Public Definition of Done:

1. A fresh user imports/selects a valid `.wmz` without terminal work.
2. Full and tiny sample views render, resize, accept input, and follow playback.
3. Skin controls drive local files, streams/radio, playlist, volume/balance, shuffle/repeat, seek, and
   10-band EQ where exposed.
4. Unsupported Windows-only behavior produces named diagnostics.
5. A hostile archive/script cannot escape resources, hang the app, or survive teardown.
6. Four-mode switching preserves mode-independent state and isolates geometry/preferences.
7. Existing three-family tests and live smoke passes remain unchanged.

## 15. Cross-phase verification matrix

| Concern | Headless/unit | Render/integration | Live/manual |
|---|---|---|---|
| Archive/security | adversarial originals | rapid load/teardown | failed import leaves no install |
| Encoding/XML | BOM/surrogate/depth/node | sample inventory parity | actionable error |
| Geometry | pure properties | synthetic pixels/sizes | measured frames |
| Images | format/key/origin/cache | 1x/2x probes | sample/resize |
| Input | map/capture/state | rendered-point hit probes | irregular controls/keyboard |
| Host/audio | typed fake | real local/stream engine | playback/radio/mode continuity |
| Scripts | protocol/budget/member | scripted originals | sample + hostile recovery |
| State/modes | Codable/routing | four-mode lifecycle | relaunch/missing skin/reset |
| Widgets | models/providers | per-tag fixtures | playlist/EQ/views/visualizer |
| Packaging | runtime lookup/policy | DMG/MAS launch | install/upgrade |

## 16. Risk register and stop conditions

| Risk | Early signal | Mitigation / stop |
|---|---|---|
| WebKit cannot hard-stop script | loop survives view/process replacement | use helper/custom VM; block Phase 5 |
| Helper cannot ship | signing/lookup/entitlement failure | resolve before Phase 5; no in-process fallback |
| Static layout too script-dependent | Phase 2 not recognizable | stop/re-estimate; no skin-specific geometry |
| Shared-mode regression | existing path/frame changes | explicit `.wmp` gates; isolate/revert |
| WMP archive changes classic loading | shared-loader behavior drifts | keep `WMPArchive` independent |
| Bridge exposes native power | dynamic selectors/objects | reject; plain versioned messages only |
| Resize/event storm | excess passes/main stalls | origin tags, coalescing, caps, prior scene |
| Provenance ambiguity | real skin proposed for tracking | keep untracked; originals only |
| Scope follows anecdotes | one-skin special cases | demand report and capability slices |
| Teardown leaks | growing process/timer/consumer count | phase fails until idempotent cleanup proven |

## 17. Effort and review cadence

The spike's 7–11k LOC remains plausible for engine/app code, but script isolation, packaging,
adversarial tests, and accessibility may push beyond it. Re-estimate after Phase 2:

| Phase | Range | Review focus |
|---|---|---|
| 0 | 3–5 days | script/security/package feasibility |
| 1 | 3–5 days | deterministic bounded loader |
| 2 | 4–6 days | visual evidence and decision |
| 3 | 3–5 days | shared-mode isolation/lifecycle |
| 4 | 4–6 days | hit testing/audio seam |
| 5 | 2–4 weeks | runtime, layout, object model, events |
| 6 | 2–3 weeks | widgets/views/hosted surfaces |
| 7 | 1–2 weeks | corpus/fuzz/performance/package |
| 8 | 2–4 days | exposure/docs/upgrade |

Every handoff states the worktree/branch/commit, proven outcomes, exact commands/results, artifacts,
plan deviations, open risks, and single next phase. An unrun GUI or packaging check is never marked
complete.
