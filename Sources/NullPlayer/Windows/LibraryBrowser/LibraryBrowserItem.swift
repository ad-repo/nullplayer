import Foundation
import NullPlayerCore

extension LibraryBrowserItem: LibraryArtRow {
    var isArtItem: Bool { type.isArtItem }
    var isAlbumItem: Bool { type.isAlbumItem }
    var isVideoContainer: Bool { type.isVideoContainer }
}

/// One row of the library browser list, shared by the classic and modern views.
struct LibraryBrowserItem {
    let id: String
    let title: String
    let info: String?
    let indentLevel: Int
    let hasChildren: Bool
    let type: ItemType
    var titlePrefix: String? = nil
    /// A YouTube video row's audio download (`YouTubeRow.audioFile`).
    var audioFile: URL? = nil

    enum ItemType {
        case artist(PlexArtist)
        case album(PlexAlbum)
        case track(PlexTrack)
        case movie(PlexMovie)
        case show(PlexShow)
        case season(PlexSeason)
        case episode(PlexEpisode)
        case header
        // Local content types
        case localArtist(Artist)
        case localAlbum(Album)
        case localTrack(LibraryTrack)
        case localFolder(url: URL, name: String)
        case localMovie(LocalVideo)
        case localShow(LocalShow)
        case localSeason(LocalSeason, showTitle: String)
        case localEpisode(LocalEpisode)
        // Subsonic content types
        case subsonicArtist(SubsonicArtist)
        case subsonicAlbum(SubsonicAlbum)
        case subsonicTrack(SubsonicSong)
        case subsonicPlaylist(SubsonicPlaylist)
        // Jellyfin content types
        case jellyfinArtist(JellyfinArtist)
        case jellyfinAlbum(JellyfinAlbum)
        case jellyfinTrack(JellyfinSong)
        case jellyfinPlaylist(JellyfinPlaylist)
        case jellyfinMovie(JellyfinMovie)
        case jellyfinShow(JellyfinShow)
        case jellyfinSeason(JellyfinSeason)
        case jellyfinEpisode(JellyfinEpisode)
        // Emby content types
        case embyArtist(EmbyArtist)
        case embyAlbum(EmbyAlbum)
        case embyTrack(EmbySong)
        case embyPlaylist(EmbyPlaylist)
        case embyMovie(EmbyMovie)
        case embyShow(EmbyShow)
        case embySeason(EmbySeason)
        case embyEpisode(EmbyEpisode)
        // Plex playlist type
        case plexPlaylist(PlexPlaylist)
        // Radio station type (Internet Radio - Shoutcast/Icecast)
        case radioStation(RadioStation)
        case radioFolder(RadioFolderDescriptor)
        // YouTube channels and videos
        case youtubeChannel(YouTubeChannel)
        case youtubeVideo(YouTubeVideo)
        // Plex Radio station type (dynamic playlists from Plex library)
        case plexRadioStation(PlexRadioType)
        case subsonicRadioStation(SubsonicRadioType)
        case jellyfinRadioStation(InstantMixRadioType)
        case embyRadioStation(InstantMixRadioType)
        case localRadioStation(LocalRadioType)
        case localPlaylist(LocalPlaylist)
        case localPlaylistTrack(Track)

        var isAlbumItem: Bool {
            switch self {
            case .album, .localAlbum, .subsonicAlbum, .jellyfinAlbum, .embyAlbum: return true
            default: return false
            }
        }

        /// Rows shown in Flow and Tiles. Containers (artists, folders, shows, seasons)
        /// drill in; albums, tracks, movies, and episodes are leaves that play.
        var isArtItem: Bool {
            switch self {
            case .artist, .localArtist, .subsonicArtist, .jellyfinArtist, .embyArtist,
                 .localFolder,
                 .track, .localTrack, .subsonicTrack, .jellyfinTrack, .embyTrack,
                 .movie, .show, .season, .episode,
                 .localMovie, .localShow, .localSeason, .localEpisode,
                 .jellyfinMovie, .jellyfinShow, .jellyfinSeason, .jellyfinEpisode,
                 .embyMovie, .embyShow, .embySeason, .embyEpisode:
                return true
            default:
                return isAlbumItem
            }
        }

        /// Movies, shows and seasons: their art is a 2:3 poster. Episodes carry a landscape still.
        var isPoster: Bool {
            switch self {
            case .movie, .show, .season, .localMovie, .localShow, .localSeason,
                 .jellyfinMovie, .jellyfinShow, .jellyfinSeason, .embyMovie, .embyShow, .embySeason:
                return true
            default:
                return false
            }
        }

        /// Search results keep music containers as navigation links, but video containers retain
        /// their show → season → episode hierarchy inside Flow and Tiles.
        var isVideoContainer: Bool {
            switch self {
            case .show, .season, .localShow, .localSeason,
                 .jellyfinShow, .jellyfinSeason, .embyShow, .embySeason:
                return true
            default:
                return false
            }
        }
    }
}

extension LibraryBrowserItem {
    /// The title as drawn: `titlePrefix` (a YouTube row's markers) ahead of the item's own title.
    var shownTitle: String { titlePrefix.map { "\($0) \(title)" } ?? title }

    /// "1 album", "3 albums".
    static func countLabel(_ count: Int, _ noun: String) -> String {
        "\(count) \(noun)\(count == 1 ? "" : "s")"
    }

    /// A row's duration info, as the Time column shows it.
    static func formatDuration(_ seconds: Int?) -> String? {
        seconds.map { formatDuration(TimeInterval($0)) }
    }

    init(_ row: YouTubeRow) {
        let type: ItemType
        switch row.kind {
        case .header: type = .header
        case .channel(let channel): type = .youtubeChannel(channel)
        case .video(let video): type = .youtubeVideo(video)
        }
        self.init(id: row.id, title: row.title, info: row.info, indentLevel: row.indentLevel,
                  hasChildren: row.hasChildren, type: type, titlePrefix: row.titlePrefix, audioFile: row.audioFile)
    }

    init(_ row: LocalFolderTree.Row) {
        let type: ItemType
        switch row.kind {
        case .folder(let url): type = .localFolder(url: url, name: row.title)
        case .track(let track): type = .localTrack(track)
        }
        self.init(id: row.id, title: row.title, info: row.info, indentLevel: row.indentLevel,
                  hasChildren: row.hasChildren, type: type)
    }
}
