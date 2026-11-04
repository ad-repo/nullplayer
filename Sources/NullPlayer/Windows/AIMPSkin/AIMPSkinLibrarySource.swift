import AppKit

/// NullPlayer's library as a skin's library window lists it (`AIMPSkinLibrary`): built on a
/// background queue while the skin shows the library (`isShown`), and again after the library
/// changes, one build at a time, the last one meanwhile. A scan's progress, or a new build, is
/// passed on through `onChange`. The window, its menus and the host read tracks from the build, so
/// no lookup copies NullPlayer's whole library.
///
/// One per AIMP window controller, through its engine host (`AIMPSkinAudioEngineHost`), and
/// stopped with it.
@MainActor
final class AIMPSkinLibrarySource {
    /// The last build; nil before the first.
    private(set) var library: AIMPSkinLibrary?
    /// Whether the skin has a library window (its own, or library lists on the deck), so the
    /// library is worth building.
    var isShown = false {
        didSet { if isShown { build() } }
    }
    private let onChange: () -> Void
    private var observers: [NSObjectProtocol] = []
    /// Bumped by every library change, so a build begun before one is not kept as current.
    private var generation = 0
    private var building = false
    private var stale = false

    /// Library reads, off the main thread: the library answers through its own queue, which a scan can hold.
    private static let queue = DispatchQueue(label: "com.nullplayer.aimp-library", qos: .utility)

    init(onChange: @escaping () -> Void) {
        self.onChange = onChange
        observers = [MediaLibrary.libraryDidChangeNotification, MediaLibrary.scanProgressNotification].map { name in
            NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    if note.name == MediaLibrary.libraryDidChangeNotification {
                        self.generation += 1
                        self.stale = true
                        self.build()
                    }
                    self.onChange()
                }
            }
        }
    }

    /// The session is over: stop following the library.
    func stop() {
        observers.forEach(NotificationCenter.default.removeObserver)
        observers = []
    }

    /// The build the skin shows: the last one while it shows the library, else none.
    var shown: AIMPSkinLibrary? { isShown ? library : nil }

    /// Builds the library model when the skin shows the library and the last build is missing or
    /// older than NullPlayer's library.
    private func build() {
        guard isShown, library == nil || stale, !building else { return }
        building = true
        stale = false
        let generation = generation
        Self.queue.async { [weak self] in
            let model = AIMPSkinLibrary(tracks: MediaLibrary.shared.tracksSnapshot)
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.building = false
                    // A change during the build asks for another; this one is still newer than nothing.
                    if generation != self.generation { self.stale = true }
                    self.library = model
                    self.build()
                    self.onChange()
                }
            }
        }
    }

    /// Asks for files or folders and adds them to the library (folders scanned), as AIMP's
    /// `acMusicLibraryAddFiles` does with one panel. Not the library browser's `addFiles` and
    /// `addWatchFolder`: those take one kind each, and act on the browser's own model.
    static func addFilesOrFolders() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.message = "Add files or folders to the music library"
        guard panel.runModal() == .OK else { return }
        let urls = panel.urls
        let folders = urls.filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
        let files = urls.filter { !folders.contains($0) }
        if !files.isEmpty { MediaLibrary.shared.addTracks(urls: files) }
        for folder in folders { MediaLibrary.shared.scanFolder(folder) }
    }
}
