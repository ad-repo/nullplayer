import AppKit

/// The `.wal` window drop shadow: `SkinWindowShadow` fed with this view's outline.
///
/// `.wal` draws straight into `draw(_:)`, so there is no frame image to hand over the way `.wmz`
/// does. The outline is rendered on purpose instead — the same `renderer.draw` the window makes,
/// into an offscreen buffer at one pixel per point, with every hosted surface's frame filled in,
/// because the renderer draws only the chrome around them and their area would otherwise read as a
/// hole.
///
/// **What asks for a render is an event that can move the outline, never invalidation.** Layer FX
/// skins invalidate the whole window 30 times a second through `repaintRequested`, and a playing
/// skin writes its readouts through `graphDidMutate` every tick; neither may cost a render. So a
/// graph change asks only when `WasabiObjectGraph.shapeGeneration` moved (geometry, structure,
/// visibility, alpha, an image), and a layout switch, a canvas change, a window resize and the
/// window coming on screen ask outright. Requests are throttled leading-edge: the first renders at
/// once, the rest coalesce to one per `shadowShapeInterval` with a trailing pass that catches the
/// end of an animation. A render whose outline did not change costs that render and an off-main
/// byte compare.
extension WinampModernMainView {
    static let shadowShapeInterval: CFTimeInterval = 0.25

    var shadowTraceName: String {
        "wal:" + (renderer.container.attributes["id"] ?? renderer.container.stableID.description)
    }

    func attachWindowShadow(to window: NSWindow) {
        detachWindowShadow()
        windowShadow.attach(to: window, name: shadowTraceName)
        let center = NotificationCenter.default
        shadowObservers.append(center.addObserver(
            forName: NSWindow.didMoveNotification, object: window, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.windowShadow.reassert() }
            })
        shadowObservers.append(center.addObserver(
            forName: NSWindow.didBecomeKeyNotification, object: window, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.windowShadow.reassert() }
            })
        shadowObservers.append(center.addObserver(
            forName: NSWindow.didResizeNotification, object: window, queue: .main) { [weak self, weak window] _ in
                MainActor.assumeIsolated {
                    guard let self, let window else { return }
                    self.windowShadow.updateFrame(parentFrame: window.frame, trigger: "resize")
                    self.requestShadowShape("resize")
                }
            })
        requestShadowShape("attach")
    }

    func detachWindowShadow() {
        shadowObservers.forEach(NotificationCenter.default.removeObserver)
        shadowObservers.removeAll()
        windowShadow.detach()
        shadowShapeGeneration = nil
        shadowSceneFingerprint = nil
    }

    func windowShadowOcclusionDidChange(isOnScreen: Bool) {
        windowShadow.reassert()
        // A window that was hidden skipped every request while it was; one render catches it up.
        if isOnScreen { requestShadowShape("visible") }
    }

    /// Ask for the outline to be rendered. `onlyIfOutlineMayHaveMoved` is the graph path: it renders
    /// only when `shapeGeneration` has moved since the last render.
    func requestShadowShape(_ trigger: String, onlyIfOutlineMayHaveMoved: Bool = false) {
        guard !isTornDown, windowShadow.isAttached, SkinWindowShadow.isEnabledPreference else { return }
        if onlyIfOutlineMayHaveMoved {
            // Two filters, cheapest first. The counter is graph-wide, so a write in another window
            // — or in this container's *inactive* layout — still moves it: cPro2 Dark Aluminum
            // writes `visible`, `alpha`, `x` and `w` in its shade layout and About window every
            // second, which cost the player 34 outline renders in 20 s of playback with nothing on
            // it moving. The scene fingerprint is this window's own active layout, and it reads the
            // renderer's memoized scene, which the next draw needs anyway.
            let generation = renderer.container.graphShapeGeneration
            guard generation != shadowShapeGeneration else { return }
            shadowShapeGeneration = generation
            guard sceneOutlineFingerprint() != shadowSceneFingerprint else { return }
        }
        let wait = shadowLastShapeRender + Self.shadowShapeInterval - CFAbsoluteTimeGetCurrent()
        if wait <= 0, !shadowShapeScheduled {
            renderShadowShape(trigger)
            return
        }
        shadowPendingTrigger = trigger
        guard !shadowShapeScheduled else { return }
        shadowShapeScheduled = true
        DispatchQueue.main.asyncAfter(deadline: .now() + max(0, wait)) { [weak self] in
            guard let self else { return }
            self.shadowShapeScheduled = false
            self.renderShadowShape(self.shadowPendingTrigger ?? "trailing")
            self.shadowPendingTrigger = nil
        }
    }

    private func renderShadowShape(_ trigger: String) {
        guard !isTornDown, let window, windowShadow.isAttached,
              window.occlusionState.contains(.visible) else { return }
        let started = CFAbsoluteTimeGetCurrent()
        shadowLastShapeRender = started
        shadowShapeGeneration = renderer.container.graphShapeGeneration
        shadowSceneFingerprint = sceneOutlineFingerprint()
        // One pixel per point is all the shadow reads (`SkinWindowShadow.alphaPlane` resamples to
        // points), and a quarter of the pixels of a Retina pass: cPro2 Dark Aluminum's beat meter
        // resizes inside its top bar ~1.5 times a second, a real geometry change that has to be
        // looked at, and each look cost 14 ms at 2x in a debug build.
        guard let image = outlineImage(scale: 1) else { return }
        // The outline render is main-thread work the shadow's own timing (off-main) cannot see.
        let label = SkinWindowShadow.isTraceEnabled
            ? trigger + String(format: " render=%.1fms", (CFAbsoluteTimeGetCurrent() - started) * 1_000)
            : trigger
        windowShadow.update(layers: [image], parentFrame: window.frame, trigger: label)
    }

    /// What in this window's scene can move its outline: each painted node's place, clip, artwork
    /// and whether it is visible at all.
    private func sceneOutlineFingerprint() -> Int {
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
            let before = Set(shadowTraceSignatures), after = Set(signatures)
            if !shadowTraceSignatures.isEmpty, before != after {
                NSLog("[shadow] %@ scene -%@ +%@", shadowTraceName,
                      before.subtracting(after).prefix(3).joined(separator: " | "),
                      after.subtracting(before).prefix(3).joined(separator: " | "))
            }
            shadowTraceSignatures = signatures
        }
        return hasher.finalize()
    }

    /// The scene as `draw(_:)` paints it, plus every visible hosted surface's frame as solid.
    private func outlineImage(scale: CGFloat) -> CGImage? {
        let size = bounds.size
        let width = Int((size.width * scale).rounded()), height = Int((size.height * scale).rounded())
        guard width > 0, height > 0,
              let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                      bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        context.scaleBy(x: scale, y: scale)
        // Strings drawn through AppKit take their destination from the current context, not from
        // the one the renderer is handed.
        let hostContext = NSGraphicsContext.current
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        defer { NSGraphicsContext.current = hostContext }
        // A bitmap's device space is its pixels (B80); put back what the next real draw set.
        let pixelsPerUnit = renderer.devicePixelsPerContextUnit
        renderer.devicePixelsPerContextUnit = 1
        defer { renderer.devicePixelsPerContextUnit = pixelsPerUnit }
        renderer.isWindowActive = window?.isKeyWindow ?? true
        // An animated layer contributes only what it shows in every frame (`drawsAnimationCores`).
        renderer.drawsAnimationCores = true
        defer { renderer.drawsAnimationCores = false }
        context.saveGState()
        if skinScale != 1 { context.scaleBy(x: skinScale, y: skinScale) }
        if drawsHostChrome { drawHostChrome(in: context) }
        renderer.draw(in: context)
        context.restoreGState()
        context.setFillColor(CGColor(gray: 0, alpha: 1))
        for subview in subviews where !subview.isHidden && subview.alphaValue > 0 {
            context.fill(subview.frame)
        }
        return context.makeImage()
    }
}
