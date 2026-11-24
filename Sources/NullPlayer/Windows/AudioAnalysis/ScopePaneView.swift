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
/// Fed by the waveform consumer (`.audioWaveform576DataUpdated`): every sample, in 576-sample chunks
/// that arrive several at a time per tap buffer. A `WaveformPlayout` plays them out at the audio's own
/// rate, and each display refresh steps its clock one chunk at a time up to now, so every chunk lands
/// in `history` in order — contiguous audio at the display's refresh rate.
///
/// Two things keep the trace readable: a **trigger** that phase-locks each window to a rising
/// zero-crossing (so periodic content stays stationary instead of swimming horizontally), and a
/// gentle **temporal blend** of the now-aligned windows (so the line stops flickering frame to frame
/// without smearing transients).
class ScopeCanvasView: NSView {
    /// Chunks of history kept: the drawn window is three chunks less the trigger search region.
    private static let historyChunks = 3
    /// Samples per drawn point.
    private static let drawStride = 3
    /// The blend weights below were tuned at the old ~20 updates per second; scaled per refresh to it.
    private static let blendReferenceRate = 20.0
    /// Below half an 8-bit step the trace is drawn flat; silence stops repeating there.
    private static let flatThreshold: Float = 0.002

    private let playout = WaveformPlayout()
    /// The last `historyChunks` played-out chunks, mono, -1…1, oldest first.
    private var history = [Float](repeating: 0, count: WaveformPlayout.sampleCount * ScopeCanvasView.historyChunks)
    private var lastChunk: [UInt8] = []
    /// Playout time already stepped through.
    private var readTime: TimeInterval?
    /// Phase-aligned, temporally smoothed window that is actually drawn.
    private var displayBuffer: [Float] = []
    private var displayLink: CADisplayLink?
    private var renderingPaused = false
    private var waveformObserver: NSObjectProtocol?

    /// Temporal-blend weights (1 = no smoothing, lower = smoother). The blend is asymmetric: a window
    /// that is louder than what's on screen (a beat) snaps in quickly so it is never averaged away,
    /// while quieter windows blend slowly to suppress flicker.
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

        // `WaveformPlayout.receive` is built to run on the posting thread (the real-time audio tap):
        // a lock and an append. Never `queue: .main`, which blocks the tap on the main queue and
        // deadlocks against tap teardown during rapid track loads.
        let playout = playout
        waveformObserver = NotificationCenter.default.addObserver(
            forName: .audioWaveform576DataUpdated,
            object: nil,
            queue: nil
        ) { notification in
            guard let userInfo = notification.userInfo,
                  let left = userInfo["left"] as? [UInt8],
                  let right = userInfo["right"] as? [UInt8] else { return }
            playout.receive(left: left, right: right, sampleRate: userInfo["sampleRate"] as? Double,
                            at: ProcessInfo.processInfo.systemUptime)
        }
    }

    deinit {
        if let observer = waveformObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    /// Hidden, minimized or closed: drop the display link (it retains this view) until shown again.
    func setRenderingPaused(_ paused: Bool) {
        renderingPaused = paused
        updateDisplayLink()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updateDisplayLink()
    }

    private func updateDisplayLink() {
        let wanted = window != nil && !renderingPaused
        guard wanted != (displayLink != nil) else { return }
        if wanted {
            let newLink = displayLink(target: self, selector: #selector(tick(_:)))
            newLink.add(to: .main, forMode: .common)
            displayLink = newLink
        } else {
            displayLink?.invalidate()
            displayLink = nil
            readTime = nil
        }
    }

    @objc private func tick(_ sender: CADisplayLink) {
        let now = ProcessInfo.processInfo.systemUptime
        let chunkDuration = TimeInterval(WaveformPlayout.sampleCount) / playout.sampleRate
        // Step the playout clock one chunk at a time so no chunk is skipped between refreshes.
        var time = max(readTime ?? now, now - chunkDuration * Double(Self.historyChunks))
        var stepped: TimeInterval = 0
        var appended = false
        while time <= now {
            let chunk = playout.samples(at: time)
            // The playout repeats its current chunk until the next is due; take each chunk once,
            // except silence (paused, or a silent passage), which repeats until the trace is flat.
            let isSilence = chunk.left == WaveformPlayout.silence
            let flattening = isSilence && displayBuffer.contains { abs($0) > Self.flatThreshold }
            if isSilence && !flattening {
                // Flat after a pause: restart the playout's clock. A gap leaves it behind real time,
                // so every later burst would be consumed in one read and show one chunk per tap.
                playout.reset()
            }
            if chunk.left != lastChunk || flattening {
                lastChunk = chunk.left
                append(chunk)
                appended = true
            }
            time += chunkDuration
            stepped += chunkDuration
        }
        readTime = time
        if appended { render(elapsed: stepped) }
    }

    private func append(_ chunk: (left: [UInt8], right: [UInt8])) {
        let count = WaveformPlayout.sampleCount
        history.removeFirst(count)
        for i in 0..<count {
            history.append((Float(chunk.left[i]) + Float(chunk.right[i]) - 256) / 254)
        }
    }

    /// Trigger-align the newest window of `history` and blend it into the display buffer.
    private func render(elapsed: TimeInterval) {
        let maxTriggerOffset = history.count / 4          // search the first quarter for the trigger
        let windowLength = (history.count - maxTriggerOffset) / Self.drawStride

        // Trigger: first rising zero-crossing in the search region. Falls back to 0 (no lock) when
        // none is found (silence / aperiodic noise), which simply leaves the trace where it is.
        var trigger = 0
        for i in 1...maxTriggerOffset where history[i - 1] <= 0 && history[i] > 0 {
            trigger = i
            break
        }
        func sample(_ i: Int) -> Float { history[trigger + i * Self.drawStride] }

        if displayBuffer.count != windowLength {
            displayBuffer = (0..<windowLength).map(sample)
            needsDisplay = true
            return
        }

        // Asymmetric blend: snap toward a louder window (a beat), ease toward a quieter one. This stops
        // the smoothing from averaging away a strong beat whose trigger locked to a different cycle.
        var framePeak: Float = 0
        var displayPeak: Float = 0
        for i in 0..<windowLength {
            framePeak = max(framePeak, abs(sample(i)))
            displayPeak = max(displayPeak, abs(displayBuffer[i]))
        }
        let frameWeight = framePeak > displayPeak ? attackWeight : releaseWeight
        let weight = 1 - pow(1 - frameWeight, Float(min(1, elapsed * Self.blendReferenceRate)))
        for i in 0..<windowLength {
            displayBuffer[i] += (sample(i) - displayBuffer[i]) * weight
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
