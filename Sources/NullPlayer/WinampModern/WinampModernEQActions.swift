import Foundation

/// What an `EQ_*` action on a skin control means, decoded once.
///
/// Skins express the same equalizer three different ways — CornerAmp writes
/// `action="EQ_PREAMP"`, mmd3 and Winamp Modern write `action="EQ_BAND" param="1"`, and ClassicPro
/// writes `EQ_BAND param="preamp"` for the same control — and the parameter is **1-based** where the
/// engine's bands are 0-based. Decoding it in each of the renderer, the view, and the script bridge
/// is how one of them ends up off by one, so all three come here.
enum WinampModernEQAction: Equatable {
    case preamp
    /// Engine band index, 0-based.
    case band(Int)

    /// Number of bands NullPlayer's classic10 equalizer has.
    static let bandCount = 10

    /// Decode an action + param pair. `nil` means "not an equalizer control", which includes a
    /// malformed or out-of-range parameter: an `EQ_BAND param="99"` must be inert, never band 9.
    static func decode(action: String?, parameter: String?) -> WinampModernEQAction? {
        switch action?.trimmingCharacters(in: .whitespaces).uppercased() {
        case "EQ_PREAMP":
            return .preamp
        case "EQ_BAND":
            let raw = parameter?.trimmingCharacters(in: .whitespaces).lowercased() ?? ""
            if raw == "preamp" { return .preamp }
            // Winamp numbers the bands 1…10 in XML; the engine indexes 0…9.
            guard let oneBased = Int(raw), (1...bandCount).contains(oneBased) else { return nil }
            return .band(oneBased - 1)
        default:
            return nil
        }
    }

    /// The current value of this control, 0…1 bottom-to-top, from an EQ snapshot.
    func normalizedValue(in snapshot: WinampModernEQSnapshot) -> CGFloat {
        let gain: Float
        switch self {
        case .preamp: gain = snapshot.preampDB
        case .band(let index): gain = snapshot.bandGainsDB.indices.contains(index)
            ? snapshot.bandGainsDB[index] : 0
        }
        return CGFloat((gain + 12) / 24)
    }

    /// Apply a 0…1 position, bottom-to-top, as ±12 dB.
    func apply(normalized: CGFloat, to host: WinampModernComponentHost) {
        let gainDB = Float(max(0, min(1, normalized)) * 24 - 12)
        switch self {
        case .preamp: host.equalizerSetPreampDB(gainDB)
        case .band(let index): host.equalizerSetBandGainDB(index, gainDB: gainDB)
        }
    }
}
