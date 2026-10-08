import Foundation

/// A YouTube list row, shaped once for both library browsers. Each browser maps it to its own
/// display item, so row ids, titles, indents and title prefixes are decided here only.
struct YouTubeRow {
    enum Kind {
        case header
        case channel(YouTubeChannel)
        case video(YouTubeVideo)
    }

    let id: String
    /// The item's own name, which sorting, the alphabet index and type-ahead read.
    let title: String
    /// Drawn ahead of `title` only: the downloaded-form markers, or `✓` on a subscribed result.
    var titlePrefix: String? = nil
    var info: String? = nil
    let indentLevel: Int
    let kind: Kind

    var hasChildren: Bool {
        if case .channel = kind { return true }
        return false
    }
}

/// Builds the YouTube rows of the Channels tab, the channel search and the Local search's
/// YouTube section. `expanded` and `uploads` are the browser's expansion state and its fetched
/// upload lists: a channel row is followed by its uploads once it is expanded and they are in.
struct YouTubeRowBuilder {
    let expanded: Set<String>
    let uploads: [String: [YouTubeVideo]]
    var manager: YouTubeManager = .shared

    /// The Channels tab: every subscription.
    func channels(_ channels: [YouTubeChannel]) -> [YouTubeRow] {
        channels.flatMap { channelRows($0, id: "youtube-channel-\($0.id)", title: $0.title, indentLevel: 0) }
    }

    /// The YouTube source's Search tab: channel results under one header. A result already
    /// subscribed is shown as its subscription, so every channel row — here or on the Channels
    /// tab — carries a subscription's own `id` when there is one, and expand/preview/download
    /// reuse the Channels-tab paths.
    func channelSearch(_ results: [YouTubeChannelSearchResult]) -> [YouTubeRow] {
        guard !results.isEmpty else { return [] }
        let header = YouTubeRow(id: "youtube-search-header", title: "Channels (\(results.count))", indentLevel: 0, kind: .header)
        return [header] + results.flatMap { result in
            let subscription = manager.subscription(matching: result)
            var channel = subscription ?? result.channel
            channel.avatarURL = channel.avatarURL ?? result.channel.avatarURL
            let info = result.infoText
            return channelRows(channel, id: "youtube-search-\(result.channelId)", title: result.channel.title,
                               titlePrefix: subscription != nil ? "✓" : nil,
                               info: info.isEmpty ? nil : info, indentLevel: 0)
        }
    }

    /// The Local source's Search tab ends with this section: matching channels, expandable in
    /// place, then matching downloads (`YouTubeManager.localSearch`). A download already shown
    /// as an upload under an expanded channel above is not repeated.
    func localSearch(query: String, excluding listedFiles: Set<URL>) -> [YouTubeRow] {
        let found = manager.localSearch(query: query, excluding: listedFiles)
        let channels = found.channels.flatMap {
            channelRows($0, id: "youtube-channel-\($0.id)", title: $0.title, indentLevel: 1)
        }
        let shownUploads = Set(found.channels.flatMap(expandedUploads(of:)).map(\.videoId))
        let downloads = found.videos.filter { !shownUploads.contains($0.videoId) }.map {
            videoRow($0, id: "youtube-download-\($0.videoId)", indentLevel: 1)
        }
        let count = found.channels.count + downloads.count
        guard count > 0 else { return [] }
        return [YouTubeRow(id: "header-local-youtube", title: "YouTube (\(count))", indentLevel: 0, kind: .header)]
            + channels + downloads
    }

    /// A channel row, then its uploads indented one level under it.
    private func channelRows(_ channel: YouTubeChannel, id: String, title: String, titlePrefix: String? = nil,
                             info: String? = nil, indentLevel: Int) -> [YouTubeRow] {
        let row = YouTubeRow(id: id, title: title, titlePrefix: titlePrefix, info: info, indentLevel: indentLevel,
                             kind: .channel(channel))
        return [row] + expandedUploads(of: channel).map {
            videoRow($0, id: "youtube-video-\($0.videoId)", indentLevel: indentLevel + 1)
        }
    }

    /// A video row, its title prefixed by one marker per form on disk. The files are checked here,
    /// once per rebuild, never while drawing: the list redraws at 10 Hz under a download spinner
    /// and the download folder may be a network mount.
    private func videoRow(_ video: YouTubeVideo, id: String, indentLevel: Int) -> YouTubeRow {
        let onDisk = manager.downloadedFiles(for: video.videoId)
        let markers = YouTubeMediaKind.allCases.filter { onDisk[$0] != nil }.map(\.mediaType.rowMarker)
        return YouTubeRow(id: id, title: video.title, titlePrefix: markers.isEmpty ? nil : markers.joined(separator: " "),
                          info: video.formattedDuration, indentLevel: indentLevel, kind: .video(video))
    }

    private func expandedUploads(of channel: YouTubeChannel) -> [YouTubeVideo] {
        expanded.contains(channel.id) ? uploads[channel.id] ?? [] : []
    }
}
