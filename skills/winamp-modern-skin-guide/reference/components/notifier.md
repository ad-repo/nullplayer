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

4. **Text setting.** `showNotifier` dispatches `onshownotification` to MAKI **first** (so the skin's
   scripts run their setup/animation), then calls `scripts.setNotifierText(title:artist:album:)` to
   **override** the text with the actual track info. The override-after-dispatch order ensures the
   host's values win over anything the MAKI scripts set (or fail to set).

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
attributes. The engine does not render these attributes directly. Instead, during groupdef expansion
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
- **`isDesktopAlphaAvailable()` must answer false.** A skin asks once and then addresses
  `getLayout("desktopalpha")` for the rest of the session without ever switching to it — in Winamp
  the container is already on that layout. Nothing here activates one, so a true answer sends every
  write to a layout no window draws. This is the failure mode that looks like nothing is wrong: the
  render dump of `notifier/desktopalpha` comes out perfect while the app draws the untouched
  `normal` layout.
- **The host must not fight it.** `setNotifierText` runs before the skin's timer does, so the
  skin's own sizing lands last and wins. Keep it that way.

The host's text override stays regardless, because the skins' timer-driven text chains do not
reliably run — but on a skin like this one it is the *only* thing the host should be doing.

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

Registered in `dispatchableEventArity` with arity 0. Dispatched to all MAKI programs via
`.system` target. The skin's notifier script typically uses this to start a fade-in animation
timer. The host dispatches it, but the text is set by the host *after* the dispatch, so the MAKI
handler's text-setting (which doesn't work anyway) is overridden.

### Files

- `WinampModernMainWindowController.swift` — `AuxiliaryContainer.isNotifier`, `noActivation`,
  `showNotifier(for:)`, `notifierDismissTimer`, notifier detection in `setupAuxiliaryContainers`,
  bottom-right positioning in `place()`, `containerAlphaChanged` wiring
- `WinampModernScriptRuntime.swift` — `setNotifierText(title:artist:album:)`,
  `setTextInSubtree(_:id:text:)`, `containerAlphaChanged` and `containerMoveRequested` callbacks,
  `applyContainerGeometry(_:)`, `isdesktopalphaavailable`, `onshownotification` in
  `dispatchableEventArity`, `refresh` no-op
- `WinampModernHost.swift` — `trackArtist`, `trackAlbum` protocol properties and implementations;
  `WinampModernTrackMetadata`, `playItemMetadata(forKey:)` (the key table), `currentTrackRating`,
  and the engine host's `libraryRow(for:)` / `ratingCache` / `currentTrackRatingChanged`
- `TrackRatingService.swift` (`Data/Models/`) — the one owner of the 0–5 star ↔ 0–10 internal ↔
  per-server rating conversions, shared with the Library Browser's ART-mode star row
- `WinampModernContainerTopology.swift` — `.hostManagedTransient` suppression for notifier containers
- `WasabiTextMetrics.swift` — `content(of:host:)` resolves `text ?? default` for text elements

