import AppKit

/// The host's visualization engine, drawn into a `.wal` skin's own AVS/visualization window (B20a).
///
/// Eight of the installed skins declare a container — `avs`, `avs_window`, `AVS`, `AVS_window` —
/// whose body is a `<component param="{0000000A-000C-0010-FF7B-01014263450C}">`: Winamp's
/// visualization *plugin* holder, the box AVS and MilkDrop drew into. We filled it with the same
/// engine-drawn spectrum bars the `<vis>` box in the player draws, so a skin's dedicated
/// visualization window was a second, larger analyzer. This puts ProjectM / Geiss / Tripex there
/// instead — the same stack, the same preferences and the same preset store as NullPlayer's own
/// visualization window.
///
/// Unlike the video surface (B20) this one really does host its output. `VisualizationGLView` is a
/// self-contained `NSOpenGLView`: it installs no view of its own above itself and sizes no ancestor,
/// which is exactly what the video engine did and why the picture had to be parked as a child
/// window. So this is the `.library` seam's shape — a subview at the holder's frame — and the GL
/// view's `hitTest` returns nil, so every click over the box still reaches the skin.
///
/// It is a **second** engine instance, not a lend of the visualization window's: two
/// `VisualizationGLView`s can render at once (each owns its GL context, display link and engine),
/// and lending would have made opening a skin's AVS window steal the picture out of a window the
/// user had already placed. The cost is bounded by the surface's own lifetime — no holder, no view,
/// no engine.
final class WinampModernVisualizationSurfaceView: NSView, WinampModernVisualizationSurface,
                                                  VisualizationMenuTarget {
    private let engineView: VisualizationGLView
    /// `VisualizationMenuTarget` / `GeissMenuTarget`: the engine the shared menu acts on.
    var visualizationGLView: VisualizationGLView? { engineView }
    private var pcmObserver: NSObjectProtocol?
    private var spectrumObserver: NSObjectProtocol?
    private var playbackObserver: NSObjectProtocol?
    private var isTornDown = false
    /// Preset/effect auto-cycling, persisted through the same keys NullPlayer's own visualization
    /// window uses, so a cycle set in one place is the cycle in the other.
    private var presetCycleMode = ProjectMPresetCycleSettings.loadMode()
    private var presetCycleInterval = ProjectMPresetCycleSettings.loadInterval()
    private var tripexCycleMode: VisualizationCycleMode = .cycle
    private var tripexCycleInterval: TimeInterval = 30
    private var cycleTimer: Timer?
    /// The screen-filling window the engine moves into for `VIS_FS`, or nil when it is in the box.
    private var fullscreenWindow: VisualizationFullscreenWindow?

    /// The audio engine's spectrum tap is reference-counted by consumer name, and every consumer has
    /// to be a distinct one or the first `remove` silences the others.
    private static let spectrumConsumer = "winampModernVisSurface"

    var view: NSView { self }

    override var isOpaque: Bool { true }

    /// Failable, and not an override of `init(frame:)`: `NSOpenGLView.init(frame:pixelFormat:)`
    /// gives up when the machine has no usable pixel format, and there is nothing this surface can
    /// be without it. `makeVisualizationSurface()` then answers nil and the skin's box keeps the
    /// analyzer, which is exactly what the seam's "nil when unavailable" default is for.
    init?(surfaceFrame frameRect: NSRect) {
        guard let gl = VisualizationGLView(frame: NSRect(origin: .zero, size: frameRect.size),
                                           pixelFormat: nil) else { return nil }
        engineView = gl
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
        // No autoresizing mask, for the same reason the video box has none: `layoutHostedSubviews`
        // gives this view its frame outright from the holder's own resolved geometry.
        autoresizingMask = []
        engineView.autoresizingMask = [.width, .height]
        addSubview(engineView)
        // The engine the user picked in the Visualizations menu, so opening a skin's AVS window
        // shows what the app's own visualization window would have shown.
        let engine = WindowManager.shared.visualizationEngineType
        if engine != engineView.currentEngineType { engineView.switchEngine(to: engine) }
        subscribeToAudio()
        loadTripexCycleState()
        applyPresetCycleMode()
    }

    private func loadTripexCycleState() {
        let raw = UserDefaults.standard.string(forKey: TripexEngine.DefaultsKey.cycleMode) ?? "cycle"
        tripexCycleMode = VisualizationCycleMode(rawValue: raw) ?? .cycle
        let stored = UserDefaults.standard.double(forKey: TripexEngine.DefaultsKey.cycleInterval)
        tripexCycleInterval = stored > 0 ? stored : 30
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    deinit {
        removeObservers()
    }

    // MARK: - Audio

    /// The same three taps `ProjectMView` takes, and deliberately the same shape: PCM and spectrum
    /// arrive on the posting thread (the GL view's own lock makes that safe) and the playback state
    /// on the main one, because it only chooses between the normal and the calmer idle sensitivity.
    private func subscribeToAudio() {
        pcmObserver = NotificationCenter.default.addObserver(
            forName: .audioPCMDataUpdated, object: nil, queue: nil
        ) { [weak self] notification in
            guard let pcm = notification.userInfo?["pcm"] as? [Float] else { return }
            self?.engineView.updatePCM(pcm)
        }
        spectrumObserver = NotificationCenter.default.addObserver(
            forName: .audioSpectrumDataUpdated, object: nil, queue: nil
        ) { [weak self] notification in
            guard let spectrum = notification.userInfo?["spectrum"] as? [Float] else { return }
            self?.engineView.updateSpectrum(spectrum)
        }
        playbackObserver = NotificationCenter.default.addObserver(
            forName: .audioPlaybackStateChanged, object: nil, queue: .main
        ) { [weak self] _ in
            self?.updateAudioActiveState()
        }
        WindowManager.shared.audioEngine.addSpectrumConsumer(Self.spectrumConsumer)
        updateAudioActiveState()
    }

    private func updateAudioActiveState() {
        engineView.setAudioActive(WindowManager.shared.audioEngine.state == .playing)
    }

    private func removeObservers() {
        for observer in [pcmObserver, spectrumObserver, playbackObserver].compactMap({ $0 }) {
            NotificationCenter.default.removeObserver(observer)
        }
        pcmObserver = nil
        spectrumObserver = nil
        playbackObserver = nil
    }

    // MARK: - WinampModernVisualizationSurface

    var engineType: VisualizationType { engineView.currentEngineType }

    func switchEngine(to type: VisualizationType) {
        guard !isTornDown, type != engineView.currentEngineType else { return }
        engineView.switchEngine(to: type)
        // Each engine cycles on its own terms, so the timer is re-armed for the one now running.
        applyPresetCycleMode()
    }

    /// `VIS_NEXT` / `VIS_PREV`. Each engine's own idea of "the next one": ProjectM steps its preset
    /// list, Geiss and Tripex their effects — which is what the same buttons do in NullPlayer's own
    /// visualization window.
    func stepPreset(by delta: Int) { stepPreset(by: delta, hardCut: false) }

    /// `hardCut` is Winamp's shift-step: switch instantly rather than blending. Only ProjectM blends,
    /// so it is the only engine the flag reaches.
    private func stepPreset(by delta: Int, hardCut: Bool) {
        guard !isTornDown, delta != 0 else { return }
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

    /// The **same** menu NullPlayer's own visualization window has
    /// (`VisualizationContextMenu`), minus the two items that need a window of one's own.
    ///
    /// This was a short hand-written menu at first — engine, next/previous/random, and the host's
    /// Visualizations submenu — and the first thing reported against it from a live Bento run was
    /// that it was truncated beside the real one. It was: no preset list, no ratings or favourites,
    /// no auto-cycle, no Geiss or Tripex configuration. All of it is here now, because all three
    /// callers build one menu.
    func buildMenu() -> NSMenu {
        VisualizationContextMenu.build(target: self, options: .init(
            cycleMode: presetCycleMode,
            cycleInterval: presetCycleInterval,
            tripexCycleMode: tripexCycleMode,
            tripexCycleInterval: tripexCycleInterval,
            // Both apply here: Fullscreen moves the engine to a screen-filling window of its own,
            // and Close puts the skin's AVS window away through the surface catalog.
            showsFullscreen: true,
            showsClose: true))
    }

    /// Nothing here for a colour theme to recolour: what fills the box is a rendered frame, and the
    /// black behind it is only ever seen for the moment before the first one.
    func applyPalette(_ palette: WasabiPalette) {}

    /// The holder's frame already arrives scaled, and the GL view fills this view, so UI Size needs
    /// no arithmetic here — only the drawable's own resolution follows, which AppKit does.
    func applySkinScale(_ scale: CGFloat) {}

    // MARK: - VisualizationMenuTarget
    //
    // Every action is the same one-liner against the engine the visualization window's view makes —
    // the engine API is where the behaviour lives, and both views were already thin wrappers over it.
    // The preset-cycle state is this surface's own, persisted through the same
    // `ProjectMPresetCycleSettings` keys, so a cycle set in one place is the cycle in the other.

    @objc func nextPresetAction(_ sender: NSMenuItem?) { engineView.nextPreset() }
    @objc func previousPresetAction(_ sender: NSMenuItem?) { engineView.previousPreset() }
    @objc func randomPresetAction(_ sender: NSMenuItem?) { engineView.randomPreset() }
    @objc func setCurrentPresetAsDefault(_ sender: NSMenuItem?) { engineView.setCurrentPresetAsDefault() }

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
        engineView.selectPreset(at: index, hardCut: false)
    }

    @objc func selectPresetFromMenu(_ sender: NSMenuItem) {
        engineView.selectPreset(at: sender.tag, hardCut: false)
    }

    @objc func setCycleModeOff(_ sender: NSMenuItem?) { setPresetCycleMode(.off) }
    @objc func setCycleModeCycle(_ sender: NSMenuItem?) { setPresetCycleMode(.cycle) }
    @objc func setCycleModeRandom(_ sender: NSMenuItem?) { setPresetCycleMode(.random) }

    @objc func setCycleInterval(_ sender: NSMenuItem) {
        presetCycleInterval = TimeInterval(sender.tag)
        ProjectMPresetCycleSettings.save(mode: presetCycleMode, interval: presetCycleInterval)
        applyPresetCycleMode()
    }

    @objc func switchVisualizationEngine(_ sender: NSMenuItem) {
        guard let type = sender.representedObject as? VisualizationType else { return }
        // Through the window manager, not straight into the engine: the choice is a preference the
        // menu bar and NullPlayer's own visualization window share.
        WindowManager.shared.switchVisualizationEngine(to: type)
        applyPresetCycleMode()
    }

    @objc func setAudioSensitivity(_ sender: NSMenuItem) {
        engineView.setPCMGain(Float(sender.tag) / 10.0)
    }

    @objc func setBeatSensitivityAction(_ sender: NSMenuItem) {
        engineView.setNormalBeatSensitivity(Float(sender.tag) / 10.0)
    }

    @objc func togglePerformanceMode(_ sender: NSMenuItem?) { engineView.toggleLowPowerMode() }

    @objc func toggleFullscreenAction(_ sender: NSMenuItem?) { toggleFullscreen() }

    /// Closing means putting the skin's own AVS window away, which routes through the surface catalog
    /// so every menu stays in agreement about what is open.
    @objc func closeWindow(_ sender: NSMenuItem?) { WindowManager.shared.toggleProjectM() }

    @objc func nextGeissEffectAction(_ sender: NSMenuItem?) { engineView.nextGeissEffect() }
    @objc func previousGeissEffectAction(_ sender: NSMenuItem?) { engineView.previousGeissEffect() }
    @objc func randomGeissEffectAction(_ sender: NSMenuItem?) { engineView.randomGeissEffect() }
    @objc func selectGeissEffectFromMenu(_ sender: NSMenuItem) {
        engineView.selectGeissEffect(at: sender.tag)
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
    @objc func randomizePalette(_ sender: NSMenuItem) { engineView.randomizeGeissPalette() }

    private func editGeissConfig(_ edit: (inout GeissEngine.Config) -> Void) {
        guard var config = engineView.getGeissConfig() else { return }
        edit(&config)
        engineView.setGeissConfig(config)
    }

    // MARK: - TripexMenuTarget

    @objc func nextTripexEffectAction(_ sender: NSMenuItem) { engineView.nextTripexEffect() }
    @objc func previousTripexEffectAction(_ sender: NSMenuItem) { engineView.previousTripexEffect() }
    @objc func randomTripexEffectAction(_ sender: NSMenuItem) { engineView.randomTripexEffect() }
    @objc func reconfigureTripexAction(_ sender: NSMenuItem) { engineView.reconfigureTripex() }
    @objc func toggleTripexHoldAction(_ sender: NSMenuItem) { engineView.toggleTripexHold() }
    @objc func toggleTripexAudioInfoAction(_ sender: NSMenuItem) { engineView.toggleTripexAudioInfo() }
    @objc func toggleTripexHelpAction(_ sender: NSMenuItem) { engineView.toggleTripexHelp() }
    @objc func selectTripexEffectFromMenu(_ sender: NSMenuItem) {
        engineView.selectTripexEffect(at: sender.tag)
    }
    @objc func setTripexIntensity(_ sender: NSMenuItem) {
        let value = Float(sender.tag) / 100.0
        engineView.tripexIntensityScale = value
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
        guard engineView.isProjectMAvailable else { return nil }
        let path = engineView.presetPath(at: engineView.currentPresetIndex)
        guard !path.isEmpty else { return nil }
        return (engineView.currentPresetName, path)
    }

    private func presetIndex(forPath path: String) -> Int? {
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
        guard engineView.currentEngineType == .projectM, presetCycleMode != .off else {
            if engineView.currentEngineType == .tripex { applyTripexCycleMode() }
            return
        }
        cycleTimer = Timer.scheduledTimer(withTimeInterval: presetCycleInterval, repeats: true) {
            [weak self] _ in
            guard let self else { return }
            self.presetCycleMode == .random ? self.engineView.randomPreset(hardCut: false)
                                            : self.engineView.nextPreset(hardCut: false)
        }
    }

    private func applyTripexCycleMode() {
        cycleTimer?.invalidate()
        cycleTimer = nil
        guard engineView.currentEngineType == .tripex, tripexCycleMode != .off else { return }
        cycleTimer = Timer.scheduledTimer(withTimeInterval: tripexCycleInterval, repeats: true) {
            [weak self] _ in
            guard let self else { return }
            self.tripexCycleMode == .random ? self.engineView.randomTripexEffect()
                                            : self.engineView.nextTripexEffect()
        }
    }

    /// Start (or re-pin) the engine now that its window is on screen.
    ///
    /// `VisualizationGLView.startRendering()` requires `window.isVisible`, and the skin's AVS window
    /// is created hidden and ordered in later — so the surface built during the first layout pass
    /// asked to render against a window nobody could see, was refused, and never asked again: the
    /// only thing that restarts it is an occlusion change, and that only resumes a link that had
    /// been stopped *because* of occlusion. cPro-Bento was the one skin unaffected, because its
    /// holder lives in the main player window, which is already visible.
    func resumeRendering() {
        guard !isTornDown, !isFullscreen else { return }
        engineView.resumeRenderingAfterWindowTransition()
        #if DEBUG
        // One line that answers "why is the box black?" without a GUI session: whether the surface is
        // in a window, whether that window is on screen (the only thing the display link refuses on),
        // the box it was given, and whether frames are actually being produced.
        NSLog("WINAMP-MODERN-VIS: resume window=%@ visible=%d box=%@ engine=%@ rendering=%d",
              window?.title ?? "-", window?.isVisible == true ? 1 : 0,
              NSStringFromRect(frame), engineView.currentEngineType.rawValue,
              engineView.isRendering ? 1 : 0)
        #endif
    }

    // MARK: - Keyboard

    /// The same keys NullPlayer's own visualization window answers, against the engine in the skin's
    /// box. Winamp's visualization keys are part of what a visualization *is*, and a skin's window
    /// gives the user nothing else to press but its five buttons.
    ///
    /// Offered only after the skin has refused the key, so a skin accelerator (`alt+g`, `ctrl+w`)
    /// always wins, and `false` here still falls through to the host's own menu shortcuts.
    @discardableResult
    func handleKeyDown(_ event: NSEvent) -> Bool {
        guard !isTornDown else { return false }
        let hard = event.modifierFlags.contains(.shift)
        switch event.keyCode {
        case 53: // Escape — only meaningful while this surface owns a screen
            guard isFullscreen else { return false }
            toggleFullscreen()
            return true
        case 3: // F
            toggleFullscreen()
            return true
        case 35: // P — 30/60fps
            engineView.toggleLowPowerMode()
            return true
        case 124: // Right arrow
            stepPreset(by: 1, hardCut: hard)
            return true
        case 123: // Left arrow
            stepPreset(by: -1, hardCut: hard)
            return true
        case 15: // R
            randomPresetAction(nil)
            return true
        case 8: // C — Manual → Auto-Cycle → Auto-Random → Manual
            guard engineView.currentEngineType == .projectM else { return false }
            switch presetCycleMode {
            case .off: setPresetCycleMode(.cycle)
            case .cycle: setPresetCycleMode(.random)
            case .random: setPresetCycleMode(.off)
            }
            return true
        default:
            return false
        }
    }

    // MARK: - Fullscreen (`VIS_FS`)

    var isFullscreen: Bool { fullscreenWindow != nil }

    /// Take the **engine** fullscreen, not the skin's window.
    ///
    /// Winamp's `VIS_FS` fills the screen with the visualization; the skin's window, its chrome and
    /// its buttons stay where they are. Ours used to answer this button by opening NullPlayer's own
    /// visualization window fullscreen, which left a second engine running behind it in the skin's
    /// box — reported as "the viz pops out of the skin window and the two windows compete".
    ///
    /// The engine view simply *moves*: `VisualizationGLView` re-pins its context and display link
    /// from `viewDidMoveToWindow`, so one view serves both places and no second engine is ever
    /// created. `.screenSaver` is the level the visualization window's own custom fullscreen uses,
    /// and the GL view reads that level as "presenting fullscreen" when it decides whether an
    /// occluded or dragged window may stop rendering.
    func toggleFullscreen() {
        isFullscreen ? exitFullscreen() : enterFullscreen()
    }

    private func enterFullscreen() {
        guard !isTornDown, fullscreenWindow == nil,
              let screen = window?.screen ?? NSScreen.main else { return }
        let fullscreen = VisualizationFullscreenWindow(contentRect: screen.frame,
                                                       styleMask: [.borderless],
                                                       backing: .buffered, defer: false)
        fullscreen.isReleasedWhenClosed = false
        fullscreen.isOpaque = true
        fullscreen.backgroundColor = .black
        fullscreen.level = .screenSaver
        fullscreen.onExit = { [weak self] in self?.exitFullscreen() }
        fullscreen.onKeyDown = { [weak self] event in self?.handleKeyDown(event) ?? false }
        let host = NSView(frame: NSRect(origin: .zero, size: screen.frame.size))
        host.wantsLayer = true
        host.layer?.backgroundColor = NSColor.black.cgColor
        fullscreen.contentView = host
        engineView.frame = host.bounds
        host.addSubview(engineView)
        fullscreen.makeKeyAndOrderFront(nil)
        NSApp.presentationOptions = [.autoHideMenuBar, .autoHideDock]
        NSCursor.setHiddenUntilMouseMoves(true)
        engineView.resumeRenderingAfterWindowTransition()
        fullscreenWindow = fullscreen
    }

    private func exitFullscreen() {
        guard let fullscreen = fullscreenWindow else { return }
        fullscreenWindow = nil
        NSApp.presentationOptions = []
        engineView.frame = bounds
        addSubview(engineView)
        fullscreen.orderOut(nil)
        engineView.resumeRenderingAfterWindowTransition()
        window?.makeKeyAndOrderFront(nil)
    }

    func prepareForUITeardown() {
        guard !isTornDown else { return }
        exitFullscreen()
        isTornDown = true
        cycleTimer?.invalidate()
        cycleTimer = nil
        removeObservers()
        WindowManager.shared.audioEngine.removeSpectrumConsumer(Self.spectrumConsumer)
        engineView.stopRendering()
        engineView.removeFromSuperview()
        removeFromSuperview()
    }
}

/// The screen-filling window `VIS_FS` moves the engine into, and the two ways out of it that Winamp's
/// own fullscreen visualization has: **Esc** (or `f`) and a **double-click**.
private final class VisualizationFullscreenWindow: NSWindow {
    var onExit: (() -> Void)?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    /// Fullscreen is where the keyboard matters most — there are no buttons on screen at all — so the
    /// whole map goes to the surface, not just the two ways out.
    var onKeyDown: ((NSEvent) -> Bool)?

    override func keyDown(with event: NSEvent) {
        if onKeyDown?(event) == true { return }
        super.keyDown(with: event)
    }

    override func mouseDown(with event: NSEvent) {
        // The engine view passes its clicks through (`hitTest` returns nil), so this is where a click
        // on the picture arrives.
        if event.clickCount >= 2 { onExit?() }
    }
}
