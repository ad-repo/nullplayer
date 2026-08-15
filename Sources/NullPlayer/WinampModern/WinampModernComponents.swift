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

    /// Resolve the kind a `windowholder hold="…"` / `componentbucket` value refers to, or a
    /// `TOGGLE`/`sendaction` parameter. Returns `nil` when nothing recognizable is named (callers
    /// treat that as no-component / `.other`).
    static func kind(for rawValue: String?) -> WinampModernComponentKind? {
        guard var value = rawValue?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            return nil
        }
        value = value.lowercased()
        if value == "@all@" { return .other }
        if value.hasPrefix("guid:") { value = String(value.dropFirst("guid:".count)) }
        if let short = shortTokenToKind[value] { return short }
        let normalized = normalize(value)
        if let guidKind = guidToKind[normalized] { return guidKind }
        // Named holders sometimes encode the kind in their id (`centro.windowholder.library`).
        for (token, kind) in shortTokenToKind where value.contains(token) { return kind }
        return nil
    }

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

    // Library — a live host view embedded at the skin-provided frame, or nil when unavailable.
    func makeLibraryContentView() -> NSView?

    /// Fallback for a component the skin does not embed: surface it through the classic
    /// WindowManager window instead of a skin-owned holder.
    func toggleClassicWindow(for kind: WinampModernComponentKind)
}

extension WinampModernComponentHost {
    func makeLibraryContentView() -> NSView? { nil }
}
