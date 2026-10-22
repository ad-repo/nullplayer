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
        /// A `new Text`/`new Layer`… before `init(parent)`: the element it becomes, what the script
        /// wrote with `setXmlParam` (it is created with those — 1010 Fullscreen's analyzer sets a
        /// layer's id, image and box this way, then `init`s it), and any other call, replayed in
        /// order once it exists (1010's `setRegionFromMap`). The calls are bounded, since nothing
        /// runs them until then.
        case pendingGUI(type: String, attributes: [String: String],
                        calls: [(method: String, arguments: [MakiValue])])
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
        /// A `Wac` — a Winamp component by GUID (`System.getWac`). It takes no commands here.
        case wac(guid: String)
        /// One `<gammagroup>` of a colour theme, from `GammaSet.enumGammaGroup(n)`.
        case gammaGroup(theme: String, group: String)
    }

    /// Ceiling on one `List`'s length. ClassicPro's longest is its tab order (a dozen entries); the
    /// cap is what stops a script appending in a loop from growing without bound.
    static let maximumListItems = 4_096
    /// The side of Wasabi's missing-bitmap placeholder, which is what a `Map` that loaded nothing
    /// reports as its size.
    static let missingMapSide: Int32 = 64

    let loadedSkin: WinampModernLoadedSkin
    let host: WinampModernHost
    let timers: MakiTimerService
    let interpreter: MakiInterpreter
    var programs: [MakiProgram] = []
    var trees = WinampModernScriptTrees()
    /// Script-made GUI objects (`new Text` then `init`), by their dynamic id.
    var dynamicGUIObjects: [UInt64: WasabiObjectID] = [:]
    private(set) var isTornDown = false

    /// Names of MAKI methods the runtime was asked for but does not implement, with a call count each.
    /// Populated by `unsupported(_:program:)` before it throws. This is the measured-demand signal that
    /// drives Phase 7.3 API additions and feeds the per-skin compatibility report (Phase 7.2); it never
    /// changes execution semantics.
    var unsupportedMethodCalls: [String: Int] = [:]
    /// Diagnostics from script events that aborted without stopping the rest of the skin. Capped:
    /// a handler that fails on a repeating event (a timer or mouse move) would otherwise accumulate
    /// forever. The report de-duplicates anyway, so the cap costs no distinct information.
    private(set) var scriptFailures: [WalDiagnostic] = []
    static let maximumRecordedScriptFailures = 512

    func recordScriptFailure(_ failure: WalFailure) {
        guard scriptFailures.count < Self.maximumRecordedScriptFailures else { return }
        scriptFailures.append(contentsOf: failure.diagnostics)
    }

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
        where WinampModernComponentRegistry.isHolderElement(object.tag) {
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
    /// What the window layer answers for the scripts; see `WinampModernScriptHooks`.
    var hooks = WinampModernScriptHooks()
    /// Show a script-built popup menu and answer the command the user picked, or `popupDismissed`.
    /// The runtime resolves the submenu tree before calling, so the presenter only builds UI.
    ///
    /// A `nil` point is `popAtMouse`. A point is `popAtXY`, in **window-client space** — the space
    /// `clientToScreenX/Y` answer in, which is what every measured caller computes the point with.
    var popupPresenter: (([WinampModernPopupMenuItem], CGPoint?) -> Int32)?
    /// What Winamp's `popAtMouse`/`popAtXY` answer for a menu that was dismissed or never shown. Not
    /// 0: skins number their first command 0 and test `res < 0` for a cancel — Anunaki's wheel
    /// (0 = Volume), lights (0 = Off) and player-mode (0 = normal) menus all do — so answering 0 ran
    /// the first row whenever a menu was dismissed.
    static let popupDismissed: Int32 = -1
    /// A hosted window's borrowed chrome dropped a strip after the window was built — Itemskin
    /// creates its chrome when the window is shown — so the window is this many points shorter.
    var hostedChromeLiftApplied: ((WasabiObjectID, CGFloat) -> Void)?
    /// A second live copy of a `dynamic="1"` container has just been grafted into the graph and needs
    /// a window of its own before the script that asked for it shows it (B110). See
    /// `dynamicContainer(named:for:)`.
    var containerInstanceCreated: ((WasabiObject) -> Void)?
    /// Which copy of a `dynamic="1"` container each program was handed, keyed by lowercased declared
    /// id and then by the calling program. Per program because that is the grain Winamp instances at:
    /// one included copy of a frame script is one window's frame, and asking twice from the same
    /// script means "the one I already have", not "another window".
    var dynamicContainerInstances: [String: [ObjectIdentifier: WasabiObjectID]] = [:]
    /// Per hosted window, the floor its borrowed chrome imposes — see `adoptChromeForHostedWindow`.
    var hostedChromeFloors: [WasabiObjectID: CGSize] = [:]
    /// Per hosted window, the height its borrowed chrome gave back — see `liftHostedClient`.
    var hostedChromeLifts: [WasabiObjectID: CGFloat] = [:]
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
    /// A container's alpha changed via `container.setAlpha(v)`. The host maps this to window alpha
    /// so notifier fade animations are visible.
    var containerAlphaChanged: ((String, CGFloat) -> Void)?
    /// The playlist the `PlEdit` singleton addresses. Weak: the window controller owns the bridge,
    /// and a skin reload tears the runtime down first. `nil` in the headless harness, where every
    /// read falls back to `WasabiTextMetrics.componentTextProvider` and every write is a no-op.
    weak var componentHost: WinampModernComponentHost?
    /// Diagnostic tap on every handler that actually ran, with the failure that aborted it or `nil`.
    ///
    /// Nil in the app. The render harness installs one because "did this script's `onScriptLoaded`
    /// run?" is otherwise unanswerable from outside: `hasBinding` reports what the *bytecode* declares,
    /// which is why `WINAMP_MODERN_RENDER_XUI`'s `onscriptloaded=false` was mistaken for a dead script
    /// in TASKS §15.6 — it says nothing about execution.
    var dispatchObserver: ((_ event: String, _ program: MakiProgram, _ failure: WalFailure?) -> Void)?
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
        /// The subsets are disjoint by construction — `scriptStarts` binds each script path+owner
        /// exactly once — so distinguishing them cannot reopen the ping-pong the guard exists for, and
        /// `WinampModernScriptStarts.maximumDepth` bounds the nesting.
        let scope: [ObjectIdentifier]
    }
    /// Events currently on the interpreter stack. A skin can wire two objects to update each other
    /// (MMD3's seek slider and its ghost both call `setPosition` from the other's `onSetPosition`),
    /// which is a bounded ping-pong in Winamp but unbounded native recursion here — and native
    /// recursion is not something the interpreter's own call-depth budget can see.
    private var eventsBeingDispatched: Set<ScriptEventKey> = []
    var isDispatchingEvent: Bool { !eventsBeingDispatched.isEmpty }

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
    static let maximumRegisteredSettings = 512
    /// Display names for the sections above, learned from `Config.newItem(name, guid)`. `getItem`
    /// and `getItemByGuid` do not name anything new — they address an item that already exists.
    var configItemNames: [String: String] = [:]

    private var nextObjectID: UInt64 = 1
    /// A fresh id for a script-created popup menu or dynamic object.
    func newObjectID() -> UInt64 {
        defer { nextObjectID &+= 1 }
        return nextObjectID
    }
    var popupCommands: [UInt64: [PopupEntry]] = [:]
    var dynamicObjects: [UInt64: DynamicObjectState] = [:]
    var activeTargetAnimations: [WasabiObjectID: TargetAnimationState] = [:]
    var activeLayoutByContainer: [WasabiObjectID: WasabiObjectID] = [:]
    /// Layouts a script sized to nothing; see `noteScriptSize`.
    var scriptCollapsedLayouts: Set<WasabiObjectID> = []

    /// Layouts that have actually been *created*.
    ///
    /// Winamp builds a container's layouts on demand — only the one on screen exists — so
    /// `getContainer("main").getLayout("shade")` answers NULL until the user shades the window, and
    /// skins are written against exactly that. Big Bento Modern's volume, mute, play/pause animation
    /// and album-art scripts all open with
    ///
    /// ```maki
    /// if (normal) { vol = normal.findObject("vol.on"); ... }
    /// if (shade)  { vol = shade.findObject("vol.on");  ... }
    /// ```
    ///
    /// — two blocks meant to be mutually exclusive. We build every layout up front, so both blocks
    /// ran and the second overwrote the first: **89 of the skin's bindings pointed into
    /// `layout#shade`**, including the click that opens its volume panel, which is why the normal
    /// layout had no working volume control at all. See `isLayoutCreated`.
    var realizedLayouts: Set<WasabiObjectID> = []
    let preferenceNamespace: String

    var scriptStarts = WinampModernScriptStarts(bound: [])
    /// Bitmap pixel sizes for `getAutoWidth`/`getLength`, and decoded `Map` images.
    var scriptBitmaps = WinampModernScriptBitmaps()
    /// The scripts that went looking for a cover beside the playing file (`WinampModernTrackFolderImage`).
    var coverSeekers = WinampModernTrackFolderImage.Seekers()
    /// Font resolution and text measurement, shared with the renderer so `getAutoWidth()` answers
    /// what the text will actually occupy when drawn.
    lazy var metrics = WasabiTextMetrics(loadedSkin: loadedSkin)
    /// Ceiling on total loaded programs. Runtime instantiation (`System.newGroup`) can add scripts,
    /// so this bounds a skin that instantiates groups in a loop.
    static let maximumRuntimePrograms = 512

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
        self.scriptStarts = WinampModernScriptStarts(bound: Set(loadedSkin.runtime.scriptBindings))
        self.scriptFailures = Array(parseFailures.prefix(Self.maximumRecordedScriptFailures))
        for root in loadedSkin.runtime.graph.roots where root.tag.is(.container) {
            let layouts = root.children.filter {
                $0.tag.is(.layout)
            }
            // The layout a container comes up in: the one Winamp names `normal`, or its only one.
            // The first is the fallback rather than nothing, so a container that names neither still
            // has *a* realized layout — `getLayout` answers only for realized ones, and a container
            // with no entry at all would answer NULL for every layout it has.
            if let opening = layouts.first(where: { $0.xmlID?.caseInsensitiveCompare("normal") == .orderedSame })
                ?? layouts.first {
                activeLayoutByContainer[root.stableID] = opening.stableID
                realizedLayouts.insert(opening.stableID)
            }
        }
    }

    /// Record that a layout has been created — the host switching a window to it, as against a
    /// script's own `switchToLayout`. See `realizedLayouts`.
    func markLayoutRealized(_ layout: WasabiObject) {
        guard layout.tag.is(.layout) else { return }
        realizedLayouts.insert(layout.stableID)
        if let container = layout.parent,
           container.tag.is(.container) {
            activeLayoutByContainer[container.stableID] = layout.stableID
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
        // Object-owned scripts start **one owner at a time**, each followed by its own XUI params (B71).
        // Wasabi configures an object completely — script loaded, then params — before the next one
        // in the document is created, so a layout's `<script>` declared after a
        // `<Wasabi:StandardFrame:* content="…">` finds the frame's content already built. Defix's
        // detached visualizer is the measured case: `visrb2.maki` resolves eleven names inside
        // `VISCON.component.gp`, and with every param deferred to the end it bound all eleven to
        // null. Params still follow their own owner's `onScriptLoaded` — a XUI handler binds to
        // the script group that event populates (see `deliverXUIParams`).
        let skinLevel = programs.filter { isSkinLevel($0) }
        let owned = programs.filter { !isSkinLevel($0) }
        var owners: [WasabiObjectID] = []
        var programsByOwner: [WasabiObjectID: [MakiProgram]] = [:]
        for program in owned {
            guard let ownerID = program.ownerID else { continue }
            if programsByOwner[ownerID] == nil { owners.append(ownerID) }
            programsByOwner[ownerID, default: []].append(program)
        }
        for ownerID in owners {
            _ = try dispatchSystem(event: "onscriptloaded", to: programsByOwner[ownerID] ?? [])
            if let owner = loadedSkin.runtime.graph.object(withID: ownerID) { deliverXUIParams(for: owner) }
        }
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
            $0.tag.is(.container) &&
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
        return owner.tag.is(.scripts)
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

    /// The sliders `postPosition(_:to:)` posts to, and the graph structure they were read from.
    var postedSliderCache: [PostedSlider: (generation: UInt64, sliders: [WasabiObject])] = [:]

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

    /// Objects whose `onTextChanged` is running right now, so a handler that writes text back into
    /// its own object cannot recurse for ever. Winamp raises the event from inside `setText`, and a
    /// skin is free to answer it with another `setText`.
    var textChangeInFlight: Set<WasabiObjectID> = []

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

    var announcedEqualizer = WinampModernAnnouncedEqualizer()

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

    /// The window positions scripts read, and the rules that recognise them being written back.
    /// See `WinampModernBorrowedOrigin`.
    var borrowedOrigin = WinampModernBorrowedOrigin()

    /// Which container's window is kept parked on which other container's window — leader → follower,
    /// learned from the `follower.resize(leader.getLeft(), leader.getTop(), …)` idiom above. The
    /// follower is drawn *over* the leader (it is the leader's border and title), so the window layer
    /// re-raises it whenever the leader comes forward.
    var windowsGluedOver: [WasabiObjectID: WasabiObjectID] = [:]

    /// The last value each bridged attribute was seen at, so a refresh only tells the skin about a
    /// setting that actually moved. Four entries — one per `WinampModernConfigBridge.Attribute`.
    var lastBridgedValues: [String: Int32] = [:]

    /// The last volume `onVolumeChanged` reported, 0…255, or −1 before the first. One per skin, and
    /// written by `setVolume` as well as by the window's poll: when only the poll kept it, a skin's
    /// own `setVolume` was announced a second time on the next tick. Alpha Media Player X5's mute
    /// takes an `onVolumeChanged` it did not expect as the user moving the volume, and un-muted.
    private(set) var announcedVolume: Int32 = -1

    static func volumeLevel(_ volume: Double) -> Int32 { Int32(max(0, min(255, volume * 255))) }

    /// Record a volume a skin's own `setVolume` announced. Taken from `host.volume`, not the level
    /// the skin passed, so the poll's reading of the same volume compares equal after a float round trip.
    func noteVolumeAnnounced() { announcedVolume = Self.volumeLevel(host.volume) }

    /// Announce a volume change made outside the skin — the menu bar, a keyboard shortcut, another
    /// window — so a readout the skin drives from `onVolumeChanged` does not sit on a stale number.
    func announceVolumeIfChanged() {
        let level = Self.volumeLevel(host.volume)
        guard level != announcedVolume else { return }
        announcedVolume = level
        _ = try? dispatchSystem(event: "onvolumechanged", arguments: [.integer(level)])
    }

    var geometrySettle = WinampModernGeometrySettle()

    /// The ids the last diffing pass judged to have left the layout — the objects it told
    /// `onResize(x, y, 0, 0)`. Recorded before the binding check, so it reports the *decision*
    /// rather than the delivery, which is what B138 turned on.
    var vanishedResizeTargetsForTesting: [WasabiObjectID] = []

    func hasBinding(for object: WasabiObject, event: String? = nil) -> Bool {
        let event = event?.lowercased()
        return !programsBinding(object) { event == nil || $0 == event }.isEmpty
    }

    /// The presses that make an object a control. Wasabi gives every non-ghost GuiObject its rect, so
    /// a `text` or `AlbumArt` a script hooks one of these on is under the pointer (B207): Ebonite's
    /// timer opens its clock menu on a right-click. A hover-only binding is left out, so a
    /// `onMouseMove` overlay does not swallow clicks meant for what is behind it.
    static let pressEvents: Set<String> = ["onleftbuttondown", "onleftbuttonup", "onleftclick",
                                           "onleftbuttondblclk", "onrightbuttondown",
                                           "onrightbuttonup", "onrightclick"]

    func hasPressBinding(for object: WasabiObject) -> Bool {
        !programsBinding(object) { Self.pressEvents.contains($0) }.isEmpty
    }

    /// The scripts with a handler bound to `object` for an event `matches` accepts.
    func programsBinding(_ object: WasabiObject, event matches: (String) -> Bool) -> [MakiProgram] {
        let target = MakiObjectReference(.gui(object.stableID))
        return programs.filter { program in
            program.bindings.contains { binding in
                if !matches(program.methods[binding.methodIndex].name) { return false }
                let variable = program.variables[binding.variableIndex]
                if self.object(variable.value, equals: target) { return true }
                return variable.classMembers.contains {
                    self.object(program.variables[$0].value, equals: target)
                }
            }
        }
    }

    @discardableResult
    func dispatchSystem(event: String, to programs: [MakiProgram]) throws -> Int {
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
            // never came gets its scripts started anyway (see `pendingRuntimeGroups`), and no window
            // position the event read can be borrowed by a later one.
            if isOutermost {
                borrowedOrigin.forget()
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
                    recordScriptFailure(failure)
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
    ///
    /// **A window that has never been shown is not a window that closed** (B112). Every auxiliary
    /// container is announced once at `scripts.start()` with whatever its window says, and for the
    /// ones a skin ships `default_visible="0"` that first announcement is `false` — a statement of
    /// the starting state, not the event Winamp fires when a window is ordered out. Dispatched as an
    /// event it runs the script's *closing* branch against a window nobody has opened, and a handler
    /// is entitled to tear its own scene down there: Itemskin's `standardframePL.maki` answers
    /// `onSetVisible(0)` with `PLEdit.normal.hide()` + `cont.clear.pl.hide()` + `Timer.stop()`, so
    /// the playlist window's own layout came up marked hidden, its frame window was never created,
    /// and the timer that pairs the two was stopped before it ever ran — an empty, frameless box the
    /// user cannot make paint. Recorded and not dispatched, so the *next* announcement is the real
    /// change.
    func notifyContainerVisibility(containerID: WasabiObjectID, visible: Bool) {
        guard !isTornDown else { return }
        guard let container = loadedSkin.runtime.graph.object(withID: containerID) else { return }
        guard containerVisibility[containerID] != visible else { return }
        let firstAnnouncement = containerVisibility[containerID] == nil
        containerVisibility[containerID] = visible
        guard visible || !firstAnnouncement else { return }
        // **Opening a container shows the layout it is on** (B112). A skin's script may have called
        // `hide()` on that layout itself — Itemskin's playlist frame does, from the `onSetVisible(0)`
        // above — and `visible="0"` is written on the layout object, where nothing but another
        // script call clears it. Winamp has no such residue: `Container::setVisible(1)` re-enters
        // the current layout, so a window the user reopens comes back whole.
        //
        // Left standing it is terminal rather than cosmetic, because the flag feeds the walk below:
        // the layout reads not-visible, so **nothing inside it hears `onSetVisible(1)`** and the very
        // handler that would rebuild the window's chrome is never reached. Itemskin's playlist opened
        // as an empty box with no frame and no way back — the scene drew nothing, `cont.clear.pl` was
        // never created, and the 10 ms timer that keeps the pair together stayed stopped.
        if visible, let layoutID = activeLayoutByContainer[containerID],
           let layout = loadedSkin.runtime.graph.object(withID: layoutID), !isVisible(layout) {
            _ = layout.setAttribute("visible", value: "1")
            visibility.reopened(layout.stableID)
            noteGeometryChange()
        }
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

    var layerFX = WinampModernLayerFXStore()

    func requestRepaint(for object: WasabiObject? = nil) {
        guard !layerFX.isEvaluating else { return }
        if let object, let objectRepaintRequested = hooks.objectRepaintRequested { objectRepaintRequested(object) }
        else if let repaintRequested = hooks.repaintRequested { repaintRequested() }
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
    /// Whether a window resize reaches the skin the way Wasabi delivers one: applied as a whole box
    /// — position before size — and reported in the same turn, `onUserResize` included (B160).
    /// `WINAMP_MODERN_RESIZE_NOTIFY=0` is the A/B switch; `reference/harness.md` lists what it
    /// withholds and what it does not.
    static let deliversResizeAsWasabiDoes =
        ProcessInfo.processInfo.environment["WINAMP_MODERN_RESIZE_NOTIFY"] != "0"

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
            if let objectID = dynamicGUIObjects[id] {
                guard let object = loadedSkin.runtime.graph.object(withID: objectID) else { return .null }
                return try invokeGUI(method: method, object: object, arguments: arguments, program: program)
            }
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

    func report(_ diagnostic: WalDiagnostic) {
        loadedSkin.runtime.record(diagnostic)
    }

    func releaseObject(_ reference: MakiObjectReference) {
        switch reference.kind {
        case .dynamic(let id):
            timers.cancel(id: id)
            dynamicObjects.removeValue(forKey: id)
            // `delete` on a script-made GUI object takes it out of the graph.
            if let objectID = dynamicGUIObjects.removeValue(forKey: id),
               let object = loadedSkin.runtime.graph.object(withID: objectID) {
                loadedSkin.runtime.graph.discardSubtree(object)
                notifyGraphDidMutate()
            }
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
        if MakiClassGUID.canonical(classGUID) == MakiClassGUID.colorManager {
            return MakiObjectReference(.colorManager)
        }
        // `new PlEdit` is the same: there is one playlist editor. Skin Consortium's `SC:Cover`
        // (Ebonite, MusicshowB) does `PeListener = new PlEdit` and reads the playing row through it;
        // as a `.dynamic` shell `getCurrentIndex()` was unsupported, its title-change handler aborted
        // before it named a single file, and the Album Art window stayed blank.
        if MakiClassGUID.canonical(classGUID) == MakiClassGUID.playlistEditor {
            return MakiObjectReference(.playlistEditor)
        }
        let id = newObjectID()
        if MakiClassGUID.canonical(classGUID) == MakiClassGUID.popupMenu {
            popupCommands[id] = []
            return MakiObjectReference(.popupMenu(id))
        }
        var state = DynamicObjectState()
        if let type = MakiClassGUID.scriptCreatableElements[MakiClassGUID.canonical(classGUID)] {
            state.role = .pendingGUI(type: type, attributes: [:], calls: [])
        }
        dynamicObjects[id] = state
        return MakiObjectReference(.dynamic(id))
    }

    func findRoot(type: WasabiKind, xmlID: String) -> WasabiObject? {
        loadedSkin.runtime.graph.roots.first {
            $0.tag.is(type) &&
            $0.xmlID?.caseInsensitiveCompare(xmlID) == .orderedSame
        }
    }

    func dynamicValue(role: DynamicRole) -> MakiValue {
        let id = newObjectID()
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

    var visibility = WinampModernScriptVisibility()

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
    static func seedHostSingletons(in program: MakiProgram) {
        for variable in program.variables where variable.declaredKind == .object {
            switch variable.classGUID.map(MakiClassGUID.canonical) {
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
        hooks = WinampModernScriptHooks()
        popupPresenter = nil
        dispatchObserver = nil
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
        realizedLayouts.removeAll()
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
