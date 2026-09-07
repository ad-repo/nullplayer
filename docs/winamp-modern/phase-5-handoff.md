# Winamp Modern (`.wal`) — Phase 5 Handoff

**For:** the agent implementing Phase 6 (ClassicPro user-supplied engine import and cPro-Bento)

**From:** Phase 5 (playlist, EQ, library, and component hosting — COMPLETE)

**Date:** 2026-08-15

Read first:

- `~/.claude/plans/i-want-to-support-frolicking-rabbit.md` — source-of-truth plan and locked scope
- `docs/winamp-modern/phase-0b-decision-record.md` §3 — the cPro-Bento component/window topology this phase implements
- `docs/winamp-modern/phase-4-handoff.md` — renderer/MAKI/host/lifecycle contracts inherited by Phase 5
- `TASKS.md` — Phase 5 is complete; Phase 6 is next

## 1. Phase 5 outcome and boundary

The Wasabi runtime now hosts NullPlayer's playlist, equalizer, and library surfaces through the
**component-hosting-first** model P0B §3 mandates for cPro-Bento (a single-window SUI where those
surfaces are embedded via `windowholder hold="guid:…"`), and also maps **separate visible containers**
to native windows for skins that declare them.

Phase 5 added:

- a typed component model (`WinampModernComponentKind`) + a GUID/shortform registry that resolves the
  standard Winamp component GUIDs — skin GUIDs never escape the registry
- windowholder/componentbucket discovery with resolved frames from the active scene
- container-topology classification (visible native window vs. SUI-collapsed 1×1 stub) and container→window mapping
- a sandboxed component-host seam (`WinampModernComponentHost`) with a production bridge to `AudioEngine`
- an embedded, skin-framed playlist (rows, now-playing + selection, bounded scroll) with click/double-click/scroll input
- an embedded classic10 EQ (preamp + 10 bands, enabled/auto, presets) bound to `AudioEngine`; gains persist across mode switches because they live in `AudioEngine`, not the skin
- a bounded library-host seam (live AppKit subview positioned at the library holder frame)
- toggle routing: `TOGGLE`/`sendaction` for eq/pl/ml/video resolves to the skin's embedded component,
  else a separate skin window, else the classic WindowManager window

Phase 6 still exclusively owns the ClassicPro engine importer (NSIS `.exe`/extracted folder → mounted
`/Plugins/classicPro/engine/`), the 3 `ClassicProFile` shell adapters, the drawer/tab/theme-selector/
notifier expansion, and the version-gate shim. No Phase 6 work is included here.

## 2. Files and seams

- `Sources/NullPlayer/WinampModern/WinampModernComponents.swift` — `WinampModernComponentKind`,
  `WinampModernComponentRegistry` (GUID/shortform → kind), holder struct, `WinampModernComponentHost`
  protocol, and the playlist/EQ snapshot value types.
- `Sources/NullPlayer/WinampModern/WinampModernContainerTopology.swift` — `analyze` / `windowContainers`.
- `Sources/NullPlayer/WinampModern/WasabiRenderer.swift` — `componentHost` (weak), `componentHolders()`,
  `componentHolder(at:)`, playlist row hit-testing/scroll helpers, and the embedded playlist/EQ/vis
  drawing paths. `WasabiSceneRenderer.init` now takes a `containerID` (default `"main"`) so any
  container can be rendered in its own window.
- `Sources/NullPlayer/Windows/WinampModern/WinampModernComponentBridge.swift` — production
  `WinampModernComponentHost` over `AudioEngine` (+ classic-window fallback via `WindowManager`).
- `Sources/NullPlayer/Windows/WinampModern/WinampModernMainView.swift` — component input routing
  (playlist/EQ), library subview hosting, `routeComponentToggle`, and a `drivesScripts` flag so
  auxiliary container views don't clobber the single-owner script callbacks.
- `Sources/NullPlayer/Windows/WinampModern/WinampModernMainWindowController.swift` — auxiliary
  container windows (one per visible non-main container) + `toggleAuxiliaryWindow`.

## 3. Ownership and teardown (important for Phase 6)

There is **one** script runtime and **one** component host per loaded skin, shared by the main window
and every auxiliary container window. Only the main (`drivesScripts: true`) view tears down the shared
runtime/host; auxiliary views tear down only their own renderer. The controller tears down auxiliary
views **before** the main view, which then tears down the shared runtime; the graph is torn down last.
Any Phase 6 drawer/tab/notifier view must fit this same synchronous boundary and never outlive its
container/runtime. `WasabiSceneRenderer.componentHost` is weak; the host is owned by the controller.

## 4. Deliberate limitations carried to later phases

- **Library embedding is a bounded seam.** The production bridge's `makeLibraryContentView()` returns
  `nil`, so a library toggle currently falls back to the classic library window. The view-side
  embedding (positioning a live AppKit subview at the library holder frame, top-left→bottom-left
  converted, removed on layout change/teardown) is implemented and tested with a synthetic host view;
  wiring the real library browser view is left to Phase 7 and must not turn library lookup into
  skin-controlled I/O.
- **Auxiliary container windows render + take input but do not drive per-container MAKI layout
  switching** (the main window owns the scripted scene). cPro-Bento is single-window so this does not
  affect the north-star target; complete per-container scripting is a Phase 7 item if a multi-window
  fixture requires it.
- **Playlist/EQ are engine-drawn inside the skin-provided frame**, not yet painted with the skin's own
  list bitmaps/scrollbars/EQ thumbs. The frame, hosting, input, and adapter bindings are correct;
  skin-bitmap-accurate list/EQ rendering is Phase 7 polish.
- **No user-facing changelog entry** was added: Winamp Modern remains DEBUG-gated and not exposed in the
  release menu (Phases 2–4 added none either). Phase 8 owns the final changelog and release exposure.

## 5. Verification completed

- `swift build` clean; `swift test` → **475 tests passed**, 4 opt-in fixture tests skipped when env
  vars are absent (was 464 in Phase 4; +10 new Phase 5 tests + 1 opt-in).
- `Tests/NullPlayerAppTests/WinampModernPhase5Tests.swift` covers: GUID/shortform/named-holder → kind
  mapping; windowholder discovery + frames; topology classification (main visible, 1×1 stub collapsed,
  separate visible container) and container→window mapping; SUI collapse to a single window; the EQ
  bridge reflecting/mutating `AudioEngine` (bands/preamp/enabled/preset); the playlist bridge over
  `AudioEngine` (rows/select/remove/out-of-range no-ops); playlist row hit-testing + bounded scroll;
  embedded playlist/EQ/library holder drawing without error; toggle routing (embedded → no classic
  window; unembedded → classic fallback; separate skin window wins); and library subview embed +
  teardown release.
- Opt-in: `WINAMP_MODERN_WAL=/path/to/Skin.wal swift test --filter testLocalComponentHostingWhenFixtureSupplied`
  asserts a real skin loads, yields exactly one main-player window, and that every discovered holder
  resolves to a typed kind. The cPro-Bento + external-engine acceptance runs once Phase 6's importer
  can mount the engine.
- The DEBUG four-mode live-switch harness was **not** rerun (per the Phase 4 note, cycling it distorts
  the user's active Classic/NullPlayer-Modern windows). No Classic or NullPlayer Modern rendering source
  was changed in Phase 5.

## 6. Phase 6 starting sequence

1. Build the user-supplied ClassicPro engine importer (NSIS `.exe` parsed internally, or an already-
   extracted `engine/` folder), validate version/hash/structure, and mount it at the logical
   `/Plugins/classicPro/engine/` path via a `WalResourceProvider` (there is currently only
   `WalMemoryResourceProvider`/`WalArchive` — add the directory/`.exe` provider here).
2. Implement the 3 `ClassicProFile` shell adapters (`exploreFile`/`findFiles`/`openFile`) as the P0B
   §1 table specifies, gated by the URL/open policy.
3. Expand the ClassicPro XUI/component system and the exact MAKI methods/events from P0B, wiring the EQ
   drawer / tabs / theme selector / notifier onto the Phase 5 component-host seam and the auxiliary
   window mapping.
4. Add the `WinampVersionCheck` (`2405;5.55`) shim (branch, not hard-block).
5. Keep the release menu gated; do not bump the version.
