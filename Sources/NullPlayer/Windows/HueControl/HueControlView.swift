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
    private let colorXSlider = NSSlider(value: 0.3, minValue: 0.0, maxValue: 1.0, target: nil, action: nil)
    private let colorYSlider = NSSlider(value: 0.3, minValue: 0.0, maxValue: 1.0, target: nil, action: nil)

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
        rootStack.addArrangedSubview(labeledRow("Color X", control: colorXSlider))
        rootStack.addArrangedSubview(labeledRow("Color Y", control: colorYSlider))

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

        colorXSlider.target = self
        colorXSlider.action = #selector(colorChanged)
        colorXSlider.isContinuous = true

        colorYSlider.target = self
        colorYSlider.action = #selector(colorChanged)
        colorYSlider.isContinuous = true
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

        colorXSlider.isEnabled = isConnected && hasRoom
        colorYSlider.isEnabled = isConnected && hasRoom
        colorXSlider.doubleValue = selectedState?.colorXY?.x ?? 0.3
        colorYSlider.doubleValue = selectedState?.colorXY?.y ?? 0.3
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
        manager.setColor(x: colorXSlider.doubleValue, y: colorYSlider.doubleValue)
    }
}
