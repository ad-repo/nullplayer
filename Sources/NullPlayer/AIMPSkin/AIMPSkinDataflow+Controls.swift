import CoreGraphics
import Foundation

/// What one frame's reading of a skin makes of a control: whether it shows, what its bindings read,
/// its text. The layout and the painter both read a frame through it (`AIMPSkinRenderer.frame`).
extension AIMPSkinDataflow {
    /// A picture, through the resource aliases a script repointed.
    func image(_ reference: String?) -> AIMPSkinImage? { skin.image(reference, links: state.script.resourceLinks) }

    /// What a script set, else its `Visibility` bindings (all non-zero), else whether it starts
    /// shown (`AIMPSkinAlignment.startsShown`: a tabbed group's page is shown by being its active one).
    /// A binding outranks `InitialVisible` False: GX-F90's, Teac's and the Onkyos' amplifiers start
    /// hidden and show while their counter is on.
    func isShown(_ element: AIMPSkinElement) -> Bool {
        if let name = element.name, let set = state.script.visible[name] { return set }
        guard !element.gates.isEmpty else { return AIMPSkinAlignment.startsShown(element, in: skin.index) }
        return element.gates.allSatisfy { value(of: $0) != 0 }
    }

    /// A binding's value for `pin` (`DisplayValue`), nil when nothing is bound to `pin`.
    func boundValue(_ control: AIMPSkinControl, _ pin: String) -> Double? {
        control.bindings[pin].map { value(of: $0) }
    }

    /// The value a control's `Action` moves (`prvVolume`, an equalizer band, a skin counter): an
    /// equalizer pin as the NullPlayer band at the same place along the scale. AIMP 4 has 18 bands,
    /// AIMP 5 has 20; a ten-band NullPlayer EQ moves them in pairs.
    func provider(_ control: AIMPSkinControl) -> AIMPSkinProvider? {
        switch control.input.moves {
        case .provider(let provider)?: return provider
        case .equalizerBand(let n)?: return host.player.eqBand(aimp: n, aimp5: skin.archive.format == .acs5).map { .equalizerBand($0) }
        case nil: return nil
        }
    }

    /// A control's tooltip: what its `Hint` binding names (an action, the playing track, a value),
    /// else its `Hint` text.
    func hint(_ control: AIMPSkinControl) -> String? {
        switch control.input.hint {
        case .text(let text)?: return text
        case .playingTrack?: return [host.player.artist, host.player.title].filter { !$0.isEmpty }.joined(separator: " – ")
        case .volume(let label)?: return "\(label): \(Int((host.player.volume * 100).rounded()))%"
        case nil: return nil
        }
    }

    /// What a display or key shows: a template a script set (Telos sets its title line's to
    /// `%Title`) reads as the skin's own does; else a running line's track, else `displayText`.
    func text(_ control: AIMPSkinControl) -> String {
        state.script.texts[control.name ?? ""].map { AIMPSkinTemplate.format($0, host: host) }
            ?? (control.kind.key?.role == .runningLine ? runningText(control) : displayText(control))
    }

    /// A caption, or what a binding to the playing file, a number or a text provider shows.
    func displayText(_ control: AIMPSkinControl) -> String {
        switch control.text.display {
        case .none: return ""
        case .caption(let caption): return caption
        case .template(let template), .file(let template): return AIMPSkinTemplate.format(template, host: host)
        case .concatenation(let inputs, let template):
            if let source = control.bindings["DisplayValue"]?.source, state.script.expressions[source] != nil {
                return concatenatorText(source)
            }
            return concatenation(inputs, template: template)
        case .number(let link, let template):
            let value = value(of: link)
            if let template { return AIMPSkinTemplate.format(template, host: host, value: value) }
            return Self.text(of: value, read: link.read)
        }
    }

    /// A text provider's template over its inputs. An input that is another concatenator's
    /// `Result` is that one's text (Bliss AIO's state line: "Playing" and the bit rate, joined twice).
    func concatenation(_ inputs: [AIMPSkinLink], template: String, depth: Int = 0) -> String {
        var variables: [String: String] = [:]
        for input in inputs {
            guard let target = input.target else { continue }
            if case .concatenator(let name) = input.read {
                let text = concatenatorText(name, depth: depth + 1)
                (variables[target], variables["Text" + target]) = (text, text)
                continue
            }
            let number = value(of: input, depth: depth)
            variables[target] = number == number.rounded() ? String(Int(number)) : String(number)
            variables["Text" + target] = input.pin == "FileInfo"
                ? AIMPSkinTemplate.format(input.textFormat ?? "%T", host: host)
                : Self.text(of: number, read: input.read)
        }
        return AIMPSkinTemplate.format(template, host: host, variables: variables)
    }

    /// Concatenator `name`'s text: its `Expression`, as a script set it or the skin wrote it (no
    /// `Expression`: its first input's text).
    func concatenatorText(_ name: String, depth: Int = 0) -> String {
        guard depth < 8, let provider = skin.index.providers[name] else { return "" }
        let expression = state.script.expressions[name] ?? provider.node.properties["Expression"]?.reference ?? "%TextValue1"
        return concatenation(provider.bindings.links, template: AIMPSkinLanguage.expanded(expression, strings: skin.strings), depth: depth)
    }

    /// A `RunningLine` scrolls the playing track when nothing else is bound to it.
    func runningText(_ control: AIMPSkinControl) -> String {
        control.text.running.map { AIMPSkinTemplate.format($0, host: host) } ?? displayText(control)
    }

    /// A pin's value as AIMP writes it: the clock as hours and minutes, a track time as minutes
    /// and seconds, the playlist's length as hours, minutes and seconds and its size in MB; else
    /// the number (Technics' hue and saturation knobs read out their counters).
    static func text(of value: Double, read: AIMPSkinSource) -> String {
        switch read {
        case .player(.timeOfDay):
            return String(format: "%02d:%02d", Int(value) / 3_600 % 24, Int(value) / 60 % 60)
        case .player(.elapsed), .player(.duration), .player(.remaining), .player(.sleepTimer):
            return String(format: "%d:%02d", Int(value) / 60, Int(value) % 60)
        case .player(.playlistDuration), .table(.duration):
            let seconds = Int(value)
            return String(format: "%d:%02d:%02d", seconds / 3_600, seconds / 60 % 60, seconds % 60)
        case .player(.playlistSize), .table(.size): return String(format: "%.2f MB", value / 1_048_576)
        case .libraryGrouping: return (AIMPSkinLibrary.Grouping(rawValue: Int(value)) ?? .artistAlbum).title
        case .page, .pointerOver, .animatorFrame, .item, .value, .player, .playlistScrolls, .table(.count),
             .libraryScanning, .commutator, .concatenator, .counter:
            return String(Int(value.rounded()))
        }
    }

    /// An animator's frame: its `AnimationFrameIndex` binding when it has one; otherwise, while it
    /// runs (its `Accessibility` binding is non-zero, or with none, while playing), one frame per
    /// `AnimationInterval` ms of the clock, backwards while `AnimationReversed` is. `own`: a frame
    /// it keeps itself counts (`AIMPSkinScript.Engine.stepAnimators`); a leader followed does not.
    func animatorFrame(_ control: AIMPSkinControl, own: Bool = true, frames: Int, depth: Int = 0) -> Int {
        let link = control.bindings["AnimationFrameIndex"]
        // On a counter's position: the counter holds its steps too (`AIMPSkinScript.Engine.stepAnimators`).
        if let link, link.expression == nil, let source = link.source, skin.index.counterModule(source) != nil {
            return min(max(Int(value(source, "Position")), 0), frames - 1)
        }
        if own, let name = control.name, let frame = state.animation.animatorFrames[name] { return min(max(frame, 0), frames - 1) }
        // Another animator's frame (Technics SL-1200's blurred disc turns with its hidden plain one).
        if let link, link.pin == "AnimationFrameIndex", let source = link.source,
           let leader = skin.index.animators[source], depth < 4 {
            let leaderFrames = max(1, image(leader.picture)?.frameCount ?? 1)
            let frame = Double(animatorFrame(leader, own: false, frames: leaderFrames, depth: depth + 1))
            return min(max(Int(link.shaped(frame)), 0), frames - 1)
        }
        if let index = boundValue(control, "AnimationFrameIndex") { return min(max(Int(index), 0), frames - 1) }
        let running = boundValue(control, "Accessibility").map { $0 != 0 } ?? (host.player.playState == .playing)
        // No interval is AIMP's default of none: the animator holds its first frame (RealPlayer 11's
        // VU meter glare, whose second frame is a white sheet).
        guard running, frames > 1, let asked = boundValue(control, "AnimationInterval") ?? control.animator?.interval
        else { return 0 }
        let step = Int(host.feedback.clock / AIMPSkinScript.tickedInterval(max(1, asked))) % frames
        let reversed = boundValue(control, "AnimationReversed").map { $0 != 0 } ?? (control.animator?.reversed ?? false)
        return reversed ? frames - 1 - step : step
    }
}
