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
