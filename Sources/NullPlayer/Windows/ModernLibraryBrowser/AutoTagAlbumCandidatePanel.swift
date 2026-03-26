import AppKit

final class AutoTagAlbumCandidatePanel: NSWindow, NSTableViewDataSource, NSTableViewDelegate, NSWindowDelegate {
    private struct ComparisonRow {
        let resultDisc: String
        let resultTrack: String
        let resultTitle: String
        let localDisc: String
        let localTrack: String
        let localTitle: String
        let status: String
    }

    private let candidates: [AutoTagAlbumCandidate]
    private let localTracks: [LibraryTrack]

    private let candidateTableView = NSTableView()
    private let comparisonTableView = NSTableView()
    private let detailsLabel = NSTextField(wrappingLabelWithString: "")
    private var comparisonRows: [ComparisonRow] = []
    private var selectedCandidate: AutoTagAlbumCandidate?
    private var modalResponse: NSApplication.ModalResponse = .cancel

    init(candidates: [AutoTagAlbumCandidate], localTracks: [LibraryTrack]) {
        self.candidates = candidates
        self.localTracks = localTracks
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 1080, height: 720),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        title = "Select Album Candidate"
        isReleasedWhenClosed = false
        minSize = NSSize(width: 900, height: 560)
        delegate = self
        buildUI()
        refreshSelection(index: 0)
    }

    func runSelectionModal() -> AutoTagAlbumCandidate? {
        center()
        makeKeyAndOrderFront(nil)
        let response = NSApp.runModal(for: self)
        orderOut(nil)
        return candidateForModalResponse(response)
    }

    @MainActor
    func simulateAcceptedCandidateForTesting(row: Int) -> AutoTagAlbumCandidate? {
        candidateTableView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        refreshSelection(index: row)
        continueClicked()
        windowWillClose(Notification(name: NSWindow.willCloseNotification, object: self))
        return candidateForModalResponse(modalResponse)
    }

    func windowWillClose(_ notification: Notification) {
        NSApp.stopModal(withCode: modalResponse)
    }

    private func buildUI() {
        guard let contentView else { return }

        let splitView = NSSplitView()
        splitView.translatesAutoresizingMaskIntoConstraints = false
        splitView.isVertical = true
        splitView.dividerStyle = .thin
        contentView.addSubview(splitView)

        let leftPane = NSView()
        leftPane.translatesAutoresizingMaskIntoConstraints = false
        splitView.addSubview(leftPane)

        let rightPane = NSView()
        rightPane.translatesAutoresizingMaskIntoConstraints = false
        splitView.addSubview(rightPane)

        let buttonRow = NSStackView()
        buttonRow.translatesAutoresizingMaskIntoConstraints = false
        buttonRow.orientation = .horizontal
        buttonRow.alignment = .centerY
        buttonRow.spacing = 8
        contentView.addSubview(buttonRow)

        let cancelButton = NSButton(title: "Cancel", target: self, action: #selector(cancelClicked))
        let continueButton = NSButton(title: "Continue", target: self, action: #selector(continueClicked))
        continueButton.keyEquivalent = "\r"
        buttonRow.addArrangedSubview(cancelButton)
        buttonRow.addArrangedSubview(continueButton)

        NSLayoutConstraint.activate([
            splitView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            splitView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            splitView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 16),
            splitView.bottomAnchor.constraint(equalTo: buttonRow.topAnchor, constant: -12),
            buttonRow.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            buttonRow.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -16)
        ])

        let leftScrollView = NSScrollView()
        leftScrollView.translatesAutoresizingMaskIntoConstraints = false
        leftScrollView.hasVerticalScroller = true
        leftScrollView.hasHorizontalScroller = false
        leftScrollView.borderType = .bezelBorder
        leftPane.addSubview(leftScrollView)

        candidateTableView.headerView = nil
        candidateTableView.allowsEmptySelection = false
        candidateTableView.usesAlternatingRowBackgroundColors = true
        candidateTableView.rowHeight = 44
        candidateTableView.delegate = self
        candidateTableView.dataSource = self
        let candidateColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("candidate"))
        candidateColumn.title = "Candidates"
        candidateColumn.width = 300
        candidateTableView.addTableColumn(candidateColumn)
        leftScrollView.documentView = candidateTableView

        NSLayoutConstraint.activate([
            leftScrollView.leadingAnchor.constraint(equalTo: leftPane.leadingAnchor),
            leftScrollView.trailingAnchor.constraint(equalTo: leftPane.trailingAnchor),
            leftScrollView.topAnchor.constraint(equalTo: leftPane.topAnchor),
            leftScrollView.bottomAnchor.constraint(equalTo: leftPane.bottomAnchor),
            leftPane.widthAnchor.constraint(equalToConstant: 320)
        ])

        let detailsTitle = NSTextField(labelWithString: "Album Metadata")
        detailsTitle.translatesAutoresizingMaskIntoConstraints = false
        detailsTitle.font = NSFont.systemFont(ofSize: 14, weight: .semibold)
        rightPane.addSubview(detailsTitle)

        let detailsCard = NSView()
        detailsCard.translatesAutoresizingMaskIntoConstraints = false
        detailsCard.wantsLayer = true
        detailsCard.layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
        detailsCard.layer?.cornerRadius = 8
        rightPane.addSubview(detailsCard)

        detailsLabel.translatesAutoresizingMaskIntoConstraints = false
        detailsLabel.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        detailsLabel.maximumNumberOfLines = 0
        detailsCard.addSubview(detailsLabel)

        let comparisonTitle = NSTextField(labelWithString: "Track Comparison")
        comparisonTitle.translatesAutoresizingMaskIntoConstraints = false
        comparisonTitle.font = NSFont.systemFont(ofSize: 14, weight: .semibold)
        rightPane.addSubview(comparisonTitle)

        let comparisonScrollView = NSScrollView()
        comparisonScrollView.translatesAutoresizingMaskIntoConstraints = false
        comparisonScrollView.hasVerticalScroller = true
        comparisonScrollView.hasHorizontalScroller = true
        comparisonScrollView.borderType = .bezelBorder
        comparisonScrollView.verticalLineScroll = 18
        rightPane.addSubview(comparisonScrollView)

        comparisonTableView.usesAlternatingRowBackgroundColors = true
        comparisonTableView.rowHeight = 22
        comparisonTableView.delegate = self
        comparisonTableView.dataSource = self
        for (identifier, title, width) in [
            ("status", "Status", 80.0),
            ("resultDisc", "Res D", 52.0),
            ("resultTrack", "Res #", 56.0),
            ("resultTitle", "Result Title", 220.0),
            ("localDisc", "Lib D", 52.0),
            ("localTrack", "Lib #", 56.0),
            ("localTitle", "Library Title", 220.0)
        ] as [(String, String, CGFloat)] {
            let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(identifier))
            column.title = title
            column.width = width
            column.minWidth = width
            comparisonTableView.addTableColumn(column)
        }
        comparisonScrollView.documentView = comparisonTableView

        NSLayoutConstraint.activate([
            detailsTitle.leadingAnchor.constraint(equalTo: rightPane.leadingAnchor),
            detailsTitle.trailingAnchor.constraint(equalTo: rightPane.trailingAnchor),
            detailsTitle.topAnchor.constraint(equalTo: rightPane.topAnchor),
            detailsCard.leadingAnchor.constraint(equalTo: rightPane.leadingAnchor),
            detailsCard.trailingAnchor.constraint(equalTo: rightPane.trailingAnchor),
            detailsCard.topAnchor.constraint(equalTo: detailsTitle.bottomAnchor, constant: 8),
            detailsLabel.leadingAnchor.constraint(equalTo: detailsCard.leadingAnchor, constant: 12),
            detailsLabel.trailingAnchor.constraint(equalTo: detailsCard.trailingAnchor, constant: -12),
            detailsLabel.topAnchor.constraint(equalTo: detailsCard.topAnchor, constant: 12),
            detailsCard.bottomAnchor.constraint(equalTo: detailsLabel.bottomAnchor, constant: 12),
            comparisonTitle.leadingAnchor.constraint(equalTo: rightPane.leadingAnchor),
            comparisonTitle.trailingAnchor.constraint(equalTo: rightPane.trailingAnchor),
            comparisonTitle.topAnchor.constraint(equalTo: detailsCard.bottomAnchor, constant: 12),
            comparisonScrollView.leadingAnchor.constraint(equalTo: rightPane.leadingAnchor),
            comparisonScrollView.trailingAnchor.constraint(equalTo: rightPane.trailingAnchor),
            comparisonScrollView.topAnchor.constraint(equalTo: comparisonTitle.bottomAnchor, constant: 8),
            comparisonScrollView.bottomAnchor.constraint(equalTo: rightPane.bottomAnchor)
        ])

        candidateTableView.reloadData()
        candidateTableView.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
    }

    @objc private func continueClicked() {
        let selectedRow = candidateTableView.selectedRow
        if selectedRow >= 0, selectedRow < candidates.count {
            selectedCandidate = candidates[selectedRow]
            NSLog("[MetadataDebug] album-candidate-continue row=%d id=%@ matchedTracks=%d totalTracks=%d",
                  selectedRow,
                  selectedCandidate?.id ?? "nil",
                  selectedCandidate?.perTrackPatches.count ?? 0,
                  localTracks.count)
        } else {
            NSLog("[MetadataDebug] album-candidate-continue row=%d fallback-id=%@",
                  selectedRow,
                  selectedCandidate?.id ?? "nil")
        }
        modalResponse = .OK
        close()
    }

    @objc private func cancelClicked() {
        selectedCandidate = nil
        modalResponse = .cancel
        close()
    }

    private func candidateForModalResponse(_ response: NSApplication.ModalResponse) -> AutoTagAlbumCandidate? {
        guard response == .OK else { return nil }
        let selectedRow = candidateTableView.selectedRow
        if selectedRow >= 0, selectedRow < candidates.count {
            return candidates[selectedRow]
        }
        return selectedCandidate
    }

    func numberOfRows(in tableView: NSTableView) -> Int {
        if tableView == candidateTableView { return candidates.count }
        return comparisonRows.count
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        guard notification.object as? NSTableView == candidateTableView else { return }
        refreshSelection(index: candidateTableView.selectedRow)
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let identifier = tableColumn?.identifier ?? NSUserInterfaceItemIdentifier("cell")
        let cell = NSTableCellView()
        let textField = NSTextField(labelWithString: "")
        textField.translatesAutoresizingMaskIntoConstraints = false
        cell.addSubview(textField)
        NSLayoutConstraint.activate([
            textField.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 6),
            textField.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -6),
            textField.centerYAnchor.constraint(equalTo: cell.centerYAnchor)
        ])

        if tableView == candidateTableView {
            let candidate = candidates[row]
            let providers = candidate.providers.map(\.rawValue).sorted().joined(separator: "+")
            let confidence = Int((candidate.confidence * 100).rounded())
            let matchCount = "\(candidate.perTrackPatches.count)/\(localTracks.count)"
            textField.lineBreakMode = .byTruncatingTail
            textField.maximumNumberOfLines = 2
            textField.stringValue = "\(candidate.displayTitle)\n\(confidence)% • \(providers) • \(matchCount) tracks"
            textField.font = NSFont.systemFont(ofSize: 12)
            textField.textColor = .labelColor
            return cell
        }

        let comparison = comparisonRows[row]
        let value: String
        switch identifier.rawValue {
        case "status": value = comparison.status
        case "resultDisc": value = comparison.resultDisc
        case "resultTrack": value = comparison.resultTrack
        case "resultTitle": value = comparison.resultTitle
        case "localDisc": value = comparison.localDisc
        case "localTrack": value = comparison.localTrack
        case "localTitle": value = comparison.localTitle
        default: value = ""
        }
        textField.stringValue = value
        textField.lineBreakMode = .byTruncatingTail
        textField.maximumNumberOfLines = 1
        textField.font = NSFont.systemFont(ofSize: 12)
        textField.textColor = identifier.rawValue == "status" ? statusColor(value) : .labelColor
        return cell
    }

    private func refreshSelection(index: Int) {
        guard index >= 0, index < candidates.count else { return }
        let candidate = candidates[index]
        selectedCandidate = candidate
        detailsLabel.stringValue = candidateDetails(candidate)
        comparisonRows = buildComparisonRows(for: candidate)
        comparisonTableView.reloadData()
    }

    private func candidateDetails(_ candidate: AutoTagAlbumCandidate) -> String {
        func value(_ label: String, _ value: String?) -> String? {
            guard let value, !value.isEmpty else { return nil }
            return "\(label): \(value)"
        }
        let lines: [String?] = [
            candidate.displayTitle,
            "Confidence: \(Int((candidate.confidence * 100).rounded()))%",
            "Providers: \(candidate.providers.map(\.rawValue).sorted().joined(separator: ", "))",
            candidate.subtitle.isEmpty ? nil : "Summary: \(candidate.subtitle)",
            "Matched Tracks: \(candidate.perTrackPatches.count) of \(localTracks.count)",
            nil,
            value("Artist", candidate.albumPatch.artist),
            value("Album", candidate.albumPatch.album),
            value("Album Artist", candidate.albumPatch.albumArtist),
            value("Genre", candidate.albumPatch.genre),
            candidate.albumPatch.year.map { "Year: \($0)" },
            value("MB Release ID", candidate.albumPatch.musicBrainzReleaseID),
            candidate.albumPatch.discogsReleaseID.map { "Discogs Release ID: \($0)" },
            candidate.albumPatch.discogsMasterID.map { "Discogs Master ID: \($0)" },
            value("Discogs Label", candidate.albumPatch.discogsLabel),
            value("Discogs Catalog #", candidate.albumPatch.discogsCatalogNumber)
        ]
        return lines.compactMap { $0 }.joined(separator: "\n")
    }

    private func buildComparisonRows(for candidate: AutoTagAlbumCandidate) -> [ComparisonRow] {
        let localByID = Dictionary(uniqueKeysWithValues: localTracks.map { ($0.id, $0) })
        let mappedByLocalID = AutoTagTrackMapper.map(releaseTracks: candidate.releaseTracks, localTracks: localTracks)
        let releaseMatchByKey = mappedByLocalID.reduce(into: [String: UUID]()) { partialResult, entry in
            if let key = releaseTrackComparisonKey(entry.value), partialResult[key] == nil {
                partialResult[key] = entry.key
            }
        }
        var matchedLocalIDs = Set<UUID>()
        var rows: [ComparisonRow] = []

        for releaseTrack in candidate.releaseTracks.sorted(by: compareReleaseTracks) {
            if let key = releaseTrackComparisonKey(releaseTrack),
               let localTrackID = releaseMatchByKey[key],
               let localTrack = localByID[localTrackID] {
                matchedLocalIDs.insert(localTrack.id)
                rows.append(ComparisonRow(
                    resultDisc: releaseTrack.discNumber.map(String.init) ?? "—",
                    resultTrack: releaseTrack.trackNumber.map(String.init) ?? "—",
                    resultTitle: releaseTrack.title,
                    localDisc: localTrack.discNumber.map(String.init) ?? "—",
                    localTrack: localTrack.trackNumber.map(String.init) ?? "—",
                    localTitle: localTrack.title,
                    status: "Matched"
                ))
            } else {
                rows.append(ComparisonRow(
                    resultDisc: releaseTrack.discNumber.map(String.init) ?? "—",
                    resultTrack: releaseTrack.trackNumber.map(String.init) ?? "—",
                    resultTitle: releaseTrack.title,
                    localDisc: "—",
                    localTrack: "—",
                    localTitle: "—",
                    status: "Result Only"
                ))
            }
        }

        for localTrack in localTracks
            .filter({ !matchedLocalIDs.contains($0.id) })
            .sorted(by: compareLocalTracks) {
            rows.append(ComparisonRow(
                resultDisc: "—",
                resultTrack: "—",
                resultTitle: "—",
                localDisc: localTrack.discNumber.map(String.init) ?? "—",
                localTrack: localTrack.trackNumber.map(String.init) ?? "—",
                localTitle: localTrack.title,
                status: "Library Only"
            ))
        }

        return rows
    }

    private func releaseTrackComparisonKey(_ releaseTrack: AutoTagReleaseTrackHint) -> String? {
        let titleKey = AutoTagTitleMatcher.normalizedKeyComponent(releaseTrack.title)
        guard !titleKey.isEmpty else { return nil }
        let discKey = releaseTrack.discNumber.map(String.init) ?? "x"
        let trackKey = releaseTrack.trackNumber.map(String.init) ?? "x"
        return "\(discKey)|\(trackKey)|\(titleKey)"
    }

    private func compareReleaseTracks(_ lhs: AutoTagReleaseTrackHint, _ rhs: AutoTagReleaseTrackHint) -> Bool {
        let lhsDisc = lhs.discNumber ?? Int.max
        let rhsDisc = rhs.discNumber ?? Int.max
        if lhsDisc != rhsDisc { return lhsDisc < rhsDisc }
        let lhsTrack = lhs.trackNumber ?? Int.max
        let rhsTrack = rhs.trackNumber ?? Int.max
        if lhsTrack != rhsTrack { return lhsTrack < rhsTrack }
        return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
    }

    private func compareLocalTracks(_ lhs: LibraryTrack, _ rhs: LibraryTrack) -> Bool {
        let lhsDisc = lhs.discNumber ?? Int.max
        let rhsDisc = rhs.discNumber ?? Int.max
        if lhsDisc != rhsDisc { return lhsDisc < rhsDisc }
        let lhsTrack = lhs.trackNumber ?? Int.max
        let rhsTrack = rhs.trackNumber ?? Int.max
        if lhsTrack != rhsTrack { return lhsTrack < rhsTrack }
        return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
    }

    private func statusColor(_ value: String) -> NSColor {
        switch value {
        case "Matched": return .systemGreen
        case "Result Only": return .systemOrange
        case "Library Only": return .systemRed
        default: return .labelColor
        }
    }
}
