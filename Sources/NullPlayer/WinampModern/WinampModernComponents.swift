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
    let surfaceID: WinampModernSurfaceID
    let frame: CGRect

    /// Legacy accessor for the real Winamp components already routed through this type. Hosted
    /// NullPlayer windows are not components, so they report `.other` here until their dedicated
    /// call sites switch to `surfaceID`.
    var kind: WinampModernComponentKind { componentKind ?? .other }

    var componentKind: WinampModernComponentKind? { surfaceID.componentKind }

    var hostedWindowID: WinampModernHostedWindowID? { surfaceID.hostedWindowID }
}

// MARK: - Host adapter seam

struct WinampModernPlaylistRow: Equatable {
    let title: String
    let secondary: String
    let duration: TimeInterval
    let isCurrent: Bool
    /// The three fields `PlEdit.getMetaData(track, field)` is asked for, kept per row rather than
    /// derived from `secondary`: the display string joins artist and album with an em dash, and a
    /// script that asks for one of them must not be handed both.
    let artist: String
    let album: String
    /// What `PlEdit.getFileName(track)` answers. Defix reads it off the current entry to derive the
    /// folder its album art lives in — the same exposure `getPlayItemMetaDataString("filename")`
    /// already carries, and read-only: nothing in the seam opens a path a script hands back.
    let filePath: String

    init(title: String, secondary: String, duration: TimeInterval, isCurrent: Bool,
         artist: String = "", album: String = "", filePath: String = "") {
        self.title = title
        self.secondary = secondary
        self.duration = duration
        self.isCurrent = isCurrent
        self.artist = artist
        self.album = album
        self.filePath = filePath
    }
}

struct WinampModernPlaylistSnapshot: Equatable {
    var rows: [WinampModernPlaylistRow]
    var currentIndex: Int
    var selectedIndex: Int
    /// Every selected row, which `PE_SEL`'s Select All / Invert and `PE_REM`'s Crop work on.
    /// `selectedIndex` stays the *anchor* — the row the user last clicked — because that is what a
    /// click, the Delete key and a script's `getCurrentIndex` mean by "the selection".
    var selectedRows: Set<Int>
    /// Total queue length, which is `rows.count` today but is the number `PE_Info` shows and must
    /// stay meaningful if the row list is ever windowed.
    var trackCount: Int
    /// Summed duration of the whole queue, in seconds.
    var totalDuration: TimeInterval

    init(rows: [WinampModernPlaylistRow], currentIndex: Int, selectedIndex: Int,
         selectedRows: Set<Int>? = nil,
         trackCount: Int? = nil, totalDuration: TimeInterval? = nil) {
        self.rows = rows
        self.currentIndex = currentIndex
        self.selectedIndex = selectedIndex
        self.selectedRows = selectedRows ?? (selectedIndex >= 0 ? [selectedIndex] : [])
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

    /// Whether a row draws selected: the anchor, or anything a multi-row selection command picked.
    func isSelected(_ index: Int) -> Bool { index == selectedIndex || selectedRows.contains(index) }

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
    /// Replace the whole selection — `PE_SEL`'s Select All / Select None / Invert Selection.
    func playlistSetSelection(_ rows: Set<Int>)
    /// Remove a whole selection at once — `PE_REM`'s Remove Selected and Crop Selection.
    func playlistRemoveRows(_ rows: Set<Int>)
    /// `PlEdit.moveTo(from, to)` — the playlist context menu's Move selected to top / to bottom /
    /// after current. Both are absolute row numbers in the queue as it stands before the move.
    func playlistMove(row: Int, to destination: Int)
    /// `PlEdit.clear()` — empty the queue.
    func playlistClear()

    // Equalizer (classic10)
    func equalizerSnapshot() -> WinampModernEQSnapshot
    func equalizerSetBandGainDB(_ band: Int, gainDB: Float)
    func equalizerSetPreampDB(_ gainDB: Float)
    func equalizerSetEnabled(_ enabled: Bool)
    func equalizerSetAuto(_ enabled: Bool)
    func equalizerApplyPreset(named name: String)

    // Library — a live host surface embedded at the skin-provided frame, or nil when unavailable.
    func makeLibrarySurface() -> WinampModernLibrarySurface?

    /// A real web surface for one `<browser>` element. It is deliberately independent from the
    /// cached Media Library surface: a skin may declare several browser tabs, each with its own
    /// history, page state, and lifecycle.
    @MainActor
    func makeBrowserSurface(initialRequest: WinampModernBrowserRequest?) -> WinampModernBrowserSurface?

    /// Video — the same shape as the library's, and for the same reason: the skin draws a window
    /// around a box it cannot fill, and only the host can put the picture in it. `nil` when no video
    /// output exists in this session.
    func makeVideoSurface() -> WinampModernVideoSurface?

    /// Visualization — the skin's AVS/vis window, filled with the host's real visualization engine
    /// (ProjectM/MilkDrop, Geiss, Tripex) rather than the engine-drawn analyzer. `nil` when no
    /// visualization output exists in this session.
    func makeVisualizationSurface() -> WinampModernVisualizationSurface?

    /// A synthesized `.wal` host window owned by NullPlayer rather than by a real Winamp component.
    /// `nil` until that hosted-window id has a runtime adapter implementation.
    func makeHostedWindowSurface(id: WinampModernHostedWindowID) -> WinampModernHostedSurface?

    /// Fallback for a component the skin does not embed: surface it through the classic
    /// WindowManager window instead of a skin-owned holder.
    func toggleClassicWindow(for kind: WinampModernComponentKind)
}

extension WinampModernComponentHost {
    func makeLibrarySurface() -> WinampModernLibrarySurface? { nil }
    @MainActor
    func makeBrowserSurface(initialRequest: WinampModernBrowserRequest?) -> WinampModernBrowserSurface? { nil }
    func makeVideoSurface() -> WinampModernVideoSurface? { nil }
    func makeVisualizationSurface() -> WinampModernVisualizationSurface? { nil }
    func makeHostedWindowSurface(id: WinampModernHostedWindowID) -> WinampModernHostedSurface? { nil }
    /// A host with no selection model of its own keeps the single anchor it already had.
    func playlistSetSelection(_ rows: Set<Int>) { playlistSelect(row: rows.min() ?? -1) }
    /// Highest row first, so each removal cannot shift the rows still to come.
    func playlistRemoveRows(_ rows: Set<Int>) {
        for row in WinampModernPlaylistSelection.removalOrder(rows) { playlistRemove(row: row) }
    }
    /// A host with no reordering of its own leaves the queue alone rather than approximating the
    /// move with a remove and an insert, which would lose the track.
    func playlistMove(row: Int, to destination: Int) {}
    func playlistClear() { playlistRemoveRows(Set(0..<playlistSnapshot().rows.count)) }
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
    /// How large to draw the library's content: the `.wal` window's own skin scale **multiplied by**
    /// the Text Size setting, resolved against the hosting canvas. One number, because every
    /// proportion inside the browser is derived from it — and it is pushed rather than pulled so the
    /// library can never disagree with the playlist drawn beside it.
    func applyContentScale(_ scale: CGFloat)
    /// Cancel work and release resources before the view is removed. Must be idempotent, and it is
    /// **terminal**: the surface never works again after it.
    func prepareForUITeardown()
    /// The skin's holder for this surface has gone from the scene (a tab switched, a layout changed),
    /// so leave the view hierarchy — and stay reusable, because the bridge is still caching this
    /// instance and will hand the very same one back the next time the holder appears.
    ///
    /// This is not `prepareForUITeardown()`. Tearing down on holder removal made the second visit to
    /// a tab re-add an already-torn-down surface, and the *third* one found the teardown latch
    /// already closed and never removed the view at all — cPro-Bento's browser then sat on top of
    /// every other tab (Media Library → Playlist → Media Library → Playlist).
    func unmountFromHolder()
}

/// A browser address supplied by a particular object in the retained graph. `sourceLogicalPath`
/// lets the host resolve a relative page through the read-only WAL VFS without ever manufacturing a
/// host `file:` URL.
struct WinampModernBrowserRequest: Equatable {
    let address: String
    let sourceLogicalPath: String

    /// Wasabi browsers use both spellings in the wild. `url` is the current location and wins when
    /// supplied; ClassicPro's `<Winamp:Browser>` commonly supplies only `home`. An addressless
    /// browser opens the host-owned start page rather than presenting an unexplained empty surface.
    static func initial(attributes: [String: String],
                        sourceLogicalPath: String) -> WinampModernBrowserRequest {
        let address = [attributes["url"], attributes["home"]]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first(where: { !$0.isEmpty }) ?? "about:blank"
        return WinampModernBrowserRequest(address: address,
                                          sourceLogicalPath: sourceLogicalPath)
    }
}

/// The platform-neutral handle for Winamp's embedded web browser. WebKit remains in the AppKit
/// bridge; the skin engine sees only typed navigation and lifecycle operations.
@MainActor
protocol WinampModernBrowserSurface: AnyObject {
    var view: NSView { get }
    func navigate(_ request: WinampModernBrowserRequest)
    func setVisible(_ visible: Bool)
    func applySkinScale(_ scale: CGFloat)
    func unmountFromHolder()
    func prepareForUITeardown()
}

/// The host's video output, placed over a `.wal` skin's video box.
///
/// Six of the corpus skins declare a full `<container id="video">` — chrome, a `ledstatusbar`, and
/// the `VID_*` buttons — around a `<component param="{F0816D7B-…}">` that was decoration over an
/// empty box: playing a video opened NullPlayer's own window somewhere else on screen while the
/// skin's stayed shut.
///
/// Two things are deliberately unlike the `.library` seam. A library surface *is* a browser the
/// bridge creates; a video surface only says **where** the one video output the app already owns
/// should be, because playback, casting, server reporting and analytics all live in
/// `VideoPlayerWindowController`. And it does not host that output as a subview — see
/// `WinampModernVideoSurfaceView` for why the video engine will not tolerate that — it hands over a
/// box and the controller parks its own window on it.
protocol WinampModernVideoSurface: AnyObject {
    var view: NSView { get }
    /// The stream's own pixel size, or `.zero` when nothing is playing or it is not known yet.
    /// `VID_1X` / `VID_2X` size the skin's window from it; with no size they stay inert rather than
    /// resizing to an invented one.
    var presentationSize: CGSize { get }
    /// Winamp's command bar over the picture. The skin's holder decides with `noshowcmdbar=`: five
    /// of the six corpus video windows switch it off because they draw their own `VID_*` buttons,
    /// and mmd3's leaves it on.
    var showsCommandBar: Bool { get set }
    /// Take the host's video output into this surface. Idempotent.
    func attachVideoOutput()
    /// Re-place the video output over this surface's box after the skin has laid it out again.
    func updateOutputPlacement()
    /// Give the video output back to a free-floating window of its own, showing it there if
    /// something is still playing. Idempotent.
    func detachVideoOutput()
    /// Put the picture **away**: unpark it and leave its own window hidden, playback untouched.
    ///
    /// This is what "close the video" means for a surface embedded in the player window (B23), which
    /// has no window of its own to order out — and unparking with `detachVideoOutput()` there would
    /// reveal exactly the free-floating window the embedded route exists to avoid. Idempotent.
    func hideVideoOutput()
    /// Recolour to the skin's active colour theme.
    func applyPalette(_ palette: WasabiPalette)
    /// UI Size, as the `.wal` window's own skin scale.
    func applySkinScale(_ scale: CGFloat)
    /// Return the video output and release resources before the view is removed. Must be idempotent.
    func prepareForUITeardown()
    /// The skin's holder has gone from the scene: leave the view hierarchy, hand the picture back,
    /// and stay reusable — the bridge caches this surface and re-serves it when the holder returns.
    func unmountFromHolder()
}

/// The host's visualization engine, drawn into a `.wal` skin's own AVS/visualization window (B20a).
///
/// Eight of the installed skins declare a `<container>` whose body is a
/// `<component param="{0000000A-000C-0010-FF7B-01014263450C}">` — Winamp's *visualization plugin*
/// component, the window AVS and MilkDrop drew into. Ours filled it with the same engine-drawn
/// spectrum bars the little `<vis>` box in the player draws, so a skin's dedicated visualization
/// window was a second, larger copy of the analyzer. It gets the real engines instead.
///
/// The two are deliberately different things and both stay: a `<vis>` is Winamp's built-in
/// analyzer/oscilloscope and remains engine-drawn (`drawVisualization`), while the component holder
/// is the plugin surface. That is Winamp's own division, and a skin that draws both wants both.
///
/// Unlike the video surface this one *does* contain its output: `VisualizationGLView` is an
/// `NSOpenGLView` that owns nothing outside itself, so it can live in the skin's view tree the way
/// the library browser does. Its `hitTest` returns nil, so the skin keeps every click over the box.
protocol WinampModernVisualizationSurface: AnyObject {
    var view: NSView { get }
    /// The engine currently drawing — the same `VisualizationType` the host's own window uses, so
    /// the Visualizations menu and this surface can never disagree about what is running.
    var engineType: VisualizationType { get }
    func switchEngine(to type: VisualizationType)
    /// `VIS_NEXT` / `VIS_PREV`: step the preset (ProjectM) or the effect (Geiss, Tripex).
    func stepPreset(by delta: Int)
    /// The visualization window's own keyboard — ←/→ step, R random, F fullscreen, P quality, C
    /// cycle, Esc leaves fullscreen — offered to a key the skin itself did not claim. Returns
    /// whether it took the key.
    func handleKeyDown(_ event: NSEvent) -> Bool
    /// The window holding this surface has just come on screen. **Load-bearing**: the engine's
    /// display link refuses to start while its window is not visible, and nothing restarts a link
    /// that never started — so a surface built inside a skin's own (initially hidden) AVS window
    /// stayed black forever without this.
    func resumeRendering()
    /// Whether this surface's engine is currently filling a screen rather than the skin's box.
    var isFullscreen: Bool { get }
    /// `VIS_FS` — take the *engine* fullscreen, leaving the skin's window where it is. It must not
    /// open NullPlayer's own visualization window: five of the eight AVS windows carry a `VIS_FS`
    /// button inside them, and answering it with our window left two visualizations running.
    func toggleFullscreen()
    /// The controls menu for whatever is running, for `VIS_CFG` and a right-click on the box.
    func buildMenu() -> NSMenu
    /// Recolour to the skin's active colour theme.
    func applyPalette(_ palette: WasabiPalette)
    /// UI Size, as the `.wal` window's own skin scale.
    func applySkinScale(_ scale: CGFloat)
    /// Stop rendering, drop observers and release the engine before the view is removed. Must be
    /// idempotent, and it is **terminal**: the engine never runs again after it.
    func prepareForUITeardown()
    /// The skin's holder has gone from the scene: stop rendering and leave the view hierarchy, but
    /// keep the engine intact — the bridge caches this surface, and `resumeRendering()` is what
    /// starts it again when the holder comes back.
    func unmountFromHolder()
}
