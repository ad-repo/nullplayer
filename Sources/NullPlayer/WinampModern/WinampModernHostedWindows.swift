import AppKit

/// Every surface the `.wal` runtime may route, keeping real Winamp components distinct from
/// NullPlayer-owned host windows synthesized into the skin.
enum WinampModernSurfaceID: Hashable, CustomStringConvertible {
    case component(WinampModernComponentKind)
    case hostWindow(WinampModernHostedWindowID)

    static let playlist: Self = .component(.playlist)
    static let equalizer: Self = .component(.equalizer)
    static let library: Self = .component(.library)
    static let video: Self = .component(.video)
    static let visualization: Self = .component(.visualization)
    static let spectrum: Self = .hostWindow(.spectrum)
    static let cava: Self = .hostWindow(.cava)
    static let flow: Self = .hostWindow(.flow)
    static let peppyMeter: Self = .hostWindow(.peppyMeter)
    static let audioAnalysis: Self = .hostWindow(.audioAnalysis)
    static let waveform: Self = .hostWindow(.waveform)

    var componentKind: WinampModernComponentKind? {
        guard case .component(let kind) = self else { return nil }
        return kind
    }

    var hostedWindowID: WinampModernHostedWindowID? {
        guard case .hostWindow(let id) = self else { return nil }
        return id
    }

    /// Stable identifier used for synthesized container and content ids.
    var identifier: String {
        switch self {
        case .component(let kind): return kind.rawValue
        case .hostWindow(let id): return id.rawValue
        }
    }

    var rawValue: String { identifier }

    var displayName: String {
        switch self {
        case .component(let kind):
            switch kind {
            case .playlist: return "playlist"
            case .library: return "library"
            case .visualization: return "visualization"
            case .video: return "video"
            case .equalizer: return "equalizer"
            case .other: return "other"
            }
        case .hostWindow(let id):
            return id.rawValue
        }
    }

    var description: String {
        switch self {
        case .component(let kind): return "component.\(kind.rawValue)"
        case .hostWindow(let id): return "hostWindow.\(id.rawValue)"
        }
    }
}

enum WinampModernHostedWindowID: String, CaseIterable {
    case spectrum
    case cava
    case flow
    case peppyMeter
    case audioAnalysis
    case waveform

    var containerIdentifier: String { "nullplayer.\(rawValue)" }
    var contentGroupIdentifier: String { "\(containerIdentifier).content" }
    var holderReference: String { "guid:np.\(rawValue)" }
}

struct WinampModernHostedStackPolicy: Equatable {
    let participatesInCenterStack: Bool
    let preferredHeightMultiplier: CGFloat
}

struct WinampModernHostedWindowDefinition {
    let id: WinampModernHostedWindowID
    let title: String
    let defaultSize: CGSize
    let minimumSize: CGSize
    let maximumSize: CGSize?
    let stackPolicy: WinampModernHostedStackPolicy
    let makeSurface: ((WinampModernHostedSurfaceContext) -> WinampModernHostedSurface)?
}

enum WinampModernHostedWindowRegistry {
    static let all: [WinampModernHostedWindowDefinition] = [
        WinampModernHostedWindowDefinition(
            id: .spectrum,
            title: "Spectrum Analyzer",
            defaultSize: SkinElements.SpectrumWindow.windowSize,
            minimumSize: SkinElements.SpectrumWindow.minSize,
            maximumSize: nil,
            stackPolicy: WinampModernHostedStackPolicy(
                participatesInCenterStack: true,
                preferredHeightMultiplier: 1
            ),
            makeSurface: { context in
                let view = SpectrumView(frame: NSRect(origin: .zero, size: SkinElements.SpectrumWindow.windowSize))
                view.configureForHostedSurface(context: context)
                return view
            }
        ),
        WinampModernHostedWindowDefinition(
            id: .cava,
            title: "Cava",
            defaultSize: SkinElements.SpectrumWindow.windowSize,
            minimumSize: SkinElements.SpectrumWindow.minSize,
            maximumSize: nil,
            stackPolicy: WinampModernHostedStackPolicy(
                participatesInCenterStack: true,
                preferredHeightMultiplier: 1
            ),
            makeSurface: { context in
                let view = CavaView(frame: NSRect(origin: .zero, size: SkinElements.SpectrumWindow.windowSize))
                view.configureForHostedSurface(context: context)
                return view
            }
        ),
        WinampModernHostedWindowDefinition(
            id: .flow,
            title: "Flow",
            defaultSize: SkinElements.SpectrumWindow.windowSize,
            minimumSize: SkinElements.SpectrumWindow.minSize,
            maximumSize: nil,
            stackPolicy: WinampModernHostedStackPolicy(
                participatesInCenterStack: true,
                preferredHeightMultiplier: 1
            ),
            makeSurface: { context in
                let view = NetworkMonitorView(frame: NSRect(origin: .zero,
                                                            size: SkinElements.SpectrumWindow.windowSize))
                view.configureForHostedSurface(context: context)
                return view
            }
        ),
        WinampModernHostedWindowDefinition(
            id: .peppyMeter,
            title: "PeppyMeter",
            defaultSize: SkinElements.PeppyMeterWindow.windowSize,
            minimumSize: SkinElements.PeppyMeterWindow.minSize,
            maximumSize: nil,
            stackPolicy: WinampModernHostedStackPolicy(
                participatesInCenterStack: true,
                preferredHeightMultiplier: 1.75
            ),
            makeSurface: { context in
                let view = PeppyMeterView(frame: NSRect(origin: .zero,
                                                       size: SkinElements.PeppyMeterWindow.windowSize))
                view.configureForHostedSurface(context: context)
                return view
            }
        ),
        WinampModernHostedWindowDefinition(
            id: .audioAnalysis,
            title: "Audio Analyzer",
            defaultSize: SkinElements.SpectrumWindow.windowSize,
            minimumSize: SkinElements.SpectrumWindow.minSize,
            maximumSize: nil,
            stackPolicy: WinampModernHostedStackPolicy(
                participatesInCenterStack: true,
                preferredHeightMultiplier: 1
            ),
            makeSurface: { context in
                let view = AudioAnalysisView(frame: NSRect(origin: .zero,
                                                          size: SkinElements.SpectrumWindow.windowSize))
                view.configureForHostedSurface(context: context)
                return view
            }
        ),
        WinampModernHostedWindowDefinition(
            id: .waveform,
            title: "Waveform",
            defaultSize: SkinElements.WaveformWindow.windowSize,
            minimumSize: SkinElements.WaveformWindow.minSize,
            maximumSize: nil,
            stackPolicy: WinampModernHostedStackPolicy(
                participatesInCenterStack: true,
                preferredHeightMultiplier: 1
            ),
            makeSurface: { context in
                let view = WaveformView(frame: NSRect(origin: .zero, size: SkinElements.WaveformWindow.windowSize))
                view.configureForHostedSurface(context: context)
                return view
            }
        ),
    ]

    static func entry(id: WinampModernHostedWindowID) -> WinampModernHostedWindowDefinition? {
        all.first { $0.id == id }
    }
}

struct WinampModernHostedFrameDescriptor {
    let groupIdentifier: String
    let xuiTag: String
    let hasArtwork: Bool
}

enum WinampModernHostedWindowRoute {
    case skinFrame(WinampModernHostedFrameDescriptor)
    case classicFallback(reason: String)
}

/// The only shape the trusted host is allowed to add to an initialized Wasabi graph.
/// Skin XML and MAKI never receive this API.
struct WinampModernHostedWindowInstantiation {
    let definition: WinampModernHostedWindowDefinition
    let frame: WinampModernHostedFrameDescriptor
}

/// Load-time routing metadata only. A route does not add graph objects or create an AppKit window;
/// the selected window is materialized later, when the user asks to show it.
struct WinampModernHostedWindowCatalog {
    private let routes: [WinampModernHostedWindowID: WinampModernHostedWindowRoute]

    init(routes: [WinampModernHostedWindowID: WinampModernHostedWindowRoute]) {
        self.routes = routes
    }

    subscript(id: WinampModernHostedWindowID) -> WinampModernHostedWindowRoute {
        routes[id] ?? .classicFallback(reason: "the window is not registered")
    }
}
