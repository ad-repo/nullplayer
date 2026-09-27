# `.wmz` hosted surfaces: playlist, effects and visualization

Moved verbatim from `reference/rendering.md` § *Drawing the skin's own controls* on 2026-09-25; the router is
`reference/rendering.md`. Before an engine-wide change here, check the counter-evidence table in
`reference/skins/README.md`.

- **Hosted `PLAYLIST` chrome attributes are unread, and verification halves the row (W133).**
  `playlist-element` defines 37 attributes; the engine reads background/foreground/itemPlaying
  colours via `WMPSurfacePalette` and nothing else. **Most of the corpus authors values that *agree*
  with what the overlay already does** — `playlistItemsVisible="false"` is 3 skins against 117
  authoring `"true"`, `moveButtonsVisible` is `"false"` in all 57 skins that author it,
  `checkboxesVisible` is `"false"` in 24 of 32 — so only the genuine differences rank:
  `columnsVisible="true"` **74 skins** (with `columns` in 131), `leftStatus`/`rightStatus` 27,
  `dropDownImage`/`dropDownBackgroundImage` 27/25, `toolbarVisible="true"` 12, `toolbarMargin` 14.
  `disabledItemColor`'s 74 have no meaning here at all — there are no disabled tracks. **The
  substance is column headers, which the overlay draws none of.** `dropDownVisible="true"`
  (114 skins) is explicitly **not** part of it: a documented deliberate refusal in `object-model.md`
  pending W66. **Closed 2026-09-24 without implementing**: the column playlists render at a median
  327 px, too narrow for readable columns — measurements in `docs/wmp-skin/wmp-backlog-archive.md` (W133).

- **A `<PLAYLIST playlistItemsVisible="false">` is hosted as the dropdown (2026-09-26).**
  `WMPSceneBuilder.widgetKind(_:)` maps it to `.dropdownPlaylist`, so it gets
  `WMPDropdownPlaylistSurfaceView` (the queue as a popup; choosing a row plays it) and, when it
  states no height, the popup's 24pt. The list surface drew one clipped, highlighted 18pt row over
  its own ground in `Heart_Butterfly`'s 22pt strip — reported live as "does not draw the playlist
  properly". Four archives author it (`Compact`, `Heart_Butterfly`, `Josie_and_the_Pussycats`,
  `Radio`); render dumps of all four are pixel-identical either side, because the strip is hidden at
  load in the two Tattoo skins and `Compact`'s unsized one never resolved before. `Compact`'s popup
  sits under its own black `svPlaylistDDown` ground and `WMP_RENDER_APPKIT` reads `differing=0`
  there, yet in the running app it opens and lists the queue (reporter-verified 2026-09-26).

- **A hosted AppKit surface obeys the container's `alphaBlend`; it is not exempt because it is not
  a paint command.** `alphaBlend` inherits, and a `.wmz` closes a pane it has not opened by fading
  the container to zero — so `WMPWidget` carries the walk's inherited alpha, `WMPMainView` hosts
  **no view at all** at `alpha == 0` (rather than `alphaValue = 0`, so a shut pane runs no GL engine
  and no 30fps readback), and a partial fade is applied every sync. `Plus! Bionic Dot` is the worked
  case twice over: its `<subview id="visMask" alphaBlend="0">` correctly drew no artwork while the
  `<EFFECTS>` inside it put a 169x160 visualizer across the face, and its `checkPlayerState()` also
  runs `visMask.alphaBlendTo(0,500)` whenever `player.controls.isAvailable("Stop")` is false — so a
  stopped player is *supposed* to show no visualizer and a disabled vis button. Six archives author
  the idiom, five of them Plus!.

- **A hosted surface is confined by the window's own shape as well, and that is a third statement
  (W198).** The two idioms below are about the *container's artwork*; this one is about whether the
  window exists at all. `clippingColor` marks pixels the skin cut out of its own silhouette, nothing
  is painted there, and therefore nothing occludes a surface that reaches into them — so a rect
  confined "by paint" is not confined at the edges of the skin. Cerulean is the reported case and
  the smallest of six: `face.bmp`'s last three columns inside the `<EFFECTS>` rect are `#FF0000`,
  and 104 px of visualizer stood outside the right of the head. `WMPSceneBuilder.groundShape`
  already computed that silhouette for `WMPEffectsGround`; `WMPWidget.clippingShape` now carries it
  to the surface, which clips to it **and** to `regionMask`, intersected. **`clippingColor` only,
  never `transparencyColor`** — a hole inside the silhouette is where the surface is *meant* to
  show, which is the same rule `groundShape` states and for the same reason.
  `WMP_RENDER_PROBE`'s `offshape=` is the only instrument that sees this class; `outside=` cannot,
  because the leak is inside the widget's own rect. `offshape>0` measures what the skin *authored*,
  so it stays non-zero after the fix: it is a rect to check, not a defect. **`pharaoh` was the
  counter-evidence and W199 is what it was pointing at** — five of the six skins W198 moved cut only
  pixels the scene leaves fully transparent, and `pharaoh`'s 1,524 were opaque because its
  container's `backgroundColor` fill was not clipped by its own keys. Confining the surface was
  right and was never the whole of it; the fill was the other half, and the two together are what
  give that window a pyramid instead of a slab and a visualizer instead of a black apex.

- **A container shapes its windowless `<EFFECTS>` in one of two ways, and they read the colour key
  oppositely. Measure which before touching either.**
  - *Artwork with a keyed hole* — every pixel is the key or opaque paint. The key is the **opening**;
    the paint occludes the rest, and the engine already renders that by hosting the container's own
    paint commands above the surface (`WMPWidget.commandSplitIndex`). **Cerulean is this** —
    `face.bmp`, 56% key, 44% paint, 0% transparent.
  - *A shape mask* — the file carries a **third state**. The key marks the **outside**, genuinely
    transparent pixels mark the opening, and the little paint there is is trim. `WMPWidgetRegionMask`
    clips the surface to it, counter-flipped exactly as `WMPRenderer.clip(to:mask:)` is.

  **The Plus! archives are a sub-family with their own idioms, and both halves of this rule came out
  of them** — `reference/skins/plus-family.md` is the dossier, including what has been ruled out.

  The discriminator is *has transparent pixels alongside keyed ones* — not a threshold, not a skin
  name. Measured over all 30 `<EFFECTS>` in the corpus whose container declares a background image
  and a transparency colour, **28 are two-state and 2 are three-state**: `Plus! Bionic Dot`'s
  `main_vis_back.png` (36/58/5) and `Plus! Professional`'s `vis_mask_s.png` (23/59/18). Getting the
  sign wrong on Cerulean does not distort its visualizer, it **erases** it: the mask would keep the
  surface only where the face already covers it and clip it away inside the hole.

  **An `<EFFECTS>` that names its own `clippingImage` is shaped by that, first (W309).** The US
  forces family (`US Army` and five siblings) writes `clippingImage="vismask.gif"
  clippingColor="#FF00FF"` on the surface itself; its container's `backgroundImage` is the same
  opaque two-state plate, which the discriminator above rightly refuses, so the spectrum filled the
  whole 370x370 window instead of the small disc. The key is `clippingMaskKeys` (the corner when
  none is authored); a mask with no key and its own alpha still shapes nothing. 14 `<EFFECTS>`
  declarations across 11 archives author one (`Secura`, `Windows XP`, `deepbluesomething`,
  `holiday_skin`, `gnome`, `Charlies_Angels_Full_Throttle`, `portals` and the six) — only the
  six were checked on screen.

- **The skin draws its controls; an AppKit overlay is only for what the scene genuinely cannot
  paint.** What is left hosted is `PLAYLIST`, `DROPDOWNPLAYLIST`, `EFFECTS`, `EDITBOX`, `LISTBOX`
  and `POPUP`. `VIDEO` is not: its placeholder filled every `<VIDEO>` frame with opaque black over
  the artwork of 166 of 177 archives, and an audio player has nothing to put there instead. Adding
  an overlay back needs the same argument — name what the renderer cannot draw.

- **A popup's height is a host metric when the markup omits it.** Measured 2026-09-10 over 177
  readable archives, both `DROPDOWNPLAYLIST`s (Corona and 9SeriesDefault) and all four `POPUP`s
  omit `height`; they have no artwork from which the generic geometry path can infer one. Their
  `NSPopUpButton` host measures 24 points high, so `WMPWidgetKind.intrinsicHeight` supplies exactly
  that value only for an unauthored, unoverridden height. The scene builder remains off-main and
  does not construct AppKit controls; an authored or scripted height wins.

- **The visualization surface is this player's own visuals in the rect the skin authored (W101).**
  `WMPEffectsSurfaceView` draws compact WMP-native **Spikes**, **Bars**, **Ambience**, **Cava**, and
  **vis_classic** directly. Cava uses its actual presenter/full-stereo tap and vis_classic uses its
  actual waveform/profile core, each with a WMP-only preference scope. Their right-click controls are
  therefore the real Cava tuning menu and vis_classic profile menu, not inert replicas.
  `WMPEffectSelection` is the one place the choice lives, because 96 archives bind
  `currentEffectType` to `wmpprop:mediacenter.effectType`. Three rules it is built on: **nothing
  playing draws nothing at all** (the skin's own screen artwork stands); **the surface never takes a
  click**, because 51 archives wire an `onClick` on `<EFFECTS>` and that handler belongs to scene hit
  testing; and **the skin's selector is not the app's preference** — cycling from the rect, its menu,
  or the arrow keys never writes `visualizationEngineType`, which the visualization window and
  menu bar share.
  **The keys are two-level, because the catalogue is.** Eight effects, and most carry a list of
  their own, so **up/down pick the effect and left/right step inside it** — ProjectM's presets,
  Geiss's and Tripex's effects, vis_classic's profiles, Cava's mono/stereo. An effect with no
  inside (Spikes, Bars, Ambience) *refuses* left/right rather than swallowing them, so the key
  falls through. Two things this wiring depends on: a preset step goes through
  `WMPEffectSelection.setPreset`, never the engine's own `nextPreset()`, or the `currentPreset` /
  `currentPresetTitle` bindings 144 archives read would show a preset that is not on screen; and
  `applySelection` must tell a preset change from an effect change, because `setPreset` posts the
  same notification as `select` and rebuilding the engine for it reinitializes ProjectM on every
  key press.
  **Do not fill the widget's rectangle.** The effect is composited over the scene, and its untouched
  pixels must stay transparent: every renderer draws into the full authored rect and the skin's own
  artwork is what shapes it, through the z-order split above. **A suite renderer needs two extra
  conversions:** Cava's shared drawer assumes a y-up AppKit host and vis_classic emits top-row-first
  BGRA, so both require a local y-flip inside the flipped WMP view. Test the effect with a real skin
  at playback and inspect the AppKit-hosted frame; a static render dump cannot show its pixels.

- **The ban on hosting ProjectM / Geiss / Tripex in the slot is reversed, and this records why
  (W140).** The rule read: *it must never host ProjectM, Geiss, Tripex, or any other standalone
  visualization window in that slot*, with the black panels reported in Asimov Radio and Cerulean as
  its evidence, and `WMPEffectsSurfaceView.makeEngineView()` / `applyPreset(to:engine:)` were left in
  the file as dead code with zero call sites.

  **Those black panels were the occlusion defect, not the engines.** `WMPMainView` blitted the whole
  scene as one flattened image and hosted every widget above it with a plain `addSubview`, so nothing
  a skin drew could ever cover the surface. An opaque renderer that nothing can occlude *is* a black
  rectangle over the artwork — it would have been one whatever was drawing in it. With the split
  above, the artwork composites over the rect and opacity stops mattering; WMP's own visualizers were
  opaque too.

  What does not change: **the selection stays WMP-session-scoped** — a skin cycling `visEffects`
  never writes `visualizationEngineType`, which is why `switchEngine(to:forceReload:)` grew a
  `persistPreference` parameter rather than the surface calling it as the visualization window does
  — and **`VisualizationGLView` is not mounted live between the two raster layers**. A legacy CGL
  drawable's ordering against sibling `CALayer`s is not guaranteed the way normal layer z-order is,
  and its own `CVDisplayLink` clock tears against the overlay's alpha-blended edge. Do not mount it
  live "just to try"; that is what produced the black panels the first time.

  **How the three are hosted.** `WMPEffectsSurfaceView` builds a `VisualizationGLView` and never adds
  it to the hierarchy: its display link never starts, and a 30fps timer pulls one frame at a time
  through `renderOffscreenImage(pixelWidth:pixelHeight:)` — an FBO render plus `glReadPixels` — which
  `draw(_:)` presents like any other picture. **The GL path takes no y-flip**, where vis_classic
  does: `glReadPixels` returns rows bottom-first, a `CGImage` calls row 0 its top, and this view is
  flipped, so the two reversals cancel. The view's frame is set in **points** before each pull, not
  pixels — `initializeEngineOnRenderThread` sizes the engine from `convertToBacking(bounds)`, so a
  frame in pixels creates the engine at twice the surface it renders into. The readback is verified
  headlessly by `WMPPhase7Tests.testOffscreenEngineReadbackProducesAnImage`, which is the only thing
  in the suite that drives an `NSOpenGLView` outside a window.

- **The effects slot's settings belong to the skin, not to the session (W157).** A `.wmz`'s
  `<EFFECTS>` rect is part of its look — Cerulean's 103x75 frame and a full-width panel want
  different effects — so `WMPVisualizationSettingsStore` files them against the installed skin name
  (length-prefixed key, as `WMPViewFrameStore` does) and `WMPMainWindowController` restores them at
  the top of `reloadSelectedSkin()`, before the scene and therefore before the surface is built.
  **What is in scope is what WMP owns**: the effect and preset, plus the keys already namespaced to
  the slot — `cava.wmpEffects.*` and `visClassic*.wmpEffects`, both asked of the subsystem that
  names them (`CavaSettings.preferenceKeys(for:)`, `PreferenceScope.wmpEffects`) so a new key is
  carried without a change here. ProjectM / Geiss / Tripex cycle and sensitivity are **not**: those
  keys are shared with the standalone Visualizations window and the `.wal` surface by design, and
  per-skin copies would rewrite that window's settings on every skin switch.
  Three things it is built on. **A skin with no record restores the app's defaults** — every scoped
  key is cleared, and `WMPEffectSelection.restore` falls back to the default effect where `select`
  would change nothing — or the second skin silently inherits the first one's choices, which is the
  half that regresses invisibly. **Capture is driven off `UserDefaults.didChangeNotification`**,
  not off each menu item: the Cava and vis_classic controls in the slot's menu write their own keys
  and offer no callback. That makes the write conditional — an unchanged record must not be
  rewritten, or the observer feeds itself. And **a captured change is filed against the skin that
  was showing when it was made**, held in `visualizationSettingsSkin`, because the defaults
  notification is delivered on the main queue asynchronously: a change made just before a skin
  switch would otherwise land in the record of the skin being switched *to*. `restoreVisualizationSettings`
  flushes the outgoing skin first for the same reason.

- **PCM arrives on the audio thread and an overlay must not hop to the main actor to take it.**
  `.audioPCMDataUpdated` is posted from inside `AudioEngine.processAudioBuffer`; a
  `MainActor.assumeIsolated` in that observer is a `dispatch_assert_queue` failure and the process
  traps the moment a surface exists and a track plays. The WMP effect surface retains the latest
  spectrum snapshot and schedules its AppKit redraw on the main actor.
