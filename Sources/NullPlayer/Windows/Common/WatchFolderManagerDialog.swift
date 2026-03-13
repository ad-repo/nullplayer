import AppKit

/// Modal helper for managing watched local-library folders.
enum WatchFolderManagerDialog {
    static func present(onLibraryChanged: (() -> Void)? = nil) {
        while true {
            let summaries = MediaLibrary.shared.watchFolderSummaries()
            guard !summaries.isEmpty else {
                showNoFoldersAlert()
                return
            }

            let popup = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 520, height: 24), pullsDown: false)
            popup.translatesAutoresizingMaskIntoConstraints = false
            for summary in summaries {
                popup.addItem(withTitle: summary.url.path)
            }
            popup.selectItem(at: 0)

            let detailsLabel = NSTextField(labelWithString: summaryDescription(summaries[0]))
            detailsLabel.translatesAutoresizingMaskIntoConstraints = false
            detailsLabel.alignment = .left
            detailsLabel.lineBreakMode = .byTruncatingTail

            popup.target = PopupObserver.shared
            popup.action = #selector(PopupObserver.popupSelectionChanged(_:))
            PopupObserver.shared.onSelectionChanged = { [weak detailsLabel] index in
                guard index >= 0 && index < summaries.count else { return }
                detailsLabel?.stringValue = summaryDescription(summaries[index])
            }

            let stack = NSStackView(views: [popup, detailsLabel])
            stack.orientation = .vertical
            stack.alignment = .leading
            stack.spacing = 8
            stack.translatesAutoresizingMaskIntoConstraints = false

            let alert = NSAlert()
            alert.messageText = "Manage Watch Folders"
            alert.informativeText = "Choose a watched folder, then rescan, reveal, or remove it."
            alert.accessoryView = stack
            alert.addButton(withTitle: "Rescan")
            alert.addButton(withTitle: "Show in Finder")
            alert.addButton(withTitle: "Remove Folder...")
            alert.addButton(withTitle: "Done")

            let response = alert.runModal()
            let selectedIndex = max(0, popup.indexOfSelectedItem)
            guard selectedIndex < summaries.count else { return }
            let selected = summaries[selectedIndex]

            switch response {
            case .alertFirstButtonReturn:
                MediaLibrary.shared.rescanWatchFolder(selected.url, cleanMissing: true)
            case .alertSecondButtonReturn:
                NSWorkspace.shared.activateFileViewerSelecting([selected.url])
            case .alertThirdButtonReturn:
                let counts = MediaLibrary.shared.removalCountsForWatchFolder(selected.url)
                if confirmRemoval(of: selected.url, removalCounts: counts) {
                    MediaLibrary.shared.removeWatchFolder(selected.url, removeEntries: true)
                    onLibraryChanged?()
                }
            default:
                return
            }
        }
    }

    private static func showNoFoldersAlert() {
        let alert = NSAlert()
        alert.messageText = "No Watch Folders"
        alert.informativeText = "You have not added any watched folders yet."
        alert.alertStyle = .informational
        alert.runModal()
    }

    private static func confirmRemoval(
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

    private static func summaryDescription(_ summary: WatchFolderSummary) -> String {
        "\(summary.totalCount) item\(summary.totalCount == 1 ? "" : "s") in library (\(summary.trackCount) tracks, \(summary.movieCount) movies, \(summary.episodeCount) episodes)"
    }
}

/// Lightweight popup target holder (NSPopUpButton target is weak).
private final class PopupObserver: NSObject {
    static let shared = PopupObserver()
    var onSelectionChanged: ((Int) -> Void)?

    @objc func popupSelectionChanged(_ sender: NSPopUpButton) {
        onSelectionChanged?(sender.indexOfSelectedItem)
    }
}
