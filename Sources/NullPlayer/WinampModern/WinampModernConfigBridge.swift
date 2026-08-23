import Foundation

/// The `cfgattrib="{GUID};Name"` attributes that address **host state** rather than skin-private
/// storage.
///
/// Most of a skin's `cfgattrib` bindings are its own preferences — Defix's nine display switches, a
/// notifier's corner, a songticker mode — and those belong in `WinampModernConfiguration`, which is
/// where every unbridged attribute still goes. A handful are not the skin's at all: they are
/// Winamp's own playback options, which the skin merely *draws*. Storing those in the skin's
/// namespace gives one setting two homes, and the copies drift the moment either side moves — a
/// shuffle toggled from the menu bar leaves the skin's lamp dark, and a lamp lit from the skin
/// shuffles nothing.
///
/// Measured demand across the 30 installed skins, which is why these four and no others:
/// `Repeat` ×52, `Shuffle` ×50, `Enable crossfading` ×32, `Crossfade time` ×12. The next candidate
/// is `{280876CF-…};Always on top` ×9, which is a *window* property rather than a host one and is
/// deliberately not bridged here. `{0000000A-…};Random` ×15 is AVS preset randomisation, not
/// playlist shuffle, and is correctly skin-private.
///
/// The GUIDs are Winamp's published configuration identifiers, matched case-insensitively because
/// skins are inconsistent about the hex case (`{1AB968B3-8687-4a35-…}` ships both ways in one
/// corpus).
enum WinampModernConfigBridge {

    enum Attribute: CaseIterable {
        /// Playlist component: shuffle playback.
        case shuffle
        /// Playlist component: repeat playback. mmd3 also writes `cfgval="2"` on this button, which
        /// is Winamp's tri-state repeat; NullPlayer's engine has one flag, so the value stays 0/1.
        case repeatPlayback
        /// Crossfading on/off.
        case crossfadeEnabled
        /// Crossfade length. The one bridged attribute that is not a flag.
        case crossfadeSeconds

        var section: String {
            switch self {
            case .shuffle, .repeatPlayback: return "{45F3F7C1-A6F3-4EE6-A15E-125E92FC3F8D}"
            case .crossfadeEnabled: return "{FC3EAF78-C66E-4ED2-A0AA-1494DFCC13FF}"
            case .crossfadeSeconds: return "{F1239F09-8CC6-4081-8519-C2AE99FCB14C}"
            }
        }

        var key: String {
            switch self {
            case .shuffle: return "Shuffle"
            case .repeatPlayback: return "Repeat"
            case .crossfadeEnabled: return "Enable crossfading"
            case .crossfadeSeconds: return "Crossfade time"
            }
        }

        /// Whether this attribute reads as a lamp (0/1) or as a number. A `<togglebutton>` asks the
        /// first question and a `<slider>` the second, and only the flags may light an `activeimage`.
        var isFlag: Bool { self != .crossfadeSeconds }
    }

    /// The seconds a skin may drive into the crossfade, clamped to the range NullPlayer's own
    /// **Fade Duration** menu offers. Winamp's sliders are cut wider — mmd3's is `high="20"` — and a
    /// skin is untrusted markup, so its range is mapped into ours rather than accepted as given. A
    /// drag past the top pins here, and because the skin reads its position back from the host the
    /// readout shows the clamped value rather than lying about a duration the engine never took.
    static let crossfadeSecondsRange: ClosedRange<Int32> = 1...10

    /// The bridged attribute a `{GUID};Name` pair names, or nil when it is the skin's own.
    static func attribute(section: String, key: String) -> Attribute? {
        Attribute.allCases.first {
            $0.section.caseInsensitiveCompare(section) == .orderedSame
                && $0.key.caseInsensitiveCompare(key) == .orderedSame
        }
    }

    static func value(of attribute: Attribute, host: WinampModernHost) -> Int32 {
        switch attribute {
        case .shuffle: return host.shuffleEnabled ? 1 : 0
        case .repeatPlayback: return host.repeatEnabled ? 1 : 0
        case .crossfadeEnabled: return host.crossfadeEnabled ? 1 : 0
        case .crossfadeSeconds: return clampedSeconds(Int32(clamping: host.crossfadeSeconds))
        }
    }

    static func setValue(_ value: Int32, of attribute: Attribute, host: WinampModernHost) {
        switch attribute {
        case .shuffle: host.shuffleEnabled = value != 0
        case .repeatPlayback: host.repeatEnabled = value != 0
        case .crossfadeEnabled: host.crossfadeEnabled = value != 0
        case .crossfadeSeconds: host.crossfadeSeconds = Int(clampedSeconds(value))
        }
    }

    private static func clampedSeconds(_ value: Int32) -> Int32 {
        min(max(value, crossfadeSecondsRange.lowerBound), crossfadeSecondsRange.upperBound)
    }
}
