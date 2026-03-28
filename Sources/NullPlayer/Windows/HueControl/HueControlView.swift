import AppKit

final class HueControlView: NSView {
    private let manager = HueManager.shared
    private var isProgrammaticUpdate = false

    private let connectionLabel = NSTextField(labelWithString: "Hue disconnected")
    private let bridgePopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let discoverButton = NSButton(title: "Discover", target: nil, action: nil)
    private let pairButton = NSButton(title: "Pair", target: nil, action: nil)
    private let retryButton = NSButton(title: "Retry", target: nil, action: nil)
    private let forgetButton = NSButton(title: "Forget", target: nil, action: nil)

    private let roomPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private var roomTargets: [HueTarget] = []

    private let scenePopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let applySceneButton = NSButton(title: "Apply Scene", target: nil, action: nil)
    private var sceneOptions: [HueScene] = []

    private let powerToggle = NSButton(checkboxWithTitle: "Power", target: nil, action: nil)
    private let brightnessSlider = NSSlider(value: 50, minValue: 1, maxValue: 100, target: nil, action: nil)
    private let colorTempSlider = NSSlider(value: 300, minValue: 153, maxValue: 500, target: nil, action: nil)
    private let colorWell = NSColorWell()

    private let individualLightsSectionLabel = NSTextField(labelWithString: "Individual Lights")
    private let lightsScrollView = NSScrollView()
    private let lightsStackView = NSStackView()
    private var lightRows: [String: HueLightRowView] = [:]

    private let diagnosticsLabel = NSTextField(labelWithString: "")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupView()
        setupActions()
        setupObservers()
        refreshUI()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupView()
        setupActions()
        setupObservers()
        refreshUI()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    private func setupView() {
        wantsLayer = true

        let rootStack = NSStackView()
        rootStack.orientation = .vertical
        rootStack.alignment = .leading
        rootStack.spacing = 10
        rootStack.translatesAutoresizingMaskIntoConstraints = false

        addSubview(rootStack)
        NSLayoutConstraint.activate([
            rootStack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            rootStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            rootStack.topAnchor.constraint(equalTo: topAnchor, constant: 14),
            rootStack.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor, constant: -14)
        ])

        connectionLabel.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        rootStack.addArrangedSubview(connectionLabel)

        let connectionRow = NSStackView(views: [bridgePopup, discoverButton, pairButton, retryButton, forgetButton])
        connectionRow.orientation = .horizontal
        connectionRow.alignment = .centerY
        connectionRow.spacing = 8
        bridgePopup.widthAnchor.constraint(greaterThanOrEqualToConstant: 220).isActive = true
        rootStack.addArrangedSubview(connectionRow)

        rootStack.addArrangedSubview(sectionLabel("Room"))
        roomPopup.widthAnchor.constraint(greaterThanOrEqualToConstant: 260).isActive = true
        rootStack.addArrangedSubview(roomPopup)

        rootStack.addArrangedSubview(sectionLabel("Scene"))
        let sceneRow = NSStackView(views: [scenePopup, applySceneButton])
        sceneRow.orientation = .horizontal
        sceneRow.alignment = .centerY
        sceneRow.spacing = 8
        scenePopup.widthAnchor.constraint(greaterThanOrEqualToConstant: 260).isActive = true
        rootStack.addArrangedSubview(sceneRow)

        rootStack.addArrangedSubview(sectionLabel("Controls"))
        rootStack.addArrangedSubview(powerToggle)
        rootStack.addArrangedSubview(labeledRow("Brightness", control: brightnessSlider))
        rootStack.addArrangedSubview(labeledRow("Color Temperature", control: colorTempSlider))
        rootStack.addArrangedSubview(labeledRow("Color", control: colorWell))

        individualLightsSectionLabel.font = NSFont.systemFont(ofSize: 12, weight: .semibold)
        rootStack.addArrangedSubview(individualLightsSectionLabel)

        lightsStackView.orientation = .vertical
        lightsStackView.alignment = .leading
        lightsStackView.spacing = 0
        lightsStackView.translatesAutoresizingMaskIntoConstraints = false

        lightsScrollView.documentView = lightsStackView
        lightsScrollView.hasVerticalScroller = true
        lightsScrollView.hasHorizontalScroller = false
        lightsScrollView.autohidesScrollers = true
        lightsScrollView.borderType = .lineBorder
        lightsScrollView.translatesAutoresizingMaskIntoConstraints = false
        lightsScrollView.heightAnchor.constraint(lessThanOrEqualToConstant: 250).isActive = true

        rootStack.addArrangedSubview(lightsScrollView)
        lightsScrollView.widthAnchor.constraint(equalTo: rootStack.widthAnchor).isActive = true
        lightsStackView.widthAnchor.constraint(equalTo: lightsScrollView.contentView.widthAnchor).isActive = true

        diagnosticsLabel.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        diagnosticsLabel.textColor = .secondaryLabelColor
        rootStack.addArrangedSubview(sectionLabel("Diagnostics"))
        rootStack.addArrangedSubview(diagnosticsLabel)
    }

    private func sectionLabel(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = NSFont.systemFont(ofSize: 12, weight: .semibold)
        return label
    }

    private func labeledRow(_ title: String, control: NSView) -> NSStackView {
        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = NSFont.systemFont(ofSize: 12)
        titleLabel.widthAnchor.constraint(equalToConstant: 130).isActive = true

        let stack = NSStackView(views: [titleLabel, control])
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 8
        control.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }

    private func setupActions() {
        discoverButton.target = self
        discoverButton.action = #selector(discoverPressed)

        pairButton.target = self
        pairButton.action = #selector(pairPressed)

        retryButton.target = self
        retryButton.action = #selector(retryPressed)

        forgetButton.target = self
        forgetButton.action = #selector(forgetPressed)

        roomPopup.target = self
        roomPopup.action = #selector(roomChanged)

        applySceneButton.target = self
        applySceneButton.action = #selector(applyScenePressed)

        powerToggle.target = self
        powerToggle.action = #selector(powerToggled)

        brightnessSlider.target = self
        brightnessSlider.action = #selector(brightnessChanged)
        brightnessSlider.isContinuous = true

        colorTempSlider.target = self
        colorTempSlider.action = #selector(colorTemperatureChanged)
        colorTempSlider.isContinuous = true

        colorWell.target = self
        colorWell.action = #selector(colorChanged)
    }

    private func setupObservers() {
        NotificationCenter.default.addObserver(self, selector: #selector(handleHueUpdate), name: .hueStateDidChange, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handleHueUpdate), name: .hueConnectionStateDidChange, object: nil)
    }

    @objc private func handleHueUpdate() {
        refreshUI()
    }

    private func refreshUI() {
        isProgrammaticUpdate = true
        defer { isProgrammaticUpdate = false }

        diagnosticsLabel.stringValue = manager.diagnosticsMessage
        connectionLabel.stringValue = connectionTitle()

        let bridges = manager.discoveredBridges
        bridgePopup.removeAllItems()
        if bridges.isEmpty {
            bridgePopup.addItem(withTitle: "No bridges")
        } else {
            for bridge in bridges {
                bridgePopup.addItem(withTitle: "\(bridge.name) (\(bridge.ipAddress))")
            }
        }

        if let current = manager.currentBridge,
           let index = bridges.firstIndex(where: { $0.id == current.id }) {
            bridgePopup.selectItem(at: index)
        }

        pairButton.isEnabled = bridges.isEmpty == false
        retryButton.isEnabled = manager.connectionState == .error
        forgetButton.isEnabled = manager.hasPairedBridge

        roomTargets = manager.targets
            .filter { $0.targetType == .room }
            .sorted { lhs, rhs in
                lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }

        if let firstRoom = roomTargets.first,
           roomTargets.contains(where: { $0.id == manager.selectedTargetID }) == false {
            manager.selectTarget(id: firstRoom.id)
        }

        roomPopup.removeAllItems()
        if roomTargets.isEmpty {
            roomPopup.addItem(withTitle: "No rooms")
        } else {
            roomPopup.addItems(withTitles: roomTargets.map(\.name))
            if let selectedID = manager.selectedTargetID,
               let index = roomTargets.firstIndex(where: { $0.id == selectedID }) {
                roomPopup.selectItem(at: index)
            }
        }

        sceneOptions = manager.scenes
        scenePopup.removeAllItems()
        if sceneOptions.isEmpty {
            scenePopup.addItem(withTitle: "No scenes in bridge")
        } else {
            scenePopup.addItems(withTitles: sceneOptions.map(\.name))
        }

        applySceneButton.isEnabled =
            manager.connectionState == .connected &&
            manager.selectedTarget?.targetType == .room &&
            sceneOptions.isEmpty == false

        let isConnected = manager.connectionState == .connected
        let selectedState = manager.stateForSelectedTarget()
        let hasRoom = manager.selectedTarget?.targetType == .room

        powerToggle.isEnabled = isConnected && hasRoom
        powerToggle.state = (selectedState?.isOn ?? false) ? .on : .off

        brightnessSlider.isEnabled = isConnected && hasRoom
        brightnessSlider.doubleValue = selectedState?.brightness ?? 50

        colorTempSlider.isEnabled = isConnected && hasRoom
        colorTempSlider.doubleValue = Double(selectedState?.mirek ?? 300)

        colorWell.isEnabled = isConnected && hasRoom
        if let xy = selectedState?.colorXY {
            colorWell.color = nsColor(fromHueXY: xy)
        }

        let shouldShowLights = manager.connectionState == .connected
            && manager.selectedTarget?.targetType == .room
        individualLightsSectionLabel.isHidden = !shouldShowLights
        lightsScrollView.isHidden = !shouldShowLights
        if shouldShowLights {
            refreshLightRows()
        }
    }

    private func refreshLightRows() {
        let lights = manager.lightsForSelectedRoom()
        let isConnected = manager.connectionState == .connected
        let newIDs = Set(lights.map(\.id))
        let currentIDs = Set(lightRows.keys)

        if currentIDs != newIDs {
            lightsStackView.arrangedSubviews.forEach { $0.removeFromSuperview() }
            lightRows.removeAll()
            for target in lights {
                let row = HueLightRowView(target: target)
                row.translatesAutoresizingMaskIntoConstraints = false
                lightsStackView.addArrangedSubview(row)
                row.widthAnchor.constraint(equalTo: lightsStackView.widthAnchor).isActive = true
                lightRows[target.id] = row
            }
        }

        for target in lights {
            lightRows[target.id]?.update(state: manager.state(forTarget: target), isConnected: isConnected)
        }
    }

    private func connectionTitle() -> String {
        switch manager.connectionState {
        case .disconnected:
            return "Status: Disconnected"
        case .discovering:
            return "Status: Discovering"
        case .awaitingLinkButton:
            return "Status: Awaiting Link Button"
        case .connected:
            return "Status: Connected"
        case .error:
            return "Status: Error"
        }
    }

    @objc private func discoverPressed() {
        manager.beginDiscovery()
    }

    @objc private func pairPressed() {
        let index = bridgePopup.indexOfSelectedItem
        if index >= 0, index < manager.discoveredBridges.count {
            manager.pair(with: manager.discoveredBridges[index])
        }
    }

    @objc private func retryPressed() {
        manager.retryConnection()
    }

    @objc private func forgetPressed() {
        manager.forgetBridge()
    }

    @objc private func roomChanged() {
        if isProgrammaticUpdate { return }
        let index = roomPopup.indexOfSelectedItem
        if index >= 0, index < roomTargets.count {
            manager.selectTarget(id: roomTargets[index].id)
        }
    }

    @objc private func applyScenePressed() {
        if isProgrammaticUpdate { return }
        let sceneIndex = scenePopup.indexOfSelectedItem
        if sceneIndex >= 0, sceneIndex < sceneOptions.count {
            manager.activateScene(sceneOptions[sceneIndex].id)
        }
    }

    @objc private func powerToggled() {
        if isProgrammaticUpdate { return }
        manager.setPower(on: powerToggle.state == .on)
    }

    @objc private func brightnessChanged() {
        if isProgrammaticUpdate { return }
        manager.setBrightness(brightnessSlider.doubleValue)
    }

    @objc private func colorTemperatureChanged() {
        if isProgrammaticUpdate { return }
        manager.setColorTemperature(mirek: Int(colorTempSlider.doubleValue.rounded()))
    }

    @objc private func colorChanged() {
        if isProgrammaticUpdate { return }
        let xy = hueXY(from: colorWell.color)
        manager.setColor(x: xy.x, y: xy.y)
    }
}

private final class HueLightRowView: NSView {
    private let manager = HueManager.shared
    private let target: HueTarget
    private var isProgrammaticUpdate = false

    private let powerToggle: NSButton
    private let nameLabel: NSTextField
    private var brightnessSlider: NSSlider?
    private var colorTempSlider: NSSlider?
    private var colorWell: NSColorWell?

    init(target: HueTarget) {
        self.target = target
        self.powerToggle = NSButton(checkboxWithTitle: "", target: nil, action: nil)
        self.nameLabel = NSTextField(labelWithString: target.name)
        self.nameLabel.font = NSFont.systemFont(ofSize: 12, weight: .medium)
        super.init(frame: .zero)
        buildLayout()
        setupActions()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not implemented") }

    func update(state: HueLightState?, isConnected: Bool) {
        isProgrammaticUpdate = true
        defer { isProgrammaticUpdate = false }
        powerToggle.isEnabled = isConnected
        powerToggle.state = (state?.isOn ?? false) ? .on : .off
        brightnessSlider?.isEnabled = isConnected
        brightnessSlider?.doubleValue = state?.brightness ?? 50
        colorTempSlider?.isEnabled = isConnected
        colorTempSlider?.doubleValue = Double(state?.mirek ?? 300)
        colorWell?.isEnabled = isConnected
        if let xy = state?.colorXY {
            colorWell?.color = nsColor(fromHueXY: xy)
        }
    }

    private func buildLayout() {
        let outerStack = NSStackView()
        outerStack.orientation = .vertical
        outerStack.alignment = .leading
        outerStack.spacing = 4
        outerStack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(outerStack)
        NSLayoutConstraint.activate([
            outerStack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            outerStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            outerStack.topAnchor.constraint(equalTo: topAnchor, constant: 6),
            outerStack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -6)
        ])

        let headerRow = NSStackView(views: [powerToggle, nameLabel])
        headerRow.orientation = .horizontal
        headerRow.alignment = .centerY
        headerRow.spacing = 8
        outerStack.addArrangedSubview(headerRow)

        if target.capabilities.supportsDimming {
            let s = NSSlider(value: 50, minValue: 1, maxValue: 100, target: nil, action: nil)
            s.isContinuous = true
            brightnessSlider = s
            outerStack.addArrangedSubview(rowWithLabel("Brightness", control: s))
        }

        if target.capabilities.supportsColorTemperature && !target.capabilities.supportsColor {
            let s = NSSlider(value: 300, minValue: 153, maxValue: 500, target: nil, action: nil)
            s.isContinuous = true
            colorTempSlider = s
            outerStack.addArrangedSubview(rowWithLabel("Color Temp", control: s))
        }

        if target.capabilities.supportsColor {
            let cw = NSColorWell()
            colorWell = cw
            outerStack.addArrangedSubview(rowWithLabel("Color", control: cw))
        }

        let sep = NSBox()
        sep.boxType = .separator
        sep.translatesAutoresizingMaskIntoConstraints = false
        outerStack.addArrangedSubview(sep)
        sep.widthAnchor.constraint(equalTo: outerStack.widthAnchor).isActive = true
    }

    private func rowWithLabel(_ title: String, control: NSView) -> NSStackView {
        let label = NSTextField(labelWithString: title)
        label.font = NSFont.systemFont(ofSize: 12)
        label.widthAnchor.constraint(equalToConstant: 130).isActive = true
        let stack = NSStackView(views: [label, control])
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 8
        control.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }

    private func setupActions() {
        powerToggle.target = self
        powerToggle.action = #selector(powerToggled)

        if let s = brightnessSlider {
            s.target = self
            s.action = #selector(brightnessChanged)
        }

        if let s = colorTempSlider {
            s.target = self
            s.action = #selector(colorTempChanged)
        }

        if let cw = colorWell {
            cw.target = self
            cw.action = #selector(colorWellChanged)
        }
    }

    @objc private func powerToggled() {
        guard !isProgrammaticUpdate else { return }
        manager.setPower(on: powerToggle.state == .on, for: target)
    }

    @objc private func brightnessChanged() {
        guard !isProgrammaticUpdate, let s = brightnessSlider else { return }
        manager.setBrightness(s.doubleValue, for: target)
    }

    @objc private func colorTempChanged() {
        guard !isProgrammaticUpdate, let s = colorTempSlider else { return }
        manager.setColorTemperature(mirek: Int(s.doubleValue.rounded()), for: target)
    }

    @objc private func colorWellChanged() {
        guard !isProgrammaticUpdate, let cw = colorWell else { return }
        let xy = hueXY(from: cw.color)
        manager.setColor(x: xy.x, y: xy.y, for: target)
    }
}

// MARK: - CIE 1931 XY ↔ NSColor (Hue wide-gamut D65)

private func nsColor(fromHueXY xy: (x: Double, y: Double)) -> NSColor {
    let x = xy.x, y = max(xy.y, 0.0001), z = 1.0 - xy.x - xy.y
    let X = x / y, Z = z / y   // Y = 1
    // Inverse wide-gamut matrix
    var r =  X * 1.656492 - 0.354851 - Z * 0.255038
    var g = -X * 0.707196 + 1.655397 + Z * 0.036152
    var b =  X * 0.051713 - 0.121364 + Z * 1.011530
    r = max(0, r); g = max(0, g); b = max(0, b)
    let m = max(r, g, b)
    if m > 1 { r /= m; g /= m; b /= m }
    func gamma(_ v: Double) -> Double {
        v <= 0.0031308 ? 12.92 * v : 1.055 * pow(v, 1.0 / 2.4) - 0.055
    }
    return NSColor(srgbRed: gamma(r), green: gamma(g), blue: gamma(b), alpha: 1)
}

private func hueXY(from color: NSColor) -> (x: Double, y: Double) {
    guard let c = color.usingColorSpace(.sRGB) else { return (0.3, 0.3) }
    func linear(_ v: Double) -> Double {
        v > 0.04045 ? pow((v + 0.055) / 1.055, 2.4) : v / 12.92
    }
    let r = linear(c.redComponent), g = linear(c.greenComponent), b = linear(c.blueComponent)
    let X = r * 0.664511 + g * 0.154324 + b * 0.162028
    let Y = r * 0.283881 + g * 0.668433 + b * 0.047685
    let Z = r * 0.000088 + g * 0.072310 + b * 0.986039
    let s = X + Y + Z
    guard s > 0 else { return (0.3, 0.3) }
    return (x: X / s, y: Y / s)
}
