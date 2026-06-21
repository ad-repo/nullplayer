import SwiftUI
import NullPlayerCore

/// Pitch Tracker pane — displays fundamental frequency, nearest note, and cents deviation.
struct PitchPaneView: View {
    @State private var frequencyHz: Double? = nil
    @State private var noteString: String = "—"
    @State private var centsDeviation: Double = 0
    @State private var sampleRate: Double = 44100

    private var centsColor: Color {
        abs(centsDeviation) < 5 ? .green : abs(centsDeviation) < 20 ? .yellow : .red
    }

    var body: some View {
        // Compact, fit-in-place layout — the Audio Analysis content area is short
        // (~88pt tall at the default window size). Centered so it scales up cleanly
        // when the window is resized taller.
        VStack(spacing: 6) {
            Spacer(minLength: 0)

            // Primary readouts: note + frequency side by side
            HStack(alignment: .top, spacing: 24) {
                readout(caption: "NOTE", value: noteString, color: .cyan)
                readout(
                    caption: "FREQ (Hz)",
                    value: frequencyHz.map { String(format: "%.1f", $0) } ?? "—",
                    color: .white
                )
            }
            .padding(.horizontal, 12)

            // Cents deviation bar
            VStack(spacing: 2) {
                Text(String(format: "%+.0f¢", centsDeviation))
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundColor(centsColor)

                GeometryReader { geo in
                    let normalized = min(1.0, max(-1.0, centsDeviation / 50.0))
                    ZStack {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color(white: 0.12))
                        Rectangle()
                            .fill(Color(white: 0.35))
                            .frame(width: 1)
                        Rectangle()
                            .fill(centsColor)
                            .frame(width: 2)
                            .position(
                                x: geo.size.width / 2 + normalized * geo.size.width / 2.2,
                                y: geo.size.height / 2
                            )
                    }
                }
                .frame(height: 10)
                .padding(.horizontal, 24)
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
        .onReceive(NotificationCenter.default.publisher(for: .audioPCMDataUpdated).receive(on: DispatchQueue.main)) { notification in
            guard let userInfo = notification.userInfo,
                  let pcm = userInfo["pcm"] as? [Float],
                  let sr = userInfo["sampleRate"] as? Double else { return }

            sampleRate = sr

            // Estimate pitch from mono PCM
            let hz = AudioAnalysisDSP.estimatePitchHz(samples: pcm, sampleRate: sr, minHz: 50, maxHz: 2000)

            if let hz = hz {
                frequencyHz = hz
                let (note, octave, cents) = hzToNote(hz)
                noteString = "\(note)\(octave)"
                centsDeviation = cents
            } else {
                frequencyHz = nil
                noteString = "—"
                centsDeviation = 0
            }
        }
    }

    /// A captioned numeric readout that shrinks to fit rather than clipping.
    private func readout(caption: String, value: String, color: Color) -> some View {
        VStack(spacing: 2) {
            Text(caption)
                .font(.system(size: 8, weight: .semibold, design: .monospaced))
                .foregroundColor(.gray)
            Text(value)
                .font(.system(size: 28, weight: .semibold, design: .monospaced))
                .foregroundColor(color)
                .lineLimit(1)
                .minimumScaleFactor(0.4)
        }
        .frame(maxWidth: .infinity)
    }
}

/// Convert frequency in Hz to note name, octave, and cents deviation from equal temperament.
/// A4 = 440 Hz
private func hzToNote(_ hz: Double) -> (note: String, octave: Int, cents: Double) {
    let noteNames = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]

    // Semitones from A4 (440 Hz): n = 12 * log2(hz / 440)
    let semitonesFromA4 = 12.0 * log2(hz / 440.0)

    // Round to nearest semitone
    let semitoneRounded = round(semitonesFromA4)
    let cents = (semitonesFromA4 - semitoneRounded) * 100.0

    // MIDI note number (A4 = 69). Map to a note name (C=0) and octave via
    // floored arithmetic so frequencies below 440 Hz (negative semitone offsets)
    // never produce a negative array index.
    let midi = 69 + Int(semitoneRounded)
    let noteIndex = ((midi % 12) + 12) % 12        // always 0...11
    let octave = Int(floor(Double(midi) / 12.0)) - 1

    let note = noteNames[noteIndex]

    return (note, octave, cents)
}
