# Skin dossiers

One file per `.wmz` that has **taught this engine something a probe could not**, and nothing else.

A dossier is not a bug list and not a compatibility report — `WMP_TASKS.md` ranks work and
`docs/wmp-skin/compatibility.md` states the contract. A dossier answers a different question, and it
is the one that keeps costing whole sessions:

> *This skin is on my screen and something is wrong with it. What is already known about it, what
> does it exercise that nothing else does, and what has already been ruled out?*

## When to write one

Write a dossier when a skin has produced **two or more unrelated engine defects**, or one defect that
no headless probe could see. Both mean the next person looking at that skin will otherwise start from
zero. A skin that merely failed once and was fixed does not get a file; that is what the backlog
archive is for.

Do **not** write one speculatively for a skin nobody has opened. An empty dossier is worse than none:
it reads as "someone looked at this".

## What goes in one

In this order, and skip any section that has nothing measured in it:

1. **What it is** — one paragraph: the era, the shape of the player, what makes it unusual.
2. **What it exercises that little else does** — the reason it is a test case. Cite a number and the
   command that produced it.
3. **Defects it found**, each with the reported words, the cause in one sentence, and the `W` row.
   The reporter's own words are load-bearing: they are what the next report will sound like.
4. **What was ruled out** — the theories that were checked and were wrong. This is the most valuable
   section and the one most often left out.
5. **How to drive it** — the exact coordinates and flags that reach its controls, so the next session
   does not re-derive them.

Every number cites the command that produced it, per the rule in `../harness.md`. A number in prose
with no command goes stale silently and nothing fails.

## The dossiers

| Skin | Why it has a file |
|---|---|
| [`cablemusic.md`](cablemusic.md) | Nine unrelated engine defects across two reports, four of which no headless probe could see |
| [`halo-2.md`](halo-2.md) | Three unrelated app-path defects, none visible to any headless probe. The corpus's purest windowless-dispatcher skin: every window it has, including its player, arrives through `theme.openView`, and every panel opens and closes through one `toggleView` function |
| [`xsn-sports.md`](xsn-sports.md) | Four unrelated defects in one report (W144), two of which no headless probe can see — the corpus's clearest **windowed** visualization, and its only skin that slides a centred drawer by script against its own 500 ms view timer |
| [`plus-family.md`](plus-family.md) | **A family dossier, not a skin one** — the 13 Microsoft Plus! archives share authoring idioms nothing else in the corpus uses at any scale, and every defect found in them so far was an idiom rather than a skin. Also the corpus's test case for **resampling** rather than layout (W160): their photo-real bodies are where a bad upscale shows and flat art hides it. Records what has been ruled out, including the dancer that is not a skin asset, and that neither the clipping masks nor the interpolation *quality* was ever the cause |
| [`portals.md`](portals.md) | Three unrelated defects in one view, all live-only, and the view had never been on screen until W153 opened it. Its three `<BUTTONGROUP>`s state the mapping-mask paint rule and its own counter-example within one file |
| [`windows-xp-media-center.md`](windows-xp-media-center.md) | **A two-archive family dossier.** Two defects in one report (W161, W162), the first of which **no headless probe can see** — the equaliser was fully built and drawn under an opaque animation frame, so every flag answers that it works. The corpus's archetype of the one-shot GIF *terminator* (79 files, 33 archives), and one of only 7 archives that bind `wmpprop:player.status` in markup |
| [`alienmorph.md`](alienmorph.md) | Four defects across the six skins that share its markup, and the corpus's densest use of a centred piece with no authored coordinate — the whole Alienware/ALX frame is built out of it (W143). Its player is healthy and all five of the windows it opens beside it were not, which is a distinction no `mainView` capture can make |
| [`colorchooser.md`](colorchooser.md) | Four unrelated defects from one report, **two of which no headless probe could see** — and one of those, W166, is invisible to a probe *and* to the corpus sweep, because a stopped player is the one state in which this skin is correct. The corpus's oldest authoring (a March 2000 SDK sample), its only `wmpprop:` colour binding, and a `<TEXT>`-only transport whose chained geometry converges on the second transaction rather than the first — which reads as a layout defect in every render dump and is not one |

## Skins that are counter-evidence, and what each one holds

These have no dossier — they are one fact each, and the fact is that they **disagree** with a change
that looked right. Check them by name when you touch the rule beside them.

| Skin | The rule it holds down |
|---|---|
| `polygon` | `mappingColor` on a `<SUBVIEW>` with real geometry is a self-mask, not group membership. Exempting every node that declares one from layout drops its panel and moves its `returnButton` to the window corner |
| `LostPlanet` | `onLoadInfo` opens `view.width = view.minWidth`. A script-assigned view size must not replace the size alignment deltas are measured from, or its stretch tiles stop covering 61 px and punch holes through the window frame |
| `AlienMorph`, `ALXMorph`, `ALXVortex`, `AlienwareTeleport`, `Alienware_Darkstar_WMP11`, `Alienware Invader` | The mirror of `LostPlanet`, and the two must be checked together: `center` is **not** a margin. Their five auxiliary windows each centre two 175-wide side columns with no authored `top`, so offsetting a centred piece instead of computing its coordinate from the parent lands both on the corner bitmaps that carry the title bar. `LostPlanet` holds the delta form for `right`/`bottom`/`stretch`; these hold the computed form for `center` |
| `Age_of_Mythology` (both releases), `ALXMorph`, `Halo 2` | A finished one-shot GIF is only cleared when its **final image block is degenerate** (1x1, disposing to background). `Age_of_Mythology` holds the rule down inside one skin: `open_shutter.gif` carries that terminator and `close_shutter.gif` does not, ending on a full-size 80%-opaque closed shutter that must persist. Reading the disposal method alone instead matches **379 corpus GIFs** and erases `ALXMorph`'s six-frame idle logo along with them; `Halo 2` is the null case, ending on a full-size frame that is entirely the key colour and so unaffected either way |
| `Xbox Live Skin`, `Rave-MP` | Their `remoteView`/`eqView` ask for their own canvas in script. Before the view root read its size overrides, all four of `Xbox Live Skin`'s views drew at one shared 423x343 |
| `Thomas` | Its `0 kbps` / `0%` readouts are the corpus's visible proof that `player.network.bitRate` reaches a handler |
| `Scooby-Doo_2` | Its `infoView` picks a character in its own `onLoad`, so that image differs between captures for a reason that is not a defect. The mechanism is `randomPic()` in `scooby.js` — `parseInt(Math.random() * 10)` — so it is nondeterministic by construction and **it is the only image a clean sweep moves**. Measured while landing W128: base vs change 5,522 px, and **two captures on the *same* tree 9,031 px**. Re-run the one view twice before reading it as a regression |
| `cerulean` | **`zIndex` is ordered among siblings, not flat across the view.** Its `<statusText zIndex="2">` sits inside `<subview zIndex="4">` and has to draw *over* the seek slider beside it, and its `<effects zIndex="-1">` sits under a colour-keyed hole in `face.bmp` with `<button id="bEye" zIndex="-2">` under that. Flattening the order to WMP's documented "z-order within the view" breaks the first and is not what W144 needed anyway — the answer there was `windowed`, not z. **W166 does not change this** — a script-assigned `zIndex` now supplies the number, and the number is still sorted among a node's own siblings |
| `Ice` | Its `videoView` authors a `<BUTTON height="144">` over a `Pl-xp.bmp` that is 196x**44**, inside a subview that draws the same bitmap as a stretched `backgroundImage` at 313x144. It is the corpus's evidence that the natural-size rule (W122) cannot be extended to background images without deciding what a stretched background does |
| `Navigator` | **A control is its artwork, not its rectangle.** Its `close`, `mcenter` and vis buttons sit in a `zIndex="-1"` subview under a `progress` slider that spans the whole player, and it cuts holes in `progress_map.bmp` exactly where they are. Any hit rule that reads the slider's rect as solid takes all five away — and it is the mirror of `Plus! Pulsar`, which needs the *ordering* half of the same fix, so check the two together |
| `holiday_skin`, `Grinch`, `Josie_and_the_Pussycats` | A fully transparent `<BUTTON>` laid over artwork the parent draws is a **hit catcher**, not a shape. Their transports are built entirely out of them — 104 controls across 21 archives — so artwork coverage must only ever subtract from a node that is opaque somewhere, never remove one that is opaque nowhere |
| `Alienware Invader`, `Radio`, `XBOX` | `<EFFECTS>` and `<VIDEO>` rank **last**, never by paint order. Their rating stars, equalizer sliders and `xDown` are all drawn over a hosted surface declared after them, and ordering that surface by its traversal position buries 58 controls across 12 archives |
| `Plus! Pulsar` (volume vs seek) | **A slider with a `value` binding to a transport path commits natively and is immune to the whole script path.** Its two arcs are identical in shape, geometry and position-map encoding; only `volume` binds `value`, and that alone is why it worked while `seek` did nothing (W151). A regression test written against a bound slider proves nothing here — 148 sliders in 112 archives take the scripted route |
| `elvis`, `Plus! HueShifter`, `Plus! Plasma Ball`, `Plus! Hard Boiled`, `Plus! SlimLine` | **`showBackground="true"` means the group's `image` is the window's artwork, not a sheet of controls.** A `<BUTTONGROUP>` is otherwise painted through its mapping mask (W154), and masking these five masks away the player body itself — `elvis` wraps its whole 335x396 body in one group. 41 declarations across 7 archives, and `Compact` is the only skin that writes the `false` default. Check them by name before touching group paint |
| `Gorillaz` | **A tiled swatch is a ground, not a shape.** Its `noodle` view is 781x467 over a `background.gif` that is a 50x28 square of solid `#33CC66` with `backgroundTiled="true"`, keyed by `clippingColor="#33CC66"` — the author saying *my ground is invisible*, not *my window is empty*. Reading it as a container shape erased the entire skin, 143,248 px, and it was the only total loss W168 produced anywhere in the corpus. A container's background shapes its children only when untiled and authored at the node's own size |
| `YIL!OMA2K` | **Two-toned or many is the question a `clippingColor` cannot answer on its own, and this is the artwork case.** `yMain Body.bmp` is 530x440 in **34,688** colours with a 246x179 rectangle of `#6699FF` cut out for the video and a `<subview zIndex="-2">` of solid black parked behind the body to show through that hole. Shaping children by it clips the backdrop away and leaves the display empty — the W147/Cerulean inversion arriving through `clippingColor`. It is the counterweight to `Combat_Flight_Simulator_3`, whose `main_bg_mask.png` is 584x321 in three colours and *must* shape its children; check the two together |
| `Plus! Hard Boiled`, `TDK`, `elvis` | **`clippingColor` keys the clipping image, never the artwork (W169).** They are the three loudest of the class: `Egg_Body_Normal.jpg` lost 27% of its pixels to its own `clippingColor="white"` at a JPEG's 64-component tolerance, `TDK`'s dial had black holes punched through it and no transport buttons, and `elvis`'s "30 #1 HITS" was unreadable. **W160 had already measured the clipping masks and cleared them** — the *edges* were clean and the attribute was not. A node with no `clippingImage` still keys its artwork; that is 84 subviews and 26 views |
| `corona` | The control. Live QA has called it "works well, has all its sliders and buttons for the most part" since Phase 3, and it is the reference result every other skin is legible against |
