import Foundation

/// What a script reaches beyond its own variables: the host calls that read the dataflow, and the
/// objects `FindObject` finds (the skin's controls, items and providers, and the player's), with
/// what `Set`, `Get` and `Execute` do to each.
extension AIMPSkinScript {
    /// The calls that read the skin or the player, resolved by name as the script compiles (the
    /// rest are `Builtin`s).
    enum HostCall: Sendable {
        /// `BindingsGetDataAsText(source, pin)`, and `…AsText3(source, pin, expression, format)`
        /// with a link's own `Expression` and `TextFormat` (DEFIX Hi-End's search links read `%T`,
        /// `%R` and `%A` of `prvPlayingFileInfo.FileInfo` this way).
        case dataAsText, dataAsText3
        /// `BindingsGetDataAsInteger`, `…AsFloat`, `…AsBoolean`.
        case dataAsNumber
        /// What scripts store with `ConfigSet` and read back with `ConfigGet(name, default)`.
        case configGet, configSet
        case findObject
        /// The object the script belongs to: the control or provider that runs it.
        case current

        init?(_ key: String) {
            switch key {
            case "bindingsgetdataastext": self = .dataAsText
            case "bindingsgetdataastext3": self = .dataAsText3
            case "bindingsgetdataasinteger", "bindingsgetdataasfloat", "bindingsgetdataasboolean": self = .dataAsNumber
            case "configget": self = .configGet
            case "configset": self = .configSet
            case "findobject": self = .findObject
            case "self": self = .current
            default: return nil
            }
        }
    }

    /// What `FindObject(name)` finds, resolved once: one of the player's values, read as a knob bound
    /// to it reads it (`AIMPSkinProvider`), or the skin's own (an item or control, a `Schema.xml`
    /// provider, an action, a list), whichever the name finds.
    struct HostObject {
        let name: String
        let kind: Kind
        let element: AIMPSkinIndex.Element?
        let provider: AIMPSkinIndex.Provider?

        enum Kind {
            /// The track's position, the volume, the balance, or the speed (AIMP's speed and tempo:
            /// NullPlayer's tempo-preserving speed is both).
            case player(AIMPSkinProvider)
            /// `prvPitch`: NullPlayer's speed too, as its knob moves it (`AIMPSkinProvider`), but AIMP
            /// centres it on 0 where speed and tempo sit on 1: the effect resets of Kenwood KX-4520,
            /// Onkyo TA-2066 and Teac V-3RX set Speed 1, Tempo 1, Pitch 0.
            case pitch
            /// `prvEqualizer`: its `BandValue<n>` and `PreampValue`, in dB.
            case equalizer
            /// An effect NullPlayer lacks (`prvReverb`): only its knob moves, keeping its place.
            case effect
            case skin
        }

        init(_ name: String, in skin: AIMPSkin) {
            self.name = name
            switch AIMPSkinProvider(name) {
            case .named:
                kind = name == "prvEqualizer" ? .equalizer : Self.effects.contains(name) ? .effect : .skin
            case .speed where name == "prvPitch":
                kind = .pitch
            case let provider:
                kind = .player(provider)
            }
            element = skin.index.byName[name]
            provider = skin.index.providers[name]
        }

        private static let effects: Set = ["prvTrueBass", "prvReverb", "prvEcho", "prvChorus", "prvFlanger", "prvEnhancer"]

        /// One of the lists the skin's windows draw from NullPlayer's: their style is the skin's to set.
        var list: AIMPSkinList? { AIMPSkinList(rawValue: name) }
    }

    /// A property a script sets or reads with `Set(name, value)` and `Get(name)`. Names are matched
    /// as AIMP writes them: a skin's `'position'` is some other property of its own.
    enum Property {
        case activePage, position, state, visible, enabled, interval, template, opacity, frameIndex, parent, name, tag
        /// `PlaceInfo.Margins.Left` … `Bottom`: 0 left, 1 top, 2 right, 3 bottom; nil for another side.
        case margin(Int?)
        /// The equalizer's `PreampValue` and `BandValue<n>` (AIMP's band n).
        case preamp
        case band(Int)
        case other

        init(_ name: String) {
            switch name {
            case "ActivePage": self = .activePage
            case "Position": self = .position
            case "State": self = .state
            case "Visible": self = .visible
            case "Enabled": self = .enabled
            case "Interval": self = .interval
            case "Template": self = .template
            case "BlendingModeOpacity": self = .opacity
            case "FrameIndex": self = .frameIndex
            case "Parent": self = .parent
            case "Name": self = .name
            case "Tag": self = .tag
            case "PreampValue": self = .preamp
            default:
                if name.hasPrefix("PlaceInfo.Margins.") {
                    self = .margin(["Left", "Top", "Right", "Bottom"].firstIndex(of: String(name.dropFirst(18))))
                } else if name.hasPrefix("BandValue"), let band = Int(name.dropFirst(9)) {
                    self = .band(band)
                } else {
                    self = .other
                }
            }
        }
    }
}

extension AIMPSkinScript.Run {
    typealias Value = AIMPSkinScript.Value
    typealias Unsupported = AIMPSkinScript.Unsupported
    typealias HostObject = AIMPSkinScript.HostObject
    typealias Member = AIMPSkinScript.Member

    func host(_ call: AIMPSkinScript.HostCall, _ args: [Value]) throws -> Value {
        func arity(_ count: Int) throws {
            guard args.count == count else { throw Unsupported(what: "\(call) arguments") }
        }
        switch call {
        case .dataAsText:
            try arity(2)
            // A tabbed group's page reads as its name: Mayak MP-140C builds `Skin.VUAveraged` +
            // 'Green' from its `Colour` group.
            if args[1].string == "ActivePage", let pages = skin.index.groups[args[0].string], !pages.isEmpty {
                return .string(pages[flow.activePage(args[0].string)])
            }
            return .string(Value.number(flow.value(args[0].string, args[1].string)).string)
        case .dataAsText3:
            try arity(4)
            return .string(text(of: link(source: args[0].string, pin: args[1].string, expression: args[2].string,
                                         textFormat: args[3].string)))
        case .dataAsNumber:
            try arity(2)
            return .number(flow.value(args[0].string, args[1].string))
        case .configGet:
            return .string(engine.state.script.config[args.first?.string ?? ""] ?? (args.count > 1 ? args[1].string : ""))
        case .configSet:
            if args.count >= 2 { engine.state.script.config[args[0].string] = args[1].string }
            return .none
        case .findObject:
            return .object(HostObject(args.first?.string ?? "", in: skin))
        case .current:
            return lookup("sender") ?? .none
        }
    }

    /// `target.member(args…)`.
    func method(_ target: Value, _ member: Member, _ args: [Value]) throws -> Value {
        if let handled = try bindingsMethod(target, member, args) { return handled }
        switch (target, member) {
        case (.resource(let id), .set) where args.count == 2:
            if args[0].string == "ID" { engine.state.script.resourceLinks[id] = args[1].string }
            // A resource's other settings are the skin's to keep; nothing here draws them yet.
            return .none
        case (.resource(let id), .get) where args.count == 1:
            if args[0].string == "ID" { return .string(engine.state.script.resourceLinks[id] ?? id) }
            // A resource's own setting (`FindResource('Skin.Default').Get('Value')`: a theme colour).
            let property = skin.resources[engine.state.script.resourceLinks[id] ?? id]?[args[0].string]
            let text = property?["value"] ?? property?.named["Value"]?["value"] ?? ""
            return Double(text).map(Value.number) ?? .string(text)
        case (.object(let object), .set) where args.count == 2:
            set(object, args[0].string, to: args[1])
            return .none
        case (.object(let object), .get) where args.count == 1:
            return get(object, args[0].string)
        case (.object(let object), .execute):
            try execute(object)
            return .none
        // Docking (`AIMPSkinDockSites`): a form into its site and out to its window, and an item or
        // control into another item (Soot's all-in-one mode, A4 3.2's layouts).
        case (.object(let object), .parent) where args.isEmpty:
            return flow.parent(of: object.name).map { .object(HostObject($0, in: skin)) } ?? .none
        case (.object(let object), .dock) where args.isEmpty:
            engine.state.script.docked[object.name] = true
            return .none
        case (.object(let object), .undock) where args.isEmpty:
            engine.state.script.docked[object.name] = false
            return .none
        case (.object, .getResourceName), (.resource, .getResourceName):
            return .string(target.string)
        // Update batching and the clipboard: nothing to do here.
        case (_, .beginUpdate), (_, .endUpdate), (_, .copyToClipboard):
            return .none
        // A mouse handler's event: the window only passes the left button on, and whether a handler
        // took the event (`Handled`) changes nothing NullPlayer does next.
        case (.arguments, .get) where args.count == 1:
            if args[0].string == "Button" { return .string("mbLeft") }
            return .number(arguments[args[0].string] ?? 0)
        case (.arguments, .set) where args.count == 2:
            return .none
        // A form event's data (its new size, `PlaceInfo.ActualWidth`): NullPlayer's forms pass none.
        case (.eventData, .get) where args.count == 1:
            return .number(0)
        // A visualization handler's data: one band of the spectrum, 0–100. AIMP's 256 bands, low
        // to high, laid over however many the host has.
        case (.visualData, .spectrum):
            let spectrum = flow.host.feedback.spectrum
            guard !spectrum.isEmpty else { return .number(0) }
            let band = Int(Double(max(0, min(255, Int(args.last?.number ?? 0)))) / 256 * Double(spectrum.count))
            return .number(spectrum[min(band, spectrum.count - 1)] * 100)
        default:
            throw Unsupported(what: "method \(member)(\(args.map(\.string).joined(separator: ","))) on \(target.described)")
        }
    }

    // MARK: - Objects

    private func set(_ object: HostObject, _ path: String, to value: Value) {
        let name = object.name
        switch (object.kind, AIMPSkinScript.Property(path)) {
        case (_, .activePage):
            engine.state.script.activePages[name] = Int(value.number)
        case (.player(let provider), .position):
            setPlayer(provider, value.number)
        // What the pitch knob does: 0, the knob's middle, is normal speed.
        case (.pitch, .position):
            engine.ask(.setValue(provider: .speed, value.number + 0.5))
        // Effects NullPlayer lacks only move their knobs.
        case (.effect, .position):
            engine.ask(.setValue(provider: .named(name), max(0, min(1, value.number))))
        // The equalizer in dB: `BandValue<n>` (AIMP's band n) and `PreampValue` (the GX-F90's bass
        // and treble knobs shape the low and high bands this way). It has nothing else to set.
        case (.equalizer, .preamp):
            engine.setPreamp(dB: value.number)
        case (.equalizer, .band(let aimp)):
            if let band = flow.host.player.eqBand(aimp: aimp, aimp5: skin.archive.format == .acs5) {
                engine.setEqualizer(band: band, aimp: aimp, dB: value.number)
            }
        case (.equalizer, _):
            break
        case (_, .position):
            // A scripted counter runs its script when it moves (Red Bias 2.0's layout switch sets
            // `ThemeSettingLayout`, whose script docks and undocks the library).
            let position = Int(value.number)
            let moved = Int(flow.value(name, "Position")) != position
            engine.state.script.counters[name] = position
            if moved, object.provider?.kind == .counter(scripted: true) { engine.setCounter(name, to: position) }
        case (_, .state) where object.element?.node["class"] == "StateDisplay":
            engine.state.animation.animatorFrames[name] = Int(value.number)
        case (_, .visible):
            engine.state.script.visible[name] = value.number != 0
        case (_, .enabled):
            engine.state.script.timerEnabled[name] = value.number != 0
        case (_, .interval):
            engine.state.script.timerIntervals[name] = value.number
        case (_, .margin(let side)):
            if let side { engine.state.script.margins[name, default: [:]][side] = value.number }
        case (_, .template):
            engine.state.script.texts[name] = value.string
        case (_, .opacity):
            engine.state.animation.opacities[name] = min(255, max(0, value.number))
        case (_, .frameIndex):
            engine.state.animation.animatorFrames[name] = Int(value.number)
            engine.state.animation.animatorStepped[name] = flow.host.feedback.clock
        case (_, .parent):
            if case .object(let parent) = value { engine.state.script.parents[name] = parent.name }
        default:
            // Any other property of a control, item or list: kept, and drawn
            // (`AIMPSkinState.Script.propertySets`). A colour given as a Delphi colour (`$F1F1F1`,
            // no alpha) is opaque. Of anything else (a form, a provider, a name the skin lacks) it
            // is AIMP's own, which nothing here draws: the run goes on.
            if path == "Expression", object.provider?.kind == .concatenator {
                engine.state.script.expressions[name] = value.string
                return
            }
            guard object.element != nil || object.list != nil else { return }
            let text: String
            if case .number(let number) = value {
                let colour = path.hasSuffix("Color") || path.contains("Color.") || path.contains("Colors.")
                text = colour && !path.hasSuffix(".ID") && number >= 0 && number <= 0xFF_FFFF
                    ? String(AIMPSkinColor.argb(delphi: Int64(number))) : String(Int64(number))
            } else {
                text = value.string
            }
            engine.state.script.propertySets[name, default: [:]][path] = text
        }
    }

    /// What setting one of the player's values asks of it.
    private func setPlayer(_ provider: AIMPSkinProvider, _ value: Double) {
        switch provider {
        // The player's position is the track's: setting it seeks (Technics' counter reset rewinds
        // to 0), asked of the window as `AIMPSkinCommand.seek`.
        case .position: engine.ask(.seek(seconds: value))
        case .volume: engine.ask(.volume(value))
        // AIMP's balance runs −1…1 (Mayak-232's left and right volume sliders set it).
        case .balance: engine.ask(.balance(value))
        // Speed and tempo are multipliers (Kenwood's effects reset sets them to 1).
        case .speed: engine.ask(.speed(value))
        // Never a `.player` object's (`HostObject` makes these four only).
        case .preamp, .equalizerBand, .named:
            break
        }
    }

    private func get(_ object: HostObject, _ path: String) -> Value {
        let name = object.name
        switch (object.kind, AIMPSkinScript.Property(path)) {
        case (.player(.balance), .position):
            return .number(flow.host.player.balance * 2 - 1)
        case (.equalizer, .preamp):
            return .number(flow.host.player.preamp * 24 - 12)
        case (.equalizer, .band(let aimp)):
            guard let band = flow.host.player.eqBand(aimp: aimp, aimp5: skin.archive.format == .acs5) else { return .number(0) }
            return .number(flow.host.player.eqGains[band] * 24 - 12)
        case (.equalizer, _):
            return .number(0)
        case (_, .margin(let side)):
            guard let side else { return .number(0) }
            if let moved = engine.state.script.margins[name]?[side] { return .number(moved) }
            let margins = object.element?.node.properties["PlaceInfo"]?["margins"]?
                .split(separator: ",").compactMap { Double($0.trimmingCharacters(in: .whitespaces)) } ?? []
            return .number(margins.indices.contains(side) ? margins[side] : 0)
        case (_, .parent):
            return flow.parent(of: name).map { .object(HostObject($0, in: skin)) } ?? .none
        case (_, .name):
            return .string(name)
        // The player's state reads as AIMP's enumeration names.
        case (.player(.position), .state):
            switch flow.host.player.playState {
            case .playing: return .string("opsPlay")
            case .paused: return .string("opsPause")
            case .stopped: return .string("opsStop")
            }
        case (_, .activePage):
            return .number(Double(flow.activePage(name)))
        case (_, .visible):
            return .number(engine.state.script.visible[name].map { $0 ? 1 : 0 } ?? 1)
        // A control's `Tag`, as the skin wrote it (Red Bias 2.0's layout switches: 0, 1, 2).
        case (_, .tag) where object.element?.node.properties["Tag"]?["value"] != nil:
            let tag = object.element?.node.properties["Tag"]?["value"] ?? ""
            return Double(tag).map { .number($0) } ?? .string(tag)
        default:
            return .number(flow.value(name, path))
        }
    }

    /// `FindObject(name).Execute`: an AIMP action asks the window for it; an event handler runs in
    /// place, on this engine (Mayak-232's left and right volume knobs run `SetSettings`, which works
    /// out the volume and balance from both). Anything else has nothing to execute.
    private func execute(_ object: HostObject) throws {
        if let action = AIMPAction(object.name) {
            engine.ask(.action(action))
        } else if let provider = object.provider, provider.kind == .eventHandler, let script = provider.script,
                  let program = engine.program(script) {
            _ = try engine.budget.nested { try engine.run(program, sender: object.name) }
        }
    }
}
