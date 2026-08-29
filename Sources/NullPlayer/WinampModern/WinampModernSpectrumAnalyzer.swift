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

/// **Which of a skin's two visualization surfaces a selection belongs to.**
///
/// A `.wal` skin draws in two different kinds of box and they are not the same surface:
///
/// - `.visBox` — the skin's own `<vis>` elements, cut and coloured by its author. Big Bento Modern's
///   butterfly is four of them.
/// - `.componentHolder` — an unhosted `{0000000A}` plugin holder, which has no `<vis>` markup at all
///   and is drawn from the host's palette (BB9). Big Bento's stretched Multi Content View pane is
///   one, as is its mini pane.
///
/// They carry **separate** selections on purpose: the butterfly is the skin's artwork and the pane
/// is an empty plugin slot, so wanting Cava in the big pane is not a request to overpaint the
/// artwork — which is exactly what one skin-wide choice would have done.
enum WinampModernVisSurface: String, CaseIterable {
    case visBox
    case componentHolder
}

extension WinampModernSpectrumAnalyzer {
    /// **The engine a pick in the combined mode/engine group implies.**
    ///
    /// A visualization menu lists Winamp's own two modes and NullPlayer's engines as *one* radio
    /// group, because they are answers to the same question — what is in this box. So picking a mode
    /// is also a choice against whatever NullPlayer engine was drawing: `Spectrum Analyzer` and
    /// `Oscilloscope` are Winamp's own, and they mean the box goes back to Winamp's engine.
    ///
    /// Missing this is a one-way door, and it reached the running app: the row ticked, vis_classic
    /// kept painting, and there was no way back out of it. `presentScriptPopup` applies the same rule
    /// to a skin's own mode rows.
    ///
    /// `Off` is the exception. It is not one of Winamp's modes but the absence of all of them, so it
    /// leaves the selection alone and switching back on returns the box to what was last in it.
    static func chosen(byPicking mode: WasabiVisualizationMode,
                       current: WinampModernSpectrumAnalyzer) -> WinampModernSpectrumAnalyzer {
        mode == .off ? current : .skin
    }
}

/// The selections and the engines behind them, **skin-wide, one per surface**.
///
/// On `WasabiSkinRuntime` beside `componentBucket`, and for the same reason: one skin draws its
/// visualization in several boxes, layouts and containers — Big Bento Modern shows six at once — and
/// each of those has its own `WasabiSceneRenderer`. A per-renderer selection would let two windows
/// of one skin disagree about what is drawing, and the engines below hold per-box state keyed by
/// object, which is only coherent if there is one of each per skin.
///
/// Skin-wide is not *surface*-wide, though: `WinampModernVisSurface` splits the `<vis>` boxes from
/// the `{0000000A}` panes, so each keeps its own choice while both share the engine objects.
///
/// Loaded from the skin's own config on first use and cached: this is read once per box per frame.
/// Main-thread only, like the renderer that owns it — every route in is a draw, a menu or a teardown.
final class WinampModernSpectrumAnalyzerState {
    private var cachedSuites: [WinampModernVisSurface: WinampModernSpectrumAnalyzer] = [:]
    private let builtIn = WasabiBuiltInVisRenderer()
    /// Built on first selection, never before: an engine nobody chose must not register an audio
    /// consumer or allocate a vis_classic core, which is B51's gating rule one level up.
    ///
    /// Keyed by *suite*, not by surface: the engines hold their per-box state keyed by object, so one
    /// `CavaVisRenderer` serves the `<vis>` boxes and a `{0000000A}` pane at once without their bars
    /// meeting. Two instances would be two audio consumers against the same audio.
    private var suiteRenderers: [WinampModernSpectrumAnalyzer: WasabiVisRenderer] = [:]

    func suite(for surface: WinampModernVisSurface,
               in configuration: WinampModernConfiguration) -> WinampModernSpectrumAnalyzer {
        if let cached = cachedSuites[surface] { return cached }
        let stored = WinampModernSkinState.spectrumAnalyzer(for: surface, in: configuration)
        cachedSuites[surface] = stored
        return stored
    }

    func renderer(for surface: WinampModernVisSurface,
                  in configuration: WinampModernConfiguration) -> WasabiVisRenderer {
        renderer(for: suite(for: surface, in: configuration))
    }

    /// Switch engines for one surface, reporting whether anything moved so the caller can skip the
    /// repaint.
    ///
    /// The outgoing engine's state goes with it — its taps, its cores and its per-box bars — because
    /// an engine nobody is looking at must not keep costing audio work. **Unless the other surface is
    /// still drawing with it**: the two selections are independent, and discarding then would wipe
    /// the bars out from under a box the user never touched.
    @discardableResult
    func select(_ suite: WinampModernSpectrumAnalyzer,
                for surface: WinampModernVisSurface,
                in configuration: WinampModernConfiguration) -> Bool {
        let current = self.suite(for: surface, in: configuration)
        guard suite != current else { return false }
        cachedSuites[surface] = suite
        WinampModernSkinState.setSpectrumAnalyzer(suite, for: surface, in: configuration)
        let stillDrawing = WinampModernVisSurface.allCases.contains {
            self.suite(for: $0, in: configuration) == current
        }
        if !stillDrawing { renderer(for: current).discardState() }
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

    /// Stop everything: a skin change, a UI teardown. Idempotent, and it leaves the *selections*
    /// alone — they are preferences, and they are on disk.
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
