import AppKit

/// Panel for bulk-editing album-level tags across all tracks in an album (in-app only)
class EditAlbumTagsPanel: NSWindow {

    // MARK: - Colors (matching TagsPanel)

    private struct Colors {
        static let background = NSColor(calibratedRed: 0.08, green: 0.08, blue: 0.12, alpha: 1.0)
        static let label = NSColor(calibratedRed: 0.0, green: 0.85, blue: 0.0, alpha: 1.0)
        static let dimLabel = NSColor(calibratedRed: 0.0, green: 0.5, blue: 0.0, alpha: 1.0)
        static let value = NSColor(calibratedRed: 0.9, green: 0.9, blue: 0.9, alpha: 1.0)
        static let fieldBg = NSColor(calibratedRed: 0.12, green: 0.12, blue: 0.18, alpha: 1.0)
    }

    // MARK: - State

    var onSave: (() -> Void)?
    private var album: Album

    private var albumNameField = NSTextField()
    private var albumArtistField = NSTextField()
    private var yearField = NSTextField()
    private var genreField = NSTextField()

    // MARK: - Init

    convenience init(album: Album) {
        let rect = NSRect(x: 0, y: 0, width: 420, height: 320)
        self.init(contentRect: rect,
                  styleMask: [.titled, .closable],
                  backing: .buffered,
                  defer: false)
        self.album = album
        title = "Edit Album Tags: \(album.name)"
        backgroundColor = Colors.background
        isReleasedWhenClosed = false
        buildUI()
    }

    override init(contentRect: NSRect, styleMask style: NSWindow.StyleMask,
                  backing backingStoreType: NSWindow.BackingStoreType, defer flag: Bool) {
        self.album = Album(id: "", name: "", artist: nil, year: nil, tracks: [])
        super.init(contentRect: contentRect, styleMask: style, backing: backingStoreType, defer: flag)
    }

    // MARK: - UI

    private func buildUI() {
        guard let cv = contentView else { return }
        cv.wantsLayer = true
        cv.layer?.backgroundColor = Colors.background.cgColor

        let first = album.tracks.first
        let artistName = album.artist ?? first?.artist ?? ""
        let trackCount = album.tracks.count

        let labelW: CGFloat = 110
        let fieldW: CGFloat = 270
        let paddingX: CGFloat = 16
        let rowH: CGFloat = 28
        let gap: CGFloat = 8
        let startY: CGFloat = 56 + 16

        struct Row { let label: String; let value: String; let editable: Bool }
        let rows: [Row] = [
            Row(label: "Artist",       value: artistName,                              editable: false),
            Row(label: "Tracks",       value: "\(trackCount) track\(trackCount == 1 ? "" : "s")", editable: false),
            Row(label: "Album Name",   value: album.name,                              editable: true),
            Row(label: "Album Artist", value: first?.albumArtist ?? "",                editable: true),
            Row(label: "Year",         value: first?.year.map(String.init) ?? "",      editable: true),
            Row(label: "Genre",        value: first?.genre ?? "",                      editable: true),
        ]

        let editableFields: [NSTextField] = [albumNameField, albumArtistField, yearField, genreField]
        var editableCount = 0

        for (i, row) in rows.enumerated() {
            let y = startY + CGFloat(rows.count - 1 - i) * (rowH + gap)

            let lbl = NSTextField(labelWithString: row.label + ":")
            lbl.frame = NSRect(x: paddingX, y: y + 5, width: labelW, height: 18)
            lbl.textColor = row.editable ? Colors.label : Colors.dimLabel
            lbl.font = NSFont.boldSystemFont(ofSize: 11)
            lbl.alignment = .right
            cv.addSubview(lbl)

            if row.editable {
                let field = editableFields[editableCount]
                configure(field: field, value: row.value)
                field.frame = NSRect(x: paddingX + labelW + 8, y: y + 3, width: fieldW, height: 22)
                cv.addSubview(field)
                editableCount += 1
            } else {
                let val = NSTextField(labelWithString: row.value)
                val.frame = NSRect(x: paddingX + labelW + 8, y: y + 5, width: fieldW, height: 18)
                val.textColor = Colors.value
                val.font = NSFont.systemFont(ofSize: 11)
                cv.addSubview(val)
            }
        }

        let cancelBtn = NSButton(title: "Cancel", target: self, action: #selector(cancelClicked))
        cancelBtn.bezelStyle = .rounded
        cancelBtn.frame = NSRect(x: 224, y: 14, width: 90, height: 28)
        cancelBtn.autoresizingMask = [.minXMargin]
        cv.addSubview(cancelBtn)

        let saveBtn = NSButton(title: "Save All Tracks", target: self, action: #selector(saveClicked))
        saveBtn.bezelStyle = .rounded
        saveBtn.frame = NSRect(x: 318, y: 14, width: 90, height: 28)
        saveBtn.autoresizingMask = [.minXMargin]
        saveBtn.keyEquivalent = "\r"
        cv.addSubview(saveBtn)
    }

    private func configure(field: NSTextField, value: String) {
        field.stringValue = value
        field.font = NSFont.systemFont(ofSize: 11)
        field.textColor = .black
        field.backgroundColor = .white
        field.drawsBackground = true
        field.isBezeled = true
        field.bezelStyle = .squareBezel
        field.isEditable = true
        field.isSelectable = true
    }

    // MARK: - Actions

    @objc private func saveClicked() {
        let newAlbumName = albumNameField.stringValue
        let newAlbumArtist = albumArtistField.stringValue.isEmpty ? nil : albumArtistField.stringValue
        let newYear = Int(yearField.stringValue)
        let newGenre = genreField.stringValue.isEmpty ? nil : genreField.stringValue

        for track in album.tracks {
            var updated = track
            if !newAlbumName.isEmpty { updated.album = newAlbumName }
            updated.albumArtist = newAlbumArtist
            updated.year = newYear
            updated.genre = newGenre
            MediaLibrary.shared.updateTrack(updated)
        }
        onSave?()
        close()
    }

    @objc private func cancelClicked() { close() }

    // MARK: - Presentation

    func show() {
        level = .modalPanel
        center()
        makeKeyAndOrderFront(nil)
    }
}
