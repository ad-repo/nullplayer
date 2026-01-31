import AppKit

/// Panel for displaying full metadata/tags of a local track
class TagsPanel: NSWindow, NSWindowDelegate {
    
    // MARK: - Properties
    
    private var contentBox: NSView!
    private var scrollView: NSScrollView!
    private var tableView: NSTableView!
    private var closeButton: NSButton!
    
    private var tagData: [(key: String, value: String)] = []
    
    // MARK: - Colors (Winamp-inspired)
    
    private struct Colors {
        static let background = NSColor(calibratedRed: 0.08, green: 0.08, blue: 0.12, alpha: 1.0)
        static let textNormal = NSColor(calibratedRed: 0.0, green: 0.85, blue: 0.0, alpha: 1.0)
        static let textDim = NSColor(calibratedRed: 0.0, green: 0.5, blue: 0.0, alpha: 1.0)
        static let textValue = NSColor(calibratedRed: 0.9, green: 0.9, blue: 0.9, alpha: 1.0)
        static let rowAlt = NSColor(calibratedRed: 0.1, green: 0.1, blue: 0.15, alpha: 1.0)
        static let border = NSColor(calibratedRed: 0.3, green: 0.3, blue: 0.4, alpha: 1.0)
    }
    
    // MARK: - Initialization
    
    convenience init(track: LibraryTrack) {
        let contentRect = NSRect(x: 0, y: 0, width: 450, height: 500)
        self.init(contentRect: contentRect,
                  styleMask: [.titled, .closable, .resizable],
                  backing: .buffered,
                  defer: false)
        
        setupWindow()
        setupUI()
        loadTagData(from: track)
    }
    
    private func setupWindow() {
        title = "File Tags"
        backgroundColor = Colors.background
        isReleasedWhenClosed = false  // Prevent release during animations
        minSize = NSSize(width: 350, height: 300)
        center()
    }
    
    private func setupUI() {
        contentBox = NSView(frame: contentView!.bounds)
        contentBox.autoresizingMask = [.width, .height]
        contentBox.wantsLayer = true
        contentBox.layer?.backgroundColor = Colors.background.cgColor
        contentView?.addSubview(contentBox)
        
        // Scroll view with table
        scrollView = NSScrollView(frame: NSRect(x: 10, y: 50, width: 430, height: 440))
        scrollView.autoresizingMask = [.width, .height]
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.borderType = .lineBorder
        scrollView.backgroundColor = Colors.background
        scrollView.drawsBackground = true
        contentBox.addSubview(scrollView)
        
        // Table view
        tableView = NSTableView()
        tableView.backgroundColor = Colors.background
        tableView.gridStyleMask = .solidHorizontalGridLineMask
        tableView.gridColor = Colors.border.withAlphaComponent(0.3)
        tableView.rowHeight = 22
        tableView.intercellSpacing = NSSize(width: 10, height: 2)
        tableView.headerView = nil  // No header
        tableView.delegate = self
        tableView.dataSource = self
        
        // Key column
        let keyColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("key"))
        keyColumn.title = "Tag"
        keyColumn.width = 120
        keyColumn.minWidth = 80
        keyColumn.maxWidth = 200
        tableView.addTableColumn(keyColumn)
        
        // Value column
        let valueColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("value"))
        valueColumn.title = "Value"
        valueColumn.width = 300
        valueColumn.minWidth = 150
        tableView.addTableColumn(valueColumn)
        
        scrollView.documentView = tableView
        
        // Close button
        closeButton = NSButton(title: "Close", target: self, action: #selector(closeClicked))
        closeButton.bezelStyle = .rounded
        closeButton.frame = NSRect(x: 350, y: 10, width: 90, height: 32)
        closeButton.autoresizingMask = [.minXMargin]
        contentBox.addSubview(closeButton)
    }
    
    // MARK: - Data Loading
    
    private func loadTagData(from track: LibraryTrack) {
        tagData = []
        
        // File info
        tagData.append(("File", track.url.lastPathComponent))
        tagData.append(("Path", track.url.deletingLastPathComponent().path))
        tagData.append(("File Size", formatFileSize(track.fileSize)))
        
        // Basic metadata
        tagData.append(("Title", track.title))
        
        if let artist = track.artist, !artist.isEmpty {
            tagData.append(("Artist", artist))
        }
        
        if let album = track.album, !album.isEmpty {
            tagData.append(("Album", album))
        }
        
        if let albumArtist = track.albumArtist, !albumArtist.isEmpty {
            tagData.append(("Album Artist", albumArtist))
        }
        
        if let genre = track.genre, !genre.isEmpty {
            tagData.append(("Genre", genre))
        }
        
        if let year = track.year {
            tagData.append(("Year", String(year)))
        }
        
        if let trackNumber = track.trackNumber {
            tagData.append(("Track Number", String(trackNumber)))
        }
        
        if let discNumber = track.discNumber {
            tagData.append(("Disc Number", String(discNumber)))
        }
        
        // Audio properties
        tagData.append(("Duration", formatDuration(track.duration)))
        
        if let bitrate = track.bitrate, bitrate > 0 {
            tagData.append(("Bitrate", "\(bitrate) kbps"))
        }
        
        if let sampleRate = track.sampleRate, sampleRate > 0 {
            tagData.append(("Sample Rate", formatSampleRate(sampleRate)))
        }
        
        if let channels = track.channels, channels > 0 {
            tagData.append(("Channels", formatChannels(channels)))
        }
        
        // Library info
        tagData.append(("Date Added", formatDate(track.dateAdded)))
        
        if let lastPlayed = track.lastPlayed {
            tagData.append(("Last Played", formatDate(lastPlayed)))
        }
        
        tagData.append(("Play Count", String(track.playCount)))
        
        // Internal ID
        tagData.append(("Library ID", track.id.uuidString))
        
        title = "Tags: \(track.title)"
        tableView.reloadData()
    }
    
    // MARK: - Formatting Helpers
    
    private func formatFileSize(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
    
    private func formatDuration(_ seconds: TimeInterval) -> String {
        let hours = Int(seconds) / 3600
        let minutes = (Int(seconds) % 3600) / 60
        let secs = Int(seconds) % 60
        
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        }
        return String(format: "%d:%02d", minutes, secs)
    }
    
    private func formatSampleRate(_ rate: Int) -> String {
        if rate >= 1000 {
            let khz = Double(rate) / 1000.0
            if khz.truncatingRemainder(dividingBy: 1) == 0 {
                return "\(Int(khz)) kHz"
            }
            return String(format: "%.1f kHz", khz)
        }
        return "\(rate) Hz"
    }
    
    private func formatChannels(_ count: Int) -> String {
        switch count {
        case 1: return "Mono"
        case 2: return "Stereo"
        case 6: return "5.1 Surround"
        case 8: return "7.1 Surround"
        default: return "\(count) channels"
        }
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
    
    // MARK: - Actions
    
    @objc private func closeClicked() {
        close()
    }
    
    // MARK: - Presentation
    
    func show() {
        self.level = .modalPanel  // Ensure dialog appears above floating windows
        center()
        makeKeyAndOrderFront(nil)
    }
}

// MARK: - NSTableViewDataSource

extension TagsPanel: NSTableViewDataSource {
    
    func numberOfRows(in tableView: NSTableView) -> Int {
        return tagData.count
    }
}

// MARK: - NSTableViewDelegate

extension TagsPanel: NSTableViewDelegate {
    
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard row < tagData.count else { return nil }
        
        let item = tagData[row]
        let isKeyColumn = tableColumn?.identifier.rawValue == "key"
        
        let identifier = NSUserInterfaceItemIdentifier(isKeyColumn ? "KeyCell" : "ValueCell")
        
        var cellView = tableView.makeView(withIdentifier: identifier, owner: nil) as? NSTableCellView
        
        if cellView == nil {
            cellView = NSTableCellView()
            cellView?.identifier = identifier
            
            let textField = NSTextField(labelWithString: "")
            textField.translatesAutoresizingMaskIntoConstraints = false
            textField.lineBreakMode = .byTruncatingTail
            textField.cell?.truncatesLastVisibleLine = true
            
            cellView?.addSubview(textField)
            cellView?.textField = textField
            
            NSLayoutConstraint.activate([
                textField.leadingAnchor.constraint(equalTo: cellView!.leadingAnchor, constant: 4),
                textField.trailingAnchor.constraint(equalTo: cellView!.trailingAnchor, constant: -4),
                textField.centerYAnchor.constraint(equalTo: cellView!.centerYAnchor)
            ])
        }
        
        if isKeyColumn {
            cellView?.textField?.stringValue = item.key
            cellView?.textField?.textColor = Colors.textNormal
            cellView?.textField?.font = NSFont.boldSystemFont(ofSize: 11)
        } else {
            cellView?.textField?.stringValue = item.value
            cellView?.textField?.textColor = Colors.textValue
            cellView?.textField?.font = NSFont.systemFont(ofSize: 11)
        }
        
        return cellView
    }
    
    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        let rowView = NSTableRowView()
        rowView.backgroundColor = row % 2 == 0 ? Colors.background : Colors.rowAlt
        return rowView
    }
}
