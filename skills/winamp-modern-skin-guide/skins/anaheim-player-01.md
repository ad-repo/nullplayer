# Anaheim Player 01

**Archive:** `Anaheim_Player_01.wal`
**Layouts:** `normal` (240×260), `mini` (260×130) — both `desktopalpha="1"`
**Background:** 400×400 shared bitmap (transparent outside artwork)

## Status

| Feature | Status | Notes |
|---------|--------|-------|
| Gamma (black templates) | **Fixed** | The skin's own `boost` attribute selects the model: 57 of 65 groups are `boost="1"` → additive. A global additive model washed out Anexa/MMD3; a global multiplicative one left Anaheim black-on-black. See `reference/rendering/colour.md` → Colour themes |
| Palette text colors | **Fixed** | `studio.*`/`wasabi.*` chains before `pledit.*` fallbacks |
| Mini hover controls | **Fixed** | `setTargetSpeed(0)` instant snap + alpha inheritance |
| Mini drawer (MiniTicker) | **Fixed** | `gotoTarget` alpha default bug — unset `targeta` defaulted to 0 |
| VisAnime (VU meter) | **Works** | AnimatedLayer driven by VU meter script (`vis_mini.m`) — body morphs with music |
| Mini ticker text | **Works** | `Mini.3Tickers` group — track title scrolling |
| Body colour (10 bodies) | **Fixed** | B134 — the mini body stayed white because BB37's layout gate reached across containers. See `reference/scripting.md` → *`getLayout()` answers NULL* |

## Skin patterns

**Hover-to-reveal controls.** `mini_mainbtns.m` / `mini_tickerbtns.m` set the control group to
`alpha=0` at load. `OnEnterArea` on each button/wheel calls `setTargetA(255); setTargetSpeed(0);
gotoTarget()` (instant show). `OnLeaveArea` calls `setTargetA(0); setTargetSpeed(0.5); gotoTarget()`
(fade hide). Requires speed=0 snap + alpha inheritance to work.

**One script, two windows.** `BodyColor.m` lives in the **Skin Options** window (`Page2`, the Colors
page) and drives the body colour of the **player**: the gear's left click steps `curBody` 1→10 and its
right click opens the named menu (white, grey, green, blue, pink, gold, red, black, x-ray, neon), and
each pick writes two `setXMLParam("image", …)` calls — `NormalBody` in `main/normal` and `VisAnime` in
`main/mini`. The pair is the point: both windows are meant to wear the same body. It resolves them
once in `onScriptLoaded` from `getContainer("main").getLayout(…)`, so anything that makes either
lookup answer NULL silently drops that window's half and leaves it on its markup default — `MiniBody1`
for the mini window, which is the **white** body (B134). `curBody` persists as `lastcurBody`.

Note the mini layout's `VisAnime` is the *body itself*, not a decoration: `vis_mini.m` drives the same
object as a VU meter by frame, over whichever `MiniBody<n>` strip BodyColor selected. Two scripts in
two different windows own one object, one choosing its artwork and the other its frame.

**Drawer slide.** `drawer.m` toggles MiniTicker between `y=140` (below the 130-tall canvas = hidden
by clip) and `y=45` (inside canvas = visible) via `setTargetSpeed(0.7); gotoTarget()`. DrawerValue
layer stores the open coordinates (`x="0" y="45"`). State is persisted via `getPrivateInt` /
`setPrivateInt`.

## Traps

- Background.png is 400×400 but both layouts declare smaller w/h. Do NOT extend the canvas to the
  background size — the canvas clip is what hides MiniTicker at its closed position (y=140).
- `Drawer` layer inside MiniTicker has `alpha="1"` (near-invisible) with `sysregion="1"` — it shapes
  the window, not a rendering bug.
- Two objects share the id `VisAnime` — the normal layout's EarVis animation and the mini layout's
  body. A lookup that is not scoped to a layout gets the wrong one.
- Almost every themed asset is a **pure-black PNG with an alpha mask** (`MiniControlWheel.png`,
  `MiniTickerBtns.png`, `MiniBodyBtn.png` all have max RGB 0), and every `<color>` in
  `studio-colors.xml` is `value="0,0,0"`. All of the colour comes from `boost="1"` gamma offsets. If
  this skin ever goes black-on-black again, check the gamma model before anything else — `MiniBody1`
  (`gammagroup=""`) is real artwork and will still render, so the window looks *mostly* fine while
  every control and label is invisible.
