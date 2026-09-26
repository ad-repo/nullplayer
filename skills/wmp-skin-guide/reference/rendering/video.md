# `.wmz` video: the `<VIDEO>` surface and its host

Moved verbatim from `reference/rendering.md` § *Static scene and image contracts* on 2026-09-25; the router is
`reference/rendering.md`. Before an engine-wide change here, check the counter-evidence table in
`reference/skins/README.md`.

- **A `<VIDEO>`'s `backgroundColor` is a surface inside the window, never part of its shape
  (W312).** The fill carries `WMPPaintCommand.confinedToPaint`, and `WMPRenderer` clips it to the
  alpha already drawn beneath it — this layer and, in the overlay, the layer below. `Navigator`'s
  `#404040` well over bare canvas under the wing is gone; `The Unit`'s, `The_Sentinel_v.1.0`'s and
  `circle`'s black wells over their own artwork are byte-identical. Suppressing the fill while
  `hasVideo` is false would have lost those three.

- **A `<VIDEO>` box shrinks the picture to fit by default and never enlarges it (W102).** The two
  fit flags are independent and neither means crop or fill: `shrinkToFit` governs the picture being
  *reduced*, `stretchToFit` its being *enlarged*, and `maintainAspectRatio` (default true) decides
  whether the two axes scale together. **`shrinkToFit` defaults to true and `stretchToFit` to
  false**, which is not symmetry for its own sake — it is what the corpus is authored against.
  **77 of the 97 sized `<VIDEO>` elements declare no `shrinkToFit` at all and 73 of those are boxes
  under 640x480** (`Heart_Butterfly` is 89x130, `Creed` 131x88, `Cablemusic` 341x215), and **not one
  archive anywhere authors `shrinkToFit="false"`** while 19 author `stretchToFit="true"` and one
  `"false"`. Defaulting the shrink flag off therefore drew every unattributed box at the stream's
  native pixel size, centred and clipped to the middle sliver of a 1080p frame — reported as "the
  video opens at full resolution instead of scaled to the window". The corresponding read defaults
  in `WMPObjectModel` are the same three values, because a skin that reads back a flag it never
  authored must be told what is actually on screen. **This is not `mediacenter.videoShrinkToFit`**,
  which is a different object with its own defaults in `reference/object-model.md`.

- **The picture is lent to the skin as a *child window*, and `isVideoOutputHosted` is our flag while
  being a child is AppKit's fact — they drift apart (W102).** A child window is the isolation that
  makes hosting work at all: VLCKit installs its own output view and sizes that view's *ancestors*,
  so moving `videoPlayerView` into the skin's tree runs the skin's content view away by tens of
  thousands of pixels, while `addChildWindow` keeps a separate layout tree glued to the skin. The
  trap is that the link can go without the flag changing, and `hostOutputWindow` re-parents only when
  `!isVideoOutputHosted`, so nothing puts it back. **Three symptoms that read as three bugs are this
  one cause**: the picture goes black while the audio plays and seeking still works (it fell *behind*
  the skin — a real child window cannot); it lags out of the window frame on a drag (the 10 Hz
  reposition trailing a tick behind); and switching apps fixes it (activation re-collects children).
  `WMPVideoSurface.update` re-asserts the relationship every tick and traces `video reparented` /
  `video reordered above parent` — **if those fire continuously rather than once per incident, the
  repair is masking a call site that keeps breaking the link, and that is the thing to fix.** Suspect
  anything that orders the parked window out: on macOS that drops its parent relationship.

- **Video readiness has two consumers and they need different truths (W124).** `WMPHostSnapshot.video`
  is the live drawable state: when VLC drops `hasVideoOut` or `videoSize` during a same-media vout
  rebuild, it must become empty so `WMPVideoSurface` detaches the child window and releases mouse
  capture. `WMPHostSnapshot.videoEvent` is the last valid state for `videostart`/`videoend` edges,
  latched by media identity and cleared by a media change or `didReachEndOfMedia`. Feeding the
  latched event state back through `video` kept the child window over the skin and made buttons look
  globally dead when the track panel had pointer capture. Test the split state: output teardown
  produces no `videoend`, the surface detaches, and a genuine media end still produces exactly one.

- **A video's natural end is not a manual Next press.** `WindowManager.videoTrackDidFinish`
  routes WMP completion to `AudioEngine.wmpVideoTrackDidFinish`, which shares the audio engine's
  natural-end repeat/shuffle/queue-exhaustion rules without running audio reporters or gapless
  promotion. Manual `next()` wraps unconditionally; using it at EOF looped a one-video playlist
  forever with repeat off. Keep the new callback gated to `.wmp`. Verified live on 2026-09-10 with
  Corona and a 6.29-second local video: EOF stopped playback, and a subsequent Play click replayed
  it and stopped again.

- **A paused film reports no time, and in `.wmz` mode that was the only thing refreshing the host
  (W102).** `videoDidUpdateTime` is driven by VLC's time-changed callback, so a pause silenced the
  whole host tick and the skin went on drawing *and hit-testing* a pause button. What that costs is
  not a stale glyph: the next click's `mousedown` triggers the rebuild that finally sees `paused`,
  the button under the pointer is swapped mid-gesture, and `WMPMainView.mouseUp`'s
  `result.activated == capturedTarget.stableID` guard drops the click — **the click is destroyed by
  the state change it triggered**, reported as "play then pause then play just breaks it".
  `videoDidChangePlaybackState` closes it, gated to the WMP family. **The general rule this leaves:
  any state a skin hit-tests against must be pushed when it changes, never sampled on the next
  rebuild** — a rebuild driven by the very gesture that needs the old geometry will always eat that
  gesture.
