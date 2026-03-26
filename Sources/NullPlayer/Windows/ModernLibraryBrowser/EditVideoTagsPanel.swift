import AppKit

/// Panel for editing metadata of a local video file (movie or episode).
/// In-app only — no file write-back.
class EditVideoTagsPanel: NSWindow {
    private let labelColumnWidth: CGFloat = 180

    enum VideoItem {
        case movie(LocalVideo)
        case episode(LocalEpisode)
    }

    var onSave: (() -> Void)?
    private var item: VideoItem
    private var fields: [String: NSTextField] = [:]

    convenience init(item: VideoItem) {
        self.init(
            contentRect: NSRect(x: 0, y: 0, width: 700, height: 460),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        self.item = item
        isReleasedWhenClosed = false
        minSize = NSSize(width: 560, height: 360)
        title = {
            switch item {
            case .movie(let m): return "Edit Movie: \(m.title)"
            case .episode(let e): return "Edit Episode: \(e.title)"
            }
        }()
        buildUI()
    }

    override init(contentRect: NSRect, styleMask style: NSWindow.StyleMask,
                  backing backingStoreType: NSWindow.BackingStoreType, defer flag: Bool) {
        self.item = .movie(LocalVideo(url: URL(fileURLWithPath: "/")))
        super.init(contentRect: contentRect, styleMask: style, backing: backingStoreType, defer: flag)
    }

    private func buildUI() {
        guard let cv = contentView else { return }

        let scrollView = NSScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.borderType = .bezelBorder
        cv.addSubview(scrollView)

        let formContainer = MetadataFormContainerView()
        formContainer.translatesAutoresizingMaskIntoConstraints = false
        scrollView.documentView = formContainer

        let grid = NSGridView()
        grid.translatesAutoresizingMaskIntoConstraints = false
        grid.rowSpacing = 8
        grid.columnSpacing = 12
        formContainer.addSubview(grid)
        NSLayoutConstraint.activate([
            formContainer.leadingAnchor.constraint(equalTo: scrollView.contentView.leadingAnchor),
            formContainer.trailingAnchor.constraint(equalTo: scrollView.contentView.trailingAnchor),
            formContainer.topAnchor.constraint(equalTo: scrollView.contentView.topAnchor),
            formContainer.bottomAnchor.constraint(greaterThanOrEqualTo: scrollView.contentView.bottomAnchor),
            formContainer.widthAnchor.constraint(equalTo: scrollView.contentView.widthAnchor),
            formContainer.heightAnchor.constraint(greaterThanOrEqualTo: scrollView.contentView.heightAnchor),
            grid.leadingAnchor.constraint(equalTo: formContainer.leadingAnchor),
            grid.trailingAnchor.constraint(equalTo: formContainer.trailingAnchor),
            grid.topAnchor.constraint(equalTo: formContainer.topAnchor),
            formContainer.bottomAnchor.constraint(greaterThanOrEqualTo: grid.bottomAnchor),
        ])

        switch item {
        case .movie(let movie):
            addReadOnlyRow(grid: grid, label: "File", value: movie.url.lastPathComponent)
            addReadOnlyRow(grid: grid, label: "Duration", value: movie.formattedDuration)
            addReadOnlyRow(grid: grid, label: "Date Added", value: formatDate(movie.dateAdded))
            addEditableRow(grid: grid, key: "title", label: "Title", value: movie.title)
            addEditableRow(grid: grid, key: "year", label: "Year", value: movie.year.map(String.init) ?? "")

        case .episode(let episode):
            addReadOnlyRow(grid: grid, label: "File", value: episode.url.lastPathComponent)
            addReadOnlyRow(grid: grid, label: "Duration", value: episode.formattedDuration)
            addReadOnlyRow(grid: grid, label: "Date Added", value: formatDate(episode.dateAdded))
            addEditableRow(grid: grid, key: "title", label: "Title", value: episode.title)
            addEditableRow(grid: grid, key: "showTitle", label: "Show Title", value: episode.showTitle)
            addEditableRow(grid: grid, key: "season", label: "Season #", value: String(episode.seasonNumber))
            addEditableRow(grid: grid, key: "episode", label: "Episode #", value: episode.episodeNumber.map(String.init) ?? "")
        }

        if grid.numberOfColumns > 1 {
            grid.column(at: 0).width = labelColumnWidth
            grid.column(at: 0).xPlacement = .trailing
            grid.column(at: 1).xPlacement = .fill
        }

        let actionRow = NSStackView()
        actionRow.translatesAutoresizingMaskIntoConstraints = false
        actionRow.orientation = .horizontal
        actionRow.alignment = .centerY
        actionRow.distribution = .fill
        actionRow.spacing = 8
        actionRow.addArrangedSubview(NSButton(title: "Cancel", target: self, action: #selector(cancelClicked)))
        let save = NSButton(title: "Save", target: self, action: #selector(saveClicked))
        save.keyEquivalent = "\r"
        actionRow.addArrangedSubview(save)
        cv.addSubview(actionRow)

        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: cv.leadingAnchor, constant: 16),
            scrollView.trailingAnchor.constraint(equalTo: cv.trailingAnchor, constant: -16),
            scrollView.topAnchor.constraint(equalTo: cv.topAnchor, constant: 16),
            scrollView.bottomAnchor.constraint(equalTo: actionRow.topAnchor, constant: -12),
            actionRow.leadingAnchor.constraint(equalTo: cv.leadingAnchor, constant: 16),
            actionRow.trailingAnchor.constraint(lessThanOrEqualTo: cv.trailingAnchor, constant: -16),
            actionRow.bottomAnchor.constraint(equalTo: cv.bottomAnchor, constant: -16)
        ])
    }

    private func addReadOnlyRow(grid: NSGridView, label: String, value: String) {
        let labelView = NSTextField(labelWithString: "\(label):")
        labelView.font = NSFont.boldSystemFont(ofSize: 12)
        labelView.textColor = .secondaryLabelColor
        labelView.alignment = .right
        labelView.translatesAutoresizingMaskIntoConstraints = false
        labelView.widthAnchor.constraint(equalToConstant: labelColumnWidth).isActive = true
        let valueView = NSTextField(labelWithString: value)
        valueView.font = NSFont.systemFont(ofSize: 12)
        valueView.lineBreakMode = .byTruncatingMiddle
        valueView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        grid.addRow(with: [labelView, valueView])
    }

    private func addEditableRow(grid: NSGridView, key: String, label: String, value: String) {
        let labelView = NSTextField(labelWithString: "\(label):")
        labelView.font = NSFont.boldSystemFont(ofSize: 12)
        labelView.alignment = .right
        labelView.translatesAutoresizingMaskIntoConstraints = false
        labelView.widthAnchor.constraint(equalToConstant: labelColumnWidth).isActive = true
        let field = NSTextField(string: value)
        field.setContentHuggingPriority(.defaultLow, for: .horizontal)
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        fields[key] = field
        grid.addRow(with: [labelView, field])
    }

    @objc private func saveClicked() {
        switch item {
        case .movie(var movie):
            movie.title = fields["title"]?.stringValue.trimmingCharacters(in: .whitespacesAndNewlines) ?? movie.title
            movie.year = intValue("year", fallback: movie.year)
            MediaLibrary.shared.updateMovie(movie)

        case .episode(var episode):
            episode.title = fields["title"]?.stringValue.trimmingCharacters(in: .whitespacesAndNewlines) ?? episode.title
            episode.showTitle = fields["showTitle"]?.stringValue.trimmingCharacters(in: .whitespacesAndNewlines) ?? episode.showTitle
            if let season = intValue("season", fallback: episode.seasonNumber) { episode.seasonNumber = season }
            episode.episodeNumber = intValue("episode", fallback: episode.episodeNumber)
            MediaLibrary.shared.updateEpisode(episode)
        }
        onSave?()
        close()
    }

    @objc private func cancelClicked() {
        close()
    }

    private func nonEmpty(_ key: String) -> String? {
        guard let text = fields[key]?.stringValue.trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty else { return nil }
        return text
    }

    /// Returns the parsed integer from the field, or nil if the field is blank.
    /// If the field contains non-numeric text, returns `fallback` to avoid silently clearing
    /// a previously-set value due to a typo.
    private func intValue(_ key: String, fallback: Int? = nil) -> Int? {
        guard let raw = fields[key]?.stringValue.trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty else { return nil }
        return Int(raw) ?? fallback
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    func show() {
        level = .modalPanel
        center()
        makeKeyAndOrderFront(nil)
    }
}
