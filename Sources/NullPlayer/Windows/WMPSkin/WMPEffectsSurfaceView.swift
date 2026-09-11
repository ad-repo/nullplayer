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
        // A WMP effect is part of the skin's composition. Do not mount a second, full-window
        // renderer into this small rect; it is the source of the black ProjectM panels reported
        // in Asimov Radio and Cerulean.
        releaseEngine()
        cavaPresenter.stop()
        visClassicWaveform.stop()
        if isActive {
            switch effect.style {
            case .cava:
                cavaPresenter.start()
            case .visClassic:
                visClassicWaveform.start()
            case .bars, .spikes, .ambience:
                break
            }
        }
        if !isActive { levels = [] }
        needsDisplay = true
    }

    private func makeEngineView() -> VisualizationGLView? {
        guard let view = VisualizationGLView(frame: bounds, pixelFormat: nil) else { return nil }
        view.autoresizingMask = [.width, .height]
        addSubview(view)
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
        guard let view = engineView else { return }
        view.stopRendering()
        view.removeFromSuperview()
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
        // A stopped player leaves the skin's own artwork visible.
        guard isActive, !levels.isEmpty else { return }
        // `bounds`, never `dirtyRect`: AppKit is free to hand a view a dirty rect larger than
        // itself — here the whole 596x468 window arrived as {{-269, -26}, {596, 468}} in this
        // view's coordinates — and a layer-backed view does not clip it (`masksToBounds` is
        // false). Filling it painted this surface's wash over the entire skin.
        switch effect.style {
        case .bars: drawBars()
        case .spikes: drawSpikes()
        case .ambience: drawAmbience()
        case .cava: drawCava()
        case .visClassic: drawVisClassic()
        }
    }

    private func drawCava() {
        let bars = cavaPresenter.barArrays
        guard !bars.isEmpty else { return }
        withCircularEffectClip {
            CavaDrawing.draw(in: compactEffectBounds, barArrays: bars,
                             lowColor: cavaPresenter.lowGradientColor,
                             highColor: cavaPresenter.highGradientColor,
                             mode: cavaPresenter.mode)
        }
    }

    private func drawVisClassic() {
        let scale = window?.backingScaleFactor ?? 1
        let content = compactEffectBounds
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
        withCircularEffectClip {
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
    }

    /// Suite renderers are rectangular canvases, but an `<EFFECTS>` slot is often a circular lens
    /// set into larger artwork (Cerulean's 103×75 slot frames an 81px eye). Keep the renderer in
    /// that inscribed lens: pixels outside remain the skin's own bezel, overlay, or LCD detail.
    private var compactEffectBounds: NSRect {
        let side = min(bounds.width, bounds.height)
        return NSRect(x: bounds.midX - side / 2, y: bounds.midY - side / 2,
                      width: side, height: side)
    }

    private func withCircularEffectClip(_ body: () -> Void) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        context.saveGState()
        context.addEllipse(in: compactEffectBounds)
        context.clip()
        body()
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

    private func drawBars() {
        let bands = normalizedLevels(count: min(32, max(16, Int(min(bounds.width, bounds.height) / 4))))
        guard !bands.isEmpty else { return }
        let context = NSGraphicsContext.current?.cgContext
        let center = NSPoint(x: bounds.midX, y: bounds.midY)
        let maximum = min(bounds.width, bounds.height) * 0.46
        let inner = maximum * 0.30
        let cellWidth = max(1, (maximum * .pi * 2 / CGFloat(bands.count)) * 0.60)
        for (index, level) in bands.enumerated() {
            let angle = (CGFloat(index) / CGFloat(bands.count)) * (.pi * 2) - (.pi / 2)
            let height = max(maximum * 0.09, (maximum - inner) * level)
            context?.saveGState()
            context?.translateBy(x: center.x, y: center.y)
            context?.rotate(by: angle)
            NSColor(calibratedRed: 0.18 + level * 0.25, green: 0.72 + level * 0.22,
                    blue: 0.30 + level * 0.22, alpha: 0.95).setFill()
            NSRect(x: inner, y: -cellWidth / 2, width: height, height: cellWidth).fill()
            context?.restoreGState()
        }
        let core = NSBezierPath(ovalIn: NSRect(x: center.x - inner, y: center.y - inner,
                                               width: inner * 2, height: inner * 2))
        core.lineWidth = max(1, maximum / 55)
        NSColor(calibratedRed: 0.35, green: 0.92, blue: 0.45, alpha: 0.65).setStroke()
        core.stroke()
    }

    private func drawSpikes() {
        let bands = normalizedLevels(count: min(48, max(20, Int(min(bounds.width, bounds.height) / 3))))
        guard !bands.isEmpty else { return }
        let center = NSPoint(x: bounds.midX, y: bounds.midY)
        let maximum = min(bounds.width, bounds.height) * 0.46
        let inner = maximum * 0.28

        // The legacy effect sits *in* the skin's display rather than replacing it. Keeping the
        // surrounding pixels transparent is what lets round frames such as Asimov Radio's remain
        // round instead of becoming a black square.
        let outline = NSBezierPath(ovalIn: NSRect(x: center.x - maximum, y: center.y - maximum,
                                                  width: maximum * 2, height: maximum * 2))
        outline.lineWidth = max(1, maximum / 42)
        NSColor(calibratedRed: 0.25, green: 0.88, blue: 1, alpha: 0.82).setStroke()
        outline.stroke()
        let core = NSBezierPath(ovalIn: NSRect(x: center.x - inner, y: center.y - inner,
                                               width: inner * 2, height: inner * 2))
        core.lineWidth = max(1, maximum / 70)
        NSColor(calibratedRed: 0.60, green: 0.96, blue: 1, alpha: 0.68).setStroke()
        core.stroke()
        for (index, level) in bands.enumerated() {
            let angle = (CGFloat(index) / CGFloat(bands.count)) * (.pi * 2) - (.pi / 2)
            let extent = inner + (maximum - inner) * level
            let start = NSPoint(x: center.x + cos(angle) * inner, y: center.y + sin(angle) * inner)
            let end = NSPoint(x: center.x + cos(angle) * extent, y: center.y + sin(angle) * extent)
            let outer = NSBezierPath()
            outer.move(to: start)
            outer.line(to: end)
            NSColor(calibratedRed: 0.04, green: 0.44 + level * 0.28,
                    blue: 0.76 + level * 0.22, alpha: 0.75).setStroke()
            outer.lineWidth = max(1, maximum / 34)
            outer.stroke()
            let core = NSBezierPath()
            core.move(to: start)
            core.line(to: NSPoint(x: center.x + cos(angle) * (extent * 0.94),
                                  y: center.y + sin(angle) * (extent * 0.94)))
            NSColor(calibratedRed: 0.64, green: 0.96, blue: 1, alpha: 0.95).setStroke()
            core.lineWidth = 1
            core.stroke()
        }
    }

    private func drawAmbience() {
        let bands = normalizedLevels(count: 12)
        guard !bands.isEmpty else { return }
        let center = NSPoint(x: bounds.midX, y: bounds.midY)
        let maximum = min(bounds.width, bounds.height) * 0.47
        for (index, level) in bands.enumerated().reversed() {
            let fraction = CGFloat(index + 1) / CGFloat(bands.count)
            let radius = maximum * fraction * (0.45 + level * 0.55)
            let rect = NSRect(x: center.x - radius, y: center.y - radius,
                              width: radius * 2, height: radius * 2)
            let ring = NSBezierPath(ovalIn: rect)
            NSColor(calibratedRed: 0.14 + fraction * 0.30, green: 0.35 + level * 0.45,
                    blue: 0.72 + fraction * 0.22, alpha: 0.18 + level * 0.38).setStroke()
            ring.lineWidth = max(1, bounds.width / 100)
            ring.stroke()
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
