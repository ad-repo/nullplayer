import XCTest
@testable import NullPlayer

final class FractalScalerTests: XCTestCase {
    func testScalerFollowsGPUTimeAndAFixedSettingWins() {
        var auto = FractalScaler(setting: 0, viewportWidth: 1280)
        XCTAssertEqual(auto.scale, 1)
        var now = 0.0
        // 16.7 ms frames: heavy passes shrink it to the floor, quantised to 5%.
        for _ in 0..<600 { now += 0.0167; _ = auto.update(gpuMs: 15, frameMs: 16.7, now: now) }
        XCTAssertEqual(auto.scale, FractalScaler.range.lowerBound, accuracy: 0.001)
        // Light passes grow it back.
        for _ in 0..<600 { now += 0.0167; _ = auto.update(gpuMs: 2, frameMs: 16.7, now: now) }
        XCTAssertEqual(auto.scale, 1, accuracy: 0.001)
        XCTAssertEqual((auto.scale * 20).rounded(), auto.scale * 20, accuracy: 1e-9)

        var fixed = FractalScaler(setting: 0.75, viewportWidth: 3840)
        XCTAssertEqual(fixed.update(gpuMs: 40, frameMs: 16.7, now: 1), 0.75)
        // Auto starts near 1280 px across on a wide viewport.
        XCTAssertEqual(FractalScaler(setting: 0, viewportWidth: 3840).scale, 1280.0 / 3840, accuracy: 0.03)
    }
}
