import SwiftUI
import NullPlayerCore

/// Delay Estimator pane — displays inter-channel phase delay using cross-correlation.
struct DelayPaneView: View {
    @State private var delaySamples: Int = 0
    @State private var delayMS: Double = 0
    @State private var direction: String = "aligned"
    @State private var sampleRate: Double = 44100

    private var rangeMS: Double { 256.0 / sampleRate * 1000 }  // ±5.8 ms at 44.1 kHz

    var body: some View {
        // Compact, fit-in-place layout — the content area is short (~88pt tall at
        // the default window size). Centered so it scales up cleanly when resized.
        VStack(spacing: 6) {
            Spacer(minLength: 0)

            // Primary readouts: delay (ms) + lag (samples)
            HStack(alignment: .top, spacing: 24) {
                readout(caption: "DELAY (ms)", value: String(format: "%.2f", delayMS))
                readout(caption: "SAMPLES", value: String(delaySamples))
            }
            .padding(.horizontal, 12)

            Text(direction)
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundColor(.cyan)

            // Horizontal needle centered at 0
            GeometryReader { geo in
                let normalized = min(1.0, max(-1.0, delayMS / rangeMS))
                ZStack {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color(white: 0.12))
                    Rectangle()
                        .fill(Color(white: 0.4))
                        .frame(width: 1)
                    Rectangle()
                        .fill(Color.yellow)
                        .frame(width: 2)
                        .position(
                            x: geo.size.width / 2 + normalized * geo.size.width / 2.2,
                            y: geo.size.height / 2
                        )
                }
            }
            .frame(height: 12)
            .padding(.horizontal, 24)

            Text("range ±\(String(format: "%.1f", rangeMS)) ms")
                .font(.system(size: 8, weight: .regular, design: .monospaced))
                .foregroundColor(Color(white: 0.5))

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
        .onReceive(NotificationCenter.default.publisher(for: .audioStereoPCMDataUpdated).receive(on: DispatchQueue.main)) { notification in
            guard let userInfo = notification.userInfo,
                  let left = userInfo["left"] as? [Float],
                  let right = userInfo["right"] as? [Float],
                  let sr = userInfo["sampleRate"] as? Double else { return }

            sampleRate = sr

            // Compute cross-correlation delay
            let maxLag = left.count / 2
            let lagSamples = AudioAnalysisDSP.estimateDelaySamples(left: left, right: right, maxLagSamples: maxLag)

            delaySamples = lagSamples
            delayMS = Double(lagSamples) / sr * 1000

            if lagSamples > 0 {
                direction = "right lags left"
            } else if lagSamples < 0 {
                direction = "left lags right"
            } else {
                direction = "aligned"
            }
        }
    }

    /// A captioned numeric readout that shrinks to fit rather than clipping.
    private func readout(caption: String, value: String) -> some View {
        VStack(spacing: 2) {
            Text(caption)
                .font(.system(size: 8, weight: .semibold, design: .monospaced))
                .foregroundColor(.gray)
            Text(value)
                .font(.system(size: 26, weight: .semibold, design: .monospaced))
                .foregroundColor(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.4)
        }
        .frame(maxWidth: .infinity)
    }
}
