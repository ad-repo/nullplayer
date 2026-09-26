# `modernblue.wmz`

## What it is

Microsoft's own 2000-era sample: a navy orb (`myview`, 204x230, one view) with a small oval
visualizer in its display, a chrome transport arc below, and three script-sized trays that widen the
view to 425 — playlist, audio controls and video. A fourth face, `smallplayer` (112x112), is nested
in the same view and swapped in by `switchToSmall()` rather than by a view switch.

## What it exercises that little else does

- **A compact face that lives inside the player's own view, authored hidden, with children the
  play-state handler writes while it is shut.** `onPlayStateChange` sets `smplayb`/`smpauseb`
  (inside `smallplayer`) on every state change alongside `playb`/`pauseb`, so the small face's
  transport is script-shown while its container has never been. This is the case that bounds
  W263's pass-through from the side `US Army`'s `help` does not.
- **The corpus's only `<TRACKNAMETEXT>`** (1 of 179; grep over the unpacked `.wms` of
  `/private/tmp/wmp-sweep-current/corpus`).
- **Unscripted overflowing metadata.** Its artist (`artistdata`, 100 px) and title (117 px) authors
  no `scrolling`, so under WMP's default a real track name clips.

## Defects it found

1. **"modernblue is drawing a pause button on the display"** (2026-09-26). The small face's
   `smpauseb` at `47,40` drew over the large display while playing. Cause: an authored-hidden
   child shown by script escaped its authored-hidden, never-shown container (W263). Fix: a
   container the skin's own code can set visible (`WMPLoadedSkin.scriptShowableIDs`, a one-time
   scan of the scripts and the `.wms`) closes its subtree until shown; `US Army`'s `help` is only
   ever hidden and still passes through. The same rule shut `portals`' EQ drawer (`portals.md`).
2. **"midnight blue show the artist but not the track name"** (2026-09-26). `<TRACKNAMETEXT>` fell
   to `.unknown` and the node was dropped; it is now a `TEXT` (its `value` is authored).
3. **"should these marquee when they dont fit?"** — WMP's answer is no (`scrolling` defaults
   `false`); by the user's request an unauthored `scrolling` now scrolls (`rendering/text.md`).

## What was ruled out

- **Not a blanket inheritance rule.** Blocking pass-through at every authored-hidden container is
  what emptied `US Army`'s Help (counter-evidence table in `README.md`); the distinguishing fact
  is whether the skin can show the container at all.
- **Not the small face drawn whole.** `smplayb` has no script override at rest and stayed hidden;
  only the node the handler wrote escaped.
- **`Scooby-Doo_2/infoView` in the before/after sweep is noise**: its `randomPic()` picks with
  `Math.random`, and three captures gave three hashes.

## How to drive it

```bash
WMP_SKIN=/private/tmp/wmp-sweep-current/corpus/modernblue.wmz \
WMP_RENDER_HOST='playing,title=If You Want Me to Stay (Single Version),artist=Sly & The Family Stone' \
WMP_RENDER_PROBE=myview WMP_RENDER_CLOCK='0;3' WMP_RENDER_DUMP=/tmp/wmp/modernblue \
  swift test --filter WMPRenderDumpTests/testSweepsSkinOrCorpus
```

The stray pause needs `WMP_RENDER_HOST=playing` — a stopped host never runs the handler's show.
Small Player is the `minibutton` at `127,18` (`WMP_RENDER_CLICK='myview@131,22'` →
`viewSize=112x112`, `smallplayer.visible=true`). Two clocks, diffed, are the marquee's proof.
