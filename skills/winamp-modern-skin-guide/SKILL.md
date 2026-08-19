---
name: winamp-modern-skin-guide
description: Winamp 5.x .wal skin engine — Wasabi XML/XUI renderer, MAKI bytecode VM, VFS mounts, component hosting, and the ClassicPro engine import. Use when working on the WinampModern subsystem, debugging a .wal skin that fails to load or renders wrong, or extending Wasabi/MAKI coverage, or triaging compatibility across many skins at once.
---

# Winamp Modern (`.wal`) Skin Engine

NullPlayer's fourth UI mode (`PlayerUIMode.winampModern`) loads and runs **Winamp 5.x modern skins** —
`.wal` archives containing Wasabi XML/XUI markup and compiled MAKI bytecode. It is a clean-room
implementation: the archive is parsed, the object graph is built, and the scripts are interpreted by
NullPlayer's own code. No Winamp binary, plugin, or asset is bundled.

**Status: experimental.** The runtime loads, scripts, and renders real skins, but see
[compatibility.md](compatibility.md) for the exact supported/unsupported surface before assuming any
behavior works.
### Pick your working mode first

Coverage is demand-driven and the wild corpus is effectively unbounded, so the *unit of work* matters
as much as the code. Three modes, three different entry points:

| You are… | Start with | Not |
|---|---|---|
| Debugging one named skin | [skins.md](skins.md) → `skins/<skin>.md`, then [reference/harness.md](reference/harness.md) | reading this file top to bottom |
| **Measuring** a skin — what does it contain, what works, how good is it? | **`/wal-skin-report <skin.wal>`** (`skills/wal-skin-report`) — fixed measurement order, structured report, A–F grade with a confidence axis | ad-hoc dumps whose findings evaporate |
| Deciding what to implement next across many skins | [triage-playbook.md](triage-playbook.md) — corpus measurement, defect classes, the demand index | fixing whatever the last bug report named |

The two habits those exist to break: **a skin is a test case, not a milestone** (batch work by
capability, not by skin — one fix that unblocks 200 skins beats ten that unblock one), and **a skin's
default state is not the skin** (Defix ships nine display styles; the cassette is one of them, and the
animated VU meters behind the other eight have never been rendered here).

## Routing: which file answers this?

This file is a **router**. It carries the pipeline, the security model, the file map, and the rules —
everything every task in this subsystem needs. The detail lives in `reference/`, one file per
concept; read the one your symptom points at, not all of them.

| Symptom / question | Read |
|---|---|
| Skin fails to load, mounts wrong, `@VARS@` unresolved, include/glob trouble | [reference/loading.md](reference/loading.md) |
| Object is in the wrong place, y flipped, window collapsed to nothing | [reference/loading.md](reference/loading.md) |
| A button is dead under the mouse; clipping, dragging, region trouble | [reference/rendering.md](reference/rendering.md) + [reference/harness.md](reference/harness.md) |
| Something draws wrong, missing, mis-clipped, wrong colour, wrong font, wrong text | [reference/rendering.md](reference/rendering.md) |
| Animation frozen, needle/reel not turning, layer stuck on one frame | [reference/rendering.md](reference/rendering.md) |
| Slow, stuttering, CPU high, repaint storm | [reference/performance.md](reference/performance.md) |
| A script does nothing, wrong arity, unknown method, script-built UI missing | [reference/scripting.md](reference/scripting.md) |
| Playlist / EQ / library / video surface missing, empty, or in the wrong window | [reference/components.md](reference/components.md) |
| A button that should open a window does nothing (`TOGGLE`, container ids) | [reference/components.md](reference/components.md) |
| Teardown crash, leak, or mode-switch breakage | [reference/components.md](reference/components.md) |
| A ClassicPro (`.wal` + NSIS engine) skin misbehaves | [reference/classicpro.md](reference/classicpro.md) |
| **How do I see what the engine is doing?** Probes, env vars, dumps | [reference/harness.md](reference/harness.md) |
| What is supported at all? Method/element tables, limits, policy | [compatibility.md](compatibility.md) |
| What does *this named skin* do today? | [skins.md](skins.md) → `skins/<skin>.md` |
| Measuring one skin end to end | `/wal-skin-report <skin.wal>` |
| Choosing what to implement next across many skins | [triage-playbook.md](triage-playbook.md) |

### Section-title map

Handoffs in `docs/winamp-modern/` cite this skill by section title. Every title below is still
verbatim; it just lives in a reference file now.

| Section title | Now in |
|---|---|
| VFS mounts | [reference/loading.md](reference/loading.md) |
| Initialization passes | [reference/loading.md](reference/loading.md) |
| Retained graph and coordinates | [reference/loading.md](reference/loading.md) |
| The protective window minimum | [reference/loading.md](reference/loading.md) |
| The two y-origin conventions (source of a whole class of bugs) | [reference/loading.md](reference/loading.md) |
| Region clipping | [reference/rendering.md](reference/rendering.md) |
| Hit testing: who owns a point | [reference/rendering.md](reference/rendering.md) |
| Dragging the window | [reference/rendering.md](reference/rendering.md) |
| `<vis mode>` — the skin says whether it wants a visualization at all | [reference/rendering.md](reference/rendering.md) |
| `<Wasabi:Frame>` — the splitter that builds its own children | [reference/rendering.md](reference/rendering.md) |
| Text width is a layout input, not just a drawing detail | [reference/rendering.md](reference/rendering.md) |
| How big the font is, and which one | [reference/rendering.md](reference/rendering.md) |
| A bitmap font's `file=` is an id **or** a path | [reference/rendering.md](reference/rendering.md) |
| What a `<text>` shows | [reference/rendering.md](reference/rendering.md) |
| A `cfgattrib` control has no `action` — the binding *is* what it does | [reference/rendering.md](reference/rendering.md) |
| `<AlbumArt>` needs a host that actually has the cover | [reference/rendering.md](reference/rendering.md) |
| `alpha` belongs to the object, not to one kind of drawing | [reference/rendering.md](reference/rendering.md) |
| An image param is a *load*, and a failed load changes nothing | [reference/rendering.md](reference/rendering.md) |
| Layer fill modes | [reference/rendering.md](reference/rendering.md) |
| `<ProgressGrid>` — the bar's *filled* part | [reference/rendering.md](reference/rendering.md) |
| A skin's own right-click menus | [reference/rendering.md](reference/rendering.md) |
| Colour themes (`gammaset` / `gammagroup`) | [reference/rendering.md](reference/rendering.md) |
| Animated layers are played as a range | [reference/rendering.md](reference/rendering.md) |
| The frame budget: what repaints, and what it costs | [reference/performance.md](reference/performance.md) |
| MAKI | [reference/scripting.md](reference/scripting.md) |
| Script-built UI: `onSetXuiParam` and `System.newGroup` | [reference/scripting.md](reference/scripting.md) |
| Rotary controls: `Map` | [reference/scripting.md](reference/scripting.md) |
| Asking a skin what it actually shipped | [reference/scripting.md](reference/scripting.md) |
| Track metadata the skins actually read | [reference/scripting.md](reference/scripting.md) |
| `TOGGLE`'s parameter is a component **or a container id** | [reference/components.md](reference/components.md) |
| Component hosting | [reference/components.md](reference/components.md) |
| The window layer these views sit in | [reference/components.md](reference/components.md) |
| Where a surface lives | [reference/components.md](reference/components.md) |
| Synthesizing a missing window | [reference/components.md](reference/components.md) |
| Container-scoped layout callbacks | [reference/components.md](reference/components.md) |
| Resize, and why a skin needs it | [reference/components.md](reference/components.md) |
| Colours and hosted AppKit content | [reference/components.md](reference/components.md) |
| Teardown order | [reference/components.md](reference/components.md) |
| Mode integration | [reference/components.md](reference/components.md) |
| ClassicPro engine | [reference/classicpro.md](reference/classicpro.md) |
| Debugging a skin | [reference/harness.md](reference/harness.md) |

## Where things live

All engine code is in `Sources/NullPlayer/WinampModern/`; all UI/controller code is in
`Sources/NullPlayer/Windows/WinampModern/`.

| Concern | File |
|---------|------|
| Archive validation | `WalArchive.swift` |
| Logical filesystem + path variables | `WalVirtualFileSystem.swift` |
| Directory-backed provider (engine) | `WalDirectoryResourceProvider.swift` |
| Lenient XML parse + include expansion | `WalXML.swift` |
| Initialization passes, registries | `WasabiSkinInitializer.swift` |
| Retained object graph | `WasabiObjectGraph.swift` |
| Coordinates / anchors | `WasabiGeometry.swift` |
| `<Wasabi:Frame>` splitter | `WasabiFrame.swift` |
| Fonts + text measurement (shared) | `WasabiTextMetrics.swift` |
| Resource cache + scene renderer | `WasabiRenderer.swift` |
| MAKI parser + interpreter | `MakiBytecode.swift` |
| Script runtime + method dispatch | `WinampModernScriptRuntime.swift` |
| Skin-facing host API | `WinampModernHost.swift` |
| Component model + host protocol | `WinampModernComponents.swift` |
| Container topology | `WinampModernContainerTopology.swift` |
| Surface inventory + synthesis | `WasabiSurfaceInventory.swift`, `WasabiSurfaceSynthesizer.swift`, `WasabiStandardFrames.swift` |
| Colour theme + palette | `WinampModernThemeCoordinator.swift`, `WasabiPalette.swift` |
| Style for NullPlayer-drawn surfaces | `WinampModernSurfaceStyle.swift` |
| EQ action decoding | `WinampModernEQActions.swift` |
| Diagnostics | `WalDiagnostics.swift` |
| Compatibility report | `WinampModernCompatibilityReport.swift` |
| Complete loader | `WinampModernSkinLoader.swift` |
| Import + storage | `WinampModernSkinImporter.swift` |
| ClassicPro engine import | `ClassicProEngine.swift`, `NSISArchive.swift`, `LZMA1Decoder.swift` |
| Window controller / view | `Windows/WinampModern/WinampModernMainWindowController.swift`, `…MainView.swift` |
| `AudioEngine` component bridge | `Windows/WinampModern/WinampModernComponentBridge.swift` |
| Surface routing | `Windows/WinampModern/WinampModernSurfaceCoordinator.swift` |
| Embedded library surface | `Windows/WinampModern/WinampModernLibrarySurfaceView.swift` |

Design records and per-phase handoffs: `docs/winamp-modern/`.

## The pipeline

```
.wal file
  └─ WalArchive              validate + bound (ZIP, read-only, on-demand inflate)
      └─ WalVirtualFileSystem  mount at /Skins/<name>/, resolve @VARS@, case-insensitive
          └─ WalXMLDocumentLoader  parse skin.xml, expand <include>/<elementinclude> + globs
              ├─ WinampModernSurfaceInventory   what the skin declares (pre-graph, bounded walk)
              └─ WasabiSurfaceSynthesizer       append windows for missing surfaces
                  └─ WasabiSkinInitializer  6 ordered passes → registries + retained graph
                      ├─ WasabiSceneRenderer   graph → Core Graphics
                      ├─ WinampModernScriptRuntime  MAKI programs bound to graph objects
                      └─ WinampModernHost      the only door to AudioEngine
```

Synthesis sits **before** initialization on purpose: synthetic XML must go through the same
registration, inheritance validation, object creation, and script binding as the skin's own. After
`scripts.start()`, `WinampModernSurfaceCoordinator` reconciles the catalog against the containers that
actually opened.

`WinampModernSkinLoader.load(from:additionalMounts:)` is the headless entry point for the whole
left column and returns a `WinampModernLoadedSkin`. Every test and the window controller go through
it — there is no second path.

### Security model

The skin is **untrusted input**. Three rules hold everywhere and must not be relaxed:

1. **No host filesystem access.** Resources are read only through `WalResourceProvider` /
   `WalVirtualFileSystem`. Never hand a skin an `NSURL` into the real filesystem.
2. **Everything is bounded.** Archive entries, uncompressed bytes, compression ratio, XML depth, node
   count, include depth, image dimensions, font size, script size, instruction count, call depth,
   allocation, stack values, active timers. See [compatibility.md](compatibility.md#limits) for values.
3. **Failures are typed, never traps.** Malformed input produces a `WalFailure` carrying
   `WalDiagnostic`s with a `WalSourceLocation` (`logical-path:line:column`). A Swift trap or a hang on
   skin input is a bug — the fuzz tests in `WinampModernPhase7Tests` exist to catch exactly that.

Scripts cannot navigate URLs, launch executables, open modal UI, reach arbitrary paths, or touch the
network. `messagebox` is denied; `navigateurl` is a no-op.


## Rules for extending this subsystem

- Do not weaken a limit or a sandbox rule to make a skin load. Degrade gracefully with a warning
  diagnostic instead — a missing optional bitmap or an unknown `wasabi.*` base should warn, not fail.
- Do not add host capabilities beyond what a measured skin needs, and keep them narrow and typed.
- Do not put platform rendering state into `WasabiObjectGraph`.
- Do not broaden the release UI surface as a side effect of unrelated compatibility work.
- Preserve `WalDiagnostic`s; do not replace them with renderer-specific string errors.
- A script method that reports **geometry** (`getWidth`, `getGuiX`, …) must answer where the object
  actually landed, not what its markup says. Bento-style skins are almost entirely relative geometry
  (`w="-4" relatw="1"`), and an attribute read there is a negative number a skin will lay itself out
  against.
- Before concluding "the script never ran", check with a probe that observes **execution**. Per-object
  binding state does not answer that question, and reading it as if it did cost two phases.
- Add fixtures, never third-party assets. Every committed test fixture is synthetic and self-authored.
- Measure with `/wal-skin-report` rather than by hand, and land what you learn: durable rules in the
  `reference/` file that owns the concept or in [compatibility.md](compatibility.md), per-skin state in
  `skins/<skin>.md`, the report itself outside the repo unless the user asks for it. An ad-hoc dump
  nobody wrote down gets re-derived, and two phases have already been lost that way.

### Where new findings land

- A durable rule about a *concept* → the `reference/` file that owns that concept.
- A fact about one named skin → `skins/<skin>.md` (indexed from [skins.md](skins.md)).
- A supported/unsupported surface fact → [compatibility.md](compatibility.md).
- A corpus-scale method or disposition → [triage-playbook.md](triage-playbook.md).
- This file grows **only** when a new *category* appears — then add a row to the routing table.
- **Dedupe rule:** long or volatile prose gets exactly one home and everything else points at it;
  short stable tables may repeat where an extra file read would cost more than the duplicate.

## Related

- `reference/` — the split-out detail; see the routing table above
- [compatibility.md](compatibility.md) — supported/unsupported Wasabi + MAKI surface, limits, engine policy
- `skills/wal-skin-report` — `/wal-skin-report <skin.wal>`: the single-skin instrument. Measures one
  skin end to end and emits the structured report (capabilities, status matrix, unknowns, grade)
- [triage-playbook.md](triage-playbook.md) — **corpus-scale triage**: how to measure many skins at once,
  classify defects, rank missing capabilities by demand, and isolate one issue once it is ranked. Read
  it before starting work that is not about a single named skin
- [skins.md](skins.md) — **per-skin index**: the status table, the skin → file map, and the trap
  index. Each measured skin's detail is `skins/<skin>.md`. Start here when a report names a skin, and
  update the skin's file when a phase closes on one
- [manual-qa-checklist.md](manual-qa-checklist.md) — the GUI verification pass
- `docs/winamp-modern/` — decision records and per-phase handoffs
- `docs/legal/winamp_modern_provenance.md` — clean-room provenance record
- `skills/modern-skin-guide` — NullPlayer's *own* modern skin system, which is unrelated to this one
