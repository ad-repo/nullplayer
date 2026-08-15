# Winamp Modern (`.wal`) — Phase 0A Decision Record

**Status:** RESOLVED — decisions locked by product owner (see §5). Go for Phase 0B.
**Scope:** legal, provenance, and security gate that must clear before any production loader/renderer
work (Phase 0B onward) begins.
**Source plan:** `~/.claude/plans/i-want-to-support-frolicking-rabbit.md`.

## 0. Locked decisions (TL;DR)

- **cPro-Bento is the north-star acceptance target**, not an optional final phase. The project is only
  worth doing if it supports skins like cPro-Bento, so the external-engine VFS mount, SUI/component
  hosting, and the ClassicPro MAKI surface are **core** requirements from day one. CornerAmp_Redux and
  Winamp Modern are engineering stepping stones that de-risk the runtime first.
- **ClassicPro engine ships via user-supplied import only.** We will **not** ask for redistribution
  permission and will **not** bundle the engine. End users supply the ClassicPro engine files themselves
  (the same way they supply the skin); our runtime renders them. NullPlayer redistributes nothing
  third-party, so no permission is required and cPro-Bento still works end-to-end.
- **Extraction is fully abstracted.** The user points at the ClassicPro installer `.exe`; NullPlayer parses
  the NSIS self-extracting archive internally, pulls out `Plugins/classicPro/engine/`, and mounts it — no
  terminal, no Windows, no third-party unzip tool. The engine is imported **once** and reused for every
  cPro `.wal`. (Also accept an already-extracted `engine/` folder and optional Winamp/WACUP auto-detect.)
- **Webamp is reference-only** (MIT-attributed if any concrete code/table is derived). WACUP's public
  GitHub repos (`WACUP/Winamp-Modern-Skin`, `WACUP/Winamp-Skinning-Archive`) are a second reference and a
  cleaner-provenance source for the Winamp Modern stepping-stone fixture.
- **All real skins + the ClassicPro engine are user-supplied local fixtures**, never committed.
- **Phase 0B entry prerequisite:** the ClassicPro **"engine one" v1.15** files must be present locally
  (developer-supplied dev fixture) to inventory cPro's topology/MAKI surface and to build/test. This is
  local dev use, not redistribution. WACUP bundles a *newer* cPro (v2.03); the skin pins engine one v1.15,
  so target the version the skin expects or prove forward-compat.

---

## Addendum — engine acquired (2026-08-15)

Developer obtained the ClassicPro plugin locally (not committed; not redistributed):
- **User-doc download reference:** https://www.softpedia.com/get/Multimedia/Audio/Audio-Plugins/ClassicPro.shtml#download
- Files pulled: `tmp/ClassicPro_2.01.exe` (chosen — newer, supports both engine generations so users can run
  more skins) and `tmp/winamp_classicpro_by_skin_consortium_d19wjs8.zip` → `ClassicPro_1.00.exe` (engine-one only).
- Extracted with 7-Zip (`brew install sevenzip` → `7zz x`) into the scratchpad. **The shipping importer must
  do this NSIS extraction itself in Swift** — the user only points at the `.exe` (see Phase 2/6 in the plan).

**2.01 engine contents (measured):**
- `Plugins/ClassicPro/engine/` — XML/MAKI content. Ships **both** `engine/one/` (Bento) and `engine/two*.xml`
  variants, and both `cPro__Bento.wal` + `cPro2__Aluminum.wal` skins. `load.xml` is the entry point cPro-Bento's
  include expects.
- **MAKI source (`*.m`) ships alongside bytecode (`*.maki`)** for every script, plus readable XML and `.mi`
  includes — a major reimplementation aid.
- **Native dependency (scope driver): `System/ClassicPro.w5s`** — a 129 KB x86 Windows DLL (Winamp 5 native
  system service), plus `ClassicPro.wbm` (38 B). No source. It almost certainly exports custom Wasabi
  objects/API the engine's XML/MAKI call into; those must be **reimplemented as Swift host objects**. **The
  pivotal Phase 0B measurement is how heavily the engine depends on this `.w5s`** — it is the single biggest
  driver of cPro-Bento feasibility/effort. This is the concrete instance of the "native Winamp plugin
  dependency" caveat noted in the plan's §0A facts.

## 1. ClassicPro engine dependency (cPro-Bento)

**Finding — the required engine is external to the `.wal` and is not present locally.**

`tmp/2222-cPro__Bento.wal` (261 KB, 47 entries) contains no `<container>`/`<layout>` of its own. Its
`skin.xml` sources the actual UI from an engine that ships *outside* the archive:

```xml
<include file="@COLORTHEMESPATH@/../../Plugins/classicPro/engine/load.xml"/>
```

The archive carries only:
- `skin.xml` (2.7 KB) — skininfo, custom groupdefs, and the three `<include>`s above.
- `ClassicPro.xml` (461 B) — `<ClassicPro version="1.15" engine="one">` config stub (text settings + a
  BeatVis list: "Bars", "Llama", "Soccer Llama!"). This configures the engine; it is not the engine.
- `warning_1.15.maki` (3.2 KB) — a single compiled MAKI script (an update/warning notifier).
- 43 bitmaps + `colors.xml` / `color-presets.xml` / `custom-element-overide.xml`.

`find` across the repo and `tmp/` returns **no `load.xml`, no `Plugins/classicPro/engine/`, and no
ClassicPro engine of any kind.** cPro-Bento therefore cannot render without a separately obtained
ClassicPro engine pack.

- **Identity:** ClassicPro v1.15, "engine one", by the Skin Consortium (`classicpro@skinconsortium.com`,
  `http://cpro.skinconsortium.com`). The `.wal`'s `<skininfo>` credits "Graphics by the the original
  Winamp development team".
- **Provenance of the engine binary itself is unknown and unverified.** It is not an Anthropic/NullPlayer
  asset, not in this repo, and not covered by any existing NullPlayer license. Its redistribution terms
  are undetermined and must not be assumed permissive.

**Consequence:** cPro-Bento is a *final compatibility target*, not a bootstrap target. It is gated behind
Phase 6 and behind the redistribution decision in §5.

---

## 2. Provenance / license inventory

The repo already has a notices pipeline we will extend rather than reinvent:
`scripts/third_party_components.tsv` → `scripts/generate_third_party_notices.sh` →
`Sources/NullPlayer/Resources/ThirdPartyLicenses/…`, validated by `scripts/validate_notices.sh`.
`BundledSkins_NOTICE.txt` is the existing precedent for skin-asset attribution.

| Asset / dependency | What it is | License / provenance | Disposition |
|---|---|---|---|
| **Webamp `webamp-modern`** | Behavioral reference (TS) for Wasabi/MAKI | MIT (repo-level); pin commit `5f56a53…` at Phase 0B start | **Reference only, not vendored as shipping code.** Reimplement in Swift. Add MIT attribution to notices if any code/data is derived. Do **not** assume repo-level MIT covers unrelated binary/compiler assets in that tree — verify per-file before deriving. |
| **MAKI SDK / `std.mi` / compiler assets** | Wasabi SDK headers & standard-library defs | Unverified; historically Winamp/Nullsoft SDK terms | **Do not bundle.** Reimplement the standard-library surface we actually need from observed behavior. Treat any SDK file as unverified until checked. |
| **CornerAmp_Redux** | First vertical-slice `.wal` target | Not in repo; provenance unverified | **User-supplied local fixture.** Do not commit until license verified. |
| **Winamp Modern** | Broad self-contained target skin | Nullsoft/Winamp asset; not in repo | **User-supplied local fixture.** Do not commit — it is third-party copyrighted skin artwork. |
| **cPro-Bento (`tmp/2222-cPro__Bento.wal`)** | External-engine stress target | Skin Consortium; already in `tmp/` (dev-only, untracked working dir) | Keep in `tmp/` for dev only. **Do not move into tracked test resources.** |
| **ClassicPro engine pack** | External engine cPro-Bento requires | Unknown/unverified (§1) | **Blocked** pending §5 decision. Never bundle without written permission. |
| **Fonts (bitmap + TrueType) referenced by skins** | Per-skin embedded/By-reference fonts | Per-asset; varies | Only bitmap fonts embedded in a licensed `.wal` are used; do not bundle standalone TTFs without their own license. |
| **NullPlayer's own Wasabi/MAKI engine code (new)** | The Swift implementation we write | NullPlayer project license | Original work; ships with the app. |

**Rule of thumb adopted:** no third-party `.wal`, engine, SDK, or font asset enters version control or the
app bundle until its license is individually verified. Everything unverified stays a *user-supplied local
fixture* loaded at runtime by the user.

---

## 3. Security threat model & concrete limits

`.wal` archives and engine packs are **untrusted input**. Resource access goes through a logical,
read-only virtual filesystem (VFS) with fixed mounts — never resolved host paths:

```
/Skins/<active-skin>/            # the imported .wal, validated & extracted to a private store
/Plugins/classicPro/engine/      # optional engine pack (only if §5 permits)
/System/                         # explicitly bundled, licensed Wasabi defaults only
```

`@SKINPATH@`, `@COLORTHEMESPATH@`, `@DEFAULTSKINPATH@`, and any other supported variable resolve **only**
inside these mounts. Normalize Windows/POSIX separators, canonicalize `.`/`..`, do intentional
case-insensitive lookup, reject case-colliding entries, reject symlinks and ZIP traversal. **Escaping a
mount is a hard error.**

### Concrete limits (initial; Phase 0B may tighten from measured need)

| Domain | Limit | Rationale |
|---|---|---|
| Archive entries | ≤ 4,096 files | zip-bomb / inode exhaustion |
| Total uncompressed size | ≤ 128 MB | memory / disk bomb |
| Per-entry uncompressed size | ≤ 32 MB | single-file bomb |
| Compression ratio (per entry) | ≤ 200:1 → reject | zip bomb |
| Nested root dirs | exactly 0 or 1 allowed | tolerate single wrapper dir, reject deep nesting |
| XML nesting depth | ≤ 256 | stack / expansion blowup |
| `<include>` depth | ≤ 32, cycle-detected | include recursion |
| groupdef inheritance depth | ≤ 64, cycle-detected | group recursion |
| Expanded node count | ≤ 100,000 | expansion bomb |
| Image dimensions | ≤ 8,192 × 8,192; ≤ 32 Mpx total | decode bomb |
| Font point size | ≤ 512 | layout blowup |
| Script (MAKI) size | ≤ 4 MB compiled | parse bomb |
| Skin resource cache | ≤ 256 MB, LRU-evicted | steady-state memory |
| MAKI: instructions / event | ≤ 5,000,000 then abort event | runaway script |
| MAKI: call depth | ≤ 256 | recursion |
| MAKI: allocations / event | ≤ 64 MB then abort | memory runaway |
| MAKI: active timers | ≤ 256; min period ≥ 8 ms | timer storm |
| MAKI: animation frequency | ≤ 120 Hz effective | CPU burn |

### MAKI host-API sandbox

MAKI never receives arbitrary filesystem, network, process, DDE, shell, or app access. Only explicit,
narrow NullPlayer capabilities are bound (transport/EQ/playlist/library/vis/config — see host adapters in
the plan). Unsupported/unsafe calls return **documented compatibility defaults or controlled errors**, never
host access. URL opening requires an explicit, user-facing policy (default: blocked). Teardown cancels all
timers, scripts, image work, and audio consumers; a runaway skin must not hang the main thread or survive a
mode switch. Legacy install/update/download warning scripts (e.g. `warning_1.15.maki`) are replaced with
safe NullPlayer messaging and **may not navigate or download**.

---

## 4. Fixtures: repo vs. user-supplied

| Fixture | Location | Committed? |
|---|---|---|
| Synthetic/minimal `.wal` fixtures we author for unit tests | `Tests/…` | **Yes** — original work, purpose-built for archive/VFS/limit tests. |
| Malformed/adversarial archives (traversal, bomb, cycle, case-collision) | `Tests/…` | **Yes** — generated by test code or authored; contain no third-party art. |
| CornerAmp_Redux, Winamp Modern, cPro-Bento, ClassicPro engine | user's machine (`tmp/`, import flow) | **No** — user-supplied local fixtures, loaded at runtime; never tracked. |

Automated compatibility tests that need a real third-party skin are **skipped-by-default** and only run
when the user points them at a locally present, licensed archive (env var / known local path).

---

## 5. Decisions (ratified by product owner) → go/no-go

1. **ClassicPro / cPro-Bento redistribution — RESOLVED: user-supplied import only.**
   Asking for redistribution permission is explicitly off the table and will not happen; therefore we do
   not bundle the ClassicPro engine. cPro-Bento is nonetheless a required (north-star) target, so we build
   a **user-supplied engine import path**: the end user provides the ClassicPro engine files, our runtime
   renders them. NullPlayer redistributes nothing third-party. This is the only option that satisfies both
   "must support cPro-Bento" and "no permission asks." (Dropping cPro was rejected; bundling-with-permission
   was rejected.)

2. **Webamp reference handling — RESOLVED: reference-only.**
   Pin the commit at Phase 0B start, add MIT attribution to `third_party_components.tsv` only if a concrete
   code/table is derived, ship no Webamp source. Use WACUP's public GitHub repos as an additional reference.

**Go/no-go:** Findings §1–§4 and the decisions above are complete and impose **no blockers on Phases
0B–5**. cPro-Bento (Phase 6) is **GO on the architecture** via user-supplied import; its only gate is the
practical one in §0 — the developer must have the ClassicPro engine-one v1.15 files locally to inventory
and test. Phase 0B is **GO**.
