import CoreAudio
import CAudioTapRing
import Foundation

/// A Core Audio process tap on NullPlayer's own output, muted while tapped: the visualization cast
/// sends the music to the TV and the Mac's speakers go quiet (the TV runs seconds behind). Tearing it
/// down unmutes the Mac. The volume slider still applies, because the tap hears the mixed output.
///
/// macOS asks once for "System Audio Recording" permission. In a bundled app creating the tap blocks
/// for about 5 s while that prompt is up (measured), so callers build it off the main thread.
@available(macOS 14.2, *)
final class ProcessAudioTap {
    private(set) var sampleRate: Double = 0
    private var tapID = AudioObjectID(kAudioObjectUnknown)
    private var aggregateID = AudioObjectID(kAudioObjectUnknown)
    private var procID: AudioDeviceIOProcID?

    init() throws {
        var pid = getpid()
        var process = AudioObjectID(kAudioObjectUnknown)
        try Self.check(Self.read(AudioObjectID(kAudioObjectSystemObject), kAudioHardwarePropertyTranslatePIDToProcessObject,
                                 &process, qualifier: &pid, qualifierSize: UInt32(MemoryLayout<pid_t>.size)), "find process")

        let description = CATapDescription(stereoMixdownOfProcesses: [process])
        description.uuid = UUID()
        description.muteBehavior = .mutedWhenTapped
        description.isPrivate = true
        try Self.check(AudioHardwareCreateProcessTap(description, &tapID), "create tap")

        do {
            var format = AudioStreamBasicDescription()
            try Self.check(Self.read(tapID, kAudioTapPropertyFormat, &format), "tap format")
            sampleRate = format.mSampleRate

            // The default output is the aggregate's clock; the tap rides on it with drift compensation.
            var output = AudioObjectID(kAudioObjectUnknown)
            try Self.check(Self.read(AudioObjectID(kAudioObjectSystemObject), kAudioHardwarePropertyDefaultSystemOutputDevice,
                                     &output), "default output")
            var outputUID = "" as CFString
            try Self.check(Self.read(output, kAudioDevicePropertyDeviceUID, &outputUID), "output UID")
            let aggregate: [String: Any] = [
                kAudioAggregateDeviceNameKey: "NullPlayer Visualization Cast",
                kAudioAggregateDeviceUIDKey: UUID().uuidString,
                kAudioAggregateDeviceMainSubDeviceKey: outputUID as String,
                kAudioAggregateDeviceIsPrivateKey: true,
                kAudioAggregateDeviceIsStackedKey: false,
                kAudioAggregateDeviceTapAutoStartKey: true,
                kAudioAggregateDeviceSubDeviceListKey: [[kAudioSubDeviceUIDKey: outputUID as String]],
                kAudioAggregateDeviceTapListKey: [[kAudioSubTapDriftCompensationKey: true,
                                                   kAudioSubTapUIDKey: description.uuid.uuidString]],
            ]
            try Self.check(AudioHardwareCreateAggregateDevice(aggregate as CFDictionary, &aggregateID), "create device")
        } catch {
            stop()
            throw error
        }
    }

    /// Starts capture (and the mute). `onAudio` runs on Core Audio's IO thread with float frames.
    func start(onAudio: @escaping (UnsafeMutableAudioBufferListPointer, Int) -> Void) throws {
        try Self.check(AudioDeviceCreateIOProcIDWithBlock(&procID, aggregateID, nil) { _, input, _, _, _ in
            let buffers = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: input))
            guard let first = buffers.first, first.mNumberChannels > 0 else { return }
            onAudio(buffers, Int(first.mDataByteSize) / (4 * Int(first.mNumberChannels)))
        }, "IO proc")
        try Self.check(AudioDeviceStart(aggregateID, procID), "start")
    }

    /// Stops capture and unmutes the Mac. Safe to call more than once.
    func stop() {
        if let procID {
            AudioDeviceStop(aggregateID, procID)
            AudioDeviceDestroyIOProcID(aggregateID, procID)
            self.procID = nil
        }
        if aggregateID != kAudioObjectUnknown {
            AudioHardwareDestroyAggregateDevice(aggregateID)
            aggregateID = AudioObjectID(kAudioObjectUnknown)
        }
        if tapID != kAudioObjectUnknown {
            AudioHardwareDestroyProcessTap(tapID)
            tapID = AudioObjectID(kAudioObjectUnknown)
        }
    }

    private static func read<T>(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector, _ value: inout T,
                                qualifier: UnsafeRawPointer? = nil, qualifierSize: UInt32 = 0) -> OSStatus {
        var address = AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        var size = UInt32(MemoryLayout<T>.size)
        return AudioObjectGetPropertyData(object, &address, qualifierSize, qualifier, &size, &value)
    }

    private static func check(_ status: OSStatus, _ step: String) throws {
        guard status == noErr else { throw VisualizationCastError.audioTap(step, status) }
    }
}

/// The tap's audio on its way to the encoder: interleaved stereo, the newest `frames` kept, so drift
/// between the device clock and the encoder's tick drops or pads. The IO thread writes and the
/// encoder reads without either blocking or allocating (`CAudioTapRing`).
final class AudioTapRing {
    private let ring: OpaquePointer
    private let keep: Int   // samples: frames × 2
    /// Frames a full ring could not take. The IO thread's alone; read it once the tap has stopped.
    private(set) var droppedFrames = 0

    init(frames: Int) {
        keep = max(frames, 1) * 2
        // Twice what is kept, so a write meets a full ring only if the reader stalls that long.
        guard let ring = np_audio_tap_ring_create(keep * 2) else { fatalError("audio ring allocation") }
        self.ring = ring
    }

    deinit { np_audio_tap_ring_destroy(ring) }

    /// Core Audio's IO thread: float frames, interleaved or one buffer per channel; mono fills both.
    func write(_ buffers: UnsafeMutableAudioBufferListPointer, frames: Int) {
        var leftChannel: (samples: UnsafeMutablePointer<Float>, stride: Int)?
        var rightChannel: (samples: UnsafeMutablePointer<Float>, stride: Int)?
        var channel = 0
        for buffer in buffers {
            guard let data = buffer.mData?.assumingMemoryBound(to: Float.self) else { continue }
            let stride = Int(buffer.mNumberChannels)
            for c in 0..<stride where channel + c < 2 {
                if channel + c == 0 { leftChannel = (data + c, stride) } else { rightChannel = (data + c, stride) }
            }
            channel += stride
        }
        guard let left = leftChannel else { return }
        let right = rightChannel ?? left
        droppedFrames += np_audio_tap_ring_write(ring, left.samples, left.stride, right.samples, right.stride, frames)
    }

    /// `frames` frames, interleaved, silence-padded where the ring runs short. Anything older than
    /// the newest `frames` the ring keeps is discarded first, so `read(frames: 0)` just trims.
    func read(frames: Int) -> [Float] {
        var out = [Float](repeating: 0, count: frames * 2)
        out.withUnsafeMutableBufferPointer { out in
            _ = np_audio_tap_ring_read(ring, out.baseAddress, out.count, keep)
        }
        return out
    }
}
