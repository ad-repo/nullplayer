# Bio-Nid

`Bio-Nid.wal` · 336,780 B · SHA-256 `a90c5a01…c31e71d9` · skininfo name **"T-800"**, author
"Quadhelix", version 1.0. First measured 2026-08-28 (Phase 80), from a live report:
*"bio-nid skin has 8 eq windows listed, the important window is empty and the eq's are little spiders
that dont seem to do anything"*. No `screenshot.png` in the archive despite `<screenshot>skinshot.png</screenshot>`,
so no reference exists to check semantics against.

**Not the same file as `T800.wal`**, which is in the corpus under the same author and the same
`<name>T-800</name>` (94 files / 558 KB vs 116 / 337 KB, and only this one has the spiders). Two skins
whose skininfo name is identical — go by the archive filename.

`separateWindows`. **Twelve** declared containers: `main`, `Message`, `Warp Browser`, `eq`, and
`spider1`…`spider8`, plus the synthesized playlist and library. 12 MAKI programs.

## State

The player, the equalizer and the browser window render. Everything the live report named is
explained below; two of the three were real, and Phase 80 closed both.

## The three things the report named

- **"8 eq windows listed"** — the skin declares **nine** containers whose `name` is `Equalizer`. Eight
  of them are `spider1`…`spider8`, made by copying `xml/eq.xml` into `xml/s1.xml`…`s8.xml` and editing
  only the container id. The ninth is the real one (`id="eq"`), which is *routed to NullPlayer's
  equalizer surface* and therefore correctly excluded from the skin-window section — so the menu was
  eight identical items, none of which was the equalizer. Menu labels are now qualified by container
  id **only where a name is ambiguous** (`WinampModernContainerTopology.menuLabels`).
- **"the important window is empty"** — the container is literally `<container id="Message"
  name="IMPORTANT">`, and its whole body is one `<Wasabi:TitleBox>` wrapping the desktop-alpha
  toggle the window exists to show ("THIS BUTTON MUST BE TURNED ON FOR GRAPHICS SMOOTHING"). The tag
  was unimplemented, so the box drew nothing **and its content group never entered the graph** — the
  window measured as 19 nodes of standard frame around a hole. Closed in Phase 80; see
  [../reference/rendering.md](../reference/rendering.md) → *`<Wasabi:TitleBox>` is a body, not just a
  border*. This skin is the diagnosis, and the capability reaches 9 skins / 33 declarations.
- **"the eq's are little spiders that dont seem to do anything"** — **not a defect.** Each spider is a
  150×122 window holding `player/smspider.png`, a 9×10 `<vis>` in the body (its red dots), and a close
  button. There is nothing in them to do; they are decorations to scatter on the desktop.

## Traps this skin sets

- **A redefinition that would have emptied the real equalizer.** Each of `s1`…`s8` re-declares
  `<groupdef id="eq.content.group">` **empty**, after `xml/eq.xml` defined it with all eleven sliders.
  Last-definition-wins would leave the actual equalizer window blank. It does not happen here because
  the registry is ordered — a `<group>` instantiates whatever definition of that id had been read *at
  its own position in the document* — which is exactly the case that rule exists for.
- **Half the skin's declared assets do not exist.** ~70 bitmaps (`player/main.png`, `player/lcd.png`,
  the whole `menu/` and `standardframe/` sets), `SUPERGLU.ttf` and `scripts/mytogglebutton.maki` are
  referenced and not shipped. All are optional resources, so they warn and the skin loads. Do not read
  a `resourceMissing` warning here as a finding.
- `<Wasabi:Text id="dta.text" default="    ">` — the label beside the smoothing toggle is four spaces
  in the markup. Nothing is missing when it draws nothing.

## What is knowingly missing

- The `<Wasabi:Text>` inside the title box is an inert standard-library shell, as everywhere else.
  Immaterial here (see above), material in Styx and Shield_Amp.
- Nothing beyond the harness dump and the Phase 80 fix has been measured: no live pass over the
  player's own transport, the browser window, or the eight spiders' `<vis>` boxes.
