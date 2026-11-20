import AudioStreaming
import AVFoundation
import CoreAudio
import XCTest
@testable import NullPlayer

/// Streams play through AudioStreaming's own output unit, reached by reflection (issue 788). These
/// fail when an AudioStreaming upgrade moves that unit, which would silently send every stream back
/// to the macOS default output whatever the Output menu says.
final class StreamOutputRoutingTests: XCTestCase {
    func testAudioStreamingOutputUnitIsReachable() {
        let player = AudioPlayer()
        XCTAssertNotNil(waitForOutputUnit(of: player),
                        "AudioPlayer.player is gone or renamed; update StreamOutputRouting")
    }

    func testRouteMovesTheOutputUnitToTheDevice() throws {
        guard let defaultUID = defaultOutputUID() else { throw XCTSkip("No default output device") }
        // A private aggregate over the default output is a second device on any Mac with audio.
        let description: [String: Any] = [
            kAudioAggregateDeviceNameKey: "StreamOutputRoutingTests",
            kAudioAggregateDeviceUIDKey: "nullplayer.tests.stream-routing.\(getpid())",
            kAudioAggregateDeviceIsPrivateKey: 1,
            kAudioAggregateDeviceSubDeviceListKey: [[kAudioSubDeviceUIDKey: defaultUID]],
            kAudioAggregateDeviceMainSubDeviceKey: defaultUID,
        ]
        var aggregate = AudioDeviceID(0)
        guard AudioHardwareCreateAggregateDevice(description as CFDictionary, &aggregate) == noErr else {
            throw XCTSkip("Cannot create an aggregate device here")
        }
        defer { AudioHardwareDestroyAggregateDevice(aggregate) }

        let player = AudioPlayer()
        let unit = try XCTUnwrap(waitForOutputUnit(of: player))
        StreamOutputRouting.route(player, to: aggregate)

        var current = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        XCTAssertEqual(AudioUnitGetProperty(unit.audioUnit, kAudioOutputUnitProperty_CurrentDevice,
                                            kAudioUnitScope_Global, 0, &current, &size), noErr)
        XCTAssertEqual(current, aggregate)
    }

    /// AudioStreaming instantiates its output unit asynchronously after `init`.
    private func waitForOutputUnit(of player: AudioPlayer) -> AVAudioUnit? {
        let deadline = Date().addingTimeInterval(5)
        while Date() < deadline {
            if let unit = StreamOutputRouting.outputUnit(of: player) { return unit }
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        }
        return nil
    }

    private func defaultOutputUID() -> String? {
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        var device = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil,
                                         &size, &device) == noErr, device != 0 else { return nil }
        address.mSelector = kAudioDevicePropertyDeviceUID
        var uid: Unmanaged<CFString>?
        size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &uid) == noErr,
              let uid else { return nil }
        return uid.takeRetainedValue() as String
    }
}
