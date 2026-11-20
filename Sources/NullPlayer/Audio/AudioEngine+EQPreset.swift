import Foundation
import NullPlayerCore

extension AudioEngine {
    /// Sets the bands from the classic ten's gains, each clamped to ±12 dB and remapped onto the
    /// engine's band layout: what a skin that thinks in Winamp's ten bands writes (WMP's
    /// `eq.gainLevels`, a preset it picks).
    func setClassicEQ(bands: [Float]) {
        let clamped = bands.map { max(-12, min(12, $0)) }
        let remapped = EQBandRemapper.remap(gains: clamped, from: .classic10, to: eqConfiguration)
        for (band, gain) in remapped.enumerated() { setEQBand(band, gain: gain) }
    }
}

extension EQPreset {
    /// Sets `engine` to this preset: its preamp, clamped to ±12 dB, and its bands, read as the classic
    /// ten (`AudioEngine.setClassicEQ`). For a skin whose script or menu picks a preset by index (WMP's
    /// `eq.currentPreset`); turning the EQ on is the caller's.
    func apply(to engine: AudioEngine) {
        engine.setPreamp(Float(max(-12, min(12, preamp))))
        engine.setClassicEQ(bands: bands)
    }
}
