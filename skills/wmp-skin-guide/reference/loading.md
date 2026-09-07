# Loading a `.wmz`: text, XML, and what is tolerated

The commands that produce every number here live in `reference/harness.md`. This file records what
the loader does and *why*, so nobody re-derives it from the parser.

**Corpus:** the 14 archives in `~/Library/Application Support/NullPlayer/WMPSkins/`. Every count
below carries that denominator; do not rewrite one of these numerators against a different corpus.

## The governing rule

**Degrade with a diagnostic, never fail the skin.** WMP loads markup that no XML parser will accept,
and the skins in the wild were authored against WMP, not against a spec. A rejection is a black
window; a warning is a ranked backlog entry. The only things that stay fatal are the sandbox bounds
(`WMPPhase0Limits`, path escapes, entity declarations) and a document whose *shape* is genuinely
unknowable.

Never relax a limit to make a skin load.

That rule is about the skin, not about the bound. A bound whose *shape* is wrong for the format is a
defect in the bound, and widening it is a fix rather than a relaxation — but only when the guard it
was standing in for is still standing. The test to apply is: name what the bound protects against,
then show that something else still provides that protection at the new value. `imageDimension` is
the worked example; see below.

## The image bounds: an area guard and an axis sanity check

`WMPPhase0Limits.imagePixels` (32 Mpx) is the memory guard. It is what bounds an allocation, it is
checked everywhere an image is admitted — archive sniff, `WMPArchive`, `WMPImageStore`,
`WMPMappingImage` — and `WMPImageStore` carries a decoded-bytes bound beside it.

`WMPPhase0Limits.imageDimension` (32,768) is **not** a second memory guard. For anything remotely
square the area bound binds first: an image 32,768 wide that also passes 32 Mpx is at most 976 tall.
The axis bound exists only to keep `bytesPerRow` arithmetic far from overflow (32,768 x 4 = 128 KiB
per row) and to reject a declared dimension that is nonsense on its face.

It was 8,192, which is a texture-size number and the wrong shape for this format. A WMP slider,
progress bar or volume control is authored as **one horizontal filmstrip of frames**, so a perfectly
ordinary skin resource is thousands of pixels wide and a few dozen tall. Across the 180 installed
archives exactly four images exceed 8,192 on an axis and all four are filmstrips:

| skin | file | declared | area |
|---|---|---|---|
| `pharaoh` | `seek_steps.bmp` | 15990x20 | 320 Kpx |
| `Nautical` | `vol_slider.bmp` | 9494x144 | 1.4 Mpx |
| `The_Doobie_Brothers` | `vol_anim.bmp` | 9152x45 | 412 Kpx |
| `Ice` | `Vid-set.bmp` | 9144x12 | 110 Kpx |

The largest is three orders of magnitude under the area bound, so the old value was costing three
skins their entire load and a fourth its only view while protecting nothing (`W33`). Reproduce the
table by reading the BMP header of every `.bmp` entry in the corpus — 3,684 of them — and sorting by
`max(width, height)`.

Two details that cost time if rediscovered:

* **`Nautical/vol_slider.bmp` is a GIF.** `GIF89a` magic, `.bmp` extension. The archive-level sniff
  in `WMPPhase0ArchiveAuditor.auditContent` reads BMP headers only, so it never saw the file; the
  rejection came later, from `WMPImageStore` asking ImageIO. That is why `Nautical` **loaded** and
  then failed to rasterize its one view, and why counting rejections undercounted this code's reach
  by one skin. Extension does not imply format anywhere in this corpus.
* **The fixtures pin the two bounds separately.** `oversized-image.wmz` is 8193x8193 and is rejected
  by the *area* bound — it stopped exercising the axis bound entirely when the axis bound moved, and
  kept passing, which is the shape of a test that has quietly stopped testing anything.
  `oversized-image-axis.wmz` (32769x10, 328 Kpx) is the axis-bound case, and
  `filmstrip-image.wmz` (15990x20) is the admitted case that fails if anyone narrows the bound back
  toward a texture size.

## Text decoding — `WMPTextDecoder`

Order: UTF-8 BOM, UTF-16LE BOM, UTF-16BE BOM, **BOM-less UTF-16 sniff**, UTF-8, Windows-1252.
Measured across the corpus: `utf16LittleEndian` ×8, `utf8` ×3, `windows1252` ×3.

The Windows-1252 fallback is deterministic and single-byte, so it is a compatibility path, not code-page
guessing. Do not shell out to `iconv` and do not add further ANSI pages.

**The BOM-less UTF-16 sniff is the one non-obvious part, and it is not optional.** Nothing downstream
can catch that case, because neither fallback can *fail*: Windows-1252 (here) and `isoLatin1` (in
`WalXML.decodeText`) accept every byte sequence, so a BOM-less UTF-16 file does not fall through to a
rejection — it "succeeds" into null-interleaved mojibake and the parser then sees a `<` that no `</`
ever closes. The `.wal` engine paid for exactly this once (B93); the sniff now exists in both engines.

The test is **positional, not statistical**: Latin-script UTF-16 markup puts a NUL in every odd byte
(little-endian) or every even byte (big-endian) and essentially never in the other, so the clean side
names the byte order. An `iconv`-style "is there a lot of zero" density guess cannot tell the two ends
apart and produces null-interleaved text when it picks wrong. It additionally requires a `<` as the
first non-whitespace unit, so a single-byte file that merely carries a NUL stays a `WMP0026`
rejection rather than being silently reinterpreted.

It claims nothing in either corpus today and is not why any skin loads. That is the intended state:
it is a guard, and it was added with proof it changes nothing — see `WMP_TASKS.md` W1 for the `.wal`
measurement (827 of 2,384 non-UTF-8 entries reach the changed fallback across 80 archives; zero are
claimed).

## XML — `WMPXMLParser`

`WMPXML.swift` is a hand-rolled parser. **Do not reintroduce `XMLParser`.**

Four of the fourteen archives — `Alpine7618_v09`, `anemone`, `Official_Xbox_XP`, `The Unit` — repeat
an attribute on a tag. libxml2 aborts the whole document on that
(`XML_ERR_ATTRIBUTE_REDEFINED`, reaching Swift as `NSXMLParserErrorDomain 111`) **before the delegate
runs**, and the delegate signature `attributes: [String: String]` could not have carried a duplicate
even if it had. There was no leniency switch to find. The parser is a port of
`WinampModern/WalXML.swift`'s `WalLenientXMLParser`, which solved the same problem for Wasabi markup.

Confirm a suspected malformed-XML rejection with `xmllint --noout <file>.wms`; it names the fault
precisely where the Foundation error code does not.

### Tolerated, with a diagnostic

| Code | What | Behaviour | Corpus |
|---|---|---|---|
| `WMP0034` | duplicate attribute on a tag | **last wins, in the slot the first spelling claimed**; the message names both values | 19 occurrences, 4 skins |
| `WMP0036` | tag left open at end of file | the node keeps its children and siblings, because a node is attached to its parent when it *opens* | 0 today |
| — | unknown tag | stays in the graph as `.unknown(name)` for the compatibility report | see `COMPAT`/`UNKNOWN` lines |
| `WMP0029` | `res://`, `file:`, `http(s):`, `activex:` resource | that one entry is skipped; a `scriptFile` list keeps its siblings (Corona's `res://wmploc.dll/RT_TEXT/#132` warns and its four real programs still register) | 15 |
| `WMP0023` | an **empty** resource attribute (`image=""`) | it names no entry, so it resolves to nothing and that one image is skipped; the node and its view still lay out | 40 views, 36 skins (180-archive corpus) |

The empty-resource row is the one entry here measured against the **180**-archive corpus, and it is
in this table because it was not: an empty path was classified with absolute and drive-qualified
paths and thrown as `WMP0024`, which is a sandbox rejection, and `WMPSceneBuilder` resolves resources
as it walks — so one `image=""` discarded the entire view. It cost 40 views across 36 skins, six of
which drew nothing at all. The loader had warned about the same attribute the whole time. **An
authoring omission is not a sandbox escape**; keep the two apart when adding a resource check.

All three duplicate values measured so far are *identical* on both spellings, so last-wins is
currently invisible. The diagnostic names the discarded value precisely so the first case where they
differ shows up in the census instead of being decided in silence. If one ever does, check what WMP
actually did before assuming last-wins is right — MSHTML took the *first*.

### Still fatal

- a closing tag that does not match the tag it closes (the shape becomes unknowable; no corpus skin
  needs this tolerance yet — if one appears, unwinding to a matching *ancestor* is the next step);
- an entity **declaration** anywhere in a `<!…>` block, including inside a DOCTYPE internal subset
  (the `res://`/`file://` sandbox posture applies to XML too, and a DOCTYPE's `[ … ]` subset must be
  tracked or the scan steps straight over the `<!ENTITY …>` inside it);
- `WMP0013` depth and `WMP0014` node count, from `WMPPhase0Limits`.

### Two things that look cosmetic and are not

**Attribute document order.** `attributes` is an ordered array and stays in the order the file wrote
it, with authored spelling intact. The old parser sorted it alphabetically. The `.wal` engine paid
for that exact mistake: sorting put `id` at position 4 of 10, silently dropped four style properties,
and left cPro2's clock drawing its elapsed and total times on top of each other
(`WalXMLNode.attributeOrder`). A skin reads its own markup positionally.

**Line endings.** Corona, `Alpine7618_v09` and `Official_Xbox_XP` are authored with **CR-only** line
endings. Counting only `\n` put every diagnostic in them at line 1 with a five-digit column. Use
`Character.isNewline`; Swift folds a CRLF pair into one `Character`, so each terminator counts once.

Locations now point at the tag's opening `<`. libxml2 reported the position where the tag *ended*, so
a multi-line tag was attributed several lines late — `corona.wms` `svTop` read as `46:28` (the line
holding that tag's closing `>`) where it opens at `42:4`. Expect that shift when comparing against any
capture taken before rev `733d3631`.

## A `.wmz` that is a ZIP everywhere except its first four bytes

Four corpus archives — `bruteforce`, `Need_for_Speed_Underground`, `QuantumRedshiftWMPSkin`,
`SplinterCellWMPSkin` — carry `01 00 01 00` where the local file header at file offset 0 should
carry `PK\03\04`. Exactly one header per archive is affected, always the one physically first in
the file; the end-of-central-directory record, the whole central directory, every other local
header and every deflate stream are intact. `unzip` and Windows Media Player both read these,
because both work from the central directory.

`ZIPFoundation` reads each entry's local header through a serialiser that validates the signature,
and a `nil` there **ends the iteration** rather than skipping that one entry. In all four the
damaged header belongs to the first central-directory record, so enumeration yielded **zero**
entries — and the loader then reported `WMP0021` "Archive must contain one `.wms` file at its root
or inside one wrapper directory" for four archives whose `.wms` *is* at the root. The diagnostic
named the last rule the empty entry list happened to fail. It was filed as a layout rule that was
too narrow (`W31`); it was the archive reader never seeing a single file, and the layout rule needed
no change at all. **Read the failing archive's bytes before widening the rule its diagnostic names.**

`WMPArchiveHeaderRepair` handles it. The gate is four bytes: an archive whose file begins with a
local header signature is handed straight to the file-backed reader and pays nothing more. Only the
others are read into memory — bounded by `WMPPhase0Limits.repairableArchiveFileBytes` (32 MiB), the
only path that holds a whole archive at once — where the central directory is walked and a local
header's signature is rewritten **only** when the header at that offset already agrees with the
central-directory record pointing at it: same file-name length, same file-name bytes. That
agreement is the entire warrant for writing, and it is what stops a run of arbitrary data being
promoted into an entry; a file that is simply not a ZIP still fails `WMP0001`. ZIP64 archives and
any file whose central directory is not where its record says it is are left alone. Nothing is
written to disk, no limit was relaxed, and the CRC of every repaired entry is still verified before
the provider is exposed.

## Which `.wms` is the skin, when there is more than one

Two of the 180 archives hold two: `Nautical` ships `Nautical.wms` beside a leftover `sample.wms`,
`Sports` ships `ExtremeSports.wms` beside the `saltmine.wms` template it was authored from. Both are
skins Microsoft shipped with WMP 7, so the Player picks one, and `WMP0022` rejecting them was a black
window over a working skin.

**The rule is archive order: the first `.wms` an enumeration of the archive yields.** The others are
named in a `WMP0022` **warning**, never a rejection.

The corpus names the right *answer* without naming the *rule*, and the two must be kept apart. The
answer came from resource resolution: `sample.wms` references 22 images and scripts and **all 22**
are absent from the archive, `saltmine.wms` references 39 and **38** are absent, while both shipping
definitions resolve every resource they name. That is ground truth for validating a rule — it is
deliberately not the rule, because resolving every candidate in order to choose between them is work
the loader should not do and would decide nothing in the other 178 archives.

Against that ground truth three cheap rules are **indistinguishable**: archive order, case-insensitive
alphabetical order, and newest modification time each pick the shipping file in both archives. Archive
order is implemented because it is the only one with warrant outside this corpus — it is what a loader
that enumerates entries and takes the first match does, and the WMP SDK's packaging guidance to add the
skin definition file to the archive first is only meaningful advice if written order is what the Player
reads. Alphabetical and mtime agreeing here is a coincidence of two archives whose leftovers sort late
and are older. The warning names the discarded files precisely so the first archive this picks wrong
appears in the census instead of being decided in silence; it fires exactly twice corpus-wide today,
both correct.

The shape rule is unchanged and still applies to whichever file is selected: at the root, or under one
wrapper directory.

## Case sensitivity

Tag names, attribute names and element ids are all case-insensitive; the corpus spells `<THEME>` and
`<theme>` both ways. Every consumer routes through `WMPElementKind(tagName:)` (which lowercases),
`WMPPath.fold` (Unicode-composed case folding) for ids and duplicate-attribute keys, or
`caseInsensitiveCompare` for attribute lookup. `authoredTagName` exists only to be displayed or
counted — never compare against it.

## What loading does not prove

All 14 archives load. Two of them (`claw`, `iconic`) still produce **zero** layouts, and nine views
across six skins fail `WMP0032` because their size is computed in script. A skin that loads and draws
nothing is indistinguishable from a rejection to anyone using the app — which is why `WMP_TASKS.md`
Tier 1 did not empty when the loader stopped rejecting. Load level is a floor, never a result.

On the 180-archive corpus at rev `9939e871` that floor holds at **180 of 180 loading and 515 views
laying out**, with **12** skins still loading and drawing nothing — every one of them `WMP0032`,
which is now the only cause left. **There are no rejections left in the corpus at all**, which
raises the stakes on the paragraph above rather than lowering them: load level is now a constant,
and every remaining defect is a rendering or runtime one that only a dumped PNG or a `SCRIPT-DIAG`
line can see. `WMP0015` was the last rejecting code and it went with W33.
