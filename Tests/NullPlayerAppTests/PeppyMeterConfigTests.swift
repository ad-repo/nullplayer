import XCTest
@testable import NullPlayer

final class PeppyMeterConfigTests: XCTestCase {

    // A trimmed but representative meters.txt covering a linear stereo meter (with overload zone),
    // a circular mono meter, and a circular stereo meter with per-channel angles.
    private let sample = """
    [bar]
    meter.type = linear
    channels = 2
    ui.refresh.period = 0.033
    bgr.filename = bar-bgr.png
    indicator.filename = bar-indicator.png
    left.x = 130
    left.y = 113
    right.x = 130
    right.y = 178
    position.regular = 11
    position.overload = 3
    step.width.regular = 19
    step.width.overload = 25
    meter.x = 0
    meter.y = 0
    screen.bgr =

    [blue]
    meter.type = circular
    channels = 1
    bgr.filename = blue-bgr.png
    fgr.filename = blue-fgr.png
    indicator.filename = blue-needle.png
    steps.per.degree = 2
    start.angle = 45
    stop.angle = -45
    distance = 184
    mono.origin.x = 238
    mono.origin.y = 382

    [big-bang]
    meter.type = circular
    channels = 2
    bgr.filename = big-bang-bgr.png
    fgr.filename =
    indicator.filename = big-bang-needle.png
    left.start.angle = 135
    left.stop.angle = 44
    right.start.angle = -136
    right.stop.angle = -45
    distance = 89
    left.origin.x = 242
    left.origin.y = 162
    right.origin.x = 236
    right.origin.y = 162

    [chillout]
    meter.type = linear
    channels = 2
    indicator.type = single
    direction = left-right
    bgr.filename = chillout-bgr.jpg
    indicator.filename = chillout-indicator.png
    left.x = 28
    left.y = 240
    right.x = 28
    right.y = 258
    position.regular = 201
    step.width.regular = 2
    """

    // MARK: Parsing

    func testParsesAllSections() {
        let meters = PeppyMeterConfig.parse(sample)
        XCTAssertEqual(meters.map { $0.name }, ["bar", "blue", "big-bang", "chillout"])
    }

    func testLinearStereoMeter() {
        let bar = PeppyMeterConfig.parse(sample).first { $0.name == "bar" }
        let t = try? XCTUnwrap(bar)
        guard let t else { return }
        XCTAssertEqual(t.type, .linear)
        XCTAssertEqual(t.channels, 2)
        XCTAssertNil(t.fgrFilename)
        XCTAssertEqual(t.leftPos, CGPoint(x: 130, y: 113))
        XCTAssertEqual(t.positionRegular, 11)
        XCTAssertEqual(t.positionOverload, 3)
        XCTAssertEqual(t.stepWidthRegular, 19)
        XCTAssertEqual(t.stepWidthOverload, 25)
    }

    func testCircularMonoMeterUsesSharedAngles() {
        let blue = PeppyMeterConfig.parse(sample).first { $0.name == "blue" }
        let t = try? XCTUnwrap(blue)
        guard let t else { return }
        XCTAssertEqual(t.type, .circular)
        XCTAssertEqual(t.channels, 1)
        XCTAssertEqual(t.fgrFilename, "blue-fgr.png")
        XCTAssertEqual(t.distance, 184)
        XCTAssertEqual(t.monoOrigin, CGPoint(x: 238, y: 382))
        // Mono needle is driven by the left angle fields, seeded from start/stop.
        XCTAssertEqual(t.leftStartAngle, 45)
        XCTAssertEqual(t.leftStopAngle, -45)
    }

    func testCircularPerChannelAngles() {
        let bb = PeppyMeterConfig.parse(sample).first { $0.name == "big-bang" }
        let t = try? XCTUnwrap(bb)
        guard let t else { return }
        XCTAssertNil(t.fgrFilename)  // empty fgr.filename → nil
        XCTAssertEqual(t.leftStartAngle, 135)
        XCTAssertEqual(t.leftStopAngle, 44)
        XCTAssertEqual(t.rightStartAngle, -136)
        XCTAssertEqual(t.rightStopAngle, -45)
    }

    func testSingleIndicatorFlag() {
        let chillout = PeppyMeterConfig.parse(sample).first { $0.name == "chillout" }
        let t = try? XCTUnwrap(chillout)
        guard let t else { return }
        XCTAssertTrue(t.indicatorSingle)
        XCTAssertEqual(t.direction, .leftRight)
    }

    // MARK: Linear mask table (ported from MaskFactory)

    func testLinearMaskTable() {
        let bar = PeppyMeterConfig.parse(sample).first { $0.name == "bar" }!
        let masks = bar.linearMasks
        // 1 (zero) + 11 regular + 3 overload = 15 entries.
        XCTAssertEqual(masks.count, 15)
        XCTAssertEqual(masks.first, 0)
        XCTAssertEqual(masks[11], 11 * 19)                 // end of regular zone
        XCTAssertEqual(masks.last, 11 * 19 + 3 * 25)       // + overload zone
    }

    // MARK: Resolution selection

    func testResolutionSelectionPrefersFullscreenAspectMatch() {
        let available = ["1280x400", "800x480", "480x320"]
        let preferred = PeppyMeterLibrary.preferredResolutionFolders(
            for: CGSize(width: 1920, height: 1080),
            available: available
        )

        XCTAssertEqual(preferred.first, "800x480")
    }

    func testResolutionSelectionUsesWidestSetForWideTargets() {
        let available = ["1280x400", "800x480", "480x320"]
        let preferred = PeppyMeterLibrary.preferredResolutionFolders(
            for: CGSize(width: 2560, height: 800),
            available: available
        )

        XCTAssertEqual(preferred.first, "1280x400")
    }

    // MARK: dBFS → volume mapping

    func testVolumeMappingClampsToFloor() {
        XCTAssertEqual(PeppyMeterLevels.volume(fromDBFS: -120, floor: -42), 0, accuracy: 0.001)
        XCTAssertEqual(PeppyMeterLevels.volume(fromDBFS: -42, floor: -42), 0, accuracy: 0.001)
    }

    func testVolumeMappingFullScale() {
        XCTAssertEqual(PeppyMeterLevels.volume(fromDBFS: 0, floor: -42), 100, accuracy: 0.001)
    }

    func testVolumeMappingMidpoint() {
        XCTAssertEqual(PeppyMeterLevels.volume(fromDBFS: -21, floor: -42), 50, accuracy: 0.001)
    }
}
