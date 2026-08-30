import CoreGraphics
import Foundation
import QuartzCore

/// What one `<vis>` box draws, decoded from its attributes once per draw.
///
/// Winamp's analyzer and oscilloscope are both configured entirely through this handful of
/// attributes, and a skin that ships a visualization settings page writes every one of them:
/// Big Bento Modern's `visualizer.maki` sets `oscstyle`, `peaks`, `falloff`, `peakfalloff` and
/// `coloring` from its own right-click menu, and until this existed the whole page was inert.
///
/// The colours arrive already **resolved** — through `WasabiSceneRenderer.objectColor`, which is the
/// only thing that reads a `<gammagroup>` and an inline `r,g,b` triple the same way (see the comment
/// at its call site for the Ujola Cat case that pins that down).
struct WasabiVisStyle {
    enum OscStyle { case solid, dots, lines }
    enum Coloring { case normal, fire, line }

    var mode: WasabiVisualizationMode = .analyzer
    /// `bandwidth` — Winamp's fat blocks (`wide`) or the full comb (`thin`).
    var isThin = false
    var oscStyle: OscStyle = .lines
    var coloring: Coloring = .normal
    var showsPeaks = true
    /// Bar and cap fall, **in box fractions per second** (see `WasabiBuiltInVisRenderer`).
    var barFalloff: CGFloat = WasabiVisStyle.barFalloffSteps[2]
    var peakFalloff: CGFloat = WasabiVisStyle.peakFalloffSteps[2]
    /// `colorband1`…`colorband16` (or `colorallbands` for all of them), lowest band first.
    var bandColors: [CGColor] = []
    /// `colorosc1`…`colorosc5`, smallest excursion first.
    var oscColors: [CGColor] = []
    /// `colorbandpeak`, or `nil` for a skin that declares none — then a cap takes its bar's colour,
    /// which is what Winamp does.
    var peakColor: CGColor?

    /// `falloff` / `peakfalloff` are written by MAKI at runtime, not declared in markup, and the
    /// range is documented nowhere. **Measured** (`WINAMP_MODERN_RENDER_DISASM=@player-normal-group`
    /// against Big Bento Modern, whose menu is Slower / Slow / Moderate / Fast / Faster): the script
    /// checkmarks each entry with `value == 0` … `value == 4`, so the attribute is **0…4**, and the
    /// same listing shows `peaks` written as `"0"`/`"1"` and `coloring` as the words
    /// `Normal`/`Fire`/`Line` rather than as numbers.
    ///
    /// Both scales are per **second**. Draws are not a clock — `updateSpectrum` throttles to 1/60 and
    /// drops frames outright when a scene is expensive (Big Bento's 238 ms case) — so a per-draw
    /// constant would make "Slower…Faster" mean different things on different skins, window widths
    /// and splitter positions. Moderate's cap fall is ~0.9/s, which is what the old fixed
    /// 0.015-per-draw came to at 60 Hz and reads the way Winamp's does.
    static let barFalloffSteps: [CGFloat] = [1.5, 2.5, 4.0, 6.5, 10.0]
    static let peakFalloffSteps: [CGFloat] = [0.35, 0.55, 0.9, 1.5, 2.4]
    static let falloffStepCount = 5

    /// **How fast a bar rises**, as the time constant of a one-pole approach to the band it is
    /// chasing, in seconds. There is no attribute for this — Winamp gives a skin `falloff` and
    /// `peakfalloff` and nothing for the attack — so it is one engine-wide constant, shared by the
    /// `<vis>` analyzer and the `{0000000A}` holder like the falloffs above.
    ///
    /// It exists because the *fall* was smoothed and the *rise* was not: a bar was assigned its band
    /// outright, so it jumped the full height of the box between two frames. The bands arrive **ten
    /// times a second** — measured, see *the analyzer's input arrives ten times a second* in
    /// `rendering/vis.md` — against a 30 Hz repaint, so that snap landed on two frames in three and
    /// the row read as frantic rather than as fast; worse since B73, whose unclipped input gave the
    /// bands real range to jump across.
    ///
    /// It is **not** a fix for that input rate and must not be stretched into one: smoothing wide
    /// enough to hide a 100 ms step is wide enough to lag the music by one.
    ///
    /// 30 ms is short on purpose. At the 30 Hz clock a bar covers two thirds of a jump in the first
    /// frame and ~96% by the third, so a transient still arrives on the beat; anything long enough
    /// to see as smoothing is long enough to see as lag, and a visualization that lags the music is
    /// a worse defect than a twitchy one.
    static let barAttackSeconds: CFTimeInterval = 0.03

    /// One frame of that rise: `bar` moved toward `level` over `elapsed`. Falls are **not** routed
    /// through here — those are the skin's own `falloff`, a straight rate per second.
    static func risen(from bar: CGFloat, toward level: CGFloat,
                      elapsed: CFTimeInterval) -> CGFloat {
        // No elapsed time is the first draw of a box, which has nothing to rise *from*.
        guard elapsed > 0, barAttackSeconds > 0 else { return level }
        return level - (level - bar) * CGFloat(exp(-elapsed / barAttackSeconds))
    }

    static func falloffStep(_ raw: String?) -> Int {
        guard let value = raw.flatMap({ Int($0.trimmingCharacters(in: .whitespaces)) }) else { return 2 }
        return max(0, min(falloffStepCount - 1, value))
    }

    /// Decode one box. `color` resolves an attribute value the way the scene renderer does; the two
    /// must not drift, so it is passed in rather than reimplemented.
    static func decode(attributes: [String: String], color: (String) -> CGColor) -> WasabiVisStyle {
        func attribute(_ name: String) -> String? { attributes[name] }
        var style = WasabiVisStyle()
        style.mode = WasabiVisualizationMode(attribute: attribute("mode"))
        style.isThin = attribute("bandwidth")?.lowercased() == "thin"
        switch attribute("oscstyle")?.lowercased() {
        case "solid": style.oscStyle = .solid
        case "dots": style.oscStyle = .dots
        // Winamp's default, and the sensible fallback for a value we do not know.
        default: style.oscStyle = .lines
        }
        switch attribute("coloring")?.lowercased() {
        case "fire": style.coloring = .fire
        case "line": style.coloring = .line
        default: style.coloring = .normal
        }
        style.showsPeaks = attribute("peaks")?.trimmingCharacters(in: .whitespaces) != "0"
        style.barFalloff = barFalloffSteps[falloffStep(attribute("falloff"))]
        style.peakFalloff = peakFalloffSteps[falloffStep(attribute("peakfalloff"))]
        // A skin colours its analyzer per band **or** in one stroke with `colorallbands`, and its
        // oscilloscope with `colorosc1`…`colorosc5`. White is the fallback because that is what
        // Winamp draws with no colour at all.
        let allBands = attribute("colorallbands")
        style.bandColors = (1...16).map { color(attribute("colorband\($0)") ?? allBands ?? "255,255,255") }
        style.oscColors = (1...5).map { color(attribute("colorosc\($0)") ?? allBands ?? "255,255,255") }
        style.peakColor = attribute("colorbandpeak").map(color)
        return style
    }

    /// The colour of the analyzer bar at `index` of `count`, at height `level`.
    func barColor(index: Int, count: Int, level: CGFloat) -> CGColor {
        guard !bandColors.isEmpty else { return WasabiVisStyle.white }
        switch coloring {
        case .normal:
            // Colour by band, which is what a skin's sixteen `colorband` values are cut for: the
            // gradient runs left to right across the row.
            return bandColors[min(bandColors.count - 1, index * bandColors.count / max(1, count))]
        case .fire:
            // Colour by the bar's own height, so a loud band lights the top of the ramp wherever it
            // sits in the row.
            return bandColors[min(bandColors.count - 1,
                                  max(0, Int(level * CGFloat(bandColors.count))))]
        case .line:
            return bandColors[0]
        }
    }

    /// The colour of one oscilloscope sample. Winamp bands the scope by **excursion** into five
    /// steps, which is why a skin declares five colours — reading only the first drew Big Bento's
    /// four scopes as a flat `#665ea1` line where the skin asked for a gradient.
    func oscColor(excursion: CGFloat) -> CGColor {
        guard !oscColors.isEmpty else { return WasabiVisStyle.white }
        let step = Int(min(1, max(0, excursion)) * CGFloat(oscColors.count))
        return oscColors[min(oscColors.count - 1, step)]
    }

    static let white = CGColor(red: 1, green: 1, blue: 1, alpha: 1)

    /// **How loud each engine draws, so the box reads the same whichever one is in it (B53).**
    ///
    /// The three engines measure the same audio on three scales that were never meant to agree.
    /// Winamp's analyzer maps its bands through a **decibel** curve (`visByte(forMagnitude:)`), which
    /// is why ordinary music fills its box to the top — it reads *hot*. Cava normalises linearly with
    /// its own slow auto-gain, and vis_classic scales against a canvas cut for a 128px-tall window;
    /// dropped into a 30px skin box both read *cold* beside it.
    ///
    /// So each engine takes one number on the way to the box, and the numbers are chosen to meet in
    /// the middle rather than to make the quiet ones as hot as Winamp's: the built-in comes down, the
    /// other two come up. They are calibration, not taste — a shared gain would only move all three
    /// together and change nothing about how differently they read.
    enum Gain {
        /// Winamp's own analyzer, pulled back off the ceiling.
        static let builtInAnalyzer: CGFloat = 0.8
        /// Winamp's own oscilloscope, left where it is. It draws the wave itself rather than a
        /// decibel curve, so it never read hot the way the analyzer did — but it takes the same
        /// **Sensitivity** the user sets for this engine, which is why it has a number of its own to
        /// be multiplied. A scope past the box is clamped, not clipped: the trace flattens against
        /// the edge instead of vanishing off it.
        static let builtInOscilloscope: CGFloat = 1.0
        /// Cava's bars, brought up to meet it. Clamped at the top, so a loud passage still tops out.
        static let cava: Float = 1.45
        /// vis_classic takes its gain on the **input** — the 576-sample buffer, scaled about the
        /// 128 centre line — because the core does its own FFT and paints its own bars, so there is
        /// no height to scale on the way out without stretching its artwork.
        static let visClassicInput: Double = 1.6
    }
}

/// Everything a renderer needs for one box, one frame.
struct WasabiVisInput {
    let objectID: WasabiObjectID
    let style: WasabiVisStyle
    /// The analyzer's bands, 0…1 and lowest frequency first, for a band count only the renderer
    /// knows — `bandwidth` picks 19 or 75, and a NullPlayer engine picks its own.
    ///
    /// A closure rather than an array because the count is decided *inside* the draw, and because
    /// the analysis behind it is memoized per frame: several `<vis>` boxes in one frame (Big Bento's
    /// butterfly is four) ask for the same count and get the same answer without a second FFT.
    /// Empty while nothing has been analysed yet; all-zero once the audio has gone quiet, so the
    /// bars fall to the floor rather than freezing where the music left them (B73).
    let bands: (Int) -> [CGFloat]
    /// Winamp's 576-sample `visdata` waveform, `UInt8` centred on 128, flat when silent.
    let waveform: (left: [UInt8], right: [UInt8])
    /// What the waveform was sampled at. Winamp's own scope does not care — it draws the buffer it
    /// is given — but a PCM engine that runs its own FFT (vis_classic, B53) needs the rate to place
    /// a frequency, and a host with no audio (the render harness) answers the CD rate.
    let sampleRate: Double
}

/// What paints a `<vis>` box.
///
/// A protocol rather than a bigger `switch`, because NullPlayer's own visualization suite (Cava,
/// vis_classic, the Metal modes) is meant to become selectable inside a `.wal` skin, and each of
/// those is a renderer of exactly this shape — `<vis>` boxes are painted straight into the scene
/// context, which is what lets Big Bento's `main.vis.mirror` sit over `main.vis` at `alpha="110"
/// flipv="1"`.
protocol WasabiVisRenderer: AnyObject {
    /// Whether this renderer reads PCM for that mode, and therefore whether the host's waveform tap
    /// has to run. Deliberately answered from the mode alone: it is recomputed whenever the graph
    /// changes, so it must not cost a colour resolution per box per frame.
    func needsWaveform(forMode mode: WasabiVisualizationMode) -> Bool
    /// Whether this renderer reads the analyzer's FFT for that mode, and therefore whether the
    /// host's own spectrum tap has to run (B73). Answered from the mode alone, for `needsWaveform`'s
    /// reason: it is recomputed whenever the graph changes.
    func needsAnalyzerBands(forMode mode: WasabiVisualizationMode) -> Bool
    func draw(_ input: WasabiVisInput, in frame: CGRect, context: CGContext)
    /// Whether any box still has a bar or a cap above the floor — what tells the window it can stop
    /// repainting after the audio went quiet.
    var hasDecayingState: Bool { get }
    func discardState()
}

/// Winamp's own two visualizations: the spectrum analyzer and the oscilloscope.
final class WasabiBuiltInVisRenderer: WasabiVisRenderer {
    /// How many bars the analyzer draws, per `bandwidth`. Winamp's analyzer is a row of **bands**,
    /// not of FFT bins: `wide` is the familiar handful of fat blocks, `thin` the full comb.
    static let wideAnalyzerBands = 19
    static let thinAnalyzerBands = 75

    /// Per-box bar heights, falling caps and the clock they were last decayed against — all in box
    /// fractions, keyed by object because one skin draws the same visualization in several boxes and
    /// several layouts.
    private struct BoxState {
        var bars: [CGFloat] = []
        var peaks: [CGFloat] = []
        var lastDraw: CFTimeInterval = 0
    }
    private var boxes: [WasabiObjectID: BoxState] = [:]

    /// The clear space a cap must have above its bar before it is drawn at all, in points. One
    /// pixel is enough to read as a gap and is the least that can: below that the cap and the bar
    /// share an edge and the cap stops looking like a cap.
    static let minimumCapGap: CGFloat = 1

    /// Whether a cap at `capY` clears a bar whose top edge is `barTop` by enough space to read as a
    /// floating cap. Shared with `WasabiRenderer.drawVisualizationBars` so the `<vis>` analyzer and
    /// the `{0000000A}` holder cannot drift on what a cap is.
    static func capClears(barTop: CGFloat, capY: CGFloat, capHeight: CGFloat) -> Bool {
        barTop - (capY + capHeight) >= minimumCapGap
    }

    /// The longest step a single frame may decay by. A stall — or the first draw, whose `lastDraw` is
    /// zero — must not drop every bar to the floor in one frame.
    private static let maximumDecayStep: CFTimeInterval = 0.25

    func needsWaveform(forMode mode: WasabiVisualizationMode) -> Bool { mode == .oscilloscope }
    func needsAnalyzerBands(forMode mode: WasabiVisualizationMode) -> Bool { mode == .analyzer }

    var hasDecayingState: Bool {
        boxes.values.contains { state in
            state.bars.contains { $0 > 0.001 } || state.peaks.contains { $0 > 0.001 }
        }
    }

    func discardState() { boxes.removeAll() }

    func draw(_ input: WasabiVisInput, in frame: CGRect, context: CGContext) {
        switch input.style.mode {
        case .off:
            return
        case .analyzer:
            drawAnalyzer(input, in: frame, context: context)
        case .oscilloscope:
            drawOscilloscope(input, in: frame, context: context)
        }
    }

    // MARK: - The analyzer

    private func drawAnalyzer(_ input: WasabiVisInput, in frame: CGRect, context: CGContext) {
        let style = input.style
        // `bandwidth` picks the band **count**, and the tap is asked for exactly that many: the
        // analysis is log-spaced across 20 Hz–20 kHz for whatever count it is given, so there is no
        // bucket-collapsing left to do here and no ceiling imposed by however many bands some other
        // consumer happened to want.
        let count = max(1, min(style.isThin ? Self.thinAnalyzerBands : Self.wideAnalyzerBands,
                               Int(frame.width)))
        let bands = input.bands(count)
        // Nothing analysed yet — before the first buffer after a skin load, or with no audio tap at
        // all (the render harness) — and the bars simply are not drawn. Silence is a different
        // thing: it arrives as zeroes, and the bars fall to the floor.
        guard bands.count == count else { return }
        // **The band is used as it stands — no decibel curve here.** The dB mapping, its window and
        // its frequency weighting all live in `WinampModernAnalyzerTap`, once, so this analyzer and
        // the `{0000000A}` holder's cannot read the same audio at different heights.
        //
        // This used to be `host.spectrumLevels` put through `visByte(forMagnitude:)`, then
        // `host.spectrumLevels` raw. Both were wrong in the same way: that array is a *display*
        // signal `AudioEngine` has already log-scaled, normalised and clamped, and it saturates —
        // 52 of its 75 bands measured at exactly 1.0 on a loud frame. Sending it through a second
        // logarithm compressed the whole 0.1…1.0 range into the top third of the box; using it raw
        // still left the row pinned at the ceiling with every peak cap latched to the identical 1.0,
        // which is the white line B54 reported. B73 replaced the input, not the curve.
        //
        // `Gain.builtInAnalyzer` stays gone with it: that 0.8 was cut to pull the old decibel curve
        // down to where Cava and vis_classic could meet it. Sensitivity alone remains, so `Normal`
        // is ×1 and a full-scale band fills the box.
        let gain = WinampModernVisSensitivity.stored(for: .skin).multiplier
        func bandFraction(_ index: Int) -> CGFloat {
            max(0, min(1, bands[index] * gain))
        }
        // Bars are laid out on whole pixels. A fractional slot antialiases the 1px gap between bars
        // into a smear, and a `wide` row then reads as one solid block rather than as Winamp's
        // separated bars.
        let slot = frame.width / CGFloat(count)
        func columns(_ index: Int) -> (x: CGFloat, width: CGFloat) {
            let start = (CGFloat(index) * slot).rounded(.down)
            let end = (CGFloat(index + 1) * slot).rounded(.down)
            return (frame.minX + start, max(1, end - start - 1))
        }

        var state = boxes[input.objectID] ?? BoxState()
        #if DEBUG
        if !state.bars.isEmpty, state.bars.count != count {
            WinampModernAnalyzerTap.traceGap("bandcount vis \(state.bars.count)->\(count) "
                                             + "width=\(frame.width)")
        }
        #endif
        if state.bars.count != count { state.bars = Array(repeating: 0, count: count) }
        if state.peaks.count != count { state.peaks = Array(repeating: 0, count: count) }
        let now = CACurrentMediaTime()
        let elapsed = state.lastDraw > 0
            ? min(Self.maximumDecayStep, max(0, now - state.lastDraw)) : 0
        state.lastDraw = now
        let barStep = style.barFalloff * CGFloat(elapsed)
        let peakStep = style.peakFalloff * CGFloat(elapsed)

        for index in 0..<count {
            let level = bandFraction(index)
            // The bar falls at the skin's `falloff` and **rises over `barAttackSeconds`** rather
            // than being assigned its band outright: assigned, it jumped the whole box in one frame
            // (`WasabiVisStyle.risen`).
            //
            // **Rise or fall, never both.** The fall is the skin's `falloff` and is clamped at the
            // band, exactly as it always was; the rise is `barAttackSeconds`. Applying both every
            // frame — subtracting `barStep` and *then* smoothing back toward the band — was wrong
            // twice over: it put the bar **below** its own band, and the two rates settled at an
            // equilibrium the band could never reach, so a full-scale band drew at 0.837 of the box
            // and the row hunted instead of tracking. Measured with `WINAMP_MODERN_VIS_FRAMES`.
            let previous = state.bars[index]
            let bar = level > previous
                ? WasabiVisStyle.risen(from: previous, toward: level, elapsed: elapsed)
                : max(level, previous - barStep)
            state.bars[index] = bar
            state.peaks[index] = max(bar, state.peaks[index] - peakStep)
            context.setFillColor(style.barColor(index: index, count: count, level: bar))
            let (x, barWidth) = columns(index)
            context.fill(CGRect(x: x, y: frame.maxY - bar * frame.height,
                                width: barWidth, height: bar * frame.height))
            // **A cap draws only once it has cleared its bar by a visible gap**, not merely once
            // `peaks > bar`. That test is true the instant a bar falls by a fraction of a pixel, and
            // the cap it paints then touches the bar top — which is not a floating cap at all, it is
            // a brighter fringe along the top of the row. At `thin`'s 75 bands in a 144px box the
            // fringe is continuous and reads as a defect, which is what B54 was still reporting
            // after its parked-cap cause was fixed.
            let capHeight: CGFloat = frame.height >= 16 ? 2 : 1
            let barTop = frame.maxY - bar * frame.height
            let capY = min(frame.maxY - capHeight, frame.maxY - state.peaks[index] * frame.height)
            guard style.showsPeaks,
                  Self.capClears(barTop: barTop, capY: capY, capHeight: capHeight)
            else { continue }
            context.setFillColor(style.peakColor
                                 ?? style.barColor(index: index, count: count, level: bar))
            context.fill(CGRect(x: x, y: capY, width: barWidth, height: capHeight))
        }
        boxes[input.objectID] = state
        #if DEBUG
        if let probe = WasabiSceneRenderer.visFrameProbe, probe < count {
            NSLog("%@", "WM-VIS-FRAME vis t=\(String(format: "%.3f", now)) "
                  + "elapsed=\(Int(elapsed * 1_000))ms band=\(probe) "
                  + "level=\(String(format: "%.3f", bandFraction(probe))) "
                  + "bar=\(String(format: "%.3f", state.bars[probe]))")
        }
        #endif
        WasabiSceneRenderer.traceVisInput(bands, site: style.isThin ? "vis/thin" : "vis/wide",
                                          peaks: state.peaks)
    }

    // MARK: - The oscilloscope

    /// **Left channel only** — Winamp's scope reads channel 0, and the mirrored second box is the
    /// skin's job (Big Bento's `main.vis` is `fliph="1"`), not ours.
    private func drawOscilloscope(_ input: WasabiVisInput, in frame: CGRect, context: CGContext) {
        let samples = input.waveform.left
        guard !samples.isEmpty else { return }
        let style = input.style
        let columns = max(1, min(samples.count, Int(frame.width.rounded())))
        let gain = WinampModernVisSensitivity.oscilloscopeGain()
        // One column per pixel of box width, sampled across the buffer.
        func sample(_ column: Int) -> (y: CGFloat, excursion: CGFloat) {
            let index = min(samples.count - 1, column * samples.count / columns)
            // Clamped to the box, so turning Sensitivity up makes a quiet track legible without
            // drawing the loud parts outside the rect the skin's author gave this box.
            let offset = max(-1, min(1, (CGFloat(samples[index]) - 128) / 128 * gain))
            return (frame.midY + offset * frame.height / 2, min(1, abs(offset)))
        }
        func x(_ column: Int) -> CGFloat {
            columns == 1 ? frame.midX
                : frame.minX + CGFloat(column) * (frame.width - 1) / CGFloat(columns - 1)
        }

        context.saveGState()
        defer { context.restoreGState() }
        context.setLineWidth(1)
        switch style.oscStyle {
        case .lines:
            // Stroked segment by segment, each in the colour of the sample it arrives at: the five
            // `colorosc` steps are a gradient by excursion, so one stroke for the whole polyline
            // would throw four of them away.
            var previous = sample(0)
            for column in 1..<max(2, columns) {
                let current = sample(column)
                context.setStrokeColor(style.oscColor(excursion: current.excursion))
                context.beginPath()
                context.move(to: CGPoint(x: x(column - 1), y: previous.y))
                context.addLine(to: CGPoint(x: x(column), y: current.y))
                context.strokePath()
                previous = current
            }
        case .dots:
            for column in 0..<columns {
                let point = sample(column)
                context.setFillColor(style.oscColor(excursion: point.excursion))
                context.fill(CGRect(x: x(column), y: point.y, width: 1, height: 1))
            }
        case .solid:
            for column in 0..<columns {
                let point = sample(column)
                context.setFillColor(style.oscColor(excursion: point.excursion))
                let top = max(point.y, frame.midY)
                let bottom = min(point.y, frame.midY)
                context.fill(CGRect(x: x(column), y: bottom,
                                    width: 1, height: max(1, top - bottom)))
            }
        }
    }
}
