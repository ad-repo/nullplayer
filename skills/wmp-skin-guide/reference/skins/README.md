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
| [`plus-family.md`](plus-family.md) | **A family dossier, not a skin one** — the 13 Microsoft Plus! archives share authoring idioms nothing else in the corpus uses at any scale, and all three defects found in them so far (W146, W147, W148) were idioms rather than skins. Also records what has been ruled out, including the dancer that is not a skin asset |
| [`portals.md`](portals.md) | Three unrelated defects in one view, all live-only, and the view had never been on screen until W153 opened it. Its three `<BUTTONGROUP>`s state the mapping-mask paint rule and its own counter-example within one file |
| [`alienmorph.md`](alienmorph.md) | Four defects across the six skins that share its markup, and the corpus's densest use of a centred piece with no authored coordinate — the whole Alienware/ALX frame is built out of it (W143). Its player is healthy and all five of the windows it opens beside it were not, which is a distinction no `mainView` capture can make |

## Skins that are counter-evidence, and what each one holds

These have no dossier — they are one fact each, and the fact is that they **disagree** with a change
that looked right. Check them by name when you touch the rule beside them.

| Skin | The rule it holds down |
|---|---|
| `polygon` | `mappingColor` on a `<SUBVIEW>` with real geometry is a self-mask, not group membership. Exempting every node that declares one from layout drops its panel and moves its `returnButton` to the window corner |
| `LostPlanet` | `onLoadInfo` opens `view.width = view.minWidth`. A script-assigned view size must not replace the size alignment deltas are measured from, or its stretch tiles stop covering 61 px and punch holes through the window frame |
| `AlienMorph`, `ALXMorph`, `ALXVortex`, `AlienwareTeleport`, `Alienware_Darkstar_WMP11`, `Alienware Invader` | The mirror of `LostPlanet`, and the two must be checked together: `center` is **not** a margin. Their five auxiliary windows each centre two 175-wide side columns with no authored `top`, so offsetting a centred piece instead of computing its coordinate from the parent lands both on the corner bitmaps that carry the title bar. `LostPlanet` holds the delta form for `right`/`bottom`/`stretch`; these hold the computed form for `center` |
| `Xbox Live Skin`, `Rave-MP` | Their `remoteView`/`eqView` ask for their own canvas in script. Before the view root read its size overrides, all four of `Xbox Live Skin`'s views drew at one shared 423x343 |
| `Thomas` | Its `0 kbps` / `0%` readouts are the corpus's visible proof that `player.network.bitRate` reaches a handler |
| `Scooby-Doo_2` | Its `infoView` picks a character in its own `onLoad`, so that image differs between captures for a reason that is not a defect. The mechanism is `randomPic()` in `scooby.js` — `parseInt(Math.random() * 10)` — so it is nondeterministic by construction and **it is the only image a clean sweep moves**. Measured while landing W128: base vs change 5,522 px, and **two captures on the *same* tree 9,031 px**. Re-run the one view twice before reading it as a regression |
| `cerulean` | **`zIndex` is ordered among siblings, not flat across the view.** Its `<statusText zIndex="2">` sits inside `<subview zIndex="4">` and has to draw *over* the seek slider beside it, and its `<effects zIndex="-1">` sits under a colour-keyed hole in `face.bmp` with `<button id="bEye" zIndex="-2">` under that. Flattening the order to WMP's documented "z-order within the view" breaks the first and is not what W144 needed anyway — the answer there was `windowed`, not z |
| `Ice` | Its `videoView` authors a `<BUTTON height="144">` over a `Pl-xp.bmp` that is 196x**44**, inside a subview that draws the same bitmap as a stretched `backgroundImage` at 313x144. It is the corpus's evidence that the natural-size rule (W122) cannot be extended to background images without deciding what a stretched background does |
| `Navigator` | **A control is its artwork, not its rectangle.** Its `close`, `mcenter` and vis buttons sit in a `zIndex="-1"` subview under a `progress` slider that spans the whole player, and it cuts holes in `progress_map.bmp` exactly where they are. Any hit rule that reads the slider's rect as solid takes all five away — and it is the mirror of `Plus! Pulsar`, which needs the *ordering* half of the same fix, so check the two together |
| `holiday_skin`, `Grinch`, `Josie_and_the_Pussycats` | A fully transparent `<BUTTON>` laid over artwork the parent draws is a **hit catcher**, not a shape. Their transports are built entirely out of them — 104 controls across 21 archives — so artwork coverage must only ever subtract from a node that is opaque somewhere, never remove one that is opaque nowhere |
| `Alienware Invader`, `Radio`, `XBOX` | `<EFFECTS>` and `<VIDEO>` rank **last**, never by paint order. Their rating stars, equalizer sliders and `xDown` are all drawn over a hosted surface declared after them, and ordering that surface by its traversal position buries 58 controls across 12 archives |
| `Plus! Pulsar` (volume vs seek) | **A slider with a `value` binding to a transport path commits natively and is immune to the whole script path.** Its two arcs are identical in shape, geometry and position-map encoding; only `volume` binds `value`, and that alone is why it worked while `seek` did nothing (W151). A regression test written against a bound slider proves nothing here — 148 sliders in 112 archives take the scripted route |
| `elvis`, `Plus! HueShifter`, `Plus! Plasma Ball`, `Plus! Hard Boiled`, `Plus! SlimLine` | **`showBackground="true"` means the group's `image` is the window's artwork, not a sheet of controls.** A `<BUTTONGROUP>` is otherwise painted through its mapping mask (W154), and masking these five masks away the player body itself — `elvis` wraps its whole 335x396 body in one group. 41 declarations across 7 archives, and `Compact` is the only skin that writes the `false` default. Check them by name before touching group paint |
| `corona` | The control. Live QA has called it "works well, has all its sliders and buttons for the most part" since Phase 3, and it is the reference result every other skin is legible against |
