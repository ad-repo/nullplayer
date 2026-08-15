# Winamp Modern (`.wal`) — Phase 6 Handoff

**For:** the agent implementing Phase 7 (compatibility hardening)

**From:** Phase 6 (ClassicPro user-supplied engine import + cPro-Bento — COMPLETE)

**Date:** 2026-08-15

Read first:

- `~/.claude/plans/i-want-to-support-frolicking-rabbit.md` — source-of-truth plan and locked scope
- `docs/winamp-modern/phase-0b-decision-record.md` §1–§3 — the native surface, engine anatomy, and cPro topology this phase implements
- `docs/winamp-modern/phase-5-handoff.md` — component-host seam and lifecycle inherited here
- `TASKS.md` — Phase 6 is complete; Phase 7 is next

## 1. Phase 6 outcome and boundary

cPro-Bento — the north-star target — now loads end-to-end from a user-supplied `.wal` plus a
user-supplied ClassicPro installer, with **all extraction internal** (no external tools, no temp files,
no code execution). The scope decision (2026-08-15) was to build the full internal `.exe` path now.

Landed:

- **`LZMA1Decoder`** (`Sources/NullPlayer/WinampModern/LZMA1Decoder.swift`) — from-scratch, incremental
  raw LZMA1 range decoder (props/dict init, `decode(untilOutputCount:)`, retained dictionary, bounded
  output). Reimplements the LZMA SDK reference decoder; no third-party code.
- **`NSISArchive`** (`.../NSISArchive.swift`) — NSIS-2 solid-LZMA reader: locate the firstheader,
  decompress the single solid stream on demand, parse the header block/string table/entry array, and
  replay only `SetOutPath`(EW_CREATEDIR p1≠0)/`ExtractFile`(EW_EXTRACTFILE) to reconstruct the file tree.
  Supports only what ClassicPro uses (NSIS-2 / solid LZMA); other layouts get an actionable diagnostic.
- **`WalDirectoryResourceProvider`** (`.../WalDirectoryResourceProvider.swift`) — bounded read-only
  `WalResourceProvider` over an extracted folder (entry/size/total caps, symlink reject, case-collision).
- **`ClassicProEngine`** (`.../ClassicProEngine.swift`) — `ClassicProEngineImporter` (accepts `.exe`
  via NSIS, `.zip` incl. a nested installer, or an extracted folder) + `ClassicProEngineStore` (one-time
  private store, structure/version validation requiring the `one` family, SHA-256 content hash, mounted
  read-only provider). Store lives at `…/WinampModernSkins/ClassicProEngine/engine/`.
- **Engine mount** — `WinampModernSkinLoader(engineStore:)` auto-mounts the installed engine at the
  logical `/Plugins/classicPro/engine/` path (default `.shared`; pass a temp store in tests, `nil` to
  disable). cPro-Bento's `@COLORTHEMESPATH@\..\..\Plugins\classicPro\engine\load.xml` resolves there.
- **Version gate shim** — `WinampModernScriptRuntime` reports `getBuildNumber() = 9999`
  (`reportedWinampBuild`), past cPro-Bento's `2405` gate, so `WinampVersionCheck.maki` branches past its
  "please update Winamp" `messageBox`. Also added `getpublicint`/`setpublicint`/`getdate`/`getdatedoy`/
  `getwinampversion` (the calls the gate makes before the build check).
- **`ClassicProFile` shell adapters** — the entire native surface (P0B §1): `exploreFile`(reveal in
  Finder), `openFile`(open existing file with default app), `findFiles`(bounded no-op → callers
  early-return). Host methods `revealInFinder`/`openExternally` gate on a real, existing, non-URL,
  non-`~` file; skins cannot navigate URLs, launch executables, or reach arbitrary paths.
- **Graceful degradation** so the full SUI expands: `file="$solid"`/`"$gradient"` predefined bitmaps are
  not resolved as VFS files; a missing *optional bitmap/cursor* image is a warning (not a hard error);
  a groupdef inheriting an unknown predefined `wasabi.*` base group warns and drops the base.
- **DEBUG UI** — "Import ClassicPro Engine…" menu action + `ClassicProEngineIngestor` on the container
  seam. Feature remains DEBUG-gated; no release exposure; no version bump.

## 2. How to reproduce the acceptance

```sh
# cPro-Bento + engine, end-to-end (internal .exe extraction, mount, script run, topology):
WINAMP_MODERN_ENGINE=/path/to/ClassicPro_2.01.exe \
WINAMP_MODERN_WAL=/path/to/2222-cPro__Bento.wal \
  swift test --filter WinampModernPhase6Tests

# LZMA/NSIS validated against the local installer with 7zz as oracle only (never shipped):
#   see scratch harness pattern in the Phase 6 session; 309/309 engine files byte-match.
```

Opt-in fixture contract (nothing third-party is committed):

- Phase 3 opt-in: `WINAMP_MODERN_WAL` = CornerAmp_Redux
- Phase 4 opt-in: `WINAMP_MODERN_WAL` = **Winamp Modern** (asserts 354×280 / shade geometry — cPro-Bento
  is the wrong fixture for it)
- Phase 5 opt-in: `WINAMP_MODERN_WAL` = any self-contained skin, **or** cPro-Bento + `WINAMP_MODERN_ENGINE`
- Phase 6 opt-in: `WINAMP_MODERN_ENGINE` (+ `WINAMP_MODERN_WAL` = cPro-Bento for the full path)

## 3. Deliberate limitations carried to Phase 7

- **Predefined Wasabi standard library is incomplete.** cPro-Bento inherits from `wasabi.*` groups and
  declares optional bitmaps that ship inside Winamp, not the skin/engine. Phase 6 makes these degrade
  gracefully (warnings) so the SUI expands and yields one main window, but the corresponding widgets
  render empty. Providing real `wasabi.*` definitions (object frames, scrollbars, etc.) and confirming
  **pixel-level** cPro rendering is Phase 7 (`packages/webamp-modern` is the behavioral reference).
- **NSIS support is intentionally narrow.** Only NSIS-2 + solid LZMA (what ClassicPro uses). Non-solid,
  zlib/bzip2, NSIS-3, and non-NSIS `.exe` fail with a clear diagnostic. Broaden only on measured demand.
- **`getPublicInt`/`setPublicInt` are per-skin namespaced** (reserved `@public` section), not truly
  app-global. Harmless because the version gate never reaches the reminder path; revisit if a skin needs
  cross-skin public config.
- **No live GUI render/interaction was driven for cPro-Bento** (headless load + graph/topology only,
  same constraint as Phases 4–5: cycling the mode-switch harness distorts the user's active windows). A
  live playback + drawer/tab/theme spot-check belongs in Phase 7 when a GUI session is available.
- **`findFiles` is a no-op** (returns −1); the "enqueue matching files" ALT-click feature is inert by
  design. Wiring a bounded host file-search adapter (P0B §1) is optional Phase 7 work.

## 4. Verification completed

- `swift build` clean; `swift test` → **492 tests pass**, 6 opt-in skipped (Phase 5 was 475; +15
  synthetic Phase 6 tests +2 opt-in).
- `Tests/NullPlayerAppTests/WinampModernPhase6Tests.swift`: LZMA reference-vector + incremental decode;
  directory provider (read/bounds/symlink/entry-limit); engine validation (rejects non-engine / missing
  `one`; stable hash); store install + provider round-trip; importer from extracted folder and nested
  `Plugins/…` tree; loader mounts engine for the cPro include (and fails when absent); version shim past
  the 2405 gate; `ClassicProFile` adapters routing through the policy. Opt-in: internal installer
  extraction (`one` family, >50 files, `load.xml` readable) and full cPro-Bento + engine load → one main
  window.
- Real-installer validation: internal NSIS/LZMA extraction is **byte-perfect** on all 309 ClassicPro 2.01
  engine files (7zz oracle); the one non-match is an installer artifact with unresolved `$SHELL`/`$LANG`
  shell-folder path variables (correctly excluded from the engine tree).
- One Phase 2 test updated to the Winamp-compatible contract: a missing bitmap image records a warning
  instead of hard-failing (security failures — traversal/escape/oversize/corrupt — still throw).

## 5. Phase 7 starting sequence

1. Stand up the predefined Wasabi standard-library groups (`wasabi.*`) and confirm pixel-level cPro-Bento
   rendering against `packages/webamp-modern`; turn the current graceful-degradation warnings into a
   per-skin compatibility report.
2. Drive the live cPro-Bento GUI: playback, seek/volume/EQ, drawers/tabs/theme selector/notifier, shade,
   casting continuity, Compact Mode/UI Size, state restore.
3. Fuzz NSIS/LZMA + archive/XML/MAKI paths; stress timers/animations/rapid switches/large playlists.
4. Profile graph mutation, drawing, and gamma/theme caches; introduce Metal only for a demonstrated hotspot.
