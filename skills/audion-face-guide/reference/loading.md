# Loading Audion faces

Read `../SKILL.md` first; its isolation rule binds every section here.

This file owns the loader, zip import, policy and diagnostics, and from Phase 3 the importer: what is
tolerated, what stays fatal, and the order checks run in. The threat model and the locked limits are
`docs/audion-face/phase-0-decision-record.md` § *Threat model* and § *Loading limits*.
`AudionFacePolicy` and `AudionFaceZipLimits` are the executable copies. **A limit is never relaxed to
make one face load**; an amendment goes in the decision record, argued about the threat.

## Entry points

- `AudionFaceLoader.load(folder:) async throws -> AudionFace`: leaves the caller's executor
  (`Task.detached`) before touching the folder. A fatal `AudionFaceFinding` is thrown; warnings are
  `AudionFace.findings`, in a stable order (roles in `allCases` order).
- `AudionFaceZipImport.unpack(_:into:limits:) throws -> [URL]`: unpacks into a folder the caller
  owns and returns every folder it unpacked an `index.json` into (never anything already there); each
  then goes through the loader.
  Synchronous, so call it off the main thread. A zip rejected by its central directory writes
  nothing; one failing a CRC may leave a partial tree, so unpack into a fresh folder and discard it on
  a throw.

## Check order

Nothing is decoded until every bound that could refuse the face has passed.

1. **Walk** the folder recursively before opening any file. The folder itself or any entry being a
   symlink is `AUD0006`. Every entry, directories included, counts toward 2,000 and every regular
   file's size toward 64 MiB (`AUD0005`). Only top-level regular files can be read; a FIFO or device
   named like a sprite is simply absent.
2. **`index.json`**: absent is `AUD0001`; read at most 256 KiB + 1 byte, so a larger one is
   `AUD0003` however it got there; unreadable or not a JSON object is `AUD0012`.
3. **`AudionFaceDocument`** decodes the elements. Malformed keys become `AUD0013`; PICT ranges
   outside 0…99,999 become `AUD0007` before any file is looked up, so a hostile count costs nothing.
4. **Headers**: `base.png` must carry a PNG header (`AUD0002`). Each element then claims its files;
   only the files an element asks for have their headers read. An element missing a file is dropped
   (`AUD0009` for a button, `AUD0013` otherwise).
5. **Budgets** over the distinct files to decode: each within 4,096 px a side and 8 MiB on disk
   (`AUD0004`), and together within 64 Mi pixels (`AUD0011`).
6. **Decode** with ImageIO, each file once (time digits commonly share one PICT range). A file that
   fails to decode, or decodes to a size its header did not declare, is treated as missing: the
   private `Plan` that chose the files from headers is built again over the decoded images, so an
   element loses a file the same way in both passes. `base.png` failing is `AUD0002`.
7. **Masks** of a size other than `base.png` are kept and reported (`AUD0008`).

## Tolerance

- Absent element (no key, zero rect): silent.
- Missing pause sprite, missing `-active`, `-disabled` or `-hover`: silent; FaceKit treats each as
  optional.
- Malformed key, missing companion key, absent artwork for an element with a rect: that element is
  dropped with a warning; the face loads. See format.md for what each element needs.
- A rect edge outside `AudionFacePolicy.coordinates` (±65,536) is malformed (`AUD0013`), so no rect
  arithmetic can overflow; a font size outside `AudionFacePolicy.fontSizes` (0–1,024) reads as absent
  (Helvetica 12), so text rasterizes into a bounded image. Both trapped before Phase 6, found by
  `AudionFaceFuzzTests`; the corpus spans 1,318 and 0–90.
- A file that is not regular (a FIFO, a device) is absent, never opened; a sprite whose header
  passes and whose data does not decode is missing.

## Zip import

Bounds and their measured basis are in the decision record § *Loading limits* (`AUD0010`'s bounds).
In order: the zip must open (`AUD0014`); each entry counts toward the entry bound; `__MACOSX/` entries
are skipped unwritten; a symlink entry or an unsafe path is `AUD0006`; expanded sizes and the
above-floor ratio are checked (`AUD0010`). Only then is anything inflated, each entry held to its
declared size and CRC (`AUD0014`).

## Codes

| Code | Test that proves it |
|---|---|
| `AUD0001` | `AudionFaceHostileInputTests.testAUD0001MissingIndex` |
| `AUD0002` | `testAUD0002MissingOrUndecodableBase` |
| `AUD0003` | `testAUD0003IndexOverItsBound` |
| `AUD0004` | `testAUD0004DecodedImageOverItsSideOrByteBound`, `testAUD0004IgnoresFilesTheLoaderNeverDecodes` |
| `AUD0005` | `testAUD0005TooManyFilesOrBytes` |
| `AUD0006` | `testAUD0006Symlinks`, `testAUD0006ZipPathsThatEscape` |
| `AUD0007` | `testAUD0007PICTRangesOutsideTheBoundDropTheElement` |
| `AUD0008` | `AudionFaceLoaderTests.testAMaskOfAnotherSizeIsKeptWithAUD0008` |
| `AUD0009` | `AudionFaceLoaderTests.testAButtonRectWithoutASpriteIsDroppedWithAUD0009` |
| `AUD0010` | `testAUD0010ZipBounds`, `testAUD0010RatioAppliesOnlyAboveItsFloor` |
| `AUD0011` | `testAUD0011PixelBudgetIsCheckedFromHeadersBeforeAnyDecode` |
| `AUD0012` | `testAUD0012MalformedIndex` (including 100,000 nested `[`) |
| `AUD0013` | `AudionFaceLoaderTests`: the digit, animation and malformed-key tests; `testAUD0013ExtremeCoordinatesAndFontSizesNeitherTrapNorDraw` |
| `AUD0014` | `testAUD0014UnreadableOrCorruptZip` |

Fixtures are synthesized in-test by `AudionFaceFixture` (in `AudionFaceLoaderTests.swift`): sparse
files and header-only PNGs reach the production bounds without building large files.

## Install, select, remove

Phase 3 (`AudionFaceImporter`).

Beyond the codes: `testAFIFOIsAbsentNeverOpened`, `testATruncatedSpriteIsMissing`, and
`AudionFaceFuzzTests` — 400 seeded mutations of an every-element face (hostile values per key, byte
damage to `index.json` and to one sprite), each of which must load or fail with a finding and then
render every host and interaction state. A failing iteration prints its mutation; the seed makes it
reproduce.
