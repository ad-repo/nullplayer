# `XBOX Music Mixer.wmz`

## What it is

A 2003 Skins Factory skin for WMP 9, shaped like the original Xbox controller: a 344x422 purple
body whose transport ring sits at the top, a green screen in the middle and its panel buttons on the
grip below. Seven views, two of which are never windows, and the only two the user is meant to see at
launch are `mainView` and `eqView` — the skin opens both, which is unusual: nearly every other
dispatcher in the corpus opens its panels only from saved preferences.

```bash
# view declarations, in document order; the markup is UTF-16LE, so decode before reading it
unzip -p ~/Library/Application\ Support/NullPlayer/WMPSkins/XBOX\ Music\ Mixer.wmz mmixer.wms \
  | iconv -f UTF-16LE -t UTF-8 | grep -n '<view id='
unzip -p ~/Library/Application\ Support/NullPlayer/WMPSkins/XBOX\ Music\ Mixer.wmz mmixer.js \
  | iconv -f UTF-16LE -t UTF-8 > /tmp/mmixer.js   # the script is UTF-16LE too
```

Render dump (`WMP_SKIN=…/XBOX\ Music\ Mixer.wmz WMP_RENDER_SCRIPTS=1`, 2026-09-15): one 23,473-byte
program, `runtime=available`, and seven views —

```
mediaSwitcherView: 0x0,    1 nodes,  0 commands,  0 hits,  0 widgets,  0 unresolved
controlView:       0x0,    1 nodes,  0 commands,  0 hits,  0 widgets,  0 unresolved
mainView:        344x422, 11 nodes,  9 commands,  5 hits,  4 widgets,  9 unresolved
plView:          363x354, 18 nodes, 15 commands,  4 hits,  1 widgets,  0 unresolved
visView:         280x350, 18 nodes, 12 commands,  3 hits,  1 widgets,  0 unresolved
eqView:          265x207, 27 nodes, 39 commands, 15 hits, 23 widgets,  0 unresolved
videoView:       343x365, 20 nodes, 19 commands,  4 hits,  0 widgets,  5 unresolved
```

Every view renders. That is the point of this file: the skin was reported broken while every probe
in `../harness.md` said it was healthy, and both statements were true.

## What it exercises that little else does

**A two-stage windowless chain, and a dispatcher that opens *two* windows unconditionally.** The
first view in document order is the store thumbnail, which erases itself and redirects:

```js
function onLoadPreview(){
    view.width = 0; view.height = 0; view.backgroundImage = "";
    theme.currentViewID = "controlView";
}
```

`controlView` is then windowless in its own right (no width, no height,
`timerInterval="100" onTimer="checkViewStatus()"` — the W89 dispatcher), and its `onLoad` ends:

```js
if ("true"==theme.loadPreference("plViewer"))  { theme.openView( 'plView' ); }
if ("true"==theme.loadPreference("eqViewer"))  { theme.openView( 'eqView' ); }
if ("true"==theme.loadPreference("visViewer")) { theme.openView( 'visView' ); }
if ("true"==theme.loadPreference("infoViewer")){ theme.openView( 'infoView' ); }
if ("true"==theme.loadPreference("metaViewer")){ theme.openView( 'metaView' ); }
theme.openView('mainView');
theme.openView( 'eqView' );
```

The last two lines are what no other skin in the corpus writes. Measured 2026-09-15 by decoding
every `.js`/`.wms` in the installed corpus and listing the `theme.openView` calls inside each
function body:

```python
# 86 functions across 69 archives call openView more than once; 25 are this windowless
# `onLoadSkin` idiom, and the id each one ends on is the view that becomes the player.
import zipfile, re, os, glob
d = os.path.expanduser("~/Library/Application Support/NullPlayer/WMPSkins")
def dec(b):
    for enc in ("utf-8-sig", "utf-16", "utf-16-le", "cp1252"):
        try:
            t = b.decode(enc)
            if "\x00" not in t: return t
        except Exception: pass
    return ""
for f in sorted(glob.glob(d + "/*.wmz")):
    z, text = zipfile.ZipFile(f), ""
    for n in z.namelist():                 # guard the read: python's zipfile rejects a few
        if n.lower().endswith((".js", ".wms")):   # local headers this engine's provider accepts
            try: text += dec(z.read(n))
            except Exception: pass
    for m in re.finditer(r"function\s+(\w+)\s*\([^)]*\)\s*\{", text):
        i, depth = m.end(), 1
        while i < len(text) and depth:
            depth += (text[i] == "{") - (text[i] == "}"); i += 1
        calls = re.findall(r"theme\.openView\s*\(\s*['\"]([^'\"]+)", text[m.end():i])
        if len(calls) > 1: print(os.path.basename(f), m.group(1), calls)
```

**21 of those 25 end on `theme.openView('mainView')` and stop** — `Halo 2`, `WoW`, `STALKER`,
`Catwoman`, `Scooby-Doo_2`, `LostPlanet`, `Jewel`, the whole Alienware/ALX family and the rest. The
four that do not are: this skin and its duplicate `XBOX_Music_Mixer.wmz`, which open `mainView` and
then `eqView`; `Need_for_Speed_Underground`, which opens `mainView` **first**, before its four
panels; and `WALL-E`, which opens no player from `onLoadSkin` at all and reaches it from the
dispatcher's timer instead (W176).

**Declaration order is what ranks them instead, and it is the one thing they all agree on**: of the
24 of those archives Python's `zipfile` can read, every one that declares both a `mainView` and a
panel view — 21 of them — declares `mainView` **first**. (`WALL-E` and `livin_it_skate` declare no
panel view at all, and `Need_for_Speed_Underground`'s `.wms` has local headers `zipfile` rejects and
this engine's provider accepts; re-derive that one through `WMPSkinLoader` if it ever matters.) Same
scan as above, reading `<view id="…">` from each `.wms` in document order.

**The player is not the last view a dispatcher opens, and this is
the skin that proves it** — which is exactly why it is the one that found W175, and why `Halo 2`,
whose architecture is identical in every other respect, never could.

`infoView` and `metaView` are named by the script and **declared nowhere in the markup**, so two of
the five preference-guarded calls can never open anything. That is the skin's own dead code, not a
loader defect; it is also why `windowlessSuccessors` has to rank undeclared ids at all.

## Defects it found

- **"xbox music player skin is not showing the main window. it opens to the playlist and there is no
  route to get to the main window"** (reported 2026-09-15). The initial-load walk read
  `theme.currentViewID` and `theme.openView` off one `hostCommands.last`, so the dispatcher's final
  `openView('eqView')` was taken as "go to the equaliser" and the 265x207 EQ panel became the app's
  player window. `mainView` carries the transport, the metadata readout and every button that opens
  another view, so nothing on screen could reach it. **W175** — see
  [`../../../../tasks/WMP_TASKS.md`](../../../../tasks/WMP_TASKS.md) and the archive. The reporter's word
  *"playlist"* is the shape of the panel, not its id; the window on screen was `eqView`.

## What was ruled out

- **Not a load, decode or render defect.** All seven views build and draw, `mainView` included —
  the dump above was taken against the same archive on the day of the report, and `mainView`'s own
  screenshot is a complete player. The engine presented a healthy view; it presented the wrong one.
- **Not the `mediaSwitcherView` collapse (W75) and not `Halo 2`'s blanked thumbnail.** That half of
  the chain works: the switcher collapses to 0x0, its `currentViewID` redirect is followed, and
  `controlView` is correctly refused a window. The defect is one step further on.
- **Not a persisted-frame or restore defect.** `wmpViewSizes` held only `eqView` for this skin —
  which was the *consequence*: `wmpSkinViewID` is written on every present, so the engine's own
  wrong player came back on every relaunch and the skin had never had a chance to record another.
  **Delete `wmpSkinViewID` before testing any change to the walk** (W153) or the old answer wins.
- **`mainView`'s 9 unresolved nodes are not part of this.** They are its `<BUTTONGROUP>` mapping
  children — colour regions, never boxes — which is the W111/W152 population, measured before this
  report and unchanged by it.

## How to drive it

```bash
skills/app-control/scripts/launch.sh "XBOX Music Mixer" --no-play
# the whole measurement for W175: which windows exist, and how big
osascript -e 'tell application "System Events" to get {name, size} of every window \
  of (first process whose name is "NullPlayer")'
# → NullPlayer — eqView 265x207, NullPlayer — Windows Media Player 344x422
```

`mainView`'s controls are a single `<BUTTONGROUP id="set1" left="38" top="13">` over
`m_set1_map.png` plus a `<PAUSEBUTTON>` at `80,24`, so reach them by mapping colour rather than by
rectangle: `#0000ff` play, `#0033ff` previous, `#0066ff` open file, `#0099ff` stop, `#00ccff` next,
`#00ffff` return to full mode, `#00ffcc` minimize. The lower grip's second group is
`<BUTTONGROUP id="set2" left="70" top="263">` over `m_set2_map.png`: `#0000ff` toggle skin colours,
`#0033ff` shutter, `#0066ff` equaliser, `#0099ff` playlist, `#00ccff` visualization, `#00ffff` mute.
The three panel buttons call the host for nothing — each writes `theme.savePreference('remoteCall…',
'true')` and the dispatcher's 100 ms `checkViewStatus()` reads it back and calls
`toggleView(name, id)`, the same round trip `Halo 2` uses (W89). A press that appears to do nothing
is therefore a *dispatcher* question, not a hit-testing one.
