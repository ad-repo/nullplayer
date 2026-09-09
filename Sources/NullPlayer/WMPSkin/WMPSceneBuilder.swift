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
    func build(viewID: String, requestedSize: WMPSize? = nil,
               interactionState: WMPInteractionState = WMPInteractionState(),
               dirtyNodeIDs: Set<Int>? = nil,
               overrides: WMPSceneOverrides = .empty) async throws -> WMPScene {
        try await Task.detached(priority: .userInitiated) {
            try buildOffMain(viewID: viewID, requestedSize: requestedSize,
                             interactionState: interactionState, dirtyNodeIDs: dirtyNodeIDs,
                             overrides: overrides)
        }.value
    }

    private func buildOffMain(viewID: String, requestedSize: WMPSize?,
                              interactionState: WMPInteractionState,
                              dirtyNodeIDs: Set<Int>?, overrides: WMPSceneOverrides) throws -> WMPScene {
        guard let registration = loadedSkin.views.first(where: {
            $0.id.caseInsensitiveCompare(viewID) == .orderedSame
        }) else {
            throw WMPFailure(WMPDiagnostic(.invalidGeometry, "WMP view '\(viewID)' does not exist."))
        }
        let view = registration.node
        // A view sizes itself the way every other node does: an authored literal first, then a
        // script override, then the natural size of its own background artwork. WMP skins routinely
        // author a top-level `<VIEW backgroundImage="...">` with no width or height at all — the
        // window *is* the bitmap — and rejecting those was the single largest cause of a skin that
        // loads and then draws nothing.
        func viewOverride(_ name: String) -> CGFloat? {
            guard let value = overrides.geometry[WMPScenePropertyAddress(stableID: view.stableID,
                                                                         property: name.lowercased())],
                  value.isFinite, value >= 0 else { return nil }
            return value
        }
        func viewDimension(_ name: String) throws -> CGFloat? {
            // **Script override first, then the markup — the same order as every other node.**
            // `parseDimension` has always read the overrides before the attribute; the view root
            // read them the other way round, so a `<VIEW width="593" height="600">` could never be
            // resized by its own script. That is what a `.wmz` compact mode is made of:
            // `Cablemusic`'s `SwitchSmall()` writes `view.width = 475; view.height = 373` and hides
            // the full-size artwork, and with the literal winning the canvas stayed 593x600 — the
            // compact player drawn in the corner of a window two hundred pixels too big on both
            // axes, the rest of it empty. Reported as "when you click the compact button there is
            // a large overlay".
            //
            // A literal zero is authored on purpose: `pharaoh` declares `vGhost` and
            // `vGhostAutoDetect` as `width="0" height="0"` views whose only job is to run an
            // `onLoad` that redirects to another view. Zero is an answer; only a negative one is
            // not — and that is true of an override too, which is the store-thumbnail collapse.
            if let value = literal(view, name), value >= 0 { return value }
            return nil
        }
        // Declared here rather than with the other scene accumulators below: resolving the view's
        // own background is the first thing that can warn.
        var diagnostics = loadedSkin.diagnostics
        var authoredWidth = try viewDimension("width")
        var authoredHeight = try viewDimension("height")
        if authoredWidth == nil || authoredHeight == nil,
           let (_, path) = try resolveResource(view, names: ["backgroundImage", "background"],
                                               overrides: overrides,
                                               warn: { diagnostics.append($0) }) {
            let intrinsic = try imageStore.image(for: path).size
            if authoredWidth == nil, intrinsic.width > 0 { authoredWidth = intrinsic.width }
            if authoredHeight == nil, intrinsic.height > 0 { authoredHeight = intrinsic.height }
        }
        if authoredWidth == nil || authoredHeight == nil {
            // Neither a literal nor its own artwork: the window is sized by what it contains.
            // WMP fits such a view to its content, and skins rely on it — `iconic` hangs its whole
            // player off one `<SUBVIEW backgroundImage="base.gif">`, and `Darkling` wraps four
            // resolution-specific subviews its script picks between. Rejecting these was a total
            // blackout for both. Only geometry the builder can place without executing script
            // counts, and visibility is deliberately ignored: Darkling authors every one of its
            // wrappers `visible="false"` and turns one on in `onLoad`, so a union of the visible
            // children alone is empty.
            let union = try contentUnionSize(of: view, overrides: overrides,
                                             warn: { diagnostics.append($0) })
            if authoredWidth == nil, union.width > 0 { authoredWidth = union.width }
            if authoredHeight == nil, union.height > 0 { authoredHeight = union.height }
        }
        // Nothing sized it and it can place nothing: the view has no drawable content at all.
        // That is a legal WMP construct, not a defect — 25 corpus skins author a `controlView`
        // holding only `<player>` and a hidden `<video>` so that a script can run with host
        // bindings and no window, and `pharaoh` writes the same idea as an explicit 0x0 view.
        // The builder still invents no geometry; the honest size of empty content is empty.
        let width = authoredWidth ?? 0
        let height = authoredHeight ?? 0
        // **The size a script assigned the view is the window's; the size the markup authored stays
        // the baseline every child's alignment delta is measured against.** They are two different
        // questions and reading one value for both broke each in turn. A `.wmz` compact mode is a
        // handler writing `view.width`/`view.height` — `Cablemusic`'s `SwitchSmall()` asks for
        // 475x373 — and with the literal winning the canvas the compact player drew inside a
        // 593x600 window with two hundred empty pixels around it ("a large overlay"). But letting
        // the override *replace* the authored size collapsed every alignment delta to zero:
        // `LostPlanet`'s `onLoadInfo` opens with `view.width = view.minWidth`, and its stretch
        // tiles — sized from `canvas − authored` — stopped covering the 61 px they had been
        // covering, punching holes through the window frame.
        let defaultSize = WMPSize(width: viewOverride("width") ?? width,
                                  height: viewOverride("height") ?? height)
        let minimum = WMPSize(width: literal(view, "minWidth") ?? defaultSize.width,
                              height: literal(view, "minHeight") ?? defaultSize.height)
        let maxWidth = literal(view, "maxWidth"), maxHeight = literal(view, "maxHeight")
        let maximum: WMPSize? = maxWidth == nil && maxHeight == nil ? nil
            : WMPSize(width: maxWidth ?? .greatestFiniteMagnitude,
                      height: maxHeight ?? .greatestFiniteMagnitude)
        let resizeLimits = WMPResizeLimits(minimum: minimum, maximum: maximum)
        let canvas = resizeLimits.clamp(requestedSize ?? defaultSize)
        let canvasRect = WMPRect(x: 0, y: 0, width: canvas.width, height: canvas.height)

        var commands: [WMPPaintCommand] = []
        var hits: [WMPHitMetadata] = []
        var widgets: [WMPWidget] = []
        var geometries: [Int: WMPResolvedGeometry] = [:]
        var unresolved: [WMPUnresolvedGeometry] = []
        var unresolvedNodes = Set<Int>()
        var unresolvedAttributes = Set<String>()
        var resolvedNodes = Set<Int>()
        var layoutResolver = WMPInitialLayoutResolver(graph: loadedSkin.graph, view: view, canvas: canvas)
        // Folded element id to node, for the view being built. `wmpprop:` paths that name another
        // element resolve through this; the first id wins, matching the duplicate-id rule.
        var idToNode: [String: WMPNode] = [:]
        func indexIDs(_ node: WMPNode) {
            if let id = node.xmlID?.lowercased(), idToNode[id] == nil { idToNode[id] = node }
            node.children.forEach(indexIDs)
        }
        indexIDs(view)

        /// A number a script may have written, then the markup's own.
        ///
        /// The type's `literal(_:_:)` reads the attribute and nothing else, and `<TEXT>` is where
        /// that showed: `Cablemusic` lays its readouts out with `txtShowLabel.fontSize = 7` over a
        /// markup that says `fontSize="10"`, so every label was measured *and* drawn three points
        /// too large — "Copyright:" ran out of its 55 px box and off the left edge of the LCD it
        /// was supposed to sit inside. Geometry has `parseDimension` and a slider has
        /// `sliderMetrics`; this is the same rule for the rest.
        func literalNumber(_ node: WMPNode, _ name: String) -> CGFloat? {
            if let value = overrides.properties[WMPScenePropertyAddress(stableID: node.stableID,
                                                                        property: name.lowercased())],
               let number = value.number, number.isFinite { return CGFloat(number) }
            return literal(node, name)
        }

        func literalString(_ node: WMPNode, _ name: String) -> String? {
            if let value = overrides.properties[WMPScenePropertyAddress(stableID: node.stableID,
                                                                        property: name.lowercased())] {
                return value.string
            }
            guard let attribute = node.attribute(named: name),
                  case let .literal(value) = attribute.value else { return nil }
            return value.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        /// A `visible="wmpprop:<element>.<property>"` answered from the skin's own graph, or nil
        /// when the path names no element here — `WoW` writes `wmpprop:plMode.visible`, and
        /// `plMode` is a name WMP's own object model owns and this skin never declares. Nil means
        /// *no answer*, which leaves the authored value standing; it is never the answer "hidden".
        /// Bounded to one hop: a mirror of a mirror is not authored anywhere in the corpus.
        func mirroredVisibility(of node: WMPNode) -> Bool? {
            guard let attribute = node.attribute(named: "visible"),
                  case let .binding(kind, path) = attribute.value, kind == .property else { return nil }
            let parts = path.split(separator: ".", maxSplits: 1)
            guard parts.count == 2,
                  let target = idToNode[String(parts[0]).lowercased()] else { return nil }
            let property = String(parts[1]).lowercased()
            if let override = overrides.properties[WMPScenePropertyAddress(stableID: target.stableID,
                                                                           property: property)] {
                return override.truth
            }
            guard let mirrored = target.attribute(named: property) else { return nil }
            guard case let .literal(value) = mirrored.value else { return nil }
            return value.caseInsensitiveCompare("false") != .orderedSame && !value.isEmpty
        }

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
            if let value = overrides.geometry[WMPScenePropertyAddress(stableID: node.stableID,
                                                                      property: name.lowercased())],
               value.isFinite { return value }
            guard let property = WMPInitialLayoutResolver.Property(rawValue: name.lowercased()) else { return nil }
            switch layoutResolver.resolve(node, property: property) {
            case let .value(value): return value
            case let .unresolved(reason):
                guard let attribute = node.attribute(named: name) else { return nil }
                recordUnresolved(node, attribute: name, value: "\(attribute.rawValue) [\(reason)]")
                return nil
            }
        }

        /// Did this coordinate come from something that already knows the view's current size?
        ///
        /// A script override and a `JScript:`/`wmpprop:` attribute both do — they were evaluated
        /// against this canvas. So does a bare literal the static grammar has to parse rather than
        /// read (`left="view.width-10"`, which the corpus writes without the prefix). Only a plain
        /// finite number, or an absent attribute, is geometry alignment is entitled to move.
        func isComputed(_ node: WMPNode, _ name: String) -> Bool {
            if overrides.geometry[WMPScenePropertyAddress(stableID: node.stableID,
                                                          property: name.lowercased())] != nil {
                return true
            }
            guard let attribute = node.attribute(named: name) else { return false }
            guard case let .literal(raw) = attribute.value else { return true }
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            return Double(trimmed).map { !$0.isFinite } ?? true
        }

        func resource(_ node: WMPNode, names: [String]) throws -> (String, String)? {
            try resolveResource(node, names: names, overrides: overrides,
                                warn: { diagnostics.append($0) })
        }

        /// A slider's numbers, from the same three places every other property comes from: a live
        /// script/`wmpprop:` override first, then an authored literal, then WMP's own default.
        func sliderMetrics(_ node: WMPNode) -> WMPSliderMetrics {
            func number(_ names: [String]) -> Double? {
                for name in names {
                    if let override = overrides.properties[WMPScenePropertyAddress(
                        stableID: node.stableID, property: name.lowercased())]?.number,
                       override.isFinite { return override }
                    if let value = literal(node, name) { return Double(value) }
                }
                return nil
            }
            let minimum = number(["min", "minValue"]) ?? 0
            let maximum = number(["max", "maxValue"]) ?? 100
            return WMPSliderMetrics(direction: WMPSliderDirection(authored: literalString(node, "direction")),
                minimum: minimum, maximum: maximum,
                value: number(["value"]) ?? minimum,
                borderSize: literal(node, "borderSize") ?? 0)
        }

        /// The metrics the `foregroundImage` fill is measured with — the slider's own value
        /// unless the skin redirected it to `foregroundProgress`, which WMP scales 0-100.
        func progressSource(_ node: WMPNode, _ slider: WMPSliderMetrics) -> WMPSliderMetrics {
            guard literalString(node, "useForegroundProgress")?.caseInsensitiveCompare("true") == .orderedSame,
                  let progress = overrides.properties[WMPScenePropertyAddress(
                    stableID: node.stableID, property: "foregroundprogress")]?.number
                    ?? literal(node, "foregroundProgress").map(Double.init),
                  progress.isFinite else { return slider }
            return WMPSliderMetrics(direction: slider.direction, minimum: 0, maximum: 100,
                                    value: progress, borderSize: slider.borderSize)
        }

        func thumbSize(_ node: WMPNode) throws -> WMPSize? {
            guard let (_, path) = try resource(node, names: ["thumbImage", "thumbDownImage",
                                                             "thumbHoverImage", "thumbDisabledImage"]) else {
                return nil
            }
            return try imageStore.image(for: path).size
        }

        /// `alphaBlend` is 0-255 and inherits: a container the skin fades takes its whole subtree
        /// with it, which is how a `.wmz` hides a pane it has not opened yet.
        func inheritedAlpha(_ node: WMPNode, _ parent: CGFloat) -> CGFloat {
            guard let authored = overrides.properties[WMPScenePropertyAddress(stableID: node.stableID,
                                                                              property: "alphablend")]?.number
                    ?? literal(node, "alphaBlend").map(Double.init) else { return parent }
            guard authored.isFinite else { return parent }
            return parent * max(0, min(1, CGFloat(authored) / 255))
        }

        func walk(_ node: WMPNode, parentFrame: WMPRect, parentAuthoredSize: WMPSize,
                  inheritedClip: WMPRect?, parentAlpha: CGFloat = 1, isRoot: Bool = false) throws {
            // A script override outranks the markup. Corona's `SetPane` switches its video and
            // visualization panes purely by writing `vid.visible` / `vis.visible`, so a builder
            // that reads only the authored attribute draws whichever the author happened to leave
            // on — which is how an opaque video pane ended up over the artwork as soon as playback
            // started.
            if let override = overrides.properties[WMPScenePropertyAddress(stableID: node.stableID,
                                                                          property: "visible")] {
                if !override.truth { return }
            } else if let mirrored = mirroredVisibility(of: node) {
                // **A `wmpprop:` path can name another element in the same skin, not only a host
                // property.** 150 of the corpus's `visible="wmpprop:…"` attributes do: `WoW` hangs
                // its CD-rip bar off `wmpprop:playlist2.visible`, and 8 skins share that exact
                // line. Resolving it here is what keeps the bar hidden now that an *unanswerable*
                // path no longer resolves to a falsy empty string.
                if !mirrored { return }
            } else if literalString(node, "visible")?.caseInsensitiveCompare("false") == .orderedSame {
                return
            }
            if isNonLayout(node) {
                for child in node.children.sorted(by: nodeOrder) {
                    try walk(child, parentFrame: parentFrame, parentAuthoredSize: parentAuthoredSize,
                             inheritedClip: inheritedClip, parentAlpha: parentAlpha)
                }
                return
            }

            let frame: WMPRect
            // The size this node would have had if its parent had not grown: the baseline every
            // child's alignment delta is measured against. It is *not* re-read from the markup
            // afterwards, because a node sized by its own artwork has no markup to re-read and the
            // frame is by then the stretched one — which made the delta zero and stopped alignment
            // cascading past any intrinsically sized container.
            let ownAuthoredSize: WMPSize
            if isRoot {
                frame = canvasRect
                ownAuthoredSize = WMPSize(width: width, height: height)
            } else {
                // **An origin the markup never stated can still have been written by script, and
                // asking the markup first meant it never was.** `left`/`top` default to 0 when the
                // skin authors neither — but the check was `attribute == nil ? 0 : resolve`, so a
                // node with no authored `left` short-circuited to 0 *before* `parseDimension` could
                // look in the scene overrides, and every element a handler positions from nothing
                // stacked at its parent's origin. `Cablemusic`'s two drawers are seventeen station
                // rows each, laid out entirely by `InitPrograms()` writing `pr<N>.top`/`.left`:
                // all thirty-four drew on top of one another in the corner of the drawer. Size
                // never had the bug, which is why the rows were the right *width* in the wrong
                // place. Overrides first, then the markup, then the default.
                let left = parseDimension(node, "left")
                    ?? (node.attribute(named: "left") == nil ? 0 : nil)
                let top = parseDimension(node, "top")
                    ?? (node.attribute(named: "top") == nil ? 0 : nil)
                var width = parseDimension(node, "width")
                var height = parseDimension(node, "height")

                if width == nil || height == nil,
                   node.attribute(named: "width") == nil || node.attribute(named: "height") == nil,
                   let (_, path) = try resource(node, names: intrinsicSizeResourceNames(for: node.kind)) {
                    let intrinsic = try imageStore.image(for: path).size
                    // `width`/`height` are already non-nil here only when a script override
                    // supplied them, since the markup authored no such attribute. The artwork's
                    // natural size is the fallback for an *unstated* dimension, never an answer
                    // that outranks one the skin computed: Corona's compact view collapses
                    // `svVideo` to height 0 through its own timer, and the background bitmap kept
                    // stamping 241 back over it, leaving a black panel across the whole window.
                    if node.attribute(named: "width") == nil, width == nil { width = intrinsic.width }
                    if node.attribute(named: "height") == nil, height == nil { height = intrinsic.height }
                }
                if node.kind == .text, width == nil || height == nil,
                   let glyphs = intrinsicTextSize(node, literal: literalNumber,
                                                  literalString: literalString) {
                    if node.attribute(named: "width") == nil, width == nil { width = glyphs.width }
                    if node.attribute(named: "height") == nil, height == nil { height = glyphs.height }
                }
                guard let left, let top else {
                    if !unresolvedNodes.contains(node.stableID) {
                        recordUnresolved(node, attribute: "position", value: "missing literal geometry")
                    }
                    return
                }
                guard var width, var height else {
                    if !unresolvedNodes.contains(node.stableID) {
                        let missing = [width == nil ? "width" : nil, height == nil ? "height" : nil]
                            .compactMap { $0 }.joined(separator: "+")
                        recordUnresolved(node, attribute: "size",
                                         value: "missing literal geometry (\(missing))")
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
                                 inheritedClip: inheritedClip, parentAlpha: parentAlpha)
                    }
                    return
                }
                ownAuthoredSize = WMPSize(width: width, height: height)
                // **Alignment moves geometry the skin left as a literal, and nothing else.**
                //
                // A resizing `.wmz` states the same intent twice: WoW's `pl5_1` authors
                // `left="JScript:view.width-202"` *and* `horizontalAlignment="right"`, and so do its
                // six siblings and `plFrame` with `stretch`. The expression already reads the new
                // `view.width`, so adding the parent's growth on top counts the resize twice —
                // measured at exactly +200 on a 453→653 drag, which threw the whole right-hand
                // chrome (close button, search box, resize grip) off the canvas and read as "the
                // window resizes and the skin doesn't". The literal cases are untouched: `pl8_1`
                // has `left=208` with no `width`, and its `stretch` still fills the top tile.
                let horizontal = WMPAxisAlignment(horizontal: literalString(node, "horizontalAlignment"))
                let vertical = WMPAxisAlignment(vertical: literalString(node, "verticalAlignment"))
                let deltaWidth = parentFrame.width - parentAuthoredSize.width
                let deltaHeight = parentFrame.height - parentAuthoredSize.height
                var x = left, y = top
                switch horizontal {
                case .center where !isComputed(node, "left"): x += deltaWidth / 2
                case .trailing where !isComputed(node, "left"): x += deltaWidth
                case .stretch where !isComputed(node, "width"): width = max(0, width + deltaWidth)
                default: break
                }
                switch vertical {
                case .center where !isComputed(node, "top"): y += deltaHeight / 2
                case .trailing where !isComputed(node, "top"): y += deltaHeight
                case .stretch where !isComputed(node, "height"): height = max(0, height + deltaHeight)
                default: break
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
            let alpha = inheritedAlpha(node, parentAlpha)
            let slider = isSlider(node.kind) ? sliderMetrics(node) : nil
            let positionMap = try node.kind == .customSlider
                ? resource(node, names: ["positionImage"]).map { try imageStore.positionMap(for: $0.1) }
                : nil

            if let kind = widgetKind(node.kind), visible != nil {
                let label = literalString(node, "accessibleName")
                    ?? literalString(node, "title") ?? literalString(node, "name")
                    ?? node.xmlID ?? node.kind.description
                widgets.append(WMPWidget(stableID: node.stableID, nodeID: node.xmlID, kind: kind,
                    frame: frame, clipRect: inheritedClip, label: label,
                    toolTip: literalString(node, "toolTip") ?? literalString(node, "tooltip"),
                    minimumValue: slider?.minimum ?? (literal(node, "min") ?? literal(node, "minValue")).map(Double.init),
                    maximumValue: slider?.maximum ?? (literal(node, "max") ?? literal(node, "maxValue")).map(Double.init),
                    value: slider?.value, direction: slider?.direction,
                    borderSize: slider?.borderSize ?? 0,
                    thumbSize: try slider == nil ? nil : thumbSize(node),
                    valueBindingPath: valueBindingPath(node)))
            }

            // `clippingImage` shapes an element by a bitmap the way `clippingColor` shapes it by a
            // colour — 25 corpus skins author a non-empty one, and every one of them declares a
            // `clippingColor` beside it, which is what the mask keys out.
            let clippingPath = try resource(node, names: ["clippingImage"])?.1
            if let background = color(node, names: ["backgroundColor"]), !frame.isEmpty {
                commands.append(WMPPaintCommand(stableID: node.stableID, nodeID: node.xmlID,
                    frame: frame, clipRect: inheritedClip, zIndex: z,
                    documentOrder: node.stableID, paint: .fill(background), alpha: alpha))
            }
            if let (_, path) = try resource(node, names: ["backgroundImage", "background"]), !frame.isEmpty {
                commands.append(imageCommand(node: node, path: path, frame: frame,
                    clip: inheritedClip, z: z, background: true, alpha: alpha,
                    clippingPath: clippingPath))
            }
            let childStates = node.kind == .buttonGroup
                ? node.children.map { ($0.stableID, interactionState.visualState(for: $0.stableID)) } : []
            let visualState: WMPVisualInteractionState
            if childStates.contains(where: { $0.1 == .down }) { visualState = .down }
            else if childStates.contains(where: { $0.1 == .hover }) { visualState = .hover }
            else if !childStates.isEmpty && childStates.allSatisfy({ $0.1 == .disabled }) { visualState = .disabled }
            else { visualState = interactionState.visualState(for: node.stableID) }
            let foregroundNames: [String]
            switch visualState {
            case .disabled: foregroundNames = ["disabledImage", "image"]
            case .down: foregroundNames = ["downImage", "image"]
            case .hover: foregroundNames = ["hoverImage", "image"]
            case .normal: foregroundNames = ["image"]
            }
            if !frame.isEmpty, node.kind != .subview && node.kind != .view {
                // **A `BUTTONGROUP`'s state artwork is a sheet the size of the whole group, and it
                // is only ever painted through the group's mapping mask.** `hoverImage` and
                // `downImage` are the *entire* player redrawn with one control lit; the mask is
                // what cuts out the region the pointer is actually over.
                //
                // The normal `image` used to be required for any of that to happen, and a group
                // that authors none — its normal state being the window's own background artwork —
                // fell through to the generic single-image path below and painted the whole sheet
                // over the window. On `Cablemusic` that is a 593x600 bitmap with a dark green
                // surround, so hovering any button in any of its six groups covered the entire
                // player: reported as "when you mouse over the compact button there is a huge
                // overlay". Nothing reached it before W108 gave those groups a frame at all — the
                // second latent trap that row uncovered, after the duplicate `mappingColor`.
                //
                // So the normal artwork is now optional and only the mask is required. With no
                // `image` there is nothing to draw *under* the lit region, which is correct: what
                // is under it is the window, exactly as in the group's normal state.
                if node.kind == .buttonGroup, visualState != .normal,
                   let (_, statePath) = try resource(node, names: foregroundNames),
                   let (_, mappingPath) = try resource(node, names: ["mappingImage"]) {
                    let normalPath = try resource(node, names: ["image"])?.1
                    let colors = mappingColors(of: node)
                    let activeIDs = childStates.filter { $0.1 == visualState }.map(\.0)
                    if !colors.isEmpty, !activeIDs.isEmpty {
                        let mapping = try imageStore.mappingImage(for: mappingPath, nodeByColor: colors)
                        if let normalPath {
                            commands.append(imageCommand(node: node, path: normalPath, frame: frame,
                                clip: inheritedClip, z: z, background: false, alpha: alpha,
                                clippingPath: clippingPath))
                        }
                        commands.append(imageCommand(node: node, path: statePath, frame: frame,
                            clip: inheritedClip, z: z, background: false, alpha: alpha,
                            mappingMask: WMPSceneMappingMask(mapping: mapping, nodeIDs: activeIDs),
                            clippingPath: clippingPath))
                    } else if normalPath != nil {
                        // A group whose own artwork *is* the sheet swaps it wholesale, the way a
                        // `<BUTTON>` does. One with no artwork of its own and nothing lit draws
                        // nothing, which is its normal state.
                        commands.append(imageCommand(node: node, path: statePath, frame: frame,
                            clip: inheritedClip, z: z, background: false, alpha: alpha,
                            clippingPath: clippingPath))
                    }
                } else if let (_, path) = try resource(node, names: foregroundNames) {
                    // A `CUSTOMSLIDER`'s artwork is a strip of every position it can be in, and the
                    // value picks the frame. `frame(for:in:)` returns nil for art that is not a
                    // whole multiple of the map, and then this is an ordinary image again.
                    let artwork = try imageStore.image(for: path).size
                    let strip = slider.flatMap { positionMap?.frame(for: $0.fraction, in: artwork) }
                    commands.append(imageCommand(node: node, path: path, frame: frame,
                        clip: inheritedClip, z: z, background: false, alpha: alpha,
                        sourceOverride: strip, clippingPath: clippingPath))
                }
            }

            // **A slider is its track plus a thumb the scene has to place.** 163 of 178 corpus
            // skins author one and 164 give it a `thumbImage`; before this the engine drew the
            // track and nothing else, so every seek bar, volume control and equaliser band in the
            // corpus rendered as an empty groove that could still be dragged invisibly.
            if let slider, !frame.isEmpty, visible != nil {
                // `foregroundImage` is the filled part of the track, revealed up to the value.
                // Cropping the source rather than scaling it keeps the artwork's own pixels: a
                // progress bar squeezed into the filled width reads as a different bitmap.
                if let (_, path) = try resource(node, names: ["foregroundImage"]) {
                    // `useForegroundProgress="true"` (46 skins) says the fill is *not* the value:
                    // it is `foregroundProgress`, which the corpus binds to the network's download
                    // progress. A seek bar authored that way shows how much is buffered behind a
                    // thumb showing where playback is, and the two are different numbers.
                    let filled = progressSource(node, slider).progressRect(in: frame)
                    if !filled.isEmpty {
                        let source = WMPRect(x: filled.x - frame.x, y: filled.y - frame.y,
                                             width: filled.width, height: filled.height)
                        commands.append(imageCommand(node: node, path: path, frame: filled,
                            clip: inheritedClip, z: z, background: false, alpha: alpha,
                            sourceOverride: source))
                    }
                }
                let thumbNames: [String]
                switch visualState {
                case .disabled: thumbNames = ["thumbDisabledImage", "thumbImage"]
                case .down: thumbNames = ["thumbDownImage", "thumbImage"]
                case .hover: thumbNames = ["thumbHoverImage", "thumbImage"]
                case .normal: thumbNames = ["thumbImage"]
                }
                if let (_, path) = try resource(node, names: thumbNames) {
                    let size = try imageStore.image(for: path).size
                    let thumb = slider.thumbFrame(in: frame, thumbSize: size)
                    if !thumb.isEmpty {
                        commands.append(imageCommand(node: node, path: path, frame: thumb,
                            clip: inheritedClip, z: z, background: false, alpha: alpha))
                    }
                }
            }
            if node.kind == .text, !frame.isEmpty,
               let value = literalString(node, "value") {
                let alignment: WMPTextAlignment
                switch literalString(node, "justification")?.lowercased() {
                case "center": alignment = .center
                case "right": alignment = .right
                default: alignment = .left
                }
                // **`fontFace` is the attribute the corpus authors, not `fontType`**: 110 skins
                // against 21. Reading only `fontType` rendered every one of those in Arial, which
                // is why so many readouts sat in the wrong face at the right size.
                let style = (literalString(node, "fontStyle") ?? "").lowercased()
                let disabled = visualState == .disabled
                let text = WMPSceneText(value: value,
                    fontName: literalString(node, "fontFace") ?? literalString(node, "fontType") ?? "Arial",
                    fontSize: max(1, literalNumber(node, "fontSize") ?? 12),
                    bold: style.contains("bold"), italic: style.contains("italic"),
                    underline: style.contains("underline"),
                    smoothed: literalString(node, "fontSmoothing")?.caseInsensitiveCompare("false") != .orderedSame,
                    color: (disabled ? color(node, names: ["disabledForegroundColor"]) : nil)
                        ?? color(node, names: ["foregroundColor", "color"])
                        ?? WMPColor(red: 255, green: 255, blue: 255), alignment: alignment,
                    scrolling: literalString(node, "scrolling")?.caseInsensitiveCompare("true")
                        == .orderedSame,
                    scrollDelayMilliseconds: Double(literalNumber(node, "scrollingDelay") ?? 100),
                    scrollAmount: max(1, literalNumber(node, "scrollingAmount") ?? 1))
                commands.append(WMPPaintCommand(stableID: node.stableID, nodeID: node.xmlID,
                    frame: frame, clipRect: inheritedClip, zIndex: z,
                    documentOrder: node.stableID, paint: .text(text), alpha: alpha))
            }
            // `passthrough="true"` is authored by 83 corpus skins, and it means exactly what it
            // says: the element is drawn and the pointer goes through it to whatever is beneath.
            // A decorative overlay registered as a hit target swallows the controls it covers.
            let passthrough = literalString(node, "passthrough")?.caseInsensitiveCompare("true") == .orderedSame
            if isInteractive(node.kind) || authorsInputHandler(node), visible != nil, !passthrough {
                let enabled = literalString(node, "enabled")?.caseInsensitiveCompare("false") != .orderedSame
                    && !interactionState.disabledNodesForScene.contains(node.stableID)
                let sticky = literalString(node, "sticky")?.caseInsensitiveCompare("true") == .orderedSame
                var mappingImage: WMPMappingImage?
                var mappingTargets: [WMPHitTarget] = []
                if node.kind == .buttonGroup,
                   let (_, mappingPath) = try resource(node, names: ["mappingImage"]) {
                    // WMP allows both literal BUTTONELEMENT nodes and semantic transport elements
                    // (PLAYELEMENT, NEXTELEMENT, and peers) inside one mapping image.
                    let children = node.children.filter { $0.attribute(named: "mappingColor") != nil }
                    let colors = mappingColors(of: node)
                    if !colors.isEmpty {
                        mappingImage = try imageStore.mappingImage(for: mappingPath, nodeByColor: colors)
                        mappingTargets = children.compactMap { child in
                            guard colors.values.contains(child.stableID) else { return nil }
                            let childEnabled = literalString(child, "enabled")?.caseInsensitiveCompare("false") != .orderedSame
                                && !interactionState.disabledNodesForScene.contains(child.stableID)
                            return WMPHitTarget(stableID: child.stableID, nodeID: child.xmlID,
                                kind: child.kind.description, frame: frame,
                                action: WMPTransportAction.authoredAction(for: child),
                                sticky: literalString(child, "sticky")?.caseInsensitiveCompare("true") == .orderedSame,
                                enabled: childEnabled,
                                toolTip: toolTip(child, state: interactionState.visualState(for: child.stableID),
                                                  literal: literalString))
                        }
                    }
                }
                // `cursor` is a *named* shape in 2,246 of its 2,319 non-empty corpus uses. The
                // remainder name a `.cur`/`.ani` file, which is a Windows cursor format nothing
                // here decodes; those resolve to no cursor rather than to a missing bitmap, which
                // is also what stops `BITMAPS … missing=hand sizenwse` reporting cursor names as
                // absent artwork.
                let cursor = literalString(node, "cursor").flatMap(WMPCursor.init(authored:))
                hits.append(WMPHitMetadata(stableID: node.stableID, nodeID: node.xmlID,
                    kind: node.kind.description, frame: frame, clipRect: inheritedClip, zIndex: z,
                    documentOrder: node.stableID, action: WMPTransportAction.authoredAction(for: node),
                    sticky: sticky, enabled: enabled, mappingImage: mappingImage,
                    mappingTargets: mappingTargets, cursor: cursor,
                    tabStop: literalString(node, "tabStop")?.caseInsensitiveCompare("false") != .orderedSame,
                    positionMap: positionMap,
                    toolTip: toolTip(node, state: visualState, literal: literalString)))
            }

            let childClip = inheritedClip.flatMap { frame.intersection($0) } ?? (inheritedClip == nil ? frame : nil)
            for child in node.children.sorted(by: nodeOrder) {
                try walk(child, parentFrame: frame, parentAuthoredSize: ownAuthoredSize,
                         inheritedClip: childClip, parentAlpha: alpha)
            }
        }

        try walk(view, parentFrame: canvasRect,
                 parentAuthoredSize: WMPSize(width: width, height: height),
                 inheritedClip: canvasRect, parentAlpha: 1, isRoot: true)
        // A fully transparent node still lays out — its geometry is readable, and a script fades it
        // in by writing `alphaBlend` — but it draws nothing, so it must not reach the command list
        // at all. Leaving it there put invisible artwork inside `visibleBounds` and every dirty
        // rect derived from it.
        commands.removeAll { $0.alpha <= 0 }
        hits.sort { ($0.zIndex, $0.stableID) < ($1.zIndex, $1.stableID) }
        let allDirty = commands.compactMap { command in
            command.clipRect.flatMap { command.frame.intersection($0) } ?? command.frame
        }.reduce(nil as WMPRect?) { accumulated, next in
            accumulated.map { $0.union(next) } ?? next
        }
        let dirty = dirtyNodeIDs.map { identifiers in
            hits.filter { identifiers.contains($0.stableID)
                || $0.mappingTargets.contains(where: { identifiers.contains($0.stableID) }) }
                .compactMap { hit in hit.clipRect.flatMap { hit.frame.intersection($0) } ?? hit.frame }
                .reduce(nil as WMPRect?) { accumulated, next in
                    accumulated.map { $0.union(next) } ?? next
                }
        } ?? allDirty
        let metrics = WMPSceneMetrics(resolvedNodeCount: resolvedNodes.count,
            unresolvedNodeCount: unresolvedNodes.count, visibleBounds: allDirty)
        // `resizAble` is the corpus's dominant spelling and `resizable` the other; both appear in
        // the same archive. Absent is false — a borderless window gets its resize edges from this
        // and from nothing else.
        let resizable = (literalString(view, "resizAble") ?? literalString(view, "resizable"))?
            .caseInsensitiveCompare("true") == .orderedSame
        return WMPScene(viewID: registration.id, canvasSize: canvas, resizeLimits: resizeLimits,
            isResizable: resizable,
            commands: commands, hits: hits, widgets: widgets, geometries: geometries, unresolved: unresolved,
            diagnostics: diagnostics, dirtyBounds: dirty, metrics: metrics,
            wasBuiltOnMainThread: Thread.isMainThread)
    }

    private func imageCommand(node: WMPNode, path: String, frame: WMPRect,
                              clip: WMPRect?, z: Int, background: Bool, alpha: CGFloat = 1,
                              mappingMask: WMPSceneMappingMask? = nil,
                              sourceOverride: WMPRect? = nil,
                              clippingPath: String? = nil) -> WMPPaintCommand {
        let prefix = background ? "background" : ""
        let sourceX = literal(node, prefix + "CropLeft") ?? literal(node, "cropLeft")
        let sourceY = literal(node, prefix + "CropTop") ?? literal(node, "cropTop")
        let sourceWidth = literal(node, prefix + "CropWidth") ?? literal(node, "cropWidth")
        let sourceHeight = literal(node, prefix + "CropHeight") ?? literal(node, "cropHeight")
        let source = sourceOverride
            ?? (sourceX == nil && sourceY == nil && sourceWidth == nil && sourceHeight == nil ? nil
                : WMPRect(x: sourceX ?? 0, y: sourceY ?? 0,
                          width: sourceWidth ?? frame.width, height: sourceHeight ?? frame.height))
        let tiledName = background ? "backgroundTiled" : "tiled"
        // **A node that declares no key at all still gets one, if its artwork has no alpha.** That
        // is WMP's implicit magenta transparency colour (W78) — the store applies it only to a
        // sprite with no alpha channel, because only such a sprite can have meant it. A node that
        // keys anything has said what it wants and is left alone, including one whose only key is
        // a colour the parser rejected: `Alpine7618_v09` writes `transparencyColor="FF00FF"` with
        // no `#`, which resolves to nothing here and therefore falls to the same default.
        let declared = colors(node, names: ["transparencyColor", "clippingColor"])
        let image = WMPSceneImage(resourcePath: path, sourceRect: source,
            colorKeys: declared,
            tiled: literalString(node, tiledName)?.caseInsensitiveCompare("true") == .orderedSame,
            interpolation: .low, mappingMask: mappingMask,
            clippingMaskPath: clippingPath,
            clippingMaskKeys: clippingPath == nil ? []
                : colors(node, names: ["clippingColor", "transparencyColor"]),
            implicitColorKey: declared.isEmpty ? WMPColorKey.implicitTransparency : nil)
        return WMPPaintCommand(stableID: node.stableID, nodeID: node.xmlID, frame: frame,
            clipRect: clip, zIndex: z, documentOrder: node.stableID, paint: .image(image),
            alpha: alpha)
    }

    /// Resolve the first resource attribute among `names` to a path inside the archive.
    /// Shared by the view root, which must resolve its background before any nested helper exists.
    ///
    /// **Artwork is a scripted property like any other.** `mainBack.backgroundImage =
    /// "png24/intro_anim_f568.png"` is how a whole family of skins swaps what a node draws —
    /// `Alienware Invader` hides its entire player behind 568 such writes — so a script override is
    /// consulted before the authored attribute. The string it carries is an authored path and
    /// resolves under the same provider rules as markup; one that resolves to nothing warns and
    /// leaves the authored artwork in place rather than blanking the node.
    private func resolveResource(_ node: WMPNode, names: [String],
                                 overrides: WMPSceneOverrides = .empty,
                                 warn: (WMPDiagnostic) -> Void = { _ in }) throws -> (String, String)? {
        for name in names {
            if let override = overrides.properties[WMPScenePropertyAddress(
                stableID: node.stableID, property: name.lowercased())]?.string {
                let authored = override.trimmingCharacters(in: .whitespacesAndNewlines)
                // `view.backgroundImage = ""` is how every store-thumbnail `previewView` clears its
                // splash bitmap: an empty override is an authored absence, not a missing file.
                if authored.isEmpty { continue }
                // `try?`, not `try`: an override is a runtime value and `resolve` *throws* for a
                // path outside the provider. A skin that assigns a `res://wmploc/RT_IMAGE/#2024`
                // it read back off its own markup must warn like any other unresolvable path. When
                // the throw escaped it took **five views across three skins** with it — `corona`
                // and `9SeriesDefault` both lost `vPlayer` and `viewTiny` outright — which is a
                // whole player rejected over one attribute.
                if let path = try? loadedSkin.archive.resolve(authored,
                                                              relativeTo: loadedSkin.definitionPath) {
                    return (name, path)
                }
                warn(WMPDiagnostic(.resourceMissing,
                    "Script set \(node.authoredTagName).\(name) to '\(authored)', which the skin does not contain.",
                    severity: .warning, location: node.location))
            }
            guard let attribute = node.attribute(named: name) else { continue }
            guard case let .resource(authored) = attribute.value else { continue }
            if let path = try loadedSkin.archive.resolve(authored, relativeTo: loadedSkin.definitionPath) {
                return (name, path)
            }
        }
        return nil
    }

    private func literal(_ node: WMPNode, _ name: String) -> CGFloat? {
        WMPNumber.literal(node.attribute(named: name))
    }

    private func literalString(_ node: WMPNode, _ name: String) -> String? {
        guard let attribute = node.attribute(named: name), case let .literal(value) = attribute.value else { return nil }
        return value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Every key `names` resolves on this node, in order and deduplicated. `color` stops at the
    /// first hit because it answers "what colour is this"; a keyed image needs all of them.
    private func colors(_ node: WMPNode, names: [String]) -> [WMPColor] {
        var resolved: [WMPColor] = []
        for name in names {
            guard let value = color(node, names: [name]), !resolved.contains(value) else { continue }
            resolved.append(value)
        }
        return resolved
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

    private func isSlider(_ kind: WMPElementKind) -> Bool {
        switch kind {
        case .slider, .volumeSlider, .seekSlider, .balanceSlider, .customSlider, .progressBar:
            return true
        default: return false
        }
    }

    /// The `wmpprop:` path a control's `value` is bound to, lower-cased, or nil when the skin
    /// authored a literal or an expression instead.
    private func valueBindingPath(_ node: WMPNode) -> String? {
        guard let attribute = node.attribute(named: "value"),
              case let .binding(kind, path) = attribute.value, kind == .property else { return nil }
        return path.lowercased()
    }

    /// A node the markup gave a mouse handler is a hit target whatever its kind.
    ///
    /// WMP dispatches mouse events to *any* element, and skins rely on it: `Sports` builds its
    /// playlist out of ten `<TEXT>` rows that highlight under the pointer through `hilightMe()`,
    /// and hovering one hit the equaliser slider behind it instead — reported on 2026-09-08 as
    /// "Sports has no hover actions". Measured over the 179-archive corpus, **537 nodes across 143
    /// skins** carry a mouse handler on a kind `isInteractive` does not list: 326 `<TEXT>` across
    /// 69 skins, 90 `<EFFECTS>` across 81, 21 `<VIDEO>` across 21, and a tail of transport spellings
    /// this engine parses as unknown kinds. Reproduce with `python3 scripts/wmp_input_kinds.py`;
    /// see `reference/harness.md` § *Input and tooltips the markup authors*.
    ///
    /// `passthrough="true"` still wins — it is the attribute that says "drawn, not touchable" — so
    /// a decorative overlay does not start swallowing the controls under it.
    private func authorsInputHandler(_ node: WMPNode) -> Bool {
        node.attributes.contains { attribute in
            guard case .handler = attribute.value else { return false }
            let name = attribute.name.lowercased()
            return ["onclick", "onmouseover", "onmouseout", "onmousedown", "onmouseup"].contains(name)
        }
    }

    /// The tip for one control in the state it is currently drawn in.
    ///
    /// WMP swaps the text with the button: `upToolTip` while it is up, `downToolTip` while it is
    /// down, and `toolTip` when the skin authored only one — a mute button reads "Mute" and then
    /// "Sound". The corpus authors 4,789 `upToolTip`, 3,797 `toolTip` and 541 `downToolTip` across
    /// 176, 175 and 105 of the 179 archives; reproduce those with the scan in
    /// `reference/harness.md` § *Input and tooltips the markup authors*.
    ///
    /// `literal` is the caller's resolver rather than this type's, so a script assignment —
    /// `alx_dl.wms` writes `toolTip='Volume'` from its slider's `onMouseUp` — is read through the
    /// scene overrides instead of being shadowed by the authored attribute.
    private func toolTip(_ node: WMPNode, state: WMPVisualInteractionState,
                         literal: (WMPNode, String) -> String?) -> String? {
        let stateTip = state == .down ? literal(node, "downToolTip") : literal(node, "upToolTip")
        return stateTip ?? literal(node, "toolTip")
    }

    private func isInteractive(_ kind: WMPElementKind) -> Bool {
        switch kind {
        case .button, .buttonGroup, .slider, .volumeSlider, .seekSlider,
             .balanceSlider, .customSlider, .playElement, .pauseElement, .stopElement, .prevElement,
             .nextElement, .rewElement, .ffwdElement,
             .playButton, .pauseButton, .stopButton, .prevButton, .nextButton,
             .rewButton, .ffwdButton, .muteButton, .repeatButton,
             .returnButton, .shuffleButton, .playlist, .dropdownPlaylist, .popup,
             .editBox, .listBox: return true
        default: return false
        }
    }

    /// The extent of the subtree a node can place using authored literals and artwork alone, in
    /// the node's own coordinates. Anything script-driven contributes nothing rather than a guess —
    /// the builder never invents geometry — but a container whose own size is unknown is still
    /// descended into at its known origin, which is how `Darkling`'s unsized `viewWrapper` reports
    /// the walls beneath it.
    private func contentUnionSize(of node: WMPNode, overrides: WMPSceneOverrides,
                                  warn: (WMPDiagnostic) -> Void) throws -> WMPSize {
        var extent = WMPSize(width: 0, height: 0)
        for child in node.children {
            if isNonLayout(child) {
                let nested = try contentUnionSize(of: child, overrides: overrides, warn: warn)
                extent = WMPSize(width: max(extent.width, nested.width),
                                 height: max(extent.height, nested.height))
                continue
            }
            guard let left = child.attribute(named: "left") == nil ? 0 : literal(child, "left"),
                  let top = child.attribute(named: "top") == nil ? 0 : literal(child, "top") else { continue }
            var width = literal(child, "width")
            var height = literal(child, "height")
            if width == nil || height == nil,
               let (_, path) = try resolveResource(child, names: intrinsicSizeResourceNames(for: child.kind),
                                                   overrides: overrides, warn: warn) {
                let intrinsic = try imageStore.image(for: path).size
                if width == nil, intrinsic.width > 0 { width = intrinsic.width }
                if height == nil, intrinsic.height > 0 { height = intrinsic.height }
            }
            if width == nil || height == nil {
                let nested = try contentUnionSize(of: child, overrides: overrides, warn: warn)
                if width == nil, nested.width > 0 { width = nested.width }
                if height == nil, nested.height > 0 { height = nested.height }
            }
            guard let width, let height, width > 0, height > 0 else { continue }
            extent = WMPSize(width: max(extent.width, left + width),
                             height: max(extent.height, top + height))
        }
        return extent
    }

    /// **A `<TEXT>`'s own artwork is its glyphs.** Every other node falls back to the natural size
    /// of its `backgroundImage`; a text has none, and WMP sizes it from the face and the string.
    ///
    /// This is the single largest starvation class in the corpus: **1,441 `<TEXT>` nodes across 127
    /// of the 179 archives** resolve no size in the default state, 1,058 of them missing width
    /// *and* height. `Cablemusic` is the worked case — its script lays out ten readouts with
    /// `txtShow.top/left/width/fontSize` and never a `height`, because in WMP there is nothing to
    /// set — so the whole show/clip/author/copyright/bitrate block, and the seventeen station rows
    /// in each of its two drawers, had no frame and never drew. Reported as "there is no track
    /// display".
    ///
    /// A width measured from the *current* value is WMP's own behaviour: the box grows with the
    /// string. That makes an empty value legitimately zero-wide and therefore still undrawn, which
    /// is correct — there is nothing to draw — and it starts drawing on the transaction that gives
    /// it a value, because a script write to `value` rebuilds the scene. An authored dimension
    /// always wins; this only answers one the skin never stated.
    ///
    /// `literal`/`literalString` are the caller's override-aware resolvers rather than this type's
    /// markup-only ones. That is the whole point here: the string and the face this measures are
    /// what a script just wrote, not what the markup declared, and reading the markup answered nil
    /// for every node whose value only exists at runtime — which is all of them.
    private func intrinsicTextSize(_ node: WMPNode,
                                   literal: (WMPNode, String) -> CGFloat?,
                                   literalString: (WMPNode, String) -> String?) -> WMPSize? {
        guard let value = literalString(node, "value") else { return nil }
        let face = literalString(node, "fontFace") ?? literalString(node, "fontType") ?? "Arial"
        let size = max(1, literal(node, "fontSize") ?? 12)
        let style = (literalString(node, "fontStyle") ?? "").lowercased()
        let bold = style.contains("bold"), italic = style.contains("italic")
        return WMPSize(
            width: WMPTextMetrics.width(of: value, fontName: face, fontSize: size,
                                        bold: bold, italic: italic).rounded(.up),
            height: WMPTextMetrics.lineHeight(fontName: face, fontSize: size,
                                              bold: bold, italic: italic))
    }

    private func intrinsicSizeResourceNames(for kind: WMPElementKind) -> [String] {
        switch kind {
        case .customSlider:
            // **A `CUSTOMSLIDER` is the size of its `positionImage`, not of its `image`.** The
            // image is a filmstrip of every position the control can be in — `ALXMorph/volume.png`
            // is 2232x38 against a 72x38 map, 31 frames — so sizing from it makes the control
            // thirty times too wide. The map comes first for that reason alone.
            return ["positionImage", "image", "backgroundImage", "background", "foregroundImage"]
        case .slider, .volumeSlider, .seekSlider, .balanceSlider, .progressBar:
            // WMP slider controls conventionally omit width/height and take their track size from
            // foregroundImage. thumbImage is a last-resort size for unusual authored controls.
            return ["image", "backgroundImage", "background", "foregroundImage", "thumbImage"]
        case .buttonGroup:
            // **A `BUTTONGROUP`'s size is its mapping image's size, and often nothing else can say
            // so.** The group's normal state is usually the window's own background artwork, so the
            // skin authors no `image` and no geometry at all: `Cablemusic`'s six groups — its eight
            // presets, stop, close, minimize, next/previous effect, shrink, the bandwidth pair and
            // all three drawer tabs — are `<BUTTONGROUP mappingImage="map.gif" hoverImage="…"
            // downImage="…">` and nothing more. With no size the group resolved no frame, so it
            // registered no hit target and every control in it was dead, while the artwork beneath
            // still drew the buttons: reported as "most buttons don't work". The mapping image is
            // definitionally the group's own pixel grid — every child is a colour region inside
            // it — so it is the right fallback, and the state images are the same bitmap again.
            // 31 groups across 16 of the 179 corpus archives resolve no size today.
            return ["image", "mappingImage", "hoverImage", "downImage",
                    "backgroundImage", "background"]
        default:
            return ["image", "backgroundImage", "background"]
        }
    }

    private func widgetKind(_ kind: WMPElementKind) -> WMPWidgetKind? {
        switch kind {
        case .text: return .text
        case .slider, .volumeSlider, .seekSlider, .balanceSlider, .customSlider, .progressBar:
            return .slider
        case .playlist: return .playlist
        case .dropdownPlaylist: return .dropdownPlaylist
        case .popup: return .popup
        case .editBox: return .editBox
        case .listBox: return .listBox
        case .effects: return .effects
        case .video, .wmpVideo: return .video
        default: return nil
        }
    }

    /// The mapping-image colour of each child that declares one, keyed by colour.
    ///
    /// **Two children can declare the same `mappingColor`, and building this with
    /// `uniqueKeysWithValues` traps the process.** `Cablemusic` authors `bnpb6` and `bnpb7` both as
    /// `#00C0FF` — one preset button too many for the eight regions its `map.gif` has — and WMP
    /// draws and hits the first of them rather than refusing the skin. Nothing reached this code
    /// before because that skin's groups resolved no frame at all; sizing them from the mapping
    /// image is what turned a dead control into a crash on load. First in document order wins.
    private func mappingColors(of group: WMPNode) -> [WMPColor: Int] {
        Dictionary(group.children.compactMap { child -> (WMPColor, Int)? in
            guard let value = child.attribute(named: "mappingColor")?.value,
                  case let .color(color) = value else { return nil }
            return (color, child.stableID)
        }, uniquingKeysWith: { first, _ in first })
    }

    /// **A `BUTTONGROUP` child that declares a `mappingColor` is a region of the group's mapping
    /// image, not a box on the canvas.** `<BUTTONELEMENT>` was already exempt from layout; its
    /// semantic siblings — `<PLAYELEMENT>`, `<STOPELEMENT>`, `<NEXTELEMENT>` and peers — were not,
    /// so every one of them was walked as a control, failed to find geometry it never had, and was
    /// recorded `unresolved`. That is **494 of the corpus's 2,380 unresolved nodes across ~90
    /// skins**, and none of it was ever a drawing defect: hit testing already reaches them through
    /// the group's `mappingTargets`. It mattered because `starved.tsv` ranks on that numerator, so
    /// a fifth of the ranking was phantom rows.
    ///
    /// The test is the attribute **under a `BUTTONGROUP`** rather than the kind, because that pair
    /// is exactly what `mappingColors(of:)` builds the group's targets from — and the attribute
    /// alone is not enough. `polygon` authors `<subview id="ToggleButton" left="75" top="27"
    /// width="18" height="18" mappingImage="Toggle_MAP.bmp" mappingColor="#FF0000">`: a mask on the
    /// subview itself, not a group membership. Testing the attribute alone dropped its geometry,
    /// which lost the panel it draws and moved the `returnButton` inside it to the window's corner.
    /// A skin that authors one of the transport tags standalone, with its own artwork and frame,
    /// still lays out for the same reason.
    private func isNonLayout(_ node: WMPNode) -> Bool {
        if node.parent?.kind == .buttonGroup, node.attribute(named: "mappingColor") != nil {
            return true
        }
        return isNonLayout(node.kind)
    }

    private func isNonLayout(_ kind: WMPElementKind) -> Bool {
        switch kind {
        // `<EQUALIZERSETTINGS id="eq" enabled="true"/>` is the object a skin's own equaliser
        // sliders bind to through `wmpprop:eq.gainLevelN`, not a control: 164 of 178 corpus skins
        // author it and not one gives it geometry. Treating it as a widget hung an AppKit panel of
        // NSSliders on it, over the artwork the skin draws its own bands with.
        case .theme, .player, .network, .script, .buttonElement, .equalizerSettings: return true
        default: return false
        }
    }

    private func nodeOrder(_ lhs: WMPNode, _ rhs: WMPNode) -> Bool {
        let leftZ = Int(literal(lhs, "zIndex") ?? 0), rightZ = Int(literal(rhs, "zIndex") ?? 0)
        return leftZ == rightZ ? lhs.stableID < rhs.stableID : leftZ < rightZ
    }

}

struct WMPScenePropertyAddress: Hashable, Codable, Sendable {
    let stableID: Int
    let property: String
}

struct WMPSceneOverrides: Hashable, Codable, Sendable {
    var geometry: [WMPScenePropertyAddress: CGFloat]
    var properties: [WMPScenePropertyAddress: WMPJSONValue]

    static let empty = WMPSceneOverrides(geometry: [:], properties: [:])
}
