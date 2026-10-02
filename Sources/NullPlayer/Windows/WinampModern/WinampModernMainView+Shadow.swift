import AppKit

/// The `.wal` window drop shadow: `SkinWindowShadow` fed with this view's outline.
///
/// `.wal` draws straight into `draw(_:)`, so there is no frame image to hand over the way `.wmz`
/// does. The outline is rendered on purpose instead — the same `renderer.draw` the window makes,
/// into an offscreen buffer at one pixel per point, with every hosted surface's frame filled in,
/// because the renderer draws only the chrome around them and their area would otherwise read as a
/// hole.
///
/// **What invalidates the shape is an event that can move the outline, never invalidation.** Layer
/// FX skins invalidate the whole window 30 times a second through `repaintRequested`, and a playing
/// skin writes its readouts through `graphDidMutate` every tick; neither may cost a render. So a
/// graph change invalidates only past `WinampModernShadowOutlineGate`, and a layout switch, a
/// canvas change and a resize invalidate outright. The shadow pulls at most once per
/// `shadowShapeInterval`, with a trailing pull that catches the end of an animation. A render whose
/// outline did not change costs that render and an off-main byte compare.
extension WinampModernMainView {
    static let shadowShapeInterval: CFTimeInterval = 0.25

    var shadowTraceName: String {
        "wal:" + (renderer.container.attributes["id"] ?? renderer.container.stableID.description)
    }

    func attachWindowShadow(to window: NSWindow) {
        windowShadow.attach(to: window, name: shadowTraceName) { [weak self] in
            self?.shadowOutline() ?? []
        }
    }

    /// The graph changed. Cheap unless the gate says this window's outline may have moved. Run once
    /// per runloop turn from the graph settle (`scheduleGraphSettle(.shadowOutline)`), never per write.
    func graphMayHaveMovedShadowOutline() {
        guard windowShadow.isActive,
              shadowOutlineGate.mayHaveMoved(renderer, traceName: shadowTraceName) else { return }
        windowShadow.invalidateShape("graph")
    }

    /// What `SkinWindowShadow` pulls: the scene as `draw(_:)` paints it, at one pixel per point.
    private func shadowOutline() -> [CGImage] {
        guard !isTornDown else { return [] }
        shadowOutlineGate.record(renderer, traceName: shadowTraceName)
        // One pixel per point is all the shadow reads (`AlphaPlane` resamples to points), and a
        // quarter of the pixels of a Retina pass: cPro2 Dark Aluminum's beat meter resizes inside
        // its top bar ~1.5 times a second, a real geometry change that has to be looked at, and
        // each look cost 14 ms at 2x in a debug build.
        return outlineImage().map { [$0] } ?? []
    }

    /// The scene as `draw(_:)` paints it, plus every visible hosted surface's frame as solid.
    private func outlineImage() -> CGImage? {
        let width = Int(bounds.width.rounded()), height = Int(bounds.height.rounded())
        guard width > 0, height > 0,
              let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                      bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        // Strings drawn through AppKit take their destination from the current context, not from
        // the one the renderer is handed.
        let hostContext = NSGraphicsContext.current
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        defer { NSGraphicsContext.current = hostContext }
        renderer.isWindowActive = window?.isKeyWindow ?? true
        context.saveGState()
        if skinScale != 1 { context.scaleBy(x: skinScale, y: skinScale) }
        if drawsHostChrome { drawHostChrome(in: context) }
        renderer.drawOutline(in: context)
        context.restoreGState()
        context.setFillColor(CGColor(gray: 0, alpha: 1))
        for subview in subviews where !subview.isHidden && subview.alphaValue > 0 {
            context.fill(subview.frame)
        }
        return context.makeImage()
    }
}

/// The two filters a `.wal` graph write passes before it costs an outline render, cheapest first.
///
/// `WasabiObjectGraph.shapeGeneration` moves only on a write that can move an outline at all —
/// geometry, structure, visibility, alpha, an image. But the counter is graph-wide, so a write in
/// another window, or in this container's *inactive* layout, still moves it: cPro2 Dark Aluminum
/// writes `visible`, `alpha`, `x` and `w` in its shade layout and About window every second, which
/// cost the player 34 outline renders in 20 s of playback with nothing on it moving. So the second
/// filter is a fingerprint of this window's own active scene, read from the renderer's memoized
/// scene, which the next draw needs anyway.
struct WinampModernShadowOutlineGate {
    private var generation: UInt64?
    private var fingerprint: Int?
    /// `NP_SKIN_SHADOW_TRACE` only: the last scene's per-node signatures, so a fingerprint change
    /// can name the node that moved.
    private var traceSignatures: [String] = []

    /// Whether a graph change may have moved the outline since the last `record`.
    mutating func mayHaveMoved(_ renderer: WasabiSceneRenderer, traceName: @autoclosure () -> String) -> Bool {
        let generation = renderer.container.graphShapeGeneration
        guard generation != self.generation else { return false }
        self.generation = generation
        return sceneFingerprint(renderer, traceName: traceName()) != fingerprint
    }

    /// The outline is being rendered from the scene as it stands now.
    mutating func record(_ renderer: WasabiSceneRenderer, traceName: @autoclosure () -> String) {
        generation = renderer.container.graphShapeGeneration
        fingerprint = sceneFingerprint(renderer, traceName: traceName())
    }

    /// What in the scene can move its outline: each painted node's place, clip, artwork and whether
    /// it is visible at all.
    private mutating func sceneFingerprint(_ renderer: WasabiSceneRenderer,
                                           traceName: @autoclosure () -> String) -> Int {
        var hasher = Hasher()
        hasher.combine(renderer.canvasSize.width)
        hasher.combine(renderer.canvasSize.height)
        var signatures: [String] = []
        for node in renderer.sceneNodes() {
            hasher.combine(node.object.stableID)
            hasher.combine(node.frame.origin.x); hasher.combine(node.frame.origin.y)
            hasher.combine(node.frame.width); hasher.combine(node.frame.height)
            hasher.combine(node.clip.origin.x); hasher.combine(node.clip.origin.y)
            hasher.combine(node.clip.width); hasher.combine(node.clip.height)
            hasher.combine(node.bitmapID)
            hasher.combine(node.inheritedAlpha)
            if SkinWindowShadow.isTraceEnabled {
                signatures.append("\(node.object.typeName)#\(node.object.attributes["id"] ?? "-") "
                    + "\(node.frame) clip=\(node.clip) bmp=\(node.bitmapID ?? "-") a=\(node.inheritedAlpha)")
            }
        }
        if SkinWindowShadow.isTraceEnabled {
            let before = Set(traceSignatures), after = Set(signatures)
            if !traceSignatures.isEmpty, before != after {
                NSLog("[shadow] %@ scene -%@ +%@", traceName(),
                      before.subtracting(after).prefix(3).joined(separator: " | "),
                      after.subtracting(before).prefix(3).joined(separator: " | "))
            }
            traceSignatures = signatures
        }
        return hasher.finalize()
    }
}
