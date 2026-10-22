import AppKit
import CoreGraphics
import Foundation

/// Every layer's FX configuration and its last evaluated warp.
struct WinampModernLayerFXStore {
    /// Per-layer FX configuration, written by the `fx_set*` methods.
    private var states: [WasabiObjectID: WasabiLayerFXState] = [:]
    /// The last evaluated mesh per layer, reused until the skin calls `fx_update()` (or always
    /// re-evaluated when it asked for `fx_setRealtime(1)`).
    private var meshes: [WasabiObjectID: WasabiLayerFXMesh] = [:]
    private var stale: Set<WasabiObjectID> = []
    /// While a mesh is being evaluated, the callbacks run *inside a repaint*. A script that touched
    /// the graph from one would ask for another repaint and settle geometry mid-draw, so both are
    /// suppressed for the duration and the pending repaint is the one already in flight.
    fileprivate(set) var isEvaluating = false

    func state(of id: WasabiObjectID) -> WasabiLayerFXState? { states[id] }
    var hasEnabled: Bool { states.values.contains { $0.enabled } }
    var enabled: [(id: WasabiObjectID, state: WasabiLayerFXState)] {
        states.compactMap { $0.value.enabled ? ($0.key, $0.value) : nil }
    }

    /// Writes a layer's configuration and marks its mesh stale.
    mutating func set(_ state: WasabiLayerFXState, for id: WasabiObjectID) {
        states[id] = state
        stale.insert(id)
    }

    mutating func invalidate(_ id: WasabiObjectID) { stale.insert(id) }
    func isStale(_ id: WasabiObjectID) -> Bool { stale.contains(id) }
    /// The layer's mesh, unless it is stale or was never evaluated.
    func freshMesh(for id: WasabiObjectID) -> WasabiLayerFXMesh? { stale.contains(id) ? nil : meshes[id] }

    mutating func store(_ mesh: WasabiLayerFXMesh, for id: WasabiObjectID) {
        meshes[id] = mesh
        stale.remove(id)
    }
}

/// Layer FX: the per-object state, the evaluated mesh and the `fx_*` callbacks. Split out of
/// `WinampModernScriptRuntime.swift`.
extension WinampModernScriptRuntime {
    /// Total vertices one layer may ask the interpreter to evaluate per mesh. `fx_setGridSize` takes
    /// script variables, so a skin can name any grid at all; this is what keeps a bad number off the
    /// UI thread. 65×65 covers every measured grid with room to spare (Defix asks for 1×1 on its
    /// cassette reels).
    static let maximumLayerFXVertices = 65 * 65

    /// `WINAMP_MODERN_FX_TRACE=1` prints every `fx_*` call with its receiver — how "which layers does
    /// this skin warp, and when does it switch them on?" is answered without a debugger.
    static let tracesLayerFX = ProcessInfo.processInfo.environment["WINAMP_MODERN_FX_TRACE"] != nil

    /// The FX configuration a layer's script has set, or `nil` when it has never called one.
    func layerFXState(of object: WasabiObject) -> WasabiLayerFXState? { layerFX.state(of: object.stableID) }

    /// Whether any layer in this skin currently has FX switched on — the signal a window uses to
    /// decide it needs the 30 Hz repaint clock.
    var hasEnabledLayerFX: Bool { layerFX.hasEnabled }

    /// Every layer with FX switched on, for the render harness (`WINAMP_MODERN_RENDER_FX=1`). The
    /// warp itself can only be seen under playback, but *which* layers are warped, how they are
    /// configured and how far the mesh moves are all answerable headlessly.
    var enabledLayerFXObjects: [WasabiObject] {
        layerFX.enabled.compactMap { loadedSkin.runtime.graph.object(withID: $0.id) }
    }

    /// The warp for one layer, or `nil` when the layer has no enabled FX (the overwhelming majority —
    /// this is checked for every object in every frame, so the miss has to be a dictionary lookup).
    func layerFXMesh(for object: WasabiObject) -> WasabiLayerFXMesh? {
        guard !isTornDown, !layerFX.isEvaluating else { return nil }
        guard let state = layerFX.state(of: object.stableID), state.enabled else { return nil }
        if let cached = layerFX.freshMesh(for: object.stableID) {
            return cached.isIdentity ? nil : cached
        }
        let mesh = evaluateLayerFXMesh(for: object, state: state)
        layerFX.store(mesh, for: object.stableID)
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
    /// realtime layer is marked stale on each pass rather than re-evaluated inside the draw. It also
    /// hears `fx_onFrame` first: wTunes' VU needle reads `getLeftVuMeter()` there, and its
    /// `fx_onGetPixelR` only answers the angle that handler stored.
    func refreshLayerFXMeshes() {
        guard !isTornDown, !layerFX.isEvaluating else { return }
        for (id, state) in layerFX.enabled {
            if state.realtime {
                _ = try? dispatch(target: MakiObjectReference(.gui(id)), event: "fx_onFrame", arguments: [])
                layerFX.invalidate(id)
            }
            guard layerFX.isStale(id),
                  let object = loadedSkin.runtime.graph.object(withID: id) else { continue }
            // Evaluated first: the callbacks may write `layerFX` themselves.
            let mesh = evaluateLayerFXMesh(for: object, state: state)
            layerFX.store(mesh, for: id)
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
        layerFX.invalidate(object.stableID)
    }

    /// Whether this layer's warp is still waiting to be evaluated — the state `refreshLayerFXMeshes`
    /// exists to clear before the frame is painted rather than during it.
    func layerFXMeshIsPending(for object: WasabiObject) -> Bool {
        layerFX.isStale(object.stableID)
    }

    func evaluateLayerFXMesh(for object: WasabiObject,
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
        layerFX.isEvaluating = true
        defer { layerFX.isEvaluating = false }
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
        var state = layerFX.state(of: object.stableID) ?? WasabiLayerFXState()
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
            layerFX.set(state, for: object.stableID)
            requestRepaint(for: object)
            return .null
        default: return .null
        }
        layerFX.set(state, for: object.stableID)
        requestRepaint(for: object)
        return .null
    }
}
