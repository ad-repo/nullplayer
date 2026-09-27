# `.wmz` harness: the corpus

Moved verbatim from `reference/harness.md` on 2026-09-25; that file is the router. Read it first.

## The corpus

Installed skins live outside the repo, matching the `.wal` convention:

```
~/Library/Application Support/NullPlayer/WMPSkins/
```

`WMPSkinImporter.swift` installs there. Archives are never committed; only per-skin `.md` notes are.

**Enumeration rule.** `*.[wW][mM][zZ]`, `-type f`. A bare `*.wmz` drops an upper-case spelling and a
bare `*` picks up directories. Every script **prints the count it measured and never asserts a fixed
one** — the corpus moves, and a document quoting a frozen number goes wrong in a way that looks
right. Each row carries a sha256 so byte-identical archives under two filenames are visible as
duplicates instead of counted twice.

**The measured corpus is 179, not the 180 in `WMPSkins/`.** `scripts/wmp_corpus_exclusions.txt`
holds `Darkling.wmz`, and `harness/scripts.md` § *`scripts/wmp_corpus_exclusions.txt`* says why and what qualifies.
An excluded archive is not a defect and never ranks work. **The corpus grew from 14 archives to 180
on 2026-09-07**; it reads 184 from 2026-09-18 and 185 from 2026-09-19 as new archives landed, which
is why every count on this page carries the archive number it was taken over.

**Two byte-identical archives were deleted. Five *name*-similar pairs were kept deliberately** —
`Ginger Man`/`Ginger_man`, `QuickSilver`/`QuickSilver (2)`, `Revert`/`Revert (1)`,
`Project Gotham Racing 2`/`Project Gotham Racing 2 (1)`, `The Unit`/`TheUnit` — because they are
different releases of the same skin with differing `.wms` and `.js`, and are separate test cases.

### A corpus number taken with `grep` is not a corpus number

**`grep` decides a `.wms` is binary and prints nothing, exiting 0.** About half the corpus's
definitions are cp1252 and carry a `0xA9` copyright sign in the header comment of the very first
line, which is not valid UTF-8; in a UTF-8 locale `grep` then reports *"binary file matches"* at
best and, piped or with `-h`, silently prints nothing at all. A scan built that way does not fail —
it produces a smaller number and a clean exit.

Two backlog claims were written from exactly that and both were false (2026-09-22):

- W256's row stated `anemone.wms` *"contains no `<equalizerSettings>` and not one `slider` element
  at all"*. It has `<EQUALIZERSETTINGS id="eq" enabled="true"/>` and **ten** `<SLIDER>` bands, and
  the row's whole "two different surfaces" framing rested on the absence.
- The same row's *"19 archives have no `<equalizerSettings>`"* is **99 of 184** when the bytes are
  read, and `object-model.md`'s *"14 name it something other than `eq`"* is **7**.

So: **decode the bytes, do not grep them.** `scripts/wmp_markup_census.sh` already strips each
`.wms` to ASCII first and is safe; for anything else use **`scripts/wms_grep.py <regex>`**, which
decodes every `.wms`/`.js` entry the way `WMPTextDecoder` does and ends on a denominator line (see
`harness/scripts.md` § *The committed scripts*). An ad-hoc scan must otherwise read the entry out of the archive in Python
(or pass `grep -a`, which is the weaker fix — it still mis-splits UTF-16). Everything in
`harness/instrument.md` § *Numbers that are void, and why* applies to anything a bare `grep` produced.

### Counting a tag across the corpus

**Check `object-model/classification.md` § *Verified **not** gaps* before you rank anything a scan turns up.** The
author-typo class there — `scrollingAmmount`, `horizontalAlignemnt`, `donwImage`, `tootip`, `hegiht`,
`visilble` — is the largest single false lead in the whole scan, and WMP ignores an unknown attribute
too, so matching one would be less faithful rather than more.

`scripts/wmp_markup_census.sh <outdir> <tag-or-attribute ...>` is the instrument, and it is the only
one to use. It matches `<NAME[[:space:]/>]`, so `VIDEO` does not catch `<VIDEOSETTINGS>`, and it
strips each `.wms` to ASCII first for the two traps in its own header comment (grep goes silent on a
UTF-16 file; a tag is spread over many lines). It reads archives through
`wmp_corpus.open_archive`, so its denominator is the full measurable corpus (179 of 180 today, the
one exclusion being `scripts/wmp_corpus_exclusions.txt`) and agrees with `wms_grep.py`. Before
W268 it used `unzip`, which refuses the two repaired-header archives, so **a census figure over 177
recorded before 2026-09-25 is two archives short** and is re-measured, not compared.

**Do not write your own scanner for this, and distrust any number that came from one.** The surface
inventory in `SKILL.md` was first measured by an ad-hoc Python scan trying `utf-8-sig`, then
`utf-16`, then `cp1252` — and **`bytes.decode('utf-16')` does not fail on Windows-1252 text**. Any
even-length cp1252 `.wms` decodes to silent garbage, so the tag is simply absent from the result:
`activate.wmz` reported zero `<EFFECTS>` elements and has one, and the corpus totals came out
**151 / 138 skins where the census says 183 / 166**. Every count was low, none was obviously wrong,
and the error was invisible until two instruments were compared. If a scan of your own is genuinely
unavoidable, decode the way `WMPTextDecoder` does — BOM first, then a **positional** BOM-less UTF-16
sniff, then Windows-1252 — and reconcile it against the census before recording a number anywhere.

**Grepping the corpus's *script text* is a different job, and the same decode trap ends it.**
Neither census reads `.wms`/`.js` as program text, so a question like "is this name ever read as a
property rather than called as a method" needs its own scan — that is the check that made W128 safe
to land. Extract with `wmp_corpus.open_archive`, not bare `zipfile` (that refuses
`Need_for_Speed_Underground.wmz` and `SplinterCellWMPSkin.wmz`, whose local headers
`WMPArchiveHeaderRepair` exists to fix, so a bare scan is **177 of 180** and every count a floor), then decode each file the way `WMPTextDecoder` does before
matching anything. The W128 scan was run twice because the first pass decoded as
`utf-8, errors="replace"`: **153 of the 392 script files are UTF-16**, they became null-interleaved
mojibake, no pattern matched in any of them, and the result — 141 uses — looked entirely plausible
beside the correct 376. The mix, for calibration: 153 UTF-16-with-BOM, 143 cp1252, 87 UTF-8, 9
UTF-8-with-BOM. **A scan of script text that did not print its own encoding breakdown has not earned
its number.**

**Three counts landed with W163–W166 came from scans of that shape**, and each states its own
denominator because none of them is a tag the census can match:

| Count | What it enumerates |
|---|---|
| **7 archives, 0 `scriptFile`** | archives shipping a `.js` that no `scriptFile` names — the shell form, and the two ways it fails silently (`LC_ALL=C`, and stripping NULs), are in `reference/loading.md` § *The script a skin never names* |
| **1 archive, 3 attributes** | `wmpprop:` bound to a colour, matching `([A-Za-z]+[Cc]olor)\s*=\s*"\s*wmpprop:` over every `.wms` — `Colorchooser` and nothing else |
| **17 views, 4 mismatched** | views declaring a literal `width`/`height` **and** a resolvable background image, with the BMP/PNG header read for its real size — the 4 are `Colorchooser`, `Cubist`, `Radio`, `Tomb Raider 2` |
| **7 archives, 58 assignments** | `\.\s*zIndex\s*=` over `.wms` **and** `.js` together, because the write is as often in an inline handler as in a program |
| **58 uses, 42 archives** | `player.network.downloadProgress` and the rest of the `<NETWORK>` member surface (W104), matching `\bnetwork\s*\.\s*([A-Za-z_]\w*)` over `.wms` **and** `.js` — the census matches a *tag* and cannot see a member read. **Split the total by resolution path before ranking it**: 55 of the 58 are `wmpprop:` bindings the registry already resolved and only 3 script reads, in one archive, reached the object model. A member count that is not split reads as 42 broken archives when it is one. Encoding breakdown 2026-09-21 over 184 archives / 400 files: 156 UTF-16-BOM / 146 cp1252 / 89 UTF-8 / 9 UTF-8-BOM |
| **970 uses, 135 archives** | `<attr>=""` — an attribute authored with an **empty value** (W241). The census matches a *name*, never a value, so this needed its own scan, and the scan needs the tag grammar rather than a flat grep: `x = ""` inside a `<SCRIPT>` body is a script assignment and not authored markup. Count attributes **inside a tag span** only, skip script bodies, and print the encoding breakdown (2026-09-20: 81 UTF-16-BOM / 75 cp1252 / 19 UTF-8 / 9 UTF-8-BOM over the 182 measured). Reconciles with the census's `flat/*.txt` to the exact total, which is the check worth repeating — the flat files keep attribute values, so grepping them is the cheap second opinion the rule above asks for |

The last is the one to copy the shape of: a property a skin writes from script is not findable by
scanning markup alone, and scanning only `.js` would have missed `Colorchooser`, whose whole
`openstatechange` handler is inline.

**Views are the one thing the census does not count**, so the per-view numbers in `reference/windows/native-windows.md`
§ *Ask what the skin provides* (595 views across 179 archives; which surface lives in which view;
`openView` targets by name) came from splitting each `.wms` on `<VIEW` with that decoder. Re-derive
them the same way and state the denominator, exactly as every other count on this page does.

---
