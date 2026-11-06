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

    /// Held, Goom keeps the chosen effect through the beats that, unheld, make it change.
    func testHeldEffectSurvivesGoomsOwnChanges() throws {
        XCTAssertGreaterThan(try effectChanges(holding: false), 0, "the input never made Goom change effect")
        XCTAssertEqual(try effectChanges(holding: true), 0)
    }

    /// How often the effect changes over 1,500 cycles with loud bursts every 15, starting forced
    /// to Crystal Ball.
    private func effectChanges(holding: Bool) throws -> Int {
        let core = try XCTUnwrap(GoomCore_create(160, 120))
        defer { GoomCore_destroy(core) }
        GoomCore_forceEffect(core, 2)
        GoomCore_setHold(core, holding ? 1 : 0)
        var changes = 0
        var previous: Int32?
        for n in 0..<1500 {
            let loud = n % 15 < 2
            let pcm = (0..<1024).map { Int16((loud ? 30000 : 3000) * sin(Double($0) * 0.3 + Double(n))) }
            _ = pcm.withUnsafeBufferPointer { GoomCore_update(core, $0.baseAddress) }
            let effect = GoomCore_currentEffect(core)
            if let previous, previous != effect { changes += 1 }
            previous = effect
        }
        return changes
    }
}
