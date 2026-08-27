import AppKit
import CoreGraphics
import QuartzCore

/// NullPlayer's own visualizations, painting a `.wal` skin's `<vis>` box (B53).
///
/// Both are `WasabiVisRenderer`s and nothing else: the box is the skin's, the geometry is the
/// skin's, and the engine only ever gets a `CGRect` and a `CGContext`. That is what lets Big Bento
/// Modern's `main.vis.mirror` sit over `main.vis` at `alpha="110" flipv="1"` and reflect whichever
/// engine is running — the flips are applied around the draw generically (B43).
///
/// **Two of the skin's compositional habits are not inherited**, and both are decided in
/// `WasabiSceneRenderer`, not here. `fliph` is dropped for these engines — Winamp's butterfly is a
/// mirror of a band row, and a mirrored frequency sweep reads backwards — and a run of adjacent
/// boxes is handed the whole run's rect with a clip to each box, so Big Bento's `main.vis` +
/// `main.vis2` show one continuous analyzer rather than two copies of the same one.

/// A suite engine also brings the controls it already has elsewhere in the app.
///
/// The standing rule from B20a: **open the menu the app already has, not a second thinner one.**
/// Cava's box menu is the same `CavaPresenter` menu its own window shows, and vis_classic's is its
/// real profile catalogue — three routes to one feature must not drift apart.
protocol WasabiSpectrumAnalyzerRenderer: WasabiVisRenderer {
    var suite: WinampModernSpectrumAnalyzer { get }
    /// The engine's own options, or nil when it has none worth showing.
    func optionsMenu() -> NSMenu?
}

/// **The scene's context is y-down** (`WasabiSceneRenderer.draw` flips it once for the whole skin,
/// because skin coordinates are top-left origin). Both engines below were written for AppKit's
/// y-up world — Cava grows its bars from `rect.minY`, and a `CGImage` drawn into a flipped context
/// lands upside down — so each of them draws inside this, which flips back about the box.
private func drawingFlipped(in frame: CGRect, context: CGContext, body: () -> Void) {
    context.saveGState()
    context.translateBy(x: 0, y: frame.minY + frame.maxY)
    context.scaleBy(x: 1, y: -1)
    body()
    context.restoreGState()
}

/// How many device pixels one skin pixel is worth, from the context's own transform.
///
/// A `<vis>` box is a hundred-odd skin pixels wide and the scene is drawn through a scaled CTM (UI
/// Size × the backing scale), so an engine that rasterises at box size and lets CoreGraphics stretch
/// the result would draw a blurry analyzer on every Retina display. `WasabiRenderer.prescaled` reads
/// the CTM for the same reason.
private func deviceScale(of context: CGContext) -> CGFloat {
    let transform = context.ctm
    let scale = (abs(transform.a) + abs(transform.d)) / 2
    return max(1, min(4, scale.isFinite ? scale : 1))
}

// MARK: - Cava

/// NullPlayer's Cava spectrum, in the skin's box.
///
/// It keeps its own `CavaPresenter` on the `winampModernVisBox` scope, so the bar count, smoothing,
/// bass tilt and colours here are this surface's own and cannot move the standalone Cava window's.
/// The presenter is also what builds the right-click menu, which is why it is a presenter rather
/// than a bare `CavaRenderModel`.
final class CavaVisRenderer: WasabiSpectrumAnalyzerRenderer {
    let suite: WinampModernSpectrumAnalyzer = .cava
    private static let scope = CavaSettings.Scope.winampModernVisBox
    private let presenter = CavaPresenter(scope: CavaVisRenderer.scope)
    private var isRunning = false
    /// The last frame drawn, and when it last differed from the one before it. See
    /// `hasDecayingState`.
    private var lastBars: [[Float]] = []
    private var lastMotion: CFTimeInterval = 0
    private static let motionWindow: CFTimeInterval = 0.75

    /// Cava takes the full-stereo tap through its own render model, so the `<vis>` PCM tap B51 built
    /// for the oscilloscope stays off while this is what is drawing.
    func needsWaveform(forMode mode: WasabiVisualizationMode) -> Bool { false }

    /// Whether the picture is still **moving** — what keeps the window's visualization clock
    /// running so a fall is painted rather than frozen half way down.
    ///
    /// Motion, not "any bar above the floor", and that distinction is the whole point: Cava's render
    /// model deliberately *holds* its last frame once the audio stops rather than decaying to zero,
    /// so a bars-are-non-zero test would answer true forever and the window would repaint its vis
    /// rects at 30 Hz for as long as the player sat paused.
    var hasDecayingState: Bool {
        isRunning && CACurrentMediaTime() - lastMotion < Self.motionWindow
    }

    func discardState() {
        lastBars = []
        lastMotion = 0
        guard isRunning else { return }
        isRunning = false
        presenter.stop()
    }

    func draw(_ input: WasabiVisInput, in frame: CGRect, context: CGContext) {
        // `mode="0"` is the skin saying "nothing here" — MMD3 ships it over its own animated
        // display — and that is not a statement about *which* engine, so it is honoured whatever is
        // selected.
        guard input.style.mode != .off, frame.width > 0, frame.height > 0 else { return }
        // Started on the first draw and never before: an engine nobody selected must not hold an
        // audio consumer open (B51's gating rule).
        if !isRunning {
            isRunning = true
            presenter.start()
        }
        applySkinColors(from: input.style)
        // Brought up to meet Winamp's own analyzer, which reads hot off its decibel curve — see
        // `WasabiVisStyle.Gain`. Clamped, so a loud passage tops out rather than clipping upward.
        let gain = Float(WinampModernVisSensitivity.gain(for: .cava))
        let bars = presenter.barArrays.map { channel in
            channel.map { min(1, $0 * gain) }
        }
        guard !bars.isEmpty else { return }
        if bars != lastBars {
            lastBars = bars
            lastMotion = CACurrentMediaTime()
        }
        drawingFlipped(in: frame, context: context) {
            let graphics = NSGraphicsContext(cgContext: context, flipped: false)
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = graphics
            // `CavaDrawing` paints with `NSColor`/`NSBezierPath`, which draw into the *current*
            // graphics context rather than into one handed to them — so the scene's `CGContext` has
            // to be published as that current context for the length of the call.
            CavaDrawing.draw(in: frame, barArrays: bars,
                             lowColor: CavaSettings.effectiveLowColor(for: Self.scope),
                             highColor: CavaSettings.effectiveHighColor(for: Self.scope),
                             mode: presenter.mode)
            NSGraphicsContext.restoreGraphicsState()
        }
    }

    func optionsMenu() -> NSMenu? {
        // No transparency item (that one is the standalone window's) and no Close: this box belongs
        // to the skin, and closing it is not ours to offer.
        let menu = presenter.buildMenu(showTransparency: false, includeClose: false)
        menu.addItem(.separator())
        menu.addItem(WinampModernVisSensitivityMenu.shared.menuItem(for: suite))
        return menu
    }

    /// The box's own colours become Cava's gradient, unless the user has picked a Cava preset.
    ///
    /// A skin declares `colorband1`…`colorband16` for the analyzer that normally lives here, and
    /// they are the colours its author chose against their own artwork — Rika asks for
    /// `colorallbands="0,0,0"` at `alpha="50"`, a dark shading over a butterfly. Dropping Cava's
    /// stock blue→magenta into that box would be the one change nobody asked for. This goes through
    /// `setSkinDefaultColors`, which is the same seam the classic and modern windows push their skin
    /// palette through, so `hasCustomColors` still wins for a user who picked a preset.
    private func applySkinColors(from style: WasabiVisStyle) {
        guard let low = style.bandColors.first, let high = style.bandColors.last,
              let lowColor = NSColor(cgColor: low), let highColor = NSColor(cgColor: high) else {
            return
        }
        CavaSettings.setSkinDefaultColors(low: lowColor, high: highColor, scope: Self.scope)
    }
}

// MARK: - vis_classic

/// NullPlayer's vis_classic analyzer, in the skin's box.
///
/// Fed by the **576-sample waveform tap B51 already built** rather than by a tap of its own: that is
/// exactly the `visdata` buffer Winamp handed its own visualization plugins, which is what
/// vis_classic is a port of. So selecting this engine costs one already-existing tap and no new
/// audio work.
final class VisClassicVisRenderer: NSObject, WasabiSpectrumAnalyzerRenderer {
    let suite: WinampModernSpectrumAnalyzer = .visClassic
    private static let scope = VisClassicBridge.PreferenceScope.winampModernVisBox

    private var bridge: VisClassicBridge?
    private var bridgeSize: (width: Int, height: Int) = (0, 0)
    private var frameBytes: [UInt8] = []
    /// When the input last carried something other than silence. The engine's own bars and peaks
    /// fall for a while after that, and the window's clock has to keep painting until they land.
    private var lastActiveDraw: CFTimeInterval = 0
    /// The buffer the core last ran its FFT over — see `draw`.
    private var lastProcessed: [UInt8] = []
    private static let decayWindow: CFTimeInterval = 2.0

    /// Always, for any mode the skin is not switching off: this *is* a PCM visualization, and its
    /// input is the tap.
    func needsWaveform(forMode mode: WasabiVisualizationMode) -> Bool { mode != .off }

    var hasDecayingState: Bool {
        bridge != nil && CACurrentMediaTime() - lastActiveDraw < Self.decayWindow
    }

    func discardState() {
        bridge = nil
        bridgeSize = (0, 0)
        frameBytes = []
        lastProcessed = []
        lastActiveDraw = 0
    }

    func draw(_ input: WasabiVisInput, in frame: CGRect, context: CGContext) {
        guard input.style.mode != .off, frame.width > 0, frame.height > 0 else { return }
        // Rasterised at device resolution, not at skin resolution: the core draws whole pixels and
        // stretching a 100px frame across a Retina box would blur every bar edge.
        let scale = deviceScale(of: context)
        let width = max(1, Int((frame.width * scale).rounded()))
        let height = max(1, Int((frame.height * scale).rounded()))
        guard let core = bridge(width: width, height: height) else { return }

        let left = input.waveform.left
        let right = input.waveform.right.isEmpty ? left : input.waveform.right
        guard !left.isEmpty else { return }
        if left.contains(where: { $0 != WinampModernWaveformTap.centre }) {
            lastActiveDraw = CACurrentMediaTime()
        }
        let stride = width * 4
        // **Processed once per buffer, drawn once per box.** A skin draws its visualization in
        // several boxes — Big Bento in four — and `processAndDraw` runs the FFT *and* advances the
        // core's own bar and peak decay, so calling it per box would age the analyzer four times a
        // frame and make its falloff a function of how many boxes the skin happens to declare. The
        // renderer samples the waveform once per frame (`WasabiSceneRenderer.draw`), so an identical
        // buffer is the reliable sign that this is another box of the same frame.
        if left != lastProcessed {
            lastProcessed = left
            // The core's own scaling is cut for a 128px-tall window, so in a 30px skin box it reads
            // cold; the gain goes on the input, about the 128 centre line (`WasabiVisStyle.Gain`).
            let amplified = Self.amplified(left)
            let amplifiedRight = right == left ? amplified : Self.amplified(right)
            core.processAndDraw(leftData: amplified, rightData: amplifiedRight,
                                sampleRate: input.sampleRate,
                                width: width, height: height, into: &frameBytes, stride: stride)
        } else {
            core.drawAtSize(width: width, height: height, into: &frameBytes, stride: stride)
        }
        guard frameBytes.count >= stride * height,
              let image = makeImage(width: width, height: height, stride: stride) else { return }
        drawingFlipped(in: frame, context: context) {
            context.saveGState()
            // The core draws hard-edged bars; smoothing them on the way in would undo the point of
            // rendering at device resolution in the first place.
            context.interpolationQuality = .none
            context.draw(image, in: frame)
            context.restoreGState()
        }
    }

    func optionsMenu() -> NSMenu? {
        let menu = NSMenu(title: WinampModernSpectrumAnalyzer.visClassic.displayName)
        menu.autoenablesItems = false
        let current = bridge?.currentProfileName ?? VisClassicBridge.lastProfileName(for: Self.scope)
        let profiles = VisClassicBridge.availableProfilesCatalog()
        guard !profiles.isEmpty else { return nil }
        let profileItem = NSMenuItem(title: "Profile", action: nil, keyEquivalent: "")
        let profileMenu = NSMenu()
        profileMenu.autoenablesItems = false
        for profile in profiles {
            let item = NSMenuItem(title: profile.name, action: #selector(applyProfile(_:)),
                                  keyEquivalent: "")
            item.target = self
            item.representedObject = profile.name
            item.state = profile.name == current ? .on : .off
            profileMenu.addItem(item)
        }
        profileItem.submenu = profileMenu
        menu.addItem(profileItem)

        let fit = NSMenuItem(title: "Fit To Width", action: #selector(toggleFitToWidth(_:)),
                             keyEquivalent: "")
        fit.target = self
        fit.state = VisClassicBridge.fitToWidthDefault(for: Self.scope) ? .on : .off
        menu.addItem(fit)

        let background = NSMenuItem(title: "Transparent Background",
                                    action: #selector(toggleTransparentBackground(_:)),
                                    keyEquivalent: "")
        background.target = self
        background.state = VisClassicBridge.transparentBgDefault(for: Self.scope) ? .on : .off
        menu.addItem(background)
        menu.addItem(.separator())
        menu.addItem(WinampModernVisSensitivityMenu.shared.menuItem(for: suite))
        return menu
    }

    // MARK: Menu actions

    @objc private func applyProfile(_ sender: NSMenuItem) {
        guard let name = sender.representedObject as? String else { return }
        // Written even with no core built yet: the setting is the scope's, and the next bridge picks
        // it up from there.
        UserDefaults.standard.set(name, forKey: Self.scope.lastProfileNameKey)
        _ = bridge?.loadProfile(named: name)
    }

    @objc private func toggleFitToWidth(_ sender: NSMenuItem) {
        let enabled = !VisClassicBridge.fitToWidthDefault(for: Self.scope)
        UserDefaults.standard.set(enabled, forKey: Self.scope.fitToWidthKey)
        _ = bridge?.setFitToWidth(enabled)
    }

    @objc private func toggleTransparentBackground(_ sender: NSMenuItem) {
        let enabled = !VisClassicBridge.transparentBgDefault(for: Self.scope)
        UserDefaults.standard.set(enabled, forKey: Self.scope.transparentBgKey)
        _ = bridge?.setTransparentBackground(enabled)
    }

    // MARK: Internals

    /// The core, sized to the box.
    ///
    /// Built once and **not** rebuilt on a resize: `processAndDraw` takes the canvas size per call,
    /// so the size at creation only seeds it. A `.wal` window is resizable — a skin with a splitter
    /// changes this box's width continuously while the user drags — and tearing down a C++ core per
    /// pixel of drag would be the cost of a resize, not of a visualization. Only the reference width
    /// follows, which is what the band layout is measured against.
    private func bridge(width: Int, height: Int) -> VisClassicBridge? {
        if let bridge {
            if bridgeSize.width != width {
                // Against the box rather than against the 576 the dedicated windows use, so a
                // profile cut for a wide window still fills a narrow skin box.
                bridge.setReferenceWidth(width)
                bridgeSize = (width, height)
            }
            return bridge
        }
        guard let made = VisClassicBridge(width: width, height: height, scope: Self.scope) else {
            return nil
        }
        made.setReferenceWidth(width)
        made.reloadPersistedSettings()
        bridge = made
        bridgeSize = (width, height)
        return made
    }

    /// The 576-sample buffer with the excursion either side of 128 scaled up, clamped to the byte
    /// range Winamp's `visdata` format is defined on.
    static func amplified(_ samples: [UInt8],
                          gain: Double = Double(WinampModernVisSensitivity.gain(for: .visClassic)))
        -> [UInt8] {
        guard gain != 1 else { return samples }
        return samples.map { sample in
            let scaled = 128 + (Double(sample) - 128) * gain
            return UInt8(max(0, min(255, scaled.rounded())))
        }
    }

    /// The core writes **BGRA**, top row first (`setPixelBounded` in `VisClassicCore.cpp`), which is
    /// the same buffer the Metal path uploads as `bgra8Unorm`.
    private func makeImage(width: Int, height: Int, stride: Int) -> CGImage? {
        let bytes = frameBytes.withUnsafeBufferPointer { pointer -> Data in
            Data(bytes: pointer.baseAddress!, count: stride * height)
        }
        guard let provider = CGDataProvider(data: bytes as CFData) else { return nil }
        let info = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue)
            .union(.byteOrder32Little)
        return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
                       bytesPerRow: stride, space: CGColorSpaceCreateDeviceRGB(),
                       bitmapInfo: info, provider: provider, decode: nil,
                       shouldInterpolate: false, intent: .defaultIntent)
    }
}
