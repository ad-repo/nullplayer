---
name: winamp-modern-skin-guide
description: Winamp 5.x .wal skin engine — Wasabi XML/XUI renderer, MAKI bytecode VM, VFS mounts, component hosting, and the ClassicPro engine import. Use when working on the WinampModern subsystem, debugging a .wal skin that fails to load or renders wrong, or extending Wasabi/MAKI coverage.
---

# Winamp Modern (`.wal`) Skin Engine

NullPlayer's fourth UI mode (`PlayerUIMode.winampModern`) loads and runs **Winamp 5.x modern skins** —
`.wal` archives containing Wasabi XML/XUI markup and compiled MAKI bytecode. It is a clean-room
implementation: the archive is parsed, the object graph is built, and the scripts are interpreted by
NullPlayer's own code. No Winamp binary, plugin, or asset is bundled.

**Status: experimental.** The runtime loads, scripts, and renders real skins, but see
[compatibility.md](compatibility.md) for the exact supported/unsupported surface before assuming any
behavior works.

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
| Resource cache + scene renderer | `WasabiRenderer.swift` |
| MAKI parser + interpreter | `MakiBytecode.swift` |
| Script runtime + method dispatch | `WinampModernScriptRuntime.swift` |
| Skin-facing host API | `WinampModernHost.swift` |
| Component model + host protocol | `WinampModernComponents.swift` |
| Container topology | `WinampModernContainerTopology.swift` |
| Diagnostics | `WalDiagnostics.swift` |
| Compatibility report | `WinampModernCompatibilityReport.swift` |
| Complete loader | `WinampModernSkinLoader.swift` |
| Import + storage | `WinampModernSkinImporter.swift` |
| ClassicPro engine import | `ClassicProEngine.swift`, `NSISArchive.swift`, `LZMA1Decoder.swift` |
| Window controller / view | `Windows/WinampModern/WinampModernMainWindowController.swift`, `…MainView.swift` |
| `AudioEngine` component bridge | `Windows/WinampModern/WinampModernComponentBridge.swift` |

Design records and per-phase handoffs: `docs/winamp-modern/`.

## The pipeline

```
.wal file
  └─ WalArchive              validate + bound (ZIP, read-only, on-demand inflate)
      └─ WalVirtualFileSystem  mount at /Skins/<name>/, resolve @VARS@, case-insensitive
          └─ WalXMLDocumentLoader  parse skin.xml, expand <include>/<elementinclude> + globs
              └─ WasabiSkinInitializer  6 ordered passes → registries + retained graph
                  ├─ WasabiSceneRenderer   graph → Core Graphics
                  ├─ WinampModernScriptRuntime  MAKI programs bound to graph objects
                  └─ WinampModernHost      the only door to AudioEngine
```

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

### VFS mounts

Fixed logical mounts only — the skin never sees a real path:

| Logical path | Backed by |
|--------------|-----------|
| `/Skins/<sanitized-name>/` | the `.wal` archive |
| `/Plugins/classicPro/engine/` | the imported ClassicPro engine, when installed |
| `/System/` | code-supplied defaults via `WinampModernAdditionalMount` |

Path variables: `@WINAMPPATH@`, `@SKINPATH@`, `@COLORTHEMESPATH@`, `@DEFAULTSKINPATH@`. Windows
separators, `.`, and `..` are normalized; a path escaping `/` is a hard error. A `*` wildcard is
allowed **only** in the final include component and returns sorted, deterministic results.

Cross-mount climbs work, which is how cPro-Bento reaches its engine:
`@COLORTHEMESPATH@\..\..\Plugins\classicPro\engine\load.xml`.

### Initialization passes

`WasabiSkinInitializer` runs six explicit, tested passes, in this order:

1. resource registration
2. groupdef/XUI registration + inheritance validation
3. object creation
4. script binding
5. initialization
6. first-paint preparation

Group semantics worth knowing:

- `inherit_group` **is** the inheritance edge (depth limit 64, cycle-detected).
- `embed_xui` is retained as metadata and is **not** an inheritance edge.
- `xuitag` registers a custom XML tag name for group instantiation.
- A later duplicate definition **replaces** an earlier one and emits a warning — this is deliberate;
  it is how skins override engine defaults.
- `registerWasabiStandardLibrary` seeds the curated `wasabi.*` base groups that ship inside Winamp
  rather than in the archive. Skin/engine definitions register first and always win. A base outside
  the curated set warns and is dropped rather than failing the load.

### Retained graph and coordinates

`WasabiObjectGraph` owns every node (including detached ones). IDs are monotonic and deterministic
for a deterministic expanded document, which makes `snapshot()` the golden-test surface. XML `id`
values are attributes and are **not** unique, so `objects(xmlID:)` returns an array.

Geometry stays in **Wasabi top-left coordinates** throughout the graph. The signed-anchor rule is
encoded in `WasabiGeometry`:

- `x=-60 relatx=1` → `parent.width - 60`
- `w=-120 relatw=1` → `parent.width - 120`
- same for Y/height; missing dimensions use the intrinsic size

> **Gotcha:** the Y flip to AppKit's bottom-left happens exactly **once**, at the Core Graphics
> drawing boundary in `WasabiSceneRenderer` (and once at the event boundary in `WinampModernMainView`).
> Never store flipped coordinates back into the graph, and never insert AppKit types into graph objects.

### MAKI

`MakiBytecodeParser` reads the `FG` compiled-script format (classes, methods, typed
variables/constants, bindings, instructions); `MakiInterpreter` executes it. The opcode surface is
**demand-driven** — opcodes were added because a measured target skin needed them, and unsupported
opcodes **fail closed** rather than becoming silent no-ops.

A missing method aborts only the script event that hit it — the rest of the skin's scripts still run
and the failure is collected into the compatibility report. It cannot be finer-grained than that:
call sites carry no argument count, so without a signature the stack cannot be unwound.

> **Gotcha:** `MakiInterpreter.dispatcher` is `weak` (the runtime owns the dispatcher). If you
> construct an interpreter in a test with a temporary dispatcher, it deallocates immediately and
> `execute` silently returns at its `guard let dispatcher` without running an instruction — the test
> then passes for the wrong reason. Bind the dispatcher to a local first.

Extending the API: add to `signature(for:)` **and** the matching system/GUI/object dispatch path
together, so argument counts and return kinds stay explicit. Add a regression test with each method.
Use the measured-demand signal rather than porting reference stubs blindly — see
[Debugging](#debugging-a-skin) below.

### Component hosting

cPro-Bento is a single-window SUI: the playlist, library, visualization, video, and EQ are embedded in
the main window via `windowholder hold="guid:…"` rather than living in separate windows. The engine is
therefore **component-hosting-first**:

- `WinampModernComponentRegistry` maps the standard Winamp component GUIDs to a typed
  `WinampModernComponentKind`. **GUIDs never escape the registry.**
- `WinampModernContainerTopology.analyze` classifies each container as a real visible window or an
  SUI-collapsed stub (1×1 / `window-overrides` invisible), and yields the container→window mapping.
- `WinampModernComponentHost` is the sandboxed seam supplying app-side content per kind;
  `WinampModernComponentBridge` implements it over `AudioEngine`.
- `TOGGLE`/`sendaction` for eq/pl/ml/video resolves to the embedded component first, then a separate
  skin window, then the classic `WindowManager` window as a fallback.

There is **one** script runtime and **one** component host per loaded skin, shared by the main window
and every auxiliary container window. Only the main view (`drivesScripts: true`) tears down the shared
runtime.

### Teardown order

Synchronous and idempotent — every async producer must stop before its resources are released:

1. `WinampModernMainView.teardown()` — interaction state, then scripts + renderer
2. `WinampModernScriptRuntime.teardown()` — graph/popup callbacks, timers, interpreter, vis consumer
3. `WasabiSceneRenderer.teardown()` — decoded resource caches
4. `WinampModernLoadedSkin.teardown()` — retained graph + VFS-owned state

Auxiliary container views tear down **before** the main view; the graph goes last.
`WinampModernMainWindowController.prepareForUITeardown()` drives this before a mode controller is
released.

## Mode integration

`PlayerUIMode` has four cases across three controller families
(`PlayerUIControllerFamily`): `classic`, `nullPlayerModern` (Modern + Metal), and `winampModern`.

> **Gotcha:** `WindowManager.isModernUIEnabled` means `controllerFamily == .nullPlayerModern`
> **only**. It is a documented shim, and it is `false` in Winamp Modern mode — the ~15 geometry call
> sites behind it deliberately route Winamp Modern down the classic path. Do not "fix" it to include
> the new family.

Winamp Modern uses the **classic 10-band EQ** (`usesModernEQLayout == false`) and has no
`modernSkinFamily`. Auxiliary windows (playlist/EQ/library) reuse the classic controllers unless the
skin embeds them as components. Mode switching is live, and `AudioEngine` is owned by `WindowManager`,
so playback survives a switch untouched.

Persistence writes `false` to the legacy `modernUIEnabled` bool so older clients degrade to classic
rather than reading a corrupt value.

## ClassicPro engine

cPro-Bento does not contain its own engine — it depends on the **ClassicPro** plugin, which ships in a
separate Windows installer. NullPlayer bundles nothing and asks for no permission; the user supplies
the installer and it is extracted **internally**, with no external tools, temp files, or code
execution:

- `LZMA1Decoder` — from-scratch incremental raw LZMA1 range decoder
- `NSISArchive` — NSIS-2 solid-LZMA reader; replays only `SetOutPath`/`ExtractFile` to reconstruct the
  file tree. Other layouts (non-solid, zlib/bzip2, NSIS-3, non-NSIS) get an actionable diagnostic.
- `ClassicProEngineImporter` accepts `.exe`, `.zip` (including a nested installer), or an extracted
  folder; validates structure (requires the `one` family) and SHA-256 hashes the content
- `ClassicProEngineStore` keeps one private copy and exposes a read-only mounted provider

The engine's entire native (`ClassicPro.w5s`) surface is three filesystem-shell methods, none on the
render path. They are adapted under a strict policy: `exploreFile` reveals an existing file in Finder,
`openFile` opens an existing file with the default app (no URLs, no `~`, no executables), and
`findFiles` is a bounded no-op returning −1 so callers early-return.

`WinampVersionCheck` is satisfied by reporting a build number past the `2405` gate, so `load.xml`
*branches* through its "please update Winamp" path rather than being hard-blocked.

## Debugging a skin

**Start with the compatibility report.** `WinampModernLoadedSkin.compatibilityReport` (and
`compatibilityReport(withRuntime:)`) aggregates load diagnostics plus the runtime's unsupported-method
tally into de-duplicated categories (`archive`, `resources`, `groups`, `scripts`,
`unsupportedMethods`, `other`) with a coarse level (`.full` / `.degraded` / `.unsupported`). In DEBUG
builds the main window controller logs it after `scripts.start()` whenever the level is not `.full`.
The `unsupportedMethods` bucket is the **measured-demand list** for what to implement next.

Load a developer archive directly (DEBUG builds):

```sh
./.build/debug/NullPlayer -uiMode winampModern -winampModernSkinPath /abs/path/Skin.wal
```

This still goes through `WinampModernSkinLoader` and its VFS — it is an acceptance hook, not a
filesystem bypass.

Run the engine tests:

```sh
swift test --filter WinampModern              # all synthetic coverage, headless
swift test --filter WinampModernPhase7Tests   # fuzz / stress / limits
```

Opt-in tests against user-supplied skins (nothing third-party is committed, so these skip unless the
env var is set):

```sh
WINAMP_MODERN_WAL=/path/CornerAmp_Redux.wal swift test --filter WinampModernPhase3Tests
WINAMP_MODERN_WAL=/path/WinampModern.wal     swift test --filter WinampModernPhase4Tests
WINAMP_MODERN_ENGINE=/path/ClassicPro_2.01.exe \
  WINAMP_MODERN_WAL=/path/cPro__Bento.wal    swift test --filter WinampModernPhase6Tests
```

Each phase expects a specific fixture — Phase 4 asserts Winamp Modern's 354×280 geometry, so
cPro-Bento is the wrong fixture for it.

## Rules for extending this subsystem

- Do not weaken a limit or a sandbox rule to make a skin load. Degrade gracefully with a warning
  diagnostic instead — a missing optional bitmap or an unknown `wasabi.*` base should warn, not fail.
- Do not add host capabilities beyond what a measured skin needs, and keep them narrow and typed.
- Do not put platform rendering state into `WasabiObjectGraph`.
- Do not broaden the release UI surface as a side effect of unrelated compatibility work.
- Preserve `WalDiagnostic`s; do not replace them with renderer-specific string errors.
- Add fixtures, never third-party assets. Every committed test fixture is synthetic and self-authored.

## Related

- [compatibility.md](compatibility.md) — supported/unsupported Wasabi + MAKI surface, limits, engine policy
- [manual-qa-checklist.md](manual-qa-checklist.md) — the GUI verification pass
- `docs/winamp-modern/` — decision records and per-phase handoffs
- `docs/legal/winamp_modern_provenance.md` — clean-room provenance record
- `skills/modern-skin-guide` — NullPlayer's *own* modern skin system, which is unrelated to this one
