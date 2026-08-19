import AppKit
import Foundation

/// The typed set of host surfaces a `.wal` skin can embed through a `windowholder`/`componentbucket`
/// or express as a separate visible container. Skin-supplied component GUIDs are resolved to one of
/// these kinds and never escape this registry: the runtime binds a kind to a NullPlayer host adapter,
/// so an unknown or unsafe GUID maps to `.other` (a bounded, inert frame) rather than to arbitrary
/// host behaviour.
enum WinampModernComponentKind: String, CaseIterable {
    case playlist
    case library
    case visualization
    case video
    case equalizer
    case other
}

/// Maps the standard Winamp component GUIDs (and the `guid:` shortforms real skins use in
/// `TOGGLE`/`sendaction`) to a typed `WinampModernComponentKind`. GUIDs are normalized to their
/// bare 32 hex digits (braces/dashes/case removed) before lookup. Source: Phase 0B decision record §3.
enum WinampModernComponentRegistry {
    /// Canonical Winamp component GUIDs, normalized to bare lowercase hex.
    private static let guidToKind: [String: WinampModernComponentKind] = [
        "45f3f7c1a6f34ee6a15e125e92fc3f8d": .playlist,
        "6b0edf80c9a511d39f2600c04f39ffc6": .library,
        "0000000a000c0010ff7b01014263450c": .visualization,
        "f0816d7bfffc434380f2e8199aa15cc3": .video,
    ]

    /// Short tokens used in `TOGGLE guid:pl` / `sendaction` and in some holder `hold` values.
    private static let shortTokenToKind: [String: WinampModernComponentKind] = [
        "pl": .playlist, "playlist": .playlist,
        "ml": .library, "library": .library, "medialibrary": .library,
        "vis": .visualization, "avs": .visualization, "visualization": .visualization,
        "vid": .video, "video": .video,
        "eq": .equalizer, "equalizer": .equalizer,
    ]

    /// The element types that can host a component surface. `<component>` is the form real skins use
    /// for their playlist/video/library *content* (mmd3 `xml/pledit-normal.xml`, CornerAmp
    /// `xml/pledit.xml`, Winamp Modern `xml/ml-normal.xml`); `windowholder`/`componentbucket` are the
    /// SUI forms cPro's engine uses.
    static func isHolderElement(_ typeName: String) -> Bool {
        switch typeName.lowercased() {
        case "windowholder", "componentbucket", "component": return true
        default: return false
        }
    }

    /// Resolve the kind a `windowholder hold="…"` / `componentbucket` / `component param="…"` value
    /// refers to, or a `TOGGLE`/`sendaction` parameter.
    ///
    /// This is an **exact** match on a canonical GUID or a documented short token — nothing else. A
    /// substring rule here would make `Pledit` a playlist *and* `colorthemes` a video window ("vid"
    /// is not in it, but `MLibrary` does contain "ml"), which is fine by luck and wrong by design;
    /// container and menu decisions must not rest on that. `nil` means "nothing recognizable named".
    static func kind(for rawValue: String?) -> WinampModernComponentKind? {
        guard var value = rawValue?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            return nil
        }
        value = value.lowercased()
        if value == "@all@" { return .other }
        if value.hasPrefix("guid:") { value = String(value.dropFirst("guid:".count)) }
        if let short = shortTokenToKind[value] { return short }
        return guidToKind[normalize(value)]
    }

    /// The canonical Winamp GUID for a kind, in the braced upper-case form a skin's script compares
    /// against (`if (guid == PL_GUID)` in ClassicPro's `CentroSUI2.m`). `nil` for the equalizer:
    /// Winamp defines no EQ component GUID, which is why every skin draws its own.
    static func canonicalGUID(for kind: WinampModernComponentKind) -> String? {
        switch kind {
        case .playlist: return "{45F3F7C1-A6F3-4EE6-A15E-125E92FC3F8D}"
        case .library: return "{6B0EDF80-C9A5-11D3-9F26-00C04F39FFC6}"
        case .visualization: return "{0000000A-000C-0010-FF7B-01014263450C}"
        case .video: return "{F0816D7B-FFFC-4343-80F2-E8199AA15CC3}"
        case .equalizer, .other: return nil
        }
    }

    /// The deliberately fuzzy companion to `kind(for:)`, for the one measured case that needs it:
    /// ClassicPro's engine names its holders `centro.windowholder.library`, `PlaylistPro.wdh`, and so
    /// on, and declares the component nowhere else. Only ever applied to a holder element's `id`,
    /// never to a container id or a menu parameter.
    static func kindFromHolderIdentifier(_ identifier: String) -> WinampModernComponentKind? {
        let value = identifier.lowercased()
        if let exact = kind(for: value) { return exact }
        for token in holderIdentifierTokens where value.contains(token.0) { return token.1 }
        return nil
    }

    /// Longest-first so `medialibrary` cannot be claimed by `ml`, and specific before generic.
    private static let holderIdentifierTokens: [(String, WinampModernComponentKind)] = [
        ("medialibrary", .library), ("library", .library),
        ("visualization", .visualization), ("playlist", .playlist), ("equalizer", .equalizer),
        ("video", .video), ("avs", .visualization),
    ]

    private static func normalize(_ guid: String) -> String {
        String(guid.lowercased().unicodeScalars.filter { CharacterSet(charactersIn: "0123456789abcdef").contains($0) })
    }
}

/// A discovered embedded-component site: the retained holder object, the kind it hosts, and its
/// frame resolved in the active scene (skin coordinates, top-left origin).
struct WinampModernComponentHolder {
    let object: WasabiObject
    let kind: WinampModernComponentKind
    let frame: CGRect
}

// MARK: - Host adapter seam

struct WinampModernPlaylistRow: Equatable {
    let title: String
    let secondary: String
    let duration: TimeInterval
    let isCurrent: Bool
}

struct WinampModernPlaylistSnapshot: Equatable {
    var rows: [WinampModernPlaylistRow]
    var currentIndex: Int
    var selectedIndex: Int
    /// Total queue length, which is `rows.count` today but is the number `PE_Info` shows and must
    /// stay meaningful if the row list is ever windowed.
    var trackCount: Int
    /// Summed duration of the whole queue, in seconds.
    var totalDuration: TimeInterval

    init(rows: [WinampModernPlaylistRow], currentIndex: Int, selectedIndex: Int,
         trackCount: Int? = nil, totalDuration: TimeInterval? = nil) {
        self.rows = rows
        self.currentIndex = currentIndex
        self.selectedIndex = selectedIndex
        self.trackCount = trackCount ?? rows.count
        self.totalDuration = totalDuration ?? rows.reduce(0) { $0 + $1.duration }
    }

    /// What a skin's `PE_Info` text shows: "N items/h:mm:ss" — Winamp's playlist status line.
    ///
    /// **The `/` separator is inferred, not verified against Winamp.** Defix parses this string with
    /// `getToken(text, "/", 1)` and writes the result as its playlist box's `Time:` readout, so the
    /// second token has to be the duration; with the ", " this used to use, that readout came out
    /// empty. The stock Winamp Modern skin displays the whole string in a 55px `PLTime` field, which
    /// fits either form and so does not settle it. What would settle it: a screenshot or capture of
    /// Winamp's own playlist showing that field. If it turns out to differ, this line is the only
    /// place to change.
    var infoLine: String {
        let items = trackCount == 1 ? "1 item" : "\(trackCount) items"
        guard totalDuration > 0 else { return items }
        let seconds = Int(totalDuration.rounded())
        let (hours, minutes, remainder) = (seconds / 3600, (seconds % 3600) / 60, seconds % 60)
        let length = hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, remainder)
            : String(format: "%d:%02d", minutes, remainder)
        return "\(items)/\(length)"
    }

    static let empty = WinampModernPlaylistSnapshot(rows: [], currentIndex: -1, selectedIndex: -1)
}

struct WinampModernEQSnapshot: Equatable {
    /// classic10 band gains in dB (-12…12).
    var bandGainsDB: [Float]
    var preampDB: Float
    var enabled: Bool
    var auto: Bool
    var presetNames: [String]

    static let flat = WinampModernEQSnapshot(bandGainsDB: Array(repeating: 0, count: 10),
                                             preampDB: 0, enabled: true, auto: false, presetNames: [])
}

/// The narrow, sandboxed seam the Wasabi runtime uses to embed NullPlayer's playlist, equalizer, and
/// library surfaces. It exposes no filesystem, network, or arbitrary app access — only the typed
/// operations the measured targets require. A `nil` return / no-op is the documented compatibility
/// default when a surface is unavailable in the current session.
protocol WinampModernComponentHost: AnyObject {
    // Playlist
    func playlistSnapshot() -> WinampModernPlaylistSnapshot
    func playlistSelect(row: Int)
    func playlistPlay(row: Int)
    func playlistRemove(row: Int)

    // Equalizer (classic10)
    func equalizerSnapshot() -> WinampModernEQSnapshot
    func equalizerSetBandGainDB(_ band: Int, gainDB: Float)
    func equalizerSetPreampDB(_ gainDB: Float)
    func equalizerSetEnabled(_ enabled: Bool)
    func equalizerSetAuto(_ enabled: Bool)
    func equalizerApplyPreset(named name: String)

    // Library — a live host surface embedded at the skin-provided frame, or nil when unavailable.
    func makeLibrarySurface() -> WinampModernLibrarySurface?

    /// Fallback for a component the skin does not embed: surface it through the classic
    /// WindowManager window instead of a skin-owned holder.
    func toggleClassicWindow(for kind: WinampModernComponentKind)
}

extension WinampModernComponentHost {
    func makeLibrarySurface() -> WinampModernLibrarySurface? { nil }
}

/// A live library browser embedded in a `.wal` skin's holder.
///
/// The previous seam returned a bare `NSView` the view layer held unowned, which gave the surface no
/// way to be told anything — not a palette change, not a UI Size change, and crucially not "you are
/// about to be removed", so its in-flight server tasks and timers outlived it. This is the typed
/// handle instead: the component bridge creates and owns it, the view positions its `view`, and every
/// lifecycle event has a name.
protocol WinampModernLibrarySurface: AnyObject {
    var view: NSView { get }
    /// Browse mode, for session save/restore through `LibraryBrowserWindowProviding`.
    var browseModeRawValue: Int { get set }
    func reloadData()
    func showLinkSheet()
    /// Recolour to the skin's active colour theme.
    func applyPalette(_ palette: WasabiPalette)
    /// UI Size, as the `.wal` window's own skin scale.
    func applySkinScale(_ scale: CGFloat)
    /// Cancel work and release resources before the view is removed. Must be idempotent.
    func prepareForUITeardown()
}
