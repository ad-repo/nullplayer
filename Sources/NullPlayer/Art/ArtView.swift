import AppKit
import AVFoundation

/// Whatever owns the window an `ArtView` is in: `ArtWindowController` for a window of its own, the
/// hosted `ArtWindowView` inside a `.wal` skin.
protocol ArtViewHost: AnyObject {
    var isArtFullscreen: Bool { get }
    func toggleArtFullscreen()
    func closeArt()
}

/// The Art window's content: the playing track's cover, its star rating, and the audio-reactive
/// VIS effects. Chrome-free and shared by every skin family — the Classic and Original window views
/// frame it, and a `.wal` skin hosts the classic one (`WinampModernHostedWindowRegistry`).
///
/// The cover is `NowPlayingManager`'s, the one fetch the app runs per track (the system Now Playing
/// panel and a `.wal` skin's `<AlbumArt>` read the same image).
final class ArtView: NSView {
    weak var host: ArtViewHost?

    /// The `browserVis*` names are the Library Browser's, from when VIS lived there; kept so a chosen
    /// effect and intensity carry over.
    private enum Keys {
        static let effect = "browserVisEffect"
        static let defaultEffect = "browserVisDefaultEffect"
        static let intensity = "browserVisIntensity"
        static let visualizing = "artWindowVisualizing"
    }

    private enum VisMode { case single, random, cycle }

    /// `NowPlayingManager`'s cover, unless the playing file embeds several pictures (an MP3's front,
    /// back and booklet), which a double-click then steps through.
    private var nowPlayingArtwork: NSImage? = NowPlayingManager.shared.currentArtwork {
        didSet { artworkDidChange() }
    }
    private var embeddedArtwork: [NSImage] = [] { didSet { embeddedIndex = 0; artworkDidChange() } }
    private var embeddedIndex = 0
    private var embeddedArtworkTask: Task<Void, Never>?
    private var pendingSingleClick: DispatchWorkItem?

    private var artwork: NSImage? {
        embeddedArtwork.isEmpty ? nowPlayingArtwork : embeddedArtwork[embeddedIndex]
    }

    private func artworkDidChange() {
        syncVisTimer()
        needsDisplay = true
    }

    private var isVisualizing = UserDefaults.standard.bool(forKey: Keys.visualizing) {
        didSet {
            UserDefaults.standard.set(isVisualizing, forKey: Keys.visualizing)
            visTime = 0
            syncVisTimer()
            needsDisplay = true
        }
    }
    private var effect: ArtVisEffect = {
        let defaults = UserDefaults.standard
        let raw = defaults.string(forKey: Keys.defaultEffect) ?? defaults.string(forKey: Keys.effect)
        return raw.flatMap(ArtVisEffect.init(rawValue:)) ?? .psychedelic
    }()
    private var visMode: VisMode = .single { didSet { syncVisTimer() } }
    private var cycleInterval: TimeInterval = 10 { didSet { cycleTimer?.invalidate(); cycleTimer = nil; syncVisTimer() } }
    private var intensity: CGFloat = UserDefaults.standard.object(forKey: Keys.intensity) != nil
        ? CGFloat(UserDefaults.standard.double(forKey: Keys.intensity)) : 1.0 {
        didSet { UserDefaults.standard.set(intensity, forKey: Keys.intensity) }
    }

    private let renderer = ArtVisRenderer()
    private var visTimer: Timer?
    private var cycleTimer: Timer?
    private var visTime: TimeInterval = 0
    private var lastBeatTime: TimeInterval = 0
    private var silenceFrames = 0
    private var isSpectrumConsumer = false
    private var windowObservers: [NSObjectProtocol] = []

    private var ratingSubmitTask: Task<Void, Never>?
    private lazy var ratingOverlay: RatingOverlayView = {
        let overlay = RatingOverlayView(frame: bounds)
        overlay.autoresizingMask = [.width, .height]
        overlay.isHidden = true
        overlay.onRatingSelected = { [weak self] rating in self?.submitRating(rating) }
        overlay.onDismiss = { [weak self] in self?.hideRatingOverlay() }
        addSubview(overlay)
        return overlay
    }()

    private var currentTrack: Track? { WindowManager.shared.audioEngine.currentTrack }
    private var isFullscreen: Bool { host?.isArtFullscreen == true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        setAccessibilityIdentifier("artView")
        setAccessibilityLabel("Album Art")
        NotificationCenter.default.addObserver(self, selector: #selector(artworkDidLoad),
                                               name: NowPlayingManager.artworkDidLoadNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(trackDidChange),
                                               name: .audioTrackDidChange, object: nil)
        loadEmbeddedArtwork()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    deinit {
        NotificationCenter.default.removeObserver(self)
        windowObservers.forEach(NotificationCenter.default.removeObserver)
    }

    /// Stop every timer and the spectrum feed. The view may be reused afterwards: showing it again
    /// restarts what its state asks for.
    func tearDown() {
        pendingSingleClick?.cancel()
        hideRatingOverlay()
        stopVisTimers()
    }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        NSColor.black.setFill()
        bounds.fill()

        guard let cgImage = artwork?.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            drawPlaceholder(currentTrack == nil ? "Nothing playing" : "No album art")
            return
        }
        let imageSize = CGSize(width: cgImage.width, height: cgImage.height)
        let image = isVisualizing
            ? renderer.render(cgImage, effect: effect, spectrum: WindowManager.shared.audioEngine.spectrumData,
                              time: visTime, intensity: intensity) ?? cgImage
            : cgImage
        context.interpolationQuality = .high
        context.draw(image, in: AVMakeRect(aspectRatio: imageSize, insideRect: bounds))
    }

    private func drawPlaceholder(_ text: String) {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12),
            .foregroundColor: NSColor(white: 0.55, alpha: 1)
        ]
        let size = text.size(withAttributes: attrs)
        text.draw(at: NSPoint(x: bounds.midX - size.width / 2, y: bounds.midY - size.height / 2),
                  withAttributes: attrs)
    }

    // MARK: - Following the playing track

    @objc private func artworkDidLoad() {
        nowPlayingArtwork = NowPlayingManager.shared.currentArtwork
    }

    /// The previous cover stays up until the next one arrives, rather than flashing the placeholder
    /// between tracks; only the rating overlay, which belongs to the old track, goes.
    @objc private func trackDidChange() {
        hideRatingOverlay()
        loadEmbeddedArtwork()
        needsDisplay = true
    }

    private func loadEmbeddedArtwork() {
        embeddedArtworkTask?.cancel()
        if !embeddedArtwork.isEmpty { embeddedArtwork = [] }
        guard let track = currentTrack, track.url.isFileURL else { return }
        embeddedArtworkTask = Task { @MainActor [weak self] in
            let images = await Self.embeddedArtwork(of: track.url)
            guard let self, !Task.isCancelled, self.currentTrack?.id == track.id, images.count > 1 else { return }
            self.embeddedArtwork = images
        }
    }

    /// Every picture embedded in a local file, de-duplicated across the metadata formats that repeat
    /// them.
    private static func embeddedArtwork(of url: URL) async -> [NSImage] {
        let asset = AVURLAsset(url: url)
        var items = (try? await asset.load(.metadata)) ?? []
        for format in [AVMetadataFormat.id3Metadata, .iTunesMetadata] {
            items += (try? await asset.loadMetadata(for: format)) ?? []
        }
        var seen = Set<Data>()
        var images: [NSImage] = []
        for item in items where item.commonKey == .commonKeyArtwork {
            guard let data = try? await item.load(.dataValue), seen.insert(data).inserted,
                  let image = NSImage(data: data) else { continue }
            images.append(image)
        }
        return images
    }

    // MARK: - VIS lifecycle

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        windowObservers.forEach(NotificationCenter.default.removeObserver)
        windowObservers = []
        if let window {
            windowObservers = [NSWindow.didChangeOcclusionStateNotification,
                               NSWindow.didMiniaturizeNotification,
                               NSWindow.didDeminiaturizeNotification].map {
                NotificationCenter.default.addObserver(forName: $0, object: window, queue: .main) { [weak self] _ in
                    self?.syncVisTimer()
                }
            }
        }
        syncVisTimer()
    }

    private var isOnScreen: Bool {
        guard let window else { return false }
        return window.isVisible && !window.isMiniaturized && window.occlusionState.contains(.visible)
    }

    /// One place decides whether the effect animates: VIS on, a cover to animate, and a window on
    /// screen. Everything that changes any of those calls this.
    private func syncVisTimer() {
        guard isVisualizing, artwork != nil, isOnScreen else {
            stopVisTimers()
            return
        }
        if visTimer == nil {
            silenceFrames = 0
            setSpectrumConsumer(true)
            let timer = Timer(timeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in self?.visTick() }
            RunLoop.main.add(timer, forMode: .common)
            visTimer = timer
        }
        if visMode == .cycle, cycleTimer == nil {
            let timer = Timer(timeInterval: cycleInterval, repeats: true) { [weak self] _ in
                guard let self else { return }
                self.effect = self.effect.advanced(by: 1)
            }
            RunLoop.main.add(timer, forMode: .common)
            cycleTimer = timer
        } else if visMode != .cycle {
            cycleTimer?.invalidate()
            cycleTimer = nil
        }
    }

    private func stopVisTimers() {
        visTimer?.invalidate()
        visTimer = nil
        cycleTimer?.invalidate()
        cycleTimer = nil
        setSpectrumConsumer(false)
    }

    private func setSpectrumConsumer(_ on: Bool) {
        guard on != isSpectrumConsumer else { return }
        isSpectrumConsumer = on
        if on {
            WindowManager.shared.audioEngine.addSpectrumConsumer("artWindowVisualizer")
        } else {
            WindowManager.shared.audioEngine.removeSpectrumConsumer("artWindowVisualizer")
        }
    }

    private func visTick() {
        visTime += 1.0 / 30.0
        let spectrum = WindowManager.shared.audioEngine.spectrumData
        let level = spectrum.isEmpty ? 0 : spectrum.reduce(0, +) / Float(spectrum.count)
        if level < 0.001 {
            silenceFrames += 1
            // Streaming audio may still be buffering while playing, so only a stopped or paused
            // engine lets the effect rest.
            if silenceFrames > 15 && WindowManager.shared.audioEngine.state != .playing { return }
        } else {
            silenceFrames = 0
            let bass = spectrum.prefix(10).reduce(0, +) / 10.0
            if visMode == .random, bass > 0.5, visTime - lastBeatTime > 0.3 {
                lastBeatTime = visTime
                if Double.random(in: 0...1) < 0.3 { effect = ArtVisEffect.allCases.randomElement() ?? effect }
            }
        }
        needsDisplay = true
    }

    private func step(by offset: Int) {
        visMode = .single
        effect = effect.advanced(by: offset)
        needsDisplay = true
    }

    // MARK: - Rating

    private func showRatingOverlay() {
        guard let track = currentTrack, TrackRatingService.isRateable(track) else { return }
        ratingOverlay.frame = bounds
        ratingOverlay.setRating(TrackRatingService.shared.localRating(for: track) ?? 0)
        ratingOverlay.isHidden = false
        Task { @MainActor [weak self] in
            let rating = await TrackRatingService.shared.rating(for: track)
            guard let self, self.currentTrack?.id == track.id, self.ratingSubmitTask == nil else { return }
            self.ratingOverlay.setRating(rating ?? 0)
        }
    }

    private func hideRatingOverlay() {
        if !ratingOverlay.isHidden { ratingOverlay.isHidden = true }
    }

    /// Every rating — a star, a key, the menu — goes through here. Debounced so a run of clicks
    /// across the stars sends one request; only a newer rating replaces it. Hiding the panel,
    /// closing the window or the next track starting does not take a chosen rating back.
    private func submitRating(_ rating: Int) {
        guard let track = currentTrack else { return }
        ratingSubmitTask?.cancel()
        ratingSubmitTask = Task { @MainActor [weak self] in
            var saved = false
            do {
                try await Task.sleep(nanoseconds: 500_000_000)
                try await TrackRatingService.shared.setRating(rating > 0 ? rating : nil, for: track)
                saved = true
            } catch is CancellationError {
            } catch {
                NSLog("ArtView: rating failed: %@", error.localizedDescription.redactingSensitiveURLQueryItems)
            }
            // A newer rating cancelled this one and holds the slot now.
            guard let self, !Task.isCancelled else { return }
            self.ratingSubmitTask = nil
            guard saved else { return }
            try? await Task.sleep(nanoseconds: 300_000_000)
            self.hideRatingOverlay()
        }
    }

    // MARK: - Mouse and keys

    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    /// A click steps the effect while VIS runs. Otherwise a double-click steps through the file's
    /// embedded pictures and a single click opens the star rating — held for the double-click
    /// interval so the first click of a double does not open it. Anything this view has no use for
    /// goes on to the window view under it, which is what drags the window.
    private var forwardsMouse = false

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        forwardsMouse = false
        pendingSingleClick?.cancel()
        pendingSingleClick = nil
        if isVisualizing, artwork != nil {
            step(by: 1)
        } else if event.clickCount >= 2, embeddedArtwork.count > 1 {
            embeddedIndex = (embeddedIndex + 1) % embeddedArtwork.count
            artworkDidChange()
        } else if let track = currentTrack, TrackRatingService.isRateable(track) {
            let click = DispatchWorkItem { [weak self] in self?.showRatingOverlay() }
            pendingSingleClick = click
            DispatchQueue.main.asyncAfter(deadline: .now() + NSEvent.doubleClickInterval, execute: click)
        } else {
            forwardsMouse = true
            super.mouseDown(with: event)
        }
    }

    override func mouseDragged(with event: NSEvent) {
        if forwardsMouse { super.mouseDragged(with: event) }
    }

    override func mouseUp(with event: NSEvent) {
        if forwardsMouse { super.mouseUp(with: event) }
        forwardsMouse = false
    }

    override func keyDown(with event: NSEvent) {
        if !ratingOverlay.isHidden {
            switch event.keyCode {
            case 53: hideRatingOverlay(); return
            case 51, 117: ratingOverlay.setRating(0); submitRating(0); return
            case 18...22:
                let rating = Int(event.keyCode - 17) * 2
                ratingOverlay.setRating(rating)
                submitRating(rating)
                return
            default: break
            }
        }
        switch event.keyCode {
        case 3: host?.toggleArtFullscreen()                              // F
        case 9: isVisualizing.toggle()                                   // V
        case 53 where isFullscreen: host?.toggleArtFullscreen()          // Esc
        case 53 where isVisualizing: isVisualizing = false
        case 123 where isVisualizing: step(by: -1)                       // ←
        case 124 where isVisualizing: step(by: 1)                        // →
        case 126 where isVisualizing: intensity = min(2.0, intensity + 0.25)  // ↑
        case 125 where isVisualizing: intensity = max(0.5, intensity - 0.25)  // ↓
        case 15 where isVisualizing: visMode = visMode == .random ? .single : .random  // R
        case 8 where isVisualizing: visMode = visMode == .cycle ? .single : .cycle     // C
        default: super.keyDown(with: event)
        }
    }

    // MARK: - Menu

    override func menu(for event: NSEvent) -> NSMenu? {
        let menu = NSMenu(title: "Art")
        func add(_ title: String, _ action: Selector?, tag: Int = 0, state: Bool = false,
                 to target: NSMenu? = nil) {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
            item.target = self
            item.tag = tag
            item.state = state ? .on : .off
            item.isEnabled = action != nil
            (target ?? menu).addItem(item)
        }

        add(isVisualizing ? "Turn Off Visualization" : "Enable Visualization", #selector(toggleVisualization))
        if isVisualizing {
            add("▶ \(effect.rawValue)", nil)
            add("Next Effect →", #selector(menuNextEffect))
            add("← Previous Effect", #selector(menuPreviousEffect))
            menu.addItem(.separator())
            add("Random Mode", #selector(toggleRandomMode), state: visMode == .random)
            add("Auto-Cycle Mode", #selector(toggleCycleMode), state: visMode == .cycle)
            let intervals = NSMenu()
            for seconds in [5, 10, 20, 30] {
                add("\(seconds) seconds", #selector(selectCycleInterval(_:)), tag: seconds,
                    state: Int(cycleInterval) == seconds, to: intervals)
            }
            menu.addItem(submenuItem("Cycle Interval", intervals))
            let levels = NSMenu()
            for (name, value) in [("Low", 50), ("Medium", 75), ("Normal", 100), ("High", 150), ("Extreme", 200)] {
                add(name, #selector(selectIntensity(_:)), tag: value,
                    state: abs(intensity * 100 - CGFloat(value)) < 10, to: levels)
            }
            menu.addItem(submenuItem("Intensity", levels))
        }

        let effects = NSMenu()
        let savedDefault = UserDefaults.standard.string(forKey: Keys.defaultEffect)
        for group in ArtVisEffect.groups {
            let sub = NSMenu(title: group.title)
            for (index, candidate) in ArtVisEffect.allCases.enumerated() where group.effects.contains(candidate) {
                add(candidate.rawValue, #selector(selectEffect(_:)), tag: index, to: sub)
                sub.items.last?.state = candidate == effect ? .on : (candidate.rawValue == savedDefault ? .mixed : .off)
            }
            effects.addItem(submenuItem(group.title, sub))
        }
        effects.addItem(.separator())
        add("Set Current as Default", #selector(setDefaultEffect), to: effects)
        menu.addItem(submenuItem("Effects", effects))

        if let track = currentTrack, TrackRatingService.isRateable(track) {
            menu.addItem(.separator())
            let stars = NSMenu()
            for count in 1...5 {
                add(String(repeating: "★", count: count) + String(repeating: "☆", count: 5 - count),
                    #selector(rateFromMenu(_:)), tag: count * 2, to: stars)
            }
            stars.addItem(.separator())
            add("Clear Rating", #selector(rateFromMenu(_:)), tag: 0, to: stars)
            menu.addItem(submenuItem("Rate", stars))
        }

        menu.addItem(.separator())
        add("Click: rate • Double-click: next picture • V: visualization • F: fullscreen", nil)
        menu.addItem(.separator())
        add(isFullscreen ? "Exit Fullscreen" : "Fullscreen", #selector(menuToggleFullscreen))
        add("Close", #selector(menuClose))
        return menu
    }

    private func submenuItem(_ title: String, _ submenu: NSMenu) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.submenu = submenu
        return item
    }

    @objc private func toggleVisualization() { isVisualizing.toggle() }
    @objc private func menuNextEffect() { step(by: 1) }
    @objc private func menuPreviousEffect() { step(by: -1) }
    @objc private func toggleRandomMode() { visMode = visMode == .random ? .single : .random }
    @objc private func toggleCycleMode() { visMode = visMode == .cycle ? .single : .cycle }
    @objc private func selectCycleInterval(_ sender: NSMenuItem) { cycleInterval = TimeInterval(sender.tag) }
    @objc private func selectIntensity(_ sender: NSMenuItem) { intensity = CGFloat(sender.tag) / 100 }
    @objc private func setDefaultEffect() { UserDefaults.standard.set(effect.rawValue, forKey: Keys.defaultEffect) }
    @objc private func menuToggleFullscreen() { host?.toggleArtFullscreen() }
    @objc private func menuClose() { host?.closeArt() }

    @objc private func selectEffect(_ sender: NSMenuItem) {
        effect = ArtVisEffect.allCases[sender.tag]
        visMode = .single
        UserDefaults.standard.set(effect.rawValue, forKey: Keys.effect)
        needsDisplay = true
    }

    @objc private func rateFromMenu(_ sender: NSMenuItem) { submitRating(sender.tag) }

    // MARK: - Default size

    /// The cover's height over its width, square when nothing is loaded — what the window's default
    /// height is cut from, so a cover opens filling it.
    static var preferredAspectRatio: CGFloat {
        guard let size = NowPlayingManager.shared.currentArtwork?.size, size.width > 0, size.height > 0 else {
            return 1
        }
        return min(max(size.height / size.width, 0.5), 2)
    }

    /// A window `width` wide whose `chrome` leaves the art a hole of `aspectRatio` (height over
    /// width): the hole's height plus the chrome's.
    static func windowHeight(forWidth width: CGFloat, chrome: CGSize,
                             aspectRatio: CGFloat = preferredAspectRatio) -> CGFloat {
        (max(0, width - chrome.width) * aspectRatio + chrome.height).rounded()
    }
}
