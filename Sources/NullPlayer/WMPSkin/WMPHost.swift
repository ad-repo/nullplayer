import Foundation

enum WMPScanDirection: String, Hashable, Codable { case reverse, forward }

enum WMPTransportAction: Hashable, Codable {
    case play, pause, stop, previous, next
    case beginScan(WMPScanDirection), endScan
    case seek, volume, balance
    case toggleMute, toggleShuffle, toggleRepeat
    case playPlaylistItem(Int), removePlaylistItem(Int), movePlaylistItem(Int, Int)
    case setWOWEnabled, setWOWLevel, setTruBassLevel, setSpeakerSize
    case setEQEnabled, setEQBand(Int), setPreamp
    /// An index into `EQPreset.allPresets`. Every `<POPUP>` in the corpus is a preset menu, and
    /// `eq.currentPreset` is what its handler writes.
    case setEQPreset(Int)
    /// What an `<EFFECTS>` rect draws, by `WMPEffectSelection` id. 96 of the 179 corpus archives
    /// bind `currentEffectType="wmpprop:mediacenter.effectType"`, so the selector is a host
    /// property the skin reads and writes rather than a menu this engine invents (W101).
    case setEffectType(String)
    case nextEffect, previousEffect
    /// The preset *within* the selected effect: ProjectM's preset, Geiss's and Tripex's effect.
    case setEffectPreset(Int), nextEffectPreset
}

enum WMPHostValue: Hashable, Codable {
    case number(Double), bool(Bool), string(String)

    var finiteNumber: Double? {
        switch self {
        case let .number(value): return value.isFinite ? value : nil
        case let .bool(value): return value ? 1 : 0
        case let .string(value):
            guard let number = Double(value), number.isFinite else { return nil }
            return number
        }
    }
}

struct WMPMediaMetadata: Hashable, Codable {
    var title = ""
    var artist = ""
    var album = ""
    /// `player.currentMedia.sourceURL`, which a skin reads to decide what it is playing before it
    /// reads anything else about it. `Cablemusic`'s `GenericProgramInfoBig()` opens with
    /// `pullString.indexOf('http')` to tell a stream from a file, and it is the third statement in
    /// the function that fills every readout in the player.
    var sourceURL = ""
}

struct WMPPlaylistItemSnapshot: Hashable, Codable {
    let title: String
    let artist: String
    let duration: TimeInterval
}

/// What the skin's `<EFFECTS>` rect is drawing, and the four members the corpus reads off it.
///
/// `type` and `presetTitle` are the strings a skin puts on screen beside the surface —
/// `visEffects.currentEffectTitle` is read by 61 archives and `currentPresetTitle` by 42 — so they
/// answer what is actually being drawn rather than a constant. See `WMPEffectSelection`.
struct WMPEffectsSnapshot: Hashable, Codable {
    /// The stable id of the selected effect: `bars`, `projectm`, `geiss`, `tripex`.
    var type = ""
    var title = ""
    var preset = 0
    var presetTitle = ""
}

struct WMPEqualizerSnapshot: Hashable, Codable {
    var enabled = false
    var enhancedAudio = false
    var wowLevel: Double = 50
    var truBassLevel: Double = 50
    var speakerSize = 0
    var currentSpeakerName: String { ["Headphones", "Normal speakers", "Large speakers"][max(0, min(2, speakerSize))] }
    var preamp: Double = 0
    var gains: [Double] = Array(repeating: 0, count: 10)
}

struct WMPHostSnapshot: Hashable, Codable {
    enum State: String, Hashable, Codable { case stopped, playing, paused }
    var state: State = .stopped
    var currentTime: TimeInterval = 0
    var duration: TimeInterval = 0
    var volume: Double = 0
    var balance: Double = 0
    var muted = false
    var shuffle = false
    var repeatMode = false
    var bufferingProgress: Double = 0
    var receptionQuality: Double = 0
    /// `player.network.bitRate`, in **bits per second** — WMP's unit, and the one a skin prints:
    /// `Cablemusic` writes `txtBit.value = bitrate + ' bps'`. Zero when nothing is playing or the
    /// track carries no rate, which is the honest answer rather than a guess.
    var bitrate: Double = 0
    var metadata = WMPMediaMetadata()
    var playlistIndex = -1
    var playlistCount = 0
    var playlistItems: [WMPPlaylistItemSnapshot] = []
    var equalizer = WMPEqualizerSnapshot()
    var effects = WMPEffectsSnapshot()
    /// The last valid video state for WMP's `videostart`/`videoend` edge detection. This stays
    /// latched through a decoder output rebuild; `video` remains live so the hosted surface can
    /// detach and release mouse capture when VLC has no drawable output.
    var videoEvent = WMPVideoSnapshot()
    var video = WMPVideoSnapshot()

    var elapsedText: String { Self.timeString(currentTime) }
    var durationText: String { Self.timeString(duration) }

    /// **`player.status` — WMP's status-bar sentence, and 69 of the 180 archives read it.**
    ///
    /// It was inert and empty for eight phases, which left the readout those skins dedicate to it
    /// blank: `Windows_XP_Media_Center_Edition` paints a `STATUS:` label beside
    /// `<TEXT value="wmpprop:player.status">` and showed the label alone. **Not one of the corpus's
    /// 128 uses compares it against a literal** — every one prints it, either straight into a
    /// readout or prepended to the track name the way the Alienware family's `updateMetadata`
    /// does — so the string is free to be the sentence WMP shows rather than a token, and no
    /// handler can branch on the wording.
    ///
    /// **There is deliberately no `Buffering (n%)` here.** WMP spells one, but `bufferingProgress`
    /// is 0-100 with 100 meaning *full* and nothing in this app ever writes it — the field stays at
    /// its `0` default outside the harness — so a `< 100` test would report every skin permanently
    /// buffering. The honest status is the one derived from state the engine actually has.
    var statusText: String {
        switch state {
        case .playing: return "Playing"
        case .paused: return "Paused"
        // WMP says `Ready` before anything is open and `Stopped` once something is and is not
        // running, which is the same split `isEnabled(.play)` already makes.
        case .stopped: return playlistCount > 0 ? "Stopped" : "Ready"
        }
    }

    func isEnabled(_ action: WMPTransportAction) -> Bool {
        switch action {
        case .play: return playlistCount > 0 && state != .playing
        case .pause: return state == .playing
        case .stop: return state != .stopped
        case .previous, .next: return playlistCount > 1
        case .seek, .beginScan: return duration > 0
        case let .playPlaylistItem(index), let .removePlaylistItem(index):
            return playlistItems.indices.contains(index)
        case let .movePlaylistItem(source, destination):
            return playlistItems.indices.contains(source) && playlistItems.indices.contains(destination)
        case .endScan, .volume, .balance, .toggleMute, .toggleShuffle, .toggleRepeat,
             .setWOWEnabled, .setWOWLevel, .setTruBassLevel, .setSpeakerSize, .setEQEnabled, .setEQBand, .setPreamp, .setEQPreset,
             .setEffectType, .nextEffect, .previousEffect, .setEffectPreset, .nextEffectPreset:
            return true
        }
    }

    private static func timeString(_ value: TimeInterval) -> String {
        let seconds = max(0, Int(value.isFinite ? value : 0))
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}

@MainActor
protocol WMPHost: AnyObject {
    var snapshot: WMPHostSnapshot { get }
    func perform(_ action: WMPTransportAction, value: WMPHostValue?)
    func stopContinuousCommands()
    func setSpectrumConsumerActive(_ active: Bool)
}

extension WMPTransportAction {
    /// The action a control's `value="wmpprop:…"` binding writes to.
    ///
    /// A `.wmz` almost never uses the semantic `<VOLUMESLIDER>`/`<SEEKSLIDER>` tags: it authors a
    /// plain `<SLIDER>` and binds its value, which is a statement about where the control writes
    /// just as much as the tag would have been. 163 of 178 corpus skins drive volume, seek and
    /// their ten equaliser bands entirely through these paths.
    static func boundAction(for path: String) -> WMPTransportAction? {
        switch path.lowercased() {
        case "player.settings.volume": return .volume
        case "player.settings.balance": return .balance
        case "player.controls.currentposition": return .seek
        case "eq.enhancedaudio": return .setWOWEnabled
        case "eq.wowlevel": return .setWOWLevel
        case "eq.trubasslevel": return .setTruBassLevel
        case "eq.speakersize": return .setSpeakerSize
        case "eq.enabled", "eq.enable": return .setEQEnabled
        default: break
        }
        guard let band = eqBand(in: path) else { return nil }
        return .setEQBand(band)
    }

    /// `eq.gainLevel1`…`eq.gainLevel10`, WMP's one-based band names, as a zero-based index.
    static func eqBand(in path: String) -> Int? {
        let lower = path.lowercased()
        guard lower.hasPrefix("eq.gainlevel"),
              let ordinal = Int(lower.dropFirst("eq.gainlevel".count)),
              (1...10).contains(ordinal) else { return nil }
        return ordinal - 1
    }

    static func authoredAction(for node: WMPNode) -> WMPTransportAction? {
        if let kindAction = kindAction(for: node) { return kindAction }
        let statements = statements(ofHandler: "onClick", on: node)
        // Phase 4 accepts only exact, non-script transport literals. General handlers remain off.
        guard statements.count == 1, let normalized = statements.first else { return nil }
        return literalAction(normalized)
    }

    /// The action the **tag itself** carries, before any handler is read. Separate from
    /// `authoredAction` because the two sources are not interchangeable: this one is the element's
    /// own behaviour, while the handler fallback below is how a plain `<BUTTON>` is given one.
    private static func kindAction(for node: WMPNode) -> WMPTransportAction? {
        switch node.kind {
        // Both spellings of every transport control carry the same action: `<PLAYELEMENT>` is the
        // region of a `BUTTONGROUP`'s mapping image and `<PLAYBUTTON>` the standalone button, and
        // WMP's own template family uses each about as often as the other.
        case .playElement, .playButton: return .play
        case .pauseElement, .pauseButton: return .pause
        case .stopElement, .stopButton: return .stop
        case .prevElement, .prevButton: return .previous
        case .nextElement, .nextButton: return .next
        case .rewButton, .rewElement: return .beginScan(.reverse)
        case .ffwdButton, .ffwdElement: return .beginScan(.forward)
        case .volumeSlider: return .volume
        case .seekSlider: return .seek
        case .balanceSlider: return .balance
        case .muteButton: return .toggleMute
        case .repeatButton: return .toggleRepeat
        case .shuffleButton: return .toggleShuffle
        default: return nil
        }
    }

    /// **A handler that issues the element's own command owns the click, and the engine must not
    /// post the command as well.** `<NEXTELEMENT onClick="player.controls.next()">` says one thing
    /// twice: the kind carries `.next` and the handler calls it, so dispatching both skipped two
    /// tracks on one press — measured live on `ALXMorph` with a three-index cue, First → Second →
    /// Third 10 ms apart. **73 transport elements across 19 of the 182 measurable archives** author
    /// this shape (`next` 17 uses / 16 skins, `previous` 15 / 14, `play` 20 / 19, `stop` 14 / 13,
    /// `pause` 7 / 7), counted over the `wmp_markup_census.sh` flat files.
    ///
    /// **It has to be a dedupe rather than "the handler wins".** Three corpus elements author an
    /// `onClick` that does something else entirely — a sound effect — and rely on the kind for the
    /// transport itself, so dropping the implicit action wherever a handler exists would kill them.
    ///
    /// This is the rule `WMPMainWindowController.dispatchScriptEvent` already applies to
    /// `<RETURNBUTTON>`, where `anemone` and `modernblue` spell `view.returnToMediaCenter()`
    /// themselves and posting the command too would toggle the library open and shut again.
    /// **Nothing headless saw this**: `WMP_RENDER_CLICK` runs the authored handler and prints its
    /// host command, and never applies `WMPHitTarget.action` the way `WMPMainView` does.
    /// **Only where the tag is the source of the action.** A plain `<BUTTON>` whose action was
    /// *derived* from its own handler literal is the Phase 4 fallback above, and suppressing the
    /// command there would leave the button with nothing but the handler it was standing in for.
    static func handlerOwnsAction(_ action: WMPTransportAction, on node: WMPNode) -> Bool {
        guard kindAction(for: node) == action else { return false }
        return statements(ofHandler: "onClick", on: node).contains { literalAction($0) == action }
    }

    /// One authored handler, lowercased, whitespace stripped, split into statements, with the
    /// skins' own sound-effect call dropped — `checkSoundPref('button.wav');player.controls.next()`
    /// is a transport statement with a noise in front of it.
    private static func statements(ofHandler name: String, on node: WMPNode) -> [String] {
        guard let attribute = node.attribute(named: name),
              case let .handler(_, source) = attribute.value else { return [] }
        return source.lowercased().split(separator: ";").map {
            String($0).filter { !$0.isWhitespace }
        }.filter { !$0.isEmpty && !$0.hasPrefix("checksoundpref(") }
    }

    private static func literalAction(_ normalized: String) -> WMPTransportAction? {
        if normalized == "player.controls.play()" { return .play }
        if normalized == "player.controls.pause()" { return .pause }
        if normalized == "player.controls.stop()" { return .stop }
        if normalized == "player.controls.previous()" { return .previous }
        if normalized == "player.controls.next()" { return .next }
        if normalized == "player.settings.mute=!player.settings.mute" { return .toggleMute }
        if normalized == "player.settings.setmode('shuffle',down)" || normalized == "player.settings.setmode(\"shuffle\",down)" {
            return .toggleShuffle
        }
        if normalized == "player.settings.setmode('loop',down)" || normalized == "player.settings.setmode(\"loop\",down)" {
            return .toggleRepeat
        }
        return nil
    }
}
