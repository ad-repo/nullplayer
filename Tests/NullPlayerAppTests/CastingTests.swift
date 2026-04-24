import XCTest
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
        XCTAssertTrue(before.castHasReceivedStatus)
        XCTAssertGreaterThan(before.castDuration, 0)

        CastManager.shared.debugSetVideoCastingStateForTesting(false)
        NotificationCenter.default.post(name: CastManager.sessionDidChangeNotification, object: nil)

        let after = controller.debugCastStateSnapshot
        XCTAssertFalse(after.isCastingVideo)
        XCTAssertFalse(after.hasTargetDevice)
        XCTAssertEqual(after.castStartPosition, 0)
        XCTAssertFalse(after.hasPlaybackStartDate)
        XCTAssertFalse(after.castHasReceivedStatus)
        XCTAssertEqual(after.castDuration, 0)

        controller.close()
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
        XCTAssertEqual(PlexManager.inferAudioContentType(from: makePlexMedia(audioCodec: "alac")), "audio/alac")
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
