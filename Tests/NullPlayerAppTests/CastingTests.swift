import XCTest
import struct NullPlayerCore.PlexMedia
@testable import NullPlayer

@MainActor
final class CastingTests: XCTestCase {
    private let preferredDeviceDefaultsKey = "preferredVideoCastDeviceID"

    private var originalPreferredDeviceID: String?
    private var originalDebugDiscoveredDevices: [CastDevice]?
    private var originalDebugActiveSession: CastSession?
    private var originalVideoPlayerController: VideoPlayerWindowController?

    override func setUp() {
        super.setUp()
        let castManager = CastManager.shared
        originalPreferredDeviceID = UserDefaults.standard.string(forKey: preferredDeviceDefaultsKey)
        originalDebugDiscoveredDevices = castManager.debugDiscoveredDevices
        originalDebugActiveSession = castManager.debugActiveSessionForTesting
        originalVideoPlayerController = WindowManager.shared.debugVideoPlayerWindowControllerForTesting

        castManager.debugDiscoveredDevices = nil
        castManager.debugActiveSessionForTesting = nil
        castManager.debugSetVideoCastingStateForTesting(false)
        castManager.debugSetChromecastHasSeenActivePlaybackForTesting(false)
        castManager.setPreferredVideoCastDevice(nil)
        WindowManager.shared.debugSetVideoPlayerWindowControllerForTesting(nil)
    }

    override func tearDown() {
        let castManager = CastManager.shared
        castManager.debugDiscoveredDevices = originalDebugDiscoveredDevices
        castManager.debugActiveSessionForTesting = originalDebugActiveSession

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

    func testChromecastDeviceIDUsesStableTxtRecordID() {
        let serviceName = "Chromecast-Ultra-91a086b76d0c422dd9dd9cda078e4911"

        let id = ChromecastManager.debugChromecastDeviceIDForTesting(
            serviceName: serviceName,
            txtRecordID: " 91A086B76D0C422DD9DD9CDA078E4911 "
        )

        XCTAssertEqual(id, "chromecast:91a086b76d0c422dd9dd9cda078e4911")
    }

    func testChromecastDeviceIDFallsBackToServiceNameNotResolvedAddress() {
        let serviceName = "Chromecast-Ultra-91a086b76d0c422dd9dd9cda078e4911"

        let id = ChromecastManager.debugChromecastDeviceIDForTesting(
            serviceName: serviceName,
            txtRecordID: nil
        )

        XCTAssertEqual(id, "chromecast:\(serviceName)")
        XCTAssertFalse(id.contains("192.168.0.199"))
        XCTAssertFalse(id.contains("8009"))
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

    func testSessionDidChangeIgnoresNoneWhileControllerStopsOwnCast() {
        let controller = VideoPlayerWindowController()
        let device = CastDevice(id: "cast-device", name: "TV", type: .chromecast, address: "192.168.1.30", port: 8009)
        controller.debugSetCastStateForTesting(device: device, startPosition: 12.5, duration: 245.0)
        controller.debugSetDidInitiateCastForTesting(true)
        controller.debugSetStoppingOwnCastForTesting(true)

        CastManager.shared.debugSetVideoCastingStateForTesting(false)
        NotificationCenter.default.post(name: CastManager.sessionDidChangeNotification, object: nil)

        let after = controller.debugCastStateSnapshot
        XCTAssertTrue(after.isCastingVideo)
        XCTAssertTrue(controller.debugDidInitiateCast)

        controller.debugSetStoppingOwnCastForTesting(false)
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

    func testChromecastLoadAckRestoreLeavesAudioSessionLoadedBeforeStatus() {
        let device = CastDevice(id: "cc-audio", name: "Living Room TV", type: .chromecast, address: "192.168.1.10", port: 8009)
        CastManager.shared.debugSetAudioCastSessionForTesting(device: device)

        // Simulate ChromecastManager.cast() marking the session as .casting when LOAD is sent.
        CastManager.shared.debugSetActiveSessionStateForTesting(.casting)
        CastManager.shared.debugRestoreChromecastLoadedStateAfterLoadForTesting()

        XCTAssertEqual(CastManager.shared.activeSession?.state, .loaded)
    }

    func testChromecastLoadAckRestoreDoesNotOverwriteActiveStatus() {
        let device = CastDevice(id: "cc-audio", name: "Living Room TV", type: .chromecast, address: "192.168.1.10", port: 8009)
        CastManager.shared.debugSetAudioCastSessionForTesting(device: device)

        CastManager.shared.debugSetActiveSessionStateForTesting(.casting)
        CastManager.shared.debugSetChromecastHasSeenActivePlaybackForTesting(true)
        CastManager.shared.debugRestoreChromecastLoadedStateAfterLoadForTesting()

        XCTAssertEqual(CastManager.shared.activeSession?.state, .casting)
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

    func testInitialChromecastAudioIdleStatusIsIgnored() {
        let device = CastDevice(id: "cc-audio", name: "Living Room TV", type: .chromecast, address: "192.168.1.10", port: 8009)
        CastManager.shared.debugSetAudioCastSessionForTesting(device: device)
        CastManager.shared.debugSetActiveSessionStateForTesting(.loaded)

        let expectation = expectation(description: "initial Chromecast audio IDLE ignored")
        var status = CastMediaStatus()
        status.currentTime = 0
        status.playerState = .idle
        status.mediaSessionId = 1

        NotificationCenter.default.post(
            name: ChromecastManager.mediaStatusDidUpdateNotification,
            object: nil,
            userInfo: ["status": status]
        )

        DispatchQueue.main.async {
            XCTAssertEqual(CastManager.shared.activeSession?.state, .loaded)
            XCTAssertNotNil(CastManager.shared.activeSession)
            XCTAssertNil(CastManager.shared.activeSession?.playbackStartDate)
            XCTAssertFalse(CastManager.shared.activeSession?.isPlaying ?? true)
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1.0)
    }

    func testChromecastAudioBufferingPromotesLoadedToCasting() {
        let device = CastDevice(id: "cc-audio", name: "Living Room TV", type: .chromecast, address: "192.168.1.10", port: 8009)
        CastManager.shared.debugSetAudioCastSessionForTesting(device: device)
        CastManager.shared.debugSetActiveSessionStateForTesting(.loaded)

        let expectation = expectation(description: "Chromecast audio BUFFERING promotes loaded session")
        var status = CastMediaStatus()
        status.currentTime = 2.0
        status.playerState = .buffering
        status.mediaSessionId = 1

        NotificationCenter.default.post(
            name: ChromecastManager.mediaStatusDidUpdateNotification,
            object: nil,
            userInfo: ["status": status]
        )

        DispatchQueue.main.async {
            XCTAssertEqual(CastManager.shared.activeSession?.state, .casting)
            XCTAssertNil(CastManager.shared.activeSession?.playbackStartDate)
            XCTAssertFalse(CastManager.shared.activeSession?.isPlaying ?? true)
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1.0)
    }

    func testChromecastAudioPlayingPromotesLoadedToCastingAndStartsClock() {
        let device = CastDevice(id: "cc-audio", name: "Living Room TV", type: .chromecast, address: "192.168.1.10", port: 8009)
        CastManager.shared.debugSetAudioCastSessionForTesting(device: device)
        CastManager.shared.debugSetActiveSessionStateForTesting(.loaded)

        let expectation = expectation(description: "Chromecast audio PLAYING promotes loaded session")
        var status = CastMediaStatus()
        status.currentTime = 2.0
        status.playerState = .playing
        status.mediaSessionId = 1

        NotificationCenter.default.post(
            name: ChromecastManager.mediaStatusDidUpdateNotification,
            object: nil,
            userInfo: ["status": status]
        )

        DispatchQueue.main.async {
            XCTAssertEqual(CastManager.shared.activeSession?.state, .casting)
            XCTAssertNotNil(CastManager.shared.activeSession?.playbackStartDate)
            XCTAssertTrue(CastManager.shared.activeSession?.isPlaying ?? false)
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1.0)
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
            title: "FLAC Track",
            sampleRate: 44_100,
            contentType: "Audio/X-FLAC; charset=binary"
        )

        XCTAssertTrue(CastManager.isSonosCompatible(track))
    }

    func testPlexContentTypeInferencePreservesLosslessCodecs() {
        XCTAssertEqual(PlexManager.inferAudioContentType(from: makePlexMedia(audioCodec: "flac")), "audio/flac")
        XCTAssertEqual(PlexManager.inferAudioContentType(from: makePlexMedia(audioCodec: "alac")), "audio/alac")
    }

    func testPlexAlacTracksAreRejectedForSonos() {
        let track = Track(
            url: URL(string: "http://plex.local:32400/library/parts/1/file?X-Plex-Token=token")!,
            title: "ALAC Track",
            sampleRate: 44_100,
            contentType: PlexManager.inferAudioContentType(from: makePlexMedia(audioCodec: "alac"))
        )

        XCTAssertFalse(CastManager.isSonosCompatible(track))
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
