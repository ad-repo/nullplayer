import AppKit
import SwiftUI

/// Oscilloscope view — displays waveform in real-time
struct ScopePaneView: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        return ScopeCanvasView()
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        // View handles all updates via notifications
    }
}

/// Canvas-based oscilloscope renderer.
///
/// The engine posts one 512-point PCM frame per 2048-sample tap buffer (~21 per second), so drawing
/// once per frame caps the trace at ~21 FPS. Instead the view keeps the last two frames and, on every
/// display refresh, slides its window through them by the time elapsed since the newest frame arrived
/// (the trace runs one frame behind, ~46 ms).
///
/// Two things keep the trace readable: a **trigger** that phase-locks each window to a rising
/// zero-crossing (so periodic content stays stationary instead of swimming horizontally), and a
/// gentle **temporal blend** of the now-aligned windows (so the line stops flickering frame to frame
/// without smearing transients).
class ScopeCanvasView: NSView {
    /// Phase-aligned, temporally smoothed window that is actually drawn.
    private var displayBuffer: [Float] = []
    /// The previous and newest PCM frames, back to back.
    private var history: [Float] = []
    private var frameLength = 0
    private var lastFrameTime: CFTimeInterval = 0
    /// Smoothed interval between frame arrivals; the slide covers one frame in this time.
    private var frameInterval: CFTimeInterval = 2048.0 / 44100.0
    private var lastTickTime: CFTimeInterval = 0
    private var link: CADisplayLink?
    private var pcmObserver: NSObjectProtocol?

    /// Temporal-blend weights per arriving frame (1 = no smoothing, lower = smoother); converted to a
    /// per-refresh weight so the feel does not depend on the display rate. The blend is asymmetric: a
    /// window that is louder than what's on screen (a beat) snaps in quickly so it is never averaged
    /// away, while quieter windows blend slowly to suppress flicker.
    private let attackWeight: Float = 0.85
    private let releaseWeight: Float = 0.45

    override init(frame: NSRect) {
        super.init(frame: frame)
        commonInit()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        commonInit()
    }

    private func commonInit() {
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor

        // Observe PCM data updates from the audio engine
        // Receive on the posting thread (`queue: nil`) and hop to main ourselves. `queue: .main`
        // makes NotificationCenter deliver synchronously and blocks the real-time audio tap
        // thread on the main queue, deadlocking against tap teardown during rapid track loads.
        pcmObserver = NotificationCenter.default.addObserver(
            forName: .audioPCMDataUpdated,
            object: nil,
            queue: nil
        ) { notification in
            guard let userInfo = notification.userInfo,
                  let pcm = userInfo["pcm"] as? [Float] else { return }
            DispatchQueue.main.async { [weak self] in
                self?.ingest(pcm)
            }
        }
    }

    deinit {
        if let observer = pcmObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        link?.invalidate()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        link?.invalidate()
        link = nil
        guard window != nil else { return }
        let link = displayLink(target: self, selector: #selector(tick(_:)))
        link.isPaused = true
        link.add(to: .main, forMode: .common)
        self.link = link
    }

    private func ingest(_ pcm: [Float]) {
        let now = CACurrentMediaTime()
        if pcm.count != frameLength {
            frameLength = pcm.count
            history = pcm + pcm
        } else {
            history.removeFirst(frameLength)
            history += pcm
            let interval = now - lastFrameTime
            if interval < 0.5 { frameInterval += (interval - frameInterval) * 0.1 }
        }
        lastFrameTime = now
        if link?.isPaused == true {
            lastTickTime = now
            link?.isPaused = false
        }
    }

    @objc private func tick(_ link: CADisplayLink) {
        let now = CACurrentMediaTime()
        let elapsed = now - lastFrameTime
        // Frames stopped (paused, silence gate, window hidden): park on the newest frame and idle.
        if elapsed > frameInterval * 3 { link.isPaused = true }
        let progress = min(1, elapsed / frameInterval)
        let dt = now - lastTickTime
        lastTickTime = now
        render(windowStart: Int(progress * Double(frameLength)), framesElapsed: Float(dt / frameInterval))
    }

    /// Trigger-align the window at `windowStart` in `history` and blend it into the display buffer.
    private func render(windowStart: Int, framesElapsed: Float) {
        let count = frameLength
        let maxTriggerOffset = count / 4          // search the first quarter for the trigger
        let windowLength = count - maxTriggerOffset
        guard windowLength > 1, maxTriggerOffset >= 1 else { return }
        let start = min(windowStart, history.count - count)

        // Trigger: first rising zero-crossing in the search region. Falls back to the window start (no lock) when
        // none is found (silence / aperiodic noise), which simply leaves the trace where it is.
        var trigger = start
        for i in (start + 1)...(start + maxTriggerOffset) where history[i - 1] <= 0 && history[i] > 0 {
            trigger = i
            break
        }

        if displayBuffer.count != windowLength {
            displayBuffer = Array(history[trigger..<(trigger + windowLength)])
            needsDisplay = true
            return
        }

        // Asymmetric blend: snap toward a louder window (a beat), ease toward a quieter one. This stops
        // the smoothing from averaging away a strong beat whose trigger locked to a different cycle.
        var framePeak: Float = 0
        var displayPeak: Float = 0
        for i in 0..<windowLength {
            framePeak = max(framePeak, abs(history[trigger + i]))
            displayPeak = max(displayPeak, abs(displayBuffer[i]))
        }
        let frameWeight = framePeak > displayPeak ? attackWeight : releaseWeight
        let weight = 1 - pow(1 - frameWeight, min(1, framesElapsed))
        for i in 0..<windowLength {
            displayBuffer[i] += (history[trigger + i] - displayBuffer[i]) * weight
        }
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        guard let context = NSGraphicsContext.current?.cgContext else { return }

        // Background
        NSColor.black.setFill()
        bounds.fill()

        guard displayBuffer.count > 1 else { return }

        drawWaveform(in: context)
    }

    private func drawWaveform(in context: CGContext) {
        let width = bounds.width
        let height = bounds.height
        let centerY = height / 2

        // Grid lines
        context.setStrokeColor(NSColor.darkGray.cgColor)
        context.setLineWidth(0.5)
        for i in 1..<4 {
            let y = CGFloat(i) * (height / 4)
            context.move(to: CGPoint(x: 0, y: y))
            context.addLine(to: CGPoint(x: width, y: y))
        }
        context.strokePath()

        // Waveform line — smoothed with quadratic segments through sample midpoints.
        context.setStrokeColor(NSColor.green.cgColor)
        context.setLineWidth(1.5)
        context.setLineJoin(.round)
        context.setLineCap(.round)

        let n = displayBuffer.count
        func point(_ i: Int) -> CGPoint {
            let x = width * CGFloat(i) / CGFloat(n - 1)
            let clamped = max(-1.0, min(1.0, CGFloat(displayBuffer[i])))
            return CGPoint(x: x, y: centerY - clamped * (centerY - 4))
        }

        context.move(to: point(0))
        if n == 2 {
            context.addLine(to: point(1))
        } else {
            for i in 1..<(n - 1) {
                let current = point(i)
                let next = point(i + 1)
                let mid = CGPoint(x: (current.x + next.x) / 2, y: (current.y + next.y) / 2)
                context.addQuadCurve(to: mid, control: current)
            }
            context.addLine(to: point(n - 1))
        }
        context.strokePath()
    }
}
