import AppKit

/// Panel for bulk-editing album-level tags across all tracks in an album (in-app only)
class EditAlbumTagsPanel: NSWindow {
    private let artworkSize: CGFloat = 220
    private let labelColumnWidth: CGFloat = 190

    private enum Field: CaseIterable {
        case artist
        case album
        case albumArtist
        case year
        case genre
        case composer
        case comment
        case grouping
        case copyright
        case mbReleaseID
        case discogsReleaseID
        case discogsMasterID
        case discogsLabel
        case discogsCatalogNumber
        case artworkURL

        var label: String {
            switch self {
            case .artist: return "Artist"
            case .album: return "Album Name"
            case .albumArtist: return "Album Artist"
            case .year: return "Year"
            case .genre: return "Genre"
            case .composer: return "Composer"
            case .comment: return "Comment"
            case .grouping: return "Grouping"
            case .copyright: return "Copyright"
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
    private var album: Album
    private var fields: [Field: NSTextField] = [:]
    private var dirtyFields: Set<Field> = []
    private var editingTracks: [LibraryTrack] = []
    private var pendingPerTrackPatches: [UUID: AutoTagTrackPatch] = [:]
    private var lastAppliedAutoTagCandidateID: String?
    private var autoTagButton = NSButton(title: "Auto-Tag", target: nil, action: nil)
    private var autoTagTask: Task<Void, Never>?
    private let artworkImageView = NSImageView()
    private let artworkPlaceholderLabel = NSTextField(labelWithString: "No Artwork")
    var trackFinder: (URL) -> LibraryTrack? = { MediaLibrary.shared.findTrack(byURL: $0) }
    var trackUpdater: (LibraryTrack) -> Void = { MediaLibrary.shared.updateTrack($0) }

    convenience init(album: Album) {
        self.init(
            contentRect: NSRect(x: 0, y: 0, width: 760, height: 620),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        self.album = album
        title = "Edit Album Tags: \(album.name)"
        isReleasedWhenClosed = false
        minSize = NSSize(width: 620, height: 420)
        hydrateAlbumTracks()
        editingTracks = tracksForEditing()
        buildUI()
    }

    override init(contentRect: NSRect, styleMask style: NSWindow.StyleMask,
                  backing backingStoreType: NSWindow.BackingStoreType, defer flag: Bool) {
        self.album = Album(id: "", name: "", artist: nil, year: nil, tracks: [])
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

        addReadOnlyRow(grid: grid, label: "Tracks", value: "\(editingTracks.count)")

        for field in Field.allCases {
            let value = value(for: field)
            let textField = NSTextField(string: value)
            textField.font = NSFont.systemFont(ofSize: 12)
            textField.delegate = self
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
        let saveButton = NSButton(title: "Save All Tracks", target: self, action: #selector(saveClicked))
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
        delegate = self
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
        persistEdits()
        onSave?()
        close()
    }

    @discardableResult
    func persistEdits() -> [LibraryTrack] {
        commitPendingEdits()
        let sharedPatch = sharedPatchFromForm()
        var savedTracks: [LibraryTrack] = []

        for track in editingTracks {
            let currentTrack = trackFinder(track.url) ?? track
            var updated = sharedPatch.applying(to: currentTrack)
            applyDirtyClears(to: &updated)
            if let perTrack = pendingPerTrackPatches[track.id] {
                updated = perTrack.applying(to: updated)
            }
            trackUpdater(updated)
            savedTracks.append(updated)
        }
        editingTracks = savedTracks
        pendingPerTrackPatches.removeAll()
        lastAppliedAutoTagCandidateID = nil
        return savedTracks
    }

    /// Clears fields on `track` that the user explicitly blanked out (dirty + empty).
    private func applyDirtyClears(to track: inout LibraryTrack) {
        for field in dirtyFields {
            let raw = fields[field]?.stringValue.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard raw.isEmpty else { continue }
            switch field {
            case .artist: track.artist = nil
            case .album: track.album = nil
            case .albumArtist: track.albumArtist = nil
            case .genre: track.genre = nil
            case .year: track.year = nil
            case .composer: track.composer = nil
            case .comment: track.comment = nil
            case .grouping: track.grouping = nil
            case .copyright: track.copyright = nil
            case .mbReleaseID: track.musicBrainzReleaseID = nil
            case .discogsReleaseID: track.discogsReleaseID = nil
            case .discogsMasterID: track.discogsMasterID = nil
            case .discogsLabel: track.discogsLabel = nil
            case .discogsCatalogNumber: track.discogsCatalogNumber = nil
            case .artworkURL: track.artworkURL = nil
            }
        }
    }

    @objc private func cancelClicked() {
        autoTagTask?.cancel()
        close()
    }

    @objc private func autoTagClicked() {
        commitPendingEdits()
        let albumName = fields[.album]?.stringValue.trimmingCharacters(in: .whitespacesAndNewlines) ?? album.name
        let albumArtist = fields[.albumArtist]?.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        autoTagButton.isEnabled = false
        autoTagTask?.cancel()
        autoTagTask = Task { [weak self] in
            guard let self else { return }
            let candidates = await AutoTaggingService.shared.searchAlbumCandidates(
                albumName: albumName,
                albumArtist: albumArtist?.isEmpty == false ? albumArtist : nil,
                tracks: editingTracks
            )
            await MainActor.run {
                guard self.isVisible else { return }
                self.autoTagButton.isEnabled = true
                self.presentAlbumAutoTag(candidates: candidates)
            }
        }
    }

    @MainActor
    private func presentAlbumAutoTag(candidates: [AutoTagAlbumCandidate]) {
        guard !candidates.isEmpty else {
            showInfoAlert(title: "Auto-Tag", message: "No album metadata matches found from Discogs/MusicBrainz.")
            return
        }

        let rankedCandidates = rankAlbumCandidates(candidates)
        guard let selectedCandidate = selectAlbumCandidate(rankedCandidates) else { return }
        let selected = resolvedCandidate(from: selectedCandidate)
        let previewLines = buildAlbumChangeLines(candidate: selected)
        guard !previewLines.isEmpty else {
            showInfoAlert(title: "Auto-Tag", message: "Selected candidate does not change any album fields or track metadata.")
            return
        }
        let preview = previewLines.prefix(24).joined(separator: "\n")
        let confirmAlert = NSAlert()
        confirmAlert.messageText = "Apply Auto-Tag Changes?"
        confirmAlert.informativeText = preview
        confirmAlert.alertStyle = .informational
        confirmAlert.addButton(withTitle: "Apply")
        confirmAlert.addButton(withTitle: "Cancel")
        guard confirmAlert.runModal() == .alertFirstButtonReturn else { return }
        applyPatchToForm(selected.albumPatch)
        pendingPerTrackPatches = selected.perTrackPatches
        lastAppliedAutoTagCandidateID = selected.id
    }

    private func selectAlbumCandidate(_ candidates: [AutoTagAlbumCandidate]) -> AutoTagAlbumCandidate? {
        let panel = AutoTagAlbumCandidatePanel(candidates: candidates, localTracks: editingTracks)
        return panel.runSelectionModal()
    }

    private func rankAlbumCandidates(_ candidates: [AutoTagAlbumCandidate]) -> [AutoTagAlbumCandidate] {
        candidates.sorted { lhs, rhs in
            let lhsMatchCount = lhs.perTrackPatches.count
            let rhsMatchCount = rhs.perTrackPatches.count
            if lhsMatchCount != rhsMatchCount {
                return lhsMatchCount > rhsMatchCount
            }
            let lhsCoverage = lhs.releaseTracks.isEmpty ? 0.0 : Double(lhsMatchCount) / Double(lhs.releaseTracks.count)
            let rhsCoverage = rhs.releaseTracks.isEmpty ? 0.0 : Double(rhsMatchCount) / Double(rhs.releaseTracks.count)
            if lhsCoverage != rhsCoverage {
                return lhsCoverage > rhsCoverage
            }
            if lhs.confidence == rhs.confidence {
                return lhs.displayTitle.localizedCaseInsensitiveCompare(rhs.displayTitle) == .orderedAscending
            }
            return lhs.confidence > rhs.confidence
        }
    }

    private func resolvedCandidate(from candidate: AutoTagAlbumCandidate) -> AutoTagAlbumCandidate {
        let mapped = AutoTagTrackMapper.map(releaseTracks: candidate.releaseTracks, localTracks: editingTracks)
        guard !mapped.isEmpty else { return candidate }

        var resolvedPerTrackPatches: [UUID: AutoTagTrackPatch] = candidate.perTrackPatches
        for (trackID, hint) in mapped {
            var patch = resolvedPerTrackPatches[trackID] ?? AutoTagTrackPatch()
            if patch.title == nil { patch.title = hint.title }
            if patch.trackNumber == nil { patch.trackNumber = hint.trackNumber }
            if patch.discNumber == nil { patch.discNumber = hint.discNumber }
            if patch.isrc == nil { patch.isrc = hint.isrc }
            if patch.musicBrainzRecordingID == nil { patch.musicBrainzRecordingID = hint.recordingID }
            resolvedPerTrackPatches[trackID] = patch
        }

        return AutoTagAlbumCandidate(
            id: candidate.id,
            displayTitle: candidate.displayTitle,
            subtitle: candidate.subtitle,
            confidence: candidate.confidence,
            providers: candidate.providers,
            mergeKey: candidate.mergeKey,
            albumPatch: candidate.albumPatch,
            perTrackPatches: resolvedPerTrackPatches,
            releaseTracks: candidate.releaseTracks
        )
    }

    private func buildAlbumChangeLines(candidate: AutoTagAlbumCandidate) -> [String] {
        var lines: [String] = []
        let sharedPatch = candidate.albumPatch
        let firstTrack = editingTracks.first

        func appendChange(_ name: String, _ old: String?, _ new: String?) {
            guard old != new else { return }
            lines.append("\(name): \(old ?? "—") -> \(new ?? "—")")
        }

        func appendIntChange(_ name: String, _ old: Int?, _ new: Int?) {
            appendChange(name, old.map(String.init), new.map(String.init))
        }

        if let firstTrack {
            let updatedShared = sharedPatch.applying(to: firstTrack)
            appendChange("Artist", firstTrack.artist, updatedShared.artist)
            appendChange("Album", firstTrack.album, updatedShared.album)
            appendChange("Album Artist", firstTrack.albumArtist, updatedShared.albumArtist)
            appendChange("Genre", firstTrack.genre, updatedShared.genre)
            appendIntChange("Year", firstTrack.year, updatedShared.year)
            appendChange("Composer", firstTrack.composer, updatedShared.composer)
            appendChange("Comment", firstTrack.comment, updatedShared.comment)
            appendChange("Grouping", firstTrack.grouping, updatedShared.grouping)
            appendChange("Copyright", firstTrack.copyright, updatedShared.copyright)
            appendChange("MB Release ID", firstTrack.musicBrainzReleaseID, updatedShared.musicBrainzReleaseID)
            appendIntChange("Discogs Release ID", firstTrack.discogsReleaseID, updatedShared.discogsReleaseID)
            appendIntChange("Discogs Master ID", firstTrack.discogsMasterID, updatedShared.discogsMasterID)
            appendChange("Discogs Label", firstTrack.discogsLabel, updatedShared.discogsLabel)
            appendChange("Discogs Catalog #", firstTrack.discogsCatalogNumber, updatedShared.discogsCatalogNumber)
            appendChange("Artwork URL", firstTrack.artworkURL, updatedShared.artworkURL)
        } else {
            func append(_ name: String, _ value: String?) {
                if let value, !value.isEmpty {
                    lines.append("\(name): \(value)")
                }
            }
            append("Artist", sharedPatch.artist)
            append("Album", sharedPatch.album)
            append("Album Artist", sharedPatch.albumArtist)
            append("Genre", sharedPatch.genre)
            append("Year", sharedPatch.year.map(String.init))
        }

        let tracksByID = Dictionary(uniqueKeysWithValues: editingTracks.map { ($0.id, $0) })
        let perTrackLines = candidate.perTrackPatches.compactMap { trackID, patch -> String? in
            guard let track = tracksByID[trackID] else { return nil }
            let updated = patch.applying(to: track)
            var parts: [String] = []
            if track.title != updated.title { parts.append("Title: \(track.title) -> \(updated.title)") }
            if track.trackNumber != updated.trackNumber {
                parts.append("Track #: \(track.trackNumber.map(String.init) ?? "—") -> \(updated.trackNumber.map(String.init) ?? "—")")
            }
            if track.discNumber != updated.discNumber {
                parts.append("Disc #: \(track.discNumber.map(String.init) ?? "—") -> \(updated.discNumber.map(String.init) ?? "—")")
            }
            if track.isrc != updated.isrc {
                parts.append("ISRC: \(track.isrc ?? "—") -> \(updated.isrc ?? "—")")
            }
            if track.musicBrainzRecordingID != updated.musicBrainzRecordingID {
                parts.append("MB Rec: \(track.musicBrainzRecordingID ?? "—") -> \(updated.musicBrainzRecordingID ?? "—")")
            }
            guard !parts.isEmpty else { return nil }
            return "\(track.title): " + parts.joined(separator: " | ")
        }
        .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }

        if !perTrackLines.isEmpty {
            lines.append("Per-track updates matched: \(candidate.perTrackPatches.count) of \(editingTracks.count)")
            lines.append(contentsOf: perTrackLines.prefix(8))
        }

        if lines.count > 24 {
            return Array(lines.prefix(24))
        }

        return lines
    }

    private func buildAlbumCandidateDetails(_ candidate: AutoTagAlbumCandidate) -> String {
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
        lines.append("Album Fields")
        append("Artist", candidate.albumPatch.artist)
        append("Album", candidate.albumPatch.album)
        append("Album Artist", candidate.albumPatch.albumArtist)
        append("Genre", candidate.albumPatch.genre)
        append("Year", candidate.albumPatch.year.map(String.init))
        append("MB Release ID", candidate.albumPatch.musicBrainzReleaseID)
        append("Discogs Release ID", candidate.albumPatch.discogsReleaseID.map(String.init))
        append("Discogs Master ID", candidate.albumPatch.discogsMasterID.map(String.init))
        append("Discogs Label", candidate.albumPatch.discogsLabel)
        append("Discogs Catalog #", candidate.albumPatch.discogsCatalogNumber)
        append("Artwork URL", candidate.albumPatch.artworkURL)
        lines.append("")
        lines.append("Track Matches: \(candidate.perTrackPatches.count) of \(editingTracks.count)")

        let tracksByID = Dictionary(uniqueKeysWithValues: editingTracks.map { ($0.id, $0) })
        let sortedMatches = candidate.perTrackPatches
            .compactMap { trackID, patch -> (LibraryTrack, AutoTagTrackPatch)? in
                guard let track = tracksByID[trackID] else { return nil }
                return (track, patch)
            }
            .sorted { lhs, rhs in
                let lhsTrack = lhs.0.trackNumber ?? Int.max
                let rhsTrack = rhs.0.trackNumber ?? Int.max
                if lhsTrack == rhsTrack {
                    return lhs.0.title.localizedCaseInsensitiveCompare(rhs.0.title) == .orderedAscending
                }
                return lhsTrack < rhsTrack
            }

        if sortedMatches.isEmpty {
            lines.append("No per-track updates")
        } else {
            for (track, patch) in sortedMatches {
                let localTrackNo = track.trackNumber.map(String.init) ?? "?"
                let localDiscNo = track.discNumber.map(String.init) ?? "?"
                let newTrackNo = patch.trackNumber.map(String.init) ?? localTrackNo
                let newDiscNo = patch.discNumber.map(String.init) ?? localDiscNo
                let newTitle = patch.title ?? track.title
                var detail = "D\(newDiscNo) T\(newTrackNo): \(newTitle)"
                if let isrc = patch.isrc, !isrc.isEmpty {
                    detail += " | ISRC: \(isrc)"
                }
                if let recordingID = patch.musicBrainzRecordingID, !recordingID.isEmpty {
                    detail += " | MB Rec: \(recordingID)"
                }
                lines.append(detail)
            }
        }

        return lines.joined(separator: "\n")
    }

    private func applyPatchToForm(_ patch: AutoTagTrackPatch) {
        setField(.artist, patch.artist)
        setField(.album, patch.album)
        setField(.albumArtist, patch.albumArtist)
        setField(.genre, patch.genre)
        setField(.year, patch.year.map(String.init))
        setField(.composer, patch.composer)
        setField(.comment, patch.comment)
        setField(.grouping, patch.grouping)
        setField(.copyright, patch.copyright)
        setField(.mbReleaseID, patch.musicBrainzReleaseID)
        setField(.discogsReleaseID, patch.discogsReleaseID.map(String.init))
        setField(.discogsMasterID, patch.discogsMasterID.map(String.init))
        setField(.discogsLabel, patch.discogsLabel)
        setField(.discogsCatalogNumber, patch.discogsCatalogNumber)
        setField(.artworkURL, patch.artworkURL)
        loadArtworkPreview()
    }

    private func setField(_ field: Field, _ value: String?) {
        guard let value else { return }
        fields[field]?.stringValue = value
        dirtyFields.insert(field)
    }

    func applyCandidateForTesting(_ candidate: AutoTagAlbumCandidate) {
        applyPatchToForm(candidate.albumPatch)
        pendingPerTrackPatches = candidate.perTrackPatches
    }

    private func sharedPatchFromForm() -> AutoTagTrackPatch {
        AutoTagTrackPatch(
            artist: dirtyFields.contains(.artist) ? nonEmpty(.artist) : nil,
            album: dirtyFields.contains(.album) ? nonEmpty(.album) : nil,
            albumArtist: dirtyFields.contains(.albumArtist) ? nonEmpty(.albumArtist) : nil,
            genre: dirtyFields.contains(.genre) ? nonEmpty(.genre) : nil,
            year: dirtyFields.contains(.year) ? intValue(.year) : nil,
            composer: dirtyFields.contains(.composer) ? nonEmpty(.composer) : nil,
            comment: dirtyFields.contains(.comment) ? nonEmpty(.comment) : nil,
            grouping: dirtyFields.contains(.grouping) ? nonEmpty(.grouping) : nil,
            copyright: dirtyFields.contains(.copyright) ? nonEmpty(.copyright) : nil,
            musicBrainzReleaseID: dirtyFields.contains(.mbReleaseID) ? nonEmpty(.mbReleaseID) : nil,
            discogsReleaseID: dirtyFields.contains(.discogsReleaseID) ? intValue(.discogsReleaseID) : nil,
            discogsMasterID: dirtyFields.contains(.discogsMasterID) ? intValue(.discogsMasterID) : nil,
            discogsLabel: dirtyFields.contains(.discogsLabel) ? nonEmpty(.discogsLabel) : nil,
            discogsCatalogNumber: dirtyFields.contains(.discogsCatalogNumber) ? nonEmpty(.discogsCatalogNumber) : nil,
            artworkURL: dirtyFields.contains(.artworkURL) ? nonEmpty(.artworkURL) : nil
        )
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

    private func value(for field: Field) -> String {
        let first = editingTracks.first
        switch field {
        case .artist: return first?.artist ?? album.artist ?? ""
        case .album: return album.name
        case .albumArtist: return first?.albumArtist ?? album.artist ?? ""
        case .year: return first?.year.map(String.init) ?? ""
        case .genre: return first?.genre ?? ""
        case .composer: return first?.composer ?? ""
        case .comment: return first?.comment ?? ""
        case .grouping: return first?.grouping ?? ""
        case .copyright: return first?.copyright ?? ""
        case .mbReleaseID: return first?.musicBrainzReleaseID ?? ""
        case .discogsReleaseID: return first?.discogsReleaseID.map(String.init) ?? ""
        case .discogsMasterID: return first?.discogsMasterID.map(String.init) ?? ""
        case .discogsLabel: return first?.discogsLabel ?? ""
        case .discogsCatalogNumber: return first?.discogsCatalogNumber ?? ""
        case .artworkURL: return first?.artworkURL ?? ""
        }
    }

    private func hydrateAlbumTracks() {
        let hydratedTracks = MediaLibraryStore.shared.tracksForAlbum(album.id)
        guard !hydratedTracks.isEmpty else { return }
        album = Album(id: album.id, name: album.name, artist: album.artist, year: album.year, tracks: hydratedTracks)
    }

    private func tracksForEditing() -> [LibraryTrack] {
        if !album.tracks.isEmpty { return album.tracks }
        return MediaLibraryStore.shared.tracksForAlbum(album.id)
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
            let image = await MetadataArtworkLoader.loadArtwork(for: editingTracks)
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

extension EditAlbumTagsPanel: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        autoTagTask?.cancel()
    }
}

extension EditAlbumTagsPanel: NSTextFieldDelegate {
    func controlTextDidChange(_ obj: Notification) {
        guard let textField = obj.object as? NSTextField,
              let field = fields.first(where: { $0.value === textField })?.key else { return }
        dirtyFields.insert(field)
        if field == .artworkURL {
            loadArtworkPreview()
        }
    }
}
