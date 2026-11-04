/// An AIMP data provider's `class` (`Schema.xml`'s `<provider>`): read once into the skin index, so
/// the dataflow, scripts and painter ask one question rather than matching class names.
enum AIMPProviderClass: Equatable, Sendable {
    /// `LogicalOperatorCounter`; `ScriptableOperatorCounter` runs its script on each new position.
    case counter(scripted: Bool)
    /// `LogicalOperatorCommutator`: `Result` is its `Expression` over its inputs.
    case commutator
    /// `StringOperatorConcatenator`: text joined from its inputs. `…Notificator` shows AIMP's
    /// passing notices over the same text (Bliss Compact Dark's title line); NullPlayer posts none.
    case concatenator
    /// `LogicalOperatorTimer`: fires its `Action` links every `Interval` ms.
    case timer
    /// `ScriptableEventHandler`: a script run when something executes it.
    case eventHandler
    /// `ScriptableVisualizationHandler`: a script run every frame over the spectrum.
    case visualizationHandler
    case other(String)

    init(_ name: String?) {
        switch name {
        case "LogicalOperatorCounter": self = .counter(scripted: false)
        case "ScriptableOperatorCounter": self = .counter(scripted: true)
        case "LogicalOperatorCommutator": self = .commutator
        case "StringOperatorConcatenator", "StringOperatorConcatenatorNotificator": self = .concatenator
        case "LogicalOperatorTimer": self = .timer
        case "ScriptableEventHandler": self = .eventHandler
        case "ScriptableVisualizationHandler": self = .visualizationHandler
        default: self = .other(name ?? "")
        }
    }

    var isCounter: Bool { if case .counter = self { true } else { false } }
}

/// What a slider, knob or value key moves: one of the player's values, or a value only the skin
/// keeps (an effect NullPlayer lacks, `prvReverb`; a skin counter a knob turns). Parsed once from
/// the control's binding.
enum AIMPSkinProvider: Hashable, Sendable, CustomStringConvertible {
    case volume, balance, position, preamp
    /// AIMP's speed, tempo and pitch, all NullPlayer's (tempo-preserving) speed.
    case speed
    /// A NullPlayer EQ band (`AIMPSkinHostState.eqBand`).
    case equalizerBand(Int)
    case named(String)

    init(_ name: String) {
        switch name {
        case "prvVolume": self = .volume
        case "prvBalance": self = .balance
        case "prvPlayerState", "prvPlayerPosition", "prvPosition": self = .position
        case "prvSpeed", "prvTempo", "prvPitch": self = .speed
        default: self = .named(name)
        }
    }

    /// One of the player's providers (`prvVolume`, `prvReverb`), not the skin's own: AIMP names
    /// every one of them `prv…`. Nil for anything else.
    init?(player name: String) {
        guard name.hasPrefix("prv") else { return nil }
        self.init(name)
    }

    var description: String {
        switch self {
        case .volume: return "prvVolume"
        case .balance: return "prvBalance"
        case .position: return "prvPlayerState"
        case .preamp: return "prvEqualizer:Preamp"
        case .speed: return "prvSpeed"
        case .equalizerBand(let band): return "prvEqualizer:\(band)"
        case .named(let name): return name
        }
    }
}
