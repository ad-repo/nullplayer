import XCTest
import CGoomCore

/// The Goom C core through its shim: frames come out lit, a forced effect lands on the next
/// update, and a second core starts after the first is gone (the font is process-wide).
final class GoomCoreSmokeTests: XCTestCase {
    func testCoreRendersAndTakesAForcedEffect() throws {
        let (width, height) = (320, 200)
        let pcm = (0..<1024).map { Int16(12000 * sin(Double($0) * 0.07)) }
        for _ in 0..<2 {
            let core = try XCTUnwrap(GoomCore_create(Int32(width), Int32(height)))
            defer { GoomCore_destroy(core) }
            var frame: UnsafePointer<UInt32>?
            for _ in 0..<60 { frame = pcm.withUnsafeBufferPointer { GoomCore_update(core, $0.baseAddress) } }
            let pixels = UnsafeBufferPointer(start: try XCTUnwrap(frame), count: width * height)
            XCTAssertGreaterThan(pixels.filter { $0 & 0xFF_FFFF != 0 }.count, width * height / 10)

            // An upstream effect and one of the port's own (the last).
            for (index, name) in [(5, "Water"), (Int(GOOM_CORE_EFFECT_COUNT) - 1, "Pentagram")] {
                GoomCore_forceEffect(core, Int32(index))
                _ = pcm.withUnsafeBufferPointer { GoomCore_update(core, $0.baseAddress) }
                XCTAssertEqual(Int(GoomCore_currentEffect(core)), index)
                XCTAssertEqual(String(cString: GoomCore_effectName(Int32(index))), name)
            }
        }
    }

    /// Held, Goom keeps the chosen effect through beats that would otherwise change it.
    func testHeldEffectSurvivesGoomsOwnChanges() throws {
        let core = try XCTUnwrap(GoomCore_create(160, 120))
        defer { GoomCore_destroy(core) }
        GoomCore_forceEffect(core, 2)
        GoomCore_setHold(core, 1)
        for n in 0..<1500 {
            // Loud bursts every 15 cycles: the sound events Goom picks a new effect on.
            let loud = n % 15 < 2
            let pcm = (0..<1024).map { Int16((loud ? 30000 : 3000) * sin(Double($0) * 0.3 + Double(n))) }
            _ = pcm.withUnsafeBufferPointer { GoomCore_update(core, $0.baseAddress) }
            XCTAssertEqual(GoomCore_currentEffect(core), 2, "cycle \(n)")
            if GoomCore_currentEffect(core) != 2 { break }
        }
    }
}
