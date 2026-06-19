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

/// Canvas-based oscilloscope renderer
class ScopeCanvasView: NSView {
    private var pcmData: [Float] = []
    private var sampleRate: Double = 44100
    private var pcmObserver: NSObjectProtocol?

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
                  let pcm = userInfo["pcm"] as? [Float],
                  let sampleRate = userInfo["sampleRate"] as? Double else { return }
            self?.pcmData = pcm
            self?.sampleRate = sampleRate
            self?.needsDisplay = true
        }
    }

    deinit {
        if let observer = pcmObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        guard let context = NSGraphicsContext.current?.cgContext else { return }

        // Background
        NSColor.black.setFill()
        bounds.fill()

        guard !pcmData.isEmpty else { return }

        // Draw waveform
        drawWaveform(in: context)
    }

    private func drawWaveform(in context: CGContext) {
        let width = bounds.width
        let height = bounds.height
        let centerY = height / 2

        // Grid lines (optional)
        context.setStrokeColor(NSColor.darkGray.cgColor)
        context.setLineWidth(0.5)
        for i in 1..<4 {
            let y = CGFloat(i) * (height / 4)
            context.move(to: CGPoint(x: 0, y: y))
            context.addLine(to: CGPoint(x: width, y: y))
        }
        context.strokePath()

        // Waveform line
        context.setStrokeColor(NSColor.green.cgColor)
        context.setLineWidth(1.5)

        let samplesPerPixel = max(1, pcmData.count / Int(width))
        var isFirstPoint = true

        for x in 0..<Int(width) {
            let sampleIndex = min(x * samplesPerPixel, pcmData.count - 1)
            let sample = pcmData[sampleIndex]

            // Clamp sample to [-1, 1] and map to screen coordinates
            let clampedSample = max(-1.0, min(1.0, sample))
            let screenY = centerY - CGFloat(clampedSample) * (centerY - 4)

            let point = CGPoint(x: CGFloat(x), y: screenY)

            if isFirstPoint {
                context.move(to: point)
                isFirstPoint = false
            } else {
                context.addLine(to: point)
            }
        }

        context.strokePath()
    }
}
