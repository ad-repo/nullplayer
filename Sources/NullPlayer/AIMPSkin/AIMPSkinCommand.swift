import Foundation

/// What a skin asks of the player: from a key, a timer, a script or the skin's own lists, handed to
/// `AIMPSkinRuntime.onAction` and carried out by `AIMPSkinAudioEngineHost.perform`.
enum AIMPSkinCommand: Hashable, Sendable, CustomStringConvertible {
    /// One of AIMP's named actions (`acPlayerPlay`, `acMainShowPlaylist`…); one NullPlayer has no
    /// counterpart for is logged once and dropped.
    case action(AIMPAction)
    /// A script set the player's position (Technics' counter reset rewinds to 0).
    case seek(seconds: Double)
    /// A seek bar dragged or wheeled to a fraction of the track, 0–1 (a script's `seek` is in seconds,
    /// as the skin writes it).
    case position(Double)
    /// A script set the volume, 0–1.
    case volume(Double)
    /// A script set the balance, −1…1.
    case balance(Double)
    /// A script set the speed or tempo, as a multiplier.
    case speed(Double)
    /// A script set a NullPlayer EQ band, in dB (AIMP bands that share one are averaged).
    case equalizerBand(Int, dB: Double)
    case preamp(dB: Double)
    /// A slider, knob or script set a provider's value, 0–1. An effect NullPlayer lacks
    /// (`prvReverb`…) is kept so its knob reads it back.
    case setValue(provider: AIMPSkinProvider, Double)
    /// A row of the skin's own playlist, double-clicked or entered.
    case playRow(Int)
    /// A row of the skin's own playlist taken out (Delete, its menu).
    case removeRow(Int)
    /// A library track, double-clicked in the skin's library window: added to the playlist and played.
    case playLibraryTrack(UUID)

    /// The form the action trace and the harness print.
    var description: String {
        switch self {
        case .action(let action): return action.name
        case .seek(let seconds): return "seek:\(seconds)"
        case .position(let fraction): return "position:\(fraction)"
        case .volume(let volume): return "volume:\(volume)"
        case .balance(let balance): return "balance:\(balance)"
        case .speed(let speed): return "speed:\(speed)"
        case .equalizerBand(let band, let dB): return "eq:\(band):\(dB)"
        case .preamp(let dB): return "preamp:\(dB)"
        case .setValue(let provider, let value): return "set:\(provider):\(value)"
        case .playRow(let row): return "play:\(row)"
        case .removeRow(let row): return "remove:\(row)"
        case .playLibraryTrack(let id): return "libplay:\(id.uuidString)"
        }
    }
}
