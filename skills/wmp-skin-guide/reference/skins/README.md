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

## Skins that are counter-evidence, and what each one holds

These have no dossier — they are one fact each, and the fact is that they **disagree** with a change
that looked right. Check them by name when you touch the rule beside them.

| Skin | The rule it holds down |
|---|---|
| `polygon` | `mappingColor` on a `<SUBVIEW>` with real geometry is a self-mask, not group membership. Exempting every node that declares one from layout drops its panel and moves its `returnButton` to the window corner |
| `LostPlanet` | `onLoadInfo` opens `view.width = view.minWidth`. A script-assigned view size must not replace the size alignment deltas are measured from, or its stretch tiles stop covering 61 px and punch holes through the window frame |
| `Xbox Live Skin`, `Rave-MP` | Their `remoteView`/`eqView` ask for their own canvas in script. Before the view root read its size overrides, all four of `Xbox Live Skin`'s views drew at one shared 423x343 |
| `Thomas` | Its `0 kbps` / `0%` readouts are the corpus's visible proof that `player.network.bitRate` reaches a handler |
| `Scooby-Doo_2` | Its `infoView` picks a character in its own `onLoad`, so that image differs between captures for a reason that is not a defect |
| `Ice` | Its `videoView` authors a `<BUTTON height="144">` over a `Pl-xp.bmp` that is 196x**44**, inside a subview that draws the same bitmap as a stretched `backgroundImage` at 313x144. It is the corpus's evidence that the natural-size rule (W122) cannot be extended to background images without deciding what a stretched background does |
| `corona` | The control. Live QA has called it "works well, has all its sliders and buttons for the most part" since Phase 3, and it is the reference result every other skin is legible against |
