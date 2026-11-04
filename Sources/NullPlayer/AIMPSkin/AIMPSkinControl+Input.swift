import Foundation

extension AIMPSkinControl {
    /// What the pointer does to a control, worked out from its bindings and handlers as the skin
    /// loads: the click target the frame offers is built from it (`AIMPSkinLayout`).
    struct Input: Sendable {
        /// What a press does (`AIMPSkinControl.press`).
        let press: AIMPSkinTarget.Kind?
        /// A `ContextMenu` binding as what a right-click does, nil for a real menu.
        let rightClick: AIMPSkinTarget.Kind?
        /// What it repeats while held (`ActionOnHold`: PREV and NEXT wind, VOLUME − and + step).
        let holdAction: AIMPAction?
        /// Held, a key sets a skin counter its scripts wind by (Tascam 32's and the Akais' PREV and
        /// NEXT: `BtnPrevHold_Counter` to 1), and its `OnMouseUp` handler stops it.
        let longClick: AIMPSkinTarget.LongClick?
        /// `OnMouseUp`: the handler a key runs when let go.
        let onMouseUp: String?
        /// Handlers for the pointer passing over (the reel decks' position preview).
        let onMouseEnter: String?
        let onMouseMove: String?
        let onMouseLeave: String?
        let hint: Hint?
        /// What its `Action` binding names (`prvVolume`, a skin counter, a tabbed group), and the
        /// value a slider or knob over it moves.
        let source: String?
        let moves: Moves?
        /// A display bound to an `Action` is a key whose value picks its picture (Onkyo TA-2066's
        /// AMPLIFIER, MUSIC LIBRARY and TAPE SELECTOR keys).
        let isActionKey: Bool
        /// A lamp that lights at one position of a skin counter a control selects (Akai CS-F33's
        /// three reverse-mode LEDs over its REV SELECTOR) picks that position when clicked: a
        /// shortcut AIMP lacks. Counters scripts drive (REW/FF lamps) stay displays.
        let lamp: (counter: String, position: Int)?

        /// The value a slider, knob or key moves: a player value, or an equalizer band found on
        /// the player's scale as each frame draws (`AIMPSkinHostState.eqBand`).
        enum Moves: Sendable {
            case provider(AIMPSkinProvider?)
            case equalizerBand(aimp: Int)
        }

        /// A tooltip: what its `Hint` binding names (an action, the playing track, a value), else
        /// its `Hint` text.
        enum Hint: Sendable {
            case text(String)
            case playingTrack
            /// The volume, after its label.
            case volume(String)
        }

        init(_ node: AIMPNode, bindings: AIMPSkinBindings, index: AIMPSkinIndex) {
            let props = node.properties
            press = Self.press(bindings, props: props, index: index)
            rightClick = Self.rightClick(bindings, index: index)
            holdAction = bindings.all("ActionOnHold").first { $0.pin == "Action" && $0.expression == nil }?.source.flatMap(AIMPAction.init)
            longClick = bindings["ActionOnLongClick"].flatMap { long in
                long.source.flatMap { index.counterModule($0) != nil ? AIMPSkinTarget.LongClick(counter: $0, value: Int(long.expression ?? "") ?? 1) : nil }
            }
            onMouseUp = props["OnMouseUp"]?.reference
            onMouseEnter = props["OnMouseEnter"]?.reference
            onMouseMove = props["OnMouseMove"]?.reference
            onMouseLeave = props["OnMouseLeave"]?.reference
            hint = Self.hint(bindings, props: props, strings: index.strings)
            let action = bindings["Action"]
            source = action?.source
            if let action, let source = action.source {
                if source == "prvEqualizer", let pin = action.pin {
                    // AIMP 4 has 18 bands (`Band1`–`Band18`), AIMP 5 has 20 (`Band0`–`Band19`).
                    moves = pin == "Preamp" ? .provider(.preamp)
                        : pin.hasPrefix("Band") ? Int(pin.dropFirst(4)).map { .equalizerBand(aimp: $0) } ?? .provider(nil) : .provider(nil)
                } else {
                    moves = .provider(AIMPSkinProvider(source))
                }
            } else {
                moves = nil
            }
            isActionKey = action != nil
            if let link = bindings["DisplayValue"], let counter = link.source, link.pin == "Position",
               index.selectorCounters.contains(counter), let position = link.expression.flatMap(Self.selectedPosition) {
                lamp = (counter, position)
            } else {
                lamp = nil
            }
        }

        /// N in a lamp's `Value = N`.
        static func selectedPosition(_ expression: String) -> Int? {
            let parts = expression.replacingOccurrences(of: " ", with: "").lowercased().split(separator: "=")
            guard parts.count == 2, parts[0] == "value" else { return nil }
            return Int(parts[1])
        }

        /// What a press does, from the control's `Action` binding:
        /// - an AIMP action (`acPlayerPlay`);
        /// - a tabbed group's `ActivePage`, shaped by the link's `Expression` (`(value+1) mod 3`);
        /// - a tab's `Visibility`: show that tab (Vega's program keys);
        /// - the main form's `Minimize`, the playlist's or library's `Visible`.
        /// A button a script drives names its action on its `Hint` binding instead (Vega MP-120's
        /// transport); a `PopupMenu` opens the player menu.
        private static func press(_ bindings: AIMPSkinBindings, props: [String: AIMPNode], index: AIMPSkinIndex) -> AIMPSkinTarget.Kind? {
            if let link = bindings["Action"], let source = link.source {
                if let action = AIMPAction(source) { return .action(action) }
                // AIMP providers count 0–100.
                if let provider = AIMPSkinProvider(player: source), let fixed = link.expression.flatMap(Double.init) {
                    return .setValue(provider: provider, value: fixed / 100)
                }
                if index.groups[source] != nil, link.pin == "ActivePage" {
                    return .page(group: source, step: AIMPSkinStep(link.expression))
                }
                if let tab = index.tabOf[source], link.pin == "Visibility" {
                    return .page(group: tab.group, step: AIMPSkinStep(String(tab.index)))
                }
                if index.names.items.contains(source), link.pin == "Visibility" { return .toggle(item: source) }
                // A companion window's key (Technicss' EQ and amplifier, Sony Media Tower's speakers).
                if index.companions.contains(source), link.pin == "Visible" { return .toggle(item: source) }
                if link.pin == "Position", index.providers[source]?.kind.isCounter == true {
                    return .counter(name: source, step: AIMPSkinStep(link.expression))
                }
                switch (source, link.pin) {
                case ("AIMPMainForm", "Minimize"): return .action(.mainMinimize)
                // A playlist or library window's own maximize key: the window fills the screen and back.
                case (let frame, "Maximize") where index.companions.contains(frame): return .maximize
                case ("AIMPMainForm", "StayOnTop"): return .action(.mainStayOnTop)
                case (let frame, "Visible"): if let opens = AIMPFormRole(frame).opens { return opens }
                default: break
                }
            }
            if let hint = bindings.all("Hint").lazy.compactMap({ $0.source.flatMap(AIMPAction.init) }).first {
                return .action(hint)
            }
            if let handler = props["OnClick"]?.reference { return .handler(handler) }
            if let down = props["OnMouseDown"]?.reference { return .hold(down: down, up: props["OnMouseUp"]?.reference) }
            return props["PopupMenu"]?.reference.map { .menu(AIMPSkinPopup($0)) }
        }

        /// A `ContextMenu` binding: a knob back to its middle (the Akais' bass and treble to 60),
        /// the balance keys to centre, an action.
        private static func rightClick(_ bindings: AIMPSkinBindings, index: AIMPSkinIndex) -> AIMPSkinTarget.Kind? {
            guard let link = bindings["ContextMenu"], let source = link.source else { return nil }
            if let fixed = link.expression.flatMap(Double.init) {
                if index.counterModule(source) != nil { return .counter(name: source, step: AIMPSkinStep(String(Int(fixed)))) }
                if let provider = AIMPSkinProvider(player: source) { return .setValue(provider: provider, value: fixed / 100) }
            }
            if let action = AIMPAction(source), link.pin == "Action" { return .action(action) }
            return nil
        }

        private static func hint(_ bindings: AIMPSkinBindings, props: [String: AIMPNode], strings: [String: String]) -> Hint? {
            if let link = bindings["Hint"], let source = link.source {
                if let name = AIMPAction(source)?.title { return .text(name) }
                if source == "prvPlayingFileInfo" || source == "prvQFI" { return .playingTrack }
                if AIMPSkinProvider(player: source) != nil, let format = link.textFormat, !format.contains("%") {
                    let label = AIMPSkinLanguage.expanded(format, strings: strings)
                    return source == "prvVolume" ? .volume(label) : .text(label)
                }
            }
            return props["Hint"]?.reference.map { .text(AIMPSkinLanguage.expanded($0, strings: strings)) }
        }
    }
}
