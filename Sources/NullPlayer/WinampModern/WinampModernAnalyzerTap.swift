import Accelerate
import CoreGraphics
import Foundation

/// The spectrum a `.wal` skin's `<vis mode="1">` analyzer draws — NullPlayer's **own** FFT over the
/// full-precision stereo PCM tap, not the host's cooked display bands (B73).
///
/// **Why this exists.** `host.spectrumLevels` is a *display* array, not an analysis result:
/// `AudioEngine` has already taken `20·log10` of its bins, normalised them, clamped them and
/// smoothed them before any skin sees them. Measured live (`WINAMP_MODERN_VIS_TRACE=1`) that came
/// out as **52 of 75 bands at exactly 1.0** on a loud frame, mean 0.98 — one fact that explains
/// every remaining analyzer defect at once: the flat bass, the missing dynamic range, and B54's
/// white line across the bar tops (a peak-hold over clipped data can only ever draw a flat line,
/// because every band's cap latches to the identical 1.0). It also made the look of every `.wal`
/// skin depend on `spectrumNormalizationMode` — a preference owned by a different window's context
/// menu, which silently changed the analyzer twice in one session.
///
/// **The input is `.audioStereoPCMFullDataUpdated`** — 2048 `Float` per channel plus `sampleRate`,
/// consumer-gated by `addFullStereoConsumer`/`removeFullStereoConsumer`, the same tap Cava reads.
/// Deliberately *not* B51's 576-sample `UInt8` visdata tap that the oscilloscope uses: 8-bit
/// quantisation caps the usable range near 48 dB, and 576 samples give ~86 Hz bins, which cannot
/// resolve bass at all. 2048 samples at full precision give ~21 Hz bins.
///
/// **Three threads, and none of the work is on two of them.** Read `WinampModernWaveformTap`'s doc
/// comment first for the real-time rules; these are the ones specific to this tap.
///
/// - The **audio thread** (`queue: nil`, the posting thread) does a lock, two array retains and an
///   unlock. Never `queue: .main`, never `DispatchQueue.main.sync`, and **never the FFT** — that is
///   what turns a real-time tap into a dropout.
/// - The **processing queue**, a serial `.userInteractive` queue of this tap's own, runs the FFT and
///   publishes the half-spectrum. It always analyses the *newest* buffer: if one arrives while it is
///   busy, the older one is dropped rather than queued, so the bars can never fall behind the sound.
/// - The **main thread** only ever maps that published half-spectrum onto the band count a box asked
///   for — a max per band and a logarithm, the same arithmetic the analyzer already did per draw.
///   No FFT, no allocation beyond the band array, no waiting on the audio: with nothing analysed yet
///   it gets no bands rather than blocking.
///
/// The mapping is memoized against the analysis counter, so several `<vis>` boxes in one frame (Big
/// Bento's butterfly is four) all draw the same spectrum — exactly as the waveform tap guarantees
/// for the scope — and per band *count* on top of that, because one skin can draw a 19-band `<vis>`
/// and a wide `{0000000A}` holder in the same frame.
///
/// **Silence has to reach the bars.** The tap stops posting on pause, stop, end of track or a move
/// to a cast device, so past `silenceTimeout` the read answers all-zero bands and the bars fall to
/// the floor instead of freezing where the music left them. Before the *first* buffer ever arrives
/// it answers no bands at all, which is what tells the analyzer not to draw yet.
final class WinampModernAnalyzerTap {
    private let consumerId: String
    private let processingQueue: DispatchQueue
    private var observer: NSObjectProtocol?
    private var running = false

    /// The newest buffer waiting to be analysed, and the newest analysis. Written on the posting
    /// thread and the processing queue, read on the main thread, all under `lock`.
    ///
    /// **Latest-value, not a queue** — the opposite of `WinampModernWaveformTap`, and for a reason
    /// specific to what each one draws. A scope draws the *waveform itself*, so a discarded chunk is
    /// audio the user can see missing. An analyzer draws a spectrum, which barely moves across one
    /// 46 ms buffer; showing the newest is showing the music, and holding a backlog would only make
    /// the bars lag the sound.
    private var pending: (left: [Float], right: [Float], sampleRate: Double)?
    private var analyzing = false
    /// The published half-spectrum: linear magnitudes, one per FFT bin, 0 dBFS at 1.0.
    private var spectrum: [Float] = []
    private var spectrumSampleRate: Double = 44_100
    /// Bumped every time `spectrum` is replaced — the key the main thread's band cache hangs on.
    private var generation: UInt64 = 0
    private var lastArrival: TimeInterval?
    private let lock = NSLock()

    /// How long the last buffer is honoured after the posts stop before the analyzer reads silence.
    /// The same window the VU meter and the scope hold theirs for, for the same reason: long enough
    /// to ride out the jitter between two taps, short enough that a paused track falls immediately.
    static let silenceTimeout = WinampModernLevelMeter.silenceTimeout

    /// The analysis window. `AudioEngine` posts exactly this many frames per channel.
    static let fftSize = 2048
    private static let log2n = vDSP_Length(11)

    // MARK: - The one dB mapping
    //
    // This replaces the band scaling at **both** analyzer sites — `WasabiBuiltInVisRenderer`'s
    // `<vis>` analyzer and `WasabiRenderer.drawVisualizationBars`' `{0000000A}` holder — so the two
    // can never read the same audio at different heights again. Tuned by eye against unclipped
    // input; there is no reference to match, only Winamp's look.

    /// The band level that fills the box, in dBFS — **not** 0 dBFS, and that distinction is the
    /// whole calibration. A single FFT band of a mix mastered to full scale sits some 30 dB below
    /// full scale, because the energy is spread across the spectrum; mapping against 0 dBFS made the
    /// top third of the box unreachable by construction. Measured on a loud frame with the window
    /// referenced at 0: bands peaked at 0.52-0.64, i.e. about -31 dBFS.
    static let fullScaleBandDB: Float = -30
    /// How far below `fullScaleBandDB` the floor sits. Narrow enough that a near-silent passage
    /// still reads as near-silent — at 60 dB the room tone measured before playback started would
    /// have drawn a third of the way up the box — and wide enough that ordinary music has somewhere
    /// to move, which the host tap's 20 dB `.accurate` clamp never gave it.
    static let windowDB: Float = 45
    /// How much a band is lifted per octave above `weightingReferenceHz`, and cut below it.
    ///
    /// Music is roughly pink — its energy falls about 3 dB per octave — so an unweighted analyzer is
    /// a wall of bass with nothing to the right of it. This is the frequency weighting the host
    /// tap's `.accurate` path never applied at all.
    static let weightingDBPerOctave: Float = 3.0
    static let weightingReferenceHz: Float = 1_000
    /// The band edges. Below 20 Hz is inaudible and the top of the range is the CD ceiling; a lower
    /// sample rate narrows it to its own Nyquist.
    static let lowestBandHz: Float = 20
    static let highestBandHz: Float = 20_000

    /// vDSP's setup and scratch. **Owned by `processingQueue` alone** — that is what lets them be
    /// allocated once and reused rather than built per buffer, with no lock in the FFT itself.
    private var fftSetup: FFTSetup?
    private var windowed = [Float](repeating: 0, count: WinampModernAnalyzerTap.fftSize)
    private var hann = [Float](repeating: 0, count: WinampModernAnalyzerTap.fftSize)
    private var realp = [Float](repeating: 0, count: WinampModernAnalyzerTap.fftSize / 2)
    private var imagp = [Float](repeating: 0, count: WinampModernAnalyzerTap.fftSize / 2)
    private var magnitudes = [Float](repeating: 0, count: WinampModernAnalyzerTap.fftSize / 2)

    /// The analysis the cached bands were mapped from, and the bands themselves per requested count.
    /// Main thread only, dropped together when a newer analysis is published.
    private var mappedGeneration: UInt64 = 0
    private var mappedSpectrum: [Float] = []
    private var mappedSampleRate: Double = 44_100
    private var bandCache: [Int: [CGFloat]] = [:]

    init(consumerId: String) {
        self.consumerId = consumerId
        self.processingQueue = DispatchQueue(
            label: "com.nullplayer.winampmodern.analyzer.\(consumerId)", qos: .userInteractive)
        vDSP_hann_window(&hann, vDSP_Length(Self.fftSize), Int32(vDSP_HANN_DENORM))
    }

    deinit {
        stop()
        if let fftSetup { vDSP_destroy_fftsetup(fftSetup) }
    }

    // MARK: - Reading, on the main thread

    /// `count` band levels, 0…1, lowest frequency first — or an empty array while nothing has been
    /// analysed yet, which is what tells the analyzer not to draw.
    func bands(count: Int) -> [CGFloat] {
        bands(count: count, at: ProcessInfo.processInfo.systemUptime)
    }

    /// Separated from the clock so the silence decay can be exercised without waiting for real time.
    func bands(count: Int, at now: TimeInterval) -> [CGFloat] {
        guard count > 0 else { return [] }
        lock.lock()
        let arrival = lastArrival
        let currentGeneration = generation
        // The half-spectrum is copied out only when it is newer than the one already mapped: a
        // second box in the same frame answers from `bandCache` without touching the lock's payload.
        let isNew = currentGeneration != mappedGeneration
        let published = isNew ? spectrum : []
        let rate = isNew ? spectrumSampleRate : mappedSampleRate
        lock.unlock()

        guard let arrival else { return [] }
        guard now - arrival < Self.silenceTimeout else {
            return [CGFloat](repeating: 0, count: count)
        }
        if isNew {
            mappedGeneration = currentGeneration
            mappedSpectrum = published
            mappedSampleRate = rate
            bandCache.removeAll(keepingCapacity: true)
        }
        guard !mappedSpectrum.isEmpty else { return [] }
        if let cached = bandCache[count] { return cached }
        let mapped = mapBands(count: count)
        bandCache[count] = mapped
        return mapped
    }

    private func mapBands(count: Int) -> [CGFloat] {
        Self.bands(count: count, spectrum: mappedSpectrum, sampleRate: mappedSampleRate)
    }

    /// The published magnitudes collapsed onto `count` **log-spaced** bands and mapped to box
    /// fractions.
    ///
    /// Log-spaced because that is what a spectrum analyzer is: linear bins put eight of every ten
    /// bars above 5 kHz, where music has almost nothing, and squeeze the entire bass range the
    /// listener actually hears into the first bar.
    ///
    /// Static and pure: this is the whole of B73's calibration — the log spacing, the frequency
    /// weighting and the dB window — and it is what a test can pin without an audio engine.
    static func bands(count: Int, spectrum: [Float], sampleRate: Double) -> [CGFloat] {
        guard count > 0 else { return [] }
        let mappedSpectrum = spectrum
        let bins = mappedSpectrum.count
        let rate = Float(sampleRate > 0 ? sampleRate : 44_100)
        let binWidth = rate / Float(Self.fftSize)
        let top = min(Self.highestBandHz, rate / 2)
        guard bins > 1, top > Self.lowestBandHz, binWidth > 0 else {
            return [CGFloat](repeating: 0, count: count)
        }
        let ratio = top / Self.lowestBandHz
        var result = [CGFloat](repeating: 0, count: count)
        for band in 0..<count {
            let lowHz = Self.lowestBandHz * powf(ratio, Float(band) / Float(count))
            let highHz = Self.lowestBandHz * powf(ratio, Float(band + 1) / Float(count))
            // At 21.5 Hz bins the lowest bands are narrower than one bin, so several of them read
            // the same bin — which is correct, and is what Winamp's own low end does.
            let firstBin = max(1, min(bins - 1, Int(lowHz / binWidth)))
            let lastBin = max(firstBin + 1, min(bins, Int(highHz / binWidth) + 1))
            var peak: Float = 0
            for bin in firstBin..<lastBin { peak = max(peak, mappedSpectrum[bin]) }
            guard peak > 0 else { continue }
            let centreHz = sqrtf(lowHz * highHz)
            let weighting = Self.weightingDBPerOctave
                * log2f(max(1, centreHz) / Self.weightingReferenceHz)
            let dB = 20 * log10f(peak) + weighting
            let above = dB - Self.fullScaleBandDB + Self.windowDB
            result[band] = CGFloat(max(0, min(1, above / Self.windowDB)))
        }
        return result
    }

    // MARK: - The tap

    func start() {
        guard !running else { return }
        running = true
        WindowManager.shared.audioEngine.addFullStereoConsumer(consumerId)
        // `queue: nil` — received and stored on the posting thread. See the class comment: the
        // observer body is a lock, two retains and an unlock, and the FFT is somewhere else.
        observer = NotificationCenter.default.addObserver(
            forName: .audioStereoPCMFullDataUpdated, object: nil, queue: nil
        ) { [weak self] note in
            guard let self else { return }
            let left = note.userInfo?["left"] as? [Float]
            let right = note.userInfo?["right"] as? [Float]
            guard left != nil || right != nil else { return }
            self.receive(left: left ?? [], right: right ?? [],
                         sampleRate: note.userInfo?["sampleRate"] as? Double,
                         at: ProcessInfo.processInfo.systemUptime)
        }
    }

    /// Store one arriving buffer and wake the processing queue if it is idle. Runs on the **posting
    /// thread** — the real-time audio tap — so it is a lock, three stores and an unlock.
    func receive(left: [Float], right: [Float], sampleRate: Double?, at now: TimeInterval) {
        lock.lock()
        pending = (left, right.isEmpty ? left : right,
                   (sampleRate.map { $0 > 0 ? $0 : spectrumSampleRate }) ?? spectrumSampleRate)
        lastArrival = now
        // One analysis in flight at a time. A buffer that arrives while the queue is busy simply
        // replaces `pending`, so the FFT always runs on the newest audio and a slow frame costs a
        // dropped analysis rather than a growing backlog.
        let idle = !analyzing && running
        if idle { analyzing = true }
        lock.unlock()
        guard idle else { return }
        processingQueue.async { [weak self] in self?.drainPending() }
    }

    /// Analyse buffers until none is waiting. **Processing queue only.**
    private func drainPending() {
        while true {
            lock.lock()
            guard running, let buffer = pending else {
                analyzing = false
                lock.unlock()
                return
            }
            pending = nil
            lock.unlock()

            guard let result = analyze(left: buffer.left, right: buffer.right) else { continue }
            lock.lock()
            spectrum = result
            spectrumSampleRate = buffer.sampleRate
            generation &+= 1
            lock.unlock()
        }
    }

    /// One real FFT over the mono sum of a buffer, as linear magnitudes. **Processing queue only** —
    /// every scratch buffer it touches is owned by that queue.
    private func analyze(left: [Float], right: [Float]) -> [Float]? {
        guard let setup = fftSetup ?? {
            fftSetup = vDSP_create_fftsetup(Self.log2n, FFTRadix(kFFTRadix2))
            return fftSetup
        }() else { return nil }
        let available = max(left.count, right.count)
        guard available > 0 else { return nil }

        // Mono sum, zero-padded when a source hands over a short buffer (the streaming player
        // forwards whatever its decoder produced). Padding is why the window is applied afterwards:
        // it must taper the *analysis frame*, not the audio inside it.
        let n = min(available, Self.fftSize)
        for index in 0..<n {
            let l = index < left.count ? left[index] : 0
            let r = index < right.count ? right[index] : l
            windowed[index] = (l + r) * 0.5
        }
        if n < Self.fftSize {
            for index in n..<Self.fftSize { windowed[index] = 0 }
        }
        vDSP_vmul(windowed, 1, hann, 1, &windowed, 1, vDSP_Length(Self.fftSize))

        let half = Self.fftSize / 2
        realp.withUnsafeMutableBufferPointer { realPointer in
            imagp.withUnsafeMutableBufferPointer { imagPointer in
                var split = DSPSplitComplex(realp: realPointer.baseAddress!,
                                            imagp: imagPointer.baseAddress!)
                windowed.withUnsafeBufferPointer { input in
                    input.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: half) {
                        vDSP_ctoz($0, 2, &split, 1, vDSP_Length(half))
                    }
                }
                vDSP_fft_zrip(setup, &split, 1, Self.log2n, FFTDirection(FFT_FORWARD))
                vDSP_zvabs(&split, 1, &magnitudes, 1, vDSP_Length(half))
            }
        }
        // `vDSP_fft_zrip` leaves every term scaled by 2, and a Hann window has a coherent gain of
        // 0.5, so the two together are `2 / fftSize` — a full-scale sine comes out at 1.0, which is
        // what makes 0 dB mean 0 dBFS in `mapBands`.
        var scale = Float(2) / Float(Self.fftSize)
        vDSP_vsmul(magnitudes, 1, &scale, &magnitudes, 1, vDSP_Length(half))
        return magnitudes
    }

    func stop() {
        guard running else { return }
        running = false
        if let observer { NotificationCenter.default.removeObserver(observer) }
        observer = nil
        WindowManager.shared.audioEngine.removeFullStereoConsumer(consumerId)
        lock.lock()
        pending = nil
        spectrum = []
        lastArrival = nil
        generation &+= 1
        let stopped = generation
        lock.unlock()
        mappedGeneration = stopped
        mappedSpectrum = []
        bandCache.removeAll(keepingCapacity: false)
    }
}
