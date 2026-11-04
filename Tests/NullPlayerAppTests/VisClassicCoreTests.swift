import CVisClassicCore
import XCTest
@testable import NullPlayer

/// Numeric checks of the vis_classic C core against the original plugin's behaviour (#682 and the
/// effect/peak/background port). Time is pinned with `vc_set_fixed_dt_ms`, so every run is the same.
final class VisClassicCoreTests: XCTestCase {
    private var core: OpaquePointer!
    private var width = 576
    private var height = 64

    override func tearDown() {
        destroyCore()
        super.tearDown()
    }

    private func destroyCore() {
        if let core { vc_destroy(core) }
        core = nil
    }

    // MARK: - Helpers

    /// A core on a bundled profile, drawing only bars and peaks (alpha 0 elsewhere).
    private func makeCore(profile: String, width: Int = 576, height: Int = 64, options: [String: Int32] = [:]) throws {
        self.width = width
        self.height = height
        core = try XCTUnwrap(vc_create(Int32(width), Int32(height)))
        let dir = try XCTUnwrap(VisClassicBridge.bundledProfilesDirectory)
        let path = dir.appendingPathComponent(profile).appendingPathExtension("ini").path
        XCTAssertEqual(vc_load_profile_ini(core, path), 1, "load \(profile)")
        // 34 ms is just over one 33.3 ms plugin frame, so every process runs exactly one tick.
        vc_set_fixed_dt_ms(core, 34)
        set("transparentbg", 1)
        set("x-spacing", 0)
        set("bar width", 1)
        for (key, value) in options { set(key, value) }
    }

    private func set(_ key: String, _ value: Int32) {
        XCTAssertEqual(vc_set_option(core, key, value), 1, key)
    }

    private func get(_ key: String) -> Int32 {
        var value: Int32 = -1
        XCTAssertEqual(vc_get_option(core, key, &value), 1, key)
        return value
    }

    private func process(_ left: [UInt8], _ right: [UInt8]? = nil, frames: Int = 1) {
        let right = right ?? left
        for _ in 0..<frames {
            left.withUnsafeBufferPointer { l in
                right.withUnsafeBufferPointer { r in
                    vc_set_waveform_u8(core, l.baseAddress, r.baseAddress, l.count, 44100)
                }
            }
            vc_process_frame_only(core)
        }
    }

    private func silence(frames: Int) { process([UInt8](repeating: 128, count: 576), frames: frames) }

    private func draw(width: Int? = nil, height: Int? = nil) -> [UInt8] {
        let w = width ?? self.width, h = height ?? self.height
        var px = [UInt8](repeating: 0, count: w * h * 4)
        px.withUnsafeMutableBufferPointer { _ = vc_draw_at_size(core, $0.baseAddress, Int32(w), Int32(h), Int32(w * 4)) }
        return px
    }

    /// Lit rows of column `x`, counted from the bottom.
    private func litRows(_ px: [UInt8], x: Int) -> [Int] {
        (0..<height).filter { row in px[((height - 1 - row) * width + x) * 4 + 3] != 0 }
    }

    private func barHeight(_ px: [UInt8], x: Int) -> Int { (litRows(px, x: x).max() ?? -1) + 1 }

    private func whiteNoise(seed: UInt32) -> [UInt8] {
        var state = seed
        return (0..<576).map { _ in
            state = state &* 1664525 &+ 1013904223
            return UInt8(truncatingIfNeeded: state >> 24)
        }
    }

    private func sine(hz: Double, amplitude: Double = 100) -> [UInt8] {
        (0..<576).map { UInt8(128 + amplitude * sin(2 * .pi * hz * Double($0) / 44100)) }
    }

    private func loudestColumn(_ px: [UInt8], in range: Range<Int>) -> Int {
        range.max { barHeight(px, x: $0) < barHeight(px, x: $1) }!
    }

    // MARK: - #682: frequency mapping

    func testWhiteNoiseLightsTheRightmostColumn() throws {
        try makeCore(profile: "Aurora Borealis", options: ["mono": 1, "fftequalize": 0])
        process(whiteNoise(seed: 1), frames: 8)
        let px = draw()
        XCTAssertGreaterThan(barHeight(px, x: width - 1), height / 2, "the last bar must get FFT bins (#682)")
    }

    func testTenKilohertzPeaksInTheRightHalfMono() throws {
        try makeCore(profile: "Aurora Borealis", options: ["mono": 1])
        process(sine(hz: 10_000), frames: 8)
        XCTAssertGreaterThan(loudestColumn(draw(), in: 0..<width), width / 2)
    }

    func testStereoHalvesEachCoverTheWholeSpectrum() throws {
        try makeCore(profile: "Aurora Borealis", options: ["mono": 0, "reverseleft": 0, "reverseright": 0])
        process(sine(hz: 10_000), frames: 8)
        let px = draw()
        let half = width / 2
        XCTAssertGreaterThan(loudestColumn(px, in: 0..<half), half / 2, "left half")
        XCTAssertGreaterThan(loudestColumn(px, in: half..<width), half + half / 2, "right half")
    }

    // MARK: - Y-Spacing

    func testYSpacingDrawsEveryNthRowAndZeroLoadsAsOne() throws {
        try makeCore(profile: "Classic", width: 76, height: 30)
        set("y-spacing", 0)
        XCTAssertEqual(get("y-spacing"), 1)

        set("y-spacing", 3)
        set("peakchange", 0)
        process(whiteNoise(seed: 2), frames: 4)
        let px = draw()
        let rows = (0..<width).flatMap { litRows(px, x: $0) }
        XCTAssertFalse(rows.isEmpty)
        XCTAssertTrue(rows.allSatisfy { $0 % 3 == 0 }, "only rows 0, 3, 6, ... are drawn")
    }

    // MARK: - Peak Effects

    /// Peak row of the tallest bar `frames` silent frames after one loud frame.
    private func peakTrace(peakEffect: Int32) throws -> (start: Int, after: Int) {
        try makeCore(profile: "Classic", width: 40, height: 256,
                     options: ["peak effect": peakEffect, "peakchange": 10, "falloff": 75, "y-spacing": 1])
        process(sine(hz: 2_000, amplitude: 15))
        let x = loudestColumn(draw(), in: 0..<width)
        let start = barHeight(draw(), x: x) - 1
        silence(frames: 13)  // the 10-frame hold, then 3 frames of movement (5 levels each)
        return (start, barHeight(draw(), x: x) - 1)
    }

    func testPeakFallMovesDownAndRiseMovesUp() throws {
        let fall = try peakTrace(peakEffect: 1)
        destroyCore()
        let rise = try peakTrace(peakEffect: 2)
        XCTAssertLessThan(fall.after, fall.start, "Fall")
        XCTAssertGreaterThan(rise.after, rise.start, "Rise")
    }

    // MARK: - Effects

    private func musicThenSilence() {
        for frame in 0..<28 {
            let amp = frame < 25 ? 90.0 : 0
            process((0..<576).map { UInt8(128 + amp * (0.6 * sin(Double($0) * 0.05 + Double(frame)) + 0.4 * sin(Double($0) * 0.4))) })
        }
    }

    func testEveryEffectDrawsPurelyAtAnySize() throws {
        for effect in Int32(0)...7 {
            try makeCore(profile: "Purple Neon", width: 152, height: 64, options: ["effect": effect, "transparentbg": 0])
            musicThenSilence()
            // A `.wal` skin draws one processed frame into several boxes: each draw must match.
            let small = draw(), large = draw(width: 300, height: 100)
            XCTAssertEqual(draw(), small, "effect \(effect) small")
            XCTAssertEqual(draw(width: 300, height: 100), large, "effect \(effect) large")
            XCTAssertTrue(small.enumerated().contains { $0.offset % 4 == 3 && $0.element != 0 }, "effect \(effect) drew nothing")
            destroyCore()
        }
    }

    func testMirrorIsSymmetric() throws {
        try makeCore(profile: "Trippy", width: 152, height: 64, options: ["y-spacing": 1])
        musicThenSilence()
        let px = draw()
        let middle = height / 2
        for y in 1..<(middle - 1) {
            let up = (height - 1 - (middle + y)) * width * 4, down = (height - 1 - (middle - y)) * width * 4
            XCTAssertEqual(px[up..<(up + width * 4)], px[down..<(down + width * 4)], "row ±\(y)")
        }
    }
}
