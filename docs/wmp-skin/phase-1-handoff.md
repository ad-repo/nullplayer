# WMP skin Phase 1 handoff

## Repository state at phase start

```text
pwd:    /Users/ad/Projects/nullplayer-wmp-skin-support
branch: feat/wmp-skin-support
status: clean
HEAD:   10bdd7f366a68be845839e1c99837c454c375a88
```

## Delivered

- `WMPArchive`: metadata-first bounded ZIP validation, exact Phase 0 limits/codes, normalized
  case-insensitive read-only lookup, root/wrapper selection, CRC validation, BMP dimension checks,
  script-size checks, and declaring-file/root resource resolution.
- `WMPTextDecoder`: strict BOM-aware UTF-8, UTF-16LE, and UTF-16BE decoding with malformed
  surrogate, odd-byte, invalid UTF-8, and embedded-NUL rejection.
- `WMPXML`: entity-safe bounded parsing with authored tag/attribute spelling, hierarchy, and source
  locations. Decoded UTF-16 declarations are masked before UTF-8 parser input without shifting
  source coordinates.
- `WMPNode` and `WMPAttributeValue`: deterministic retained graph, closed known-element catalog,
  retained unknown nodes, duplicate-ID warnings, and non-executing classification of JScript,
  property/enabled bindings, handlers, colors, resources, and unsupported forms.
- `WMPSkinLoader`: deterministic view/resource/script registries, optional-image and `res://`
  warnings, required-script failures, decoded script inventory, immutable graph dump/report handoff,
  and 50-cycle load/release coverage.
- `WMPCompatibilityReport`: deterministic tag, attribute, resource, script, member, event, and
  diagnostic inventories.
- `wmp-skin-guide`: WMP-owned technical rules for isolation, locked limits, background execution,
  the unskinned first-launch player, and verification.

## Main-thread boundary

The production loader entry point is async and moves the complete archive, inflation, decode, XML,
graph, registry, compatibility-report, and dump pipeline into a detached background task. The main
actor receives only the completed immutable `WMPLoadedSkin`. A `@MainActor` test asserts that the
actual loader work did not execute on the main thread. No `DispatchQueue.main.sync` path exists.

## Real-corpus parity

The opt-in user-supplied `/Users/ad/Downloads/9SeriesDefault.wmz` test passed with:

- 2 views and the spike's per-tag element inventory;
- 115 BMP resources;
- 3 unique available scripts;
- 87 `.wms` lines containing `JScript:` and 44 containing `wmpprop:`.

No Microsoft/community skin or derived artifact was added to the repository.

## Change-boundary audit

Production and test implementation is confined to `Sources/NullPlayer/WMPSkin/` and WMP-prefixed
test files. No shared application source, existing skin engine, UI mode, controller, preference, or
installed state changed in Phase 1.

`docs/wmp-skin-integration-plan.md` is the only changed path outside the WMP implementation/test/doc
folders. It is the implementation mirror of the canonical plan and was explicitly updated to lock:

- the hard worktree/branch preflight;
- WMP-local changes unless no local seam exists;
- off-main WMP input work;
- the WMP-owned unskinned fresh-install/default/recovery player, never Original.

An initial implementation attempt mistakenly created only new untracked WMP files under
`/Users/ad/Projects/nullplayer`. Work stopped immediately after discovery; those exact new files were
copied into this worktree and removed from the original checkout. No pre-existing file or user edit
there was modified or removed. Before this commit, all three worktrees were audited; implementation
files exist only here, while the planning worktree contains only its intentional canonical-plan edit.

## Verification

```text
focused Phase 1 suite: 17 passed, 1 expected opt-in skip, 0 failed
9SeriesDefault opt-in parity: 1 passed, 0 failed
full swift test: 457 passed, 1 expected opt-in skip, 0 failed (29.493 s)
Phase 0 archive/helper tests within full suite: 8 passed, 0 failed
git diff --check: passed
```

The skill-creator validator could not start because its environment lacks the optional `yaml` Python
module; the skill frontmatter and structure were checked manually and contain no scaffold fields.

## Phase 2 boundary

Phase 2 may consume only the immutable graph/resource registries. Image metadata/decode/cache work
must remain bounded and off-main, and the retained graph must not gain AppKit state. Expressions stay
unresolved with diagnostics; no skin code executes. The static renderer remains a test harness and
does not add a UI mode.

## Repository state at phase end

```text
pwd:    /Users/ad/Projects/nullplayer-wmp-skin-support
branch: feat/wmp-skin-support
status: clean after committing this handoff
Phase 1 implementation HEAD: 934976bd
```
