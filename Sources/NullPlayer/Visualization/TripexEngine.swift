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
final class TripexEngine: NSObject, VisualizationEngine {

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
        super.init()
        self.width = max(1, width)
        self.height = max(1, height)

        guard let handle = TripexCore_create(Int32(self.width), Int32(self.height)) else {
            let startupError = String(cString: TripexCore_lastStartupError())
            NSLog("TripexEngine: TripexCore_create returned NULL: %@", startupError.isEmpty ? "unknown startup error" : startupError)
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
        // A failed frame draws nothing, so the view keeps the last one: log the core's error once
        // per distinct message rather than every frame.
        let result = TripexCore_renderFrame(core)
        drewLastFrame = result == TRIPEX_FRAME_DRAWN
        var error = ""
        if result == TRIPEX_FRAME_ERROR {
            error = TripexCore_lastError(core).map { String(cString: $0) } ?? "?"
        }
        if error != lastRenderError {
            lastRenderError = error
            if !error.isEmpty { NSLog("TripexEngine: frame failed: %@", error) }
        }
    }

    private var lastRenderError = ""
    private(set) var drewLastFrame = true

    // MARK: - Effect navigation

    var presetCount: Int {
        coreLock.lock()
        defer { coreLock.unlock() }
        guard let core else { return 0 }
        return Int(TripexCore_effectCount(core))
    }

    var presetIndex: Int? {
        coreLock.lock()
        defer { coreLock.unlock() }
        guard let core else { return nil }
        let index = Int(TripexCore_currentEffectIndex(core))
        return index >= 0 ? index : nil
    }

    func presetName(at index: Int) -> String {
        coreLock.lock()
        defer { coreLock.unlock() }
        guard let core, let cName = TripexCore_effectName(core, Int32(index)) else { return "" }
        return String(cString: cName)
    }

    func reconfigure()     { withCore { TripexCore_reconfigureEffect($0) } }
    func setHold(_ on: Bool) { withCore { TripexCore_setHold($0, on ? 1 : 0) } }
    func toggleAudioInfo() { withCore { TripexCore_toggleAudioInfo($0) } }
    func toggleHelp()      { withCore { TripexCore_toggleHelp($0) } }

    var intensityScale: Float {
        get {
            coreLock.lock(); defer { coreLock.unlock() }
            guard let core else { return 1.0 }
            return TripexCore_getIntensityScale(core)
        }
        set {
            withCore { TripexCore_setIntensityScale($0, newValue) }
        }
    }

    // Each choice is saved as `lastEffectIndex`, which the engine restores at creation.

    func selectPreset(at index: Int, hardCut: Bool) {
        withCore { TripexCore_selectEffect($0, Int32(index)) }
        savePresetIndex()
    }

    func stepPreset(forward: Bool, hardCut: Bool) {
        withCore { forward ? TripexCore_nextEffect($0) : TripexCore_prevEffect($0) }
        savePresetIndex()
    }

    /// Jumps straight to a random effect. `TripexCore_changeEffect` cannot: it starts a crossfade,
    /// and the hold every host sets (`setHold(true)`) cancels the fade each frame
    /// (`Tripex.cpp` `TXS_HOLD`), so R left the effect where it was.
    func randomPreset(hardCut: Bool) {
        let count = presetCount
        guard count > 1 else { return }
        let current = presetIndex
        var index: Int
        repeat { index = Int.random(in: 0..<count) } while index == current
        selectPreset(at: index, hardCut: hardCut)
    }

    private func savePresetIndex() {
        guard let index = presetIndex else { return }
        UserDefaults.standard.set(index, forKey: DefaultsKey.lastEffectIndex)
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
        static let intensityScale    = "tripex.intensityScale"
    }
}
