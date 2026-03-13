import Foundation

/// User-configurable playback options for radio generation.
enum RadioPlaybackOptions {
    private enum Keys {
        static let maxTracksPerArtist = "radioMaxTracksPerArtist"
    }

    static let unlimitedMaxTracksPerArtist = 0
    static let defaultMaxTracksPerArtist = 2
    static let maxTracksPerArtistRange = 0...6
    static let menuChoices = [0, 1, 2, 3, 4, 5, 6]

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
}
