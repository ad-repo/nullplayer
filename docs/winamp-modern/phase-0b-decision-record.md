# Winamp Modern (`.wal`) — Phase 0B Decision Record

**Phase:** 0B — Feasibility harness and compatibility inventory.
**Date:** 2026-08-15.
**Inputs:** Phase 0A decision record + `~/.claude/plans/i-want-to-support-frolicking-rabbit.md` (locked
decisions) + `~/.claude/plans/winamp-modern-phase-0b-handoff.md`.
**Verdict:** **GO for Phase 1.** Feasibility of the cPro-Bento north-star target is materially
higher than Phase 0A assumed — the native `ClassicPro.w5s` is **not** on the render/behavior critical path.

---

## 0. How to reproduce this inventory

Everything below is produced by a throwaway, read-only Swift harness committed at
`tools/winamp-inventory/` (a **separate SPM package** — it never builds with the app). Re-run:

```sh
# 1. Re-extract the engine (NSIS installer) — ephemeral, not committed:
7zz x -y -o<dest> tmp/ClassicPro_2.01.exe
# 2. Build + run the inventory harness:
cd tools/winamp-inventory && swift build
.build/debug/winamp-inventory \
  --wal ../../tmp/2222-cPro__Bento.wal \
  --engine <dest>/Plugins/ClassicPro/engine \
  --out ../../docs/winamp-modern/phase-0b-artifacts
```

Latest snapshot: `docs/winamp-modern/phase-0b-artifacts/inventory-2222-cPro__Bento.md`.

The harness demonstrates the Phase-2 building blocks in miniature: a **bounded ZIP reader** (entry /
per-entry / total-size caps, traversal + symlink rejection), a **logical VFS** (`@VAR@` resolution,
Windows-backslash normalization, `.`/`..` canonicalization, case-insensitive lookup, glob includes,
include-cycle detection), a **lenient XML tag inventory**, and a **MAKI header/symbol inventory**.

---

## 1. THE feasibility gate — native `ClassicPro.w5s` dependency (resolved)

Phase 0A flagged the opaque native `ClassicPro.w5s` (129 KB x86 Windows DLL, no source) as *"the biggest
cPro-Bento feasibility driver."* **Measured result: it is a minor, replaceable dependency.**

- **The custom XUI classes are pure-XML composites, not native objects.** All 24 `xuitag=`
  registrations used by the engine (`ClassicPro:SUI`, `Centro:SUI`, `PlaylistPro`, `Cpro:Tabs`,
  `SC:VScrollBar`, `SC:ProgressGrid`, `ModernSongticker`, …) are `<groupdef>`s that expand to **standard
  Wasabi primitives** (`group`, `layer`, `button`, `togglebutton`, `slider`, `list`, `grid`, `text`,
  `rect`, `edit`, `windowholder`, `Wasabi:Frame`, `Wasabi:AlbumArt`, …) plus an attached `.maki` script.
  None bottoms out in a native visual class.
- **What `.w5s` actually is:** its RTTI symbols (`ScriptObjectService`, `waServiceFactory`,
  `svc_scriptObject`, `SClassicProFile`, `SClassicProFlex`) show it registers **MAKI script-object
  *services*** — a native API callable *from* scripts, not renderable objects.
- **The entire native surface invoked by the engine's MAKI is 3 filesystem-shell methods** on one static
  service, `ClassicProFile`:

  | Native method | Call sites | NullPlayer replacement |
  |---|--:|---|
  | `ClassicProFile.exploreFile(path)` | 9 | `NSWorkspace.activateFileViewerSelecting` (reveal in Finder) |
  | `ClassicProFile.findFiles(…)` | 6 | Host file-search adapter, or bounded no-op |
  | `ClassicProFile.openFile(path)` | 2 | `NSWorkspace.open` (open with default app), gated by URL/open policy |

  17 call sites, 3 methods, all OS-shell helpers. The second native class, `ClassicProFlex`, is
  **cpro2-only and never called** from any `.m`/`.maki` in the engine-one path cPro-Bento pins.
- **Every other "Capitalized" call** in the MAKI source (`PlEdit`, `Config`, `WinampConfig`, `ColorMgr`,
  `AlbumArt`, `XUIGroup`, `CproTabs`, …) is either a standard Wasabi/Winamp-SDK class we build for every
  target anyway, or a composite whose `.m` source we have.

**Conclusion:** cPro-Bento does not require reimplementing an opaque native DLL. It requires the **base
Wasabi/XML + MAKI runtime** (the CornerAmp → Winamp Modern ladder) plus three trivial shell adapters.

---

## 2. Measured engine + skin anatomy (from the harness)

**Engine (`Plugins/ClassicPro/engine`, 2.01):** 74 `.xml`, 90 `.maki`, **98 `.m` MAKI source files**
(readable source ships for every script), 3 `.mi`. Native: `ClassicPro.w5s` (129 KB, opaque),
`ClassicPro.wbm` (38 B marker).

**cPro-Bento archive (`tmp/2222-cPro__Bento.wal`):** 47 entries, 249 KB uncompressed (40 png, 5 xml, 1
txt, 1 maki) — well inside all caps. Its own content is only bitmaps + color themes + "overlay"
groupdefs; **100% of structure comes from the engine** via one cross-mount include
(`@COLORTHEMESPATH@\..\..\Plugins\classicPro\engine\load.xml`).

**Expanded include graph (skin + engine):** 40 XML files; resolving required glob includes
(`widgets\load\*.xml`), Windows backslashes, and the cross-mount `@COLORTHEMESPATH@` climb — all handled.

| Inventory | Count |
|---|--:|
| groupdefs | 129 |
| — of which `xuitag=` registrations | 24 |
| containers (window definitions) | 9 |
| layouts | 11 |
| windowholders / component buckets | 10 |
| scripts attached | 47 |
| bitmaps / fonts / colors / gamma resources | 630 / 2 / 38 / 300 |

**MAKI corpus:** 91 `.maki` parsed, header version uniform (`0x0403`), **59 distinct imported class
GUIDs**, **635 distinct API method names**. The most-referenced methods are all standard Wasabi/`std.mi`
(`getPrivateInt`, `getRuntimeVersion`, `findObject`, `setXmlParam`, `getContainer`, `getLayout`,
`onTimer`, `onResize`, `show`/`hide`, `getObject`, …) — confirming the runtime surface is standard
Wasabi, not ClassicPro-proprietary.

---

## 3. cPro-Bento container/component topology (drives Phase 5)

**cPro-Bento is a single-window SUI.** The only real window is `container id="main"` (component GUID
`{45F3F7C1-…}` = Winamp main player), which includes `player-normal.xml` (the `ClassicPro:SUI` +
normal layout) and `player-shade.xml` (shade layout).

The playlist, media library, video, and visualization surfaces are **embedded inside the SUI**, not shown
as separate windows. `one/xml/window-overrides.xml` deliberately redefines the standard Winamp
containers as invisible 1×1 stubs — its own comment: *"This file is needed to prohibit the SUI Components
show in a stand alone window."* The surfaces are hosted via `windowholder hold="guid:…"` keyed by the
standard component GUIDs:

| Surface | Hosted via | GUID |
|---|---|---|
| Playlist | `PlaylistPro` → windowholder `PlaylistPro.wdh` | `{45f3f7c1-a6f3-4ee6-a15e-125e92fc3f8d}` |
| Media Library | `centro.windowholder.library` | `{6B0EDF80-C9A5-11D3-9F26-00C04F39FFC6}` |
| Visualization | `centro.windowholder.visualization` | `{0000000A-000C-0010-FF7B-01014263450C}` |
| Video | `centro.windowholder.video` | `{F0816D7B-FFFC-4343-80F2-E8199AA15CC3}` |
| Plugins (any) | `centro.windowholder.other` | `@all@` |
| Widgets | component buckets `widget.loader{,.mini}` | `centro.widgets.{main,mini,drawer}` |
| EQ | drawer group (skin overlay `cpro.drawer.eq.*`, actions `EQ_TOGGLE`/`EQ_AUTO`) | — (embedded, not a container) |

**Phase-5 implication (confirms locked decision #1):** the mandatory model is **component hosting**
(map each `windowholder`/`componentbucket` GUID to a NullPlayer host adapter — playlist, library, vis,
EQ) embedded in tabs/drawers of one window. The "four independent native windows" model does **not**
apply to cPro-Bento.

---

## 4. Capability matrix

Only cPro-Bento is available locally (Phase 0A: real skins are user-supplied, never committed). CornerAmp
and Winamp Modern are **not yet inventoried** — the harness will produce their columns when the fixtures
are supplied at Phase 3/4. Those cells below are reference-derived (Webamp `packages/webamp-modern`) and
marked ~.

| Capability | CornerAmp_Redux | Winamp Modern | cPro-Bento *(measured)* |
|---|---|---|---|
| Purpose in ladder | bootstrap slice | breadth target | **north-star** |
| Archive shape | ~single container | ~single container | container + **external engine** (measured) |
| Top-level windows | ~few containers | ~standard set | **1** (SUI); others collapsed |
| Custom XUI = composites+MAKI | ~yes | ~yes | **yes** (24 regs, all composite) |
| Standard Wasabi primitives | ~small set | ~full set | **full set** |
| Component hosting (windowholder/bucket) | ~minimal | ~some | **central** (10 holders) |
| MAKI scripting | ~light | ~moderate | **heavy** (91 scripts, 635 methods) |
| Native plugin dependency | none | none | **`.w5s` = 3 shell methods only** |
| Fonts / gamma / color themes | ~basic | bitmap+TTF, gamma sets | 2 fonts, 38 colors, **300 gamma** |
| EQ surface | n/a | classic10 window | embedded drawer (classic10 maps) |

---

## 5. Refined estimates and scope adjustments

- **The critical path is the base runtime, not ClassicPro.** Effort is dominated by Phases 2–4 (bounded
  archive/VFS, retained Wasabi graph, standard primitive rendering, MAKI parser+interpreter+`std.mi`
  surface). Phase 6 shrinks to: the NSIS/`.exe` engine importer + mounting + 3 shell adapters + the
  window-overrides/SUI wiring. The native DLL is **not** reimplemented.
- **MAKI: source-first.** `.m` source ships for all 98 scripts; a full bytecode **disassembler is a
  fallback**, not a Phase-3 blocker. The interpreter still executes compiled `.maki`, but the semantic
  reference is the `.m` source. Header format confirmed: `FG` + `u16` version `0x0403` + `u32` const `23`
  + `u32 nTypes` + `nTypes`×16-byte class GUIDs + plaintext symbol pool.
- **`std.mi` surface is measurable and finite.** 635 method names / 59 class GUIDs bound the Wasabi/SDK
  API to implement; prioritize by cross-file frequency (top-40 emitted by the harness).
- **Phase 5 is component-hosting-first** for cPro (see §3); the separate-windows path is only for skins
  that actually declare multiple visible containers (to be measured for Winamp Modern).
- **Version gate risk retained:** `load.xml` runs `WinampVersionCheck.maki` with param `2405;5.55`. A
  compat shim must report a satisfactory Winamp version; confirm branch-vs-hard-block when the
  interpreter lands (open question carried to Phase 1/3).

---

## 6. Go/No-Go

**GO for Phase 1.** The Phase 0A feasibility gate (native `.w5s` centrality) is retired: cPro-Bento's
UI is interpreted content (pure-XML composites + MAKI with full source) over the standard Wasabi runtime,
with a 3-method OS-shell native tail that maps to trivial host adapters. Nothing measured requires
reimplementing an opaque native object system. The remaining risk is the **size** of the base
Wasabi/MAKI runtime (Phases 2–4), which is now bounded by concrete inventory, not the *possibility* of an
unimplementable native surface.

**Carry-forward open questions:** (1) `WinampVersionCheck` block-vs-branch behavior; (2) CornerAmp +
Winamp Modern fixtures must be supplied to fill the capability matrix at Phase 3/4; (3) exact `std.mi`
method semantics to prioritize from the 635-method frequency list.
