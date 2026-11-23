import AppKit

/// Edits a finished rip's tags and saves them into the file itself (`RipFileTags`), before the
/// rip is split or added to the library. `onClose` runs once, after Save or Cancel.
final class RipTagsPanel: NSPanel {
    var onClose: (() -> Void)?
    private let file: URL
    private let jobID: String
    private var fields: [String: NSTextField] = [:]
    private let saveButton = NSButton(title: "Save", target: nil, action: nil)
    /// While a save runs the panel stays open: closing it would start the follow-up (a split,
    /// a library add) on the file before its new tags are in.
    private var saving = false
    /// Open panels, kept alive until they close.
    private static var open: Set<RipTagsPanel> = []

    init(file: URL, jobID: String) {
        self.file = file
        self.jobID = jobID
        super.init(contentRect: NSRect(x: 0, y: 0, width: 440, height: 300),
                   styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        title = "Edit Tags: \(file.lastPathComponent)"
        isReleasedWhenClosed = false
        buildUI()
        // ffprobe runs off the main thread; Save waits until the fields are filled, and stays off
        // if they could not be read.
        saveButton.isEnabled = false
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let tags = RipFileTags.read(file)
            DispatchQueue.main.async {
                guard let self else { return }
                guard let tags else {
                    self.alert("Tags Not Read", "The file's tags could not be read, so they cannot be saved.")
                    return
                }
                for (key, field) in self.fields where field.stringValue.isEmpty { field.stringValue = tags[key] ?? "" }
                self.saveButton.isEnabled = true
            }
        }
    }

    func show() {
        Self.open.insert(self)
        center()
        NSApp.activate(ignoringOtherApps: true)
        makeKeyAndOrderFront(nil)
    }

    private func buildUI() {
        let grid = NSGridView()
        for (key, label) in RipFileTags.keys {
            let field = NSTextField()
            field.setContentHuggingPriority(.defaultLow, for: .horizontal)
            fields[key] = field
            grid.addRow(with: [NSTextField(labelWithString: label), field])
        }
        grid.column(at: 0).xPlacement = .trailing
        grid.rowAlignment = .firstBaseline
        let cancel = NSButton(title: "Cancel", target: self, action: #selector(cancelClicked))
        cancel.keyEquivalent = "\u{1b}"
        saveButton.target = self
        saveButton.action = #selector(saveClicked)
        saveButton.keyEquivalent = "\r"
        let buttons = NSStackView(views: [cancel, saveButton])
        let stack = NSStackView(views: [grid, buttons])
        stack.orientation = .vertical
        stack.alignment = .trailing
        stack.edgeInsets = NSEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)
        stack.translatesAutoresizingMaskIntoConstraints = false
        contentView = NSView()
        contentView?.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: contentView!.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: contentView!.trailingAnchor),
            stack.topAnchor.constraint(equalTo: contentView!.topAnchor),
            stack.bottomAnchor.constraint(equalTo: contentView!.bottomAnchor),
            grid.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -32),
        ])
    }

    @objc private func saveClicked() {
        makeFirstResponder(nil)
        let tags = fields.mapValues { $0.stringValue.trimmingCharacters(in: .whitespacesAndNewlines) }
        saveButton.isEnabled = false
        saving = true
        let file = file, jobID = jobID
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let error: Error?
            do { try RipFileTags.write(tags, to: file); error = nil } catch let e { error = e }
            StreamRipper.log(jobID, error.map { "tag save failed: \($0.localizedDescription)" } ?? "tags saved")
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.saving = false
                if let error {
                    self.saveButton.isEnabled = true
                    self.alert("Tags Not Saved", error.localizedDescription)
                } else { self.close() }
            }
        }
    }

    private func alert(_ title: String, _ text: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = text
        alert.beginSheetModal(for: self)
    }

    @objc private func cancelClicked() { close() }

    override func close() {
        guard !saving else { NSSound.beep(); return }
        super.close()
        guard Self.open.remove(self) != nil else { return }
        let onClose = onClose
        self.onClose = nil
        onClose?()
    }
}
