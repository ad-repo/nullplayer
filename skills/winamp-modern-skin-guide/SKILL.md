---
name: winamp-modern-skin-guide
description: Winamp 5.x .wal skin engine — Wasabi XML/XUI renderer, MAKI bytecode VM, VFS mounts, component hosting, and the ClassicPro engine import. Use when working on the WinampModern subsystem, debugging a .wal skin that fails to load or renders wrong, or extending Wasabi/MAKI coverage, or triaging compatibility across many skins at once.
---

# Winamp Modern (`.wal`) Skin Engine

NullPlayer's fourth UI mode (`PlayerUIMode.winampModern`) loads and runs **Winamp 5.x modern skins** —
`.wal` archives containing Wasabi XML/XUI markup and compiled MAKI bytecode. It is a clean-room
implementation: the archive is parsed, the object graph is built, and the scripts are interpreted by
NullPlayer's own code. No Winamp binary, plugin, or asset is bundled.

**User-facing name: Modern.** This family is presented in the skin menu as **Modern**; NullPlayer's
own former Modern/Metal families are shown as **Original**/**Original-Metal**. Every internal
identifier is unchanged — the enum case and persisted raw value stay `winampModern`, as does the
`-uiMode winampModern` flag. Never rename compatibility identifiers, preference keys, type names, or
references to the actual stock *Winamp Modern* skin.

The runtime loads, scripts, and renders real skins, but see
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
default state is not the skin** (Defix ships eight display styles; the cassette is one of them, and the
animated VU meters behind the other eight have never been rendered here).

## Routing: which file answers this?

This file is a router. Read the one focused reference your symptom names.

| Symptom / question | Read |
|---|---|
| Load, mounts, `@VARS@`, include/glob, sibling skins | [reference/loading.md](reference/loading.md) |
| Geometry, anchors, y-origin, collapsed windows | [reference/loading.md](reference/loading.md) |
| Dead mouse target, clipping, regions, drag policy, `sysregion` | [reference/rendering/hit-testing.md](reference/rendering/hit-testing.md) |
| Invisible layer blocks clicks or drags the window | [reference/rendering/hit-testing.md](reference/rendering/hit-testing.md) → *Hit testing* |
| Splitter cursor/drag/persistence or `<Wasabi:Frame>` | [reference/rendering/frame-splitter.md](reference/rendering/frame-splitter.md) |
| `<vis>` analyzer/oscilloscope, gain, colours, modes | [reference/rendering/vis.md](reference/rendering/vis.md) |
| Visualization timing, stepped motion, pause freeze | [reference/performance.md](reference/performance.md) → *The visualization has a clock of its own* |
| Text metrics, fonts, clocks, bitmap fonts, missing height, offsets | [reference/rendering/text.md](reference/rendering/text.md) |
| Colour resolution, themes, unreadable selections/titles | [reference/rendering/colour.md](reference/rendering/colour.md) |
| Selected row or title text matches its background | [reference/rendering/colour.md](reference/rendering/colour.md) → *A resolved colour is not yet readable* |
| `cfgattrib`, `onActivate`, album art, alpha, fill, sliders, `ProgressGrid`, animation | [reference/rendering.md](reference/rendering.md) |
| Slow rendering, CPU, repaint storms | [reference/performance.md](reference/performance.md) |
| Frame is fast but the app hangs | [reference/harness.md](reference/harness.md) → *Profiling the running app* |
| Script abort, arity, unknown method, script-built UI | [reference/scripting.md](reference/scripting.md) |
| Host readout or EQ change never reaches a script | [reference/scripting.md](reference/scripting.md) |
| Keyboard, mouse wheel, wrapper value, scrolling | [reference/scripting.md](reference/scripting.md) |
| `getAutoWidth` / `getAutoHeight`, scripted layout drift | [reference/scripting.md](reference/scripting.md) |
| `setText`/search terms disappear through `embed_xui` | [reference/scripting.md](reference/scripting.md) |
| Slider action families and `onSetPosition` | [compatibility/wasabi-surface.md](compatibility/wasabi-surface.md) |
| Playlist/EQ/library hosting, synthesis, topology | [reference/components.md](reference/components.md) |
| Embedded playlist/library text sizes disagree | [reference/components.md](reference/components.md) → *How large NullPlayer draws its own text* |
| Hosted surface survives the wrong tab or remounts dead | [reference/components.md](reference/components.md) → *Unmounting is not teardown* |
| `hold="none"`, flat holder slab, component routing | [reference/components.md](reference/components.md) → *Component hosting* |
| `TOGGLE`, container ids, first layout, `default_visible` | [reference/components.md](reference/components.md) |
| Component bucket/thinger, missing widget from include closure | [reference/components.md](reference/components.md) → *The component bucket* |
| NullPlayer-hosted text size or palette | [reference/components.md](reference/components.md) |
| Auxiliary window freezes; repaint or teardown issue | [reference/components.md](reference/components.md) |
| Video picture, child-window sizing, control bar | [reference/components/video.md](reference/components/video.md) |
| AVS/MilkDrop component holder or embedded visualization | [reference/components/visualization.md](reference/components/visualization.md) |
| Several visualization holders show the wrong engine | [reference/components/visualization.md](reference/components/visualization.md) → *one holder per skin* |
| Browser/WebKit, navigation, search URL, duplicate toolbar | [reference/components/browser.md](reference/components/browser.md) |
| Scheme-less web address is mistaken for a VFS path | [reference/components/browser.md](reference/components/browser.md) → *four navigation routes* |
| Notifier toast text, layout, visibility, timing | [reference/components/notifier.md](reference/components/notifier.md) |
| Notifier title is invisible or rows overlap | [reference/components/notifier.md](reference/components/notifier.md) → *text and layout* |
| Playlist/visualization/video toolbar actions | [compatibility/wasabi-surface.md](compatibility/wasabi-surface.md) |
| ClassicPro engine/import behavior | [reference/classicpro.md](reference/classicpro.md) |
| WACUP probe, branding branch, WACUP-only surface | [reference/wacup.md](reference/wacup.md) |
| Probes, env vars, dumps, live defect | [reference/harness.md](reference/harness.md) |
| Probe reports no match or no event | [reference/harness.md](reference/harness.md) → *A blind instrument reads as a working feature* |
| Whole skin dead or startup handler aborts | [reference/harness.md](reference/harness.md) → *The order that made Phase 33 cheap* |
| Meter moves too little | [reference/harness.md](reference/harness.md) → histogram the frames |
| Renderer regression proof | [reference/harness.md](reference/harness.md) → *The golden images* |
| Supported Wasabi markup | [compatibility/wasabi-surface.md](compatibility/wasabi-surface.md) |
| Host action is accepted but deliberately inert | [compatibility/wasabi-surface.md](compatibility/wasabi-surface.md) → action families |
| Implemented MAKI method/events | [compatibility/maki-surface.md](compatibility/maki-surface.md) |
| Limits, policy, verification status | [compatibility/limits-and-policy.md](compatibility/limits-and-policy.md) |
| One named skin's current state | [skins.md](skins.md) → `skins/<skin>.md` |
| Skin declares a widget that never enters its include graph | [reference/components.md](reference/components.md) → *The component bucket* |
| Measure one skin end to end | `/wal-skin-report <skin.wal>` |
| Choose the next cross-skin capability | [triage-playbook.md](triage-playbook.md), then the ranked Reach table in `TASKS.md` |
| Window restores at the wrong size or one skin inherits another's frame | [reference/rendering.md](reference/rendering.md) → *A .wal window's size is still the skin's* |
| Toggle works but never looks active | [reference/rendering.md](reference/rendering.md) → *onActivate* |
| Shuffle/repeat/crossfade disagree with the host | [reference/rendering.md](reference/rendering.md) → *Some cfgattrib values are the host's* |
| Control works once, hides itself, and cannot be clicked again | [reference/scripting.md](reference/scripting.md) → *A layout must not be left with no way to seek* |
| Skin starts in an impossible all-zero settings state | [reference/loading.md](reference/loading.md) → *settings must start in a state scripts can express* |
| Vertical slider uses the wrong axis or EQ curve is absent | [reference/rendering.md](reference/rendering.md) → *A skin spells the axis two ways* |
| Clock fields collide or the separator sits off baseline | [reference/rendering/text.md](reference/rendering/text.md) → *A clock is a run of fields* |
| White/black slab appears where a named colour belongs | [reference/rendering/colour.md](reference/rendering/colour.md) → *How a colour resolves* |
| Theme picker is empty or will not switch | [reference/rendering/colour.md](reference/rendering/colour.md) → *The picker* |
| Skin-owned right-click menu is missing or wrong | [reference/rendering.md](reference/rendering.md) → *A skin's own right-click menus* |
| Container/layout writes do not move or size their window | [reference/rendering.md](reference/rendering.md) → *A container's x/y/w/h are its window's* |
| Search action receives empty terms | [reference/scripting.md](reference/scripting.md) → *embed_xui* |
| GUI-only scripted-control report | [reference/harness.md](reference/harness.md) → *Ask for the live trace first, not fourth* |
| Config/EQ drawer or custom list will not scroll | [reference/scripting.md](reference/scripting.md) → *The mouse wheel is a layout event* |
| Album art, animated layer, or image parameter draws stale/wrong | [reference/rendering.md](reference/rendering.md) |
| Skin-opened window appears in the wrong place | [reference/components.md](reference/components.md) → *default_visible* |
| Mode switch teardown crashes or leaks a hosted surface | [reference/components.md](reference/components.md) → *Teardown order* |
| Current open work | `TASKS.md` — the only live backlog; closed history is [the archive](../../docs/winamp-modern/backlog-archive.md) |

The backward-compatibility map for section-title pointers in old handoffs lives in
[`docs/winamp-modern/section-title-map.md`](../../docs/winamp-modern/section-title-map.md).

Routing rules:

- Follow the most specific row. The parent `rendering.md` now owns drawable behavior that does not
  belong to hit testing, visualization, splitters, text, or colour; the parent `components.md` owns
  hosting core that does not belong to video, visualization, browser, or notifier surfaces.
- A visual symptom and its evidence can route to different files. For example, a dead control's
  semantics live in hit testing or scripting, while the command that proves which object won the
  point lives in `reference/harness.md`.
- A white or black slab with a declared colour is a colour-resolution question; a flat slab over a
  component holder is a hosting question. They look alike but exercise different paths.
- The player's built-in `<vis>` element is not the `{0000000A}` visualization component. The former
  routes to `rendering/vis.md`; the latter routes to `components/visualization.md`.
- A `<layout>` or `<container>` changing its own window geometry is core rendering behavior. A
  `<Wasabi:Frame>` changing the division between its children is splitter behavior.
- Historical handoffs are evidence, not current routing. Resolve their old section titles through
  the map, then use the focused reference and the live `TASKS.md` ranking.
- When two rows appear plausible, read both section headings before loading either whole file; the
  split is designed so the narrower file normally settles the ownership question immediately.

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
| What the host remembers about a skin between launches (B44/B44a/B50) | `WinampModernSkinState.swift` |
| How large the host draws its own text (Text Size, B50) | `WinampModernTextScale.swift` |
| What paints a `<vis>` box: the choice, the engines, the gain (B51/B53) | `WasabiVisPainter.swift`, `WinampModernSpectrumAnalyzer.swift`, `WinampModernSpectrumAnalyzerRenderers.swift`, `WinampModernVisSensitivity.swift` |
| The oscilloscope's PCM tap (B51) | `WinampModernWaveformTap.swift` |
| Fonts + text measurement (shared) | `WasabiTextMetrics.swift` |
| Resource cache + scene renderer | `WasabiRenderer.swift` |
| MAKI parser + interpreter | `MakiBytecode.swift` |
| Script runtime + method dispatch | `WinampModernScriptRuntime.swift` |
| Skin-facing host API | `WinampModernHost.swift` |
| Component model + host protocol | `WinampModernComponents.swift` |
| Component bucket (thinger): icon set, box layout, strip state | `WinampModernComponentBucket.swift`, `WasabiRenderer.swift` |
| Container topology | `WinampModernContainerTopology.swift` |
| Surface inventory + synthesis | `WasabiSurfaceInventory.swift`, `WasabiSurfaceSynthesizer.swift`, `WasabiStandardFrames.swift` |
| Colour theme + palette | `WinampModernThemeCoordinator.swift`, `WasabiPalette.swift` |
| Colour theme picker (`<ColorThemes:List>`) | `WasabiColorThemeList.swift`, `WasabiRenderer.swift` |
| Style for NullPlayer-drawn surfaces | `WinampModernSurfaceStyle.swift` |
| EQ action decoding | `WinampModernEQActions.swift` |
| `cfgattrib` values that are host state | `WinampModernConfigBridge.swift` |
| Balance (`PAN`) unit conversion | `WinampModernPanAction.swift` |
| Diagnostics | `WalDiagnostics.swift` |
| Compatibility report | `WinampModernCompatibilityReport.swift` |
| Complete loader | `WinampModernSkinLoader.swift` |
| Import + storage | `WinampModernSkinImporter.swift` |
| ClassicPro engine import | `ClassicProEngine.swift`, `NSISArchive.swift`, `LZMA1Decoder.swift` |
| Window controller / view | `Windows/WinampModern/WinampModernMainWindowController.swift`, `…MainView.swift` |
| Keyboard accelerator names | `WinampModernKeyAccelerator.swift` |
| `AudioEngine` component bridge | `Windows/WinampModern/WinampModernComponentBridge.swift` |
| Surface routing | `Windows/WinampModern/WinampModernSurfaceCoordinator.swift` |
| Application-owned hosted-window registry | `WinampModernHostedWindows.swift` |
| Lazy hosted-window materializer + surface contract | `Windows/WinampModern/WinampModernHostedWindowMaterializer.swift`, `…HostedWindowSurface.swift` |
| Shared `.wal` fallback chrome | `WinampModernChrome.swift` |
| Embedded library surface | `Windows/WinampModern/WinampModernLibrarySurfaceView.swift` |
| Embedded web browser | `Windows/WinampModern/WinampModernBrowserSurfaceView.swift` |

Design records and per-phase handoffs: `docs/winamp-modern/` — see its `INDEX.md`.

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
   allocation, stack values, active timers. See [compatibility/limits-and-policy.md](compatibility/limits-and-policy.md#limits) for values.
3. **Failures are typed, never traps.** Malformed input produces a `WalFailure` carrying
   `WalDiagnostic`s with a `WalSourceLocation` (`logical-path:line:column`). A Swift trap or a hang on
   skin input is a bug — the fuzz tests in `WinampModernPhase7Tests` exist to catch exactly that.

Scripts cannot launch executables, open modal UI, reach arbitrary host paths, or make general host
network requests, and `messagebox` remains denied.

**Navigation is the one narrow exception, and it is typed rather than free** (B40). Every address a
skin authors — from `<browser>.navigateUrl`, from `System.navigateUrl` /
`System.navigateUrlBrowser`, or from a `browser_search` / `browser_navigate` action — passes through
`WinampModernWebNavigationPolicy`: HTTP/HTTPS with a real host only, no other scheme, no file or
application URL. An internal address reaches only that skin's own ephemeral, policy-gated WebKit
surface. The **external** route (`System.navigateUrl`, the user's default browser) additionally
requires the user's consent: a sheet naming the URL on first use, remembered per skin if they choose
"Always Allow", one outstanding question at a time, and never a modal loop. See
[reference/components/browser.md](reference/components/browser.md) — *The four routes a skin reaches the web by*.


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
- **Instrument before you reason.** Deducing a mechanism from the skin's bytecode and the engine
  source produced three wrong answers in a row on one defect; `WINAMP_MODERN_CALL_TRACE=1` on the
  running app settled it in a single launch. Count what a method *returns*, not whether it is called.
- **When a fix changes nothing on screen, look for the next fault before reverting it.** One Defix
  readout had four independent faults stacked on it, so the first two correct fixes looked like no
  change at all.
- **A number handed to skin artwork must be in the unit that artwork is cut for.** Winamp's meters are
  vis bytes on a logarithmic sweep; a linear magnitude × 255 has now been found twice (`getLeftVUMeter`
  Phase 29, `getVisBand` Phase 30) and is still open in the `<vis>` analyzer. The test is to histogram
  the frames a meter actually uses: a healthy one spreads, a mis-scaled one piles on its rest frame.
- **Check `RENDER_SCRIPTS` for a failed handler before believing anything about what a skin contains.**
  Dispatch is fail-closed: one unimplemented method abandons the *whole handler*, and skins put their
  entire startup in one. multipass's eleven initialisers all sat behind statement eight of the first
  one, so the skin was a static picture and every feature "missing" — including a widget a graph-walking
  probe then recorded as absent, because a script had never run to create it. A skin whose startup
  aborted has no features to debug (Phase 33; the *whole* method is in `reference/harness.md` §*The
  order that made Phase 33 cheap*).
- **Read the skin's own `scripts/*.m` when the archive ships them** — several do, and it turns an
  afternoon of disassembly into a five-minute read.
- **Ask what kind of object a control is before concluding the skin has none.** multipass's seek bar
  is an `<animatedlayer>` plus a `Map`, not a `<slider>`.
- **Corpus-scan the attribute, not the button.** One `action="…"` grep across the installed skins
  turned "this button does nothing" into nine dead buttons in five skins plus a list of what is still
  inert — a coverage decision rather than a one-off fix. Then run the render sweep, which is what
  proves the fix reached other skins *and* broke none.
- **When a probe reports nothing, check the probe can see the thing at all.** Three harness blind
  spots each made a real defect look absent (see *A blind instrument reads as a working feature*).
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
- A new backlog item → `TASKS.md` with a Reach measurement; move it to the archive in the same change that closes it.
- This file grows **only** when a new *category* appears — then add a row to the routing table.
- **Dedupe rule:** long or volatile prose gets exactly one home and everything else points at it;
  short stable tables may repeat where an extra file read would cost more than the duplicate.

## Related

- `reference/` — the split-out detail; see the routing table above
- [compatibility.md](compatibility.md) — the supported/unsupported surface: archive rules and hosted
  components inline, with `compatibility/` holding the Wasabi, MAKI, and limits/policy tables
- `skills/wal-skin-report` — `/wal-skin-report <skin.wal>`: the single-skin instrument. Measures one
  skin end to end and emits the structured report (capabilities, status matrix, unknowns, grade)
- [triage-playbook.md](triage-playbook.md) — **corpus-scale triage**: how to measure many skins at once,
  classify defects, rank missing capabilities by demand, and isolate one issue once it is ranked. Read
  it before starting work that is not about a single named skin
- [skins.md](skins.md) — **per-skin index**: the status table, the skin → file map, and the trap
  index. Each measured skin's detail is `skins/<skin>.md`. Start here when a report names a skin, and
  update the skin's file when a phase closes on one
- [manual-qa-checklist.md](manual-qa-checklist.md) — the GUI verification pass
- `docs/winamp-modern/INDEX.md` — decision records and per-phase handoffs, one line each. The
  historical record; where it and this skill disagree, this skill is right
- `docs/legal/winamp_modern_provenance.md` — clean-room provenance record
- `skills/modern-skin-guide` — NullPlayer's *own* modern skin system, which is unrelated to this one
