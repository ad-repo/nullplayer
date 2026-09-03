#### Text width is a layout input, not just a drawing detail

A skin lays *itself* out from `getAutoWidth()`: ClassicPro sizes every SUI tab to
`label.getAutoWidth() + 14` and positions its five menu-bar groups by accumulating theirs. So the
script's measurement and the renderer's drawing must be the same measurement, or the skin builds
boxes that do not fit their own contents. Both go through `WasabiTextMetrics` (fonts, point-size
clamp, content resolution, width incl. `leftpadding`/`rightpadding`); it hangs off the loaded skin
because the runtime must be able to measure before any renderer exists — the dump harness runs the
scripts first.

Two auto-sizing rules in the renderer, both only when the object declares no `w`: a group with
`autowidthsource="<id>"` takes the width of the descendant it names, and a `<text>` takes its own
content's width.

> **The source's width is not the group's width** (B68). The source then resolves its own geometry
> *inside* the group, so a group sized to the bare measurement leaves the source short by whatever
> room the source keeps beside itself. The rule is that resolve, solved for the group's width, and
> `WasabiGeometrySpec.autoWidthInset(of:)` is the one place it lives — shared by the renderer and by
> `getAutoWidth()` so a script's measurement and the drawn box stay one number:
>
> - a **relative** width (`w="-14" relatw="1"`) makes the source `groupWidth + w` wide, so the group
>   needs `sourceWidth - w`. The negative `w` already states the *total* room on both sides, so `x`
>   is not added on top of it — impulse writes `w="-14"` for `x="13"`, Bio-Nid `w="-13"` for `x="5"`;
> - an **absolute** width does not depend on the group at all, so what matters is how far the source
>   reaches: `x + sourceWidth`;
> - a source that measures **nothing** leaves the group collapsed rather than sizing it to its own
>   padding. S7Reflex's config tabs are `<text default="">` filled in by a script.
>
> An inset of zero is the answer for every declaration this machinery was originally tuned for —
> ClassicPro's and stock Winamp Modern's menu bars are `<layer id="File.txt" x="0" y="0"/>`, and the
> `wasabi.titlebox.center.group` bodies are `x="0" w="0" relatw="1"` — so those are unchanged. Of 53
> declarations in 13 corpus skins, 26 name an offset source and 27 do not.

#### A `<text>`'s box bounds it vertically; horizontally its **group** does (B87)

A skin sizes its own boxes from the very measurement this renderer draws with, and then routinely
declares one *narrower* than the string it just measured. ClassicPro's SUI tab is the measured case
and it does it twice, in two independent engine versions: v1's `updateTabWidth` is
`label.getAutoWidth() + 14` around a `<text x="6" w="-15" relatw="1">`, so the label's box is always
`measurement - 1`, and v2's is `getTextWidth() + 23` around `w="-26"`, three short. Scissor the string
at its own rect and the last glyph is cut through the middle: the five cPro skins' tab strip read
`LIE PLE VII VIS BRO BPF NOV` for `LIB PLE VID VIS BRO BPR NOW`.

The group is what actually bounds it — the tab is 32 wide and hands its label only 17 of them — so a
**non-scrolling** string is clipped to the ambient clip horizontally and to its own rect vertically.
The vertical half is unchanged and load-bearing: BB27's auto-height still decides whether a line draws
at all, and a skin that stacks readouts one box apart and shows one at a time by moving their alphas
(Defix's Kbps / KHz / Channels) must not have them bleed onto each other. A **scrolling** ticker keeps
its own box on both axes, because the motion is defined against that box and a marquee let loose in
its parent would smear across the whole panel.

> **Gotcha, now historical: there were two scissors, and moving one alone did nothing.**
> `NSString.draw(in:)` lays the string out *inside* the rect it is given and cuts it there, so
> widening the context clip and leaving `drawFrame` alone produced a byte-identical render. The draw
> rect had to be widened to `max(drawFrame.width, measured)` purely to defeat that second scissor.
>
> Since the CoreText conversion (2026-09-02) a non-wrapping string is drawn as a `CTLine` from an
> origin, which has no rect and therefore no second scissor — **the widened context clip is the only
> horizontal bound, which is what this rule always meant.** The widening is gone. The rect's
> *vertical* scissor was real and is kept as an explicit clip at `drawFrame`; a 24pt line in a 16px
> box differs by ~350 pixels without it. The object's alignment is applied to the string's **origin**,
> as it already was.

This does not make text unclippable, and the difference matters for BB29 below: an `offsetx` that
pushes a caption out of its *group* still swallows it, and the early return for a string starting in
the clip's last pixel column reads `context.boundingBoxOfClipPath ∩ frame` before any of this.

Reach, measured on the corpus render sweep (441 renders, 53 skins): 433 pixel-identical, four
differing by a single antialiasing row, and Big Bento Modern's `query.pathurl` overflow caption
showing one more glyph before stopping at its group's edge.

#### Where the glyphs come from (2026-09-02)

A non-wrapping string is a **cached `CTLine`**, held by `WasabiTextMetrics.line(for:font:)` beside
the B106 width memo and built colourless so a playlist row does not need one per selection state. It
is drawn inside the local flip `drawText` already establishes — that mirror is what makes the space
y-up, because the scene's own transform is top-origin — at

```swift
baseline = drawFrame.maxY - NSLayoutManager().defaultBaselineOffset(for: font)   // cached per font
```

That offset is **TextKit's, not the font's**: at 8pt four different faces all want 8 while their
ascenders run 6.03…7.73. Two branches still use `NSString.draw` on purpose and say so in the code —
a wrapping object, whose rect *is* the line-breaking width, and a `drawFlippedText` row too long for
its column, because `.byTruncatingTail` tightens inter-character spacing before it cuts and a
`CTLine` reproduces the cut and not the tightening. See
[../performance.md](../performance.md) → *The drawing half of `drawText`* for the measurements and the
full before/after.

#### Two strings in one box is two columns, not one string

Both text paths stop at the rect they are handed — `drawFlippedText` truncates with an ellipsis,
`drawBitmapText` clips — and **neither knows what else is drawn into the same rect.** So a caller that
draws one string left-aligned and another right-aligned into the *same* box gets an overlap the moment
the first one is long: it runs to the box's right edge, and the second paints on top of its last few
characters.

That is what put ClassicPro's long playlist titles under their own running times. The playlist row is
the measured case, and `WasabiSceneRenderer.playlistRowColumns(text:duration:pointSize:)` is the
shape of the fix: measure the right-hand string with **`surfaceTextWidth`** — which resolves the font
by the same two branches `drawSurfaceText` does, so a string measured in one font and drawn in another
cannot reopen the gap — subtract it plus a two-space separator, and hand the left-hand string the
remainder. A row with nothing to show on the right keeps the whole width; reserving a column for a
time that is never drawn would cut titles for no reason.

If you add a second string to any existing box, split the rect. Do not rely on the two happening to
fit.

#### How big the font is, and which one

Three rules, all measured against Love is War Miku's shipped `screenshot.png` (a skin's own reference
render is the ground truth for this kind of thing):

- **`fontsize` is a pixel height, not a point size.** Winamp hands it to GDI as a font height and the
  em it draws is measurably smaller: `fontsize="30"` draws digits 17px tall, Arial's cap height at a
  **24pt** em, and `fontsize="10"` matches an 8pt em — the same 0.8 ratio
  (`WasabiTextMetrics.pixelHeightToPointSize`). Taken at face value every string is a quarter too big
  and overflows the box the skin drew for it: this skin's song ticker spilled its descenders onto the
  seek bar below and its `0:00` collided with the title.
- **`font=` is an id *or* a plain family name.** A skin that ships no `<truetypefont>` simply names one
  it expects the system to have (`font="Arial"`), exactly as it asks GDI. Resolving only declared
  resources drew every such string in the monospaced fallback. `bold="1"`/`italic="1"` are their own
  attributes, not part of the name.
- **Text is centred in its box**, not drawn from the top edge that string drawing starts at. On a
  30px-tall readout that is a whole line's leading; on a tight one it is the difference between a
  ticker inside its slot and one sitting on whatever is under it.
- **`valign` moves it** (Phase 38) — `top`, `center` (the default) or `bottom`, decoded by
  `WasabiTextMetrics.verticalAlignment` and applied as one
  offset down from the box's top edge (`VerticalAlignment.offset(cell:in:)`). 63 declarations across
  9 of the 17 skins, 54 of them `top`: Defix's songticker and Infoticker, every readout in Nokia
  5220's screen, multipass's whole display. The Core Text inset is **clamped at zero**, so a string
  taller than its own box starts at the top rather than above it.
  **The bitmap-font sheet path shares this**, and used to be pinned to `frame.minY` — that is
  `valign="top"` and nothing else, so every sheet-drawn readout with no `valign` (and every playlist
  row NullPlayer draws into a skin's own list) sat half a box too high. `valign` on a `<layer>` is
  inert, here and in Wasabi.
- **A spelling Wasabi does not know is not the default — it reads as `top`** (BB29). Only the
  *absent* attribute centres; `center`, `bottom` and `top` are the whole vocabulary, and anything
  else (including the empty string) falls to the top edge. This is not pedantry about one typo: a
  skin author who hit it corrected for it, so reading the value charitably breaks the skin *twice*.
  Big Bento Modern's two small clock readouts declare `valign="middle"` and `songticker.maki` then
  pushes each of them down by `y=4` — exactly `(30 - 21) / 2`, a 21px line inside a 30px box. Read as
  `center`, that nudge lands on top of a centring already done and both times sit 4px below the `/`
  between them, which declares no `valign` at all. Nine declarations corpus-wide, eight of them
  Bento's; the arithmetic is what identifies them, not the spelling.

#### A paragraph is not a line — `wrap="1"` (B91)

`wrap="1"` on a `<text>` is the Text class's **multi-line** mode: the string is broken at word
boundaries inside the object's own width, stacked downward, and it never scrolls. Until B91 the
attribute was not implemented at all, so any object carrying it drew as one line cut at its own box.
Four things follow from that and each of them was a separate way to lose the text:

- **The box is the line-breaking width.** The wrapped rect is neither widened to the measurement (the
  B87 rule above) nor shifted by the object's own alignment — the paragraph style already aligns each
  broken line inside it, and moving the rect would align the block a second time. A wrapping object
  therefore keeps its box on **both** axes, like a ticker and unlike an ordinary label: a line that
  still overruns is one unbreakable word, and Winamp cuts it there.
- **A paragraph has no ticker.** The overflow that would start a marquee is absorbed into extra lines,
  so `tickerMotion` is never consulted. A marquee running a wrapped block sideways is not a thing any
  skin asks for.
- **Its vertical `cell` is the whole block**, not one line. `valign` is applied to the measured height
  of the broken text (`boundingRect(with:options:)`), because aligning a nine-line block by a single
  line's leading centres its *first* line in the box and runs the other eight out of the bottom. That
  is exactly what Hal's Eye's credits looked like: one sentence floating in the middle of an empty
  panel.
- **`\n` in a markup literal is a line break.** XML cannot carry one inside an attribute value, so a
  skin spells it the way the MAKI compiler takes it, and `WasabiTextMetrics.unescaped` turns the pair
  back into the character (`\t` likewise). Deliberately **only** the markup literal: a string a script
  assigned already carries real newlines, since MAKI resolves its own escapes at compile time, so
  translating there would eat a backslash the script meant to keep (a Windows path in a `setText`).

**And `<Wasabi:Text>` is a wrapping, top-aligned label** — the attribute matters far beyond the skins
that spell it, because the standard widget carries it. `WasabiFormWidgets` seeds `wrap="1"` and
`valign="top"` on the substitution, which is Winamp's own definition measured from the six corpus
skins that ship a *replacement* for the tag: all six say `valign="top"` and four (Lobe, ZDL,
dreliction, and Hal's Eye by relying on it) also say `wrap="1"`. Seeded, not forced — an instance
that states either keeps its own.

Reach: 11 skins declare `wrap="1"` and 15 declare `<Wasabi:Text>`. Corpus sweep after the change:
16 of 441 renders differ, all of them config/preferences/about/message windows, and every difference
is either a paragraph that was being cut and now is not (BLAKK's About, Core-X5's Message) or a
group title moving a pixel or two up to its box's top edge.

#### A clock is a run of fields, not a string (BB29)

A time readout — `display="time"`, `timeelapsed` or `songlength`, with a colon in the value — is laid
out by `WasabiTextMetrics.clockRun`, and it is a third layout beside the plain string and the
fixed-pitch run. Three things distinguish it, and Big Bento Modern's elapsed/total line needs all
three (it is right-aligned in a box the `/` separator's own box overlaps by four pixels — flush
against the edge, the digits land on the slash):

- **The colon has a cell**, sized by `timecolonwidth` and centred in it. A skin declaring a cell
  *wider* than the glyph is moving the digits apart, not pushing the colon against the ones on its
  left — Sony Walkman, Styx, T800 and the Nokia 5220 all do, and drawing the colon at the cell's left
  edge renders them `1: 13`.
- **The leading field holds room for two digits** whether or not the value needs them, so the run is
  aligned by the widest thing it can become. A single-digit minute leaves the second digit's room
  empty rather than sitting a column further along and jumping sideways at `10:00`. `ClockRun.width`
  is what is on screen now; `ClockRun.layoutWidth` is the room, and alignment uses the second.
- **The run keeps `ClockRun.edgeInset` clear** of the edge it aligns against. Centring needs none —
  both edges are already free.

`getTextWidth()` goes through the same call, because a skin lays out everything beside a readout from
what it measures. `forcefixed="1"` still gives every glyph the same advance (the widest digit's) via
`WasabiTextMetrics.fixedPitch`, which the clock run uses per glyph when both are declared; a
`forcefixed` counter that is *not* a time display keeps the plain fixed-pitch path.

#### A bitmap font's `file=` is an id **or** a path

`<bitmapfont file="…">` is written both ways and a skin picks one freely: the stock Winamp Modern skin
names a previously declared `<bitmap>`, MMD3 names a path inside the archive
(`file="player/tickerfont2.png"`). The loader resolves the path form into `logicalFile` and simply
registers without one when that fails, so the identifier form still resolves through the registry;
`WasabiResourceCache.fontSheet(for:)` tries both, in that order, and applies the font's own
`gammagroup`.

> **Gotcha:** a font with no sheet draws *nothing at all* and records no diagnostic, so the failure
> looks like "this skin has no text" rather than a missing resource. Supporting only the identifier
> form silently removed every string MMD3 draws — song title, time, KBPS, KHZ, crossfade — while the
> compatibility report stayed clean.

The glyph map is Winamp's fixed three-row sheet layout. The two trailing spaces on row 0 are
load-bearing: they map the space character onto a blank cell instead of onto the fallback glyph (0, 0).

#### And a bitmap-font clock's colon has a cell of its own

`timecolonwidth` is not only the Core Text path's business (BB29 above). A bitmap font is a
**fixed-pitch atlas**, and its colon is the one glyph a sheet routinely inks into only part of its
cell — so advancing the whole cell leaves the remainder as a gap *before the seconds*, which is what
`WasabiSceneRenderer.drawBitmapText` did until this was fixed. ClassicPro's `numfont.png` is 15px per
glyph with its colon in the leftmost **6**, and the engine says so on the object:

```xml
<bitmapfont id="player.bitmapfont.nums" file="player.bitmapfont.nums.source"
            charwidth="15" charheight="31" hspacing="0" vspacing="-2"/>
<text id="SongTime" font="player.bitmapfont.nums" timecolonwidth="6" display="time" .../>
```

Reported live 2026-09-03 across the cPro family — *"there is a space between the : and the seconds"* —
and the readout drew `1:03: 16`, nine pixels of empty cell per colon.

- **The colon advances by its declared cell; every other glyph keeps `charwidth + hspacing`.** The
  glyph is **cropped** to that cell rather than centred in it, because a sheet's ink is at the cell's
  left edge — which is also what the Core Text path's per-cell clip does with a `timecolonwidth`
  narrower than the glyph. Every corpus case declares a cell narrower than the atlas advance, so the
  two paths never disagree in practice.
- **Only a clock reads it** (`WasabiTextMetrics.bitmapColonWidth`, gated on the same
  `display=` set as `clockRun`), so a label carrying a stray `timecolonwidth` is still one
  fixed-pitch run.
- **`width(of:)`'s bitmap branch sums per-glyph advances** for the same reason `getTextWidth()` goes
  through `clockRun` on the other path: a skin lays out the total time from what it measures, and a
  measurement that kept the full-cell advance would put the separator nine pixels off the readout.

Reach: the **whole cPro family**, through the engine, plus Enkera, TRON Legacy and impulse — the
corpus's other bitmap-font clocks that declare a colon cell (9 or 11px atlas advance against a 5, 6
or 7px colon). Everything else declares its `timecolonwidth` on a TrueType font and was already
right. Pinned by `WinampModernBitmapClockTests`, which draws a synthetic atlas of the engine's own
geometry and reads the run back column by column — an *extent* cannot see a gap inside a run.

#### What a `<text>` shows

Resolution order in `WasabiTextMetrics.content` — and `getText()` answers with the same string,
because `songinfo.maki` reads a text object back out and tokenises it:

1. a script's `setAlternateText`, while it is non-empty — an **override** (MMD3 puts its SEEK, VOLUME,
   BASS and TREBLE readouts on the song ticker this way). `setText` clears it, which is how a skin
   takes it back down a second later.
2. the `display=` binding (below), else a `songticker`'s implicit track title, else `text`/`default`.
3. the XML `alternatetext` attribute, when everything above is empty — a **placeholder**, not an
   override. These are stored apart (`WasabiTextMetrics.scriptAlternateTextKey`) precisely because
   they are different things: promoting the declared one to an override pinned MMD3's whole display
   to its shipped placeholder, "updating songticker", for the entire session.

A script measures the same strings two ways, and the difference matters: **`getAutoWidth()`** is how
wide the object *wants to be* (a named `autowidthsource` plus that source's inset, else a declared
`w`, else its artwork, else its text), while **`getTextWidth()`** is how wide the string it currently shows actually draws. Skins
compare them — `if (t.getWidth() < t.getTextWidth()) t.hide(); else t.show();` — to decide whether a
caption fits. `getAutoHeight()` is `getAutoWidth`'s vertical twin, resolved from the same three
sources plus a one-line font height for text.

`display=` values, all of them measured demand from the installed corpus:

| Binding | Answers | Note |
|---|---|---|
| `time`, `timeelapsed` | `currentTime` as `m:ss` | the same value under two spellings; both ship |
| `songlength` | `duration` as `m:ss` | |
| `songname` | `trackDisplayTitle` | "Artist - Title" — what Winamp calls the song *name* |
| `songtitle` | `trackTitle` | the title **alone**, a different field from `songname` |
| `songartist`, `artistname` | `trackArtist` | |
| `songalbum` | `trackAlbum` | |
| `songbitrate` | `bitrateKbps` | a bare number; the skin draws its own `KBPS` label |
| `songsamplerate` | `sampleRateHz` in **kHz** | Big Bento gives the field 35px — "44", never "44100" |
| `songinfo` | `songInfoText` | the **stream info** line, not the artist/album |
| `PE_Info` | the playlist status line | matched by `display=` *or* `id=` — see above |

`timerhours="1"` on a clock readout widens it to `h:mm:ss` past the hour; without it a 93-minute set
reads `93:20` in a box the skin sized for `1:33:20`.

Everything else falls through to `text`/`default`, which is what makes an unmapped binding degrade to
the placeholder the skin ships rather than to a blank. See
[Track metadata](#track-metadata-the-skins-actually-read) for why the shape of `songinfo` matters.

#### A `<text>` with no `h` is one line tall (BB27, 2026-08-25)

A `<text>` that declares no height at all sizes to the height of the font it draws in. It is not a
degenerate case: Big Bento's notifier declares all three of its readouts that way
(`<text id="title" w="0" relatw="1" fontsize="46">`), and so do skins across the corpus.

The geometry resolver defaults a missing dimension to the object's **intrinsic size** — artwork for a
layer, a frame for an animated layer, `autowidthsource` or its own text for a width. A `<text>` had
no intrinsic *height*, so it fell through to 0 and the renderer's `context.clip(to: frame)` erased it.
The height it takes now is `WasabiTextMetrics.lineHeight(of:)`, which is the same number
`getAutoHeight()` answers — so the box a script measures and the box we draw cannot drift apart.

> **Gotcha:** this is the fix for text that *overlaps the row beneath it*, not only for text that
> does not appear. Before it, `setNotifierText` pasted `ceil(fontSize * 1.4)` onto the notifier's
> text objects so that something would draw; 1.4 × 46 is 65 where the skin spaced its rows 42 apart,
> so the title ran down through the artist. A per-surface height guess anywhere else in the engine is
> the same bug waiting to happen — auto-sizing belongs here, in the intrinsic-size rules.

Only `<text>` auto-sizes vertically. Everything else with no `h` keeps taking its height from its
artwork or from nothing, which is what the corpus is laid out against.

#### A container's `x`/`y`/`w`/`h` are its window's (BB27, 2026-08-25)

Every other object's geometry is read back out of the graph when the scene is next drawn, so writing
the attribute is the whole job. **A container is not drawn.** Its size lives in the window and its
position on the desktop, and both are the host's to set, so the two ways a script asks for either
have to be forwarded rather than stored:

- `container.resize(x, y, w, h)`
- `setTargetX/Y/W/H` + `gotoTarget()`, per animation tick and at the instant path

`WinampModernScriptRuntime.applyContainerGeometry` is called from both and splits the request in
two: the size through `layoutResizeRequested` (the same callback a layout resize uses, keyed by the
container's id), the origin through `containerMoveRequested`. The controller answers the second by
setting that window's frame origin — **Winamp's screen space is top-left origin**, the space
`getViewportWidth`/`getViewportHeight` answer in, so the y flips into AppKit's. It is in screen
points, not skin pixels: the script derived it from the viewport rather than from the scene, so UI
Size does not enter into it. Clamped to `visibleFrame`, because Winamp's viewport excludes the
taskbar and ours does not — a toast that puts itself two pixels above the bottom of the screen would
otherwise land under the Dock.

Dropping these is a silent failure with a very misleading shape: the skin's script runs clean, every
handler counts, `RENDER_PROBE` shows the layout it addressed laid out perfectly, and the window on
screen is untouched.

#### `offsetx` / `offsety` move the string, not the box

A `<text>` can shift its own drawing without moving its rect. The box still measures, hit-tests and
**clips** where it was declared, so a large enough offset pushes the string entirely out of view —
which is not a degenerate case but the mechanism a skin uses. Big Bento Modern's SUI tab captions are
`offsetx="35"`: in the icons+text tab mode that clears the 40px icon, and in the icons-only mode
(a 40px-wide strip) the same 35 puts the caption outside the clip. Ignoring the attribute drew every
tab's caption straight over its own icon.

**A string whose origin lands in the clip's last pixel column is not drawn at all** (BB29). Bento's
caption starts on column 39 of that 40px strip, so the clip leaves exactly one column: a glyph with no
left side bearing (`V`, `W`) painted one bright column beside its icon plus one of antialiasing, and
because the amount depends on each caption's first letter the strip looked *notched*, differently on
every tab. One column of a 24px letter is never information — it is the fringe of a string the clip
was meant to swallow — so a left-aligned, non-scrolling string with `drawFrame.minX >= visible.maxX-1`
returns early (`visible` is `context.boundingBoxOfClipPath ∩ frame`, read before the flip). Measured
on the corpus: 310 images, 305 identical, the 4 Bento `main-normal`s the fix, Anexa's nondeterministic
`main-shade` discounted.


## `forcefixed` reserves a width; it does not monospace the glyphs

The reservation is the point: it stops a readout's box jittering as the digits change. The string
itself is drawn with the font's own advances, from the reserved room's aligned edge —
`WasabiTextMetrics.fixedPitch` still supplies the *measurement*, so `getTextWidth()` and any box a
skin sizes from it are unchanged.

Drawing each glyph centred in a widest-digit cell was the earlier reading, and cPro2 Dark Aluminum
rules it out on evidence rather than taste. `info-text.m` places the total time at
`trackTime.getTextWidth() - 4 + 21` while the elapsed time sits at `x = 21` — a deliberate 4px tuck
into the elapsed time's *reserved* box, so the two boxes overlap by 4px **whatever** the measurement
returns. (Widening the cell only slides the whole group left; it cannot open the gap. That was tried,
and reverted.) Under cell drawing the final digit fills its cell, the ink runs to the box edge, and
the `/` lands on top of it for *every* value and *every* cell width — clearing a 4px tuck by centring
would need a cell 8px wider than the glyph on each side. The archive's own `screenshot.png` shows
`2:16 / 3:56` with a clear gap. Only a proportionally drawn string inside a fixed reservation
produces it.

**A clock run is unaffected and must stay that way.** `display="time"` / `timeelapsed"` / `songlength`
goes through `clockRun`, which keeps its per-field cells — that is what holds Big Bento Modern's
digits in their columns across 9:59 → 10:00, and it is a separately measured case. The corpus check
is Ebonite_2_1, whose `1 : 13` clock is byte-identical across this change while its `khz :44` label
became `khz:44`: the colon had been forced into a digit-width cell and floated off the word it
belongs to. Shield_Amp's `kbps :320` → `kbps: 320` is the same correction.

**Beware `display=` that is not a display binding.** ClassicPro's `<TextSettings>` uses `display` as a
right-margin *number* (`display="4"` = "move the text 4px away from the right side") and reads it back
with `getXmlParam("display")`. So a ClassicPro time readout is `forcefixed` but is **not** a clock
run, and anything keyed on `isClockDisplay` will not see it.
