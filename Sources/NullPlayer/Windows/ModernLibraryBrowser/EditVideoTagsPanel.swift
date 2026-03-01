import AppKit

/// Panel for editing metadata of a local video file (movie or episode).
/// In-app only — no file write-back.
class EditVideoTagsPanel: NSWindow {

    // MARK: - Video item type

    enum VideoItem {
        case movie(LocalVideo)
        case episode(LocalEpisode)
    }

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
    private var item: VideoItem

    // Movie fields
    private var movieTitleField: NSTextField?
    private var movieYearField: NSTextField?

    // Episode fields
    private var epTitleField: NSTextField?
    private var epShowTitleField: NSTextField?
    private var epSeasonField: NSTextField?
    private var epEpisodeField: NSTextField?

    // MARK: - Init

    convenience init(item: VideoItem) {
        let rect = NSRect(x: 0, y: 0, width: 440, height: 340)
        self.init(contentRect: rect,
                  styleMask: [.titled, .closable],
                  backing: .buffered,
                  defer: false)
        self.item = item
        setupWindow()
        buildUI()
    }

    override init(contentRect: NSRect, styleMask style: NSWindow.StyleMask,
                  backing backingStoreType: NSWindow.BackingStoreType, defer flag: Bool) {
        self.item = .movie(LocalVideo(url: URL(fileURLWithPath: "/")))
        super.init(contentRect: contentRect, styleMask: style, backing: backingStoreType, defer: flag)
    }

    private func setupWindow() {
        switch item {
        case .movie(let m): title = "Edit Movie: \(m.title)"
        case .episode(let e): title = "Edit Episode: \(e.title)"
        }
        backgroundColor = Colors.background
        isReleasedWhenClosed = false
        isMovableByWindowBackground = true
        center()
    }

    // MARK: - UI

    private func buildUI() {
        guard let cv = contentView else { return }
        cv.wantsLayer = true
        cv.layer?.backgroundColor = Colors.background.cgColor

        switch item {
        case .movie(let movie):   buildMovieUI(in: cv, movie: movie)
        case .episode(let ep):    buildEpisodeUI(in: cv, episode: ep)
        }
    }

    private func buildMovieUI(in cv: NSView, movie: LocalVideo) {
        let readRows: [(String, String)] = [
            ("File",       movie.url.lastPathComponent),
            ("Duration",   movie.formattedDuration),
            ("Date Added", formatDate(movie.dateAdded)),
        ]
        let editRows: [(String, String)] = [
            ("Title", movie.title),
            ("Year",  movie.year.map(String.init) ?? ""),
        ]
        layoutRows(in: cv, readRows: readRows, editRows: editRows) { [weak self] fields in
            self?.movieTitleField = fields[0]
            self?.movieYearField  = fields[1]
        }
    }

    private func buildEpisodeUI(in cv: NSView, episode: LocalEpisode) {
        let readRows: [(String, String)] = [
            ("File",       episode.url.lastPathComponent),
            ("Duration",   episode.formattedDuration),
            ("Date Added", formatDate(episode.dateAdded)),
        ]
        let editRows: [(String, String)] = [
            ("Title",      episode.title),
            ("Show Title", episode.showTitle),
            ("Season #",   String(episode.seasonNumber)),
            ("Episode #",  episode.episodeNumber.map(String.init) ?? ""),
        ]
        layoutRows(in: cv, readRows: readRows, editRows: editRows) { [weak self] fields in
            self?.epTitleField      = fields[0]
            self?.epShowTitleField  = fields[1]
            self?.epSeasonField     = fields[2]
            self?.epEpisodeField    = fields[3]
        }
    }

    private func layoutRows(in cv: NSView,
                            readRows: [(String, String)],
                            editRows: [(String, String)],
                            assignFields: ([NSTextField]) -> Void) {
        let labelW: CGFloat = 100
        let fieldW: CGFloat = 300
        let paddingX: CGFloat = 16
        let rowH: CGFloat = 28
        let gap: CGFloat = 8
        let totalRows = readRows.count + editRows.count
        var rowIndex = 0
        var editFields: [NSTextField] = []

        for (label, value) in readRows {
            let y = CGFloat(totalRows - 1 - rowIndex) * (rowH + gap) + 56 + 16
            addLabel(to: cv, text: label + ":", x: paddingX, y: y + 5, w: labelW, editable: false)
            addReadValue(to: cv, text: value, x: paddingX + labelW + 8, y: y + 5, w: fieldW)
            rowIndex += 1
        }

        for (label, value) in editRows {
            let y = CGFloat(totalRows - 1 - rowIndex) * (rowH + gap) + 56 + 16
            addLabel(to: cv, text: label + ":", x: paddingX, y: y + 5, w: labelW, editable: true)
            let field = makeEditableField(value: value)
            field.frame = NSRect(x: paddingX + labelW + 8, y: y + 3, width: fieldW, height: 22)
            cv.addSubview(field)
            editFields.append(field)
            rowIndex += 1
        }

        assignFields(editFields)

        // Buttons
        let cancelBtn = NSButton(title: "Cancel", target: self, action: #selector(cancelClicked))
        cancelBtn.bezelStyle = .rounded
        cancelBtn.frame = NSRect(x: 238, y: 14, width: 90, height: 28)
        cancelBtn.autoresizingMask = [.minXMargin]
        cv.addSubview(cancelBtn)

        let saveBtn = NSButton(title: "Save", target: self, action: #selector(saveClicked))
        saveBtn.bezelStyle = .rounded
        saveBtn.frame = NSRect(x: 332, y: 14, width: 90, height: 28)
        saveBtn.autoresizingMask = [.minXMargin]
        saveBtn.keyEquivalent = "\r"
        cv.addSubview(saveBtn)
    }

    private func addLabel(to view: NSView, text: String, x: CGFloat, y: CGFloat, w: CGFloat, editable: Bool) {
        let lbl = NSTextField(labelWithString: text)
        lbl.frame = NSRect(x: x, y: y, width: w, height: 18)
        lbl.textColor = editable ? Colors.label : Colors.dimLabel
        lbl.font = NSFont.boldSystemFont(ofSize: 11)
        lbl.alignment = .right
        view.addSubview(lbl)
    }

    private func addReadValue(to view: NSView, text: String, x: CGFloat, y: CGFloat, w: CGFloat) {
        let lbl = NSTextField(labelWithString: text)
        lbl.frame = NSRect(x: x, y: y, width: w, height: 18)
        lbl.textColor = Colors.value
        lbl.font = NSFont.systemFont(ofSize: 11)
        lbl.lineBreakMode = .byTruncatingMiddle
        view.addSubview(lbl)
    }

    private func makeEditableField(value: String) -> NSTextField {
        let field = NSTextField(string: value)
        field.font = NSFont.systemFont(ofSize: 11)
        field.textColor = .black
        field.backgroundColor = .white
        field.drawsBackground = true
        field.isBezeled = true
        field.bezelStyle = .squareBezel
        field.isEditable = true
        field.isSelectable = true
        return field
    }

    // MARK: - Actions

    @objc private func saveClicked() {
        switch item {
        case .movie(var m):
            if let titleField = movieTitleField, !titleField.stringValue.isEmpty {
                m.title = titleField.stringValue
            }
            m.year = movieYearField.flatMap { Int($0.stringValue) }
            MediaLibrary.shared.updateMovie(m)

        case .episode(var e):
            if let titleField = epTitleField, !titleField.stringValue.isEmpty {
                e.title = titleField.stringValue
            }
            if let showField = epShowTitleField, !showField.stringValue.isEmpty {
                e.showTitle = showField.stringValue
            }
            if let seasonField = epSeasonField, let season = Int(seasonField.stringValue) {
                e.seasonNumber = season
            }
            e.episodeNumber = epEpisodeField.flatMap { Int($0.stringValue) }
            MediaLibrary.shared.updateEpisode(e)
        }
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
