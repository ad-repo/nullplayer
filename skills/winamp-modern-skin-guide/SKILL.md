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
default state is not the skin** (Defix ships eight display styles; the cassette is one of them, and the
animated VU meters behind the other eight have never been rendered here).

## Routing: which file answers this?

This file is a **router**. It carries the pipeline, the security model, the file map, and the rules —
everything every task in this subsystem needs. The detail lives in `reference/`, one file per
concept; read the one your symptom points at, not all of them.

| Symptom / question | Read |
|---|---|
| Skin fails to load, mounts wrong, `@VARS@` unresolved, include/glob trouble | [reference/loading.md](reference/loading.md) |
| Skin says it needs another skin installed; an overlay/`Light` edition; `@SKINSPATH@` | [reference/loading.md](reference/loading.md) → *Sibling skin mounts* |
| Object is in the wrong place, y flipped, window collapsed to nothing | [reference/loading.md](reference/loading.md) |
| A button is dead under the mouse; clipping, dragging, region trouble | [reference/rendering.md](reference/rendering.md) + [reference/harness.md](reference/harness.md) |
| Something draws wrong, missing, mis-clipped, wrong colour, wrong font, wrong text | [reference/rendering.md](reference/rendering.md) |
| **Text or controls are black-on-black, or a colour theme washes out** — and "fixing" one skin breaks another | [reference/rendering.md](reference/rendering.md) — *Colour themes*: the additive/multiplicative model is per-`<gammagroup>`, chosen by its own `boost`. Never pick one globally |
| Animation frozen, needle/reel not turning, layer stuck on one frame | [reference/rendering.md](reference/rendering.md) |
| Slow, stuttering, CPU high, repaint storm | [reference/performance.md](reference/performance.md) |
| **The UI hangs or runs at a few fps** — and `RENDER_TIME` says the frame is fine | [reference/harness.md](reference/harness.md) — *Profiling the running app*: `sample` the process; `RENDER_TIME` measures `renderer.draw` and nothing else |
| **A splitter shows a resize cursor but drags the window instead** | [reference/rendering.md](reference/rendering.md) — *What outranks a splitter on its own grab strip* |
| **A splitter (or any skin-owned state) forgets where the user put it on relaunch** | [reference/rendering.md](reference/rendering.md) — *Where the user left the divider survives a relaunch*: only a **drag** is stored, and the restore has to land after the scripts settle |
| **Deciding whether some new piece of skin state should persist** | [reference/rendering.md](reference/rendering.md) — *What else the host remembers about a skin, and what it must not*: the skin's own prefs already persist; only graph-owned state needs saving, and only from a user gesture |
| A `{0000000A}` visualization slot shows the wrong thing, or only one of several works | [reference/components.md](reference/components.md) — *`{0000000A}` is a plugin host*: it is not "MilkDrop's box", and one holder per skin gets the engine |
| A script does nothing, wrong arity, unknown method, script-built UI missing | [reference/scripting.md](reference/scripting.md) |
| A host-fed readout never updates (`onTextChanged`) | [reference/scripting.md](reference/scripting.md) |
| An EQ readout follows the skin's own slider but not a preset, the menu bar or another window | [reference/scripting.md](reference/scripting.md) — *The equalizer tells the skin it moved* |
| A keyboard shortcut the skin declares does nothing (`onKeyDown`, `alt+g`, `ctrl+w`) | [reference/scripting.md](reference/scripting.md) — *The keyboard is a string, and a borderless window has to ask for it* |
| **A toggle works but never looks on** — a lamp, an `activeimage`, a word in the display that should brighten | [reference/rendering.md](reference/rendering.md) — *`onActivate`*: the indicator's event, and a `cfgattrib`-bound control keeps no `activated` of its own |
| Shuffle / repeat / crossfade disagree with the menu bar, or a skin's crossfade button drives nothing | [reference/rendering.md](reference/rendering.md) — *Some `cfgattrib` values are the host's*: `WinampModernConfigBridge`, and why one setting must not have two homes |
| A slider drags but nothing happens, or its readout never appears | [compatibility/wasabi-surface.md](compatibility/wasabi-surface.md) — the action families, and `onSetPosition` on a drag |
| Playlist / EQ / library / video surface missing, empty, or in the wrong window | [reference/components.md](reference/components.md) |
| A hosted surface (library/video/vis) stays on screen over another tab, or comes back dead, after its holder went away and returned | [reference/components.md](reference/components.md) — *Unmounting is not teardown* |
| **A flat slab of one colour covers artwork that should be there** — a seek bar, a display panel | [reference/components.md](reference/components.md) — *Component hosting*: an `.other` holder fills its rect, and `hold="none"` means the holder holds nothing |
| **A control works once and then cannot be clicked again**, or a seek bar vanishes after one drag | [reference/scripting.md](reference/scripting.md) — *A layout must not be left with no way to seek*: a script's `hide()` can strand an action, and an invisible object is not hit-testable |
| **The mouse wheel does nothing** — a settings page, drawer or custom list will not scroll | [reference/scripting.md](reference/scripting.md) — *The mouse wheel is a layout event, and it carries two arguments* |
| **A vertical slider will not drag**, its thumb slides the wrong way, or an EQ shows no curve | [reference/rendering.md](reference/rendering.md) — *A skin spells the axis two ways, and `"v"` is not a typo* |
| A scrollbar moves but its page does not, or a control's position reads 0 however far it is dragged | [reference/scripting.md](reference/scripting.md) — *`embed_xui` — the wrapper **is** the control* |
| **A GUI-only report on a scripted control** — where do I even start? | [reference/harness.md](reference/harness.md) — *Ask for the live trace first, not fourth* |
| A button that should open a window does nothing (`TOGGLE`, container ids) | [reference/components.md](reference/components.md) |
| **A skin's web button does nothing, opens the wrong browser, or lands on a page with no query** | [reference/components.md](reference/components.md) — *The four routes a skin reaches the web by*: `navigateUrl` is the **user's** browser, a scheme-less address is not a VFS path, and `browser_search` carries terms while `browser_navigate` carries a URL |
| **A search runs with the terms missing** (`?q=` empty, "searched for the word lyrics") | [reference/scripting.md](reference/scripting.md) — *`embed_xui`*: `getText()` on a wrapper whose inner control holds the string answers `""` |
| A window the skin opens with itself does not open, or opens in the wrong place (`default_visible`, `default_x`/`default_y`) | [reference/components.md](reference/components.md) |
| A whole container — or a whole skin — is missing, and its layouts are named something other than `normal` | [reference/components.md](reference/components.md) — *Which layout a container opens in* |
| A toolbar button on a playlist/visualization/video window does nothing (`PE_*`, `VIS_*`, `VID_*`, `CB_*`) | [compatibility/wasabi-surface.md](compatibility/wasabi-surface.md) — the host-action families, and the three that are inert on purpose |
| An auxiliary window draws once then freezes; a script's `onTimer` changes nothing on screen | [reference/components.md](reference/components.md) |
| Notifier toast doesn't show, shows wrong text, ghost default text, title invisible | [reference/components.md](reference/components.md) §*Notifier — track-change toast* |
| Teardown crash, leak, or mode-switch breakage | [reference/components.md](reference/components.md) |
| A ClassicPro (`.wal` + NSIS engine) skin misbehaves | [reference/classicpro.md](reference/classicpro.md) |
| A **WACUP**-era skin: should we claim to be WACUP, why a branch is dead, a plugin surface that never appears | [reference/wacup.md](reference/wacup.md) — the answer is *no*, with the measurement |
| **How do I see what the engine is doing?** Probes, env vars, dumps | [reference/harness.md](reference/harness.md) |
| A GUI-only report, and no probe reproduces it | [reference/harness.md](reference/harness.md) — *Debugging a live defect* |
| **A whole skin is dead / "none of it works"** — start at the abort, not the symptom | [reference/harness.md](reference/harness.md) — *The order that made Phase 33 cheap* |
| **What should I work on next?** | `TASKS.md` for the engine, **`BENTO_TASKS.md`** for the Big Bento Modern family (`BB*`, split out 2026-08-23 when it had grown to four sections). Those two files are the **whole** backlog, and both are tracked in git (they were gitignored until 2026-08-23). The old third copy `docs/winamp-modern/open-items.md` was deleted 2026-08-23; do not recreate it |
| A meter/needle/cone runs but barely moves | [reference/harness.md](reference/harness.md) — histogram the frames it uses |
| **I changed the renderer — what proves I broke nothing?** | [reference/harness.md](reference/harness.md) — *The golden images*, then the 17-skin sweep for real artwork |
| What Wasabi markup is supported at all? | [compatibility/wasabi-surface.md](compatibility/wasabi-surface.md) |
| Is this MAKI method implemented? What events fire? | [compatibility/maki-surface.md](compatibility/maki-surface.md) |
| Limits, engine policy, verification status | [compatibility/limits-and-policy.md](compatibility/limits-and-policy.md) |
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
| Some `cfgattrib` values are the **host's**, not the skin's — and a bound control keeps no state of its own | [reference/rendering.md](reference/rendering.md) |
| `onActivate` — how a skin shows that a toggle is on | [reference/rendering.md](reference/rendering.md) |
| `<AlbumArt>` needs a host that actually has the cover | [reference/rendering.md](reference/rendering.md) |
| `alpha` belongs to the object, not to one kind of drawing | [reference/rendering.md](reference/rendering.md) |
| An image param is a *load*, and a failed load changes nothing | [reference/rendering.md](reference/rendering.md) |
| Layer fill modes | [reference/rendering.md](reference/rendering.md) |
| `<ProgressGrid>` — the bar's *filled* part | [reference/rendering.md](reference/rendering.md) |
| A skin's own right-click menus | [reference/rendering.md](reference/rendering.md) |
| The three action attributes (Phase 36) | [reference/rendering.md](reference/rendering.md) |
| Colour themes (`gammaset` / `gammagroup`) | [reference/rendering.md](reference/rendering.md) |
| Colour theme screen is empty / will not switch | [reference/rendering.md](reference/rendering.md) §*The picker* |
| Animated layers are played as a range | [reference/rendering.md](reference/rendering.md) |
| The frame budget: what repaints, and what it costs | [reference/performance.md](reference/performance.md) |
| MAKI | [reference/scripting.md](reference/scripting.md) |
| Script-built UI: `onSetXuiParam` and `System.newGroup` | [reference/scripting.md](reference/scripting.md) |
| Rotary controls: `Map` | [reference/scripting.md](reference/scripting.md) |
| Asking a skin what it actually shipped | [reference/scripting.md](reference/scripting.md) |
| Track metadata the skins actually read | [reference/scripting.md](reference/scripting.md) |
| A file-info line is blank / `getPlayItemMetaDataString` keys and units | [compatibility/maki-surface.md](compatibility/maki-surface.md) |
| Star ratings (`getCurrentTrackRating` and its 0–5 vs 0–10 scale) | [compatibility/maki-surface.md](compatibility/maki-surface.md) |
| `onTextChanged` is how a skin learns a host readout moved | [reference/scripting.md](reference/scripting.md) |
| The equalizer tells the skin it moved | [reference/scripting.md](reference/scripting.md) |
| The keyboard is a string, and a borderless window has to ask for it | [reference/scripting.md](reference/scripting.md) |
| The mouse wheel is a *layout* event, and it carries two arguments | [reference/scripting.md](reference/scripting.md) |
| `embed_xui` — the wrapper **is** the control, and must not keep a second copy of its value | [reference/scripting.md](reference/scripting.md) |
| Scrolling: `scrollToPercent` is a viewport offset, not a layout change | [reference/scripting.md](reference/scripting.md) |
| A skin spells the axis two ways, and `"v"` is not a typo | [reference/rendering.md](reference/rendering.md) |
| Ask for the live trace first, not fourth | [reference/harness.md](reference/harness.md) |
| Which layout a container opens in | [reference/components.md](reference/components.md) |
| `TOGGLE`'s parameter is a component **or a container id** | [reference/components.md](reference/components.md) |
| `default_visible="1"` — the windows a skin opens with itself | [reference/components.md](reference/components.md) |
| Component hosting | [reference/components.md](reference/components.md) |
| The four routes a skin reaches the web by (B40) | [reference/components.md](reference/components.md) |
| The window layer these views sit in | [reference/components.md](reference/components.md) |
| Where a surface lives | [reference/components.md](reference/components.md) |
| Synthesizing a missing window | [reference/components.md](reference/components.md) |
| NullPlayer-owned hosted windows are lazy | [reference/components.md](reference/components.md) |
| Container-scoped layout callbacks | [reference/components.md](reference/components.md) |
| Resize, and why a skin needs it | [reference/components.md](reference/components.md) |
| Colours and hosted AppKit content | [reference/components.md](reference/components.md) |
| Repaint routes are per-window, and scripts are not | [reference/components.md](reference/components.md) |
| Teardown order | [reference/components.md](reference/components.md) |
| Mode integration | [reference/components.md](reference/components.md) |
| Notifier — track-change toast | [reference/components.md](reference/components.md) |
| ClassicPro engine | [reference/classicpro.md](reference/classicpro.md) |
| WACUP-era skins | [reference/wacup.md](reference/wacup.md) |
| An `<animatedlayer>` is one frame, not one sheet | [reference/rendering.md](reference/rendering.md) |
| Debugging a skin | [reference/harness.md](reference/harness.md) |
| The order that made Phase 33 cheap | [reference/harness.md](reference/harness.md) |
| The golden images | [reference/harness.md](reference/harness.md) |
| What is open right now, ranked | `TASKS.md` + `BENTO_TASKS.md` (together, the whole backlog); [triage-playbook.md](triage-playbook.md) §4b keeps B1–B10's ranking as history |

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
| What the host remembers about a skin between launches (B44/B44a) | `WinampModernSkinState.swift` |
| Fonts + text measurement (shared) | `WasabiTextMetrics.swift` |
| Resource cache + scene renderer | `WasabiRenderer.swift` |
| MAKI parser + interpreter | `MakiBytecode.swift` |
| Script runtime + method dispatch | `WinampModernScriptRuntime.swift` |
| Skin-facing host API | `WinampModernHost.swift` |
| Component model + host protocol | `WinampModernComponents.swift` |
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
[reference/components.md](reference/components.md) — *The four routes a skin reaches the web by*.


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
