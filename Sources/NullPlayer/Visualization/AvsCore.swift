import Foundation
import CAvsCore

/// One libavs instance: Advanced Visualization Studio, vendored as `CAvsCore` (see the
/// `avs-port` skill).
///
/// Threading: libavs is not thread-safe. Rendering and every `avs_editor.h` call go through
/// `withHandle`, under one lock. The audio tap never takes that lock — it only fills `audio`
/// and `beats`, which `renderFrame` drains under it.
///
/// Beats come from `beats`, fed by Winamp's standard detector or, with advanced beat detection
/// on, by aubio's beat tracker (`BPMDetector`): libavs's own AVS_BEAT_INTERNAL is a stub
/// (upstream left beat detection in the Winamp frontend), so the instance runs with
/// AVS_BEAT_EXTERNAL.
final class AvsCore {
    let audio = AvsAudioSlot()
    let beats = BeatFeed()
    private let lock = NSLock()
    private let handle: AVS_Handle
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
    /// `width` a multiple of 4, `height` a multiple of 2) at `nowMs`, the clock `beats` are
    /// released by.
    @discardableResult
    func renderFrame(into pixels: UnsafeMutablePointer<UInt32>, width: Int, height: Int,
                     nowMs: Int = BeatFeed.milliseconds()) -> Bool {
        withHandle { handle in
            let isBeat = beats.take(nowMs: nowMs)
            #if DEBUG
            // `AVS_BEAT_TRACE`: every frame with a beat.
            if Self.tracesBeats, isBeat {
                NSLog("AVS-BEAT t=%ld", nowMs)
            }
            #endif
            if let buffer = audio.take() {
                let frames = min(buffer.left.count, buffer.right.count)
                audioEndSample += Int64(frames)
                buffer.left.withUnsafeBufferPointer { left in
                    buffer.right.withUnsafeBufferPointer { right in
                        _ = avs_audio_set(handle, left.baseAddress, right.baseAddress, frames,
                                          Int(buffer.sampleRate), audioEndSample)
                    }
                }
            }
            return avs_render_frame(handle, pixels, width, height, -1, isBeat, AVS_PIXEL_RGB0_8)
        }
    }

    #if DEBUG
    private static let tracesBeats = ProcessInfo.processInfo.environment["AVS_BEAT_TRACE"] != nil
    #endif

    func loadPreset(at url: URL) -> Bool {
        withHandle { avs_preset_load($0, url.path) }
    }

    /// The instance's most recent error, "" when the last call succeeded.
    var lastError: String {
        withHandle { String(cString: avs_error_str($0)) }
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
