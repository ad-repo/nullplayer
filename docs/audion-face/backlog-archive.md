# Audion Faces backlog archive

Closed entries moved out of [`AUDION_TASKS.md`](../../AUDION_TASKS.md) so the live backlog stays a
list of work that is still open. Every row below is preserved **verbatim**, including the evidence it
was closed on.

## Issuing a number

**The next free number is A10.** A1–A9 were issued 2026-10-08, seeded from the phased plan; A1
closed the same day and is archived below. Check this file before reusing any number — the live
backlog is a list of *open* work and says nothing about which numbers are spent.

## Closed

| ID | Item | Closed on |
|---|---|---|
| A1 | **Phase 0 — worktree, decision record, skeleton docs** | 2026-10-08. Worktree `.claude/worktrees/audion-faces` on `feat/audion-faces` at `a950f44e`, made with `scripts/baseline_worktree.sh`. Baseline: `swift build --build-system native` passes; `swift test --build-system native` executes 2,972 tests, 18 skipped, 0 failures (the toolchain's default build system fails the build with `unable to resolve module dependency: 'VLCKit'`). `docs/audion-face/phase-0-decision-record.md` locks the format, provenance, button mapping, window policy, packaging and limits; corpus headroom measured against every limit, and `AUD0011` (64 Mpx decoded per face) added because nothing else bounded decoded memory. `skills/audion-face-guide/` router and five reference stubs, this backlog, and the `CLAUDE.md` and `skin-subsystem-blueprint` index lines. |
