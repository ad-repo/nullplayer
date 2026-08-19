# MAKI scripting

Reference for the `winamp-modern-skin-guide` skill: the bytecode VM, script-built UI, rotary maps, and the host data scripts read.

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

> **Gotcha:** a method with a `signature(for:)` entry but a stubbed dispatch case is **invisible to
> the compatibility report** — it looks implemented and returns a plausible value. `newgroup`
> returned `.null` this way, and the report showed zero script findings while the entire Winamp
> Modern window body was missing. If you cannot implement a method, leave it out of `signature(for:)`
> so the demand tally records it.

> **Gotcha:** the blocking list is a **queue, not a set**. Each method you add lets its script run
> further and reach the next thing it needs, so the report after a fix names methods the report
> before it could not have known about. cPro-Bento took three full rounds (9 methods → 4 → 0).
> Re-measure after every change; never work down a static list.

> **Gotcha: a float constant is two 16-bit halves, and the high half must be widened before it is
> shifted.** `(0x80 | (initial2 & 0x7f)) << 16` on a `UInt16` shifts the implicit leading one and every
> stored bit clean out of the word and leaves only `initial1`, so **every** float and double in every
> script decoded to a fraction of its value. Nothing failed and nothing was reported: Love is War
> Miku's volume step (2.55 of 255) arrived as 0.003, so the buttons ran their whole handler, called
> `setVolume`, and moved the level by nothing. Scripts reach for floats rarely enough that this
> survived every phase — assume any *arithmetic* result is untested until a skin has been watched
> doing the arithmetic.

MAKI's casts are System methods (`System.Integer(v)`, `Float`, `String`, `Boolean`), and a script
reaches for them wherever it mixes a float with an int-typed API — which is exactly where the volume
path runs.

**Opcodes are exercised at the same rate as methods** — that is, barely, until a script gets far
enough to use one. `delete` (opcode 97) consumed its operand for eight phases before anything reached
it. `delete obj` is an **expression**: the compiler emits `push; delete; pop`, so the opcode must
leave the value for the statement's own discard pop. When you first unblock a batch of scripts,
expect the *next* failure to be an interpreter bug rather than a missing method.

**A parse failure is worse than a runtime one** — it kills the whole skin, not one event. Opcode 104
(dynamic `Member` access) carries an immediate shaped like a variable record's first two bytes: a
type offset, then an "is object" flag. `Member GuiObject Tab.left;` therefore compiles to
`0x0100 | classIndex` (265 in ClassicPro's `CproTabs.maki`), which read as a plain value kind is an
"unknown value type" and fails the parse. Object members carry their class GUID through to the
member's storage.

#### Script-built UI: `onSetXuiParam` and `System.newGroup`

Winamp Modern's window frames are **hollow XML**. `Wasabi:MainFrame:NoStatus` ships only titlebar and
menubar chrome; the entire client area comes from its `content=` param at runtime:

1. The object is created from the groupdef, and its script (`standardframe.maki`) is bound to it.
2. `onScriptLoaded` fires (a **System** event) and the script caches `getScriptGroup()`.
3. Each XML attribute is delivered as `onSetXuiParam(name, value)`.
4. The handler for `content` calls `System.newGroup(id)`, which expands that groupdef as a child of
   the calling script's own group; the script then positions it with `setXmlParam`.

Three ordering rules make or break this:

- `onSetXuiParam` is a **System** event, not a GUI-object event, and each XUI instance has its own
  program instance. Dispatch it only to programs whose `ownerID` is that object, or one frame's
  `content` reaches all of them.
- It must run **after** `onScriptLoaded`. The handler binds to the script-group variable that
  `getScriptGroup()` populates during `onScriptLoaded`; dispatched earlier, no binding matches and
  every param is silently dropped.
- A **skin-level `<scripts>` block loads last** — after every object's `onScriptLoaded` *and* after the
  params. It sits at the end of `skin.xml`, which is where Winamp reads it, and it is the one script
  that may assume the rest of the skin is configured. Defix's lays out its whole SUI tab strip as
  `label.getAutoWidth() + 20` per tab; run before the labels arrived as params, all five tabs came out
  at that bare 20px, stacked at the left edge. `start()` therefore runs object-owned scripts, then
  `deliverXUIParams`, then the skin-level ones — do not collapse it back into one pass.

`<script param="…">` carries Winamp's own macros rather than a path, so it is expanded in
`WasabiSkinInitializer`, not by the VFS: `@HAVE_LIBRARY@` → `1` (we host a library surface), anything
else passed through. Defix's global script reads `stringToInteger(getParam())` as "is there a media
library?" and drops the tab when told there is not.

`WasabiSkinRuntime.instantiateGroup` performs the expansion (set by `WasabiSkinInitializer`, so
runtime growth shares the load-time VFS, limits, and object budget). Scripts declared inside the new
subtree are parsed and started via `startScripts(addedBeneath:)`, bounded by `maximumRuntimePrograms`
and by `maximumRuntimeScriptStartDepth` (a new subtree's `onScriptLoaded` may instantiate more groups;
ClassicPro nests two levels — the SUI builds the tab strip, which builds each tab).

**`newGroup` is only half of it.** Wasabi instantiates in two steps, and a skin that uses both needs
both:

```c
Tab tabI = newGroup("cpro.tab");   // created under the *calling script's* group
tabI.init(tabHolder);              // moved where it actually belongs
```

- `init(parent)` **reparents**. Treating it as a no-op left every cPro-Bento tab in the wrong parent,
  so each tab button's `setDispatcher(getScriptGroup().getParent())` addressed an object nothing was
  listening on — the tab strip had never worked in any version.
- The new subtree's own scripts must start on **attachment**, not on creation: a script's first act is
  to look around from its own group (`getScriptGroup()`, `getParent()`, `findObject`), and started
  before `init` it sees the wrong parent. Groups wait in `pendingRuntimeGroups`; one that never gets an
  `init` (Winamp Modern's frames simply leave theirs where `newGroup` put them) starts anyway once the
  outermost dispatch unwinds.
- That nested `onScriptLoaded` is dispatched to a **subset** of programs while the outer one is still
  on the stack, so the re-entrancy guard is keyed by dispatch scope as well as by (target, event) —
  otherwise the outer dispatch swallows it and every runtime-created control comes up unbound.

#### Rotary controls: `Map`

A `Map` is a bitmap the script samples rather than draws: `getValue(x, y)` returns the pixel value at
a point (MMD3's `map.png` is a 44×44 grayscale sweep of the knob's angle) and `inRegion(x, y)` says
whether the point is on the control. `new Map` and `new Timer` produce the same kind of dynamic
object — class GUIDs are not in the archive — so an object becomes a map on its first `loadMap`.
Knob scripts mix `getMousePosX()` with the x/y of a mouse event in one expression, so the cursor
position is reported in **skin pixels**, not screen points; UI Size never enters the script's world.

A `Map` is also a general **image-inspection** object, not only a knob lookup: `getWidth`/`getHeight`
size things from artwork, and `getARGBValue(x, y, channel)` reads whole pixels — ClassicPro derives
its visualization colour bands this way (`colorbandpeak="r,g,b"` from channels **2, 1, 0**, i.e. the
index is BGRA). And `loadMap` takes **either a resource id or a VFS path**; ClassicPro's "is the
plugin installed?" probe is the path form (a 1×1 `installed.png`, checked with `getWidth() != 1`).
Supporting only ids made cPro-Bento conclude the engine was missing and try to switch skins.

#### Asking a skin what it actually shipped

Engines are written to run against skins that omit optional pieces, and they ask two questions:

- **`isInvalid()`** — is this object real? True for a null receiver *and* for an object whose declared
  bitmap never resolved. ClassicPro probes for optional artwork by declaring a hidden layer over it
  (`<layer id="read.bg.left" image="player.left.alt" visible="0"/>`) and asking that layer. Answering
  "valid" for a skin that ships no `mainframe_lr.png` sent `player.maki` on to swap the window frame
  over to bitmaps that do not exist — visible as holes punched through the window's edges.
- **`getCurCfgVal()`** — the value of the config attribute the object is bound to via
  `cfgattrib="{GUID};Name"`. The GUID is the section key, the same addressing `getItemByGuid` uses.

#### Track metadata the skins actually read

Skins do not call dedicated bitrate/sample-rate APIs. `songinfo.maki` lowercases
`System.getSongInfoText()` and pulls values out around the literals `kbps`, `khz`, and the channel
words. The units must be **attached to the number** (`320kbps`, `44khz`) — a space between them and
the fields stay empty. `WinampModernHost.songInfoText` builds this; `trackDisplayTitle` supplies the
`"Artist - Title"` a song ticker shows (`trackTitle` alone drops the artist).

A skin reads that string through a `<text display="songinfo">`, so that binding must carry
`songInfoText` and not the artist/album, or its KBPS/KHZ fields stay empty however good the parse is.

A `songticker` carries no `text`/`default` attribute — its content **is** the current track, and it
scrolls by default. `ticker="bounce"` slides to the end and back; any other enabled value scrolls
continuously and is drawn twice with a gap so it never blanks between cycles. Both the TrueType and
bitmap-font paths share `tickerMotion(for:overflow:textWidth:)`.

