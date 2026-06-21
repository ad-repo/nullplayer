import SwiftUI
import NullPlayerCore

/// Levels pane — displays stereo peak and RMS meters as vertical bars that fill the window.
struct LevelsPaneView: View {
    @State private var leftPeakDB: Float = -120
    @State private var rightPeakDB: Float = -120
    @State private var leftRMSDB: Float = -120
    @State private var rightRMSDB: Float = -120

    var body: some View {
        HStack(spacing: 24) {
            ChannelMetersView(
                name: "LEFT",
                nameColor: .cyan,
                peakDB: leftPeakDB,
                rmsDB: leftRMSDB
            )
            ChannelMetersView(
                name: "RIGHT",
                nameColor: Color(red: 1, green: 0, blue: 1),
                peakDB: rightPeakDB,
                rmsDB: rightRMSDB
            )
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
        .onReceive(NotificationCenter.default.publisher(for: .audioStereoPCMDataUpdated).receive(on: DispatchQueue.main)) { notification in
            guard let userInfo = notification.userInfo,
                  let left = userInfo["left"] as? [Float],
                  let right = userInfo["right"] as? [Float] else { return }

            leftPeakDB = AudioAnalysisDSP.peakDBFS(left)
            rightPeakDB = AudioAnalysisDSP.peakDBFS(right)
            leftRMSDB = AudioAnalysisDSP.rmsDBFS(left)
            rightRMSDB = AudioAnalysisDSP.rmsDBFS(right)
        }
    }
}

/// One channel: a label above a pair of full-height Peak/RMS vertical meters.
private struct ChannelMetersView: View {
    let name: String
    let nameColor: Color
    let peakDB: Float
    let rmsDB: Float

    var body: some View {
        VStack(spacing: 8) {
            Text(name)
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundColor(nameColor)

            HStack(spacing: 16) {
                VerticalMeterView(label: "Peak", value: peakDB)
                VerticalMeterView(label: "RMS", value: rmsDB)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// A single vertical level meter that fills the available height.
struct VerticalMeterView: View {
    let label: String
    let value: Float

    private var normalizedValue: CGFloat {
        CGFloat(max(0, min(1, (value + 120) / 120)))  // -120…0 dB → 0…1
    }

    private var meterColor: Color {
        if value > -6 { return .red }
        if value > -12 { return .yellow }
        return .green
    }

    var body: some View {
        VStack(spacing: 6) {
            GeometryReader { geo in
                ZStack(alignment: .bottom) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color(white: 0.18))
                    RoundedRectangle(cornerRadius: 3)
                        .fill(meterColor)
                        .frame(height: geo.size.height * normalizedValue)
                }
            }
            .frame(maxWidth: 44, maxHeight: .infinity)

            Text(label)
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .foregroundColor(.gray)

            Text(String(format: "%.1f", value))
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .foregroundColor(.white)
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity)
    }
}

#Preview {
    LevelsPaneView()
        .frame(width: 275, height: 220)
}
