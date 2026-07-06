import AppKit

/// Mode-neutral runtime shared by the classic and modern PeppyMeter windows: owns the audio level
/// model and the random-switch timer, tracks the current meter, and builds the right-click menu.
/// Contains no skin-specific code so both UI modes can reuse it.
final class PeppyMeterPresenter {
    private let levelModel = PeppyMeterLevelModel()
    private var randomTimer: Timer?

    private(set) var leftVolume: Double = 0
    private(set) var rightVolume: Double = 0
    private(set) var currentTemplate: PeppyMeterTemplate?

    /// Invoked on the main thread whenever the view should repaint.
    var onNeedsDisplay: (() -> Void)?

    init() {
        PeppyMeterLibrary.shared.loadIfNeeded()
        currentTemplate = PeppyMeterLibrary.shared.templateOrFirst(named: PeppyMeterSettings.currentMeter)
        levelModel.onLevels = { [weak self] left, right in
            guard let self else { return }
            self.leftVolume = left
            self.rightVolume = right
            self.onNeedsDisplay?()
        }
    }

    var meterNames: [String] { PeppyMeterLibrary.shared.meterNames }
    var currentMeterName: String? { currentTemplate?.name }
    var randomEnabled: Bool { PeppyMeterSettings.randomEnabled }
    var hasMeters: Bool { !PeppyMeterLibrary.shared.isEmpty }

    // MARK: Lifecycle

    func start() {
        levelModel.start()
        if PeppyMeterSettings.randomEnabled { startRandomTimer() }
    }

    func stop() {
        levelModel.stop()
        stopRandomTimer()
        leftVolume = 0
        rightVolume = 0
    }

    // MARK: Meter selection

    func selectMeter(named name: String) {
        guard let template = PeppyMeterLibrary.shared.template(named: name) else { return }
        currentTemplate = template
        PeppyMeterSettings.currentMeter = name
        onNeedsDisplay?()
    }

    func selectNextMeter() {
        selectAdjacentMeter(offset: 1)
    }

    func selectPreviousMeter() {
        selectAdjacentMeter(offset: -1)
    }

    private func selectAdjacentMeter(offset: Int) {
        let names = meterNames
        guard !names.isEmpty else { return }
        let currentIndex = currentMeterName.flatMap { names.firstIndex(of: $0) } ?? 0
        let nextIndex = (currentIndex + offset + names.count) % names.count
        selectMeter(named: names[nextIndex])
    }

    func toggleRandom() {
        PeppyMeterSettings.randomEnabled.toggle()
        if PeppyMeterSettings.randomEnabled { startRandomTimer() } else { stopRandomTimer() }
    }

    private func startRandomTimer() {
        stopRandomTimer()
        let t = Timer(timeInterval: PeppyMeterSettings.randomIntervalSeconds, repeats: true) { [weak self] _ in
            self?.advanceRandom()
        }
        RunLoop.main.add(t, forMode: .common)
        randomTimer = t
    }

    private func stopRandomTimer() {
        randomTimer?.invalidate()
        randomTimer = nil
    }

    private func advanceRandom() {
        let names = PeppyMeterLibrary.shared.meterNames
        guard names.count > 1 else { return }
        var next = currentTemplate?.name
        while next == currentTemplate?.name { next = names.randomElement() }
        if let next { selectMeter(named: next) }
    }

    // MARK: Menu

    /// Build the shared right-click menu (meter radio list + Random/Fullscreen toggles + Close).
    func buildMenu(target: AnyObject,
                   selectMeter: Selector,
                   toggleRandom: Selector,
                   toggleFullscreen: Selector,
                   close: Selector,
                   isFullscreen: Bool) -> NSMenu {
        let menu = NSMenu()
        for name in meterNames {
            let item = NSMenuItem(title: name.capitalized, action: selectMeter, keyEquivalent: "")
            item.target = target
            item.representedObject = name
            item.state = (name == currentMeterName) ? .on : .off
            menu.addItem(item)
        }
        if !meterNames.isEmpty { menu.addItem(.separator()) }
        let randomItem = NSMenuItem(title: "Random", action: toggleRandom, keyEquivalent: "")
        randomItem.target = target
        randomItem.state = randomEnabled ? .on : .off
        menu.addItem(randomItem)
        menu.addItem(.separator())
        let fullscreenItem = NSMenuItem(
            title: isFullscreen ? "Exit Fullscreen" : "Fullscreen",
            action: toggleFullscreen,
            keyEquivalent: "f"
        )
        fullscreenItem.target = target
        fullscreenItem.state = isFullscreen ? .on : .off
        menu.addItem(fullscreenItem)
        menu.addItem(.separator())
        let closeItem = NSMenuItem(title: "Close", action: close, keyEquivalent: "")
        closeItem.target = target
        menu.addItem(closeItem)
        return menu
    }
}

/// Shared meter compositing entry point used by both window views.
enum PeppyMeterDrawing {
    static func draw(in rect: CGRect, presenter: PeppyMeterPresenter, context: CGContext) {
        guard rect.width > 0, rect.height > 0 else { return }
        guard let template = presenter.currentTemplate else {
            drawPlaceholder(in: rect)
            return
        }
        PeppyMeterRenderer.draw(
            template: template,
            leftVolume: presenter.leftVolume,
            rightVolume: presenter.rightVolume,
            in: rect,
            context: context
        )
    }

    /// Shown when no meter templates are bundled (e.g. the GPL assets were removed from the build).
    private static func drawPlaceholder(in rect: CGRect) {
        let text = "No meters bundled" as NSString
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13),
            .foregroundColor: NSColor.secondaryLabelColor
        ]
        let size = text.size(withAttributes: attrs)
        text.draw(
            at: NSPoint(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2),
            withAttributes: attrs
        )
    }
}
