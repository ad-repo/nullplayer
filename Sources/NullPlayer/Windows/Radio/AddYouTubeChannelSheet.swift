import AppKit

/// Controller for adding YouTube channels
class AddYouTubeChannelSheet: NSWindowController, NSWindowDelegate {
    private var urlField: NSTextField!
    private var statusLabel: NSTextField!
    private var saveButton: NSButton!
    private var addTask: Task<Void, Never>?

    private var completionHandler: ((YouTubeChannel?) -> Void)?

    convenience init() {
        let w = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 140),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        w.title = "Add YouTube Channel"

        self.init(window: w)
        w.delegate = self
        setupUI()
    }

    private func setupUI() {
        guard let cv = window?.contentView else { return }

        var y: CGFloat = 110
        let lx: CGFloat = 20, lw: CGFloat = 60, fx: CGFloat = 88, fw: CGFloat = 312, rh: CGFloat = 24, gap: CGFloat = 8

        let ul = NSTextField(labelWithString: "URL:")
        ul.frame = NSRect(x: lx, y: y, width: lw, height: rh)
        ul.alignment = .right
        cv.addSubview(ul)

        urlField = NSTextField(frame: NSRect(x: fx, y: y, width: fw, height: rh))
        urlField.placeholderString = "https://www.youtube.com/@channel"
        cv.addSubview(urlField)

        y -= rh + gap + 4
        statusLabel = NSTextField(labelWithString: "")
        statusLabel.frame = NSRect(x: lx, y: y, width: 380, height: rh)
        statusLabel.alignment = .center
        statusLabel.isBezeled = false
        statusLabel.drawsBackground = false
        statusLabel.isEditable = false
        statusLabel.font = NSFont.systemFont(ofSize: 11)
        cv.addSubview(statusLabel)

        let cb = NSButton(title: "Cancel", target: self, action: #selector(cancel))
        cb.bezelStyle = .rounded
        cb.frame = NSRect(x: 20, y: 16, width: 80, height: 32)
        cb.keyEquivalent = "\u{1b}"
        cv.addSubview(cb)

        saveButton = NSButton(title: "Add", target: self, action: #selector(save))
        saveButton.bezelStyle = .rounded
        saveButton.frame = NSRect(x: 320, y: 16, width: 80, height: 32)
        saveButton.keyEquivalent = "\r"
        cv.addSubview(saveButton)
    }

    func showDialog(completion: @escaping (YouTubeChannel?) -> Void) {
        completionHandler = completion
        window?.level = .modalPanel
        window?.center()
        showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
        window?.makeFirstResponder(urlField)
    }

    func windowWillClose(_ notification: Notification) {
        addTask?.cancel()
        addTask = nil
        completionHandler?(nil)
        completionHandler = nil
    }

    private func status(_ msg: String, err: Bool = false) {
        statusLabel.stringValue = msg
        statusLabel.textColor = err ? .systemRed : .secondaryLabelColor
    }

    private func buttons(_ on: Bool) {
        saveButton.isEnabled = on
    }

    private func validate() -> Bool {
        let urlString = urlField.stringValue.trimmingCharacters(in: .whitespaces)
        if urlString.isEmpty {
            status("Enter channel URL", err: true)
            return false
        }

        guard URL(string: urlString) != nil else {
            status("Invalid URL format", err: true)
            return false
        }

        return true
    }

    @objc private func cancel() {
        addTask?.cancel()
        addTask = nil
        let handler = completionHandler
        completionHandler = nil
        window?.close()
        handler?(nil)
    }

    @objc private func save() {
        guard validate() else { return }

        let urlString = urlField.stringValue.trimmingCharacters(in: .whitespaces)
        guard let url = URL(string: urlString) else {
            status("Invalid URL", err: true)
            return
        }

        status("Adding channel...")
        buttons(false)

        addTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                try await YouTubeManager.shared.addChannel(url: url)
                try Task.checkCancellation()
                let handler = completionHandler
                completionHandler = nil
                addTask = nil
                window?.close()
                handler?(YouTubeManager.shared.channels.last)
            } catch is CancellationError {
                addTask = nil
            } catch {
                status(error.localizedDescription, err: true)
                buttons(true)
                addTask = nil
            }
        }
    }
}
