# Winamp Modern (`.wal`) — State of the Work

- **Date:** 2026-08-19
- **Branch:** `feat/winamp-modern` (~69 commits ahead of `main`)
- **Phases completed:** 0A/0B, then 2–33 — **all closed.** What is still open is one ranked list:
  [open-items.md](open-items.md)
- **Audience:** anyone picking this up, reviewing it, or deciding whether it ships

This is the orientation document; `skills/winamp-modern-skin-guide/triage-playbook.md` is the process
for working the long tail beyond the measured skins (17 are installed locally; two of them —
`Itemskin.wal`, `Overdrive_2.wal` — still fail to load outright, which is the top item in
[open-items.md](open-items.md)). The durable technical reference is
`skills/winamp-modern-skin-guide/` — SKILL.md is a router over `reference/` topic files, alongside
compatibility.md, skins.md → `skins/<skin>.md`, and manual-qa-checklist.md. The per-phase records are
in `docs/winamp-modern/`; [INDEX.md](INDEX.md) lists them and resolves any pointer they make into the
skill. Where this file and a skill disagree, the skill
wins.

---

## 1. What was built

A fourth UI mode (`PlayerUIMode.winampModern`, gated by `AppFeature.winampModernMode`) that loads and
runs **real Winamp 5.x modern skins** — `.wal` archives containing Wasabi XML/XUI markup and compiled
MAKI bytecode — inside NullPlayer, on macOS, with no Winamp binary, plugin, or asset involved.

Concretely that meant writing, from scratch, in Swift:

| Layer | What it is |
|---|---|
| Archive + VFS | Bounded ZIP reader, logical mounts, `@VARS@` expansion, case-insensitive resolution |
| XML/XUI front end | Lenient parser, include/glob expansion, groupdef inheritance, XUI tags, document-order redefinition semantics |
| Object model | Retained `WasabiObjectGraph` with deterministic IDs; Wasabi top-left geometry with signed anchors |
| Renderer | Core Graphics scene renderer: sprites, nine-slice grids, bitmap + TrueType text, animated layers, region clipping, colour themes, tiling/stretching, hit testing |
| Script VM | `MAKI` bytecode parser + interpreter, ~budgeted, with a demand-driven method surface |
| Host seam | `WinampModernHost` — the only door from skin scripts to `AudioEngine`, playback state, track metadata, artwork |
| Component hosting | Playlist / EQ / library resolved as embedded, declared, synthesized, or classic-fallback surfaces |
| ClassicPro import | From-scratch LZMA1 decoder + NSIS-2 reader so a user-supplied plugin installer can be unpacked internally |

**Size** (Phase 26 snapshot; the suite is **785 tests** as of Phase 33): ~10.5k lines of engine (`Sources/NullPlayer/WinampModern/`), ~1.9k lines of window/controller
code (`Sources/NullPlayer/Windows/WinampModern/`), ~8.9k lines of tests (291 test functions across 25
files). Suite total at Phase 26: **721 tests**, all green (the counts in this paragraph are a
Phase 26 snapshot and have not been re-measured since).

---

## 2. Engine status, component by component

Legend: **Solid** = exercised by multiple real skins and pinned by tests · **Working** = real skins
depend on it, narrower evidence · **Partial** = known holes · **Absent** = deliberately not built.

### Archive, VFS, XML — **Solid**

`.wal` (ZIP) with `skin.xml` at the root or one wrapper deep. Case-insensitive lookup, Windows
separators, `.`/`..` normalization, the four `@…PATH@` variables, `<include>`/`<elementinclude>` with a
trailing-component glob, and cross-mount climbs into the ClassicPro engine. Every rejection path
(traversal, escape, cycles, corrupt ZIP, every limit) produces a typed `WalDiagnostic` — never a trap.
Fuzzed at the archive, XML, group-expansion, MAKI-parse and VM levels for bounded outcomes.

The security posture is the strongest part of the work and should stay that way: **the skin is
untrusted input.** No host filesystem access, everything bounded (24 enforced limits, from archive
entries to MAKI stack values), failures typed rather than fatal. Scripts cannot navigate URLs, launch
executables, open modal UI, reach arbitrary paths, or touch the network.

### Wasabi object model + geometry — **Solid**

Six ordered initialization passes; `inherit_group` inheritance (depth 64, cycle-detected); `embed_xui`
as metadata *plus* mouse-event forwarding; `xuitag` registration; document-order group redefinition
(the streaming-parser semantics real Winamp has, which T800 depends on); signed anchors; `fitparent`;
layouts sized from their background art; a "protective minimum" that probes for the smallest size at
which a scene still lays out the way its author drew it.

Two hard-won invariants worth not breaking: geometry is **always** Wasabi top-left inside the graph
(the Y flip happens exactly once, at the drawing boundary and once at the event boundary), and a group
clips its children only when the skin **declared** its box.

### Renderer — **Working**, and the least test-protected layer

Draws sprites, stretched and tiled layers, nine-slice `<grid>`, bitmap fonts and TrueType text (with
Winamp's pixel-height-to-point-size ratio, `forcefixed`, ticker motion), animated layers, `ProgressGrid`,
`<vis>` in the three declared modes, region clipping from map bitmaps, colour themes (`gammaset`/
`gammagroup`), per-object alpha, **callback-driven Layer FX** (the mesh warp that turns VU needles and
cassette reels), and hit testing including `rectrgn` and `move=` policy. Artwork is cached pre-scaled
to the backing store and repaints name the rects that changed — a Defix frame costs 3.5 ms at 2×.

`WinampModernRenderPixelTests` pins crop origin, orientation, tiling and `fitparent` per pixel — but
the evidence that a renderer change doesn't disturb *other* skins is still a **manual 17-skin
before/after sweep with the clock pinned**. Nothing in CI catches a third skin regressing. That is the
single biggest process gap in the subsystem.

Known rendering gaps: Winamp Modern's config/EQ drawer area (`player.main` and `player.normal.drawer`
overlap at y≈17), body-less `wasabi.*` shells (`wasabi.panel`, `wasabi.objectframe.group`), `valign`
(text always vertically centres), `<Browser>` (Defix's Explorer tab draws nothing — an embedded web
view for untrusted skin content is outside the sandbox and no one has decided to build it), and the
corners of Layer FX nothing measured has asked for — `fx_setBgFx(1)` (warping the backdrop),
`fx_onGetPixelA` (alpha) and `fx_onFrame`/`fx_setSpeed` as a host-driven clock are accepted and inert.
The warp itself works (Phase 28–29).

### MAKI VM — **Working, demand-driven by design**

The parser reads the `FG` format completely (classes, methods, typed variables/constants, bindings,
instructions). The interpreter's *method* surface is deliberately narrow: opcodes and methods were
added because a measured skin needed them, and unsupported ones **fail closed** rather than becoming
silent no-ops, so the compatibility report's `unsupportedMethods` bucket is a real measured-demand
list. A missing method aborts one script event, not the skin.

This is the layer where "it looks done" is most misleading. Three failure modes have already bitten:
a method with a `signature(for:)` entry but a stubbed dispatch case is *invisible* to the compatibility
report; an interpreter arithmetic bug (float constant decoding) survived eight phases because scripts
reach for floats rarely; and the blocking list is a **queue, not a set** — each method you add lets a
script run further and reach the next thing it needs (cPro-Bento took three rounds: 9 → 4 → 0).
Assume untested until a skin has been watched doing the thing.

Script-built UI is supported end to end: `onSetXuiParam`, `System.newGroup`, `Group.init(parent)`
reparenting, runtime script start on attachment, container-scoped `onResize`/layout callbacks, and
skin-built popup menus. Winamp Modern's own frames are hollow XML whose entire client area is built at
runtime, so none of this is optional.

### Component hosting + mode integration — **Working**

`WinampModernSurfaceCoordinator` resolves each surface as **embedded → declared container →
synthesized container → classic fallback**, and both routes to a surface (the app menu and a skin's own
`TOGGLE` button) go through it. The equalizer is deliberately **never synthesized** — both routes land
on the classic EQ window, which since Phase 16 paints from the skin's own palette rather than from
whatever `.wsz` is selected. Live four-mode switching works; `AudioEngine` is `WindowManager`-owned so
playback survives a switch. UI Size works by scaling at the drawing/input boundary only.

### ClassicPro engine import — **Working, narrow on purpose**

`.exe` (NSIS-2, solid LZMA only), `.zip`, or an extracted folder, parsed by our own reader and
decoder — no external tools, no temp files, **no code execution**. Validated, SHA-256 hashed, stored as
one private read-only mount. Validated byte-for-byte against the real installer (309/309 files match a
reference oracle). Its entire native surface is three shell methods, none on the render path.
`NSISArchive` and `LZMA1Decoder` are **not fuzzed** — reasonable future hardening.

### Per-skin state (the honest scoreboard)

**Not here.** Per-skin state is measured, and it drifts — the scoreboard that used to sit in this
section was stale within two phases (it recorded six of Defix's eight display styles as frozen for
want of Layer FX, which Phase 29 shipped). It has one home:
`skills/winamp-modern-skin-guide/skins.md` for the status table and the skin → file index, and
`skins/<skin>.md` for each measured skin's detail and traps.

---

## 3. What is *not* verified

- **Casting continuity, Compact Mode, window docking** from this mode. Playback and casting are
  `AudioEngine`-owned and proven for the other three families, but have never been driven from a
  `.wal` skin's own controls.
- **Pixel-exact fidelity against real Winamp.** The bar is "matches the skin author's own
  `screenshot.png`", not "matches Winamp".
- **One open crash report** (2026-08-16, cPro-Bento, `drawText` → `NSString.size(withAttributes:)` with
  a nil attribute). The text boundary is hardened; neither the dump harness nor `WinampModernCrashRepro`
  reproduces it with or without the hardening reverted. **Treat the fix as plausible, not proven.**
- **Defix's speaker cones.** They get their `onSetVisible` so the `getVisBand` timer starts, but
  whether they actually animate has never been seen. Auxiliary containers do not install their own
  repaint hooks — a mutation in a speaker window repaints the *main* view — which is the likeliest
  reason they would still look dead (`docs/winamp-modern/phase-29-handoff.md` §4).
- Playlist ADD/REM/SEL/MISC skin menus are inert; auxiliary `default_visible="1"` is not honoured.

**Overall maturity: experimental but genuinely functional.** Nine real third-party skins load, render,
script, and respond to input; the two most demanding ones (cPro-Bento with its plugin engine, and the
stock Winamp Modern skin whose UI is entirely script-built) are the deepest verified targets. What it
is not is a general-purpose Winamp compatibility layer — an arbitrary `.wal` off the internet will
more likely land somewhere between "loads with a degraded report" and "renders with dead controls"
than "just works".

---

## 4. Is it safe to call this reverse engineering?

**Yes — and it's the accurate word, not a risky one.** Two separate questions are hiding inside it,
though, and only the second matters.

### Is it reverse engineering, descriptively?

Yes. This is textbook interoperability reverse engineering: an undocumented container format, an
undocumented XML/XUI dialect, and an undocumented bytecode ISA, all reconstructed from **observation of
artifacts** (skin archives, their shipped `.m` MAKI sources, their own reference screenshots) plus a
permissively-licensed third-party reference implementation. `WINAMP_MODERN_RENDER_DISASM` — which
prints resolved instruction listings so an unknown method's arity can be settled by counting net
pushes — is a reverse-engineering tool by any definition, and Winamp Modern's titlebar layout was
literally recovered by reading a disassembly.

The term carries no legal implication on its own. Reverse engineering for interoperability is a
well-established, lawful activity, and the case law that matters (in the US: *Sega v. Accolade*,
*Sony v. Connectix*, and *Google v. Oracle* on interface reimplementation) is about exactly this
pattern — study an undocumented interface, then write your own implementation of it.

### Is *this particular* reverse engineering defensible?

That's decided by practice, not vocabulary, and the practices here are already the strong ones. Per
`docs/legal/winamp_modern_provenance.md` (audited 2026-08-15):

- **Nothing third-party is redistributed.** No skin, engine, font, or bitmap ships in the repo or the
  app bundle. Every committed test fixture is synthetic and self-authored; fixture-based tests are
  opt-in behind env vars pointing at files the developer supplies locally.
- **No Winamp binary or plugin is bundled, downloaded, or required.** The ClassicPro engine is
  user-supplied and never leaves the user's machine.
- **No derived code.** An identifier-level scan for Webamp traces found no matches; the architecture is
  independently shaped by our own constraints. The one LZMA SDK–flavoured constant name is
  unprotectable, and the SDK is public domain regardless.
- **No circumvention.** A `.wal` is a plain ZIP with no technical protection measure, so DMCA §1201
  never enters the picture — and §1201(f)'s interoperability exception would cover it if it did.
- **Facts vs. expression.** File layouts, opcode numbers, attribute names and GUIDs are facts about a
  format. Reimplementing them is not copying expression.

The three residual risks worth naming explicitly, none of which is about the label:

1. **Trademark, not copyright.** "Winamp" is someone else's mark. Internal identifiers and
   documentation are nominative and fine; what matters is that the *product* isn't branded as or
   presented as Winamp. Describing a feature as "loads Winamp 5.x modern skins" is descriptive use;
   naming a shipping product after it isn't. Worth a deliberate check of user-facing strings before
   this mode ships.
2. **The 2024 Winamp source release is a contamination vector, and nothing here rules it out in
   writing.** That code was published under a licence that forbids derived works and forks. Nothing in
   this subsystem suggests anyone looked at it, and the provenance audit doesn't mention it because it
   scanned for Webamp — but it should be a written project rule: **do not read, quote, or consult the
   published Winamp source (or WACUP's non-public code) for this work.** Behaviour, shipped `.m`
   scripts, skin artifacts, and MIT-licensed references only. I'd add that line to Phase 0A's
   dispositions.
3. **The Webamp comparison is unreviewed at line level.** The audit says so itself: the scan was
   identifier- and asset-level, and a reviewer wanting stronger assurance should spot-check
   `MakiBytecode.swift` and `WasabiSkinInitializer.swift` against `packages/webamp-modern` directly.
   That's a cheap, bounded task and it closes the last open provenance item. (Webamp is MIT, so even
   actual derivation would only cost an attribution row, not the work.)

**Framing to use:** *a clean-room, interoperability-motivated reimplementation of the Winamp 5.x modern
skin format* — reverse engineering in the ordinary technical sense, carrying no third-party code, no
third-party assets, and no redistribution.

I'm not a lawyer and none of this is legal advice; if this mode ships in a paid or App Store edition,
the trademark question and item 2 above are the ones worth ten minutes of a real one's time.

---

## 5. If you're picking this up next

1. Read `skills/winamp-modern-skin-guide/SKILL.md` — it is a short router: the pipeline, the security
   model, and a symptom → file table over `reference/`. Follow it to the one topic file your problem
   points at and read *that* end to end. Each paragraph in there is a bug that cost a phase.
2. Check `skins.md` → `skins/<skin>.md` before touching anything a skin report names.
3. Look at pixels, not test results: 490+ green tests once coexisted with a vertical flip and a wrong
   crop origin, because nothing ever rendered a frame.
4. Never work down a static list of unsupported methods — re-measure after every change.
5. Do the 17-skin render sweep (clock pinned) for any renderer change until that sweep is automated —
   and diff it against *itself* first: one skin (Anexa's shade layout) renders differently run-to-run
   on an unchanged build, so a raw difference is not automatically a regression.
6. **Take work from [open-items.md](open-items.md), top down.** It is the compiled, ranked backlog;
   the prose below it in this section is history and may name work that has since been done.

**Layer FX is done.** Phase 28 made every Defix display style move; Phase 29 closed the two
complaints about *how* it moved, and both were host problems rather than skin ones — a pre-scaled
artwork cache and named repaint rects took the frame from 18.3 to 3.5 ms at Retina scale, and the
level meter now measures **peak** amplitude (Winamp's VU byte) instead of RMS, played out per block
and falling to rest on silence. All of it confirmed live by the user on 2026-08-19.
See `docs/winamp-modern/phase-29-handoff.md`.

**Phase 30** split the documentation and fixed four GUI-only defects in Defix's auxiliary windows;
its handoff carries the open list and the debugging method that found them
(`docs/winamp-modern/phase-30-handoff.md`).

**The highest-value next work is now [open-items.md](open-items.md)**, which supersedes the paragraph
that used to sit here — that one was written at Phase 30, and several of its items (the Layer FX
follow-ups, the auxiliary-window repaint hooks, `getVisBand`'s scale) have since landed. Two things
from it survive in that file's ranking: **the `<vis>` analyzer's linear scale** (B13 — the third
instance of "a linear magnitude handed to artwork cut for a logarithmic sweep", after the VU meter in
Phase 29 and `getVisBand` in Phase 30) and **automating the multi-skin render sweep** (B10).

Three more remain true and are deliberately *not* in that file, because they are engine-wide or
process work rather than skin-facing compatibility: **per-object repaint rects** — `graphDidMutate` is
still a full-window repaint on any script mutation, and the graph already records which objects were
invalidated (`consumeInvalidations()`), making this the last thing on the paint path that scales with
what the skin does rather than with what changed; **closing the provenance spot-check**; and driving
the untested integration surfaces (casting, docking, Compact Mode) from a `.wal` skin, plus fuzzing
`NSISArchive`/`LZMA1Decoder`.
