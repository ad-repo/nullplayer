import AppKit

/// Panel for editing metadata tags of a local audio track (in-app only, no file write-back)
class EditTagsPanel: NSWindow {

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
    private var track: LibraryTrack

    private var titleField = NSTextField()
    private var artistField = NSTextField()
    private var albumField = NSTextField()
    private var albumArtistField = NSTextField()
    private var genreField = NSTextField()
    private var yearField = NSTextField()
    private var trackNumField = NSTextField()
    private var discNumField = NSTextField()

    // MARK: - Init

    convenience init(track: LibraryTrack) {
        let rect = NSRect(x: 0, y: 0, width: 460, height: 480)
        self.init(contentRect: rect,
                  styleMask: [.titled, .closable],
                  backing: .buffered,
                  defer: false)
        self.track = track
        title = "Edit Tags: \(track.title)"
        backgroundColor = Colors.background
        isReleasedWhenClosed = false
        buildUI()
    }

    override init(contentRect: NSRect, styleMask style: NSWindow.StyleMask,
                  backing backingStoreType: NSWindow.BackingStoreType, defer flag: Bool) {
        self.track = LibraryTrack(url: URL(fileURLWithPath: "/"))
        super.init(contentRect: contentRect, styleMask: style, backing: backingStoreType, defer: flag)
    }

    // MARK: - UI

    private func buildUI() {
        guard let cv = contentView else { return }
        cv.wantsLayer = true
        cv.layer?.backgroundColor = Colors.background.cgColor

        let labelW: CGFloat = 110
        let fieldW: CGFloat = 310
        let paddingX: CGFloat = 16
        let rowH: CGFloat = 28
        let gap: CGFloat = 8
        let startY: CGFloat = 56 + 16

        struct Row { let label: String; let value: String; let editable: Bool }
        let rows: [Row] = [
            Row(label: "File",         value: track.url.lastPathComponent,              editable: false),
            Row(label: "Duration",     value: track.formattedDuration,                  editable: false),
            Row(label: "Date Added",   value: formatDate(track.dateAdded),              editable: false),
            Row(label: "Title",        value: track.title,                              editable: true),
            Row(label: "Artist",       value: track.artist ?? "",                       editable: true),
            Row(label: "Album",        value: track.album ?? "",                        editable: true),
            Row(label: "Album Artist", value: track.albumArtist ?? "",                  editable: true),
            Row(label: "Genre",        value: track.genre ?? "",                        editable: true),
            Row(label: "Year",         value: track.year.map(String.init) ?? "",        editable: true),
            Row(label: "Track #",      value: track.trackNumber.map(String.init) ?? "", editable: true),
            Row(label: "Disc #",       value: track.discNumber.map(String.init) ?? "",  editable: true),
        ]

        var editableCount = 0
        let editableFields: [NSTextField] = [
            titleField, artistField, albumField, albumArtistField,
            genreField, yearField, trackNumField, discNumField,
        ]

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
                val.lineBreakMode = .byTruncatingMiddle
                cv.addSubview(val)
            }
        }

        let cancelBtn = NSButton(title: "Cancel", target: self, action: #selector(cancelClicked))
        cancelBtn.bezelStyle = .rounded
        cancelBtn.frame = NSRect(x: 250, y: 14, width: 90, height: 28)
        cancelBtn.autoresizingMask = [.minXMargin]
        cv.addSubview(cancelBtn)

        let saveBtn = NSButton(title: "Save", target: self, action: #selector(saveClicked))
        saveBtn.bezelStyle = .rounded
        saveBtn.frame = NSRect(x: 354, y: 14, width: 90, height: 28)
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
        var updated = track
        updated.title = titleField.stringValue.isEmpty ? track.title : titleField.stringValue
        updated.artist = artistField.stringValue.isEmpty ? nil : artistField.stringValue
        updated.album = albumField.stringValue.isEmpty ? nil : albumField.stringValue
        updated.albumArtist = albumArtistField.stringValue.isEmpty ? nil : albumArtistField.stringValue
        updated.genre = genreField.stringValue.isEmpty ? nil : genreField.stringValue
        updated.year = Int(yearField.stringValue)
        updated.trackNumber = Int(trackNumField.stringValue)
        updated.discNumber = Int(discNumField.stringValue)
        MediaLibrary.shared.updateTrack(updated)
        onSave?()
        close()
    }

    @objc private func cancelClicked() { close() }

    // MARK: - Helpers

    private func formatDate(_ date: Date) -> String {
        let f = DateFormatter(); f.dateStyle = .medium; f.timeStyle = .short
        return f.string(from: date)
    }

    // MARK: - Presentation

    func show() {
        level = .modalPanel
        center()
        makeKeyAndOrderFront(nil)
    }
}
