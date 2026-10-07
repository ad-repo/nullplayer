import AppKit

/// The library's play verbs, as every play menu titles them, with the engine call each makes.
/// Both library browsers build their rows' play items from `addMenuItems`, and their Enter
/// shortcuts run the same verbs; YouTube video rows put the same items in **Audio ▸** / **Video ▸**.
enum TrackVerb: CaseIterable {
    case play, playAndReplaceQueue, playNext, addToQueue

    var title: String {
        switch self {
        case .play: return "Play"
        case .playAndReplaceQueue: return "Play and Replace Queue"
        case .playNext: return "Play Next"
        case .addToQueue: return "Add to Queue"
        }
    }

    /// Whether the verb replaces what is playing, so a newer one supersedes it.
    var startsPlayback: Bool { self == .play || self == .playAndReplaceQueue }

    @MainActor
    func perform(_ tracks: [Track]) {
        let engine = WindowManager.shared.audioEngine
        switch self {
        case .play: engine.playNow(tracks)
        case .playAndReplaceQueue: engine.loadTracks(tracks)
        case .playNext: engine.insertTracksAfterCurrent(tracks)
        case .addToQueue:
            let wasEmpty = engine.playlist.isEmpty
            engine.appendTracks(tracks)
            if wasEmpty { engine.playTrack(at: 0) }
        }
    }

    // MARK: - Running

    /// Bumped by every verb that starts playback: a newer one supersedes a play still resolving,
    /// so a slow server fetch never starts playing over what the user picked after it.
    @MainActor private static var playEpoch = 0

    /// Resolve the tracks, then perform. A failed resolve is logged and does nothing.
    @MainActor
    func run(_ resolve: @escaping @MainActor () async throws -> [Track]) {
        if startsPlayback { Self.playEpoch += 1 }
        let epoch = Self.playEpoch
        Task { @MainActor in
            do {
                let tracks = try await resolve()
                guard !startsPlayback || Self.playEpoch == epoch else { return }
                perform(tracks)
            } catch is CancellationError {
            } catch {
                NSLog("%@ failed: %@", title, error.localizedDescription.redactingSensitiveURLQueryItems)
            }
        }
    }

    @MainActor
    func run(_ playable: LibraryPlayable) {
        run { try await playable.tracks() }
    }

    // MARK: - Menu

    /// Append one item per verb, each resolving the row's tracks when chosen.
    @MainActor
    static func addMenuItems(to menu: NSMenu, resolve: @escaping @MainActor () async throws -> [Track]) {
        for verb in allCases {
            let item = NSMenuItem(title: verb.title, action: #selector(MenuTarget.performVerb(_:)), keyEquivalent: "")
            item.target = MenuTarget.shared
            item.representedObject = MenuRequest(verb: verb, resolve: resolve)
            menu.addItem(item)
        }
    }

    @MainActor
    static func addMenuItems(to menu: NSMenu, for playable: LibraryPlayable) {
        addMenuItems(to: menu) { try await playable.tracks() }
    }

    private struct MenuRequest {
        let verb: TrackVerb
        let resolve: @MainActor () async throws -> [Track]
    }

    /// `NSMenuItem.target` is weak, so the items share one long-lived target.
    @MainActor
    private final class MenuTarget: NSObject {
        static let shared = MenuTarget()

        @objc func performVerb(_ sender: NSMenuItem) {
            guard let request = sender.representedObject as? MenuRequest else { return }
            request.verb.run(request.resolve)
        }
    }
}
