# The Plus! family

A **family dossier**, not a skin one — the exception the README's "one file per `.wmz`" rule earns,
because every defect found in these archives so far has been an *idiom* shared across several of
them rather than a property of one. A reporter's instinct on 2026-09-12 named it before the engine
did: *"all plus skins seem to have unique issues I suspect they are a different sub family of
skins"*. That is correct, and this file is what it costs to not rediscover it.

## What it is

The 13 archives shipped with **Microsoft Plus! for Windows XP** and **Plus! Digital Media Edition**
(2002), against the WMP 8/9 skin SDK. Installed corpus:

```
Plus! Aquarium      Plus! Hard Boiled    Plus! Nature       Plus! Pulsar      Plus! Space
Plus! Bionic Dot    Plus! HueShifter     Plus! Plasma Ball  Plus! SlimLine
Plus! da Vinci      Plus! Mecha          Plus! Professional Plus!_The_Bionic_Dot
```

`Plus! Bionic Dot` and `Plus!_The_Bionic_Dot` are **two archives of the same skin** (`bionic.wms`,
268 entries; `bionic_d.wms`, 240). A count of "skins affected" that treats them as two is inflated by
one; a fix must still be verified against both, because their node numbering differs.

**All 13 load.** Measured 2026-09-12 with `WMP_SKIN=<corpus dir>`, every one parses
`utf16LittleEndian` and renders every view it declares.

### Two sub-shapes inside the family, and they behave differently

| | Single-view | Multi-view |
|---|---|---|
| Archives | Aquarium, da Vinci, Hard Boiled, HueShifter, Nature, Plasma Ball, SlimLine, Space | Bionic Dot (×2), Mecha, Professional, Pulsar |
| Views | 1–2 | 3–5 (`mainView`, `plView`, `videoView`, `eqView`) |
| Nodes | 53–83 | 137–271 |
| `<EFFECTS>` tag | `WMPEFFECTS` | `EFFECTS` |
| View ids | `view-2`, `eggSkin`, `BubbleSkin`, `hueshifterSkin`, `perfectSkin` | `mainView` + siblings |

**Both spellings of the effects tag live in this family**, which is worth knowing before grepping:
`WMPElementKind` once mapped only `wmpeffects`, and the 166 archives spelling it the other way fell
to `.unknown` and were never widgets (W101).

## What it exercises that little else does

- **Panes hidden by a fade rather than by `visible`.** 7 widget elements in 6 archives sit inside a
  fully transparent subtree; 5 of the 6 are Plus!. Nothing else in the corpus hides a hosted surface
  this way at any scale. Command: see *Fading* below.
- **Containers that shape their children by a mask instead of occluding them with paint.** 2 of the
  corpus's 30 keyed `<EFFECTS>` containers carry a third pixel state, and **both are Plus!** —
  `Plus! Bionic Dot`'s `main_vis_back.png` and `Plus! Professional`'s `vis_mask_s.png`. The family
  names the asset outright: `Egg_Body_Mask.gif`, `body_Mask.gif`, `green_body_MASK.gif`,
  `perfect_tray_shape_mask.gif`, `vis_mask_s.png`.
- **Photo-real bodies whose detail is baked in at a few pixels each.** This is why the family is
  the corpus's test case for *resampling* rather than layout (W160): flat cartoon art survives a bad
  upscale and a specular highlight does not. The reporter's list — Hard Boiled, HueShifter,
  SlimLine — is the same list any resampling change should be re-checked against, on a Retina
  display and never from a 1x render dump.
- **A player state handler that answers by *playing*.** The single-view sub-shape's
  `OnOpenStateChange` ends its `osMediaOpen` arm in `player.controls.play()`, so this family is the
  corpus's detector for a host event raised on the wrong edge: everywhere else a spurious
  `openstatechange` repaints a readout and nobody notices. Three archives (W170).
- **Stacked full-body colour variants cross-faded by script.** Bionic Dot carries seven complete
  `main_body_<colour>.png` bodies plus matching button sets and frame rings, switched by
  `switchThemes(themeID++)` writing `alphaBlend` on each. This is the same mechanism `xsn_sports`
  uses for its window ring (W145) and it is not unique to that skin.

## Defects it found

### W146 — a faded-shut pane was hosted anyway

*"bionic dot spectrum is displaying as rectangle on top of the player and look bad it should be
layered in the opening"*. `alphaBlend` inherits and paint honoured it; hosted `NSView`s did not.
Archived in `docs/wmp-skin/wmp-backlog-archive.md` § *Phase 21*.

**The family-wide shape:** `Plus! Bionic Dot` (×2), `Plus! Professional`, `Plus! HueShifter`,
`Plus! Plasma Ball`, `Plus! Pulsar`, and the non-Plus! `Halloween` — which is almost certainly a
Bionic Dot derivative, on the evidence of an identically named `visMask`/`visEffects` pair.

### W147 — the visualizer was clipped to a rectangle, not the lens

*"the spectrum is just slapped on top of the UI covering controls"*. Same archive entry. The rule
that came out of it is in `../rendering/hosted-surfaces.md`, and **the guard on it
is Cerulean** — a two-state keyed container means the opposite of a three-state one.

### W148 — the controls hovered and did nothing

*"plus pulsar skin seems to ignore most clicks despite showing hover graphics"*. Reported
2026-09-12 against `Plus! Pulsar`; the cause was engine-wide and the family was where it showed.
Archived in `docs/wmp-skin/wmp-backlog-archive.md` § *Phase 22*.

`Pulsar` authors its equalizer, playlist and three visualization buttons as one `<BUTTONGROUP>` in a
`<SUBVIEW zIndex="10">`, and drops a `<CUSTOMSLIDER zIndex="55">` on either side of it inside
`<SUBVIEW zIndex="5">` siblings whose 79x136 rects cover the group completely. Hit testing sorted a
*flat* list by the authored `zIndex`, so `55 > 0` gave all five clicks to a slider — and every
contested pixel of `vol.png`/`seek.png` is `#ff00ff`, so the slider is not even drawn there.

**The family-wide shape:** 7 of the 13 archives gained controls — `Pulsar` 3, `HueShifter` 5,
`Bionic Dot` (×2) 1 each, `Plasma Ball`, `Professional` and `SlimLine` 1 each. Corpus-wide it is
**103 controls across 32 archives**, so this is an idiom the family shares rather than owns; the
worst-hit skins are not Plus! at all (`Beck` 16, `Spider-man` 13).

**The reporter's instinct was right a second time** — *"you might want to test other plus skins for
the same defect"* — and the instrument that answered it is `WMP_RENDER_OCCLUDED=1`, written for this
report because no existing probe could see the class. `starved.tsv` ranks views that failed to *lay
out*; `Pulsar/mainView` lays out completely and its `RENDER-DUMP` line is healthy. A fully resolved
view whose controls are buried reads as a pass in every count the harness had.

### W150 — the seek arc, and the square it lives in

*"the seek area does not work properly"* and *"there is also a clickable artifact to the right of the
seek that does nothing"*. Reported 2026-09-12 against `Plus! Pulsar` immediately after W148, and it
is three defects in one control. Archived in `docs/wmp-skin/wmp-backlog-archive.md` § *Phase 22*.

`seekMain` and `volume` are **diagonal arcs inside 79x136 squares**, and only 29% of each square is
the control. `seek_map.png` marks the other 66% as opaque `#ff00ff`, which `WMPPositionMap` averaged
into a fraction of `0.667` — so a click anywhere in the dead corners seeked to 67% of the track.
W148's coverage then derived the arc's region from `seek.png`, which is a **13-frame filmstrip**, and
lost 577 pixels of the arc's own soft edges (551 on volume). And the cursor rect and the tooltip
fallback both still covered the whole square, so it kept a hand cursor and a "Seek" tip over pixels
that hit nothing — the "clickable artifact".

**Both arcs are the same shape, so check the volume control whenever the seek one moves.** They are
mirror images with the same map encoding, and every measurement above has a volume twin.

### W151 — the seek snapped back on release

*"seek is still not working"*, then *"it snaps back when you release the mouse"*, and the sentence
that found it: *"the volume is fine and has the same control shape"*. Archived in
`docs/wmp-skin/wmp-backlog-archive.md` § *Phase 22*.

**Not a Plus! defect at all — 148 sliders across 112 of the 180 archives** have the shape, and
Pulsar is simply where it was looked at. Any slider whose `max` binds to
`player.currentMedia.duration` receives an *implicit* `value` binding to
`player.controls.currentPosition` (W128), which settles on every transaction — including the one the
release raises, which is where a skin like this one reads the control back:
`onmouseup="player.controls.currentPosition=seekMain.value;"`. Dragged to 521 s, it committed 18.95 s
— the live position — so the audio never moved and the thumb snapped back to the truth.

**Why `volume` was fine on an identical arc:** it carries
`value="wmpprop:player.settings.volume"`, so `performSlider` commits it natively through
`WMPTransportAction.boundAction` and never goes near the script. **A bound slider cannot reproduce
this**, and most of the corpus binds — reach for an unbound one when testing this path.

**The two arcs are mirror images, so check volume whenever seek moves**, and vice versa.

### W160 — the artwork looked low resolution

*"several of the plus skins have a low res look to the grapics, plus hard boiled, plus hue shifter,
plus slimline"*, and then, against the first fix: *"it does not look better. can the lines be
crisp?"*

**Not a property of these skins' artwork, and not a resolution problem at all.** Their art is 1x
like the whole corpus — `Plus! Hard Boiled`'s `Egg_Body_Normal.jpg` is 190x253 drawn into a 190x253
subview, and `New Super Mario Bros`, which the reporter had open beside it and did not complain
about, is 582x435 art in a 582x435 view. Identical density. What separates them is *content*: the
Plus! family's bodies are photo-real JPEGs with specular highlights and glyphs baked in at a few
pixels each, and a 2x bilinear upscale destroys exactly that. Flat cartoon art survives it.

**The engine's side of it** was one hardcoded constant: `WMPSceneBuilder` passed
`interpolation: .low` for every image, so on a Retina display every bitmap took a bilinear 2x
upscale. Classic (`SkinRenderer`) and Winamp Modern (`WasabiBitmapInterpolationPolicy`) had both
already decided this question for their own 1x artwork; the WMP engine was the only one that had
not. The fix and its three conditions are in `../rendering/artwork.md`.

**The first fix was wrong and the reporter's second sentence is why.** Matching the other two
engines means `.none` — crisp pixel-doubling, which is right for the pixel art those engines were
built for and merely *blocky* on a photograph. Neither filter CoreGraphics offers is acceptable
here, which is what moved the resample out of the draw and into Lanczos.

**Three numbers worth keeping**, each of which corrected a version of the fix that looked right:

| Version | Views moved at 1x, of 535 |
|---|---|
| `.none` at any integer scale, `.high` otherwise | 159 |
| same, fallback left at `.low` | 148 |
| + destination must be the bitmap's authored size | 146 |
| + destination must land on the pixel grid | **8** |

The last 8 are four at `maxdelta=1` over 2–5 px, `Scooby-Doo_2/infoView` (nondeterministic by
construction — see the README's counter-evidence table), and three genuine sharpenings with no
geometry shift (`Television`, `Erektorset`, `Crystalball`).

**Two implementation traps, both paid for.** Core Image was the first backend and failed twice for
real reasons: `CILanczosScaleTransform` treats everything outside the source extent as transparent
black and bleeds it inward — it turned the render fixture's opaque corner to `alpha=155` and would
have haloed every sprite in the corpus — and a retained `CIContext` costs a file descriptor, which
`testHundredRapidLoadsViewsResizesAndCacheTeardownRemainBounded` counts and failed on. vImage has
neither problem. Then the sharpen kernel was first written with a divisor of 1, an effective amount
of *four*, and Hard Boiled came back ringing with white halos on every bevel. It is now 3/16;
6/16 still speckled the smooth light band, which is JPEG noise being amplified.

### W167 / W168 / W169 — the gray box, and a quarter of the egg

Three independent defects in one report, opened *"combat flight simulator and plus plasma ball have
a gray box background I suspect should not be showing"* and closed *"this is a huge improvement"*.
The rules are in `../rendering/keys-and-shapes.md`; what the family contributes is
the reach, and the reason two of the three were invisible for a whole phase.

**W167 — `clippingColor="auto"`.** `Plus! Plasma Ball`'s `mainButtons` and `playListPanel` are two of
the corpus's four `auto` declarations. The parser rejected the word, so `screen_MASK.gif` cut
nothing, and `screen_normal.jpg` — the whole player drawn against a flat `#9FA8AD` surround — was
painted opaque over the plasma globe. **The globe had never been on screen.** The skin's four other
layers state `clippingColor="white"` by hand over masks that are white at 0,0; the two that write
`auto` sit over masks that are white at 0,0 as well, which is what makes the corner rule measurable
rather than a guess.

**W168 — a container's shape did not reach its children.** Not a Plus! defect —
`Combat_Flight_Simulator_3` is the archive that showed it — but `Melvin`'s eye sockets are the same
rule, and the two guards on it (`Gorillaz`, `YIL!OMA2K`) are in the README's counter-evidence table.

**W169 — `clippingColor` was keyed out of the artwork too, and this is the family's own defect.**
Share of each bitmap turned transparent, measured by keying every node's artwork against its own
declared clipping colour at the format's tolerance:

| Skin | bitmap | eaten |
|---|---|---:|
| `Plus! Plasma Ball` | `eq_panel_normal.jpg` | 85.7% |
| `Plus! HueShifter` | `hueshifter_top` / `_right` / `_left.bmp` | 76% / 75.7% / 75.5% |
| `Plus! Plasma Ball` | `playlist_vid_panel.jpg` | 57.6% |
| `Plus! SlimLine` | `perfectV_progressbar.jpg` | 54.3% |
| `Plus! SlimLine` | `perfect_body_normal.jpg` | 47.5% |
| `Plus! Hard Boiled` | `Egg_Arm.jpg` | 39.5% |
| `Plus! Hard Boiled` | **`Egg_Body_Normal.jpg`** | **27%** |
| `Plus! HueShifter` | `eq_tray_normal.jpg` | 26% |

The reporter's list for W160 — *"plus hard boiled, plus hue shifter, plus slimline"* — is exactly the
list here, and **it was never a resampling problem.** `Egg_Body_Normal.jpg` is the bitmap that commit
is named after. Outside the family the same defect held `TDK`'s transport buttons (`info_bg.jpg`
52.1%, `main_bg.jpg` 20.8% — its dial had black holes punched through it) and `elvis`'s
`elvis_tray.jpg` (39%; "30 #1 HITS" was unreadable and his shirt and shoes were gone).

**What this cost, and the process lesson.** W160 measured the clipping masks, found their *edges*
clean, and wrote the masks off in `Ruled out` — and the attribute went on deleting a quarter of the
egg for another two days. A mechanism cleared is not an attribute cleared. The instrument that
finally named it was neither a probe nor the sweep: it was decoding each archive's artwork and
counting how much of it matched its own declared key.

### W171 / W172 / W173 — the green section, and the button the skin is named after

Three defects behind one screenshot, opened *"Plus! HueShifter has a green section"* and then
*"is it supposed to be green or not because it still is"*. **The reported colour was not one of
them.** The rules are in `../../SKILL.md`; what the family contributes is the ground truth and the
reason the answer took a measurement rather than an opinion.

**The green is the artwork, and the skin ships the proof.** `hueshifter_final.jpg` is a 600x600
picture of the skin drawn by its own authors, with every tray open. Cropped at the coordinates the
markup puts `botCandy` in that state — `videoTray` 205,232 plus `botCandy` 3,222, so
`(208,454)-(396,537)` — it is `hueshifter_bottom.bmp` pixel for pixel: the same saturated green, the
same black wedges in the upper corners, the same yellow highlight at the bottom centre.
`shift_parts.bmp` says it a second way, laying all four candies out in their assembled ring. **When
a reporter asks whether a colour is intended, look for the skin's own self-portrait before
reasoning about the markup** — eight of this family's thirteen archives ship one.

**What was actually wrong, in the order it was found:**

| | Defect | What it looked like |
|---|---|---|
| W171 | `body_lower.jpg` declares `clippingImage` and **no** `clippingColor` | A 213x66 lavender plate boxed hard-edged across the bottom of the player |
| W172 | Its five subviews state their shape with `transparencyColor`, which `clipMask` did not read | The bottom candy hung 22 px below the silhouette; the body's edge was fringed with speckle |
| W173 | `hueShift` unimplemented | The paintbrush button did nothing and the candies were frozen at green |

**The speckle is worth its own line, because it looked like a resampling defect and was not — again.**
`bodyNormalMask.gif` is a dithered **254-colour** GIF: its white region carries 2,108 px within 8 of
white but not equal to it, 12.5% of that region, and each one survived the key and let the JPEG's
`#8286AC` surround through. That reads on screen as noise around the body outline and invites a
tolerance change; the actual fix was W172 letting `body_Mask.gif` shape the children, after which
the edge is clean and the mask's dithering never matters. **This family has now produced three
defects that presented as image quality and were none of them** — W160 (resampling, actually W169's
key), this, and the W169 erosion itself.

**W173's numbers.** `changeHue()` is `360.0 / 11` per press, ten stops: 33°, 65°, 98° … 327°.
Driven live it prints `topCandy.hueshift=33 leftCandy.hueshift=33 botCandyFacade.hueshift=33
botCandy.hueshift=33 rightCandy.hueshift=33` — five elements, one press. Rendered through the
skin's own `loadPrefs()` restore path the ring walks green → teal → blue → magenta → red → orange
while the player body stays byte-identical at `(73,201,222)`, which is the check worth keeping: only
the five candies carry the property, and a body that moves means the rotation reached something it
should not have.

**`WMP_RENDER_CLICK` restarts the view per point, so N clicks do not accumulate.** Each point rebuilds
the same `viewID` and the JSContext with it, so ten clicks all land on 33° rather than walking the
spectrum. That is the harness, not the engine — `currHue` is a script global in the persistent
per-session context and `changeHue()` also writes it through `theme.savePreference`. To render a
specific angle, patch `loadPrefs()` in a copy of the archive to force `currHue`: that is the skin's
own restore path and exercises script assignment → scene → image store → renderer end to end.

### The equaliser drawer drew no bands (2026-09-24)

*"the eq in plus hugh shifter is non functional"*. The bands were buried under the drawer's own art.
`hueshifter_eq` (the eight sliders) and the tray's `<buttonGroup>` are both `zIndex="2"`, the
subview first, and `eq_tray_MASK.gif` is opaque over the whole band area. `hueshifter_final.jpg`
shows the green thumbs over the tray. Fixed engine-wide as a tie rule: `../rendering/paint-order.md`
§ *At a `zIndex` tie a `<SUBVIEW>` paints above its non-subview siblings*. **The resting render
cannot show it**: the drawer is parked behind the body at `left="235"` until `openTray('eqTray')`
moves it to 395. Author `left="395"` in a copy of the archive to render it open.

### W170 — pause did not pause, and stop reloaded the track

*"in hue pressing pause does not pause the stream and play is not responsive at all"*, then *"stop
does not stop"*. Reported 2026-09-14 against `Plus! HueShifter`; the cause was engine-wide and this
family is the only place in the corpus it could show. The rule is in `../input.md` § *Phase 4
input and transport contracts*.

`openstatechange` was raised off the **play** state, so every pause told the skin a media had just
opened. Three archives here share the handler that answers that by playing:

```js
function OnOpenStateChange() {
    switch (player.OpenState) {
    case osUndefined: break;
    case osMediaOpen: UpdateMetadata(); Play(); break;   // Play() ends in player.controls.play()
    }
}
```

`Plus! HueShifter`, `Plus! Plasma Ball`, `Plus! SlimLine` — the family's single-view sub-shape, all
three from the same template. 109 of the 180 archives author `OpenState_onchange`; these are the
three whose handler *acts* on it. After a pause, playback resumed 16 ms later; after a stop, the
re-play found the player stopped and reloaded the track from 0:00.

**Three things this cost, all of them process:**

- **The corpus click sweep said the transport was fine, and it was right.** 284 decoded play/pause
  points across 149 skins, driven in both host states: `action=pause` dispatched everywhere. The
  defect is not in the click, it is in what the engine raises 16 ms *after* it — and a sweep seeds
  one snapshot and never transitions, so no probe here can compute that edge.
- **A local file cannot reproduce it.** The first live pass used `NULLPLAYER_PLAY` with
  `audio-long.mp3`, watched the clock freeze, and cleared the skin. Through the streaming path the
  re-play is a real restart; on an already-loaded local engine it is invisible. **Reproduce a
  transport report on the source the reporter uses** — here a Plex track, reached through the
  Library Browser's Radio tab.
- **The app's own log named it in one gesture**, where two rounds of probe work had not:
  `AudioEngine.pause()` immediately followed by `play(): Starting streaming playback via
  AudioStreaming (state: paused)`. For a "the control does nothing" report on this engine, read the
  playback log before reaching for a WMP probe.

### W257 — the orientation switch landed and `SlimLine` put it straight back

*"when I click the recycle it switches and instantly switches back"*, reported 2026-09-22 against
`Plus! SlimLine`, vertical view. The skin is the family's **two-view** shape and the only one here
that declares a *different* `.js` per view: `scriptFile="perfect.js"` on `perfectSkin`,
`scriptFile="perfectV.js"` on `perfectVSkin`. Both files define `Init`, `savePrefs`, `switchSkin`,
`EndVideo` and 13 other names, one script scope serves the whole skin, and the last program
evaluated therefore won every call in **both** views.

So the arriving horizontal view ran `perfectV.js`'s `Init()` → `vidIsRunning` false →
`EndVideo()` → `switchSkin('perfectVSkin')` → home again, inside the load transaction. The rule and
what it deliberately leaves shared is `../object-model.md` § *A view runs the functions its own
`scriptFile` names*; `WMP_VIEW_SCRIPT_SCOPE=0` is the A/B.

**Two things about this skin are worth keeping.** It was only reachable once W40 landed — before
that `Init()` threw on `perfectV_pl` at `PerfectV.js:20` and never reached the restore below it.
And the row that reported it had cleared `Init()` as a suspect by reading `perfect.js`, which is the
file the markup names and not the one that ran: **in a shared scope, "which function is this" is a
question about load order.**

`SlimLine` is also where `OnTimerTick` is called by both views' `onTimer` and declared in neither
file — that still throws roughly three times a second and is W42's class (a name no spelling
reaches), not this one.

## Ruled out — do not chase these again

- **Interpolation *quality* was not the cause.** `.low` vs `.high` at 2x is **byte-identical** on
  this path, so any fix phrased as raising the interpolation quality is a no-op. Only `.none` differs
  (max delta 44), and it is worse. W160.

- ~~**The clipping masks were not the cause.**~~ **This was wrong, and W169 is the correction.** The
  reasoning held for the masks' *edges* — the silhouette of a `clippingImage` skin is already
  antialiased, 6,512 partial-alpha pixels in a live 1350x1200 capture of Hard Boiled, so the
  stair-stepping in a zoomed screenshot is a colour boundary inside the artwork. But the family's
  `clippingColor="white"` was also being keyed out of the *artwork*, at a JPEG's 64-component
  tolerance, and `Egg_Body_Normal.jpg` was losing **27% of its pixels** to it. Two lessons, and the
  second is the sharper one: **a "low res" report about a photo-real skin is not necessarily about
  resampling**, and **a clearing measurement scoped to one mechanism does not clear the attribute**.
  See *W169* below.

- **The dancer is not ours and is not in the archive.** Reference screenshots of Bionic Dot show a
  dancing figure standing in the lens. That is **Plus! Dancer**, a separate Microsoft *Plus! for
  Windows XP* product that overlays a character on top of Windows Media Player; it is not a
  visualization and not a skin asset. Checked 2026-09-12: no Plus! archive contains any
  character/dancer asset. The animated GIFs some of them do ship are unrelated —
  `img_animation_diamond.gif` etc. (Aquarium), `playback_anim.gif`/`vis_animation.gif` (Pulsar),
  `anim_booster_*.gif` (Space). The thin waveform behind the figure in those screenshots is WMP's own
  visualization, which is the slot NullPlayer's effects fill.
- **A stopped Bionic Dot showing no visualizer and a greyed vis button is correct, not a defect.**
  `checkPlayerState()` runs `visMask.alphaBlendTo(0,500)` and `visButton.enabled = false` whenever
  `player.controls.isAvailable("Stop")` is false. Patching the markup *or* the script to force the
  pane open does not open it in the harness — that is the script runtime getting this right.

## Open, measured, unfixed

- **`mediaSwitcherView` renders at 0x0** in `Plus! Mecha` (`future.wms`) and `Plus! Professional`
  (`base.wms`) — 1 node, 0 commands. `WMP_RENDER_APPKIT` reports `SKIPPED canvas=0x0`. Not yet
  investigated; no reported symptom attached to it.
- **`Plus! Space`'s `btnBoosterLeft`/`btnBoosterRight` are unresolved for size**, and they are the
  two buttons whose artwork is `anim_booster_*.gif`. The booster animation is therefore unverified.
- **Unresolved counts on the multi-view mains run 8–10** (Bionic Dot 8, Mecha 10, Professional 8,
  Pulsar 10). Most are the benign population `../harness.md` already names — sizeless `<TEXT>` and
  `<SUBVIEW>` nodes that exist only to carry `toolTip` strings (`plShow`, `plHide`, `toolTipSub`,
  `vidToolTips`, `vidSize*`). **Do not open a row on the count itself**; name the node first.

## The instruments to reach for

```bash
# Which controls in the family cannot be reached, and what answers instead (W148).
WMP_SKIN="$HOME/Library/Application Support/NullPlayer/WMPSkins" \
WMP_RENDER_HOST=playing WMP_RENDER_OCCLUDED=1 \
  swift test --filter WMPRenderDumpTests/testSweepsSkinOrCorpus 2>&1 | grep "^OCCLUDED"
```

The seek arc, end to end — `follows-pointer=yes`, and the dead corners of its square must `MISS`:

```bash
WMP_SKIN="…/Plus! Pulsar.wmz" WMP_RENDER_HOST=playing \
WMP_RENDER_CLICK="mainView@332,78>330,94>328,110>326,126>320,142>313,158>300,174>284,190>273,206;318,194;308,204" \
  swift test --filter WMPRenderDumpTests/testSweepsSkinOrCorpus
```

`Pulsar`'s five contested controls, once they dispatch — `mainView@218,100` eq, `258,92` vis,
`274,92` vis-next, `297,101` playlist, and `242,92` vis-prev, which correctly answers the slider
underneath while the skin has it disabled:

```bash
WMP_SKIN="…/Plus! Pulsar.wmz" WMP_RENDER_HOST=playing \
WMP_RENDER_CLICK="mainView@218,100;258,92;274,92;297,101" \
  swift test --filter WMPRenderDumpTests/testSweepsSkinOrCorpus
```

```bash
# Which Plus! surfaces are faded shut, and which are shaped by a mask.
WMP_SKIN="$HOME/Library/Application Support/NullPlayer/WMPSkins" \
WMP_RENDER_HOST=playing WMP_RENDER_PROBE=all \
  swift test --filter WMPRenderDumpTests/testSweepsSkinOrCorpus 2>&1 \
  | grep "WIDGET .*effects" | grep -E "alpha=|mask="
```

`WMP_RENDER_HOST=playing` is not optional for this family. Half of what these skins do is conditional
on `checkPlayerState()`, and the default stopped host shows a legitimately empty player that is
indistinguishable from a broken one. See `../harness.md`.
