import AppKit

/// Controller for Emby server configuration dialog
class EmbyLinkSheet: NSWindowController, NSWindowDelegate {

    private var nameField: NSTextField!
    private var urlField: NSTextField!
    private var usernameField: NSTextField!
    private var passwordField: NSSecureTextField!
    private var statusLabel: NSTextField!
    private var saveButton: NSButton!
    private var testButton: NSButton!

    private var editingServer: EmbyServer?
    var completionHandler: ((EmbyServer?) -> Void)?

    /// No-argument convenience init - required to override inherited NSWindowController.init()
    convenience init() {
        self.init(server: nil)
    }

    convenience init(server: EmbyServer?) {
        let w = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 240),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        w.title = server == nil ? "Add Emby Server" : "Edit Emby Server"

        self.init(window: w)
        self.editingServer = server
        w.delegate = self

        setupUI()

        if let s = server {
            nameField.stringValue = s.name
            urlField.stringValue = s.url
            usernameField.stringValue = s.username
            if let creds = KeychainHelper.shared.getEmbyServer(id: s.id) {
                passwordField.stringValue = creds.password
            }
        }
    }

    private func setupUI() {
        guard let cv = window?.contentView else { return }

        var y: CGFloat = 190
        let lx: CGFloat = 20, lw: CGFloat = 80, fx: CGFloat = 108, fw: CGFloat = 292, rh: CGFloat = 24, gap: CGFloat = 8

        let nl = NSTextField(labelWithString: "Name:")
        nl.frame = NSRect(x: lx, y: y, width: lw, height: rh)
        nl.alignment = .right
        cv.addSubview(nl)
        nameField = NSTextField(frame: NSRect(x: fx, y: y, width: fw, height: rh))
        nameField.placeholderString = "My Emby Server"
        cv.addSubview(nameField)

        y -= rh + gap
        let ul = NSTextField(labelWithString: "URL:")
        ul.frame = NSRect(x: lx, y: y, width: lw, height: rh)
        ul.alignment = .right
        cv.addSubview(ul)
        urlField = NSTextField(frame: NSRect(x: fx, y: y, width: fw, height: rh))
        urlField.placeholderString = "http://localhost:8096"
        cv.addSubview(urlField)

        y -= rh + gap
        let usl = NSTextField(labelWithString: "Username:")
        usl.frame = NSRect(x: lx, y: y, width: lw, height: rh)
        usl.alignment = .right
        cv.addSubview(usl)
        usernameField = NSTextField(frame: NSRect(x: fx, y: y, width: fw, height: rh))
        usernameField.placeholderString = "username"
        cv.addSubview(usernameField)

        y -= rh + gap
        let pl = NSTextField(labelWithString: "Password:")
        pl.frame = NSRect(x: lx, y: y, width: lw, height: rh)
        pl.alignment = .right
        cv.addSubview(pl)
        passwordField = NSSecureTextField(frame: NSRect(x: fx, y: y, width: fw, height: rh))
        passwordField.placeholderString = "password"
        cv.addSubview(passwordField)

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

        testButton = NSButton(title: "Test", target: self, action: #selector(test))
        testButton.bezelStyle = .rounded
        testButton.frame = NSRect(x: 108, y: 16, width: 80, height: 32)
        cv.addSubview(testButton)

        saveButton = NSButton(title: "Save", target: self, action: #selector(save))
        saveButton.bezelStyle = .rounded
        saveButton.frame = NSRect(x: 320, y: 16, width: 80, height: 32)
        saveButton.keyEquivalent = "\r"
        cv.addSubview(saveButton)
    }

    func showDialog(completion: @escaping (EmbyServer?) -> Void) {
        completionHandler = completion
        window?.center()
        showWindow(nil)
        window?.makeKey()
        NSApp.activate(ignoringOtherApps: true)
    }

    func windowWillClose(_ notification: Notification) {
        completionHandler?(nil)
        completionHandler = nil
    }

    private func status(_ msg: String, err: Bool = false) {
        statusLabel.stringValue = msg
        statusLabel.textColor = err ? .systemRed : .secondaryLabelColor
    }

    private func buttons(_ on: Bool) {
        saveButton.isEnabled = on
        testButton.isEnabled = on
    }

    private func ok() -> Bool {
        if nameField.stringValue.trimmingCharacters(in: .whitespaces).isEmpty { status("Enter name", err: true); return false }
        let u = urlField.stringValue.trimmingCharacters(in: .whitespaces)
        if u.isEmpty { status("Enter URL", err: true); return false }
        if !u.hasPrefix("http://") && !u.hasPrefix("https://") { status("URL needs http:// or https://", err: true); return false }
        if usernameField.stringValue.trimmingCharacters(in: .whitespaces).isEmpty { status("Enter username", err: true); return false }
        if passwordField.stringValue.isEmpty { status("Enter password", err: true); return false }
        return true
    }

    @objc private func cancel() {
        completionHandler = nil
        window?.close()
    }

    @objc private func test() {
        guard ok() else { return }
        buttons(false)
        status("Testing...")

        let deviceId = KeychainHelper.shared.getOrCreateClientIdentifier()
        let testURL = urlField.stringValue.trimmingCharacters(in: .whitespaces)
        let testUsername = usernameField.stringValue.trimmingCharacters(in: .whitespaces)
        let testPassword = passwordField.stringValue

        Task { @MainActor in
            do {
                // Test by authenticating
                _ = try await EmbyServerClient.authenticate(
                    url: testURL,
                    username: testUsername,
                    password: testPassword,
                    deviceId: deviceId
                )
                status("Success!")
                statusLabel.textColor = .systemGreen
            } catch {
                status("Error: \(error.localizedDescription)", err: true)
            }
            buttons(true)
        }
    }

    @objc private func save() {
        guard ok() else { return }
        buttons(false)
        status("Saving...")

        let nm = nameField.stringValue.trimmingCharacters(in: .whitespaces)
        let ur = urlField.stringValue.trimmingCharacters(in: .whitespaces)
        let us = usernameField.stringValue.trimmingCharacters(in: .whitespaces)
        let pw = passwordField.stringValue

        Task { @MainActor in
            do {
                let server: EmbyServer
                if let e = editingServer {
                    try await EmbyManager.shared.updateServer(id: e.id, name: nm, url: ur, username: us, password: pw)
                    server = EmbyServer(id: e.id, name: nm, url: ur, username: us, userId: e.userId)
                } else {
                    server = try await EmbyManager.shared.addServer(name: nm, url: ur, username: us, password: pw)
                }
                let handler = completionHandler
                completionHandler = nil
                window?.close()
                handler?(server)
            } catch {
                status("Error: \(error.localizedDescription)", err: true)
                buttons(true)
            }
        }
    }
}

/// Controller for Emby server list dialog
class EmbyServerListSheet: NSWindowController, NSWindowDelegate, NSTableViewDataSource, NSTableViewDelegate {

    private var tableView: NSTableView!
    private var servers: [EmbyServer] = []
    private var editBtn: NSButton!
    private var removeBtn: NSButton!
    private var connectBtn: NSButton!
    var completionHandler: ((EmbyServer?) -> Void)?

    // Keep reference to child dialogs
    private var linkSheet: EmbyLinkSheet?

    convenience init() {
        let w = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 500, height: 300),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        w.title = "Manage Emby Servers"

        self.init(window: w)
        w.delegate = self
        setupUI()
        load()
    }

    private func setupUI() {
        guard let cv = window?.contentView else { return }

        tableView = NSTableView()
        tableView.usesAlternatingRowBackgroundColors = true
        tableView.delegate = self
        tableView.dataSource = self
        tableView.doubleAction = #selector(connect)
        tableView.target = self

        let c1 = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("name"))
        c1.title = "Name"; c1.width = 140
        tableView.addTableColumn(c1)

        let c2 = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("url"))
        c2.title = "URL"; c2.width = 200
        tableView.addTableColumn(c2)

        let c3 = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("user"))
        c3.title = "User"; c3.width = 100
        tableView.addTableColumn(c3)

        let sv = NSScrollView(frame: NSRect(x: 16, y: 56, width: 468, height: 220))
        sv.documentView = tableView
        sv.hasVerticalScroller = true
        cv.addSubview(sv)

        let ab = NSButton(title: "Add", target: self, action: #selector(add))
        ab.bezelStyle = .rounded
        ab.frame = NSRect(x: 16, y: 14, width: 70, height: 32)
        cv.addSubview(ab)

        editBtn = NSButton(title: "Edit", target: self, action: #selector(edit))
        editBtn.bezelStyle = .rounded
        editBtn.frame = NSRect(x: 90, y: 14, width: 70, height: 32)
        editBtn.isEnabled = false
        cv.addSubview(editBtn)

        removeBtn = NSButton(title: "Remove", target: self, action: #selector(remove))
        removeBtn.bezelStyle = .rounded
        removeBtn.frame = NSRect(x: 164, y: 14, width: 80, height: 32)
        removeBtn.isEnabled = false
        cv.addSubview(removeBtn)

        let cb = NSButton(title: "Close", target: self, action: #selector(closeWin))
        cb.bezelStyle = .rounded
        cb.frame = NSRect(x: 340, y: 14, width: 70, height: 32)
        cb.keyEquivalent = "\u{1b}"
        cv.addSubview(cb)

        connectBtn = NSButton(title: "Connect", target: self, action: #selector(connect))
        connectBtn.bezelStyle = .rounded
        connectBtn.frame = NSRect(x: 414, y: 14, width: 70, height: 32)
        connectBtn.keyEquivalent = "\r"
        connectBtn.isEnabled = false
        cv.addSubview(connectBtn)
    }

    private func load() {
        servers = EmbyManager.shared.servers
        tableView.reloadData()
        updateBtns()
    }

    private func updateBtns() {
        let sel = tableView.selectedRow >= 0
        editBtn.isEnabled = sel
        removeBtn.isEnabled = sel
        connectBtn.isEnabled = sel
    }

    func showDialog(completion: @escaping (EmbyServer?) -> Void) {
        completionHandler = completion
        window?.center()
        showWindow(nil)
        window?.makeKey()
        NSApp.activate(ignoringOtherApps: true)
    }

    func windowWillClose(_ notification: Notification) {
        completionHandler?(nil)
        completionHandler = nil
    }

    @objc private func add() {
        linkSheet = EmbyLinkSheet()
        linkSheet?.showDialog { [weak self] server in
            self?.linkSheet = nil
            if server != nil { self?.load() }
        }
    }

    @objc private func edit() {
        guard tableView.selectedRow >= 0 else { return }
        linkSheet = EmbyLinkSheet(server: servers[tableView.selectedRow])
        linkSheet?.showDialog { [weak self] _ in
            self?.linkSheet = nil
            self?.load()
        }
    }

    @objc private func remove() {
        guard tableView.selectedRow >= 0 else { return }
        let s = servers[tableView.selectedRow]
        let a = NSAlert()
        a.messageText = "Remove '\(s.name)'?"
        a.addButton(withTitle: "Remove")
        a.addButton(withTitle: "Cancel")
        if a.runModal() == .alertFirstButtonReturn {
            EmbyManager.shared.removeServer(id: s.id)
            load()
        }
    }

    @objc private func connect() {
        guard tableView.selectedRow >= 0 else { return }
        let s = servers[tableView.selectedRow]
        Task { @MainActor in
            do {
                try await EmbyManager.shared.connect(to: s)
                let handler = completionHandler
                completionHandler = nil
                window?.close()
                handler?(s)
            } catch {
                let a = NSAlert()
                a.messageText = "Failed"
                a.informativeText = error.localizedDescription
                a.runModal()
            }
        }
    }

    @objc private func closeWin() {
        completionHandler = nil
        window?.close()
    }

    // Table
    func numberOfRows(in tableView: NSTableView) -> Int { servers.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let s = servers[row]
        let cell = NSTextField(labelWithString: "")
        switch tableColumn?.identifier.rawValue {
        case "name": cell.stringValue = (EmbyManager.shared.currentServer?.id == s.id ? "● " : "") + s.name
        case "url": cell.stringValue = s.url
        case "user": cell.stringValue = s.username
        default: break
        }
        return cell
    }

    func tableViewSelectionDidChange(_ notification: Notification) { updateBtns() }
}
