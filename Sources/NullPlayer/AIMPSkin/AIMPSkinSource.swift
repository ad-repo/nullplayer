import Foundation

/// What a binding reads: a link's `Source` and `SourcePin`, resolved once as the skin loads against
/// what the skin names (`AIMPSkinIndex.Names`), so a frame evaluates it with one exhaustive switch
/// (`AIMPSkinDataflow.value`) rather than matching strings. Scripts naming a source at run time
/// (`BindingsGetDataAsInteger`) resolve the same way. Anything not modelled, including a typo, is
/// `.value(0)`: what AIMP's own unknown pins read (`reference/layout.md` § *Visibility*).
indirect enum AIMPSkinSource: Sendable, Equatable {
    /// A tabbed group's page (`ActivePage`).
    case page(group: String)
    /// `IsActive`: whether the pointer is over a named item or control as last drawn; where the
    /// window has no pointer or has not drawn it (the probe), what the rest of the pin reads.
    case pointerOver(String, otherwise: AIMPSkinSource)
    /// `AnimationFrameIndex` of an animator that keeps its own frame; else what the rest reads.
    case animatorFrame(String, otherwise: AIMPSkinSource)
    /// An item's or form's visibility (any pin of it but `Maximize`).
    case item(String)
    case value(Double)
    /// The player (`AIMPSkinHostState`).
    case player(PlayerPin)
    /// Whether the playlist runs past its window: its scroll bar shows only then (Onkyo TA-2250's
    /// `PlaylistScrollBarHost`).
    case playlistScrolls
    /// The library table's totals, following the window's group and search.
    case table(TablePin)
    case libraryScanning, libraryGrouping
    /// The skin's own providers (`Schema.xml`): a commutator's `Result`, a concatenator's `Result`,
    /// a counter's `Position`.
    case commutator(String)
    case concatenator(String)
    case counter(String)

    enum TablePin: Sendable { case count, duration, size }

    /// A player pin, as `AIMPSkinHostState.value(_:)` reads it.
    enum PlayerPin: Sendable, Equatable {
        /// `prvVolume`'s `Position` as 0–1 (scripts set it so: Sony TC-MR2), its other pins 0–100.
        case volumeFraction, volume, balance, playState, timeOfDay, duration, elapsed, progress, hasCoverArt
        case playlistCount, playlistDuration, playlistSize
        case bitrate, sampleRate, channels, rating, ratingAvailable
        /// A clock's colon blinks each second (Revox B-710).
        case clockFlash
        case tracksStarted, tracksFinished, remaining
        /// The sleep timer's time left (`prvSleepTime`, `prvScheduler`): NullPlayer has none, so 0:00.
        case sleepTimer
        case levelL, levelR
        case nightMode, shuffle, repeatAll, stayOnTop, muted, equalizerOn
        /// NullPlayer's window for a form the skin does not draw (`AIMPFormRole.isOpen`).
        case window(AIMPFormRole)

        /// The pin `source`.`pin` of the player, nil for anything else.
        init?(_ source: String, _ pin: String) {
            switch (source, pin) {
            // Scripts ask an action whether it is on as `Checked`: Denon Classic Style's speakers
            // script mutes when its speakers go off unless already muted, and read as never muted it
            // took every mute straight back.
            case (_, "Checked"): self.init(source, "State")
            case ("prvVolume", "Position"): self = .volumeFraction
            case ("prvVolume", _): self = .volume
            case ("prvBalance", _): self = .balance
            case ("prvPlayerState", "State"): self = .playState
            case ("prvSystemTime", "Time"): self = .timeOfDay
            case ("prvPlayerState", "TrackDuration"), ("prvPlayerState", "PositionMax"), ("prvPlayingFileInfo", "Duration"): self = .duration
            case ("prvPlayerState", "TrackPosition"), ("prvPlayerState", "Position"): self = .elapsed
            case ("prvPlayerState", "Progress"): self = .progress
            case ("prvPlayingFileInfo", "CoverArt"): self = .hasCoverArt
            case ("Playlist", "Count"): self = .playlistCount
            case ("Playlist", "Duration"): self = .playlistDuration
            case ("Playlist", "Size"): self = .playlistSize
            // AIMP reads pin names without regard to case; skins spell this one both ways.
            case ("prvPlayingFileInfo", "BitRate"), ("prvPlayingFileInfo", "Bitrate"): self = .bitrate
            case ("prvPlayingFileInfo", "SampleRate"): self = .sampleRate
            case ("prvPlayingFileInfo", "Channels"): self = .channels
            case ("prvPlayingFileInfo", "Mark"): self = .rating
            case ("prvPlayingFileInfo", "MarkAvailable"): self = .ratingAvailable
            case ("prvSystemTime", "Flashing"): self = .clockFlash
            case ("prvSleepTime", "Time"), ("prvScheduler", "Time"): self = .sleepTimer
            case ("prvPlayerState", "OnTrackStarted"): self = .tracksStarted
            case ("prvPlayerState", "OnTrackFinished"): self = .tracksFinished
            case ("prvPlayerState", "TrackPositionRemaining"): self = .remaining
            case ("prvVisual", "LevelL"): self = .levelL
            case ("prvVisual", "LevelR"): self = .levelR
            case ("prvPlayerPosition", _): self = .elapsed
            // Vega MP-120's tape counter is a script object counting playback seconds; until scripts
            // run, it is fed them directly.
            case ("CounterPosition", "Position"): self = .elapsed
            case ("AIMPMainForm", "NightMode"): self = .nightMode
            case ("acPlayerShuffle", "State"), ("acPlayerShuffleMode", "State"): self = .shuffle
            case ("acPlayerRepeat", "State"), ("acPlayerRepeatPlaylist", "State"): self = .repeatAll
            case ("acMainStayOnTop", "State"): self = .stayOnTop
            case ("acPlayerVolumeMute", "State"): self = .muted
            case ("acEqualizerSwitch", "State"): self = .equalizerOn
            // NullPlayer's windows, under whatever prefix the skin gives them (`TA2066_PlaylistWindow`).
            case (let frame, "Visible") where AIMPFormRole(frame).hasWindow: self = .window(AIMPFormRole(frame))
            default: return nil
            }
        }
    }

    /// `source`.`pin`, as the skin's `names` make it.
    init(_ source: String, _ pin: String, names: AIMPSkinIndex.Names) {
        if names.groups.contains(source), pin == "ActivePage" {
            self = .page(group: source)
            return
        }
        let rest = Self.rest(source, pin, names: names)
        switch pin {
        case "IsActive": self = .pointerOver(source, otherwise: rest)
        case "AnimationFrameIndex": self = .animatorFrame(source, otherwise: rest)
        default: self = rest
        }
    }

    private static func rest(_ source: String, _ pin: String, names: AIMPSkinIndex.Names) -> AIMPSkinSource {
        // A form's window is not maximized (Sony Media Tower Reborn's restore glyph showed). A list's
        // totals are the list's, though the skin names an item after it (Dark Blocks' `Playlist`).
        let listTotal = AIMPSkinList(rawValue: source) != nil && ["Count", "Duration", "Size"].contains(pin)
        if names.items.contains(source), !listTotal { return pin == "Maximize" ? .value(0) : .item(source) }
        switch (source, pin) {
        case ("Main", "IsActive"), ("AIMPMainForm", "Visible"), ("AIMPMainForm", "IsActive"): return .value(1)
        case ("AIMPMainForm", "StayOnTop"): return .player(.stayOnTop)
        // AIMP 5: skins hide their speakers and warn below 4.6 (`< 4600`, or `< 460`).
        case ("acMainAbout", "Version"): return .value(5_000)
        case ("Playlist", "Scrolling"): return .playlistScrolls
        case ("MLTable", "Count"): return .table(.count)
        case ("MLTable", "Duration"): return .table(.duration)
        case ("MLTable", "Size"): return .table(.size)
        case ("prvMusicLibraryManager", "BackgroundTaskCount"): return .libraryScanning
        case ("prvMusicLibraryManager", "GroupingPresets"): return .libraryGrouping
        default: break
        }
        if let player = PlayerPin(source, pin) { return .player(player) }
        switch (names.providers[source], pin) {
        case (.commutator?, "Result"): return .commutator(source)
        case (.concatenator?, "Result"): return .concatenator(source)
        case (.counter?, "Position"): return .counter(source)
        default: return .value(0)
        }
    }
}
