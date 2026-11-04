# AIMP layout and bindings

What `AIMPSkinRenderer` implements, and what it does not yet.

## How a frame is made

1. **Read once, as the skin loads.** `AIMPSkinIndex` reads every form into typed `AIMPSkinItem`s
   (docking: `AIMPSkinItem.Layout`, `AIMPSkinDock`) and `AIMPSkinControl`s (an identity, its class
   with what that class alone reads: `AIMPControlClass`; bindings by target pin, placement, picture,
   text, and what a press, right-click, hold or long click does: `AIMPSkinControl.Input`), and
   `Schema.xml`'s providers into `AIMPSkinIndex.Provider`; links are `AIMPSkinLink`s with their
   expressions compiled and what they read resolved (`AIMPSkinSource`, against
   `AIMPSkinIndex.Names`). Colours are read by `AIMPSkinColor` and fonts by `AIMPSkinFont`, one
   reader each. Actions are `AIMPAction`. Nothing re-reads node properties per frame; a control a
   script restyled (`AIMPSkinState.Script.propertySets`) is read again with the script's values
   over its own, once per set of them. The windows' sizing, hover sources and whether the skin
   lists the library are worked out here too (`AIMPSkinIndex.sizing`, `hoverSources`,
   `showsLibrary`).
2. **Laid out.** `AIMPSkinLayout` places the shown items and, in each, the controls it shows, in
   drawing order, resolving how each looks (`AIMPSkinLayout.Look`: everything the painter needs,
   from a key's frame and caption to a list's rows in view) and what it offers the pointer. It
   measures each item once a frame. Once laid out, each playlist scroll bar is sized by the
   playlist laid out last before it (`withScrollBars`).
3. **Painted.** `AIMPSkinPainter` draws the laid-out tree, pictures layer then controls layer,
   switching once on each control's `Look`, on `AIMPSkinCanvas`'s primitives.
4. **Read.** The frame's click targets, tooltips, named rects, pointer handlers, gauges and search
   font come from the tree (`AIMPSkinLayout.Tree.offers`), not from drawing. A window's natural
   size is measured from layouts alone (`AIMPSkinRenderer.naturalSize`).

`AIMPSkinDataflow` is what layout and painter both read of one frame: what bindings read, and
what that makes of a control (`AIMPSkinDataflow+Controls.swift`: visibility, bound values,
providers, texts and animator frames).

## Forms

`AIMPMainForm.xml` (and `PlaylistFrame.xml`, `MusicLibraryFrame.xml`…) is a `layout` root with
nested `items/item` (`LayoutContainer`, `LayoutItem`, `LayoutTexture`, `LayoutTabbedGroup`,
`LayoutSplitView`…) and, under each item, `controls/control`. Every node's settings are
`properties/property` children named by `name`, valued by `value`, `link`, or a nested `ID`.

## Items

1. Docked items take their edge first: `Alignment` `laTop`, `laBottom`, `laLeft`, `laRight`, sized
   by `Size`/`SizeMinimal`. Each edge takes its items by `AlignmentLevel`, level 0 first, so
   against the edge (Denon Classic Style's amplifier under its equalizer under its deck); which
   edge goes first stays in document order. An item with no size of its own is as big as its
   children laid out: bars stack, side panels and shared clients sit in a row.
2. Items with no `Alignment` run down from the top in `AlignmentLevel` order, whatever the
   `LayoutDirection` (Soot's caption bar over its transport keys); a zero height falls through to
   step 3.
3. `laClient` items get what remains. Several share it along the parent's `LayoutDirection`
   (`ldHorizontal` by default: 398 corpus rows of clients constrained in width without one, 54 in
   height), in `AlignmentLevel` order: each takes its `Size`, else the larger of its `SizeMinimal`
   and what it holds needs (LX-tix's cover beside its info panel), and those whose `SizeMaximal`
   allows split the rest evenly (`AIMPSkinAlignment.share`: Office 2016's ribbon groups, Red Bias's
   library beside its playlist, FLAT DARK's caption: a 64-px icon, the title, 192 px of keys).
4. `AlignmentMargins` (l, t, r, b; may be negative) insets the result.
   Before any of this, an item with `AutoHide` True leaves the layout while its parent is smaller
   than its `AutoHideParentSizeThreshold` along its axis (across for side panels and a row's
   clients, down for bars), or, with none given, too small to hold it (80 corpus skins; Soot's
   all-in-one view, from 550 px wide). Such an item shows whenever it fits, whatever `Visible` the
   editor saved (Soot's trigger is saved hidden). Bindings and scripts read it hidden from the
   next frame on (`AIMPSkinState.Script.autoHidden`, which the runtime gathers from the windows on screen:
   Soot's size triggers drive scripted counters, so the frame cannot settle it alone; the probe
   settles the scripts and draws again when it changed).
   `AIMPSkinAlignment` holds these rules once: which children take part (a tabbed group's pages by what
   is measured), what they add up to, each edge's order and the clients' shares. `AIMPSkinLayout`
   lays out and measures by them, a frame's size (`size`) and the least (`leastSize`) by one rule
   (`AIMPSkinLayout.Measure`: what the item holds, each child in its slot with its margins, as
   `AIMPSkinAlignment.content` adds it up, no smaller than its `SizeMinimal`); the renderer's
   natural size and AIMP 3.0's translator measure by them too.
5. An item paints its `Color`, then its `Texture` as the picture fills (`format.md` § ACLIMG32:
   nine-sliced, tiled or centred). A colour is a number (the property's `value`, LX-tix; a nested `Value`, Unsquareable) or a
   `TACLResourceColor` by `ID`, which may name another (`Skin.Color.Content.Background` →
   `….Dark`: the themes scripts switch by repointing).
6. A sizable main form opens at its `Schema.xml` `InitialSize` (Pandemic's 920×640); one with no
   picture to size it (flat fills only) at the least its docked parts' `SizeMinimal`s allow; a docked item
   whose `AutoSize` is False keeps its own size whatever it holds. A tabbed group whose active page
   is hidden shows its first shown page. A main form opens tall enough to give each form docked in
   it its site's `SizeMinimal` beside the rest (Trident 3's 299-px playlist under its 242-px deck,
   not an 18-px strip of it).
7. Every item's picture draws first, then every control, an item's own before its children's: a
   parent's control lies under its children's controls and over their pictures (the Mayaks'
   meter glass under their level bars; Kenwood KX-800's keys over its panels).

## Controls

`PlaceInfo`: `anchors` (left, top, right, bottom), `margins` from each side of the parent, `Size`.
Anchored to both sides of an axis: stretch between the margins; to one: keep that margin; to neither:
keep the margins' proportion. Margins on an unanchored side are stale from the editor and ignored.

| Class | Drawn |
|---|---|
| `Button`, `Panel`… | `Skin` frame 0 (1 hovered, 2 pressed, 3 disabled); a frame left over after whole runs of `FramesPerState` (default 4) is the hit mask, so buttons can share a rect; a caption from `Caption` (`@Lng:N;` → the user's language, else `English.lng`: `AIMPSkinLanguage`) inside the skin's content margins, centred unless `Alignment` says otherwise |
| `Switch` | as a button, plus `FramesPerState` frames on while its action's `State` is 1 (shuffle, repeat, stay on top, mute) |
| `TextDisplay` | text from a `FileInfo` binding's `TextFormat` (`%Title`, `%Artist`, `%Album`); bound to nothing, its own `Template` (window titles, labels, RealPlayer 11's skin-info lines: 4,874 displays in 279 corpus skins); `WordWrap` True or a `MultiLine` `Layout` breaks it into lines down from the top; `AutoSize` `csHeight` makes it as tall as its lines |
| `Slider*`, `SeekBar` | track frame 0, progress frame 1 over the whole track clipped to the value, `SkinThumb` |
| `SliderMasked` | a filmstrip of positions (knob rotation, tape reel): the value picks the frame |
| `RunningLine` | the playing track (`%R - %T`) unless a `DisplayValue` binding says otherwise; scrolling not yet |
| `Gauge` | a filmstrip of needle positions; `DisplayValue` 0–100 picks the frame (VU meters read `prvVisual.LevelL/R`, about 0–145) |
| `Animator` | a filmstrip: `AnimationFrameIndex` when bound; else, while its `Accessibility` binding is non-zero (or, unbound, while playing), one frame per `AnimationInterval` ms (none set: it holds its first frame, AIMP's default), reversed while `AnimationReversed` is |
| `TimeDisplay` | a 13-frame strip (0–9, separator, minus, blank) showing the bound seconds as `MM:SS` in `Digits` places |
| `SpectrumDisplay` | `ColumnsCount` bars `ColumnsIndent` apart, heights from the spectrum, in `Color` |
| `CoverArtDisplay` | the playing track's artwork filling its rect inside its mask frame, blurred by `BlurLevel` (Soot's backdrop) |
| `BlurredGlass` | what is drawn under it so far, blurred by `BlurLevel` (0–100), inside its skin's `MaskFrame` (on the control's `Skin` or its resource), tinted by its `Color` |
| `DigitsDisplay` | `Digits` frames of a digit strip (0–9 first), zero-padded, stepped by frame width + `IndentBetweenDigits`; value from the `DisplayValue` binding and its `Expression`. One digit of a one-frame image is a plain picture (Vega's cassette sticker) |

Controls nest: a control's own `controls/control` are placed inside its rect (Cassette-3D's `Panel` of animators).
A control whose picture names a `MaskFrame` (on its `Skin`, or on the resource that names) shows
itself and the controls in it only inside that frame's shape, filled as the picture fills: A4's
keys are their state's fill seen through a glyph (133 corpus skins).

## Visibility

- `Visible` or `InitialVisible` `False` hides.
- A `LayoutTabbedGroup` shows one page: the page its `ActivePage` binding reads (Soot's playlist
  page while `LyricsVisibility` is 0), else the one a key or script turned it to, else at the start
  its first not saved hidden, else its first (`AIMPSkinIndex.initialPages`; the editor saves the
  pages it was not showing hidden). A page's own `Visible`/`InitialVisible` says only that: it shows
  while it is the active page (Unsquareable starts on its second, playlist view; RealPlayer's
  equalizer window holds one page saved hidden). A page with no size or picture of its own fills
  the group, whatever its alignment (Kantaris-Teyp's decks).
- A control's `BlendingModeOpacity` (0–255) is its opacity until a script fades it (75 corpus
  skins; Soot's 0 over its swipe surfaces); `BlendingMode` `bmAddition` adds.
- A `Bindings/link` with `TargetPin="Visibility"` hides when its value is 0. The value is its
  `Source`'s: an item's visibility (1/0), or a provider pin. It is shaped by `Expression`
  (`AIMPSkinExpression`: `not value`, `value=1`, `value<>50`, `div`, `mod`). Its operators on
  numbers are the scripts' too (`AIMPSkinExpression.Operator.apply`): `and`, `or`, `xor` bitwise
  on whole numbers, as Pascal's on integers (so logical on 1 and 0); a zero divisor nil, the
  unshaped value kept, where a script raises an error its `except` catches.
- Host values (`AIMPSkinSource.PlayerPin`, read by `AIMPSkinHostState.value`): player state, volume, balance 50, elapsed seconds, time of
  day, `AIMPMainForm.NightMode` (the Mac's dark appearance; the probe's sample player,
  `AIMPSkinPlayerSnapshot.probe` in the test target, is dark: 15 corpus skins
  pick their automatic theme by it). Anything not modelled, including script objects, is 0, except Vega's `CounterPosition`,
  fed elapsed seconds.
- A resource whose `Resource` is a `link` is an alias for another resource (`Skin.BodyFace_` →
  `Skin.BodyFace_4`); `AIMPSkin.image` follows it.

## Providers and skin state

`Schema.xml`'s `providers` are the skin's own dataflow (`AIMPSkinDataflow`):
- `LogicalOperatorCommutator`: `Result` = `Expression` over `value1…valueN`, each a link; with no
  `Expression`, `value1` (28 corpus skins: Office 2016's volume read-out).
- `LogicalOperatorCounter` / `ScriptableOperatorCounter`: `Position`, held in `AIMPSkinState`, else
  a bound `Position` link, else `PositionDefault`.

`AIMPSkinState` is what the skin keeps for itself, in three parts by how often they move:
- `script`: what keys, bindings and scripts set: each tabbed group's page (keys bound to a group's
  `ActivePage` or a tab's `Visibility` turn it), counters, resource aliases, shown and hidden items,
  docking, script variables and config;
- `animation`: what moves every frame while playing: timers fired, animator frames, lamps, the
  inputs scripts last ran on;
- `lists`: where the skin's own playlist and library stand (scrolled, chosen, searched).

A change outside `animation` can move the layout (`layoutMoved(from:)`): the window then measures
its content again. A new field goes in the part it belongs to; nothing else lists it.

## Scripts

`AIMPSkinScript` runs a `ScriptableOperatorCounter`'s script when the value bound to its `Position`
changes. The subset it runs, and the host calls, are in its doc comment. Anything else stops that
run (`Unsupported`) and the skin keeps its state. Vega's `ChangeCassetteScript` is the worked case:
the cassette keys turn tab pages, `VisibilityCassette` computes the cassette number, the script
repoints `Skin.BodyFace_` to that sticker.

How a script runs, file by file:

| Step | Where |
|---|---|
| Decoded (`FSXMLBIN`) and compiled once as the skin loads, into a typed tree (`Program`, `Statement`, `Expression`, operators as enums; a call's routine or built-in resolved). A tree it does not take is an `AM0008` warning and the script is left out | `+Decoder`, `+Syntax`, `AIMPSkinScript.Library` |
| One `Engine` per tick or event owns the skin, the player's snapshot, the state the scripts leave, what they ask of the player, the budget, and the guards: a counter's script that moves its own counter only moves it; AIMP's EQ bands written in it are asked for once per NullPlayer band. A run that stops leaves nothing behind | `+Engine` |
| `Run` executes one program on the engine: its scopes (dynamic, as FastScript's), `with` objects and binding sets | `+Run` |
| `FindObject(name)` is resolved once into a `HostObject` (the player's through `AIMPSkinProvider`, `prvEqualizer`, an effect, or the skin's own element and provider); `Set` and `Get` take a typed `Property` | `+HostBridge` |
| The Delphi functions that read nothing of the skin, one table | `+Builtins` |
| Binding sets a script holds, as `AIMPSkinLink`s read through the dataflow | `+Bindings` |

As the skin is shown, each script named after a form runs (`AIMPMainForm.script`: the reel decks
hide their position preview there, the amplifiers set their tone knobs), the main form's first,
then the main form's `OnLoaded` handler (`Engine.loaded`; the probe runs it too). A window's tick
is `Engine.frame`: timers, visualization handlers and animators, then the scripts whose input moved.

A run is the program's own `begin … end.` block, then `Execute`; a unit without `Execute` (Arc's
empty `SOFMaster`) is only its block. `Execute`'s parameters are the event's, by name: `State`
(a counter, `var`), `EventData` (a form's events), `Sender, Arguments` (handlers), `Data`
(visualization handlers); a counter's `var` parameter is its state whatever it is called (Red
Bias's `Execute(var ALayout: Integer)`). `var X: T = v` and parameter defaults (`Count: Integer = 5`)
start at their value. Host calls for things NullPlayer lacks finish neutrally: `ExecuteColorPicker`
reads as cancelled, `ApplySkin` and `Randomize` do nothing, `IsFadingEnabled` is false.

A script's operators are a binding expression's (`AIMPSkinExpression.Operator.apply`), with
text on top: `+` joins text, `in` tests a set, and a comparison compares text unless a number
meets a number or text that reads as one (`'1.0' = 1`), as Delphi's variants do. A zero divisor
raises (`Raised`, Delphi's `EDivByZero`), which the skin's `except` catches; uncaught, it ends
the run where it was raised and what ran before it stands, as in FastScript (Marantz 5030's
position script divides by a `PositionMax` of 0 with nothing loaded).

A skin's `try … except` does not catch `Unsupported` (nor `exit`, nor the budget running out): an
interpreter gap shows as a script that stops (`AIMP_RENDER_SCRIPTS=1`), not as the skin's fallback
quietly taking over. Its `finally` runs whatever happens. Every crawled script finishes so (`AIMP_RENDER_SCRIPTS=1`:
3,489 of 3,489). A `case` label's or a set's range (`0..1`) matches its two ends only, as it always
has (`tasks/AIMP_TASKS.md`, *Next*).

## Playlist and library windows

A skin's playlist form (`PLWin`, `_Playlist_`, `PlaylistWindow`, `PlaylistFrame`, `PlaylistForm`)
and library form (`MusicLibraryFrame`) open as companion windows, over NullPlayer's own: keys bound
to the form's `Visible` show and hide them, `Maximize` fills the screen. They size from their edges
where `Schema.xml` gives the form `SizingHitTestAreaWidth`, are no smaller than their docked bars'
`SizeMinimal`, and leave their list at least 160 px (`AIMPSkinPolicy.listRoom`; the other measuring
thresholds sit beside it).

| Control | Drawn and done |
|---|---|
| `<control link="Playlist">` | NullPlayer's playlist in `Resources`' fonts and colours; click, double click, wheel, Delete, Return; right-click `pmPlaylistMain` |
| `SearchEdit` on `Playlist`/`MLTable`/`MLGroupingTree.QuickSearch`, `link="PlaylistSearch"` | the search over the box; a click types into a field over it; rows hold every word |
| `PlaylistTabs`, `TabControl` on `prvPlaylistManager`/`prvMusicLibraryManager` | one lit tab: "Playlist", "Music Library" |
| `<control link="MLGroupingTree">` | "All Tracks", groups of `AIMPSkinLibrary`'s grouping preset with counts, subgroups under open ones (`RowExpandButton`) |
| `<control link="MLTable">` | a `ColumnHeader` row (number, title, artist, album, length), then the chosen group's tracks; a double click adds one and plays it |

List colours come from `Style` (`.acs4`, a nested `Value`) or `StyleContent` (`.acs5`, the value
itself), ARGB: `RowColor1`/`2`, `RowColorSelected`, `RowColorSelectedText`, `RowColorText`,
`ColorContent`. Menus by name: `pmAdd`, `pmDelete`, `pmSorting`, `pmMisc`, `pmPlaylistMain`,
`pmMLGroupingTree`, `pmMLTable`, `pmMLGroupingPresets`, `pmMLDelete`, `pmMLMisc`, `pmMLMainMenu`.
Pins: `Playlist`/`MLTable` `Count`, `Duration` (H:MM:SS as text), `Size` (MB as text);
`prvMusicLibraryManager` `BackgroundTaskCount`, `GroupingPresets`.

## Where windows open

A companion opens where `Schema.xml`'s `Placement` on its form says (`AIMPSkin.Companion.DeclaredPlacement`):
`value` 0 left of the deck, 1 above, 2 right, 3 below; `margins` (l, t, r, b): beside the deck the
window stands `t` below its top (Vilma M-212C's right speaker, -626: bottoms level), above or below it
is centred, `b` or `t` clear (K-2's open glass lid, Sharp GF-777's handle). Without one, by name: left
and right speakers beside the deck, anything else below. A window whose items all start hidden
(K-2's lid, shown while the lid is open) is sized by them (`AIMPSkinRenderer.naturalSize`) and shows
once they do.

## Dock sites

A `LayoutDockSite` in the main form holds another of the skin's forms where AIMP would otherwise
open it as a window (`AIMPSkinDockSites`): `.acs4` names it by `ControlName`, `.acs5` by its
`AllowedForms`' `default`; `InitialDocked` `False` leaves the site empty and the form a window.
The loader mounts the form's items in the site inside one item named after the form, so the keys
bound to the form's `Visible` show and hide it in place, and the form opens no window
(`AIMPSkinDataflow.isDocked`); a docked playlist or library still stands in for NullPlayer's. The site shows
while its form does, so a form that starts hidden (`InitialVisible` False on its `Schema.xml` entry:
Telos's equalizer over its transport panel, LX-tix's playlist over its track details) leaves its room
to the rest until its key shows it; a site that holds no form (its form a window, or
`InitialDocked` False) is hidden (A4 3.2's library site left its playlist off the window). `ContentExtends`
(l, t, r, b) lays the form out that far past the site, which clips it: the docked form's own window
frame falls outside. The probe prints `DOCKED <form>`. Scripts that dock and undock at run time
(`Dock`, `Undock`, `Parent`: A4, Telos) are not followed yet.

## Text

`@Lng:Section\Key;` names a string of AIMP's own language files, not the skin's: it reads as the
key's words ("Quick search" for Soot's `Actions\QuickSearch`).

Captions, displays and lists draw in the font the control names; none named is Tahoma (AIMP's
default, which macOS ships), whose narrow letters the skins are measured against. Text may carry
AIMP's markup: `[COLOR=#rrggbb]` or `[COLOR=rrggbb]` (the corpus's usual form), `[B]`, `[I]`, `[U]`
and their closing tags (Dark v1.7's title line); `[URL=…]`…`[/URL]` keeps its text plain; any other
bracket is text.

## Not yet

`LayoutSplitView` dragging, `AllowColoration` tinting,
bundled fonts, scripts beyond the subset; the library table's card view and column choice;
bookmarks, playlist manager, several playlists.
