import AppKit

/// How an AIMP window's frames are drawn, and by what clock. A window draws off the main thread, on
/// one queue every AIMP window shares, one frame at a time: requests made while one is drawing wait
/// as one, the latest, which also measures if any of them asked to. The probe draws each frame as it
/// asks for it, so what it measures and clicks is that frame, at a clock it moves itself.
@MainActor
final class AIMPSkinFrameScheduler {
    enum Timing: Equatable {
        /// Off the main thread, at the media clock.
        case window
        /// At once, at `clock` where the probe sets one (the deck), else at the skin's tick's (its
        /// other windows).
        case probe(clock: Double?)
    }

    var timing = Timing.window

    /// The probe's clock; nil for the media clock, or the tick's.
    var probeClock: Double? {
        guard case .probe(let clock) = timing else { return nil }
        return clock
    }

    /// Now, by this window's clock.
    var now: Double { probeClock ?? CACurrentMediaTime() }

    /// What a frame is drawn from: everything is a value, so it can be drawn off the main thread.
    struct RenderInput: Sendable {
        let skin: AIMPSkin
        let size: CGSize
        let form: String?
        let host: AIMPSkinHostState
        let state: AIMPSkinState
        let interaction: AIMPSkinInteraction
        /// Also measure what the frame draws (its layout moved).
        var measures: Bool
        /// Whose frame it is: the view's skin as it asked (`AIMPSkinMainView.Generation`), so a
        /// frame of a skin since replaced, even by one of the same name, is not shown.
        let generation: AIMPSkinMainView.Generation
    }

    struct RenderOutput: Sendable {
        let generation: AIMPSkinMainView.Generation
        let frame: AIMPSkinFrame?
        /// The drawn part of the canvas, and whether anything is, when the input asked.
        let measured: (bounds: CGRect?, size: CGSize)?
    }

    /// Frames are drawn here, one at a time, for every AIMP window.
    private static let drawQueue = DispatchQueue(label: "com.nullplayer.aimp-draw", qos: .userInteractive)
    private var drawing = false
    /// What was asked while a frame drew: the latest input, measuring if any asked to, and where its
    /// frame goes.
    private var pending: (input: RenderInput, show: @MainActor (RenderOutput) -> Void)?

    /// Draws `input` and hands the frame to `show` on the main thread. Asked while a frame is drawing,
    /// it waits; the latest of those waiting draws next, and measures if any of them asked to.
    func draw(_ input: RenderInput, show: @escaping @MainActor (RenderOutput) -> Void) {
        guard timing == .window else { return show(Self.draw(input)) }
        guard !drawing else {
            var latest = input
            latest.measures = input.measures || pending?.input.measures == true
            pending = (latest, show)
            return
        }
        drawing = true
        Self.drawQueue.async { [weak self] in
            let output = Self.draw(input)
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.drawing = false
                    show(output)
                    guard let next = self.pending else { return }
                    self.pending = nil
                    self.draw(next.input, show: next.show)
                }
            }
        }
    }

    nonisolated static func draw(_ input: RenderInput) -> RenderOutput {
        let frame = AIMPSkinRenderer.frame(input.skin, size: input.size, form: input.form, host: input.host,
                                           state: input.state, interaction: input.interaction)
        var measured: (bounds: CGRect?, size: CGSize)?
        if input.measures, let frame {
            // Measured with everything a pointer reveals revealed, so the window holds still as it comes and goes.
            var revealed = input.host
            revealed.feedback.pointer = .anywhere
            let full = input.host.feedback.hoverRects.isEmpty ? frame
                : AIMPSkinRenderer.frame(input.skin, size: input.size, form: input.form, host: revealed, state: input.state) ?? frame
            measured = (full.alpha?.drawnBounds, input.size)
        }
        return RenderOutput(generation: input.generation, frame: frame, measured: measured)
    }
}
