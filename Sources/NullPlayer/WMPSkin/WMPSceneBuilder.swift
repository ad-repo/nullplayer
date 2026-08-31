import CoreGraphics
import Foundation

struct WMPSceneBuilder: @unchecked Sendable {
    let loadedSkin: WMPLoadedSkin
    let imageStore: WMPImageStore

    init(loadedSkin: WMPLoadedSkin, imageStore: WMPImageStore? = nil) {
        self.loadedSkin = loadedSkin
        self.imageStore = imageStore ?? WMPImageStore(provider: loadedSkin.archive)
    }

    /// Layout, resource resolution, and image metadata/decode stay off the main thread even when a
    /// UI caller initiates the transaction.
    func build(viewID: String, requestedSize: WMPSize? = nil) async throws -> WMPScene {
        try await Task.detached(priority: .userInitiated) {
            try buildOffMain(viewID: viewID, requestedSize: requestedSize)
        }.value
    }

    private func buildOffMain(viewID: String, requestedSize: WMPSize?) throws -> WMPScene {
        guard let registration = loadedSkin.views.first(where: {
            $0.id.caseInsensitiveCompare(viewID) == .orderedSame
        }) else {
            throw WMPFailure(WMPDiagnostic(.invalidGeometry, "WMP view '\(viewID)' does not exist."))
        }
        let view = registration.node
        guard let authoredWidth = literal(view, "width"), authoredWidth > 0,
              let authoredHeight = literal(view, "height"), authoredHeight > 0 else {
            throw WMPFailure(WMPDiagnostic(.invalidGeometry,
                "View '\(viewID)' requires positive literal width and height for static layout.",
                location: view.location))
        }
        let minimum = WMPSize(width: literal(view, "minWidth") ?? authoredWidth,
                              height: literal(view, "minHeight") ?? authoredHeight)
        let maxWidth = literal(view, "maxWidth"), maxHeight = literal(view, "maxHeight")
        let maximum: WMPSize? = maxWidth == nil && maxHeight == nil ? nil
            : WMPSize(width: maxWidth ?? .greatestFiniteMagnitude,
                      height: maxHeight ?? .greatestFiniteMagnitude)
        let resizeLimits = WMPResizeLimits(minimum: minimum, maximum: maximum)
        let canvas = resizeLimits.clamp(requestedSize ?? WMPSize(width: authoredWidth, height: authoredHeight))
        let canvasRect = WMPRect(x: 0, y: 0, width: canvas.width, height: canvas.height)

        var commands: [WMPPaintCommand] = []
        var hits: [WMPHitMetadata] = []
        var geometries: [Int: WMPResolvedGeometry] = [:]
        var unresolved: [WMPUnresolvedGeometry] = []
        var diagnostics = loadedSkin.diagnostics
        var unresolvedNodes = Set<Int>()
        var unresolvedAttributes = Set<String>()
        var resolvedNodes = Set<Int>()
        var layoutResolver = WMPInitialLayoutResolver(graph: loadedSkin.graph, view: view, canvas: canvas)

        func recordUnresolved(_ node: WMPNode, attribute: String, value: String) {
            let key = "\(node.stableID):\(attribute.lowercased())"
            guard unresolvedAttributes.insert(key).inserted else { return }
            unresolved.append(WMPUnresolvedGeometry(stableID: node.stableID, nodeID: node.xmlID,
                                                    attribute: attribute, authoredValue: value))
            unresolvedNodes.insert(node.stableID)
            diagnostics.append(WMPDiagnostic(.unresolvedGeometry,
                "Static layout cannot resolve \(node.authoredTagName).\(attribute)='\(value)'.",
                severity: .warning, location: node.location))
        }

        func parseDimension(_ node: WMPNode, _ name: String) -> CGFloat? {
            guard let property = WMPInitialLayoutResolver.Property(rawValue: name.lowercased()) else { return nil }
            switch layoutResolver.resolve(node, property: property) {
            case let .value(value): return value
            case let .unresolved(reason):
                guard let attribute = node.attribute(named: name) else { return nil }
                recordUnresolved(node, attribute: name, value: "\(attribute.rawValue) [\(reason)]")
                return nil
            }
        }

        func resource(_ node: WMPNode, names: [String]) throws -> (String, String)? {
            for name in names {
                guard let attribute = node.attribute(named: name) else { continue }
                guard case let .resource(authored) = attribute.value else { continue }
                if let path = try loadedSkin.archive.resolve(authored, relativeTo: loadedSkin.definitionPath) {
                    return (name, path)
                }
            }
            return nil
        }

        func walk(_ node: WMPNode, parentFrame: WMPRect, parentAuthoredSize: WMPSize,
                  inheritedClip: WMPRect?, isRoot: Bool = false) throws {
            if literalString(node, "visible")?.caseInsensitiveCompare("false") == .orderedSame { return }
            if isNonLayout(node.kind) {
                for child in node.children.sorted(by: nodeOrder) {
                    try walk(child, parentFrame: parentFrame, parentAuthoredSize: parentAuthoredSize,
                             inheritedClip: inheritedClip)
                }
                return
            }

            let frame: WMPRect
            if isRoot {
                frame = canvasRect
            } else {
                let leftAttribute = node.attribute(named: "left")
                let topAttribute = node.attribute(named: "top")
                let left = leftAttribute == nil ? 0 : parseDimension(node, "left")
                let top = topAttribute == nil ? 0 : parseDimension(node, "top")
                var width = parseDimension(node, "width")
                var height = parseDimension(node, "height")

                if width == nil || height == nil,
                   node.attribute(named: "width") == nil || node.attribute(named: "height") == nil,
                   let (_, path) = try resource(node, names: ["image", "backgroundImage", "background"]) {
                    let intrinsic = try imageStore.image(for: path).size
                    if node.attribute(named: "width") == nil { width = intrinsic.width }
                    if node.attribute(named: "height") == nil { height = intrinsic.height }
                }
                guard let left, let top else {
                    if !unresolvedNodes.contains(node.stableID) {
                        recordUnresolved(node, attribute: "position", value: "missing literal geometry")
                    }
                    return
                }
                guard var width, var height else {
                    if !unresolvedNodes.contains(node.stableID) {
                        recordUnresolved(node, attribute: "size", value: "missing literal geometry")
                    }
                    // A script-sized container can still have a literal origin and independently
                    // literal descendants. Keep the container unresolved/unpainted and carry only
                    // its known origin. A zero-sized private baseline makes alignment delta zero; it
                    // is never emitted as authored geometry or used as a fallback paint frame.
                    let partial = WMPRect(x: parentFrame.x + left, y: parentFrame.y + top,
                        width: width ?? 0, height: height ?? 0)
                    let partialAuthored = WMPSize(width: width ?? 0, height: height ?? 0)
                    for child in node.children.sorted(by: nodeOrder) {
                        try walk(child, parentFrame: partial, parentAuthoredSize: partialAuthored,
                                 inheritedClip: inheritedClip)
                    }
                    return
                }
                let horizontal = WMPAxisAlignment(horizontal: literalString(node, "horizontalAlignment"))
                let vertical = WMPAxisAlignment(vertical: literalString(node, "verticalAlignment"))
                let deltaWidth = parentFrame.width - parentAuthoredSize.width
                let deltaHeight = parentFrame.height - parentAuthoredSize.height
                var x = left, y = top
                switch horizontal {
                case .center: x += deltaWidth / 2
                case .trailing: x += deltaWidth
                case .stretch: width = max(0, width + deltaWidth)
                case .leading: break
                }
                switch vertical {
                case .center: y += deltaHeight / 2
                case .trailing: y += deltaHeight
                case .stretch: height = max(0, height + deltaHeight)
                case .leading: break
                }
                frame = WMPRect(x: parentFrame.x + x, y: parentFrame.y + y, width: width, height: height)
            }

            let visible = inheritedClip.flatMap { frame.intersection($0) } ?? (inheritedClip == nil ? frame : nil)
            let local = WMPRect(x: frame.x - parentFrame.x, y: frame.y - parentFrame.y,
                                width: frame.width, height: frame.height)
            geometries[node.stableID] = WMPResolvedGeometry(localFrame: local,
                absoluteFrame: frame, visibleFrame: visible, clipRect: inheritedClip)
            resolvedNodes.insert(node.stableID)
            let z = Int(literal(node, "zIndex") ?? 0)

            if let background = color(node, names: ["backgroundColor"]), !frame.isEmpty {
                commands.append(WMPPaintCommand(stableID: node.stableID, nodeID: node.xmlID,
                    frame: frame, clipRect: inheritedClip, zIndex: z,
                    documentOrder: node.stableID, paint: .fill(background)))
            }
            if let (_, path) = try resource(node, names: ["backgroundImage", "background"]), !frame.isEmpty {
                commands.append(imageCommand(node: node, path: path, frame: frame,
                    clip: inheritedClip, z: z, background: true))
            }
            if let (_, path) = try resource(node, names: ["image"]), !frame.isEmpty,
               node.kind != .subview && node.kind != .view {
                commands.append(imageCommand(node: node, path: path, frame: frame,
                    clip: inheritedClip, z: z, background: false))
            }
            if node.kind == .text, !frame.isEmpty,
               let value = literalString(node, "value") {
                let alignment: WMPTextAlignment
                switch literalString(node, "justification")?.lowercased() {
                case "center": alignment = .center
                case "right": alignment = .right
                default: alignment = .left
                }
                let text = WMPSceneText(value: value,
                    fontName: literalString(node, "fontType") ?? "Arial",
                    fontSize: max(1, literal(node, "fontSize") ?? 12),
                    bold: literalString(node, "fontStyle")?.lowercased().contains("bold") == true,
                    color: color(node, names: ["foregroundColor", "color"])
                        ?? WMPColor(red: 255, green: 255, blue: 255), alignment: alignment)
                commands.append(WMPPaintCommand(stableID: node.stableID, nodeID: node.xmlID,
                    frame: frame, clipRect: inheritedClip, zIndex: z,
                    documentOrder: node.stableID, paint: .text(text)))
            }
            if isInteractive(node.kind), let visible {
                hits.append(WMPHitMetadata(stableID: node.stableID, nodeID: node.xmlID,
                    kind: node.kind.description, frame: visible, clipRect: inheritedClip, zIndex: z))
            }

            let childClip = inheritedClip.flatMap { frame.intersection($0) } ?? (inheritedClip == nil ? frame : nil)
            let authoredSize = isRoot
                ? WMPSize(width: authoredWidth, height: authoredHeight)
                : WMPSize(width: parseDimension(node, "width") ?? frame.width,
                          height: parseDimension(node, "height") ?? frame.height)
            for child in node.children.sorted(by: nodeOrder) {
                try walk(child, parentFrame: frame, parentAuthoredSize: authoredSize,
                         inheritedClip: childClip)
            }
        }

        try walk(view, parentFrame: canvasRect,
                 parentAuthoredSize: WMPSize(width: authoredWidth, height: authoredHeight),
                 inheritedClip: canvasRect, isRoot: true)
        hits.sort { ($0.zIndex, $0.stableID) < ($1.zIndex, $1.stableID) }
        let dirty = commands.compactMap { command in
            command.clipRect.flatMap { command.frame.intersection($0) } ?? command.frame
        }.reduce(nil as WMPRect?) { accumulated, next in
            accumulated.map { $0.union(next) } ?? next
        }
        let metrics = WMPSceneMetrics(resolvedNodeCount: resolvedNodes.count,
            unresolvedNodeCount: unresolvedNodes.count, visibleBounds: dirty)
        return WMPScene(viewID: registration.id, canvasSize: canvas, resizeLimits: resizeLimits,
            commands: commands, hits: hits, geometries: geometries, unresolved: unresolved,
            diagnostics: diagnostics, dirtyBounds: dirty, metrics: metrics,
            wasBuiltOnMainThread: Thread.isMainThread)
    }

    private func imageCommand(node: WMPNode, path: String, frame: WMPRect,
                              clip: WMPRect?, z: Int, background: Bool) -> WMPPaintCommand {
        let prefix = background ? "background" : ""
        let sourceX = literal(node, prefix + "CropLeft") ?? literal(node, "cropLeft")
        let sourceY = literal(node, prefix + "CropTop") ?? literal(node, "cropTop")
        let sourceWidth = literal(node, prefix + "CropWidth") ?? literal(node, "cropWidth")
        let sourceHeight = literal(node, prefix + "CropHeight") ?? literal(node, "cropHeight")
        let source = sourceX == nil && sourceY == nil && sourceWidth == nil && sourceHeight == nil ? nil
            : WMPRect(x: sourceX ?? 0, y: sourceY ?? 0,
                      width: sourceWidth ?? frame.width, height: sourceHeight ?? frame.height)
        let tiledName = background ? "backgroundTiled" : "tiled"
        let image = WMPSceneImage(resourcePath: path, sourceRect: source,
            colorKey: color(node, names: ["transparencyColor"]),
            tiled: literalString(node, tiledName)?.caseInsensitiveCompare("true") == .orderedSame,
            interpolation: .low)
        return WMPPaintCommand(stableID: node.stableID, nodeID: node.xmlID, frame: frame,
            clipRect: clip, zIndex: z, documentOrder: node.stableID, paint: .image(image))
    }

    private func literal(_ node: WMPNode, _ name: String) -> CGFloat? {
        WMPNumber.literal(node.attribute(named: name))
    }

    private func literalString(_ node: WMPNode, _ name: String) -> String? {
        guard let attribute = node.attribute(named: name), case let .literal(value) = attribute.value else { return nil }
        return value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func color(_ node: WMPNode, names: [String]) -> WMPColor? {
        for name in names {
            guard let attribute = node.attribute(named: name) else { continue }
            if case let .color(value) = attribute.value { return value }
            let raw = attribute.rawValue.lowercased()
            switch raw {
            case "black": return WMPColor(red: 0, green: 0, blue: 0)
            case "white": return WMPColor(red: 255, green: 255, blue: 255)
            case "red": return WMPColor(red: 255, green: 0, blue: 0)
            case "green": return WMPColor(red: 0, green: 128, blue: 0)
            case "blue": return WMPColor(red: 0, green: 0, blue: 255)
            default: continue
            }
        }
        return nil
    }

    private func isInteractive(_ kind: WMPElementKind) -> Bool {
        switch kind {
        case .button, .buttonGroup, .slider, .volumeSlider, .seekSlider,
             .balanceSlider, .playElement, .pauseButton, .stopElement, .prevElement,
             .nextElement, .rewButton, .rewElement, .ffwdButton, .ffwdElement,
             .returnButton, .shuffleButton, .playlist, .dropdownPlaylist, .popup: return true
        default: return false
        }
    }

    private func isNonLayout(_ kind: WMPElementKind) -> Bool {
        switch kind {
        case .theme, .player, .network, .script, .buttonElement: return true
        default: return false
        }
    }

    private func nodeOrder(_ lhs: WMPNode, _ rhs: WMPNode) -> Bool {
        let leftZ = Int(literal(lhs, "zIndex") ?? 0), rightZ = Int(literal(rhs, "zIndex") ?? 0)
        return leftZ == rightZ ? lhs.stableID < rhs.stableID : leftZ < rightZ
    }

}
