import AppKit
import SwiftUI
import NullPlayerCore

/// Octave spectrum pane — displays logarithmic octave band analysis with peak-hold.
struct OctavePaneView: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        return OctaveCanvasView()
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        // View handles all updates via notifications
    }
}

/// Canvas-based octave spectrum analyzer with peak-hold decay.
class OctaveCanvasView: NSView {
    private var magnitudes: [Float] = []
    private var sampleRate: Double = 44100
    private var fftSize: Int = 2048
    private var bands: [(centerHz: Double, level: Float)] = []

    // Peak-hold per band (decays slowly)
    private var peakHolds: [Float] = Array(repeating: 0, count: 100)
    private var magnitudesObserver: NSObjectProtocol?

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

        // Observe magnitudes updates from the audio engine
        // Receive on the posting thread (`queue: nil`) and hop to main ourselves. `queue: .main`
        // makes NotificationCenter deliver synchronously and blocks the real-time audio tap
        // thread on the main queue, deadlocking against tap teardown during rapid track loads.
        magnitudesObserver = NotificationCenter.default.addObserver(
            forName: .audioFFTMagnitudesUpdated,
            object: nil,
            queue: nil
        ) { notification in
            guard let userInfo = notification.userInfo,
                  let magnitudes = userInfo["magnitudes"] as? [Float],
                  let sampleRate = userInfo["sampleRate"] as? Double,
                  let fftSize = userInfo["fftSize"] as? Int else { return }

            DispatchQueue.main.async { [weak self] in
                self?.updateWithMagnitudes(magnitudes, sampleRate: sampleRate, fftSize: fftSize)
                self?.needsDisplay = true
            }
        }
    }

    deinit {
        if let observer = magnitudesObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    private func updateWithMagnitudes(_ magnitudes: [Float], sampleRate: Double, fftSize: Int) {
        self.magnitudes = magnitudes
        self.sampleRate = sampleRate
        self.fftSize = fftSize

        // Compute octave bands (3 bands per octave, 20 Hz to 20 kHz)
        self.bands = AudioAnalysisDSP.octaveBands(
            magnitudes: magnitudes,
            sampleRate: sampleRate,
            fftSize: fftSize,
            bandsPerOctave: 3,
            minFreq: 20,
            maxFreq: 20000
        )

        // Update peak holds (decay slowly, track maxima). Preserve peaks across
        // frames; resize only when the band count changes.
        if peakHolds.count != bands.count {
            peakHolds = Array(repeating: 0, count: bands.count)
        }
        for i in 0..<bands.count {
            let level = bands[i].level
            let oldPeak = peakHolds[i]
            peakHolds[i] = max(level, oldPeak * 0.85)  // 85% decay per frame
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        guard let context = NSGraphicsContext.current?.cgContext else { return }

        // Background
        NSColor.black.setFill()
        bounds.fill()

        guard !bands.isEmpty else { return }

        drawOctaveSpectrum(in: context)
    }

    private func drawOctaveSpectrum(in context: CGContext) {
        let width = bounds.width
        let height = bounds.height
        // Tight margins: the content area is short (~88pt), so reserve only a title
        // line at the top and an x-axis label strip at the bottom. The bars get the rest.
        let topMargin: CGFloat = 15
        let bottomMargin: CGFloat = 14
        let leftMargin: CGFloat = 6
        let rightMargin: CGFloat = 6

        let plotWidth = width - leftMargin - rightMargin
        let plotHeight = height - topMargin - bottomMargin

        guard plotWidth > 0, plotHeight > 0, !bands.isEmpty else { return }

        // Draw title (top line)
        let titleAttr: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 10, weight: .semibold),
            .foregroundColor: NSColor.green
        ]
        let titleStr = NSAttributedString(string: "Octave (1/3)", attributes: titleAttr)
        titleStr.draw(at: CGPoint(x: leftMargin, y: height - 13))

        // Bars grow UP from a bottom baseline (non-flipped NSView: y=0 is the bottom).
        let baselineY = bottomMargin
        let barWidth = plotWidth / CGFloat(bands.count)

        for (index, band) in bands.enumerated() {
            let x = leftMargin + CGFloat(index) * barWidth + barWidth * 0.1
            let barActualWidth = max(1, barWidth * 0.8)
            let barHeight = CGFloat(band.level) * plotHeight

            let barRect = CGRect(x: x, y: baselineY, width: barActualWidth, height: barHeight)

            let color: NSColor
            if band.level > 0.7 {
                color = NSColor.red
            } else if band.level > 0.4 {
                color = NSColor.yellow
            } else {
                color = NSColor.green
            }

            context.setFillColor(color.cgColor)
            context.fill(barRect)

            // Peak-hold marker
            if index < peakHolds.count {
                let peakY = baselineY + CGFloat(peakHolds[index]) * plotHeight
                context.setStrokeColor(NSColor.white.cgColor)
                context.setLineWidth(1)
                context.move(to: CGPoint(x: x, y: peakY))
                context.addLine(to: CGPoint(x: x + barActualWidth, y: peakY))
                context.strokePath()
            }
        }

        // Frequency labels below the baseline. Use a sparse set so they don't crowd.
        let labelFreqs: [Double] = [63, 250, 1000, 4000, 16000]
        let labelAttr: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 8, weight: .regular),
            .foregroundColor: NSColor.gray
        ]

        for freq in labelFreqs {
            if let closestIndex = bands.enumerated().min(by: {
                abs($0.element.centerHz - freq) < abs($1.element.centerHz - freq)
            })?.offset {
                let x = leftMargin + CGFloat(closestIndex) * barWidth + barWidth / 2
                let labelStr = NSAttributedString(string: formatFrequency(freq), attributes: labelAttr)
                let labelSize = labelStr.size()
                labelStr.draw(at: CGPoint(x: x - labelSize.width / 2, y: 2))
            }
        }
    }

    private func formatFrequency(_ hz: Double) -> String {
        if hz >= 1000 {
            return String(format: "%.1fk", hz / 1000)
        } else {
            return String(format: "%.0f", hz)
        }
    }
}
