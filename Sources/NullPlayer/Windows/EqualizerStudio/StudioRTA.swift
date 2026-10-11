import Accelerate
import Foundation

/// The Studio's per-channel analyser: the 31 ISO ⅓-octave bands of each channel, in dBFS.
///
/// Reads the full-rate stereo feed (`.audioStereoPCMFullDataUpdated`, both pipelines), consumer-gated
/// while the Studio is open. Threading as `WinampModernAnalyzerTap`: the observer runs on the tap
/// thread (`queue: nil`) and only hands the buffer to a serial queue, which keeps an 8192-sample ring
/// per channel (≈5 Hz bins, so the 20–80 Hz bands resolve) and runs a Hann-windowed real FFT; the
/// main thread only receives finished levels. Not shared with that file: it sums to mono and belongs
/// to the `.wal` family.
///
/// Where the feed sits differs by pipeline — local is pre-profile, streaming is the output — so the
/// view, not this, decides what to add on top.
final class StudioRTA {
    static let fftSize = 8192
    private static let log2n = vDSP_Length(13)
    /// Display floor, dBFS.
    static let floorDB: Float = -96

    /// Levels and held peaks per channel, 31 each, on the main thread.
    var onUpdate: ((_ levels: [[Float]], _ peaks: [[Float]]) -> Void)?

    private let consumerId = "equalizerStudio"
    private let queue = DispatchQueue(label: "NullPlayer.StudioRTA", qos: .userInitiated)
    private var observer: NSObjectProtocol?

    // Owned by `queue`.
    private var rings = [[Float]](repeating: [Float](repeating: 0, count: fftSize), count: 2)
    private var writeIndex = 0
    private var levels = [[Float]](repeating: [Float](repeating: floorDB, count: EQProfileDesign.bandCount), count: 2)
    private var peaks = [[Float]](repeating: [Float](repeating: floorDB, count: EQProfileDesign.bandCount), count: 2)
    private var peakAge = [[Double]](repeating: [Double](repeating: 0, count: EQProfileDesign.bandCount), count: 2)
    private let hann: [Float] = {
        var w = [Float](repeating: 0, count: fftSize)
        vDSP_hann_window(&w, vDSP_Length(fftSize), Int32(vDSP_HANN_NORM))
        return w
    }()
    private let setup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2))

    deinit {
        stop()
        if let setup { vDSP_destroy_fftsetup(setup) }
    }

    func start() {
        guard observer == nil else { return }
        WindowManager.shared.audioEngine.addFullStereoConsumer(consumerId)
        // Never `queue: .main` — this is posted from the audio tap thread (audio-system skill).
        observer = NotificationCenter.default.addObserver(
            forName: .audioStereoPCMFullDataUpdated, object: nil, queue: nil
        ) { [weak self] note in
            guard let left = note.userInfo?["left"] as? [Float],
                  let right = note.userInfo?["right"] as? [Float],
                  let rate = note.userInfo?["sampleRate"] as? Double, rate > 0 else { return }
            self?.queue.async { self?.ingest(left: left, right: right, sampleRate: rate) }
        }
    }

    func stop() {
        guard let observer else { return }
        NotificationCenter.default.removeObserver(observer)
        self.observer = nil
        WindowManager.shared.audioEngine.removeFullStereoConsumer(consumerId)
    }

    private func ingest(left: [Float], right: [Float], sampleRate: Double) {
        let count = min(left.count, right.count, Self.fftSize)
        guard count > 0, let setup else { return }
        for i in 0..<count {
            rings[0][writeIndex] = left[i]
            rings[1][writeIndex] = right[i]
            writeIndex = (writeIndex + 1) % Self.fftSize
        }
        let elapsed = Double(count) / sampleRate
        let n = Self.fftSize
        // Power reference: a full-scale sine's Hann main lobe (centre bin N/4, neighbours half that).
        let reference = 1.5 * pow(Double(n) / 4, 2)
        let binHz = sampleRate / Double(n)
        var linear = [Float](repeating: 0, count: n)
        var real = [Float](repeating: 0, count: n / 2)
        var imag = [Float](repeating: 0, count: n / 2)
        var power = [Float](repeating: 0, count: n / 2)
        for channel in 0..<2 {
            // Oldest sample first.
            let tail = n - writeIndex
            linear.withUnsafeMutableBufferPointer { out in
                rings[channel].withUnsafeBufferPointer { ring in
                    out.baseAddress!.update(from: ring.baseAddress! + writeIndex, count: tail)
                    (out.baseAddress! + tail).update(from: ring.baseAddress!, count: writeIndex)
                }
            }
            linear.withUnsafeMutableBufferPointer {
                vDSP_vmul($0.baseAddress!, 1, hann, 1, $0.baseAddress!, 1, vDSP_Length(n))
            }
            real.withUnsafeMutableBufferPointer { re in
                imag.withUnsafeMutableBufferPointer { im in
                    var split = DSPSplitComplex(realp: re.baseAddress!, imagp: im.baseAddress!)
                    linear.withUnsafeBytes {
                        vDSP_ctoz($0.bindMemory(to: DSPComplex.self).baseAddress!, 2, &split, 1, vDSP_Length(n / 2))
                    }
                    vDSP_fft_zrip(setup, &split, 1, Self.log2n, FFTDirection(FFT_FORWARD))
                    // zrip returns twice the DFT, so each bin's power is a quarter of this.
                    vDSP_zvmags(&split, 1, &power, 1, vDSP_Length(n / 2))
                }
            }
            power[0] = 0 // DC and Nyquist share bin 0
            for band in 0..<EQProfileDesign.bandCount {
                let centre = EQProfileDesign.frequencies[band]
                let lo = Int((centre * pow(2, -1.0 / 6) / binHz).rounded(.up))
                let hi = Int((centre * pow(2, 1.0 / 6) / binHz).rounded(.down))
                var sum = 0.0
                if lo <= hi, lo >= 1, hi < n / 2 {
                    for k in lo...hi { sum += Double(power[k]) }
                } else {
                    let nearest = min(n / 2 - 1, max(1, Int((centre / binHz).rounded())))
                    sum = Double(power[nearest])
                }
                let db = Float(max(Double(Self.floorDB), 10 * log10(max(sum / 4 / reference, 1e-20))))
                // Fast attack, 24 dB/s release; peaks hold 1.5 s, then fall at 12 dB/s.
                levels[channel][band] = max(db, levels[channel][band] - Float(24 * elapsed))
                if db >= peaks[channel][band] {
                    peaks[channel][band] = db
                    peakAge[channel][band] = 0
                } else {
                    peakAge[channel][band] += elapsed
                    if peakAge[channel][band] > 1.5 {
                        peaks[channel][band] = max(levels[channel][band], peaks[channel][band] - Float(12 * elapsed))
                    }
                }
            }
        }
        let levels = levels, peaks = peaks
        DispatchQueue.main.async { [weak self] in self?.onUpdate?(levels, peaks) }
    }
}
