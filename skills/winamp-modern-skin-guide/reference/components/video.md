## The video surface — the picture goes in a **child window**, not a subview (B20)

**15 of the 33 measured `.wal` skins declare a `<container>` for the video component** — chrome, a
`ledstatusbar`, the `VID_*` buttons, and a `<component param="{F0816D7B-…}">` holder — and until B20
every one of them was decoration over an empty box: playing a video opened NullPlayer's own window
somewhere else on screen while the skin's stayed shut.

### Why it is not shaped like `.library`

The obvious shape is the library seam's: move the host's view into the skin's holder. **It does not
survive contact with the video engine.** VLCKit installs its own output view under the player's host
view and sizes *that view's ancestors*, so the skin window's content view ran away at +46pt per
layout pass — measured from 372 to 14,219 in 80ms — and the picture did not appear at all until
something else forced a relayout.

So the surface holds only a **black box the skin lays out**, and
`VideoPlayerWindowController` parks its **own window** over that box with `addChildWindow`. AppKit
gives a child window its own layout tree, so nothing the decoder does can reach the skin's, while the
child follows the parent's moves, hides and closes for free. It is also what answers the lifetime
question: the video window is mode-independent and preserved across `reloadUI`, so parking rather
than owning means a layout switch, a skin switch or a mode switch *unparks* it — still playing —
instead of tearing the player down with the skin.

### The trap that cost the most: a window minimum derived from Auto Layout

`window.setFrame` **silently refuses** any size below the minimum AppKit derives from required
constraints in the window's content, and there is no error — the window simply comes back a different
size. `VideoControlBarView` lays its controls out with a required chain
(`10+30+5+30+5+30+5+30+10+50` leading, `10+30+5+30+5+30+10+50+10` trailing) that sums to exactly
**395pt**, so every parked frame narrower than that was quietly widened and the picture ran out
through the skin's own chrome. **A hidden view's constraints are still live** — `isHidden` does not
help; the bar has to leave the view hierarchy.

Two rules follow, and both are load-bearing:

- **`showsControlBar` adds and removes the bar from its superview**, it does not hide it.
- **The surface gates the bar on the box**: it goes in only when the holder asked for it *and* the box
  is at least `controlBarMinimumWidth` (the bar's own `fittingSize`, not a number written down
  twice). Ask for the frame again straight after the bar leaves — the refusal happened while the
  minimum was still in force.

When debugging any "the hosted thing is the wrong size" report, **compare the frame asked for against
`window.frame` afterwards**. A DEBUG log in `updateHostedOutputFrame` does exactly that
(`video: box … refused, window took …`); it is the line that ended this defect after three wrong
theories.

#### A `refused` line on its own is not a defect — measured 2026-09-03

The refusal still shows up in the log on every skin measured, and **that is expected**, not a
regression. Recorded on 2026-09-03:

| Skin | Box asked for | Window took |
|---|---|---|
| multipass | `{332, 113}` | `{395, 113}` |
| cPro_MMD | `{278, 272}` | `{395, 272}` |
| Enkera | `{308, 228}` | `{395, 228}` |

**The picture is correct in all of them.** Checked in the running app on multipass and cPro_MMD —
the latter the largest gap of the three at 117pt, which is the case that would show it worst — and
the video sits in its window properly in both.

The reading that fits: this is the **first** ask, made while the control bar is still in the
hierarchy and its 395pt minimum still in force. That is precisely the refusal the retry above exists
to absorb — the bar leaves, the frame is asked for again, and the second ask is the one that lands.
A `refused` line is therefore evidence of the mechanism working, not of a mis-sized picture.

Two things follow for anyone reading this log in future:

- **Do not infer a visible defect from the `refused` line.** It was read that way once, and a
  backlog entry was filed and then withdrawn on the strength of actually looking at the app. The
  line reports one ask, not the final frame.
- **The check is the frame *after* the retry**, not the refusal. If the picture really is wrong, the
  window will still be 395 wide once the bar has left — that is the state worth capturing, and it is
  not what was measured above.

Aspect-fit is why a too-wide window is benign anyway: surplus width becomes letterboxing, never a
clipped or stretched picture. multipass's box is a 2.9:1 slot that a 16:9 film is already
height-constrained inside, so widening it changes nothing on screen.

### The picture's clock is not the audio engine's (B63)

`WindowManager.videoPlaybackDidStart()` **pauses `AudioEngine`** for the whole of a film. So a host
that answers `playbackState`, `currentTime`, `duration` and `trackTitle` from the engine alone reports
a skin's transport as *paused* and its readout as *0:00* while the picture plays in plain sight — and
in an embedded surface the picture is the thing the user is looking at, in the same window as the
frozen clock. Classic and Original never had this: their views substitute
`WindowManager.isVideoActivePlayback` at every draw.

`WinampModernAudioEngineHost.videoSession` is the same substitution made **once, at the host** — the
seam every `.wal` readout, script binding and `getPlayItemMetaDataString` key already passes through,
so a `<text display="time">` the renderer draws and a `timeelapsed` a script writes cannot disagree
about how far into the film it is. Two details are load-bearing:

- **It is keyed on the video's title, not on `isVideoActivePlayback`.** That property's
  `isVideoOutputVisible` term goes false the moment the picture is unparked — which is exactly the
  state a film left running behind another tab is in, and the one where the clock must keep ticking.
- **It is a closure, re-read on every access.** The value is polled ten times a second; a snapshot
  taken when the skin loaded would freeze the readout at whatever it said then.

The transitions have no callback of their own — `videoPlaybackDidStart` fires once and *nothing at
all* reports a pause — so `WinampModernMainView.updateTime` compares the state against
`lastPlaybackState` each tick and calls `updatePlaybackState()` when it moved. That is what gets a
paused film's play/pause artwork repainted and its `onPause` / `onResume` to the skin's scripts. The
clock keeps ticking while a film is paused (the video view's time observer is a plain repeating
timer), so the comparison is actually reached.

### The skin's transport drives the **film**, not the engine behind it

B63 substituted the *readouts*; the **commands** kept going straight to `AudioEngine`, so in every
skin the play/pause button, the stop button, the seek slider and PREV/NEXT did nothing to the picture
(cPro-Bento included — it looked closest only because its readout happened to bind the one substituted
string). One seam fixes every skin at once: **every** `.wal` transport path funnels through the six
`WinampModernHost` methods — `<button action="PLAY">`, MAKI `System.play()/pause()/stop()/seekTo()`,
the seek slider drag and the waveform seeker — so `WinampModernAudioEngineHost.videoTransport` is
consulted there and the engine is the fall-through:

```swift
func play() { if let v = videoTransport() { v.togglePlayPause() } else { engine.play() } }
```

- **Keyed on the session, not on `isVideoActivePlayback`** — the same key `videoSession` uses, so a
  skin can never take commands for a session whose clock it is not reading, and a film left running
  behind another tab (where `isVideoOutputVisible` is false) still takes its transport.
- **PLAY and PAUSE both toggle.** That is what Classic does: a skin's single play/pause button sends
  whichever of the two its artwork currently shows, and either has to flip the film.
- **PREV/NEXT skip ∓10s**, mirroring Classic — which means a *video playlist* advances only on a
  film's own end, never from the skin's NEXT button. An accepted parity limit, not an oversight.
- The four commands map onto `WindowManager.toggleVideoPlayPause/stopVideo/skipVideoForward,Backward/
  seekVideo(to:)`, each of which already forks cast-vs-local.

**And the rest of the readouts follow the film too.** `trackDisplayTitle` is the important one: it is
what `display="songname"` binds to, the readout most skins print, and it read `engine.currentTrack`
with no substitution at all — so most skins showed the *previous audio track's* title through a whole
film. Everything else (`trackInfo`, `trackArtist/Album`, `trackPath`, `decoderName`, `bitrateKbps`,
`sampleRateHz`, `channelCount`, `trackMetadata`) answers **empty/zero** during a session, which makes
a skin *hide* those lines rather than print a stale track's — the same "never invent a placeholder"
rule `playItemMetadata` follows. `albumArtwork` and `isArtworkLoading` key on the video controller's
`currentArtworkTrack` instead. Because `playItemMetadata` is table-driven off `trackTitle`/`trackArtist`/
`trackAlbum`, all eighteen of Big Bento's file-info keys follow for free, as do
`System.getPlayItemDisplayTitle()` and the two other `trackDisplayTitle` bindings.

### A finished film is not a session — in `.wal` only

Nothing clears `currentTitle` at natural end of media: `clearLoadedContentState()` has four call sites
and end-of-media is not among them, and `videoPlaybackState` can never answer `.stopped` while a
controller exists. So a dead film reads `.paused` **forever**. Before the transport was routed that
was a stale readout; after it, it would be a permanent transport lockout — every `.wal` command
driving a corpse, with no way to start audio from the skin again.

**Clearing the session was rejected.** `currentTitle` and `isVideoActivePlayback` are shared state
Classic and Original read, and their behaviour cannot change. So the session stays and the **`.wal`
host alone disregards a finished film**, through an additive
`VideoPlayerWindowController.didReachEndOfMedia` that no code outside `WinampModern/` reads:

- set **true** in the existing `onPlaybackFinished` handler, and only for the non-playlist case;
- set **false** in `updatePlayingState(true)` — the funnel every playing transition goes through,
  which is what makes "seek back past the end and press play" restore the session;
- set **false** in `clearLoadedContentState()`, so a new film never inherits the old one's end.

Both `videoSession` and `videoTransport` guard on it. Classic keeps the phantom on purpose — recorded
as **B107** in `TASKS.md`, not fixed under a `.wal` pass. Cast video is out of scope: `currentVideoTitle`
forks to `CastManager.videoCastTitle` for a cast session, which the flag does not cover.

One DEBUG line makes the re-host observable in a running build, and it is load-bearing when a report
says "the picture did not follow the skin":

- `WinampModern: re-hosting film after skin load hosted=<0/1>` — the re-offer below, and whether the
  new skin took the picture.

**There is deliberately no trace on the latch itself.** `updatePlayingState` is in
`VideoPlayerWindowController`, which every mode shares, so a `#if DEBUG` `NSLog` there fires during
Classic and Original playback too — noise in their logs for a `.wal` concern. One was added during
the pass and removed on 2026-09-03 for that reason. If the latch needs instrumenting again, put the
probe on the `.wal` side that reads the flag, not in the shared controller that sets it.

### A skin switch has to re-offer the picture

The only two routes that park a picture are a **play** call and a video holder *reappearing* (the tab
switch). A skin switch is neither, so a film already running when a new skin loaded stayed in
NullPlayer's own window while the new skin's video window sat empty beside it. Only cPro→cPro looked
right, and only because a cPro tab strip re-creates its holder; a `declaredContainer` skin has no
holder until its window opens, so that path never fires for it.

`WinampModernMainWindowController.rehostVideoOutputIfPlaying()` closes it, from **one** call site —
the end of `loadSkin(at:)` — and `hostVideoOutput()` already knows how to ask *any* skin what it
declares, so nothing here is per-skin. That single site covers `.wal` → `.wal` switches (including
into the placeholder on the failure path, where "the skin declares no video" is the right answer)
**and** `reloadUI` / mode switches back into Winamp Modern, because a recreated controller loads its
skin: `showMainWindow` builds a fresh `WinampModernMainWindowController` when the controller is nil,
and touching `.window` forces the load whether or not the window is revealed.

**Do not add a second call from `WindowManager`.** One was written and removed on 2026-09-03. Inside
`recreateModeDependentLayout` everything below runs in a single runloop turn:

1. `showMainWindow(reveal:)` — the fresh controller loads its skin, which schedules the re-host **one
   turn later**;
2. the main window's `setFrame` for the incoming mode;
3. the sub-windows are restored;
4. `pushCurrentPresentationStateToRecreatedWindows()`;
5. `makeKeyAndOrderFront` / `orderOut`.

A call placed at (4) is therefore the *early* one, not a safety net: it asks before the window is
ordered front and before the skin's own resize and layout cascade have settled — the exact condition
the async hook exists to avoid — so it either answers `false` or parks a mis-sized box, and the
`loadSkin` hook silently corrects it afterwards. Keeping the single async site also keeps the whole
re-host inside `WinampModern/`, with no shared-code touch at all.

Three rules it obeys:

- **Guarded on `currentTitle`, not on "is playing"** — a *paused* film re-hosts on the same terms —
  and not on `isVideoActivePlayback`, whose `isVideoOutputVisible` term is false in exactly the
  unparked state a mode switch leaves behind.
- **Re-parented, never re-opened.** `VideoPlayerWindowController` and its VLC pipeline survive the
  switch untouched, so the film keeps playing and the clock the skin reads carries straight on.
- **One runloop turn after the load**, so the skin's own `onScriptLoaded` resizes and layout cascade
  have settled — the same reason `hostVideoOutputInPlayer` re-places asynchronously.

Switching *out* needs nothing: `tearDownSkin()` → `releaseVideoSurface()` → `prepareForUITeardown()`
already unparks and reveals a still-running film, which is what makes the round trip through a
no-video skin work.

### A holder leaving is a tab switch, not the end of the film (B63)

For a **window**-hosted surface, the holder only ever goes away with the scene, and handing the
picture back to NullPlayer's own window is right. For an **embedded** one it is not: cPro-Bento's tab
strip removes and restores that holder all session long, so `detachVideoOutput()`'s reveal popped our
video window out over the skin every time the user left the Video tab — which reads as the player
escaping, not as the picture being put away.

So the video surface joins the library and visualization surfaces in keeping the two paths apart, on
a different axis than they do (see [components.md](../components.md) → *Unmounting is not teardown*):

- `unmountFromHolder()` — unpark and **stay hidden**. The film plays on, unseen.
- `prepareForUITeardown()` — unpark and **reveal** if a film is still running. The scene is going;
  there is no tab to come back to.

Unparking either way is not optional: the one video view in the app must never be left orphaned in a
view that is about to leave the hierarchy.

Hiding only works because something parks the picture back. `reconcileHostedSurfaces` watches for a
video holder *appearing* — that is the tab being switched to again, and the only other route that
parks a picture runs on a **play** call, which will not come, because the film has been playing all
along. It re-attaches one turn later (after a layout pass, which is what gives the returning box its
frame) and asks `hostedVideoSurface` for the target, so the largest visible box wins exactly as it did
the first time.

### The rest of the shape

- **Routing.** `.video` is a **routed** surface but not a **managed** one
  (`WinampModernSurfaceInventory.routedKinds` vs `managedKinds`). Never synthesized — a skin that
  draws no video window is served by the host's own. Embedded **only** when the skin declares no
  visible video window of its own (B23): Winamp Modern's player also declares an invisible in-player
  `windowholder` for the component, and resolving there would leave the skin's real video window
  empty, so a skin with a visible one keeps it. cPro-Bento is the case the exception exists for — its
  video lives in an SUI tab and its standalone `Video` container is a deliberate 1×1 stub. So the
  catalog answers `.embedded`, `.declaredContainer` or `.classicFallback`.
- **`autoopen` / `autoclose`.** Playing reveals the skin's video window; stopping hides it and
  unparks, so no child window is left hanging off a skin window a mode switch may take away.
- **Casting never resurrects a local window.** Every `play*` entry point returns before reaching the
  video controller when a cast device is active, so the skin path is never entered.
- **Fullscreen** unparks first (a child window cannot go fullscreen), and re-parks **one runloop turn
  after** `windowDidExitFullScreen` — AppKit is still restoring the window's own frame as the
  notification lands, and re-parenting inside that leaves it parked at the fullscreen size.
- **The box carries no autoresizing mask** and reports its own geometry (`setFrameSize`,
  `setFrameOrigin`, `viewDidMoveToWindow`) so the parked window follows whatever moves it. Pushing
  placement from the layout pass alone leaves the picture behind on every path that moves the box
  without one.
- **Drag and resize zones are off while parked.** Both belong to the free-floating window; inside a
  skin's box they slide or stretch the picture out of the hole it is filling.
- **`VID_1X` / `VID_2X`** were inert before this (nothing read `presentationSize`). They size the
  *skin's* window so the box is the stream's own pixel size times N, clamped to the visible screen as
  well as the layout's range — Winamp's 1x on a 1080p film is a ~1940pt window, which is faithful but
  must not run off the display.
- **A declared container with no holder** (Hoop_Life_WA3, Media_Whore) routes but has no box;
  `hostVideoOutput()` answers false and the host's own window takes it. That is the correct outcome,
  not a gap.

### The corpus, measured

`cmdbar=` is the holder's `noshowcmdbar=` decoded (`WinampModernVideoHolder.showsCommandBar`).

| Skin | Box (skin px) | cmdbar |
|---|---|---|
| hatsune_miku_5 | 429×340 | 0 |
| Ujola Cat | 390×91 | 0 |
| mmd3 | 375×190 | **1** |
| winampmodern566 | 342×232 | 0 |
| multipass | 332×113 | 0 |
| corneramp_redux | 310×164 | 0 |
| Styx | 284×59 | 0 |
| Itemskin | 277×71 | 0 |
| Anaheim_Player_01 | 240×120 | 0 |
| Love is War Miku | 240×184 | 0 |
| Love Is War Miku V2 | 240×190 | 0 |
| Ebonite_2_1 | 227×172 | 0 |
| BLAKK | 192×125 | **1** |
| Hoop_Life_WA3, Media_Whore | declared, **no holder** | — |

Only mmd3 and BLAKK ask for the command bar, and both boxes are under 395pt, so **no skin in the
corpus actually gets one** — the gate decides every measured case in favour of the picture fitting
its box.

