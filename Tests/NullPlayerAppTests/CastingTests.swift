import XCTest
import struct NullPlayerCore.PlexMedia
@testable import NullPlayer

@MainActor
final class CastingTests: XCTestCase {
    private let preferredDeviceDefaultsKey = "preferredVideoCastDeviceID"

    private var originalPreferredDeviceID: String?
    private var originalDebugDiscoveredDevices: [CastDevice]?
    private var originalVideoPlayerController: VideoPlayerWindowController?

    override func setUp() {
        super.setUp()
        let castManager = CastManager.shared
        originalPreferredDeviceID = UserDefaults.standard.string(forKey: preferredDeviceDefaultsKey)
        originalDebugDiscoveredDevices = castManager.debugDiscoveredDevices
        originalVideoPlayerController = WindowManager.shared.debugVideoPlayerWindowControllerForTesting

        castManager.debugDiscoveredDevices = nil
        castManager.debugSetVideoCastingStateForTesting(false)
        castManager.setPreferredVideoCastDevice(nil)
        WindowManager.shared.debugSetVideoPlayerWindowControllerForTesting(nil)
    }

    override func tearDown() {
        let castManager = CastManager.shared
        castManager.debugDiscoveredDevices = originalDebugDiscoveredDevices
        castManager.debugSetVideoCastingStateForTesting(false)

        if let originalPreferredDeviceID {
            castManager.setPreferredVideoCastDevice(originalPreferredDeviceID)
            UserDefaults.standard.set(originalPreferredDeviceID, forKey: preferredDeviceDefaultsKey)
        } else {
            castManager.setPreferredVideoCastDevice(nil)
            UserDefaults.standard.removeObject(forKey: preferredDeviceDefaultsKey)
        }

        WindowManager.shared.debugSetVideoPlayerWindowControllerForTesting(originalVideoPlayerController)
        super.tearDown()
    }

    func testPreferredVideoCastDeviceIDPersistsToUserDefaults() {
        CastManager.shared.setPreferredVideoCastDevice("video-device-1")

        XCTAssertEqual(CastManager.shared.preferredVideoCastDeviceID, "video-device-1")
        XCTAssertEqual(UserDefaults.standard.string(forKey: preferredDeviceDefaultsKey), "video-device-1")
    }

    func testSettingPreferenceToNonVideoDeviceIsIgnored() {
        let videoDevice = CastDevice(id: "video-device", name: "Living Room Chromecast", type: .chromecast, address: "192.168.1.10", port: 8009)
        let nonVideoDevice = CastDevice(id: "sonos-device", name: "Kitchen Sonos", type: .sonos, address: "192.168.1.20", port: 1400)
        CastManager.shared.debugDiscoveredDevices = [videoDevice, nonVideoDevice]

        CastManager.shared.setPreferredVideoCastDevice(videoDevice.id)
        CastManager.shared.setPreferredVideoCastDevice(nonVideoDevice.id)

        XCTAssertEqual(CastManager.shared.preferredVideoCastDeviceID, videoDevice.id)
    }

    func testSetPreferredVideoCastDevicePostsSessionDidChangeNotification() {
        let expectation = expectation(description: "sessionDidChange posted")
        let observer = NotificationCenter.default.addObserver(
            forName: CastManager.sessionDidChangeNotification,
            object: nil,
            queue: nil
        ) { _ in
            expectation.fulfill()
        }

        CastManager.shared.setPreferredVideoCastDevice("notify-device")

        wait(for: [expectation], timeout: 1.0)
        NotificationCenter.default.removeObserver(observer)
    }

    func testIsVideoContentActiveUsesWindowVisibilityAndVideoCastingState() {
        let windowManager = WindowManager.shared
        let castManager = CastManager.shared

        castManager.debugSetVideoCastingStateForTesting(false)
        windowManager.debugSetVideoPlayerWindowControllerForTesting(nil)
        XCTAssertFalse(windowManager.isVideoContentActive)

        let controller = VideoPlayerWindowController()
        controller.debugSetCurrentTitleForTesting("Example Video")
        controller.showWindow(nil)
        windowManager.debugSetVideoPlayerWindowControllerForTesting(controller)
        XCTAssertTrue(windowManager.isVideoContentActive)

        controller.window?.orderOut(nil)
        castManager.debugSetVideoCastingStateForTesting(true)
        XCTAssertTrue(windowManager.isVideoContentActive)

        castManager.debugSetVideoCastingStateForTesting(false)
        controller.close()
    }

    func testSessionDidChangeClearsVideoControllerCastStateWhenVideoCastingIsInactive() {
        let controller = VideoPlayerWindowController()
        let device = CastDevice(id: "cast-device", name: "TV", type: .chromecast, address: "192.168.1.30", port: 8009)
        controller.debugSetCastStateForTesting(device: device, startPosition: 12.5, duration: 245.0)

        let before = controller.debugCastStateSnapshot
        XCTAssertTrue(before.isCastingVideo)
        XCTAssertTrue(before.hasTargetDevice)
        XCTAssertGreaterThan(before.castStartPosition, 0)
        XCTAssertTrue(before.hasPlaybackStartDate)
        XCTAssertEqual(before.castState, .casting)
        XCTAssertGreaterThan(before.castDuration, 0)

        CastManager.shared.debugSetVideoCastingStateForTesting(false)
        NotificationCenter.default.post(name: CastManager.sessionDidChangeNotification, object: nil)

        let after = controller.debugCastStateSnapshot
        XCTAssertFalse(after.isCastingVideo)
        XCTAssertFalse(after.hasTargetDevice)
        XCTAssertEqual(after.castStartPosition, 0)
        XCTAssertFalse(after.hasPlaybackStartDate)
        XCTAssertEqual(after.castState, .idle)
        XCTAssertEqual(after.castDuration, 0)

        controller.close()
    }

    // MARK: - currentCast enum

    func testCurrentCastIsNoneWhenNoActiveSession() {
        CastManager.shared.debugSetVideoCastingStateForTesting(false)
        if case .none = CastManager.shared.currentCast { } else {
            XCTFail("Expected currentCast == .none when no active session")
        }
    }

    func testCurrentCastIsVideoWhenSessionHasVideoMediaType() {
        CastManager.shared.debugSetVideoCastingStateForTesting(true)
        if case .video = CastManager.shared.currentCast { } else {
            XCTFail("Expected currentCast == .video for video session")
        }
    }

    func testCurrentCastIsAudioWhenSessionHasAudioMediaType() {
        let device = CastDevice(id: "audio-device", name: "Kitchen Sonos", type: .sonos, address: "192.168.1.5", port: 1400)
        CastManager.shared.debugSetAudioCastSessionForTesting(device: device)
        if case .audio = CastManager.shared.currentCast { } else {
            XCTFail("Expected currentCast == .audio for audio session")
        }
    }

    func testCurrentCastSwitchesToNoneAfterSessionCleared() {
        CastManager.shared.debugSetVideoCastingStateForTesting(true)
        if case .video = CastManager.shared.currentCast { } else {
            XCTFail("Expected .video before clear")
        }

        CastManager.shared.debugSetVideoCastingStateForTesting(false)
        if case .none = CastManager.shared.currentCast { } else {
            XCTFail("Expected .none after clear")
        }
    }

    // MARK: - .loaded state semantics

    func testLoadedStateIsDistinctFromCastingAndIdle() {
        XCTAssertNotEqual(CastState.loaded, CastState.casting)
        XCTAssertNotEqual(CastState.loaded, CastState.idle)
    }

    func testSessionInLoadedStateIsRecognizedAsNotYetReceivingStatus() {
        let device = CastDevice(id: "cc-device", name: "Living Room TV", type: .chromecast, address: "192.168.1.10", port: 8009)
        CastManager.shared.debugSetActiveCastSessionForTesting(device: device, startPosition: 0, duration: 120)
        CastManager.shared.debugSetActiveSessionStateForTesting(.loaded)

        XCTAssertEqual(CastManager.shared.activeSession?.state, .loaded,
                       "Session should remain in .loaded state until first status update")
    }

    func testLoadedAudioCastCountsAsActiveForTrackRouting() {
        let device = CastDevice(id: "cc-audio", name: "Living Room TV", type: .chromecast, address: "192.168.1.10", port: 8009)
        CastManager.shared.debugSetAudioCastSessionForTesting(device: device)
        CastManager.shared.debugSetActiveSessionStateForTesting(.loaded)

        XCTAssertFalse(WindowManager.shared.audioEngine.isCastingActive)
        XCTAssertTrue(WindowManager.shared.audioEngine.isAudioCastRoutingActive)
        XCTAssertTrue(WindowManager.shared.audioEngine.isAnyCastingActive)
    }

    func testIdleAudioCastDoesNotCountAsActiveForTrackRouting() {
        let device = CastDevice(id: "cc-audio", name: "Living Room TV", type: .chromecast, address: "192.168.1.10", port: 8009)
        CastManager.shared.debugSetAudioCastSessionForTesting(device: device)
        CastManager.shared.debugSetActiveSessionStateForTesting(.idle)

        XCTAssertFalse(WindowManager.shared.audioEngine.isAudioCastRoutingActive)
        XCTAssertFalse(WindowManager.shared.audioEngine.isAnyCastingActive)
    }

    func testSessionTransitionsFromLoadedToCastingAfterFirstStatus() {
        let device = CastDevice(id: "cc-device", name: "Living Room TV", type: .chromecast, address: "192.168.1.10", port: 8009)
        CastManager.shared.debugSetActiveCastSessionForTesting(device: device, startPosition: 0, duration: 120)
        CastManager.shared.debugSetActiveSessionStateForTesting(.loaded)

        XCTAssertEqual(CastManager.shared.activeSession?.state, .loaded)

        let expectation = expectation(description: "first Chromecast status transitions loaded session")
        var status = CastMediaStatus()
        status.currentTime = 1.5
        status.duration = 120
        status.playerState = .playing
        status.mediaSessionId = 1

        NotificationCenter.default.post(
            name: ChromecastManager.mediaStatusDidUpdateNotification,
            object: nil,
            userInfo: ["status": status]
        )

        DispatchQueue.main.async {
            XCTAssertEqual(CastManager.shared.activeSession?.state, .casting)
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1.0)
        XCTAssertEqual(CastManager.shared.activeSession?.state, .casting)
    }

    // MARK: - Session notification

    func testSessionDidChangeNotificationFiresOnStateChange() {
        let expectation = expectation(description: "sessionDidChange posted")
        let device = CastDevice(id: "notify-device", name: "Living Room TV", type: .chromecast, address: "192.168.1.10", port: 8009)
        CastManager.shared.debugSetActiveCastSessionForTesting(device: device, startPosition: 0, duration: 120)
        let observer = NotificationCenter.default.addObserver(
            forName: CastManager.sessionDidChangeNotification,
            object: nil,
            queue: nil
        ) { _ in expectation.fulfill() }

        CastManager.shared.debugSetActiveSessionStateForTesting(.loaded)

        wait(for: [expectation], timeout: 1.0)
        NotificationCenter.default.removeObserver(observer)
    }

    // MARK: - windowWillClose ownership

    func testVPWCDidInitiateCastFlagIsSetWhenCastStateIsConfigured() {
        let device = CastDevice(id: "tv", name: "TV", type: .chromecast, address: "192.168.1.10", port: 8009)
        let controller = VideoPlayerWindowController()

        // debugSetCastStateForTesting sets isCastingVideo but NOT didInitiateCast (library-menu path)
        controller.debugSetCastStateForTesting(device: device, startPosition: 0, duration: 120)
        XCTAssertFalse(controller.debugDidInitiateCast,
                       "Library-menu casts must not set didInitiateCast on the player window")

        // Explicitly marking this window as the initiator simulates the player-window cast path
        controller.debugSetDidInitiateCastForTesting(true)
        XCTAssertTrue(controller.debugDidInitiateCast)

        controller.close()
    }

    func testVideoCastCurrentTimeDoesNotClampToZeroWhenDurationUnknown() {
        let device = CastDevice(id: "tv", name: "TV", type: .chromecast, address: "192.168.1.10", port: 8009)
        let controller = VideoPlayerWindowController()
        controller.debugSetCastStateForTesting(device: device, startPosition: 12.5, duration: 0)

        XCTAssertGreaterThanOrEqual(controller.castCurrentTime, 12.5)

        controller.close()
    }

    func testVPWCWithDidInitiateCastFalseSessionRemainsAfterWindowClose() {
        let castManager = CastManager.shared
        let device = CastDevice(id: "tv", name: "TV", type: .chromecast, address: "192.168.1.10", port: 8009)
        castManager.debugSetActiveCastSessionForTesting(device: device, startPosition: 0, duration: 120)

        let controller = VideoPlayerWindowController()
        // isCastingVideo NOT set — controller did not initiate this cast
        controller.debugSetDidInitiateCastForTesting(false)

        XCTAssertFalse(controller.debugDidInitiateCast)
        XCTAssertNotNil(castManager.activeSession)

        controller.close()

        // Session should remain alive — this controller didn't initiate it
        XCTAssertNotNil(castManager.activeSession)
    }

    func testExtensionlessHighResolutionFlacIsNotSonosCompatible() {
        let track = Track(
            url: URL(string: "http://plex.local:32400/library/parts/1/file?X-Plex-Token=token")!,
            title: "24/192 FLAC",
            sampleRate: 192_000,
            contentType: "audio/flac"
        )

        XCTAssertFalse(CastManager.isSonosCompatible(track))
    }

    func testSonosCompatibilityNormalizesContentTypeParameters() {
        let track = Track(
            url: URL(string: "http://server.local/stream/123")!,
            title: "High-res FLAC",
            sampleRate: 96_000,
            contentType: "Audio/X-FLAC; charset=binary"
        )

        XCTAssertFalse(CastManager.isSonosCompatible(track))
    }

    func testPlexContentTypeInferencePreservesLosslessCodecs() {
        XCTAssertEqual(PlexManager.inferAudioContentType(from: makePlexMedia(audioCodec: "flac")), "audio/flac")
        XCTAssertEqual(PlexManager.inferAudioContentType(from: makePlexMedia(audioCodec: "alac")), "audio/mp4")
    }

    private func makePlexMedia(audioCodec: String? = nil, container: String? = nil) -> PlexMedia {
        PlexMedia(
            id: 1,
            duration: nil,
            bitrate: nil,
            audioChannels: nil,
            audioCodec: audioCodec,
            videoCodec: nil,
            videoResolution: nil,
            width: nil,
            height: nil,
            container: container,
            parts: []
        )
    }
}
