import Foundation
@testable import NullPlayer

extension AppStateManager.AppState {
    /// A minimal saved session: every required field at a neutral value. Tests set the fields
    /// they are about, so a new required field is added here and nowhere else.
    static func fixture() -> Self {
        Self(
            isPlaylistVisible: false,
            isEqualizerVisible: false,
            isPlexBrowserVisible: false,
            isProjectMVisible: false,
            mainWindowFrame: nil,
            playlistWindowFrame: nil,
            equalizerWindowFrame: nil,
            plexBrowserWindowFrame: nil,
            projectMWindowFrame: nil,
            volume: 0.75,
            balance: 0,
            shuffleEnabled: false,
            repeatEnabled: false,
            gaplessPlaybackEnabled: false,
            volumeNormalizationEnabled: false,
            sweetFadeEnabled: false,
            sweetFadeDuration: 5,
            eqEnabled: false,
            eqAutoEnabled: false,
            eqPreamp: 0,
            eqBands: Array(repeating: 0, count: 10),
            eqBandsByLayout: [:],
            playlistTracks: [],
            currentTrackIndex: -1,
            playbackPosition: 0,
            wasPlaying: false,
            timeDisplayMode: TimeDisplayMode.elapsed.rawValue,
            isAlwaysOnTop: false
        )
    }
}
