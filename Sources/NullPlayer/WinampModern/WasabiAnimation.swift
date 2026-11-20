import Foundation

/// The playback model shared by the renderer (which paints the current frame) and the script runtime
/// (which answers `getCurFrame()` / `isPlaying()`).
///
/// An `animatedlayer` is a sprite sheet plus a play head. Winamp scripts drive it as a *range*:
/// `setStartFrame(current)`, `setEndFrame(target)`, `setSpeed(msPerFrame)`, `play()` — MMD3 turns its
/// volume/bass/treble knobs exactly this way and polls `isPlaying()` to know when the sweep is done.
/// Keeping the play head a pure function of the elapsed time since `play()` means both sides agree
/// without either of them owning a ticking clock.
enum WasabiAnimation {
    static func now() -> TimeInterval { ProcessInfo.processInfo.systemUptime }
    static func state(of object: WasabiObject, frameCount: Int,
                      clock: TimeInterval = now()) -> (frame: Int, isPlaying: Bool) {
        let attributes = object.attributes
        let count = max(1, frameCount)
        let selected = max(0, min(count - 1, Int(attributes["frame"] ?? "0") ?? 0))
        // An explicit `playing` (set by `play()`/`stop()`) wins over the XML's `autoplay`, so a script
        // can stop a layer the skin declared as self-playing.
        let playing: Bool
        if let explicit = attributes["playing"] {
            playing = explicit == "1"
        } else {
            playing = attributes["autoplay"] == "1" || attributes["autoreplay"] == "1"
        }
        guard playing else { return (selected, false) }
        let period = period(of: object)
        let elapsed = max(0, clock - (Double(attributes["animstart"] ?? "") ?? 0))
        let steps = Int(elapsed / period)

        // A range replays unless the layer says `autoreplay="0"`. The skins that sweep a knob to a
        // value and wait for it to stop declare that (MMD3's knobs); the ones that set the whole sheet
        // as the range, `play()` it in `onPlay` and `stop()` it in `onStop` mean "animate while the
        // music plays" (Hitchhikers_Guide's robot, jvc.tape's reels), which a one-shot froze after
        // one pass.
        let replays = attributes["autoreplay"] != "0"
        // No range set: `autoreplay="0"` plays once to the last frame, so its `onStop` arrives — Moon
        // Groove's PLAY/PAUSE/STOP status hides itself and brings the song ticker back from there
        // (B256). Anything else is the classic looping animation.
        let end: Int? = if let raw = attributes["endframe"] { Int(raw) }
            else if !replays { count - 1 }
            else { nil }
        guard let end else { return ((selected + steps) % count, true) }
        let start = max(0, min(count - 1, Int(attributes["startframe"] ?? "") ?? selected))
        let target = max(0, min(count - 1, end))
        let distance = abs(target - start)
        guard distance > 0 else { return (target, false) }
        if steps >= distance, !replays { return (target, false) }
        // The range holds `distance + 1` frames (both ends), so a replay wraps after that many steps.
        let step = replays ? steps % (distance + 1) : steps
        return (start + (target > start ? step : -step), true)
    }

    /// Seconds per frame: the script's `setSpeed` / the XML's `speed`, in milliseconds.
    static func period(of object: WasabiObject) -> TimeInterval {
        max(0.008, (Double(object.attributes["speed"] ?? "100") ?? 100) / 1_000)
    }

    /// Whether the layer has a clock to read its play head from: a script's `play()` set one, or the
    /// first draw stamped it (`stampFirstShow`). Before that `state` would count from uptime 0.
    static func hasClock(_ object: WasabiObject) -> Bool { object.attributes["animstart"] != nil }

    /// The window just came on screen: a self-playing layer drawn while it was still ordered out
    /// (the first whole frame is recorded before AppKit shows the window) has already spent its
    /// start, so it starts over. JetBlue_Card's 0.8 s intro was over before the window appeared (B452).
    static func restartAtFirstVisible(_ object: WasabiObject, clock: TimeInterval) {
        // Only a once-only layer: a loop's start is just its phase, and a script that drives a range
        // (`setStartFrame`/`setEndFrame`) reads the stamp it already holds (Pepsi_EVo's vis stopped).
        guard object.attributes["animstart"] != nil, object.attributes["playing"] == nil,
              object.attributes["autoplay"] == "1", object.attributes["autoreplay"] == "0",
              object.attributes["endframe"] == nil else { return }
        _ = object.setAttribute("animstart", value: String(clock))
    }

    /// A layer that plays itself from markup (`autoplay`/`autoreplay`, no `play()` yet) starts when it
    /// is first drawn. Without a stamp `state` counted from uptime 0, so a once-only intro was over
    /// before the window opened: Official_Zwan_Skin's rainbow wipe and thinger strips sat on their
    /// last frame (B280). A loop is periodic, so its start only sets its phase.
    static func stampFirstShow(_ object: WasabiObject, clock: TimeInterval) {
        let attributes = object.attributes
        guard attributes["animstart"] == nil, attributes["playing"] == nil,
              attributes["autoplay"] == "1" || attributes["autoreplay"] == "1" else { return }
        _ = object.setAttribute("animstart", value: String(clock))
    }
}
