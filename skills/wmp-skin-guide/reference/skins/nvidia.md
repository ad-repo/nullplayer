# `NVIDIA.wmz` — *NVIDIA Reactor*

A 2004 Skins Factory build for NVIDIA, and the **head of a nine-archive family**: `Alienware
Invader`, `Batman Begins`, `Constantine`, `Disney_Mix_Central`, `LostPlanet`, `STALKER`,
`Star Wars` and `WoW` ship the same `<VIEW>` skeleton and the same `nvidia.js`-shaped script with
the names changed. Measured 2026-09-16 by a decoded `.wms`+`.js` scan of the 185 installed archives:
**those nine are every archive in the corpus that declares a `<LISTBOX>`**, and their `fillListBox()`
is byte-identical. Anything found here is nine skins, not one.

One `titleBar="false"` window, `285x301` with four modes swapped inside it by script — audio,
playlist, visualization, video — plus an `eqView` and a `vidRemoteView` opened through `theme`. A
128-frame JPEG intro animation runs off the view timer at launch, which is why a launch takes ~12 s
to settle before anything is worth measuring.

## What it exercises that little else does

- **A mode is a size floor the script writes.** `setModesMinWidth(mode)` assigns
  `view.minWidth`/`view.minHeight` — 285x301 for audio, 700x480 for playlist — and then
  `autoSizeView('mWidth','mHeight')` takes the window to it. Only **3 of 185 archives** write a view
  limit from script at all (this one, `Compact` and `Disney_Mix_Central`), and this is the one whose
  *layout* collapses when the floor is wrong. It is also the corpus's clearest statement that
  `minWidth` is a contract rather than a layout, which is W196.
- **A short view timer across a resize.** `timerInterval="100"`, and the handler behind it only pokes
  `btnEq.down`. Ten transactions a second against a switch that takes ~45 ms to build and render is
  what makes W197 a certainty here rather than a rare race.
- **`autoSizeView` depends on the absent-preference sentinel.** `theme.loadPreference('mWidth')` must
  answer `"--"`, because the skin's `else` branch is the one that does the work
  (`view.width = view.minWidth`). `mWidth` is never saved — `saveViewSize` is commented out of
  `onPlayerResize` — so the sentinel is the *only* path this skin ever takes. An empty string here
  would silently leave the window wherever it was.
- **A `<LISTBOX>` that is a playlist chooser, filled from a click rather than a load.**
  `fillListBox()` walks `player.playlistCollection`, not `mediaCollection` — "Now Playing", then a row
  per CD drive, then each saved playlist's `getItemInfo("Title")` — and is answered since W136 from the
  library browser's selected source (`object-model/library.md` § *The library*). **Unlike `WoW`, whose
  `onLoadPl()` fills on load, `NVIDIA` fills in `plModeToggle()`** — the Show Playlist click — and only
  while its saved `loadList` preference is `'false'`: reset in the view's load (`nvidia.js:33`), set
  `'true'` at the end of `fillListBox()` (`:694`), so it fills **once per load**. The `"All Music"`/
  `"All Video"` branches in `getSelPlaylist()` are unreachable: nothing in any of the nine archives ever
  appends those rows. The media collection is reached only by the **search box** above the library
  (`onMlSearch`: `getAll()`, filtered in script), which on a server is the server's track search
  (W136).

## Defects it found

| Reported | Cause | Row |
|---|---|---|
| *"the playlist library is opening very small size now and possibly distorting the aspect ratio"* | The window resize the switch asked for was lost when the view's own 100 ms timer cancelled the transaction carrying it, so a 730x574 picture was presented into the 285x301 window and stretched | W197 |
| the same report | A script-assigned `minWidth`/`minHeight` never reached `WMPResizeLimits`, so the playlist's floor stayed at the audio mode's 285x301 and the window could sit far below what its layout resolves in | W196 |
| *"media library just does not work in nvidia but does work in WOW"* (2026-09-24; search works) | Four defects, measured live 2026-09-25 and fixed together. **(1)** `plModeToggle()` grows the window to 700x480 and then `resizeListBox()` reads `plListBoxSub.height` in the same click — still the audio mode's −95 — so `plListBox1.height` was −95 and the list was never hosted, even on Local Files; the engine never raised `onResize` for a script's own resize, which is what `onPlayerResize()` → `resizeListBox()` corrects. **(2)** The chooser and search box are first hosted in the frame that sizes them and were created empty. **(3)** A source switch never refilled it: it fills from a click, not `onLoad`; the refill is now its own `CdromMediaChange="onCdRomChange()"`, with the view's `onResize` after it because this `fillListBox()` — alone of the nine — does not size the list. **(4)** The fill loop's `getItemInfo("Title")` demanded every server playlist's tracks, 1,850 serial Jellyfin fetches. The fill fits the 0.25 s budget on that 1,850-playlist server (no `terminated` line) | W274 |
| *"i switched to nvidia skin and the search keeps coming back when i switch sources"* (2026-09-24; the search had been run in `WoW`) | Tracks a server fetched — for a search or an opened playlist — were counted in the library proper, so `getAll()` outside a search answered with an earlier skin's search; and a search result kept across a source switch left `library.media:<n>` references that no longer existed, so `updatePlInfo()` threw on every `Playlist_onChange` (`unimplemented library.media.getiteminfo (no such media)`) | W136 (closed) |

## What was ruled out

- **The white "Media Library" panel is the skin's own artwork, not a control this engine draws.** It
  is the middle band of `pl_left_tile.png` (185x11, `backgroundTiled="true"` down the left column
  from `top=225`); its white runs x 25–150 of the tile, which lands at 61–188 in view coordinates and
  matches the block on screen exactly. **Two fixes were built and both backed out**: suppressing the
  `<LISTBOX>`'s own `backgroundColor="#ffffff"` fill in `WMPSceneBuilder`, and having
  `WMPListBoxSurfaceView` paint nothing while it has no rows. Neither moved a pixel. The panel is
  white because it was **empty** — W66 then, closed by W136 on 2026-09-24 — and not because anything
  paints it.
- **The `<LISTBOX>` was not hosted in this view at all** (measured 2026-09-16, before W136).
  `WMP_RENDER_CLICK`'s after-state read `16 widgets[editBox×1 playlist×1 slider×3 text×11]`:
  `plListBox1` declares no `height`, so it did not resolve and never became a widget. **Its only height
  is the one `resizeListBox()` writes** — `itemCount × 14 + 1`, capped at `plListBoxSub.height`.
  Answered 2026-09-25 (W274): the click writes `plListBox1.height=-95`, because the cap is read before
  the window's new size is laid out; `WMP_RENDER_CLICK` still prints that −95, since the probe raises
  `onClick` only and never the `onResize` the app now runs after it. Do not reason about its AppKit
  surface from what is on screen.
- **`plModeToggle` was never the suspect it looked like.** `WMP_RENDER_CLICK` answered
  `viewSize=700x480` before and after both fixes. The engine always computed the right size; only the
  window was wrong, and no flag in `harness.md` has a window.
- **The audio↔playlist round trip was not the trigger.** Three round trips in a row reproduce nothing
  on a healthy build; the defect needs the timer tick to land inside the switch.

## How to drive it

Window origin plus the point, per `harness.md`. `uiScale` 1; the window opens at `285x301` in audio
mode and settles at `730x574` in playlist mode (700x480 from `setModesMinWidth`, then grown by the
skin's own resize handlers).

| Target | Point | Notes |
|---|---|---|
| Show Playlist | `208,95` | `<BUTTONELEMENT mappingColor="#0066ff">` in the `m_audio_map.png` group at `frame=171,84 60x22`; audio mode only |
| Show Audio Mode | `610,95` | playlist mode only, at `730x574` — `left="mainModePlaylist.width-82"`, so it moves with the window |

**Wait ~12 s after launch.** The 128-frame intro runs off the view timer and every measurement taken
during it is of a different scene. A capture at 6 s shows the animation, not the player.

```bash
skills/app-control/scripts/launch.sh NVIDIA --no-play        # opens on mainView, the skin's own default
```
