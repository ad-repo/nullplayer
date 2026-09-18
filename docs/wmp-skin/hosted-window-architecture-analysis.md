# WMP native hosted windows: architecture and verification analysis

Date: 2026-09-18. Reviewed revision: `49f644425fe923a6ec4977793d0d59cfdc783eca`.

Status: WMP-only proposal, revised to enforce skin-system isolation and avoid unnecessary
architecture. No runtime changes accompany this document. The earlier container migration and
new presentation/lifecycle framework are withdrawn.

## Recommendation

Keep the existing WMP donor renderer, frame provider, and native-window integration. Fix concrete
WMP defects at their existing ownership boundary. Where multiple WMP call sites repeat the same
proven operation, use a small WMP-owned helper; do not redesign the window system to remove every
repeated line.

A donor extraction defect belongs in `WMPHostedFrameTemplate`; asynchronous WMP artwork handling
belongs in `WMPHostedFrameProvider`; a WMP composition defect belongs in the affected view’s
explicitly WMP-gated path. Start with the failing case and a counterexample, not a new framework.

## Non-negotiable scope: WMP skins only

These changes may affect `.wmp` mode only. Classic, Original (including Original-Metal), and
Winamp Modern (`.wal`) are outside the implementation scope. Their rendering, geometry, input,
animation, docking, restoration, and preferences remain unchanged. Passing regression tests does
not authorize changing those systems.

- Keep new logic in `WMPSkin/` or `Windows/WMPSkin/`, with WMP tests and documentation.
- Edit a shared app/view file only for a necessary, minimal, explicitly `.wmp`-gated correction or
  call into a WMP helper. Leave the non-WMP path intact and record why a WMP-local change alone
  cannot solve the defect.
- Consume shared chrome/value types and notifications under their existing contracts. Do not
  redesign them, extract common view code, or change Winamp Modern hosted contexts.
- Check active family and existing generation/request identity before applying delayed WMP work.
  A gate at request time does not protect a callback delivered after leaving WMP.
- If a proposed fix requires changing another skin system, stop that approach and find a WMP-local
  solution. Defer the fix if none is available; do not expand scope.

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

## Revised implementation approach

### 1. Establish the actual WMP failure before changing code

The history above explains architectural risks; it does not prove that every risk is a current
bug. For an on-screen report, follow the owning skill’s live-defect workflow. Capture the affected
window and a known-good WMP comparison at the relevant size. Record donor identity, artwork
readiness, content bounds, and backing scale using existing probes before adding instrumentation.

Distinguish extraction from integration: if the frame PNG is already wrong, fix the WMP frame
builder. If it is correct but the live window is wrong, inspect that window’s WMP layout, ground
fill, and overlay/redraw path. A defect seen in only one window may still be a size-dependent donor
defect, as Alienware Invader demonstrated.

### 2. Correct the existing WMP path

Keep whole-donor ring rendering, panel nine-slicing, donor-floor behavior, and existing palette
fallback. Preserve the recorded rail/reclaim counterexamples. Do not add donor-selection rules or
new fallback policies without a measured failing case.

For integration defects, first use the existing WMP artwork, metrics, relayout, and redraw hooks.
A necessary edit in a shared view must sit behind an explicit WMP-family check; the other-family
branch must keep its existing implementation. Keep content drawing, native children, controls,
input, and window ownership where they are.

If the same WMP coordinate conversion or frame-paint operation needs correction in multiple
places, add one narrowly named helper under `Windows/WMPSkin/` and call it only from those WMP
branches. Pass the existing artwork and geometry values. Do not introduce a new protocol,
adapter hierarchy, content-only mode, or general rendering abstraction for a small drawing fix.
A helper is useful only if it removes actual repeated policy without changing other modes.

Keep the current full-redraw behavior where borrowed artwork overlays animated content. A separate
compositing layer is not required to fix correctness, and its performance benefit has not been
measured. Do not reparent SwiftUI/Metal/OpenGL content as part of this work.

### 3. Address provider or geometry issues only when demonstrated

The provider’s main-screen scale lookup, cross-window provisional image, and nil readiness result
are audit leads, not a mandate for a new state machine. If a case reproduces, make the smallest
WMP-provider change that fixes it—for example, passing destination scale or rejecting a stale
completion—and test that behavior. Retain existing consumers and notification semantics.

Keep `HostedWindowBorderLayout`, its registry, and persistence contract. Do not introduce a second
layout coordinator, a new defaults namespace, or a restoration migration. If a WMP border defect
requires a shared-file edit, isolate the correction behind the WMP family gate and preserve all
non-WMP sizing and writes. Prove that a delayed WMP completion cannot resize or persist a window
after the family changes. If the correction cannot be isolated there, revisit the local approach.

The eight current growth participants remain the same. Playlist/EQ fallback routing and their
exclusion from border growth remain unchanged. Waveform and ProjectM need relevant WMP regression
coverage when a provider or donor change reaches them; they do not need a migration.

## Verification proportional to the change

Use existing tests, frame dumps, corpus scripts, and live capture tools. Add a small regression
fixture for the actual failure and a counterexample to an overly broad fix. Avoid a new harness
framework, synthetic event system, or exhaustive live matrix before it is needed.

| Change | Required evidence |
|---|---|
| WMP donor extraction or repair | Triggering size/skin plus documented counterexamples; existing WMP corpus comparison for a rule used across donors. Attribute changed output. |
| WMP drawing/layout in one window | Live before/after capture of that window at the failing and a normal size; native child placement if present. |
| WMP helper used by several windows | Exercise each changed WMP call site, including animation where relevant. |
| WMP provider completion/scale handling | Focused test for the reproduced transition and a live check at the affected scale or skin switch. |
| Shared-file WMP branch | Diff review confirming unchanged non-WMP path; affected behavior checked in other families and during entry/exit from WMP. |

For animation, capture multiple live frames to ensure content redraw does not erase the bezel.
For asynchronous arrival, verify relayout as well as repaint. For size-dependent defects, include
the actual failing dimensions; 357×238, 550×464, and 710×810 are useful historical cases, not a
replacement for the reported window size. Use both backing scales when the change concerns pixels
or coordinate conversion.

Use existing isolated test defaults/profile support where available. Do not clear user defaults or
turn this task into app-wide test-profile infrastructure. Preserve user window placement during
manual checks. Run focused existing WMP tests while implementing and `swift test` before landing
runtime changes. Static frame PNGs do not replace live verification of GPU/native-child composition.

Other-family checks verify isolation only. A failure there means revise or remove the WMP change;
it is not permission to fix or refactor another skin system.

## Work order and completion criteria

1. Select a concrete WMP failure and reproduce it with existing tools. This analysis alone does
   not authorize a broad runtime rewrite.
2. Identify the smallest WMP-owned fix and any unavoidable WMP-gated shared call site. Reject
   approaches that alter another skin system.
3. Implement the fix, extracting a small WMP helper only if multiple affected sites need it.
4. Run the focused regression, relevant WMP counterexamples/corpus checks, live checks, and
   non-WMP isolation checks appropriate to that change.
5. Update the WMP owning skill with the implemented behavior and evidence. Stop when the defect
   is resolved; do not bundle unrelated cleanup or speculative infrastructure.

Completion means the reported WMP behavior works, affected WMP consumers still work, and other
skin systems have no implementation or behavior changes. It does not require six windows to
adopt a new host API.

## Explicitly deferred

The proposed `WMPHostedSurfaceContainer`, content adapters, presentation-state framework, separate
border coordinator, new persistence keys, donor-plan decomposition, script-layout execution, and
new matrix/capture harnesses are not part of this plan. Reconsider an individual item only when a
concrete WMP problem cannot be solved cleanly through the current seams, with a separate bounded
proposal. File size, repeated code, or hypothetical performance savings alone do not justify them.

## Documentation audit — resolved 2026-09-18

The original audit identified D1–D20 against the reviewed revision. All listed corrections have
now been applied to operational documentation and source comments. This completion record replaces
the stale imperative findings. The earlier hosting redesign is withdrawn; the WMP-only corrective
approach above remains a proposal.
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
