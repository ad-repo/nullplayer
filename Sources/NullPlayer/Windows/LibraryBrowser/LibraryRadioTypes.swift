import Foundation

/// Types of Plex Radio stations
enum PlexRadioType: Equatable, Hashable {
    case libraryRadio
    case libraryRadioSonic
    case hitsRadio
    case hitsRadioSonic
    case deepCutsRadio
    case deepCutsRadioSonic
    case genreRadio(String)
    case genreRadioSonic(String)
    case decadeRadio(start: Int, end: Int, name: String)
    case decadeRadioSonic(start: Int, end: Int, name: String)
    case ratingRadio(minRating: Double, name: String)
    case ratingRadioSonic(minRating: Double, name: String)
    
    var displayName: String {
        switch self {
        case .libraryRadio: return "Library Radio"
        case .libraryRadioSonic: return "Library Radio (Sonic)"
        case .hitsRadio: return "Only the Hits"
        case .hitsRadioSonic: return "Only the Hits (Sonic)"
        case .deepCutsRadio: return "Deep Cuts"
        case .deepCutsRadioSonic: return "Deep Cuts (Sonic)"
        case .genreRadio(let genre): return "\(genre) Radio"
        case .genreRadioSonic(let genre): return "\(genre) Radio (Sonic)"
        case .decadeRadio(_, _, let name): return "\(name) Radio"
        case .decadeRadioSonic(_, _, let name): return "\(name) Radio (Sonic)"
        case .ratingRadio(_, let name): return "\(name) Radio"
        case .ratingRadioSonic(_, let name): return "\(name) Radio (Sonic)"
        }
    }
    
    var category: String {
        switch self {
        case .libraryRadio, .libraryRadioSonic: return "Library"
        case .hitsRadio, .hitsRadioSonic: return "Popularity"
        case .deepCutsRadio, .deepCutsRadioSonic: return "Popularity"
        case .genreRadio, .genreRadioSonic: return "Genre"
        case .decadeRadio, .decadeRadioSonic: return "Decade"
        case .ratingRadio, .ratingRadioSonic: return "My Ratings"
        }
    }
    
    var isSonic: Bool {
        switch self {
        case .libraryRadioSonic, .hitsRadioSonic, .deepCutsRadioSonic, 
             .genreRadioSonic, .decadeRadioSonic, .ratingRadioSonic:
            return true
        default:
            return false
        }
    }
}

enum SubsonicRadioType: Equatable, Hashable {
    case libraryRadio
    case librarySimilar
    case genreRadio(String)
    case genreSimilar(String)
    case decadeRadio(start: Int, end: Int, name: String)
    case decadeSimilar(start: Int, end: Int, name: String)
    case starredRadio
    case starredSimilar

    var displayName: String {
        switch self {
        case .libraryRadio: return "Library Radio"
        case .librarySimilar: return "Library Radio (Similar)"
        case .genreRadio(let g): return "\(g) Radio"
        case .genreSimilar(let g): return "\(g) Radio (Similar)"
        case .decadeRadio(_, _, let n): return "\(n) Radio"
        case .decadeSimilar(_, _, let n): return "\(n) Radio (Similar)"
        case .starredRadio: return "Starred Radio"
        case .starredSimilar: return "Starred Radio (Similar)"
        }
    }
    var category: String {
        switch self {
        case .libraryRadio, .librarySimilar: return "Library"
        case .genreRadio, .genreSimilar: return "Genre"
        case .decadeRadio, .decadeSimilar: return "Decade"
        case .starredRadio, .starredSimilar: return "Starred"
        }
    }
}

/// A Jellyfin or Emby radio station: each plain, or as an Instant Mix seeded from it.
enum InstantMixRadioType: Equatable, Hashable {
    case libraryRadio
    case libraryInstantMix
    case genreRadio(String)
    case genreInstantMix(String)
    case decadeRadio(start: Int, end: Int, name: String)
    case decadeInstantMix(start: Int, end: Int, name: String)
    case favoritesRadio
    case favoritesInstantMix

    var displayName: String {
        switch self {
        case .libraryRadio: return "Library Radio"
        case .libraryInstantMix: return "Library Radio (Instant Mix)"
        case .genreRadio(let g): return "\(g) Radio"
        case .genreInstantMix(let g): return "\(g) Radio (Instant Mix)"
        case .decadeRadio(_, _, let n): return "\(n) Radio"
        case .decadeInstantMix(_, _, let n): return "\(n) Radio (Instant Mix)"
        case .favoritesRadio: return "Favorites Radio"
        case .favoritesInstantMix: return "Favorites Radio (Instant Mix)"
        }
    }
    var category: String {
        switch self {
        case .libraryRadio, .libraryInstantMix: return "Library"
        case .genreRadio, .genreInstantMix: return "Genre"
        case .decadeRadio, .decadeInstantMix: return "Decade"
        case .favoritesRadio, .favoritesInstantMix: return "Favorites"
        }
    }
}

extension InstantMixRadioType: BrowsableRadioStation {
    static func stations(genres: [String]) -> [Self] {
        [.libraryRadio, .libraryInstantMix, .favoritesRadio, .favoritesInstantMix]
            + genres.flatMap { [.genreRadio($0), .genreInstantMix($0)] }
            + RadioConfig.decades.flatMap {
                [.decadeRadio(start: $0.start, end: $0.end, name: $0.name),
                 .decadeInstantMix(start: $0.start, end: $0.end, name: $0.name)]
            }
    }
}

enum LocalRadioType: Equatable, Hashable {
    case libraryRadio
    case genreRadio(String)
    case decadeRadio(start: Int, end: Int, name: String)

    var displayName: String {
        switch self {
        case .libraryRadio: return "Library Radio"
        case .genreRadio(let g): return "\(g) Radio"
        case .decadeRadio(_, _, let n): return "\(n) Radio"
        }
    }
    var category: String {
        switch self {
        case .libraryRadio: return "Library"
        case .genreRadio: return "Genre"
        case .decadeRadio: return "Decade"
        }
    }
}
