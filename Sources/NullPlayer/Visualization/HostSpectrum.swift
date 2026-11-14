import Accelerate
import Foundation

/// Winamp-compatible host spectrum for the engines that read one (`consumesHostSpectrum`: Geiss,
/// Corona, Smear, Fractal): 256 bins from a 512-sample real FFT. Called from the audio thread;
/// its own lock serialises the shared FFT buffers.
final class HostSpectrum: @unchecked Sendable {  // `lock` guards every buffer
    private static let binCount = 256

    private static let fftSize = 512
    private static let log2N = vDSP_Length(9)
    private static let scale: Float = 2.0 / 512.0

    private let setup: FFTSetup?
    private var window = [Float](repeating: 0, count: HostSpectrum.fftSize)
    private var input = [Float](repeating: 0, count: HostSpectrum.fftSize)
    private var real = [Float](repeating: 0, count: HostSpectrum.binCount)
    private var imag = [Float](repeating: 0, count: HostSpectrum.binCount)
    private var bins = [Float](repeating: 0, count: HostSpectrum.binCount)
    private let lock = NSLock()

    init() {
        setup = vDSP_create_fftsetup(Self.log2N, FFTRadix(kFFTRadix2))
        vDSP_hann_window(&window, vDSP_Length(Self.fftSize), Int32(vDSP_HANN_DENORM))
    }

    deinit {
        if let setup { vDSP_destroy_fftsetup(setup) }
    }

    /// Computes the bins from `pcm` scaled by `gain`, and hands them to `body` while they are still
    /// locked against the next audio callback. Lock order: this lock, then whatever `body` takes —
    /// `VisualizationGLView` takes `dataLock`, then only *tries* `engineLock`, so the audio thread
    /// never waits on a render. `body` must not block.
    func compute(from pcm: [Float], gain: Float, _ body: ([Float]) -> Void) {
        guard let setup else { return }
        lock.lock()
        defer { lock.unlock() }

        let copied = min(pcm.count, Self.fftSize)
        for i in 0..<copied {
            let sample = max(-1.0, min(1.0, pcm[i] * gain))
            input[i] = sample * window[i]
        }
        for i in copied..<Self.fftSize {
            input[i] = 0
        }

        input.withUnsafeBufferPointer { inputPtr in
            inputPtr.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: Self.binCount) { complexPtr in
                real.withUnsafeMutableBufferPointer { realPtr in
                    imag.withUnsafeMutableBufferPointer { imagPtr in
                        var split = DSPSplitComplex(realp: realPtr.baseAddress!, imagp: imagPtr.baseAddress!)
                        vDSP_ctoz(complexPtr, 2, &split, 1, vDSP_Length(Self.binCount))
                        vDSP_fft_zrip(setup, &split, 1, Self.log2N, FFTDirection(FFT_FORWARD))
                        vDSP_zvabs(&split, 1, &bins, 1, vDSP_Length(Self.binCount))
                    }
                }
            }
        }

        // Convert the FFT's linear magnitudes into Winamp-style normalized bins.
        // The square-root curve keeps quiet treble visible without clipping bass hits.
        for i in 0..<Self.binCount {
            bins[i] = sqrtf(min(1.0, max(0.0, bins[i] * Self.scale)))
        }
        body(bins)
    }
}
