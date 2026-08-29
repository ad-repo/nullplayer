import XCTest
@testable import NullPlayer

/// B73 — the `.wal` analyzers run their own FFT, off the full-stereo PCM tap.
///
/// **The defect this closes.** Both analyzer sites drew from `host.spectrumLevels`, which is a
/// *display* array rather than an analysis result: `AudioEngine` has already taken `20·log10` of the
/// bins, normalised, clamped and smoothed them before any skin sees them. Measured live with
/// `WINAMP_MODERN_VIS_TRACE=1`, that came out as **52 of 75 bands at exactly 1.0** on a loud frame,
/// mean 0.98 — one fact behind three symptoms: no dynamic range, flat bass, and B54's white line
/// across the bar tops, because a peak-hold over clipped data can only draw a flat line when every
/// band's cap latches to the identical 1.0. It also made every `.wal` skin's analyzer depend on
/// `spectrumNormalizationMode`, a preference owned by a different window's context menu.
///
/// What is pinned here is the part that has no audio engine in it: `WinampModernAnalyzerTap.bands`,
/// which is the whole calibration (log spacing, frequency weighting, dB window), the tap's silence
/// contract, and the cap-gap rule both analyzer sites now draw their peak caps by.
///
/// Measured after the fix, same probe, same skin, playing: `pinned@1.0` between 2 and 6 of 19 bands
/// at `wide` on loud passages — momentary peaks touching the ceiling rather than a row parked
/// against it.
final class WinampModernB73Tests: XCTestCase {

    // MARK: - The calibration

    private static let rate: Double = 44_100

    /// A half-spectrum with a single bin set, at the bin nearest `hz`.
    private func spectrum(tone hz: Float, magnitude: Float,
                          rate: Double = WinampModernB73Tests.rate) -> [Float] {
        let size = WinampModernAnalyzerTap.fftSize
        var bins = [Float](repeating: 0, count: size / 2)
        let binWidth = Float(rate) / Float(size)
        bins[min(bins.count - 1, max(1, Int((hz / binWidth).rounded())))] = magnitude
        return bins
    }

    func testSilenceMapsToTheFloor() {
        let bands = WinampModernAnalyzerTap.bands(
            count: 19, spectrum: [Float](repeating: 0, count: WinampModernAnalyzerTap.fftSize / 2),
            sampleRate: Self.rate)
        XCTAssertEqual(bands.count, 19)
        XCTAssertTrue(bands.allSatisfy { $0 == 0 }, "silence must draw no bar at all: \(bands)")
    }

    /// The point of the reference level. A single FFT band of a full-scale mix sits some 30 dB below
    /// full scale, so mapping against 0 dBFS put the top of the box out of reach — measured at 0.52
    /// to 0.64 on loud music, which is a row that never fills its box.
    func testABandAtTheReferenceLevelFillsTheBox() {
        let magnitude = powf(10, WinampModernAnalyzerTap.fullScaleBandDB / 20)
        let bands = WinampModernAnalyzerTap.bands(
            count: 19, spectrum: spectrum(tone: WinampModernAnalyzerTap.weightingReferenceHz,
                                         magnitude: magnitude),
            sampleRate: Self.rate)
        XCTAssertEqual(bands.max() ?? 0, 1, accuracy: 0.02,
                       "a band at the reference level must reach the top of the box")
    }

    /// A band `windowDB` below the reference reaches the floor, and nothing goes below it: the
    /// window is what gives ordinary music somewhere to move, against the host tap's 20 dB clamp.
    func testTheWindowBottomsOutAtTheFloor() {
        let floorDB = WinampModernAnalyzerTap.fullScaleBandDB - WinampModernAnalyzerTap.windowDB
        let bands = WinampModernAnalyzerTap.bands(
            count: 19,
            spectrum: spectrum(tone: WinampModernAnalyzerTap.weightingReferenceHz,
                               magnitude: powf(10, floorDB / 20)),
            sampleRate: Self.rate)
        XCTAssertEqual(bands.max() ?? 1, 0, accuracy: 0.02)

        let halfway = WinampModernAnalyzerTap.fullScaleBandDB - WinampModernAnalyzerTap.windowDB / 2
        let mid = WinampModernAnalyzerTap.bands(
            count: 19,
            spectrum: spectrum(tone: WinampModernAnalyzerTap.weightingReferenceHz,
                               magnitude: powf(10, halfway / 20)),
            sampleRate: Self.rate)
        XCTAssertEqual(mid.max() ?? 0, 0.5, accuracy: 0.02, "the window must be linear in dB")
    }

    /// Log spacing, which is what makes it a spectrum analyzer: linear bins put eight of every ten
    /// bars above 5 kHz and squeeze the whole audible bass range into the first one.
    func testBandsAreLogSpacedAcrossTheAudibleRange() {
        let count = 19
        let magnitude = powf(10, WinampModernAnalyzerTap.fullScaleBandDB / 20)
        func loudestBand(at hz: Float) -> Int {
            let bands = WinampModernAnalyzerTap.bands(
                count: count, spectrum: spectrum(tone: hz, magnitude: magnitude),
                sampleRate: Self.rate)
            return bands.firstIndex(of: bands.max() ?? 0) ?? -1
        }
        let low = loudestBand(at: 60)
        let mid = loudestBand(at: 1_000)
        let high = loudestBand(at: 10_000)
        XCTAssertLessThan(low, mid)
        XCTAssertLessThan(mid, high)
        // Log spacing puts 1 kHz — five and a half octaves up a ten-octave range — past the middle
        // of the row, where linear spacing would leave it in the first tenth of it.
        XCTAssertGreaterThan(mid, count / 3)
        XCTAssertLessThan(high, count)
    }

    /// The frequency weighting the host tap's `.accurate` path never applied. Music is roughly pink,
    /// so an unweighted analyzer is a wall of bass with nothing to the right of it.
    func testHighFrequenciesAreWeightedUpAgainstLowOnesOfEqualMagnitude() {
        let magnitude = powf(10, (WinampModernAnalyzerTap.fullScaleBandDB - 20) / 20)
        func level(at hz: Float) -> CGFloat {
            WinampModernAnalyzerTap.bands(count: 19,
                                          spectrum: spectrum(tone: hz, magnitude: magnitude),
                                          sampleRate: Self.rate).max() ?? 0
        }
        let bass = level(at: 60)
        let treble = level(at: 8_000)
        XCTAssertGreaterThan(treble, bass,
                             "equal magnitudes must not draw equal bars: the tilt is the weighting")
        // One octave is `weightingDBPerOctave`, and 60 Hz to 8 kHz is a little over seven of them.
        let octaves = log2f(8_000 / 60)
        let expected = CGFloat(WinampModernAnalyzerTap.weightingDBPerOctave * octaves
                               / WinampModernAnalyzerTap.windowDB)
        XCTAssertEqual(treble - bass, expected, accuracy: 0.06)
    }

    /// The band count is the caller's, and the analysis is log-spaced for whatever it is given —
    /// there is no bucket-collapsing left in the renderers and no ceiling from another consumer's
    /// resolution. `bandwidth="thin"` asks for 75; a wide `{0000000A}` pane asks for more.
    func testAnyBandCountIsAnsweredExactly() {
        let magnitude = powf(10, WinampModernAnalyzerTap.fullScaleBandDB / 20)
        let bins = spectrum(tone: 1_000, magnitude: magnitude)
        for count in [1, 19, 75, 89, 256] {
            XCTAssertEqual(
                WinampModernAnalyzerTap.bands(count: count, spectrum: bins,
                                              sampleRate: Self.rate).count,
                count)
        }
        XCTAssertTrue(WinampModernAnalyzerTap.bands(count: 0, spectrum: bins,
                                                    sampleRate: Self.rate).isEmpty)
    }

    /// A lower sample rate narrows the range to its own Nyquist rather than reading past it.
    func testTheTopOfTheRangeFollowsNyquist() {
        let magnitude = powf(10, WinampModernAnalyzerTap.fullScaleBandDB / 20)
        let bands = WinampModernAnalyzerTap.bands(
            count: 19, spectrum: spectrum(tone: 3_000, magnitude: magnitude, rate: 8_000),
            sampleRate: 8_000)
        XCTAssertEqual(bands.count, 19)
        // 3 kHz is near the top of a 4 kHz Nyquist, so it must land in the last few bands rather
        // than a fifth of the way along a row still scaled for 20 kHz.
        XCTAssertGreaterThan(bands.firstIndex(of: bands.max() ?? 0) ?? 0, 14)
    }

    // MARK: - The tap's silence contract

    /// Before any audio has arrived the tap answers **no** bands, which is what tells the analyzer
    /// not to draw. A host with no tap at all (the render harness, a test double) answers the same.
    func testNoBandsBeforeTheFirstBuffer() {
        let tap = WinampModernAnalyzerTap(consumerId: "test.b73.cold")
        XCTAssertTrue(tap.bands(count: 19, at: 1_000).isEmpty)
    }

    /// Past `silenceTimeout` the read decays to all-zero rather than holding the last spectrum, so
    /// the bars fall to the floor instead of freezing where the music left them. The tap simply
    /// stops being posted to on pause, stop, end of track or a move to a cast device.
    func testSilenceDecaysToZeroRatherThanHoldingTheLastFrame() {
        let tap = WinampModernAnalyzerTap(consumerId: "test.b73.silence")
        let samples = [Float](repeating: 0.5, count: WinampModernAnalyzerTap.fftSize)
        tap.receive(left: samples, right: samples, sampleRate: Self.rate, at: 1_000)

        let quiet = tap.bands(count: 19, at: 1_000 + WinampModernAnalyzerTap.silenceTimeout + 1)
        XCTAssertEqual(quiet.count, 19)
        XCTAssertTrue(quiet.allSatisfy { $0 == 0 }, "a stopped tap must read silence: \(quiet)")
    }

    // MARK: - The cap gap (B54's remaining half)

    /// **A cap draws only once it has cleared its bar by a visible gap**, not merely once
    /// `peaks > bar`. That test is true the instant a bar falls by a fraction of a pixel, and the
    /// cap it paints then shares an edge with the bar — which is not a floating cap, it is a
    /// brighter fringe along the top of the row. At `thin`'s 75 bands in a 144px box the fringe is
    /// continuous, which is what was still being reported after the parked-cap cause was fixed.
    func testACapTouchingItsBarIsNotDrawn() {
        let capHeight: CGFloat = 2
        // Bar top at y=50, cap sitting directly on it: no gap at all.
        XCTAssertFalse(WasabiBuiltInVisRenderer.capClears(barTop: 50, capY: 48,
                                                          capHeight: capHeight))
        // Half a pixel of gap still reads as a fringe.
        XCTAssertFalse(WasabiBuiltInVisRenderer.capClears(barTop: 50, capY: 47.5,
                                                          capHeight: capHeight))
        // A full pixel of clear space is a cap.
        XCTAssertTrue(WasabiBuiltInVisRenderer.capClears(barTop: 50, capY: 47,
                                                         capHeight: capHeight))
        XCTAssertTrue(WasabiBuiltInVisRenderer.capClears(barTop: 50, capY: 30,
                                                         capHeight: capHeight))
    }

    /// A cap *below* its bar top — which is what a rising bar overtaking its own cap looks like for
    /// a frame — is never drawn either.
    func testACapInsideItsBarIsNotDrawn() {
        XCTAssertFalse(WasabiBuiltInVisRenderer.capClears(barTop: 50, capY: 60, capHeight: 2))
    }
}
