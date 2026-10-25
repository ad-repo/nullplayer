import AppKit
import CoreGraphics
import Foundation

/// The arity of every MAKI method the runtime answers, derived from the method tables, where each
/// arity is declared beside the body that answers it (B243); plus the events a script may call as
/// methods. The interpreter asks through `signature(for:classGUID:)`.
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
    /// The other arities of three events `dispatchableEventArity` keys by name, each on the one class
    /// that declares it (B182).
    private static let classEventArity: [String: [String: Int]] = [
        MakiClassGUID.wac: ["onnotify": 3],
        MakiClassGUID.system: ["onaccelerator": 3],
        MakiClassGUID.vis: ["onframe": 0],
    ]

    /// Every method table the runtime answers from, read off the lists the receivers dispatch through,
    /// so a table is declared here by being dispatched at all (B243).
    static var tables: [[MakiMethodDeclaration]] {
        typealias R = WinampModernScriptRuntime
        var tables = R.systemFamilies.map(\.declarations)
        tables += R.guiKindTables.map(\.table.declarations)
        tables += R.guiFamilies.map(\.declarations)
        tables += [R.colorManagerMethods, R.playlistEditorMethods, R.playlistManagerMethods].map(\.declarations)
        tables += [R.popupMethods.declarations, R.treeItemMethods.declarations,
                   R.dynamicMethods.declarations, R.pendingGUIMethods.declarations]
        return tables
    }

    /// Verbs answered only on their **declaring** class — which is what the interpreter passes as
    /// `classGUID`, and the reason a short verb like `apply` can be given an arity at all. Registering
    /// one globally would hand its arity to every class that happens to declare the same verb, and a
    /// wrong argument count is the one error the interpreter cannot recover from: it leaves values on
    /// the stack and desynchronises everything after the call. See `reference/scripting.md` →
    /// *`PlEdit`*, which records that failure mode. Checked before `generalSignatures`.
    ///
    /// `static`, and that is the whole point of both: these were once a **local** literal inside
    /// `signature(for:classGUID:)`, allocated and hashed on every method invocation the interpreter
    /// makes. Measured at 10.4% of the main thread on cPro Bento, whose realtime Layer FX layer
    /// dispatches 1320 calls a second (B103).
    private static let classSignatures: [String: [String: MakiMethodSignature]] = {
        var signatures = classEventArity.mapValues { $0.mapValues(MakiMethodSignature.init(argumentCount:)) }
        for declaration in tables.joined() {
            guard let owner = declaration.declaringClass else { continue }
            signatures[owner,
                       default: [:]][declaration.name] = signatures[owner]?[declaration.name] ?? declaration.signature
        }
        return signatures
    }()

    /// Every verb that is **not** gated on a declaring class, and the arity the interpreter must
    /// unwind the stack by. A name several tables declare carries one signature in all of them,
    /// which `WinampModernB243Tests` holds.
    private static let generalSignatures: [String: MakiMethodSignature] = {
        var signatures: [String: MakiMethodSignature] = [:]
        for declaration in tables.joined() where declaration.declaringClass == nil {
            signatures[declaration.name] = signatures[declaration.name] ?? declaration.signature
        }
        return signatures
    }()

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
        return dispatchableEventArity[name].map(MakiMethodSignature.init(argumentCount:))
    }
}

/// One call as a method body sees it: the name it came in under (a body several names share reads
/// it), the receiver, the arguments in source order and the calling program.
struct MakiCall<Receiver> {
    let method: String
    let receiver: Receiver
    let arguments: [MakiValue]
    let program: MakiProgram
}

extension MakiCall where Receiver == WasabiObject {
    var object: WasabiObject { receiver }
}

extension MakiCall where Receiver == UInt64 {
    /// The `PopupMenu` or `TreeItem` the call is on.
    var id: UInt64 { receiver }
}

/// A script-made object's id and the state it had when the call arrived.
struct MakiDynamicReceiver {
    let id: UInt64
    let state: WinampModernScriptRuntime.DynamicObjectState
}

extension MakiCall where Receiver == MakiDynamicReceiver {
    var id: UInt64 { receiver.id }
    var state: WinampModernScriptRuntime.DynamicObjectState { receiver.state }
}

/// A MAKI method declared once: the arity the interpreter unwinds the stack by, the class it is
/// gated on, and the body that answers it — side by side, so the two cannot drift (B243). A body
/// answers nil to pass the call on to the next table that declares the same name.
struct MakiMethodDefinition<Receiver> {
    typealias Body = (WinampModernScriptRuntime, MakiCall<Receiver>) throws -> MakiValue?
    let signature: MakiMethodSignature
    /// The canonical GUID of the one class the arity belongs to, or nil for every receiver.
    let declaringClass: String?
    let body: Body
}

/// What `WinampModernScriptSignatures` reads off a table: a name and its arity, without the body.
struct MakiMethodDeclaration {
    let name: String
    let signature: MakiMethodSignature
    let declaringClass: String?
}

/// One concern's methods, keyed by lowercased name.
struct MakiMethodTable<Receiver> {
    private var methods: [String: MakiMethodDefinition<Receiver>] = [:]

    subscript(name: String) -> MakiMethodDefinition<Receiver>? { methods[name] }

    var declarations: [MakiMethodDeclaration] {
        methods.map { MakiMethodDeclaration(name: $0.key, signature: $0.value.signature,
                                            declaringClass: $0.value.declaringClass) }
    }

    mutating func add(_ names: [String], _ argumentCount: Int, on declaringClass: String? = nil,
                      _ body: @escaping MakiMethodDefinition<Receiver>.Body) {
        for name in names {
            precondition(methods[name] == nil, "MAKI method '\(name)' declared twice in one table")
            methods[name] = MakiMethodDefinition(signature: .init(argumentCount: argumentCount),
                                                 declaringClass: declaringClass, body: body)
        }
    }

    mutating func add(_ name: String, _ argumentCount: Int, on declaringClass: String? = nil,
                      _ body: @escaping MakiMethodDefinition<Receiver>.Body) {
        add([name], argumentCount, on: declaringClass, body)
    }
}

extension WinampModernScriptRuntime {
    /// `call` answered from `table`, or nil when the table does not declare the name or its body
    /// passes.
    func answer<Receiver>(_ table: MakiMethodTable<Receiver>, _ call: MakiCall<Receiver>) throws -> MakiValue? {
        try table[call.method]?.body(self, call)
    }

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
