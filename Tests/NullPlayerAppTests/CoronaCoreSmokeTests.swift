import XCTest
import CCoronaCore

/// The Corona C core through its shim: loud frames come out lit, a held palette is the one drawn,
/// and every palette has a name.
final class CoronaCoreSmokeTests: XCTestCase {
    private let (width, height) = (160, 120)

    func testLoudSpectrumLightsTheFrame() throws {
        let core = try XCTUnwrap(CoronaCore_create(Int32(width), Int32(height)))
        defer { CoronaCore_destroy(core) }
        CoronaCore_setBlaze(core, 1)
        let pixels = try run(core, frames: 200)
        XCTAssertGreaterThan(Set(pixels).count, 8, "Corona drew a flat frame")
    }

    /// "White" fades black to white, so a frame held on it is grey throughout; any other palette
    /// fading in would tint it.
    func testHeldPaletteIsTheOneDrawn() throws {
        let core = try XCTUnwrap(CoronaCore_create(Int32(width), Int32(height)))
        defer { CoronaCore_destroy(core) }
        let white = try XCTUnwrap((0..<Int(CORONA_CORE_PALETTE_COUNT)).first {
            String(cString: CoronaCore_paletteName(Int32($0))) == "White"
        })
        CoronaCore_setPalette(core, Int32(white), 0)
        let tinted = try run(core, frames: 600).filter { pixel in
            let (r, g, b) = (pixel & 0xFF, pixel >> 8 & 0xFF, pixel >> 16 & 0xFF)
            return r != g || g != b
        }
        XCTAssertEqual(tinted.count, 0, "the held palette drifted")
    }

    func testEveryPaletteIsNamed() {
        for index in 0..<Int(CORONA_CORE_PALETTE_COUNT) {
            XCTAssertFalse(String(cString: CoronaCore_paletteName(Int32(index))).isEmpty, "palette \(index)")
        }
        XCTAssertEqual(String(cString: CoronaCore_paletteName(CORONA_CORE_PALETTE_COUNT)), "")
    }

    /// Runs `frames` updates of a loud spectrum with a burst every 50 (Corona's beats need 750 ms
    /// apart, so 20 ms a frame) and returns the last frame.
    private func run(_ core: OpaquePointer, frames: Int) throws -> [UInt32] {
        var frame: UnsafePointer<UInt32>?
        for i in 0..<frames {
            let level: UInt8 = i % 50 < 3 ? 250 : 40
            let spectrum = [UInt8](repeating: level, count: 512)
            frame = spectrum.withUnsafeBufferPointer { CoronaCore_update(core, $0.baseAddress, 20) }
        }
        return Array(UnsafeBufferPointer(start: try XCTUnwrap(frame), count: width * height))
    }
}
