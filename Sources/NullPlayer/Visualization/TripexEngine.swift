import Foundation
import OpenGL.GL3
import CTripexCore

/// Tripex visualization engine — Winamp-era 3D effects (ben-marsh/tripex)
/// ported to OpenGL 3.2 core via the CTripexCore SwiftPM target.
///
/// PCM flow: NullPlayer's audio pump pushes float mono samples; we convert
/// to interleaved int16 stereo @ 44.1 kHz (Tripex's `AudioSource` contract)
/// and forward to the ring buffer in `HostAudioSource`. Tripex runs its
/// own FFT (upstream/Fourier.cpp), so no spectrum is supplied.
final class TripexEngine: VisualizationEngine {

    // MARK: - VisualizationEngine

    private(set) var isAvailable: Bool = false
    let displayName: String = "Tripex"

    // MARK: - State

    /// Serializes access to the C handle. CTripexCore already has its own
    /// mutex per handle; this lock guards Swift-side state (handle pointer,
    /// width/height, pcmScratch).
    private let coreLock = NSLock()

    private var core: OpaquePointer?
    private var width: Int = 0
    private var height: Int = 0

    /// Scratch buffer for float→int16 stereo conversion; reused across
    /// addPCMMono calls to avoid per-frame allocation.
    private var pcmScratch: [Int16] = []

    // MARK: - Init / cleanup

    init(width: Int, height: Int) {
        self.width = max(1, width)
        self.height = max(1, height)

        guard let handle = TripexCore_create(Int32(self.width), Int32(self.height)) else {
            NSLog("TripexEngine: TripexCore_create failed")
            return
        }
        self.core = handle
        self.isAvailable = true
        NSLog("TripexEngine: initialized %dx%d, %d effects", self.width, self.height, Int(TripexCore_effectCount(handle)))
    }

    deinit { cleanup() }

    func cleanup() {
        coreLock.lock()
        defer { coreLock.unlock() }
        if let core {
            TripexCore_destroy(core)
            self.core = nil
        }
        isAvailable = false
    }

    // MARK: - VisualizationEngine API

    func setViewportSize(width: Int, height: Int) {
        let newW = max(1, width)
        let newH = max(1, height)
        coreLock.lock()
        defer { coreLock.unlock() }
        guard newW != self.width || newH != self.height else { return }
        self.width = newW
        self.height = newH
        if let core { TripexCore_resize(core, Int32(newW), Int32(newH)) }
    }

    func addPCMMono(_ samples: [Float]) {
        coreLock.lock()
        defer { coreLock.unlock() }
        guard let core, !samples.isEmpty else { return }

        // Float mono [-1, 1] → interleaved int16 stereo. Tripex consumes
        // PCM via AudioSource::Read; the per-frame byte count depends on
        // the effect, but practical Tripex effects need <4 KB per frame.
        let stereoCount = samples.count * 2
        if pcmScratch.count != stereoCount {
            pcmScratch = Array(repeating: 0, count: stereoCount)
        }
        for i in 0..<samples.count {
            let clamped = max(-1.0, min(1.0, samples[i]))
            let s = Int16(clamped * 32767.0)
            pcmScratch[2 * i]     = s
            pcmScratch[2 * i + 1] = s
        }
        pcmScratch.withUnsafeBufferPointer { ptr in
            TripexCore_pushPCM(core, ptr.baseAddress, stereoCount)
        }
    }

    func renderFrame() {
        coreLock.lock()
        defer { coreLock.unlock() }
        guard isAvailable, let core else { return }
        _ = TripexCore_renderFrame(core)
    }

    // MARK: - Effect navigation (used by TripexMenuBuilder in Chunk 7)

    var effectCount: Int {
        coreLock.lock()
        defer { coreLock.unlock() }
        guard let core else { return 0 }
        return Int(TripexCore_effectCount(core))
    }

    var currentEffectIndex: Int {
        coreLock.lock()
        defer { coreLock.unlock() }
        guard let core else { return -1 }
        return Int(TripexCore_currentEffectIndex(core))
    }

    func effectName(at index: Int) -> String {
        coreLock.lock()
        defer { coreLock.unlock() }
        guard let core, let cName = TripexCore_effectName(core, Int32(index)) else { return "" }
        return String(cString: cName)
    }

    func nextEffect()      { withCore { TripexCore_nextEffect($0) } }
    func previousEffect()  { withCore { TripexCore_prevEffect($0) } }
    func randomEffect()    { withCore { TripexCore_changeEffect($0) } }
    func reconfigure()     { withCore { TripexCore_reconfigureEffect($0) } }
    func toggleHold()      { withCore { TripexCore_toggleHoldingEffect($0) } }
    func toggleAudioInfo() { withCore { TripexCore_toggleAudioInfo($0) } }
    func toggleHelp()      { withCore { TripexCore_toggleHelp($0) } }

    func selectEffect(at index: Int) {
        withCore { TripexCore_selectEffect($0, Int32(index)) }
    }

    private func withCore(_ body: (OpaquePointer) -> Void) {
        coreLock.lock()
        defer { coreLock.unlock() }
        guard let core else { return }
        body(core)
    }
}

// MARK: - Persistence (UserDefaults keys, Chunk 6 subset)

extension TripexEngine {
    enum DefaultsKey {
        static let lastEffectIndex   = "tripex.lastEffectIndex"
        static let lockedEffectIndex = "tripex.lockedEffectIndex"
    }
}
