import AppKit

/// The YouTube source's Search tab, shared by both library browsers: the channels found by
/// the last submitted query. A search is a network call, so it runs only when submitted
/// (Enter, Refresh), never per keystroke; returning to the tab reuses an unchanged query's
/// results.
@MainActor
final class YouTubeChannelSearch {
    private(set) var results: [YouTubeChannelSearchResult] = []
    /// The query that produced `results` (nil before any search, and after a failed one).
    private var submittedQuery: String?
    private var task: Task<Void, Never>?

    /// Whether `query` is typed but not yet searched, so Enter should submit it rather than
    /// act on the selected row.
    func isUnsubmitted(_ query: String) -> Bool {
        !query.isEmpty && Self.normalized(query) != submittedQuery
    }

    /// Search for `query` unless its results are already showing (`force` re-runs it).
    /// Returns false when nothing was started — the current results stand, cleared for an
    /// empty query. Otherwise `completion` runs when the search lands: nil on success, or
    /// the error (the results are then cleared). A cancelled search never completes.
    func submit(_ query: String, force: Bool, completion: @escaping @MainActor (Error?) -> Void) -> Bool {
        let query = Self.normalized(query)
        guard !query.isEmpty else {
            cancel()
            results = []; submittedQuery = nil
            return false
        }
        guard force || query != submittedQuery else { return false }
        task?.cancel()
        task = Task { [weak self] in
            do {
                let found = try await YouTubeManager.shared.searchChannels(query: query)
                try Task.checkCancellation()
                guard let self else { return }
                self.task = nil
                self.results = found; self.submittedQuery = query
                completion(nil)
            } catch is CancellationError {
            } catch where Task.isCancelled {
            } catch {
                guard let self else { return }
                self.task = nil
                self.results = []; self.submittedQuery = nil
                NSLog("YouTube channel search failed: %@", error.localizedDescription.redactingSensitiveURLQueryItems)
                completion(error)
            }
        }
        return true
    }

    func cancel() {
        task?.cancel(); task = nil
    }

    /// Folder title for a preview video's download when its channel isn't subscribed, so the
    /// folder isn't named after a bare ID.
    func channelTitle(forVideo video: YouTubeVideo) -> String? {
        results.first { $0.channel.id == video.channelId }?.channel.title
    }

    /// Subscribe to a search result's channel, reporting a failure (ffmpeg missing, already
    /// subscribed) in an alert. The browsers rebuild on `youtubeChannelsDidChangeNotification`.
    func subscribe(to channel: YouTubeChannel) {
        do {
            try YouTubeManager.shared.subscribe(to: channel)
        } catch {
            let alert = NSAlert()
            alert.messageText = "Could not subscribe"
            alert.informativeText = error.localizedDescription
            alert.runModal()
        }
    }

    private static func normalized(_ query: String) -> String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
