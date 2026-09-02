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
    enum DynamicRole {
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
        /// An `XmlDoc` the script asked to `load`, carrying the logical path the load resolved to —
        /// `nil` when the file is not in the VFS, which is what `exists()` answers on. ClassicPro
        /// reads the optional `ClassicPro.xml` extras (songticker antialiasing, custom beat-vis
        /// names) through one, always behind `if (myDoc.exists())`; Big Bento Modern's Web Reader
        /// runs the *callback* parser over `scripts/reader/source/reader_providers.xml` to build its
        /// provider drop-down. See `parserStart(…)`.
        case xmlDocument(logicalPath: String?)
        /// A `WinampConfigGroup` — one section of Winamp's own preferences, addressed by GUID.
        /// ClassicPro reads exactly one value from one (`eq.m` asks whether the EQ uses classic or
        /// ISO frequencies before it labels the bands).
        case configGroup(section: String)
        /// A `GammaSet` — one named colour theme, handed back by `ColorMgr.getGammaSet(name)` and
        /// carrying only that name until `apply()` asks for it. Unlike `Map`/`Region`/`XmlDoc` this
        /// role is settled at *creation*, because the object never comes from a bare `new`.
        case gammaSet(name: String)
        /// A `Color` — what `ColorMgr.getColor(name)` answers with, resolved once at creation.
        /// Settled at creation for the same reason `gammaSet` is: it never comes from a bare `new`.
        case color(red: Int32, green: Int32, blue: Int32)
    }

    /// Ceiling on one `List`'s length. ClassicPro's longest is its tab order (a dozen entries); the
    /// cap is what stops a script appending in a loop from growing without bound.
    static let maximumListItems = 4_096

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
    internal(set) var unsupportedMethodCalls: [String: Int] = [:]
    /// Diagnostics from script events that aborted without stopping the rest of the skin. Capped:
    /// a handler that fails on a repeating event (a timer or mouse move) would otherwise accumulate
    /// forever. The report de-duplicates anyway, so the cap costs no distinct information.
    private(set) var scriptFailures: [WalDiagnostic] = []
    private static let maximumRecordedScriptFailures = 512

    /// The component kinds a holder in this skin is actually carrying, for `isNamedWindowVisible`.
    ///
    /// Derived from the graph rather than plumbed in: the claim is a `hold` write on the holder
    /// (`WinampModernAvailableComponents`), and reading it back keeps one source of truth for "what
    /// is in this box". Computed once — the claim runs before the scripts start, and a skin cannot
    /// stamp a holder for itself.
    private var cachedClaimedComponentKinds: Set<WinampModernComponentKind>?
    var claimedComponentKinds: Set<WinampModernComponentKind> {
        if let cachedClaimedComponentKinds { return cachedClaimedComponentKinds }
        var kinds: Set<WinampModernComponentKind> = []
        for object in loadedSkin.runtime.graph.allObjectsUnordered
        where WinampModernComponentRegistry.isHolderElement(object.typeName) {
            guard let hold = object.attributes["hold"],
                  let kind = WinampModernComponentRegistry.kind(for: hold),
                  WinampModernAvailableComponents.offered.contains(kind) else { continue }
            kinds.insert(kind)
        }
        cachedClaimedComponentKinds = kinds
        return kinds
    }

    /// Whether a holder in this skin is carrying that component — the window layer's read of the
    /// same claim `isNamedWindowVisible` answers from.
    func hasClaimedComponent(_ kind: WinampModernComponentKind) -> Bool {
        claimedComponentKinds.contains(kind)
    }

    /// Drop the cached set after a claim changed mid-session (the user's per-skin toggle). Without
    /// this the skin's gate would keep reading the answer from load time, and `isNamedWindowVisible`
    /// would disagree with the `hold` param it is paired with — which is exactly the split that kept
    /// the strip hidden before either half existed.
    func invalidateClaimedComponents() {
        cachedClaimedComponentKinds = nil
    }

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
    ///
    /// The third argument says the point is **pinned** to another window rather than chosen: it is
    /// the desktop origin of a window the script just read, so it must be honoured as-is. Placing a
    /// window is clamped to the visible frame; mirroring one is not, or a pair that the host has
    /// already let sit partly off-screen comes apart at the edge (B69).
    var containerMoveRequested: ((WasabiObjectID, CGPoint, Bool) -> Void)?
    /// `layout.setScale(f)` — the skin asking for the **whole UI** at a different size. Defix's
    /// configurator offers seven of them (100–300%) and every one of its five window scripts calls
    /// this on its own layout from the same stored `SCALING`, so it is one global request repeated,
    /// not five per-window scales. NullPlayer answers it with its own **UI Size**: a `.wal` scene is
    /// always laid out on the skin's pixel grid and the view scales at the drawing and input
    /// boundaries (Phase 10), so a second, layout-local scale would be a rival to that one and the
    /// two would fight over every window's size. `nil` in the harness, and while a skin is still
    /// loading the host defers the request rather than resizing windows that do not exist yet.
    var uiScaleRequested: ((CGFloat) -> Void)?
    /// The whole display containing the skin's player window, in logical screen points. MAKI's
    /// monitor methods are global (there is no GUI-object receiver from which to find a window), so
    /// the window layer supplies the screen explicitly. AppKit points are intentional: converting
    /// through `backingScaleFactor` would leak Retina pixels into script geometry, while every other
    /// desktop coordinate the runtime exchanges with the window layer is expressed in points.
    var monitorSizeRequested: (() -> CGSize?)?
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
    /// Where a container's window actually sits on the desktop, for `getLeft()`/`getTop()` on a
    /// window object. The exact inverse of the point `containerMoveRequested` accepts — Winamp's
    /// screen space, top-left origin — so a script that reads its own position and writes it back
    /// unchanged leaves the window where it is. `nil` (the headless harness, an id no window backs)
    /// falls back to the graph attribute.
    var containerOriginQuery: ((String) -> CGPoint?)?
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
    static let maximumRegisteredSettings = 512
    /// Display names for the sections above, learned from `Config.newItem(name, guid)`. `getItem`
    /// and `getItemByGuid` do not name anything new — they address an item that already exists.
    var configItemNames: [String: String] = [:]

    private var nextPopupID: UInt64 = 1
    var popupCommands: [UInt64: [PopupEntry]] = [:]
    var dynamicObjects: [UInt64: DynamicObjectState] = [:]
    var activeTargetAnimations: [WasabiObjectID: TargetAnimationState] = [:]
    var activeLayoutByContainer: [WasabiObjectID: WasabiObjectID] = [:]
    let preferenceNamespace: String

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
    lazy var metrics = WasabiTextMetrics(loadedSkin: loadedSkin)
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

    /// A host time in seconds as the milliseconds Winamp's script API reports — the single place the
    /// conversion happens, so `getPosition`, `getPlayItemLength` and the `length` metadata key cannot
    /// drift apart. Clamped, because a skin's Int is 32-bit and a stream reports no duration at all.
    static func milliseconds(_ seconds: TimeInterval) -> Int32 {
        guard seconds.isFinite, seconds > 0 else { return 0 }
        return Int32(clamping: Int64((seconds * 1000).rounded()))
    }

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
        // Recorded on the skin runtime, which the scene renderers can see; see `hasStartedScripts`.
        defer { loadedSkin.runtime.markScriptsStarted() }
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
        dispatchColorManagerLoaded()
        dispatchColdStartLayoutShown()
    }

    /// `System.onShowLayout(<layout>)` for the window that comes up with the skin.
    ///
    /// Winamp shows the main player's layout as the last step of loading a skin, and a script that
    /// lays the window out from that event has no other signal that it may start. Nothing here
    /// dispatched it at all, so every such script was dead.
    ///
    /// ClassicPro engine "two" is the measured case. `two/scripts/layout.m` places `two.screen` —
    /// the entire info + transport band — only from `fullScreen()`, whose sole cold-start caller is
    /// `System.onShowLayout`, commented in the engine as *"On cold start"*; the one line in
    /// `buildSkin()` that would otherwise set it is commented out. Without the event `two.screen`
    /// kept its declared default of `y=0`: the song title and transport row drew on top of the
    /// titlebar, and a 28px dead strip opened above the SUI, which is `cpro.sui`'s hard-coded
    /// `y="98"` — titlebar 28 + info 40 + playback 30 — with nothing beneath it.
    ///
    /// Only the **main player** is announced. Every other container opens on request, and telling a
    /// skin that a window it has not been asked to show is on screen is a worse answer than silence.
    private func dispatchColdStartLayoutShown() {
        guard let main = loadedSkin.runtime.graph.roots.first(where: {
            $0.typeName.caseInsensitiveCompare("container") == .orderedSame &&
            $0.xmlID?.caseInsensitiveCompare("main") == .orderedSame
        }),
              let layoutID = activeLayoutByContainer[main.stableID],
              let layout = loadedSkin.runtime.graph.object(withID: layoutID) else { return }
        _ = try? dispatchSystem(event: "onshowlayout", arguments: [objectValue(layout)])
    }

    /// `ColorMgr.onLoaded` — Winamp's "the skin has finished loading" callback, and the one event a
    /// script can bind to that fires *after* every `onScriptLoaded` in the skin has run.
    ///
    /// It goes last for the reason ClassicPro needs it last: its three `cProLoaded()` bodies call
    /// actions on `widgetsManager.maki`, which is a **skin-level** script, so anything dispatching
    /// this earlier would reach a manager whose own `onScriptLoaded` had not yet found its list.
    /// Three separate scripts register a widget place from here (`CproTabs` "Main Area",
    /// `drawer` "Drawer Area", `CentroSUI` "Side Area"), which is the 3 its `NUM_WIDGET_PLACES`
    /// counts — so all three have to be dispatched, not just the one whose window is open.
    ///
    /// A failure in one is already contained by `dispatch`, which records it and runs the rest.
    private func dispatchColorManagerLoaded() {
        _ = try? dispatch(target: MakiObjectReference(.colorManager), event: "onloaded", arguments: [])
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

    /// `<CustomObject groupid="…">` — a holder whose **content is named by an attribute**.
    ///
    /// Unlike a `<group id="x">`, which instantiates `x` once at parse time, a custom object is empty
    /// until a script names a groupdef for it, and it swaps that content whenever the name changes.
    /// ClassicPro's widget panes are the measured case: `<CustomObject id="widget.holder"
    /// fitparent="1"/>` sits in the SUI's widget tab, and choosing a widget is one line —
    /// `widgetHolder.setXmlParam("groupid", ids)` — after which the pane *is* that widget.
    ///
    /// No skin in the corpus declares `groupid` in markup, so this runtime write is the whole path.
    ///
    /// The old content is discarded rather than hidden: a custom object holds one thing at a time,
    /// and leaving the previous widget in the tree keeps its scripts and timers running behind the
    /// one on screen.
    func applyCustomObjectGroup(_ key: String, value: String, to object: WasabiObject) {
        guard key.caseInsensitiveCompare("groupid") == .orderedSame,
              (object.typeName.lowercased().components(separatedBy: ":").last ?? "") == "customobject"
        else { return }
        // `children` is a value-typed array, so the loop iterates the snapshot it took even though
        // `discardSubtree` empties the property underneath it.
        for child in object.children { loadedSkin.runtime.graph.discardSubtree(child) }
        guard !value.isEmpty, let instantiate = loadedSkin.runtime.instantiateGroup,
              let child = try? instantiate(value, object) else { return }
        // A custom object's content **fills it** — the object is the box, the named group is what
        // goes in it. `instantiateGroup` builds a bare `<group id="…">`, which declares no geometry
        // and so resolves to 0x0 (measured: `centro.widgets.nowplaying` laid out at
        // `frame=(8.0, 132.0, 0.0, 0.0)` inside a 280x176 holder, drawing nothing at all while its
        // script ran perfectly). `System.newGroup`'s path deliberately keeps the bare node — there
        // the script places the group itself with `init(parent)` — so the fill belongs here.
        _ = child.setAttribute("fitparent", value: "1")
        // Started now, for the reason `instantiate` starts its own: the group is already parented,
        // and the caller's next move is to configure what it just put on screen.
        try? startScripts(addedBeneath: child)
        noteGeometryChange()
        notifyGraphDidMutate()
    }

    /// A runtime `setXmlParam(key, value)` is also an `onSetXuiParam(key, value)` to the scripts the
    /// written object owns — that is how Wasabi delivers a param a *script* sets, as opposed to one
    /// the markup declares (`deliverXUIParams`, which runs once at load and only for XUI tags).
    ///
    /// Scoped to the target's own programs, exactly as the load-time delivery is, so an object with
    /// no script of its own is untouched and nothing else in the skin hears it.
    ///
    /// ClassicPro's Widgets Manager is the measured case: `widgetsManager.maki` instantiates a
    /// `widgets.manager.listitem` per widget and then *only* writes params on it —
    /// `g.setXmlParam("widgetname", …)`, `"widgetauthor"`, `"widgetversion"`, `"widgetpos_main"` and
    /// the rest — while `widgetManItem.maki`'s whole body is one `system.onSetXuiParam` switch. With
    /// the write silent, every row drew with the groupdef's placeholder text and dead buttons.
    func deliverRuntimeXUIParam(_ key: String, value: String, to object: WasabiObject) {
        guard !object.scriptBindings.isEmpty else { return }
        let owned = programs.filter { $0.ownerID == object.stableID }
        guard !owned.isEmpty else { return }
        _ = try? dispatch(target: MakiObjectReference(.system), event: "onsetxuiparam",
                          arguments: [.string(key), .string(value)], in: owned)
    }

    /// `getAutoWidth()` — the width an object wants to be. A group delegates to the object named by
    /// its `autowidthsource` attribute, which is how the menubar sizes itself: each `menugroup.*`
    /// points at the layer holding its rendered label bitmap, and `menualign.maki` reads these
    /// widths to lay the menus out left-to-right. Returning a text estimate for those groups (the
    /// previous behaviour) left every menu at width 0, stacked on the same x.
    func autoWidth(of object: WasabiObject) -> Int32 {
        if let sourceID = object.attributes["autowidthsource"],
           let source = descendant(of: object, xmlID: sourceID), source !== object {
            // The source's width is not the group's: it is what the source resolves to *inside*
            // the group, so a source that keeps room beside itself needs the group to be that much
            // wider (B68). Shared with the renderer so a script's measurement and the drawn box stay
            // one number. Only applied to a real measurement — a source that answers 0 answers 0.
            let width = autoWidth(of: source)
            guard width > 0 else { return width }
            let inset = WasabiGeometrySpec.autoWidthInset(of: source.attributes)
            return Int32(clamping: Int(width) + Int(inset.rounded(.up)))
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
    func autoHeight(of object: WasabiObject) -> Int32 {
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
    func animationFrameCount(of object: WasabiObject) -> Int {
        if let raw = object.attributes["frames"], let count = Int(raw), count > 0 { return count }
        guard let imageID = object.attributes["image"], let sheet = bitmapSize(identifier: imageID) else { return 1 }
        let frameWidth = Int(object.attributes["framewidth"] ?? object.attributes["w"] ?? "") ?? Int(sheet.width)
        let frameHeight = Int(object.attributes["frameheight"] ?? object.attributes["h"] ?? "") ?? Int(sheet.height)
        guard frameWidth > 0, frameHeight > 0 else { return 1 }
        return max(1, (Int(sheet.width) / frameWidth) * (Int(sheet.height) / frameHeight))
    }

    func animationFrame(of object: WasabiObject) -> Int {
        WasabiAnimation.state(of: object, frameCount: animationFrameCount(of: object)).frame
    }

    /// Sample a `Map`'s bitmap at a point in its own pixel space. Decoded images are cached, bounded
    /// by `maximumCachedMaps`; the bitmap itself passed the loader's dimension limits.
    func mapPixel(bitmapID: String, source: WalSourceLocation, x: Int, y: Int)
        -> (red: UInt8, green: UInt8, blue: UInt8, alpha: UInt8, inBounds: Bool) {
        guard let image = mapImage(bitmapID: bitmapID, source: source) else { return (0, 0, 0, 0, false) }
        let crop = mapCrop(bitmapID: bitmapID, image: image)
        guard x >= 0, y >= 0, x < crop.width, y < crop.height else { return (0, 0, 0, 0, false) }
        let bitmap = WasabiBitmap(image: image, width: image.width, height: image.height, cost: 0)
        guard let pixel = bitmap.pixel(at: CGPoint(x: crop.x + x, y: crop.y + y))
        else { return (0, 0, 0, 0, false) }
        return (pixel.red, pixel.green, pixel.blue, pixel.alpha, true)
    }

    /// The region of the decoded file a `Map` actually covers.
    ///
    /// `loadMap` takes a **bitmap id** as well as a path, and a `<bitmap>` is routinely a *slice* of a
    /// shared sheet: `<bitmap id="window.titlebar.menu.1" file="buttons.png" x="0" y="87" w="10"
    /// h="21"/>`. A map of that id is 10x21 starting at (0, 87) — pixel (0, 0) of the map is pixel
    /// (0, 87) of the file — and sampling the file's own origin instead reads whatever art happens to
    /// sit in the sheet's top-left corner.
    ///
    /// Measured, and the whole of the cPro "pink menu bar": ClassicPro's `mainmenu.maki` opens with a
    /// self-check for a skin that never cut its menu artwork —
    ///
    /// ```maki
    /// temp.loadMap("window.titlebar.menu.1");
    /// if (temp.getARGBValue(0,0,3) != 0)                        // not fully transparent
    ///   if (temp.getARGBValue(0,0,2)==255 && temp.getARGBValue(0,0,1)==0
    ///       && temp.getARGBValue(0,0,0)==128) {                 // the template's (255,0,128) filler
    ///     myGroup.hide(); disableMenu = true; bg_title.show();  // no menu bar; centred title instead
    ///   }
    /// ```
    ///
    /// — so the engine hides its own menu bar and shows a plain title whenever the slice is filler.
    /// Reading (0, 0) of `buttons.png` gave it a transport button, the test never fired, and four cPro
    /// skins drew five magenta boxes across the titlebar that Winamp never shows.
    func mapCrop(bitmapID: String, image: CGImage) -> (x: Int, y: Int, width: Int, height: Int) {
        let whole = (x: 0, y: 0, width: image.width, height: image.height)
        guard let definition = loadedSkin.runtime.resources.resolvedDefinition(identifier: bitmapID),
              definition.kind == "bitmap" else { return whole }
        let number: (String) -> Int? = { definition.attributes[$0].flatMap { Int($0) } }
        // A `<bitmap>` with no `x`/`y`/`w`/`h` is the whole file, which is the common case and the one
        // the path form always takes.
        guard number("x") != nil || number("y") != nil
                || number("w") != nil || number("h") != nil else { return whole }
        let x = min(max(0, number("x") ?? 0), image.width)
        let y = min(max(0, number("y") ?? 0), image.height)
        return (x: x, y: y,
                width: min(number("w") ?? (image.width - x), image.width - x),
                height: min(number("h") ?? (image.height - y), image.height - y))
    }

    func mapImage(bitmapID: String, source scriptSource: WalSourceLocation) -> CGImage? {
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
    func mapLogicalPath(bitmapID: String, source scriptSource: WalSourceLocation) -> String? {
        if let definition = loadedSkin.runtime.resources.resolvedDefinition(identifier: bitmapID),
           definition.kind == "bitmap", let path = definition.logicalFile,
           (try? loadedSkin.vfs.data(at: path, location: definition.source)) != nil {
            return path
        }
        // The path form is relative to the **skin**, not to the script that called it — a `.wal`
        // engine's scripts sit in their own mount and read the *skin's* artwork by bare filename.
        // ClassicPro's `player.maki` sizes the Winamp bolt from `buttons.png` and only gives that
        // button an `image` when the answer is 332 wide; resolved beside the script the file was
        // never found, `getWidth()` answered 0, and the logo stayed invisible until the pointer was
        // over it, because `hoverImage` is the only artwork its markup declares.
        for base in [scriptSource.path, loadedSkin.vfs.skinRoot.map { $0 + "/skin.xml" }] {
            guard let base,
                  let resolved = try? loadedSkin.vfs.resolve(bitmapID, relativeTo: base,
                                                             location: scriptSource),
                  (try? loadedSkin.vfs.data(at: resolved.logicalPath, location: scriptSource)) != nil
            else { continue }
            return resolved.logicalPath
        }
        return nil
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
    var pendingRuntimeGroups: [WasabiObject] = []

    /// Start the scripts of a pending runtime group, if `object` is one (or contains one — a script may
    /// `init` an ancestor of the group it created).
    func startPendingScripts(for object: WasabiObject) throws {
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

    func startScripts(addedBeneath root: WasabiObject) throws {
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
    var lastDispatchedText: [WasabiObjectID: String] = [:]

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
    func requestWindow(for object: WasabiObject, visible: Bool) {
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

    /// Where the window backing this container or layout sits on the desktop, in Winamp's screen
    /// space, or `nil` when no host has answered (the headless harness, an id no window backs).
    func windowOrigin(of object: WasabiObject) -> CGPoint? {
        guard Self.isWindowObject(object) else { return nil }
        return enclosingWindowID(of: object).flatMap { containerOriginQuery?($0) }
    }

    /// The last position a script read off a **window object**, with the desktop origin that same
    /// object actually sits at. `reported` is what `getLeft()`/`getTop()` answered — the canvas
    /// origin for a layout, already the desktop origin for a container — so the pair is what
    /// recognises those coordinates being handed straight back to `resize()` on *another* window.
    /// See `borrowedWindowOrigin`.
    private var lastWindowOriginRead: (objectID: WasabiObjectID, reported: CGPoint, desktop: CGPoint)?

    /// Remember a window object's position read, for `borrowedWindowOrigin` to recognise.
    func noteWindowOriginRead(of object: WasabiObject) {
        guard Self.isWindowObject(object), let desktop = windowOrigin(of: object) else { return }
        lastWindowOriginRead = (object.stableID, reportedOrigin(of: object), desktop)
    }

    /// **One window placed at another window's position** — the desktop origin a `resize()` is
    /// really asking for, or `nil` when it is not that idiom.
    ///
    /// A layout answers `getLeft()`/`getTop()` in its own canvas space (0), while the `x`/`y` a
    /// `resize()` writes are pushed to the desktop. B61 fixed the *self* round trip
    /// (`me.resize(me.getLeft(), …)`) by recognising it and not moving. The other half of the same
    /// asymmetry is the *cross-window* round trip: Itemskin's window chrome is a second, dynamic
    /// container per component window, and every frame script keeps it on top of its content window
    /// with `chrome.resize(content.getLeft(), content.getTop(), content.getWidth(),
    /// content.getHeight())`. Both sides are layouts, so both read 0, and the move was suppressed as
    /// a no-op — the chrome stayed wherever the tiler had parked it while the content window sat
    /// somewhere else on screen (B69).
    ///
    /// So the coordinates are re-expressed in the space the *reader* was in: only when they are the
    /// exact pair another window object just reported, and only when that window is not this one.
    /// A value the script did not read stays a plain move, as it does for B61.
    func borrowedWindowOrigin(matching requested: CGPoint,
                                      writtenOn object: WasabiObject) -> CGPoint? {
        guard Self.isWindowObject(object), let read = lastWindowOriginRead,
              read.objectID != object.stableID,
              Int(requested.x.rounded()) == Int(read.reported.x.rounded()),
              Int(requested.y.rounded()) == Int(read.reported.y.rounded())
        else { return nil }
        // Consumed: each of these writes is preceded by its own pair of reads, so a stale record
        // must not be able to pin a later write that only happens to name the same coordinates.
        lastWindowOriginRead = nil
        return read.desktop
    }

    /// Exactly what `getLeft()`/`getTop()` would answer for this object right now, in whatever space
    /// they answer in — the host's desktop origin for a container, the layout's own canvas origin
    /// (usually 0) for a layout. Used to recognise a write that is only handing back what was just
    /// read; see `applyContainerGeometry`.
    func reportedOrigin(of object: WasabiObject) -> CGPoint {
        if Self.isWindowObject(object) {
            if object.typeName.caseInsensitiveCompare("container") == .orderedSame,
               let origin = windowOrigin(of: object) {
                return origin
            }
            if let x = Double(object.attributes["x"] ?? ""), let y = Double(object.attributes["y"] ?? "") {
                return CGPoint(x: x, y: y)
            }
        }
        return CGPoint(x: Double(dimension(resolvedFrame(of: object)?.minX, declared: object.geometry.x)),
                       y: Double(dimension(resolvedFrame(of: object)?.minY, declared: object.geometry.y)))
    }

    /// The `<container>` an object lives in, or nil for one that is not inside a window.
    static func enclosingContainer(of object: WasabiObject) -> WasabiObject? {
        var node: WasabiObject? = object.parent
        while let current = node {
            if current.typeName.caseInsensitiveCompare("container") == .orderedSame { return current }
            node = current.parent
        }
        return nil
    }

    /// A slider position held inside the `low…high` the object declares. Untouched when it declares
    /// neither, so nothing that never stated a range changes behaviour.
    static func clampedSliderPosition(_ value: Int32, of object: WasabiObject) -> Int32 {
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
    /// Click a `<Wasabi:CheckBox radioid="…">`: this one goes on and the rest of its set goes off
    /// (B66).
    ///
    /// A radio is not a toggle and must not be flipped like one — clicking the member that is already
    /// on leaves it on, which is the difference between "choose Classic" and "choose nothing". Styx's
    /// four preference pairs are all this shape, and its scripts read the choice back from
    /// `onToggle`, so every member that *changes* has to be told, not just the one clicked.
    ///
    /// The set is looked up from the top of the object's own tree: `radioid` is a flat name shared
    /// across whatever groups the skin happens to have nested, and Styx's pairs live in two different
    /// content groups of the same window.
    @discardableResult
    func selectRadioMember(_ object: WasabiObject) -> Bool {
        guard WasabiFormWidgets.kind(of: object) == .checkBox,
              let radio = WasabiFormWidgets.radioIdentifier(of: object) else { return false }
        var root = object
        while let parent = root.parent { root = parent }
        var members: [WasabiObject] = []
        func collect(_ node: WasabiObject) {
            if WasabiFormWidgets.radioIdentifier(of: node) == radio,
               WasabiFormWidgets.kind(of: node) == .checkBox {
                members.append(node)
            }
            node.children.forEach(collect)
        }
        collect(root)
        for member in members {
            let wanted = member === object
            guard (member.attributes["activated"] == "1") != wanted else { continue }
            setActivated(member, wanted)
            _ = try? dispatch(object: member, event: "ontoggle", arguments: [.boolean(wanted)])
            notifyActivated(member, activated: wanted)
        }
        return true
    }

    @discardableResult
    func toggleActivation(of object: WasabiObject) -> Bool {
        let type = object.typeName.lowercased()
        guard type == "togglebutton" || type == "nstatesbutton",
              Self.configBinding(of: object) == nil else { return false }
        // An `nstatesbutton` is a togglebutton that counts: a click advances it to the next state
        // and wraps, and `getCurCfgVal()` is how its script reads the position it landed on.
        // ClassicPro's mute is one of these with no binding — `mute_but.onToggle` is the whole of
        // its behaviour (save the volume, set it to zero, and back) and nothing was ever flipping
        // it, so the button was inert however completely the engine implemented it.
        let states = type == "nstatesbutton" ? max(1, Int(object.attributes["nstates"] ?? "") ?? 2) : 2
        let previous = Int(object.attributes["value"] ?? "") ?? (object.attributes["activated"] == "1" ? 1 : 0)
        let state = (max(0, previous) + 1) % states
        _ = object.setAttribute("value", value: String(state))
        let activated = state != 0
        _ = object.setAttribute("activated", value: activated ? "1" : "0")
        notifyObjectDidMutate(object)
        // The state is flipped *before* the notification, because that is what the handler reads:
        // multipass's `onToggle` asks the button `getActivated()` rather than trusting its argument.
        _ = try? dispatch(object: object, event: "ontoggle", arguments: [.boolean(activated)])
        notifyActivated(object, activated: activated)
        return true
    }

    /// Write a button's activation, keeping an `nstatesbutton`'s counted position in step with it.
    ///
    /// The two are one state, spelled twice: `activated` is what `getActivated()` and a togglebutton's
    /// `activeimage` read, `value` is the state index the artwork is cut in and what `getCurCfgVal()`
    /// answers. ClassicPro restores a persisted mute with `setActivated(true)` at startup, so without
    /// this the lamp came up lit while the button still counted itself as sitting on state 0.
    func setActivated(_ object: WasabiObject, _ activated: Bool) {
        _ = object.setAttribute("activated", value: activated ? "1" : "0")
        if object.typeName.caseInsensitiveCompare("nstatesbutton") == .orderedSame {
            _ = object.setAttribute("value", value: activated ? "1" : "0")
        }
        notifyObjectDidMutate(object)
    }

    /// `onActivate(int activated)` — Wasabi raises it whenever a button's activation changes,
    /// whoever changed it, and it is separate from `onToggle`: skins hang their *indicator* off this
    /// one. mmd3's three lamps and the three words in its display are `setAlpha(activated * 255)`
    /// from nothing else, so with no dispatch site at all no `.wal` skin could show a toggle's state.
    func notifyActivated(_ object: WasabiObject, activated: Bool) {
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

    /// The current value of a registered setting addressed the way `cfgattrib` addresses it, or nil
    /// when the skin registered no such attribute. Lets the renderer read a setting that no object in
    /// the scene carries a binding for — Big Bento Modern's two *File Info Components* check boxes
    /// live in its config window, which is closed while the panes they govern are on screen (BB9).
    func configAttributeValue(section: String, key: String) -> String? {
        guard let setting = registeredSettings.first(where: {
            $0.section.caseInsensitiveCompare(section) == .orderedSame &&
            $0.name.caseInsensitiveCompare(key) == .orderedSame
        }) else { return nil }
        return configAttributeValue(setting)
    }

    /// The current value of a registered setting, straight from the skin's own configuration.
    func configAttributeValue(_ setting: RegisteredSetting) -> String {
        loadedSkin.configuration.string(section: setting.section, key: setting.name,
                                        default: setting.defaultValue)
    }

    func recordRegisteredSetting(section: String, name: String, defaultValue: String) {
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

    func noteGeometryChange() {
        geometryMayHaveChanged = true
        // A mutation made *outside* any event (the host, or a direct call) has no event to unwind, so
        // it settles at once. Inside one it waits: a handler that moves five things in a row should
        // produce one round of `onResize`, not five.
        if eventsBeingDispatched.isEmpty { settleGeometryIfNeeded() }
    }

    /// `setXmlParam` keys that can move an object or take it out of the layout. Everything else a
    /// script writes (an image swap, a tooltip, a colour) leaves every frame where it was.
    static let geometryKeys: Set<String> = [
        "x", "y", "w", "h", "relatx", "relaty", "relatw", "relath",
        "visible", "fitparent", "position", "sysregion"
    ]

    /// `setXmlParam` keys whose value names a resource rather than being a value in itself.
    static let imageKeys: Set<String> = [
        "image", "bitmap", "background", "downimage", "hoverimage", "activeimage",
        "thumb", "downthumb", "hoverthumb", "notfoundimage"
    ]

    /// Does this identifier name a resource the skin actually registered? `background` is written
    /// with a colour id as well as a bitmap one, so the question is registration, not kind.
    func resolvesToResource(_ identifier: String) -> Bool {
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
    /// (Its declaration follows `dispatchWindowMove` below.)

    /// The **window** moved on the desktop — Wasabi's `onMove()`, which takes no arguments and is
    /// addressed at the container and its active layout.
    ///
    /// A resize is a change inside the scene and every object hears it; a move is not, because
    /// nothing inside the window changed position relative to anything else. Only the window objects
    /// are told. Itemskin is what needs it: each of its component windows is drawn by a *second*,
    /// dynamic container holding the frame artwork, and `onMove` on the frame's layout is how the
    /// content window is pulled along when the user drags the frame (B69).
    @discardableResult
    func dispatchWindowMove(container: WasabiObject, layout: WasabiObject) -> Int {
        var dispatched = 0
        for object in (container === layout ? [container] : [container, layout]) {
            guard hasBinding(for: object, event: "onmove") else { continue }
            if (try? dispatch(object: object, event: "onmove")) != nil { dispatched += 1 }
        }
        return dispatched
    }

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
    func dispatch(target: MakiObjectReference, event: String,
                          arguments: [MakiValue], in subset: [MakiProgram]? = nil) throws -> Int {
        var ignored: MakiValue?
        return try dispatch(target: target, event: event, arguments: arguments, in: subset,
                            answer: &ignored, stoppingAtFirstAnswer: false)
    }

    func dispatch(target: MakiObjectReference, event: String, arguments: [MakiValue],
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
    static let tracesLayerFX = ProcessInfo.processInfo.environment["WINAMP_MODERN_FX_TRACE"] != nil

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

    func requestRepaint(for object: WasabiObject? = nil) {
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
    func notifyGraphDidMutate() {
        graphDidMutate?()
        notifyAuxiliaryViews(of: nil)
    }

    func notifyObjectDidMutate(_ object: WasabiObject) {
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
    func invokeLayerFX(method: String, object: WasabiObject,
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
        // Arity pinned by ClassicPro's own `extendedbuttons.m`, which ships its source beside the
        // compiled program: `PlEdit.enqueueFile(enqFile)`, one string.
        "enqueuefile": .init(argumentCount: 1, returnKind: .null),
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
        "explorefile": .init(argumentCount: 1, returnKind: .null),
        "openfile": .init(argumentCount: 2, returnKind: .null),
        "findfiles": .init(argumentCount: 3, returnKind: .integer),
        // Arity settled off the call sites (`RENDER_DISASM=playFile`): T800's
        // `quicksongpick.maki` emits `op1(v0) op1(v44) op112(playfile)` — receiver, one push —
        // and Big Bento's `progbutton.maki` the same shape with the path built by a subroutine.
        // The name is unique across the installed corpus and belongs to `System` at both sites.
        "playfile": .init(argumentCount: 1, returnKind: .null),
    ]

    func signature(for method: String, classGUID: String?) -> MakiMethodSignature? {
        // Both of these were recomputed per test below — the GUID five times, through a fold that
        // is itself O(n²) (see `MakiClassGUID.canonical`). They are loop-invariant for the call.
        let canonical = classGUID.map(Self.canonicalGUID)
        let name = method.lowercased()
        if method.caseInsensitiveCompare("getcontainer") == .orderedSame,
           canonical == "60906d4e482e537e94cc04b072568861" {
            return .init(argumentCount: 0, returnKind: .object)
        }
        // A program compiled without a class table (the pre-5.0 MAKI layout) carries no GUID here, so
        // it does not reach this. None of the measured corpus's PlEdit callers are in that form.
        if canonical == MakiClassGUID.playlistEditor,
           let signature = Self.playlistEditorSignatures[name] {
            return signature
        }
        if canonical == MakiClassGUID.playlistManager,
           let signature = Self.playlistManagerSignatures[name] {
            return signature
        }
        // The colour-theme pair, both gated by their **declaring** class — which is what the
        // interpreter passes here, and the reason `apply` can be given an arity at all. Registering
        // either name globally would hand its arity to every class that happens to declare the same
        // verb, and a wrong argument count is the one error the interpreter cannot recover from: it
        // leaves values on the stack and desynchronises everything after the call. See
        // `reference/scripting.md` → *`PlEdit`*, which records that failure mode.
        switch canonical {
        case MakiClassGUID.colorManager where method.caseInsensitiveCompare("getgammaset") == .orderedSame:
            return .init(argumentCount: 1, returnKind: .object)
        // Gated for the same reason `getGammaSet` is — "getColor" is exactly the sort of verb another
        // class could declare with a different arity.
        case MakiClassGUID.colorManager where method.caseInsensitiveCompare("getcolor") == .orderedSame:
            return .init(argumentCount: 1, returnKind: .object)
        case MakiClassGUID.gammaSet where method.caseInsensitiveCompare("apply") == .orderedSame:
            return .init(argumentCount: 0, returnKind: .null)
        default:
            break
        }
        if let signature = Self.generalSignatures[name] { return signature }
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
    /// `WINAMP_MODERN_ACTION_TRACE=1` names each `onAction` and its addressee. Read once: this is
    /// on the dispatch path every ClassicPro internal message takes.
    static let tracesActions = ProcessInfo.processInfo.environment["WINAMP_MODERN_ACTION_TRACE"] != nil

    private func invokeTraced(method: String, on reference: MakiObjectReference, arguments: [MakiValue],
                              program: MakiProgram) throws -> MakiValue {
        switch reference.kind {
        case .system:
            return try invokeSystem(method: method, arguments: arguments, program: program)
        case .playlistEditor:
            return invokePlaylistEditor(method: method, arguments: arguments)
        case .colorManager:
            return try invokeColorManager(method: method, arguments: arguments, program: program)
        case .playlistManager:
            return invokePlaylistManager(method: method, arguments: arguments)
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
        case .system, .playlistEditor, .colorManager, .playlistManager, .gui:
            break // Not script-owned; a skin cannot delete the graph out from under the renderer.
        }
    }

    func makeObject(classGUID: String, program: MakiProgram) throws -> MakiObjectReference {
        // `new ColorMgr` does not build anything — Winamp's colour manager is a singleton, and a
        // script saying `new` is asking for *the* one. Answering with a generic `.dynamic` shell
        // instead broke two things at once: its methods (`getColor`, `getGammaSet`) went to an object
        // that has none, and — the measured defect — an `onLoaded` handler bound to that variable
        // could never be reached, because dispatch matches on the value the variable holds.
        //
        // ClassicPro hangs its whole widget census off exactly that: `StartupCallback = new ColorMgr`
        // then `StartupCallback.onLoaded() { cProLoaded(); }`, and `cProLoaded` is the *only* caller
        // of the `widget_manager_register`/`_check`/`_done` actions that fill the Widgets Manager's
        // list. With `onLoaded` unreachable the window drew an empty list, in every cPro skin.
        if Self.canonicalGUID(classGUID) == MakiClassGUID.colorManager {
            return MakiObjectReference(.colorManager)
        }
        let id = nextPopupID
        nextPopupID &+= 1
        if Self.canonicalGUID(classGUID) == "f4787af44ef7b2bb4be7fb9c8da8bea9" {
            popupCommands[id] = []
            return MakiObjectReference(.popupMenu(id))
        }
        dynamicObjects[id] = DynamicObjectState()
        return MakiObjectReference(.dynamic(id))
    }

    // MARK: - ColorMgr (the colour-theme manager)

    // MARK: - PlEdit (the playlist editor)

    // MARK: - XmlDoc's callback parser

    /// Ceiling on the paths one `XmlDoc` may register. Big Bento Modern registers one.
    static let maximumParserCallbacks = 16
    /// Ceiling on the elements one `parser_start()` reports. The measured document holds 31
    /// `<sourceitem>`s; the cap is what stops a hand-edited one — this file is the skin's own
    /// documented customisation point, so users do edit it — from driving an unbounded number of
    /// script dispatches inside a single event.
    private static let maximumParserElements = 512

    /// Where `XmlDoc.load(path)` landed, or `nil` when the file is not in the VFS. Skins call `load`
    /// speculatively and branch on `exists()`, so a miss is the ordinary case rather than a failure:
    /// Big Bento Modern's reader tries its own `@SKINSPATH@\…\reader_providers.xml` first and then
    /// falls back to a Windows install path under `getApplicationPath()`, which resolves to nothing
    /// here and must answer false rather than abort the handler.
    func xmlDocumentPath(_ rawPath: String, program: MakiProgram) -> String? {
        guard !rawPath.isEmpty else { return nil }
        guard let resolved = try? loadedSkin.vfs.resolve(rawPath, relativeTo: program.source.path,
                                                         location: program.source) else { return nil }
        return resolved.logicalPath
    }

    /// Walks the loaded document once and dispatches `parser_onCallback` at the `XmlDoc` for every
    /// element whose path matches one of the registered callbacks.
    ///
    /// The handler's four arguments are pinned by Big Bento Modern's bytecode, which pops them into
    /// `(String path, String tag, List names, List values)` and then walks the two lists in parallel
    /// with `getNumItems`/`enumItem`, branching on the name to fill its provider row. The two lists
    /// are one reused pair of dynamic objects rather than a pair per element: the callback reads them
    /// synchronously and keeps neither, and a document of hand-edited length would otherwise allocate
    /// a script object per attribute set with nothing to free it.
    func parserStart(documentAt path: String, callbacks: [String], id: UInt64,
                             program: MakiProgram) {
        guard !callbacks.isEmpty,
              let data = try? loadedSkin.vfs.data(at: path, location: program.source),
              let text = String(data: data, encoding: .utf8)
                  ?? String(data: data, encoding: .isoLatin1),
              let parsed = try? WalLenientXMLParser().parse(text, path: path) else { return }

        let names = makeParserList()
        let values = makeParserList()
        defer {
            dynamicObjects.removeValue(forKey: names.id)
            dynamicObjects.removeValue(forKey: values.id)
        }

        var reported = 0
        func walk(_ node: WalXMLNode, path components: [String]) {
            guard reported < Self.maximumParserElements else { return }
            let here = components + [node.name]
            if callbacks.contains(where: { Self.parserPath($0, matches: here) }) {
                reported += 1
                // Document order, not alphabetical: a `parser_onCallback` body reads these two lists
                // positionally and ClassicPro's keys its whole apply loop on reaching `id` first.
                // See `WalXMLNode.attributeOrder`.
                let attributes = node.orderedAttributes
                dynamicObjects[names.id]?.items = attributes.map { .string($0.key) }
                dynamicObjects[values.id]?.items = attributes.map { .string($0.value) }
                _ = try? dispatch(target: MakiObjectReference(.dynamic(id)),
                                  event: "parser_oncallback",
                                  arguments: [.string(here.joined(separator: "/")),
                                              .string(node.name),
                                              .object(names.reference),
                                              .object(values.reference)])
            }
            for child in node.children { walk(child, path: here) }
        }
        for root in parsed.roots { walk(root, path: []) }
    }

    private func makeParserList() -> (id: UInt64, reference: MakiObjectReference) {
        let id = nextPopupID
        nextPopupID &+= 1
        dynamicObjects[id] = DynamicObjectState()
        return (id, MakiObjectReference(.dynamic(id)))
    }

    /// A `parser_addCallback` path against an element's own path.
    ///
    /// Three spellings, because the corpus uses three (B86; measured 2026-08-31 by pulling the
    /// literals out of the compiled `.maki`, since none of them appears in any XML):
    ///
    /// | Pattern | Registered by | Targets | Form |
    /// |---|---|---|---|
    /// | `WasabiXML/BrowserPro/*` | Big Bento's `main.maki` | `…/sourceitem` | absolute, same depth |
    /// | `ClassicPro/Visualization/BeatVis*` | ClassicPro `beat.maki` | `…/BeatVis/customvis` | absolute, **subtree** |
    /// | `ClassicPro/TextSettings*` | ClassicPro `player.maki`, `shade.maki` | `…/TextSettings/Style` | absolute, subtree |
    /// | `ClassicPro/About:Skin*` | ClassicPro `about.maki` | children of that node | absolute, subtree |
    /// | `BeatVis/*` | ClassicPro `beat.maki` | `ClassicPro/Visualization/BeatVis/customvis` | **relative** |
    ///
    /// This used to be the first row alone — equal component counts, `*` matching exactly one whole
    /// component. That is the shape Big Bento happens to have, and it silently rejected the other
    /// four: cPro's seven custom beat-vis animations never loaded, its songticker never got its
    /// antialias setting, and its About box never got its skin info. Nothing reported a failure,
    /// because a callback that never fires is indistinguishable from a document with nothing in it.
    ///
    /// Being generous here is safe by the callers' own construction: **every** `parser_onCallback`
    /// body in the corpus opens with `if (strlower(xmltag) == "<tag>")`, so an extra fire is
    /// discarded by the script itself. `beat.maki` registering two patterns for one set of nodes is
    /// the same defensiveness from the other side. What must not happen is a *missed* fire, so where
    /// the exact Winamp semantics are unknown this errs towards matching.
    /// Internal, not private, so the three spellings above can be pinned without a skin — the
    /// corpus patterns are the specification and a regression here is silent by nature.
    static func parserPath(_ pattern: String, matches components: [String]) -> Bool {
        let wanted = pattern.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        guard !wanted.isEmpty, !components.isEmpty else { return false }

        func alike(_ expected: String, _ actual: String) -> Bool {
            expected == "*" || expected.caseInsensitiveCompare(actual) == .orderedSame
        }

        // Absolute, same depth — the original rule, kept exactly so Big Bento's provider list keeps
        // matching the nodes it matches today and no others.
        if wanted.count == components.count, zip(wanted, components).allSatisfy(alike) {
            return true
        }

        // Absolute with a trailing `*` glued to the final component (`BeatVis*`): that component is a
        // *prefix*, and the pattern covers the node it names **and everything beneath it**. A bare
        // final `*` is not this case — there it means one component, which the rule above handles.
        if let last = wanted.last, last != "*", last.hasSuffix("*"), components.count >= wanted.count {
            let stem = last.dropLast()
            let leading = wanted.dropLast()
            if zip(leading, components).allSatisfy(alike),
               components[leading.count].lowercased().hasPrefix(stem.lowercased()) {
                return true
            }
        }

        // Relative (`BeatVis/*`) — align the pattern with the *end* of the path. Requires at least
        // two components: a bare `foo` would otherwise match an element of that name at any depth,
        // which nothing asks for and which would fire callbacks a script never registered.
        if wanted.count >= 2, wanted.count < components.count,
           zip(wanted, components.suffix(wanted.count)).allSatisfy(alike) {
            return true
        }

        return false
    }

    /// Which layout a `newGroupAsLayout` group hangs off: the one its groupdef names in
    /// `owner="<container>,<layout>"`, falling back to the calling script's own ancestor layout when
    /// there is no `owner=` or it names something this skin did not instantiate.
    ///
    /// The fallback matters because the caller is often not under a layout at all — multipass's
    /// `system.maki` is a `skin.xml`-level script whose owner is the `<scripts>` element — in which
    /// case there is nothing to parent to and the call answers null rather than misplacing the group.
    func ownerLayout(forGroupDefinition identifier: String, program: MakiProgram) -> WasabiObject? {
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

    func findRoot(type: String, xmlID: String) -> WasabiObject? {
        loadedSkin.runtime.graph.roots.first {
            $0.typeName.caseInsensitiveCompare(type) == .orderedSame &&
            $0.xmlID?.caseInsensitiveCompare(xmlID) == .orderedSame
        }
    }

    func dynamicValue(role: DynamicRole) -> MakiValue {
        let id = nextPopupID
        nextPopupID &+= 1
        dynamicObjects[id] = DynamicObjectState(role: role)
        return .object(MakiObjectReference(.dynamic(id)))
    }

    /// How many instances one `instantiate` call may add. The corpus's only caller asks for 1.
    static let maximumGroupListInstances = 64

    func objectValue(_ object: WasabiObject?) -> MakiValue {
        object.map { .object(MakiObjectReference(.gui($0.stableID))) } ?? .null
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
    func visBand(channel: Int32, band: Int32) -> Int32 {
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
    func vuValue(left: Bool) -> Int32 {
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

    func isInvalid(_ object: WasabiObject) -> Bool {
        guard let imageID = object.attributes["image"] ?? object.attributes["bitmap"] else { return false }
        guard let definition = loadedSkin.runtime.resources.resolvedDefinition(identifier: imageID),
              definition.kind == "bitmap" else { return true }
        // Generated bitmaps (`file="$solid"`) carry no file and are perfectly valid.
        if definition.attributes["file"]?.hasPrefix("$") == true { return false }
        return definition.logicalFile == nil
    }

    /// `show` / `hide` / `toggle`, in one place: the attribute, the notification, and the host
    /// request a container needs, in the order Wasabi does them.
    func setVisible(_ object: WasabiObject, _ visible: Bool) throws -> MakiValue {
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

    /// Visible *as the user sees it*. The window this object lives in is the outer term — only the
    /// host knows whether it is on screen — and the object's own `visible` attribute is the inner
    /// one. `nil` from the host (the headless harness, the player's own container, an id no window
    /// backs) falls back to the attribute alone.
    ///
    /// The ancestor **groups** between the two are deliberately not consulted: Winamp's
    /// `GuiObject::isVisible()` answers for the object itself, and walking the group chain broke
    /// cPro-Bento's tab system, whose script shows a tab page whose parent group is still hidden
    /// (B22). A closed *window* is a different question, and it is the one Defix asks.
    /// The player window's box in **Winamp's screen space** — y measured downward from the top of the
    /// screen the window is on — or `nil` when no host has answered (the headless harness).
    ///
    /// The obvious `NSApp.mainWindow?.frame` is wrong twice over. `NSApp` is an implicitly-unwrapped
    /// global that is **nil** until an `NSApplication` exists, so reading it traps in the headless
    /// harness rather than answering; and AppKit's `minY` is the window's *bottom* measured upward,
    /// which is the opposite of the coordinate every other window read in this runtime answers in
    /// (`getLeft`/`getTop` go through `containerOriginQuery`, which the controller fills from
    /// `winampScreenOrigin`). ClassicPro seeds `normal.resize(x, y, …)` from `getCurAppTop()` when
    /// the user has no stored position, so an upward y put the player wherever the flip landed.
    ///
    /// Both faults were unreachable until `System.onShowLayout` began to be dispatched: `fullScreen()`
    /// is the only caller, and nothing ran it.
    var playerWindowFrame: CGRect? {
        guard let origin = containerOriginQuery?(Self.playerContainerID),
              let size = playerWindowSizeRequested?() else { return nil }
        return CGRect(origin: origin, size: size)
    }

    /// The id Winamp gives the player's own container. The same literal the topology keys `isMainPlayer` on.
    private static let playerContainerID = "main"

    /// The player window's size in logical points. Paired with `containerOriginQuery` rather than
    /// folded into it, because the origin needs a coordinate flip and the size does not.
    var playerWindowSizeRequested: (() -> CGSize?)?

    /// One edge of that frame as MAKI sees it: clamped, and 0 when there is no window to measure.
    static func appFrameDimension(_ value: CGFloat?) -> Int32 {
        guard let value, value.isFinite else { return 0 }
        return Int32(clamping: Int(value.rounded()))
    }

    func effectiveVisibility(of object: WasabiObject) -> Bool {
        let hosted = enclosingWindowID(of: object).flatMap { containerVisibilityQuery?($0) }
        // Nothing inside a closed window is on screen, whatever its own attribute still says.
        // Defix's `ML` round button asks the media-library tab page this before deciding what
        // its click means; with the SUI window shut and the page's stale `visible="1"` answering
        // yes, every press took the "already showing — close it" branch, so the button could
        // only ever shut a window the menu had opened (B22).
        if hosted == false { return false }
        // A container shows exactly **one** layout at a time, so a layout that is not its
        // container's active one is not on screen however open the window is. Answering for the
        // window alone made `normal` and `shade` both report visible simultaneously, which is a
        // state no Winamp skin can be in, and a skin that tells the two apart then read the wrong
        // one: ClassicPro engine "two" lays its whole player out from
        // `if(_layout==normal && !shade.isVisible())` on cold start, and with `shade` answering yes
        // that branch never ran — `two.screen` kept its default `y=0`, the info and transport bands
        // drew over the titlebar, and a 28px dead strip sat above the SUI (cPro2 Dark Aluminum).
        //
        // This is deliberately answered from the graph rather than from the host, so it holds in
        // the headless harness too, where no container visibility is reported at all.
        if object.typeName.caseInsensitiveCompare("layout") == .orderedSame,
           let container = Self.enclosingContainer(of: object),
           let active = activeLayoutByContainer[container.stableID] {
            return active == object.stableID
        }
        // A layout answers for its window as its container does, and for the same reason: the window
        // is the thing that is actually on screen, and the host can close it (a dismissed
        // `autoclose` popup) without the graph attribute moving. Big Bento asks its search results'
        // *layout* whether it is open before re-showing it, so a stale `visible="1"` there left the
        // skin believing a window the user had dismissed was still up — and the next search filled a
        // list nobody could see (BB31).
        if hosted == true, Self.isWindowObject(object) { return true }
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
    func isActive(_ object: WasabiObject) -> Bool {
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

    /// Winamp applies `targetspeed` as an exponential ease factor per ~20 ms timer tick.
    /// Scale to real elapsed time so the animation looks the same at any frame rate.
    static let wasabiTargetTickPeriod: Double = 0.020

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
            case MakiClassGUID.playlistManager:
                variable.value = .object(MakiObjectReference(.playlistManager))
            default:
                continue
            }
        }
    }

    /// Compiled MAKI stores class IDs as four little-endian 32-bit words.
    /// Normalize them to the compact string form used by std.mi.
    private static func canonicalGUID(_ raw: String) -> String { MakiClassGUID.canonical(raw) }

    func unsupported(_ method: String, program: MakiProgram) -> WalFailure {
        unsupportedMethodCalls[method.lowercased(), default: 0] += 1
        // Traced with the calls that *did* work, because that is the line the reader is looking for:
        // an unimplemented method aborts its whole handler, so what a trace shows is a sequence that
        // simply stops, and the reason is otherwise only in a compatibility report taken later.
        if Self.tracesEveryCall {
            print("CALL-TRACE \(method.lowercased())(…) -> UNSUPPORTED, handler aborts "
                  + "[\((program.source.path as NSString).lastPathComponent)]")
        }
        return WalFailure(WalDiagnostic(.unsupportedScriptCapability,
                                 "Winamp Modern runtime does not support method '\(method)'.",
                                 location: program.source))
    }

    /// Screen dimensions come from AppKit as `CGFloat`; MAKI exposes a signed integer. Invalid or
    /// negative host values degrade to zero, and very large values clamp instead of trapping.
    static func screenDimension(_ value: CGFloat?) -> Int32 {
        guard let value, value.isFinite, value > 0 else { return 0 }
        guard value < CGFloat(Int32.max) else { return Int32.max }
        return Int32(value.rounded(.down))
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
        playerWindowSizeRequested = nil
        layoutResizeRequested = nil
        uiScaleRequested = nil
        monitorSizeRequested = nil
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
