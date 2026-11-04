import CoreGraphics

/// An AIMP control's `class`, read once with what that class alone reads (`reference/layout.md` §
/// Controls). Classes are matched by name, some by prefix (`ScrollBar…`, `TextDisplay…`,
/// `Slider…`); a control bound to one of NullPlayer's lists is that list's whatever its class. One
/// the renderer has no drawing of its own for is a key: its picture's frame by state, a panel's
/// fill, a caption (`Key`).
enum AIMPControlClass: Sendable {
    case key(Key)
    /// `Slider`, `SliderHorizontal`, `SliderVertical`…, and `SeekBar`.
    case slider(Slider)
    /// `SliderMasked`: a filmstrip of positions (a knob's turn, a selector's positions).
    case selector
    /// `DigitsDisplay`, and `TimeDisplay`'s 13-frame strip.
    case digits(Digits)
    case time(Digits)
    /// `Gauge`: a filmstrip of needle positions, eased by the window where it gives reaction speeds.
    case gauge(reaction: (up: Double, down: Double)?)
    case animator(Animator)
    /// `StateDisplay`: the frame its `State` names (Teac V-8BL 4K's counter drums).
    case stateDisplay
    case spectrum(Spectrum)
    /// `VisualDisplay`: AIMP's visualization screen, where NullPlayer draws the spectrum under the
    /// picture's `CoverFrame` (RealPlayer 11's gloss).
    case visualization(Spectrum, cover: Int?)
    case waveForm(Trace)
    /// `EqualizerDisplay`'s `ColorPreamp` and `ColorCurve`, ARGB, when not clear.
    case equalizer(preamp: UInt32?, curve: UInt32?)
    case coverArt(Cover)
    /// `BlurredGlass`: what is drawn under it, blurred by `BlurLevel`, inside its mask frame, tinted
    /// by its `Color`.
    case glass(blur: Double?, tint: AIMPSkinColor?)
    /// `Rating`: five stars of its picture; with no picture, a key's (`Key`).
    case rating(Key)
    /// NullPlayer's lists placed in the skin's frame, in the skin's colours and fonts: the playlist
    /// (`<control link="Playlist">`), the library's group tree and table (`"MLGroupingTree"`, `"MLTable"`).
    case playlist(AIMPSkinControl.Playlist)
    case libraryTree(AIMPSkinControl.Library)
    case libraryTable(AIMPSkinControl.Library)
    /// A scroll bar bound to the playlist, and its `SkinThumb`.
    case playlistScrollBar(thumb: String?)
    /// A list's quick search box (a `SearchEdit` bound to a list's `QuickSearch`; `.acs3`'s
    /// `<control link="PlaylistSearch">`).
    case search(AIMPSkinList)
    /// AIMP 4's `TabControl` over a playlist or library manager (over anything else it is a key),
    /// and `PlaylistTabs`.
    case tabControl(AIMPSkinControl.Tabs, manager: String)
    case playlistTabs(AIMPSkinControl.Tabs)
    /// `PlaylistBox`, the playlist chooser: `.acs3`'s one-value `Font`, and `TextAlign` centred.
    case playlistBox(font: AIMPSkinFont?, centred: Bool)

    /// What a control the renderer draws as its picture is: a key with hot, pressed and disabled
    /// frames (`Button`; `Switch` with a run of them per state), a display of text, or any other.
    struct Key: Sendable {
        enum Role: Sendable, Equatable { case button, `switch`, textDisplay, runningLine, picture }
        let role: Role
        /// A `Panel`'s `Color`, which fills it under its picture (Unsquareable's light theme).
        let fill: AIMPSkinColor?
        /// `Frame`: a fixed picture (an AIMP 3.0 skin's lit playlist tab); `FramesPerState`, as declared.
        let fixedFrame: Int
        let framesPerState: Int?

        /// Keys have normal, hot, pressed and disabled frames.
        var isKey: Bool { role == .button || role == .switch }
        /// Draws its caption or bound text over its picture.
        var showsText: Bool { role == .button || role == .textDisplay || role == .runningLine }
    }

    struct Slider: Sendable {
        let isSeek: Bool
        /// Turned upright: `SliderVertical`, or `Orientation` oVertical (Kenwood KX-4520's EQ).
        let isVertical: Bool
        /// `SkinThumb`.
        let thumb: String?
    }

    /// `Digits` and `IndentBetweenDigits` of a digit strip.
    struct Digits: Sendable {
        let places: Int?
        let indent: Int
    }

    /// An animator's `AnimationInterval` and `AnimationReversed`, as written.
    struct Animator: Sendable {
        let interval: Double?
        let reversed: Bool
    }

    /// A spectrum's `ColumnsCount` and `ColumnsIndent`, its bars' `Color`, and the lit display it
    /// reveals (`PeakColumns`, in `PeakColumnsSegmentation`-px steps).
    struct Spectrum: Sendable {
        let columns: Int
        let indent: CGFloat
        let color: AIMPSkinColor?
        let peakColumns: String?
        let peakSegment: CGFloat
    }

    /// An oscilloscope's trace colour (`ColorContent`, a Delphi colour) and channel (`Source`).
    struct Trace: Sendable {
        let color: UInt32?
        let channel: String?
    }

    /// A cover display's `CoverFrame` laid over it (RealPlayer 11's gloss) and `BlurLevel` (Soot's
    /// backdrop); its mask is the control's `maskFrame` (SL-1200's round label).
    struct Cover: Sendable {
        let coverFrame: Int?
        let blur: Double?
    }

    /// A control's class, by its `link` to one of NullPlayer's lists, else by its `class`, a scroll
    /// bar or search box bound to a list being that list's.
    init(_ node: AIMPNode, bindings: AIMPSkinBindings, resources: [String: [String: AIMPNode]]) {
        let props = node.properties
        func number(_ name: String) -> Double? { Double(props[name]?.reference ?? "") }
        func integer(_ name: String) -> Int? { Int(props[name]?.reference ?? "") }
        let name = node["class"] ?? ""
        func keyed(_ role: Key.Role) -> Key {
            Key(role: role, fill: name == "Panel" ? AIMPSkinColor(props["Color"]) : nil,
                fixedFrame: integer("Frame") ?? 0, framesPerState: integer("FramesPerState"))
        }
        func key(_ role: Key.Role) -> AIMPControlClass { .key(keyed(role)) }
        func slider(seek: Bool) -> AIMPControlClass {
            .slider(Slider(isSeek: seek, isVertical: name == "SliderVertical" || props["Orientation"]?.reference == "oVertical",
                           thumb: props["SkinThumb"]?.reference))
        }
        let digits = Digits(places: integer("Digits"), indent: integer("IndentBetweenDigits") ?? 0)
        let spectrum = Spectrum(columns: max(1, integer("ColumnsCount") ?? 16), indent: CGFloat(integer("ColumnsIndent") ?? 1),
                                color: AIMPSkinColor(props["Color"]), peakColumns: props["PeakColumns"]?.reference,
                                peakSegment: CGFloat(max(1, integer("PeakColumnsSegmentation") ?? 1)))
        // Read as `AIMPSkinControl.maskFrame` is: the `Skin`'s, else its resource's (Windows Media
        // Player 11's gloss, frame 2, over its cover).
        let coverFrame = (props["Skin"]?["CoverFrame"] ?? props["Skin"]?.reference.flatMap { resources[$0]?["Resource"]?["CoverFrame"] })
            .flatMap { Int($0) }
        switch node["link"] {
        case "PlaylistSearch"?: self = .search(.playlist); return
        case AIMPSkinList.playlist.rawValue?: self = .playlist(.init(props, resources: resources)); return
        case AIMPSkinList.libraryTree.rawValue?: self = .libraryTree(.init(props, resources: resources)); return
        case AIMPSkinList.libraryTable.rawValue?: self = .libraryTable(.init(props, resources: resources)); return
        default: break
        }
        switch name {
        case "Button": self = key(.button)
        case "Switch": self = key(.switch)
        case "SearchEdit":
            let list = bindings.links.first { $0.pin == "QuickSearch" }?.source.flatMap(AIMPSkinList.init(rawValue:))
            self = list.map { .search($0) } ?? key(.picture)
        case "TabControl":
            let tabs = AIMPSkinControl.Tabs(node, bindings: bindings, resources: resources)
            self = tabs.source.map { .tabControl(tabs, manager: $0) } ?? key(.picture)
        case "PlaylistTabs": self = .playlistTabs(AIMPSkinControl.Tabs(node, bindings: bindings, resources: resources))
        case "PlaylistBox":
            self = .playlistBox(font: AIMPSkinFont(flat: props["Font"]?.reference),
                                centred: AIMPSkinTextAlign(props["TextAlign"]?.reference) == .center)
        case "Gauge":
            let up = number("ReactionSpeedLevelUp") ?? 0, down = number("ReactionSpeedLevelDown") ?? 0
            self = .gauge(reaction: up > 0 && down > 0 ? (up, down) : nil)
        case "Animator": self = .animator(Animator(interval: number("AnimationInterval"), reversed: props["AnimationReversed"]?.reference == "True"))
        case "TimeDisplay": self = .time(digits)
        case "DigitsDisplay": self = .digits(digits)
        case "EqualizerDisplay": self = .equalizer(preamp: AIMPSkinColor.visible(props["ColorPreamp"]), curve: AIMPSkinColor.visible(props["ColorCurve"]))
        case "CoverArtDisplay":
            self = .coverArt(Cover(coverFrame: coverFrame, blur: number("BlurLevel")))
        case "WaveFormDisplay": self = .waveForm(Trace(color: AIMPSkinColor.delphi(props["ColorContent"]), channel: props["Source"]?.reference))
        case "Rating": self = .rating(keyed(.picture))
        case "VisualDisplay": self = .visualization(spectrum, cover: coverFrame)
        case "SpectrumDisplay": self = .spectrum(spectrum)
        case "StateDisplay": self = .stateDisplay
        case "SliderMasked": self = .selector
        case "BlurredGlass": self = .glass(blur: number("BlurLevel"), tint: AIMPSkinColor(props["Color"]))
        case "SeekBar": self = slider(seek: true)
        case "RunningLine": self = key(.runningLine)
        case let other where other.hasPrefix("ScrollBar"):
            self = bindings.links.contains(where: { $0.source == AIMPSkinList.playlist.rawValue })
                ? .playlistScrollBar(thumb: props["SkinThumb"]?.reference) : key(.picture)
        case let other where other.hasPrefix("TextDisplay"): self = key(.textDisplay)
        case let other where other.hasPrefix("Slider"): self = slider(seek: false)
        default: self = key(.picture)
        }
    }

    /// A key, or a control drawn as one.
    var key: Key? {
        switch self {
        case .key(let key), .rating(let key): return key
        default: return nil
        }
    }
}
