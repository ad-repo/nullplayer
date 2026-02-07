import AppKit
@preconcurrency import KSPlayer

/// Track type for the selection panel
enum TrackType {
    case audio
    case subtitle
}

/// Represents a track that can be selected (either from KSPlayer or Plex)
struct SelectableTrack: Identifiable, Equatable {
    let id: String
    let type: TrackType
    let name: String
    let language: String?
    let codec: String?
    let isSelected: Bool
    let isExternal: Bool      // For Plex external subtitles
    let externalURL: URL?     // URL for external subtitle download
    let ksTrack: MediaPlayerTrack?  // Reference to KSPlayer track
    let plexStream: PlexStream?     // Reference to Plex stream
    
    static func == (lhs: SelectableTrack, rhs: SelectableTrack) -> Bool {
        lhs.id == rhs.id && lhs.type == rhs.type && lhs.isSelected == rhs.isSelected
    }
}

/// Delegate protocol for track selection panel actions
protocol TrackSelectionPanelDelegate: AnyObject {
    func trackSelectionPanel(_ panel: TrackSelectionPanelView, didSelectAudioTrack track: SelectableTrack?)
    func trackSelectionPanel(_ panel: TrackSelectionPanelView, didSelectSubtitleTrack track: SelectableTrack?)
    func trackSelectionPanel(_ panel: TrackSelectionPanelView, didChangeSubtitleDelay delay: TimeInterval)
    func trackSelectionPanelDidRequestClose(_ panel: TrackSelectionPanelView)
}

/// Netflix-style slide-out panel for audio/subtitle track selection
class TrackSelectionPanelView: NSView {
    
    // MARK: - Properties
    
    weak var delegate: TrackSelectionPanelDelegate?
    
    private var audioTracks: [SelectableTrack] = []
    private var subtitleTracks: [SelectableTrack] = []
    
    // UI Components
    private var backgroundView: NSVisualEffectView!
    private var contentView: NSView!
    private var scrollView: NSScrollView!
    private var stackView: NSStackView!
    
    // Subtitle settings
    private var subtitleDelaySlider: NSSlider?
    private var subtitleDelayLabel: NSTextField?
    private var currentSubtitleDelay: TimeInterval = 0
    
    /// Panel width
    private let panelWidth: CGFloat = 320
    
    /// Whether the panel is currently visible
    private(set) var isVisible: Bool = false
    
    // MARK: - Initialization
    
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupView()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupView()
    }
    
    // MARK: - Setup
    
    private func setupView() {
        wantsLayer = true
        layer?.backgroundColor = .clear
        
        // Click-outside detection (full overlay)
        let clickCatcher = NSView(frame: bounds)
        clickCatcher.autoresizingMask = [.width, .height]
        addSubview(clickCatcher)
        
        let clickGesture = NSClickGestureRecognizer(target: self, action: #selector(handleClickOutside(_:)))
        clickCatcher.addGestureRecognizer(clickGesture)
        
        // Background blur effect for the panel
        backgroundView = NSVisualEffectView(frame: NSRect(x: bounds.width - panelWidth, y: 0, width: panelWidth, height: bounds.height))
        backgroundView.material = .hudWindow
        backgroundView.blendingMode = .behindWindow
        backgroundView.state = .active
        backgroundView.wantsLayer = true
        backgroundView.layer?.cornerRadius = 0
        backgroundView.autoresizingMask = [.height, .minXMargin]
        addSubview(backgroundView)
        
        // Semi-transparent dark overlay on the panel
        contentView = NSView(frame: backgroundView.bounds)
        contentView.wantsLayer = true
        contentView.layer?.backgroundColor = NSColor(white: 0.1, alpha: 0.85).cgColor
        contentView.autoresizingMask = [.width, .height]
        backgroundView.addSubview(contentView)
        
        // Scroll view for content
        scrollView = NSScrollView(frame: contentView.bounds.insetBy(dx: 0, dy: 0))
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false
        scrollView.autoresizingMask = [.width, .height]
        contentView.addSubview(scrollView)
        
        // Stack view for sections
        stackView = NSStackView()
        stackView.orientation = .vertical
        stackView.alignment = .leading
        stackView.spacing = 20
        stackView.translatesAutoresizingMaskIntoConstraints = false
        
        let documentView = NSView()
        documentView.translatesAutoresizingMaskIntoConstraints = false
        documentView.addSubview(stackView)
        scrollView.documentView = documentView
        
        NSLayoutConstraint.activate([
            stackView.topAnchor.constraint(equalTo: documentView.topAnchor, constant: 20),
            stackView.leadingAnchor.constraint(equalTo: documentView.leadingAnchor, constant: 20),
            stackView.trailingAnchor.constraint(equalTo: documentView.trailingAnchor, constant: -20),
            stackView.bottomAnchor.constraint(lessThanOrEqualTo: documentView.bottomAnchor, constant: -20),
            documentView.widthAnchor.constraint(equalToConstant: panelWidth)
        ])
        
        // Initially hidden
        alphaValue = 0
        isHidden = true
    }
    
    // MARK: - Public Methods
    
    /// Update the tracks displayed in the panel
    func updateTracks(audioTracks: [SelectableTrack], subtitleTracks: [SelectableTrack]) {
        self.audioTracks = audioTracks
        self.subtitleTracks = subtitleTracks
        rebuildContent()
    }
    
    /// Show the panel with animation
    func show() {
        guard !isVisible else { return }
        isVisible = true
        isHidden = false
        
        // Start off-screen
        backgroundView.frame.origin.x = bounds.width
        
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.25
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            self.alphaValue = 1.0
            self.backgroundView.animator().frame.origin.x = self.bounds.width - self.panelWidth
        }
    }
    
    /// Hide the panel with animation
    func hide() {
        guard isVisible else { return }
        isVisible = false
        
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.2
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            self.alphaValue = 0
            self.backgroundView.animator().frame.origin.x = self.bounds.width
        }, completionHandler: {
            self.isHidden = true
        })
    }
    
    /// Toggle panel visibility
    func toggle() {
        if isVisible {
            hide()
        } else {
            show()
        }
    }
    
    // MARK: - Content Building
    
    private func rebuildContent() {
        // Remove existing content
        stackView.arrangedSubviews.forEach { $0.removeFromSuperview() }
        
        // Title
        let titleLabel = createSectionTitle("Track Selection")
        titleLabel.font = NSFont.boldSystemFont(ofSize: 18)
        stackView.addArrangedSubview(titleLabel)
        
        // Audio section
        if !audioTracks.isEmpty {
            let audioSection = createSection(title: "Audio", tracks: audioTracks, type: .audio)
            stackView.addArrangedSubview(audioSection)
        }
        
        // Subtitles section
        let subtitleSection = createSection(title: "Subtitles", tracks: subtitleTracks, type: .subtitle, includeOffOption: true)
        stackView.addArrangedSubview(subtitleSection)
        
        // Subtitle settings (only if subtitles are available)
        if !subtitleTracks.isEmpty {
            let settingsSection = createSubtitleSettingsSection()
            stackView.addArrangedSubview(settingsSection)
        }
        
        // Force layout update
        stackView.needsLayout = true
        scrollView.documentView?.needsLayout = true
    }
    
    private func createSectionTitle(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.textColor = .white
        label.font = NSFont.boldSystemFont(ofSize: 14)
        return label
    }
    
    private func createSection(title: String, tracks: [SelectableTrack], type: TrackType, includeOffOption: Bool = false) -> NSView {
        let container = NSStackView()
        container.orientation = .vertical
        container.alignment = .leading
        container.spacing = 8
        
        // Section title
        let titleLabel = createSectionTitle(title)
        container.addArrangedSubview(titleLabel)
        
        // "Off" option for subtitles
        if includeOffOption {
            let isOff = tracks.allSatisfy { !$0.isSelected }
            let offButton = createTrackButton(name: "Off", subtitle: nil, isSelected: isOff, tag: -1, type: type)
            container.addArrangedSubview(offButton)
        }
        
        // Track buttons
        for (index, track) in tracks.enumerated() {
            let subtitle = buildTrackSubtitle(track)
            let button = createTrackButton(name: track.name, subtitle: subtitle, isSelected: track.isSelected, tag: index, type: type)
            container.addArrangedSubview(button)
        }
        
        return container
    }
    
    private func buildTrackSubtitle(_ track: SelectableTrack) -> String? {
        var parts: [String] = []
        
        if let codec = track.codec {
            parts.append(codec.uppercased())
        }
        
        if track.isExternal {
            parts.append("External")
        }
        
        return parts.isEmpty ? nil : parts.joined(separator: " • ")
    }
    
    private func createTrackButton(name: String, subtitle: String?, isSelected: Bool, tag: Int, type: TrackType) -> NSView {
        let container = NSView()
        container.wantsLayer = true
        container.layer?.cornerRadius = 8
        container.layer?.backgroundColor = isSelected ? NSColor.controlAccentColor.withAlphaComponent(0.3).cgColor : NSColor.clear.cgColor
        
        let stack = NSStackView()
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(stack)
        
        // Checkmark indicator
        let checkmark = NSTextField(labelWithString: isSelected ? "✓" : "")
        checkmark.textColor = .controlAccentColor
        checkmark.font = NSFont.systemFont(ofSize: 16, weight: .bold)
        checkmark.setContentHuggingPriority(.required, for: .horizontal)
        stack.addArrangedSubview(checkmark)
        
        // Text stack
        let textStack = NSStackView()
        textStack.orientation = .vertical
        textStack.alignment = .leading
        textStack.spacing = 2
        
        let nameLabel = NSTextField(labelWithString: name)
        nameLabel.textColor = .white
        nameLabel.font = NSFont.systemFont(ofSize: 14, weight: isSelected ? .semibold : .regular)
        textStack.addArrangedSubview(nameLabel)
        
        if let subtitle = subtitle {
            let subtitleLabel = NSTextField(labelWithString: subtitle)
            subtitleLabel.textColor = NSColor.white.withAlphaComponent(0.6)
            subtitleLabel.font = NSFont.systemFont(ofSize: 11)
            textStack.addArrangedSubview(subtitleLabel)
        }
        
        stack.addArrangedSubview(textStack)
        
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: container.topAnchor, constant: 10),
            stack.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -10),
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 12),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -12),
            container.widthAnchor.constraint(equalToConstant: panelWidth - 40)
        ])
        
        // Click handling
        let clickGesture = NSClickGestureRecognizer(target: self, action: type == .audio ? #selector(audioTrackClicked(_:)) : #selector(subtitleTrackClicked(_:)))
        container.addGestureRecognizer(clickGesture)
        container.tag = tag  // Use tag to identify which track was clicked
        
        // Store type info using associated object
        objc_setAssociatedObject(container, &AssociatedKeys.trackType, type, .OBJC_ASSOCIATION_RETAIN)
        
        return container
    }
    
    private func createSubtitleSettingsSection() -> NSView {
        let container = NSStackView()
        container.orientation = .vertical
        container.alignment = .leading
        container.spacing = 12
        
        // Section title
        let titleLabel = createSectionTitle("Subtitle Settings")
        container.addArrangedSubview(titleLabel)
        
        // Delay slider
        let delayStack = NSStackView()
        delayStack.orientation = .vertical
        delayStack.alignment = .leading
        delayStack.spacing = 4
        
        let delayTitleStack = NSStackView()
        delayTitleStack.orientation = .horizontal
        delayTitleStack.spacing = 8
        
        let delayLabel = NSTextField(labelWithString: "Subtitle Delay")
        delayLabel.textColor = NSColor.white.withAlphaComponent(0.8)
        delayLabel.font = NSFont.systemFont(ofSize: 12)
        delayTitleStack.addArrangedSubview(delayLabel)
        
        subtitleDelayLabel = NSTextField(labelWithString: "0.0s")
        subtitleDelayLabel?.textColor = .controlAccentColor
        subtitleDelayLabel?.font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        delayTitleStack.addArrangedSubview(subtitleDelayLabel!)
        
        delayStack.addArrangedSubview(delayTitleStack)
        
        subtitleDelaySlider = NSSlider(value: 0, minValue: -5, maxValue: 5, target: self, action: #selector(subtitleDelayChanged(_:)))
        subtitleDelaySlider?.isContinuous = true
        subtitleDelaySlider?.translatesAutoresizingMaskIntoConstraints = false
        delayStack.addArrangedSubview(subtitleDelaySlider!)
        
        NSLayoutConstraint.activate([
            subtitleDelaySlider!.widthAnchor.constraint(equalToConstant: panelWidth - 60)
        ])
        
        // Delay range labels
        let rangeStack = NSStackView()
        rangeStack.orientation = .horizontal
        rangeStack.distribution = .equalSpacing
        
        let minLabel = NSTextField(labelWithString: "-5s")
        minLabel.textColor = NSColor.white.withAlphaComponent(0.5)
        minLabel.font = NSFont.systemFont(ofSize: 10)
        
        let maxLabel = NSTextField(labelWithString: "+5s")
        maxLabel.textColor = NSColor.white.withAlphaComponent(0.5)
        maxLabel.font = NSFont.systemFont(ofSize: 10)
        
        rangeStack.addArrangedSubview(minLabel)
        rangeStack.addArrangedSubview(maxLabel)
        rangeStack.translatesAutoresizingMaskIntoConstraints = false
        delayStack.addArrangedSubview(rangeStack)
        
        NSLayoutConstraint.activate([
            rangeStack.widthAnchor.constraint(equalToConstant: panelWidth - 60)
        ])
        
        container.addArrangedSubview(delayStack)
        
        return container
    }
    
    // MARK: - Actions
    
    @objc private func handleClickOutside(_ gesture: NSClickGestureRecognizer) {
        let location = gesture.location(in: self)
        if !backgroundView.frame.contains(location) {
            hide()
            delegate?.trackSelectionPanelDidRequestClose(self)
        }
    }
    
    @objc private func audioTrackClicked(_ gesture: NSClickGestureRecognizer) {
        guard let view = gesture.view else { return }
        let index = view.tag
        
        if index >= 0 && index < audioTracks.count {
            delegate?.trackSelectionPanel(self, didSelectAudioTrack: audioTracks[index])
        }
    }
    
    @objc private func subtitleTrackClicked(_ gesture: NSClickGestureRecognizer) {
        guard let view = gesture.view else { return }
        let index = view.tag
        
        if index == -1 {
            // "Off" option selected
            delegate?.trackSelectionPanel(self, didSelectSubtitleTrack: nil)
        } else if index >= 0 && index < subtitleTracks.count {
            delegate?.trackSelectionPanel(self, didSelectSubtitleTrack: subtitleTracks[index])
        }
    }
    
    @objc private func subtitleDelayChanged(_ sender: NSSlider) {
        currentSubtitleDelay = sender.doubleValue
        let sign = currentSubtitleDelay >= 0 ? "+" : ""
        subtitleDelayLabel?.stringValue = String(format: "%@%.1fs", sign, currentSubtitleDelay)
        delegate?.trackSelectionPanel(self, didChangeSubtitleDelay: currentSubtitleDelay)
    }
    
    // MARK: - Layout
    
    override func layout() {
        super.layout()
        backgroundView.frame = NSRect(x: isVisible ? bounds.width - panelWidth : bounds.width, y: 0, width: panelWidth, height: bounds.height)
    }
}

// MARK: - Associated Keys

private struct AssociatedKeys {
    static var trackType = "trackType"
}

// MARK: - View Tag Extension

extension NSView {
    private struct AssociatedKeys {
        static var viewTag = "viewTag"
    }
    
    var tag: Int {
        get {
            return objc_getAssociatedObject(self, &AssociatedKeys.viewTag) as? Int ?? 0
        }
        set {
            objc_setAssociatedObject(self, &AssociatedKeys.viewTag, newValue, .OBJC_ASSOCIATION_RETAIN)
        }
    }
}
