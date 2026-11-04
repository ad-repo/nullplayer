import Foundation

/// A form's part in the player, read from its name, whatever prefix or suffix the skin gives it
/// (`TA2066_PlaylistWindow`, `PLWin`, `RX80_MusicLibraryFrame`, `EqualizerFrame`). One place
/// reads form names: what NullPlayer window stands for it, what a key bound to its `Visible` opens
/// and whether that is open (the host's window pins), and a companion's title and side.
/// AIMP's role names are case-sensitive; the title and side read the skin's own names (`EQForm`,
/// `LSpeaker`), which are no role.
enum AIMPFormRole: Equatable {
    case main, menu, equalizer, visualization, info, lyrics, tray, dropWheel, quickFileInfo, playlist, library, other

    init(_ name: String) {
        switch name {
        case "AIMPMainForm": self = .main
        // A skin-drawn menu window (AIMP-Cassette's, TC-MR2's).
        case "Menu": self = .menu
        case let n where n.contains("Equalizer"): self = .equalizer
        case let n where n.contains("Visualization"): self = .visualization
        case let n where n.contains("InfoFrame") || n.contains("InfoBox"): self = .info
        case let n where n.contains("Lyrics"): self = .lyrics
        case let n where n.contains("TrayControl"): self = .tray
        case let n where n.contains("DropWheel"): self = .dropWheel
        case let n where n.contains("QFI"): self = .quickFileInfo
        case let n where n.contains("Playlist") || n == "PLWin": self = .playlist
        case let n where n.contains("MusicLibrary"): self = .library
        default: self = .other
        }
    }

    /// What a key bound to the form's `Visible` does where NullPlayer has the window: AIMP's own
    /// windows the skin does not draw open NullPlayer's; a skin-drawn menu window (AIMP-Cassette's,
    /// TC-MR2's) opens NullPlayer's menu. Nil for a form the skin draws.
    var opens: AIMPSkinTarget.Kind? {
        switch self {
        case .equalizer: return .action(.equalizerShow)
        case .visualization: return .action(.visualizationShow)
        case .info: return .action(.playableFileShowFileInfoAtCursor)
        case .menu: return .menu(nil)
        case .playlist: return .action(.playlistShow)
        case .library: return .action(.mainShowMusicLibrary)
        case .main, .lyrics, .tray, .dropWheel, .quickFileInfo, .other: return nil
        }
    }

    /// Whether NullPlayer keeps a window for the form whose being open a binding to its `Visible`
    /// reads (`isOpen`).
    var hasWindow: Bool {
        switch self {
        case .playlist, .library, .equalizer, .visualization: return true
        case .main, .menu, .info, .lyrics, .tray, .dropWheel, .quickFileInfo, .other: return false
        }
    }

    /// Whether NullPlayer's window for the form is open; false for one it keeps none of.
    func isOpen(in player: AIMPSkinPlayerSnapshot) -> Bool {
        switch self {
        case .playlist: return player.playlistVisible
        case .library: return player.libraryVisible
        case .equalizer: return player.equalizerVisible
        case .visualization: return player.visualizationVisible
        case .main, .menu, .info, .lyrics, .tray, .dropWheel, .quickFileInfo, .other: return false
        }
    }

    /// A readable name for a form a skin gave no `DisplayName` (`PLWin`, `EQForm`,
    /// `Amplifier_Window`), for the context menu: a list AIMP has its own word for, else the name's
    /// words without Window, Form or Frame.
    static func title(ofForm name: String, role: AIMPSkin.Companion.Role) -> String {
        switch role {
        case .playlist: return "Playlist"
        case .library: return "Music Library"
        case .other: break
        }
        let lower = name.lowercased()
        for (keys, title) in [(["equalizer", "eqform", "eqwin"], "Equalizer"), (["cover"], "Cover Art"),
                              (["speaker", "boxes"], "Speakers"), (["visual"], "Visualization")]
            where keys.contains(where: lower.contains) {
            return title
        }
        // `Amplifier_Window` → Amplifier, `MusicLightWindow` → Music Light, `Win_1` → Window 1.
        let spaced = name.replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "([a-z])([A-Z])", with: "$1 $2", options: .regularExpression)
        let words = spaced.split(separator: " ").filter { !["window", "win", "form", "frame"].contains($0.lowercased()) }
        guard !words.isEmpty else { return name }
        let title = words.joined(separator: " ")
        return words.allSatisfy { $0.allSatisfy(\.isNumber) } ? "Window " + title : title
    }

    /// The side of the deck a companion opens on when neither `Schema.xml` nor the layout says:
    /// left and right speakers beside it (`LSpeaker`, `SpeakerRightWindow`), anything else below.
    static func side(ofForm name: String) -> AIMPSkin.Companion.Placement {
        let lower = name.lowercased()
        return lower.contains("left") || name.hasPrefix("LSpeaker") ? .left
            : lower.contains("right") || name.hasPrefix("RSpeaker") ? .right : .below
    }

    /// Windows NullPlayer shows its own of, so the skin's form is not opened: the info and lyrics
    /// windows, the visualization, the tray's panel, the drop wheel, quick file info, and the
    /// skin-drawn menu (NullPlayer's menu stands in).
    var isNullPlayers: Bool {
        switch self {
        case .info, .lyrics, .visualization, .tray, .dropWheel, .quickFileInfo, .menu: return true
        case .main, .equalizer, .playlist, .library, .other: return false
        }
    }
}
