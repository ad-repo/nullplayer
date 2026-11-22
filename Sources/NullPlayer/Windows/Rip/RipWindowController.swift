import AppKit

/// The Rip window: start rips and follow every rip and YouTube download. Its content is a view of
/// `RipJobCenter`, so it holds no job state.
final class RipWindowController: AuxiliarySurfaceWindowController {
    let ripView: RipWindowView

    init() {
        ripView = RipWindowView(frame: NSRect(x: 0, y: 0, width: 380, height: 400))
        super.init(surface: ripView, title: "Stream Ripper", size: NSSize(width: 380, height: 400),
                   minSize: NSSize(width: 300, height: 300), accessibilityID: "RipWindow",
                   accessibilityLabel: "Stream Ripper", close: { WindowManager.shared.toggleRip() })
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}

/// The choices the form remembers between rips.
private struct RipChoices {
    private static let defaults = UserDefaults.standard
    var isVideo: Bool
    var resolution: RipResolution
    var videoFormat: RipVideoFormat
    var audioFormat: RipAudioFormat
    var audioKbps: Int
    var followUp: RipFollowUp
    var folder: String

    static func load() -> RipChoices {
        RipChoices(
            isVideo: defaults.object(forKey: "rip.isVideo") as? Bool ?? true,
            resolution: defaults.string(forKey: "rip.resolution").flatMap(RipResolution.init) ?? .p1080,
            videoFormat: defaults.string(forKey: "rip.videoFormat").flatMap(RipVideoFormat.init) ?? .original,
            audioFormat: defaults.string(forKey: "rip.audioFormat").flatMap(RipAudioFormat.init) ?? .originalOpus,
            audioKbps: (defaults.object(forKey: "rip.audioKbps") as? Int).flatMap { RipAudioFormat.bitrates.contains($0) ? $0 : nil }
                ?? RipAudioFormat.defaultKbps,
            followUp: RipFollowUp(editTags: defaults.bool(forKey: "rip.editTags"),
                                  addToLibrary: defaults.bool(forKey: "rip.addToLibrary")),
            folder: defaults.string(forKey: "rip.folder")
                ?? FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first?.path
                ?? NSHomeDirectory())
    }

    func save() {
        Self.defaults.set(isVideo, forKey: "rip.isVideo")
        Self.defaults.set(resolution.rawValue, forKey: "rip.resolution")
        Self.defaults.set(videoFormat.rawValue, forKey: "rip.videoFormat")
        Self.defaults.set(audioFormat.rawValue, forKey: "rip.audioFormat")
        Self.defaults.set(audioKbps, forKey: "rip.audioKbps")
        Self.defaults.set(followUp.editTags, forKey: "rip.editTags")
        Self.defaults.set(followUp.addToLibrary, forKey: "rip.addToLibrary")
        Self.defaults.set(folder, forKey: "rip.folder")
    }

    var mode: StreamRipper.Mode {
        isVideo ? .video(StreamRipper.VideoProfile(resolution: resolution, format: videoFormat))
            : .audio(audioFormat.format(kbps: audioKbps))
    }
}

/// The Rip window's content: the form, the Jobs / History list and the footer. A `.wal` skin
/// hosts the same view.
final class RipWindowView: AuxiliarySurfaceView, NSTextFieldDelegate {
    private var observing = false
    private var choices = RipChoices.load()
    private var message: String?
    private var highlightedID: String?
    /// The history revision the History tab last drew, so job progress does not redraw it.
    private var drawnHistoryRevision = -1

    private let urlLabel = NSTextField(labelWithString: "URL")
    private let urlField = NSTextField()
    private let typePopup = NSPopUpButton()
    private let resolutionPopup = NSPopUpButton()
    private let bitratePopup = NSPopUpButton()
    private let formatPopup = NSPopUpButton()
    private let editTagsCheckbox = NSButton(checkboxWithTitle: "Edit tags when done", target: nil, action: nil)
    private let libraryCheckbox = NSButton(checkboxWithTitle: "Add to Library", target: nil, action: nil)
    private let hint = NSTextField(labelWithString: "")
    private let folderPopup = NSPopUpButton()
    private let ripButton = NSButton(title: "Rip", target: nil, action: nil)
    private let tabs = NSSegmentedControl(labels: ["Jobs", "History"], trackingMode: .selectOne, target: nil, action: nil)
    private let scroll = NSScrollView()
    private let document = RipListDocumentView()
    private var rows: [RipJobRowView] = []
    private let empty = NSTextField(labelWithString: "")
    private let notifyCheckbox = NSButton(checkboxWithTitle: "Show in notification panel", target: nil, action: nil)
    private let clearButton = NSButton(title: "Clear", target: nil, action: nil)

    private var center: RipJobCenter { .shared }
    private var showsHistory: Bool { tabs.selectedSegment == 1 }

    init(frame: NSRect) {
        super.init(frame: frame, chromeTitle: "STREAM RIPPER")
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.documentView = document
        addSubview(scroll)
        for view in [urlLabel, urlField, typePopup, resolutionPopup, bitratePopup, formatPopup,
                     editTagsCheckbox, libraryCheckbox, hint, folderPopup, ripButton,
                     tabs, empty, notifyCheckbox, clearButton] { addSubview(view) }
        urlLabel.font = .systemFont(ofSize: 11)
        urlField.placeholderString = "https://…"
        urlField.lineBreakMode = .byTruncatingHead
        urlField.delegate = self
        urlField.setAccessibilityIdentifier("RipURLField")
        typePopup.addItems(withTitles: ["Video", "Audio"])
        resolutionPopup.addItems(withTitles: RipResolution.allCases.map(\.title))
        bitratePopup.addItems(withTitles: RipAudioFormat.bitrates.map { "\($0) kbps" })
        hint.font = .systemFont(ofSize: 10)
        hint.lineBreakMode = .byTruncatingTail
        empty.font = .systemFont(ofSize: 11)
        empty.alignment = .center
        notifyCheckbox.font = .systemFont(ofSize: 10)
        editTagsCheckbox.font = .systemFont(ofSize: 11)
        libraryCheckbox.font = .systemFont(ofSize: 11)
        libraryCheckbox.toolTip = "Adds the rip to the local library, split into tracks when it has chapters."
        tabs.selectedSegment = 0
        for button in [ripButton, clearButton] { button.bezelStyle = .rounded }
        ripButton.keyEquivalent = "\r"
        ripButton.setAccessibilityIdentifier("RipStartButton")
        for (control, action) in [(typePopup, #selector(choicesChanged)), (resolutionPopup, #selector(choicesChanged)),
                                  (bitratePopup, #selector(choicesChanged)),
                                  (editTagsCheckbox, #selector(choicesChanged)), (libraryCheckbox, #selector(choicesChanged)),
                                  (formatPopup, #selector(choicesChanged)), (folderPopup, #selector(folderChanged)),
                                  (ripButton, #selector(ripClicked)), (tabs, #selector(tabChanged)),
                                  (notifyCheckbox, #selector(notifyChanged)), (clearButton, #selector(clearClicked))]
            as [(NSControl, Selector)] {
            control.target = self
            control.action = action
        }
        loadChoicesIntoForm()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func paletteDidChange() { refresh() }

    // MARK: - Form

    private func loadChoicesIntoForm() {
        typePopup.selectItem(at: choices.isVideo ? 0 : 1)
        resolutionPopup.selectItem(at: RipResolution.allCases.firstIndex(of: choices.resolution) ?? 1)
        formatPopup.removeAllItems()
        if choices.isVideo {
            formatPopup.addItems(withTitles: RipVideoFormat.allCases.map(\.title))
            formatPopup.selectItem(at: RipVideoFormat.allCases.firstIndex(of: choices.videoFormat) ?? 0)
        } else {
            formatPopup.addItems(withTitles: RipAudioFormat.allCases.map(\.title))
            formatPopup.selectItem(at: RipAudioFormat.allCases.firstIndex(of: choices.audioFormat) ?? 0)
        }
        bitratePopup.selectItem(at: RipAudioFormat.bitrates.firstIndex(of: choices.audioKbps) ?? 1)
        resolutionPopup.isHidden = !choices.isVideo
        bitratePopup.isHidden = choices.isVideo || !choices.audioFormat.takesBitrate
        editTagsCheckbox.state = choices.followUp.editTags ? .on : .off
        libraryCheckbox.state = choices.followUp.addToLibrary ? .on : .off
        editTagsCheckbox.isHidden = choices.isVideo
        libraryCheckbox.isHidden = choices.isVideo
        folderPopup.removeAllItems()
        folderPopup.addItem(withTitle: (choices.folder as NSString).lastPathComponent)
        folderPopup.lastItem?.toolTip = choices.folder
        folderPopup.menu?.addItem(.separator())
        folderPopup.addItem(withTitle: "Choose Folder…")
        folderPopup.selectItem(at: 0)
        updateFormState()
    }

    private func updateFormState() {
        ripButton.isEnabled = Self.ripURL(from: urlField.stringValue) != nil
        if let message {
            hint.stringValue = message
            hint.textColor = .systemRed
        } else {
            hint.stringValue = choices.isVideo ? choices.videoFormat.hint : choices.audioFormat.hint
            hint.textColor = textColor.withAlphaComponent(0.7)
        }
        hint.toolTip = hint.stringValue
    }

    private static func ripURL(from text: String) -> URL? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed), url.scheme == "http" || url.scheme == "https", url.host != nil else { return nil }
        return url
    }

    /// Focuses the URL field, pre-filled from the clipboard when it holds a web URL and the field
    /// is empty (Libraries → YouTube → Rip URL…).
    func focusURLField() {
        if urlField.stringValue.isEmpty, let clip = NSPasteboard.general.string(forType: .string),
           Self.ripURL(from: clip) != nil {
            urlField.stringValue = clip.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        window?.makeFirstResponder(urlField)
        updateFormState()
    }

    func controlTextDidChange(_ obj: Notification) {
        message = nil
        updateFormState()
    }

    @objc private func choicesChanged() {
        let wasVideo = choices.isVideo
        choices.isVideo = typePopup.indexOfSelectedItem == 0
        choices.resolution = RipResolution.allCases[max(0, resolutionPopup.indexOfSelectedItem)]
        choices.audioKbps = RipAudioFormat.bitrates[max(0, bitratePopup.indexOfSelectedItem)]
        choices.followUp = RipFollowUp(editTags: editTagsCheckbox.state == .on, addToLibrary: libraryCheckbox.state == .on)
        if wasVideo == choices.isVideo {
            let index = max(0, formatPopup.indexOfSelectedItem)
            if choices.isVideo { choices.videoFormat = RipVideoFormat.allCases[index] }
            else { choices.audioFormat = RipAudioFormat.allCases[index] }
        }
        choices.save()
        loadChoicesIntoForm()
        needsLayout = true
    }

    @objc private func folderChanged() {
        defer { loadChoicesIntoForm() }
        guard folderPopup.indexOfSelectedItem != 0 else { return }
        let panel = NSOpenPanel()
        panel.title = "Choose Destination Folder"
        panel.prompt = "Save Here"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.directoryURL = URL(fileURLWithPath: choices.folder)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        choices.folder = url.path
        choices.save()
    }

    @objc private func ripClicked() {
        guard let url = Self.ripURL(from: urlField.stringValue) else { return }
        guard StreamRipper.resolveRipTools() != nil else {
            message = StreamRipper.missingToolsMessage
            updateFormState()
            return
        }
        let before = Set(center.jobs.map(\.id))
        let job = center.startRip(url: url, mode: choices.mode, folder: choices.folder,
                                  followUp: choices.isVideo ? RipFollowUp() : choices.followUp)
        tabs.selectedSegment = 0
        if before.contains(job.id) {
            // Already running with these choices: point at it rather than start it twice.
            highlightedID = job.id
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
                self?.highlightedID = nil
                self?.refresh()
            }
        } else {
            urlField.stringValue = ""
        }
        updateFormState()
        refresh()
    }

    @objc private func tabChanged() { refresh() }
    @objc private func notifyChanged() { center.showsActivityNotifications = notifyCheckbox.state == .on }
    @objc private func clearClicked() { showsHistory ? center.clearHistory() : center.clearFinished() }

    // MARK: - List

    @objc private func jobsDidChange() {
        // History rows check their files on disk; progress ticks must not repeat that.
        if showsHistory, center.history.revision == drawnHistoryRevision { return }
        refresh()
    }

    override func refresh() {
        super.refresh()
        let color = textColor
        for control in [ripButton, clearButton, notifyCheckbox, editTagsCheckbox, libraryCheckbox] { control.contentTintColor = color }
        urlLabel.textColor = color
        notifyCheckbox.state = center.showsActivityNotifications ? .on : .off

        let models = showsHistory ? center.history.entries.map(model(for:)) : center.jobs.map(model(for:))
        drawnHistoryRevision = showsHistory ? center.history.revision : -1
        while rows.count < models.count {
            let row = RipJobRowView()
            rows.append(row)
            document.addSubview(row)
        }
        while rows.count > models.count { rows.removeLast().removeFromSuperview() }
        for (row, model) in zip(rows, models) {
            row.update(model, color: color)
            row.highlighted = model.id == highlightedID
        }
        empty.isHidden = !models.isEmpty
        empty.stringValue = showsHistory ? "No finished rips yet." : "Paste a URL above and press Rip."
        empty.textColor = color.withAlphaComponent(0.6)
        clearButton.title = showsHistory ? "Clear History" : "Clear Finished"
        clearButton.isEnabled = showsHistory ? !center.history.entries.isEmpty : center.jobs.contains { $0.phase.isFinished }
        updateFormState()
        needsLayout = true
        needsDisplay = true
    }

    private func model(for job: RipJob) -> RipRowModel {
        var parts = [job.phase.title]
        if job.phase == .queuedForEncode, let position = RipEncodeQueue.position(of: job.id) { parts.append("#\(position) in line") }
        if let fraction = job.fraction, !job.phase.isFinished { parts.append("\(Int(fraction * 100))%") }
        if let remaining = job.remaining, remaining.isFinite { parts.append("\(Self.shortDuration(remaining)) left") }
        if job.request.isYouTube { parts.append("YouTube") }
        parts.append(job.request.summary)
        var actions: [RipRowModel.Action] = []
        switch job.phase {
        case .done:
            if let path = job.outputPath { actions += fileActions(path: path) }
            if let size = job.sizeBytes { parts.insert(ByteCountFormatter.string(fromByteCount: size, countStyle: .file), at: 1) }
        case .failed:
            parts = ["Failed: " + Self.firstLine(of: job.error)]
            actions += retryAction(job.request, followUp: job.followUp)
        case .cancelled:
            actions += retryAction(job.request, followUp: job.followUp)
        default:
            actions.append(.init(symbol: "xmark.circle", label: "Cancel") { [weak self] in self?.center.cancel(job) })
        }
        return RipRowModel(id: job.id, title: job.title, detail: parts.joined(separator: " · "),
                           detailToolTip: job.error, fraction: job.fraction,
                           showsProgress: !job.phase.isFinished, isFailure: job.phase == .failed, actions: actions)
    }

    private func model(for entry: RipHistoryEntry) -> RipRowModel {
        var parts = [Self.dateFormatter.string(from: entry.finishedAt), entry.outcome.title]
        if let size = entry.sizeBytes { parts.append(ByteCountFormatter.string(fromByteCount: size, countStyle: .file)) }
        if entry.request.isYouTube { parts.append("YouTube") }
        parts.append(entry.request.summary)
        var actions: [RipRowModel.Action] = []
        if let path = entry.outputPath {
            if FileManager.default.fileExists(atPath: path) { actions += fileActions(path: path) }
            else { parts.append("file moved or deleted") }
        }
        if entry.outcome == .failed { parts.append(Self.firstLine(of: entry.error)) }
        actions += retryAction(entry.request)
        actions.append(.init(symbol: "doc.on.doc", label: "Copy URL") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(entry.request.url.absoluteString, forType: .string)
        })
        actions.append(.init(symbol: "trash", label: "Remove from History") { [weak self] in
            self?.center.removeHistoryEntry(id: entry.id)
        })
        return RipRowModel(id: entry.id, title: entry.title, detail: parts.joined(separator: " · "), detailToolTip: entry.error,
                           fraction: nil, showsProgress: false, isFailure: entry.outcome == .failed, actions: actions)
    }

    /// A failure's first line; the row's tooltip carries the whole error.
    private static func firstLine(of error: String?) -> String {
        error?.split(separator: "\n").first.map(String.init) ?? ""
    }

    private func fileActions(path: String) -> [RipRowModel.Action] {
        [.init(symbol: "play.fill", label: "Play") { StreamRipper.play(path: path) },
         .init(symbol: "magnifyingglass", label: "Reveal in Finder") {
             NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
         }]
    }

    /// Retry for a rip; a YouTube download has no rip choices and is not retried here.
    private func retryAction(_ request: RipRequest, followUp: RipFollowUp = RipFollowUp()) -> [RipRowModel.Action] {
        guard case .rip(let mode, let folder) = request.kind else { return [] }
        return [.init(symbol: "arrow.clockwise", label: "Retry") { [weak self] in
            self?.center.startRip(url: request.url, mode: mode, folder: folder, followUp: followUp)
            self?.tabs.selectedSegment = 0
            self?.refresh()
        }]
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter
    }()

    private static func shortDuration(_ seconds: TimeInterval) -> String {
        let s = Int(seconds)
        return s >= 3600 ? String(format: "%dh%02dm", s / 3600, s / 60 % 60) : String(format: "%dm%02ds", s / 60, s % 60)
    }

    // MARK: - Layout and drawing

    override func layout() {
        super.layout()
        let area = contentArea
        let s = controlScale
        let pad: CGFloat = 10 * s
        let width = max(0, area.width - pad * 2)
        let left = area.minX + pad
        let line: CGFloat = 28 * s
        var top = area.maxY - 8 * s
        func place(_ view: NSView, x: CGFloat, width: CGFloat, height: CGFloat = 24) {
            view.frame = NSRect(x: x, y: top - height * s, width: max(0, width), height: height * s)
            view.setBoundsSize(NSSize(width: view.frame.width / s, height: height))
        }
        place(urlLabel, x: left, width: 30 * s, height: 20)
        place(urlField, x: left + 32 * s, width: width - 32 * s, height: 22)
        top -= line
        let half = (width - 6 * s) / 2
        if choices.isVideo {
            place(typePopup, x: left, width: half)
            place(resolutionPopup, x: left + half + 6 * s, width: half)
            top -= line
            place(formatPopup, x: left, width: width)
        } else {
            // Audio: Type, Format and (for a lossy encode) Bitrate share one line.
            let typeWidth = 80 * s
            let bitrateWidth: CGFloat = choices.audioFormat.takesBitrate ? 96 * s : 0
            place(typePopup, x: left, width: typeWidth)
            place(formatPopup, x: left + typeWidth + 6 * s,
                  width: width - typeWidth - 6 * s - (bitrateWidth > 0 ? bitrateWidth + 6 * s : 0))
            place(bitratePopup, x: left + width - bitrateWidth, width: bitrateWidth)
            top -= line - 4 * s
            place(editTagsCheckbox, x: left, width: half, height: 20)
            place(libraryCheckbox, x: left + half + 6 * s, width: half, height: 20)
        }
        top -= line - 4 * s
        place(hint, x: left, width: width, height: 14)
        top -= 18 * s
        place(folderPopup, x: left, width: width - 70 * s)
        place(ripButton, x: left + width - 64 * s, width: 64 * s)
        top -= line + 2 * s
        place(tabs, x: left, width: 150 * s, height: 22)
        let listTop = top - 26 * s

        let footer: CGFloat = 32 * s
        top = area.minY + footer - 4 * s
        place(notifyCheckbox, x: left, width: width - 116 * s, height: 20)
        place(clearButton, x: left + width - 110 * s, width: 110 * s)

        scroll.frame = NSRect(x: area.minX, y: area.minY + footer, width: area.width, height: max(0, listTop - area.minY - footer))
        let rowWidth = scroll.contentSize.width
        let rowHeight = RipJobRowView.height * s
        document.frame = NSRect(x: 0, y: 0, width: rowWidth, height: max(scroll.contentSize.height, CGFloat(rows.count) * rowHeight))
        for (index, row) in rows.enumerated() {
            row.frame = NSRect(x: 0, y: CGFloat(index) * rowHeight, width: rowWidth, height: rowHeight)
            row.setBoundsSize(NSSize(width: rowWidth / s, height: RipJobRowView.height))
            row.needsLayout = true
        }
        empty.frame = NSRect(x: scroll.frame.minX + pad, y: scroll.frame.midY - 8 * s, width: width, height: 16 * s)
        empty.setBoundsSize(NSSize(width: empty.frame.width / s, height: 16))
        finishLayout()
    }

    /// Reattaches to `RipJobCenter`: rows for every job at its current state, then its updates.
    override func resume() {
        if !observing {
            NotificationCenter.default.addObserver(self, selector: #selector(jobsDidChange), name: .ripJobsDidChange, object: nil)
            observing = true
        }
        super.resume()
    }

    /// Detaches from `RipJobCenter`; the jobs carry on without the window.
    override func suspend() {
        guard observing else { return }
        NotificationCenter.default.removeObserver(self, name: .ripJobsDidChange, object: nil)
        observing = false
    }
}

private final class RipListDocumentView: NSView {
    override var isFlipped: Bool { true }
}
