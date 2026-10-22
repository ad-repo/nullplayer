import AppKit
import CoreGraphics
import Foundation

/// The equalizer as the scripts were last told it: bands and preamp on MAKI's −127…127 scale, and the
/// two switches the skin's EQ buttons mirror.
struct WinampModernAnnouncedEqualizer {
    /// `nil` before the first observation, which is what makes the opening state an announcement
    /// rather than silence.
    private(set) var bands: [Int]?
    private(set) var preamp: Int?
    /// `nil` before the first observation, which is *not* announced: the buttons load in step.
    private var switches: (enabled: Bool, auto: Bool)?

    /// Records the switches and answers whether they moved since the last observation.
    mutating func announce(switches: (enabled: Bool, auto: Bool)) -> Bool {
        defer { self.switches = switches }
        guard let previous = self.switches else { return false }
        return previous != switches
    }

    /// Records the new values and answers the previous ones, or nil when nothing moved.
    mutating func announce(bands: [Int], preamp: Int) -> (bands: [Int]?, preamp: Int?)? {
        guard self.bands != bands || self.preamp != preamp else { return nil }
        defer { (self.bands, self.preamp) = (bands, preamp) }
        return (self.bands, self.preamp)
    }
}

/// The equalizer event funnel: host EQ state into `onEqBandChanged`/`onEqPreampChanged` and the
/// skin's EQ sliders. Split out of
/// `WinampModernScriptRuntime.swift`.
extension WinampModernScriptRuntime {
    /// Test seam: what the scripts were last told the equalizer was.
    var lastDispatchedEqualizerForTesting: (bands: [Int]?, preamp: Int?) {
        (announcedEqualizer.bands, announcedEqualizer.preamp)
    }

    /// Raise `onEqBandChanged(band, value)` / `onEqPreampChanged(value)` for whatever moved, and put
    /// the skin's own EQ sliders on the new value first.
    ///
    /// Winamp raises these whenever the equalizer moves, *whoever* moved it — a preset, the menu bar,
    /// another window, the skin's own slider — and a skin's readout is written from nowhere else.
    /// multipass's eleven `ledfillbar` bars are the measured case: each one re-reads its
    /// `parentslider`'s position from this handler, which is why the slider positions are synced
    /// **before** the events go out. Rika and winampmodern566 use the value itself (Rika slices a
    /// region map at `128 - value`), so it must be the same −127…127 scale `getEqBand` answers in.
    ///
    /// One funnel for every route, and it dispatches only on an actual change: `System.setEqBand`
    /// comes through here too, so a skin that sets a band from its own handler cannot be told about
    /// its own write twice, and a poll costs eleven integer compares.
    func refreshEqualizerState() {
        guard !isTornDown else { return }
        syncEqualizerSwitches()
        guard let bandValue = hooks.equalizerBandRequested else { return }
        let bands = (0..<WinampModernEQAction.bandCount).map { bandValue($0) }
        let preamp = hooks.equalizerPreampRequested?() ?? 0
        guard let (previousBands, previousPreamp) = announcedEqualizer.announce(bands: bands, preamp: preamp)
        else { return }
        var movedSlider = false
        if previousPreamp != preamp {
            movedSlider = syncEqualizerSliders(for: .preamp, value: preamp) || movedSlider
        }
        for (index, value) in bands.enumerated() where previousBands?.indices.contains(index) != true
            || previousBands?[index] != value {
            movedSlider = syncEqualizerSliders(for: .band(index), value: value) || movedSlider
        }
        if movedSlider { notifyGraphDidMutate() }
        if previousPreamp != preamp {
            _ = try? dispatchSystem(event: "oneqpreampchanged",
                                    arguments: [.integer(Int32(clamping: preamp))])
        }
        for (index, value) in bands.enumerated() where previousBands?.indices.contains(index) != true
            || previousBands?[index] != value {
            _ = try? dispatchSystem(event: "oneqbandchanged",
                                    arguments: [.integer(Int32(index)), .integer(Int32(clamping: value))])
        }
    }

    /// Write the position of every slider bound to `action`, in its own `low…high` unit, so a script
    /// that reads the slider rather than the event (multipass's fillbars) sees the change too. The
    /// renderer already draws an EQ slider's thumb from the host, so this is the *script's* view of
    /// it catching up. Returns whether anything moved.
    func syncEqualizerSliders(for action: WinampModernEQAction, value: Int) -> Bool {
        let normalized = CGFloat(Double(max(-127, min(127, value))) + 127) / 254
        var moved = false
        for object in loadedSkin.runtime.graph.allObjectsUnordered
        where object.tag.is(.slider) {
            guard WinampModernEQAction.decode(action: object.attributes["action"],
                                              parameter: object.attributes["param"]) == action else { continue }
            let position = String(Self.sliderPosition(normalized: normalized, of: object))
            guard object.attributes["value"] != position else { continue }
            _ = object.setAttribute("value", value: position)
            moved = true
        }
        return moved
    }
}
