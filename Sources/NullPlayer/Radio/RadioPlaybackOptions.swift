import Foundation

/// User-configurable playback options for radio generation.
enum RadioPlaybackOptions {
    private enum Keys {
        static let maxTracksPerArtist = "radioMaxTracksPerArtist"
        static let playlistLength = "radioPlaylistLength"
    }

    static let unlimitedMaxTracksPerArtist = 0
    static let defaultMaxTracksPerArtist = 2
    static let maxTracksPerArtistRange = 0...6
    static let menuChoices = [0, 1, 2, 3, 4, 5, 6]
    static let defaultPlaylistLength = 100
    static let playlistLengthChoices = [100, 250, 500, 1_000, 10_000]

    /// Maximum number of tracks allowed per artist for non-sonic radio generation.
    static var maxTracksPerArtist: Int {
        get {
            let rawValue = UserDefaults.standard.object(forKey: Keys.maxTracksPerArtist) as? Int ?? defaultMaxTracksPerArtist
            return min(max(rawValue, maxTracksPerArtistRange.lowerBound), maxTracksPerArtistRange.upperBound)
        }
        set {
            let clamped = min(max(newValue, maxTracksPerArtistRange.lowerBound), maxTracksPerArtistRange.upperBound)
            UserDefaults.standard.set(clamped, forKey: Keys.maxTracksPerArtist)
        }
    }

    /// Number of tracks to generate for radio playlists.
    static var playlistLength: Int {
        get {
            let rawValue = UserDefaults.standard.object(forKey: Keys.playlistLength) as? Int ?? defaultPlaylistLength
            return playlistLengthChoices.contains(rawValue) ? rawValue : defaultPlaylistLength
        }
        set {
            let normalized = playlistLengthChoices.contains(newValue) ? newValue : defaultPlaylistLength
            UserDefaults.standard.set(normalized, forKey: Keys.playlistLength)
        }
    }

    /// When artist variety is disabled, avoid over-fetching remote candidates we will never use.
    static func candidateFetchLimit(for requestedLimit: Int, maxPerArtist: Int) -> Int {
        guard requestedLimit > 0 else { return 0 }
        if maxPerArtist <= unlimitedMaxTracksPerArtist {
            return requestedLimit
        }
        return requestedLimit * 3
    }
}
