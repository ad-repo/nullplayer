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
            for (index, name) in [(5, "Water"), (Int(GOOM_CORE_EFFECT_COUNT) - 1, "Ooh/Ugh")] {
                GoomCore_forceEffect(core, Int32(index))
                _ = pcm.withUnsafeBufferPointer { GoomCore_update(core, $0.baseAddress) }
                XCTAssertEqual(Int(GoomCore_currentEffect(core)), index)
                XCTAssertEqual(String(cString: GoomCore_effectName(Int32(index))), name)
            }
        }
    }

    /// Ooh/Ugh paints only red, black and white: green always equals blue and never exceeds red.
    func testOohUghStaysRedBlackAndWhite() throws {
        let (width, height) = (320, 200)
        let core = try XCTUnwrap(GoomCore_create(Int32(width), Int32(height)))
        defer { GoomCore_destroy(core) }
        GoomCore_forceEffect(core, GOOM_CORE_EFFECT_COUNT - 1)
        GoomCore_setHold(core, 1)
        var frame: UnsafePointer<UInt32>?
        for n in 0..<300 {
            let loud = n % 15 < 2
            let pcm = (0..<1024).map { Int16((loud ? 30000 : 6000) * sin(Double($0) * 0.07 + Double(n))) }
            frame = pcm.withUnsafeBufferPointer { GoomCore_update(core, $0.baseAddress) }
        }
        let pixels = UnsafeBufferPointer(start: try XCTUnwrap(frame), count: width * height)
        XCTAssertGreaterThan(pixels.filter { $0 & 0xFF != 0 }.count, width * height / 20, "the frame is dark")
        let offHue = pixels.filter { let r = $0 & 0xFF, g = ($0 >> 8) & 0xFF, b = ($0 >> 16) & 0xFF; return g != b || g > r }
        XCTAssertEqual(offHue.count, 0)
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
