import AppKit

/// The `<EFFECTS>` rect: NullPlayer's own visuals, in the frame the skin authored for them.
///
/// **The geometry was always there and nothing is invented here.** Every `<EFFECTS>` element
/// measured in the corpus carries `width` and `height`, most of them expressions off the frame the
/// skin drew around it (`WoW`: `<effects id="visEffects" width="jscript:visFrame.width" …>`), and
/// 183 of them across 166 of 177 archives were hosted on nothing at all until `<EFFECTS>` became an
/// element kind (W101). What goes *in* the rect is `WMPEffectSelection`: the bars this engine drew
/// by hand for the five `<WMPEFFECTS>` skins, or one of the three engines NullPlayer's own
/// visualization window runs.
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

    override var isFlipped: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
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
        engineView?.updateSpectrum(levels)
        if effect.engine == nil, isActive { needsDisplay = true }
    }

    override func layout() {
        super.layout()
        engineView?.frame = bounds
    }

    private func applySelection() {
        guard !isTornDown else { return }
        effect = WMPEffectSelection.shared.current
        guard isActive, let engine = effect.engine else {
            releaseEngine()
            levels = []
            needsDisplay = true
            return
        }
        let view = engineView ?? makeEngineView()
        guard let view else {
            // No usable pixel format: the bars are what this rect can still draw, which is exactly
            // what the `.wal` surface's "nil when unavailable" fallback answers with.
            needsDisplay = true
            return
        }
        if view.currentEngineType != engine { view.switchEngine(to: engine) }
        view.setAudioActive(true)
        applyPreset(to: view, engine: engine)
        // Each engine cycles on its own terms, so the timer is re-armed for the one now running.
        applyPresetCycleMode()
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
        // Nothing is playing, or an engine is drawing its own frames into its own subview: either
        // way this view paints nothing and the skin's artwork stands.
        guard isActive, effect.engine == nil, !levels.isEmpty else { return }
        // `bounds`, never `dirtyRect`: AppKit is free to hand a view a dirty rect larger than
        // itself — here the whole 596x468 window arrived as {{-269, -26}, {596, 468}} in this
        // view's coordinates — and a layer-backed view does not clip it (`masksToBounds` is
        // false). Filling it painted this surface's wash over the entire skin.
        NSColor(calibratedWhite: 0.04, alpha: 0.9).setFill(); bounds.fill()
        let count = min(32, levels.count), width = bounds.width / CGFloat(count)
        NSColor.systemGreen.setFill()
        for index in 0..<count {
            let level = CGFloat(max(0, min(1, levels[index])))
            NSRect(x: CGFloat(index) * width, y: bounds.height * (1 - level),
                   width: max(1, width - 1), height: bounds.height * level).fill()
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
        guard !isTornDown, let engineView else { return false }
        let hard = event.modifierFlags.contains(.shift)
        switch event.keyCode {
        case 124: stepPreset(by: 1, hardCut: hard); return true
        case 123: stepPreset(by: -1, hardCut: hard); return true
        case 15: engineView.randomPreset(); return true
        case 35: engineView.toggleLowPowerMode(); return true
        case 8:
            guard engineView.currentEngineType == .projectM else { return false }
            switch presetCycleMode {
            case .off: setPresetCycleMode(.cycle)
            case .cycle: setPresetCycleMode(.random)
            case .random: setPresetCycleMode(.off)
            }
            return true
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

    /// **The same menu NullPlayer's own visualization window has**, on the rect the skin authored
    /// for it. `VisualizationContextMenu` is the one builder all three callers use — the
    /// visualization window, the `.wal` AVS surface and this — so a preset list, ratings,
    /// favourites, auto-cycle and the Geiss and Tripex panels are not restated here.
    ///
    /// Fullscreen and Close are the two items this surface does not offer: its "window" is a box
    /// inside the skin's own, `effectCanGoFullScreen="false"` is what 12 corpus skins author on it,
    /// and there is no window of its own to close — the skin decides whether its pane is visible.
    func buildMenu() -> NSMenu {
        VisualizationContextMenu.build(target: self, options: .init(
            cycleMode: presetCycleMode,
            cycleInterval: presetCycleInterval,
            tripexCycleMode: tripexCycleMode,
            tripexCycleInterval: tripexCycleInterval,
            showsFullscreen: false,
            showsClose: false))
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
