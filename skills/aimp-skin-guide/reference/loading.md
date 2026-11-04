# AIMP loading: what is tolerated, what stays fatal

`AIMPSkinLoader.load` (`AIMPSkin.swift`) reads one archive into an `AIMPSkin`. The limits are
`AIMPSkinPolicy`; the codes are `AIMPSkinDiagnosticCode`, stable once written. A fatal finding is
thrown; a warning rides on `skin.findings`. Never relax a limit to make a skin load: argue the threat.

Every document is read through one `AIMPSkinDocuments` per load, which keeps what does not read as
a finding: nothing is dropped with `try?`. Missing is nil; there and unreadable is nil and a finding;
the caller decides whether that is fatal (`throwing`, for the main form). Every binary read goes
through one bounds-checked cursor (`AIMPSkinBytes`), every inflate through `AIMPSkinZlib` (the zlib
header checked), every `main.ini` and `.lng` through `AIMPSkinINI`.

## The codes

| Code | Fatal | Raised when |
|---|---|---|
| `AM0001` | yes | not an AIMP archive: too short, no header, no zlib body where the metadata length says |
| `AM0002` | yes | the file is over `fileBytes` (1 GB), or a `.zip` entry inflates past its declared size on import |
| `AM0003` | yes | more than `entries` (32,768) entries |
| `AM0004` | yes | an entry or header field lies past the end of the file |
| `AM0005` | yes | one entry, or a whole `.acs4` body, inflates past `inflatedBytes` (1 GB) |
| `AM0006` | yes | an image's *frame* side is over `imageSide` (16,384 px); a filmstrip's full width is not |
| `AM0007` | yes | one image alone is over `decodedPixels` (256 Mpx), from its header. Pictures decode when first drawn, and a skin keeps at most `decodedPixels` decoded at once (`AIMPSkinPixelBudget`): a decode that would pass it lets the least recently drawn pictures go, to decode again if drawn again |
| `AM0008` | **no** | an entry does not inflate, is truncated, or is not an image; or a compiled script (`FSXMLBIN`) does not decode, or has a tree the script compiler does not take: it is skipped |
| `AM0009` | if the main form | malformed or over-deep XML (`xmlDepth` 256, `xmlNodes` 1,000,000). The main form includes AIMP 3.0's `MainFrame.xml` and AIMP 2's `MainLayout.xml` and `PlaylistLayout.xml`: a malformed one is this, not `AM0010` |
| `AM0010` | yes | no `AIMPMainForm.xml`, and no AIMP 3.0 `main.ini` to build one from; a `main.ini` that is not UTF-16; AIMP 3.0 with no `MainFrame.xml`, AIMP 2 version 3 with no `MainLayout.xml` (or no `PlaylistLayout.xml` when its layout holds the playlist). Version 2 alone takes the fixed layout |
| `AM0011` | yes | a container this engine does not read (an `ACSP` version other than 2 or 3) |
| `AM0012` | yes (import) | a `.zip` import past `AIMPSkinZipLimits` (entries, total bytes, a ratio past 200:1 above 1 MiB), or a skin in it failing its CRC or size. A skin over the file limit in a zip is `AM0002` |

## Tolerated

| Input | What the loader does |
|---|---|
| `Schema.xml` missing or malformed | loads without providers or resources; the parse failure is a warning |
| An image entry unreadable | skipped with `AM0008` when its header is; pixels that do not decode draw nothing. A picture of several frames is read, the first time it is laid out, for whether its first frame is blank and its last a flat mask (`AIMPSkinPixels.flags`), and that is kept after its pixels are let go |
| An AIMP 2 bitmap whose pixel offset overshoots (1,024 bytes too far in some of the catalog's) | read from the end of the file, where its pixels are |
| DPI variants (`-120`, `-144`, `-168`, `-192`) | never decoded; the 96-DPI image is used |
| `.myimg` (older skins, Sony TC-MR2), `.bmp` (AIMP 3.0 BMP skins) | filed as `.img`; an `.img` of the same name wins, then `.myimg`. A `.bmp` is cut as its object's `main.ini` section says (`format.md` § *AIMP 3.0 BMP pictures*) |
| `.lng` files | `@Lng:N;` captions read the Mac's first preferred language the skin has a file for (`AIMPSkinLanguage`, AIMP's file names), then `English.lng` caption by caption; a key neither has reads as empty (Delphi's `ReadString` default), never as raw `@Lng:` text |
| No form documents, a `main.ini` (AIMP 3.0, AIMP 2) | the form is built from `main.ini` by `AIMPSkinLegacy` from the images' headers; AIMP 2's bitmaps are laid out (frames, stretching columns) as it reads them |
| A compiled script that does not decode or compile | left out with `AM0008`; `AIMP_RENDER_SCRIPTS` counts it as one that stops (`skin.scripts.unreadable`) |
| A script stored as Pascal source (some `.acs4` `.script`s) | not run, and not counted: the engine runs FastScript's compiled tree only |
| A dock site's frame document (`PlaylistFrame.xml`) malformed | an `AM0009` warning; the site is built as if it had none |
| A `.zip` holding two skins of one name (another folder or extension) | the first is installed, the rest left |
| A companion form missing or malformed | that window is left out; a malformed one is a warning |

## Confirm a change kept the gate

```bash
swift test --filter AIMPCorpusLoadTests
```

Confirm it took: `AIMP corpus: <n>/<n> loaded` and `0 failures`. A recorded `ok` skin that now throws
fails the suite by name (`reference/harness.md` § *The load gate and the census*).
