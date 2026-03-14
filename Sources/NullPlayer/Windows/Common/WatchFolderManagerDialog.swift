import AppKit

/// Window-based manager for watched local-library folders.
final class WatchFolderManagerWindow: NSWindowController, NSWindowDelegate,
                                      NSTableViewDataSource, NSTableViewDelegate {

    private var tableView: NSTableView!
    private var rescanBtn: NSButton!
    private var finderBtn: NSButton!
    private var removeBtn: NSButton!
    private var summaries: [WatchFolderSummary] = []
    private var onLibraryChanged: (() -> Void)?

    // MARK: - Public entry point

    private static var shared: WatchFolderManagerWindow?

    static func present(onLibraryChanged: (() -> Void)? = nil) {
        if let existing = shared {
            existing.onLibraryChanged = onLibraryChanged
            existing.reload()
            existing.window?.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let controller = WatchFolderManagerWindow(onLibraryChanged: onLibraryChanged)
        shared = controller
        controller.window?.center()
        controller.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: - Init

    private init(onLibraryChanged: (() -> Void)?) {
        let w = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 310),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        w.title = "Manage Watch Folders"
        w.minSize = NSSize(width: 420, height: 240)
        super.init(window: w)
        self.onLibraryChanged = onLibraryChanged
        w.delegate = self
        setupUI()
        reload()
    }

    required init?(coder: NSCoder) { fatalError() }

    // MARK: - UI Setup

    private func setupUI() {
        guard let cv = window?.contentView else { return }

        // Bottom button bar (frame-based; autoresizingMask handles resize)
        let bh: CGFloat = 28, by: CGFloat = 12
        let gap: CGFloat = 8
        let cw: CGFloat = 560   // matches contentRect width

        let doneBtn  = makeButton("Done",            action: #selector(done))
        removeBtn    = makeButton("Remove...",      action: #selector(removeSelected))
        finderBtn    = makeButton("Show in Finder", action: #selector(showInFinder))
        rescanBtn    = makeButton("Rescan",         action: #selector(rescanSelected))
        let addBtn   = makeButton("Add Folder...",  action: #selector(addFolder))

        doneBtn.frame   = NSRect(x: cw - 20 - 80,                            y: by, width: 80,  height: bh)
        removeBtn.frame = NSRect(x: doneBtn.frame.minX - gap - 88,           y: by, width: 88,  height: bh)
        finderBtn.frame = NSRect(x: removeBtn.frame.minX - gap - 120,        y: by, width: 120, height: bh)
        rescanBtn.frame = NSRect(x: finderBtn.frame.minX - gap - 70,         y: by, width: 70,  height: bh)
        addBtn.frame    = NSRect(x: 20,                                       y: by, width: 100, height: bh)

        doneBtn.autoresizingMask   = [.minXMargin]
        removeBtn.autoresizingMask = [.minXMargin]
        finderBtn.autoresizingMask = [.minXMargin]
        rescanBtn.autoresizingMask = [.minXMargin]
        addBtn.autoresizingMask    = [.maxXMargin]

        for btn in [addBtn, rescanBtn!, finderBtn!, removeBtn!, doneBtn] {
            cv.addSubview(btn)
        }

        // Separator above buttons
        let sepY: CGFloat = by + bh + 8
        let sep = NSBox()
        sep.boxType = .separator
        sep.frame = NSRect(x: 0, y: sepY, width: cw, height: 1)
        sep.autoresizingMask = [.width]
        cv.addSubview(sep)

        // Scroll view + table filling the rest
        let tableTop: CGFloat = sepY + 2
        let scrollView = NSScrollView(
            frame: NSRect(x: 0, y: tableTop, width: cw, height: 310 - tableTop)
        )
        scrollView.autoresizingMask = [.width, .height]
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .noBorder

        let tv = NSTableView()
        tv.usesAlternatingRowBackgroundColors = true
        tv.rowHeight = 22

        let nameCol = NSTableColumn(identifier: .init("name"))
        nameCol.title = "Folder"
        nameCol.width = 150
        nameCol.minWidth = 80
        tv.addTableColumn(nameCol)

        let pathCol = NSTableColumn(identifier: .init("path"))
        pathCol.title = "Path"
        pathCol.width = 280
        pathCol.minWidth = 100
        tv.addTableColumn(pathCol)

        let itemsCol = NSTableColumn(identifier: .init("items"))
        itemsCol.title = "Items"
        itemsCol.width = 80
        itemsCol.minWidth = 60
        tv.addTableColumn(itemsCol)

        tv.dataSource = self
        tv.delegate = self
        tv.target = self
        tv.doubleAction = #selector(tableDoubleClicked)

        scrollView.documentView = tv
        cv.addSubview(scrollView)
        tableView = tv

        updateButtonStates()
    }

    private func makeButton(_ title: String, action: Selector) -> NSButton {
        let b = NSButton(title: title, target: self, action: action)
        b.bezelStyle = .rounded
        return b
    }

    // MARK: - Data

    private func reload() {
        // watchFolderSummaries() blocks on dataQueue.sync, which is held for extended
        // periods during import scans. Load off-main to avoid beachballing.
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let result = MediaLibrary.shared.watchFolderSummaries()
            DispatchQueue.main.async {
                self?.summaries = result
                self?.tableView?.reloadData()
                self?.updateButtonStates()
            }
        }
    }

    private func updateButtonStates() {
        let hasSelection = (tableView?.selectedRow ?? -1) >= 0
        rescanBtn?.isEnabled = hasSelection
        finderBtn?.isEnabled = hasSelection
        removeBtn?.isEnabled = hasSelection
    }

    // MARK: - NSTableViewDataSource

    func numberOfRows(in tableView: NSTableView) -> Int { summaries.count }

    // MARK: - NSTableViewDelegate

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard row < summaries.count else { return nil }
        let id = tableColumn?.identifier ?? .init("")
        var cell = tableView.makeView(withIdentifier: id, owner: self) as? NSTableCellView
        if cell == nil {
            cell = NSTableCellView()
            cell?.identifier = id
            let tf = NSTextField(labelWithString: "")
            tf.translatesAutoresizingMaskIntoConstraints = false
            cell?.addSubview(tf)
            cell?.textField = tf
            NSLayoutConstraint.activate([
                tf.leadingAnchor.constraint(equalTo: cell!.leadingAnchor, constant: 4),
                tf.trailingAnchor.constraint(equalTo: cell!.trailingAnchor, constant: -4),
                tf.centerYAnchor.constraint(equalTo: cell!.centerYAnchor),
            ])
        }
        let s = summaries[row]
        switch id.rawValue {
        case "name":
            cell?.textField?.stringValue = s.url.lastPathComponent
            cell?.textField?.lineBreakMode = .byTruncatingTail
        case "path":
            cell?.textField?.stringValue = s.url.path
            cell?.textField?.lineBreakMode = .byTruncatingMiddle
        case "items":
            let n = s.totalCount
            cell?.textField?.stringValue = "\(n) item\(n == 1 ? "" : "s")"
            cell?.textField?.lineBreakMode = .byTruncatingTail
        default: break
        }
        return cell
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        updateButtonStates()
    }

    // MARK: - Actions

    @objc private func addFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.message = "Select a folder to add to your library"
        let folderDelegate = TopLevelFolderPickerDelegate()
        panel.delegate = folderDelegate
        withExtendedLifetime(folderDelegate) {
            guard panel.runModal() == .OK, let url = panel.url else { return }
            MediaLibrary.shared.addWatchFolder(url)
            MediaLibrary.shared.scanFolder(url)
            onLibraryChanged?()
            reload()
        }
    }

    @objc private func rescanSelected() {
        let row = tableView.selectedRow
        guard row >= 0 && row < summaries.count else { return }
        MediaLibrary.shared.rescanWatchFolder(summaries[row].url, cleanMissing: true)
        onLibraryChanged?()
        reload()
    }

    @objc private func showInFinder() {
        let row = tableView.selectedRow
        guard row >= 0 && row < summaries.count else { return }
        NSWorkspace.shared.activateFileViewerSelecting([summaries[row].url])
    }

    @objc private func removeSelected() {
        let row = tableView.selectedRow
        guard row >= 0 && row < summaries.count else { return }
        let summary = summaries[row]
        let counts = MediaLibrary.shared.removalCountsForWatchFolder(summary.url)
        guard confirmRemoval(of: summary.url, removalCounts: counts) else { return }
        MediaLibrary.shared.removeWatchFolder(summary.url, removeEntries: true)
        onLibraryChanged?()
        reload()
    }

    @objc private func done() {
        window?.close()
    }

    @objc private func tableDoubleClicked() {
        let row = tableView.clickedRow
        guard row >= 0 && row < summaries.count else { return }
        NSWorkspace.shared.activateFileViewerSelecting([summaries[row].url])
    }

    // MARK: - Helpers

    private func confirmRemoval(
        of folderURL: URL,
        removalCounts: (tracks: Int, movies: Int, episodes: Int)
    ) -> Bool {
        let total = removalCounts.tracks + removalCounts.movies + removalCounts.episodes
        let alert = NSAlert()
        alert.messageText = "Remove Watched Folder?"
        alert.informativeText = """
        Folder:
        \(folderURL.path)

        This will stop watching this folder and remove \(total) local item\(total == 1 ? "" : "s") from the library (\(removalCounts.tracks) tracks, \(removalCounts.movies) movies, \(removalCounts.episodes) episodes).

        Files on disk will not be deleted.
        """
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Remove Folder")
        alert.addButton(withTitle: "Cancel")
        return alert.runModal() == .alertFirstButtonReturn
    }

    // MARK: - NSWindowDelegate

    func windowWillClose(_ notification: Notification) {
        WatchFolderManagerWindow.shared = nil
    }
}

// MARK: - Compatibility shim (preserves the existing call sites)

enum WatchFolderManagerDialog {
    static func present(onLibraryChanged: (() -> Void)? = nil) {
        WatchFolderManagerWindow.present(onLibraryChanged: onLibraryChanged)
    }
}
