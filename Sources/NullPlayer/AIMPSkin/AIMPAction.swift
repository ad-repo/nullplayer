/// One of AIMP's named actions (`acPlayerPlay`, `acMainShowPlaylist`…), read once from the name a
/// key's binding, a timer's link or a script gives it. The names are AIMP's own; NullPlayer carries
/// out the ones it has a counterpart for (`AIMPSkinAudioEngineHost`, the window's own in
/// `AIMPSkinMainView`), and any other, `unknown`, is logged once and dropped.
enum AIMPAction: Hashable, Sendable, CustomStringConvertible {
    case playerPlay, playerPause, playerPlayPause, playerStop, playerPrevTrack, playerNextTrack
    case playerShuffle, playerShuffleMode, playerRepeat, playerRepeatPlaylist, playerRepeatTrack
    case playerSeekForward, playerSeekBackward, playerVolumeUp, playerVolumeDown, playerVolumeMute
    case playerOpenFiles, playerOpen, playerRadioCapture, playerRepeatPartAB
    case mainExit, mainAbout, mainMinimize, mainStayOnTop, mainOpenFiles
    case mainDSPManager, mainDSPManagerEQ, mainShowPlaylist, mainShowMusicLibrary, mainShowEqualizer
    case equalizerSwitch, equalizerShow, visualizationShow
    case playlistShow, playlistAddFiles, playlistFocusedItemShowQTE, playlistOpenFolderWithSelectedFile
    case musicLibraryShow, musicLibraryAddFiles
    case playableFileShowFileInfoAtCursor, playableFileShowQTE
    case playableFileCopyInfoToClipboard, playableFileCopyFileToClipboard
    case sendToTagEditor, utilsTagEditor
    case options, optionSkins, searchQuick, searchAdvanced
    /// A name NullPlayer has no counterpart for, as the skin wrote it.
    case unknown(String)

    /// Every action NullPlayer knows: its AIMP name, and the words AIMP shows for it in a key's
    /// tooltip, where the skin's `Hint` binding names it.
    private static let table: [(action: AIMPAction, name: String, title: String?)] = [
        (.playerPlay, "acPlayerPlay", "Play"), (.playerPause, "acPlayerPause", "Pause"),
        (.playerPlayPause, "acPlayerPlayPause", "Play / Pause"), (.playerStop, "acPlayerStop", "Stop"),
        (.playerPrevTrack, "acPlayerPrevTrack", "Previous track"), (.playerNextTrack, "acPlayerNextTrack", "Next track"),
        (.playerShuffle, "acPlayerShuffle", "Shuffle"), (.playerShuffleMode, "acPlayerShuffleMode", nil),
        (.playerRepeat, "acPlayerRepeat", "Repeat"), (.playerRepeatPlaylist, "acPlayerRepeatPlaylist", nil),
        (.playerRepeatTrack, "acPlayerRepeatTrack", nil),
        (.playerSeekForward, "acPlayerSeekForward", "Fast forward"), (.playerSeekBackward, "acPlayerSeekBackward", "Rewind"),
        (.playerVolumeUp, "acPlayerVolumeUp", nil), (.playerVolumeDown, "acPlayerVolumeDown", nil),
        (.playerVolumeMute, "acPlayerVolumeMute", "Mute"),
        (.playerOpenFiles, "acPlayerOpenFiles", nil), (.playerOpen, "acPlayerOpen", nil),
        (.playerRadioCapture, "acPlayerRadioCapture", "Record"), (.playerRepeatPartAB, "acPlayerRepeatPartAB", "Repeat A–B"),
        (.mainExit, "acMainExit", "Exit"), (.mainAbout, "acMainAbout", nil), (.mainMinimize, "acMainMinimize", "Minimize"),
        (.mainStayOnTop, "acMainStayOnTop", "Stay on top"), (.mainOpenFiles, "acMainOpenFiles", "Open files"),
        (.mainDSPManager, "acMainDSPManager", "Sound effects"), (.mainDSPManagerEQ, "acMainDSPManagerEQ", nil),
        (.mainShowPlaylist, "acMainShowPlaylist", nil), (.mainShowMusicLibrary, "acMainShowMusicLibrary", nil),
        (.mainShowEqualizer, "acMainShowEqualizer", nil),
        (.equalizerSwitch, "acEqualizerSwitch", "Equalizer on / off"), (.equalizerShow, "acEqualizerShow", nil),
        (.visualizationShow, "acVisualizationShow", nil),
        (.playlistShow, "acPlaylistShow", nil), (.playlistAddFiles, "acPlaylistAddFiles", nil),
        (.playlistFocusedItemShowQTE, "acPlaylistFocusedItemShowQTE", nil),
        (.playlistOpenFolderWithSelectedFile, "acPlaylistOpenFolderWithSelectedFile", nil),
        (.musicLibraryShow, "acMusicLibraryShow", nil), (.musicLibraryAddFiles, "acMLAddFiles", nil),
        (.playableFileShowFileInfoAtCursor, "acPlayableFileShowFileInfoAtCursor", nil),
        (.playableFileShowQTE, "acPlayableFileShowQTE", nil),
        (.playableFileCopyInfoToClipboard, "acPlayableFileCopyInfoToClipboard", nil),
        (.playableFileCopyFileToClipboard, "acPlayableFileCopyFileToClipboard", nil),
        (.sendToTagEditor, "acSendToTagEditor", nil), (.utilsTagEditor, "acUtilsTagEditor", nil),
        (.options, "acOptions", nil), (.optionSkins, "acOptionSkins", nil),
        (.searchQuick, "acSearchQuick", nil), (.searchAdvanced, "acSearchAdvanced", nil),
    ]
    private static let byName = Dictionary(uniqueKeysWithValues: table.map { ($0.name, $0.action) })
    private static let entries = Dictionary(uniqueKeysWithValues: table.map { ($0.action, (name: $0.name, title: $0.title)) })

    /// The action an AIMP name (`ac…`) names; nil for anything else a binding reads (a provider, a
    /// counter, a form).
    init?(_ name: String) {
        guard name.hasPrefix("ac") else { return nil }
        self = Self.byName[name] ?? .unknown(name)
    }

    /// The name as AIMP writes it, which the action trace and the harness print.
    var name: String {
        if case .unknown(let name) = self { return name }
        return Self.entries[self]?.name ?? ""
    }

    /// The words AIMP shows for it (a key's tooltip), nil where NullPlayer has none.
    var title: String? { Self.entries[self]?.title }

    var description: String { name }
}
