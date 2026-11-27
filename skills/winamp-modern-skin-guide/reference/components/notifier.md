## Notifier — track-change toast

A `.wal` skin's `<container id="notifier">` is a floating toast popup that appears when the track
changes. Winamp Modern, Love is War Miku, and cPro-Bento all ship one. The notifier is **host-driven**:
the host triggers it on track change, sets the text content, and auto-dismisses it — the skin's MAKI
scripts handle fade animation but do not reliably set text (the bytecode's condition check fails in the
`onTimer` handler body, so the timer-based text-setting chain does nothing).

### How it works — end to end

1. **Detection.** During `setupAuxiliaryContainers`, any container whose lowercased id is `"notifier"`
   or starts with `"notifier."` is tagged `isNotifier = true` and `noActivation = true`. Its window
   gets `level = .floating` and `hidesOnDeactivate = false` so the toast appears over other apps and
   survives app-deactivation.

2. **Suppression.** `WinampModernContainerTopology.defaultVisibilitySuppression` returns
   `.hostManagedTransient` for notifier containers, preventing them from auto-opening with the skin.
   Without this, a notifier with `default_visible="1"` would sit on screen reading its XML default
   text ("Nothing / Next track / Nithin Sawhney / Prophesy") for the entire session.

3. **Trigger.** `WinampModernMainWindowController.updateTrackInfo(_:)` calls `showNotifier(for:)` when
   a non-nil track is passed. This is the same path that fires `ontitlechange` to MAKI scripts (via
   `skinView?.updateTrackInfo()`), so the notifier appears on every track change.

4. **Text setting.** `showNotifier` asks `announceNotification`, which calls
   `scripts.setNotifierText(title:artist:album:)` to **override** the text with the actual track
   info, unless the toast shows itself (below). No `onshownotification` goes with it (B309, see
   *`onshownotification` system event*).

5. **`setNotifierText` internals.** This method on `WinampModernScriptRuntime`:
   - Finds the `<container id="notifier">` root in the object graph.
   - Iterates all layouts (typically `normal` and `desktopalpha`).
   - For each layout, walks the subtree with `setTextInSubtree` to set text on `title`, `artist`,
     `album`, and to clear `plentry`, `nexttrack`, and `endofplayback`.
   - Calls `ensureTextHeight` to fix 0-height text elements (see below).
   - Resizes the layout to 350px wide via `setAttribute("w", "350")`.
   - Fires `layoutResizeRequested` to update the renderer's canvas and window size.
   - Calls `noteGeometryChange()` + `notifyGraphDidMutate()` to invalidate the scene cache and
     trigger a full redraw.

6. **Display.** After text is set, `showNotifier` resets `window.alphaValue = 1`, shows the window
   via `setAuxiliaryWindow(id:, visible: true, activate: false)` (which uses `orderFrontRegardless()`
   for `noActivation` containers — no focus steal), and forces `needsDisplay = true`.

7. **Positioning.** The notifier is placed at the bottom-right of the screen with a 12pt margin
   (in `place()`, gated on `container.isNotifier`), unless the skin specifies `default_x`/`default_y`.
   The startup tiler (`arrangeWindows`) skips every **desktop toast**
   (`WinampModernContainerTopology.isDesktopToast`): a `notifier` id, or a container whose primary
   layout is both `noparent="1"` and `nodock="1"`. Pixelated's `pixelatednotifier` is the second
   kind; tiled, it took the slot under the player and pushed the playlist down 27 px until its
   script moved it to the corner (B398). In the gold corpus the `noparent`+`nodock` rule on a
   `default_visible` container matches only Pixelated's, Copter's, No-Vita's and Ryoko's toasts and
   Official Tristania's `update` popup. A `newDynamicContainer` window is skipped too: its script
   places it.

8. **Auto-dismiss.** A 5-second `Timer` hides the notifier. On a new track change, the timer is
   invalidated and restarted — so rapid track changes keep the notifier visible with the latest info.

9. **Fade animation.** MAKI scripts can call `container.setAlpha(n)` to animate the notifier's
   opacity. The `containerAlphaChanged` callback on `WinampModernScriptRuntime` is wired to update
   `window.alphaValue` for any container (notifier included), converting the 0–255 Wasabi alpha to
   0.0–1.0.

### The shadow element problem

Winamp Modern's notifier uses an unusual technique for text shadows: the XML comment says *"I know
this is an unusual way to get text shadow — but it creates a much better effect than the shadow
params."* Each `<text>` element has `shadow="1" shadowcolor="notifier.bright" shadowx="1" shadowy="1"`
attributes, which the renderer now draws as well ([`rendering/text.md`](../rendering/text.md) →
*`shadowx`/`shadowy`*, B363). During groupdef expansion
the engine synthesizes paired text elements with IDs like `title.shadow`, `artist.shadow` — each
drawn 1px below its sibling, in the shadow colour, to create the shadow effect.

`setTextInSubtree` must therefore match not only the exact id (`"title"`) but also any text element
whose id starts with the target + `"."` (e.g. `"title.shadow"`). It also sets both the `text` and
`default` attributes, because the renderer resolves content as `text ?? default` — leaving `default`
at its XML value ("Nithin Sawhney") causes ghost text when the new `text` value is shorter.

### The zero-height text problem — fixed in the renderer, not here (BB27)

The notifier groupdef defines `<text id="title" w="0" relatw="1" fontsize="17">` with no `h`
attribute. The geometry resolver defaulted a missing `h` to 0 and the renderer clips to the frame
rect (`context.clip(to: frame)`), so the element drew nothing at all.

**A heightless `<text>` now takes its font's line height as its intrinsic height**, in
`WasabiSceneRenderer.append` beside the existing `autoWidth` case — see
[rendering.md](rendering.md) → *A `<text>` with no `h` is one line tall*. It is the same number
`getAutoHeight()` answers, so a script's measurement and the drawn box are one measurement.

The notifier used to carry its own patch for this (`ensureTextHeight`, `ceil(fontSize * 1.4)`,
called from `setNotifierText`). **It is gone.** That number is ~40% taller than the line a skin
spaces its rows for: Big Bento stacks `title` at `y="22"` (46pt) over `artist` at `y="64"`, so a
64-pixel title box ran 22 pixels into the artist underneath it. Do not reintroduce a per-surface
height guess — if some other object type turns out to need auto-sizing, it belongs next to the
renderer's intrinsic-size rules.

### The layout-width floor

The notifier's `<groupdef id="notifier.text">` is placed inside each layout at `x="75" w="-95"
relatw="1"`. With Winamp Modern's declared `w="128"`, the text group is only `128 - 95 = 33` px wide
— too narrow for any useful text, so `setNotifierText` widens the layout and fires
`layoutResizeRequested` to resize the renderer's canvas, view and window to match. The background
`<grid>` stretches to fill (`fitparent="1"`) and the `relatw="1"` text group recalculates.

**350 is a floor, not a size**: `max(declared, 350)` per layout. It used to be assigned, which
*shrank* every skin that already declares a usable width — Big Bento's notifier is `w="540"` with a
310px text group, and forcing 350 left 120px for 46pt text. That is the reported "giant font".

### A notifier that lays itself out (BB27)

Winamp Modern's notifier is a static layout the host fills in. **Big Bento's is not**, and the
difference is worth knowing before touching this code: `notifier.maki` starts a 30 ms poll from
`onTitleChange`, and the poll reads its four `Notifications` settings, hides the album line or the
transport row, moves the text group with `setXmlParam(x/w)`, measures the result with
`getAutoWidth`, and then **sizes and positions its own window** — `container.resize(0, 928, 540,
150)` followed by a `setTargetX/Y/W/H` animation into the corner of the screen. Three engine
capabilities have to be present for any of that to appear:

- **A container's geometry must reach its window.** See [rendering.md](rendering.md) →
  *A container's `x`/`y`/`w`/`h` are its window's*.
- **The window must be on the layout `isDesktopAlphaAvailable()` points the skin at.** A skin asks
  once and then addresses `getLayout("desktopalpha")` for the rest of the session without ever
  switching to it — in Winamp the container is already on that layout. So a container that ships a
  `desktopalpha` layout opens on it (`WasabiSceneRenderer.primaryLayout`, B262), and the call
  answers true exactly when some container does. Answer true with the window left on `normal` and
  every write goes to a layout no window draws (BB27): the render dump of `notifier/desktopalpha`
  comes out perfect while the app draws the untouched `normal` layout. The `normal` layout is the
  no-desktop-alpha fallback, a region window: drawn through it, CPro_iPhone3gv2's cover sprite
  turned a faint shadow it shares with its neighbour on the sheet into a solid strip.
- **The host must not fight it.** `setNotifierText` runs before the skin's timer does, so the
  skin's own sizing lands last and wins. Keep it that way.

The host's text override stays regardless, because the skins' timer-driven text chains do not
reliably run — but on a skin like this one it is the *only* thing the host should be doing.

### A notifier whose own container scripts its show (#805, 2026-11-24)

Steps 4–8 above are the host's fallback for a notifier the skin does not drive. **Jpod's drives
everything**: `<script file="Scripts/Notifier-Notifier.maki">` sits *inside* `<container
id="notifier">`, and its `System.onTitleChange` reads the skin's own Notifier Settings (Do Not Show,
Display On Left/Right, Anim Off/Slide), then `show()`s, `resize()`s, slides and `hide()`s the
layout itself. The host showing it as well overrode every one of those: the toast appeared under
Do Not Show, the 350 floor widened its authored 300 (which its left/right arithmetic is cut for),
the 5 s dismiss ran beside its own 3 s one, and the visible-frame clamp in `moveContainerWindow`
pulled the slide's start — below the screen edge — back on screen, so the toast popped up whole and
hopped the last 49 px.

`WinampModernScriptRuntime.notifierShowsItself(_:)` is the test: a notifier container with a
program **owned by it or by something inside it** that binds `System.onTitleChange` or
`onShowNotification` (found through `programsBinding`). When it holds, `announceNotification`
answers nil and `showNotifier` does not show, fill or dismiss the toast, and
`applyContainerGeometry` sends that container's moves as **pins**, which `moveContainerWindow`
does not clamp. Ownership is the line because stock Winamp Modern's,
Love is War Miku's and Big Bento's notifier scripts are **skin-level** (`owner=-#-` in
`RENDER_SCRIPTS`) and Big Bento's in-container groups bind only `onPlay`/`onPause`: all three keep
the host's show, unless their script takes the container with `newDynamicContainer` (next section). Measured reach (static scan of gold+silver, then `RENDER_EVENTS=ontitlechange` +
`CALL_TRACE` on each): Jpod, CNYforWinamp, WTM, YST and Symplicipod — one script family, and every
one `show()`s and places its own layout. A static scan sees only `<script>`s written directly in the
container, so it is a lower bound.

**The host's toast is the plain `notifier` id, never a `notifier.*` sibling** (#810).
`announceNotification` finds `<container id="notifier">` itself and answers it (or nil), and
`showNotifier` shows that window. It used to show the first container `isNotifier` matched, which
on Rectangular (`notifier.preferences` then `notifier.popup`, no plain `notifier`) was the
preferences window, popped up at the screen corner on every track change beside the popup its own
script shows. Ten corpus skins, the Love is War Miku family, also declare `notifier.preferences`
ahead of `notifier` in archive order; Love is War Miku now shows its 350×80 `notifier`, measured live.
`isNotifier`'s prefix rule still decides suppression and placement.

Two things that look like defects and are the skin's: its **first** toast after launch never slides
(the hide timer `onScriptLoaded` starts is still running, so `ShowNotifier` keeps the `ANIM_STYLE_NONE`
it was born with), and the slide starts about 39 px visible, because the skin takes the viewport's
height as its bottom edge and ignores `getViewportTop()` (the menu bar).

### A notifier a script takes with `newDynamicContainer` (B479, B309, 2026-11-27)

Stock Winamp Modern's `notifier.m` is the other way a skin owns its toast, and it is copied widely:
44 gold skins ship it as source (GlassAMPfinal, ipamp14, Ebonite, Resurgence, …), and 127 ship a
`notifier.maki`. Its script is skin-level, so the ownership test above misses it. Instead, on each
track change it calls `newDynamicContainer("notifier")`, fills and sizes the layout, places it in
the corner and shows it, then on dismiss `hide()`s it and drops the reference. **`notifierShowsItself`
also holds for a container `isDynamicallyClaimed`**, so the host stands down for it. Shown by the
host as well, stock's script found the layout already visible and slid it from wherever the host had
left it, across the whole screen, opening at x=0 (B479).

Three engine pieces have to be present for that script's toast to appear right:

- **`AlbumArt.onAlbumArtLoaded(boolean success)`.** Stock's and Love is War Miku's scripts build,
  place and show the toast only from this event. `announceAlbumArtLoaded()`
  (`WinampModernTrackFolderImage.swift`) sends it to every `<AlbumArt>` when the cover finishes
  loading (`NowPlayingManager.artworkDidLoadNotification`), with `success` = a cover was found.
  All ten corpus declarations take the one boolean.
- **A closed container comes back as first handed out.** Winamp builds a fresh instance on every
  `newDynamicContainer` call; ours hands the same program the same container. Once it is off screen
  (`effectiveVisibility`), asking again restores every object under a `dynamic="1"` container to the
  attributes it had when first handed out, except `visible`, and cancels any target animation
  (`reclaim` in `WinampModernScriptRuntimeDynamicContainers.swift`; the attributes are kept in the
  program's `HeldDynamicContainer`). Without it, GlassAMPfinal's `coverandbutton.resize(0,0,85,92)`
  from one show stayed on the next, the cover and text 11 px out of the frame (B309). A copy per call
  was tried and dropped: GlassAMP's notifier carries its own `<covern>` script, and a discarded
  copy's timers would leak on every track. A container still on screen, and a `dynamic="0"`
  singleton, are handed back as they are.
- **No `onStop` between tracks.** A natural advance passes through `.stopped` for about 15 ms.
  `WinampModernScriptRuntime.playbackStateDidChange(to:)` reports a stop only after it has lasted
  `stopGracePeriod` (0.25 s), so a
  skin sees no `onStop`/`onPlay` pair between tracks (GlassAMP printed "Stopped" and showed its toast
  twice more). A load slower than that, such as a stream, still reports the stop (`ponytail:` in the
  code).

**Stock ships its notifier set to "Never show"** (`newattribute(Never show,1)`), and its script
then never claims the container, so with default settings the toast is the host's, placed by
`place()` 12 pt in from the bottom-right (measured at 1438,1077 on an 1800×1169 visible frame).

GlassAMPfinal's first one or two toasts after launch still take its script's "already visible"
branch, because the startup toast is still up when the next track starts. That is the skin's logic.

### `getPlayItemMetaDataString` — per-field metadata

MAKI scripts use `System.getPlayItemMetaDataString("artist")` etc. to read track metadata.

**The key table is not here — it is `WinampModernHost.playItemMetadata(forKey:)`**, a method on the
protocol extension, and the runtime's `getplayitemmetadatastring` is a one-line delegation to it.
Putting it on the protocol is deliberate: the render harness and every test double then answer
identically to the live host, so a probe run is comparable to the real app. The full table, the units
and the rules for an unanswerable key are in
[compatibility/maki-surface.md](../compatibility/maki-surface.md) → `getPlayItemMetaDataString`; do
not restate it here, and do not add a key to the runtime's switch instead of to the table.

`trackTitle` / `trackArtist` / `trackAlbum` are properties on `WinampModernHost` (defaults `""`,
live implementations on `WinampModernAudioEngineHost` reading `engine.currentTrack`). These were
added alongside the notifier — earlier, both keys incorrectly returned the combined `host.trackInfo`
string. Everything past those three arrives through `host.trackMetadata`
(`WinampModernTrackMetadata`), which the engine host fills from the **library row** for the playing
file, looked up once per track id: a `Track` carries only `genre` of the panel's fields, and a
file-info panel asks for a dozen in a row, so a per-key lookup would take the library's queue a dozen
times per repaint.

### `onshownotification` system event

Registered in `dispatchableEventArity` with arity 0. **The host does not send it on a track
change** (B309). It is Winamp's *show the notification now* request, not a track change, and every
corpus script that handles it also shows its toast from the `onTitleChange` the same track change
sends. Sent as well, GlassAMPfinal's and ipamp14's toast showed twice per track, and the second
show's `coverandbutton.resize(0,0,…)` pulled the cover and text out of their frame. A skin can still
call it on itself (GlassAMP's `timerShow` does).

### Files

- `WinampModernMainWindowController.swift` — `AuxiliaryContainer.isNotifier`, `noActivation`,
  `notifierDismissTimer`, notifier detection in `setupAuxiliaryContainers`,
  bottom-right positioning in `place()`, `containerAlphaChanged` wiring
- `WinampModernMainWindowController+Notifier.swift` — `showNotifier(for:)`
- `WinampModernScriptRuntimeText.swift` — `announceNotification(title:artist:album:)`,
  `notifierShowsItself(_:)`, `setNotifierText(title:artist:album:)`, `setTextInSubtree(_:id:text:)`
- `WinampModernScriptRuntimeTimer.swift` — `applyContainerGeometry(_:)`
- `WinampModernScriptRuntimeDynamicContainers.swift` — `dynamicContainer(named:for:)`, `reclaim`,
  `isDynamicallyClaimed(_:)`
- `WinampModernScriptRuntimePlayback.swift` — `playbackStateDidChange(to:)`, `stopGracePeriod`
- `WinampModernTrackFolderImage.swift` — `announceAlbumArtLoaded()`
- `WinampModernScriptRuntime.swift` — `containerAlphaChanged` and `containerMoveRequested`
  callbacks, `isdesktopalphaavailable`, `onshownotification` in `dispatchableEventArity`,
  `refresh` no-op
- `WinampModernHost.swift` — `trackArtist`, `trackAlbum` protocol properties and implementations;
  `WinampModernTrackMetadata`, `playItemMetadata(forKey:)` (the key table), `currentTrackRating`,
  and the engine host's `libraryRow(for:)` / `ratingCache` / `currentTrackRatingChanged`
- `TrackRatingService.swift` (`Data/Models/`) — the one owner of the 0–5 star ↔ 0–10 internal ↔
  per-server rating conversions, shared with the Library Browser's ART-mode star row
- `WinampModernContainerTopology.swift` — `.hostManagedTransient` suppression for notifier
  containers, `isDesktopToast(_:)`
- `WasabiTextMetrics.swift` — `content(of:host:)` resolves `text ?? default` for text elements

