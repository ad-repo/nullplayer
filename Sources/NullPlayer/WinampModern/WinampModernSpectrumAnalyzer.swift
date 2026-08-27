import AppKit
import Foundation

/// Which visualization paints a skin's `<vis>` box (B53).
///
/// Winamp's `<vis>` is a *box*, not an engine: the skin says how big it is, where it sits, what
/// colours it may use and — through `mode` — whether it shows an analyzer, an oscilloscope or
/// nothing. Everything that actually paints it is the host's, which is why NullPlayer's own
/// visualizations can draw there instead without the skin knowing: they are all
/// `WasabiVisRenderer`s painting into the scene's `CGContext`, the seam B51 built.
///
/// **This is only about that box.** A skin's separate AVS/visualization window — the
/// `{0000000A}` plugin holder — is a different surface with its own engines (ProjectM, Geiss,
/// Tripex; B20a), and nothing here touches it.
enum WinampModernSpectrumAnalyzer: String, CaseIterable {
    /// Winamp's own analyzer and oscilloscope, drawn from the skin's own attributes. The default,
    /// because a skin should look the way its author drew it until the user says otherwise.
    case skin
    /// NullPlayer's Cava spectrum.
    case cava
    /// NullPlayer's vis_classic — the Winamp-plugin analyzer, with its own profile catalogue.
    case visClassic

    var displayName: String {
        switch self {
        case .skin: return "Skin's Own"
        // The names these engines carry everywhere else in the app — `MainWindowVisMode` and the
        // spectrum window both spell it `vis_classic` — because three routes to one feature must
        // not call it three things.
        case .cava: return "Cava"
        case .visClassic: return "vis_classic"
        }
    }

    /// A stored value that names nothing (a downgrade, a hand-edited config) reads as the skin's
    /// own, which is the one choice that is always right for a skin we know nothing else about.
    static func from(storedValue: String) -> WinampModernSpectrumAnalyzer {
        WinampModernSpectrumAnalyzer(rawValue: storedValue) ?? .skin
    }
}

/// The selection and the engines behind it, **skin-wide**.
///
/// On `WasabiSkinRuntime` beside `componentBucket`, and for the same reason: one skin draws its
/// visualization in several boxes, layouts and containers — Big Bento Modern shows six at once — and
/// each of those has its own `WasabiSceneRenderer`. A per-renderer selection would let two windows
/// of one skin disagree about what is drawing, and the engines below hold per-box state keyed by
/// object, which is only coherent if there is one of each per skin.
///
/// Loaded from the skin's own config on first use and cached: this is read once per box per frame.
/// Main-thread only, like the renderer that owns it — every route in is a draw, a menu or a teardown.
final class WinampModernSpectrumAnalyzerState {
    private var cachedSuite: WinampModernSpectrumAnalyzer?
    private let builtIn = WasabiBuiltInVisRenderer()
    /// Built on first selection, never before: an engine nobody chose must not register an audio
    /// consumer or allocate a vis_classic core, which is B51's gating rule one level up.
    private var suiteRenderers: [WinampModernSpectrumAnalyzer: WasabiVisRenderer] = [:]

    func suite(in configuration: WinampModernConfiguration) -> WinampModernSpectrumAnalyzer {
        if let cachedSuite { return cachedSuite }
        let stored = WinampModernSkinState.spectrumAnalyzer(in: configuration)
        cachedSuite = stored
        return stored
    }

    func renderer(in configuration: WinampModernConfiguration) -> WasabiVisRenderer {
        renderer(for: suite(in: configuration))
    }

    /// Switch engines, reporting whether anything moved so the caller can skip the repaint.
    ///
    /// The outgoing engine's state goes with it — its taps, its cores and its per-box bars — because
    /// an engine nobody is looking at must not keep costing audio work.
    @discardableResult
    func select(_ suite: WinampModernSpectrumAnalyzer,
                in configuration: WinampModernConfiguration) -> Bool {
        let current = self.suite(in: configuration)
        guard suite != current else { return false }
        renderer(for: current).discardState()
        cachedSuite = suite
        WinampModernSkinState.setSpectrumAnalyzer(suite, in: configuration)
        return true
    }

    /// Every NullPlayer engine's own controls, whether or not it is the one drawing.
    ///
    /// All of them, deliberately: a menu that shows only the running engine's options makes picking
    /// an engine and configuring it two trips through the menu, and on a skin that traps the right
    /// button over its visualization the second trip may not be available at all. Building a menu
    /// costs an engine *object* and nothing else — a `CavaPresenter` holds no timer and no audio
    /// consumer until its first draw, and a `VisClassicVisRenderer` builds no C++ core.
    func optionMenus() -> [(suite: WinampModernSpectrumAnalyzer, menu: NSMenu)] {
        WinampModernSpectrumAnalyzer.allCases.compactMap { suite in
            guard let engine = renderer(for: suite) as? WasabiSpectrumAnalyzerRenderer,
                  let menu = engine.optionsMenu() else { return nil }
            return (suite, menu)
        }
    }

    /// Stop everything: a skin change, a UI teardown. Idempotent, and it leaves the *selection*
    /// alone — that is a preference, and it is on disk.
    func discardAll() {
        builtIn.discardState()
        for renderer in suiteRenderers.values { renderer.discardState() }
    }

    private func renderer(for suite: WinampModernSpectrumAnalyzer) -> WasabiVisRenderer {
        switch suite {
        case .skin:
            return builtIn
        case .cava, .visClassic:
            if let existing = suiteRenderers[suite] { return existing }
            let made: WasabiVisRenderer = suite == .cava ? CavaVisRenderer() : VisClassicVisRenderer()
            suiteRenderers[suite] = made
            return made
        }
    }
}
