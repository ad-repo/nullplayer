import XCTest
import CSmearCore

/// The Smear C core through its shim: every bundled script compiles, every move can be held, and
/// a loud signal lights the frame.
final class SmearCoreSmokeTests: XCTestCase {
    private static let scripts = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Sources/NullPlayer/Resources/Smear")

    private func makeCore() throws -> OpaquePointer {
        try XCTUnwrap(Self.scripts.withUnsafeFileSystemRepresentation { SmearCore_create($0) })
    }

    private func files(_ folder: String, _ ext: String) throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: Self.scripts.appendingPathComponent(folder).path)
            .filter { $0.lowercased().hasSuffix(ext) }
    }

    /// A script that fails to compile is skipped silently, as upstream did; here it is a failure.
    func testEveryBundledScriptCompiles() throws {
        let core = try makeCore()
        defer { SmearCore_destroy(core) }
        for (kind, folder, ext) in [(0, "Moves", ".sms"), (1, "Color", ".scs"),
                                    (2, "Waveform", ".sws"), (3, "Particle", ".sps")] {
            let count = try files(folder, ext).count
            XCTAssertGreaterThan(count, 0, folder)
            XCTAssertEqual(Int(SmearCore_scriptCount(core, Int32(kind))), count, folder)
        }
    }

    func testEveryMoveCanBeHeld() throws {
        let core = try makeCore()
        defer { SmearCore_destroy(core) }
        for move in try files("Moves", ".sms") {
            XCTAssertEqual(SmearCore_holdMove(core, move), 1, move)
        }
        XCTAssertEqual(SmearCore_holdMove(core, "missing.sms"), 0)
    }

    func testLoudSignalLightsTheFrame() throws {
        let core = try makeCore()
        defer { SmearCore_destroy(core) }
        let (width, height) = (160, 120)
        let spectrum = [UInt8](repeating: 200, count: Int(SMEAR_CORE_SPECTRUM_SIZE))
        var frame: UnsafePointer<UInt8>?
        for f in 0..<30 {
            let waveform = (0..<Int(SMEAR_CORE_WAVEFORM_SIZE)).map { Int8(100 * sin(Double($0 + f) * 0.05)) }
            frame = waveform.withUnsafeBufferPointer { wave in
                spectrum.withUnsafeBufferPointer { SmearCore_render(core, Int32(width), Int32(height), wave.baseAddress, $0.baseAddress) }
            }
        }
        let rgba = UnsafeBufferPointer(start: try XCTUnwrap(frame), count: width * height * 4)
        let colours = Set(stride(from: 0, to: rgba.count, by: 4).map { Int(rgba[$0]) << 16 | Int(rgba[$0 + 1]) << 8 | Int(rgba[$0 + 2]) })
        XCTAssertGreaterThan(colours.count, 8, "Smear drew a flat frame")
    }
}
