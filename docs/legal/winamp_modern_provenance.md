# Winamp Modern (`.wal`) Implementation Provenance Audit

- Date: 2026-08-15
- Scope: `Sources/NullPlayer/WinampModern/`, `Sources/NullPlayer/Windows/WinampModern/`,
  `Tests/NullPlayerAppTests/WinampModern*Tests.swift`, `docs/winamp-modern/`
- Purpose: establish that the Wasabi/XUI renderer, MAKI virtual machine, and ClassicPro engine
  importer are clean-room work, that no third-party skin or engine asset ships, and that no
  third-party notice obligation was created.

Companion to the Phase 0A decision record (`docs/winamp-modern/phase-0a-decision-record.md`), which
set the disposition this audit verifies.

## Dispositions being verified

Phase 0A locked three rules:

1. **Webamp (`webamp-modern`) is a behavioral reference only** — reimplement in Swift, do not vendor.
   Add MIT attribution to `scripts/third_party_components.tsv` **only if** concrete code or data is
   derived.
2. **The ClassicPro engine is user-supplied** — never bundled, never downloaded.
3. **Skin fixtures are user-supplied local files** — not committed until provenance is verified, which
   for the three targets it never was.

## Audit method and results

### 1. No Webamp-derived code

```bash
grep -rniE "webamp|UI_ROOT|makiTree|parseMaki|BitmapFont\.ts|Vm\.ts" \
  Sources/NullPlayer/WinampModern Sources/NullPlayer/Windows/WinampModern
```

Result: **no matches.** The Swift implementation shares no identifiers, file structure, or naming
scheme with the TypeScript reference. Its architecture is independently shaped by NullPlayer's own
constraints (a bounded `WalResourceProvider`, a retained `WasabiObjectGraph` with deterministic IDs,
typed `WalDiagnostic`s, and a `weak`-dispatcher interpreter), none of which have a Webamp analogue.

**Determination:** no derivation → **no manifest entry required**, per the Phase 0A rule.

### 2. LZMA1 decoder

```bash
grep -rniE "Pavlov|LzmaDec|CLzmaDec|kMatchMinLen|LZMA_SDK|7-?zip" Sources/NullPlayer/WinampModern
```

Result: one match — the constant name `kMatchMinLen` in `LZMA1Decoder.swift`, which echoes the LZMA
SDK reference decoder's naming for the same protocol constant.

`LZMA1Decoder` is a from-scratch incremental range decoder written against the LZMA format. A format
constant's name and value are not protectable expression, and in any case **the LZMA SDK is released
into the public domain**, so even actual derivation would carry no attribution or notice obligation.

**Determination:** **no manifest entry required.** Nothing to attribute.

### 3. No third-party assets committed

```bash
git ls-files | grep -iE "\.wal$|\.maki$|\.wsz$|ClassicPro|CornerAmp|Bento"
```

Result: three matches, all cleared:

| Path | Assessment |
|------|------------|
| `Sources/NullPlayer/Resources/Skins/NullPlayer-Silver.wsz` | NullPlayer's own classic skin; unrelated to this subsystem and already covered by existing notices |
| `Sources/NullPlayer/WinampModern/ClassicProEngine.swift` | NullPlayer source (the importer). Contains no engine content |
| `docs/winamp-modern/phase-0b-artifacts/inventory-2222-cPro__Bento.md` | See below |

The cPro-Bento inventory is a **structural metadata dump** produced by the Phase 0B harness: element
counts, identifier names, and `file:line` references. It contains no artwork, no bytecode, and no
copied markup. Counts and identifier names are facts about a file rather than a reproduction of it.

**Determination:** retained. No skin, engine, font, or bitmap asset ships in the app bundle or the
repository.

### 4. Test fixtures

Every committed fixture is synthetic and self-authored — archives are constructed in-test via
ZIPFoundation, and MAKI programs are hand-assembled by `makeMinimalScript`. Tests that need a real
skin are **opt-in and skip by default**, gated on `WINAMP_MODERN_WAL` / `WINAMP_MODERN_ENGINE`
pointing at a file the developer supplies locally.

**Determination:** the test suite creates no distribution obligation.

### 5. Runtime engine handling

The ClassicPro engine is supplied by the user, extracted **internally** (no external tools, no code
execution), and stored in the user's own Application Support directory. NullPlayer never bundles,
downloads, or redistributes it — the installer never leaves the user's machine.

**Determination:** no redistribution → no notice obligation.

## Manifest impact

**None.** `scripts/third_party_components.tsv` needs no new row for this subsystem. The only
third-party dependency on the `.wal` code path is **ZIPFoundation**, which is already covered
(`zipfoundation`, MIT).

Note the contrast with `vis_classic`, `geiss`, and `tripex`: those are *ports of existing source* and
therefore carry upstream license entries. The Winamp Modern engine is not a port of anything — adding
a manifest row for it would misdescribe the shipped code.

Verify with:

```bash
./scripts/validate_notices.sh <path-to-app>/Contents/Resources
```

## Residual items for human sign-off

- This audit is identifier- and asset-level, matching the method used for
  `waveform_provenance.md`. It is not a line-by-line comparison against the Webamp tree, which no
  automated scan can substitute for. The Phase 2–7 records consistently assert clean-room
  implementation, and scan (1) found no trace of the reference; a reviewer wanting stronger assurance
  should spot-check `MakiBytecode.swift` and `WasabiSkinInitializer.swift` against
  `packages/webamp-modern` directly.
- Skin fixtures used during QA remain the developer's own responsibility; do not commit them. If a
  fixture is ever proposed for the repository, its license must be verified first, per Phase 0A.
