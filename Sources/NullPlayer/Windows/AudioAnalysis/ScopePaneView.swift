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
/// Two things keep the trace readable: a **trigger** that phase-locks each frame to a rising
/// zero-crossing (so periodic content stays stationary instead of swimming horizontally), and a
/// gentle **temporal blend** of the now-aligned frames (so the line stops flickering frame to frame
/// without smearing transients).
class ScopeCanvasView: NSView {
    /// Phase-aligned, temporally smoothed window that is actually drawn.
    private var displayBuffer: [Float] = []
    private var pcmObserver: NSObjectProtocol?

    /// Temporal-blend weights (1 = no smoothing, lower = smoother). The blend is asymmetric: a frame
    /// that is louder than what's on screen (a beat) snaps in quickly so it is never averaged away,
    /// while quieter frames blend slowly to suppress flicker.
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
        pcmObserver = NotificationCenter.default.addObserver(
            forName: .audioPCMDataUpdated,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let userInfo = notification.userInfo,
                  let pcm = userInfo["pcm"] as? [Float] else { return }
            self?.ingest(pcm)
        }
    }

    deinit {
        if let observer = pcmObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    /// Trigger-align an incoming frame and blend it into the display buffer.
    private func ingest(_ pcm: [Float]) {
        let count = pcm.count
        let maxTriggerOffset = count / 4          // search the first quarter for the trigger
        let windowLength = count - maxTriggerOffset
        guard windowLength > 1, maxTriggerOffset >= 1 else { return }

        // Trigger: first rising zero-crossing in the search region. Falls back to 0 (no lock) when
        // none is found (silence / aperiodic noise), which simply leaves the trace where it is.
        var trigger = 0
        for i in 1...maxTriggerOffset where pcm[i - 1] <= 0 && pcm[i] > 0 {
            trigger = i
            break
        }

        if displayBuffer.count != windowLength {
            displayBuffer = Array(pcm[trigger..<(trigger + windowLength)])
            needsDisplay = true
            return
        }

        // Asymmetric blend: snap toward a louder frame (a beat), ease toward a quieter one. This stops
        // the smoothing from averaging away a strong beat whose trigger locked to a different cycle.
        var framePeak: Float = 0
        var displayPeak: Float = 0
        for i in 0..<windowLength {
            framePeak = max(framePeak, abs(pcm[trigger + i]))
            displayPeak = max(displayPeak, abs(displayBuffer[i]))
        }
        let weight = framePeak > displayPeak ? attackWeight : releaseWeight
        for i in 0..<windowLength {
            displayBuffer[i] += (pcm[trigger + i] - displayBuffer[i]) * weight
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
