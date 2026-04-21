//
//  UserDefaults+Keys.swift
//  NullPlayer
//
//  Centralized UserDefaults key names.
//
//  Every UserDefaults key used in the app is declared here as a static
//  constant on `UserDefaults.Key`. Call sites pass the constant instead
//  of a string literal:
//
//      UserDefaults.standard.set(value, forKey: .mainWindowFrame)
//      let x = UserDefaults.standard.string(forKey: .modernSkinName)
//
//  Benefits:
//    * Compile-time checking prevents typos
//    * Rename refactors work (string literals don't)
//    * Single place to audit what the app persists
//    * Avoids silent key collisions
//
//  The raw string values MUST remain stable across releases — changing
//  them orphans existing users' saved settings.
//

import Foundation

// MARK: - Key type

extension UserDefaults {

    /// Type-safe wrapper for a UserDefaults key name.
    ///
    /// Backed by a String raw value that matches the legacy key names
    /// used before centralization, so existing preferences continue to
    /// load after upgrading.
    ///
    /// All known keys are declared as static constants on this type so
    /// that dot-shorthand works at call sites:
    ///
    ///     UserDefaults.standard.bool(forKey: .modernUIEnabled)
    ///
    struct Key: RawRepresentable, Hashable, ExpressibleByStringLiteral {
        let rawValue: String
        init(rawValue: String) { self.rawValue = rawValue }
        init(stringLiteral value: String) { self.rawValue = value }
    }
}

// MARK: - Key constants

extension UserDefaults.Key {

    // MARK: Window frames

    static let artVisualizerWindowFrame: Self = "ArtVisualizerWindowFrame"
    static let equalizerWindowFrame:     Self = "EqualizerWindowFrame"
    static let mainWindowFrame:          Self = "MainWindowFrame"
    static let playlistWindowFrame:      Self = "PlaylistWindowFrame"
    static let plexBrowserWindowFrame:   Self = "PlexBrowserWindowFrame"
    static let projectMWindowFrame:      Self = "ProjectMWindowFrame"
    static let spectrumWindowFrame:      Self = "SpectrumWindowFrame"
    static let videoPlayerWindowFrame:   Self = "VideoPlayerWindowFrame"
    static let waveformWindowFrame:      Self = "WaveformWindowFrame"

    // MARK: Window layout

    static let hideTitleBars:        Self = "hideTitleBars"
    static let isAlwaysOnTop:        Self = "isAlwaysOnTop"
    static let isWindowLayoutLocked: Self = "isWindowLayoutLocked"

    // MARK: Library browser — columns

    static let browserColumnSortAscending:   Self = "BrowserColumnSortAscending"
    static let browserColumnSortId:          Self = "BrowserColumnSortId"
    static let browserColumnWidths:          Self = "BrowserColumnWidths"
    static let browserVisibleAlbumColumns:   Self = "BrowserVisibleAlbumColumns"
    static let browserVisibleArtistColumns:  Self = "BrowserVisibleArtistColumns"
    static let browserVisibleTrackColumns:   Self = "BrowserVisibleTrackColumns"
    static let showBrowserArtworkBackground: Self = "showBrowserArtworkBackground"

    // MARK: Library browser — visualization

    static let browserVisDefaultEffect: Self = "browserVisDefaultEffect"
    static let browserVisEffect:        Self = "browserVisEffect"
    static let browserVisIntensity:     Self = "browserVisIntensity"

    // MARK: Plex

    static let plexCurrentLibraryID: Self = "PlexCurrentLibraryID"
    static let plexCurrentServerID:  Self = "PlexCurrentServerID"

    // MARK: Jellyfin

    static let jellyfinCurrentMovieLibraryID: Self = "JellyfinCurrentMovieLibraryID"
    static let jellyfinCurrentMusicLibraryID: Self = "JellyfinCurrentMusicLibraryID"
    static let jellyfinCurrentServerID:       Self = "JellyfinCurrentServerID"
    static let jellyfinCurrentShowLibraryID:  Self = "JellyfinCurrentShowLibraryID"

    // MARK: Emby

    static let embyCurrentMovieLibraryID: Self = "EmbyCurrentMovieLibraryID"
    static let embyCurrentMusicLibraryID: Self = "EmbyCurrentMusicLibraryID"
    static let embyCurrentServerID:       Self = "EmbyCurrentServerID"
    static let embyCurrentShowLibraryID:  Self = "EmbyCurrentShowLibraryID"

    // MARK: Subsonic

    static let subsonicCurrentMusicFolderID: Self = "SubsonicCurrentMusicFolderID"
    static let subsonicCurrentServerID:      Self = "SubsonicCurrentServerID"

    // MARK: Radio

    static let radioAutoReconnect:           Self = "RadioAutoReconnect"
    static let embyRadioHistoryInterval:     Self = "embyRadioHistoryInterval"
    static let jellyfinRadioHistoryInterval: Self = "jellyfinRadioHistoryInterval"
    static let localRadioHistoryInterval:    Self = "localRadioHistoryInterval"
    static let plexRadioHistoryInterval:     Self = "plexRadioHistoryInterval"
    static let subsonicRadioHistoryInterval: Self = "subsonicRadioHistoryInterval"

    // MARK: Equalizer

    static let eqAutoEnabled: Self = "EQAutoEnabled"

    // MARK: Audio output / playback

    static let gaplessPlaybackEnabled:     Self = "gaplessPlaybackEnabled"
    static let selectedOutputDeviceUID:    Self = "selectedOutputDeviceUID"
    static let sweetFadeDuration:          Self = "sweetFadeDuration"
    static let sweetFadeEnabled:           Self = "sweetFadeEnabled"
    static let timeDisplayMode:            Self = "timeDisplayMode"
    static let volumeNormalizationEnabled: Self = "volumeNormalizationEnabled"

    // MARK: Skin

    static let lastClassicSkinPath:       Self = "lastClassicSkinPath"
    static let modernSkinName:            Self = "modernSkinName"
    static let modernUIEnabled:           Self = "modernUIEnabled"
    static let visClassicFitToWidth:      Self = "visClassicFitToWidth"
    static let visClassicLastProfileName: Self = "visClassicLastProfileName"

    // MARK: Main-window visualization

    static let mainWindowDecayMode:         Self = "mainWindowDecayMode"
    static let mainWindowFlameIntensity:    Self = "mainWindowFlameIntensity"
    static let mainWindowFlameStyle:        Self = "mainWindowFlameStyle"
    static let mainWindowLightningStyle:    Self = "mainWindowLightningStyle"
    static let mainWindowMatrixColorScheme: Self = "mainWindowMatrixColorScheme"
    static let mainWindowMatrixIntensity:   Self = "mainWindowMatrixIntensity"
    static let mainWindowNormalizationMode: Self = "mainWindowNormalizationMode"
    static let mainWindowVisMode:           Self = "mainWindowVisMode"
    static let modernMainWindowVisMode:     Self = "modernMainWindowVisMode"

    // MARK: Shared visualization settings

    static let flameIntensity:          Self = "flameIntensity"
    static let flameStyle:              Self = "flameStyle"
    static let lightningStyle:          Self = "lightningStyle"
    static let matrixColorScheme:       Self = "matrixColorScheme"
    static let matrixIntensity:         Self = "matrixIntensity"
    static let visualizationEngineType: Self = "visualizationEngineType"

    // MARK: Spectrum window

    static let spectrumDecayMode:         Self = "spectrumDecayMode"
    static let spectrumNormalizationMode: Self = "spectrumNormalizationMode"
    static let spectrumQualityMode:       Self = "spectrumQualityMode"

    // MARK: ProjectM

    static let projectMBeatSensitivity: Self = "projectMBeatSensitivity"
    static let projectMLowPowerMode:    Self = "projectMLowPowerMode"
    static let projectMPCMGain:         Self = "projectMPCMGain"

    // MARK: Waveform

    static let waveformHideTooltip:   Self = "waveformHideTooltip"
    static let waveformShowCuePoints: Self = "waveformShowCuePoints"

    // MARK: Migrations / housekeeping

    static let trackArtistsBackfillComplete: Self = "trackArtistsBackfillComplete"
}

// MARK: - UserDefaults convenience accessors taking typed keys

extension UserDefaults {

    // Reading

    func object(forKey key: Key) -> Any?               { object(forKey: key.rawValue) }
    func string(forKey key: Key) -> String?             { string(forKey: key.rawValue) }
    func array(forKey key: Key) -> [Any]?               { array(forKey: key.rawValue) }
    func dictionary(forKey key: Key) -> [String: Any]?  { dictionary(forKey: key.rawValue) }
    func stringArray(forKey key: Key) -> [String]?      { stringArray(forKey: key.rawValue) }
    func data(forKey key: Key) -> Data?                 { data(forKey: key.rawValue) }
    func bool(forKey key: Key) -> Bool                  { bool(forKey: key.rawValue) }
    func integer(forKey key: Key) -> Int                { integer(forKey: key.rawValue) }
    func float(forKey key: Key) -> Float                { float(forKey: key.rawValue) }
    func double(forKey key: Key) -> Double              { double(forKey: key.rawValue) }
    func url(forKey key: Key) -> URL?                   { url(forKey: key.rawValue) }

    // Writing
    //
    // We mirror each Foundation setter overload so that Swift's overload
    // resolution picks the same typed variant it would for String keys.
    // Without the full set, Swift reports "ambiguous use" or
    // "cannot resolve member" at call sites where the value type
    // (Int, Bool, etc.) would normally disambiguate.

    func set(_ value: Any?, forKey key: Key)   { set(value, forKey: key.rawValue) }
    func set(_ value: Bool, forKey key: Key)   { set(value, forKey: key.rawValue) }
    func set(_ value: Int, forKey key: Key)    { set(value, forKey: key.rawValue) }
    func set(_ value: Float, forKey key: Key)  { set(value, forKey: key.rawValue) }
    func set(_ value: Double, forKey key: Key) { set(value, forKey: key.rawValue) }
    func set(_ value: URL?, forKey key: Key)   { set(value, forKey: key.rawValue) }

    // Deleting / checking

    func removeObject(forKey key: Key) { removeObject(forKey: key.rawValue) }
    func contains(_ key: Key) -> Bool  { object(forKey: key.rawValue) != nil }
}
