import SwiftUI
import NullPlayerCore

/// Levels pane — displays stereo peak and RMS meters
struct LevelsPaneView: View {
    @State private var leftPeakDB: Float = -120
    @State private var rightPeakDB: Float = -120
    @State private var leftRMSDB: Float = -120
    @State private var rightRMSDB: Float = -120

    var body: some View {
        VStack(spacing: 16) {
            Text("LEVELS")
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .padding(.top, 12)

            HStack(spacing: 24) {
                VStack(spacing: 12) {
                    Text("LEFT")
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundColor(.cyan)

                    MeterView(label: "Peak", value: leftPeakDB)
                    MeterView(label: "RMS", value: leftRMSDB)
                }
                .frame(maxWidth: .infinity)

                VStack(spacing: 12) {
                    Text("RIGHT")
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundColor(Color(red: 1, green: 0, blue: 1))

                    MeterView(label: "Peak", value: rightPeakDB)
                    MeterView(label: "RMS", value: rightRMSDB)
                }
                .frame(maxWidth: .infinity)
            }
            .padding(.horizontal, 12)

            Spacer()
        }
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

struct MeterView: View {
    let label: String
    let value: Float

    private var normalizedValue: CGFloat {
        CGFloat((value + 120) / 120)  // Map -120 to 0 dB → 0.0 to 1.0
    }

    private var meterColor: Color {
        if value > -6 { return .red }
        if value > -12 { return .yellow }
        return .green
    }

    var body: some View {
        VStack(spacing: 4) {
            HStack(spacing: 8) {
                Text(label)
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .foregroundColor(.gray)
                    .frame(width: 40, alignment: .leading)

                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color(white: 0.3))

                        RoundedRectangle(cornerRadius: 2)
                            .fill(meterColor)
                            .frame(width: geo.size.width * normalizedValue)
                    }
                }
                .frame(height: 12)

                Text(String(format: "%.1f", value))
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .foregroundColor(.white)
                    .frame(width: 50, alignment: .trailing)
            }
        }
    }
}

#Preview {
    LevelsPaneView()
}
