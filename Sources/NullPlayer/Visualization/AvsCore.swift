import Foundation
import CAvsCore

/// One libavs instance: Advanced Visualization Studio, vendored as `CAvsCore` (see the
/// `avs-port` skill).
///
/// Threading: libavs is not thread-safe. Rendering and every `avs_editor.h` call go through
/// `withHandle`, under one lock. The audio tap never takes that lock — it only fills `audio`,
/// which `renderFrame` drains under it.
///
/// Beats come from `AvsBeatDetector`, refined by `AvsBpmRefiner` when advanced beat detection
/// is on: libavs's own AVS_BEAT_INTERNAL is a stub (upstream left beat detection in the Winamp
/// frontend), so the instance runs with AVS_BEAT_EXTERNAL.
final class AvsCore {
    let audio = AvsAudioSlot()
    private let lock = NSLock()
    private let handle: AVS_Handle
    private var beats = AvsBeatDetector()
    private var tempo = AvsBpmRefiner()
    /// libavs only accepts audio whose end time moves forward, so the frames fed so far
    /// stand in for the tap's clock (realtime mode always renders the newest audio anyway).
    private var audioEndSample: Int64 = 0

    /// `resourcePath` is where effects look up image files (Picture, Texer); nil for none.
    init?(resourcePath: String? = nil) {
        let handle = avs_init(resourcePath, AVS_AUDIO_EXTERNAL, AVS_BEAT_EXTERNAL)
        guard handle != 0 else {
            NSLog("AvsCore: avs_init failed: %@", String(cString: avs_error_str(0)))
            return nil
        }
        self.handle = handle
    }

    deinit {
        avs_free(handle)
    }

    /// Runs `body` with exclusive use of the instance. Keep it short: rendering waits on it.
    func withHandle<T>(_ body: (AVS_Handle) throws -> T) rethrows -> T {
        lock.lock()
        defer { lock.unlock() }
        return try body(handle)
    }

    /// Feeds the newest tap audio, then renders one realtime frame into `pixels` (RGB0,
    /// `width` a multiple of 4, `height` a multiple of 2).
    @discardableResult
    func renderFrame(into pixels: UnsafeMutablePointer<UInt32>, width: Int, height: Int) -> Bool {
        withHandle { handle in
            var isBeat = false
            if let buffer = audio.take() {
                isBeat = beats.isBeat(left: buffer.left, right: buffer.right)
                let frames = min(buffer.left.count, buffer.right.count)
                audioEndSample += Int64(frames)
                buffer.left.withUnsafeBufferPointer { left in
                    buffer.right.withUnsafeBufferPointer { right in
                        _ = avs_audio_set(handle, left.baseAddress, right.baseAddress, frames,
                                          Int(buffer.sampleRate), audioEndSample)
                    }
                }
            }
            if AvsPresets.advancedBeatDetection {
                isBeat = tempo.refine(isBeat: isBeat, now: Self.milliseconds())
            }
            return avs_render_frame(handle, pixels, width, height, -1, isBeat, AVS_PIXEL_RGB0_8)
        }
    }

    /// A new song: advanced beat detection learns its tempo afresh, as Winamp's did.
    func resetTempo() {
        withHandle { _ in tempo.reset(now: Self.milliseconds()) }
    }

    /// Uptime in ms, `GetTickCount`'s clock for `AvsBpmRefiner`.
    private static func milliseconds() -> Int {
        Int(DispatchTime.now().uptimeNanoseconds / 1_000_000)
    }

    func loadPreset(at url: URL) -> Bool {
        withHandle { avs_preset_load($0, url.path) }
    }

    /// The instance's most recent error, "" when the last call succeeded.
    var lastError: String {
        withHandle { String(cString: avs_error_str($0)) }
    }
}

/// The Winamp AVS frontend's standard beat detector (upstream `vis_avs/main.cpp` `render()`,
/// BSD-3), on the newest 576 samples as signed 8-bit like Winamp's waveform data: a beat is
/// a summed amplitude 34/32 above a slowly decaying peak, and above a silence floor. The
/// frontend's optional "advanced" BPM refinement is `AvsBpmRefiner`.
struct AvsBeatDetector {
    private static let window = 576
    private var peak1 = 0
    private var peak2 = 0
    private var peak1Peak = 0

    mutating func isBeat(left: [Float], right: [Float]) -> Bool {
        let level = max(Self.amplitude(left), Self.amplitude(right))
        peak1 = (peak1 * 125 + peak2 * 3) / 128
        // Upstream also counts frames since the last beat, but tests the count right after
        // incrementing it, so it never vetoes one; it is left out.
        if level >= (peak1 * 34) / 32 && level > Self.window * 16 {
            peak1 = (level + peak1Peak) / 2
            peak1Peak = level
            return true
        }
        peak2 = level > peak2 ? level : (peak2 * 14) / 16
        return false
    }

    private static func amplitude(_ samples: [Float]) -> Int {
        samples.suffix(window).reduce(0) { $0 + abs(Int(max(-1, min(1, $1)) * 127)) }
    }
}

/// The newest stereo buffer from the audio tap, waiting for the next render. `store` runs on
/// the tap thread (`installTap`, not real-time) and holds the lock for one store; an unrendered
/// buffer is simply replaced.
final class AvsAudioSlot {
    struct Buffer {
        var left: [Float]
        var right: [Float]
        var sampleRate: Double
    }

    private let lock = NSLock()
    private var pending: Buffer?

    func store(_ buffer: Buffer) {
        lock.lock()
        pending = buffer
        lock.unlock()
    }

    func take() -> Buffer? {
        lock.lock()
        defer { lock.unlock() }
        let buffer = pending
        pending = nil
        return buffer
    }
}
