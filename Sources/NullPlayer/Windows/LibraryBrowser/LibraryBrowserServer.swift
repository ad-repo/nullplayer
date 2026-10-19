import Foundation

// The Subsonic, Jellyfin and Emby sources load, list and expand the same way; only the types differ.
// These protocols name what the browser reads from each, so `LibraryBrowserModel+Servers.swift`
// is written once for all three. Each model type says which browser row it becomes.

// MARK: - Rows

protocol BrowsableArtist {
    var id: String { get }
    var name: String { get }
    var albumCount: Int { get }
    var itemType: LibraryBrowserItem.ItemType { get }
    static var expansionKind: LibraryBrowserModel.ExpansionKey.Kind { get }
    /// The server's index letter, which the name sort groups by; nil to sort by name alone.
    static var sortIndexLetter: ((Self) -> String?)? { get }
}

extension BrowsableArtist {
    static var sortIndexLetter: ((Self) -> String?)? { nil }
}

protocol BrowsableAlbum {
    var id: String { get }
    var name: String { get }
    var artist: String? { get }
    var artistId: String? { get }
    var year: Int? { get }
    var created: Date? { get }
    var itemType: LibraryBrowserItem.ItemType { get }
    static var expansionKind: LibraryBrowserModel.ExpansionKey.Kind { get }
}

protocol BrowsableSong {
    var id: String { get }
    var title: String { get }
    var duration: Int { get }
    var discNumber: Int? { get }
    var track: Int? { get }
    var year: Int? { get }
    var created: Date? { get }
    var itemType: LibraryBrowserItem.ItemType { get }
}

protocol BrowsablePlaylist {
    var id: String { get }
    var name: String { get }
    var songCount: Int { get }
    var itemType: LibraryBrowserItem.ItemType { get }
    static var expansionKind: LibraryBrowserModel.ExpansionKey.Kind { get }
    /// When the playlist was added, for the date sorts; nil to sort by name alone.
    static var addedDate: ((Self) -> Date?)? { get }
}

extension BrowsablePlaylist {
    static var addedDate: ((Self) -> Date?)? { nil }
}

protocol BrowsableMovie {
    var id: String { get }
    var title: String { get }
    var year: Int? { get }
    var formattedDuration: String? { get }
    var itemType: LibraryBrowserItem.ItemType { get }
}

protocol BrowsableShow {
    var id: String { get }
    var title: String { get }
    var year: Int? { get }
    /// Its seasons; 0 when the server does not say.
    var childCount: Int { get }
    var itemType: LibraryBrowserItem.ItemType { get }
    static var expansionKind: LibraryBrowserModel.ExpansionKey.Kind { get }
}

protocol BrowsableSeason {
    var id: String { get }
    var title: String { get }
    /// Its episodes; 0 when the server does not say.
    var childCount: Int { get }
    var itemType: LibraryBrowserItem.ItemType { get }
    static var expansionKind: LibraryBrowserModel.ExpansionKey.Kind { get }
}

protocol BrowsableEpisode {
    var id: String { get }
    var title: String { get }
    var episodeIdentifier: String { get }
    var formattedDuration: String? { get }
    var itemType: LibraryBrowserItem.ItemType { get }
}

/// A server's radio stations: its library and favourites, then each genre's and each decade's.
protocol BrowsableRadioStation {
    var displayName: String { get }
    var category: String { get }
    static func stations(genres: [String]) -> [Self]
}

// MARK: - Search results

protocol ServerSearchResults {
    associatedtype Artist
    associatedtype Album
    associatedtype Song
    var artists: [Artist] { get }
    var albums: [Album] { get }
    var songs: [Song] { get }
}

protocol ServerVideoSearchResults: ServerSearchResults {
    associatedtype Movie: BrowsableMovie
    associatedtype Show: BrowsableShow
    var movies: [Movie] { get }
    var shows: [Show] { get }
}

// MARK: - Servers

/// A Subsonic, Jellyfin or Emby manager: its servers, its music, and its radio.
protocol MusicServerBrowsing: AnyObject {
    associatedtype Server: Identifiable where Server.ID == String
    associatedtype Artist: BrowsableArtist
    associatedtype Album: BrowsableAlbum
    associatedtype Song: BrowsableSong
    associatedtype Playlist: BrowsablePlaylist
    associatedtype SearchResults: ServerSearchResults
        where SearchResults.Artist == Artist, SearchResults.Album == Album, SearchResults.Song == Song
    associatedtype RadioStation: BrowsableRadioStation

    static func source(serverId: String) -> LibraryBrowserSource
    /// Where the browser keeps this server's music rows.
    @MainActor static var musicCache: ReferenceWritableKeyPath<LibraryBrowserModel, ServerMusicCache<Self>> { get }
    /// Fetch the albums in the background after the Artists tab loads, rather than before.
    static var warmsAlbumsAfterArtists: Bool { get }
    static func radioItem(_ station: RadioStation) -> LibraryBrowserItem.ItemType

    var servers: [Server] { get }
    var currentServer: Server? { get }
    var isPreloading: Bool { get }
    var isContentPreloaded: Bool { get }
    var cachedArtists: [Artist] { get }
    var cachedAlbums: [Album] { get }
    var cachedPlaylists: [Playlist] { get }

    func connect(to server: Server) async throws
    func clearCachedContent()
    func preloadLibraryContent() async
    func fetchArtists() async throws -> [Artist]
    func fetchArtistsUnfiltered() async throws -> [Artist]
    func fetchAlbums() async throws -> [Album]
    func fetchPlaylists() async throws -> [Playlist]
    func fetchAlbums(forArtist artist: Artist) async throws -> [Album]
    func fetchSongs(forAlbum album: Album) async throws -> [Song]
    func playlistSongs(_ playlist: Playlist) async throws -> [Song]
    /// The Search tab's results, with each found artist's albums.
    func librarySearch(_ query: String) async throws -> SearchResults
    func radioGenres() async -> [String]
}

extension MusicServerBrowsing {
    static var warmsAlbumsAfterArtists: Bool { false }
}

/// A Jellyfin or Emby manager: a music server with movie and TV libraries too.
protocol VideoServerBrowsing: MusicServerBrowsing
    where SearchResults: ServerVideoSearchResults, SearchResults.Movie == Movie, SearchResults.Show == Show {
    associatedtype Movie: BrowsableMovie
    associatedtype Show: BrowsableShow
    associatedtype Season: BrowsableSeason
    associatedtype Episode: BrowsableEpisode

    /// Where the browser keeps this server's video rows.
    @MainActor static var videoCache: ReferenceWritableKeyPath<LibraryBrowserModel, ServerVideoCache<Self>> { get }

    var cachedMovies: [Movie] { get }
    var cachedShows: [Show] { get }
    func fetchMovies() async throws -> [Movie]
    func fetchShows() async throws -> [Show]
    func fetchSeasons(forShow show: Show) async throws -> [Season]
    func fetchEpisodes(forSeason season: Season) async throws -> [Episode]
}

/// A Subsonic, Jellyfin or Emby server's music rows. Children fetched on expand are keyed by
/// their parent's id.
struct ServerMusicCache<Server: MusicServerBrowsing> {
    var artists: [Server.Artist] = []
    var albums: [Server.Album] = []
    var playlists: [Server.Playlist] = []
    var artistAlbums: [String: [Server.Album]] = [:]
    var albumSongs: [String: [Server.Song]] = [:]
    var playlistTracks: [String: [Server.Song]] = [:]
    var searchResults: Server.SearchResults?
}

/// A Jellyfin or Emby server's video rows.
struct ServerVideoCache<Server: VideoServerBrowsing> {
    var movies: [Server.Movie] = []
    var shows: [Server.Show] = []
    var showSeasons: [String: [Server.Season]] = [:]
    var seasonEpisodes: [String: [Server.Episode]] = [:]
}

// MARK: - Subsonic

extension SubsonicManager: MusicServerBrowsing {
    static func source(serverId: String) -> LibraryBrowserSource { .subsonic(serverId: serverId) }
    @MainActor static var musicCache: ReferenceWritableKeyPath<LibraryBrowserModel, ServerMusicCache<SubsonicManager>> { \.subsonic }
    static func radioItem(_ station: SubsonicRadioType) -> LibraryBrowserItem.ItemType { .subsonicRadioStation(station) }

    func playlistSongs(_ playlist: SubsonicPlaylist) async throws -> [SubsonicSong] {
        try await serverClient?.fetchPlaylist(id: playlist.id).songs ?? []
    }
    func librarySearch(_ query: String) async throws -> SubsonicSearchResults { try await searchWithArtistAlbums(query: query) }
    func radioGenres() async -> [String] { await getGenres() }
}

extension SubsonicSearchResults: ServerSearchResults {}

extension SubsonicArtist: BrowsableArtist {
    var itemType: LibraryBrowserItem.ItemType { .subsonicArtist(self) }
    static var expansionKind: LibraryBrowserModel.ExpansionKey.Kind { .subsonicArtist }
    /// Navidrome files "The Atlas Moth" under T; the name sort groups as the server does.
    static var sortIndexLetter: ((Self) -> String?)? { { $0.indexLetter } }
}

extension SubsonicAlbum: BrowsableAlbum {
    var itemType: LibraryBrowserItem.ItemType { .subsonicAlbum(self) }
    static var expansionKind: LibraryBrowserModel.ExpansionKey.Kind { .subsonicAlbum }
}

extension SubsonicSong: BrowsableSong {
    var itemType: LibraryBrowserItem.ItemType { .subsonicTrack(self) }
}

extension SubsonicPlaylist: BrowsablePlaylist {
    var itemType: LibraryBrowserItem.ItemType { .subsonicPlaylist(self) }
    static var expansionKind: LibraryBrowserModel.ExpansionKey.Kind { .subsonicPlaylist }
    static var addedDate: ((Self) -> Date?)? { { $0.changed ?? $0.created } }
}

extension SubsonicRadioType: BrowsableRadioStation {
    static func stations(genres: [String]) -> [Self] {
        [.libraryRadio, .librarySimilar, .starredRadio, .starredSimilar]
            + genres.flatMap { [.genreRadio($0), .genreSimilar($0)] }
            + RadioConfig.decades.flatMap {
                [.decadeRadio(start: $0.start, end: $0.end, name: $0.name), .decadeSimilar(start: $0.start, end: $0.end, name: $0.name)]
            }
    }
}

// MARK: - Jellyfin

extension JellyfinManager: VideoServerBrowsing {
    static func source(serverId: String) -> LibraryBrowserSource { .jellyfin(serverId: serverId) }
    @MainActor static var musicCache: ReferenceWritableKeyPath<LibraryBrowserModel, ServerMusicCache<JellyfinManager>> { \.jellyfin }
    @MainActor static var videoCache: ReferenceWritableKeyPath<LibraryBrowserModel, ServerVideoCache<JellyfinManager>> { \.jellyfinVideo }
    static var warmsAlbumsAfterArtists: Bool { true }
    static func radioItem(_ station: InstantMixRadioType) -> LibraryBrowserItem.ItemType { .jellyfinRadioStation(station) }

    func playlistSongs(_ playlist: JellyfinPlaylist) async throws -> [JellyfinSong] {
        try await serverClient?.fetchPlaylist(id: playlist.id).songs ?? []
    }
    func librarySearch(_ query: String) async throws -> JellyfinSearchResults { try await searchWithArtistAlbums(query: query) }
    func radioGenres() async -> [String] { await getMusicGenres() }
}

extension JellyfinSearchResults: ServerVideoSearchResults {}

extension JellyfinArtist: BrowsableArtist {
    var itemType: LibraryBrowserItem.ItemType { .jellyfinArtist(self) }
    static var expansionKind: LibraryBrowserModel.ExpansionKey.Kind { .jellyfinArtist }
}

extension JellyfinAlbum: BrowsableAlbum {
    var itemType: LibraryBrowserItem.ItemType { .jellyfinAlbum(self) }
    static var expansionKind: LibraryBrowserModel.ExpansionKey.Kind { .jellyfinAlbum }
}

extension JellyfinSong: BrowsableSong {
    var itemType: LibraryBrowserItem.ItemType { .jellyfinTrack(self) }
}

extension JellyfinPlaylist: BrowsablePlaylist {
    var itemType: LibraryBrowserItem.ItemType { .jellyfinPlaylist(self) }
    static var expansionKind: LibraryBrowserModel.ExpansionKey.Kind { .jellyfinPlaylist }
}

extension JellyfinMovie: BrowsableMovie {
    var itemType: LibraryBrowserItem.ItemType { .jellyfinMovie(self) }
}

extension JellyfinShow: BrowsableShow {
    var itemType: LibraryBrowserItem.ItemType { .jellyfinShow(self) }
    static var expansionKind: LibraryBrowserModel.ExpansionKey.Kind { .jellyfinShow }
}

extension JellyfinSeason: BrowsableSeason {
    var itemType: LibraryBrowserItem.ItemType { .jellyfinSeason(self) }
    static var expansionKind: LibraryBrowserModel.ExpansionKey.Kind { .jellyfinSeason }
}

extension JellyfinEpisode: BrowsableEpisode {
    var itemType: LibraryBrowserItem.ItemType { .jellyfinEpisode(self) }
}

// MARK: - Emby

extension EmbyManager: VideoServerBrowsing {
    static func source(serverId: String) -> LibraryBrowserSource { .emby(serverId: serverId) }
    @MainActor static var musicCache: ReferenceWritableKeyPath<LibraryBrowserModel, ServerMusicCache<EmbyManager>> { \.emby }
    @MainActor static var videoCache: ReferenceWritableKeyPath<LibraryBrowserModel, ServerVideoCache<EmbyManager>> { \.embyVideo }
    static func radioItem(_ station: InstantMixRadioType) -> LibraryBrowserItem.ItemType { .embyRadioStation(station) }

    func playlistSongs(_ playlist: EmbyPlaylist) async throws -> [EmbySong] {
        try await serverClient?.fetchPlaylist(id: playlist.id).songs ?? []
    }
    func librarySearch(_ query: String) async throws -> EmbySearchResults { try await searchWithArtistAlbums(query: query) }
    func radioGenres() async -> [String] { await getMusicGenres() }
}

extension EmbySearchResults: ServerVideoSearchResults {}

extension EmbyArtist: BrowsableArtist {
    var itemType: LibraryBrowserItem.ItemType { .embyArtist(self) }
    static var expansionKind: LibraryBrowserModel.ExpansionKey.Kind { .embyArtist }
}

extension EmbyAlbum: BrowsableAlbum {
    var itemType: LibraryBrowserItem.ItemType { .embyAlbum(self) }
    static var expansionKind: LibraryBrowserModel.ExpansionKey.Kind { .embyAlbum }
}

extension EmbySong: BrowsableSong {
    var itemType: LibraryBrowserItem.ItemType { .embyTrack(self) }
}

extension EmbyPlaylist: BrowsablePlaylist {
    var itemType: LibraryBrowserItem.ItemType { .embyPlaylist(self) }
    static var expansionKind: LibraryBrowserModel.ExpansionKey.Kind { .embyPlaylist }
}

extension EmbyMovie: BrowsableMovie {
    var itemType: LibraryBrowserItem.ItemType { .embyMovie(self) }
}

extension EmbyShow: BrowsableShow {
    var itemType: LibraryBrowserItem.ItemType { .embyShow(self) }
    static var expansionKind: LibraryBrowserModel.ExpansionKey.Kind { .embyShow }
}

extension EmbySeason: BrowsableSeason {
    var itemType: LibraryBrowserItem.ItemType { .embySeason(self) }
    static var expansionKind: LibraryBrowserModel.ExpansionKey.Kind { .embySeason }
}

extension EmbyEpisode: BrowsableEpisode {
    var itemType: LibraryBrowserItem.ItemType { .embyEpisode(self) }
}
