import Foundation

/// The Folders tab's rows, shaped once for both library browsers. Each browser maps a row to its
/// own display item, so row ids, titles and indents are decided here only. A depth-first walk of
/// the watch folders into every expanded directory: one root shows its contents directly, several
/// are each a top-level folder. Reads the file system and the store, so it runs off the main actor,
/// and stops early once its task is cancelled.
enum LocalFolderTree {
    struct Row {
        enum Kind {
            case folder(URL)
            case track(LibraryTrack)
        }

        let id: String
        /// The folder's name, or the track's own title: the Artist column already shows its artist (#542).
        let title: String
        var info: String? = nil
        let indentLevel: Int
        let kind: Kind

        var hasChildren: Bool {
            if case .folder = kind { return true }
            return false
        }

        static func folder(_ url: URL, indent: Int) -> Row {
            Row(id: url.path, title: url.lastPathComponent, indentLevel: indent, kind: .folder(url))
        }

        static func track(_ track: LibraryTrack, indent: Int) -> Row {
            Row(id: track.id.uuidString, title: track.title, info: track.formattedDuration,
                indentLevel: indent, kind: .track(track))
        }
    }

    /// The watch folders that are reachable now. `watchFolderSummaries()` blocks on the library's
    /// data queue, which a running import scan can hold for seconds, so this never runs on the main actor.
    static func availableRoots() -> [URL] {
        MediaLibrary.shared.watchFolderSummaries().filter { $0.isAvailable }.map { $0.url }
    }

    /// `expanded` holds folder paths. `tracks` looks up the scanned tracks for a folder's audio
    /// files; a file it does not return is listed from its URL alone.
    static func rows(
        roots: [URL] = availableRoots(),
        expanded: Set<String>,
        tracks: ([URL]) -> [URL: LibraryTrack] = { MediaLibraryStore.shared.tracks(forURLs: $0) }
    ) -> [Row] {
        var rows: [Row] = []

        func walk(_ url: URL, indent: Int) {
            if Task.isCancelled { return }
            var subdirectories: [URL] = []
            var audioFiles: [URL] = []
            let contents = (try? FileManager.default.contentsOfDirectory(
                at: url, includingPropertiesForKeys: [.isSymbolicLinkKey], options: .skipsHiddenFiles)) ?? []
            for item in contents {
                var isDirectory: ObjCBool = false
                guard FileManager.default.fileExists(atPath: item.path, isDirectory: &isDirectory) else { continue }
                if isDirectory.boolValue {
                    // A symlinked directory could loop forever. Ask the item itself: comparing resolved
                    // paths also dropped every folder under a symlinked root such as /tmp.
                    let isLink = (try? item.resourceValues(forKeys: [.isSymbolicLinkKey]))?.isSymbolicLink ?? false
                    if !isLink { subdirectories.append(item) }
                } else if LocalFileDiscovery.isSupportedAudioFile(item) {
                    audioFiles.append(item)
                }
            }
            // Directories first, then files, each in Finder's order: numbers by value (#543)
            subdirectories.sort { inFinderOrder($0.lastPathComponent, $1.lastPathComponent) }
            audioFiles.sort { inFinderOrder($0.lastPathComponent, $1.lastPathComponent) }

            for directory in subdirectories {
                rows.append(.folder(directory, indent: indent))
                // Recurse in place, so a folder's contents follow it directly
                if expanded.contains(directory.path) { walk(directory, indent: indent + 1) }
            }
            let scanned = tracks(audioFiles)
            for file in audioFiles {
                rows.append(.track(scanned[file] ?? LibraryTrack(url: file), indent: indent))
            }
        }

        if roots.count > 1 {
            for root in roots {
                rows.append(.folder(root, indent: 0))
                if expanded.contains(root.path) { walk(root, indent: 1) }
            }
        } else if let only = roots.first {
            walk(only, indent: 0)
        }
        return rows
    }

    /// Case- and diacritic-insensitive, numbers by value, and no leading-article stripping: Finder
    /// files "The Wall" under T.
    private static func inFinderOrder(_ lhs: String, _ rhs: String) -> Bool {
        LibraryTextSorter.areInOrder(lhs, rhs, ascending: true, ignoreLeadingArticles: false)
    }
}
