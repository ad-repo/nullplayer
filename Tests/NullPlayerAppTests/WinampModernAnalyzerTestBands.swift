import CoreGraphics
import Foundation

/// What a test's stub `WinampModernHost` answers `analyzerBands(count:)` with.
///
/// Before B73 both analyzer sites read `host.spectrumLevels` and collapsed it into the band count
/// they wanted by taking the loudest bin in each bucket. The bands now come from the host instead
/// (`WinampModernAnalyzerTap`, an FFT over the full-stereo PCM tap), and a stub host has no tap —
/// so it does that bucketing itself. Every analyzer test that predates B73 keeps setting
/// `spectrumLevels` and keeps measuring exactly what it always measured.
///
/// The tap's own calibration — the log spacing, the dB window, the frequency weighting — is *not*
/// modelled here. It has no business in a test about colours or band counts, and it is pinned
/// directly in `WinampModernB73Tests`.
func analyzerTestBands(from levels: [Float], count: Int) -> [CGFloat] {
    guard count > 0, !levels.isEmpty else { return [] }
    return (0..<count).map { index in
        let start = index * levels.count / count
        let end = min(levels.count, max(start + 1, (index + 1) * levels.count / count))
        return CGFloat(levels[start..<end].max() ?? 0)
    }
}
