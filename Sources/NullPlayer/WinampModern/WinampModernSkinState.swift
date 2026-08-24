import Foundation

/// What the **host** remembers about a `.wal` skin between launches (B44).
///
/// A skin's own preferences already survive on their own: `setPrivateInt`/`setPrivateString` and
/// `cfgattrib` write straight into `WinampModernConfiguration`, namespaced per skin, and a skin that
/// wants to remember something about itself does exactly that. What is collected here is the short
/// list the **engine** owns instead — state that lives in the object graph, which is rebuilt from the
/// markup on every load, so nothing about it survives unless we save it:
///
/// | State | Section | Key |
/// |---|---|---|
/// | A `<Wasabi:Frame>`'s divider offset | `@nullplayer.frames` | `container-id/frame-id` |
/// | Which layout a container is on (shade) | `@nullplayer.layouts` | `container-id` |
/// | Whether one of the skin's windows is open | `@nullplayer.windows` | `container-id` |
///
/// Two things are deliberately **not** here. The active colour theme is already persisted by
/// `WasabiColorThemeList` under `appearance/theme`, which is where a skin's own script would look for
/// it. And a window's frame on screen belongs to the *player's* window rather than to the skin, so it
/// goes through `AppStateManager` with everything else the app restores.
///
/// **The rule every entry obeys: a state the *user* set is a preference and survives; a state the
/// skin's own script set is the author's default and does not.** A splitter is stored from mouse-up
/// and from nowhere else; a layout from a `SWITCH` on a control the user clicked; a window from a
/// menu item, a skin button or a close box. A script's `setPosition`, `switchToLayout` or `hide()` is
/// the skin describing *this* run, and recording it would freeze the author's opening layout into a
/// preference the user never expressed — Big Bento's `setPosition(434)` is a genuine "narrow player,
/// wide playlist" default, not a defect to be overridden.
///
/// Keys are the names that survive a reload — a container's and an object's `id`. `stableID` is a
/// per-load counter and would address a different object next launch, so an object with no `id` is
/// skipped rather than given a positional key a markup edit would silently reassign.
enum WinampModernSkinState {

    // MARK: - Sections

    static let framesSection = "@nullplayer.frames"
    static let layoutsSection = "@nullplayer.layouts"
    static let windowsSection = "@nullplayer.windows"

    // MARK: - A splitter's divider offset

    /// The stored divider offset, or nil when the user has never dragged this one.
    static func framePosition(container: String, frame: String,
                              in configuration: WinampModernConfiguration) -> Double? {
        storedInteger(section: framesSection, key: frameKey(container: container, frame: frame),
                      in: configuration).map(Double.init)
    }

    static func setFramePosition(_ position: Double, container: String, frame: String,
                                 in configuration: WinampModernConfiguration) {
        let value = position.isFinite ? Int32(clamping: Int(max(0, position.rounded()))) : 0
        configuration.setInteger(value, section: framesSection,
                                 key: frameKey(container: container, frame: frame))
    }

    /// The container is part of the key because a skin may carry the same frame id in two of its
    /// windows — and because a frame is only ever addressed from the container that declares it.
    static func frameKey(container: String, frame: String) -> String { "\(container)/\(frame)" }

    // MARK: - Which layout a container is on

    /// The layout the user last switched this container to, or nil when they never have.
    ///
    /// This is Winamp's "it comes back shaded if you left it shaded". Empty is read as nil so a
    /// cleared value cannot name a layout no container has.
    static func layout(container: String, in configuration: WinampModernConfiguration) -> String? {
        let stored = configuration.string(section: layoutsSection, key: container, default: "")
        return stored.isEmpty ? nil : stored
    }

    static func setLayout(_ id: String, container: String,
                          in configuration: WinampModernConfiguration) {
        configuration.setString(id, section: layoutsSection, key: container)
    }

    // MARK: - Whether one of the skin's windows is open

    /// What the user last did with this window, or nil when they have never said. Distinct from
    /// "closed": a window they have never touched falls back to what the skin declares.
    static func windowIsVisible(container: String,
                                in configuration: WinampModernConfiguration) -> Bool? {
        storedInteger(section: windowsSection, key: container, in: configuration).map { $0 != 0 }
    }

    static func setWindowIsVisible(_ visible: Bool, container: String,
                                   in configuration: WinampModernConfiguration) {
        configuration.setInteger(visible ? 1 : 0, section: windowsSection, key: container)
    }

    // MARK: - The sentinel

    /// `-1` means "never set", which is why it cannot be spelled as `0`: **zero is a legal value for
    /// both integer entries here.** ClassicPro closes its side view with `setPosition(0)` and a user
    /// may leave it closed, and `0` is exactly how a deliberately closed window is stored.
    private static let unset: Int32 = -1

    private static func storedInteger(section: String, key: String,
                                      in configuration: WinampModernConfiguration) -> Int32? {
        let stored = configuration.integer(section: section, key: key, default: unset)
        return stored < 0 ? nil : stored
    }
}
