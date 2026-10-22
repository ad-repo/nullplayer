import AppKit
import CoreGraphics
import Foundation

/// The arity table: every MAKI method the runtime answers, and the class-gated tables for
/// `PlEdit` and `MLPlaylists`. Pure static data; the runtime asks through `signature(for:classGUID:)`.
enum WinampModernScriptSignatures {
    /// Standard GUI events a script is allowed to invoke as a method on an object, with their argument
    /// counts. Kept explicit: an unknown arity would desynchronise the interpreter's stack.
    static let dispatchableEventArity: [String: Int] = [
        "onsetposition": 1,
        "onsetfinalposition": 1,
        "onpostedposition": 1,
        "onleftclick": 0,
        "onrightclick": 0,
        "ontargetreached": 0,
        "ontoggle": 1,
        // `onActivate`'s companion. One argument, read off every handler in the corpus — mmd3,
        // BLAKK, Ebonite, boom, impulse and Styx all open theirs with a single integer store.
        "onactivate": 1,
        // `onAction` is Wasabi's generic message channel, and scripts *send* on it as well as
        // receive: ClassicPro's menu bar posts itself `update_menu`, and the drawer registers its
        // widgets with the widget manager, both by calling the event as a method.
        "onaction": 7,
        // ClassicPro's EQ script labels its bands by calling its own `System.onEqFreqChanged` handler
        // once at load with the value it read out of Winamp's config.
        "oneqfreqchanged": 1,
        // Same idiom, one layer in: a XUI object's script hands itself a param it computed rather
        // than one the markup declared. ClassicPro's Now Playing widget resolves the skin's list
        // background through `ColorMgr` and then feeds it to its own handler as
        // `System.onSetXuiParam("bgcolor", "r,g,b")` — which, unimplemented, aborted `onScriptLoaded`
        // on the line after `getColor` and left the widget an empty pane.
        "onsetxuiparam": 2,
        // Winamp fires this whenever the level moves, and a skin with no volume slider relies on it
        // for the only feedback it has: Love is War Miku's `+`/`-` buttons show "Volume: 40%" on the
        // song ticker from this handler and clear it a moment later.
        "onvolumechanged": 1,
        // The star row's echo: Winamp raises it whenever the playing track's rating changes, whoever
        // changed it, and Big Bento's `fileinfo` redraws its five stars from the handler rather than
        // from the click. One argument — the new rating in stars — which is also how the API is
        // documented and the only shape the getter/setter pair leaves room for.
        "oncurrenttrackrated": 1,
        // The equalizer's two, on the same footing: Winamp raises them whenever a band or the preamp
        // moves, whoever moved it. Arities read off the five skins that handle them (multipass, mmd3,
        // Rika, winampmodern566, Overdrive_2) — every one of them opens `onEqBandChanged` with two
        // stores and `onEqPreampChanged` with one.
        "oneqbandchanged": 2,
        "oneqpreampchanged": 1,
        // The Phase 24 additions. ClassicPro calls all of these as methods as well as receiving them:
        // `beat.m`'s own `frameGroup.onResize(0, 0, w, h)` re-solves its geometry after a change it
        // made itself, `tagviewer.m` does the same, and a script that reuses its `onSetVisible` or
        // `onTitleChange` body is the same idiom `onSetPosition` already had.
        "onresize": 4,
        // Scripts call their own pointer and notify handlers to reuse them: Bio-Nid's playlist editor
        // runs `poppler.onMouseMove(x, y)` while it resizes, NMP10's `about` script
        // `Next.onLeftButtonDown(0, 0)` (B182). Arities from `std.mi`. Three names are declared
        // with another arity on a class the corpus never calls them on (`Wac.onNotify` 3,
        // `System.onAccelerator` 3, `Vis.onFrame` 0); `signature(for:classGUID:)` gates those.
        "onleftbuttondown": 2,
        "onleftbuttonup": 2,
        "onrightbuttondown": 2,
        "onrightbuttonup": 2,
        "onmousemove": 2,
        "onnotify": 4,
        "oneqchanged": 1,
        "oninfochange": 1,
        "onswitchtolayout": 1,
        "onplay": 0,
        "onstop": 0,
        "onaccelerator": 1,
        "onframe": 1,
        // `onUserResize` is **not** `onResize`: it fires only for a resize the *user* dragged, which
        // is the whole difference a standard frame is built on. Ebonite's frame writes the client's
        // new box from it (through a 1 ms timer) and would otherwise fight its own `onResize`.
        // Four arguments, the same box `onResize` carries.
        "onuserresize": 4,
        "onsetvisible": 1,
        // The wheel. **Two** arguments, not one — read off two independent skins' bytecode (Big Bento
        // Modern's `config_vscrollbars` at `@638` and cPro-Bento's `centro.multidrawer` at `@1091`
        // both open with two `op3` stores), which is the corroboration a guessed arity needs. Wasabi
        // documents them as `(clicks, lines)`; neither corpus consumer *reads* them, both simply relay
        // them as `sendAction`'s `p1`/`p2`, so the names are taken from the API rather than measured.
        "onmousewheelup": 2,
        "onmousewheeldown": 2,
        // `Timer.onTimer()` called as a method is "run the body now rather than at the next tick".
        // Zero arguments — Winamp's timer event carries none, and every handler in the corpus opens
        // with no store. Big Bento Modern's songticker uses it to restore the song title the moment
        // a seek preview is cancelled instead of a beat later.
        "ontimer": 0,
        "onpause": 0,
        "onresume": 0,
        "ontitlechange": 1,
        "onleftbuttondblclk": 2,
        "ontextchanged": 1,
        // The keyboard. Winamp hands `onKeyDown` **one string** — `"alt+g"`, `"ctrl+w"`, `"esc"` —
        // not a virtual keycode, and every handler in the corpus opens with a single string store
        // (multipass `system.maki`, Defix `PLAYLIST_WINDOW.xml`, winampmodern566's display, playlist
        // and album-art programs). It is in this table because it is dispatchable, not because a
        // script calls it: none in the corpus does, but the arity has to be declared for the
        // dispatch either way.
        "onkeydown": 1,
        // The pointer's own pair, called as methods. ClassicPro's CentroSUI uses them as the *only*
        // way to put its album-art overlay up and away, and calls them from five places in
        // `CentroSUI2.m` — including the two that decide what the Now Playing selector does after the
        // menu closes. Without an arity the interpreter fails closed before the call is even traced,
        // so `but_miniGoto.onLeftClick` stopped one statement after its two `isMouseOverRect` tests
        // and `openMini()` never ran (B100): Album Art, File Info and Visualization all did nothing,
        // the last two after `openMini` had already hidden every pane. Zero arguments — 57 handler
        // declarations in the engine and 193 in the corpus, every one of them `()`.
        "onenterarea": 0,
        "onleavearea": 0,
        "onshownotification": 0,
        // `System.onScriptLoaded()` called as a method — a script re-running its **own** startup body.
        // Ebonite's standard frame is built around it: it closes its frame container on every hide and
        // rebuilds it on the next show with
        // `if (!comp_layout.getContainer().isDynamic()) system.onScriptLoaded();`, so without an arity
        // the call abandoned `onSetVisible` one statement before `frame_layout.show()` and the frame
        // never came back (B110). Zero arguments — Winamp's load event carries none.
        // `invokeSystem` scopes this one to the calling program; see there for why.
        "onscriptloaded": 0,
        // `System.onSeek(int newpos)` — the position the player moved to, in the same milliseconds
        // `getPosition()` answers. It is in this table because Anexa *calls* it: both its main and
        // shade progress bars are a `<layer>` clipped by a region map, and the only thing that fills
        // them is a 99 ms timer whose whole body is `System.onSeek(getPosition())`. Dispatch is
        // fail-closed, so without an arity that call abandoned the handler on its first statement and
        // the bar never moved — it was only ever seen full, because `onStop` sets it to 255 (B64).
        "onseek": 1,
        // The `<edit>` control's own three events, all arity 0 in Wasabi. `onEnter` is the one every
        // corpus consumer declares (Big Bento's `playlistpro.maki` runs the playlist search from it);
        // `onAbort` is Escape leaving the box, and `onEditUpdate` fires per keystroke for a skin that
        // filters as you type. Declared here because they are dispatchable — the view drives them from
        // the keyboard.
        "onenter": 0,
        "onabort": 0,
        // `List.onDoubleClick(item)` — the row, one argument (a single store at Big Bento's handler
        // entry, which is what opens the track a search result names).
        "ondoubleclick": 1,
        "oneditupdate": 0,
        // Config pages call it to run their own field handler (B189).
        "onidleeditupdate": 0,
        // `attribute.onDataChanged()` — a script running its own settings handler once at load, so
        // the layout the stored options describe is applied before anything is drawn. Zero
        // arguments, and it is the *only* way a skin has of saying "apply what I read". Big Bento
        // Modern's `pledit` ends `onScriptLoaded` with it, and while the call was inert the enlarged
        // playlist never positioned its album-art splitter at load — leaving the frame on its markup
        // seed, which the same script then saved over the user's remembered cover height at unload
        // (BB32).
        "ondatachanged": 0,
        "onscriptunloading": 0
    ]

    /// The playlist-editor API, **keyed by `PlEdit`'s class** rather than registered globally.
    ///
    /// Half of these names belong to other classes too — `getLength` is an `animatedlayer`'s frame
    /// count (ClassicPro's `beat.m` reads it 28 times), `getTitle` a container's caption, `clear` a
    /// list's. Registering them by name would claim every one of those call sites with the wrong
    /// arity *and* hide their demand from the compatibility report, so the whole set is gated on the
    /// receiver's class.
    ///
    /// Every arity here was counted off the corpus's own call sites (`RENDER_DISASM`), not ported
    /// from a reference header: the compiler emits the receiver, then one push per argument in
    /// reverse, so the net pushes between the two settle it. `moveTo` is the one that pays for the
    /// measurement — it reads like a one-argument "scroll to" and is `moveTo(from, to)`, which
    /// Defix's *Move selected to top* proves by passing a literal 0 and then a running counter.
    private static let playlistEditorSignatures: [String: MakiMethodSignature] = [
        "getcurrentindex": .init(argumentCount: 0, returnKind: .integer),
        "getnumtracks": .init(argumentCount: 0, returnKind: .integer),
        "gettitle": .init(argumentCount: 1, returnKind: .string),
        "getlength": .init(argumentCount: 1, returnKind: .string),
        "getfilename": .init(argumentCount: 1, returnKind: .string),
        "getmetadata": .init(argumentCount: 2, returnKind: .string),
        "playtrack": .init(argumentCount: 1, returnKind: .null),
        "removetrack": .init(argumentCount: 1, returnKind: .null),
        "showtrack": .init(argumentCount: 1, returnKind: .null),
        "moveto": .init(argumentCount: 2, returnKind: .null),
        "showcurrentlyplayingtrack": .init(argumentCount: 0, returnKind: .null),
        "clear": .init(argumentCount: 0, returnKind: .null),
        // Arity pinned by ClassicPro's own `extendedbuttons.m`, which ships its source beside the
        // compiled program: `PlEdit.enqueueFile(enqFile)`, one string.
        "enqueuefile": .init(argumentCount: 1, returnKind: .null),
        "moveup": .init(argumentCount: 1, returnKind: .null),
        "movedown": .init(argumentCount: 1, returnKind: .null),
        "getrating": .init(argumentCount: 1, returnKind: .integer),
        "setrating": .init(argumentCount: 2, returnKind: .null),
    ]

    /// `MLPlaylists`, the Media Library's saved-playlist manager. Gated by class for the same reason
    /// `PlEdit`'s table is: `getNumItems` is **already** registered globally for a MAKI `List` and
    /// `getItemName` is the sort of short verb any list-like class could declare, so binding either
    /// by name would hand its arity to every one of them.
    ///
    /// Arities read off Big Bento's own call sites (`RENDER_DISASM=@player-normal-mcv`): the menu
    /// loop is `for (i = 0; i < manager.getNumItems(); i++) addCommand(manager.getItemName(i), …)`
    /// — one push for the receiver at `getnumitems`, two at `getitemname` and `playitem`.
    private static let playlistManagerSignatures: [String: MakiMethodSignature] = [
        "getnumitems": .init(argumentCount: 0, returnKind: .integer),
        "getitemname": .init(argumentCount: 1, returnKind: .string),
        "playitem": .init(argumentCount: 1, returnKind: .null),
    ]

    /// Verbs answered only on their **declaring** class — which is what the interpreter passes as
    /// `classGUID`, and the reason a short verb like `apply` can be given an arity at all. Registering
    /// one globally would hand its arity to every class that happens to declare the same verb, and a
    /// wrong argument count is the one error the interpreter cannot recover from: it leaves values on
    /// the stack and desynchronises everything after the call. See `reference/scripting.md` →
    /// *`PlEdit`*, which records that failure mode. Checked before `generalSignatures`.
    private static let classSignatures: [String: [String: MakiMethodSignature]] = [
        MakiClassGUID.playlistEditor: playlistEditorSignatures,
        MakiClassGUID.playlistManager: playlistManagerSignatures,
        // `Layout.getContainer()` takes nothing; the global form names the container.
        MakiClassGUID.layout: ["getcontainer": .init(argumentCount: 0, returnKind: .object)],
        MakiClassGUID.colorManager: [
            "getgammaset": .init(argumentCount: 1, returnKind: .object),
            "getcolor": .init(argumentCount: 1, returnKind: .object),
        ],
        MakiClassGUID.gammaSet: ["apply": .init(argumentCount: 0, returnKind: .null)],
        MakiClassGUID.application: ["shutdown": .init(argumentCount: 0, returnKind: .null)],
        // The other arities of three events `dispatchableEventArity` keys by name (B182).
        // `selectItem` is `(id, hover)` on a drop-down and `(item)` on a tree; `GuiList`'s
        // `getItemSelected(pos)` takes a row, the drop-down's nothing.
        MakiClassGUID.dropDownList: [
            "selectitem": .init(argumentCount: 2, returnKind: .null),
            "getitemselected": .init(argumentCount: 0, returnKind: .string),
        ],
        MakiClassGUID.guiTree: ["selectitem": .init(argumentCount: 1, returnKind: .null)],
        MakiClassGUID.wac: ["onnotify": .init(argumentCount: 3, returnKind: .integer)],
        MakiClassGUID.system: ["onaccelerator": .init(argumentCount: 3, returnKind: .null)],
        MakiClassGUID.vis: ["onframe": .init(argumentCount: 0, returnKind: .null)],
    ]

    /// Every verb that is **not** gated on a declaring class, and the arity the interpreter must
    /// unwind the stack by.
    ///
    /// `static`, and that is the whole point: this was a **local** literal inside
    /// `signature(for:classGUID:)`, so all 311 entries were allocated and hashed on every call —
    /// which is every method invocation the interpreter makes, in every skin. Measured at 10.4% of
    /// the main thread on cPro Bento, whose realtime Layer FX layer dispatches 1320 calls a second
    /// (B103). A dictionary literal this size is not something to rebuild on a hot path.
    private static let generalSignatures: [String: MakiMethodSignature] = [
        "getcontainer": .init(argumentCount: 1, returnKind: .object),
        "newdynamiccontainer": .init(argumentCount: 1, returnKind: .object),
        // `Container.isDynamic()` — was this container created by `newDynamicContainer`, or is it one
        // the skin declared? Ebonite's standard frame asks it of the *client* container to decide
        // whether to rebuild its frame overlay on every re-show, and an unimplemented method aborts
        // the whole handler, so without this its `onSetVisible` never reaches `frame_layout.show()`.
        "isdynamic": .init(argumentCount: 0, returnKind: .boolean),
        "getlayout": .init(argumentCount: 1, returnKind: .object),
        "getobject": .init(argumentCount: 1, returnKind: .object),
        "findobject": .init(argumentCount: 1, returnKind: .object),
        "getscriptgroup": .init(argumentCount: 0, returnKind: .object),
        "getparam": .init(argumentCount: 0, returnKind: .string),
        "gettoken": .init(argumentCount: 3, returnKind: .string),
        "getid": .init(argumentCount: 0, returnKind: .string),
        // `Color`'s channels. Global rather than class-gated: all three are zero-argument getters,
        // so even a collision with another class's same-named verb cannot desynchronise the stack
        // the way a wrong *count* would.
        "getred": .init(argumentCount: 0, returnKind: .integer),
        "getgreen": .init(argumentCount: 0, returnKind: .integer),
        "getblue": .init(argumentCount: 0, returnKind: .integer),
        // The gamma-corrected spellings of the same three. `ColorMgr.getColor` already resolves
        // through the active `<gammaset>`, so here they *are* the same three — see the receiver.
        "getredwithgamma": .init(argumentCount: 0, returnKind: .integer),
        "getgreenwithgamma": .init(argumentCount: 0, returnKind: .integer),
        "getbluewithgamma": .init(argumentCount: 0, returnKind: .integer),
        "getparent": .init(argumentCount: 0, returnKind: .object),
        "getparentlayout": .init(argumentCount: 0, returnKind: .object),
        "getcurlayout": .init(argumentCount: 0, returnKind: .object),
        "switchtolayout": .init(argumentCount: 1, returnKind: .null),
        "getxmlparam": .init(argumentCount: 1, returnKind: .string),
        "setxmlparam": .init(argumentCount: 2, returnKind: .null),
        "settext": .init(argumentCount: 1, returnKind: .null),
        "gettext": .init(argumentCount: 0, returnKind: .string),
        "getautowidth": .init(argumentCount: 0, returnKind: .integer),
        "getautoheight": .init(argumentCount: 0, returnKind: .integer),
        // `getTextWidth()` — how wide the string this object *currently shows* draws. Distinct
        // from `getAutoWidth()`, which is how wide the object wants to be: a skin compares the
        // two (`if (t.getWidth() < t.getTextWidth()) t.hide(); else t.show();`) to decide whether
        // a caption fits its box. Big Bento Modern does exactly that from `onTextChanged`, so
        // the method was missing on the one handler that runs at every track change.
        "gettextwidth": .init(argumentCount: 0, returnKind: .integer),
        // `GuiObject.getGuid()` — the component GUID an object was declared with, "" for the
        // objects that carry none (which is most of them).
        "getguid": .init(argumentCount: 0, returnKind: .string),
        // The playlist *widget's* own "scroll to the playing entry", as against `PlEdit`'s
        // `showCurrentlyPlayingTrack`. Itemskin and micro reach it through `findObject` on their
        // playlist object, so it is a GUI method with a receiver, not a System one. Unique in the
        // corpus, so it needs no class gate.
        "showcurrentlyplayingentry": .init(argumentCount: 0, returnKind: .null),
        "resize": .init(argumentCount: 4, returnKind: .null),
        "show": .init(argumentCount: 0, returnKind: .null),
        "hide": .init(argumentCount: 0, returnKind: .null),
        "toggle": .init(argumentCount: 0, returnKind: .null),
        "isvisible": .init(argumentCount: 0, returnKind: .boolean),
        // "does my window have the keyboard?" — the gate a skin puts in front of a key handler
        // so one window's accelerator does not fire while another is focused. A System event
        // reaches every program in the skin, so without this winampmodern566's `ctrl+w` would
        // shade its playlist window from anywhere.
        "isactive": .init(argumentCount: 0, returnKind: .boolean),
        "setalpha": .init(argumentCount: 1, returnKind: .null),
        "getalpha": .init(argumentCount: 0, returnKind: .integer),
        "setenabled": .init(argumentCount: 1, returnKind: .null),
        "setactivated": .init(argumentCount: 1, returnKind: .null),
        // The same write **without** the `onToggle` it would otherwise provoke. A skin uses it to
        // follow state it is already reacting to: multipass's `configAttribute_eqVisible`
        // handler moves the drawer's toggle to match the attribute it just observed, and
        // `setActivated` there would re-enter `toggleDrawer` from inside its own notification.
        "setactivatednocallback": .init(argumentCount: 1, returnKind: .null),
        "getactivated": .init(argumentCount: 0, returnKind: .boolean),
        "setchecked": .init(argumentCount: 1, returnKind: .null),
        "ischecked": .init(argumentCount: 0, returnKind: .integer),
        "getcurpage": .init(argumentCount: 0, returnKind: .integer),
        "setcurpage": .init(argumentCount: 1, returnKind: .null),
        "setautoenter": .init(argumentCount: 1, returnKind: .null),
        "getautoenter": .init(argumentCount: 0, returnKind: .integer),
        "enter": .init(argumentCount: 0, returnKind: .null),
        // The object's Wasabi class, which a script branches on to treat a heterogeneous set of
        // objects uniformly: multipass's `initStyle` walks its whole element list and swaps
        // `image=` on a LAYER, `image=`/`downImage=`/`hoverImage=` on a BUTTON, and the thumb
        // ids on a SLIDER — one loop over every skinnable thing the Style menu touches.
        "getclassname": .init(argumentCount: 0, returnKind: .string),
        // Closing a container is hiding its window: `.wal` windows are ours, and nothing in the
        // engine owns a destroyed-container lifecycle. Multipass's notifier closes itself.
        "close": .init(argumentCount: 0, returnKind: .null),
        "getleft": .init(argumentCount: 0, returnKind: .integer),
        "gettop": .init(argumentCount: 0, returnKind: .integer),
        "getwidth": .init(argumentCount: 0, returnKind: .integer),
        "getheight": .init(argumentCount: 0, returnKind: .integer),
        "getguix": .init(argumentCount: 0, returnKind: .integer),
        "getguiy": .init(argumentCount: 0, returnKind: .integer),
        "getguiw": .init(argumentCount: 0, returnKind: .integer),
        "getguih": .init(argumentCount: 0, returnKind: .integer),
        "getposition": .init(argumentCount: 0, returnKind: .integer),
        "setposition": .init(argumentCount: 1, returnKind: .null),
        "clienttoscreenx": .init(argumentCount: 1, returnKind: .integer),
        "clienttoscreeny": .init(argumentCount: 1, returnKind: .integer),
        "screentoclientx": .init(argumentCount: 1, returnKind: .integer),
        "screentoclienty": .init(argumentCount: 1, returnKind: .integer),
        // `isInvalid()` is how a ClassicPro script asks "did this element survive the skin's
        // overrides?" before configuring it; `getScale()` is a layout's zoom factor.
        "isinvalid": .init(argumentCount: 0, returnKind: .boolean),
        // Its write half is the host's UI Size, not a layout transform — see `uiScaleRequested`.
        "setscale": .init(argumentCount: 1, returnKind: .null),
        "getscale": .init(argumentCount: 0, returnKind: .float),
        "setredraw": .init(argumentCount: 1, returnKind: .null),
        // `scrollToPercent(pct)` on a scrolling group. Arity 1, result discarded — pinned by the
        // bytecode (`v103.scrollToPercent(v119)` followed by `op2`).
        "scrolltopercent": .init(argumentCount: 1, returnKind: .null),
        "setregionfrommap": .init(argumentCount: 3, returnKind: .null),
        "setmode": .init(argumentCount: 1, returnKind: .null),
        "getmode": .init(argumentCount: 0, returnKind: .integer),
        "getcomponentname": .init(argumentCount: 0, returnKind: .string),
        "enumgammagroup": .init(argumentCount: 1, returnKind: .object),
        "getregion": .init(argumentCount: 0, returnKind: .object),
        "back": .init(argumentCount: 0, returnKind: .null),
        "forward": .init(argumentCount: 0, returnKind: .null),
        "getmainbrowser": .init(argumentCount: 0, returnKind: .object),
        "popmainbrowser": .init(argumentCount: 0, returnKind: .null),
        "showwindow": .init(argumentCount: 3, returnKind: .object),
        "setred": .init(argumentCount: 1, returnKind: .null),
        "setgreen": .init(argumentCount: 1, returnKind: .null),
        "setblue": .init(argumentCount: 1, returnKind: .null),
        // Demand-table batch (the S4 queue's tail): signatures from the corpus's own `.mi` headers.
        "sqr": .init(argumentCount: 1, returnKind: .double),
        "frac": .init(argumentCount: 1, returnKind: .double),
        "getdateday": .init(argumentCount: 1, returnKind: .integer),
        "getdatedow": .init(argumentCount: 1, returnKind: .integer),
        "getdatedst": .init(argumentCount: 1, returnKind: .integer),
        "getdatemonth": .init(argumentCount: 1, returnKind: .integer),
        "formatdate": .init(argumentCount: 1, returnKind: .string),
        "formatlongdate": .init(argumentCount: 1, returnKind: .string),
        "datetolongtime": .init(argumentCount: 1, returnKind: .string),
        "getmonitorleftfromguiobject": .init(argumentCount: 1, returnKind: .integer),
        "getmonitortopfromguiobject": .init(argumentCount: 1, returnKind: .integer),
        "getmonitorwidthfromguiobject": .init(argumentCount: 1, returnKind: .integer),
        "getmonitorheightfromguiobject": .init(argumentCount: 1, returnKind: .integer),
        "getwac": .init(argumentCount: 1, returnKind: .object),
        "sendcommand": .init(argumentCount: 4, returnKind: .integer),
        "enqueuefile": .init(argumentCount: 1, returnKind: .null),
        "nextmode": .init(argumentCount: 0, returnKind: .null),
        "setrealtime": .init(argumentCount: 1, returnKind: .null),
        "getautoreplay": .init(argumentCount: 0, returnKind: .boolean),
        "islayout": .init(argumentCount: 0, returnKind: .boolean),
        "getnumlayouts": .init(argumentCount: 0, returnKind: .integer),
        "enumlayout": .init(argumentCount: 1, returnKind: .object),
        "setname": .init(argumentCount: 1, returnKind: .null),
        "getsnapadjustleft": .init(argumentCount: 0, returnKind: .integer),
        "getsnapadjusttop": .init(argumentCount: 0, returnKind: .integer),
        "getsnapadjustright": .init(argumentCount: 0, returnKind: .integer),
        "getsnapadjustbottom": .init(argumentCount: 0, returnKind: .integer),
        "setdesktopalpha": .init(argumentCount: 1, returnKind: .null),
        "getdesktopalpha": .init(argumentCount: 0, returnKind: .boolean),
        "clienttoscreenw": .init(argumentCount: 1, returnKind: .integer),
        "clienttoscreenh": .init(argumentCount: 1, returnKind: .integer),
        "screentoclientw": .init(argumentCount: 1, returnKind: .integer),
        "screentoclienth": .init(argumentCount: 1, returnKind: .integer),
        "bringbelow": .init(argumentCount: 1, returnKind: .null),
        "bringabove": .init(argumentCount: 1, returnKind: .null),
        "rightclick": .init(argumentCount: 0, returnKind: .null),
        "lock": .init(argumentCount: 0, returnKind: .null),
        "unlock": .init(argumentCount: 0, returnKind: .null),
        "getskipped": .init(argumentCount: 0, returnKind: .integer),
        "disablecommand": .init(argumentCount: 2, returnKind: .null),
        "cfggetint": .init(argumentCount: 0, returnKind: .integer),
        "cfggetfloat": .init(argumentCount: 0, returnKind: .double),
        "cfggetstring": .init(argumentCount: 0, returnKind: .string),
        "cfggetname": .init(argumentCount: 0, returnKind: .string),
        "cfggetguid": .init(argumentCount: 0, returnKind: .string),
        "cfgsetint": .init(argumentCount: 1, returnKind: .null),
        "cfgsetfloat": .init(argumentCount: 1, returnKind: .null),
        "cfgsetstring": .init(argumentCount: 1, returnKind: .null),
        "getselectedtext": .init(argumentCount: 0, returnKind: .string),
        "getitemtext": .init(argumentCount: 1, returnKind: .string),
        "setitems": .init(argumentCount: 1, returnKind: .null),
        "delitem": .init(argumentCount: 1, returnKind: .null),
        "getselected": .init(argumentCount: 0, returnKind: .integer),
        "setlistheight": .init(argumentCount: 1, returnKind: .null),
        "getscroll": .init(argumentCount: 0, returnKind: .integer),
        "setscroll": .init(argumentCount: 1, returnKind: .integer),
        "setredirection": .init(argumentCount: 1, returnKind: .null),
        "endmodal": .init(argumentCount: 1, returnKind: .null),
        "insertitem": .init(argumentCount: 2, returnKind: .integer),
        "deletebypos": .init(argumentCount: 1, returnKind: .integer),
        "moveitem": .init(argumentCount: 2, returnKind: .null),
        "getsubitemtext": .init(argumentCount: 2, returnKind: .string),
        "deselectall": .init(argumentCount: 0, returnKind: .integer),
        "getitemfocused": .init(argumentCount: 0, returnKind: .integer),
        "setitemfocused": .init(argumentCount: 1, returnKind: .null),
        "addcolumn": .init(argumentCount: 3, returnKind: .integer),
        "setcolumnlabel": .init(argumentCount: 2, returnKind: .null),
        "setcolumnwidth": .init(argumentCount: 2, returnKind: .null),
        "getcolumnlabel": .init(argumentCount: 1, returnKind: .string),
        "setautosort": .init(argumentCount: 1, returnKind: .null),
        "setpreventmultipleselection": .init(argumentCount: 1, returnKind: .integer),
        "setlabel": .init(argumentCount: 1, returnKind: .null),
        "getlabel": .init(argumentCount: 0, returnKind: .string),
        "expand": .init(argumentCount: 0, returnKind: .integer),
        "collapse": .init(argumentCount: 0, returnKind: .integer),
        "isexpanded": .init(argumentCount: 0, returnKind: .integer),
        "addtreeitem": .init(argumentCount: 4, returnKind: .object),
        "movetreeitem": .init(argumentCount: 2, returnKind: .null),
        "enumrootitem": .init(argumentCount: 1, returnKind: .object),
        "enumallitems": .init(argumentCount: 1, returnKind: .object),
        "getnumvisibleitems": .init(argumentCount: 0, returnKind: .integer),
        "getbylabel": .init(argumentCount: 2, returnKind: .object),
        "setsorted": .init(argumentCount: 1, returnKind: .null),
        "getsorted": .init(argumentCount: 0, returnKind: .integer),
        "play": .init(argumentCount: 0, returnKind: .null),
        "pause": .init(argumentCount: 0, returnKind: .null),
        "gotoframe": .init(argumentCount: 1, returnKind: .null),
        "setframe": .init(argumentCount: 1, returnKind: .null),
        "getcurframe": .init(argumentCount: 0, returnKind: .integer),
        // Animated-layer playback control. MMD3's volume/bass/treble knobs are animated layers
        // played frame-range to frame-range, and the driving timer polls `isPlaying()`.
        "getlength": .init(argumentCount: 0, returnKind: .integer),
        "setstartframe": .init(argumentCount: 1, returnKind: .null),
        "setendframe": .init(argumentCount: 1, returnKind: .null),
        // The read halves of the same pair. A skin that pages through a sprite sheet by hand
        // asks the layer where its own ends are rather than hard-coding a count: Hal's Eye
        // `manual.maki` caches `getCurFrame()`/`getEndFrame()` in `onScriptLoaded` and clamps
        // both page buttons against them, so with the signature missing the handler abandoned
        // the whole initialiser at that call and both buttons sat at frame 0 forever (B91).
        "getstartframe": .init(argumentCount: 0, returnKind: .integer),
        "getendframe": .init(argumentCount: 0, returnKind: .integer),
        "setspeed": .init(argumentCount: 1, returnKind: .null),
        // Part of the same four-call preamble every skin writes before `play()`, and the one that
        // was missing: Big Bento Modern's `animbutton` sets start, end, **autoreplay** and speed
        // in that order, so a missing signature here abandoned the whole handler at the third
        // call — the play/pause morph never ran and the buttons were never swapped.
        "setautoreplay": .init(argumentCount: 1, returnKind: .null),
        "isplaying": .init(argumentCount: 0, returnKind: .boolean),
        // `isStopped()` is the **`AnimatedLayer`'s**, not the player's — the same receiver
        // `play()` and `stop()` take, pinned by the call sites (`RENDER_DISASM=isStopped`:
        // `op1(v3) op24(isstopped)` where `v3` is also the receiver of `play`). It reads like a
        // transport question, and that resemblance is the trap: `isPlaying` beside it was already
        // implemented for animated layers, so the pair looked complete while T800's jaw animation
        // — `Noname2.maki`, behind the `animationbutton` under the mouth — aborted on the missing
        // half every time it was pressed.
        "isstopped": .init(argumentCount: 0, returnKind: .boolean),
        "setalternatetext": .init(argumentCount: 1, returnKind: .null),
        "setfontsize": .init(argumentCount: 1, returnKind: .null),
        // `setFocus()` — the keyboard, asked for by the object that wants it. Big Bento's
        // `playlistpro.maki` shows its playlist search box and focuses it in the same handler, so
        // without this the handler aborted at the focus call and the box could never be typed in.
        "setfocus": .init(argumentCount: 0, returnKind: .null),
        // The `<list>` control a script fills — Big Bento's playlist search is the measured
        // consumer, and every arity here is counted from its call sites: `deleteAllItems()`,
        // `getItemLabel(item, column)`, `getFirstItemSelected()`, `getNextItemSelected(after)`,
        // `scrollToItem(item)`. `addItem` is already declared (the dynamic `List` container shares
        // the name); the receiver decides which one answers.
        "deleteallitems": .init(argumentCount: 0, returnKind: .null),
        "getitemlabel": .init(argumentCount: 2, returnKind: .string),
        "getfirstitemselected": .init(argumentCount: 0, returnKind: .integer),
        "getnextitemselected": .init(argumentCount: 1, returnKind: .integer),
        "scrolltoitem": .init(argumentCount: 1, returnKind: .null),
        // The write half of the same control, and Big Bento Modern's Web Reader is the measured
        // consumer: its provider drop-down adds a placeholder row per `parser_onCallback` and
        // then fills that row's two columns and its icon. The three `setIcon*`/`setShowIcons`
        // calls sit at the very top of the same `onSetVisible` that loads the provider file, so
        // until they existed the handler aborted before reaching the parser at all.
        "setitemlabel": .init(argumentCount: 2, returnKind: .null),
        "setsubitem": .init(argumentCount: 3, returnKind: .null),
        "setitemicon": .init(argumentCount: 2, returnKind: .null),
        // `setSelected(row, selected)` — the write half of `getFirstItemSelected`. The reader
        // selects the provider it restored so the drop-down opens on it.
        "setselected": .init(argumentCount: 2, returnKind: .null),
        "seticonwidth": .init(argumentCount: 1, returnKind: .null),
        "seticonheight": .init(argumentCount: 1, returnKind: .null),
        "setshowicons": .init(argumentCount: 1, returnKind: .null),
        "leftclick": .init(argumentCount: 0, returnKind: .null),
        // Layer FX: Winamp warps a layer through a grid whose per-pixel source is supplied by the
        // skin's own `fx_onGetPixel*` callbacks — implemented in Phase 28 (`invokeLayerFX`,
        // `layerFXMesh(for:)`). Arities are read off the call sites, not assumed
        // (`WINAMP_MODERN_RENDER_DISASM=fx_setgridsize`): every setter takes one argument except
        // `fx_setGridSize(w, h)`, and `fx_update()` takes none.
        "fx_setenabled": .init(argumentCount: 1, returnKind: .null),
        "fx_setalphamode": .init(argumentCount: 1, returnKind: .null),
        "fx_restart": .init(argumentCount: 0, returnKind: .null),
        "fx_getenabled": .init(argumentCount: 0, returnKind: .boolean),
        "fx_getwrap": .init(argumentCount: 0, returnKind: .boolean),
        "fx_getrect": .init(argumentCount: 0, returnKind: .boolean),
        "fx_getbgfx": .init(argumentCount: 0, returnKind: .boolean),
        "fx_getclear": .init(argumentCount: 0, returnKind: .boolean),
        "fx_getrealtime": .init(argumentCount: 0, returnKind: .boolean),
        "fx_getlocalized": .init(argumentCount: 0, returnKind: .boolean),
        "fx_getbilinear": .init(argumentCount: 0, returnKind: .boolean),
        "fx_getalphamode": .init(argumentCount: 0, returnKind: .boolean),
        "fx_getspeed": .init(argumentCount: 0, returnKind: .integer),
        "fx_setwrap": .init(argumentCount: 1, returnKind: .null),
        "fx_setrect": .init(argumentCount: 1, returnKind: .null),
        "fx_setbgfx": .init(argumentCount: 1, returnKind: .null),
        "fx_setclear": .init(argumentCount: 1, returnKind: .null),
        "fx_setrealtime": .init(argumentCount: 1, returnKind: .null),
        "fx_setlocalized": .init(argumentCount: 1, returnKind: .null),
        "fx_setbilinear": .init(argumentCount: 1, returnKind: .null),
        "fx_setspeed": .init(argumentCount: 1, returnKind: .null),
        "fx_setgridsize": .init(argumentCount: 2, returnKind: .null),
        "fx_update": .init(argumentCount: 0, returnKind: .null),
        // `Map`: a bitmap sampled by the script (the knob-angle lookup MMD3 drives its rotary
        // controls with). `new Map` yields a generic dynamic object; `loadMap` gives it its role.
        "loadmap": .init(argumentCount: 1, returnKind: .null),
        "inregion": .init(argumentCount: 2, returnKind: .boolean),
        "getvalue": .init(argumentCount: 2, returnKind: .integer),
        // A `Map` is also queried for its own size and for whole pixels: ClassicPro reads its
        // colour scheme out of a bitmap (`player.maki` builds the classic-vis colour bands from
        // `getARGBValue`) and sizes animations from `getWidth`/`getHeight`.
        "getargbvalue": .init(argumentCount: 3, returnKind: .integer),
        // `Region`: `loadFromMap(Map, Int threshold, Boolean reversed)` turns a map into a
        // shape, `offset` moves it into the clipped object's own space, and `setRegion` clips
        // the object to it. T800 fills its volume bar this way; the stock `customseek.m` its
        // seek ghost.
        "loadfrommap": .init(argumentCount: 3, returnKind: .null),
        // `loadFromBitmap(String bitmapid)` is the same region without the `Map` in front of it:
        // the shape is the bitmap's own opaque area. MMD3's `std.mi` declares the pair together
        // (`extern Region.loadFromMap(…); extern Region.loadFromBitmap(String bitmapid);`) and
        // three more skins call it — BLAKK's `boombox.m` clips its seek bar with
        // `seekregion.loadfrombitmap("player.bb-seek-region"); seek1.setregion(seekregion);`.
        "loadfrombitmap": .init(argumentCount: 1, returnKind: .null),
        "offset": .init(argumentCount: 2, returnKind: .null),
        "setregion": .init(argumentCount: 1, returnKind: .null),
        // Screen-space cursor position, in the same skin-pixel units as the x/y a mouse event
        // hands the script — the knob scripts mix the two in one expression.
        "getmouseposx": .init(argumentCount: 0, returnKind: .integer),
        "getmouseposy": .init(argumentCount: 0, returnKind: .integer),
        // "is the pointer still on me?" — what a button asks in `onLeftButtonUp` to tell a click
        // from a drag that left the control. Defix's every SUI tab does exactly that, so without
        // it the handler aborted at the first tab and the whole tab strip was inert.
        "ismouseoverrect": .init(argumentCount: 0, returnKind: .boolean),
        "ismouseover": .init(argumentCount: 2, returnKind: .boolean),
        "center": .init(argumentCount: 0, returnKind: .null),
        "atan": .init(argumentCount: 1, returnKind: .float),
        "geteq": .init(argumentCount: 0, returnKind: .integer),
        "geteqband": .init(argumentCount: 1, returnKind: .integer),
        "seteqband": .init(argumentCount: 2, returnKind: .null),
        "geteqpreamp": .init(argumentCount: 0, returnKind: .integer),
        "seteqpreamp": .init(argumentCount: 1, returnKind: .null),
        "seteq": .init(argumentCount: 1, returnKind: .null),
        "eject": .init(argumentCount: 0, returnKind: .null),
        "minimizeapplication": .init(argumentCount: 0, returnKind: .null),
        "restoreapplication": .init(argumentCount: 0, returnKind: .null),
        "activateapplication": .init(argumentCount: 0, returnKind: .null),
        "windowmenu": .init(argumentCount: 0, returnKind: .null),
        "settargetx": .init(argumentCount: 1, returnKind: .null),
        "settargety": .init(argumentCount: 1, returnKind: .null),
        "settargetw": .init(argumentCount: 1, returnKind: .null),
        "settargeth": .init(argumentCount: 1, returnKind: .null),
        "settargeta": .init(argumentCount: 1, returnKind: .null),
        "settargetspeed": .init(argumentCount: 1, returnKind: .null),
        "gototarget": .init(argumentCount: 0, returnKind: .null),
        "reversetarget": .init(argumentCount: 1, returnKind: .null),
        "canceltarget": .init(argumentCount: 0, returnKind: .null),
        "isgoingtotarget": .init(argumentCount: 0, returnKind: .boolean),
        "sendaction": .init(argumentCount: 6, returnKind: .null),
        "triggeraction": .init(argumentCount: 2, returnKind: .null),
        "getleftvumeter": .init(argumentCount: 0, returnKind: .integer),
        "getrightvumeter": .init(argumentCount: 0, returnKind: .integer),
        // `extern Int System.getVisBand(int channel, int band); // 0,1 / 0..75` (std.mi). Every
        // meter a skin draws itself reads this — Defix's speaker cones, VU needles and level
        // bars all poll it from a timer — so without it those layers never move at all.
        "getvisband": .init(argumentCount: 2, returnKind: .integer),
        // `extern AlbumArtLayer.isLoading()`. Defix's playlist window polls it every tick, and
        // the miss aborted that whole `ontimer` handler continuously.
        "isloading": .init(argumentCount: 0, returnKind: .boolean),
        "refresh": .init(argumentCount: 0, returnKind: .null),
        "getvolume": .init(argumentCount: 0, returnKind: .integer),
        "setvolume": .init(argumentCount: 1, returnKind: .null),
        "seekto": .init(argumentCount: 1, returnKind: .null),
        "getplayitemlength": .init(argumentCount: 0, returnKind: .integer),
        "getplaylistlength": .init(argumentCount: 0, returnKind: .integer),
        "getplaylistindex": .init(argumentCount: 0, returnKind: .integer),
        "integertostring": .init(argumentCount: 1, returnKind: .string),
        "integertotime": .init(argumentCount: 1, returnKind: .string),
        "integertolongtime": .init(argumentCount: 1, returnKind: .string),
        "floattostring": .init(argumentCount: 2, returnKind: .string),
        "stringtointeger": .init(argumentCount: 1, returnKind: .integer),
        "stringtofloat": .init(argumentCount: 1, returnKind: .float),
        // MAKI's casts are System methods: `System.Integer(v)`, `System.Float(v)`, … A script
        // reaches for them wherever it mixes a float with an int-typed API — Love is War Miku's
        // volume buttons keep the level as a float and hand `Integer(level)` to `setVolume`, so
        // without these the whole volume path aborted at the first press.
        "integer": .init(argumentCount: 1, returnKind: .integer),
        "float": .init(argumentCount: 1, returnKind: .float),
        "string": .init(argumentCount: 1, returnKind: .string),
        "boolean": .init(argumentCount: 1, returnKind: .boolean),
        // MAKI's math library, all `System` methods. Measured demand, not a shopping list:
        // Defix's VU needle computes its ballistics with `sqrt` and its rotation with `sin`/`cos`,
        // and the *whole* `onTimer` aborted on the first `sqrt` — which is why the needle styles
        // stood still even with Layer FX implemented.
        "sqrt": .init(argumentCount: 1, returnKind: .double),
        "pow": .init(argumentCount: 2, returnKind: .double),
        "sin": .init(argumentCount: 1, returnKind: .double),
        "cos": .init(argumentCount: 1, returnKind: .double),
        "tan": .init(argumentCount: 1, returnKind: .double),
        "asin": .init(argumentCount: 1, returnKind: .double),
        "acos": .init(argumentCount: 1, returnKind: .double),
        "atan2": .init(argumentCount: 2, returnKind: .double),
        "log": .init(argumentCount: 1, returnKind: .double),
        "log10": .init(argumentCount: 1, returnKind: .double),
        "exp": .init(argumentCount: 1, returnKind: .double),
        "abs": .init(argumentCount: 1, returnKind: .double),
        "strlen": .init(argumentCount: 1, returnKind: .integer),
        "strlower": .init(argumentCount: 1, returnKind: .string),
        "strupper": .init(argumentCount: 1, returnKind: .string),
        "strsearch": .init(argumentCount: 2, returnKind: .integer),
        // Percent-encoding for a search term a skin is about to put in a URL. Every measured call
        // sits *inside* the expression that builds the address — Big Bento's lyrics finder is
        // `"…/search?q=" + urlEncode(artist) + " " + urlEncode(title) + " lyrics"` — so refusing
        // it took the whole handler down and the two magnifier buttons did nothing at all, one
        // layer before the navigation this phase is about (B40).
        "urlencode": .init(argumentCount: 1, returnKind: .string),
        "strleft": .init(argumentCount: 2, returnKind: .string),
        "strright": .init(argumentCount: 2, returnKind: .string),
        "strmid": .init(argumentCount: 3, returnKind: .string),
        // The extension of a filename, without the dot. Defix reads it off the playing item
        // (`getExtension(getPlayItemMetaDataString("filename"))`) for the display's format
        // readout, in the middle of the main layout's `onScriptLoaded` — so refusing it took the
        // rest of that handler, and the whole display area, down with it.
        "getextension": .init(argumentCount: 1, returnKind: .string),
        // `getPath(filename)` — the *directory* half, the way `getExtension` is the tail. Pure
        // string work on a string the host already handed out: it opens nothing and reaches no
        // filesystem. Big Bento's file-info panel prints it as the track's folder, and the corpus
        // always calls it on the playing item.
        "getpath": .init(argumentCount: 1, returnKind: .string),
        // …and its complement, the leaf. `getPath` + `removePath` is how a skin splits an item
        // into "folder" and "file" for two separate readouts.
        "removepath": .init(argumentCount: 1, returnKind: .string),
        "translate": .init(argumentCount: 1, returnKind: .string),
        "getprivateint": .init(argumentCount: 3, returnKind: .integer),
        "setprivateint": .init(argumentCount: 3, returnKind: .null),
        // The string half of the same store. Unreachable until Phase 24 dispatched `onResize`:
        // `CproTabs.m` reads its saved tab order out of it while laying the strip out, and the
        // missing method aborted that handler — so the tabs never re-sized to fit.
        "getprivatestring": .init(argumentCount: 3, returnKind: .string),
        "setprivatestring": .init(argumentCount: 3, returnKind: .null),
        "getitem": .init(argumentCount: 1, returnKind: .object),
        "getitembyguid": .init(argumentCount: 1, returnKind: .object),
        "newitem": .init(argumentCount: 2, returnKind: .object),
        "newattribute": .init(argumentCount: 2, returnKind: .object),
        "getattribute": .init(argumentCount: 1, returnKind: .object),
        "getdata": .init(argumentCount: 0, returnKind: .string),
        "getattributename": .init(argumentCount: 0, returnKind: .string),
        "setdata": .init(argumentCount: 1, returnKind: .null),
        "ondatachanged": .init(argumentCount: 0, returnKind: .null),
        "setdelay": .init(argumentCount: 1, returnKind: .null),
        "getdelay": .init(argumentCount: 0, returnKind: .integer),
        "start": .init(argumentCount: 0, returnKind: .boolean),
        "stop": .init(argumentCount: 0, returnKind: .null),
        "isrunning": .init(argumentCount: 0, returnKind: .boolean),
        // Window-manager notifications around a layout resize. Arities read out of the bytecode
        // rather than guessed (`WINAMP_MODERN_RENDER_DISASM`): each is called on the layout, and
        // counting the net pushes between receiver and call gives `beforeRedock()` /
        // `snapAdjust(x, y, w, h)`. Guessing here is not an option — a wrong count desynchronises
        // the interpreter's stack.
        "beforeredock": .init(argumentCount: 0, returnKind: .null),
        "redock": .init(argumentCount: 0, returnKind: .null),
        "snapadjust": .init(argumentCount: 4, returnKind: .null),
        // `debugString(msg, level)` — a skin's own trace output. Two arguments, pinned by
        // ClassicPro (`debugString("setCustomVis=" + …, 9)`).
        "debugstring": .init(argumentCount: 2, returnKind: .null),
        "getviewportwidth": .init(argumentCount: 0, returnKind: .integer),
        "getviewportheight": .init(argumentCount: 0, returnKind: .integer),
        "getviewportleft": .init(argumentCount: 0, returnKind: .integer),
        "getviewporttop": .init(argumentCount: 0, returnKind: .integer),
        "getviewportwidthfromguiobject": .init(argumentCount: 1, returnKind: .integer),
        "getviewportheightfromguiobject": .init(argumentCount: 1, returnKind: .integer),
        "getviewportleftfrompoint": .init(argumentCount: 2, returnKind: .integer),
        "getviewporttopfrompoint": .init(argumentCount: 2, returnKind: .integer),
        "getviewportwidthfrompoint": .init(argumentCount: 2, returnKind: .integer),
        "getviewportheightfrompoint": .init(argumentCount: 2, returnKind: .integer),
        "getalbumart": .init(argumentCount: 1, returnKind: .integer),
        "getviewportleftfromguiobject": .init(argumentCount: 1, returnKind: .integer),
        "getviewporttopfromguiobject": .init(argumentCount: 1, returnKind: .integer),
        // The **monitor** family, which is the viewport's whole-screen twin: Winamp's viewport is
        // the work area, the monitor is the display it sits on. Big Bento's notifier asks for both
        // one after the other, and its `pledit.maki` sizes the side playlist from
        // `getMonitorWidth()` — so with this unimplemented the `onAction("load_comp")` that moves
        // the playlist beside the player aborted, and with it every option that governs that
        // playlist ("Enlarge Playlist" had nothing left to enlarge). Arity 0, pinned by the four
        // call sites in that skin.
        "getmonitorwidth": .init(argumentCount: 0, returnKind: .integer),
        "getmonitorheight": .init(argumentCount: 0, returnKind: .integer),
        "getmonitorleft": .init(argumentCount: 0, returnKind: .integer),
        "getmonitortop": .init(argumentCount: 0, returnKind: .integer),
        // The player window's own box. `getCurAppWidth`/`getCurAppHeight` were missing while
        // their two siblings were present, and `two/scripts/presetpos.m` calls all four in one
        // expression — `saveFramePos()` died on the third call, so the F9–F12 preset positions
        // stored nothing and `gotoFramePos` could only ever restore its fallback.
        "getcurappleft": .init(argumentCount: 0, returnKind: .integer),
        "getcurapptop": .init(argumentCount: 0, returnKind: .integer),
        "getcurappwidth": .init(argumentCount: 0, returnKind: .integer),
        "getcurappheight": .init(argumentCount: 0, returnKind: .integer),
        "getruntimeversion": .init(argumentCount: 0, returnKind: .integer),
        "getskinname": .init(argumentCount: 0, returnKind: .string),
        // `System.getSettingsPath()` — where the player keeps its own configuration. Arity 0,
        // pinned by the bytecode (`v82 = v67.getSettingsPath() + "/WACUP_Tools/koopa.ini"`, then
        // a `File.load`/`exists` pair): the string is only ever concatenated with a filename and
        // probed. Missing it aborted 23 of Big Bento Modern's `onScriptLoaded` handlers.
        "getsettingspath": .init(argumentCount: 0, returnKind: .string),
        // `System.getApplicationPath()` — where the *player* is installed, as against
        // `getSettingsPath`'s where it keeps its configuration. Arity 0, pinned by the bytecode
        // (`getApplicationPath() + "/Lang/Winamp-es-us.wlz"`, then a `File.load`/`exists`/
        // `getSize` probe). Big Bento's Localization page is built entirely out of those probes.
        "getapplicationpath": .init(argumentCount: 0, returnKind: .string),
        "getcolortheme": .init(argumentCount: 0, returnKind: .string),
        "setcolortheme": .init(argumentCount: 1, returnKind: .null),
        "getnumcolorthemes": .init(argumentCount: 0, returnKind: .integer),
        "enumcolorthemes": .init(argumentCount: 1, returnKind: .string),
        "gettimeofday": .init(argumentCount: 0, returnKind: .integer),
        "getplayitemdisplaytitle": .init(argumentCount: 0, returnKind: .string),
        "getplayitemmetadatastring": .init(argumentCount: 1, returnKind: .string),
        "getplayitemstring": .init(argumentCount: 0, returnKind: .string),
        // `System.getDecoderName(item)` — the input plugin decoding the named item. Counted from
        // the call site, which is `getDecoderName(getPlayItemString())`: one argument, a string
        // back. Big Bento's file-info panel fills its *Decoder* line from it, in the same
        // `onSetVisible` that fills every other line, so the whole panel stayed empty without it.
        "getdecodername": .init(argumentCount: 1, returnKind: .string),
        "getstatus": .init(argumentCount: 0, returnKind: .integer),
        "getsonginfotext": .init(argumentCount: 0, returnKind: .string),
        "isvideo": .init(argumentCount: 0, returnKind: .boolean),
        "isvideofullscreen": .init(argumentCount: 0, returnKind: .boolean),
        "iskeydown": .init(argumentCount: 1, returnKind: .boolean),
        "isminimized": .init(argumentCount: 0, returnKind: .boolean),
        // Answered honestly, unlike its neighbours: a skin *gates work* on it. Multipass's drawer
        // "Focus Mode" returns early from its 100 ms timer whenever the app is inactive, so a
        // hardcoded `false` would not just mis-report — it would stop the drawers from ever
        // opening again once that option was turned on.
        "isappactive": .init(argumentCount: 0, returnKind: .boolean),
        "isdesktopalphaavailable": .init(argumentCount: 0, returnKind: .boolean),
        "istransparencyavailable": .init(argumentCount: 0, returnKind: .boolean),
        "istransparencysafe": .init(argumentCount: 0, returnKind: .boolean),
        "islayoutanimationsafe": .init(argumentCount: 0, returnKind: .boolean),
        "hasvideosupport": .init(argumentCount: 0, returnKind: .boolean),
        // The playing video's native size. Zero is the honest answer here for the same reason
        // `hasVideoSupport` is false — there is no video component behind a `.wal` holder — and it
        // is also what Winamp answers for an audio track, which is the case skins branch on.
        "getidealvideowidth": .init(argumentCount: 0, returnKind: .integer),
        "getidealvideoheight": .init(argumentCount: 0, returnKind: .integer),
        "lockui": .init(argumentCount: 0, returnKind: .null),
        "unlockui": .init(argumentCount: 0, returnKind: .null),
        "hidenamedwindow": .init(argumentCount: 1, returnKind: .null),
        "isnamedwindowvisible": .init(argumentCount: 1, returnKind: .boolean),
        "navigateurl": .init(argumentCount: 1, returnKind: .null),
        "navigateurlbrowser": .init(argumentCount: 1, returnKind: .null),
        "setclipboardtext": .init(argumentCount: 1, returnKind: .null),
        // Internet Explorer's own error page, which a `<browser>` asks Winamp to suppress so it
        // can show its own. There is no IE here — the surface is WebKit — so the preference is
        // recorded and nothing else; refusing it aborted the handler that sets it, which on Big
        // Bento Modern is the one that also loads the Web Reader's provider list.
        "setcancelieerrorpage": .init(argumentCount: 1, returnKind: .null),
        "addcommand": .init(argumentCount: 4, returnKind: .null),
        "addseparator": .init(argumentCount: 0, returnKind: .null),
        "addsubmenu": .init(argumentCount: 2, returnKind: .null),
        "checkcommand": .init(argumentCount: 2, returnKind: .null),
        "popatmouse": .init(argumentCount: 0, returnKind: .integer),
        "popatxy": .init(argumentCount: 2, returnKind: .integer),
        "newgroup": .init(argumentCount: 1, returnKind: .object),
        "newgroupaslayout": .init(argumentCount: 1, returnKind: .object),
        // `GroupList.instantiate(groupdef, count)` — the *list's* own expansion, as against
        // `System.newGroup`. The second argument is a **count**, not an index; the author's own
        // comment in `config_vscrollbars.m` says so, and the bytecode agrees
        // (`v103.instantiate(v121:"…part1", v6:1)`, receiver + two pushes, result assigned).
        "instantiate": .init(argumentCount: 2, returnKind: .object),
        "init": .init(argumentCount: 1, returnKind: .null),
        // Paint order within the parent. ClassicPro raises a tab while it is being dragged along
        // the strip, and the missing method aborted the whole drag handler.
        "bringtofront": .init(argumentCount: 0, returnKind: .null),
        "bringtoback": .init(argumentCount: 0, returnKind: .null),
        "messagebox": .init(argumentCount: 4, returnKind: .integer),
        "callme": .init(argumentCount: 1, returnKind: .null),
        // ClassicPro version gate (branch, not hard-block) + public config.
        "getbuildnumber": .init(argumentCount: 0, returnKind: .integer),
        "getwinampversion": .init(argumentCount: 0, returnKind: .string),
        "getpublicint": .init(argumentCount: 2, returnKind: .integer),
        "setpublicint": .init(argumentCount: 2, returnKind: .null),
        "getpublicstring": .init(argumentCount: 2, returnKind: .string),
        "setpublicstring": .init(argumentCount: 2, returnKind: .null),
        "switchskin": .init(argumentCount: 1, returnKind: .null),
        "getcurcfgval": .init(argumentCount: 0, returnKind: .integer),
        "getdate": .init(argumentCount: 0, returnKind: .integer),
        // `System.random(max)` — one argument, settled from the bytecode rather than guessed
        // (`WINAMP_MODERN_RENDER_DISASM=random`: every one of the eighteen call sites in the
        // stock skin's `about.maki` pushes the receiver and exactly one value before `op24`).
        "random": .init(argumentCount: 1, returnKind: .integer),
        "getdatedoy": .init(argumentCount: 1, returnKind: .integer),
        "getdateyear": .init(argumentCount: 1, returnKind: .integer),
        "getdatehour": .init(argumentCount: 1, returnKind: .integer),
        "getdatemin": .init(argumentCount: 1, returnKind: .integer),
        "getdatesec": .init(argumentCount: 1, returnKind: .integer),
        "isobjectvalid": .init(argumentCount: 1, returnKind: .boolean),
        "chr": .init(argumentCount: 1, returnKind: .string),
        "next": .init(argumentCount: 0, returnKind: .null),
        "previous": .init(argumentCount: 0, returnKind: .null),
        // ClassicPro `ClassicProFile` shell service (the entire native surface, P0B §1).
        // `XmlDoc`: load an optional config document. Bounded — see `DynamicRole.xmlDocument`.
        "load": .init(argumentCount: 1, returnKind: .null),
        "exists": .init(argumentCount: 0, returnKind: .boolean),
        // `XmlDoc`'s callback parser. The document is walked once by `parser_start()`, which
        // dispatches `parser_onCallback` back at the same object for every element matching a
        // path registered with `parser_addCallback`. Big Bento Modern's Web Reader is the whole
        // measured demand: its provider drop-down is built entirely from those callbacks, so
        // without them `exists()` answered false, the skin took its "Oops! Something went wrong!"
        // branch on every `onSetVisible`, and the list came up empty.
        "parser_addcallback": .init(argumentCount: 1, returnKind: .null),
        "parser_start": .init(argumentCount: 0, returnKind: .null),
        "parser_destroy": .init(argumentCount: 0, returnKind: .null),
        "getfilesize": .init(argumentCount: 1, returnKind: .integer),
        "getlanguageid": .init(argumentCount: 0, returnKind: .string),
        // `List`: MAKI's own container (`extern List.addItem(Any)` …). ClassicPro builds its tab
        // order, its widget registry and its beat-vis names in one, so a missing `addItem` aborts
        // the script that assembles the SUI's tab strip.
        "additem": .init(argumentCount: 1, returnKind: .integer),
        "enumitem": .init(argumentCount: 1, returnKind: .object),
        "getnumitems": .init(argumentCount: 0, returnKind: .integer),
        "removeitem": .init(argumentCount: 1, returnKind: .null),
        "removeall": .init(argumentCount: 0, returnKind: .null),
        "finditem": .init(argumentCount: 1, returnKind: .integer),
        // `BitList` — a sized array of flags, sharing the `List` backing store.
        "setsize": .init(argumentCount: 1, returnKind: .null),
        "getsize": .init(argumentCount: 0, returnKind: .integer),
        "setitem": .init(argumentCount: 2, returnKind: .null),
        // `WinampConfig.getGroup(guid)` → a `WinampConfigGroup`. Arities follow `winampconfig.mi`,
        // which is what the skin's compiler encoded.
        "getgroup": .init(argumentCount: 1, returnKind: .object),
        "getint": .init(argumentCount: 1, returnKind: .integer),
        "getbool": .init(argumentCount: 1, returnKind: .boolean),
        "getstring": .init(argumentCount: 1, returnKind: .string),
        "getcurrenttrackrating": .init(argumentCount: 0, returnKind: .integer),
        "setcurrenttrackrating": .init(argumentCount: 1, returnKind: .null),
        // A group's children, which ClassicPro walks to find the widgets a component bucket loaded.
        "getnumchildren": .init(argumentCount: 0, returnKind: .integer),
        "enumchildren": .init(argumentCount: 1, returnKind: .object),
        // `Group.getNumObjects` / `Group.enumObject` (`std.mi`) — the stock spelling of the same walk.
        // ClassicPro's InfoViewer (`auto_arange.m`) lays out its tag lines with it.
        "getnumobjects": .init(argumentCount: 0, returnKind: .integer),
        "enumobject": .init(argumentCount: 1, returnKind: .object),
        "explorefile": .init(argumentCount: 1, returnKind: .null),
        "openfile": .init(argumentCount: 2, returnKind: .null),
        "findfiles": .init(argumentCount: 3, returnKind: .integer),
        // Arity settled off the call sites (`RENDER_DISASM=playFile`): T800's
        // `quicksongpick.maki` emits `op1(v0) op1(v44) op112(playfile)` — receiver, one push —
        // and Big Bento's `progbutton.maki` the same shape with the path built by a subroutine.
        // The name is unique across the installed corpus and belongs to `System` at both sites.
        "playfile": .init(argumentCount: 1, returnKind: .null),
    ]

    /// The arity of `method` on a receiver declared by `classGUID`, or nil when the runtime has none.
    static func signature(for method: String, classGUID: String?) -> MakiMethodSignature? {
        // Both of these were recomputed per test below — the GUID five times, through a fold that
        // is itself O(n²) (see `MakiClassGUID.canonical`). They are loop-invariant for the call.
        let name = method.lowercased()
        // A program compiled without a class table (the pre-5.0 MAKI layout) carries no GUID here, so
        // it does not reach the class-gated table. None of the measured corpus's PlEdit callers are in
        // that form.
        if let canonical = classGUID.map(MakiClassGUID.canonical),
           let signature = Self.classSignatures[canonical]?[name] {
            return signature
        }
        if let signature = Self.generalSignatures[name] { return signature }
        // A script may call one of its own event handlers directly to reuse it — MMD3 runs its
        // crossfade slider's handler once at load with `slidercb.onSetPosition(slidercb.getPosition())`.
        // Without an arity the interpreter cannot unwind the stack, so only events with a known
        // signature are callable; the call dispatches the event exactly as the UI would.
        if let arity = dispatchableEventArity[name] {
            // `onAction` answers with an int (the drawer keeps the slot the widget manager gives it);
            // the rest are void.
            return .init(argumentCount: arity, returnKind: name == "onaction" ? .integer : .null)
        }
        return nil
    }
}

extension WinampModernScriptRuntime {
    func signature(for method: String, classGUID: String?) -> MakiMethodSignature? {
        if let signature = WinampModernScriptSignatures.signature(for: method, classGUID: classGUID) {
            return signature
        }
        // Record the miss here as well as in `unsupported(_:program:)`: the interpreter fails closed
        // on a missing *signature* (without an arity it cannot unwind the stack), so this is the path
        // most unimplemented methods actually take. Phase 7.3's tally never saw it.
        unsupportedMethodCalls[method.lowercased(), default: 0] += 1
        return nil
    }
}
