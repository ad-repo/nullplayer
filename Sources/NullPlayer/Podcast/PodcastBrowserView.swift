import AppKit
import SwiftUI

struct PodcastBrowserTheme {
    let background: NSColor
    let surface: NSColor
    let elevated: NSColor
    let accent: NSColor
    let text: NSColor
    let secondaryText: NSColor
    let separator: NSColor
    let selection: NSColor
    let selectionText: NSColor
    let warning: NSColor

    var isDark: Bool {
        guard let rgb = background.usingColorSpace(.deviceRGB) else { return true }
        return (0.299 * rgb.redComponent + 0.587 * rgb.greenComponent + 0.114 * rgb.blueComponent) < 0.5
    }

    static let classic = PodcastBrowserTheme(
        background: NSColor(calibratedWhite: 0.06, alpha: 1),
        surface: NSColor(calibratedWhite: 0.11, alpha: 1),
        elevated: NSColor(calibratedWhite: 0.16, alpha: 1),
        accent: NSColor(calibratedRed: 0.18, green: 0.95, blue: 0.42, alpha: 1),
        text: .white,
        secondaryText: NSColor(calibratedWhite: 0.68, alpha: 1),
        separator: NSColor(calibratedWhite: 0.28, alpha: 1),
        selection: NSColor(calibratedRed: 0.08, green: 0.28, blue: 0.58, alpha: 1),
        selectionText: .white,
        warning: NSColor(calibratedRed: 0.95, green: 0.28, blue: 0.25, alpha: 1)
    )
}

struct PodcastBrowserView: View {
    @ObservedObject var store: PodcastStore
    let theme: PodcastBrowserTheme

    @State private var searchText = ""
    @State private var showingSettings = false
    @State private var showingAddFeed = false
    @State private var hidePlayed = false

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider().overlay(Color(theme.separator))
            content
        }
        .background(Color(theme.background))
        .foregroundStyle(Color(theme.text))
        .tint(Color(theme.accent))
        .preferredColorScheme(theme.isDark ? .dark : .light)
        .sheet(isPresented: $showingSettings) { PodcastIndexSettingsView(store: store, theme: theme) }
        .sheet(isPresented: $showingAddFeed) { AddPodcastFeedView(store: store, theme: theme) }
        .onAppear { store.start() }
        .onReceive(NotificationCenter.default.publisher(for: PodcastStore.showSettingsNotification)) { _ in
            showingSettings = true
        }
        .onReceive(NotificationCenter.default.publisher(for: PodcastStore.showAddFeedNotification)) { _ in
            showingAddFeed = true
        }
    }

    private var toolbar: some View {
        HStack(spacing: 10) {
            if store.section == .discover, store.selectedFeed == nil {
                Button {
                    searchText = ""
                    store.showSubscriptions()
                } label: {
                    Image(systemName: "chevron.left")
                }
                .buttonStyle(.borderless)
                .help("Back to Subscriptions")
            }

            TextField("Search Podcast Index", text: $searchText)
                .textFieldStyle(.roundedBorder)
                .foregroundStyle(Color(theme.text))
                .frame(maxWidth: .infinity)
                .onSubmit { store.search(searchText) }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(Color(theme.surface))
    }

    @ViewBuilder private var content: some View {
        if let feed = store.selectedFeed {
            feedDetail(feed)
        } else if store.section == .favorites {
            episodeCollection(store.favoriteEpisodes)
        } else if store.section == .downloads {
            episodeCollection(store.downloadedEpisodes)
        } else {
            feedCollection
        }
    }

    private var feedCollection: some View {
        Group {
            if store.isLoading && displayedFeeds.isEmpty {
                loadingView
            } else if displayedFeeds.isEmpty {
                emptyView
            } else {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 132, maximum: 190), spacing: 16)], spacing: 18) {
                        ForEach(displayedFeeds) { feed in PodcastTile(feed: feed, store: store, theme: theme) }
                    }
                    .padding(18)
                }
            }
        }
        .overlay(alignment: .bottom) { statusBanner }
    }

    private var displayedFeeds: [PodcastFeed] {
        switch store.section {
        case .subscriptions: return store.subscribedFeeds
        case .discover: return store.discoveryFeeds
        case .favorites, .downloads: return []
        }
    }

    private func episodeCollection(_ episodes: [PodcastEpisode]) -> some View {
        Group {
            if episodes.isEmpty {
                emptyView
            } else {
                ScrollView {
                    LazyVStack(spacing: 1) {
                        ForEach(episodes) { episode in
                            PodcastEpisodeRow(episode: episode, store: store, theme: theme)
                        }
                    }
                    .padding(.vertical, 10)
                }
            }
        }
        .overlay(alignment: .bottom) { statusBanner }
    }

    private var emptyView: some View {
        VStack(spacing: 12) {
            Image(systemName: store.section == .downloads ? "arrow.down.circle" :
                    (store.section == .favorites ? "star.circle" : "mic.circle"))
                .font(.system(size: 46, weight: .light)).foregroundStyle(Color(theme.secondaryText))
            Text(emptyTitle).font(.title3.weight(.semibold))
            Text(emptyDetail).multilineTextAlignment(.center).foregroundStyle(Color(theme.secondaryText))
                .frame(maxWidth: 460)
            if store.section == .subscriptions {
                Button("Add RSS Feed") { showingAddFeed = true }
                    .buttonStyle(.borderedProminent)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(30)
    }

    private var emptyTitle: String {
        switch store.section {
        case .subscriptions: return "Your podcast shelf is empty"
        case .discover: return "No podcasts found"
        case .favorites: return "No favorite episodes"
        case .downloads: return "No downloaded episodes"
        }
    }

    private var emptyDetail: String {
        switch store.section {
        case .subscriptions: return "Search the open Podcast Index directory, then subscribe."
        case .discover: return "Try a different search."
        case .favorites: return "Favorite an episode from its menu and it will be collected here."
        case .downloads: return "Downloaded audio and video episodes will appear here for offline playback."
        }
    }

    private func feedDetail(_ feed: PodcastFeed) -> some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 14) {
                Button { store.closeFeed() } label: { Image(systemName: "chevron.left") }
                    .buttonStyle(.borderless).help("Back")
                PodcastArtwork(url: feed.imageURL, size: 92, theme: theme)
                VStack(alignment: .leading, spacing: 5) {
                    Text(feed.title).font(.title2.weight(.bold)).lineLimit(2)
                    if let author = feed.author { Text(author).foregroundStyle(Color(theme.secondaryText)) }
                    if let summary = feed.summary {
                        Text(summary).font(.body).foregroundStyle(Color(theme.secondaryText)).lineLimit(5)
                    }
                    HStack(spacing: 8) {
                        Button(store.isSubscribed(feed) ? "Subscribed" : "Subscribe") { store.toggleSubscription(feed) }
                        Button("Add Unplayed to Playlist") { store.addUnplayedToPlaylist(store.selectedEpisodes) }
                        if store.isSubscribed(feed) {
                            let auto = store.subscriptions.first(where: { $0.feed.id == feed.id })?.autoDownloadNewest == true
                            Button(auto ? "Auto-download On" : "Auto-download Off") { store.toggleAutoDownload(feed) }
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                Spacer()
            }
            .padding(14)
            .background(Color(theme.surface))

            HStack {
                TextField("Filter episodes", text: $store.episodeSearch).textFieldStyle(.roundedBorder)
                Toggle("Hide played", isOn: $hidePlayed).toggleStyle(.checkbox)
                Text("\(filteredEpisodes.count) episodes")
                    .font(.caption).foregroundStyle(Color(theme.secondaryText))
            }
            .padding(.horizontal, 14).padding(.vertical, 8)

            Divider().overlay(Color(theme.separator))
            if store.isLoading && store.selectedEpisodes.isEmpty { loadingView }
            else {
                ScrollView {
                    LazyVStack(spacing: 1) {
                        ForEach(filteredEpisodes) { episode in
                            PodcastEpisodeRow(episode: episode, store: store, theme: theme)
                        }
                    }
                }
            }
        }
        .overlay(alignment: .bottom) { statusBanner }
    }

    private var filteredEpisodes: [PodcastEpisode] {
        let query = store.episodeSearch.trimmingCharacters(in: .whitespacesAndNewlines)
        return store.selectedEpisodes.filter { episode in
            (!hidePlayed || !store.state(for: episode).isPlayed) &&
            (query.isEmpty || episode.title.localizedCaseInsensitiveContains(query) ||
             episode.summary?.localizedCaseInsensitiveContains(query) == true)
        }
    }

    private var loadingView: some View {
        VStack(spacing: 10) { ProgressView(); Text("Loading podcasts").foregroundStyle(Color(theme.secondaryText)) }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder private var statusBanner: some View {
        if let error = store.errorMessage {
            Text(error).font(.caption).padding(.horizontal, 12).padding(.vertical, 7)
                .background(Color(theme.warning)).foregroundStyle(Color(theme.selectionText)).clipShape(Capsule()).padding(10)
        } else if let end = store.sleepTimerEnd {
            Text("Sleep timer: \(end, style: .timer)").font(.caption).padding(.horizontal, 10).padding(.vertical, 5)
                .background(Color(theme.elevated)).clipShape(Capsule()).padding(8)
        }
    }

}

private struct PodcastTile: View {
    let feed: PodcastFeed
    @ObservedObject var store: PodcastStore
    let theme: PodcastBrowserTheme

    var body: some View {
        Button { store.select(feed) } label: {
            VStack(alignment: .leading, spacing: 7) {
                ZStack(alignment: .topTrailing) {
                    PodcastArtwork(url: feed.imageURL, size: nil, theme: theme).aspectRatio(1, contentMode: .fit)
                    if store.isSubscribed(feed) {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(Color(theme.accent))
                            .padding(6).background(.black.opacity(0.55), in: Circle()).padding(5)
                    }
                }
                Text(feed.title).font(.headline).lineLimit(2).multilineTextAlignment(.leading)
                    .foregroundStyle(Color(theme.text))
                Text(feed.author ?? feed.categories.first ?? "Podcast")
                    .font(.caption).foregroundStyle(Color(theme.secondaryText)).lineLimit(1)
            }
            .padding(9)
            .background(Color(theme.surface), in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color(theme.separator), lineWidth: 0.5))
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("Open") { store.select(feed) }
            Button(store.isSubscribed(feed) ? "Unsubscribe" : "Subscribe") { store.toggleSubscription(feed) }
            if store.isSubscribed(feed) {
                let auto = store.subscriptions.first(where: { $0.feed.id == feed.id })?.autoDownloadNewest == true
                Button(auto ? "Disable Auto-download" : "Auto-download Newest") { store.toggleAutoDownload(feed) }
            }
        }
    }
}

private struct PodcastEpisodeRow: View {
    let episode: PodcastEpisode
    @ObservedObject var store: PodcastStore
    let theme: PodcastBrowserTheme

    private var state: PodcastEpisodeState { store.state(for: episode) }

    var body: some View {
        HStack(alignment: .top, spacing: 11) {
            PodcastArtwork(url: episode.imageURL, size: 64, theme: theme)
            Button { store.play(episode) } label: {
                Image(systemName: episode.isVideo ? "play.rectangle.fill" : "play.circle.fill")
                    .font(.title2).foregroundStyle(Color(theme.accent))
            }.buttonStyle(.plain).help(episode.isVideo ? "Play video episode" : "Play episode")

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 5) {
                    if !state.isPlayed { Circle().fill(Color(theme.accent)).frame(width: 7, height: 7) }
                    Text(episode.title).font(.headline).lineLimit(2)
                    if episode.isVideo { Image(systemName: "video.fill").font(.caption).foregroundStyle(Color(theme.secondaryText)) }
                    if state.isFavorite { Image(systemName: "star.fill").foregroundStyle(Color(theme.accent)).font(.caption) }
                    if state.downloadedPath != nil { Image(systemName: "arrow.down.circle.fill").font(.caption) }
                }
                HStack(spacing: 8) {
                    if let date = episode.publishedAt { Text(date, style: .date) }
                    Text(episode.formattedDuration)
                    if episode.explicit { Text("E").fontWeight(.bold) }
                }.font(.subheadline).foregroundStyle(Color(theme.secondaryText))
                if let summary = episode.summary {
                    Text(summary).font(.callout).foregroundStyle(Color(theme.secondaryText)).lineLimit(3)
                }
                if let duration = state.duration ?? episode.duration, duration > 0, state.position > 0, !state.isPlayed {
                    ProgressView(value: min(1, state.position / duration)).tint(Color(theme.accent))
                }
            }
            Spacer(minLength: 5)
            if store.isDownloading(episode) { ProgressView().controlSize(.small) }
            Menu {
                episodeMenu
            } label: { Image(systemName: "ellipsis") }.menuStyle(.borderlessButton).frame(width: 24)
        }
        .padding(.horizontal, 13).padding(.vertical, 10)
        .background(Color(theme.surface).opacity(state.isPlayed ? 0.58 : 0.9))
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { store.play(episode) }
        .contextMenu { episodeMenu }
    }

    @ViewBuilder private var episodeMenu: some View {
        Button("Play") { store.play(episode) }
        Button("Play Next") { store.playNext(episode) }
        Button("Add to Playlist") { store.addToPlaylist(episode) }
        Divider()
        Button(state.isPlayed ? "Mark Unplayed" : "Mark Played") { store.togglePlayed(episode) }
        Button(state.isFavorite ? "Remove Favorite" : "Favorite") { store.toggleFavorite(episode) }
        Divider()
        if state.downloadedPath == nil {
            Button("Download Episode") { store.download(episode) }
        } else {
            Button("Remove Download") { store.removeDownload(episode) }
        }
        if let website = episode.websiteURL { Link("Open Episode Web Page", destination: website) }
    }
}

private struct PodcastArtwork: View {
    let url: URL?
    let size: CGFloat?
    let theme: PodcastBrowserTheme

    var body: some View {
        Group {
            if let url {
                AsyncImage(url: url, transaction: Transaction(animation: .easeInOut(duration: 0.2))) { phase in
                    switch phase {
                    case .success(let image): image.resizable().scaledToFill()
                    default: placeholder
                    }
                }
            } else { placeholder }
        }
        .frame(width: size, height: size)
        .clipped()
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var placeholder: some View {
        ZStack {
            LinearGradient(colors: [Color(theme.elevated), Color(theme.accent).opacity(0.45)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            Image(systemName: "mic.fill").font(.system(size: size.map { $0 * 0.34 } ?? 34)).foregroundStyle(Color(theme.text).opacity(0.86))
        }
    }
}

private struct AddPodcastFeedView: View {
    @ObservedObject var store: PodcastStore
    let theme: PodcastBrowserTheme
    @Environment(\.dismiss) private var dismiss
    @State private var url = ""
    @State private var error: String?
    @State private var adding = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Add Podcast Feed").font(.title2.bold())
            Text("Paste any public RSS or Atom podcast feed URL.").foregroundStyle(Color(theme.secondaryText))
            TextField("https://example.com/podcast.xml", text: $url).textFieldStyle(.roundedBorder)
            if let error { Text(error).foregroundStyle(Color(theme.warning)).font(.caption) }
            HStack { Spacer(); Button("Cancel") { dismiss() }; Button("Add") { add() }.keyboardShortcut(.defaultAction).disabled(url.isEmpty || adding) }
        }
        .padding(22).frame(width: 480).background(Color(theme.background)).foregroundStyle(Color(theme.text))
    }

    private func add() {
        adding = true; error = nil
        Task {
            do { try await store.addFeed(urlString: url); dismiss() }
            catch { self.error = error.localizedDescription; adding = false }
        }
    }
}

private struct PodcastIndexSettingsView: View {
    @ObservedObject var store: PodcastStore
    let theme: PodcastBrowserTheme
    @Environment(\.dismiss) private var dismiss
    @State private var key = ""
    @State private var secret = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            Text("Podcast Index").font(.title2.bold())
            Text("A free API key unlocks richer directory metadata and higher search limits. Search and RSS subscriptions work without one.")
                .foregroundStyle(Color(theme.secondaryText)).fixedSize(horizontal: false, vertical: true)
            Link("Get a free key at api.podcastindex.org", destination: URL(string: "https://api.podcastindex.org/")!)
            TextField("API key", text: $key).textFieldStyle(.roundedBorder)
            SecureField("API secret", text: $secret).textFieldStyle(.roundedBorder)
            HStack {
                if store.hasCredentials { Button("Remove Credentials") { store.clearCredentials(); dismiss() } }
                Spacer(); Button("Cancel") { dismiss() }
                Button("Save") { store.saveCredentials(key: key, secret: secret); dismiss() }
                    .keyboardShortcut(.defaultAction).disabled(key.isEmpty || secret.isEmpty)
            }
        }
        .padding(22).frame(width: 500).background(Color(theme.background)).foregroundStyle(Color(theme.text))
    }
}
