# Audion face windows: the face's own, and NullPlayer's beside it

Read `../SKILL.md` first; its isolation rule binds every section here. The policy these implement is
`docs/audion-face/phase-0-decision-record.md` § *Auxiliary-window policy* and § *Button mapping*.

## The face window (`Windows/AudionFace/`)

| File | Owns |
|---|---|
| `AudionFaceMainWindowController.swift` | `AudionFaceWindow` (borderless, clear, key/main-capable) and the `MainWindowProviding` controller: loads the selected face off the main thread, swaps between the face and the unskinned view, sizes the window to `base` × UI scale keeping the top-left, holds `surfaceStyle` |
| `AudionFaceMainView.swift` | Draws `AudionFaceRenderer.render(AudionFaceScene(...))` as layer contents at `ceil(uiScale × backing)`; the frame clock; hit-tests; drags; the two slider popups and the info menu; keys; right-click menu; accessibility |
| `AudionFaceSliderWindow.swift` | FaceKit's `AudionSliderWindow`, ported (Panic's header): a borderless popup holding one `NSSlider`, closed when it resigns key |
| `AudionFaceAudioEngineHost.swift` | `AudioEngine` → `AudionFaceHostState`, and an `AudionFaceCommand` (a button, a volume, a seek) → its NullPlayer action |
| `AudionFaceUnskinnedView.swift` | The app-authored fallback when no face is selected or the selected one fails |
| `AudionFace/AudionFaceImporter.swift` | Installed faces, the `audionFaceName` selection, folder/zip install (validate the copy, then one move), remove |
| `AudionFace/AudionFacePalette.swift` | The `SkinnedSurfaceStyle` NullPlayer's windows wear beside a face |

- **Hit testing:** a pixel whose rendered alpha is 0 is not the window (`hitTest` returns nil);
  then the topmost visible button by `AudionFaceScene.button(atX:y:face:host:)`, a hit only if
  `AudionFaceScene.isEnabled` (the rule `buttonOps` draws the disabled sprite by: stop needs a
  track, and `interaction.disabled`); then, with a track, a time digit (`AudionFaceScene.timeDigitRects`)
  opens the position slider; anything else drags. `drag.png` is not read: every opaque non-button
  pixel drags, a superset of the authored drag region, and FaceKit ignores the file too (decided in
  Phase 4; `format.md` § *Files FaceKit ignores*).
- **Drag** goes through `WindowManager.windowWillStartDragging` / `windowWillMove` /
  `windowDidFinishDragging` (`AudionFaceWindowDrag`, used by both the face and the unskinned
  view), and `windowDidMove` applies the snapped position, the Classic recipe — so snapping and
  docked groups work. AppKit's background drag is off for the window and both views.
- **Shadow:** AppKit's own (`hasShadow`), not `SkinWindowShadow`; `hostsSkinShadowWindows` is
  false for Audion. `invalidateShadow` runs on every redraw on purpose: the outline is mostly the
  face's, but an animation frame clears the base under it, so a state change can reshape it.
- **Buttons** (decision record § *Button mapping*): play, pause, stop, rw/ff (previous/next), eject
  (Open Files…), menu (toggle the playlist), close (quit, as every NullPlayer main window's close
  does), mode (shuffle and repeat as a two-bit counter: off → shuffle → repeat → both → off). Volume
  and info are the view's own: volume opens the vertical slider (19 × 96, FaceKit's size) at the
  engine's volume, read when it opens (no face draws volume, so it is not in the host state), with its
  top-left at the button's bottom-right, and the button stays disabled (`interaction.disabled`)
  until the slider closes; info pops a menu of **About Playing…** (`MenuActions.showAboutPlaying`,
  the app's track info) and **About This Face…** (an alert with `faceInfo` and `about.png`).
- **Position slider:** 192 × 19 under the clicked time digit, range `0…duration`, only while
  `AudionFaceHostState.isSeekable` (a live stream counts as a track but has no position). A scrub
  pauses a playing track, seeks on every move, and resumes on mouse-up (FaceKit `adjustTime`) or,
  for a change with no mouse-up (keyboard, VoiceOver), when the popup closes.
- **Commands refresh the host:** the controller re-snapshots `AudionFaceHostState` after every
  `AudionFaceCommand`, so a seek while paused shows at once.
- **Frame clock:** a 60 Hz `Timer` (common run-loop modes) advances the scene's `frame` only while
  `AudionFaceScene.isAnimated` (a multi-frame animation, or an album line that scrolls) and the
  window is visible (`windowDidChangeOcclusionState`). Every tick re-renders the whole face; dirty
  rects are Phase 6's. The tick count is never reset, as FaceKit's is not, so a new track's
  marquee can start mid-cycle.
- **Stream phase:** radio's `RadioManager.connectionState` picks connecting (connecting),
  lag (reconnecting) or streaming; the controller observes
  `RadioManager.connectionStateDidChangeNotification`. Any other non-file track reads as streaming:
  a server stream's buffering is private to `AudioEngine`.
- **Keys** are the Modern main window's, through the one shared `MainWindowKeys.perform` (`App/`),
  video routing included. Menu key equivalents reach
  the main menu as in any window. The view takes first responder when it joins the window.
- **Accessibility** (FaceKit's elements): one button per visible face button (`audion.<sprite>`,
  labelled with FaceKit's tooltip or NullPlayer's action, enabled by `isEnabled`, pressable), the
  time digits as one button (`Time Digits`, label `mm:ss — Show Position Slider`, press opens the
  slider, disabled unless `isSeekable`), and the artist and album lines as static text with their
  string as value. The elements are kept by identifier across calls, so VoiceOver's focus survives a
  redraw; a new face drops them.
- **Not done:** FaceKit's hover tooltips on the buttons and time digits.

## Shared-code seams

Every change outside the family's directories, each gated on the Audion family.

| Seam | Audion answer | Why not local |
|---|---|---|
| `PlayerUIMode.audion` / `PlayerUIControllerFamily.audion` | display name "Audion Faces"; no modern EQ, no modern skin family | the mode enum is the routing seam |
| `AppFeature.audionFaceMode`, `AppCapabilities.supports` | true only in DEBUG; `PlayerUIMode.isAvailable` reads it, and `reloadUI`, `argumentOverride` and the init-time stored-mode check refuse an unavailable mode | the one capability seam |
| `PlayerUIControllerFamily.hostsForeignSkin` | true, as `.wal`/`.wmz`: NullPlayer's windows float free — `appliesPlacementRecovery`, `reopensWhereLeft`, `positionSubWindow`'s tiling, no slide-up on close, no library refit, library reopen keeps its height, `prepareUIRuntime` forgets the Spectrum profile's skin, no compact or main-window vis menu items | one exhaustive switch, so a sixth family is a compile error, not a silent Classic answer |
| `PlayerUIControllerFamily.bringsOwnRuntime` | true, as `.wmz`: no default Classic skin load at init, `prepareUIRuntime` returns early, Compact Mode/Window unavailable (4 `WindowManager` guards, `AppDelegate`), `playlistChromeScale` is the app scale, `tightenClassicCenterStackIfNeeded` skipped, restored centre-stack frames kept | as above |
| `WindowManager.makeMainWindowController` / `runningControllerFamily` | `AudionFaceMainWindowController` | factory |
| `auxiliaryControllerStyle` | `.wmp` — the shared NullPlayer controllers, chrome from `hostedSurfaceStyle` | |
| `hostedSurfaceStyle` → `audionSurfaceStyle` | the controller's face palette, neutral before a face loads | the one style seam |
| `hostedSkinIdentity` | the loaded face folder, so the Spectrum vis_classic profile follows the face | |
| `SkinnedSurfaceChrome.hidesPaletteTitleBar` | true: titleless gloss frame, as `.wmz` | |
| frame-lending switches (`hostedSurfaceFrameArtwork`, `…BorderInsets`, `…Settled…`, `demand…`, `prewarm…`, `…LiveResize`) | lends nothing | a face has no frame to lend |
| `hostedInteriorScope` | `"audion"` | |
| `hostsSkinShadowWindows` | false (native shadow, above) | |
| `managedWindowRecords` | main window is a snap target, not a centre-stack member | a face has no column |
| `applyDoubleSize` | `SkinSizedMainWindow` (with `.wal`/`.wmz`): `applyUIScale`, size `base × scale` | |
| `snapToDefaultPositions` | `snapHostedFamilyToDefaultPositions(playerWindow:skinWindows: [])`, the body shared with `.wmz`; it holds `isSnappingWindow` and posts the layout change itself | |
| fallback main size | `AudionFaceMainWindowController.unskinnedSize` | |
| `VisualizationPreferences` reset | the `.wal`/`.wmz` arm | |
| `ContextMenuBuilder+SkinFamilies` | `buildAudionFacesMenu`, `groupedAlphabetically` (A–Z past 40), `RemovableSkin.audion`, actions | |
| `AppStateManager` | `audionFaceName`, saved only in Audion mode; frame restore keeps the top-left | |
| `AppDelegate` | `-audionFacePath`; the acceptance loop's arm | |
| `App/MainWindowKeys.swift` | the face's `keyDown` calls `MainWindowKeys.perform` | **not gated**: the Original (`ModernMainWindowView`) key switch moved there verbatim and both call it, so the face cannot drift from it again |

## NullPlayer's windows beside a face

`AudionFacePalette.surfaceStyle(for:)` samples the face **as drawn** — stopped, through
`AudionFaceRenderer`, so the mask has cut it to its window: ground = the dominant colour under the
album (else artist) display rect; text = the album colour; current text = the artist colour;
selection = the face body's dominant colour. A display counts only when its rect is wider and taller
than one pixel (`AudionFacePalette.displayed`): 85 faces author a 1×1 box at 0,0 meaning "no display",
whose colour is a default and whose pixel is a corner. Selection must stand 1.3:1 off the ground,
else it is the ground blended 35% toward a text colour that is legible there (the authored one can
be the ground itself), else black or white. `SkinnedSurfaceStyle` runs every foreground through
`legible`. A face change posts `.hostedSurfaceStyleDidChange`, so open windows recolour. The windows
wear the titleless gloss rim. Corpus contrasts and the goldens: `harness.md` § *Palette legibility*.

- **Playlist selected rows** keep the classic idiom — white text, no selection fill — but under any
  hosted style (`.wal`, `.wmz`, Audion) the white goes through `style.legibleText(_:on: background)`
  (`PlaylistView.selectedRowTextColor`); on a light face it was white on white. Classic and Original
  have no hosted style and still get plain white.
- **Route to a track:** the face's menu button toggles the playlist, eject is Open Files…, and the
  Library Browser opens from the Windows menu or the right-click menu.
- **Checked live** (A7, debug build, user confirmed): playlist, EQ, Library Browser and Spectrum
  Analyzer beside AppleClassic, Cracked, Chromium, Smart and >maxk_typo<.

## Docking

The face window is a snap target. NullPlayer's windows tile beside it through the shared tiler on
first open and stay where the user leaves them; `AUDION_PLACE_TRACE` (`harness.md`) logs each
placement.
