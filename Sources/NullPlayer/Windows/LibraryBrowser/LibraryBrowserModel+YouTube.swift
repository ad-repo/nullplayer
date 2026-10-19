import Foundation

/// The YouTube source: subscribed channels on the Radio tab slot, a channel search on Search.
extension LibraryBrowserModel {

    func loadYouTubeChannels() {
        loadState = .idle
        buildYouTubeChannelItems()
        YouTubeManager.shared.backfillMissingAvatars()
    }

    var youtubeRows: YouTubeRowBuilder {
        YouTubeRowBuilder(expanded: Set(expandedYouTubeChannels.keys),
                          uploads: YouTubeChannelUploads.shared.uploads(of: expandedYouTubeChannels.keys))
    }

    func buildYouTubeChannelItems() {
        displayItems = youtubeRows.channels(YouTubeManager.shared.channels).map { LibraryBrowserItem($0) }
    }

    /// Search tab (YouTube source): run the submitted query as a YouTube channel search, or show
    /// the results of an unchanged one; `force` (Refresh) re-runs it.
    func loadYouTubeSearchResults(force: Bool = false) {
        let started = youtubeSearch.submit(searchedQuery, force: force) { [weak self] error in
            guard let self, self.isYouTubeChannelSearch else { return }
            if let error {
                self.loadState = .failed(error.localizedDescription)
            } else {
                self.loadState = .idle
                self.rebuildCurrentModeItems()
            }
        }
        guard started else {
            loadState = .idle
            buildYouTubeSearchItems()
            return
        }
        displayItems = []
        rowsReplaced()
        loadState = .loading
    }

    func buildYouTubeSearchItems() {
        displayItems = youtubeRows.channelSearch(youtubeSearch.results).map { LibraryBrowserItem($0) }
    }

    /// Fetch a channel's uploads again, expanding it.
    func refreshYouTubeChannel(_ channel: YouTubeChannel) {
        expandedYouTubeChannels[channel.id] = channel
        YouTubeChannelUploads.shared.load([channel], force: true)
    }

    func removeYouTubeChannel(_ channel: YouTubeChannel) {
        YouTubeManager.shared.removeChannel(channel)
        expandedYouTubeChannels.removeValue(forKey: channel.id)
        rebuildCurrentModeItems()
    }
}
