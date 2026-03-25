import AppKit

/// Panel for editing metadata tags of a local audio track (in-app only, no file write-back)
class EditTagsPanel: NSWindow {
    private let artworkSize: CGFloat = 220
    private let labelColumnWidth: CGFloat = 190

    private enum Field: CaseIterable {
        case title
        case artist
        case album
        case albumArtist
        case genre
        case year
        case trackNumber
        case discNumber
        case composer
        case comment
        case grouping
        case bpm
        case musicalKey
        case isrc
        case copyright
        case mbRecordingID
        case mbReleaseID
        case discogsReleaseID
        case discogsMasterID
        case discogsLabel
        case discogsCatalogNumber
        case artworkURL

        var label: String {
            switch self {
            case .title: return "Title"
            case .artist: return "Artist"
            case .album: return "Album"
            case .albumArtist: return "Album Artist"
            case .genre: return "Genre"
            case .year: return "Year"
            case .trackNumber: return "Track #"
            case .discNumber: return "Disc #"
            case .composer: return "Composer"
            case .comment: return "Comment"
            case .grouping: return "Grouping"
            case .bpm: return "BPM"
            case .musicalKey: return "Key"
            case .isrc: return "ISRC"
            case .copyright: return "Copyright"
            case .mbRecordingID: return "MB Recording ID"
            case .mbReleaseID: return "MB Release ID"
            case .discogsReleaseID: return "Discogs Release ID"
            case .discogsMasterID: return "Discogs Master ID"
            case .discogsLabel: return "Discogs Label"
            case .discogsCatalogNumber: return "Discogs Catalog #"
            case .artworkURL: return "Artwork URL"
            }
        }
    }

    var onSave: (() -> Void)?
    private var track: LibraryTrack
    private var fields: [Field: NSTextField] = [:]
    private var autoTagButton = NSButton(title: "Auto-Tag", target: nil, action: nil)
    private let artworkImageView = NSImageView()
    private let artworkPlaceholderLabel = NSTextField(labelWithString: "No Artwork")

    convenience init(track: LibraryTrack) {
        self.init(
            contentRect: NSRect(x: 0, y: 0, width: 760, height: 700),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        self.track = track
        title = "Edit Tags: \(track.title)"
        isReleasedWhenClosed = false
        minSize = NSSize(width: 640, height: 460)
        buildUI()
    }

    override init(contentRect: NSRect, styleMask style: NSWindow.StyleMask,
                  backing backingStoreType: NSWindow.BackingStoreType, defer flag: Bool) {
        self.track = LibraryTrack(url: URL(fileURLWithPath: "/"))
        super.init(contentRect: contentRect, styleMask: style, backing: backingStoreType, defer: flag)
    }

    private func buildUI() {
        guard let cv = contentView else { return }

        let artworkFrame = NSView()
        artworkFrame.translatesAutoresizingMaskIntoConstraints = false
        artworkFrame.wantsLayer = true
        artworkFrame.layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
        artworkFrame.layer?.borderColor = NSColor.separatorColor.cgColor
        artworkFrame.layer?.borderWidth = 1
        artworkFrame.layer?.cornerRadius = 10
        cv.addSubview(artworkFrame)

        artworkImageView.translatesAutoresizingMaskIntoConstraints = false
        artworkImageView.imageAlignment = .alignCenter
        artworkImageView.imageScaling = .scaleProportionallyUpOrDown
        artworkImageView.wantsLayer = true
        artworkImageView.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        artworkImageView.layer?.cornerRadius = 8
        artworkImageView.layer?.masksToBounds = true
        artworkFrame.addSubview(artworkImageView)

        artworkPlaceholderLabel.translatesAutoresizingMaskIntoConstraints = false
        artworkPlaceholderLabel.alignment = .center
        artworkPlaceholderLabel.textColor = .secondaryLabelColor
        artworkPlaceholderLabel.font = NSFont.systemFont(ofSize: 13, weight: .medium)
        artworkFrame.addSubview(artworkPlaceholderLabel)

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
            artworkImageView.leadingAnchor.constraint(equalTo: artworkFrame.leadingAnchor, constant: 12),
            artworkImageView.trailingAnchor.constraint(equalTo: artworkFrame.trailingAnchor, constant: -12),
            artworkImageView.topAnchor.constraint(equalTo: artworkFrame.topAnchor, constant: 12),
            artworkImageView.bottomAnchor.constraint(equalTo: artworkFrame.bottomAnchor, constant: -12),
            artworkPlaceholderLabel.centerXAnchor.constraint(equalTo: artworkImageView.centerXAnchor),
            artworkPlaceholderLabel.centerYAnchor.constraint(equalTo: artworkImageView.centerYAnchor),
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

        addReadOnlyRow(grid: grid, label: "File", value: track.url.lastPathComponent)
        addReadOnlyRow(grid: grid, label: "Duration", value: track.formattedDuration)
        addReadOnlyRow(grid: grid, label: "Date Added", value: formatDate(track.dateAdded))

        for field in Field.allCases {
            let value = value(for: field)
            let textField = NSTextField(string: value)
            textField.font = NSFont.systemFont(ofSize: 12)
            fields[field] = textField
            addEditableRow(grid: grid, label: field.label, field: textField)
        }

        if grid.numberOfColumns > 1 {
            grid.column(at: 0).width = labelColumnWidth
            grid.column(at: 0).xPlacement = .trailing
            grid.column(at: 1).xPlacement = .fill
        }

        let actions = NSStackView()
        actions.translatesAutoresizingMaskIntoConstraints = false
        actions.orientation = .horizontal
        actions.alignment = .centerY
        actions.distribution = .fill
        actions.spacing = 8

        let cancelButton = NSButton(title: "Cancel", target: self, action: #selector(cancelClicked))
        autoTagButton = NSButton(title: "Auto-Tag", target: self, action: #selector(autoTagClicked))
        let saveButton = NSButton(title: "Save", target: self, action: #selector(saveClicked))
        saveButton.keyEquivalent = "\r"
        actions.addArrangedSubview(cancelButton)
        actions.addArrangedSubview(autoTagButton)
        actions.addArrangedSubview(saveButton)
        cv.addSubview(actions)
        actions.setHuggingPriority(.required, for: .vertical)
        actions.setContentCompressionResistancePriority(.required, for: .vertical)

        NSLayoutConstraint.activate([
            artworkFrame.leadingAnchor.constraint(equalTo: cv.leadingAnchor, constant: 16),
            artworkFrame.topAnchor.constraint(equalTo: cv.topAnchor, constant: 16),
            artworkFrame.widthAnchor.constraint(equalToConstant: artworkSize + 24),
            artworkFrame.heightAnchor.constraint(equalToConstant: artworkSize + 24),
            scrollView.leadingAnchor.constraint(equalTo: artworkFrame.trailingAnchor, constant: 16),
            scrollView.trailingAnchor.constraint(equalTo: cv.trailingAnchor, constant: -16),
            scrollView.topAnchor.constraint(equalTo: cv.topAnchor, constant: 16),
            scrollView.bottomAnchor.constraint(equalTo: actions.topAnchor, constant: -12),
            actions.leadingAnchor.constraint(equalTo: cv.leadingAnchor, constant: 16),
            actions.trailingAnchor.constraint(lessThanOrEqualTo: cv.trailingAnchor, constant: -16),
            actions.bottomAnchor.constraint(equalTo: cv.bottomAnchor, constant: -16)
        ])

        loadArtworkPreview()
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
        valueView.maximumNumberOfLines = 1
        valueView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        grid.addRow(with: [labelView, valueView])
    }

    private func addEditableRow(grid: NSGridView, label: String, field: NSTextField) {
        let labelView = NSTextField(labelWithString: "\(label):")
        labelView.font = NSFont.boldSystemFont(ofSize: 12)
        labelView.textColor = .labelColor
        labelView.alignment = .right
        labelView.translatesAutoresizingMaskIntoConstraints = false
        labelView.widthAnchor.constraint(equalToConstant: labelColumnWidth).isActive = true
        field.translatesAutoresizingMaskIntoConstraints = false
        field.setContentHuggingPriority(.defaultLow, for: .horizontal)
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        grid.addRow(with: [labelView, field])
    }

    @objc private func saveClicked() {
        commitPendingEdits()
        track = trackFromForm()
        NSLog("[MetadataDebug] track-save url=%@ title=%@ artist=%@ album=%@ albumArtist=%@",
              track.url.absoluteString,
              track.title,
              track.artist ?? "nil",
              track.album ?? "nil",
              track.albumArtist ?? "nil")
        MediaLibrary.shared.updateTrack(track)
        onSave?()
        close()
    }

    @objc private func cancelClicked() {
        close()
    }

    @objc private func autoTagClicked() {
        commitPendingEdits()
        let draft = trackFromForm()
        autoTagButton.isEnabled = false
        Task { [weak self] in
            guard let self else { return }
            let candidates = await AutoTaggingService.shared.searchTrackCandidates(for: draft)
            await MainActor.run {
                self.autoTagButton.isEnabled = true
                self.presentTrackAutoTag(candidates: candidates, baseTrack: draft)
            }
        }
    }

    @MainActor
    private func presentTrackAutoTag(candidates: [AutoTagTrackCandidate], baseTrack: LibraryTrack) {
        guard !candidates.isEmpty else {
            showInfoAlert(title: "Auto-Tag", message: "No metadata matches found from Discogs/MusicBrainz.")
            return
        }

        guard let selected = selectTrackCandidate(candidates) else { return }
        let patchedTrack = selected.patch.applying(to: baseTrack)
        let changes = diffLines(before: baseTrack, after: patchedTrack).prefix(24)
        guard !changes.isEmpty else {
            showInfoAlert(title: "Auto-Tag", message: "Selected candidate does not change any editable fields.")
            return
        }

        let preview = changes.joined(separator: "\n")
        let previewAlert = NSAlert()
        previewAlert.messageText = "Apply Auto-Tag Changes?"
        previewAlert.informativeText = preview
        previewAlert.alertStyle = .informational
        previewAlert.addButton(withTitle: "Apply")
        previewAlert.addButton(withTitle: "Cancel")
        guard previewAlert.runModal() == .alertFirstButtonReturn else { return }
        NSLog("[MetadataDebug] track-apply-candidate id=%@ title=%@ artist=%@ album=%@ albumArtist=%@",
              selected.id,
              selected.patch.title ?? "nil",
              selected.patch.artist ?? "nil",
              selected.patch.album ?? "nil",
              selected.patch.albumArtist ?? "nil")
        applyPatchToForm(selected.patch)
    }

    private func selectTrackCandidate(_ candidates: [AutoTagTrackCandidate]) -> AutoTagTrackCandidate? {
        let alert = NSAlert()
        alert.messageText = "Select Metadata Candidate"
        alert.informativeText = "Review up to 5 matches from Discogs and MusicBrainz, then choose the best metadata."
        alert.addButton(withTitle: "Continue")
        alert.addButton(withTitle: "Cancel")

        let summaries = candidates.map { candidate in
            let providerLabel = candidate.providers.map(\.rawValue).sorted().joined(separator: "+")
            let confidence = Int((candidate.confidence * 100).rounded())
            let subtitle = candidate.subtitle.isEmpty ? providerLabel : "\(candidate.subtitle) • \(providerLabel)"
            return "\(candidate.displayTitle) (\(confidence)%) — \(subtitle)"
        }
        let accessory = AutoTagCandidateSelectionAccessory(optionTitles: summaries) { [weak self] index in
            guard let self, index >= 0, index < candidates.count else { return "" }
            return self.buildTrackCandidateDetails(candidates[index])
        }
        alert.accessoryView = accessory.view
        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        let index = accessory.selectedIndex
        guard index >= 0, index < candidates.count else { return nil }
        return candidates[index]
    }

    private func buildTrackCandidateDetails(_ candidate: AutoTagTrackCandidate) -> String {
        var lines: [String] = []

        func append(_ name: String, _ value: String?) {
            guard let value, !value.isEmpty else { return }
            lines.append("\(name): \(value)")
        }

        lines.append(candidate.displayTitle)
        lines.append("Confidence: \(Int((candidate.confidence * 100).rounded()))%")
        lines.append("Providers: \(candidate.providers.map(\.rawValue).sorted().joined(separator: ", "))")
        if !candidate.subtitle.isEmpty {
            lines.append("Summary: \(candidate.subtitle)")
        }
        lines.append("")
        append("Title", candidate.patch.title)
        append("Artist", candidate.patch.artist)
        append("Album", candidate.patch.album)
        append("Album Artist", candidate.patch.albumArtist)
        append("Genre", candidate.patch.genre)
        append("Year", candidate.patch.year.map(String.init))
        append("Track #", candidate.patch.trackNumber.map(String.init))
        append("Disc #", candidate.patch.discNumber.map(String.init))
        append("Composer", candidate.patch.composer)
        append("Comment", candidate.patch.comment)
        append("Grouping", candidate.patch.grouping)
        append("BPM", candidate.patch.bpm.map(String.init))
        append("Key", candidate.patch.musicalKey)
        append("ISRC", candidate.patch.isrc)
        append("Copyright", candidate.patch.copyright)
        append("MB Recording ID", candidate.patch.musicBrainzRecordingID)
        append("MB Release ID", candidate.patch.musicBrainzReleaseID)
        append("Discogs Release ID", candidate.patch.discogsReleaseID.map(String.init))
        append("Discogs Master ID", candidate.patch.discogsMasterID.map(String.init))
        append("Discogs Label", candidate.patch.discogsLabel)
        append("Discogs Catalog #", candidate.patch.discogsCatalogNumber)
        append("Artwork URL", candidate.patch.artworkURL)
        return lines.joined(separator: "\n")
    }

    private func diffLines(before: LibraryTrack, after: LibraryTrack) -> [String] {
        var lines: [String] = []
        func appendChange(_ label: String, _ old: String?, _ new: String?) {
            if old != new {
                lines.append("\(label): \(old ?? "—") -> \(new ?? "—")")
            }
        }

        appendChange("Title", before.title, after.title)
        appendChange("Artist", before.artist, after.artist)
        appendChange("Album", before.album, after.album)
        appendChange("Album Artist", before.albumArtist, after.albumArtist)
        appendChange("Genre", before.genre, after.genre)
        appendChange("Year", before.year.map(String.init), after.year.map(String.init))
        appendChange("Track #", before.trackNumber.map(String.init), after.trackNumber.map(String.init))
        appendChange("Disc #", before.discNumber.map(String.init), after.discNumber.map(String.init))
        appendChange("Composer", before.composer, after.composer)
        appendChange("Comment", before.comment, after.comment)
        appendChange("Grouping", before.grouping, after.grouping)
        appendChange("BPM", before.bpm.map(String.init), after.bpm.map(String.init))
        appendChange("Key", before.musicalKey, after.musicalKey)
        appendChange("ISRC", before.isrc, after.isrc)
        appendChange("Copyright", before.copyright, after.copyright)
        appendChange("MB Recording ID", before.musicBrainzRecordingID, after.musicBrainzRecordingID)
        appendChange("MB Release ID", before.musicBrainzReleaseID, after.musicBrainzReleaseID)
        appendChange("Discogs Release ID", before.discogsReleaseID.map(String.init), after.discogsReleaseID.map(String.init))
        appendChange("Discogs Master ID", before.discogsMasterID.map(String.init), after.discogsMasterID.map(String.init))
        appendChange("Discogs Label", before.discogsLabel, after.discogsLabel)
        appendChange("Discogs Catalog #", before.discogsCatalogNumber, after.discogsCatalogNumber)
        appendChange("Artwork URL", before.artworkURL, after.artworkURL)
        return lines
    }

    private func applyPatchToForm(_ patch: AutoTagTrackPatch) {
        setField(.title, patch.title)
        setField(.artist, patch.artist)
        setField(.album, patch.album)
        setField(.albumArtist, patch.albumArtist)
        setField(.genre, patch.genre)
        setField(.year, patch.year.map(String.init))
        setField(.trackNumber, patch.trackNumber.map(String.init))
        setField(.discNumber, patch.discNumber.map(String.init))
        setField(.composer, patch.composer)
        setField(.comment, patch.comment)
        setField(.grouping, patch.grouping)
        setField(.bpm, patch.bpm.map(String.init))
        setField(.musicalKey, patch.musicalKey)
        setField(.isrc, patch.isrc)
        setField(.copyright, patch.copyright)
        setField(.mbRecordingID, patch.musicBrainzRecordingID)
        setField(.mbReleaseID, patch.musicBrainzReleaseID)
        setField(.discogsReleaseID, patch.discogsReleaseID.map(String.init))
        setField(.discogsMasterID, patch.discogsMasterID.map(String.init))
        setField(.discogsLabel, patch.discogsLabel)
        setField(.discogsCatalogNumber, patch.discogsCatalogNumber)
        setField(.artworkURL, patch.artworkURL)
    }

    private func setField(_ field: Field, _ value: String?) {
        guard let value else { return }
        fields[field]?.stringValue = value
    }

    private func trackFromForm() -> LibraryTrack {
        var updated = MediaLibrary.shared.findTrack(byURL: track.url) ?? track
        updated.title = nonEmpty(.title) ?? track.title
        updated.artist = nonEmpty(.artist)
        updated.album = nonEmpty(.album)
        updated.albumArtist = nonEmpty(.albumArtist)
        updated.genre = nonEmpty(.genre)
        updated.year = intValue(.year)
        updated.trackNumber = intValue(.trackNumber)
        updated.discNumber = intValue(.discNumber)
        updated.composer = nonEmpty(.composer)
        updated.comment = nonEmpty(.comment)
        updated.grouping = nonEmpty(.grouping)
        updated.bpm = intValue(.bpm)
        updated.musicalKey = nonEmpty(.musicalKey)
        updated.isrc = nonEmpty(.isrc)
        updated.copyright = nonEmpty(.copyright)
        updated.musicBrainzRecordingID = nonEmpty(.mbRecordingID)
        updated.musicBrainzReleaseID = nonEmpty(.mbReleaseID)
        updated.discogsReleaseID = intValue(.discogsReleaseID)
        updated.discogsMasterID = intValue(.discogsMasterID)
        updated.discogsLabel = nonEmpty(.discogsLabel)
        updated.discogsCatalogNumber = nonEmpty(.discogsCatalogNumber)
        updated.artworkURL = nonEmpty(.artworkURL)
        return updated
    }

    private func value(for field: Field) -> String {
        switch field {
        case .title: return track.title
        case .artist: return track.artist ?? ""
        case .album: return track.album ?? ""
        case .albumArtist: return track.albumArtist ?? ""
        case .genre: return track.genre ?? ""
        case .year: return track.year.map(String.init) ?? ""
        case .trackNumber: return track.trackNumber.map(String.init) ?? ""
        case .discNumber: return track.discNumber.map(String.init) ?? ""
        case .composer: return track.composer ?? ""
        case .comment: return track.comment ?? ""
        case .grouping: return track.grouping ?? ""
        case .bpm: return track.bpm.map(String.init) ?? ""
        case .musicalKey: return track.musicalKey ?? ""
        case .isrc: return track.isrc ?? ""
        case .copyright: return track.copyright ?? ""
        case .mbRecordingID: return track.musicBrainzRecordingID ?? ""
        case .mbReleaseID: return track.musicBrainzReleaseID ?? ""
        case .discogsReleaseID: return track.discogsReleaseID.map(String.init) ?? ""
        case .discogsMasterID: return track.discogsMasterID.map(String.init) ?? ""
        case .discogsLabel: return track.discogsLabel ?? ""
        case .discogsCatalogNumber: return track.discogsCatalogNumber ?? ""
        case .artworkURL: return track.artworkURL ?? ""
        }
    }

    private func intValue(_ field: Field) -> Int? {
        guard let raw = fields[field]?.stringValue.trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty else { return nil }
        return Int(raw)
    }

    private func nonEmpty(_ field: Field) -> String? {
        guard let value = fields[field]?.stringValue.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else { return nil }
        return value
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    private func showInfoAlert(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    private func commitPendingEdits() {
        contentView?.window?.makeFirstResponder(nil)
    }

    private func loadArtworkPreview() {
        Task { [weak self] in
            guard let self else { return }
            let image = await MetadataArtworkLoader.loadArtwork(for: track)
            await MainActor.run {
                self.artworkImageView.image = image
                self.artworkPlaceholderLabel.isHidden = image != nil
            }
        }
    }

    func show() {
        level = .modalPanel
        center()
        makeKeyAndOrderFront(nil)
    }
}
