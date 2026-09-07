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

## The rule that outranks everything below

**Winamp Modern must never change how Classic or Original skins behave.** Those modes work; this one
is the one under construction, and a regression there is a regression in the part of the app people
already rely on.

The trap is not `import` — that is already covered by the `ModernSkin/`/`Windows/Modern*/` rule in
CLAUDE.md. It is **shared code every mode runs**, `App/WindowManager.swift` above all. Adding
behavior there and reasoning that it "should be a no-op for the other modes" is not good enough, and
has already produced one live regression (B56: a screen clamp added for `.wal` window placement moved
Classic's sub-windows too). Gate on the mode explicitly —
`uiMode.controllerFamily == .winampModern` — so the other modes run the identical code path they ran
before, and the claim is enforced by the compiler rather than by an argument.

**The rule forbids side effects, not deliberate fixes.** It protects Classic from being changed *as a
consequence of* `.wal` work; it does not mean a bug in shared code can never be fixed. 2026-09-03: the
`.wal` video pass correctly kept the end-of-media session leak out of its own change — an additive
flag only the `.wal` host reads — but the underlying bug hit Classic too (B107), and its sibling B108
killed Plex/Jellyfin/Emby finish-scrobbling and video-playlist advance in **every** mode. Fixing those
necessarily changed Classic, and that was legitimate as its own scoped change with the impact stated
up front. Do not let the rule turn a shared bug into one nobody is allowed to fix — say plainly that
it is separate work and let the user decide.

Three corollaries follow from it, each of which has already cost a phase. They are one line here and
a worked example in [reference/harness.md](reference/harness.md):

- **A structural probe is not a picture.** `surfaces=1` says a client area exists, never where it is
  drawn. Render it or run it before handing it over — §*A structural probe is not a picture*.
- **A number that moved is not the symptom that was reported.** Reproduce the reporter's own steps end
  to end, and drive the repro yourself — §*A number that moved is not the symptom that was reported*.
- **Verify window geometry in the running app, not in your head.** `WINAMP_MODERN_PLACE_TRACE=1` is
  the probe — §*Verify window geometry in the running app*.

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

This file is a router. Find your symptom below and read that one focused reference — not this file
top to bottom. Rows are grouped by area; within a group, follow the most specific row.

### Loading, geometry, and where windows open

| Symptom / question | Read |
|---|---|
| Load, mounts, `@VARS@`, include/glob, sibling skins | [reference/loading.md](reference/loading.md) |
| Geometry, anchors, y-origin, collapsed windows | [reference/loading.md](reference/loading.md) |
| The bundled default skin, or Modern mode has nothing to load | [reference/loading.md](reference/loading.md) → *The bundled default skin* |
| A window opens at its `minimum_*` rather than the size its skin declares | [reference/loading.md](reference/loading.md) → *`default_w`/`default_h` are `<container>` attributes too* |
| A component window (visualizer, video) opens as a sliver | [reference/loading.md](reference/loading.md) → *A component window with no stated size* |
| Skin starts in an impossible all-zero settings state | [reference/loading.md](reference/loading.md) → *settings must start in a state scripts can express* |
| Where a skin's windows open, overlapping windows, the tiling | [reference/components.md](reference/components.md) |
| Skin-opened window appears in the wrong place | [reference/components.md](reference/components.md) → *default_visible* |
| Several windows in the menu share one name | [reference/components.md](reference/components.md) → *default_visible*, and `WinampModernContainerTopology.menuLabels` |
| A window the skin closes at startup is missing from every probe | [reference/components.md](reference/components.md) → *`visible` on a container answers two questions* |
| Window restores at the wrong size or one skin inherits another's frame | [reference/rendering.md](reference/rendering.md) → *A .wal window's size is still the skin's* |
| Container/layout writes do not move or size their window | [reference/rendering.md](reference/rendering.md) → *A container's x/y/w/h are its window's* |
| A bare outline rectangle opens beside the player (drop shadow, snap preview) | [reference/components.md](reference/components.md) → *A window that only fakes a Windows desktop effect* |

### Drawing: sprites, colour, text

| Symptom / question | Read |
|---|---|
| `cfgattrib`, `onActivate`, alpha, fill, sliders, `ProgressGrid`, animation; album art, animated layer or image parameter draws stale/wrong | [reference/rendering.md](reference/rendering.md) |
| Toggle works but never looks active | [reference/rendering.md](reference/rendering.md) → *onActivate* |
| Playlist/EQ/library lamp on a skin button is inverted or counts clicks | [reference/rendering.md](reference/rendering.md) → *A `TOGGLE` button's lamp* |
| Shuffle/repeat/crossfade disagree with the host | [reference/rendering.md](reference/rendering.md) → *Some cfgattrib values are the host's* |
| Vertical slider uses the wrong axis or EQ curve is absent | [reference/rendering.md](reference/rendering.md) → *A skin spells the axis two ways* |
| Bitmap icons/borders look blurry at an integer UI Size | [reference/rendering.md](reference/rendering.md) → *Bitmap interpolation follows UI Size × backing scale* |
| A window has no border or background, or a skin's own labels are invisible against it | [reference/rendering.md](reference/rendering.md) → *A standard frame whose artwork stayed in Winamp* |
| Settings window is an empty slab, or a `<Wasabi:TitleBox>` shows neither label nor body | [reference/rendering.md](reference/rendering.md) → *`<Wasabi:TitleBox>` is a body, not just a border* |
| Settings page has boxes but no switches, labels, sliders or drop-downs | [reference/rendering.md](reference/rendering.md) → *The Wasabi standard form widgets are the primitives they wrap* |
| A skin-owned right-click menu is missing or wrong, or a menu a **double-click** opens never appears | [reference/rendering.md](reference/rendering.md) → *A skin's own right-click menus* |
| Colour resolution, themes, unreadable selections/titles | [reference/rendering/colour.md](reference/rendering/colour.md) |
| White/black slab appears where a named colour belongs | [reference/rendering/colour.md](reference/rendering/colour.md) → *How a colour resolves* |
| Selected row or title text matches its background | [reference/rendering/colour.md](reference/rendering/colour.md) → *A resolved colour is not yet readable* |
| A title draws as a smear, or two objects in one slot both draw, or artwork ignores window focus | [reference/rendering/colour.md](reference/rendering/colour.md) → *`activealpha`/`inactivealpha`* |
| A `<gradient>` fills flat instead of ramping | [reference/rendering/colour.md](reference/rendering/colour.md) → *a `<gradient>` with no direction* |
| The playing playlist row has no marker, or the selection bar never appears | [reference/rendering/colour.md](reference/rendering/colour.md) → *A marker only marks when it differs* |
| Theme picker is empty or will not switch | [reference/rendering/colour.md](reference/rendering/colour.md) → *The picker* |
| A skin's colours are readable-but-bad and the user wants to fix them by hand | [reference/rendering/colour.md](reference/rendering/colour.md) → *A user override outranks the chain* |
| Text metrics, fonts, clocks, bitmap fonts, missing height, offsets | [reference/rendering/text.md](reference/rendering/text.md) |
| A paragraph draws as one clipped line, or `wrap=`/`<Wasabi:Text>` layout | [reference/rendering/text.md](reference/rendering/text.md) → *A paragraph is not a line* |
| Playlist/library/tab text draws in a console font, or a size too small | [reference/rendering/text.md](reference/rendering/text.md) → *Host-drawn text is not skin-declared text* |
| Clock fields collide or the separator sits off baseline | [reference/rendering/text.md](reference/rendering/text.md) → *A clock is a run of fields* |
| A separator or icon a script placed sits on the string beside it | [reference/rendering/text.md](reference/rendering/text.md) → *`getTextWidth()` carries the box's own margin* |
| A readout's glyphs are chopped at the bottom, or sit low in their box | [reference/rendering/text.md](reference/rendering/text.md) → *A line is centred in the cell the skin declared* |
| Splitter cursor/drag/persistence or `<Wasabi:Frame>` | [reference/rendering/frame-splitter.md](reference/rendering/frame-splitter.md) |
| Slow rendering, CPU, repaint storms | [reference/performance.md](reference/performance.md) |

### Input and hit testing

| Symptom / question | Read |
|---|---|
| Dead mouse target, clipping, regions, drag policy, `sysregion` | [reference/rendering/hit-testing.md](reference/rendering/hit-testing.md) |
| Invisible layer blocks clicks or drags the window | [reference/rendering/hit-testing.md](reference/rendering/hit-testing.md) → *Hit testing* |
| A control is dead because a *second* object shares its rect, or a skin declares the same id twice | [reference/scripting.md](reference/scripting.md) → *`getObject` skips a duplicate id that never came up* |
| A button draws, presses and glows but runs no command; `setText`/search terms disappear or a search action receives empty terms | [reference/scripting.md](reference/scripting.md) → *`embed_xui` — the wrapper **is** the control* |
| Control works once, hides itself, and cannot be clicked again | [reference/scripting.md](reference/scripting.md) → *A layout must not be left with no way to seek* |
| Config/EQ drawer or custom list will not scroll | [reference/scripting.md](reference/scripting.md) → *The mouse wheel is a layout event* |

### Scripting (MAKI)

| Symptom / question | Read |
|---|---|
| Script abort, arity, unknown method, script-built UI; host readout or EQ change never reaches a script; keyboard, mouse wheel, wrapper value, scrolling; `getAutoWidth`/`getAutoHeight` and scripted layout drift | [reference/scripting.md](reference/scripting.md) |
| A call trace stops mid-handler with no failure line | [reference/scripting.md](reference/scripting.md) → *An event handler is also a method* |
| Window jumps to a screen corner when a skin panel opens, or a skin's window chrome drifts away from the window's content | [reference/scripting.md](reference/scripting.md) → *Writing back the position a window just read* |
| A window a skin's own script closed never comes back, or opens empty | [reference/scripting.md](reference/scripting.md) → *`onSetVisible` — a window a script closes has to be reopened* |
| One window's script sets something in another window and nothing happens | [reference/scripting.md](reference/scripting.md) → *`getLayout()` answers NULL for a layout that has never been shown* |
| Dragging one window should pull another along and does not | [reference/scripting.md](reference/scripting.md) → *`onMove()` is dispatched to the window objects only* |

### Components and hosted surfaces

| Symptom / question | Read |
|---|---|
| Playlist/EQ/library hosting, synthesis, topology; `TOGGLE`, container ids, first layout, `default_visible`; NullPlayer-hosted text size or palette; an auxiliary window freezes, repaints wrong, or leaks on teardown | [reference/components.md](reference/components.md) |
| `hold="none"`, flat holder slab, component routing | [reference/components.md](reference/components.md) → *Component hosting* |
| A window opens as the skin's own frame around an empty hole | [reference/components.md](reference/components.md) → *A frame the skin drew and left for Winamp to fill* |
| Component bucket/thinger, or a skin declares a widget that never enters its include closure | [reference/components.md](reference/components.md) → *The component bucket* |
| Hosted surface survives the wrong tab or remounts dead | [reference/components.md](reference/components.md) → *Unmounting is not teardown* |
| Mode switch teardown crashes or leaks a hosted surface | [reference/components.md](reference/components.md) → *Teardown order* |
| Embedded playlist/library text sizes disagree | [reference/components.md](reference/components.md) → *How large NullPlayer draws its own text* |
| A skin's own About page, `skin.about.group`, the About GUID | [reference/components.md](reference/components.md) → *The About page is a group, not a window* |

### Visualization, video, browser, notifier

| Symptom / question | Read |
|---|---|
| `<vis>` analyzer/oscilloscope, gain, colours, modes | [reference/rendering/vis.md](reference/rendering/vis.md) |
| Visualization timing, stepped motion, pause freeze | [reference/performance.md](reference/performance.md) → *The visualization has a clock of its own* |
| AVS/MilkDrop component holder or embedded visualization | [reference/components/visualization.md](reference/components/visualization.md) |
| Plugin pane draws an analyzer and the user wants something else in it | [reference/components/visualization.md](reference/components/visualization.md) → *An unhosted pane is a surface with a choice of its own* |
| Several visualization holders show the wrong engine | [reference/components/visualization.md](reference/components/visualization.md) → *one holder per skin* |
| Video picture, child-window sizing, control bar | [reference/components/video.md](reference/components/video.md) |
| Clock or transport frozen while a video plays | [reference/components/video.md](reference/components/video.md) → *The picture's clock* |
| Video window pops out when a tab changes | [reference/components/video.md](reference/components/video.md) → *A holder leaving is a tab switch* |
| Browser/WebKit, navigation, search URL, duplicate toolbar | [reference/components/browser.md](reference/components/browser.md) |
| Scheme-less web address is mistaken for a VFS path | [reference/components/browser.md](reference/components/browser.md) → *four navigation routes* |
| Notifier toast text, layout, visibility, timing | [reference/components/notifier.md](reference/components/notifier.md) |
| Notifier title is invisible or rows overlap | [reference/components/notifier.md](reference/components/notifier.md) → *text and layout* |

### The compatibility surface, and the other engines

| Symptom / question | Read |
|---|---|
| Supported Wasabi markup; slider action families and `onSetPosition`; playlist/visualization/video toolbar actions | [compatibility/wasabi-surface.md](compatibility/wasabi-surface.md) |
| Host action is accepted but deliberately inert | [compatibility/wasabi-surface.md](compatibility/wasabi-surface.md) → action families |
| Implemented MAKI method/events | [compatibility/maki-surface.md](compatibility/maki-surface.md) |
| Security model, limits, policy, verification status | [compatibility/limits-and-policy.md](compatibility/limits-and-policy.md) |
| ClassicPro engine/import behavior | [reference/classicpro.md](reference/classicpro.md) |
| WACUP probe, branding branch, WACUP-only surface | [reference/wacup.md](reference/wacup.md) |

### Instruments, proof, and what to work on

| Symptom / question | Read |
|---|---|
| Probes, env vars, dumps, live defect | [reference/harness.md](reference/harness.md) |
| Probe reports no match or no event | [reference/harness.md](reference/harness.md) → *A blind instrument reads as a working feature* |
| Whole skin dead or startup handler aborts | [reference/harness.md](reference/harness.md) → *The order that made Phase 33 cheap* |
| Meter moves too little | [reference/harness.md](reference/harness.md) → histogram the frames |
| GUI-only scripted-control report | [reference/harness.md](reference/harness.md) → *Ask for the live trace first, not fourth* |
| Frame is fast but the app hangs | [reference/harness.md](reference/harness.md) → *Profiling the running app* |
| Renderer regression proof | [reference/harness.md](reference/harness.md) → *The golden images* |
| Proving an engine-wide change broke no other skin | [reference/harness.md](reference/harness.md) → *The corpus render sweep* |
| Measure one skin end to end | `/wal-skin-report <skin.wal>` |
| The GUI verification pass before handing work over | [manual-qa-checklist.md](manual-qa-checklist.md) |
| One named skin's current state | [skins.md](skins.md) → `skins/<skin>.md` |
| Choose the next cross-skin capability | [triage-playbook.md](triage-playbook.md), then the ranked Reach table in `WINAMP5_TASKS.md` |
| Current open work | `WINAMP5_TASKS.md` — the only live backlog; closed history is [the archive](../../docs/winamp-modern/backlog-archive.md) |

The backward-compatibility map for section-title pointers in old handoffs lives in
[`docs/winamp-modern/section-title-map.md`](../../docs/winamp-modern/section-title-map.md).

Routing rules:

- Follow the most specific row. The parent `rendering.md` owns drawable behavior that does not
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
  the map, then use the focused reference and the live `WINAMP5_TASKS.md` ranking.
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
| Resource cache + scene renderer | `WasabiRenderer.swift` — the spine: scene walk, clipping, dispatch |
| Sprites, text, colour, hit testing, Layer FX | `WasabiRendererSprites.swift`, `…Text.swift`, `…Colour.swift`, `…HitTesting.swift`, `…LayerFX.swift` |
| MAKI parser + interpreter | `MakiBytecode.swift` |
| Script runtime + method dispatch | `WinampModernScriptRuntime.swift` — the VM loop, the event surface, object lifecycle |
| MAKI receivers, by class | `WinampModernScriptRuntimeSystem.swift` (System, PlEdit, ColorMgr), `…Object.swift` (GuiObject, dynamic objects), `…Menu.swift` (PopupMenu), `…Timer.swift` (`target*`), `…Text.swift` |
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

## The pipeline and the security model

Both moved out of this router; each is one read away.

- **The load pipeline** (`.wal` → archive → VFS → XML → inventory/synthesis → initializer → renderer /
  script runtime / host, and why synthesis sits *before* initialization) —
  [reference/loading.md](reference/loading.md) → *The pipeline*.
  `WinampModernSkinLoader.load(from:additionalMounts:)` is the headless entry point for that whole
  column and the only path any test or window controller takes.
- **The security model** — the skin is untrusted input: no host filesystem access, everything bounded,
  failures typed rather than traps, a write-only plain-text pasteboard, and the one narrow typed
  exception for web navigation —
  [compatibility/limits-and-policy.md](compatibility/limits-and-policy.md) → *Security model*.
  **Do not relax any of it to make a skin load.**


## Rules for extending this subsystem

**Engine rules — normative, and none of them bend for one skin.**

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
- Add fixtures, never third-party assets. Every committed test fixture is synthetic and self-authored.
- Measure with `/wal-skin-report` rather than by hand, and land what you learn — see
  *Where new findings land*. An ad-hoc dump nobody wrote down gets re-derived, and two phases have
  already been lost that way.

**Debugging rules — always paid.** These are generalised for every subsystem in
`skills/live-ui-testing`, which treats this subsystem's harness as its reference implementation;
read that when the defect is in another engine. Each is one line here; the worked example that earned it is the
named section of [reference/harness.md](reference/harness.md).

- **Instrument before you reason.** Deducing a mechanism from bytecode plus engine source produced
  three wrong answers in a row on one defect; `WINAMP_MODERN_CALL_TRACE=1` on the running app settled
  it in one launch. Count what a method *returns*, not whether it is called — and never conclude "the
  script never ran" from per-object binding state, which does not answer that question and cost two
  phases when it was read as if it did. §*Instrument
  before you reason*, §*Ask for the live trace first, not fourth*.
- **Check `RENDER_SCRIPTS` for a failed handler before believing anything about what a skin contains.**
  Dispatch is fail-closed: one unimplemented method abandons the *whole* handler, and skins put their
  entire startup in one, so a skin whose startup aborted has no features to debug. §*The order that
  made Phase 33 cheap* — which also carries: read the skin's own `scripts/*.m` when the archive ships
  them, ask what *kind* of object a control is before concluding the skin has none, and corpus-scan
  the attribute rather than the button, then run the render sweep.
- **When a fix changes nothing on screen, look for the next fault before reverting it.** One Defix
  readout had four independent faults stacked on it. §*When a fix changes nothing on screen*.
- **A number handed to skin artwork must be in the unit that artwork is cut for.** Winamp's meters are
  vis bytes on a logarithmic sweep; a linear magnitude × 255 has been found twice and is still open in
  the `<vis>` analyzer. §*The measurement that finds scale bugs*.
- **When a probe reports nothing, check the probe can see the thing at all.** Three harness blind spots
  each made a real defect look absent. §*A blind instrument reads as a working feature*.
- The three corollaries of the Classic-safety rule above — probe-is-not-a-picture, a-number-that-moved,
  and verify-geometry-in-the-running-app — are debugging rules too.


### Where new findings land

- A durable rule about a *concept* → the `reference/` file that owns that concept.
- A fact about one named skin → `skins/<skin>.md` (indexed from [skins.md](skins.md)).
- A supported/unsupported surface fact → [compatibility.md](compatibility.md).
- A corpus-scale method or disposition → [triage-playbook.md](triage-playbook.md).
- A new backlog item → `WINAMP5_TASKS.md` with a Reach measurement; move it to the archive in the same change that closes it.
- A `/wal-skin-report` run itself → **outside the repo** unless the user asks for it; only what it
  taught you lands in the files above.
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
- `skills/original-skin-guide` — NullPlayer's own Original skin system, which is unrelated to this one
