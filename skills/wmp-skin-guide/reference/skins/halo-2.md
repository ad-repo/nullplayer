# `Halo 2.wmz`

## What it is

A 2004 Skins Factory skin for WMP 10, and the corpus's purest example of the **windowless-dispatcher
architecture**: ten views, of which only two are ever drawn by the skin's own markup as a starting
point, and *every* window it has — including its player — arrives through `theme.openView`. The
player is 327x294; `plView`, `visView`, `eqView`, `videoView`, `infoView` and `upgradeView` are each
406x209, and `vidRemoteView` is a 139x224 floating remote. Nothing in it is the same size as anything
else, which is why it is the skin that broke the one-window assumption.

```bash
# view declarations, in document order
unzip -p ~/Library/Application\ Support/NullPlayer/WMPSkins/Halo\ 2.wmz halo2.wms \
  | grep -o '<view id="[a-zA-Z0-9_]*"'
# the script is UTF-16LE; decode before reading it
unzip -p ~/Library/Application\ Support/NullPlayer/WMPSkins/Halo\ 2.wmz halo2.js \
  | iconv -f UTF-16LE -t UTF-8 > /tmp/halo2.js
```

Census row (`scripts/wmp_skin_census.sh`, 2026-09-11): `load ok`, 10 views, 266 nodes, 151 commands,
72 hits, 24 unresolved, worst view `mainView` at 0.33. It is not a starved skin and never was — every
defect it has produced is an *app-path* defect, which is the whole reason it has a file.

## What it exercises that little else does

**The whole panel vocabulary, routed through one function.** `controlView` is the windowless
dispatcher (`timerInterval="100" onTimer="checkRemoteViewStatus()"`, no width, no height, no
background), and the five panel buttons in `mainView`'s markup do not call the host at all — each
writes a preference:

```
onClick="checkSoundPref('window.wav');theme.savePreference('remoteCallPl', 'true');"
onClick="checkSoundPref('window.wav');theme.savePreference('remoteCallEq', 'true');"
onClick="checkSoundPref('window.wav');theme.savePreference('remoteCallVis', 'true');"
onClick="theme.savePreference('remoteCallInfo', 'true');"
onClick="checkSoundPref('button.wav');theme.savePreference('remoteCallVidRemote', 'true');"
```

`checkRemoteViewStatus()` reads each back ten times a second and answers through **`toggleView`,
which is the single function every panel in this skin opens and closes by**:

```js
function toggleView(name,id)
{
	if("true"==theme.loadPreference(id))
	{
	    theme.savePreference(id, "false");
		theme.closeView( name );
	}else{
		theme.openView( name );
	}
}
```

It also calls `view.minimize()`, and closes the floating remote **by name** when the video panel has
gone: `theme.closeView( 'vidRemoteView' )`. And `onLoadSkin()` — `controlView`'s own `onLoad` — opens
up to four panels from saved preferences and *then* opens the player:

```js
if ("true"==theme.loadPreference("plViewer"))  { theme.openView( 'plView' ); }
if ("true"==theme.loadPreference("eqViewer"))  { theme.openView( 'eqView' ); }
if ("true"==theme.loadPreference("visViewer")) { theme.openView( 'visView' ); }
if ("true"==theme.loadPreference("infoViewer")){ theme.openView( 'infoView' ); }
theme.openView('mainView');
```

So this one skin exercises, in a single launch: the dispatcher (W89), a windowless view that blanks
itself and redirects, up to five windows opened before anything is on screen, close-by-name, and
`view.minimize()` addressed at a window that is not the one the handler is running in.

## Defects it found

- **"Halo 2 has no UI at all"** (reported 2026-09-08). It opens on `previewView` — the skin-chooser
  thumbnail, sized 280x348 by its own `preview.png` — whose `onLoadSkinPreview()` sets
  `view.width = 0`, `view.height = 0`, `view.backgroundImage = ""` and then calls
  `checkPlayerVersion()`, which blanks it *again* and redirects on `player.versionInfo`. Judging the
  view on the canvas it had **before** its script ran presented the thumbnail and then let the
  handler empty it: a blank window, on a skin whose `mainView` renders perfectly. Its zero size was
  then saved under `wmpViewSizes` and handed back on every launch after. Cause: the initial-load
  walk needed a `collapsed` test **after** the load transaction, not only a canvas test before it.
  See `SKILL.md` § *Static scene and image contracts*.
- **`introStart()` never opened its shutter** (reported 2026-09-08). No `.wmz` view timer in the
  corpus had ever fired: a load transaction that requested no script timers — the common case —
  cancelled the view timer `apply` had just started, one line earlier. Cause: `cancelScriptTimers`
  owning all three clocks instead of the script's own. W119.
- **"Its playlist, equaliser, visualisation, info and video panels each replace the player instead
  of opening next to it"** (reported 2026-09-11). This engine had one WMP window, so `theme.openView`
  presented the panel over the player and remembered what it covered. **W141** made the second window
  real. The same report's other half is the one only this skin's script could show: `theme.closeView`
  was an unrecognised member, so **`toggleView`'s close branch aborted on its last statement** — and
  it aborts *after* `theme.savePreference(id, "false")` has already run. The preference therefore
  flipped to closed while the window stayed open, so the next press on the same button took the
  *open* branch and re-opened a panel that had never gone away. That is a one-function explanation
  for "the panel buttons only work once", and no probe that does not run the skin's own script can
  see it. W41's `theme.closeView` half.

## What was ruled out

- **Not a starved view, and not expressions.** The census ranks `mainView` at 0.33 unresolved with
  151 commands and 72 hits — well outside `starved.tsv`'s ranking band. Every defect above is an app
  path. Reading the unresolved count as the cause here would have cost a session; it is the trap
  `SKILL.md` § *Debugging a live defect* records as "a ratio, not a count, ranks a starved view".
- **Not the implicit magenta key.** This skin keys three siblings by hand and leaves `m_trans_no.png`
  to the default, which made it evidence *for* W78's default rather than against it.
- **Not `theme.currentViewID` in `onLoadSkinPreview`.** That line is present in the source and
  **commented out**; the live redirect is the `switch` on `player.versionInfo` inside
  `checkPlayerVersion()`. Reading the handler body without noticing the comment attributes the
  redirect to the wrong function and to the wrong condition.

## How to drive it

Select the skin, launch the debug build with a track playing, and watch the placement of the windows
it opens for itself:

```bash
./scripts/kill_build_run.sh --debug
WMP_PLACE_TRACE=1 NULLPLAYER_PLAY=/abs/path/track.mp3 \
  nohup ./.build/arm64-apple-macosx/debug/NullPlayer -uiMode wmp > /tmp/app.log 2>&1 &
```

One `[wmp/place]` line per auxiliary window, once each. **Five windows at load is the case to watch**
— `onLoadSkin` opens four from preferences plus `mainView` — and the failure mode is an invisible
window rather than a wrong-looking one, so read the frames against the screen rather than the
screenshot. The panel buttons are in `mainView`; find them with
`WMP_RENDER_PROBE=mainView` and press them with `WMP_RENDER_CLICK='mainView@x,y'` rather than by
guessing, per `../harness.md` § *Driving the app*. Because every button here writes a preference
that the dispatcher reads back at 100 ms, **a click's effect is up to a tick late by construction**;
do not read the absence of an immediate change as a dead button, and check
`theme.loadPreference` state in the defaults namespace before theorising.
