import XCTest
@testable import NullPlayer

final class ClassicCenterStackRepairTests: XCTestCase {

    func testNearDockedGapIsCollapsedToFlush() {
        let scale: CGFloat = 1.0
        let main = NSRect(
            x: 200,
            y: 500,
            width: Skin.mainWindowSize.width * scale,
            height: Skin.mainWindowSize.height * scale
        )
        let eqHeight = Skin.eqWindowSize.height * scale
        let eq = NSRect(
            x: main.minX + 6,
            y: main.minY - eqHeight - 22,
            width: main.width - 15,
            height: eqHeight
        )  // 22px gap from main

        let repaired = AppStateManager.repairClassicCenterStackFrames(
            mainFrame: main,
            equalizerFrame: eq,
            playlistFrame: nil,
            spectrumFrame: nil,
            scale: scale
        )

        XCTAssertTrue(repaired.repaired)
        guard let eqFrame = repaired.equalizerFrame else {
            XCTFail("Expected equalizer frame")
            return
        }
        assertEqual(eqFrame.maxY, repaired.mainFrame.minY)
        assertEqual(eqFrame.minX, repaired.mainFrame.minX)
        assertEqual(eqFrame.width, repaired.mainFrame.width)
    }

    func testGapBeyondThresholdRemainsUnchanged() {
        let scale: CGFloat = 1.0
        let main = NSRect(
            x: 200,
            y: 500,
            width: Skin.mainWindowSize.width * scale,
            height: Skin.mainWindowSize.height * scale
        )
        let eqHeight = Skin.eqWindowSize.height * scale
        let eq = NSRect(
            x: main.minX,
            y: main.minY - eqHeight - 30,
            width: main.width,
            height: eqHeight
        )  // 30px gap from main

        let repaired = AppStateManager.repairClassicCenterStackFrames(
            mainFrame: main,
            equalizerFrame: eq,
            playlistFrame: nil,
            spectrumFrame: nil,
            scale: scale
        )

        XCTAssertFalse(repaired.repaired)
        XCTAssertEqual(repaired.equalizerFrame, eq)
    }

    func testLargeLeftMisalignmentRemainsUnchanged() {
        let scale: CGFloat = 1.0
        let main = NSRect(
            x: 200,
            y: 500,
            width: Skin.mainWindowSize.width * scale,
            height: Skin.mainWindowSize.height * scale
        )
        let eqHeight = Skin.eqWindowSize.height * scale
        let eq = NSRect(
            x: main.minX + 31,
            y: main.minY - eqHeight - 10,
            width: main.width,
            height: eqHeight
        )  // 10px gap, 31px X offset

        let repaired = AppStateManager.repairClassicCenterStackFrames(
            mainFrame: main,
            equalizerFrame: eq,
            playlistFrame: nil,
            spectrumFrame: nil,
            scale: scale
        )

        XCTAssertFalse(repaired.repaired)
        XCTAssertEqual(repaired.equalizerFrame, eq)
    }

    func testScaledClassicNearDockedGapIsRepairedAtOnePointFiveX() {
        let scale: CGFloat = 1.5
        let main = NSRect(
            x: 200,
            y: 500,
            width: Skin.mainWindowSize.width * scale,
            height: Skin.mainWindowSize.height * scale
        )
        let eqHeight = Skin.eqWindowSize.height * scale
        let eq = NSRect(
            x: main.minX + 10,
            y: main.minY - eqHeight - 32,
            width: main.width - 30,
            height: eqHeight
        )  // 32px gap from main

        let repaired = AppStateManager.repairClassicCenterStackFrames(
            mainFrame: main,
            equalizerFrame: eq,
            playlistFrame: nil,
            spectrumFrame: nil,
            scale: scale
        )

        XCTAssertTrue(repaired.repaired)
        guard let eqFrame = repaired.equalizerFrame else {
            XCTFail("Expected equalizer frame")
            return
        }
        assertEqual(eqFrame.maxY, repaired.mainFrame.minY)
        assertEqual(eqFrame.minX, repaired.mainFrame.minX)
        assertEqual(eqFrame.width, repaired.mainFrame.width)
    }

    func testChainedEqPlaylistSpectrumRepairCreatesContiguousStack() {
        let scale: CGFloat = 1.0
        let main = NSRect(
            x: 160,
            y: 520,
            width: Skin.mainWindowSize.width * scale,
            height: Skin.mainWindowSize.height * scale
        )
        let eqHeight = Skin.eqWindowSize.height * scale
        let playlistHeight: CGFloat = 220
        let spectrumHeight = Skin.mainWindowSize.height * scale

        let eq = NSRect(
            x: main.minX + 8,
            y: main.minY - eqHeight - 22,
            width: main.width - 15,
            height: eqHeight
        )  // 22px gap to main
        let playlist = NSRect(
            x: main.minX + 10,
            y: eq.minY - playlistHeight,
            width: main.width - 25,
            height: playlistHeight
        )  // flush to EQ before EQ gets repaired upward
        let spectrum = NSRect(
            x: main.minX + 9,
            y: playlist.minY - spectrumHeight,
            width: main.width - 30,
            height: spectrumHeight
        )  // flush to playlist before playlist gets repaired upward

        let repaired = AppStateManager.repairClassicCenterStackFrames(
            mainFrame: main,
            equalizerFrame: eq,
            playlistFrame: playlist,
            spectrumFrame: spectrum,
            scale: scale
        )

        XCTAssertTrue(repaired.repaired)
        guard let eqFrame = repaired.equalizerFrame,
              let playlistFrame = repaired.playlistFrame,
              let spectrumFrame = repaired.spectrumFrame else {
            XCTFail("Expected all center-stack frames")
            return
        }

        assertEqual(eqFrame.maxY, repaired.mainFrame.minY)
        assertEqual(playlistFrame.maxY, eqFrame.minY)
        assertEqual(spectrumFrame.maxY, playlistFrame.minY)

        for frame in [eqFrame, playlistFrame, spectrumFrame] {
            assertEqual(frame.minX, repaired.mainFrame.minX)
            assertEqual(frame.width, repaired.mainFrame.width)
        }
    }

    private func assertEqual(_ lhs: CGFloat, _ rhs: CGFloat, accuracy: CGFloat = 0.001, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(lhs, rhs, accuracy: accuracy, file: file, line: line)
    }
}
