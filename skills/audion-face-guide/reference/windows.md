# Audion face windows: the face's own, and NullPlayer's beside it

Read `../SKILL.md` first; its isolation rule binds every section here. The policy these implement is
`docs/audion-face/phase-0-decision-record.md` § *Auxiliary-window policy* and § *Button mapping*.

## The face window (`Windows/AudionFace/`)

| File | Owns |
|---|---|
| `AudionFaceMainWindowController.swift` | `AudionFaceWindow` (borderless, clear, key/main-capable) and the `MainWindowProviding` controller: loads the selected face off the main thread, swaps between the face and the unskinned view, sizes the window to `base` × UI scale keeping the top-left, holds `surfaceStyle` |
| `AudionFaceMainView.swift` | Draws `AudionFaceRenderer.render(AudionFaceScene(...))` as layer contents at `ceil(uiScale × backing)`; hit-tests; drags; right-click menu |
| `AudionFaceAudioEngineHost.swift` | `AudioEngine` → `AudionFaceHostState`, and a pressed button → its NullPlayer action |
| `AudionFaceUnskinnedView.swift` | The app-authored fallback when no face is selected or the selected one fails |
| `AudionFace/AudionFaceImporter.swift` | Installed faces, the `audionFaceName` selection, folder/zip install (validate the copy, then one move), remove |
| `AudionFace/AudionFacePalette.swift` | The `SkinnedSurfaceStyle` NullPlayer's windows wear beside a face |

- **Hit testing:** a pixel whose rendered alpha is 0 is not the window (`hitTest` returns nil);
  then the topmost visible button by `AudionFaceScene.button(atX:y:face:host:)`; anything else
  drags. Stop with no track is not a hit. `drag.png` is not read yet: every opaque non-button
  pixel drags, a superset of the authored drag region. Narrowing it to `drag.png` is Phase 4's.
- **Drag** goes through `WindowManager.windowWillStartDragging` / `windowWillMove` /
  `windowDidFinishDragging`, and `windowDidMove` applies the snapped position, the Classic recipe —
  so snapping and docked groups work. AppKit's background drag is off for the face view.
- **Shadow:** AppKit's own (`hasShadow`, `invalidateShadow` on every redraw), not
  `SkinWindowShadow`. A face's outline changes only when the face (or its active/inactive mask)
  does, which is the case the native shadow handles; `hostsSkinShadowWindows` is false for Audion.
- **Buttons wired in Phase 3:** play, pause, stop, rw/ff (previous/next), eject (Open Files…),
  menu (toggle the playlist). Close, info, volume and mode are Phase 4.
- **Not yet:** the frame clock (marquee, animations), streaming phases beyond "non-file URL is
  streaming", sliders, accessibility — Phase 4.

## Shared-code seams

Every change outside the family's directories, each gated on the Audion family.

| Seam | Audion answer | Why not local |
|---|---|---|
| `PlayerUIMode.audion` / `PlayerUIControllerFamily.audion` | display name "Audion Faces"; no modern EQ, no modern skin family | the mode enum is the routing seam |
| `AppFeature.audionFaceMode`, `AppCapabilities.supports` | true only in DEBUG; `reloadUI`, `argumentOverride` and the init-time stored-mode check refuse it otherwise | the one capability seam |
| `WindowManager.makeMainWindowController` / `runningControllerFamily` | `AudionFaceMainWindowController` | factory |
| `auxiliaryControllerStyle` | `.wmp` — the shared NullPlayer controllers, chrome from `hostedSurfaceStyle` | |
| `hostedSurfaceStyle` → `audionSurfaceStyle` | the controller's face palette, neutral before a face loads | the one style seam |
| `hostedSkinIdentity` | the loaded face folder, so the Spectrum vis_classic profile follows the face | |
| `SkinnedSurfaceChrome.hidesPaletteTitleBar` | true: titleless gloss frame, as `.wmz` | |
| frame-lending switches (`hostedSurfaceFrameArtwork`, `…BorderInsets`, `…Settled…`, `demand…`, `prewarm…`, `…LiveResize`) | lends nothing | a face has no frame to lend |
| `hostedInteriorScope` | `"audion"` | |
| `hostsSkinShadowWindows` | false (native shadow, above) | |
| `appliesPlacementRecovery`, `reopensWhereLeft`, `positionSubWindow`'s `familyTiles` | included: windows tile beside the face, placed once, rescued if unreachable | free-floating, like `.wal`/`.wmz` |
| `managedWindowRecords` | main window is a snap target, not a centre-stack member | a face has no column |
| `tightenClassicCenterStackIfNeeded` | skipped | it would resize the face to Classic's height |
| `handleCenterStackWindowWillClose`, `refitDockedPlexBrowserToVerticalStack` | no slide, no refit | no stack |
| `normalizedCenterStackRestoredFrame`, library reopen | keep saved frames/heights | as `.wmz` |
| `playlistChromeScale` | app scale, not main-width / 275 | a face's width is not a classic zoom |
| `applyDoubleSize` | `controller.applyUIScale`, size `base × scale` | |
| `snapToDefaultPositions` | `snapHostedFamilyToDefaultPositions(playerWindow:skinWindows: [])`, the body shared with `.wmz` | |
| fallback main size | `AudionFaceMainWindowController.unskinnedSize` | |
| init default-skin gate, `prepareUIRuntime` | no Classic skin loaded; early return | never another family's skin |
| compact mode (4 guards in `WindowManager`, `AppDelegate`, two menus) | unavailable | |
| main-window visualization menu | hidden | a face has no vis box |
| `VisualizationPreferences` reset | the `.wal`/`.wmz` arm | |
| `ContextMenuBuilder+SkinFamilies` | `buildAudionFacesMenu`, `groupedAlphabetically` (A–Z past 40), `RemovableSkin.audion`, actions | |
| `AppStateManager` | `audionFaceName`, saved only in Audion mode; frame restore keeps the top-left | |
| `AppDelegate` | `-audionFacePath`; the acceptance loop's arm | |

## NullPlayer's windows beside a face

`AudionFacePalette.surfaceStyle(for:)`: ground = the dominant colour of `base` under the album
(else artist) display rect; text = the album colour; current text = the artist colour; selection =
the face body's dominant colour (blended toward the current text when it matches the ground).
`SkinnedSurfaceStyle` runs every foreground through `legible`. A face change posts
`.hostedSurfaceStyleDidChange`, so open windows recolour. The windows wear the titleless gloss rim.

## Docking

The face window is a snap target. NullPlayer's windows tile beside it through the shared tiler on
first open and stay where the user leaves them; `AUDION_PLACE_TRACE` (`harness.md`) logs each
placement.
