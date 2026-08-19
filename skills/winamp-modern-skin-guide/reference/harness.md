# Debugging harness

Reference for the `winamp-modern-skin-guide` skill. **This is the canonical probe and environment-variable reference** — every other document points here.

## Debugging a skin

(Debugging *one* skin is below. For work spanning many skins — ranking what to implement next,
finding what a skin contains that we have never rendered — use
[triage-playbook.md](../triage-playbook.md) instead.)

**Start with [skins.md](../skins.md) if the report names a skin we have measured** — it records what
already works, what is knowingly missing, and the traps that skin sets.

**Then the compatibility report.** `WinampModernLoadedSkin.compatibilityReport` (and
`compatibilityReport(withRuntime:)`) aggregates load diagnostics plus the runtime's unsupported-method
tally into de-duplicated categories (`archive`, `resources`, `groups`, `scripts`,
`unsupportedMethods`, `other`) with a coarse level (`.full` / `.degraded` / `.unsupported`). In DEBUG
builds the main window controller logs it after `scripts.start()` whenever the level is not `.full`.
The `unsupportedMethods` bucket is the **measured-demand list** for what to implement next.

**Then look at the pixels.** Structural assertions (graph built, scripts ran, node counts) cannot see
a rendering bug: a vertical-flip and a wrong crop origin survived 490+ green tests because nothing
ever rendered a frame. `WinampModernRenderDumpTests` renders every container/layout of a real skin to
PNG and reports the scene:

```sh
WINAMP_MODERN_WAL=/path/Skin.wal \
WINAMP_MODERN_RENDER_DUMP=/tmp/render \
  swift test --filter WinampModernRenderDumpTests
```

Optional env switches, all off by default:

| Variable | Effect |
|---|---|
| `WINAMP_MODERN_ENGINE` | import + mount the ClassicPro engine first (cPro skins) |
| `WINAMP_MODERN_RENDER_PROBE=<container>/<layout>` | dump every scene node: type, id, frame, clip, bitmap, attributes |
| `WINAMP_MODERN_RENDER_BITMAPS=1` | count resolved bitmaps and list any that fail to load |
| `WINAMP_MODERN_RENDER_XUI=1` | list objects with scripts and whether their events bind |
| `WINAMP_MODERN_RENDER_CLOCK=<seconds>` | pin the animation/ticker clock; render two values to prove motion |
| `WINAMP_MODERN_RENDER_MINIMUM=1` | name the objects that set each layout's protective minimum |
| `WINAMP_MODERN_RENDER_CLICKABLE=1` | objects the markup-only hit test rejects but a script hooks the mouse on |
| `WINAMP_MODERN_RENDER_CLICK=<container>/<layout>@x,y[;x,y…]` | drive a click (down, **double-click**, up, left-click, right-click) and report what it hit, its handler counts, **every attribute it changed anywhere in the graph**, the whole chain of handlers it set off, the menu a right-click builds, and a compatibility report taken *after*. Several points are driven **in order** — how you check that a second click undoes the first |
| `WINAMP_MODERN_RENDER_CLICK_WATCH=<id>,<id>` | where those objects ended up after the click, changed or not — for "it opened, but in the wrong place" |
| `WINAMP_MODERN_RENDER_SIZE=<W>x<H>` | resize the layout (clamped, as a drag is) before measuring, so a defect can be reproduced at the user's window size. It resizes the *canvas* only — the app dispatches `onResize` on a real drag, so pair it with `RENDER_EVENTS=onresize` (applied after the resize) or a script-driven layout stays at its old width |
| `WINAMP_MODERN_RENDER_EVENTS=[<container>/<layout>@]onresize,onplay,…` | drive events in order before measuring, each at its real target with its real arity. **`onresize` first** for any ClassicPro skin: much of its state is only ever assigned there |
| `WINAMP_MODERN_RENDER_SCRIPTS=1` (or `=bindings`) | per program: owner, source, declared handlers, which events actually **ran**, and which failed with what. `=bindings` adds what every handler is bound to *right now* and each script group's ancestor chain |
| `WINAMP_MODERN_RENDER_DISASM=<method>` | the instructions around every call site of a method — how an unknown **arity** is settled, by counting the net pushes between the receiver and the call |
| `WINAMP_MODERN_RENDER_DISASM=@<source>` | the **whole** listing for every program whose path matches: each handler's entry point, every instruction, constants and method names resolved. Variable values are read *after* the run, so a `vN=null` at a `findObject` is a lookup that failed. This is how Winamp Modern's titlebar layout was recovered — an arity fits in an 8-instruction window, a layout routine does not |
| `WINAMP_MODERN_RENDER_SETTINGS=1` | every option the skin registered with `newAttribute` — item name, section GUID, current and default value. What the host's **Skin Settings** window will offer, and the only headless way to see options a skin registers for Winamp's preferences dialog and binds no control to |
| `WINAMP_MODERN_RENDER_FX[=play]` | every layer whose script has switched **Layer FX** on: grid, flags, and where the evaluated mesh samples its corners from. A mesh that is not the identity is a layer that is actually moving. `=play` tells the skin a track started first, because a meter's FX is switched on from playback |
| `WINAMP_MODERN_RENDER_FX_SPIN=<seconds>` | samples every warped layer's angle at 60 Hz, printing the wall-clock step between updates and how far it turned. This is how "the animation is rough" is split into *the script's cadence* and *our frame rate* — a smooth meter is a small, even step at an even interval |
| `WINAMP_MODERN_RENDER_VU=<level>` | inject a program level per channel (0…1) for `getLeftVUMeter`/`getRightVUMeter`; `sweep` oscillates 0…1 at 0.5 Hz. The harness has no audio, so without it every meter reads silence and a needle's travel cannot be measured |
| `WINAMP_MODERN_RENDER_CONFIG=<section>;<key>=<value>[\|…]` | write skin configuration **before** the scripts start — where the app reads it from, since the value is persisted. How a skin option that changes what is drawn (Defix's eight display styles) is selected without a GUI. Note it *stays* set for later runs, and a skin may keep its own private copy (Defix: `CurVuVis`) |
| `WINAMP_MODERN_RENDER_TIME=<frames>` (+ `_SCALE=2`, `_CLIP=1`) | ms/frame for a full repaint. `_SCALE=2` is the number that matters — it is the Retina backing store the app actually pays for; `_CLIP=1` measures the same frame clipped to the warped layers' rects. Defix, after Phase 29's pre-scaled artwork cache: **3.5 ms at 2×** idle, 5.4 ms with both reels warping, 4.4 ms clipped (it was 19.3 / 6.9 when every bitmap was resampled to the backing scale on every frame) |
| `WINAMP_MODERN_DRAW_PROFILE=1` | per-object draw cost, top 8 — which node costs the frame, without a sampling profiler |
| `WINAMP_MODERN_FX_TRACE=1` | every `fx_*` call with its receiver: which layers a skin warps, and **when** it switches them on |
| `WINAMP_MODERN_CALL_TRACE=1` | every MAKI method call with its arguments and result |
| `WINAMP_MODERN_VU_LOG=1` | **live**, not headless: once a second, the arriving buffer's peak and RMS, the tap cadence, how many ~13 ms blocks it was split into, and the 0…255 byte range the skin receives across them. `peak` against `blockRange` is the whole diagnosis for "the meter doesn't follow peaks and valleys" — a wide block range with a flat needle is a skin-side ballistics question, a narrow one is a measurement question. `RENDER_VU` exercises only the half of the path *above* the meter |
| `WINAMP_MODERN_MAKI_TRACE=<program>` | every bytecode instruction of the matching programs, with the top of the value stack. The last resort, and the only thing that finds a wrong *result* from a handler that does not fail — it is how an integer-truncating unary minus was found collapsing a needle's angle to two positions |
| `WINAMP_MODERN_RENDER_SETTLE=<seconds>` | pump the run loop before dumping, so timer-driven state has happened — and **between driven clicks**, because a skin that gates a transition on a timer (`if (anim.isRunning()) return; anim.start();`, Defix's tab switch) never releases the gate without one, and a working control measures as one that only responds the first time |


Timing probes need an optimized build: `swift test -Xswiftc -O --filter WinampModernRenderDumpTests`
(a debug build is ~6× slower and will mislead you; `swift test -c release` does not compile, because
the test target uses `#if DEBUG` hooks). Two things that waste an afternoon: `cd`-ing out of the repo
before `swift test` fails silently when the output is piped to `grep`, and the harness's skin
configuration persists in the **xctest** UserDefaults domain between runs
(`defaults delete com.apple.dt.xctest.tool` resets it).

Use the probe to answer "is it missing art, bad geometry, or a script that never ran" before changing
renderer code — `BITMAPS … missing=` distinguishes an unresolved resource from one that draws wrongly.

**A dead control is usually a dead script, not a bad hit test.** `RENDER_CLICK` answers that in one
run: it prints the object under the point, `bindings=`, and the handler count for each mouse event.
`hits togglebutton#… bindings=false` with `onleftclick -> 0` means the script that should have hooked
it never ran.

> **Do not read `RENDER_XUI`'s `onscriptloaded=false` as "the script never ran."** It reports per-object
> *bindings*, and on cPro-Bento it says `false` for **every** object in the skin, `layout id=normal`
> included — whose scripts demonstrably run. An earlier phase pinned the inert tab strip on exactly
> that misreading and chased the wrong thing for two phases; the real cause was `Group.init(parent)`
> being a no-op. `RENDER_SCRIPTS` is the probe that observes execution, and `RENDER_CLICK`'s handler
> chain is the one that shows where a message stops.

**A control that responds but changes nothing is a chain that stops partway.** `RENDER_CLICK` prints
the chain (`CproTabButton.onleftbuttonup -> CproTabs.onaction -> CentroSUI.onaction`) and every
attribute the click moved. A chain that ends one hop early is a missing script-to-script route; a click
that changes the right attributes but nothing on screen is a renderer gap.

> **Gotcha:** the harness must install an `NSGraphicsContext` around `renderer.draw`. `drawText` ends
> in `NSString.draw(in:withAttributes:)`, which renders into the *current* `NSGraphicsContext`, not
> the `CGContext` it was handed. Without it every TrueType/system-font string is silently dropped from
> the dump while the real app (always inside `NSView.draw`) shows them — the harness lies to you.

`RENDER_SETTLE` is usually the difference between a dump that means something and one that does not:
Love is War Miku's whole opening animation (the display panel sliding to `y=84`, the character to
`x=129`) runs on a 300ms timer, so without it the dump shows a scene the user never sees. And the
load-time compatibility report is **clean** for anything a click reaches — a handler that fails on a
missing method records nothing until something drives the event, which is why `RENDER_CLICK` prints its
own report afterwards.

**The dump only ever renders a skin's *initial* state.** A defect a script mutation introduces later
(a font swapped at runtime, an object shown after a click) is invisible to it. `WinampModernCrashRepro`
is the opt-in harness for that case: it fires every standard event at every object in graph order,
redrawing after each, then sweeps the clock. It was written for a live-run crash it still does not
reproduce — extend it rather than starting over.

> **Anything a skin controls can reach CoreText, and a nil there kills the process.**
> `NSString.size(withAttributes:)` aborts with `attempt to insert nil object` if any attribute value
> is null — inside `NSView.draw`, so it is an app crash, not a bad frame. AppKit/CoreText
> constructors are imported as non-optional but can still return null, and **only an `Optional`
> binding sees it** (`let font: NSFont? = …`). `WasabiResources.font` therefore returns `NSFont?`,
> point sizes are clamped to a finite 1…256, and a skin TrueType with no PostScript name is rejected.
> Apply the same discipline to any new skin-derived value handed to a system API.

`WinampModernRenderPixelTests` is the synthetic guard for all of the above: a banded atlas whose crop
origin, upright orientation, tiling, and `fitparent` sizing are asserted per pixel. When you touch
`WasabiSceneRenderer`, verify a fix *fails* without the change before trusting it.

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

