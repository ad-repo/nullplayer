import AppKit
import Foundation
import XCTest
@testable import NullPlayer

final class ReeltoneModeSwitchIntegrationTests: XCTestCase {
    func testLiveModeSwitchSequencePreservesActiveLocalPlaybackState() throws {
        guard ProcessInfo.processInfo.environment["NULLPLAYER_RUN_REELTONE_LIVE_SWITCH_TEST"] == "1" else {
            throw XCTSkip("Set NULLPLAYER_RUN_REELTONE_LIVE_SWITCH_TEST=1 in an isolated fixed home")
        }

        _ = NSApplication.shared
        let temporaryRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("ReeltoneModeSwitchTests-" + UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: temporaryRoot) }
        try FileManager.default.createDirectory(at: temporaryRoot, withIntermediateDirectories: true)
        let audioURL = temporaryRoot.appendingPathComponent("continuity.wav")
        try makePCM16WAV(sampleRate: 44_100, channels: 2, seconds: 8).write(to: audioURL)

        let manager = WindowManager.shared
        let engine = manager.audioEngine
        XCTAssertTrue(engine.playlist.isEmpty, "Run the integration test in a fresh fixed home")
        XCTAssertEqual(CastManager.shared.currentCast, .none, "The isolated test must not inherit a cast session")
        defer {
            engine.stop()
            engine.setPlaylistTracks([])
            manager.teardownModeDependentWindows()
        }

        if manager.uiMode != .classic { manager.reloadUI(to: .classic) }
        manager.showMainWindow(reveal: false)
        manager.showSpectrum(at: NSRect(x: 40, y: 40, width: 550, height: 116))
        manager.showProjectM(at: NSRect(x: 610, y: 40, width: 275, height: 232))
        let expectedSpectrumConsumers = engine.spectrumConsumerRegistrationCount
        XCTAssertGreaterThanOrEqual(expectedSpectrumConsumers, 2)
        let track = Track(url: audioURL, title: "Mode Switch Continuity", artist: "NullPlayer", duration: 8)
        engine.setPlaylistTracks([track])
        engine.play()
        XCTAssertTrue(waitUntil(timeout: 4) { engine.state == .playing })
        engine.seek(to: 1.5)
        XCTAssertTrue(waitUntil(timeout: 2) { engine.currentTime >= 1.35 })

        let initialPlaylistIDs = engine.playlist.map(\.id)
        let initialTrackID = try XCTUnwrap(engine.currentTrack?.id)
        let initialCast = CastManager.shared.currentCast
        let sequence: [(PlayerUIMode, AnyClass)] = [
            (.reeltone, ReeltoneMainWindowController.self),
            (.modern, ModernMainWindowController.self),
            (.reeltone, ReeltoneMainWindowController.self),
            (.metal, ModernMainWindowController.self),
            (.reeltone, ReeltoneMainWindowController.self),
            (.classic, MainWindowController.self),
        ]

        var previousTime = engine.currentTime
        for entry in sequence {
            let mode = entry.0
            let controllerClass: AnyClass = entry.1
            manager.reloadUI(to: mode)
            XCTAssertEqual(manager.uiMode, mode)
            XCTAssertTrue(type(of: try XCTUnwrap(manager.mainWindowController)) == controllerClass)
            XCTAssertEqual(engine.playlist.map(\.id), initialPlaylistIDs)
            XCTAssertEqual(engine.currentTrack?.id, initialTrackID)
            XCTAssertEqual(engine.state, .playing)
            XCTAssertEqual(CastManager.shared.currentCast, initialCast)
            XCTAssertEqual(engine.spectrumConsumerRegistrationCount, expectedSpectrumConsumers)
            XCTAssertGreaterThanOrEqual(engine.currentTime, previousTime - 0.08)
            previousTime = engine.currentTime
        }
        XCTAssertGreaterThan(engine.currentTime, 1.35)

        manager.reloadUI(to: .modern)
        manager.enterCompactWindow(treatMainAsVisible: true)
        XCTAssertTrue(manager.compactWindowEnabled)
        XCTAssertTrue(manager.hasCompactSurfaceController)
        manager.reloadUI(to: .reeltone)
        XCTAssertFalse(manager.compactWindowEnabled)
        XCTAssertFalse(manager.compactModeEnabled)
        XCTAssertFalse(manager.hasCompactSurfaceController)
        XCTAssertTrue(manager.mainWindowController is ReeltoneMainWindowController)
        XCTAssertEqual(engine.state, .playing)
        XCTAssertEqual(engine.currentTrack?.id, initialTrackID)
        XCTAssertEqual(engine.spectrumConsumerRegistrationCount, expectedSpectrumConsumers)

        manager.reloadUI(to: .modern)
        let modeIndependentPanel = NSPanel(
            contentRect: NSRect(x: 80, y: 80, width: 180, height: 100),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        modeIndependentPanel.title = "Mode-independent integration panel"
        modeIndependentPanel.orderFront(nil)
        defer { modeIndependentPanel.close() }
        manager.enterCompactMode(revealWindow: false, treatMainAsVisible: true)
        XCTAssertTrue(waitUntil(timeout: 2) { manager.compactModeEnabled })
        XCTAssertTrue(manager.hasCompactSurfaceController)
        XCTAssertFalse(modeIndependentPanel.isVisible)
        let switchedFromCompactMode = expectation(description: "Compact Mode exits into regular Reeltone")
        manager.reloadUI(to: .reeltone) { switchedFromCompactMode.fulfill() }
        wait(for: [switchedFromCompactMode], timeout: 4)
        XCTAssertFalse(manager.compactModeEnabled)
        XCTAssertFalse(manager.compactWindowEnabled)
        XCTAssertFalse(manager.hasCompactSurfaceController)
        XCTAssertEqual(NSApp.activationPolicy(), .regular)
        XCTAssertTrue(manager.mainWindowController is ReeltoneMainWindowController)
        XCTAssertTrue(modeIndependentPanel.isVisible)
        XCTAssertEqual(engine.state, .playing)
        XCTAssertEqual(engine.currentTrack?.id, initialTrackID)
        XCTAssertEqual(engine.spectrumConsumerRegistrationCount, expectedSpectrumConsumers)
    }

    private func waitUntil(timeout: TimeInterval, condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            if condition() { return true }
            RunLoop.current.run(until: Date().addingTimeInterval(0.02))
        } while Date() < deadline
        return condition()
    }

    private func makePCM16WAV(sampleRate: UInt32, channels: UInt16, seconds: UInt32) -> Data {
        let bytesPerSample: UInt16 = 2
        let blockAlign = channels * bytesPerSample
        let frames = sampleRate * seconds
        let dataSize = frames * UInt32(blockAlign)
        var data = Data()
        data.append(contentsOf: "RIFF".utf8)
        appendLittleEndian(36 + dataSize, to: &data)
        data.append(contentsOf: "WAVEfmt ".utf8)
        appendLittleEndian(UInt32(16), to: &data)
        appendLittleEndian(UInt16(1), to: &data)
        appendLittleEndian(channels, to: &data)
        appendLittleEndian(sampleRate, to: &data)
        appendLittleEndian(sampleRate * UInt32(blockAlign), to: &data)
        appendLittleEndian(blockAlign, to: &data)
        appendLittleEndian(UInt16(16), to: &data)
        data.append(contentsOf: "data".utf8)
        appendLittleEndian(dataSize, to: &data)
        data.append(Data(repeating: 0, count: Int(dataSize)))
        return data
    }

    private func appendLittleEndian<T: FixedWidthInteger>(_ value: T, to data: inout Data) {
        var littleEndian = value.littleEndian
        withUnsafeBytes(of: &littleEndian) { data.append(contentsOf: $0) }
    }
}
