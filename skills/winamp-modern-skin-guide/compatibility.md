# Winamp Modern (`.wal`) — Supported and Unsupported Behavior

What NullPlayer's Wasabi/MAKI runtime actually does, what it deliberately does not, and the limits it
enforces. Companion to [SKILL.md](SKILL.md).

The engine is **demand-driven**: coverage was added because a measured target skin needed it, not by
porting a reference implementation wholesale. So this document describes a real, narrow surface —
assume anything not listed is unimplemented, and confirm with the per-skin compatibility report rather
than guessing.

## Reference targets

Three skins drove the implementation, in increasing order of demand:

| Target | Role | State |
|--------|------|-------|
| **CornerAmp_Redux** | first vertical slice | loads, scripts, renders its 246×228 alpha-shaped layout, button input routed |
| **Winamp Modern** | compatibility expansion | **renders**: window chrome, menubar, display (timer, song ticker, bitrate/sample rate, spectrum), transport, sliders. Normal (354×280) and shade (354×25) switch through script dispatch; resize clamps; theme switching restores. Client area is built at runtime from the frame's `content=` param |
| **cPro-Bento** + ClassicPro engine | north-star | full 40-file include graph expands, graph builds, scripts bind and run, topology yields exactly one SUI window; **renders** its frame, titlebar, menu bar, display, transport, sliders, and — since the `Wasabi:Frame` splitter builds them — the SUI's tab strip, playlist pane and album-art area. Since Phase 13 the Media Library tab hosts the **real library browser** and the playlist pane draws the live queue; all three surfaces resolve inside the skin with no classic window |

None of these ship with NullPlayer. All fixture-based tests are opt-in behind `WINAMP_MODERN_WAL` /
`WINAMP_MODERN_ENGINE`; everything committed is synthetic and self-authored.

## Archive and filesystem

**Supported**

- `.wal` (ZIP) with `skin.xml` at the archive root, or under exactly one wrapper directory
- Case-insensitive lookup with original spelling retained for diagnostics
- Windows path separators; `.` and `..` normalization; `@WINAMPPATH@`, `@SKINPATH@`,
  `@COLORTHEMESPATH@`, `@DEFAULTSKINPATH@`
- `<include>` / `<elementinclude>` expansion, including a `*` glob in the **final** path component
  (sorted, deterministic)
- Cross-mount climbs into the ClassicPro engine mount

**Rejected** (typed diagnostic, never a crash)

- Path traversal, absolute paths, drive letters, symlinks, split/deep roots
- Case-colliding resources, corrupt ZIPs, archives exceeding any limit below
- Include cycles, missing include targets, a path escaping `/`
- A glob anywhere but the final component

## Wasabi XML / XUI

**Supported**

- Multiple document roots and raw ampersands (real skins contain both) — but tags must balance
- `groupdef` with `inherit_group` inheritance; `xuitag` custom tag registration
- Group template expansion during object creation
- Containers, layouts, layers, sprite regions, buttons/toggles with state images, sliders (horizontal
  and vertical), text, `clipchildren` parent clipping
- Bitmap fonts and TTF fonts (Core Text, not installed globally), colors, gamma groups. A
  `<bitmapfont file=…>` may name either a declared `<bitmap>` (Winamp Modern's form) or a path inside
  the archive (MMD3's form); both resolve, and the glyph sheet carries the font's own `gammagroup`
- `<text>` content: a script's `setAlternateText` overrides while set (`setText` clears it), then the
  `display=` binding (`time`, `songname` → "Artist - Title", `songinfo` → the stream-info line a
  `songinfo.maki` tokenises), then `text`/`default`, then the XML `alternatetext` as the
  nothing-to-show placeholder. `getText()` answers with the same resolved string
- `<vis mode>`: `1` = oscilloscope, `2` = spectrum analyzer, `0`/`3` = off (a skin uses "off" when it
  fills the box with its own animated layer); an undeclared mode is the analyzer. `setMode` switches it
- Hit testing follows Wasabi's region rule: a `group`/`layout` claims a point only where it paints a
  `background` — a bare container declared over the whole window does not swallow clicks meant for
  what is beneath it — and `animatedlayer` takes clicks like `layer` (MMD3's rotary knobs)
- Colour themes: a `<gammagroup value="r,g,b">` is a per-channel **multiplier**, `(4096 + v) / 4096`
  (0 = unchanged, +4096 = doubled, −4096 = zeroed), applied to bitmaps and to `<color>` resources;
  `gray` is a mode (any non-zero desaturates). The default theme is the **first gammaset in the
  document**, and the theme list keeps document order. A `gammagroup` id is scoped to its gammaset,
  not to the global resource namespace.
- An object whose frame is **entirely outside its parent** is culled with its subtree — skins park
  objects off-layout to hide them, and their art must not leak into the window
- Animated, N-state, ticker, album-art, and visualization elements
- Layout/shade switching, resize constraints, alpha-shaped window regions
- Namespaced per-skin configuration persistence
- Aliases and meta-commands
- `<Wasabi:Frame>` / `<frame>` splitters: the frame instantiates the groups named by
  `left`/`right` (vertical divider) or `top`/`bottom` (horizontal) and lays them out either side of
  an 8px divider placed `width`/`height` pixels from the `from` edge. On a frame,
  `getPosition`/`setPosition` are that offset. The divider is **draggable**: its grab strip takes the
  resize cursor and a drag rewrites `position`, bounded by `minwidth`/`maxwidth` (which skins spell
  that way for both orientations, and which are measured from the far edge when negative —
  ClassicPro's `maxwidth="-224"` means "always leave 224px for the other pane")
- Auto-sizing from text: a group with `autowidthsource="<id>"` takes the width of the descendant it
  names, and a `<text>` with no `w` takes its own content's width. `getAutoWidth()` measures with the
  object's real font (bitmap-font pitch or Core Text) plus `leftpadding`/`rightpadding`, so a skin
  that sizes its own boxes from that number gets boxes that fit
- `windowholder hold="guid:…"` component embedding and `componentbucket` discovery
- The curated predefined `wasabi.*` standard-library base groups (`registerWasabiStandardLibrary`),
  including a clean-room text-only `Wasabi:TitleBar` that draws the window's own name

**Not supported / degraded**

- **`wasabi.*` shells are structure-free, so a widget that has no body of its own draws nothing.**
  What is missing is the standard library's *structure*, not the pixels: the skins ship the standard
  artwork themselves under the conventional ids (mmd3 declares 174 `wasabi.*` bitmaps, Winamp Modern
  114, CornerAmp 22), but the groupdef bodies that compose them live inside Winamp. Measured across
  the four reference skins the live footprint is small — cPro-Bento references no `wasabi.*` group at
  all (the ClassicPro engine supplies real definitions) and Winamp Modern declares its own; what falls
  to a shell is `wasabi.panel` (CornerAmp ×4, mmd3 ×1 — all inside `modal`/`static` frames, which
  synthesis never selects), `wasabi.objectframe.group` (mmd3 ×1), and `wasabi.titlebar`. Unresolved
  conventional *tags* — `<Wasabi:Button>` (CornerAmp, mmd3 colour-theme dialogs) and `<Wasabi:TabSheet>`
  (mmd3's winshade sidecar) — become inert nodes the same way.
- A base group outside the curated set warns and is dropped.
- A missing **optional** bitmap or cursor is a warning, not an error (Winamp-compatible).
- `file="$solid"` / `file="$gradient"` predefined bitmaps are recognized but not resolved as files.
- `embed_xui` is retained as metadata only — it is **not** an inheritance edge.
- A splitter's `jump` (snap-to-detent) is parsed but not honoured — a drag is continuous.
- `<vis mode="1">` (oscilloscope) is drawn from the same band levels as the analyzer, mirrored about
  the centre line: the host publishes a spectrum, not raw PCM, so it is the shape of the signal rather
  than the waveform itself. It is distinguishable from the analyzer, not faithful to Winamp's scope.
- **A `xuitag` instance's own script may never initialize, leaving its controls inert.** Measured on
  cPro-Bento's tab strip: `WINAMP_MODERN_RENDER_XUI` reports `Cpro:Tabs … scripts=["CproTabs.maki"]
  onsetxuiparam=false onscriptloaded=false`, so the script never looks up its five
  `cpro.tab.button` toggle buttons and never hooks them. The strip builds and hit-tests correctly
  (`WINAMP_MODERN_RENDER_CLICK=main/normal@175,115` → `hits togglebutton#cpro.tab.button`), but the
  button has `bindings=false` and every mouse event dispatches to 0 handlers — the tab names have
  never switched tabs. Same family as Phase 9.6's `System.newGroup`/`onSetXuiParam` delivery, which
  does not cover this case. The embedded library is reached through the surface coordinator instead,
  which is why Windows → Library Browser works where the tab does not.
- Auxiliary container windows render and take input but do **not** drive per-container MAKI layout
  switching; the main window owns the scripted scene. (cPro-Bento is single-window, so this is
  invisible there.)
- Pixel-exact fidelity against real Winamp has never been verified for any target.

Duplicate resource/group/XUI definitions **replace** earlier ones and warn — this is intentional
override behavior, not an error.

## MAKI

**Supported opcodes** — stack push/pop/assignment; equality and ordered comparison; conditional and
unconditional branches; host/global method calls; local call/return; move; pre/post
increment/decrement; arithmetic and modulo; bitwise and logical operations; allocation; delete.

**Supported API** — the authoritative list is `signature(for:)` in `WinampModernScriptRuntime.swift`.
By area:

- **Playback host**: playback state, current time, duration, volume, shuffle/repeat, title/info,
  spectrum levels, transport (play/pause/stop/prev/next), seek, file-open
- **GUI mutation**: `setxmlparam`, `resize`, `show`, `hide` (each invalidates the view)
- **Lookups**: containers, layouts, object descendants, script group, script parameter/token access
- **System**: viewport/application coordinates, runtime/skin identity, integer/string conversion,
  date helpers, per-skin `getPublicInt`/`setPublicInt`
- **Timers**: bounded scheduling (see limits)
- **Animated layers**: `getLength`, `gotoFrame`, `getCurFrame`, `setStartFrame`, `setEndFrame`,
  `setSpeed`, `play`/`stop`, `isPlaying` — the play head is a pure function of the time since `play()`
  (`WasabiAnimation`), so the renderer and the script always agree on the current frame
- **`Map`**: `loadMap`, `inRegion`, `getValue`, `getWidth`, `getHeight`, `getARGBValue(x, y, channel)`
  — a bitmap the script samples. `new Map` and `new Timer` are indistinguishable at construction
  (class GUIDs are not in the archive), so a dynamic object becomes a map on its first `loadMap`.
  `loadMap` takes **either a declared bitmap id or a VFS path**; ClassicPro's "is the plugin
  installed?" probe is the path form (`…/engine/image/installed.png`, width 1). The `getARGBValue`
  channel index is **BGRA** — pinned by `player.maki` building `colorbandpeak="r,g,b"` from channels
  2, 1, 0
- **`XmlDoc`**: `load`, `exists` — **inert**. The callback-driven parser is not implemented, so a
  document always reports that it does not exist and every caller takes its own skip path. Cost: a
  skin's optional `ClassicPro.xml` extras (songticker antialiasing, custom beat-vis names) are ignored
- **Object validity**: `isInvalid()` is true for a null receiver *and* for an object whose declared
  bitmap never resolved. ClassicPro probes for optional artwork by declaring a hidden layer over it
  and asking that layer whether it is invalid
- **Cursor + EQ**: `getMousePosX`/`getMousePosY` (in **skin pixels**, the same units as a mouse event's
  x/y), `getEQ`, `getEqBand`/`setEqBand` (MAKI's −127…127 scale ↔ the engine's ±12 dB), `atan`
- **`List`**: `addItem`, `enumItem`, `getNumItems`, `removeItem`, `removeAll`, `findItem` (objects
  match by identity, other values by string form); bounded at 4096 items.
  **`BitList`**: `setSize`, `getSize`, `setItem`, `getItem` — same backing store, holding flags
- **`WinampConfig`**: `getGroup(guid)` → `getInt`/`getBool`/`getString`, resolved against the skin's
  own namespaced configuration, never real Winamp settings. Unset reads 0/""/false, which is also the
  right answer for the one item ClassicPro asks about (`"frequencies"` = 0, the classic EQ frequencies
  NullPlayer's `EQConfiguration.classic10` uses). The setters are deliberately absent
- **Children**: `getNumChildren`, `enumChildren(i)`
- **`System.getCurrentTrackRating()`** — always 0 (unrated). NullPlayer's playback `Track` carries no
  user rating (the library's rating is in `MediaLibrary`, which is not on the host adapter), so the
  ClassicPro ratings widget draws no stars rather than aborting its script
- **ClassicPro shell**: `exploreFile`, `openFile`, `findFiles` (policy below)

**Script events callable as methods.** A script may invoke one of its own handlers directly to reuse
it (`slidercb.onSetPosition(slidercb.getPosition())`). Only events with a known arity are callable —
see `dispatchableEventArity` — because the stack cannot be unwound without one. This works for
**system** events too (`System.onEqFreqChanged(freqmode)` in ClassicPro's `eq.m`).

**Robustness rules** (each earned from a real skin, and each keeping one skin defect from taking down
a whole script):

- A method call on a **null object** is a no-op returning null, as in Winamp — not an abort. MMD3
  checks menu commands from a function that also runs before the menu exists.
- `setPosition` fires `onSetPosition` **only on a change**. Skins pair two sliders that write each
  other's position from that handler.
- Event dispatch is **re-entrancy guarded** per (object, event): the interpreter's own call-depth
  budget cannot see native recursion through dispatch, and an unguarded pair overflowed the stack.

**Not supported**

- Any method not in `signature(for:)` — fails closed with `.unsupportedScriptCapability` and is
  recorded in the compatibility report's `unsupportedMethods` bucket
- Unsupported opcodes fail closed; they never become silent no-ops

**Failure granularity.** A method miss aborts *that script event only*; the remaining scripts still
run and the skin loads degraded, with every failure collected into the compatibility report. It
cannot degrade any finer than the event: the bytecode does not encode a call's argument count, so
without a signature the interpreter cannot unwind the stack and must abandon the event rather than
guess. This is why each needed method has to be implemented rather than stubbed.

**Measured demand — cPro-Bento startup.** As of 2026-08-16 (Phase 12): **none.** The target reports
zero error-severity findings and zero unsupported methods, at compatibility level `degraded`.

Phase 12 emptied the queue a second time, after `Wasabi:Frame` let the SUI's own scripts run for the
first time: `additem`, `getnumchildren`, `getgroup`, `getcurrenttrackrating`, `oneqfreqchanged` (a
system event called as a method), then `setsize` — plus a *parse* failure, which is worse than a
method miss because it fails the whole skin: opcode 104's immediate is a type offset plus an
"is object" flag, so an object-typed `Member` is `0x0100 | classIndex`, not a value kind.

Getting there took three waves, because each fix let a script run further and reach the next miss —
so re-measure after every change rather than working from a static list (193 methods are *referenced*
across the engine but never reached at startup):

1. `getargbvalue`, `getwidth`/`getheight` (on `Map`), `getitembyguid`, `getposition`, `getscale`,
   `isinvalid`, `setredraw`, `setregionfrommap`, `getdateyear`
2. `delete` (opcode 97) underflowing the value stack — see the note below — then `load`/`exists`
   (`XmlDoc`), `getfilesize`, `getlanguageid`
3. `switchskin`, `getpublicstring`/`setpublicstring`, `getcurcfgval`, `onaction` as a method

> **`delete` is an expression.** The compiler emits `push; delete; pop`, so the delete opcode must
> leave its operand for that discard pop. Consuming it underflowed the stack and killed every script
> that deletes anything — which stayed invisible for eight phases because those scripts aborted
> earlier on a missing method.

**Measured demand — Winamp Modern startup.** Three methods as of Phase 12 (`getgroup` and
`getnumchildren` were implemented for cPro), none of which block the window from rendering:
`clienttoscreenx` (×10), `snapadjust`, `debugstring`.

> A method listed in `signature(for:)` but stubbed in dispatch does **not** appear in either list — it
> looks implemented. `newgroup` hid there and cost the entire Winamp Modern window body. Omit the
> signature instead of stubbing.
- `messagebox` — denied (no arbitrary modal host UI)
- `navigateurl` — sandboxed no-op
- `newgroup` — **implemented**: expands a registered groupdef as a child of the calling script's group, and starts the scripts the new subtree declares (bounded by the load-time object budget and `maximumRuntimePrograms`)
- Popup menus use an inert command model with an injected presenter
- `getPublicInt`/`setPublicInt` are per-skin namespaced, not truly app-global

## Hosted components

| Component | State |
|-----------|-------|
| Playlist | Embedded and bound to `AudioEngine` — rows, now-playing marker, selection, bounded scroll, click/double-click/wheel, Delete/Forward-Delete removal while focused, `PE_Info` status line. Drawn in the skin's palette and list font |
| EQ | Embedded classic 10-band + preamp, enabled/auto, presets, `<eqvis>`, bound to `AudioEngine`; gains persist across mode switches |
| Library | **The real browser, embedded** in the skin's holder — servers, tabs, search, CoverFlow, history, linking. Falls back to a window of its own only when the skin offers no home for it; either way it is drawn in the skin's palette, not with classic `.wsz` artwork |
| Visualization / video | Holder discovered and framed; content per the component host |

A holder is any of `<windowholder hold=…>`, `<componentbucket>`, or `<component param=…>` — the last
is the form separate-window skins use for their real content.

Playlist and EQ are **engine-drawn inside the skin-provided frame**: correct geometry, behavior, and
colours (via `WasabiPalette`, resolved through the skin's own colour resources and active colour
theme), but not painted with the skin's own list bitmaps, scrollbars, or EQ thumbs.

### Where a surface lives

Every request for the playlist, equalizer, or library — a menu item, a skin button's
`TOGGLE guid:…`, a restored session — resolves through one catalog, in one order:

1. **Embedded** — the skin already shows it inside a window it owns. Revealing it dispatches
   `System.onGetCancelComponent(guid, true)`, Wasabi's own "this component wants to be visible"
   contract, *and* applies `windowholder autoopen="1"` by un-hiding the ancestors between that holder
   and its layout. (ClassicPro switches tabs from that event but only `if (active_tab != 0)`, and at
   startup its `active_tab` is already 0 — so the holder half of the contract is what actually opens
   the Media Library tab.) An embedded surface owns no `NSWindow` and never enters docking,
   compact-mode snapshots, or frame persistence. **An embedded library is revealed once at launch**
   (`revealEmbeddedLibraryAtStartup`, right after the catalog is reconciled) — cPro-Bento opens on its
   Media Library tab, and without this that tab is an empty pane until the user picks Windows →
   Library Browser. Only for `isEmbedded(.library)`, so a skin with its own library window opens
   nothing at launch.
2. **Declared container** — the skin ships a window for it (`<container id="Pledit" component="guid:…">`).
3. **Synthesized container** — the skin ships none, so one is built *before initialization* from the
   skin's own `<Wasabi:StandardFrame:…>` around a `<component>` of that kind. Only in the
   separate-window arrangement, and only when a frame qualifies: a skin-declared groupdef with a
   frame script that can instantiate its `content=` group. The built-in `wasabi.*` shells do not
   qualify — synthesis reads the *document's* groupdefs, so a seeded shell is never a candidate.
4. **Classic fallback** — NullPlayer's own window, with a diagnostic naming the prerequisite that
   failed. "Classic" is the *controller*, not the look: since Phase 16 these windows are drawn flat
   from the loaded skin's `WasabiPalette` (via `WinampModernSurfaceStyle`) rather than with `.wsz`
   sprites, the 5×6 bitmap font, and the selected classic skin's list colours. Geometry is unchanged
   — same title-bar height, borders, and button boxes — so only the pixels differ.

Measured, for the four reference skins:

| Skin | Playlist | Equalizer | Library |
|---|---|---|---|
| cPro-Bento | embedded | embedded (drawer) | embedded (tab) |
| mmd3 | declared `Pledit` | embedded (main-window drawer) | synthesized |
| CornerAmp_Redux | declared `Pledit` | declared `eq` | synthesized |
| Winamp Modern | declared `Pledit` | embedded | declared `MLibrary` |

Winamp defines **no equalizer component GUID** — no measured skin contains one — so an equalizer is
recognized by its controls (`EQ_BAND`, `EQ_PREAMP`, `<eqvis>`), and a synthesized one uses `guid:eq`.
`EQ_TOGGLE`/`EQ_AUTO` deliberately do not count as evidence: a button that opens the equalizer is not
an equalizer.

### Not implemented in the playlist

The skin-specific ADD / REM / SEL / MISC button menus are **inert**. They open Winamp's own nested
popup menus over playlist-manager operations NullPlayer has no equivalent for; the buttons draw and
respond to hover, and clicking one does nothing.

## ClassicPro engine policy

- **User-supplied only.** Nothing is bundled and no permission is requested. The user provides the
  ClassicPro installer; NullPlayer never downloads it.
- **Internal extraction.** No external tools, no temp files, **no code execution** — the `.exe` is
  parsed by NullPlayer's own NSIS-2 reader and LZMA1 decoder.
- **Narrow format support.** NSIS-2 with a solid LZMA stream only (what ClassicPro ships). Non-solid,
  zlib/bzip2, NSIS-3, and non-NSIS `.exe` files fail with an actionable diagnostic. `.zip` (including
  a nested installer) and an already-extracted folder are also accepted.
- **Validated and hashed.** Structure validation requires the `one` engine family; content is
  SHA-256 hashed. One private copy is stored and mounted read-only.
- **Native surface is three shell methods**, none on the render path:
  - `exploreFile` — reveal an **existing** file in Finder
  - `openFile` — open an **existing** file with the default app
  - `findFiles` — bounded no-op returning −1, so callers early-return

  All gate on a real, existing, non-URL, non-`~` path. Skins cannot navigate URLs, launch
  executables, or reach arbitrary paths.
- **Version gate.** `WinampVersionCheck` sees a build number past the `2405` gate, so `load.xml`
  *branches* past its update warning rather than being hard-blocked. Install/update/download prompts
  are inert.

## Limits

All enforced; exceeding one produces a typed `WalDiagnostic`, never a crash or a hang.

| Area | Limit |
|------|-------|
| Archive entries | 4,096 |
| Entry uncompressed size | 32 MB |
| Archive total uncompressed | 128 MB |
| Compression ratio | 200:1 |
| XML nesting depth | 256 |
| Include depth | 32 |
| Expanded XML nodes | 100,000 |
| Group inheritance depth | 64 |
| Image dimensions | 8,192 × 8,192, and 32 Mpx |
| Font point size | 512 |
| Script (`.maki`) size | 4 MB |
| MAKI table entries | 100,000 |
| Bitmap cache | 256 MB (LRU) |
| MAKI instructions per event | 5,000,000 |
| MAKI call depth | 256 |
| MAKI allocation per event | 64 MB |
| MAKI stack values | 1,000,000 |
| Active timers | 256 |
| Timer period | ≥ 8 ms, ≤ 120 Hz |

## Verification status

**Verified headlessly** (synthetic + opt-in fixtures): archive/VFS/XML contracts and every rejection
path; initialization pass order and graph snapshots; geometry/anchor rules; MAKI parse/execute and all
budget aborts; fuzzing of the archive, XML, group-expansion, MAKI-parser, and VM paths (bounded
outcome, no trap or hang); stress (timer caps, 50× rapid load/teardown, malformed images, 2,000
groupdefs); teardown completeness; live four-mode switching.

**Verified by rendering** (2026-08-15/16, `WinampModernRenderDumpTests` against user-supplied
archives, plus a manual GUI pass): Winamp Modern and cPro-Bento both render their frames and controls;
sprite crop origin, upright orientation, layer stretching, tiling, and `fitparent` are pinned per
pixel by `WinampModernRenderPixelTests`. Since Phase 11 cPro-Bento also renders its beat
visualization, spectrum and stream-info readouts, with all engine scripts completing. Since Phase 17
MMD3 draws its bitmap-font text (song title, time, KBPS, KHZ), resolves its drawer tabs and rotary
knobs to themselves under `WINAMP_MODERN_RENDER_CLICK`/`CLICKABLE`, and leaves its own animated
display unobstructed; a 2.5 s timer-driven run confirms the ticker settling on the track title and the
KBPS/KHZ fields filling from the skin's own `songinfo.maki`.

**Open crash report (2026-08-16, not reproduced).** A live cPro-Bento run aborted in `drawText` with
`-[__NSPlaceholderDictionary initWithObjects:forKeys:count:]: attempt to insert nil object` from
`NSString.size(withAttributes:)`. The text boundary is now hardened (optional-typed font, clamped
point size, PostScript-name check, optional-typed colour), but neither the dump harness nor
`WinampModernCrashRepro` — which fires every standard event at all 290 objects with a redraw after
each — triggers it, with or without the hardening reverted. **Treat the fix as plausible, not
proven**, and see `docs/winamp-modern/phase-11-handoff.md` §5 for what is still untried.

**Not verified**: casting continuity in this mode, Compact Mode, UI Size, window docking, and
pixel-exact fidelity against real Winamp. Playback and casting are `AudioEngine`-owned and
mode-independent, and are proven for the other three families, but have not been driven from a `.wal`
skin's own controls. See [manual-qa-checklist.md](manual-qa-checklist.md).

**Known rendering gaps**: the lower third of Winamp Modern's main window (`player.main` and
`player.normal.drawer` both resolve to y≈17 and overlap, leaving the config/EQ drawer area blank), and
any widget whose visuals come entirely from a body-less `wasabi.*` standard-library shell — measured,
that is `wasabi.panel` and `wasabi.objectframe.group` only, and none of it on cPro-Bento or Winamp
Modern.

> **cPro-Bento's centre is no longer empty.** Phase 12 implemented the `Wasabi:Frame` splitter that
> builds the SUI body, and Phase 13 filled the surfaces inside it: the playlist pane draws the live
> queue, and the Media Library tab hosts the real browser (verified live against a Plex server).

**Window sizing** (Phase 13.0). A `.wal` window is sized by its own layout, and a frame restored from
saved state is now honoured for its *position* but clamped to that layout's `minimum_*`/`maximum_*`
with the saved top-left preserved — restoring verbatim is what brought a 500×500 cPro-Bento window
back as 376×182. Separately, an object whose parent is smaller than the object's own margins resolves
to a **negative** box; those are dropped with their subtree rather than flipped across their origin,
which is what made an undersized window scramble instead of cramp. Zero-sized objects are still
walked — skins park real content in 0×0 groups that size themselves from their children.

**The protective minimum** (Phase 15). A skin's declared `minimum_w`/`minimum_h` is written for
Winamp, where *every* group clips its children; we clip only on `clipchildren="1"`, so below a
certain size a child that no longer fits paints over its siblings instead of being cut off —
cPro-Bento at 376×182, comfortably above its declared 317×168, overlaps its tab strip
(`cpro.tab`) onto the transport. Rather than change clipping globally (which would change what every
skin draws), `WasabiSceneRenderer.layoutMinimumSize` raises the floor to the smallest size at which
the scene still lays out the way its author drew it, and every window, script `resize`, and restored
frame is clamped to it.

The probe calibrates against the layout's **own default size**: at the size its author ships, the
scene is by definition correct, so overhang already present there is deliberate (a slider centres its
thumb on its track) and only failures that appear *after* shrinking count. Two failure kinds are
tracked separately — an object escaping the box it resolved against, and an object disappearing from
the scene entirely (`append` culls a node that lands wholly outside its parent) — so an object
allowed to overhang is still never allowed to vanish. ~20 scene builds per layout, binary-searched
per axis and cached; the result never exceeds the layout's default size. Measured floors: cPro-Bento
`main/normal` 317×168 → **477×203**, mmd3 `Pledit` 275×116 → 310×116, `ctsbig` → 310×133, Winamp
Modern unchanged everywhere (its declared minima already dominate).

**Not fuzzed**: `NSISArchive` and `LZMA1Decoder`. They are validated byte-for-byte against the real
installer (309/309 engine files match a reference oracle), but a bounded fuzz over them remains
reasonable future hardening.
