# Winamp Modern (`.wal`) — Phase 8 Handoff

**For:** the agent picking up Winamp Modern work after Phase 8

**From:** Phase 8 (documentation and release readiness — COMPLETE)

**Date:** 2026-08-15

Read first:

- `skills/winamp-modern-skin-guide/SKILL.md` — the durable subsystem guide Phase 8 produced. **This
  supersedes the per-phase handoffs as the starting point.** Read it before this document.
- `skills/winamp-modern-skin-guide/compatibility.md` — supported/unsupported surface, limits, and the
  measured demand list
- `skills/winamp-modern-skin-guide/manual-qa-checklist.md` — the GUI pass that has never been run
- `TASKS.md` — Phases 0A–8 complete

## 1. What Phase 8 landed

Phase 8 was scoped as documentation, but running the thing turned it into a bug-fix phase as well.
Both halves matter to whoever comes next.

### Documentation

- **`skills/winamp-modern-skin-guide/`** (new skill, 3 files): architecture and pipeline, the security
  model, VFS mounts, initialization passes, graph/geometry, MAKI, component hosting, teardown order,
  mode integration, the ClassicPro engine, a debugging workflow, and rules for extending the
  subsystem. Registered in `CLAUDE.md`, which also gains `WinampModern/` in the architecture tree.
- **`docs/legal/winamp_modern_provenance.md`**: an evidence-based clean-room audit modeled on
  `waveform_provenance.md` — identifier scans for Webamp and LZMA-SDK derivation, plus a
  committed-asset scan. **Conclusion: `scripts/third_party_components.tsv` needs no new row.** Nothing
  third-party is derived or shipped; ZIPFoundation (the only dependency on this path) is already
  covered. Do not "helpfully" add an entry for this subsystem — it is not a port, and a row would
  misdescribe the shipped code.
- **Changelog**: one entry under `## Unreleased`. **No version bump** (still the standing rule).

### Release exposure

The user's decision (2026-08-15) was **expose as experimental**, not "stay DEBUG-gated" and not "ship
plain".

- `AppFeature.winampModernMode` replaces the `#if DEBUG` around the menu, matching how
  `classicMode`/`modernMode`/`metalMode` are gated. The whole submenu block is behind one capability
  check so an edition that disables it pays none of the filesystem work.
- Submenu is titled **"Winamp Modern (Experimental)"**.
- `setWinampModernMode`, the `.wal` importer, the engine importer, and skin selection are all
  un-gated. **Still DEBUG-only:** `-winampModernSkinPath`, `-winampModernAcceptanceLoop`, and the
  compatibility-report logging in the window controller.
- **Release config is now the one that matters.** Before Phase 8 this code never compiled without
  `DEBUG`. Run `swift build -c release` after touching it (verified clean here).

### Defects fixed

**Phase 7 had never actually been run.** Its own notes admitted the suite "did not finish"; the real
reason was that its fuzz test had found a bug and was spinning on it. Three defects:

1. **Infinite loop in production XML parsing** (`WalXML.swift`). In the attribute scanner, a `/` that
   does not close the tag (`<a /x>`, or `/` as the last byte) matched no branch and left `cursor`
   unchanged — an unbounded spin on the loading thread, reachable from any malformed skin. Fixed with
   a per-iteration forward-progress guarantee. This is the class of bug the fuzz harness exists to
   catch, and it worked; nobody looked at the result.
2. **`testInterpreterInstructionBudgetAborts` never exercised the budget.**
   `MakiInterpreter.dispatcher` is `weak`, the test passed a temporary, it deallocated immediately,
   and `execute` returned at `guard let dispatcher` having run zero instructions. See the gotcha in
   SKILL.md — this trap is easy to re-introduce.
3. **`testMalformedImageResourceDegrades…` trapped in its own setup** (`UInt8(index &* 7)` overflows
   at index 37), so the malformed-image path was never reached.

All three fixed; `swift test --filter WinampModernPhase7Tests` → **23/23**.

### Live-run fixes (the user ran cPro-Bento + engine in the GUI)

4. **MAKI opcode 104 implemented — dynamic `Member` access.** This hard-failed the load with
   "Unsupported MAKI opcode 104". Determined empirically rather than guessed (method in §4 below):
   the immediate is a `MakiValueKind`, and the opcode pops an object and a name and pushes the
   member's storage **as an lvalue**, so opcode 48 assigns straight through it. Backed by
   `MakiInterpreter.objectMembers`, keyed by object identity, capped by
   `limits.maximumObjectMembers` (65,536), cleared on teardown.
5. **A failing script no longer kills the whole skin.** `dispatch` catches `WalFailure` per binding,
   records it in `scriptFailures`, and continues. The skin loads degraded and *every* blocker shows up
   in one run instead of one crash per rebuild. **This cannot be made finer-grained than per-event:**
   MAKI call sites carry no argument count, so without a signature the stack cannot be unwound — which
   is also why unsupported methods must be *implemented*, never stubbed.
6. **Signature misses are now recorded.** `signature(for:)` returning nil is the path most
   unimplemented methods take, and Phase 7.3's tally only hooked `invoke` — so the report was blind to
   exactly the thing it was built to measure.
7. **Opt-in acceptance gap closed.** The Phase 6 cPro-Bento test stopped at load + topology and never
   constructed the script runtime — which is precisely why opcode 104 was invisible to a green suite
   and only appeared when the app ran. `testLocalSkinScriptRuntimeStartsWhenSupplied` (Phase 8 tests)
   now drives load → runtime → `start()` and prints the categorized report.

## 2. The immediate next task

**Implement the five MAKI methods that block cPro-Bento's startup.** This is measured, not guessed —
it is the `unsupportedMethods` bucket from a real run:

| Method | Calls at startup |
|--------|------------------|
| `loadmap` | 5 |
| `getitembyguid` | 2 |
| `getposition` | 1 |
| `getscale` | 1 |
| `isinvalid` | 1 |

Two follow-on `findobject`-on-null errors are downstream of these and should be re-measured after,
not chased first.

Scale note: **193 methods are referenced across the engine's 90 `.maki` files, but only these five are
reached at startup.** Do not work from the static list — it is a wildly pessimistic upper bound. Add
each method to `signature(for:)` *and* its dispatch path together, with a regression test, then re-run
the acceptance and read the new report. Repeat. That loop is the whole methodology.

Reproduce the measurement:

```sh
WINAMP_MODERN_ENGINE=tmp/ClassicPro_2.01.exe \
WINAMP_MODERN_WAL=tmp/2222-cPro__Bento.wal \
  swift test --filter testLocalSkinScriptRuntimeStartsWhenSupplied
```

Current state of that run: loads, level `unsupported`, 12 resource / 279 group / 12 script findings.
The 279 group findings are the `wasabi.*` predefined-artwork gap (Phase 7.1's curated shells are
identifier-only) and are the reason cPro-Bento will render largely empty even once the five methods
land. **Expect to need real `wasabi.*` template content before the skin looks like anything.**

## 3. What is still unverified — read this before claiming anything works

**No GUI verification has ever been performed, in any phase.** Not once, across Phases 3–8, has any
target skin been watched render or take input. Every "PASS" in the phase records is headless.
Specifically unverified: live rendering and pixel fidelity, input, playback driven from a skin's own
controls, casting continuity, Compact Mode, UI Size, and window docking in this mode.

`skills/winamp-modern-skin-guide/manual-qa-checklist.md` exists to close this and is the gate on
removing the "Experimental" label. Do not remove that label on the strength of a green test suite.

Also still open:

- `NSISArchive` / `LZMA1Decoder` are not fuzzed (they are byte-validated against the real installer,
  309/309 files).
- Library embedding is a seam: the production bridge returns `nil`, so a library toggle falls back to
  the classic window.
- Auxiliary container windows render and take input but do not drive per-container MAKI layout
  switching (invisible on cPro-Bento, which is single-window).
- Playlist/EQ are engine-drawn in the skin's frame, not painted with the skin's own bitmaps.

## 4. Method worth reusing: identifying an unknown opcode

Opcode 104 was resolved without a reference implementation, and the same approach will work for the
next unknown one:

1. **Find the candidates.** Walk every `.maki` code section with the parser's own opcode/immediate
   rules and collect what fails. 104 was the only unknown across all 90 engine scripts.
2. **Determine the encoding by alignment.** A code section must consume to exactly `codeEnd`.
   Assuming "no immediate" desynchronized the stream into garbage opcodes (0, 5, 6) in 6 files;
   assuming a u32 immediate parsed all 90 cleanly. That is decisive, not suggestive.
3. **Determine semantics from the shipped source.** ClassicPro ships `.m` source next to the
   bytecode for all 98 scripts. Dump the immediate values and the surrounding pushes with variable
   kinds and string constants resolved, then grep the `.m` for those constants. `push obj`,
   `push "custombg"`, `104 TYPE=int`, `push 7`, `48` lined up exactly with
   `Member int CProWidget.custombg;` / `drawer_equalizer.custombg = 2;`.
4. **Confirm the value type.** The immediates were 2/5/6, which are precisely `MakiValueKind`'s
   integer/boolean/string — the compiler emits the member's declared type.

The throwaway Python walker used for this is not committed; it is ~60 lines mirroring
`MakiBytecodeParser`'s header and instruction reads.

## 5. Verification completed in Phase 8

- `swift test` → **523 pass**, 7 opt-in skipped (was 492 + 6 at Phase 6). Includes 23 Phase 7 tests now
  genuinely green and 8 new Phase 8 tests.
- `swift build -c release` → clean. Newly meaningful, since the menu is no longer `#if DEBUG`.
- cPro-Bento + ClassicPro engine: loads end-to-end through the script runtime with a categorized
  compatibility report.
- No third-party asset committed; notices manifest deliberately unchanged.
- The DEBUG four-mode live-switch harness was **not** rerun (cycling it distorts the user's active
  Classic/Modern windows — constraint carried from Phases 4–7). No Classic or NullPlayer-Modern
  rendering source was changed.
