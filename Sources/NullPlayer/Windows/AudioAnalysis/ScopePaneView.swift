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
/// in the `ScopeTrace` in order — contiguous audio at the display's refresh rate.
class ScopeCanvasView: NSView, AudioAnalysisPausableRenderer {
    private let playout = WaveformPlayout()
    private var trace = ScopeTrace()
    /// The playout's number for the last chunk taken, so each chunk is taken once and none is missed.
    private var lastChunkNumber: Int?
    /// Playout time already stepped through.
    private var readTime: TimeInterval?
    private var displayLink: CADisplayLink?
    private var renderingPaused = false
    private var waveformObserver: NSObjectProtocol?

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
        var time = max(readTime ?? now, now - chunkDuration * Double(ScopeTrace.historyChunks))
        var appended = false
        while time <= now {
            // Every chunk played since the last one taken, in order; once the audio has stopped,
            // silence repeats until the trace is flat.
            let played = playout.chunksPlayed(after: lastChunkNumber, at: time)
            for chunk in played {
                trace.append(left: chunk.left, right: chunk.right)
            }
            if let newest = played.last {
                lastChunkNumber = newest.number
                appended = true
            } else if !trace.isFlat, playout.samples(at: time).left == WaveformPlayout.silence {
                trace.append(left: WaveformPlayout.silence, right: WaveformPlayout.silence)
                appended = true
            }
            time += chunkDuration
        }
        readTime = time
        if appended {
            trace.render(at: now)
            needsDisplay = true
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        guard let context = NSGraphicsContext.current?.cgContext else { return }

        // Background
        NSColor.black.setFill()
        bounds.fill()

        guard trace.points.count > 1 else { return }

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

        let points = trace.points
        let n = points.count
        func point(_ i: Int) -> CGPoint {
            let x = width * CGFloat(i) / CGFloat(n - 1)
            let clamped = max(-1.0, min(1.0, CGFloat(points[i])))
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
