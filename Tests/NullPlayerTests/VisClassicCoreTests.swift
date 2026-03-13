import XCTest
import CVisClassicCore

final class VisClassicCoreTests: XCTestCase {
    func testRenderDeterministicForFixedWaveform() {
        let width = 96
        let height = 48

        let frameA = renderFrame(width: width, height: height)
        let frameB = renderFrame(width: width, height: height)

        XCTAssertEqual(frameA, frameB)
        XCTAssertNotEqual(fnv1a64(frameA), 0)
    }

    func testSetGetOptionClamp() {
        guard let core = vc_create(64, 32) else {
            XCTFail("vc_create failed")
            return
        }
        defer { vc_destroy(core) }

        XCTAssertEqual(vc_set_option(core, "Falloff", 999), 1)

        var value: Int32 = 0
        XCTAssertEqual(vc_get_option(core, "Falloff", &value), 1)
        XCTAssertEqual(value, 255)
    }

    func testProfileLoadSaveRoundTrip() throws {
        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("vis_classic_tests_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)

        let source = tmpDir.appendingPathComponent("source.ini")
        let exported = tmpDir.appendingPathComponent("exported.ini")

        let ini = """
        [Classic Analyzer]
        Falloff=220
        PeakChange=7
        Bar Width=5
        X-Spacing=2
        Mono=1
        FFTScale=130

        [BarColours]
        0=0 32 255
        255=255 255 255

        [PeakColours]
        0=10 20 30
        255=250 240 230
        """
        try ini.write(to: source, atomically: true, encoding: .utf8)

        guard let coreA = vc_create(80, 40), let coreB = vc_create(80, 40) else {
            XCTFail("vc_create failed")
            return
        }
        defer {
            vc_destroy(coreA)
            vc_destroy(coreB)
        }

        XCTAssertEqual(source.path.withCString { vc_load_profile_ini(coreA, $0) }, 1)
        XCTAssertEqual(exported.path.withCString { vc_save_profile_ini(coreA, $0) }, 1)
        XCTAssertEqual(exported.path.withCString { vc_load_profile_ini(coreB, $0) }, 1)

        var aFalloff: Int32 = 0
        var bFalloff: Int32 = 0
        var aMono: Int32 = 0
        var bMono: Int32 = 0
        var aScale: Int32 = 0
        var bScale: Int32 = 0

        XCTAssertEqual(vc_get_option(coreA, "Falloff", &aFalloff), 1)
        XCTAssertEqual(vc_get_option(coreB, "Falloff", &bFalloff), 1)
        XCTAssertEqual(vc_get_option(coreA, "Mono", &aMono), 1)
        XCTAssertEqual(vc_get_option(coreB, "Mono", &bMono), 1)
        XCTAssertEqual(vc_get_option(coreA, "FFTScale", &aScale), 1)
        XCTAssertEqual(vc_get_option(coreB, "FFTScale", &bScale), 1)

        XCTAssertEqual(aFalloff, bFalloff)
        XCTAssertEqual(aMono, bMono)
        XCTAssertEqual(aScale, bScale)
    }

    private func renderFrame(width: Int, height: Int) -> [UInt8] {
        guard let core = vc_create(Int32(width), Int32(height)) else {
            return []
        }
        defer { vc_destroy(core) }

        var left = [UInt8](repeating: 0, count: 576)
        var right = [UInt8](repeating: 0, count: 576)
        for i in 0..<576 {
            left[i] = UInt8((i * 17) & 0xFF)
            right[i] = UInt8((255 - ((i * 13) & 0xFF)) & 0xFF)
        }

        left.withUnsafeBufferPointer { l in
            right.withUnsafeBufferPointer { r in
                vc_set_waveform_u8(core, l.baseAddress, r.baseAddress, 576, 44_100)
            }
        }

        var frame = [UInt8](repeating: 0, count: width * height * 4)
        frame.withUnsafeMutableBufferPointer { out in
            vc_render_rgba(core, out.baseAddress, Int32(width), Int32(height), width * 4)
        }
        return frame
    }

    private func fnv1a64(_ bytes: [UInt8]) -> UInt64 {
        var hash: UInt64 = 0xcbf29ce484222325
        for b in bytes {
            hash ^= UInt64(b)
            hash = hash &* 0x100000001b3
        }
        return hash
    }
}
