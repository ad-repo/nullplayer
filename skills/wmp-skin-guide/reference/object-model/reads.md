# `.wmz` object model: what a property read answers

Moved verbatim from `reference/object-model.md` on 2026-09-25; that file is the router. Read it first.

## What a property read answers, and who wins

Three rules, each of which was a live defect first:

1. **An element answers the geometry it is *drawn* at.** Every transaction is handed
   `WMPScene.scriptGeometry` — the local frame of every node the last scene resolved — and element
   state is synced from it before anything runs. WMP's `element.height` includes a height that came
   from background artwork or an alignment stretch, and a script tests exactly that: Corona's
   `ResizeY` animates `svVideo` to 0 and **gives up on the first tick if it reads 0 to begin with**,
   which is what an authored-attributes-only model reports for an element sized by its bitmap.
2. **A script value outranks the markup.** `visible` is resolved from the override before the
   authored attribute — Corona's `SetPane` switches its video and visualization panes purely by
   writing `vid.visible` / `vis.visible`, and a builder reading only markup draws whichever the
   author left on.
3. **A script value outranks the artwork's natural size.** The intrinsic size of a background bitmap
   fills in an *unstated* dimension; it never overwrites one the skin computed. It did, and every
   rebuild stamped 241 px back over the height the script had just set.
4. **Artwork is a scripted property like any other, and the view root is not an exception.**
   `WMPSceneBuilder.resolveResource` used to read the authored attribute alone, so images were the
   single property class the override path skipped while geometry, colours, slider metrics and text
   all went through it (W75). `Alienware Invader` hides its whole player behind a 568-frame intro
   whose every tick is `mainBack.backgroundImage = "png24/intro_anim_f<N>.png"`, and its `mainView`
   drew **nothing at all** until the override was consulted. Three rules the fix is made of, and each
   is a way of getting it wrong:
   - The override carries an **authored path string**, so it resolves through
     `archive.resolve(_:relativeTo:)` under the same provider rules as markup. It is not a file path
     and it is not trusted.
   - A path the skin does not contain **warns (`WMP0023`) and leaves the authored artwork in place**.
     A mistyped frame name must never blank a node that has something to draw.
   - `""` is an **authored absence**, not a missing file: it clears that name the way an absent
     attribute does, which is how every store-thumbnail `previewView` drops its splash bitmap
     alongside the zero-size collapse. `view.backgroundImage` is on the `view` compatibility list for
     that reason — the view root resolves it like any other node, so the tally must not call it
     unknown.

   The image store keys its cache on the canonical resource path, so a scripted swap is a different
   key and a different decode; the scene owns no image state of its own.

6. **A host path has more than one resolution, and a member being live does not make the binding
   live (W162).** `player.status` reaches the skin three ways — the object-model member
   (`metadata.value = player.status`), the `wmpprop:player.status` binding a `<TEXT>` authors, and
   the `status_onchange` argument — answered by `WMPObjectModel.readPlayer`,
   `WMPObservablePropertyRegistry.value(path:kind:snapshot:)` and
   `WMPMainWindowController.arguments(for:_:)` respectively. All three read
   `WMPHostSnapshot.statusText`, which is where a new host string belongs: it was possible for the
   member to answer and the readout to stay blank because the registry had no case for the path, and
   that is exactly how `Windows_XP_Media_Center_Edition`'s `STATUS:` line shipped empty. **Adding a
   host property means checking all three**, and any new one has to state whether an event argument
   exists for it at all.

   The wording is WMP's status-bar sentence — `Playing`, `Paused`, `Stopped`, and `Ready` before
   anything is open — and it is free to be a sentence because **not one of the corpus's 128 uses
   compares it against a literal**. Every one prints it, either into a readout or in front of the
   track name. **There is no `Buffering (n%)` case** although WMP spells one:
   `snapshot.bufferingProgress` is 0-100 with 100 meaning *full* and nothing outside the harness
   writes it, so a `< 100` test would report every skin permanently buffering on the default `0`.

7. **`WMPImage_AlbumArtLarge` and `WMPImage_AlbumArtSmall` are WMP-owned pseudo-resources.** They
   resolve before archive lookup and are backed only by the current track's artwork, asynchronously
   loaded by the WMP session from local tags, supported servers, or a stream artwork URL. They are
   200px and 75px square respectively, preserve aspect ratio, and draw transparent until artwork
   arrives. The skin never receives a URL, token, `Track`, or any other host object. No other
   `WMPImage_*` spelling is accepted: in particular `WMPImage_AdBanner` remains unresolved because
   NullPlayer has no equivalent surface.

8. **`player.fullScreen` is the Player's own member, and `playState` tells the truth while a media
   opens (2026-09-20).** Two halves of one live defect, reported as *"when i start the video the
   video player window does not open"* and *"the video adjustment drawer is open by default"* on
   `ALXMorph`.

   - **`player.fullScreen` (read and write).** It existed only on the `<VIDEO>` element, so the
     Player spelling was `UNRECOGNISED` — and an unrecognised member **throws and takes the rest of
     the handler with it**. `alienware.js`'s `onChangeVidPlayerState()` reaches
     `if(!player.fullScreen){ checkSnapStatus(); }` from `onLoadVid()`, so the four statements after
     it never ran, `toggleVidDrawer('0')` among them — which is the call that closes the video
     settings drawer at load. **35 of the installed archives read or write it**, every
     Alienware/ALX frame among them. The read answers `snapshot.video.fullScreen`; the write posts
     the same `setVideoFullScreen` host command the element's own `fullScreen` write does, so the
     two spellings drive one picture.
   - **`WMPHostSnapshot.State.transitioning` → `playState` 9 (`psTransitioning`).** VLC reports no
     picture size for a few hundred milliseconds after `play`, and the engine was calling that
     interval `playing`. A `.wmz` that checks — and this family is the corpus's most-shared example
     — reads `playState == 3` with `imageSourceWidth == 0`, concludes the media has no picture, and
     calls `view.close()` **in the `onLoad` of the window the app has just opened for it**: the
     skin's video window opened and shut itself inside 200 ms and the user saw nothing open at all.
     The state is emitted only from the local-video branch of `WMPAudioEngineHost.snapshot`, while
     `video.isPlaying` is true and `hasVideoOutput`/`presentationSize` are not yet; it answers as
     *running* everywhere else in this engine (`State.isRunning` — transport availability, the
     `<EFFECTS>` tap, the unskinned player), so the only thing that can see it is a skin asking
     `player.playState`. The `playstatechange` edge to `playing` on the tick the decoder answers is
     what then reveals the picture, which is WMP's own sequence.

   **The lesson worth keeping: deferring the open is not the fix, and it deadlocks.** The first
   attempt held the reveal back until the picture had a size — and VLC produces no output until it
   has a window, so the window waited on a picture that was waiting on the window, and the view
   never opened again in any run. The engine has to open the window and *describe the state
   honestly*; it must not wait for a decoder it is starving.

## An unanswered `wmpenabled:` can delete a control, not grey it (W255)

`WMPObservablePropertyRegistry` owns both `wmpprop:` and `wmpenabled:`, and its `enabled` table is a
literal `switch` over paths with `default: return nil`. `unansweredValue` turns that nil into
`.bool(false)` — the right default, because a control this engine cannot drive should look dead
rather than claim a feature that is not there.

**What that default does not account for is a control that mirrors `visible` onto its own `enabled`.**
`Revert` authors

```xml
<slider id="seek" enabled="wmpenabled:player.controls.seek" visible="wmpprop:seek.enabled" … />
```

A `visible="wmpprop:<element>.<property>"` is answered from the skin's own graph by
`WMPSceneBuilder.mirroredVisibility` — **150 of the corpus's `visible="wmpprop:…"` attributes name an
element rather than a host path** — and here the element it names is the slider itself. So the false
`enabled` became a false `visible`, and the builder deletes a node whose `visible` override is false:
`vwPlayer` built **12 nodes with no `slider` among them**. Not a greyed-out seek bar. No seek bar.

Two consequences worth carrying:

- **A missing control and a dead control are the same bug here.** When a report says a control *is
  not there*, the `enabled` table is on the list of places to look, not just the hit map and the
  layout. `WMP_RENDER_PROBE` answers it in one run: the node is simply absent from the dump.
- **WMP spells some capabilities twice and a skin may author either.** `IWMPControls` carries both
  `currentPosition` and `seek`; the table answered the first and defaulted the second. Before adding
  a row, check whether the capability already has a sibling spelling that *is* answered, and gate
  both on the same snapshot quantity so they can never disagree.

Reach, over 185 archives, decoding script text the way `WMPTextDecoder` does (the census matches
tags, never binding paths, so this needs the script-text scan in `harness.md`):
`pause` 151 uses / 125 skins, `play` 36/30, `stop` 21/17, `previous` and `next` 11/10 each,
`currentposition` 6/6, `fastforward` and `fastreverse` 3/3 each, **`seek` 2/2 — and those two are
`Revert` and `Revert (1)`, the same markup, so one skin.**
