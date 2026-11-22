import AppKit

/// What happens to a finished audio rip: open the tag editor on it, add it to the local library
/// (split into tracks first when the rip wrote a .cue), or both — tags first, so the split
/// tracks and the library read the edited tags.
struct RipFollowUp: Equatable, Sendable {
    var editTags = false
    var addToLibrary = false

    var isEmpty: Bool { !editTags && !addToLibrary }

    @MainActor
    func run(jobID: String, path: String) {
        guard !isEmpty else { return }
        let file = URL(fileURLWithPath: path)
        let library = addToLibrary
        guard editTags else { return Self.addToLibrary(file, jobID: jobID) }
        let panel = RipTagsPanel(file: file, jobID: jobID)
        panel.onClose = { if library { Self.addToLibrary(file, jobID: jobID) } }
        panel.show()
    }

    /// Adds the rip to the library; with a sibling .cue it splits first and adds the tracks.
    @MainActor
    private static func addToLibrary(_ file: URL, jobID: String) {
        let cue = file.deletingPathExtension().appendingPathExtension("cue")
        DispatchQueue.global(qos: .userInitiated).async {
            var urls = [file]
            if FileManager.default.fileExists(atPath: cue.path) {
                let tracks = CueAlbumSplitter.splitIfNeeded(cueURL: cue).trackFiles
                if !tracks.isEmpty { urls = tracks }
            }
            StreamRipper.log(jobID, "adding \(urls.count) file(s) to the library")
            DispatchQueue.main.async { MediaLibrary.shared.addTracks(urls: urls) }
        }
    }
}
