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
    var actionRequested: ((String, String?) -> Void)?
    var themeNamesRequested: (() -> [String])?
    var activeThemeRequested: (() -> String)?
    var themeSwitchRequested: ((String) -> Bool)?
    /// Cursor position in the *skin's own pixel space* — the same units as the x/y a mouse event hands
    /// a script, which rotary-knob scripts combine in a single expression.
    var mousePositionRequested: (() -> CGPoint)?
    /// The same cursor position, but in the pixel space of the window that renders `object` — which is
    /// a *different* window from the one `mousePositionRequested` answers for whenever the receiver
    /// lives in an auxiliary container. `System.getMousePos*` has no receiver and cannot ask this;
    /// `isMouseOverRect` does, and Defix's SUI tabs are in the SUI window while the mouse hook is
    /// installed by the main view, so comparing against the main window's space put every tab's
    /// hit somewhere else entirely. `nil` when no window renders the object (the headless harness).
    var mousePositionInObjectSpaceRequested: ((WasabiObject) -> CGPoint?)?
    /// Whether the equalizer is on, for `System.getEQ()`.
    var equalizerEnabledRequested: (() -> Bool)?
    /// One EQ band, on MAKI's −127…127 scale (MMD3's bass/treble knobs read and write the bands).
    var equalizerBandRequested: ((Int) -> Int)?
    var equalizerBandSetterRequested: ((Int, Int) -> Void)?
    /// The EQ preamp, on the same MAKI −127…127 scale as a band.
    var equalizerPreampRequested: (() -> Int)?
    var equalizerPreampSetterRequested: ((Int) -> Void)?
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
        // The Phase 24 additions. ClassicPro calls all of these as methods as well as receiving them:
        // `beat.m`'s own `frameGroup.onResize(0, 0, w, h)` re-solves its geometry after a change it
        // made itself, `tagviewer.m` does the same, and a script that reuses its `onSetVisible` or
        // `onTitleChange` body is the same idiom `onSetPosition` already had.
        "onresize": 4,
        "onsetvisible": 1,
        "onpause": 0,
        "onresume": 0,
        "ontitlechange": 1,
        "onleftbuttondblclk": 2,
        "ontextchanged": 1,
        "onscriptunloading": 0
    ]

    /// Version-gate shim. ClassicPro's `WinampVersionCheck.maki` early-returns when the reported build
    /// number is at least the skin's required build (`2405` for cPro-Bento), so a comfortably modern
    /// value branches the script past its "please update Winamp" warning without hard-blocking.
    static let reportedWinampBuild: Int32 = 9999
    static let reportedWinampVersion = "5.9"

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
        self.programs = try loadedSkin.runtime.scriptBindings.map { binding in
            let data = try loadedSkin.vfs.data(at: binding.logicalPath, location: binding.source)
            return try MakiBytecodeParser().parse(data, source: binding.source,
                                                  ownerID: binding.ownerID,
                                                  parameter: binding.parameter)
        }
        self.boundScriptPaths = Set(loadedSkin.runtime.scriptBindings)
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
        guard loadedSkin.runtime.types.isXUITag(object.typeName), !object.scriptBindings.isEmpty else { return }
        // `onSetXuiParam` is a *System* event, and each XUI instance gets its own program
        // instance, so the params must go only to the programs that instance owns —
        // dispatching to every program would hand one frame's `content` to all of them.
        let owned = programs.filter { $0.ownerID == object.stableID }
        guard !owned.isEmpty else { return }
        for (name, value) in object.attributes.sorted(by: { $0.key < $1.key }) {
            _ = try? dispatch(target: MakiObjectReference(.system), event: "onsetxuiparam",
                              arguments: [.string(name), .string(value)], in: owned)
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
        if let explicit = object.attributes["w"], let width = Int32(explicit), width > 0 { return width }
        if let imageID = object.attributes["image"], let width = bitmapWidth(identifier: imageID) {
            return width
        }
        // Measured with the font the renderer draws with, not estimated: ClassicPro sizes every SUI
        // tab to `label.getAutoWidth() + 14` and lays its menu bar out from these numbers, so an
        // estimate that runs narrow clips every label inside a box the skin thinks fits it.
        let type = object.typeName.lowercased()
        guard type == "text" || type == "songticker" else { return 0 }
        let text = WasabiTextMetrics.content(of: object, host: host)
        return Int32(clamping: Int(metrics.width(of: object, text: text).rounded(.up)))
    }

    /// Pixel width of a declared bitmap. Uses the resource's explicit `w` when the declaration crops
    /// a sprite sheet, otherwise reads the image header (no full decode) for whole-file bitmaps.
    private func bitmapWidth(identifier: String) -> Int32? { bitmapSize(identifier: identifier)?.width }

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
                let data = try loadedSkin.vfs.data(at: binding.logicalPath, location: binding.source)
                added.append(try MakiBytecodeParser().parse(data, source: binding.source,
                                                            ownerID: binding.ownerID,
                                                            parameter: binding.parameter))
            }
            for child in object.children { try collect(child) }
        }
        try collect(root)
        guard !added.isEmpty else { return }
        programs.append(contentsOf: added)
        try dispatchSystem(event: "onscriptloaded", to: added)
        deliverXUIParams(forSubtreeOf: root)
    }

    @discardableResult
    func dispatchSystem(event: String, arguments: [MakiValue] = []) throws -> Int {
        try dispatch(target: MakiObjectReference(.system), event: event, arguments: arguments)
    }

    /// Last content dispatched for each host-bound text object, so `onTextChanged` fires on a *change*
    /// rather than on every poll.
    private var lastDispatchedText: [WasabiObjectID: String] = [:]

    /// Test seam: what was last announced for an object, or `nil` if nothing has been.
    func lastDispatchedTextForTesting(_ object: WasabiObject) -> String? {
        lastDispatchedText[object.stableID]
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

    @discardableResult
    func dispatch(object: WasabiObject, event: String, arguments: [MakiValue] = []) throws -> Int {
        var handled = try dispatch(target: MakiObjectReference(.gui(object.stableID)),
                                   event: event, arguments: arguments)
        // A group that embeds a control (`embed_xui`) *is* that control as far as a script that holds
        // the group is concerned, so the pointer events the child receives are the group's too. Only
        // the mouse set is carried across: those are the events the embedding exists to express, and
        // forwarding lifecycle or data events would fire a handler twice for one occurrence.
        if Self.embeddedXUIForwardedEvents.contains(event) {
            for owner in embeddingOwners(of: object) {
                handled += try dispatch(target: MakiObjectReference(.gui(owner.stableID)),
                                        event: event, arguments: arguments)
            }
        }
        return handled
    }

    private static let embeddedXUIForwardedEvents: Set<String> = [
        "onleftbuttondown", "onleftbuttonup", "onleftclick", "onleftbuttondblclk",
        "onrightbuttondown", "onrightbuttonup", "onrightclick", "onenterarea", "onleavearea"
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
        return loadedSkin.configuration.integer(section: binding.section, key: binding.key, default: 0) != 0
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
        let flipped = loadedSkin.configuration.integer(section: binding.section, key: binding.key,
                                                       default: 0) != 0 ? "0" : "1"
        setConfigAttribute(section: binding.section, key: binding.key, value: flipped)
        return true
    }

    /// Write one configuration attribute and tell the skin — the single write route, shared by a
    /// `cfgattrib` control the skin drew itself and by the host's own settings list (Phase 27.3).
    /// A second route would let the two disagree about whether the skin was notified.
    func setConfigAttribute(section: String, key: String, value: String) {
        loadedSkin.configuration.setString(value, section: section, key: key)
        for (id, state) in dynamicObjects {
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
        guard geometryMayHaveChanged, !isSettlingGeometry, !isEvaluatingLayerFX,
              let geometryDidSettle else { return }
        geometryMayHaveChanged = false
        isSettlingGeometry = true
        defer { isSettlingGeometry = false }
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
            for binding in program.bindings where program.methods[binding.methodIndex].name == eventName {
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

    func signature(for method: String, classGUID: String?) -> MakiMethodSignature? {
        if method.caseInsensitiveCompare("getcontainer") == .orderedSame,
           classGUID.map(Self.canonicalGUID) == "60906d4e482e537e94cc04b072568861" {
            return .init(argumentCount: 0, returnKind: .object)
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
            "resize": .init(argumentCount: 4, returnKind: .null),
            "show": .init(argumentCount: 0, returnKind: .null),
            "hide": .init(argumentCount: 0, returnKind: .null),
            "isvisible": .init(argumentCount: 0, returnKind: .boolean),
            "setalpha": .init(argumentCount: 1, returnKind: .null),
            "getalpha": .init(argumentCount: 0, returnKind: .integer),
            "setenabled": .init(argumentCount: 1, returnKind: .null),
            "setactivated": .init(argumentCount: 1, returnKind: .null),
            "getactivated": .init(argumentCount: 0, returnKind: .boolean),
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
            "getscale": .init(argumentCount: 0, returnKind: .float),
            "setredraw": .init(argumentCount: 1, returnKind: .null),
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
            "isplaying": .init(argumentCount: 0, returnKind: .boolean),
            "setalternatetext": .init(argumentCount: 1, returnKind: .null),
            "setfontsize": .init(argumentCount: 1, returnKind: .null),
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
            "getvolume": .init(argumentCount: 0, returnKind: .integer),
            "setvolume": .init(argumentCount: 1, returnKind: .null),
            "seekto": .init(argumentCount: 1, returnKind: .null),
            "getplayitemlength": .init(argumentCount: 0, returnKind: .integer),
            "getplaylistlength": .init(argumentCount: 0, returnKind: .integer),
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
            "strsearch": .init(argumentCount: 2, returnKind: .integer),
            "strleft": .init(argumentCount: 2, returnKind: .string),
            "strright": .init(argumentCount: 2, returnKind: .string),
            "strmid": .init(argumentCount: 3, returnKind: .string),
            // The extension of a filename, without the dot. Defix reads it off the playing item
            // (`getExtension(getPlayItemMetaDataString("filename"))`) for the display's format
            // readout, in the middle of the main layout's `onScriptLoaded` — so refusing it took the
            // rest of that handler, and the whole display area, down with it.
            "getextension": .init(argumentCount: 1, returnKind: .string),
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
            "getcurappleft": .init(argumentCount: 0, returnKind: .integer),
            "getcurapptop": .init(argumentCount: 0, returnKind: .integer),
            "getruntimeversion": .init(argumentCount: 0, returnKind: .integer),
            "getskinname": .init(argumentCount: 0, returnKind: .string),
            "getcolortheme": .init(argumentCount: 0, returnKind: .string),
            "setcolortheme": .init(argumentCount: 1, returnKind: .null),
            "getnumcolorthemes": .init(argumentCount: 0, returnKind: .integer),
            "enumcolorthemes": .init(argumentCount: 1, returnKind: .string),
            "gettimeofday": .init(argumentCount: 0, returnKind: .integer),
            "getplayitemdisplaytitle": .init(argumentCount: 0, returnKind: .string),
            "getplayitemmetadatastring": .init(argumentCount: 1, returnKind: .string),
            "getplayitemstring": .init(argumentCount: 0, returnKind: .string),
            "getstatus": .init(argumentCount: 0, returnKind: .integer),
            "getsonginfotext": .init(argumentCount: 0, returnKind: .string),
            "isvideo": .init(argumentCount: 0, returnKind: .boolean),
            "isvideofullscreen": .init(argumentCount: 0, returnKind: .boolean),
            "iskeydown": .init(argumentCount: 1, returnKind: .boolean),
            "isminimized": .init(argumentCount: 0, returnKind: .boolean),
            "isdesktopalphaavailable": .init(argumentCount: 0, returnKind: .boolean),
            "istransparencyavailable": .init(argumentCount: 0, returnKind: .boolean),
            "istransparencysafe": .init(argumentCount: 0, returnKind: .boolean),
            "islayoutanimationsafe": .init(argumentCount: 0, returnKind: .boolean),
            "hasvideosupport": .init(argumentCount: 0, returnKind: .boolean),
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
            print("CALL-TRACE \(method)(\(arguments.map(\.stringValue).joined(separator: ","))) -> \(result.stringValue)")
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
        case .system, .gui:
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
            let count = WasabiTextMetrics.componentTextProvider?()?.trackCount ?? 0
            return .integer(Int32(clamping: Int64(count)))
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
            return .null
        // The preamp is the band before band 0, on the same −127…127 scale. Rika's `eq.xml` reads it
        // while wiring its own equalizer window, and the miss aborted that whole script.
        case "geteqpreamp":
            return .integer(Int32(clamping: equalizerPreampRequested?() ?? 0))
        case "seteqpreamp":
            equalizerPreampSetterRequested?(Int(arguments[0].integerValue))
            return .null
        case "getruntimeversion": return .integer(5)
        case "getskinname": return .string(preferenceNamespace)
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
        case "getplayitemmetadatastring":
            switch arguments[0].stringValue.lowercased() {
            case "title": return .string(host.trackTitle)
            case "artist", "album": return .string(host.trackInfo)
            default: return .string("")
            }
        case "getstatus":
            switch host.playbackState {
            case .playing: return .integer(1)
            case .paused: return .integer(-1)
            case .stopped: return .integer(0)
            }
        case "getsonginfotext": return .string(host.songInfoText)
        case "isvideo", "isvideofullscreen", "iskeydown", "isminimized", "isnamedwindowvisible":
            return .boolean(false)
        case "isdesktopalphaavailable", "istransparencyavailable", "istransparencysafe", "islayoutanimationsafe":
            return .boolean(true)
        // No video *component*: a `.wal` video holder gets the neutral backing every unhosted kind
        // gets, so a skin that asks is told the truth and lays itself out without a video tab. Defix
        // asks in the same `onScriptLoaded` that positions its whole tab strip — while the question
        // was refused, the strip was never laid out and its Album Art and Video tabs sat on top of
        // each other at the x both are declared at.
        case "hasvideosupport": return .boolean(false)
        case "lockui", "unlockui", "hidenamedwindow": return .null
        case "navigateurl", "navigateurlbrowser": return .null // Sandboxed: no script-driven navigation.
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
        case "getcurrenttrackrating":
            // NullPlayer's playback `Track` carries no user rating (the library's rating lives in
            // `MediaLibrary`, which is not on the host adapter), so every track reports unrated. The
            // ClassicPro ratings widget then draws no stars instead of aborting its script.
            return .integer(0)
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

    private func invokeGUI(method: String, object: WasabiObject, arguments: [MakiValue],
                           program: MakiProgram) throws -> MakiValue {
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
            if Self.geometryKeys.contains(key.lowercased()) { noteGeometryChange() }
            notifyGraphDidMutate()
            return .null
        case "settext":
            _ = object.setAttribute("text", value: arguments[0].stringValue)
            // `setText` is also how a skin takes an alternate text back down: MMD3's ticker timer
            // fires `setText("")` a second after a `setAlternateText("VOLUME: 40%")` and expects the
            // song title back.
            _ = object.setAttribute(WasabiTextMetrics.scriptAlternateTextKey, value: "")
            notifyGraphDidMutate()
            return .null
        // What the object *shows*, not just the literal it was declared with. MMD3's songinfo timer
        // reads `getText()` off the `display="songinfo"` text and tokenises it for KBPS/KHZ; answering
        // with the (empty) `default=` attribute left both fields blank forever.
        case "gettext": return .string(WasabiTextMetrics.content(of: object, host: host))
        case "getautowidth":
            return .integer(autoWidth(of: object))
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
            noteGeometryChange()
            notifyGraphDidMutate()
            return .null
        // `onSetVisible` fires only on an actual change, as in Wasabi. ClassicPro's `beat.m` hangs its
        // VU timer off `beatGroup.onSetVisible`, and `showGroup` hides both display groups before
        // showing one — notifying unconditionally would stop and restart the timer on every refresh.
        case "show":
            let shown = object.setAttribute("visible", value: "1")
            if shown { noteGeometryChange() }
            notifyGraphDidMutate()
            if shown { _ = try dispatch(object: object, event: "onsetvisible", arguments: [.boolean(true)]) }
            return .null
        case "hide":
            let hidden = object.setAttribute("visible", value: "0")
            if hidden { noteGeometryChange() }
            notifyGraphDidMutate()
            if hidden { _ = try dispatch(object: object, event: "onsetvisible", arguments: [.boolean(false)]) }
            return .null
        case "isvisible": return .boolean(isVisible(object))
        case "setalpha":
            _ = object.setAttribute("alpha", value: String(max(0, min(255, arguments[0].integerValue))))
            notifyGraphDidMutate()
            return .null
        case "getalpha": return .integer(Int32(object.attributes["alpha"] ?? "255") ?? 255)
        case "setenabled":
            _ = object.setAttribute("enabled", value: arguments[0].truthy ? "1" : "0")
            notifyGraphDidMutate()
            return .null
        case "setactivated":
            _ = object.setAttribute("activated", value: arguments[0].truthy ? "1" : "0")
            notifyGraphDidMutate()
            _ = try dispatch(object: object, event: "ontoggle", arguments: [.boolean(arguments[0].truthy)])
            return .null
        case "getactivated": return .boolean(object.attributes["activated"] == "1")
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
        case "getleft", "getguix":
            return .integer(dimension(resolvedFrame(of: object)?.minX, declared: object.geometry.x))
        case "gettop", "getguiy":
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
        case "getposition": return .integer(Int32(object.attributes["value"] ?? object.attributes["position"] ?? "0") ?? 0)
        case "setposition":
            // Only an actual change notifies, as in Wasabi. Skins pair sliders that write each
            // other's position from their own `onSetPosition`; notifying unconditionally turns that
            // into an endless round trip.
            let position = String(arguments[0].integerValue)
            guard object.attributes["value"] != position else { return .null }
            _ = object.setAttribute("value", value: position)
            notifyGraphDidMutate()
            _ = try dispatch(object: object, event: "onsetposition", arguments: [arguments[0]])
            return .null
        case "setmode":
            _ = object.setAttribute("mode", value: arguments[0].stringValue)
            notifyGraphDidMutate()
            return .null
        case "play":
            // Stamp the clock so the frame is a pure function of elapsed time (`WasabiAnimation`),
            // which keeps the renderer and `isPlaying()` on exactly the same model.
            _ = object.setAttribute("animstart", value: String(WasabiAnimation.now()))
            _ = object.setAttribute("playing", value: "1")
            notifyGraphDidMutate()
            return .null
        case "pause", "stop":
            // Freeze where the animation actually is, not where it started.
            _ = object.setAttribute("frame", value: String(animationFrame(of: object)))
            _ = object.setAttribute("playing", value: "0")
            notifyGraphDidMutate()
            return .null
        case "gotoframe", "setframe":
            _ = object.setAttribute("frame", value: String(max(0, arguments[0].integerValue)))
            _ = object.setAttribute("playing", value: "0")
            notifyGraphDidMutate()
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
        case "isplaying":
            return .boolean(WasabiAnimation.state(of: object,
                                                  frameCount: animationFrameCount(of: object)).isPlaying)
        case "setfontsize":
            // The same pixel height the XML attribute carries, so it goes through the one
            // `WasabiTextMetrics` conversion the renderer and `getAutoWidth()` share.
            _ = object.setAttribute("fontsize", value: String(arguments[0].integerValue))
            notifyGraphDidMutate()
            return .null
        case "setalternatetext":
            // A script's alternate text *replaces* what the object shows — MMD3 puts its SEEK, VOLUME,
            // BASS and TREBLE readouts on the song ticker this way, then clears them a second later.
            // Empty restores the normal content. It is written to its own key rather than over the
            // XML `alternatetext`, which is a placeholder for "nothing to show" and must not be
            // promoted into an override (that is what pinned MMD3's display to "updating songticker").
            _ = object.setAttribute(WasabiTextMetrics.scriptAlternateTextKey,
                                    value: arguments[0].stringValue)
            notifyGraphDidMutate()
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
        case "settargetspeed": return setTarget("targetspeed", object: object, value: arguments[0])
        case "gototarget":
            for (target, actual) in [("targetx", "x"), ("targety", "y"), ("targetw", "w"),
                                     ("targeth", "h"), ("targeta", "alpha")] {
                if let value = object.attributes[target] { _ = object.setAttribute(actual, value: value) }
            }
            _ = object.setAttribute("goingtotarget", value: "0")
            notifyGraphDidMutate()
            _ = try dispatch(object: object, event: "ontargetreached")
            return .null
        case "reversetarget", "canceltarget":
            _ = object.setAttribute("goingtotarget", value: "0")
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
            _ = try dispatch(object: object, event: "onaction",
                             arguments: Array(arguments.prefix(6)) + [objectValue(source)])
            // The host action route is kept: a skin is also free to name one of NullPlayer's own
            // actions here, and nothing that used to work should stop.
            actionRequested?(arguments[0].stringValue, arguments[1].stringValue)
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
            if let attribute = object.attributes["cfgattrib"] {
                let parts = attribute.components(separatedBy: ";")
                if parts.count >= 2 {
                    return .integer(loadedSkin.configuration.integer(section: parts[0],
                                                                     key: parts[1...].joined(separator: ";"),
                                                                     default: 0))
                }
            }
            return .integer(Int32(object.attributes["value"] ?? "") ?? (object.attributes["activated"] == "1" ? 1 : 0))
        case "getscale":
            // The scene is always on the skin's own pixel grid: UI Size is applied at the view's
            // drawing/input boundary and is deliberately invisible to scripts (Phase 10), so the
            // layout's own scale is 1. ClassicPro multiplies its resize arithmetic by this.
            return .float(1)
        case "setredraw":
            // A redraw hint (`widgetsManager` throttles its list while populating). The renderer
            // repaints from the graph, so there is no suspended-drawing state to honour.
            return .null
        case "navigateurl":
            // The object form: a `<browser>`'s own navigation, as against `System.navigateUrl`.
            // Denied for the same reason — a skin script does not get to drive the network — but
            // denied *quietly*, because refusing the method aborts the handler that called it.
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
        switch method {
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
            _ = try timers.schedule(id: id, period: TimeInterval(state.delayMilliseconds) / 1_000) { [weak self] in
                guard let self else { return }
                _ = try? self.dispatch(target: reference, event: "ontimer", arguments: [])
            }
            return .boolean(true)
        case "stop":
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
            return .string(loadedSkin.configuration.string(section: section, key: key))
        case "setdata":
            guard case .configAttribute(let section, let key) = state.role else { return .null }
            loadedSkin.configuration.setString(arguments[0].stringValue, section: section, key: key)
            _ = try dispatch(target: MakiObjectReference(.dynamic(id)), event: "ondatachanged", arguments: [])
            return .null
        case "getid":
            switch state.role {
            case .configItem(let section): return .string(section)
            case .configAttribute(_, let key): return .string(key)
            case .map(let bitmapID, _): return .string(bitmapID)
            case .region(let clip): return .string(clip.mapID)
            case .xmlDocument: return .string("")
            case .configGroup(let section): return .string(section)
            case .generic: return .string("dynamic_\(id)")
            }
        case "init", "callme", "ondatachanged": return .null
        default:
            if let value = classicProFileMethod(method, arguments: arguments) { return value }
            throw unsupported(method, program: program)
        }
    }

    private func findRoot(type: String, xmlID: String) -> WasabiObject? {
        loadedSkin.runtime.graph.roots.first {
            $0.typeName.caseInsensitiveCompare(type) == .orderedSame &&
            $0.xmlID?.caseInsensitiveCompare(xmlID) == .orderedSame
        }
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
    private func isInvalid(_ object: WasabiObject) -> Bool {
        guard let imageID = object.attributes["image"] ?? object.attributes["bitmap"] else { return false }
        guard let definition = loadedSkin.runtime.resources.resolvedDefinition(identifier: imageID),
              definition.kind == "bitmap" else { return true }
        // Generated bitmaps (`file="$solid"`) carry no file and are perfectly valid.
        if definition.attributes["file"]?.hasPrefix("$") == true { return false }
        return definition.logicalFile == nil
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

    /// Compiled MAKI stores class IDs as four little-endian 32-bit words.
    /// Normalize them to the compact string form used by std.mi.
    private static func canonicalGUID(_ raw: String) -> String {
        guard raw.count == 32 else { return raw.lowercased() }
        let bytes = stride(from: 0, to: raw.count, by: 2).map { offset -> String in
            let start = raw.index(raw.startIndex, offsetBy: offset)
            let end = raw.index(start, offsetBy: 2)
            return String(raw[start..<end])
        }
        var ordered: [String] = []
        for start in stride(from: 0, to: 16, by: 4) {
            ordered.append(contentsOf: bytes[start..<(start + 4)].reversed())
        }
        return ordered.joined().lowercased()
    }

    private func unsupported(_ method: String, program: MakiProgram) -> WalFailure {
        unsupportedMethodCalls[method.lowercased(), default: 0] += 1
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
        actionRequested = nil
        themeNamesRequested = nil
        activeThemeRequested = nil
        themeSwitchRequested = nil
        dispatchObserver = nil
        resolvedGeometryRequested = nil
        mousePositionInObjectSpaceRequested = nil
        geometryDidSettle = nil
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
