import AVFoundation
import AudioStreaming

/// Points AudioStreaming's hardware output unit at a Core Audio device.
///
/// AudioStreaming (1.4.4) renders its engine offline and plays the result through its own
/// `kAudioUnitSubType_DefaultOutput` unit, held in the internal `AudioPlayer.player`, and has no
/// output-device API, so a stream follows the macOS default output whatever the Output menu says.
/// The unit is reached by reflection; if a later AudioStreaming renames the property this logs and
/// streams fall back to the macOS default.
enum StreamOutputRouting {
    static func route(_ player: AudioPlayer, to deviceID: AudioDeviceID) {
        guard let unit = outputUnit(of: player) else { return }

        var current = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        if AudioUnitGetProperty(unit.audioUnit, kAudioOutputUnitProperty_CurrentDevice,
                                kAudioUnitScope_Global, 0, &current, &size) == noErr,
           current == deviceID { return }

        var target = deviceID
        let status = AudioUnitSetProperty(unit.audioUnit, kAudioOutputUnitProperty_CurrentDevice,
                                          kAudioUnitScope_Global, 0, &target,
                                          UInt32(MemoryLayout<AudioDeviceID>.size))
        NSLog("StreamOutputRouting: Output device %u -> %u (status %d)", current, deviceID, status)
    }

    /// The player's hardware output unit, or nil before AudioStreaming has instantiated it (it
    /// does so asynchronously, leaving a bare placeholder until then; `StreamingAudioPlayer`
    /// routes again when playback starts).
    static func outputUnit(of player: AudioPlayer) -> AVAudioUnit? {
        guard let unit = Mirror(reflecting: player).children
            .first(where: { $0.label == "player" })?.value as? AVAudioUnit else {
            NSLog("StreamOutputRouting: AudioPlayer.player not found; streams use the macOS default output")
            return nil
        }
        return unit.audioComponentDescription.componentType == kAudioUnitType_Output ? unit : nil
    }
}
