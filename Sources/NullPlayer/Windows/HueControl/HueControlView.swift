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
    private let deleteSceneButton = NSButton(title: "Delete Scene", target: nil, action: nil)
    private var sceneOptions: [HueScene] = []
    private var selectedSceneID: String?
    private let sceneNameField = NSTextField()
    private let saveSceneButton = NSButton(title: "Save Scene", target: nil, action: nil)

    private let powerToggle = NSButton(checkboxWithTitle: "On", target: nil, action: nil)
    private let brightnessSlider = NSSlider(value: 50, minValue: 1, maxValue: 100, target: nil, action: nil)
    private let colorTempSlider = NSSlider(value: 300, minValue: 153, maxValue: 500, target: nil, action: nil)
    private let colorWell = NSColorWell()

    private let individualLightsSectionLabel = NSTextField(labelWithString: "Individual Lights")
    private let lightsScrollView = NSScrollView()
    private let lightsStackView = NSStackView()
    private var lightRows: [String: HueLightRowView] = [:]

    private let multiRoomSectionLabel = NSTextField(labelWithString: "Multi-Room Scenes")
    private let multiRoomScenePopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let applyMultiRoomSceneButton = NSButton(title: "Apply", target: nil, action: nil)
    private let editMultiRoomSceneButton = NSButton(title: "Edit", target: nil, action: nil)
    private let deleteMultiRoomSceneButton = NSButton(title: "Delete", target: nil, action: nil)
    private let newMultiRoomSceneButton = NSButton(title: "New Multi-Room Scene…", target: nil, action: nil)
    private var multiRoomSceneOptions: [HueMultiRoomSceneRecord] = []
    private var multiRoomScenePicker: HueMultiRoomScenePickerSheet?

    private let reactiveModePopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let reactiveIntensitySlider = NSSlider(value: 0.6, minValue: 0.1, maxValue: 1.0, target: nil, action: nil)
    private let reactiveSpeedSlider = NSSlider(value: 0.5, minValue: 0.0, maxValue: 1.0, target: nil, action: nil)
    private let reactivePresetPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let reactiveStatusLabel = NSTextField(labelWithString: "Reactive idle")

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
        let sceneRow = NSStackView(views: [scenePopup, applySceneButton, deleteSceneButton])
        sceneRow.orientation = .horizontal
        sceneRow.alignment = .centerY
        sceneRow.spacing = 8
        scenePopup.widthAnchor.constraint(greaterThanOrEqualToConstant: 260).isActive = true
        rootStack.addArrangedSubview(sceneRow)

        sceneNameField.placeholderString = "New scene name"
        sceneNameField.translatesAutoresizingMaskIntoConstraints = false
        let saveSceneRow = NSStackView(views: [sceneNameField, saveSceneButton])
        saveSceneRow.orientation = .horizontal
        saveSceneRow.alignment = .centerY
        saveSceneRow.spacing = 8
        sceneNameField.widthAnchor.constraint(greaterThanOrEqualToConstant: 180).isActive = true
        rootStack.addArrangedSubview(saveSceneRow)

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

        multiRoomSectionLabel.font = NSFont.systemFont(ofSize: 12, weight: .semibold)
        rootStack.addArrangedSubview(multiRoomSectionLabel)
        let multiRoomRow = NSStackView(views: [multiRoomScenePopup, applyMultiRoomSceneButton, editMultiRoomSceneButton, deleteMultiRoomSceneButton])
        multiRoomRow.orientation = .horizontal
        multiRoomRow.alignment = .centerY
        multiRoomRow.spacing = 8
        multiRoomScenePopup.widthAnchor.constraint(greaterThanOrEqualToConstant: 200).isActive = true
        rootStack.addArrangedSubview(multiRoomRow)
        rootStack.addArrangedSubview(newMultiRoomSceneButton)

        rootStack.addArrangedSubview(sectionLabel("Reactive"))
        reactiveModePopup.widthAnchor.constraint(greaterThanOrEqualToConstant: 200).isActive = true
        rootStack.addArrangedSubview(labeledRow("Mode", control: reactiveModePopup))
        rootStack.addArrangedSubview(labeledRow("Preset", control: reactivePresetPopup))
        rootStack.addArrangedSubview(labeledRow("Intensity", control: reactiveIntensitySlider))
        rootStack.addArrangedSubview(labeledRow("Speed", control: reactiveSpeedSlider))
        reactiveStatusLabel.font = NSFont.systemFont(ofSize: 11)
        reactiveStatusLabel.textColor = .secondaryLabelColor
        rootStack.addArrangedSubview(reactiveStatusLabel)

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

        scenePopup.target = self
        scenePopup.action = #selector(scenePickerChanged)

        applySceneButton.target = self
        applySceneButton.action = #selector(applyScenePressed)

        deleteSceneButton.target = self
        deleteSceneButton.action = #selector(deleteScenePressed)

        saveSceneButton.target = self
        saveSceneButton.action = #selector(saveScenePressed)

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

        applyMultiRoomSceneButton.target = self
        applyMultiRoomSceneButton.action = #selector(applyMultiRoomScenePressed)

        editMultiRoomSceneButton.target = self
        editMultiRoomSceneButton.action = #selector(editMultiRoomScenePressed)

        deleteMultiRoomSceneButton.target = self
        deleteMultiRoomSceneButton.action = #selector(deleteMultiRoomScenePressed)

        newMultiRoomSceneButton.target = self
        newMultiRoomSceneButton.action = #selector(newMultiRoomScenePressed)

        reactiveModePopup.target = self
        reactiveModePopup.action = #selector(reactiveModeChanged)

        reactivePresetPopup.target = self
        reactivePresetPopup.action = #selector(reactivePresetChanged)

        reactiveIntensitySlider.target = self
        reactiveIntensitySlider.action = #selector(reactiveIntensityChanged)
        reactiveIntensitySlider.isContinuous = true

        reactiveSpeedSlider.target = self
        reactiveSpeedSlider.action = #selector(reactiveSpeedChanged)
        reactiveSpeedSlider.isContinuous = true
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

        sceneOptions = manager.filteredScenes
        scenePopup.removeAllItems()
        if sceneOptions.isEmpty {
            scenePopup.addItem(withTitle: "No scenes in bridge")
        } else {
            scenePopup.addItems(withTitles: sceneOptions.map(\.name))
            if let id = selectedSceneID,
               let index = sceneOptions.firstIndex(where: { $0.id == id }) {
                scenePopup.selectItem(at: index)
            } else {
                selectedSceneID = sceneOptions.first?.id
            }
        }

        let hasScenes = manager.connectionState == .connected
            && manager.selectedTarget?.targetType == .room
            && sceneOptions.isEmpty == false
        applySceneButton.isEnabled = hasScenes
        deleteSceneButton.isEnabled = hasScenes

        saveSceneButton.isEnabled =
            manager.connectionState == .connected &&
            manager.selectedTarget?.targetType == .room

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

        multiRoomSceneOptions = manager.multiRoomSceneRecords
        multiRoomSectionLabel.isHidden = !isConnected
        multiRoomScenePopup.isHidden = !isConnected
        applyMultiRoomSceneButton.isHidden = !isConnected
        deleteMultiRoomSceneButton.isHidden = !isConnected
        newMultiRoomSceneButton.isHidden = !isConnected

        multiRoomScenePopup.removeAllItems()
        if multiRoomSceneOptions.isEmpty {
            multiRoomScenePopup.addItem(withTitle: "No multi-room scenes")
        } else {
            multiRoomScenePopup.addItems(withTitles: multiRoomSceneOptions.map(\.name))
        }
        let hasMultiRoomScenes = isConnected && !multiRoomSceneOptions.isEmpty
        applyMultiRoomSceneButton.isEnabled = hasMultiRoomScenes
        editMultiRoomSceneButton.isEnabled = hasMultiRoomScenes
        deleteMultiRoomSceneButton.isEnabled = hasMultiRoomScenes
        newMultiRoomSceneButton.isEnabled = isConnected

        let modeOptions: [(String, HueReactiveMode)] = [
            ("Off", .off),
            ("Entertainment (Low Latency)", .entertainment),
            ("Group Fallback", .groupFallback)
        ]
        reactiveModePopup.removeAllItems()
        reactiveModePopup.addItems(withTitles: modeOptions.map(\.0))
        if let modeIndex = modeOptions.firstIndex(where: { $0.1 == manager.reactiveSettings.mode }) {
            reactiveModePopup.selectItem(at: modeIndex)
        }

        let presetOptions = HueLightshowPreset.allCases
        reactivePresetPopup.removeAllItems()
        reactivePresetPopup.addItems(withTitles: presetOptions.map { preset in
            switch preset {
            case .auto: return "Auto"
            case .pulse: return "Pulse"
            case .ambientWave: return "Ambient Wave"
            case .strobeSafe: return "Strobe Safe"
            }
        })
        if let presetIndex = presetOptions.firstIndex(of: manager.lightshowPreset) {
            reactivePresetPopup.selectItem(at: presetIndex)
        }

        reactiveIntensitySlider.doubleValue = manager.reactiveSettings.intensity
        reactiveSpeedSlider.doubleValue = manager.reactiveSettings.speed
        let reactiveControlsEnabled = isConnected && hasRoom
        reactiveModePopup.isEnabled = reactiveControlsEnabled
        reactivePresetPopup.isEnabled = reactiveControlsEnabled
        reactiveIntensitySlider.isEnabled = reactiveControlsEnabled
        reactiveSpeedSlider.isEnabled = reactiveControlsEnabled
        reactiveStatusLabel.stringValue = "Mode: \(modeOptions.first(where: { $0.1 == manager.reactiveSettings.mode })?.0 ?? "Off")"
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

    @objc private func scenePickerChanged() {
        if isProgrammaticUpdate { return }
        let index = scenePopup.indexOfSelectedItem
        if index >= 0, index < sceneOptions.count {
            selectedSceneID = sceneOptions[index].id
        }
    }

    @objc private func applyScenePressed() {
        if isProgrammaticUpdate { return }
        let sceneIndex = scenePopup.indexOfSelectedItem
        if sceneIndex >= 0, sceneIndex < sceneOptions.count {
            selectedSceneID = sceneOptions[sceneIndex].id
            manager.activateScene(sceneOptions[sceneIndex].id)
        }
    }

    @objc private func deleteScenePressed() {
        if isProgrammaticUpdate { return }
        let sceneIndex = scenePopup.indexOfSelectedItem
        if sceneIndex >= 0, sceneIndex < sceneOptions.count {
            manager.deleteScene(sceneOptions[sceneIndex].id)
        }
    }

    @objc private func saveScenePressed() {
        if isProgrammaticUpdate { return }
        let name = sceneNameField.stringValue.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        manager.createScene(name: name)
        sceneNameField.stringValue = ""
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

    @objc private func reactiveModeChanged() {
        if isProgrammaticUpdate { return }
        let modeOptions: [HueReactiveMode] = [.off, .entertainment, .groupFallback]
        let index = reactiveModePopup.indexOfSelectedItem
        guard index >= 0, index < modeOptions.count else { return }
        manager.setReactiveMode(modeOptions[index])
    }

    @objc private func reactivePresetChanged() {
        if isProgrammaticUpdate { return }
        let presets = HueLightshowPreset.allCases
        let index = reactivePresetPopup.indexOfSelectedItem
        guard index >= 0, index < presets.count else { return }
        manager.setLightshowPreset(presets[index])
    }

    @objc private func reactiveIntensityChanged() {
        if isProgrammaticUpdate { return }
        manager.setReactiveIntensity(reactiveIntensitySlider.doubleValue)
    }

    @objc private func reactiveSpeedChanged() {
        if isProgrammaticUpdate { return }
        manager.setReactiveSpeed(reactiveSpeedSlider.doubleValue)
    }

    @objc private func applyMultiRoomScenePressed() {
        if isProgrammaticUpdate { return }
        let index = multiRoomScenePopup.indexOfSelectedItem
        guard index >= 0, index < multiRoomSceneOptions.count else { return }
        manager.activateMultiRoomScene(multiRoomSceneOptions[index])
    }

    @objc private func deleteMultiRoomScenePressed() {
        if isProgrammaticUpdate { return }
        let index = multiRoomScenePopup.indexOfSelectedItem
        guard index >= 0, index < multiRoomSceneOptions.count else { return }
        manager.deleteMultiRoomScene(multiRoomSceneOptions[index])
    }

    @objc private func editMultiRoomScenePressed() {
        if isProgrammaticUpdate { return }
        let index = multiRoomScenePopup.indexOfSelectedItem
        guard index >= 0, index < multiRoomSceneOptions.count else { return }
        showMultiRoomScenePicker(editing: multiRoomSceneOptions[index])
    }

    @objc private func newMultiRoomScenePressed() {
        showMultiRoomScenePicker(editing: nil)
    }

    private func showMultiRoomScenePicker(editing record: HueMultiRoomSceneRecord?) {
        guard let window else { return }
        let picker = HueMultiRoomScenePickerSheet(editing: record)
        picker.onSave = { [weak self] name, lightIDs in
            self?.manager.createMultiRoomScene(name: name, lightIDs: lightIDs)
        }
        multiRoomScenePicker = picker
        window.beginSheet(picker.window) { [weak self] _ in
            self?.multiRoomScenePicker = nil
        }
    }
}

private final class HueLightRowView: NSView {
    private let manager = HueManager.shared
    private let target: HueTarget
    private var isProgrammaticUpdate = false

    private let powerToggle: NSButton
    private var brightnessSlider: NSSlider?
    private var colorTempSlider: NSSlider?
    private var colorWell: NSColorWell?

    init(target: HueTarget) {
        self.target = target
        self.powerToggle = NSButton(checkboxWithTitle: target.name, target: nil, action: nil)
        self.powerToggle.font = NSFont.systemFont(ofSize: 12, weight: .medium)
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

        outerStack.addArrangedSubview(powerToggle)

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

// MARK: - Multi-Room Scene Picker Sheet

private final class HueMultiRoomScenePickerSheet: NSObject {
    var onSave: ((String, [String]) -> Void)?

    private let manager = HueManager.shared
    let window: NSWindow

    private let nameField = NSTextField()
    private let saveButton = NSButton(title: "Save", target: nil, action: nil)
    private let cancelButton = NSButton(title: "Cancel", target: nil, action: nil)
    private var lightRows: [HueLightPickerRow] = []

    init(editing record: HueMultiRoomSceneRecord? = nil) {
        let panel = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 560),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        panel.title = record == nil ? "New Multi-Room Scene" : "Edit Multi-Room Scene"
        panel.isReleasedWhenClosed = false
        self.window = panel
        super.init()
        buildUI(in: panel, preselectedLightIDs: record.map { Set($0.lightIDs) }, prefilledName: record?.name)
    }

    private func buildUI(in window: NSWindow, preselectedLightIDs: Set<String>?, prefilledName: String?) {
        let root = NSStackView()
        root.orientation = .vertical
        root.alignment = .leading
        root.spacing = 12
        root.edgeInsets = NSEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)
        root.translatesAutoresizingMaskIntoConstraints = false

        let titleLabel = NSTextField(labelWithString: "Configure lights for this scene:")
        titleLabel.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        root.addArrangedSubview(titleLabel)

        let hintLabel = NSTextField(wrappingLabelWithString: "Check lights to include. Adjust brightness and color — changes apply live to your lights.")
        hintLabel.font = NSFont.systemFont(ofSize: 11)
        hintLabel.textColor = .secondaryLabelColor
        root.addArrangedSubview(hintLabel)

        let listStack = NSStackView()
        listStack.orientation = .vertical
        listStack.alignment = .leading
        listStack.spacing = 2
        listStack.translatesAutoresizingMaskIntoConstraints = false

        let groups = manager.allLightTargetsByRoom()
        for group in groups {
            let roomLabel = NSTextField(labelWithString: group.roomName.uppercased())
            roomLabel.font = NSFont.systemFont(ofSize: 10, weight: .semibold)
            roomLabel.textColor = .secondaryLabelColor
            let roomHeader = NSView()
            roomHeader.translatesAutoresizingMaskIntoConstraints = false
            roomLabel.translatesAutoresizingMaskIntoConstraints = false
            roomHeader.addSubview(roomLabel)
            NSLayoutConstraint.activate([
                roomLabel.leadingAnchor.constraint(equalTo: roomHeader.leadingAnchor, constant: 8),
                roomLabel.centerYAnchor.constraint(equalTo: roomHeader.centerYAnchor),
                roomHeader.heightAnchor.constraint(equalToConstant: 22)
            ])
            listStack.addArrangedSubview(roomHeader)
            roomHeader.widthAnchor.constraint(equalTo: listStack.widthAnchor).isActive = true

            for light in group.lights {
                let included = preselectedLightIDs.map { $0.contains(light.lightID ?? "") } ?? true
                let row = HueLightPickerRow(target: light, included: included)
                row.translatesAutoresizingMaskIntoConstraints = false
                listStack.addArrangedSubview(row)
                row.widthAnchor.constraint(equalTo: listStack.widthAnchor).isActive = true
                lightRows.append(row)
            }
        }

        let scrollView = NSScrollView()
        scrollView.documentView = listStack
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .lineBorder
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.heightAnchor.constraint(equalToConstant: 320).isActive = true
        scrollView.widthAnchor.constraint(equalToConstant: 424).isActive = true
        listStack.widthAnchor.constraint(equalTo: scrollView.contentView.widthAnchor).isActive = true
        root.addArrangedSubview(scrollView)

        if let name = prefilledName { nameField.stringValue = name }
        nameField.placeholderString = "Enter scene name"
        nameField.widthAnchor.constraint(greaterThanOrEqualToConstant: 220).isActive = true
        let nameRow = NSStackView(views: [NSTextField(labelWithString: "Scene name:"), nameField])
        nameRow.orientation = .horizontal
        nameRow.alignment = .centerY
        nameRow.spacing = 8
        root.addArrangedSubview(nameRow)

        saveButton.bezelStyle = .rounded
        saveButton.keyEquivalent = "\r"
        cancelButton.bezelStyle = .rounded
        cancelButton.keyEquivalent = "\u{1b}"
        saveButton.target = self
        saveButton.action = #selector(savePressed)
        cancelButton.target = self
        cancelButton.action = #selector(cancelPressed)

        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let buttonRow = NSStackView(views: [spacer, cancelButton, saveButton])
        buttonRow.orientation = .horizontal
        buttonRow.alignment = .centerY
        buttonRow.spacing = 8
        root.addArrangedSubview(buttonRow)

        let contentView = NSView()
        contentView.addSubview(root)
        NSLayoutConstraint.activate([
            root.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            root.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            root.topAnchor.constraint(equalTo: contentView.topAnchor),
            root.bottomAnchor.constraint(equalTo: contentView.bottomAnchor)
        ])
        window.contentView = contentView
    }

    @objc private func savePressed() {
        let name = nameField.stringValue.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else {
            nameField.becomeFirstResponder()
            return
        }
        let selectedIDs = lightRows
            .filter { $0.isIncluded }
            .compactMap { $0.target.lightID }
        guard !selectedIDs.isEmpty else { return }
        window.sheetParent?.endSheet(window)
        onSave?(name, selectedIDs)
    }

    @objc private func cancelPressed() {
        window.sheetParent?.endSheet(window)
    }
}

// MARK: - Light picker row (include checkbox + live controls)

private final class HueLightPickerRow: NSView {
    let target: HueTarget
    var isIncluded: Bool { includeCheckbox.state == .on }

    private let manager = HueManager.shared
    private var isProgrammaticUpdate = false

    private let includeCheckbox: NSButton
    private let controlsStack = NSStackView()
    private var powerToggle: NSButton?
    private var brightnessSlider: NSSlider?
    private var colorTempSlider: NSSlider?
    private var colorWell: NSColorWell?

    init(target: HueTarget, included: Bool) {
        self.target = target
        self.includeCheckbox = NSButton(checkboxWithTitle: target.name, target: nil, action: nil)
        super.init(frame: .zero)
        includeCheckbox.state = included ? .on : .off
        includeCheckbox.font = NSFont.systemFont(ofSize: 12, weight: .medium)
        buildLayout()
        setupActions()
        updateControlsVisibility()
        NotificationCenter.default.addObserver(self, selector: #selector(hueStateChanged), name: .hueStateDidChange, object: nil)
        refreshControls()
    }

    required init?(coder: NSCoder) { fatalError() }

    deinit { NotificationCenter.default.removeObserver(self) }

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
            outerStack.topAnchor.constraint(equalTo: topAnchor, constant: 4),
            outerStack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -4)
        ])

        outerStack.addArrangedSubview(includeCheckbox)

        controlsStack.orientation = .vertical
        controlsStack.alignment = .leading
        controlsStack.spacing = 4
        controlsStack.edgeInsets = NSEdgeInsets(top: 0, left: 16, bottom: 0, right: 0)
        outerStack.addArrangedSubview(controlsStack)
        controlsStack.widthAnchor.constraint(equalTo: outerStack.widthAnchor).isActive = true

        let pt = NSButton(checkboxWithTitle: "On", target: nil, action: nil)
        pt.font = NSFont.systemFont(ofSize: 12)
        powerToggle = pt
        controlsStack.addArrangedSubview(pt)

        if target.capabilities.supportsDimming {
            let s = NSSlider(value: 50, minValue: 1, maxValue: 100, target: nil, action: nil)
            s.isContinuous = true
            brightnessSlider = s
            controlsStack.addArrangedSubview(pickerRow("Brightness", control: s))
        }

        if target.capabilities.supportsColor {
            let cw = NSColorWell()
            colorWell = cw
            controlsStack.addArrangedSubview(pickerRow("Color", control: cw))
        } else if target.capabilities.supportsColorTemperature {
            let s = NSSlider(value: 300, minValue: 153, maxValue: 500, target: nil, action: nil)
            s.isContinuous = true
            colorTempSlider = s
            controlsStack.addArrangedSubview(pickerRow("Color Temp", control: s))
        }

        let sep = NSBox()
        sep.boxType = .separator
        sep.translatesAutoresizingMaskIntoConstraints = false
        outerStack.addArrangedSubview(sep)
        sep.widthAnchor.constraint(equalTo: outerStack.widthAnchor).isActive = true
    }

    private func pickerRow(_ title: String, control: NSView) -> NSStackView {
        let label = NSTextField(labelWithString: title)
        label.font = NSFont.systemFont(ofSize: 12)
        label.widthAnchor.constraint(equalToConstant: 90).isActive = true
        let stack = NSStackView(views: [label, control])
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 8
        control.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }

    private func setupActions() {
        includeCheckbox.target = self
        includeCheckbox.action = #selector(includeToggled)
        powerToggle?.target = self
        powerToggle?.action = #selector(powerToggled)
        brightnessSlider?.target = self
        brightnessSlider?.action = #selector(brightnessChanged)
        colorTempSlider?.target = self
        colorTempSlider?.action = #selector(colorTempChanged)
        colorWell?.target = self
        colorWell?.action = #selector(colorChanged)
    }

    private func updateControlsVisibility() {
        controlsStack.isHidden = includeCheckbox.state == .off
    }

    @objc private func hueStateChanged() {
        refreshControls()
    }

    private func refreshControls() {
        isProgrammaticUpdate = true
        defer { isProgrammaticUpdate = false }
        let state = manager.state(forTarget: target)
        let connected = manager.connectionState == .connected
        powerToggle?.isEnabled = connected
        powerToggle?.state = (state?.isOn ?? false) ? .on : .off
        brightnessSlider?.isEnabled = connected
        brightnessSlider?.doubleValue = state?.brightness ?? 50
        colorTempSlider?.isEnabled = connected
        colorTempSlider?.doubleValue = Double(state?.mirek ?? 300)
        colorWell?.isEnabled = connected
        if let xy = state?.colorXY {
            colorWell?.color = nsColor(fromHueXY: xy)
        }
    }

    @objc private func includeToggled() {
        updateControlsVisibility()
    }

    @objc private func powerToggled() {
        guard !isProgrammaticUpdate, let pt = powerToggle else { return }
        manager.setPower(on: pt.state == .on, for: target)
    }

    @objc private func brightnessChanged() {
        guard !isProgrammaticUpdate, let s = brightnessSlider else { return }
        manager.setBrightness(s.doubleValue, for: target)
    }

    @objc private func colorTempChanged() {
        guard !isProgrammaticUpdate, let s = colorTempSlider else { return }
        manager.setColorTemperature(mirek: Int(s.doubleValue.rounded()), for: target)
    }

    @objc private func colorChanged() {
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
