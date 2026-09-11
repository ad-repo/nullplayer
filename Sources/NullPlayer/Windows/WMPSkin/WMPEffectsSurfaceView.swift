import AppKit

/// The `<EFFECTS>` rect: NullPlayer's own visuals, in the frame the skin authored for them.
///
/// **The geometry was always there and nothing is invented here.** Every `<EFFECTS>` element
/// measured in the corpus carries `width` and `height`, most of them expressions off the frame the
/// skin drew around it (`WoW`: `<effects id="visEffects" width="jscript:visFrame.width" …>`), and
/// 183 of them across 166 of 177 archives were hosted on nothing at all until `<EFFECTS>` became an
/// element kind (W101). What goes in the rect is `WMPEffectSelection`'s compact WMP-native effect,
/// rendered in this view rather than borrowed from NullPlayer's standalone visualization window.
///
/// **Nothing playing draws nothing at all.** W9 removed the video placeholder because an opaque
/// surface with nothing to show is worse than no surface: it filled its frame with black over the
/// artwork of 166 skins. This one is transparent whenever no visualizer is running, so the skin's
/// own screen artwork is what shows through — and it never takes a click, because 51 skins wire an
/// `onClick` on the rect to cycle their effect and that handler belongs to the scene's own hit
/// testing, not to this overlay.
@MainActor
final class WMPEffectsSurfaceView: NSView, VisualizationMenuTarget {
    private var levels: [Float] = []
    private var isActive = false
    private var effect = WMPEffectSelection.shared.current
    private var appliedPreset = -1
    private var engineView: VisualizationGLView?
    private var pcmObserver: NSObjectProtocol?
    private var selectionObserver: NSObjectProtocol?
    private var isTornDown = false
    /// Preset/effect auto-cycling, through the same stored keys NullPlayer's own visualization
    /// window and the `.wal` surface use, so a cycle set in one place is the cycle in all of them.
    private var presetCycleMode = ProjectMPresetCycleSettings.loadMode()
    private var presetCycleInterval = ProjectMPresetCycleSettings.loadInterval()
    private var tripexCycleMode: VisualizationCycleMode = .cycle
    private var tripexCycleInterval: TimeInterval = 30
    private var cycleTimer: Timer?
    /// These are the actual suite renderers, not visual approximations. Their scopes keep a WMP
    /// skin's right-click choices separate from the standalone and `.wal` surfaces.
    private let cavaPresenter = CavaPresenter(scope: .wmpEffects)
    private let visClassicWaveform = WinampModernWaveformTap(consumerId: "wmp.effects.visclassic")
    private var visClassicBridge: VisClassicBridge?
    private var visClassicBytes: [UInt8] = []
    /// The GL engines are pulled, not pushed: the view is never in the hierarchy, its display link
    /// never starts, and this timer asks it for one frame at a time. 30fps rather than 60 because
    /// every frame costs a `glReadPixels` of the rect, and the rect is small — Cerulean's is
    /// 103x75 — so the readback is cheap but not free.
    private var engineFrameTimer: Timer?
    private var engineImage: CGImage?
    private static let engineFrameInterval: TimeInterval = 1.0 / 30

    override var isFlipped: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        cavaPresenter.onNeedsDisplay = { [weak self] in
            guard let self, self.isActive, self.effect.style == .cava else { return }
            self.needsDisplay = true
        }
        selectionObserver = NotificationCenter.default.addObserver(
            forName: WMPEffectSelection.didChange, object: nil, queue: .main
        ) { [weak self] _ in MainActor.assumeIsolated { self?.applySelection() } }
    }

    required init?(coder: NSCoder) { nil }

    deinit {
        for observer in [pcmObserver, selectionObserver].compactMap({ $0 }) {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    /// The engine hosts a click-through picture, so the whole surface is click-through: a press over
    /// the rect reaches `WMPMainView`, which raises the skin's own `onClick` on the `<EFFECTS>` node.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func removeFromSuperview() {
        teardown()
        super.removeFromSuperview()
    }

    private func teardown() {
        guard !isTornDown else { return }
        isTornDown = true
        for observer in [pcmObserver, selectionObserver].compactMap({ $0 }) {
            NotificationCenter.default.removeObserver(observer)
        }
        pcmObserver = nil; selectionObserver = nil
        cycleTimer?.invalidate(); cycleTimer = nil
        engineFrameTimer?.invalidate(); engineFrameTimer = nil
        cavaPresenter.stop()
        visClassicWaveform.stop()
        visClassicBridge = nil
        visClassicBytes = []
        releaseEngine()
    }

    // MARK: - Host state

    /// Playback state is what decides whether anything is drawn at all, and the selection is what
    /// decides what. Both arrive on the same snapshot the rest of the window refreshes from.
    func update(_ snapshot: WMPHostSnapshot) {
        let active = snapshot.state == .playing
        guard active != isActive else { return }
        isActive = active
        applySelection()
    }

    func updateSpectrum(_ levels: [Float]) {
        self.levels = levels
        if isActive { needsDisplay = true }
    }

    override func layout() {
        super.layout()
        engineView?.frame = bounds
    }

    private func applySelection() {
        guard !isTornDown else { return }
        effect = WMPEffectSelection.shared.current
        // **A WMP effect is part of the skin's composition, and that is now enforced by the scene
        // rather than by refusing engines (W140).** The skin's own artwork composites over this
        // rect, so an opaque renderer is occluded exactly where the markup says it is. What still
        // holds is that a GL engine is never *mounted* here: it renders offscreen and is presented
        // as an image, because a legacy CGL drawable between two raster layers has no guaranteed
        // ordering and its own clock tears against the overlay's edge.
        releaseEngine()
        cavaPresenter.stop()
        visClassicWaveform.stop()
        if isActive {
            switch effect.style {
            case .cava:
                cavaPresenter.start()
            case .visClassic:
                visClassicWaveform.start()
            case .projectM, .geiss, .tripex:
                startOffscreenEngine()
            case .bars, .spikes, .ambience:
                break
            }
        }
        if !isActive { levels = [] }
        needsDisplay = true
    }

    /// The engine view, built but never added to the hierarchy. `makeEngineView` wires the PCM
    /// observer it needs; `startRendering` is deliberately not called, because the frames come from
    /// `engineFrameTimer` and a display link would render onto a drawable nothing presents.
    private func startOffscreenEngine() {
        guard let engine = effect.engine, let view = makeEngineView() else { return }
        view.switchEngine(to: engine, persistPreference: false)
        applyPreset(to: view, engine: engine)
        applyPresetCycleMode()
        engineFrameTimer = Timer.scheduledTimer(withTimeInterval: Self.engineFrameInterval,
                                                repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.pullOffscreenFrame() }
        }
    }

    private func pullOffscreenFrame() {
        guard !isTornDown, isActive, let engineView, let engine = effect.engine else { return }
        let scale = window?.backingScaleFactor ?? 2
        let width = max(1, Int((bounds.width * scale).rounded()))
        let height = max(1, Int((bounds.height * scale).rounded()))
        // `initializeEngineOnRenderThread` sizes the engine from `convertToBacking(bounds)`, so the
        // frame is the rect in *points* and the readback asks for the same rect in pixels — set it
        // in pixels and the engine would be created at twice the surface it renders into.
        engineView.frame = NSRect(origin: .zero, size: bounds.size)
        applyPreset(to: engineView, engine: engine)
        guard let image = engineView.renderOffscreenImage(pixelWidth: width, pixelHeight: height) else { return }
        engineImage = image
        needsDisplay = true
    }

    private func makeEngineView() -> VisualizationGLView? {
        guard let view = VisualizationGLView(frame: bounds, pixelFormat: nil) else { return nil }
        // **Never `addSubview`.** See `startOffscreenEngine`: this view exists only to own a GL
        // context and an engine, and its picture reaches the skin through `renderOffscreenImage`.
        engineView = view
        appliedPreset = -1
        // **PCM arrives on the audio thread, and the observer must not hop to the main actor to
        // deliver it.** `.audioPCMDataUpdated` is posted from `AudioEngine.processAudioBuffer`
        // inside the tap; `MainActor.assumeIsolated` there is a `dispatch_assert_queue` failure and
        // the process traps (SIGTRAP) the moment a surface exists and a track plays. The engine
        // view takes its own lock, so it is written to directly off the posting thread — the same
        // shape `WinampModernVisualizationSurfaceView` uses.
        let engine = view
        pcmObserver = NotificationCenter.default.addObserver(
            forName: .audioPCMDataUpdated, object: nil, queue: nil
        ) { notification in
            guard let pcm = notification.userInfo?["pcm"] as? [Float] else { return }
            engine.updatePCM(pcm)
        }
        return view
    }

    private func releaseEngine() {
        if let observer = pcmObserver { NotificationCenter.default.removeObserver(observer) }
        pcmObserver = nil
        cycleTimer?.invalidate(); cycleTimer = nil
        engineFrameTimer?.invalidate(); engineFrameTimer = nil
        engineImage = nil
        guard let view = engineView else { return }
        view.stopRendering()
        engineView = nil
        appliedPreset = -1
    }

    /// `currentPreset` is a number in the markup and a different thing in each engine — ProjectM's
    /// preset list, Geiss's and Tripex's effect list — so the selection's number is applied modulo
    /// what the running engine has, and the title it landed on is reported back. A skin reading
    /// `currentPresetTitle` (42 archives) then sees the preset that is actually on screen.
    private func applyPreset(to view: VisualizationGLView, engine: VisualizationType) {
        let wanted = WMPEffectSelection.shared.preset
        guard wanted != appliedPreset else { return }
        appliedPreset = wanted
        switch engine {
        case .projectM:
            guard view.presetCount > 0 else { return }
            let index = wanted % view.presetCount
            view.selectPreset(at: index)
            WMPEffectSelection.shared.presetTitle = view.presetName(at: index)
        case .geiss:
            guard view.geissEffectCount > 0 else { return }
            let index = wanted % view.geissEffectCount
            view.selectGeissEffect(at: index)
            WMPEffectSelection.shared.presetTitle = view.geissEffectName(at: index)
        case .tripex:
            guard view.tripexEffectCount > 0 else { return }
            let index = wanted % view.tripexEffectCount
            view.selectTripexEffect(at: index)
            WMPEffectSelection.shared.presetTitle = view.tripexEffectName(at: index)
        }
    }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        // A stopped player leaves the skin's own artwork visible. The spectrum is what the three
        // WMP-native renderers draw from; Cava, vis_classic and the GL engines carry their own
        // audio, so an empty `levels` must not stand them down.
        guard isActive else { return }
        switch effect.style {
        case .bars, .spikes, .ambience: if levels.isEmpty { return }
        case .cava, .visClassic, .projectM, .geiss, .tripex: break
        }
        // `bounds`, never `dirtyRect`: AppKit is free to hand a view a dirty rect larger than
        // itself — here the whole 596x468 window arrived as {{-269, -26}, {596, 468}} in this
        // view's coordinates — and a layer-backed view does not clip it (`masksToBounds` is
        // false). Filling it painted this surface's wash over the entire skin.
        //
        // **Every renderer fills the authored rect and nothing shapes it here.** A skin that wants
        // a circular lens, a tilted oval, or a square pane draws its own artwork *over* this
        // surface — the scene's paint commands from the `<EFFECTS>` node onwards are hosted above
        // it (`WMPWidget.commandSplitIndex`), which is what a negative `zIndex` means in WMP. The
        // inscribed-circle clip that used to stand in for that occlusion is gone: it approximated
        // Cerulean's real 73px hole and was wrong for the 83 corpus rects that are wider than tall.
        NSGraphicsContext.current?.cgContext.clip(to: bounds)
        switch effect.style {
        case .bars: drawBars()
        case .spikes: drawSpikes()
        case .ambience: drawAmbience()
        case .cava: drawCava()
        case .visClassic: drawVisClassic()
        case .projectM, .geiss, .tripex: drawOffscreenEngine()
        }
    }

    /// The GL readback, drawn like any other picture. **No y-flip**: `glReadPixels` returns rows
    /// bottom-first, a `CGImage` calls row 0 its top, and this view is flipped — the two reversals
    /// cancel. vis_classic needs one precisely because its buffer is top-first instead.
    private func drawOffscreenEngine() {
        guard let engineImage, let context = NSGraphicsContext.current?.cgContext else { return }
        context.saveGState()
        context.interpolationQuality = .low
        context.draw(engineImage, in: bounds)
        context.restoreGState()
    }

    private func drawCava() {
        let bars = cavaPresenter.barArrays
        guard !bars.isEmpty else { return }
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        context.saveGState()
        // CavaDrawing is shared with y-up AppKit hosts. The WMP skin view is flipped, so
        // present its baseline through the same local transform as vis_classic.
        context.translateBy(x: 0, y: bounds.minY + bounds.maxY)
        context.scaleBy(x: 1, y: -1)
        CavaDrawing.draw(in: bounds, barArrays: bars,
                         lowColor: cavaPresenter.lowGradientColor,
                         highColor: cavaPresenter.highGradientColor,
                         mode: cavaPresenter.mode)
        context.restoreGState()
    }

    private func drawVisClassic() {
        let scale = window?.backingScaleFactor ?? 1
        let content = bounds
        let width = max(1, Int((content.width * scale).rounded()))
        let height = max(1, Int((content.height * scale).rounded()))
        guard let bridge = visClassicBridge(width: width, height: height) else { return }
        let waveform = visClassicWaveform.samples
        let stride = width * 4
        bridge.processAndDraw(leftData: waveform.left, rightData: waveform.right,
                              sampleRate: 44_100, width: width, height: height,
                              into: &visClassicBytes, stride: stride)
        guard visClassicBytes.count >= stride * height,
              let image = visClassicImage(width: width, height: height, stride: stride) else { return }
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        context.saveGState()
        // CVisClassicCore writes top-row-first pixels. A flipped AppKit view uses the opposite
        // image orientation, so draw through a local y-flip rather than presenting its bars
        // upside down in the skin.
        context.translateBy(x: 0, y: content.minY + content.maxY)
        context.scaleBy(x: 1, y: -1)
        context.interpolationQuality = .none
        context.draw(image, in: content)
        context.restoreGState()
    }

    private func visClassicBridge(width: Int, height: Int) -> VisClassicBridge? {
        if let visClassicBridge {
            visClassicBridge.setReferenceWidth(width)
            return visClassicBridge
        }
        guard let made = VisClassicBridge(width: width, height: height, scope: .wmpEffects) else {
            return nil
        }
        made.setReferenceWidth(width)
        made.reloadPersistedSettings()
        // This is an overlay, not a standalone analyzer canvas. Profiles may specify a black
        // background for their window, but that must not cover the WMP skin's authored lens.
        _ = made.setTransparentBackground(true)
        visClassicBridge = made
        return made
    }

    private func visClassicImage(width: Int, height: Int, stride: Int) -> CGImage? {
        let bytes = visClassicBytes.withUnsafeBufferPointer { Data($0) }
        guard let provider = CGDataProvider(data: bytes as CFData) else { return nil }
        let info = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue)
            .union(.byteOrder32Little)
        return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
                       bytesPerRow: stride, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: info,
                       provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
    }

    private func normalizedLevels(count: Int) -> [CGFloat] {
        guard count > 0, !levels.isEmpty else { return [] }
        return (0..<count).map { index in
            let source = min(levels.count - 1, index * levels.count / count)
            return CGFloat(max(0.035, min(1, levels[source])))
        }
    }

    /// **The three WMP-native renderers draw against the rect, not about its centre.**
    ///
    /// They used to be polar — rays and rings around `bounds.mid` at `min(w, h) * 0.46` — which put
    /// a circle in every slot whatever its shape. Of the 107 corpus `<EFFECTS>` rects with numeric
    /// dimensions only 19 are square and 83 are wider than tall, so the centred square covered a
    /// median 75% of the authored rect and as little as 17% (`Alpine7618_v09`, 150x26). A skin with
    /// no occluding artwork gets its full `width x height`: no shape fitting, no letterboxing.
    ///
    /// `isFlipped` is true here, so `bounds.maxY` is the baseline a bar stands on.
    private func drawBars() {
        guard bounds.width > 0, bounds.height > 0 else { return }
        let bands = normalizedLevels(count: min(48, max(6, Int(bounds.width / 6))))
        guard !bands.isEmpty else { return }
        let slot = bounds.width / CGFloat(bands.count)
        let barWidth = max(1, slot * 0.68)
        for (index, level) in bands.enumerated() {
            let height = max(1, bounds.height * level)
            let x = bounds.minX + CGFloat(index) * slot + (slot - barWidth) / 2
            NSColor(calibratedRed: 0.18 + level * 0.25, green: 0.72 + level * 0.22,
                    blue: 0.30 + level * 0.22, alpha: 0.95).setFill()
            NSRect(x: x, y: bounds.maxY - height, width: barWidth, height: height).fill()
            // The cap is what reads as a level on a 26px LCD strip, where the bar itself is a
            // couple of pixels tall.
            NSColor(calibratedRed: 0.62, green: 0.98, blue: 0.66, alpha: 0.9).setFill()
            NSRect(x: x, y: bounds.maxY - height, width: barWidth, height: 1).fill()
        }
    }

    private func drawSpikes() {
        guard bounds.width > 0, bounds.height > 0 else { return }
        let bands = normalizedLevels(count: min(64, max(8, Int(bounds.width / 4))))
        guard !bands.isEmpty else { return }
        let slot = bounds.width / CGFloat(bands.count)
        let lineWidth = max(1, slot * 0.5)
        let baseline = bounds.maxY
        for (index, level) in bands.enumerated() {
            let x = bounds.minX + (CGFloat(index) + 0.5) * slot
            let extent = max(1, bounds.height * level)
            let spike = NSBezierPath()
            spike.move(to: NSPoint(x: x, y: baseline))
            spike.line(to: NSPoint(x: x, y: baseline - extent))
            NSColor(calibratedRed: 0.04, green: 0.44 + level * 0.28,
                    blue: 0.76 + level * 0.22, alpha: 0.75).setStroke()
            spike.lineWidth = lineWidth
            spike.stroke()
            let core = NSBezierPath()
            core.move(to: NSPoint(x: x, y: baseline))
            core.line(to: NSPoint(x: x, y: baseline - extent * 0.94))
            NSColor(calibratedRed: 0.64, green: 0.96, blue: 1, alpha: 0.95).setStroke()
            core.lineWidth = 1
            core.stroke()
        }
        // The baseline rule replaces the old outer ring: the same "this is a display, not a hole in
        // the artwork" cue, drawn along the rect the skin authored.
        NSColor(calibratedRed: 0.25, green: 0.88, blue: 1, alpha: 0.5).setFill()
        NSRect(x: bounds.minX, y: baseline - 1, width: bounds.width, height: 1).fill()
    }

    private func drawAmbience() {
        guard bounds.width > 0, bounds.height > 0 else { return }
        let bands = normalizedLevels(count: max(4, min(24, Int(bounds.width / 8))))
        guard bands.count > 1 else { return }
        // Three translucent envelopes over the whole rect, the near one tallest. Layered alpha is
        // what made the old concentric rings read as "ambience"; the shape is now the skin's rect.
        for layer in (0..<3).reversed() {
            let scale = 1 - CGFloat(layer) * 0.24
            let path = NSBezierPath()
            path.move(to: NSPoint(x: bounds.minX, y: bounds.maxY))
            for (index, level) in bands.enumerated() {
                let x = bounds.minX + bounds.width * CGFloat(index) / CGFloat(bands.count - 1)
                path.line(to: NSPoint(x: x, y: bounds.maxY - bounds.height * level * scale))
            }
            path.line(to: NSPoint(x: bounds.maxX, y: bounds.maxY))
            path.close()
            let depth = CGFloat(layer) / 3
            NSColor(calibratedRed: 0.14 + depth * 0.30, green: 0.35 + depth * 0.35,
                    blue: 0.72 + depth * 0.22, alpha: 0.42 - depth * 0.10).setFill()
            path.fill()
        }
    }

    // MARK: - Keyboard

    /// The visualization keys NullPlayer's own window and the `.wal` surface answer, on the rect the
    /// skin authored: **left/right step the preset** (shift steps hard, without a blend), `r` picks
    /// a random one, `p` halves the frame rate and `c` walks Manual → Auto-Cycle → Auto-Random.
    ///
    /// Offered only after the skin has refused the key, so a focused slider still takes its own
    /// arrows and an authored accelerator always wins. Fullscreen is not among them: this surface
    /// is a box inside the skin's window and has no screen of its own to take.
    @discardableResult
    func handleKeyDown(_ event: NSEvent) -> Bool {
        guard !isTornDown else { return false }
        switch event.keyCode {
        case 124: WMPEffectSelection.shared.step(by: 1); return true
        case 123: WMPEffectSelection.shared.step(by: -1); return true
        default: return false
        }
    }

    /// Each engine's own idea of "the next one": ProjectM steps its preset list, Geiss and Tripex
    /// their effects — the same thing the arrows do in NullPlayer's own visualization window.
    private func stepPreset(by delta: Int, hardCut: Bool) {
        guard let engineView, delta != 0 else { return }
        switch engineView.currentEngineType {
        case .geiss:
            delta > 0 ? engineView.nextGeissEffect() : engineView.previousGeissEffect()
        case .tripex:
            delta > 0 ? engineView.nextTripexEffect() : engineView.previousTripexEffect()
        case .projectM:
            delta > 0 ? engineView.nextPreset(hardCut: hardCut)
                      : engineView.previousPreset(hardCut: hardCut)
        }
    }

    // MARK: - The visualization's own menu

    /// WMP effects have their own small catalogue; this surface is not a second instance of
    /// NullPlayer's Visualizations window.
    func buildMenu() -> NSMenu {
        let menu = NSMenu(title: "Visual Effects")
        let effectItem = NSMenuItem(title: "Effect", action: nil, keyEquivalent: "")
        let effectMenu = NSMenu(title: "Effect")
        for candidate in WMPEffectSelection.catalogue {
            let item = NSMenuItem(title: candidate.title, action: #selector(selectNativeEffect(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = candidate.id
            item.state = candidate.id == effect.id ? .on : .off
            effectMenu.addItem(item)
        }
        effectItem.submenu = effectMenu
        menu.addItem(effectItem)

        switch effect.style {
        case .cava:
            menu.addItem(.separator())
            // Same presenter and controls as the Cava window; only Close/transparency are omitted
            // because this is a skin-owned display slot.
            cavaPresenter.buildMenu(showTransparency: false, includeClose: false).items.forEach(menu.addItem)
        case .visClassic:
            menu.addItem(.separator())
            visClassicOptionsMenu().items.forEach(menu.addItem)
        case .projectM, .geiss, .tripex:
            // The engine's own menu, through the shared `VisualizationMenuTarget` protocol this
            // view already conforms to — the same presets, cycling and sensitivity items the
            // standalone window offers, minus fullscreen and close, which a slot inside a skin's
            // window has nowhere to go with.
            menu.addItem(.separator())
            let options = VisualizationContextMenu.Options(
                cycleMode: presetCycleMode, cycleInterval: presetCycleInterval,
                tripexCycleMode: tripexCycleMode, tripexCycleInterval: tripexCycleInterval,
                showsFullscreen: false, showsClose: false)
            VisualizationContextMenu.build(target: self, options: options).items.forEach(menu.addItem)
        case .bars, .spikes, .ambience:
            break
        }
        return menu
    }

    private func visClassicOptionsMenu() -> NSMenu {
        let menu = NSMenu(title: "vis_classic")
        let current = visClassicBridge?.currentProfileName ?? VisClassicBridge.lastProfileName(for: .wmpEffects)
        let profileItem = NSMenuItem(title: "Profile", action: nil, keyEquivalent: "")
        let profileMenu = NSMenu(title: "Profile")
        for profile in VisClassicBridge.availableProfilesCatalog() {
            let item = NSMenuItem(title: profile.name, action: #selector(selectVisClassicProfile(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = profile.name
            item.state = profile.name == current ? .on : .off
            profileMenu.addItem(item)
        }
        profileItem.submenu = profileMenu
        menu.addItem(profileItem)
        let fit = NSMenuItem(title: "Fit To Width", action: #selector(toggleVisClassicFit(_:)), keyEquivalent: "")
        fit.target = self
        fit.state = VisClassicBridge.fitToWidthDefault(for: .wmpEffects) ? .on : .off
        menu.addItem(fit)
        let transparent = NSMenuItem(title: "Transparent Background", action: #selector(toggleVisClassicTransparency(_:)), keyEquivalent: "")
        transparent.target = self
        transparent.state = VisClassicBridge.transparentBgDefault(for: .wmpEffects) ? .on : .off
        menu.addItem(transparent)
        return menu
    }

    @objc private func selectVisClassicProfile(_ sender: NSMenuItem) {
        guard let name = sender.representedObject as? String else { return }
        UserDefaults.standard.set(name, forKey: VisClassicBridge.PreferenceScope.wmpEffects.lastProfileNameKey)
        _ = visClassicBridge?.loadProfile(named: name)
        needsDisplay = true
    }

    @objc private func toggleVisClassicFit(_ sender: NSMenuItem) {
        let enabled = !VisClassicBridge.fitToWidthDefault(for: .wmpEffects)
        UserDefaults.standard.set(enabled, forKey: VisClassicBridge.PreferenceScope.wmpEffects.fitToWidthKey)
        _ = visClassicBridge?.setFitToWidth(enabled)
        needsDisplay = true
    }

    @objc private func toggleVisClassicTransparency(_ sender: NSMenuItem) {
        let enabled = !VisClassicBridge.transparentBgDefault(for: .wmpEffects)
        UserDefaults.standard.set(enabled, forKey: VisClassicBridge.PreferenceScope.wmpEffects.transparentBgKey)
        _ = visClassicBridge?.setTransparentBackground(enabled)
        needsDisplay = true
    }

    @objc private func selectNativeEffect(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String else { return }
        WMPEffectSelection.shared.select(id)
    }

    /// `VisualizationMenuTarget` / `GeissMenuTarget`: the engine the shared menu acts on. It is nil
    /// while the rect is drawing bars or standing aside, and the builder answers its defaults.
    var visualizationGLView: VisualizationGLView? { engineView }

    // MARK: - VisualizationMenuTarget

    @objc func nextPresetAction(_ sender: NSMenuItem?) { engineView?.nextPreset() }
    @objc func previousPresetAction(_ sender: NSMenuItem?) { engineView?.previousPreset() }
    @objc func randomPresetAction(_ sender: NSMenuItem?) { engineView?.randomPreset() }
    @objc func setCurrentPresetAsDefault(_ sender: NSMenuItem?) { engineView?.setCurrentPresetAsDefault() }

    @objc func setCurrentPresetRatingFromMenu(_ sender: NSMenuItem) {
        guard let preset = currentPresetIdentity() else { return }
        ProjectMPresetRatingsStore.shared.setRating(min(5, max(0, sender.tag)),
                                                    forPresetPath: preset.path,
                                                    presetName: preset.name)
    }

    @objc func toggleCurrentPresetFavorite(_ sender: NSMenuItem?) {
        guard let preset = currentPresetIdentity() else { return }
        let store = ProjectMPresetRatingsStore.shared
        store.setFavorite(!store.isFavorite(forPresetPath: preset.path),
                          forPresetPath: preset.path, presetName: preset.name)
    }

    @objc func selectFavoritePresetFromMenu(_ sender: NSMenuItem) {
        guard let path = sender.representedObject as? String,
              let index = presetIndex(forPath: path) else { return }
        engineView?.selectPreset(at: index, hardCut: false)
    }

    @objc func selectPresetFromMenu(_ sender: NSMenuItem) {
        engineView?.selectPreset(at: sender.tag, hardCut: false)
    }

    @objc func setCycleModeOff(_ sender: NSMenuItem?) { setPresetCycleMode(.off) }
    @objc func setCycleModeCycle(_ sender: NSMenuItem?) { setPresetCycleMode(.cycle) }
    @objc func setCycleModeRandom(_ sender: NSMenuItem?) { setPresetCycleMode(.random) }

    @objc func setCycleInterval(_ sender: NSMenuItem) {
        presetCycleInterval = TimeInterval(sender.tag)
        ProjectMPresetCycleSettings.save(mode: presetCycleMode, interval: presetCycleInterval)
        applyPresetCycleMode()
    }

    /// **Through the skin's own selector, not the app's preference.** The engine a `.wmz` draws is
    /// `mediacenter.effectType`, which 96 archives bind their rect's `currentEffectType` to, so a
    /// choice made in this menu is one the skin can read back and put on screen beside the picture.
    /// It is deliberately not `WindowManager.switchVisualizationEngine`: that is the setting the
    /// visualization window and the menu bar share, and a skin is not entitled to rewrite it.
    @objc func switchVisualizationEngine(_ sender: NSMenuItem) {
        guard let type = sender.representedObject as? VisualizationType,
              let effect = WMPEffectSelection.catalogue.first(where: { $0.engine == type }) else { return }
        WMPEffectSelection.shared.select(effect.id)
        applyPresetCycleMode()
    }

    @objc func setAudioSensitivity(_ sender: NSMenuItem) {
        engineView?.setPCMGain(Float(sender.tag) / 10.0)
    }

    @objc func setBeatSensitivityAction(_ sender: NSMenuItem) {
        engineView?.setNormalBeatSensitivity(Float(sender.tag) / 10.0)
    }

    @objc func togglePerformanceMode(_ sender: NSMenuItem?) { engineView?.toggleLowPowerMode() }

    /// Neither item is offered by `buildMenu()`; the protocol still requires them.
    @objc func toggleFullscreenAction(_ sender: NSMenuItem?) {}
    @objc func closeWindow(_ sender: NSMenuItem?) {}

    @objc func nextGeissEffectAction(_ sender: NSMenuItem?) { engineView?.nextGeissEffect() }
    @objc func previousGeissEffectAction(_ sender: NSMenuItem?) { engineView?.previousGeissEffect() }
    @objc func randomGeissEffectAction(_ sender: NSMenuItem?) { engineView?.randomGeissEffect() }
    @objc func selectGeissEffectFromMenu(_ sender: NSMenuItem) {
        engineView?.selectGeissEffect(at: sender.tag)
    }

    // MARK: - GeissMenuTarget

    @objc func toggleBeatDetection(_ sender: NSMenuItem) { editGeissConfig { $0.beatDetection.toggle() } }
    @objc func toggleSyncColorToSound(_ sender: NSMenuItem) { editGeissConfig { $0.syncColorToSound.toggle() } }
    @objc func toggleSlideShift(_ sender: NSMenuItem) { editGeissConfig { $0.slideShift.toggle() } }
    @objc func toggleModeLock(_ sender: NSMenuItem) { editGeissConfig { $0.modeLocked.toggle() } }
    @objc func togglePaletteLock(_ sender: NSMenuItem) { editGeissConfig { $0.paletteLocked.toggle() } }
    @objc func setSensitivity(_ sender: NSMenuItem) {
        editGeissConfig { $0.sensitivity = Float(sender.tag) / 100.0 }
    }
    @objc func setGamma(_ sender: NSMenuItem) { editGeissConfig { $0.gamma = sender.tag } }
    @objc func setAutoSwitch(_ sender: NSMenuItem) { editGeissConfig { $0.autoSwitchSeconds = sender.tag } }
    @objc func setVisMode(_ sender: NSMenuItem) { editGeissConfig { $0.visMode = sender.tag } }
    @objc func randomizePalette(_ sender: NSMenuItem) { engineView?.randomizeGeissPalette() }

    private func editGeissConfig(_ edit: (inout GeissEngine.Config) -> Void) {
        guard var config = engineView?.getGeissConfig() else { return }
        edit(&config)
        engineView?.setGeissConfig(config)
    }

    // MARK: - TripexMenuTarget

    @objc func nextTripexEffectAction(_ sender: NSMenuItem) { engineView?.nextTripexEffect() }
    @objc func previousTripexEffectAction(_ sender: NSMenuItem) { engineView?.previousTripexEffect() }
    @objc func randomTripexEffectAction(_ sender: NSMenuItem) { engineView?.randomTripexEffect() }
    @objc func reconfigureTripexAction(_ sender: NSMenuItem) { engineView?.reconfigureTripex() }
    @objc func toggleTripexHoldAction(_ sender: NSMenuItem) { engineView?.toggleTripexHold() }
    @objc func toggleTripexAudioInfoAction(_ sender: NSMenuItem) { engineView?.toggleTripexAudioInfo() }
    @objc func toggleTripexHelpAction(_ sender: NSMenuItem) { engineView?.toggleTripexHelp() }
    @objc func selectTripexEffectFromMenu(_ sender: NSMenuItem) {
        engineView?.selectTripexEffect(at: sender.tag)
    }
    @objc func setTripexIntensity(_ sender: NSMenuItem) {
        let value = Float(sender.tag) / 100.0
        engineView?.tripexIntensityScale = value
        UserDefaults.standard.set(value, forKey: TripexEngine.DefaultsKey.intensityScale)
    }
    /// The toggle-on-state pattern the Tripex menu uses: the item that is already on turns itself off.
    @objc func setTripexCycleModeCycle(_ sender: Any?) {
        setTripexCycleMode((sender as? NSMenuItem)?.state == .on ? .off : .cycle)
    }
    @objc func setTripexCycleModeRandom(_ sender: Any?) {
        setTripexCycleMode((sender as? NSMenuItem)?.state == .on ? .off : .random)
    }
    @objc func setTripexCycleIntervalFromMenu(_ sender: NSMenuItem) {
        tripexCycleInterval = TimeInterval(sender.tag)
        UserDefaults.standard.set(tripexCycleInterval, forKey: TripexEngine.DefaultsKey.cycleInterval)
        applyTripexCycleMode()
    }

    // MARK: - Preset cycling

    private func currentPresetIdentity() -> (name: String, path: String)? {
        guard let engineView, engineView.isProjectMAvailable else { return nil }
        let path = engineView.presetPath(at: engineView.currentPresetIndex)
        guard !path.isEmpty else { return nil }
        return (engineView.currentPresetName, path)
    }

    private func presetIndex(forPath path: String) -> Int? {
        guard let engineView else { return nil }
        let wanted = (path as NSString).standardizingPath
        guard !wanted.isEmpty else { return nil }
        return (0..<engineView.presetCount).first {
            (engineView.presetPath(at: $0) as NSString).standardizingPath == wanted
        }
    }

    private func setPresetCycleMode(_ mode: VisualizationCycleMode) {
        presetCycleMode = mode
        ProjectMPresetCycleSettings.save(mode: mode, interval: presetCycleInterval)
        applyPresetCycleMode()
    }

    private func setTripexCycleMode(_ mode: VisualizationCycleMode) {
        tripexCycleMode = mode
        UserDefaults.standard.set(mode.rawValue, forKey: TripexEngine.DefaultsKey.cycleMode)
        applyTripexCycleMode()
    }

    /// One timer for whichever engine is running: ProjectM steps presets, Tripex steps effects, and
    /// Geiss cycles inside its own engine (`autoSwitchSeconds`), so it needs none here.
    private func applyPresetCycleMode() {
        cycleTimer?.invalidate()
        cycleTimer = nil
        guard let engineView else { return }
        guard engineView.currentEngineType == .projectM, presetCycleMode != .off else {
            if engineView.currentEngineType == .tripex { applyTripexCycleMode() }
            return
        }
        cycleTimer = Timer.scheduledTimer(withTimeInterval: presetCycleInterval, repeats: true) {
            [weak self] _ in
            guard let self, let engine = self.engineView else { return }
            self.presetCycleMode == .random ? engine.randomPreset(hardCut: false)
                                            : engine.nextPreset(hardCut: false)
        }
    }

    private func applyTripexCycleMode() {
        cycleTimer?.invalidate()
        cycleTimer = nil
        guard let engineView, engineView.currentEngineType == .tripex, tripexCycleMode != .off else { return }
        cycleTimer = Timer.scheduledTimer(withTimeInterval: tripexCycleInterval, repeats: true) {
            [weak self] _ in
            guard let self, let engine = self.engineView else { return }
            self.tripexCycleMode == .random ? engine.randomTripexEffect() : engine.nextTripexEffect()
        }
    }
}
