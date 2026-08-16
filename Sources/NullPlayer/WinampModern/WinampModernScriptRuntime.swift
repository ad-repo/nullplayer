import AppKit
import Foundation

final class WinampModernScriptRuntime: MakiMethodDispatching {
    private enum DynamicRole {
        case generic
        case configItem(section: String)
        case configAttribute(section: String, key: String)
        /// A `Map` that has been given its bitmap. `new Map` and `new Timer` are indistinguishable at
        /// construction (the class GUIDs are not part of the archive), so the role is settled by the
        /// first call that only one of them accepts — here, `loadMap`.
        case map(bitmapID: String)
    }

    private struct DynamicObjectState {
        var role: DynamicRole = .generic
        var delayMilliseconds: Int32 = 5_000
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
    var popupPresenter: (([(String, Int32, Bool, Bool)]) -> Int32)?
    var layoutSwitchRequested: ((String) -> Bool)?
    var layoutResizeRequested: ((CGSize) -> Void)?
    var actionRequested: ((String, String?) -> Void)?
    var themeNamesRequested: (() -> [String])?
    var activeThemeRequested: (() -> String)?
    var themeSwitchRequested: ((String) -> Bool)?
    /// Cursor position in the *skin's own pixel space* — the same units as the x/y a mouse event hands
    /// a script, which rotary-knob scripts combine in a single expression.
    var mousePositionRequested: (() -> CGPoint)?
    /// Whether the equalizer is on, for `System.getEQ()`.
    var equalizerEnabledRequested: (() -> Bool)?
    /// One EQ band, on MAKI's −127…127 scale (MMD3's bass/treble knobs read and write the bands).
    var equalizerBandRequested: ((Int) -> Int)?
    var equalizerBandSetterRequested: ((Int, Int) -> Void)?

    private struct ScriptEventKey: Hashable {
        let target: MakiObjectReference.Kind
        let event: String
    }
    /// Events currently on the interpreter stack. A skin can wire two objects to update each other
    /// (MMD3's seek slider and its ghost both call `setPosition` from the other's `onSetPosition`),
    /// which is a bounded ping-pong in Winamp but unbounded native recursion here — and native
    /// recursion is not something the interpreter's own call-depth budget can see.
    private var eventsBeingDispatched: Set<ScriptEventKey> = []

    private var nextPopupID: UInt64 = 1
    private var popupCommands: [UInt64: [(String, Int32, Bool, Bool)]] = [:]
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
    private var mapImages: [String: CGImage] = [:]
    private static let maximumCachedMaps = 16
    /// Ceiling on total loaded programs. Runtime instantiation (`System.newGroup`) can add scripts,
    /// so this bounds a skin that instantiates groups in a loop.
    private static let maximumRuntimePrograms = 512

    /// Standard GUI events a script is allowed to invoke as a method on an object, with their argument
    /// counts. Kept explicit: an unknown arity would desynchronise the interpreter's stack.
    private static let dispatchableEventArity: [String: Int] = [
        "onsetposition": 1,
        "onsetfinalposition": 1,
        "onpostedposition": 1,
        "onleftclick": 0,
        "onrightclick": 0,
        "ontargetreached": 0,
        "ontoggle": 1
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
        try dispatchSystem(event: "onscriptloaded")
        deliverXUIParams(for: loadedSkin.runtime.graph.roots)
    }

    /// Wasabi hands a XUI object's XML attributes to its script as `onSetXuiParam(name, value)`.
    /// Winamp Modern's window frames rely on this entirely: `Wasabi:MainFrame:NoStatus
    /// content="player.content.group"` is inert XML until the script sees the `content` param and
    /// instantiates that group.
    ///
    /// Must run *after* `onScriptLoaded`: the handler is bound to the script's own group variable,
    /// which the script only populates via `getScriptGroup()` inside `onScriptLoaded`. Dispatched
    /// before that, no binding matches and every param is silently dropped.
    private func deliverXUIParams(for objects: [WasabiObject]) {
        for object in objects {
            if loadedSkin.runtime.types.isXUITag(object.typeName), !object.scriptBindings.isEmpty {
                // `onSetXuiParam` is a *System* event, and each XUI instance gets its own program
                // instance, so the params must go only to the programs that instance owns —
                // dispatching to every program would hand one frame's `content` to all of them.
                let owned = programs.filter { $0.ownerID == object.stableID }
                for (name, value) in object.attributes.sorted(by: { $0.key < $1.key }) where !owned.isEmpty {
                    _ = try? dispatch(target: MakiObjectReference(.system), event: "onsetxuiparam",
                                      arguments: [.string(name), .string(value)], in: owned)
                }
            }
            deliverXUIParams(for: object.children)
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
        let text = object.attributes["text"] ?? object.attributes["default"] ?? ""
        let charWidth = Int32(Double(object.attributes["fontsize"] ?? "11") ?? 11) * 3 / 5
        return max(0, Int32(clamping: text.count) * max(1, charWidth))
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
    private func mapPixel(bitmapID: String, x: Int, y: Int) -> (red: UInt8, alpha: UInt8, inBounds: Bool) {
        guard let image = mapImage(bitmapID: bitmapID) else { return (0, 0, false) }
        guard x >= 0, y >= 0, x < image.width, y < image.height else { return (0, 0, false) }
        let bitmap = WasabiBitmap(image: image, width: image.width, height: image.height, cost: 0)
        guard let pixel = bitmap.pixel(at: CGPoint(x: x, y: y)) else { return (0, 0, false) }
        return (pixel.red, pixel.alpha, true)
    }

    private func mapImage(bitmapID: String) -> CGImage? {
        let key = bitmapID.lowercased()
        if let cached = mapImages[key] { return cached }
        guard mapImages.count < Self.maximumCachedMaps,
              let definition = loadedSkin.runtime.resources.resolvedDefinition(identifier: bitmapID),
              definition.kind == "bitmap", let path = definition.logicalFile,
              let data = try? loadedSkin.vfs.data(at: path, location: definition.source),
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
        mapImages[key] = image
        return image
    }

    /// Load and start the scripts a runtime-instantiated subtree declares, so nested components come
    /// up exactly as they would have at load time. Bounded by `maximumRuntimePrograms` so a script
    /// cannot grow the program list without limit by instantiating groups in a loop.
    private func startScripts(addedBeneath root: WasabiObject) throws {
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
        deliverXUIParams(for: [root])
    }

    @discardableResult
    func dispatchSystem(event: String, arguments: [MakiValue] = []) throws -> Int {
        try dispatch(target: MakiObjectReference(.system), event: event, arguments: arguments)
    }

    @discardableResult
    func dispatch(object: WasabiObject, event: String, arguments: [MakiValue] = []) throws -> Int {
        try dispatch(target: MakiObjectReference(.gui(object.stableID)), event: event, arguments: arguments)
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

    private func dispatch(target: MakiObjectReference, event: String,
                          arguments: [MakiValue], in subset: [MakiProgram]? = nil) throws -> Int {
        guard !isTornDown else { return 0 }
        let eventName = event.lowercased()
        let key = ScriptEventKey(target: target.kind, event: eventName)
        guard eventsBeingDispatched.insert(key).inserted else { return 0 }
        defer { eventsBeingDispatched.remove(key) }
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
                    try interpreter.execute(program: program, at: binding.instructionIndex,
                                            arguments: arguments)
                    executed += 1
                } catch let failure as WalFailure {
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

    func signature(for method: String, classGUID: String?) -> MakiMethodSignature? {
        if method.caseInsensitiveCompare("getcontainer") == .orderedSame,
           classGUID.map(Self.canonicalGUID) == "60906d4e482e537e94cc04b072568861" {
            return .init(argumentCount: 0, returnKind: .object)
        }
        let signatures: [String: MakiMethodSignature] = [
            "getcontainer": .init(argumentCount: 1, returnKind: .object),
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
            "leftclick": .init(argumentCount: 0, returnKind: .null),
            // `Map`: a bitmap sampled by the script (the knob-angle lookup MMD3 drives its rotary
            // controls with). `new Map` yields a generic dynamic object; `loadMap` gives it its role.
            "loadmap": .init(argumentCount: 1, returnKind: .null),
            "inregion": .init(argumentCount: 2, returnKind: .boolean),
            "getvalue": .init(argumentCount: 2, returnKind: .integer),
            // Screen-space cursor position, in the same skin-pixel units as the x/y a mouse event
            // hands the script — the knob scripts mix the two in one expression.
            "getmouseposx": .init(argumentCount: 0, returnKind: .integer),
            "getmouseposy": .init(argumentCount: 0, returnKind: .integer),
            "atan": .init(argumentCount: 1, returnKind: .float),
            "geteq": .init(argumentCount: 0, returnKind: .integer),
            "geteqband": .init(argumentCount: 1, returnKind: .integer),
            "seteqband": .init(argumentCount: 2, returnKind: .null),
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
            "getvolume": .init(argumentCount: 0, returnKind: .integer),
            "setvolume": .init(argumentCount: 1, returnKind: .null),
            "seekto": .init(argumentCount: 1, returnKind: .null),
            "getplayitemlength": .init(argumentCount: 0, returnKind: .integer),
            "integertostring": .init(argumentCount: 1, returnKind: .string),
            "integertotime": .init(argumentCount: 1, returnKind: .string),
            "floattostring": .init(argumentCount: 2, returnKind: .string),
            "stringtointeger": .init(argumentCount: 1, returnKind: .integer),
            "strlen": .init(argumentCount: 1, returnKind: .integer),
            "strlower": .init(argumentCount: 1, returnKind: .string),
            "strsearch": .init(argumentCount: 2, returnKind: .integer),
            "strleft": .init(argumentCount: 2, returnKind: .string),
            "strright": .init(argumentCount: 2, returnKind: .string),
            "strmid": .init(argumentCount: 3, returnKind: .string),
            "translate": .init(argumentCount: 1, returnKind: .string),
            "getprivateint": .init(argumentCount: 3, returnKind: .integer),
            "setprivateint": .init(argumentCount: 3, returnKind: .null),
            "getitem": .init(argumentCount: 1, returnKind: .object),
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
            "lockui": .init(argumentCount: 0, returnKind: .null),
            "unlockui": .init(argumentCount: 0, returnKind: .null),
            "hidenamedwindow": .init(argumentCount: 1, returnKind: .null),
            "isnamedwindowvisible": .init(argumentCount: 1, returnKind: .boolean),
            "navigateurl": .init(argumentCount: 1, returnKind: .null),
            "navigateurlbrowser": .init(argumentCount: 1, returnKind: .null),
            "addcommand": .init(argumentCount: 4, returnKind: .null),
            "addseparator": .init(argumentCount: 0, returnKind: .null),
            "checkcommand": .init(argumentCount: 2, returnKind: .null),
            "popatmouse": .init(argumentCount: 0, returnKind: .integer),
            "newgroup": .init(argumentCount: 1, returnKind: .object),
            "init": .init(argumentCount: 1, returnKind: .null),
            "messagebox": .init(argumentCount: 4, returnKind: .integer),
            "callme": .init(argumentCount: 1, returnKind: .null),
            // ClassicPro version gate (branch, not hard-block) + public config.
            "getbuildnumber": .init(argumentCount: 0, returnKind: .integer),
            "getwinampversion": .init(argumentCount: 0, returnKind: .string),
            "getpublicint": .init(argumentCount: 2, returnKind: .integer),
            "setpublicint": .init(argumentCount: 2, returnKind: .null),
            "getdate": .init(argumentCount: 0, returnKind: .integer),
            "getdatedoy": .init(argumentCount: 1, returnKind: .integer),
            // ClassicPro `ClassicProFile` shell service (the entire native surface, P0B §1).
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
            return .init(argumentCount: arity, returnKind: .null)
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
        switch method {
        case "getcontainer":
            return objectValue(findRoot(type: "container", xmlID: arguments[0].stringValue))
        case "getscriptgroup":
            return objectValue(program.ownerID.flatMap(loadedSkin.runtime.graph.object(withID:)))
        case "getparam": return .string(program.parameter ?? "")
        case "gettoken":
            let tokens = arguments[0].stringValue.components(separatedBy: arguments[1].stringValue)
            let index = Int(arguments[2].integerValue)
            return .string(tokens.indices.contains(index) ? tokens[index] : "")
        case "getleftvumeter": return .integer(vuValue(left: true))
        case "getrightvumeter": return .integer(vuValue(left: false))
        case "getvolume": return .integer(Int32((host.volume * 255).rounded()))
        case "setvolume":
            host.volume = Double(arguments[0].integerValue) / 255
            return .null
        case "play": host.play(); return .null
        case "pause": host.pause(); return .null
        case "stop": host.stop(); return .null
        case "seekto":
            host.seek(to: TimeInterval(arguments[0].integerValue))
            return .null
        case "getplayitemlength": return .integer(Int32(clamping: Int64(host.duration)))
        case "integertostring": return .string(String(arguments[0].integerValue))
        case "integertotime":
            let seconds = max(0, Int(arguments[0].integerValue))
            return .string(String(format: "%d:%02d", seconds / 60, seconds % 60))
        case "floattostring":
            let digits = max(0, min(12, Int(arguments[1].integerValue)))
            return .string(String(format: "%.*f", digits, arguments[0].doubleValue))
        case "stringtointeger": return .integer(Int32(arguments[0].stringValue) ?? 0)
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
        case "getitem":
            return dynamicValue(role: .configItem(section: arguments[0].stringValue))
        case "newitem":
            return dynamicValue(role: .configItem(section: arguments[1].stringValue.isEmpty
                                                   ? arguments[0].stringValue : arguments[1].stringValue))
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
        case "geteq": return .integer((equalizerEnabledRequested?() ?? false) ? 1 : 0)
        case "geteqband":
            return .integer(Int32(clamping: equalizerBandRequested?(Int(arguments[0].integerValue)) ?? 0))
        case "seteqband":
            equalizerBandSetterRequested?(Int(arguments[0].integerValue), Int(arguments[1].integerValue))
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
        case "lockui", "unlockui", "hidenamedwindow": return .null
        case "navigateurl", "navigateurlbrowser": return .null // Sandboxed: no script-driven navigation.
        case "newgroup":
            // Wasabi creates the group as a child of the calling script's own group; the script then
            // positions it with `setXmlParam`. This is how Winamp Modern fills a window frame's
            // client area (`content=` → `newGroup` → the whole player UI).
            guard let owner = program.ownerID.flatMap(loadedSkin.runtime.graph.object(withID:)),
                  let instantiate = loadedSkin.runtime.instantiateGroup else { return .null }
            let created = try instantiate(arguments[0].stringValue, owner)
            try startScripts(addedBeneath: created)
            graphDidMutate?()
            return objectValue(created)
        case "messagebox": return .integer(0) // Sandboxed: skins cannot create modal host UI.
        // ClassicPro version gate + public config (see `reportedWinampBuild`).
        case "getbuildnumber": return .integer(Self.reportedWinampBuild)
        case "getwinampversion": return .string(Self.reportedWinampVersion)
        case "getpublicint":
            return .integer(loadedSkin.configuration.integer(section: "@public",
                                                             key: arguments[0].stringValue,
                                                             default: arguments[1].integerValue))
        case "setpublicint":
            loadedSkin.configuration.setInteger(arguments[1].integerValue,
                                                section: "@public", key: arguments[0].stringValue)
            return .null
        case "getdate": return .integer(Int32(truncatingIfNeeded: Int64(Date().timeIntervalSince1970)))
        case "getdatedoy":
            return .integer(Int32(Calendar.current.ordinality(of: .day, in: .year, for: Date()) ?? 0))
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
            return .null
        }
        switch method {
        case "getlayout":
            return objectValue(object.children.first {
                $0.typeName.caseInsensitiveCompare("layout") == .orderedSame &&
                $0.xmlID?.caseInsensitiveCompare(arguments[0].stringValue) == .orderedSame
            } ?? descendant(of: object, xmlID: arguments[0].stringValue))
        case "getobject", "findobject":
            return objectValue(descendant(of: object, xmlID: arguments[0].stringValue))
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
            _ = layoutSwitchRequested?(arguments[0].stringValue)
            _ = try dispatch(object: object, event: "onswitchtolayout", arguments: [objectValue(next)])
            return .null
        case "getid": return .string(object.xmlID ?? "")
        case "getparent": return objectValue(object.parent)
        case "getparentlayout": return objectValue(ancestor(of: object, type: "layout"))
        case "getxmlparam": return .string(object.attributes[arguments[0].stringValue.lowercased()] ?? "")
        case "setxmlparam":
            _ = object.setAttribute(arguments[0].stringValue, value: arguments[1].stringValue)
            graphDidMutate?()
            return .null
        case "settext":
            _ = object.setAttribute("text", value: arguments[0].stringValue)
            graphDidMutate?()
            return .null
        case "gettext": return .string(object.attributes["text"] ?? object.attributes["default"] ?? "")
        case "getautowidth":
            return .integer(autoWidth(of: object))
        case "resize":
            for (key, value) in zip(["x", "y", "w", "h"], arguments) {
                _ = object.setAttribute(key, value: String(value.integerValue))
            }
            if object.typeName.caseInsensitiveCompare("layout") == .orderedSame {
                layoutResizeRequested?(CGSize(width: CGFloat(arguments[2].integerValue),
                                              height: CGFloat(arguments[3].integerValue)))
            }
            graphDidMutate?()
            return .null
        case "show":
            _ = object.setAttribute("visible", value: "1")
            graphDidMutate?()
            return .null
        case "hide":
            _ = object.setAttribute("visible", value: "0")
            graphDidMutate?()
            return .null
        case "isvisible": return .boolean(isVisible(object))
        case "setalpha":
            _ = object.setAttribute("alpha", value: String(max(0, min(255, arguments[0].integerValue))))
            graphDidMutate?()
            return .null
        case "getalpha": return .integer(Int32(object.attributes["alpha"] ?? "255") ?? 255)
        case "setenabled":
            _ = object.setAttribute("enabled", value: arguments[0].truthy ? "1" : "0")
            graphDidMutate?()
            return .null
        case "setactivated":
            _ = object.setAttribute("activated", value: arguments[0].truthy ? "1" : "0")
            graphDidMutate?()
            _ = try dispatch(object: object, event: "ontoggle", arguments: [.boolean(arguments[0].truthy)])
            return .null
        case "getactivated": return .boolean(object.attributes["activated"] == "1")
        case "getleft", "getguix": return .integer(Int32(object.geometry.x))
        case "gettop", "getguiy": return .integer(Int32(object.geometry.y))
        case "getwidth", "getguiw": return .integer(Int32(object.geometry.width ?? 0))
        case "getheight", "getguih": return .integer(Int32(object.geometry.height ?? 0))
        case "getposition": return .integer(Int32(object.attributes["value"] ?? object.attributes["position"] ?? "0") ?? 0)
        case "setposition":
            // Only an actual change notifies, as in Wasabi. Skins pair sliders that write each
            // other's position from their own `onSetPosition`; notifying unconditionally turns that
            // into an endless round trip.
            let position = String(arguments[0].integerValue)
            guard object.attributes["value"] != position else { return .null }
            _ = object.setAttribute("value", value: position)
            graphDidMutate?()
            _ = try dispatch(object: object, event: "onsetposition", arguments: [arguments[0]])
            return .null
        case "setmode":
            _ = object.setAttribute("mode", value: arguments[0].stringValue)
            graphDidMutate?()
            return .null
        case "play":
            // Stamp the clock so the frame is a pure function of elapsed time (`WasabiAnimation`),
            // which keeps the renderer and `isPlaying()` on exactly the same model.
            _ = object.setAttribute("animstart", value: String(WasabiAnimation.now()))
            _ = object.setAttribute("playing", value: "1")
            graphDidMutate?()
            return .null
        case "pause", "stop":
            // Freeze where the animation actually is, not where it started.
            _ = object.setAttribute("frame", value: String(animationFrame(of: object)))
            _ = object.setAttribute("playing", value: "0")
            graphDidMutate?()
            return .null
        case "gotoframe", "setframe":
            _ = object.setAttribute("frame", value: String(max(0, arguments[0].integerValue)))
            _ = object.setAttribute("playing", value: "0")
            graphDidMutate?()
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
        case "setalternatetext":
            // A `songticker`'s alternate text temporarily replaces the track title (volume readouts,
            // hints). An empty string restores the normal content.
            _ = object.setAttribute("alternatetext", value: arguments[0].stringValue)
            graphDidMutate?()
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
            graphDidMutate?()
            _ = try dispatch(object: object, event: "ontargetreached")
            return .null
        case "reversetarget", "canceltarget":
            _ = object.setAttribute("goingtotarget", value: "0")
            return .null
        case "isgoingtotarget": return .boolean(object.attributes["goingtotarget"] == "1")
        case "sendaction":
            actionRequested?(arguments[0].stringValue, arguments[1].stringValue)
            return .null
        case "triggeraction":
            actionRequested?(arguments[0].stringValue, arguments[1].stringValue)
            return .null
        case "islayoutanimationsafe", "istransparencysafe": return .boolean(true)
        case "init", "callme", "ondatachanged": return .null
        default:
            throw unsupported(method, program: program)
        }
    }

    private func invokePopup(method: String, id: UInt64, arguments: [MakiValue]) -> MakiValue {
        switch method {
        case "addcommand":
            popupCommands[id, default: []].append((arguments[0].stringValue, arguments[1].integerValue,
                                                   arguments[2].truthy, arguments[3].truthy))
            return .null
        case "addseparator":
            popupCommands[id, default: []].append(("", 0, false, true))
            return .null
        case "checkcommand":
            let commandID = arguments[0].integerValue
            if let index = popupCommands[id]?.firstIndex(where: { $0.1 == commandID }) {
                let old = popupCommands[id]![index]
                popupCommands[id]![index] = (old.0, old.1, arguments[1].truthy, old.3)
            }
            return .null
        case "popatmouse": return .integer(popupPresenter?(popupCommands[id] ?? []) ?? 0)
        default: return .null
        }
    }

    private func invokeDynamic(method: String, id: UInt64, arguments: [MakiValue],
                               program: MakiProgram) throws -> MakiValue {
        guard var state = dynamicObjects[id] else { return .null }
        switch method {
        case "loadmap":
            state.role = .map(bitmapID: arguments[0].stringValue)
            dynamicObjects[id] = state
            return .null
        case "inregion", "getvalue":
            guard case .map(let bitmapID) = state.role else { return method == "inregion" ? .boolean(false) : .integer(0) }
            let sample = mapPixel(bitmapID: bitmapID,
                                  x: Int(arguments[0].integerValue), y: Int(arguments[1].integerValue))
            if method == "inregion" {
                // A map with an alpha channel masks its region; MMD3's are opaque grayscale, where
                // being inside the bitmap *is* being in the region.
                return .boolean(sample.inBounds && sample.alpha > 0)
            }
            return .integer(Int32(sample.red))
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
            case .map(let bitmapID): return .string(bitmapID)
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

    private func objectValue(_ object: WasabiObject?) -> MakiValue {
        object.map { .object(MakiObjectReference(.gui($0.stableID))) } ?? .null
    }

    private func object(_ value: MakiValue, equals reference: MakiObjectReference) -> Bool {
        guard case .object(let candidate) = value else { return false }
        return candidate == reference
    }

    private func vuValue(left: Bool) -> Int32 {
        let levels = host.spectrumLevels
        guard !levels.isEmpty else { return 0 }
        let range = left ? levels.prefix((levels.count + 1) / 2) : levels.suffix(levels.count / 2)
        return Int32(max(0, min(255, (range.max() ?? 0) * 255)))
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
        graphDidMutate = nil
        popupPresenter = nil
        layoutSwitchRequested = nil
        layoutResizeRequested = nil
        actionRequested = nil
        themeNamesRequested = nil
        activeThemeRequested = nil
        themeSwitchRequested = nil
        timers.teardown()
        interpreter.teardown()
        host.endVisualizationConsumption()
        programs.removeAll()
        popupCommands.removeAll()
        dynamicObjects.removeAll()
        activeLayoutByContainer.removeAll()
        isTornDown = true
    }

    deinit { teardown() }
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
