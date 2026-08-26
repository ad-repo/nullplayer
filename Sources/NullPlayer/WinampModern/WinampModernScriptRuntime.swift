import AppKit
import Foundation

/// One row of a menu a script built with `PopupMenu`, submenus resolved.
struct WinampModernPopupMenuItem {
    let title: String
    let commandID: Int32
    let checked: Bool
    let disabled: Bool
    let isSeparator: Bool
    let children: [WinampModernPopupMenuItem]
}

final class WinampModernScriptRuntime: MakiMethodDispatching {
    private enum DynamicRole {
        case generic
        case configItem(section: String)
        case configAttribute(section: String, key: String)
        /// A `Map` that has been given its bitmap. `new Map` and `new Timer` are indistinguishable at
        /// construction (the class GUIDs are not part of the archive), so the role is settled by the
        /// first call that only one of them accepts — here, `loadMap`.
        case map(bitmapID: String, source: WalSourceLocation)
        /// A `Region` that has been loaded from a map. Settled the same way a `Map` is: `new Region`
        /// is the same bare `new` as `new Map`, and only `loadFromMap` accepts a region.
        case region(clip: WasabiRegionClip)
        /// An `XmlDoc` the script asked to `load`. ClassicPro uses one only to read the optional
        /// `ClassicPro.xml` extras (songticker antialiasing, custom beat-vis names), always behind
        /// `if (myDoc.exists())`. The callback-driven parser is not implemented, so the document
        /// reports that it does not exist and every caller takes its own skip path.
        case xmlDocument
        /// A `WinampConfigGroup` — one section of Winamp's own preferences, addressed by GUID.
        /// ClassicPro reads exactly one value from one (`eq.m` asks whether the EQ uses classic or
        /// ISO frequencies before it labels the bands).
        case configGroup(section: String)
        /// A `GammaSet` — one named colour theme, handed back by `ColorMgr.getGammaSet(name)` and
        /// carrying only that name until `apply()` asks for it. Unlike `Map`/`Region`/`XmlDoc` this
        /// role is settled at *creation*, because the object never comes from a bare `new`.
        case gammaSet(name: String)
    }

    private struct DynamicObjectState {
        var role: DynamicRole = .generic
        var delayMilliseconds: Int32 = 5_000
        /// Backing store for a MAKI `List`. Kept on every dynamic object rather than in the role: a
        /// `List` is created by the same `new` as a `Timer` or a `Map` and only its first list call
        /// would distinguish it, and nothing else ever touches these items.
        var items: [MakiValue] = []
    }

    /// Ceiling on one `List`'s length. ClassicPro's longest is its tab order (a dozen entries); the
    /// cap is what stops a script appending in a loop from growing without bound.
    private static let maximumListItems = 4_096

    private struct TargetAnimationState {
        var currentX: Double
        var currentY: Double
        var currentW: Double
        var currentH: Double
        var currentAlpha: Double
        var targetX: Double
        var targetY: Double
        var targetW: Double
        var targetH: Double
        var targetAlpha: Double
        let startX: Double
        let startY: Double
        let startW: Double
        let startH: Double
        let startAlpha: Double
        let speed: Double
        var lastTick: Double
        let hasTargetX: Bool
        let hasTargetY: Bool
        let hasTargetW: Bool
        let hasTargetH: Bool
        let hasTargetA: Bool
    }

    let loadedSkin: WinampModernLoadedSkin
    let host: WinampModernHost
    let timers: MakiTimerService
    let interpreter: MakiInterpreter
    private(set) var programs: [MakiProgram] = []
    private(set) var isTornDown = false

    /// Names of MAKI methods the runtime was asked for but does not implement, with a call count each.
    /// Populated by `unsupported(_:program:)` before it throws. This is the measured-demand signal that
    /// drives Phase 7.3 API additions and feeds the per-skin compatibility report (Phase 7.2); it never
    /// changes execution semantics.
    private(set) var unsupportedMethodCalls: [String: Int] = [:]
    /// Diagnostics from script events that aborted without stopping the rest of the skin. Capped:
    /// a handler that fails on a repeating event (a timer or mouse move) would otherwise accumulate
    /// forever. The report de-duplicates anyway, so the cap costs no distinct information.
    private(set) var scriptFailures: [WalDiagnostic] = []
    private static let maximumRecordedScriptFailures = 512

    var graphDidMutate: (() -> Void)?
    /// A repaint, and nothing more — no re-layout, no surface reconciliation. Layer FX drives this
    /// 30 times a second per warped layer, and `graphDidMutate` is far too heavy for that path (it
    /// re-runs component-holder reconciliation, since a script may have built one). Falls back to
    /// `graphDidMutate` when a window has not supplied it.
    var repaintRequested: (() -> Void)?
    /// The same, for a repaint that is confined to **one object's rect**. A warped meter changes a
    /// few hundred pixels 30 times a second, and repainting the whole window for it costs three
    /// times as much per frame as repainting what moved (measured on Defix at Retina scale: 19.3 ms
    /// against 6.9 ms), which is the difference between a smooth reel and a rough one.
    var objectRepaintRequested: ((WasabiObject) -> Void)?
    /// Show a script-built popup menu and answer the command the user picked, or 0. The runtime
    /// resolves the submenu tree before calling, so the presenter only builds UI.
    ///
    /// A `nil` point is `popAtMouse`. A point is `popAtXY`, in **window-client space** — the space
    /// `clientToScreenX/Y` answer in, which is what every measured caller computes the point with.
    var popupPresenter: (([WinampModernPopupMenuItem], CGPoint?) -> Int32)?
    /// A layout switch or resize, addressed to the *container* whose script asked for it. A `.wal`
    /// skin has one script runtime and several windows; without the container id every playlist
    /// script that resized itself at startup resized the player instead.
    var layoutSwitchRequested: ((WasabiObjectID, String) -> Bool)?
    var layoutResizeRequested: ((WasabiObjectID, CGSize) -> Void)?
    /// A script moving its own *window*, in Winamp's screen coordinates (top-left origin, the space
    /// `getViewportWidth`/`getViewportHeight` answer in). A container's `x`/`y` are the window's
    /// position on the desktop, not a box inside a scene, so unlike every other geometry write these
    /// two reach nothing the renderer draws — Big Bento's notifier parks itself at the bottom-right
    /// corner with `resize()` and a `setTargetX/Y` animation, and with this unwired the toast stayed
    /// wherever the host had first placed it (BB27).
    var containerMoveRequested: ((WasabiObjectID, CGPoint) -> Void)?
    /// `layout.setScale(f)` — the skin asking for the **whole UI** at a different size. Defix's
    /// configurator offers seven of them (100–300%) and every one of its five window scripts calls
    /// this on its own layout from the same stored `SCALING`, so it is one global request repeated,
    /// not five per-window scales. NullPlayer answers it with its own **UI Size**: a `.wal` scene is
    /// always laid out on the skin's pixel grid and the view scales at the drawing and input
    /// boundaries (Phase 10), so a second, layout-local scale would be a rival to that one and the
    /// two would fight over every window's size. `nil` in the harness, and while a skin is still
    /// loading the host defers the request rather than resizing windows that do not exist yet.
    var uiScaleRequested: ((CGFloat) -> Void)?
    var actionRequested: ((String, String?) -> Void)?
    /// The object form of `navigateUrl`: only the addressed `<browser>` may navigate.
    var browserNavigationRequested: ((WasabiObjectID, String) -> Void)?
    /// The **global** form, which names no object: `System.navigateUrl` (the user's browser) and
    /// `System.navigateUrlBrowser` (the player's own). Both are routed rather than executed here —
    /// the address is skin-authored, so the window layer resolves it against
    /// `WinampModernWebNavigationPolicy` and the external route is confirmation-gated (B40).
    var globalNavigationRequested: ((WinampModernWebNavigationTarget, String) -> Void)?
    /// A script showing or hiding a **container** is asking for its *window*, not just for an
    /// attribute on the graph. Defix's SUI is reachable only this way: its four round PL/EQ/ML/VD
    /// buttons send the skin's own `opentab` action, and `skin.xml`'s `onAction` answers it with
    /// `getContainer("SUI").show()` — there is no host action and no markup `TOGGLE` for the host to
    /// see, so without this the attribute flipped and no window ever appeared. Fired on every call,
    /// not only on a change, because the window can be closed while the attribute still says visible;
    /// the host is the one that knows, and ignores a request that asks for the state it is already in.
    var containerVisibilityRequested: ((String, Bool) -> Void)?
    /// The other half of the pair: what the container's window state *is*, asked of the host, for
    /// `toggle()` and `isVisible()`. The graph's `visible` attribute cannot answer it — the window is
    /// shown and hidden by routes that never write the attribute — so a script that asks drifts out
    /// of step with the screen without it. `nil` (no host, as in the harness) reads the attribute.
    var containerVisibilityQuery: ((String) -> Bool?)?
    /// Which container's window has the keyboard, for `isActive()`. `nil` (the headless harness, or
    /// an id no window backs) reads as inactive for every container **except** when nothing has
    /// answered at all — see `isActive(_:)`.
    var containerActiveQuery: ((String) -> Bool?)?
    var themeNamesRequested: (() -> [String])?
    var activeThemeRequested: (() -> String)?
    var themeSwitchRequested: ((String) -> Bool)?
    /// Cursor position in the *skin's own pixel space* (the window's canvas), in skin pixels.
    ///
    /// **Not** the space a mouse event's x/y are in — those are relative to the receiver's parent
    /// (see `WinampModernMainView.dispatch`). A rotary-knob script combines the two in one
    /// expression precisely because they differ: mmd3's `getMousePosX() - x + knob.getLeft()` is the
    /// parent's origin plus the knob's own offset, i.e. the knob in cursor space.
    var mousePositionRequested: (() -> CGPoint)?
    /// `setFocus()` on an object: the view gives the keyboard to the `<edit>` it resolves to.
    var focusRequested: ((WasabiObject) -> Void)?
    /// The same cursor position, but in the pixel space of the window that renders `object` — which is
    /// a *different* window from the one `mousePositionRequested` answers for whenever the receiver
    /// lives in an auxiliary container. `System.getMousePos*` has no receiver and cannot ask this;
    /// `isMouseOverRect` does, and Defix's SUI tabs are in the SUI window while the mouse hook is
    /// installed by the main view, so comparing against the main window's space put every tab's
    /// hit somewhere else entirely. `nil` when no window renders the object (the headless harness).
    var mousePositionInObjectSpaceRequested: ((WasabiObject) -> CGPoint?)?
    /// A container's alpha changed via `container.setAlpha(v)`. The host maps this to window alpha
    /// so notifier fade animations are visible.
    var containerAlphaChanged: ((String, CGFloat) -> Void)?
    /// Whether the equalizer is on, for `System.getEQ()`.
    var equalizerEnabledRequested: (() -> Bool)?
    /// One EQ band, on MAKI's −127…127 scale (MMD3's bass/treble knobs read and write the bands).
    var equalizerBandRequested: ((Int) -> Int)?
    var equalizerBandSetterRequested: ((Int, Int) -> Void)?
    /// The EQ preamp, on the same MAKI −127…127 scale as a band.
    var equalizerPreampRequested: (() -> Int)?
    var equalizerPreampSetterRequested: ((Int) -> Void)?
    /// The playlist the `PlEdit` singleton addresses. Weak: the window controller owns the bridge,
    /// and a skin reload tears the runtime down first. `nil` in the headless harness, where every
    /// read falls back to `WasabiTextMetrics.componentTextProvider` and every write is a no-op.
    weak var componentHost: WinampModernComponentHost?
    /// `PlEdit.showTrack(n)` and `showCurrentlyPlayingTrack()` — scroll the drawn playlist so a row
    /// is on screen. The scroll offset lives in the renderer, which the runtime does not own, so the
    /// window supplies this the way it supplies the equalizer's setters.
    var playlistRevealRowRequested: ((Int) -> Void)?
    /// Diagnostic tap on every handler that actually ran, with the failure that aborted it or `nil`.
    ///
    /// Nil in the app. The render harness installs one because "did this script's `onScriptLoaded`
    /// run?" is otherwise unanswerable from outside: `hasBinding` reports what the *bytecode* declares,
    /// which is why `WINAMP_MODERN_RENDER_XUI`'s `onscriptloaded=false` was mistaken for a dead script
    /// in TASKS §15.6 — it says nothing about execution.
    var dispatchObserver: ((_ event: String, _ program: MakiProgram, _ failure: WalFailure?) -> Void)?
    /// One object's resolved rect and the box it resolved against, in skin pixels — supplied by the
    /// window that renders the object's container, since only a scene knows where anything landed.
    /// `nil` before any window is wired, and for an object outside the active layout.
    var resolvedGeometryRequested: ((WasabiObject) -> (frame: CGRect, parent: CGRect)?)?
    /// A script has finished an event that moved something, so resolved geometry may have changed and
    /// `onResize` is owed to whatever moved. Called once per outermost event, never mid-event.
    ///
    /// Wasabi resizes synchronously and notifies as it goes, and skins lean on it hard: cPro-Bento's
    /// "close side view" button collapses the playlist pane with `setPosition(0)` and then relies on
    /// `area_right.onResize` to swap the close button for the **open** one — which ships `visible="0"`.
    /// Without this, closing the playlist hid the only control that could bring it back.
    var geometryDidSettle: (() -> Void)?

    private struct ScriptEventKey: Hashable {
        let target: MakiObjectReference.Kind
        let event: String
        /// The programs a *scoped* dispatch was limited to; empty for a dispatch to all of them.
        ///
        /// Without this, cPro-Bento's tab strip could never come up. `CproTabs.m` builds its five tabs
        /// with `System.newGroup("cpro.tab")` **from inside its own `System.onScriptLoaded`**, and each
        /// new group declares `CproTabButton.maki`; `startScripts(addedBeneath:)` then dispatches
        /// `onScriptLoaded` to just those new programs — a nested dispatch of the same event to the
        /// same (System) target, which the guard below swallowed. So every tab button was created with
        /// its script's `trigger`/`label`/`grid` variables never bound, which is the real reason
        /// clicking a tab did nothing (TASKS §15.6 blamed the strip's own script, which does run).
        ///
        /// The subsets are disjoint by construction — `boundScriptPaths` binds each script path+owner
        /// exactly once — so distinguishing them cannot reopen the ping-pong the guard exists for, and
        /// `maximumRuntimeScriptStartDepth` bounds the nesting.
        let scope: [ObjectIdentifier]
    }
    /// Events currently on the interpreter stack. A skin can wire two objects to update each other
    /// (MMD3's seek slider and its ghost both call `setPosition` from the other's `onSetPosition`),
    /// which is a bounded ping-pong in Winamp but unbounded native recursion here — and native
    /// recursion is not something the interpreter's own call-depth budget can see.
    private var eventsBeingDispatched: Set<ScriptEventKey> = []

    /// One setting a skin registered with `ConfigItem.newAttribute`, in registration order.
    ///
    /// In Winamp these appear in the *preferences dialog*, not in the skin, so a skin that registers
    /// them and binds no control of its own — Defix registers eight display styles and three
    /// songticker modes that way — leaves them unreachable here unless the host lists them. The
    /// value is not carried on the struct: it lives in the skin's own namespaced configuration and
    /// is read on demand, so a skin that changes it from a script cannot leave this stale.
    struct RegisteredSetting: Equatable {
        /// The storage section — the item's GUID when it declared one, else its name. The same key
        /// `cfgattrib="{GUID};Name"` addresses, so a control the skin *does* bind and this list are
        /// two views of one value.
        let section: String
        /// What the skin called the item ("Visualizer", "Playlist"), for grouping.
        let sectionName: String
        let name: String
        let defaultValue: String
    }

    /// Every setting the loaded skin registered, in registration order, de-duplicated by
    /// section+name. Bounded: registration happens from script, so a skin that registers in a loop
    /// must not grow this without limit.
    private(set) var registeredSettings: [RegisteredSetting] = []
    private static let maximumRegisteredSettings = 512
    /// Display names for the sections above, learned from `Config.newItem(name, guid)`. `getItem`
    /// and `getItemByGuid` do not name anything new — they address an item that already exists.
    private var configItemNames: [String: String] = [:]

    private var nextPopupID: UInt64 = 1
    private var popupCommands: [UInt64: [PopupEntry]] = [:]
    private var dynamicObjects: [UInt64: DynamicObjectState] = [:]
    private var activeTargetAnimations: [WasabiObjectID: TargetAnimationState] = [:]
    private var activeLayoutByContainer: [WasabiObjectID: WasabiObjectID] = [:]
    private let preferenceNamespace: String

    /// Script bindings already parsed into `programs`, so a runtime-instantiated group's scripts are
    /// started exactly once even if the same group is instantiated again.
    private var boundScriptPaths: Set<WasabiScriptBinding> = []
    /// Memoised bitmap pixel sizes for `getAutoWidth`/`getLength`; `nil` records a resolved-but-unknown
    /// size.
    private var bitmapSizes: [String: (width: Int32, height: Int32)?] = [:]
    /// Decoded `Map` bitmaps, keyed by resource id. Maps are small lookup images (44×44 for MMD3's
    /// volume knob) and there are a handful per skin.
    /// Font resolution and text measurement, shared with the renderer so `getAutoWidth()` answers
    /// what the text will actually occupy when drawn.
    private lazy var metrics = WasabiTextMetrics(loadedSkin: loadedSkin)
    private var mapImages: [String: CGImage] = [:]
    private static let maximumCachedMaps = 16
    /// Ceiling on total loaded programs. Runtime instantiation (`System.newGroup`) can add scripts,
    /// so this bounds a skin that instantiates groups in a loop.
    private static let maximumRuntimePrograms = 512
    /// How deeply a runtime-instantiated group's `onScriptLoaded` may instantiate further groups.
    /// ClassicPro nests two levels (the SUI builds the tab strip, which builds each tab).
    private static let maximumRuntimeScriptStartDepth = 8
    private var runtimeScriptStartDepth = 0

    /// Standard GUI events a script is allowed to invoke as a method on an object, with their argument
    /// counts. Kept explicit: an unknown arity would desynchronise the interpreter's stack.
    private static let dispatchableEventArity: [String: Int] = [
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
        "onshownotification": 0,
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
        "onscriptunloading": 0
    ]

    /// Version-gate shim. ClassicPro's `WinampVersionCheck.maki` early-returns when the reported build
    /// number is at least the skin's required build (`2405` for cPro-Bento), so a comfortably modern
    /// value branches the script past its "please update Winamp" warning without hard-blocking.
    static let reportedWinampBuild: Int32 = 9999
    static let reportedWinampVersion = "5.9"

    /// The two `sendAction` names a skin's own reader script answers for itself, and which the host
    /// therefore only picks up when nothing did. See the `sendaction` case.
    static let scriptOwnedBrowserActions: Set<String> = ["browser_search", "browser_navigate"]

    /// What `System.urlEncode` leaves alone — RFC 3986's unreserved characters.
    static let urlUnreserved = CharacterSet(
        charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_.~")

    init(loadedSkin: WinampModernLoadedSkin, host: WinampModernHost,
         executionLimits: MakiExecutionLimits = .production,
         timers: MakiTimerService = MakiTimerService()) throws {
        self.loadedSkin = loadedSkin
        self.host = host
        self.timers = timers
        self.preferenceNamespace = loadedSkin.archive.sourceURL.deletingPathExtension().lastPathComponent
            .replacingOccurrences(of: ".", with: "_")
        self.interpreter = MakiInterpreter(dispatcher: DummyMakiDispatcher.shared,
                                           limits: executionLimits)
        self.interpreter.dispatcher = self
        // One script the parser cannot read must not take the whole skin down with it — the same
        // policy the event dispatch below already applies to a script that fails while running.
        // `Overdrive_2` is the measured case: four of its five programs are ordinary MAKI, and
        // `scripts/seek.maki` (2001) ships a header its own siblings do not, so the strict parse
        // aborted the load and the skin did not appear at all. The unreadable program is dropped,
        // its diagnostic lands in the compatibility report, and everything else runs.
        var parsedPrograms: [MakiProgram] = []
        var parseFailures: [WalDiagnostic] = []
        for binding in loadedSkin.runtime.scriptBindings {
            do {
                let data = try loadedSkin.vfs.data(at: binding.logicalPath, location: binding.source)
                parsedPrograms.append(try MakiBytecodeParser().parse(data, source: binding.source,
                                                                     ownerID: binding.ownerID,
                                                                     parameter: binding.parameter))
            } catch let failure as WalFailure {
                parseFailures.append(contentsOf: failure.diagnostics)
            }
        }
        parsedPrograms.forEach(Self.seedHostSingletons)
        self.programs = parsedPrograms
        self.boundScriptPaths = Set(loadedSkin.runtime.scriptBindings)
        self.scriptFailures = Array(parseFailures.prefix(Self.maximumRecordedScriptFailures))
        for root in loadedSkin.runtime.graph.roots where root.typeName.caseInsensitiveCompare("container") == .orderedSame {
            if let normal = root.children.first(where: {
                $0.typeName.caseInsensitiveCompare("layout") == .orderedSame &&
                ($0.xmlID?.caseInsensitiveCompare("normal") == .orderedSame || root.children.count == 1)
            }) {
                activeLayoutByContainer[root.stableID] = normal.stableID
            }
        }
    }

    func start() throws {
        host.beginVisualizationConsumption()
        // A skin-level `<scripts>` block sits at the end of `skin.xml`, after every object and every
        // XUI param, and Winamp loads it there — so it is the one script that may assume the rest of
        // the skin is already configured. Defix's does exactly that: its `onScriptLoaded` lays out
        // the whole SUI tab strip as `label.getAutoWidth() + 20` per tab, and run before the tab
        // labels arrived as params it sized all five to that bare 20px, stacked at the left edge.
        //
        // Object-owned scripts keep the order they had: all of them, then the params (a XUI object's
        // handler binds to the script group `onScriptLoaded` populates, so its own params can never
        // come first — see `deliverXUIParams`).
        let skinLevel = programs.filter { isSkinLevel($0) }
        let owned = programs.filter { !isSkinLevel($0) }
        if !owned.isEmpty { _ = try dispatchSystem(event: "onscriptloaded", to: owned) }
        deliverXUIParams(forSubtreeOf: loadedSkin.runtime.graph.roots)
        if !skinLevel.isEmpty { _ = try dispatchSystem(event: "onscriptloaded", to: skinLevel) }
    }

    /// Wasabi hands a XUI object's XML attributes to its script as `onSetXuiParam(name, value)`.
    /// Winamp Modern's window frames rely on this entirely: `Wasabi:MainFrame:NoStatus
    /// content="player.content.group"` is inert XML until the script sees the `content` param and
    /// instantiates that group.
    ///
    /// Must run *after* `onScriptLoaded`: the handler is bound to the script's own group variable,
    /// which the script only populates via `getScriptGroup()` inside `onScriptLoaded`. Dispatched
    /// before that, no binding matches and every param is silently dropped.
    /// A script declared in a skin-level `<scripts>` block rather than on an object of its own.
    private func isSkinLevel(_ program: MakiProgram) -> Bool {
        guard let ownerID = program.ownerID,
              let owner = loadedSkin.runtime.graph.object(withID: ownerID) else { return true }
        return owner.typeName.caseInsensitiveCompare("scripts") == .orderedSame
    }

    private func deliverXUIParams(forSubtreeOf objects: [WasabiObject]) {
        for object in objects { deliverXUIParams(forSubtreeOf: object) }
    }

    private func deliverXUIParams(forSubtreeOf object: WasabiObject) {
        deliverXUIParams(for: object)
        for child in object.children { deliverXUIParams(forSubtreeOf: child) }
    }

    private func deliverXUIParams(for object: WasabiObject) {
        guard !object.scriptBindings.isEmpty else { return }
        let owned = programs.filter { $0.ownerID == object.stableID }
        guard !owned.isEmpty else { return }
        if loadedSkin.runtime.types.isXUITag(object.typeName) {
            // `onSetXuiParam` is a *System* event, and each XUI instance gets its own program
            // instance, so the params must go only to the programs that instance owns —
            // dispatching to every program would hand one frame's `content` to all of them.
            for (name, value) in object.attributes.sorted(by: { $0.key < $1.key }) {
                _ = try? dispatch(target: MakiObjectReference(.system), event: "onsetxuiparam",
                                  arguments: [.string(name), .string(value)], in: owned)
            }
        }
        // Wasabi's `notify="key,value"` delivers `key` as an XUI param with the given value.
        // Lobe uses `<group id="wasabi.standardframe.statusbar" notify="content,pledit.normal.
        // content.group">` — a `<group>` instance, not a XUI tag, so the standard param loop
        // above never fires, but the standard frame script still needs `content` to instantiate
        // the playlist body.
        if let notify = object.attributes["notify"] {
            let parts = notify.split(separator: ",", maxSplits: 1)
            if parts.count == 2 {
                let key = String(parts[0])
                let value = String(parts[1])
                _ = try? dispatch(target: MakiObjectReference(.system), event: "onsetxuiparam",
                                  arguments: [.string(key), .string(value)], in: owned)
            }
        }
    }

    /// `getAutoWidth()` — the width an object wants to be. A group delegates to the object named by
    /// its `autowidthsource` attribute, which is how the menubar sizes itself: each `menugroup.*`
    /// points at the layer holding its rendered label bitmap, and `menualign.maki` reads these
    /// widths to lay the menus out left-to-right. Returning a text estimate for those groups (the
    /// previous behaviour) left every menu at width 0, stacked on the same x.
    private func autoWidth(of object: WasabiObject) -> Int32 {
        if let sourceID = object.attributes["autowidthsource"],
           let source = descendant(of: object, xmlID: sourceID), source !== object {
            return autoWidth(of: source)
        }
        // Measured with the font the renderer draws with, not estimated: ClassicPro sizes every SUI
        // tab to `label.getAutoWidth() + 14` and lays its menu bar out from these numbers, so an
        // estimate that runs narrow clips every label inside a box the skin thinks fits it.
        //
        // The measurement outranks the declared `w`. For a `<text>` the *box* and the *string* are
        // two different numbers, and "auto" is the string's — a label declared `w="0" relatw="1"`
        // stretches to its parent and would otherwise answer with that stretch.
        let type = object.typeName.lowercased()
        if type == "text" || type == "songticker" {
            let text = WasabiTextMetrics.content(of: object, host: host)
            return Int32(clamping: Int(metrics.width(of: object, text: text).rounded(.up)))
        }
        if let explicit = object.attributes["w"], let width = Int32(explicit), width > 0 { return width }
        if let imageID = object.attributes["image"], let width = bitmapWidth(identifier: imageID) {
            return width
        }
        return 0
    }

    /// `getAutoHeight()` — the vertical twin of `autoWidth(of:)`, resolved from the same sources in
    /// the same order (a named source object, the font, a declared `h`, the artwork). Big Bento
    /// Modern's album-art script asks for both together (`getAutoWidth()` then `getAutoHeight()` on
    /// the cover layer) to keep the picture's aspect ratio, so answering one and aborting on the
    /// other took the whole cover panel's `onScriptLoaded` down with it.
    private func autoHeight(of object: WasabiObject) -> Int32 {
        if let sourceID = object.attributes["autoheightsource"],
           let source = descendant(of: object, xmlID: sourceID), source !== object {
            return autoHeight(of: source)
        }
        // A single line in the font the renderer would draw with, and it outranks the declared `h`
        // for the same reason the width measurement outranks `w` — see `autoWidth(of:)`. Big Bento
        // Modern's tab strip is the case that shows it: `tabcontrol.maki` sizes every SUI tab to
        // `4 * label.y + label.getAutoHeight()`, and the label is declared `h="60"` inside a 60-tall
        // tab. Answering 60 made each tab 96 tall, which stretched all seven icons vertically and
        // pushed the strip 37px per tab down the column. Measured, the answer is the font's 24 and
        // the arithmetic lands back on the skin's own 60.
        let type = object.typeName.lowercased()
        if type == "text" || type == "songticker" {
            return Int32(clamping: Int(metrics.lineHeight(of: object).rounded(.up)))
        }
        if let explicit = object.attributes["h"], let height = Int32(explicit), height > 0 { return height }
        if let imageID = object.attributes["image"], let height = bitmapHeight(identifier: imageID) {
            return height
        }
        return 0
    }

    /// Pixel width of a declared bitmap. Uses the resource's explicit `w` when the declaration crops
    /// a sprite sheet, otherwise reads the image header (no full decode) for whole-file bitmaps.
    private func bitmapWidth(identifier: String) -> Int32? { bitmapSize(identifier: identifier)?.width }

    private func bitmapHeight(identifier: String) -> Int32? { bitmapSize(identifier: identifier)?.height }

    private func bitmapSize(identifier: String) -> (width: Int32, height: Int32)? {
        let key = identifier.lowercased()
        if let cached = bitmapSizes[key] { return cached }
        var size: (width: Int32, height: Int32)?
        defer { bitmapSizes[key] = size }
        guard let definition = loadedSkin.runtime.resources.resolvedDefinition(identifier: identifier),
              definition.kind == "bitmap" else { return nil }
        var declared: (Int32?, Int32?) = (definition.attributes["w"].flatMap { Int32($0) },
                                          definition.attributes["h"].flatMap { Int32($0) })
        if declared.0 == nil || declared.1 == nil,
           let path = definition.logicalFile,
           let data = try? loadedSkin.vfs.data(at: path, location: definition.source),
           let source = CGImageSourceCreateWithData(data as CFData, nil),
           let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] {
            declared.0 = declared.0 ?? (properties[kCGImagePropertyPixelWidth] as? Int).map { Int32(clamping: $0) }
            declared.1 = declared.1 ?? (properties[kCGImagePropertyPixelHeight] as? Int).map { Int32(clamping: $0) }
        }
        if let width = declared.0, let height = declared.1, width > 0, height > 0 {
            size = (width, height)
        }
        return size
    }

    /// How many frames an `animatedlayer`'s sheet holds: its explicit `frames`, else the sheet
    /// divided by the layer's frame box (MMD3's volume knob is a 44×1012 strip of 44×44 frames).
    private func animationFrameCount(of object: WasabiObject) -> Int {
        if let raw = object.attributes["frames"], let count = Int(raw), count > 0 { return count }
        guard let imageID = object.attributes["image"], let sheet = bitmapSize(identifier: imageID) else { return 1 }
        let frameWidth = Int(object.attributes["framewidth"] ?? object.attributes["w"] ?? "") ?? Int(sheet.width)
        let frameHeight = Int(object.attributes["frameheight"] ?? object.attributes["h"] ?? "") ?? Int(sheet.height)
        guard frameWidth > 0, frameHeight > 0 else { return 1 }
        return max(1, (Int(sheet.width) / frameWidth) * (Int(sheet.height) / frameHeight))
    }

    private func animationFrame(of object: WasabiObject) -> Int {
        WasabiAnimation.state(of: object, frameCount: animationFrameCount(of: object)).frame
    }

    /// Sample a `Map`'s bitmap at a point in its own pixel space. Decoded images are cached, bounded
    /// by `maximumCachedMaps`; the bitmap itself passed the loader's dimension limits.
    private func mapPixel(bitmapID: String, source: WalSourceLocation, x: Int, y: Int)
        -> (red: UInt8, green: UInt8, blue: UInt8, alpha: UInt8, inBounds: Bool) {
        guard let image = mapImage(bitmapID: bitmapID, source: source) else { return (0, 0, 0, 0, false) }
        guard x >= 0, y >= 0, x < image.width, y < image.height else { return (0, 0, 0, 0, false) }
        let bitmap = WasabiBitmap(image: image, width: image.width, height: image.height, cost: 0)
        guard let pixel = bitmap.pixel(at: CGPoint(x: x, y: y)) else { return (0, 0, 0, 0, false) }
        return (pixel.red, pixel.green, pixel.blue, pixel.alpha, true)
    }

    private func mapImage(bitmapID: String, source scriptSource: WalSourceLocation) -> CGImage? {
        let key = bitmapID.lowercased()
        if let cached = mapImages[key] { return cached }
        guard mapImages.count < Self.maximumCachedMaps,
              let data = mapData(bitmapID: bitmapID, source: scriptSource),
              let imageSource = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(imageSource, 0, nil) else { return nil }
        mapImages[key] = image
        return image
    }

    /// `loadMap` takes *either* a declared bitmap id or a path. ClassicPro's install check is the
    /// second form — `warning.maki` loads `…\Plugins\classicPro\engine\image\installed.png` and
    /// treats a width other than 1 as "the plugin is missing", which made cPro-Bento conclude the
    /// engine was not installed and try to switch skins. Paths go through the VFS like any other
    /// resource, so they stay inside the mounts.
    private func mapData(bitmapID: String, source scriptSource: WalSourceLocation) -> Data? {
        guard let path = mapLogicalPath(bitmapID: bitmapID, source: scriptSource) else { return nil }
        return try? loadedSkin.vfs.data(at: path, location: scriptSource)
    }

    /// Where a map's bitmap actually lives, by either route. The renderer needs this for a region,
    /// because the path form leaves nothing in the resource registry for it to look the map up by.
    private func mapLogicalPath(bitmapID: String, source scriptSource: WalSourceLocation) -> String? {
        if let definition = loadedSkin.runtime.resources.resolvedDefinition(identifier: bitmapID),
           definition.kind == "bitmap", let path = definition.logicalFile,
           (try? loadedSkin.vfs.data(at: path, location: definition.source)) != nil {
            return path
        }
        return try? loadedSkin.vfs.resolve(bitmapID, relativeTo: scriptSource.path,
                                           location: scriptSource).logicalPath
    }

    /// Load and start the scripts a runtime-instantiated subtree declares, so nested components come
    /// up exactly as they would have at load time. Bounded by `maximumRuntimePrograms` so a script
    /// cannot grow the program list without limit by instantiating groups in a loop.
    /// Groups created by `System.newGroup` whose own scripts have not started yet.
    ///
    /// Wasabi instantiates a runtime group in two steps — `newGroup(id)` creates it, `init(parent)`
    /// puts it where it belongs — and the scripts inside it have to start *after* the second, because
    /// the first thing such a script does is look around from its own group (`getScriptGroup()`,
    /// `getParent()`, `findObject`). Starting them at creation gave cPro-Bento's tab buttons the tab
    /// strip's *container* as their parent instead of the strip, and their `setDispatcher` then
    /// addressed an object nothing was listening on.
    ///
    /// A skin that never calls `init` (it is optional — Winamp Modern's window frames simply leave the
    /// group where `newGroup` put it) is not left with dead scripts: whatever is still pending is
    /// started when the outermost dispatch finishes.
    private var pendingRuntimeGroups: [WasabiObject] = []

    /// Start the scripts of a pending runtime group, if `object` is one (or contains one — a script may
    /// `init` an ancestor of the group it created).
    private func startPendingScripts(for object: WasabiObject) throws {
        let matches = pendingRuntimeGroups.filter { $0 === object || Self.isDescendant($0, of: object) }
        guard !matches.isEmpty else { return }
        pendingRuntimeGroups.removeAll { pending in matches.contains { $0 === pending } }
        for match in matches { try startScripts(addedBeneath: match) }
    }

    /// Everything still waiting, in creation order. Called once the outermost dispatch unwinds.
    private func drainPendingScripts() {
        while !pendingRuntimeGroups.isEmpty {
            let next = pendingRuntimeGroups.removeFirst()
            // A group's `onScriptLoaded` can create more groups; those join the queue behind it.
            try? startScripts(addedBeneath: next)
        }
    }

    private static func isDescendant(_ object: WasabiObject, of ancestor: WasabiObject) -> Bool {
        var node = object.parent
        while let current = node {
            if current === ancestor { return true }
            node = current.parent
        }
        return false
    }

    private func startScripts(addedBeneath root: WasabiObject) throws {
        // A group's `onScriptLoaded` may itself instantiate groups (ClassicPro's tab strip does exactly
        // that, five times), so this is genuinely recursive. `maximumRuntimePrograms` bounds the total
        // but not the native stack depth, which this does.
        guard runtimeScriptStartDepth < Self.maximumRuntimeScriptStartDepth else {
            loadedSkin.runtime.record(WalDiagnostic(.scriptBudgetExceeded,
                                                    "Runtime group instantiation nested deeper than "
                                                    + "\(Self.maximumRuntimeScriptStartDepth); the "
                                                    + "scripts of '\(root.xmlID ?? root.typeName)' were "
                                                    + "not started.",
                                                    severity: .warning, location: root.source))
            return
        }
        runtimeScriptStartDepth += 1
        defer { runtimeScriptStartDepth -= 1 }
        var added: [MakiProgram] = []
        func collect(_ object: WasabiObject) throws {
            for binding in object.scriptBindings where !boundScriptPaths.contains(binding) {
                guard programs.count + added.count < Self.maximumRuntimePrograms else { return }
                boundScriptPaths.insert(binding)
                do {
                    let data = try loadedSkin.vfs.data(at: binding.logicalPath, location: binding.source)
                    added.append(try MakiBytecodeParser().parse(data, source: binding.source,
                                                                ownerID: binding.ownerID,
                                                                parameter: binding.parameter))
                } catch let failure as WalFailure {
                    // Same tolerance as the initial load: an unreadable program is dropped, not fatal.
                    if scriptFailures.count < Self.maximumRecordedScriptFailures {
                        scriptFailures.append(contentsOf: failure.diagnostics)
                    }
                }
            }
            for child in object.children { try collect(child) }
        }
        try collect(root)
        guard !added.isEmpty else { return }
        added.forEach(Self.seedHostSingletons)
        programs.append(contentsOf: added)
        try dispatchSystem(event: "onscriptloaded", to: added)
        deliverXUIParams(forSubtreeOf: root)
    }

    /// Start a subtree inserted by the host after global skin startup. The ordering is the same as
    /// any runtime-created group: object-owned `onScriptLoaded`, then XUI params. Global scripts are
    /// already running and are deliberately not restarted.
    func startTrustedHostedWindowScripts(beneath root: WasabiObject) throws {
        guard root.typeName.caseInsensitiveCompare("container") == .orderedSame,
              root.source.path == WasabiSurfaceSynthesizer.sourcePath,
              root.attributes[WinampModernContainerTopology.synthesizedAttribute] == "1"
        else {
            throw WalFailure(WalDiagnostic(.unsupportedScriptCapability,
                                           "Refused to start an untrusted hosted-window subtree.",
                                           location: root.source))
        }
        if let layout = root.children.first(where: {
            $0.typeName.caseInsensitiveCompare("layout") == .orderedSame
        }) {
            activeLayoutByContainer[root.stableID] = layout.stableID
        }
        try startScripts(addedBeneath: root)
    }

    /// The narrowest a track-change toast is allowed to be, whatever its layout declares.
    private static let notifierMinimumWidth: CGFloat = 350

    func setNotifierText(title: String, artist: String, album: String) {
        guard let container = findRoot(type: "container", xmlID: "notifier") else { return }
        let layouts = container.children.filter {
            $0.typeName.caseInsensitiveCompare("layout") == .orderedSame
        }
        // The 350 is a *floor*, not a size. Stock Winamp Modern declares its notifier layout
        // `w="128"` and hangs a `w="-95" relatw="1"` text group inside it — 33px, too narrow for a
        // title — so that skin's toast has to be widened to be readable at all. A skin that already
        // declares a usable width must keep it: Big Bento's notifier is `w="540"` with a 310px text
        // group, and forcing 350 on it left 120px for 46pt text, clipping every line.
        var width = Self.notifierMinimumWidth
        for layout in layouts {
            setTextInSubtree(layout, id: "title", text: title)
            setTextInSubtree(layout, id: "artist", text: artist)
            setTextInSubtree(layout, id: "album", text: album)
            setTextInSubtree(layout, id: "plentry", text: "")
            setTextInSubtree(layout, id: "nexttrack", text: "")
            setTextInSubtree(layout, id: "endofplayback", text: "")
            let declared = CGFloat(Int32(layout.attributes["w"] ?? "") ?? 0)
            let target = max(declared, Self.notifierMinimumWidth)
            width = max(width, target)
            _ = layout.setAttribute("w", value: String(Int(target)))
        }
        let height = CGFloat(Int32(layouts.first?.attributes["h"] ?? "80") ?? 80)
        layoutResizeRequested?(container.stableID, CGSize(width: width, height: height))
        noteGeometryChange()
        notifyGraphDidMutate()
    }

    private func setTextInSubtree(_ root: WasabiObject, id: String, text: String) {
        if let xmlID = root.xmlID,
           root.typeName.caseInsensitiveCompare("text") == .orderedSame,
           (xmlID.caseInsensitiveCompare(id) == .orderedSame ||
            xmlID.lowercased().hasPrefix(id.lowercased() + ".")) {
            _ = root.setAttribute("text", value: text)
            _ = root.setAttribute("default", value: text)
            _ = root.setAttribute(WasabiTextMetrics.scriptTextKey, value: text)
            _ = root.setAttribute(WasabiTextMetrics.scriptAlternateTextKey, value: "")
            notifyObjectDidMutate(root)
        }
        for child in root.children { setTextInSubtree(child, id: id, text: text) }
    }

    @discardableResult
    func dispatchSystem(event: String, arguments: [MakiValue] = []) throws -> Int {
        if recordsDispatchedEventsForTesting {
            dispatchedSystemEventsForTesting.append((event.lowercased(), arguments))
        }
        return try dispatch(target: MakiObjectReference(.system), event: event, arguments: arguments)
    }

    /// Test seam, off with the one above: the *system* events the runtime sent, with their arguments.
    /// A system event goes to whichever programs bind it, so unlike an object dispatch there is no
    /// receiver to assert against — the arguments are the whole observable.
    private(set) var dispatchedSystemEventsForTesting: [(event: String, arguments: [MakiValue])] = []

    /// Last content dispatched for each host-bound text object, so `onTextChanged` fires on a *change*
    /// rather than on every poll.
    private var lastDispatchedText: [WasabiObjectID: String] = [:]

    /// Test seam: what was last announced for an object, or `nil` if nothing has been.
    func lastDispatchedTextForTesting(_ object: WasabiObject) -> String? {
        lastDispatchedText[object.stableID]
    }

    /// Hand the skin a key press as `System.onKeyDown(<accelerator>)`, and say whether it took it.
    ///
    /// The accelerator is Winamp's own string (`WinampModernKeyAccelerator` builds it): the corpus's
    /// handlers compare it against a lowercase literal and nothing else. Dispatch is to **System**,
    /// so it reaches every program in the skin whatever window is focused — which is how Winamp does
    /// it, and why the two handlers that must not fire from the wrong window gate themselves on
    /// `isActive()` rather than expecting the host to route by focus.
    ///
    /// The answer is `complete;` — MAKI's "I dealt with this" — counted across the whole dispatch, so
    /// the view knows whether to swallow the key or pass it on to the responder chain. A handler that
    /// ran but matched none of its branches never reaches its `complete;` and the key falls through,
    /// which is the behaviour a skin with one accelerator and a live app around it needs.
    @discardableResult
    func dispatchKeyDown(_ accelerator: String) -> Bool {
        let before = interpreter.completionCount
        _ = try? dispatchSystem(event: "onkeydown", arguments: [.string(accelerator)])
        return interpreter.completionCount != before
    }

    /// Fire `onTextChanged(newtext)` on every text object whose host-bound content has changed.
    ///
    /// Winamp's `Text` object raises this whenever its content changes, and skins use it as the only
    /// signal that a host-supplied readout is worth re-reading. Defix's playlist box is the measured
    /// case: its `Items:`/`Time:` readouts are written by a subroutine whose **only** caller is
    /// `onTextChanged` — the `onTimer` beside it just stops a spinner. Never dispatching the event
    /// left that subroutine unreachable, so the box stayed on its XML placeholders no matter what the
    /// status line said.
    ///
    /// Bound text only: a `<text text="Add">` is a literal and cannot change, and re-dispatching for
    /// one would be a lie. Cheap enough to poll — the measured corpus declares a handful of bound
    /// text objects per skin, not hundreds.
    func refreshBoundText() {
        for object in loadedSkin.runtime.graph.allObjectsUnordered
        where WasabiTextMetrics.isHostBoundText(object) {
            let content = WasabiTextMetrics.content(of: object, host: host)
            let identifier = object.stableID
            if let previous = lastDispatchedText[identifier], previous == content { continue }
            // The **first** observation of real content fires too. Winamp raises the event when the
            // text goes from nothing to something, and a skin whose readouts are written only from
            // this handler has no other way to learn its opening value. Seeding silently instead —
            // the first thing this code did — meant a queue that was already populated before the
            // first poll never produced a change, so the event never fired at all and the readouts
            // stayed blank for the whole session. Empty content still says nothing.
            lastDispatchedText[identifier] = content
            guard !content.isEmpty else { continue }
            _ = try? dispatch(object: object, event: "ontextchanged", arguments: [.string(content)])
        }
    }

    /// Last equalizer values announced to the scripts, on MAKI's −127…127 scale. `nil` before the
    /// first observation, which is what makes the opening state an announcement rather than silence.
    private var lastDispatchedEQBands: [Int]?
    private var lastDispatchedEQPreamp: Int?

    /// Test seam: what the scripts were last told the equalizer was.
    var lastDispatchedEqualizerForTesting: (bands: [Int]?, preamp: Int?) {
        (lastDispatchedEQBands, lastDispatchedEQPreamp)
    }

    /// Raise `onEqBandChanged(band, value)` / `onEqPreampChanged(value)` for whatever moved, and put
    /// the skin's own EQ sliders on the new value first.
    ///
    /// Winamp raises these whenever the equalizer moves, *whoever* moved it — a preset, the menu bar,
    /// another window, the skin's own slider — and a skin's readout is written from nowhere else.
    /// multipass's eleven `ledfillbar` bars are the measured case: each one re-reads its
    /// `parentslider`'s position from this handler, which is why the slider positions are synced
    /// **before** the events go out. Rika and winampmodern566 use the value itself (Rika slices a
    /// region map at `128 - value`), so it must be the same −127…127 scale `getEqBand` answers in.
    ///
    /// One funnel for every route, and it dispatches only on an actual change: `System.setEqBand`
    /// comes through here too, so a skin that sets a band from its own handler cannot be told about
    /// its own write twice, and a poll costs eleven integer compares.
    func refreshEqualizerState() {
        guard !isTornDown else { return }
        guard let bandValue = equalizerBandRequested else { return }
        let bands = (0..<WinampModernEQAction.bandCount).map { bandValue($0) }
        let preamp = equalizerPreampRequested?() ?? 0
        let previousBands = lastDispatchedEQBands
        let previousPreamp = lastDispatchedEQPreamp
        guard previousBands != bands || previousPreamp != preamp else { return }
        lastDispatchedEQBands = bands
        lastDispatchedEQPreamp = preamp
        var movedSlider = false
        if previousPreamp != preamp {
            movedSlider = syncEqualizerSliders(for: .preamp, value: preamp) || movedSlider
        }
        for (index, value) in bands.enumerated() where previousBands?.indices.contains(index) != true
            || previousBands?[index] != value {
            movedSlider = syncEqualizerSliders(for: .band(index), value: value) || movedSlider
        }
        if movedSlider { notifyGraphDidMutate() }
        if previousPreamp != preamp {
            _ = try? dispatchSystem(event: "oneqpreampchanged",
                                    arguments: [.integer(Int32(clamping: preamp))])
        }
        for (index, value) in bands.enumerated() where previousBands?.indices.contains(index) != true
            || previousBands?[index] != value {
            _ = try? dispatchSystem(event: "oneqbandchanged",
                                    arguments: [.integer(Int32(index)), .integer(Int32(clamping: value))])
        }
    }

    /// Write the 0…255 position of every slider bound to `action`, so a script that reads the slider
    /// rather than the event (multipass's fillbars) sees the change too. The renderer already draws
    /// an EQ slider's thumb from the host, so this is the *script's* view of it catching up.
    /// Returns whether anything moved.
    private func syncEqualizerSliders(for action: WinampModernEQAction, value: Int) -> Bool {
        // −127…127 → 0…255, through the same ±12 dB midpoint the renderer and the drag use.
        let position = String(Int32(((Double(max(-127, min(127, value))) + 127) / 254 * 255).rounded()))
        var moved = false
        for object in loadedSkin.runtime.graph.allObjectsUnordered
        where object.typeName.caseInsensitiveCompare("slider") == .orderedSame {
            guard WinampModernEQAction.decode(action: object.attributes["action"],
                                              parameter: object.attributes["param"]) == action else { continue }
            guard object.attributes["value"] != position else { continue }
            _ = object.setAttribute("value", value: position)
            moved = true
        }
        return moved
    }

    /// Test seam, off by default: the GUI events the runtime sent, in order. The difference between
    /// `setActivated` and `setActivatedNoCallback` is *whether the event went out at all*, and with no
    /// script bound to `onToggle` there is nothing else in the graph that can show it. Off in the app
    /// because timers dispatch continuously and this would grow without bound.
    /// Run `body` as though it were the body of one dispatched event, so everything that settles when
    /// an event unwinds — the `onResize` pass, the stranded-control rule — settles **once** at the end
    /// rather than after each individual call. Tests only; the real path is `dispatch`.
    func withSimulatedEventForTesting(_ body: () throws -> Void) rethrows {
        let key = ScriptEventKey(target: .system, event: "__test__", scope: [])
        let inserted = eventsBeingDispatched.insert(key).inserted
        defer {
            if inserted {
                eventsBeingDispatched.remove(key)
                settleGeometryIfNeeded()
            }
        }
        try body()
    }

    var recordsDispatchedEventsForTesting = false
    private(set) var dispatchedEventsForTesting: [(object: String, event: String)] = []

    @discardableResult
    func dispatch(object: WasabiObject, event: String, arguments: [MakiValue] = []) throws -> Int {
        if recordsDispatchedEventsForTesting {
            dispatchedEventsForTesting.append((object.xmlID ?? object.typeName, event.lowercased()))
        }
        var handled = try dispatch(target: MakiObjectReference(.gui(object.stableID)),
                                   event: event, arguments: arguments)
        // A group that embeds a control (`embed_xui`) *is* that control as far as a script that holds
        // the group is concerned, so the pointer events the child receives are the group's too. Only
        // the mouse set is carried across: those are the events the embedding exists to express, and
        // forwarding lifecycle or data events would fire a handler twice for one occurrence.
        if Self.embeddedXUIForwardedEvents.contains(event) {
            for owner in embeddingOwners(of: object) {
                if recordsDispatchedEventsForTesting {
                    // Recorded here as well as above, or a test watching for the forward sees nothing
                    // and reads a working seam as a broken one.
                    dispatchedEventsForTesting.append((owner.xmlID ?? owner.typeName, event.lowercased()))
                }
                handled += try dispatch(target: MakiObjectReference(.gui(owner.stableID)),
                                        event: event, arguments: arguments)
            }
        }
        return handled
    }

    /// Route a `show()`/`hide()` on a top-level container to whoever owns that window. Anything else
    /// — a group, a layer, a layout — is graph state and stops here.
    private func requestWindow(for object: WasabiObject, visible: Bool) {
        // A **layout** counts as its container: showing a layout is how Winamp opens the window that
        // holds it, and skins say it that way as often as they name the container. Big Bento's
        // playlist search is the measured case — it fills the `searchresults` container's list, sizes
        // it, and then calls `show()` on that container's `normal` *layout*. Routed only from a
        // `<container>`, the results window never opened and pressing Return looked like a dead key,
        // with the search itself demonstrably running (BB31).
        let target: WasabiObject?
        if object.typeName.caseInsensitiveCompare("container") == .orderedSame {
            target = object
        } else if object.typeName.caseInsensitiveCompare("layout") == .orderedSame {
            target = Self.enclosingContainer(of: object)
        } else {
            target = nil
        }
        guard let target, let id = target.xmlID, !id.isEmpty else { return }
        containerVisibilityRequested?(id, visible)
    }

    /// Whether this object *is* a window — a `<container>` or one of its `<layout>`s. Both carry a
    /// desktop position rather than a position inside a parent.
    static func isWindowObject(_ object: WasabiObject) -> Bool {
        object.typeName.caseInsensitiveCompare("container") == .orderedSame
            || object.typeName.caseInsensitiveCompare("layout") == .orderedSame
    }

    /// The `<container>` an object lives in, or nil for one that is not inside a window.
    private static func enclosingContainer(of object: WasabiObject) -> WasabiObject? {
        var node: WasabiObject? = object.parent
        while let current = node {
            if current.typeName.caseInsensitiveCompare("container") == .orderedSame { return current }
            node = current.parent
        }
        return nil
    }

    /// A slider position held inside the `low…high` the object declares. Untouched when it declares
    /// neither, so nothing that never stated a range changes behaviour.
    private static func clampedSliderPosition(_ value: Int32, of object: WasabiObject) -> Int32 {
        let lowText = object.attributes["low"]
        let highText = object.attributes["high"]
        guard lowText != nil || highText != nil else { return value }
        let low = Int32(lowText ?? "") ?? 0
        let high = Int32(highText ?? "") ?? 255
        guard low <= high else { return value }
        return min(high, max(low, value))
    }

    private static let embeddedXUIForwardedEvents: Set<String> = [
        "onleftbuttondown", "onleftbuttonup", "onleftclick", "onleftbuttondblclk",
        "onrightbuttondown", "onrightbuttonup", "onrightclick", "onenterarea", "onleavearea",
        // The slider's *value* events belong to the embedding too, and for the same reason as the
        // pointer's: a `<groupdef embed_xui="slider">` **is** a slider to anyone holding the group, so
        // a script that binds `onSetPosition` to the group is asking about the embedded control.
        // Big Bento Modern's scrollbar is exactly this shape — `SC:VScrollBar` wraps a `<slider>` and
        // the up/down buttons nudge the *inner* one (`cscrollbar.maki`), while the settings page binds
        // its `onSetPosition` to the **outer** `vscroll`. Without the forward the page never learned
        // the bar had moved, so the buttons and the drag both lit up and scrolled nothing (BB19).
        "onsetposition", "onsetfinalposition", "onpostedposition"
    ]

    /// The `{GUID};Name` pair a control is bound to, or `nil` when it is not config-bound.
    static func configBinding(of object: WasabiObject) -> (section: String, key: String)? {
        guard let attribute = object.attributes["cfgattrib"] else { return nil }
        let parts = attribute.components(separatedBy: ";")
        guard parts.count >= 2 else { return nil }
        return (parts[0], parts[1...].joined(separator: ";"))
    }

    /// The current value of a `cfgattrib`-bound control, for the renderer's active-state decision.
    func configValue(of object: WasabiObject) -> Bool {
        guard let binding = Self.configBinding(of: object) else { return false }
        // A number is not a lamp: mmd3's crossfade *slider* names `Crossfade time`, and reading its
        // seconds as truthiness would light an `activeimage` for any non-zero duration.
        if let bridged = WinampModernConfigBridge.attribute(section: binding.section, key: binding.key) {
            guard bridged.isFlag else { return false }
            return WinampModernConfigBridge.value(of: bridged, host: host) != 0
        }
        return loadedSkin.configuration.integer(section: binding.section, key: binding.key, default: 0) != 0
    }

    /// The raw integer behind a `cfgattrib` binding — the lamps' 0/1 and the sliders' own unit —
    /// from the host for a bridged attribute and from the skin's namespace for its own.
    func configInteger(of object: WasabiObject) -> Int32? {
        guard let binding = Self.configBinding(of: object) else { return nil }
        return configInteger(section: binding.section, key: binding.key)
    }

    private func configInteger(section: String, key: String) -> Int32 {
        if let bridged = WinampModernConfigBridge.attribute(section: section, key: key) {
            return WinampModernConfigBridge.value(of: bridged, host: host)
        }
        return loadedSkin.configuration.integer(section: section, key: key, default: 0)
    }

    /// Flip a `cfgattrib`-bound control and tell the skin, returning false when it is not bound.
    ///
    /// Winamp's own preferences own these values, and a skin both writes them from its configurator
    /// and *reacts* to them. Defix's settings window is nine of these — each one a pair of
    /// togglebuttons over the same rect, a `ghost="1"` one that shows the state and a bare
    /// `rectrgn="1"` one that takes the click, both naming the same attribute. Neither carries an
    /// `action`, so nothing in the view had anything to run and every switch was inert.
    ///
    /// The notification is the half that matters: a skin applies a setting from `onDataChanged` on
    /// the `newAttribute` object it registered, not by polling. Writing the value silently would move
    /// the switch and change nothing on screen until the skin was reloaded. Every dynamic object bound
    /// to the same attribute is told, because each script registers its own.
    @discardableResult
    func toggleConfigAttribute(of object: WasabiObject) -> Bool {
        guard let binding = Self.configBinding(of: object) else { return false }
        let flipped = configInteger(section: binding.section, key: binding.key) != 0 ? "0" : "1"
        setConfigAttribute(section: binding.section, key: binding.key, value: flipped)
        return true
    }

    /// Write a `cfgattrib`-bound **slider** from a drag, mapping 0…1 through the control's own
    /// `low…high`, and returning false when it is not bound.
    ///
    /// The unit is the slider's, not Winamp's 0…255: mmd3's crossfade slider is cut `high="20"` and
    /// its readout prints the position as seconds, so handing it a 0…255 would have shown "255s".
    @discardableResult
    func setConfigAttribute(of object: WasabiObject, normalized: CGFloat) -> Bool {
        guard let binding = Self.configBinding(of: object) else { return false }
        let low = Double(object.attributes["low"] ?? "0") ?? 0
        let high = Double(object.attributes["high"] ?? "255") ?? 255
        let value = Int32((low + Double(max(0, min(1, normalized))) * (high - low)).rounded())
        guard configInteger(section: binding.section, key: binding.key) != value else { return true }
        setConfigAttribute(section: binding.section, key: binding.key, value: String(value))
        return true
    }

    /// Flip a togglebutton the way a *click* does, and tell the skin — returning false for anything
    /// that is not a plain togglebutton.
    ///
    /// Wasabi's togglebutton owns its own state: pressing it flips `activated` and then calls
    /// `onToggle(activated)`. Ours only ever changed from `setActivated`, which is a script talking
    /// to itself, so a togglebutton a person clicked was inert however completely the skin
    /// implemented it. Multipass's bottom drawer opens from `buttonDrawerBottomToggle.onToggle` and
    /// from nothing else — the button was hit, its bindings were live, and every handler count was
    /// zero.
    ///
    /// A `cfgattrib`-bound control is deliberately excluded: for those the stored preference *is* the
    /// state (`configValue`), they already have `toggleConfigAttribute` as their route, and flipping a
    /// second copy of the state here would let `getActivated()` disagree with the value the skin reads.
    @discardableResult
    func toggleActivation(of object: WasabiObject) -> Bool {
        guard object.typeName.caseInsensitiveCompare("togglebutton") == .orderedSame,
              Self.configBinding(of: object) == nil else { return false }
        let activated = object.attributes["activated"] != "1"
        _ = object.setAttribute("activated", value: activated ? "1" : "0")
        notifyObjectDidMutate(object)
        // The state is flipped *before* the notification, because that is what the handler reads:
        // multipass's `onToggle` asks the button `getActivated()` rather than trusting its argument.
        _ = try? dispatch(object: object, event: "ontoggle", arguments: [.boolean(activated)])
        notifyActivated(object, activated: activated)
        return true
    }

    /// `onActivate(int activated)` — Wasabi raises it whenever a button's activation changes,
    /// whoever changed it, and it is separate from `onToggle`: skins hang their *indicator* off this
    /// one. mmd3's three lamps and the three words in its display are `setAlpha(activated * 255)`
    /// from nothing else, so with no dispatch site at all no `.wal` skin could show a toggle's state.
    private func notifyActivated(_ object: WasabiObject, activated: Bool) {
        _ = try? dispatch(object: object, event: "onactivate", arguments: [.boolean(activated)])
    }

    /// The last value each bridged attribute was seen at, so a refresh only tells the skin about a
    /// setting that actually moved. Four entries — one per `WinampModernConfigBridge.Attribute`.
    private var lastBridgedValues: [String: Int32] = [:]

    /// Tell the skin that one of Winamp's playback options moved from **outside** it — NullPlayer's
    /// own Playback menu, a keyboard shortcut, a restored session.
    ///
    /// Without this the bridge is only half a fix: `configValue` would answer correctly the next
    /// time anything asked, but mmd3's lamps are not polled — their alpha is written once, from
    /// `onActivate`, and a shuffle toggled in the menu bar left the skin showing the old state.
    /// That is the same drift two copies of the setting used to cause, arriving by a different road.
    func refreshBridgedConfigState() {
        var moved = false
        for attribute in WinampModernConfigBridge.Attribute.allCases {
            let value = WinampModernConfigBridge.value(of: attribute, host: host)
            let cacheKey = "\(attribute.section);\(attribute.key)"
            let previous = lastBridgedValues.updateValue(value, forKey: cacheKey)
            // First sight seeds the cache without notifying: the skin read the value itself at load
            // (mmd3's `getActivated()` / `getPosition()` init), and an event for a change that never
            // happened would be a lie about what the person just did.
            guard let previous, previous != value else { continue }
            notifyActivationChanged(section: attribute.section, key: attribute.key)
            notifyPositionChanged(section: attribute.section, key: attribute.key, value: value)
            moved = true
        }
        if moved { notifyGraphDidMutate() }
    }

    /// A bound **slider** learns the same news through `onSetPosition` — that is where mmd3 prints
    /// its crossfade readout, and a duration changed from the Fade Duration menu has to reach it.
    private func notifyPositionChanged(section: String, key: String, value: Int32) {
        for object in loadedSkin.runtime.graph.allObjectsUnordered
        where object.typeName.caseInsensitiveCompare("slider") == .orderedSame {
            guard let binding = Self.configBinding(of: object),
                  binding.section.caseInsensitiveCompare(section) == .orderedSame,
                  binding.key.caseInsensitiveCompare(key) == .orderedSame else { continue }
            _ = try? dispatch(object: object, event: "onsetposition", arguments: [.integer(value)])
        }
    }

    /// Tell every control bound to `{section};key` that its activation moved.
    ///
    /// Bounded by the graph: this walks the objects that already exist, and a skin cannot declare
    /// more of them at runtime than `newGroup`'s own ceiling allows.
    private func notifyActivationChanged(section: String, key: String) {
        let activated = configInteger(section: section, key: key) != 0
        for object in loadedSkin.runtime.graph.allObjectsUnordered {
            guard let binding = Self.configBinding(of: object),
                  binding.section.caseInsensitiveCompare(section) == .orderedSame,
                  binding.key.caseInsensitiveCompare(key) == .orderedSame else { continue }
            notifyActivated(object, activated: activated)
        }
    }

    /// Write one configuration attribute and tell the skin — the single write route, shared by a
    /// `cfgattrib` control the skin drew itself and by the host's own settings list (Phase 27.3).
    /// A second route would let the two disagree about whether the skin was notified.
    func setConfigAttribute(section: String, key: String, value: String) {
        // A bridged attribute is Winamp's own playback option, and the host owns it. Writing it to
        // the skin's namespace as well would give one setting two homes that drift apart — a shuffle
        // toggled from the menu bar leaving the skin's lamp dark, and vice versa.
        if let bridged = WinampModernConfigBridge.attribute(section: section, key: key) {
            WinampModernConfigBridge.setValue(Int32(value) ?? (value.isEmpty ? 0 : 1),
                                              of: bridged, host: host)
            // The engine will post its options-changed notification for this very write, and
            // `refreshBridgedConfigState` must not read it back as news and raise `onActivate` a
            // second time for one click. Recording the settled value here is what makes the two
            // routes idempotent with each other.
            lastBridgedValues["\(bridged.section);\(bridged.key)"] =
                WinampModernConfigBridge.value(of: bridged, host: host)
        } else {
            loadedSkin.configuration.setString(value, section: section, key: key)
        }
        // Wasabi's togglebutton raises `onActivate` when its activation changes, and for a
        // config-bound button the attribute *is* that activation — so the write is the change. Every
        // object bound to this attribute hears it, because a skin declares the same switch once per
        // layout: mmd3's Crossfade button exists in `normal`, `shade` and `shade2`, and its
        // indicator layers are per-layout too.
        notifyActivationChanged(section: section, key: key)
        // **In creation order**, which is script-load order — never the dictionary's. Every script
        // that asks for an attribute gets its own object, so a radio group is a set of sibling
        // handlers that each re-assert their own state: Big Bento's Multi Content View has one per
        // page, and the one whose page is being *turned off* zeroes the others as it goes. Dispatched
        // in hash order, a sibling could run before the page the user actually picked and clear its
        // flag first, so that page's handler read `getData() != "1"` and never switched — the setting
        // changed, the panel did not, and on the next launch the stored page and the stored radio
        // disagreed and the skin opened both (the stretched visualization over the file info).
        // Swift's dictionary order is also unstable per process, so this failed differently per run.
        for (id, state) in dynamicObjects.sorted(by: { $0.key < $1.key }) {
            guard case .configAttribute(let attributeSection, let attributeKey) = state.role,
                  attributeSection.caseInsensitiveCompare(section) == .orderedSame,
                  attributeKey.caseInsensitiveCompare(key) == .orderedSame else { continue }
            _ = try? dispatch(target: MakiObjectReference(.dynamic(id)), event: "ondatachanged",
                              arguments: [])
        }
        notifyGraphDidMutate()
    }

    /// The registered settings that are actually *settings*, for a list a person reads.
    ///
    /// Winamp's config is a tree: a skin's root item registers one attribute per **child item**,
    /// whose value is that child's GUID (Defix: `Appearance = {F1036C9C-…}`). Measured against
    /// Defix, 6 of its 38 registrations are those structural links. They are navigation, not
    /// options, so they stay out of the list while `registeredSettings` keeps the raw measurement.
    var presentableSettings: [RegisteredSetting] {
        registeredSettings.filter { !Self.namesAnItem(configAttributeValue($0)) }
    }

    private static func namesAnItem(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespaces)
        return trimmed.hasPrefix("{") && trimmed.hasSuffix("}")
    }

    /// The current value of a registered setting, straight from the skin's own configuration.
    func configAttributeValue(_ setting: RegisteredSetting) -> String {
        loadedSkin.configuration.string(section: setting.section, key: setting.name,
                                        default: setting.defaultValue)
    }

    private func recordRegisteredSetting(section: String, name: String, defaultValue: String) {
        guard !name.isEmpty, registeredSettings.count < Self.maximumRegisteredSettings else { return }
        // Every script that needs a setting registers it again — Defix's eight scripts each register
        // the same eleven — so the same attribute arrives many times over one load.
        guard !registeredSettings.contains(where: {
            $0.section.caseInsensitiveCompare(section) == .orderedSame &&
            $0.name.caseInsensitiveCompare(name) == .orderedSame
        }) else { return }
        registeredSettings.append(RegisteredSetting(section: section,
                                                    sectionName: configItemNames[section] ?? section,
                                                    name: name, defaultValue: defaultValue))
    }

    /// The groups that declared `embed_xui` naming this object — the ancestors that speak for it.
    /// Nearly always none or one; the walk is up the parent chain, so it is bounded by tree depth.
    private func embeddingOwners(of object: WasabiObject) -> [WasabiObject] {
        guard let id = object.xmlID?.lowercased() else { return [] }
        var owners: [WasabiObject] = []
        var candidate = object.parent
        while let current = candidate {
            if current.attributes["nullplayer.embedxui"] == id { owners.append(current) }
            candidate = current.parent
        }
        return owners
    }

    /// Whether anything a script did during the current event could have moved an object. Only the
    /// mutations that can — geometry, visibility, parentage, splitter position — set it, so a skin whose
    /// timer merely advances an animation frame (cPro's beat display, every 10 ms) costs nothing.
    private var geometryMayHaveChanged = false
    /// Guards the settle callback against the `onResize` dispatch it makes re-entering it.
    private var isSettlingGeometry = false

    private func noteGeometryChange() {
        geometryMayHaveChanged = true
        // A mutation made *outside* any event (the host, or a direct call) has no event to unwind, so
        // it settles at once. Inside one it waits: a handler that moves five things in a row should
        // produce one round of `onResize`, not five.
        if eventsBeingDispatched.isEmpty { settleGeometryIfNeeded() }
    }

    /// `setXmlParam` keys that can move an object or take it out of the layout. Everything else a
    /// script writes (an image swap, a tooltip, a colour) leaves every frame where it was.
    private static let geometryKeys: Set<String> = [
        "x", "y", "w", "h", "relatx", "relaty", "relatw", "relath",
        "visible", "fitparent", "position", "sysregion"
    ]

    /// `setXmlParam` keys whose value names a resource rather than being a value in itself.
    private static let imageKeys: Set<String> = [
        "image", "bitmap", "background", "downimage", "hoverimage", "activeimage",
        "thumb", "downthumb", "hoverthumb", "notfoundimage"
    ]

    /// Does this identifier name a resource the skin actually registered? `background` is written
    /// with a colour id as well as a bitmap one, so the question is registration, not kind.
    private func resolvesToResource(_ identifier: String) -> Bool {
        loadedSkin.runtime.resources.resolvedDefinition(identifier: identifier) != nil
    }

    private func settleGeometryIfNeeded() {
        // Never mid-draw: a Layer FX callback runs inside a repaint, and settling geometry from there
        // would re-solve the scene while it is being painted.
        guard !isSettlingGeometry, !isEvaluatingLayerFX else { return }
        isSettlingGeometry = true
        defer { isSettlingGeometry = false }
        // Before the resize pass, and independently of whether a scene is listening: the stranding
        // rule is about the graph, and a headless load has no `geometryDidSettle` to hang it off.
        // A restore here marks the geometry dirty again, so the pass below sees the restored state.
        settleStrandedControls()
        guard geometryMayHaveChanged, let geometryDidSettle else { return }
        geometryMayHaveChanged = false
        geometryDidSettle()
    }

    /// Report a resize to the scene, as Wasabi does: every object whose own box changed hears about
    /// its **own** new geometry, in its own parent's coordinates.
    ///
    /// `previous` is the pre-change frame per object; pass `nil` to seed the whole scene, which is the
    /// one dispatch that has to happen after `start()` — a script that only assigns state inside
    /// `onResize` (ClassicPro's `beat.m` sets `showBeat`/`showPromo` nowhere else) has none of it until
    /// the event has fired at least once, and the first `onPlay` then hides its display for good.
    @discardableResult
    func dispatchResize(targets: [(object: WasabiObject, frame: CGRect)],
                        previous: [WasabiObjectID: CGRect]?) -> Int {
        var dispatched = 0
        // An object that has *left* the layout resized too, and it has to hear that exactly once.
        //
        // A pane collapsed to nothing takes its subtree out of the scene entirely: closing Big Bento's
        // side playlist leaves `player.component.playlist.frame` 0 wide, so `playlist.dualwnd` inside
        // it resolves to `w = 0 − 10` and the negative-box rule drops it and everything under it. The
        // group that reacts to the close — `player.component.playlist`, whose `onResize` is where
        // `pledit.maki` gives the tab area its width back — is inside that subtree, so it was never
        // told, and the SUI content kept the 335px hole the open playlist had left in it on every tab.
        //
        // Wasabi resizes a window to nothing rather than forgetting about it, so that is what this
        // does: the vanished object hears its old origin at 0×0, once, and then drops out of
        // `previous` because the caller records the new target set.
        if let previous {
            let present = Set(targets.map(\.object.stableID))
            for (id, before) in previous where !present.contains(id) {
                guard let object = loadedSkin.runtime.graph.object(withID: id),
                      hasBinding(for: object, event: "onresize") else { continue }
                let origin: [MakiValue] = [.integer(Int32(clamping: Int(before.minX))),
                                           .integer(Int32(clamping: Int(before.minY)))]
                dispatched += (try? dispatch(object: object, event: "onresize",
                                             arguments: origin + [.integer(0), .integer(0)])) ?? 0
            }
        }
        for target in targets {
            if let previous, let before = previous[target.object.stableID], before == target.frame {
                continue
            }
            let frame = target.frame
            let arguments: [MakiValue] = [.integer(Int32(clamping: Int(frame.minX))),
                                          .integer(Int32(clamping: Int(frame.minY))),
                                          .integer(Int32(clamping: Int(frame.width))),
                                          .integer(Int32(clamping: Int(frame.height)))]
            dispatched += (try? dispatch(object: target.object, event: "onresize",
                                         arguments: arguments)) ?? 0
        }
        return dispatched
    }

    func hasBinding(for object: WasabiObject, event: String? = nil) -> Bool {
        let target = MakiObjectReference(.gui(object.stableID))
        return programs.contains { program in
            program.bindings.contains { binding in
                if let event, program.methods[binding.methodIndex].name != event.lowercased() { return false }
                let variable = program.variables[binding.variableIndex]
                if self.object(variable.value, equals: target) { return true }
                return variable.classMembers.contains {
                    self.object(program.variables[$0].value, equals: target)
                }
            }
        }
    }

    @discardableResult
    private func dispatchSystem(event: String, to programs: [MakiProgram]) throws -> Int {
        try dispatch(target: MakiObjectReference(.system), event: event, arguments: [], in: programs)
    }

    /// Call a handler for its **answer** rather than for its effect, returning `nil` when the object
    /// has no such handler bound (or when the one it has aborted).
    ///
    /// Only the *first* matching handler runs: this is a question with one answer, unlike an event,
    /// which every listener hears. Layer FX is the only caller — see `layerFXMesh(for:)`.
    func call(object: WasabiObject, event: String, arguments: [MakiValue]) -> MakiValue? {
        var answer: MakiValue?
        _ = try? dispatch(target: MakiObjectReference(.gui(object.stableID)), event: event,
                          arguments: arguments, answer: &answer)
        return answer
    }

    @discardableResult
    private func dispatch(target: MakiObjectReference, event: String,
                          arguments: [MakiValue], in subset: [MakiProgram]? = nil) throws -> Int {
        var ignored: MakiValue?
        return try dispatch(target: target, event: event, arguments: arguments, in: subset,
                            answer: &ignored, stoppingAtFirstAnswer: false)
    }

    private func dispatch(target: MakiObjectReference, event: String, arguments: [MakiValue],
                          in subset: [MakiProgram]? = nil,
                          answer: inout MakiValue?, stoppingAtFirstAnswer: Bool = true) throws -> Int {
        guard !isTornDown else { return 0 }
        let eventName = event.lowercased()
        let key = ScriptEventKey(target: target.kind, event: eventName,
                                 scope: subset?.map(ObjectIdentifier.init) ?? [])
        let isOutermost = eventsBeingDispatched.isEmpty
        guard eventsBeingDispatched.insert(key).inserted else { return 0 }
        defer {
            eventsBeingDispatched.remove(key)
            // Once the whole event has unwound, any runtime group still waiting for an `init` that
            // never came gets its scripts started anyway (see `pendingRuntimeGroups`).
            if isOutermost {
                drainPendingScripts()
                settleGeometryIfNeeded()
            }
        }
        var executed = 0
        for program in subset ?? programs {
            for binding in program.dispatchBindings
            where program.methods[binding.methodIndex].name == eventName {
                let variable = program.variables[binding.variableIndex]
                var matches = object(variable.value, equals: target)
                if variable.isClass {
                    matches = variable.classMembers.contains { index in
                        object(program.variables[index].value, equals: target)
                    }
                    if matches { variable.value = .object(target) }
                }
                guard matches else { continue }
                do {
                    let result = try interpreter.execute(program: program, at: binding.instructionIndex,
                                                         arguments: arguments)
                    executed += 1
                    dispatchObserver?(eventName, program, nil)
                    if stoppingAtFirstAnswer {
                        answer = result
                        return executed
                    }
                } catch let failure as WalFailure {
                    dispatchObserver?(eventName, program, failure)
                    // One script hitting an unimplemented capability must not take the whole skin
                    // down with it — the remaining scripts still run and the skin loads degraded.
                    // The interpreter's stack is local to `execute`, so an aborted event leaves no
                    // shared state behind. Every failure lands in the compatibility report.
                    if scriptFailures.count < Self.maximumRecordedScriptFailures {
                        scriptFailures.append(contentsOf: failure.diagnostics)
                    }
                }
            }
        }
        return executed
    }

    /// Tell a container's scene it has been shown (or ordered out), as Wasabi does when a window
    /// appears — every visible object that listens hears `onSetVisible`, once per actual change.
    ///
    /// Winamp fires this for the objects a window brings on screen, and skins hang their whole
    /// animation on it: **Defix's cassette reels are switched on from exactly this handler**
    /// (`onSetVisible(1)` → `fx_setEnabled(1)` on `CASROLL`/`CASROLR` plus `Timer.start()`), and its
    /// speaker cabinets start their `getVisBand` timer the same way. Showing a native window with
    /// `orderFront` never touches the graph, so before this nothing in the scene was ever told, and
    /// the reels and cones stood still with nothing failing.
    ///
    /// Bounded by the object's own state: an object inside a hidden group is not on screen, so it is
    /// not told it is, and a container told the same thing twice dispatches once.
    func notifyContainerVisibility(containerID: WasabiObjectID, visible: Bool) {
        guard !isTornDown else { return }
        guard let container = loadedSkin.runtime.graph.object(withID: containerID) else { return }
        guard containerVisibility[containerID] != visible else { return }
        containerVisibility[containerID] = visible
        func walk(_ object: WasabiObject, ancestorsVisible: Bool) {
            let selfVisible = ancestorsVisible && isVisible(object)
            if selfVisible || !visible {
                _ = try? dispatch(object: object, event: "onsetvisible",
                                  arguments: [.boolean(visible)])
            }
            for child in object.children { walk(child, ancestorsVisible: selfVisible) }
        }
        walk(container, ancestorsVisible: true)
        notifyGraphDidMutate()
    }

    private var containerVisibility: [WasabiObjectID: Bool] = [:]

    // MARK: - Layer FX

    /// Per-layer FX configuration, written by the `fx_set*` methods.
    private var layerFXStates: [WasabiObjectID: WasabiLayerFXState] = [:]
    /// The last evaluated mesh per layer, reused until the skin calls `fx_update()` (or always
    /// re-evaluated when it asked for `fx_setRealtime(1)`).
    private var layerFXMeshes: [WasabiObjectID: WasabiLayerFXMesh] = [:]
    private var layerFXNeedsEvaluation: Set<WasabiObjectID> = []
    /// While a mesh is being evaluated, the callbacks run *inside a repaint*. A script that touched
    /// the graph from one would ask for another repaint and settle geometry mid-draw, so both are
    /// suppressed for the duration and the pending repaint is the one already in flight.
    private var isEvaluatingLayerFX = false

    /// Total vertices one layer may ask the interpreter to evaluate per mesh. `fx_setGridSize` takes
    /// script variables, so a skin can name any grid at all; this is what keeps a bad number off the
    /// UI thread. 65×65 covers every measured grid with room to spare (Defix asks for 1×1 on its
    /// cassette reels).
    private static let maximumLayerFXVertices = 65 * 65

    /// `WINAMP_MODERN_FX_TRACE=1` prints every `fx_*` call with its receiver — how "which layers does
    /// this skin warp, and when does it switch them on?" is answered without a debugger.
    private static let tracesLayerFX = ProcessInfo.processInfo.environment["WINAMP_MODERN_FX_TRACE"] != nil

    /// The FX configuration a layer's script has set, or `nil` when it has never called one.
    func layerFXState(of object: WasabiObject) -> WasabiLayerFXState? { layerFXStates[object.stableID] }

    /// Whether any layer in this skin currently has FX switched on — the signal a window uses to
    /// decide it needs the 30 Hz repaint clock.
    var hasEnabledLayerFX: Bool { layerFXStates.values.contains { $0.enabled } }

    /// Every layer with FX switched on, for the render harness (`WINAMP_MODERN_RENDER_FX=1`). The
    /// warp itself can only be seen under playback, but *which* layers are warped, how they are
    /// configured and how far the mesh moves are all answerable headlessly.
    var enabledLayerFXObjects: [WasabiObject] {
        layerFXStates.compactMap { id, state in
            guard state.enabled else { return nil }
            return loadedSkin.runtime.graph.object(withID: id)
        }
    }

    /// The warp for one layer, or `nil` when the layer has no enabled FX (the overwhelming majority —
    /// this is checked for every object in every frame, so the miss has to be a dictionary lookup).
    func layerFXMesh(for object: WasabiObject) -> WasabiLayerFXMesh? {
        guard !isTornDown, !isEvaluatingLayerFX else { return nil }
        guard let state = layerFXStates[object.stableID], state.enabled else { return nil }
        if !layerFXNeedsEvaluation.contains(object.stableID),
           let cached = layerFXMeshes[object.stableID] {
            return cached.isIdentity ? nil : cached
        }
        let mesh = evaluateLayerFXMesh(for: object, state: state)
        layerFXNeedsEvaluation.remove(object.stableID)
        layerFXMeshes[object.stableID] = mesh
        return mesh.isIdentity ? nil : mesh
    }

    /// Re-evaluate every warp whose skin has invalidated it, **off the paint path**.
    ///
    /// Evaluating a mesh runs the skin's `fx_onGetPixel*` callbacks once per grid vertex through the
    /// MAKI interpreter — 49 vertices × 2 layers × 30 Hz for Defix — and doing that lazily from
    /// `layerFXMesh(for:)` put all of it inside `NSView.draw`, between the frame the user is watching
    /// and the next one. The window's animation clock calls this *before* it invalidates, so the paint
    /// that follows finds a mesh already built and does nothing but resample.
    ///
    /// `fx_setRealtime(1)` means "re-run the callbacks every frame", and the frame clock is here, so a
    /// realtime layer is marked stale on each pass rather than re-evaluated inside the draw.
    func refreshLayerFXMeshes() {
        guard !isTornDown, !isEvaluatingLayerFX else { return }
        for (id, state) in layerFXStates where state.enabled {
            if state.realtime { layerFXNeedsEvaluation.insert(id) }
            guard layerFXNeedsEvaluation.contains(id),
                  let object = loadedSkin.runtime.graph.object(withID: id) else { continue }
            layerFXMeshes[id] = evaluateLayerFXMesh(for: object, state: state)
            layerFXNeedsEvaluation.remove(id)
        }
    }

    /// Every script bound to one layer's `fx_onGetPixelR`, with the answer each gives for one probe
    /// point — the harness probe behind "*which* script drives this layer's warp?". A layer can be
    /// configured by one script and animated by another (Defix's needles are), and only the first
    /// bound handler answers.
    func layerFXAnswerBreakdown(for object: WasabiObject, event: String = "fx_ongetpixelr",
                                arguments: [MakiValue] = [.double(0), .double(1), .double(1), .double(0.5)])
    -> [(program: String, answer: Double)] {
        var results: [(String, Double)] = []
        for program in programs {
            guard program.bindings.contains(where: {
                program.methods[$0.methodIndex].name == event.lowercased()
            }) else { continue }
            var answer: MakiValue?
            _ = try? dispatch(target: MakiObjectReference(.gui(object.stableID)), event: event,
                              arguments: arguments, in: [program], answer: &answer)
            guard let answer else { continue }
            let name = (program.source.path as NSString).lastPathComponent
            results.append(("\(name)[\(program.parameter ?? "-")]", answer.doubleValue))
        }
        return results
    }

    /// Force the next `layerFXMesh(for:)` to re-run the skin's callbacks. The harness uses it to
    /// measure a frame that really does re-evaluate, as a moving meter's does.
    func invalidateLayerFXMesh(for object: WasabiObject) {
        layerFXNeedsEvaluation.insert(object.stableID)
    }

    /// Whether this layer's warp is still waiting to be evaluated — the state `refreshLayerFXMeshes`
    /// exists to clear before the frame is painted rather than during it.
    func layerFXMeshIsPending(for object: WasabiObject) -> Bool {
        layerFXNeedsEvaluation.contains(object.stableID)
    }

    private func requestRepaint(for object: WasabiObject? = nil) {
        guard !isEvaluatingLayerFX else { return }
        if let object, let objectRepaintRequested { objectRepaintRequested(object) }
        else if let repaintRequested { repaintRequested() }
        else { graphDidMutate?() }
        notifyAuxiliaryViews(of: object)
    }

    /// Repaint sinks for the container windows that do **not** own the single-owner callbacks above.
    ///
    /// The main window owns `graphDidMutate`/`repaintRequested`/`objectRepaintRequested` because the
    /// theme, action, mouse and EQ callbacks beside them genuinely admit one owner. Repainting does
    /// not: a MAKI `Timer` is owned by the *runtime*, so a script in an auxiliary container ticks and
    /// mutates its own objects perfectly well — and then nothing told that window to redraw. Defix's
    /// playlist box writes its `Items:`/`Time:` readouts from `onTimer`, and its speaker cones step
    /// `SpeakerVis` the same way; both updated the graph and neither ever reached a screen.
    ///
    /// Each sink decides for itself whether the object is in its own container, so a warped layer on
    /// the main window does not drag every other window into its 30 Hz repaint.
    private var auxiliaryRepaintSinks: [AuxiliaryRepaintSink] = []

    private struct AuxiliaryRepaintSink {
        weak var owner: AnyObject?
        let repaint: (WasabiObject?) -> Void
    }

    /// Register a container window that renders this runtime's graph but does not drive it.
    /// `repaint` is called with the object that changed, or `nil` for "something did".
    func addAuxiliaryRepaintSink(owner: AnyObject, repaint: @escaping (WasabiObject?) -> Void) {
        auxiliaryRepaintSinks.removeAll { $0.owner == nil || $0.owner === owner }
        auxiliaryRepaintSinks.append(AuxiliaryRepaintSink(owner: owner, repaint: repaint))
    }

    func removeAuxiliaryRepaintSink(owner: AnyObject) {
        auxiliaryRepaintSinks.removeAll { $0.owner == nil || $0.owner === owner }
    }

    /// A graph change: the owning window re-lays-out and repaints, every other container window
    /// repaints. `settext`/`setxmlparam`/`show`/`hide` all land here, which is the path Defix's
    /// playlist readouts take.
    private func notifyGraphDidMutate() {
        graphDidMutate?()
        notifyAuxiliaryViews(of: nil)
    }

    private func notifyObjectDidMutate(_ object: WasabiObject) {
        graphDidMutate?()
        notifyAuxiliaryViews(of: object)
    }

    private func notifyAuxiliaryViews(of object: WasabiObject?) {
        guard !auxiliaryRepaintSinks.isEmpty else { return }
        auxiliaryRepaintSinks.removeAll { $0.owner == nil }
        for sink in auxiliaryRepaintSinks { sink.repaint(object) }
    }

    private func evaluateLayerFXMesh(for object: WasabiObject,
                                     state: WasabiLayerFXState) -> WasabiLayerFXMesh {
        var columns = state.vertexColumns
        var rows = state.vertexRows
        while columns * rows > Self.maximumLayerFXVertices {
            columns = max(2, columns / 2)
            rows = max(2, rows / 2)
        }
        // Which callbacks this layer actually implements, resolved once rather than per vertex: a
        // skin supplies only the coordinate it wants changed and leaves the other one alone.
        let events = state.rect ? ("fx_ongetpixelx", "fx_ongetpixely")
                                : ("fx_ongetpixelr", "fx_ongetpixeld")
        let hasFirst = hasBinding(for: object, event: events.0)
        let hasSecond = hasBinding(for: object, event: events.1)
        var sources = [CGPoint](repeating: .zero, count: columns * rows)
        isEvaluatingLayerFX = true
        defer { isEvaluatingLayerFX = false }
        for row in 0..<rows {
            for column in 0..<columns {
                let x = CGFloat(column) / CGFloat(columns - 1)
                let y = CGFloat(row) / CGFloat(rows - 1)
                let angle = WasabiLayerFXCoordinates.angle(x: x, y: y)
                let distance = WasabiLayerFXCoordinates.distance(x: x, y: y)
                let arguments: [MakiValue] = [.double(Double(angle)), .double(Double(distance)),
                                              .double(Double(x)), .double(Double(y))]
                func answer(_ event: String, _ fallback: CGFloat) -> CGFloat {
                    guard let value = call(object: object, event: event, arguments: arguments) else {
                        return fallback
                    }
                    let result = CGFloat(value.doubleValue)
                    return result.isFinite ? result : fallback
                }
                let first = hasFirst ? answer(events.0, state.rect ? x : angle) : (state.rect ? x : angle)
                if Self.tracesLayerFX, row == 0, column == 0 {
                    print(String(format: "FX-TRACE mesh %@ in=%.4f out=%.4f",
                                 object.xmlID ?? "-", Double(state.rect ? x : angle), Double(first)))
                }
                let second = hasSecond ? answer(events.1, state.rect ? y : distance) : (state.rect ? y : distance)
                sources[row * columns + column] = state.rect
                    ? CGPoint(x: first, y: second)
                    : WasabiLayerFXCoordinates.point(angle: first, distance: second)
            }
        }
        return WasabiLayerFXMesh(columns: columns, rows: rows, sources: sources,
                                 wrap: state.wrap, bilinear: state.bilinear)
    }

    /// One `fx_*` call. Every setter writes state and, where it changes what is drawn, invalidates the
    /// layer's mesh and asks for a repaint; the getters answer from the same state.
    private func invokeLayerFX(method: String, object: WasabiObject,
                               arguments: [MakiValue]) -> MakiValue {
        var state = layerFXStates[object.stableID] ?? WasabiLayerFXState()
        let flag = arguments.first?.truthy ?? false
        if Self.tracesLayerFX {
            print("FX-TRACE \(method) on \(object.typeName)#\(object.xmlID ?? "-") "
                  + "args=\(arguments.map(\.stringValue))")
        }
        switch method {
        case "fx_setenabled": state.enabled = flag
        case "fx_setwrap": state.wrap = flag
        case "fx_setrect": state.rect = flag
        case "fx_setbgfx": state.backgroundFX = flag
        case "fx_setclear": state.clear = flag
        case "fx_setrealtime": state.realtime = flag
        case "fx_setlocalized": state.localized = flag
        case "fx_setbilinear": state.bilinear = flag
        case "fx_setalphamode": state.alphaMode = flag
        case "fx_setspeed": state.speedMilliseconds = arguments.first?.integerValue ?? 0
        case "fx_setgridsize":
            state.gridX = max(1, Int(arguments.first?.integerValue ?? 1))
            state.gridY = max(1, Int(arguments.count > 1 ? arguments[1].integerValue : 1))
        case "fx_getenabled": return .boolean(state.enabled)
        case "fx_getwrap": return .boolean(state.wrap)
        case "fx_getrect": return .boolean(state.rect)
        case "fx_getbgfx": return .boolean(state.backgroundFX)
        case "fx_getclear": return .boolean(state.clear)
        case "fx_getrealtime": return .boolean(state.realtime)
        case "fx_getlocalized": return .boolean(state.localized)
        case "fx_getbilinear": return .boolean(state.bilinear)
        case "fx_getalphamode": return .boolean(state.alphaMode)
        case "fx_getspeed": return .integer(state.speedMilliseconds)
        case "fx_update", "fx_restart":
            // The skin has changed whatever its callbacks read (a needle's angle) and is telling the
            // host to re-run them. This is the repaint that moves the meter.
            layerFXStates[object.stableID] = state
            layerFXNeedsEvaluation.insert(object.stableID)
            requestRepaint(for: object)
            return .null
        default: return .null
        }
        layerFXStates[object.stableID] = state
        layerFXNeedsEvaluation.insert(object.stableID)
        requestRepaint(for: object)
        return .null
    }

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
    ]

    func signature(for method: String, classGUID: String?) -> MakiMethodSignature? {
        if method.caseInsensitiveCompare("getcontainer") == .orderedSame,
           classGUID.map(Self.canonicalGUID) == "60906d4e482e537e94cc04b072568861" {
            return .init(argumentCount: 0, returnKind: .object)
        }
        // A program compiled without a class table (the pre-5.0 MAKI layout) carries no GUID here, so
        // it does not reach this. None of the measured corpus's PlEdit callers are in that form.
        if classGUID.map(Self.canonicalGUID) == MakiClassGUID.playlistEditor,
           let signature = Self.playlistEditorSignatures[method.lowercased()] {
            return signature
        }
        // The colour-theme pair, both gated by their **declaring** class — which is what the
        // interpreter passes here, and the reason `apply` can be given an arity at all. Registering
        // either name globally would hand its arity to every class that happens to declare the same
        // verb, and a wrong argument count is the one error the interpreter cannot recover from: it
        // leaves values on the stack and desynchronises everything after the call. See
        // `reference/scripting.md` → *`PlEdit`*, which records that failure mode.
        switch classGUID.map(Self.canonicalGUID) {
        case MakiClassGUID.colorManager where method.caseInsensitiveCompare("getgammaset") == .orderedSame:
            return .init(argumentCount: 1, returnKind: .object)
        case MakiClassGUID.gammaSet where method.caseInsensitiveCompare("apply") == .orderedSame:
            return .init(argumentCount: 0, returnKind: .null)
        default:
            break
        }
        let signatures: [String: MakiMethodSignature] = [
            "getcontainer": .init(argumentCount: 1, returnKind: .object),
            "newdynamiccontainer": .init(argumentCount: 1, returnKind: .object),
            "getlayout": .init(argumentCount: 1, returnKind: .object),
            "getobject": .init(argumentCount: 1, returnKind: .object),
            "findobject": .init(argumentCount: 1, returnKind: .object),
            "getscriptgroup": .init(argumentCount: 0, returnKind: .object),
            "getparam": .init(argumentCount: 0, returnKind: .string),
            "gettoken": .init(argumentCount: 3, returnKind: .string),
            "getid": .init(argumentCount: 0, returnKind: .string),
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
            "setspeed": .init(argumentCount: 1, returnKind: .null),
            // Part of the same four-call preamble every skin writes before `play()`, and the one that
            // was missing: Big Bento Modern's `animbutton` sets start, end, **autoreplay** and speed
            // in that order, so a missing signature here abandoned the whole handler at the third
            // call — the play/pause morph never ran and the buttons were never swapped.
            "setautoreplay": .init(argumentCount: 1, returnKind: .null),
            "isplaying": .init(argumentCount: 0, returnKind: .boolean),
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
            "atan": .init(argumentCount: 1, returnKind: .float),
            "geteq": .init(argumentCount: 0, returnKind: .integer),
            "geteqband": .init(argumentCount: 1, returnKind: .integer),
            "seteqband": .init(argumentCount: 2, returnKind: .null),
            "geteqpreamp": .init(argumentCount: 0, returnKind: .integer),
            "seteqpreamp": .init(argumentCount: 1, returnKind: .null),
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
            "setdata": .init(argumentCount: 1, returnKind: .null),
            "ondatachanged": .init(argumentCount: 0, returnKind: .null),
            "setdelay": .init(argumentCount: 1, returnKind: .null),
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
            "getcurappleft": .init(argumentCount: 0, returnKind: .integer),
            "getcurapptop": .init(argumentCount: 0, returnKind: .integer),
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
            "getdatedoy": .init(argumentCount: 1, returnKind: .integer),
            "getdateyear": .init(argumentCount: 1, returnKind: .integer),
            // ClassicPro `ClassicProFile` shell service (the entire native surface, P0B §1).
            // `XmlDoc`: load an optional config document. Bounded — see `DynamicRole.xmlDocument`.
            "load": .init(argumentCount: 1, returnKind: .null),
            "exists": .init(argumentCount: 0, returnKind: .boolean),
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
            "explorefile": .init(argumentCount: 1, returnKind: .null),
            "openfile": .init(argumentCount: 2, returnKind: .null),
            "findfiles": .init(argumentCount: 3, returnKind: .integer),
        ]
        let name = method.lowercased()
        if let signature = signatures[name] { return signature }
        // A script may call one of its own event handlers directly to reuse it — MMD3 runs its
        // crossfade slider's handler once at load with `slidercb.onSetPosition(slidercb.getPosition())`.
        // Without an arity the interpreter cannot unwind the stack, so only events with a known
        // signature are callable; the call dispatches the event exactly as the UI would.
        if let arity = Self.dispatchableEventArity[name] {
            // `onAction` answers with an int (the drawer keeps the slot the widget manager gives it);
            // the rest are void.
            return .init(argumentCount: arity, returnKind: name == "onaction" ? .integer : .null)
        }
        // Record the miss here as well as in `unsupported(_:program:)`: the interpreter fails closed
        // on a missing *signature* (without an arity it cannot unwind the stack), so this is the path
        // most unimplemented methods actually take. Phase 7.3's tally never saw it.
        unsupportedMethodCalls[name, default: 0] += 1
        return nil
    }

    func invoke(method: String, on reference: MakiObjectReference, arguments: [MakiValue],
                program: MakiProgram) throws -> MakiValue {
        let method = method.lowercased()
        if Self.tracesEveryCall {
            let result = try invokeTraced(method: method, on: reference, arguments: arguments, program: program)
            // The **receiver**, not just the call: "who was this written to" is the question a
            // geometry or visibility trace is always really asking, and a bare
            // `setxmlparam(x,70)` cannot answer it.
            var receiver = ""
            if case .gui(let objectID) = reference.kind,
               let object = loadedSkin.runtime.graph.object(withID: objectID) {
                receiver = " on \(object.typeName)#\(object.xmlID ?? "-")"
            }
            print("CALL-TRACE \(method)(\(arguments.map(\.stringValue).joined(separator: ",")))"
                  + "\(receiver) -> \(result.stringValue)")
            return result
        }
        return try invokeTraced(method: method, on: reference, arguments: arguments, program: program)
    }

    static let tracesEveryCall = ProcessInfo.processInfo.environment["WINAMP_MODERN_CALL_TRACE"] != nil

    private func invokeTraced(method: String, on reference: MakiObjectReference, arguments: [MakiValue],
                              program: MakiProgram) throws -> MakiValue {
        switch reference.kind {
        case .system:
            return try invokeSystem(method: method, arguments: arguments, program: program)
        case .playlistEditor:
            return invokePlaylistEditor(method: method, arguments: arguments)
        case .colorManager:
            return try invokeColorManager(method: method, arguments: arguments, program: program)
        case .gui(let objectID):
            guard let object = loadedSkin.runtime.graph.object(withID: objectID) else { return .null }
            return try invokeGUI(method: method, object: object, arguments: arguments, program: program)
        case .popupMenu(let id):
            return invokePopup(method: method, id: id, arguments: arguments)
        case .dynamic(let id):
            return try invokeDynamic(method: method, id: id, arguments: arguments, program: program)
        }
    }

    /// An object that was never found *is* invalid, which is the whole reason ClassicPro asks:
    /// `player.maki` guards `if (!bgLeftRead.isInvalid())` around elements a skin is free to remove,
    /// and answering `false` (the generic null-call result) would send it on to configure something
    /// that does not exist.
    func nullReceiverResult(for method: String) -> MakiValue {
        method.lowercased() == "isinvalid" ? .boolean(true) : .null
    }

    func releaseObject(_ reference: MakiObjectReference) {
        switch reference.kind {
        case .dynamic(let id):
            timers.cancel(id: id)
            dynamicObjects.removeValue(forKey: id)
        case .popupMenu(let id):
            popupCommands.removeValue(forKey: id)
        case .system, .playlistEditor, .colorManager, .gui:
            break // Not script-owned; a skin cannot delete the graph out from under the renderer.
        }
    }

    func makeObject(classGUID: String, program: MakiProgram) throws -> MakiObjectReference {
        let id = nextPopupID
        nextPopupID &+= 1
        if Self.canonicalGUID(classGUID) == "f4787af44ef7b2bb4be7fb9c8da8bea9" {
            popupCommands[id] = []
            return MakiObjectReference(.popupMenu(id))
        }
        dynamicObjects[id] = DynamicObjectState()
        return MakiObjectReference(.dynamic(id))
    }

    private func invokeSystem(method: String, arguments: [MakiValue], program: MakiProgram) throws -> MakiValue {
        // A script may call a *system* event handler as a method to reuse it, exactly as it may an
        // object's (`System.onEqFreqChanged(freqmode)` in ClassicPro's `eq.m`).
        if Self.dispatchableEventArity[method] != nil {
            _ = try dispatchSystem(event: method, arguments: arguments)
            return method == "onaction" ? .integer(0) : .null
        }
        switch method {
        case "getcontainer", "newdynamiccontainer":
            // Winamp's `newDynamicContainer` builds a *fresh instance* of a declared container so a
            // skin can have several of the same window. Every container the skin declares is already
            // instantiated here, and a script's next move is always to reach into the one it just
            // asked for (`newDynamicContainer("browserpro").getLayout("resultslayout")
            // .findObject("BrowserPro.list")`), so it is answered with that container. One instance
            // rather than N is a real limit — but refusing the method took Defix's *global* script
            // down in `onScriptLoaded`, along with the playlist window's, the mini browser's and the
            // notifier's, which is most of the skin for the sake of a duplicate window.
            return objectValue(findRoot(type: "container", xmlID: arguments[0].stringValue))
        case "getscriptgroup":
            return objectValue(program.ownerID.flatMap(loadedSkin.runtime.graph.object(withID:)))
        case "getparam": return .string(program.parameter ?? "")
        case "gettoken":
            let tokens = arguments[0].stringValue.components(separatedBy: arguments[1].stringValue)
            let index = Int(arguments[2].integerValue)
            return .string(tokens.indices.contains(index) ? tokens[index] : "")
        case "getleftvumeter", "getrightvumeter":
            let value = vuValue(left: method == "getleftvumeter")
            if Self.tracesLayerFX { print("FX-TRACE \(method) -> \(value)") }
            return .integer(value)
        case "getvisband":
            return .integer(visBand(channel: arguments[0].integerValue, band: arguments[1].integerValue))
        case "getvolume": return .integer(Int32((host.volume * 255).rounded()))
        case "setvolume":
            let level = max(0, min(255, arguments[0].integerValue))
            host.volume = Double(level) / 255
            // The change is what a skin listens for. Re-entrancy is bounded by the dispatch guard, so
            // a handler that sets the volume again cannot recurse.
            _ = try? dispatchSystem(event: "onvolumechanged", arguments: [.integer(level)])
            return .null
        case "play": host.play(); return .null
        case "pause": host.pause(); return .null
        case "stop": host.stop(); return .null
        case "seekto":
            host.seek(to: TimeInterval(arguments[0].integerValue))
            return .null
        case "getplayitemlength": return .integer(Int32(clamping: Int64(host.duration)))
        // The number of tracks in the queue, from the same snapshot `PE_Info` is built from, so a
        // skin that shows both cannot disagree with itself. Defix's playlist box reads it directly
        // (`Items: ` + `integerToString(getPlaylistLength())`) rather than parsing the status line —
        // and because the call sat *before* its `a3` write, the missing method aborted the whole
        // `onTimer` and took the readout with it.
        case "getplaylistlength":
            return .integer(Int32(clamping: Int64(playlistSnapshot.trackCount)))
        // The 0-based position of the playing entry — six of the seventeen skins ask for it, the most
        // demanded unimplemented method in the corpus. Winamp's own notifier shows it as
        // `getPlaylistIndex() + 1 + " of " + getPlaylistLength()`, which pins both the base and the
        // pairing. `-1` when nothing is playing, as `currentIndex` already means.
        case "getplaylistindex":
            return .integer(Int32(clamping: Int64(playlistSnapshot.currentIndex)))
        case "getposition":
            // Same unit as `getPlayItemLength` and `seekTo` — seconds. The engine's scripts only ever
            // use the two together as a ratio (`SC-ProgressGrid` scales its grid by
            // `getPosition()/getPlayItemLength()`), so the unit must match, and `integerToTime`
            // is applied to the length elsewhere, which pins both to seconds.
            return .integer(Int32(clamping: Int64(host.currentTime)))
        case "integertostring": return .string(String(arguments[0].integerValue))
        case "integertotime":
            let seconds = max(0, Int(arguments[0].integerValue))
            return .string(String(format: "%d:%02d", seconds / 60, seconds % 60))
        case "floattostring":
            let digits = max(0, min(12, Int(arguments[1].integerValue)))
            return .string(String(format: "%.*f", digits, arguments[0].doubleValue))
        case "stringtointeger": return .integer(Int32(arguments[0].stringValue) ?? 0)
        // The mirror of `floattostring`, and the last method Love is War Miku's notifier preferences
        // reached for. A string that is not a number is 0, as it is on the integer side.
        case "stringtofloat": return .float(Double(arguments[0].stringValue) ?? 0)
        case "integer": return .integer(arguments[0].integerValue)
        case "float": return .float(arguments[0].doubleValue)
        case "string": return .string(arguments[0].stringValue)
        case "boolean": return .boolean(arguments[0].truthy)
        case "strlen": return .integer(Int32(clamping: arguments[0].stringValue.count))
        case "strlower": return .string(arguments[0].stringValue.lowercased())
        case "strupper": return .string(arguments[0].stringValue.uppercased())
        // RFC 3986 unreserved set, everything else escaped. Deliberately stricter than
        // `.urlQueryAllowed`: the argument is one *term* being pasted into a query a skin is
        // assembling, so a `&`, a `?` or a `#` in an album title must not survive as syntax.
        case "urlencode":
            return .string(arguments[0].stringValue
                .addingPercentEncoding(withAllowedCharacters: Self.urlUnreserved) ?? "")
        case "strsearch":
            let range = arguments[0].stringValue.range(of: arguments[1].stringValue)
            return .integer(range.map { Int32(arguments[0].stringValue.distance(from: arguments[0].stringValue.startIndex, to: $0.lowerBound)) } ?? -1)
        case "strleft":
            return .string(String(arguments[0].stringValue.prefix(max(0, Int(arguments[1].integerValue)))))
        case "strright":
            return .string(String(arguments[0].stringValue.suffix(max(0, Int(arguments[1].integerValue)))))
        case "strmid":
            let value = arguments[0].stringValue
            let start = max(0, min(value.count, Int(arguments[1].integerValue)))
            let count = max(0, Int(arguments[2].integerValue))
            let lower = value.index(value.startIndex, offsetBy: start)
            return .string(String(value[lower...].prefix(count)))
        case "getextension":
            // Windows separators as well as POSIX ones: a skin reads these out of playlist entries
            // and Winamp's own paths, and a dot in a *directory* name is not an extension.
            let name = arguments[0].stringValue
                .split(whereSeparator: { $0 == "/" || $0 == "\\" }).last.map(String.init) ?? ""
            guard let dot = name.lastIndex(of: "."), dot != name.startIndex else { return .string("") }
            return .string(String(name[name.index(after: dot)...]))
        case "getpath":
            // The other half of the same split, and the same two separators. The trailing one is
            // dropped, as Winamp drops it: `getPath("C:\Music\a.mp3")` is `C:\Music`. A bare name
            // with no separator at all has no directory, and answers empty.
            let value = arguments[0].stringValue
            guard let separator = value.lastIndex(where: { $0 == "/" || $0 == "\\" }) else {
                return .string("")
            }
            return .string(String(value[value.startIndex..<separator]))
        case "removepath":
            let value = arguments[0].stringValue
            guard let separator = value.lastIndex(where: { $0 == "/" || $0 == "\\" }) else {
                return .string(value)
            }
            return .string(String(value[value.index(after: separator)...]))
        case "translate": return .string(arguments[0].stringValue)
        case "getprivateint":
            return .integer(loadedSkin.configuration.integer(section: arguments[0].stringValue,
                                                              key: arguments[1].stringValue,
                                                              default: arguments[2].integerValue))
        case "setprivateint":
            loadedSkin.configuration.setInteger(arguments[2].integerValue,
                                                section: arguments[0].stringValue,
                                                key: arguments[1].stringValue)
            return .null
        case "getprivatestring":
            return .string(loadedSkin.configuration.string(section: arguments[0].stringValue,
                                                           key: arguments[1].stringValue,
                                                           default: arguments[2].stringValue))
        case "setprivatestring":
            loadedSkin.configuration.setString(arguments[2].stringValue,
                                               section: arguments[0].stringValue,
                                               key: arguments[1].stringValue)
            return .null
        case "getitem":
            return dynamicValue(role: .configItem(section: arguments[0].stringValue))
        case "getitembyguid":
            // Winamp's config is addressed either by display name or by the owning component's GUID.
            // Both name the same private store here, so the GUID is simply the section key —
            // `loadattribs.maki` and `playlistmenu.maki` reach every attribute they need this way.
            return dynamicValue(role: .configItem(section: arguments[0].stringValue))
        case "newitem":
            let name = arguments[0].stringValue
            let section = arguments[1].stringValue.isEmpty ? name : arguments[1].stringValue
            // The item's own name is the only human-readable label its attributes ever get: the
            // attribute names are the values ("Audio cassette"), the item is the setting
            // ("Visualizer"). Losing it would leave a settings list grouped by raw GUID.
            if !name.isEmpty, configItemNames[section] == nil,
               configItemNames.count < Self.maximumRegisteredSettings {
                configItemNames[section] = name
            }
            return dynamicValue(role: .configItem(section: section))
        // A skin's trace output. Deliberately dropped rather than logged: it is per-frame in some
        // skins, and nothing in NullPlayer consumes it.
        case "debugstring": return .null
        case "getviewportwidth": return .integer(Int32(NSScreen.main?.frame.width ?? 0))
        case "getviewportheight": return .integer(Int32(NSScreen.main?.frame.height ?? 0))
        case "getviewportleft", "getviewporttop", "getviewportleftfromguiobject", "getviewporttopfromguiobject":
            return .integer(0)
        case "getviewportwidthfromguiobject": return .integer(Int32(NSScreen.main?.frame.width ?? 0))
        case "getviewportheightfromguiobject": return .integer(Int32(NSScreen.main?.frame.height ?? 0))
        // The monitor is the whole display; the viewport above is the area a window may use. macOS
        // states them as `frame` and `visibleFrame`, and the only reason the viewport does not use the
        // latter here is that every skin in the corpus was measured against the value it already
        // answers. `left`/`top` are the display's own origin, which for the single-screen case every
        // skin assumes is 0 — a skin reads them to keep a notifier inside the screen it is on.
        case "getmonitorwidth": return .integer(Int32(NSScreen.main?.frame.width ?? 0))
        case "getmonitorheight": return .integer(Int32(NSScreen.main?.frame.height ?? 0))
        case "getmonitorleft", "getmonitortop": return .integer(0)
        case "getcurappleft": return .integer(Int32(NSApp.mainWindow?.frame.minX ?? 0))
        case "getcurapptop": return .integer(Int32(NSApp.mainWindow?.frame.minY ?? 0))
        case "getmouseposx": return .integer(Int32(clamping: Int((mousePositionRequested?().x ?? 0).rounded())))
        case "getmouseposy": return .integer(Int32(clamping: Int((mousePositionRequested?().y ?? 0).rounded())))
        case "atan": return .float(atan(arguments[0].doubleValue))
        // The rest of MAKI's math library. Every result is guarded against a domain error: a script
        // that asks for `sqrt(-1)` gets 0 rather than a NaN that would then travel into a coordinate
        // and take a whole layer off screen.
        case "sqrt", "pow", "sin", "cos", "tan", "asin", "acos", "atan2", "log", "log10", "exp", "abs":
            let x = arguments[0].doubleValue
            let y = arguments.count > 1 ? arguments[1].doubleValue : 0
            let result: Double
            switch method {
            case "sqrt": result = x < 0 ? 0 : sqrt(x)
            case "pow": result = pow(x, y)
            case "sin": result = sin(x)
            case "cos": result = cos(x)
            case "tan": result = tan(x)
            case "asin": result = asin(min(1, max(-1, x)))
            case "acos": result = acos(min(1, max(-1, x)))
            case "atan2": result = atan2(x, y)
            case "log": result = x > 0 ? log(x) : 0
            case "log10": result = x > 0 ? log10(x) : 0
            case "exp": result = exp(x)
            default: result = abs(x)
            }
            return .double(result.isFinite ? result : 0)
        case "geteq": return .integer((equalizerEnabledRequested?() ?? false) ? 1 : 0)
        case "geteqband":
            return .integer(Int32(clamping: equalizerBandRequested?(Int(arguments[0].integerValue)) ?? 0))
        case "seteqband":
            equalizerBandSetterRequested?(Int(arguments[0].integerValue), Int(arguments[1].integerValue))
            // The change is what a skin listens for, exactly as `setVolume` announces itself. The
            // funnel dispatches only on a real change, so a handler that writes the band it was just
            // told about stops there rather than recursing.
            refreshEqualizerState()
            return .null
        // The preamp is the band before band 0, on the same −127…127 scale. Rika's `eq.xml` reads it
        // while wiring its own equalizer window, and the miss aborted that whole script.
        case "geteqpreamp":
            return .integer(Int32(clamping: equalizerPreampRequested?() ?? 0))
        case "seteqpreamp":
            equalizerPreampSetterRequested?(Int(arguments[0].integerValue))
            refreshEqualizerState()
            return .null
        case "getruntimeversion": return .integer(5)
        case "getskinname": return .string(preferenceNamespace)
        // The player's own settings directory. Winamp answers its install/profile folder and skins
        // build sibling paths from it to sniff for another player's files — Big Bento Modern probes
        // `<settings>/WACUP_Tools/koopa.ini` to decide whether it is running under WACUP. Answering
        // NullPlayer's Application Support folder is the honest reply: the probe misses, the skin
        // takes its "not WACUP" branch, and the handler runs to the end. `File.exists()` is a
        // sandboxed `false` regardless, so nothing here widens what a script can read.
        case "getsettingspath":
            return .string(WinampModernSkinImporter.defaultDestinationDirectory()
                .deletingLastPathComponent().path)
        // The directory the player itself sits in, which is what Winamp answers. Handing back a
        // string is not filesystem access and does not become any: every route a skin has from here
        // is already sandboxed — `File.load`/`exists` are a no-op and a constant `false`,
        // `System.navigateUrl` is inert, and `openFile`/`exploreFile` take an arbitrary skin-authored
        // string anyway. What the callers are actually doing is probing for Winamp's own `/Lang`
        // packs and its plugin folder; those probes correctly find nothing here, and the branch the
        // skin takes on that is the truthful one.
        case "getapplicationpath": return .string(Bundle.main.bundleURL.deletingLastPathComponent().path)
        case "getcolortheme": return .string(activeThemeRequested?() ?? "Default")
        case "setcolortheme":
            _ = themeSwitchRequested?(arguments[0].stringValue)
            return .null
        case "getnumcolorthemes": return .integer(Int32(clamping: themeNamesRequested?().count ?? 0))
        case "enumcolorthemes":
            let themes = themeNamesRequested?() ?? []
            let index = Int(arguments[0].integerValue)
            return .string(themes.indices.contains(index) ? themes[index] : "")
        case "gettimeofday": return .integer(Int32(truncatingIfNeeded: Int64(Date().timeIntervalSince1970 * 1000)))
        case "getplayitemdisplaytitle": return .string(host.trackDisplayTitle)
        case "getplayitemstring": return .string(host.trackDisplayTitle)
        // The whole key table lives on the host (`playItemMetadata(forKey:)`) rather than here: a
        // file-info panel asks for eighteen different fields and hides the line for every key that
        // comes back empty, and the harness has to answer them the same way the live host does.
        case "getplayitemmetadatastring":
            return .string(host.playItemMetadata(forKey: arguments[0].stringValue))
        case "getstatus":
            switch host.playbackState {
            case .playing: return .integer(1)
            case .paused: return .integer(-1)
            case .stopped: return .integer(0)
            }
        case "getsonginfotext": return .string(host.songInfoText)
        // The argument names an item, but every call site in the corpus passes the *current* one, and
        // the host only knows what it is decoding now — so the answer is about the playing track.
        case "getdecodername": return .string(host.decoderName)
        case "isvideo", "isvideofullscreen", "iskeydown", "isminimized", "isnamedwindowvisible":
            return .boolean(false)
        // Not in the group above on purpose — see the signature. Under the headless harness there is
        // no `NSApplication` at all, and "the app the skin is running in is in front" is then the
        // honest answer: the alternative reports every probe run as a background app and takes the
        // focus-gated half of a skin's behaviour out of measurement.
        case "isappactive": return .boolean(NSApp?.isActive ?? true)
        case "istransparencyavailable", "istransparencysafe", "islayoutanimationsafe":
            return .boolean(true)
        // **False, unlike the three above.** Desktop alpha is not "can this window be translucent" —
        // it is Winamp asking whether it may run the container on its `desktopalpha="1"` *layout*,
        // which is a second layout built from a second set of artwork. A skin asks once and then
        // addresses that layout for the rest of the session without ever switching to it, because in
        // Winamp the container is already on it. Nothing here activates it, so answering true sent
        // every write to a layout no window shows: Big Bento's notifier laid out `desktopalpha`
        // perfectly — sized to its text, album art in, transport row placed — while the app went on
        // drawing the untouched `normal` layout underneath (BB27). Answer it the way the engine
        // actually behaves and the skin lays out the layout that is on screen.
        case "isdesktopalphaavailable":
            return .boolean(false)
        // No video *component*: a `.wal` video holder gets the neutral backing every unhosted kind
        // gets, so a skin that asks is told the truth and lays itself out without a video tab. Defix
        // asks in the same `onScriptLoaded` that positions its whole tab strip — while the question
        // was refused, the strip was never laid out and its Album Art and Video tabs sat on top of
        // each other at the x both are declared at.
        case "hasvideosupport": return .boolean(false)
        case "getidealvideowidth", "getidealvideoheight": return .integer(0)
        case "lockui", "unlockui", "hidenamedwindow": return .null
        // Winamp's two global navigations, and they are not synonyms: `navigateUrl` means the user's
        // default browser and `navigateUrlBrowser` the player's own. Neither opens anything from
        // here — the request carries a skin-authored string, so it is handed to the window layer,
        // which resolves it through `WinampModernWebNavigationPolicy` (HTTP/HTTPS with a real host,
        // nothing else) and asks the user before the external one leaves the app (B40).
        case "navigateurl":
            globalNavigationRequested?(.defaultBrowser, arguments[0].stringValue)
            return .null
        case "navigateurlbrowser":
            globalNavigationRequested?(.internalBrowser, arguments[0].stringValue)
            return .null
        case "newgroup":
            // Wasabi creates the group as a child of the calling script's own group; the script then
            // positions it with `setXmlParam`. This is how Winamp Modern fills a window frame's
            // client area (`content=` → `newGroup` → the whole player UI).
            guard let owner = program.ownerID.flatMap(loadedSkin.runtime.graph.object(withID:)),
                  let instantiate = loadedSkin.runtime.instantiateGroup else { return .null }
            let created = try instantiate(arguments[0].stringValue, owner)
            // The subtree's scripts start on **attachment**, not here: `newGroup` is only the first half
            // of Wasabi's two-step, and a script that runs before its group has been `init`'d into place
            // reads the wrong parent. See `pendingRuntimeGroups`.
            pendingRuntimeGroups.append(created)
            notifyGraphDidMutate()
            return objectValue(created)
        // The same instantiation, but for a groupdef that declares itself a floating window
        // (`owner="main,normal"` + `nodock="1"`): Winamp gives it a borderless layout of its own,
        // owned by that layout. We make it an **overlay child of the owner layout** instead, and the
        // coordinate maths says that is the right answer rather than a compromise — multipass
        // positions the result with `resize(layoutMainNormal.getLeft() + 54, …getTop() + 217, …)`,
        // and `getLeft()`/`getTop()` on a root layout answer 0 here (window-local; see the
        // `clientToScreenX` note), so it lands at (54, 217) — exactly where the author's own
        // commented-out `<group … x="9" y="62"/>` inside drawer.bottom (45,155) → colorthemes (0,0)
        // would have put it.
        //
        // The created object keeps its **group** type. Typing it `layout` would send the `resize`
        // above through `layoutResizeRequested` and resize the *window* to 164×78.
        case "newgroupaslayout":
            guard let instantiate = loadedSkin.runtime.instantiateGroup,
                  let parent = ownerLayout(forGroupDefinition: arguments[0].stringValue, program: program)
            else { return .null }
            // Appended last, so it draws over the drawer background it sits on rather than under it.
            let floated = try instantiate(arguments[0].stringValue, parent)
            pendingRuntimeGroups.append(floated)
            notifyGraphDidMutate()
            return objectValue(floated)
        case "messagebox": return .integer(0) // Sandboxed: skins cannot create modal host UI.
        // ClassicPro version gate + public config (see `reportedWinampBuild`).
        case "getbuildnumber": return .integer(Self.reportedWinampBuild)
        case "getwinampversion": return .string(Self.reportedWinampVersion)
        case "getpublicint":
            return .integer(loadedSkin.configuration.integer(section: "@public",
                                                             key: arguments[0].stringValue,
                                                             default: arguments[1].integerValue))
        case "getpublicstring":
            return .string(loadedSkin.configuration.string(section: "@public",
                                                           key: arguments[0].stringValue,
                                                           default: arguments[1].stringValue))
        case "setpublicstring":
            loadedSkin.configuration.setString(arguments[1].stringValue,
                                               section: "@public", key: arguments[0].stringValue)
            return .null
        case "switchskin":
            // A skin asking the player to load a *different* skin is a host decision, not a script's.
            // The one caller here is ClassicPro's "the plugin is not installed" bail-out, which this
            // runtime does not reach: the engine is mounted or the skin does not load at all.
            return .null
        case "setpublicint":
            loadedSkin.configuration.setInteger(arguments[1].integerValue,
                                                section: "@public", key: arguments[0].stringValue)
            return .null
        case "getdate": return .integer(Int32(truncatingIfNeeded: Int64(Date().timeIntervalSince1970)))
        case "getdatedoy":
            return .integer(Int32(Calendar.current.ordinality(of: .day, in: .year, for: Date()) ?? 0))
        case "getfilesize":
            // Bounded no-op, for the same reason `findFiles` is one: a script that can stat any path
            // it names has a filesystem-probe capability, which this runtime does not grant. The
            // file-info readout shows 0 bytes rather than the script that draws it aborting.
            return .integer(0)
        case "getlanguageid": return .string("en")
        case "getgroup":
            // One section of Winamp's preferences, keyed by GUID. Backed by the skin's own namespaced
            // configuration store — MAKI never reads or writes real Winamp settings.
            return dynamicValue(role: .configGroup(section: arguments[0].stringValue))
        // Stars, 0–5 — Winamp's unit, and the one NullPlayer's own star rows already use. The host
        // reads a local file's rating straight out of the library and asks the server for anything
        // else, announcing the late answer through `onCurrentTrackRated`.
        case "getcurrenttrackrating":
            return .integer(Int32(clamping: host.currentTrackRating))
        case "setcurrenttrackrating":
            host.currentTrackRating = Int(arguments[0].integerValue)
            return .null
        case "getdateyear":
            // Years since 1900, as C's `tm_year`. Pinned by the engine's own use of it: `cproabout.m`
            // computes an age as `1899 + getDateYear(...) - birthYear` (+1 once the birthday has
            // passed) and leap-year-tests it with `% 4`, both of which are only correct on that scale.
            let date = arguments[0].integerValue > 0
                ? Date(timeIntervalSince1970: TimeInterval(arguments[0].integerValue)) : Date()
            return .integer(Int32(Calendar.current.component(.year, from: date) - 1900))
        default:
            if let value = classicProFileMethod(method, arguments: arguments) { return value }
            throw unsupported(method, program: program)
        }
    }

    /// The complete native surface ClassicPro's MAKI invokes (P0B §1): three `ClassicProFile`
    /// filesystem-shell helpers, each routed through the host's intentional reveal/open policy or a
    /// bounded no-op. Returns `nil` when `method` is not one of them.
    private func classicProFileMethod(_ method: String, arguments: [MakiValue]) -> MakiValue? {
        switch method {
        case "explorefile":
            host.revealInFinder(arguments[0].stringValue)
            return .null
        case "openfile":
            host.openExternally(arguments[0].stringValue)
            return .null
        case "findfiles":
            // Bounded no-op: report "unavailable" so callers take their early-return path rather than
            // enumerating results. Skins never gain a filesystem-search capability.
            return .integer(-1)
        default:
            return nil
        }
    }

    // MARK: - ColorMgr (the colour-theme manager)

    /// `ColorMgr`, Winamp's colour-theme manager. The whole surface the corpus reaches is one
    /// method: `getGammaSet(name)` hands back the named theme, and `apply()` on that switches to it.
    ///
    /// The theme itself is not built here. `WasabiColorThemeCatalog` already holds every `<gammaset>`
    /// the skin declared and tracks the active one, and `System.setColorTheme` already routes a
    /// switch through `themeSwitchRequested` — so this is a *binding* job, not a rendering one, and
    /// it deliberately lands on the same route rather than a second one that could disagree with it.
    ///
    /// A name the skin does not ship is answered with the object anyway, and `apply()` on it is a
    /// no-op: the catalog rejects the switch. Refusing here instead would abort the caller's whole
    /// handler over one missing theme.
    /// **Unknown methods fall through to `System`, and that is not a convenience — it is what keeps
    /// this change from being a regression.** Before `ColorMgr` was bound, the parser seeded a global
    /// of this class with the *System* object, so every call a skin made on it went to
    /// `invokeSystem`. Winamp declares `getColorTheme` / `setColorTheme` / `getNumColorThemes` /
    /// `enumColorThemes` on `ColorMgr` as well, and this runtime answers all four on `System` — so
    /// handling `getGammaSet` alone and returning null for the rest would silently take those four
    /// away from any skin that reaches them through its `ColorMgr` global. Binding a singleton must
    /// only ever *add* to what its receiver could already do.
    private func invokeColorManager(method: String, arguments: [MakiValue],
                                    program: MakiProgram) throws -> MakiValue {
        switch method {
        case "getgammaset":
            return dynamicValue(role: .gammaSet(name: arguments[0].stringValue))
        default:
            return try invokeSystem(method: method, arguments: arguments, program: program)
        }
    }

    // MARK: - PlEdit (the playlist editor)

    /// What every playlist read answers from. The component host is the live queue; the text
    /// provider is the same snapshot under the headless harness, so a probe run and the app agree.
    private var playlistSnapshot: WinampModernPlaylistSnapshot {
        componentHost?.playlistSnapshot() ?? WasabiTextMetrics.componentTextProvider?() ?? .empty
    }

    /// `PlEdit`, Winamp's playlist-editor singleton. Every index here is **0-based** and absolute in
    /// the queue; an out-of-range one answers empty or does nothing rather than failing, because a
    /// skin polls this from a timer while the queue is being edited underneath it.
    private func invokePlaylistEditor(method: String, arguments: [MakiValue]) -> MakiValue {
        let snapshot = playlistSnapshot
        func row(_ index: Int) -> WinampModernPlaylistRow? {
            snapshot.rows.indices.contains(index) ? snapshot.rows[index] : nil
        }
        switch method {
        case "getcurrentindex": return .integer(Int32(clamping: Int64(snapshot.currentIndex)))
        case "getnumtracks": return .integer(Int32(clamping: Int64(snapshot.trackCount)))
        // The entry's display title — the same string the skin's own playlist draws, so a script that
        // builds a menu from it (ClassicPro's Quick Playlist) cannot disagree with the list beside it.
        case "gettitle": return .string(row(Int(arguments[0].integerValue))?.title ?? "")
        // A *string*, not a number: ClassicPro tests it against `""` before appending it in brackets,
        // and writes it straight into a text object. An unknown duration is empty, which is exactly
        // the case that test exists for.
        case "getlength":
            guard let entry = row(Int(arguments[0].integerValue)), entry.duration > 0 else { return .string("") }
            let seconds = Int(entry.duration)
            return .string(String(format: "%d:%02d", seconds / 60, seconds % 60))
        case "getfilename": return .string(row(Int(arguments[0].integerValue))?.filePath ?? "")
        case "getmetadata":
            guard let entry = row(Int(arguments[0].integerValue)) else { return .string("") }
            switch arguments[1].stringValue.lowercased() {
            case "title": return .string(entry.title)
            case "artist": return .string(entry.artist)
            case "album": return .string(entry.album)
            case "filename": return .string(entry.filePath)
            case "length": return .string(entry.duration > 0 ? String(Int(entry.duration)) : "")
            default: return .string("")
            }
        case "playtrack":
            componentHost?.playlistPlay(row: Int(arguments[0].integerValue))
            return .null
        case "removetrack":
            componentHost?.playlistRemove(row: Int(arguments[0].integerValue))
            return .null
        case "moveto":
            componentHost?.playlistMove(row: Int(arguments[0].integerValue),
                                        to: Int(arguments[1].integerValue))
            return .null
        case "clear":
            componentHost?.playlistClear()
            return .null
        case "showtrack":
            playlistRevealRowRequested?(Int(arguments[0].integerValue))
            return .null
        case "showcurrentlyplayingtrack":
            guard snapshot.currentIndex >= 0 else { return .null }
            playlistRevealRowRequested?(snapshot.currentIndex)
            return .null
        default:
            // Unreachable while `playlistEditorSignatures` and this switch stay in step; recorded
            // rather than silently null so a name added to one and not the other is visible.
            unsupportedMethodCalls[method, default: 0] += 1
            return .null
        }
    }

    private func invokeGUI(method: String, object: WasabiObject, arguments: [MakiValue],
                           program: MakiProgram) throws -> MakiValue {
        if method == "showcurrentlyplayingentry" {
            let index = playlistSnapshot.currentIndex
            if index >= 0 { playlistRevealRowRequested?(index) }
            return .null
        }
        if Self.dispatchableEventArity[method] != nil {
            _ = try dispatch(object: object, event: method, arguments: arguments)
            // No handler can answer through this path (the interpreter's return value belongs to the
            // handler's own frame), so `onAction` reports the neutral slot 0 rather than a fiction.
            return method == "onaction" ? .integer(0) : .null
        }
        switch method {
        case "getlayout":
            return objectValue(object.children.first {
                $0.typeName.caseInsensitiveCompare("layout") == .orderedSame &&
                $0.xmlID?.caseInsensitiveCompare(arguments[0].stringValue) == .orderedSame
            } ?? descendant(of: object, xmlID: arguments[0].stringValue))
        case "getobject":
            return objectValue(descendant(of: object, xmlID: arguments[0].stringValue))
        // `findObject` is the *wide* lookup and `getObject` the narrow one — Wasabi searches the
        // receiver's own subtree first and then the rest of the window, which is the whole reason a
        // skin reaches for one name over the other. Defix's core script holds `sui.content` and asks
        // it for `switch.ml`, a tab button that lives in `grid.s2`, a **sibling** subtree: answered
        // from descendants alone every one of the five tab lookups came back null, the script bound
        // its click handlers to nothing, and the SUI body never switched tabs however well the
        // buttons themselves lit up. The nearest match still wins, so a skin with the same id in
        // both places keeps getting its own.
        case "findobject":
            let wanted = arguments[0].stringValue
            if let near = descendant(of: object, xmlID: wanted) { return objectValue(near) }
            guard let root = ancestor(of: object, type: "container") else { return .null }
            return objectValue(descendant(of: root, xmlID: wanted))
        case "getcontainer": return objectValue(ancestor(of: object, type: "container"))
        case "getcurlayout":
            return objectValue(activeLayoutByContainer[object.stableID].flatMap(loadedSkin.runtime.graph.object(withID:)))
        case "switchtolayout":
            guard object.typeName.caseInsensitiveCompare("container") == .orderedSame,
                  let next = object.children.first(where: {
                      $0.typeName.caseInsensitiveCompare("layout") == .orderedSame &&
                      $0.xmlID?.caseInsensitiveCompare(arguments[0].stringValue) == .orderedSame
                  }) else { return .null }
            activeLayoutByContainer[object.stableID] = next.stableID
            _ = layoutSwitchRequested?(object.stableID, arguments[0].stringValue)
            _ = try dispatch(object: object, event: "onswitchtolayout", arguments: [objectValue(next)])
            return .null
        case "getnumchildren": return .integer(Int32(clamping: object.children.count))
        case "enumchildren":
            let index = Int(arguments[0].integerValue)
            guard object.children.indices.contains(index) else { return .null }
            return objectValue(object.children[index])
        // `GroupList.instantiate(groupdef, count)` — the *list's* own expansion, as against
        // `System.newGroup`. Big Bento Modern builds all nine of its config pages and the SUI's
        // equalizer tab this way: the page's XML holds an empty `<GroupList>` and a scrollbar, and
        // every option on it lives in a `…part1` / `…part2` groupdef the script expands here. That
        // is why the whole family reported `unsupported` although it drew.
        case "instantiate":
            guard let instantiate = loadedSkin.runtime.instantiateGroup else { return .null }
            let identifier = arguments[0].stringValue
            // The count is skin input, so it is bounded here as well as by the shared object budget
            // `instantiateGroupAtRuntime` counts against. Nothing measured asks for more than one.
            let count = min(max(Int(arguments[1].integerValue), 0), Self.maximumGroupListInstances)
            var instantiated: WasabiObject?
            for _ in 0..<count {
                let child = try instantiate(identifier, object)
                stackInGroupList(child, list: object)
                // The subtree's scripts start on attachment, exactly as `newGroup`'s do.
                pendingRuntimeGroups.append(child)
                instantiated = child
            }
            if instantiated != nil {
                noteGeometryChange()
                notifyGraphDidMutate()
            }
            return objectValue(instantiated)
        case "getid": return .string(object.xmlID ?? "")
        case "getparent": return objectValue(object.parent)
        case "getparentlayout": return objectValue(ancestor(of: object, type: "layout"))
        case "getxmlparam": return .string(object.attributes[arguments[0].stringValue.lowercased()] ?? "")
        case "setxmlparam":
            let key = arguments[0].stringValue
            let value = arguments[1].stringValue
            // An image-valued param is a *load*, and a load that fails leaves the object wearing the
            // artwork it already had — including when the new id is empty, which loads nothing.
            //
            // Defix names its background art from a stored preference and never seeds one:
            // `getPrivateString(getSkinName(), "BG", "")`. On a profile that has not opened its
            // configurator that is `""`, so the layout is asked for background `""` and every one of
            // the nine frame slices for `"" + "_background_material.Element.top.left"` — ids no skin
            // defines. Taking them literally threw away the wood panel the layout declares
            // (`background="BG1"`) and the frame around the player, both speakers, the playlist and
            // the library, leaving flat black boxes. The skin ships a screenshot of itself framed and
            // panelled, which is what Winamp shows for a set that never loaded.
            guard !Self.imageKeys.contains(key.lowercased()) || resolvesToResource(value)
            else { return .null }
            _ = object.setAttribute(key, value: value)
            if Self.geometryKeys.contains(key.lowercased()) {
                // A container or a layout is a *window*: its box is not read back out of the graph at
                // the next repaint, it has to be pushed to AppKit. `resize()` already did this; the
                // same four attributes written one at a time did not, which is how Big Bento's search
                // results came out at the container's declared 275×116 in the corner of the screen
                // instead of under the search box it measured itself against (BB31).
                applyContainerGeometry(object)
                noteGeometryChange()
                notifyGraphDidMutate()
            } else {
                notifyObjectDidMutate(object)
            }
            return .null
        case "settext":
            // Through the `embed_xui` link, exactly as `setPosition`/`getPosition` are: the wrapper
            // **is** the control and its text must not exist in two places. Big Bento's file-info
            // lines are the case that proves it — `<groupdef id="bento.infodisplay.line"
            // embed_xui="text" xuitag="Bento:InfoLine">` — where `fileinfo.maki` fills the inner
            // `<Text id="text">` while `fileinfo_lyrics_finder.maki` reads the *wrapper* with
            // `getText()` to build its search. Kept apart, the reader answered "" and the lyrics
            // button searched the web for the bare word "lyrics" (B40).
            let object = embeddedControl(of: object) ?? object
            _ = object.setAttribute("text", value: arguments[0].stringValue)
            // Written to its own key as well, because a non-empty value has to beat the object's
            // `display=` binding — see `WasabiTextMetrics.scriptTextKey`. Empty writes through as
            // empty, which is exactly the revert a skin means by `setText("")`.
            _ = object.setAttribute(WasabiTextMetrics.scriptTextKey, value: arguments[0].stringValue)
            // `setText` is also how a skin takes an alternate text back down: MMD3's ticker timer
            // fires `setText("")` a second after a `setAlternateText("VOLUME: 40%")` and expects the
            // song title back.
            _ = object.setAttribute(WasabiTextMetrics.scriptAlternateTextKey, value: "")
            notifyObjectDidMutate(object)
            return .null
        // What the object *shows*, not just the literal it was declared with. MMD3's songinfo timer
        // reads `getText()` off the `display="songinfo"` text and tokenises it for KBPS/KHZ; answering
        // with the (empty) `default=` attribute left both fields blank forever.
        // Read through the same `embed_xui` link `setText` writes through, above.
        case "gettext":
            return .string(WasabiTextMetrics.content(of: embeddedControl(of: object) ?? object,
                                                     host: host))
        case "getautowidth":
            return .integer(autoWidth(of: object))
        case "getautoheight":
            return .integer(autoHeight(of: object))
        case "gettextwidth":
            // Measured with the font the renderer draws with, and through the same content
            // resolution — a `display=` binding, a songticker's implicit title, `setAlternateText` —
            // so the answer is about the string on screen rather than the XML literal. Through the
            // `embed_xui` link for the same reason `getText` is: the wrapper draws nothing itself,
            // so measuring it measures an empty string.
            let measured = embeddedControl(of: object) ?? object
            return .integer(Int32(clamping: Int(metrics.width(
                of: measured, text: WasabiTextMetrics.content(of: measured, host: host)).rounded(.up))))
        case "getguid":
            return .string(object.attributes["guid"] ?? "")
        case "resize":
            for (key, value) in zip(["x", "y", "w", "h"], arguments) {
                _ = object.setAttribute(key, value: String(value.integerValue))
            }
            if object.typeName.caseInsensitiveCompare("layout") == .orderedSame,
               let container = ancestor(of: object, type: "container") {
                layoutResizeRequested?(container.stableID,
                                       CGSize(width: CGFloat(arguments[2].integerValue),
                                              height: CGFloat(arguments[3].integerValue)))
            }
            applyContainerGeometry(object)
            noteGeometryChange()
            notifyGraphDidMutate()
            return .null
        // `onSetVisible` fires only on an actual change, as in Wasabi. ClassicPro's `beat.m` hangs its
        // VU timer off `beatGroup.onSetVisible`, and `showGroup` hides both display groups before
        // showing one — notifying unconditionally would stop and restart the timer on every refresh.
        case "show": return try setVisible(object, true)
        case "hide": return try setVisible(object, false)
        // `toggle()` is `show`/`hide` with the direction read back first, and the direction has to
        // come from the **host's** window state rather than from the graph. Ujola Cat's two console
        // buttons carry no `action` at all — `getContainer("colorthemes").toggle()` is their entire
        // behaviour — and a window's visibility changes by four routes that never write the graph's
        // `visible` attribute (the Windows menu, a markup `TOGGLE`, this call, the window's own close
        // button), so an attribute-read toggle inverts after the first manual close.
        case "toggle": return try setVisible(object, !effectiveVisibility(of: object))
        case "isvisible": return .boolean(effectiveVisibility(of: object))
        case "isactive": return .boolean(isActive(object))
        case "setalpha":
            let clamped = max(0, min(255, arguments[0].integerValue))
            _ = object.setAttribute("alpha", value: String(clamped))
            notifyObjectDidMutate(object)
            if object.typeName.caseInsensitiveCompare("container") == .orderedSame,
               let id = object.xmlID {
                containerAlphaChanged?(id, CGFloat(clamped) / 255.0)
            }
            return .null
        case "getalpha": return .integer(Int32(object.attributes["alpha"] ?? "255") ?? 255)
        case "setenabled":
            _ = object.setAttribute("enabled", value: arguments[0].truthy ? "1" : "0")
            notifyObjectDidMutate(object)
            return .null
        case "setactivated":
            _ = object.setAttribute("activated", value: arguments[0].truthy ? "1" : "0")
            notifyObjectDidMutate(object)
            _ = try dispatch(object: object, event: "ontoggle", arguments: [.boolean(arguments[0].truthy)])
            notifyActivated(object, activated: arguments[0].truthy)
            return .null
        case "setactivatednocallback":
            _ = object.setAttribute("activated", value: arguments[0].truthy ? "1" : "0")
            notifyObjectDidMutate(object)
            return .null
        // For a `cfgattrib`-bound control the stored preference **is** the activation — the button
        // keeps no second copy, which is why `toggleActivation` refuses these. Answering from the
        // `activated` attribute instead reported every such button as off forever, and mmd3's whole
        // crossfade/shuffle/repeat indicator set is `alpha = 255 * getActivated()` at load.
        case "getactivated":
            if Self.configBinding(of: object) != nil { return .boolean(configValue(of: object)) }
            return .boolean(object.attributes["activated"] == "1")
        // The graph type, which is the XML tag the object was declared with (`layer`, `button`,
        // `togglebutton`, `slider`, …) — what a script comparing `strUpper(getClassName())` against
        // "LAYER" is asking for.
        case "getclassname": return .string(object.typeName)
        // A container closing itself is that window going away; anything else has no window and the
        // request stops in the graph, exactly as `hide()` does.
        case "close":
            _ = object.setAttribute("visible", value: "0")
            notifyGraphDidMutate()
            requestWindow(for: object, visible: false)
            return .null
        // Client ↔ screen conversion, relative to the receiver's **parent** client area — the space
        // `getLeft()`/`getTop()` already answer in, which is what every measured call site converts:
        // `b.clientToScreenX(b.getLeft())`, receiver and coordinate the same object. Reading it as the
        // receiver's *own* box instead double-counts that idiom, and reading it as pure identity loses
        // the parent chain, which is what put ClassicPro's tab menu at the window's left edge instead
        // of under its tab.
        //
        // "Screen" is this window's client space: a `.wal` window is borderless and positioned by us,
        // so the window origin is a constant that cancels in the round trip every caller makes, and
        // the popup presenter places `popAtXY` in the same window the point came from. Winamp Modern's
        // titlebar centres its title with `layout.clientToScreenX((w − titleW) / 2)`, converts back
        // through the titlebar group and subtracts that group's own `getLeft()`; both objects hang off
        // the layout, so the round trip returns the input and the correction lands.
        case "clienttoscreenx", "clienttoscreeny", "screentoclientx", "screentoclienty":
            let origin = resolvedGeometryRequested?(object)?.parent.origin ?? .zero
            let offset = method.hasSuffix("x") ? origin.x : origin.y
            let signed = method.hasPrefix("client") ? offset : -offset
            return .integer(Int32(clamping: Int(Double(arguments[0].integerValue) + Double(signed))))
        // Docking/snapping notifications a layout sends while resizing itself. NullPlayer places `.wal`
        // windows itself and has no docking model for them, so these are deliberate no-ops — but they
        // must *exist*, because a missing method aborts the whole handler: this trio is what stopped
        // Winamp Modern's CONFIG button from ever opening its drawer.
        case "beforeredock", "redock", "snapadjust": return .null
        case "debugstring": return .null
        // A **window's** left and top are where it sits on the desktop, not where it sits inside
        // itself. A layout resolves to the origin of its own canvas, so both answered 0 — and Big
        // Bento's playlist search reads them straight back to re-place its results popup
        // (`results.resize(results.getLeft(), results.getTop(), w, h)` after writing the screen
        // position it measured), which put the window at (0,0) and undid the placement (BB31).
        case "getleft", "getguix":
            if Self.isWindowObject(object), let x = Double(object.attributes["x"] ?? "") {
                return .integer(Int32(clamping: Int(x)))
            }
            return .integer(dimension(resolvedFrame(of: object)?.minX, declared: object.geometry.x))
        case "gettop", "getguiy":
            if Self.isWindowObject(object), let y = Double(object.attributes["y"] ?? "") {
                return .integer(Int32(clamping: Int(y)))
            }
            return .integer(dimension(resolvedFrame(of: object)?.minY, declared: object.geometry.y))
        case "getwidth", "getguiw":
            return .integer(dimension(resolvedFrame(of: object)?.width,
                                      declared: object.geometry.width ?? 0))
        case "getheight", "getguih":
            return .integer(dimension(resolvedFrame(of: object)?.height,
                                      declared: object.geometry.height ?? 0))
        // Both sides of this comparison must be in the *same* window's space, so the point comes from
        // the window that renders this object rather than from the global mouse hook, and the rect is
        // the object's resolved frame in that window (not the parent-relative one `getLeft` answers).
        // With no window — the headless harness — the honest answer is "no", which still lets the
        // handler run to the end instead of aborting it.
        case "ismouseoverrect":
            guard let point = mousePositionInObjectSpaceRequested?(object),
                  let frame = resolvedGeometryRequested?(object)?.frame else { return .boolean(false) }
            return .boolean(frame.contains(point))
        case "refresh":
            notifyObjectDidMutate(object)
            return .null
        // `AlbumArtLayer.isLoading()`. Only an `<AlbumArt>` has a fetch to wait on; any other
        // receiver is honestly not loading anything.
        case "isloading":
            // The XUI form (`<Wasabi:AlbumArt>`) keeps its namespace prefix in the element name.
            let type = object.typeName.lowercased().components(separatedBy: ":").last ?? ""
            guard type == "albumart" else { return .boolean(false) }
            return .boolean(host.isArtworkLoading)
        case "getposition" where WasabiFrame.isFrame(object):
            // A splitter's position is its divider offset, not a slider value. ClassicPro reads it to
            // decide whether the side view is open (`mainFrame.getPosition()==0`).
            return .integer(Int32(clamping: Int(WasabiFrame.position(of: object))))
        case "setposition" where WasabiFrame.isFrame(object):
            guard WasabiFrame.setPosition(Double(arguments[0].integerValue), on: object) else { return .null }
            noteGeometryChange()
            notifyGraphDidMutate()
            _ = try dispatch(object: object, event: "onsetposition", arguments: [arguments[0]])
            return .null
        // Same rule as `getactivated`: for a bound control the setting *is* the position, and the
        // `value` attribute is not a second copy of it. mmd3 seeds its crossfade readout with
        // `slidercb.onSetPosition(slidercb.getPosition())` at load, which read 0 whatever the
        // stored duration was.
        case "getposition":
            let readFrom = embeddedControl(of: object) ?? object
            if let value = configInteger(of: readFrom) { return .integer(value) }
            return .integer(Int32(readFrom.attributes["value"] ?? readFrom.attributes["position"] ?? "0") ?? 0)
        case "setposition" where Self.configBinding(of: object) != nil:
            if let binding = Self.configBinding(of: object) {
                setConfigAttribute(section: binding.section, key: binding.key,
                                   value: String(arguments[0].integerValue))
            }
            _ = try dispatch(object: object, event: "onsetposition", arguments: [arguments[0]])
            return .null
        case "setposition":
            // Only an actual change notifies, as in Wasabi. Skins pair sliders that write each
            // other's position from their own `onSetPosition`; notifying unconditionally turns that
            // into an endless round trip.
            // Clamped to the range the slider declares, as Wasabi does. A skin that steps a slider
            // relative to itself — `slider.setPosition(slider.getPosition() + 5)`, which is how every
            // scrollbar's up/down button in the corpus works — otherwise walks straight off the end
            // and never comes back, and whatever reads the position is handed a number outside the
            // unit it was cut for. Only a declared range clamps: an object that states neither `low`
            // nor `high` is left exactly as it was.
            let target = embeddedControl(of: object) ?? object
            let position = String(Self.clampedSliderPosition(arguments[0].integerValue, of: target))
            guard target.attributes["value"] != position else { return .null }
            _ = target.setAttribute("value", value: position)
            notifyObjectDidMutate(target)
            // Dispatched at the control that actually moved; `embeddedXUIForwardedEvents` carries it
            // back up to the wrapper, so a script bound to either one hears it exactly once.
            _ = try dispatch(object: target, event: "onsetposition",
                             arguments: [.integer(Int32(position) ?? arguments[0].integerValue)])
            return .null
        case "setmode":
            _ = object.setAttribute("mode", value: arguments[0].stringValue)
            notifyObjectDidMutate(object)
            return .null
        case "play":
            // Stamp the clock so the frame is a pure function of elapsed time (`WasabiAnimation`),
            // which keeps the renderer and `isPlaying()` on exactly the same model.
            _ = object.setAttribute("animstart", value: String(WasabiAnimation.now()))
            _ = object.setAttribute("playing", value: "1")
            notifyObjectDidMutate(object)
            return .null
        case "pause", "stop":
            // Freeze where the animation actually is, not where it started.
            _ = object.setAttribute("frame", value: String(animationFrame(of: object)))
            _ = object.setAttribute("playing", value: "0")
            notifyObjectDidMutate(object)
            return .null
        case "gotoframe", "setframe":
            _ = object.setAttribute("frame", value: String(max(0, arguments[0].integerValue)))
            _ = object.setAttribute("playing", value: "0")
            notifyObjectDidMutate(object)
            return .null
        case "getcurframe": return .integer(Int32(animationFrame(of: object)))
        case "getlength": return .integer(Int32(clamping: animationFrameCount(of: object)))
        case "setstartframe":
            _ = object.setAttribute("startframe", value: String(max(0, arguments[0].integerValue)))
            return .null
        case "setendframe":
            _ = object.setAttribute("endframe", value: String(max(0, arguments[0].integerValue)))
            return .null
        case "setspeed":
            _ = object.setAttribute("speed", value: String(max(1, arguments[0].integerValue)))
            return .null
        case "setautoreplay":
            // Written to the same attribute the markup carries, so `WasabiAnimation` reads one value
            // whether the skin declared it or a script set it. It only decides what a layer does with
            // *no* explicit `playing`, which is why a range play started right after is unaffected.
            _ = object.setAttribute("autoreplay", value: arguments[0].integerValue != 0 ? "1" : "0")
            return .null
        case "isplaying":
            return .boolean(WasabiAnimation.state(of: object,
                                                  frameCount: animationFrameCount(of: object)).isPlaying)
        // The `<list>` control. Its rows live on the object (`WasabiGuiList`), so the renderer draws
        // what the script just wrote with no second copy in between.
        case "deleteallitems" where WasabiGuiList.isList(object):
            WasabiGuiList.setItems([], on: object)
            WasabiGuiList.setSelection([], on: object)
            WasabiGuiList.setScrollOffset(0, on: object)
            notifyObjectDidMutate(object)
            return .null
        case "additem" where WasabiGuiList.isList(object):
            var items = WasabiGuiList.items(of: object)
            guard items.count < WasabiGuiList.maximumItems else { return .integer(-1) }
            items.append(arguments[0].stringValue)
            WasabiGuiList.setItems(items, on: object)
            notifyObjectDidMutate(object)
            return .integer(Int32(items.count - 1))
        case "getnumitems" where WasabiGuiList.isList(object):
            return .integer(Int32(clamping: WasabiGuiList.items(of: object).count))
        case "getitemlabel" where WasabiGuiList.isList(object):
            // One column: the skin's own list is `nocolheader="1"` and puts the whole row in the
            // string it adds, so the column argument names the only column there is.
            let items = WasabiGuiList.items(of: object)
            let index = Int(arguments[0].integerValue)
            guard items.indices.contains(index) else { return .string("") }
            return .string(items[index])
        case "getfirstitemselected" where WasabiGuiList.isList(object):
            return .integer(Int32(WasabiGuiList.selection(of: object).first ?? -1))
        case "getnextitemselected" where WasabiGuiList.isList(object):
            let after = Int(arguments[0].integerValue)
            return .integer(Int32(WasabiGuiList.selection(of: object).first { $0 > after } ?? -1))
        case "scrolltoitem" where WasabiGuiList.isList(object):
            // The row becomes the top of the box. Wasabi scrolls the least it can, but the renderer
            // clamps this against the box it ends up drawing in, and a script only ever asks for this
            // to bring a fresh hit into view.
            WasabiGuiList.setScrollOffset(Int(arguments[0].integerValue), on: object)
            notifyObjectDidMutate(object)
            return .null
        case "setfocus":
            // The view owns the focus, because the keyboard is a window's property rather than the
            // graph's. It resolves the object to the `<edit>` it is or contains — a skin focuses the
            // wrapper (`Wasabi:EditBox2`) as often as the control.
            focusRequested?(embeddedControl(of: object) ?? object)
            return .null
        case "setfontsize":
            // The same pixel height the XML attribute carries, so it goes through the one
            // `WasabiTextMetrics` conversion the renderer and `getAutoWidth()` share.
            _ = object.setAttribute("fontsize", value: String(arguments[0].integerValue))
            notifyObjectDidMutate(object)
            return .null
        case "setalternatetext":
            // A script's alternate text *replaces* what the object shows — MMD3 puts its SEEK, VOLUME,
            // BASS and TREBLE readouts on the song ticker this way, then clears them a second later.
            // Empty restores the normal content. It is written to its own key rather than over the
            // XML `alternatetext`, which is a placeholder for "nothing to show" and must not be
            // promoted into an override (that is what pinned MMD3's display to "updating songticker").
            _ = object.setAttribute(WasabiTextMetrics.scriptAlternateTextKey,
                                    value: arguments[0].stringValue)
            notifyObjectDidMutate(object)
            return .null
        case "leftclick":
            _ = try dispatch(object: object, event: "onleftclick")
            actionRequested?(object.attributes["action"] ?? "", object.attributes["param"])
            return .null
        case "settargetx": return setTarget("targetx", object: object, value: arguments[0])
        case "settargety": return setTarget("targety", object: object, value: arguments[0])
        case "settargetw": return setTarget("targetw", object: object, value: arguments[0])
        case "settargeth": return setTarget("targeth", object: object, value: arguments[0])
        case "settargeta": return setTarget("targeta", object: object, value: arguments[0])
        case "settargetspeed":
            _ = object.setAttribute("targetspeed", value: String(arguments[0].doubleValue))
            return .null
        case "gototarget":
            startTargetAnimation(object: object)
            return .null
        case "canceltarget":
            cancelTargetAnimation(objectID: object.stableID)
            _ = object.setAttribute("goingtotarget", value: "0")
            return .null
        case "reversetarget":
            reverseTargetAnimation(object: object)
            return .null
        case "isgoingtotarget": return .boolean(object.attributes["goingtotarget"] == "1")
        case "sendaction":
            // `sendAction` is Wasabi's script-to-script channel, and the receiver hears it as its own
            // `onAction(action, param, x, y, p1, p2, source)` — six arguments in, seven out, the last
            // being the sender. Routing it only to the host's action handler (the previous behaviour)
            // left every internal ClassicPro message unheard: the tab strip answers a click with
            // `CproSUI.sendAction("show_tab", …)`, and with nothing dispatching that, clicking a tab
            // reached the button's script and then stopped dead there.
            //
            // Delivered to the addressed object only, not down its subtree: every measured use names
            // the exact group whose script declares the handler.
            let source = program.ownerID.flatMap(loadedSkin.runtime.graph.object(withID:))
            if ProcessInfo.processInfo.environment["WINAMP_MODERN_ACTION_TRACE"] != nil {
                print("ACTION \(arguments[0].stringValue) param=\(arguments[1].stringValue) "
                      + "-> \(object.typeName)#\(object.xmlID ?? "-")")
            }
            let handled = try dispatch(object: object, event: "onaction",
                                       arguments: Array(arguments.prefix(6)) + [objectValue(source)])
            // The host action route is kept: a skin is also free to name one of NullPlayer's own
            // actions here, and nothing that used to work should stop.
            //
            // The **browser pair is the exception**, and only because both ends are real here now
            // (B40): a skin that ships its own reader answers `browser_search` / `browser_navigate`
            // itself — Big Bento's turns the terms into a query with its own engine setting and
            // navigates its `<browser>` — so letting the host act as well loads that same surface a
            // second time, with a URL the skin did not choose. They reach the host only when no
            // script took them, which is the skin that sends one and ships no reader.
            if handled == 0 || !Self.scriptOwnedBrowserActions.contains(arguments[0].stringValue.lowercased()) {
                actionRequested?(arguments[0].stringValue, arguments[1].stringValue)
            }
            return .null
        case "triggeraction":
            actionRequested?(arguments[0].stringValue, arguments[1].stringValue)
            return .null
        case "isinvalid":
            return .boolean(isInvalid(object))
        case "getcurcfgval":
            // A button bound to a config attribute (`cfgattrib="{GUID};Name"`) reports that
            // attribute's value; the GUID is the section key, exactly as `getItemByGuid` uses it.
            // Unbound objects fall back to their own toggle state.
            if let value = configInteger(of: object) { return .integer(value) }
            return .integer(Int32(object.attributes["value"] ?? "") ?? (object.attributes["activated"] == "1" ? 1 : 0))
        case "setscale":
            // "Scale all my windows to this." Answered by the host's UI Size, and only from a
            // **layout** receiver: that is the only form in the corpus, and a scale stamped on a
            // child object would be a second, rival scale for the same pixels (see `getscale`
            // below, which stays 1 for exactly that reason). A non-layout receiver is accepted and
            // inert rather than refused — refusing a method aborts the handler that called it.
            if object.typeName.caseInsensitiveCompare("layout") == .orderedSame {
                let factor = arguments[0].doubleValue
                // A skin is not allowed to drive the host off the end of the scale; the host snaps
                // the request to one of its own levels anyway, and a garbage value should not reach
                // it as one. Winamp's own range is 1…3.
                if factor.isFinite, factor > 0 {
                    uiScaleRequested?(CGFloat(min(max(factor, 0.25), 4)))
                }
            }
            return .null
        case "getscale":
            // The scene is always on the skin's own pixel grid: UI Size is applied at the view's
            // drawing/input boundary and is deliberately invisible to scripts (Phase 10), so the
            // layout's own scale is 1. ClassicPro multiplies its resize arithmetic by this.
            return .float(1)
        case "setredraw":
            // A redraw hint (`widgetsManager` throttles its list while populating). The renderer
            // repaints from the graph, so there is no suspended-drawing state to honour.
            return .null
        case "scrolltopercent":
            // Park a scrolling container at a percentage of its travel: `0` is the top, `100` the
            // bottom, and the renderer turns it into an offset applied to the children (see
            // `WasabiSceneRenderer.scrollOffset`). Every route a user has ends here — Big Bento
            // Modern's settings pages drive it from the scrollbar's drag (`onSetPosition`), from its
            // up/down buttons (`cscrollbar.maki` nudges the slider by 5), and from the wheel — so
            // while this was an accepted no-op *nothing* scrolled, by any means, and everything below
            // the fold on a settings page was unreachable (BB19).
            let percent = max(0, min(100, arguments[0].doubleValue))
            _ = object.setAttribute(WasabiSceneRenderer.scrollPercentKey, value: String(percent))
            noteGeometryChange()
            notifyObjectDidMutate(object)
            return .null
        case "navigateurl":
            // A browser object may drive only its own embedded, policy-gated WebKit surface. Calls
            // on any other GUI object stay quietly inert so an untrusted skin cannot turn a generic
            // object reference into a network primitive.
            if WasabiSceneRenderer.isBrowserElement(object) {
                browserNavigationRequested?(object.stableID, arguments[0].stringValue)
            }
            return .null
        case let name where name.hasPrefix("fx_"):
            // The layer warp itself: `invokeLayerFX` writes the configuration and `fx_update()` is
            // what re-runs the skin's callbacks. See `WasabiLayerFX.swift` for the model.
            return invokeLayerFX(method: name, object: object, arguments: arguments)
        case "setregion":
            // The renderer draws from the graph and nothing else, so a region is stamped onto the
            // object and the scene redrawn — the same route `play`/`gotoFrame` take. A region that
            // was never loaded from a map (or an explicitly null one) clears the clip.
            var applied = false
            if case .object(let reference) = arguments[0],
               case .dynamic(let regionID) = reference.kind,
               let regionState = dynamicObjects[regionID],
               case .region(let clip) = regionState.role {
                applied = clip.apply(to: object)
            } else {
                applied = WasabiRegionClip.clear(on: object)
            }
            if applied { notifyGraphDidMutate() }
            return .null
        case "setregionfrommap":
            // The short form: a map, a threshold and the reversed flag, with no `Region` in between.
            guard case .object(let reference) = arguments[0],
                  case .dynamic(let mapID) = reference.kind,
                  let mapState = dynamicObjects[mapID],
                  case .map(let bitmapID, let source) = mapState.role else {
                if WasabiRegionClip.clear(on: object) { notifyGraphDidMutate() }
                return .null
            }
            let clip = WasabiRegionClip(mapID: bitmapID,
                                        mapPath: mapLogicalPath(bitmapID: bitmapID, source: source),
                                        threshold: Int(arguments[1].integerValue),
                                        reversed: arguments[2].truthy)
            if clip.apply(to: object) { notifyGraphDidMutate() }
            return .null
        case "islayoutanimationsafe", "istransparencysafe": return .boolean(true)
        // `init(parent)` — the second half of Wasabi's two-step runtime instantiation: `newGroup(id)`
        // *creates* the group, `init(parent)` **puts it where the script wants it**. Treating it as a
        // no-op is what made cPro-Bento's tab strip inert, and it is the whole of TASKS §15.6:
        //
        //   Tab tabI = newGroup("cpro.tab");   // lands under the script group, `Cpro.tabs`
        //   tabI.init(tabHolder);              // belongs in `cprotabs.buttons`, the 4px-inset strip
        //
        // Left under `Cpro.tabs`, each tab's `getParent()` answered the wrong object, so
        // `CproTabButton.m`'s `setDispatcher(getScriptGroup().getParent())` addressed `Cpro.tabs` while
        // `CproTabs.m` receives on `cprotabs.buttons` — a click reached the button's own script and
        // then went nowhere. It also left every pill 4px up and to the left of where the skin's own
        // reference render puts it. (§15.6 blamed the strip's script never initializing; it does run.)
        case "init":
            if case .object(let reference) = arguments[0], case .gui(let parentID) = reference.kind,
               let parent = loadedSkin.runtime.graph.object(withID: parentID), parent !== object.parent {
                // `insertChild` detaches from the old parent and refuses a cycle, so a script cannot
                // reparent an object into its own subtree.
                try parent.appendChild(object)
                noteGeometryChange()
                notifyGraphDidMutate()
            }
            // Attachment is also when the new subtree's own scripts start — see `pendingRuntimeGroups`.
            try startPendingScripts(for: object)
            return .null
        // Paint order is sibling order (the renderer walks `children` front to back), so raising an
        // object is moving it to the end of its parent's list.
        case "bringtofront", "bringtoback":
            guard let parent = object.parent, parent.children.count > 1 else { return .null }
            try parent.insertChild(object, at: method == "bringtofront" ? parent.children.count : 0)
            notifyGraphDidMutate()
            return .null
        case "callme", "ondatachanged": return .null
        default:
            throw unsupported(method, program: program)
        }
    }

    private func invokePopup(method: String, id: UInt64, arguments: [MakiValue]) -> MakiValue {
        switch method {
        case "addcommand":
            // Winamp's fourth argument is *disabled*, not "separator": storing it in the separator
            // slot turned every greyed-out command into a divider.
            popupCommands[id, default: []].append(
                PopupEntry(title: arguments[0].stringValue, commandID: arguments[1].integerValue,
                           checked: arguments[2].truthy, disabled: arguments[3].truthy))
            return .null
        case "addseparator":
            popupCommands[id, default: []].append(PopupEntry(isSeparator: true))
            return .null
        case "addsubmenu":
            // `parent.addSubMenu(child, title)` — the child is a PopupMenu the script has already
            // filled in. It is referenced rather than copied, so a script that keeps adding to the
            // child after attaching it still gets what it built (Love is War Miku's visualization
            // menu nests its Spectrum Analyzer and Oscilloscope presets this way).
            guard case .object(let reference) = arguments[0],
                  case .popupMenu(let child) = reference.kind else { return .null }
            popupCommands[id, default: []].append(
                PopupEntry(title: arguments[1].stringValue, submenu: child))
            return .null
        case "checkcommand":
            let commandID = arguments[0].integerValue
            if let index = popupCommands[id]?.firstIndex(where: { $0.commandID == commandID }) {
                popupCommands[id]![index].checked = arguments[1].truthy
            }
            return .null
        case "popatmouse": return .integer(popupPresenter?(popupItems(of: id, depth: 0), nil) ?? 0)
        case "popatxy":
            // ClassicPro positions its tab-strip and "goto" menus with
            // `popAtXY(clientToScreenX(b.getLeft()), clientToScreenY(b.getTop() + 26))` — the point is
            // whatever those conversions answer, so the two have to agree. They do: both are
            // window-client space, and the presenter places the menu in that window.
            return .integer(popupPresenter?(popupItems(of: id, depth: 0),
                                            CGPoint(x: Int(arguments[0].integerValue),
                                                    y: Int(arguments[1].integerValue))) ?? 0)
        default: return .null
        }
    }

    /// One entry of a script-built menu, before its submenus are resolved.
    private struct PopupEntry {
        var title = ""
        var commandID: Int32 = 0
        var checked = false
        var disabled = false
        var isSeparator = false
        /// The id of the `PopupMenu` this entry opens, for a submenu row.
        var submenu: UInt64?
    }

    /// Resolve a menu and everything it nests into the presenter's shape. A skin could attach a menu
    /// to itself, so the walk is depth-bounded rather than trusting the graph of menus to be a tree.
    private func popupItems(of id: UInt64, depth: Int) -> [WinampModernPopupMenuItem] {
        guard depth < 8, let entries = popupCommands[id] else { return [] }
        return entries.map { entry in
            WinampModernPopupMenuItem(
                title: entry.title, commandID: entry.commandID, checked: entry.checked,
                disabled: entry.disabled, isSeparator: entry.isSeparator,
                children: entry.submenu.map { popupItems(of: $0, depth: depth + 1) } ?? [])
        }
    }

    private func invokeDynamic(method: String, id: UInt64, arguments: [MakiValue],
                               program: MakiProgram) throws -> MakiValue {
        guard var state = dynamicObjects[id] else { return .null }
        // A script may call one of *this* object's event handlers as a method, exactly as it may a
        // GUI object's or `System`'s (the two routes above). For a `Timer` that is the "run the
        // timer's body now, don't wait for the next tick" idiom: Big Bento Modern's songticker
        // answers `sendAction("cancelinfo")` — which `seek.maki` posts on every mouse-up and on
        // `onSetFinalPosition` — with `timer.onTimer()`, and without this the whole `onAction`
        // handler aborted there, leaving the ticker stuck on its `Seek: 1:13/4:05 (30%)` preview.
        if Self.dispatchableEventArity[method] != nil {
            _ = try dispatch(target: MakiObjectReference(.dynamic(id)), event: method,
                             arguments: arguments)
            return method == "onaction" ? .integer(0) : .null
        }
        switch method {
        // `GammaSet.apply()` — switch to the theme this object names, through the one route
        // `System.setColorTheme` already uses. A theme the skin does not ship is refused by the
        // catalog and the call is simply inert.
        case "apply":
            guard case .gammaSet(let name) = state.role else { return .null }
            _ = themeSwitchRequested?(name)
            return .null
        case "loadmap":
            state.role = .map(bitmapID: arguments[0].stringValue, source: program.source)
            dynamicObjects[id] = state
            return .null
        case "loadfrommap":
            // Argument 0 is the `Map` object itself, so the region borrows the bitmap that map
            // already resolved — including the path form, which has no `<bitmap>` definition and so
            // has to be handed to the renderer as an already-resolved logical path.
            guard case .object(let reference) = arguments[0],
                  case .dynamic(let mapID) = reference.kind,
                  let mapState = dynamicObjects[mapID],
                  case .map(let bitmapID, let source) = mapState.role else { return .null }
            state.role = .region(clip: WasabiRegionClip(mapID: bitmapID,
                                                        mapPath: mapLogicalPath(bitmapID: bitmapID, source: source),
                                                        threshold: Int(arguments[1].integerValue),
                                                        reversed: arguments[2].truthy))
            dynamicObjects[id] = state
            return .null
        case "offset":
            guard case .region(let clip) = state.role else { return .null }
            state.role = .region(clip: WasabiRegionClip(mapID: clip.mapID, mapPath: clip.mapPath,
                                                        threshold: clip.threshold, reversed: clip.reversed,
                                                        offsetX: clip.offsetX + Int(arguments[0].integerValue),
                                                        offsetY: clip.offsetY + Int(arguments[1].integerValue)))
            dynamicObjects[id] = state
            return .null
        case "load":
            state.role = .xmlDocument
            dynamicObjects[id] = state
            return .null
        case "exists":
            return .boolean(false)
        case "inregion", "getvalue":
            guard case .map(let bitmapID, let source) = state.role else {
                return method == "inregion" ? .boolean(false) : .integer(0)
            }
            let sample = mapPixel(bitmapID: bitmapID, source: source,
                                  x: Int(arguments[0].integerValue), y: Int(arguments[1].integerValue))
            if method == "inregion" {
                // A map with an alpha channel masks its region; MMD3's are opaque grayscale, where
                // being inside the bitmap *is* being in the region.
                return .boolean(sample.inBounds && sample.alpha > 0)
            }
            return .integer(Int32(sample.red))
        case "getargbvalue":
            // One channel of one pixel. The channel index is BGRA — pinned by `player.maki`, which
            // builds a `colorbandpeak="r,g,b"` attribute from channels 2, 1, 0 in that order.
            guard case .map(let bitmapID, let source) = state.role else { return .integer(0) }
            let sample = mapPixel(bitmapID: bitmapID, source: source,
                                  x: Int(arguments[0].integerValue), y: Int(arguments[1].integerValue))
            switch arguments[2].integerValue {
            case 0: return .integer(Int32(sample.blue))
            case 1: return .integer(Int32(sample.green))
            case 2: return .integer(Int32(sample.red))
            case 3: return .integer(Int32(sample.alpha))
            default: return .integer(0)
            }
        case "getwidth", "getheight":
            guard case .map(let bitmapID, let source) = state.role,
                  let image = mapImage(bitmapID: bitmapID, source: source) else { return .integer(0) }
            return .integer(Int32(clamping: method == "getwidth" ? image.width : image.height))
        case "additem":
            guard state.items.count < Self.maximumListItems else { return .integer(-1) }
            state.items.append(arguments[0])
            dynamicObjects[id] = state
            return .integer(Int32(state.items.count - 1))
        case "enumitem":
            let index = Int(arguments[0].integerValue)
            guard state.items.indices.contains(index) else { return .null }
            return state.items[index]
        case "getnumitems", "getsize": return .integer(Int32(clamping: state.items.count))
        case "setsize":
            // `BitList` — same backing store as `List`, holding booleans. ClassicPro sizes one to the
            // widget count and ticks off the widgets it has already initialised.
            let size = max(0, min(Self.maximumListItems, Int(arguments[0].integerValue)))
            state.items = (0..<size).map { index in
                index < state.items.count ? state.items[index] : .boolean(false)
            }
            dynamicObjects[id] = state
            return .null
        case "getitem":
            let index = Int(arguments[0].integerValue)
            guard state.items.indices.contains(index) else { return .boolean(false) }
            return .boolean(state.items[index].truthy)
        case "setitem":
            let index = Int(arguments[0].integerValue)
            guard state.items.indices.contains(index) else { return .null }
            state.items[index] = .boolean(arguments[1].truthy)
            dynamicObjects[id] = state
            return .null
        case "removeitem":
            let index = Int(arguments[0].integerValue)
            guard state.items.indices.contains(index) else { return .null }
            state.items.remove(at: index)
            dynamicObjects[id] = state
            return .null
        case "removeall":
            state.items.removeAll()
            dynamicObjects[id] = state
            return .null
        case "finditem":
            // `Any` items: an object matches by identity, everything else by its string form, which is
            // how the engine searches its string lists.
            let index = state.items.firstIndex { item in
                if case .object(let reference) = arguments[0] { return object(item, equals: reference) }
                if case .object = item { return false }
                return item.stringValue == arguments[0].stringValue
            }
            return .integer(Int32(index ?? -1))
        case "getint", "getbool", "getstring":
            guard case .configGroup(let section) = state.role else {
                return method == "getstring" ? .string("") : .integer(0)
            }
            let key = arguments[0].stringValue
            // An unset item reads 0. That is also the right answer for the one item ClassicPro asks
            // about — `"frequencies"`, where 0 means Winamp's classic EQ frequencies, which is what
            // NullPlayer's `EQConfiguration.classic10` uses.
            let value = loadedSkin.configuration.integer(section: section, key: key, default: 0)
            switch method {
            case "getbool": return .boolean(value != 0)
            case "getstring": return .string(loadedSkin.configuration.string(section: section, key: key))
            default: return .integer(value)
            }
        case "setdelay":
            state.delayMilliseconds = max(8, arguments[0].integerValue)
            dynamicObjects[id] = state
            return .null
        case "start":
            let reference = MakiObjectReference(.dynamic(id))
            if MakiInterpreter.tracesExecution {
                print("MAKI timer start id=\(id) delay=\(state.delayMilliseconds) "
                      + "by=\(MakiInterpreter.traceStack.last ?? "-")")
            }
            _ = try timers.schedule(id: id, period: TimeInterval(state.delayMilliseconds) / 1_000) { [weak self] in
                guard let self else { return }
                _ = try? self.dispatch(target: reference, event: "ontimer", arguments: [])
            }
            return .boolean(true)
        case "stop":
            if MakiInterpreter.tracesExecution {
                print("MAKI timer stop id=\(id) running=\(timers.contains(id: id)) "
                      + "by=\(MakiInterpreter.traceStack.last ?? "-")")
            }
            timers.cancel(id: id)
            return .null
        case "isrunning": return .boolean(timers.contains(id: id))
        case "newattribute", "getattribute":
            guard case .configItem(let section) = state.role else { return .null }
            let key = arguments[0].stringValue
            if method == "newattribute" {
                let defaultValue = arguments[1].stringValue
                let existing = loadedSkin.configuration.string(section: section, key: key,
                                                                 default: defaultValue)
                loadedSkin.configuration.setString(existing, section: section, key: key)
                recordRegisteredSetting(section: section, name: key, defaultValue: defaultValue)
            }
            return dynamicValue(role: .configAttribute(section: section, key: key))
        case "getdata":
            guard case .configAttribute(let section, let key) = state.role else { return .string("") }
            let data = loadedSkin.configuration.string(section: section, key: key)
            if ProcessInfo.processInfo.environment["WINAMP_MODERN_CALL_TRACE"] != nil {
                print("CALL-TRACE getdata[\(section);\(key)] -> \(data)")
            }
            return .string(data)
        case "setdata":
            guard case .configAttribute(let section, let key) = state.role else { return .null }
            // Through the shared write route, not this object alone. A skin's configurator writes an
            // attribute from one script and every *other* script that registered the same attribute
            // applies it from its own `onDataChanged` — Defix changes its background that way, one
            // `setData` in the configurator against a `STANDARDFRAME` script per window. Dispatching
            // only to the caller left the write visible in exactly the window that made it.
            setConfigAttribute(section: section, key: key, value: arguments[0].stringValue)
            return .null
        case "getid":
            switch state.role {
            case .configItem(let section): return .string(section)
            case .configAttribute(_, let key): return .string(key)
            case .map(let bitmapID, _): return .string(bitmapID)
            case .region(let clip): return .string(clip.mapID)
            case .xmlDocument: return .string("")
            case .configGroup(let section): return .string(section)
            case .gammaSet(let name): return .string(name)
            case .generic: return .string("dynamic_\(id)")
            }
        case "init", "callme", "ondatachanged": return .null
        default:
            if let value = classicProFileMethod(method, arguments: arguments) { return value }
            throw unsupported(method, program: program)
        }
    }

    /// Which layout a `newGroupAsLayout` group hangs off: the one its groupdef names in
    /// `owner="<container>,<layout>"`, falling back to the calling script's own ancestor layout when
    /// there is no `owner=` or it names something this skin did not instantiate.
    ///
    /// The fallback matters because the caller is often not under a layout at all — multipass's
    /// `system.maki` is a `skin.xml`-level script whose owner is the `<scripts>` element — in which
    /// case there is nothing to parent to and the call answers null rather than misplacing the group.
    private func ownerLayout(forGroupDefinition identifier: String, program: MakiProgram) -> WasabiObject? {
        let owner = (try? loadedSkin.runtime.types.resolved(identifier: identifier))?
            .defaultAttributes["owner"] ?? ""
        let parts = owner.components(separatedBy: ",").map {
            $0.trimmingCharacters(in: .whitespaces)
        }.filter { !$0.isEmpty }
        if let containerID = parts.first, let container = findRoot(type: "container", xmlID: containerID) {
            let layouts = container.children.filter {
                $0.typeName.caseInsensitiveCompare("layout") == .orderedSame
            }
            // `owner="main"` with no layout half means the container's first layout.
            if parts.count < 2 { if let first = layouts.first { return first } }
            if let named = layouts.first(where: { $0.xmlID?.caseInsensitiveCompare(parts[1]) == .orderedSame }) {
                return named
            }
        }
        guard let caller = program.ownerID.flatMap(loadedSkin.runtime.graph.object(withID:)) else { return nil }
        return ancestor(of: caller, type: "layout")
    }

    private func findRoot(type: String, xmlID: String) -> WasabiObject? {
        loadedSkin.runtime.graph.roots.first {
            $0.typeName.caseInsensitiveCompare(type) == .orderedSame &&
            $0.xmlID?.caseInsensitiveCompare(xmlID) == .orderedSame
        }
    }

    /// The control a `<groupdef embed_xui="…">` wrapper speaks for.
    ///
    /// The wrapper **is** that control, so its value has to be one number and not two. Big Bento
    /// Modern's scrollbar is the case that proves it: `cscrollbar.maki` moves the *inner* `<slider>`
    /// from the up/down buttons, while the settings page reads `vscroll.getPosition()` on the
    /// **wrapper**. Kept apart, the two drifted permanently — the page read 0 however far the bar had
    /// been moved, and opened every settings page scrolled to its own bottom (BB19).
    private func embeddedControl(of object: WasabiObject) -> WasabiObject? {
        guard let id = object.attributes["nullplayer.embedxui"] else { return nil }
        return descendant(of: object, xmlID: id)
    }

    private func descendant(of root: WasabiObject, xmlID: String) -> WasabiObject? {
        if root.xmlID?.caseInsensitiveCompare(xmlID) == .orderedSame { return root }
        for child in root.children {
            if let match = descendant(of: child, xmlID: xmlID) { return match }
        }
        return nil
    }

    private func ancestor(of object: WasabiObject, type: String) -> WasabiObject? {
        var candidate: WasabiObject? = object
        while let current = candidate {
            if current.typeName.caseInsensitiveCompare(type) == .orderedSame { return current }
            candidate = current.parent
        }
        return nil
    }

    private func dynamicValue(role: DynamicRole) -> MakiValue {
        let id = nextPopupID
        nextPopupID &+= 1
        dynamicObjects[id] = DynamicObjectState(role: role)
        return .object(MakiObjectReference(.dynamic(id)))
    }

    /// An object's box in its **parent's** coordinates — the space Wasabi's `getGuiX`/`getGuiY` and
    /// `getLeft`/`getTop` report in — or `nil` when no scene can place it.
    ///
    /// Reading the raw `x`/`y`/`w`/`h` attributes instead is only right for absolute geometry, and
    /// Bento-style skins barely use any: cPro's tab strip is `w="-4" relatw="1"`, so `getWidth()`
    /// answered **−4**, `CproTabs.m` concluded it had no room for its tabs, switched to short names and
    /// squeezed every tab to the 20px floor. The declared value stays as the fallback for an object the
    /// active scene does not contain (a hidden layout, or a runtime with no window wired at all).
    private func resolvedFrame(of object: WasabiObject) -> CGRect? {
        guard let geometry = resolvedGeometryRequested?(object) else { return nil }
        return geometry.frame.offsetBy(dx: -geometry.parent.minX, dy: -geometry.parent.minY)
    }

    /// How many instances one `instantiate` call may add. The corpus's only caller asks for 1.
    private static let maximumGroupListInstances = 64

    /// Wasabi's `<GroupList>` is a **vertical stack**: each instance spans the list's width and sits
    /// below the ones already in it. Two things follow, and both have to be stamped onto the child
    /// here because a groupdef carries neither.
    ///
    /// *Width.* The part groupdefs declare `h=` and no `w=` at all, so a child left at its markup
    /// geometry is zero-width and draws nothing — its own contents are relative to it
    /// (`w="-203" relatw="1"`), which is a negative box, not a small one.
    ///
    /// *Top.* Both parts would otherwise land at `y=0` and cover each other. The offset is the sum of
    /// the heights the earlier siblings declare, which is the number the author writes the groupdef's
    /// `h=` for (Big Bento's pages are 223+220, 243+251, …) — and the same number the page's
    /// scrollbar script compares its `param`'s third token against to decide whether to show itself.
    ///
    /// Anything that is not a `GroupList` keeps whatever geometry it was instantiated with.
    private func stackInGroupList(_ child: WasabiObject, list: WasabiObject) {
        guard list.typeName.caseInsensitiveCompare("grouplist") == .orderedSame else { return }
        var top = 0.0
        for sibling in list.children where sibling !== child { top += stackedHeight(of: sibling) }
        _ = child.setAttribute("x", value: "0")
        _ = child.setAttribute("relatx", value: "0")
        _ = child.setAttribute("y", value: String(Int(top.rounded())))
        _ = child.setAttribute("relaty", value: "0")
        _ = child.setAttribute("w", value: "0")
        _ = child.setAttribute("relatw", value: "1")
    }

    /// The vertical room one list entry takes. The declared `h=` is the authority — the entries are
    /// stacked before any layout pass has run, so a resolved frame exists for at most the ones
    /// already on screen, and mixing the two units would stack the second entry against the first
    /// one's *scene* height rather than the height the author sized the list around.
    private func stackedHeight(of object: WasabiObject) -> Double {
        max(0, Double(object.attributes["h"] ?? "") ?? 0)
    }

    /// A resolved coordinate when the scene could supply one, and the markup's own value otherwise.
    private func dimension(_ resolved: CGFloat?, declared: Double) -> Int32 {
        Int32(clamping: Int(resolved.map(Double.init) ?? declared))
    }

    private func objectValue(_ object: WasabiObject?) -> MakiValue {
        object.map { .object(MakiObjectReference(.gui($0.stableID))) } ?? .null
    }

    private func object(_ value: MakiValue, equals reference: MakiObjectReference) -> Bool {
        guard case .object(let candidate) = value else { return false }
        return candidate == reference
    }

    /// Winamp's fixed band scale: `getVisBand`'s band argument is documented `0..75` in `std.mi`,
    /// so a skin indexes in that scale whatever the host's analyser actually produces.
    static let visBandCount = 76

    /// `System.getVisBand(channel, band)` — one band of the spectrum as a vis byte (0…255, the same
    /// unit `getLeftVUMeter` answers in, which is what a skin's meter artwork is cut for).
    ///
    /// The source is the existing spectrum tap every other visualization window already consumes
    /// (`AudioEngine` → `updateSpectrum` → `host.spectrumLevels`); no second analysis path is added.
    /// That tap is **mono**, so both channels answer the same value — a stereo split would mean a
    /// second FFT for skins alone. The tap's own band count is an audio-side detail, so the request
    /// is resampled into Winamp's 0…75 scale rather than indexed directly: getting the scale wrong
    /// reads as "the meters twitch" rather than as a bug.
    private func visBand(channel: Int32, band: Int32) -> Int32 {
        _ = channel
        let levels = host.spectrumLevels
        guard !levels.isEmpty else { return 0 }
        let requested = max(0, min(Self.visBandCount - 1, Int(band)))
        let index = levels.count == Self.visBandCount
            ? requested
            : min(levels.count - 1, requested * levels.count / Self.visBandCount)
        return Self.visByte(forMagnitude: levels[index])
    }

    /// A linear FFT magnitude as Winamp's vis byte, on a **decibel** scale.
    ///
    /// The same mistake Phase 29 found in the VU meter, in the other tap. `levels[…]` is a linear
    /// magnitude, and scaling it by 255 puts ordinary music at the very bottom of a range the skin's
    /// artwork spans: measured on Defix's speaker cones over real playback, `getVisBand(0,0)` ran
    /// **min 0, max 39, mean 4, p50 1** out of 255. The cone has 25 frames and spent **96.5%** of the
    /// track on frame 0 — which reads as "the speakers don't animate, and they're dark", because
    /// frame 0 is the cone at rest.
    ///
    /// Hearing is logarithmic and so is Winamp's meter artwork, so the magnitude is mapped through
    /// `20·log10` over a 60 dB window: −60 dB and below is 0, full scale is 255. That puts the same
    /// measured material across roughly a third to three-quarters of the sweep, which is the travel
    /// the frames are cut for.
    ///
    /// `WINAMP_MODERN_CALL_TRACE=1` and watching `getvisband` against `gotoframe` is how this was
    /// found and is how to check it again: a healthy meter uses a spread of frames, not one.
    static func visByte(forMagnitude magnitude: Float) -> Int32 {
        guard magnitude > 0 else { return 0 }
        let floorDecibels: Double = -60
        let decibels = 20 * log10(Double(min(1, magnitude)))
        guard decibels > floorDecibels else { return 0 }
        let fraction = (decibels - floorDecibels) / -floorDecibels
        return Int32(max(0, min(255, (fraction * 255).rounded())))
    }

    /// `System.getLeftVUMeter()` / `getRightVUMeter()` — program level per channel as a vis byte
    /// (0…255), which is the unit analog VU artwork is cut for.
    ///
    /// The source is the host's **RMS level model**, not the spectrum. Reading a peak band out of the
    /// bar-display tap and calling it a channel was wrong twice over — that tap is mono, so both
    /// channels answered the same number, and its bands are already normalised so bars fill their
    /// window, so ×255 sat at the ceiling and every needle in every skin pinned.
    private func vuValue(left: Bool) -> Int32 {
        let level = left ? host.vuLevels.left : host.vuLevels.right
        guard level.isFinite else { return 0 }
        return Int32(max(0, min(255, (level * 255).rounded())))
    }

    /// `isInvalid()` — the object did not come up. For a *null* receiver that is answered in the
    /// interpreter; here it means an image-backed object whose bitmap never resolved, which is what
    /// the engine actually asks about. ClassicPro probes for optional artwork by declaring a hidden
    /// layer over it (`read.bg.left image="player.left.alt"`) and asking whether that layer is
    /// invalid; answering "valid" for a skin that ships no `mainframe_lr.png` made `player.maki`
    /// swap the window frame over to bitmaps that do not exist, punching holes in the window.
    // MARK: - A layout must not be left with no way to seek

    /// Objects a script hid during this event that carry a *positional* host action, checked once the
    /// event unwinds (see `settleStrandedControls`).
    private var strandingCandidates: Set<WasabiObjectID> = []

    /// Objects the skin's own script has **closed**, as opposed to ones that merely start life
    /// `visible="0"` and have never been opened. The `autoopen` fallback needs the difference: a
    /// page the script deliberately shut is a decision to respect, while an unopened one is exactly
    /// what the fallback exists to open. Big Bento's `mcvcore` closes the whole file-info page when
    /// it switches the Multi Content View to the stretched visualization, and the fallback reopened
    /// one of those groups on the next reveal — two pages on screen at once.
    private(set) var scriptClosedObjects: Set<WasabiObjectID> = []

    /// The host actions this rule protects, and why it is only these.
    ///
    /// A **positional** control — the seek bar — has no paired counterpart to swap with, so a layout
    /// that ends an event with none of them visible has lost the only way to perform that action and
    /// cannot get it back: an invisible object is not hit-testable, so nothing can re-show it. That is
    /// not true of transport buttons, which skins swap constantly (`play.hide(); pause.show()`), and
    /// including those would restore a PLAY button every time a track started. The set is
    /// demand-driven — extend it when a measured skin strands another action, not on principle.
    private static let strandableActions: Set<String> = ["SEEK"]

    private static func strandableAction(of object: WasabiObject) -> String? {
        guard let action = object.attributes["action"]?
            .trimmingCharacters(in: .whitespacesAndNewlines).uppercased(),
              strandableActions.contains(action) else { return nil }
        return action
    }

    /// Undo a hide that left a layout with no visible control for a positional action.
    ///
    /// Checked at **settle** rather than vetoed at the `hide()` itself, because a skin that swaps one
    /// control for another writes `a.hide(); b.show();` — at the moment of the hide, `b` is still
    /// hidden, so a call-time veto would refuse a perfectly good swap and leave both on screen. By the
    /// time the outermost event unwinds, `b` is up and the rule correctly does nothing.
    ///
    /// Big Bento Modern is the measured case (BB16). `seek.maki` binds every one of its handlers to
    /// `seeker.ghost` and its `onLeftButtonUp` calls `hide()` on that same object — a duplicate
    /// `findObject("seeker.ghost")` where stock Winamp Modern's script reaches for a *readout* that
    /// does not exist in the layout, making the call a no-op on null there. The skin then mirrors
    /// `progressbar` and `player.seek.bg` to the seeker's visibility from `onSetVisible`, so one
    /// press-release took the whole seek bar with it and seeking stopped working until a track change.
    /// Restoring through `setVisible` rather than by writing the attribute is deliberate: the
    /// `onSetVisible(1)` it dispatches is what puts the trough and the fill back, so the skin's own
    /// mirror undoes itself.
    ///
    /// Defix runs the identical script and never reaches this: its `<Slider id="seeker">` stays
    /// visible, so the action still has a carrier. That is the difference the rule keys on — a
    /// capability of the layout, not the identity of the skin.
    private func settleStrandedControls() {
        guard !strandingCandidates.isEmpty else { return }
        let candidates = strandingCandidates
        strandingCandidates.removeAll()
        for id in candidates {
            guard let object = loadedSkin.runtime.graph.object(withID: id),
                  let action = Self.strandableAction(of: object),
                  !isVisible(object) else { continue }
            guard let layout = ancestor(of: object, type: "layout") else { continue }
            guard !layoutHasVisibleControl(for: action, in: layout, excluding: object) else { continue }
            _ = try? setVisible(object, true)
        }
    }

    /// Is any object under `layout` carrying `action` visible all the way up to the layout?
    private func layoutHasVisibleControl(for action: String, in layout: WasabiObject,
                                         excluding object: WasabiObject) -> Bool {
        var found = false
        func walk(_ node: WasabiObject, visibleSoFar: Bool) {
            if found { return }
            let visible = visibleSoFar && isVisible(node)
            if visible, node !== object, Self.strandableAction(of: node) == action {
                found = true
                return
            }
            // A hidden subtree can still contain the carrier the skin is *about* to reveal, but it is
            // not one today; recursing with `visible` false keeps that honest without losing the walk.
            for child in node.children { walk(child, visibleSoFar: visible) }
        }
        for child in layout.children { walk(child, visibleSoFar: true) }
        return found
    }

    private func isInvalid(_ object: WasabiObject) -> Bool {
        guard let imageID = object.attributes["image"] ?? object.attributes["bitmap"] else { return false }
        guard let definition = loadedSkin.runtime.resources.resolvedDefinition(identifier: imageID),
              definition.kind == "bitmap" else { return true }
        // Generated bitmaps (`file="$solid"`) carry no file and are perfectly valid.
        if definition.attributes["file"]?.hasPrefix("$") == true { return false }
        return definition.logicalFile == nil
    }

    /// `show` / `hide` / `toggle`, in one place: the attribute, the notification, and the host
    /// request a container needs, in the order Wasabi does them.
    private func setVisible(_ object: WasabiObject, _ visible: Bool) throws -> MakiValue {
        let changed = object.setAttribute("visible", value: visible ? "1" : "0")
        #if DEBUG
        if changed, ProcessInfo.processInfo.environment["WINAMP_MODERN_DEBUG_HOLDERS"] != nil {
            NSLog("WinampModern SETVISIBLE %@ -> %d by=%@", object.xmlID ?? object.typeName,
                  visible ? 1 : 0, MakiInterpreter.traceStack.last ?? "-")
        }
        #endif
        if visible { scriptClosedObjects.remove(object.stableID) }
        else { scriptClosedObjects.insert(object.stableID) }
        if changed, !visible, Self.strandableAction(of: object) != nil {
            strandingCandidates.insert(object.stableID)
        }
        if changed { noteGeometryChange() }
        notifyGraphDidMutate()
        if changed {
            _ = try dispatch(object: object, event: "onsetvisible", arguments: [.boolean(visible)])
        }
        requestWindow(for: object, visible: visible)
        return .null
    }

    /// Visible *as the user sees it*. For a container that is its window's state, which only the host
    /// knows; for anything else the graph attribute is the whole truth. `nil` from the host — the
    /// headless harness, or an id no window backs — falls back to the attribute.
    private func effectiveVisibility(of object: WasabiObject) -> Bool {
        // A layout answers for its window as its container does, and for the same reason: the window
        // is the thing that is actually on screen, and the host can close it (a dismissed
        // `autoclose` popup) without the graph attribute moving. Big Bento asks its search results'
        // *layout* whether it is open before re-showing it, so a stale `visible="1"` there left the
        // skin believing a window the user had dismissed was still up — and the next search filled a
        // list nobody could see (BB31).
        if Self.isWindowObject(object), let hosted = enclosingWindowID(of: object)
            .flatMap({ containerVisibilityQuery?($0) }) {
            return hosted
        }
        return isVisible(object)
    }

    /// The container id of the window this object belongs to, for the host queries that are answered
    /// per window rather than per object.
    private func enclosingWindowID(of object: WasabiObject) -> String? {
        let container = object.typeName.caseInsensitiveCompare("container") == .orderedSame
            ? object
            : Self.enclosingContainer(of: object)
        guard let id = container?.xmlID, !id.isEmpty else { return nil }
        return id
    }

    /// Active *as the window server sees it*: the container this object belongs to owns the
    /// keyboard.
    ///
    /// Winamp answers this per object, and winampmodern566's playlist asks it of two different ones —
    /// the content group and that container's `shade` layout — before it will act on `ctrl+w`. Both
    /// live in the same window, and the window is the only thing that can actually be focused, so
    /// walking up to the container and asking the host once answers both terms correctly.
    ///
    /// With no host installed (the headless harness) there is no focus to report and every object
    /// reads active, so a probe can still drive a handler that gates on it. In the app the host
    /// always answers.
    private func isActive(_ object: WasabiObject) -> Bool {
        guard let query = containerActiveQuery else { return true }
        var node: WasabiObject? = object
        while let current = node {
            if current.typeName.caseInsensitiveCompare("container") == .orderedSame,
               let id = current.xmlID, !id.isEmpty {
                return query(id) ?? false
            }
            node = current.parent
        }
        return false
    }

    private func isVisible(_ object: WasabiObject) -> Bool {
        let value = object.attributes["visible"]?.lowercased()
        return value != "0" && value != "false" && value != "no"
    }

    private func setTarget(_ key: String, object: WasabiObject, value: MakiValue) -> MakiValue {
        _ = object.setAttribute(key, value: String(value.integerValue))
        _ = object.setAttribute("goingtotarget", value: "1")
        return .null
    }

    private func targetTimerID(for objectID: WasabiObjectID) -> UInt64 {
        objectID.rawValue | 0x8000_0000_0000_0000
    }

    private func targetAttr(_ object: WasabiObject, _ key: String, fallback: String) -> Double {
        Double(object.attributes[key] ?? object.attributes[fallback] ?? "0") ?? 0
    }

    /// Push a *container's* `x`/`y`/`w`/`h` out to its window.
    ///
    /// Every other object's geometry is read back out of the graph when the scene is next drawn, so
    /// writing the attribute is the whole job. A container is not drawn: its size lives in the
    /// window and its position on the desktop, and both are the host's to set. `resize()` and the
    /// `setTargetX/Y/W/H` animation are the two ways a script asks for either, and Big Bento's
    /// notifier uses both — it measures its own text with `getAutoWidth`, resizes to fit, and then
    /// animates itself into the corner of the screen. Silently dropping these is why that toast came
    /// out at its declared 540 with the text clipped into the third of it the XML reserves for the
    /// album art it had already hidden (BB27).
    private func applyContainerGeometry(_ object: WasabiObject) {
        // A **layout** is its window as much as the container is — a `noparent` popup is placed and
        // sized by writing `x`/`y`/`w`/`h` on the layout, in screen coordinates the script builds with
        // `clientToScreenX/Y`. Big Bento's playlist search does exactly that before showing its
        // results (BB31); `resize()` on a layout already routed its size here, and `setXmlParam` of
        // the same four attributes now does too, position included.
        let target: WasabiObject?
        if object.typeName.caseInsensitiveCompare("container") == .orderedSame {
            target = object
        } else if object.typeName.caseInsensitiveCompare("layout") == .orderedSame {
            target = Self.enclosingContainer(of: object)
        } else {
            target = nil
        }
        guard let target else { return }
        if let width = Double(object.attributes["w"] ?? ""),
           let height = Double(object.attributes["h"] ?? ""), width > 0, height > 0 {
            layoutResizeRequested?(target.stableID, CGSize(width: width, height: height))
        }
        if let x = Double(object.attributes["x"] ?? ""), let y = Double(object.attributes["y"] ?? "") {
            containerMoveRequested?(target.stableID, CGPoint(x: x, y: y))
        }
    }

    private func startTargetAnimation(object: WasabiObject) {
        let id = object.stableID
        cancelTargetAnimation(objectID: id)

        let hasX = object.attributes["targetx"] != nil
        let hasY = object.attributes["targety"] != nil
        let hasW = object.attributes["targetw"] != nil
        let hasH = object.attributes["targeth"] != nil
        let hasA = object.attributes["targeta"] != nil

        let rawSpeed = Double(object.attributes["targetspeed"] ?? "0.5") ?? 0.5
        if rawSpeed <= 0 {
            if hasX { _ = object.setAttribute("x", value: object.attributes["targetx"]!) }
            if hasY { _ = object.setAttribute("y", value: object.attributes["targety"]!) }
            if hasW { _ = object.setAttribute("w", value: object.attributes["targetw"]!) }
            if hasH { _ = object.setAttribute("h", value: object.attributes["targeth"]!) }
            if hasA { _ = object.setAttribute("alpha", value: object.attributes["targeta"]!) }
            _ = object.setAttribute("goingtotarget", value: "0")
            applyContainerGeometry(object)
            notifyGraphDidMutate()
            _ = try? dispatch(object: object, event: "ontargetreached")
            return
        }
        let speed = min(1.0, rawSpeed)
        let cx = Double(object.attributes["x"] ?? "0") ?? 0
        let cy = Double(object.attributes["y"] ?? "0") ?? 0
        let cw = Double(object.attributes["w"] ?? "0") ?? 0
        let ch = Double(object.attributes["h"] ?? "0") ?? 0
        let ca = Double(object.attributes["alpha"] ?? "255") ?? 255
        let state = TargetAnimationState(
            currentX: cx, currentY: cy, currentW: cw, currentH: ch, currentAlpha: ca,
            targetX: hasX ? (Double(object.attributes["targetx"]!) ?? cx) : cx,
            targetY: hasY ? (Double(object.attributes["targety"]!) ?? cy) : cy,
            targetW: hasW ? (Double(object.attributes["targetw"]!) ?? cw) : cw,
            targetH: hasH ? (Double(object.attributes["targeth"]!) ?? ch) : ch,
            targetAlpha: hasA ? (Double(object.attributes["targeta"]!) ?? ca) : ca,
            startX: cx, startY: cy, startW: cw, startH: ch, startAlpha: ca,
            speed: speed,
            lastTick: ProcessInfo.processInfo.systemUptime,
            hasTargetX: hasX, hasTargetY: hasY, hasTargetW: hasW, hasTargetH: hasH, hasTargetA: hasA
        )

        if animationReached(state) {
            _ = object.setAttribute("goingtotarget", value: "0")
            notifyGraphDidMutate()
            _ = try? dispatch(object: object, event: "ontargetreached")
            return
        }

        _ = object.setAttribute("goingtotarget", value: "1")
        activeTargetAnimations[id] = state

        let timerID = targetTimerID(for: id)
        _ = try? timers.schedule(id: timerID, period: 1.0 / 60.0) { [weak self] in
            self?.tickTargetAnimation(objectID: id)
        }
    }

    /// Winamp applies `targetspeed` as an exponential ease factor per ~20 ms timer tick.
    /// Scale to real elapsed time so the animation looks the same at any frame rate.
    private static let wasabiTargetTickPeriod: Double = 0.020

    private func tickTargetAnimation(objectID: WasabiObjectID) {
        guard var state = activeTargetAnimations[objectID] else { return }
        guard let object = loadedSkin.runtime.graph.object(withID: objectID) else {
            cancelTargetAnimation(objectID: objectID)
            return
        }

        let now = ProcessInfo.processInfo.systemUptime
        let dt = max(0.001, now - state.lastTick)
        state.lastTick = now
        let factor = 1 - pow(1 - state.speed, dt / Self.wasabiTargetTickPeriod)

        func lerp(_ current: Double, _ target: Double) -> Double {
            current + (target - current) * factor
        }

        state.currentX = lerp(state.currentX, state.targetX)
        state.currentY = lerp(state.currentY, state.targetY)
        state.currentW = lerp(state.currentW, state.targetW)
        state.currentH = lerp(state.currentH, state.targetH)
        state.currentAlpha = lerp(state.currentAlpha, state.targetAlpha)

        if state.hasTargetX { _ = object.setAttribute("x", value: String(Int(state.currentX.rounded()))) }
        if state.hasTargetY { _ = object.setAttribute("y", value: String(Int(state.currentY.rounded()))) }
        if state.hasTargetW { _ = object.setAttribute("w", value: String(Int(state.currentW.rounded()))) }
        if state.hasTargetH { _ = object.setAttribute("h", value: String(Int(state.currentH.rounded()))) }
        if state.hasTargetA { _ = object.setAttribute("alpha", value: String(Int(state.currentAlpha.rounded()))) }

        if animationReached(state) {
            if state.hasTargetX { _ = object.setAttribute("x", value: String(Int(state.targetX))) }
            if state.hasTargetY { _ = object.setAttribute("y", value: String(Int(state.targetY))) }
            if state.hasTargetW { _ = object.setAttribute("w", value: String(Int(state.targetW))) }
            if state.hasTargetH { _ = object.setAttribute("h", value: String(Int(state.targetH))) }
            if state.hasTargetA { _ = object.setAttribute("alpha", value: String(Int(state.targetAlpha))) }
            activeTargetAnimations.removeValue(forKey: objectID)
            timers.cancel(id: targetTimerID(for: objectID))
            _ = object.setAttribute("goingtotarget", value: "0")
            applyContainerGeometry(object)
            notifyGraphDidMutate()
            _ = try? dispatch(object: object, event: "ontargetreached")
        } else {
            activeTargetAnimations[objectID] = state
            applyContainerGeometry(object)
            notifyGraphDidMutate()
        }
    }

    private func animationReached(_ state: TargetAnimationState) -> Bool {
        abs(state.currentX - state.targetX) < 0.5 &&
        abs(state.currentY - state.targetY) < 0.5 &&
        abs(state.currentW - state.targetW) < 0.5 &&
        abs(state.currentH - state.targetH) < 0.5 &&
        abs(state.currentAlpha - state.targetAlpha) < 0.5
    }

    private func cancelTargetAnimation(objectID: WasabiObjectID) {
        activeTargetAnimations.removeValue(forKey: objectID)
        timers.cancel(id: targetTimerID(for: objectID))
    }

    private func reverseTargetAnimation(object: WasabiObject) {
        let id = object.stableID
        if var state = activeTargetAnimations[id] {
            state.targetX = state.startX
            state.targetY = state.startY
            state.targetW = state.startW
            state.targetH = state.startH
            state.targetAlpha = state.startAlpha
            activeTargetAnimations[id] = state
        } else {
            startTargetAnimation(object: object)
        }
    }

    /// Bind the host-provided singletons a program declares but never assigns.
    ///
    /// `std.mi` declares `PlEdit` the same way it declares `System`: a global object the host owns
    /// and the script simply calls methods on. The compiler marks *both* with the variable record's
    /// `system` flag, and the parser used to read that flag as "this is the System object" — so every
    /// `PlEdit.getCurrentIndex()` in the corpus arrived as a call **on System**, and failed there as
    /// an unknown System method. The flag now only seeds the variable whose class is System's, and
    /// each other host singleton is bound here, by class.
    ///
    /// A variable declared with `PlEdit`'s class can only ever hold the one playlist editor, so it is
    /// bound unconditionally — which also corrects the parser's older guess for any archive that
    /// predates the class check there.
    private static func seedHostSingletons(in program: MakiProgram) {
        for variable in program.variables where variable.declaredKind == .object {
            switch variable.classGUID.map(canonicalGUID) {
            case MakiClassGUID.playlistEditor:
                variable.value = .object(MakiObjectReference(.playlistEditor))
            case MakiClassGUID.colorManager:
                variable.value = .object(MakiObjectReference(.colorManager))
            default:
                continue
            }
        }
    }

    /// Compiled MAKI stores class IDs as four little-endian 32-bit words.
    /// Normalize them to the compact string form used by std.mi.
    private static func canonicalGUID(_ raw: String) -> String { MakiClassGUID.canonical(raw) }

    private func unsupported(_ method: String, program: MakiProgram) -> WalFailure {
        unsupportedMethodCalls[method.lowercased(), default: 0] += 1
        // Traced with the calls that *did* work, because that is the line the reader is looking for:
        // an unimplemented method aborts its whole handler, so what a trace shows is a sequence that
        // simply stops, and the reason is otherwise only in a compatibility report taken later.
        if ProcessInfo.processInfo.environment["WINAMP_MODERN_CALL_TRACE"] != nil {
            print("CALL-TRACE \(method.lowercased())(…) -> UNSUPPORTED, handler aborts "
                  + "[\((program.source.path as NSString).lastPathComponent)]")
        }
        return WalFailure(WalDiagnostic(.unsupportedScriptCapability,
                                 "Winamp Modern runtime does not support method '\(method)'.",
                                 location: program.source))
    }

    func teardown() {
        guard !isTornDown else { return }
        // First, while the interpreter, the timers and the graph are all still alive: a script releases
        // its own objects here (`beat.m` deletes its VU timer, `CproTabButton.m` stops and deletes the
        // one it polls the button state with), and dispatched after teardown it would reach nothing.
        //
        // Not on the `deinit` path: the interpreter holds this runtime **weakly**, so by then the
        // dispatcher is already gone and every handler would execute nothing anyway — and running skin
        // bytecode from inside a deallocation is not something to attempt for a no-op.
        if !isDeinitializing { _ = try? dispatchSystem(event: "onscriptunloading") }
        graphDidMutate = nil
        popupPresenter = nil
        layoutSwitchRequested = nil
        layoutResizeRequested = nil
        uiScaleRequested = nil
        actionRequested = nil
        focusRequested = nil
        browserNavigationRequested = nil
        globalNavigationRequested = nil
        themeNamesRequested = nil
        activeThemeRequested = nil
        themeSwitchRequested = nil
        dispatchObserver = nil
        resolvedGeometryRequested = nil
        mousePositionInObjectSpaceRequested = nil
        geometryDidSettle = nil
        activeTargetAnimations.removeAll()
        timers.teardown()
        interpreter.teardown()
        host.endVisualizationConsumption()
        programs.removeAll()
        popupCommands.removeAll()
        pendingRuntimeGroups.removeAll()
        dynamicObjects.removeAll()
        activeLayoutByContainer.removeAll()
        metrics.teardown()
        isTornDown = true
    }

    /// Set only while `deinit` is unwinding, so `teardown` knows not to run skin bytecode there.
    private var isDeinitializing = false

    deinit {
        isDeinitializing = true
        teardown()
    }
}

private final class DummyMakiDispatcher: MakiMethodDispatching {
    static let shared = DummyMakiDispatcher()
    func signature(for method: String, classGUID: String?) -> MakiMethodSignature? { nil }
    func invoke(method: String, on object: MakiObjectReference, arguments: [MakiValue],
                program: MakiProgram) throws -> MakiValue { .null }
    func makeObject(classGUID: String, program: MakiProgram) throws -> MakiObjectReference {
        MakiObjectReference(.system)
    }
}
