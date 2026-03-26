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
            waveformFrame: nil,
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
            waveformFrame: nil,
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
            waveformFrame: nil,
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
            waveformFrame: nil,
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

    func testChainedEqPlaylistSpectrumWaveformRepairCreatesContiguousStack() {
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
        let waveformHeight: CGFloat = 260

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
        let waveform = NSRect(
            x: main.minX + 7,
            y: spectrum.minY - waveformHeight,
            width: main.width - 35,
            height: waveformHeight
        )  // flush to spectrum before spectrum gets repaired upward

        let repaired = AppStateManager.repairClassicCenterStackFrames(
            mainFrame: main,
            equalizerFrame: eq,
            playlistFrame: playlist,
            spectrumFrame: spectrum,
            waveformFrame: waveform,
            scale: scale
        )

        XCTAssertTrue(repaired.repaired)
        guard let eqFrame = repaired.equalizerFrame,
              let playlistFrame = repaired.playlistFrame,
              let spectrumFrame = repaired.spectrumFrame,
              let waveformFrame = repaired.waveformFrame else {
            XCTFail("Expected all center-stack frames")
            return
        }

        assertEqual(eqFrame.maxY, repaired.mainFrame.minY)
        assertEqual(playlistFrame.maxY, eqFrame.minY)
        assertEqual(spectrumFrame.maxY, playlistFrame.minY)
        assertEqual(waveformFrame.maxY, spectrumFrame.minY)

        // EQ width is normalized to main width; playlist/spectrum/waveform preserve original width
        assertEqual(eqFrame.minX, repaired.mainFrame.minX)
        assertEqual(eqFrame.width, repaired.mainFrame.width)
        for frame in [playlistFrame, spectrumFrame, waveformFrame] {
            assertEqual(frame.minX, repaired.mainFrame.minX)
        }
    }

    func testSpectrumAndWaveformRepairCreatesContiguousLowerStack() {
        let scale: CGFloat = 1.0
        let main = NSRect(
            x: 140,
            y: 500,
            width: Skin.mainWindowSize.width * scale,
            height: Skin.mainWindowSize.height * scale
        )
        let spectrumHeight = Skin.mainWindowSize.height * scale
        let waveformHeight: CGFloat = 240
        let spectrum = NSRect(
            x: main.minX + 11,
            y: main.minY - spectrumHeight - 16,
            width: main.width - 18,
            height: spectrumHeight
        )
        let waveform = NSRect(
            x: main.minX + 6,
            y: spectrum.minY - waveformHeight,
            width: main.width - 24,
            height: waveformHeight
        )

        let repaired = AppStateManager.repairClassicCenterStackFrames(
            mainFrame: main,
            equalizerFrame: nil,
            playlistFrame: nil,
            spectrumFrame: spectrum,
            waveformFrame: waveform,
            scale: scale
        )

        XCTAssertTrue(repaired.repaired)
        guard let spectrumFrame = repaired.spectrumFrame,
              let waveformFrame = repaired.waveformFrame else {
            XCTFail("Expected spectrum and waveform frames")
            return
        }

        assertEqual(spectrumFrame.maxY, repaired.mainFrame.minY)
        assertEqual(waveformFrame.maxY, spectrumFrame.minY)
        // spectrum/waveform preserve original width; only minX is corrected
        for frame in [spectrumFrame, waveformFrame] {
            assertEqual(frame.minX, repaired.mainFrame.minX)
        }
    }

    func testWaveformGapBeyondThresholdRemainsUnchanged() {
        let scale: CGFloat = 1.0
        let main = NSRect(
            x: 200,
            y: 500,
            width: Skin.mainWindowSize.width * scale,
            height: Skin.mainWindowSize.height * scale
        )
        let spectrumHeight = Skin.mainWindowSize.height * scale
        let waveformHeight: CGFloat = 240
        let spectrum = NSRect(
            x: main.minX,
            y: main.minY - spectrumHeight,
            width: main.width,
            height: spectrumHeight
        )
        let waveform = NSRect(
            x: main.minX,
            y: spectrum.minY - waveformHeight - 32,
            width: main.width,
            height: waveformHeight
        )  // 32px gap from spectrum

        let repaired = AppStateManager.repairClassicCenterStackFrames(
            mainFrame: main,
            equalizerFrame: nil,
            playlistFrame: nil,
            spectrumFrame: spectrum,
            waveformFrame: waveform,
            scale: scale
        )

        XCTAssertFalse(repaired.repaired)
        XCTAssertEqual(repaired.waveformFrame, waveform)
    }

    private func assertEqual(_ lhs: CGFloat, _ rhs: CGFloat, accuracy: CGFloat = 0.001, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(lhs, rhs, accuracy: accuracy, file: file, line: line)
    }
}
