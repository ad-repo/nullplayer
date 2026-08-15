# Winamp Modern (`.wal`) — Phase 7 Handoff

**For:** the agent implementing Phase 8 (documentation and release readiness)

**From:** Phase 7 (compatibility hardening — COMPLETE)

**Date:** 2026-08-15

Read first:

- `~/.claude/plans/i-want-to-support-frolicking-rabbit.md` — source-of-truth plan and locked scope
- `docs/winamp-modern/phase-6-handoff.md` — the ClassicPro engine import + cPro-Bento boundary Phase 7 hardens
- `TASKS.md` — Phase 7 is complete; Phase 8 is next

## 1. What Phase 7 landed

Hardening + measured-demand expansion over the Phases 2–6 runtime. Feature stays DEBUG-gated; no
version bump (release exposure + changelog are Phase 8). Everything below runs headlessly on synthetic,
self-authored fixtures — no third-party skin assets committed.

- **7.1 Predefined Wasabi standard library.** `WasabiSkinInitializer.registerWasabiStandardLibrary`
  seeds the curated set of predefined `wasabi.*` base groups (frames/scrollbars/buttons/text/edits/list/
  standardframe variants/albumart/ratings — `wasabiStandardLibraryGroups`) that real skins and the
  ClassicPro engine inherit from but that ship *inside Winamp*, not the archive. Skin/engine groupdefs
  register first, so an explicit definition always wins over our identifier-only shell (no duplicate
  warning). A base outside the curated set still warns-and-drops (graceful degradation preserved).
- **7.2 Per-skin compatibility report.** `WinampModernCompatibilityReport` aggregates load-time
  `WalDiagnostic`s + the runtime unsupported-method tally into stable categories
  (`archive`/`resources`/`groups`/`scripts`/`unsupportedMethods`/`other`) with de-duplicated counts and
  a coarse `level` (`.full` / `.degraded` / `.unsupported`). Reachable via
  `WinampModernLoadedSkin.compatibilityReport` and `compatibilityReport(withRuntime:)`. The main window
  controller logs it (DEBUG only) after `scripts.start()` when the level is not `.full`.
- **7.3 Unsupported-method demand instrumentation.** `WinampModernScriptRuntime.unsupportedMethodCalls`
  records every MAKI method the runtime was asked for but does not implement (case-folded, with counts),
  populated by `unsupported(_:program:)` before it throws — no change to execution semantics. This is the
  measured-demand signal for adding APIs. **Concrete API additions are deliberately fixture-gated:** run
  the opt-in cPro-Bento / Winamp-Modern / CornerAmp acceptance paths, read the report's
  `unsupportedMethods` bucket, and add exactly those methods (each with a regression test). No blind port
  of reference stubs — see §3.
- **7.4 Fuzz — archive / XML / group expansion.** Seeded (`xorshift64`, reproducible) fuzzing of random
  bytes → `WalArchive`, random XML token soup → the full initializer, plus targeted depth-bomb and
  group-inheritance-cycle cases. Guarantee: bounded outcome (valid parse or thrown error) — never a Swift
  trap or hang; targeted cases assert the specific typed diagnostics (`xmlDepthExceeded`,
  `groupInheritanceCycle`).
- **7.5 Fuzz — MAKI parser + VM.** Random bytes (and valid-`FG`-prefixed random bytes) → `MakiBytecodeParser`
  never produce a non-`WalFailure` error; every strict prefix of a valid script rejects cleanly; the
  interpreter's instruction budget aborts a self-jumping loop with `scriptBudgetExceeded`.
- **7.6 Stress.** Timer cap under load (+ reschedule-doesn't-exceed-cap + teardown clears), 50× rapid
  load→start→teardown cycles (graph torn down each time, idempotent), malformed-image resource degrades
  to a typed diagnostic instead of crashing, 2000-groupdef expansion stays within bounds.
- **7.7 Profiling instrumentation.** `testProfileLoadAndTeardownHotPath` records wall-clock metrics over
  the load→graph→script→teardown hot path via XCTest `measure` (no hard time assertion — CI-timing safe).
  **No hotspot warranting Metal was found;** AppKit/Core Graphics stays the renderer (plan §3). Revisit
  only if a representative animated/gamma-heavy skin profiles hot on a real GUI session.

## 2. Verification

- New: `Tests/NullPlayerAppTests/WinampModernPhase7Tests.swift` (7.1–7.7 above).
- `swift test` → **all green** (Phase 6 baseline was 492 pass / 6 opt-in skipped; Phase 7 adds the
  synthetic tests in this file). Opt-in user-supplied fixture paths (CornerAmp / Winamp-Modern /
  cPro-Bento + engine) are unchanged and still gated on their `WINAMP_MODERN_*` env vars.
- The DEBUG four-mode live-switch harness was **not** rerun (cycling it distorts the user's active
  Classic/Modern windows — same constraint carried from Phases 4–6). No Classic or NullPlayer-Modern
  rendering source changed.

## 3. Deliberate limitations carried to Phase 8 / future work

- **7.3 concrete API additions are fixture-gated (not done headlessly).** The instrumentation is in
  place; the actual method list to add can only be *measured* by running the opt-in fixtures on a machine
  that has them. Phase 8 QA is the natural place to capture the report from cPro-Bento and file the
  precise `unsupportedMethods` additions. Do not speculatively add reference stubs.
- **7.8 live playback / casting / GUI verification is spot-check-when-available.** Headlessly drivable
  lifecycle is covered (rapid load/teardown, timer/consumer teardown, mode-switch survival from Phase 1).
  Live playback, seek/volume/EQ from the skin, casting continuity, Compact Mode, UI Size, docking, and
  pixel-level cPro-Bento render still need a GUI session with the user-supplied fixtures — carried into
  the Phase 8 manual QA checklist. Playback/casting are `AudioEngine`-owned and mode-independent, already
  proven for the other families.
- **Predefined Wasabi library is curated, not exhaustive.** `wasabiStandardLibraryGroups` covers the
  bases the measured targets inherit; the shells are identifier-only (no artwork/frames). Widgets whose
  visuals come from those bases render empty. Extend the list (and give shells real template children)
  on measured demand, using the compatibility report as the signal.
- **NSIS/LZMA fuzzing not added.** Phase 7.4/7.5 fuzz the archive/XML/MAKI paths. The internal NSIS-2 /
  LZMA1 engine-installer decoders (Phase 6) are exercised byte-for-byte against the real installer but
  are not fuzzed here; a bounded fuzz over `NSISArchive`/`LZMA1Decoder` is reasonable future hardening.

## 4. Phase 8 starting sequence

1. Write `skills/winamp-modern-skin-guide/SKILL.md` (architecture, VFS/mounts, init passes, scene graph,
   MAKI sandbox, host adapters, controller lifecycle, compatibility workflow using the Phase 7 report).
2. Third-party notices + final provenance record; confirm no third-party asset ships.
3. Document supported/unsupported Wasabi + MAKI behavior and the ClassicPro engine install policy.
4. Changelog entries under the current version (no bump).
5. Manual QA checklist + reference screenshots for CornerAmp / Winamp Modern / cPro-Bento — this is where
   7.3's fixture-gated API additions and 7.8's live verification actually get exercised.
