import Foundation

/// Every `skin.ini` key Sonique reads, resolved at load: the skin's value, else the default
/// (`SoniqueSkinDefaults`). A value reads the way the oracle reads it (decision record § *INI rules*):
/// its leading integer (`33.5` is 33, `69 (Repeat Green)` is 69), a colour's `0x` hex with the alpha
/// byte dropped, or `NAME`, `NAME + n`, `NAME - n` naming another key of the same section. An empty
/// value is unwritten; anything else is `SQ0011` and takes the default.
struct SoniqueSkinSettings {
    private(set) var values: [String: [String: Int]] = [:]
    private(set) var findings: [SoniqueSkinFinding] = []
    private let ini: SoniqueSkinINI
    private var visiting: Set<String> = []

    init(_ ini: SoniqueSkinINI) {
        self.ini = ini
        for (section, keys) in SoniqueSkinDefaults.values.sorted(by: { $0.key < $1.key }) {
            for key in keys.keys.sorted() { _ = resolve(section, key) }
        }
    }

    /// A key Sonique reads; `section` and `key` as `misc.txt` names them, in any case.
    func int(_ section: String, _ key: String) -> Int {
        values[section.lowercased()]![key.lowercased()]!
    }

    /// `<key>_x` and `<key>_y`, the way every position in `skin.ini` is written.
    func point(_ section: String, _ key: String) -> (x: Int, y: Int) {
        (int(section, key + "_x"), int(section, key + "_y"))
    }

    /// `0xRRGGBB` from `[sonique colors]`.
    func colour(_ key: SoniqueColour) -> UInt32 {
        UInt32(truncatingIfNeeded: int("sonique colors", key.rawValue)) & 0xFF_FFFF
    }

    /// Where the closed drawer's (0,0) sits on the navigator picture. `DRAWER_POS` wins whenever the
    /// skin writes it, whatever its version; `MISC_DRAWER_POS` only otherwise, and 0,0 there reads as
    /// unwritten (format.md § *Window outline*).
    var drawerPosition: (x: Int, y: Int) {
        if written("misc locations", "DRAWER_POS_x") != nil { return point("misc locations", "DRAWER_POS") }
        let misc = point("misc values", "MISC_DRAWER_POS")
        return misc == (0, 0) ? (29, 229) : misc  // `MISC_DRAWER_POS`'s default (`SoniqueSkinDefaults`)
    }

    /// How far the navigator's drawer slides down to open.
    var drawerSlide: Int { int("misc values", "MISC_DRAWER_DISTANCE_TOSLIDE") }

    // MARK: - What the scene and renderer read

    // Every key below has a default, so none of these traps; `SoniqueSkinSettingsTests` reads each.

    /// A lit state's top-left in `/jpeg/misc`; `navigator` reads its `NAV_` twin where it has one.
    func origin(_ lit: SoniqueLitState, navigator: Bool = false) -> (x: Int, y: Int) {
        point("misc locations", (navigator && lit.hasNavigatorTwin ? "NAV_" : "") + lit.rawValue)
    }

    /// A knob strip's frame width and frame count (`<key>_width`, `<key>_images`).
    func frames(_ strip: SoniqueKnobStrip) -> (width: Int, count: Int) {
        (int("misc values", strip.rawValue + "_width"), int("misc values", strip.rawValue + "_images"))
    }

    /// The navigator drawer's EQ sliders, in the drawer's own pixels.
    var drawerSliders: SoniqueDrawerSliders {
        let v = { int("misc values", "MISC_DRAWER_SLIDER_" + $0) }
        return SoniqueDrawerSliders(left: v("ARRAY_POS_x"), top: v("ARRAY_POS_y"), pitch: v("PITCH"),
                                    width: v("SIZE_x"), height: v("SIZE_y"),
                                    handleWidth: v("HANDLE_SIZE_width"), handleHeight: v("HANDLE_SIZE_height"))
    }

    /// Mid mode's balls' top-lefts from the vis window's corner (`[msm locations]`): mode up, mode
    /// down, help, minimise, close.
    var midBallOrigins: [(x: Int, y: Int)] {
        ["MSM_SINGLEUP", "MSM_SINGLEDOWN", "MSM_HELP", "MSM_MINIMIZE", "MSM_CLOSE"].map { point("msm locations", $0) }
    }

    /// How far the navigator's balls sit in from the display's right edge.
    var navBallInset: Int { int("misc values", "NC_BB_DIST_FROM_RIGHT") }

    /// Whether mid mode's rings fill a whole turn clockwise from the top (`mid_playlistmode=0`), not
    /// 270° from the bottom left.
    var midRingsFillFromTop: Bool { int("misc values", "mid_playlistmode") == 0 }

    /// The skin's own value; an empty one (`MISC_DRAWER_POS_x=`; 8 skins write one) counts as unwritten.
    private func written(_ section: String, _ key: String) -> String? {
        ini.value(section, key).flatMap { $0.isEmpty ? nil : $0 }
    }

    /// Nil only for a key that is neither a default nor written, or one that names itself through a cycle.
    private mutating func resolve(_ section: String, _ key: String) -> Int? {
        if let value = values[section]?[key] { return value }
        guard visiting.insert(section + "/" + key).inserted else { return nil }
        defer { visiting.remove(section + "/" + key) }
        let fallback = SoniqueSkinDefaults.values[section]?[key]
        var value: Int?
        if let raw = written(section, key) {
            value = parse(raw, section)
            if value == nil, fallback != nil {
                findings.append(SoniqueSkinFinding(.iniValueMalformed, "[\(section)] \(key) = \(raw) does not parse; the default is used."))
            }
        }
        if value == nil, let fallback { value = parse(fallback, section) }
        if let value, fallback != nil { values[section, default: [:]][key] = value }
        return value
    }

    private mutating func parse(_ raw: String, _ section: String) -> Int? {
        let text = Substring(raw.trimmingCharacters(in: .whitespaces))
        if section == "sonique colors", text.lowercased().hasPrefix("0x") {
            let digits = text.dropFirst(2).prefix { $0.isHexDigit }
            return digits.isEmpty ? nil : UInt32(digits.suffix(8), radix: 16).map(Int.init)
        }
        if let number = Self.leadingInteger(text) { return number }
        let name = text.prefix { $0.isLetter || $0.isNumber || $0 == "_" }
        guard let first = name.first, first.isLetter || first == "_" else { return nil }
        var rest = text.dropFirst(name.count).drop { $0 == " " || $0 == "\t" }
        var offset = 0
        if let sign = rest.first, sign == "+" || sign == "-" {
            rest = rest.dropFirst().drop { $0 == " " || $0 == "\t" }
            guard let n = Self.leadingInteger(rest), rest.allSatisfy({ $0.isNumber }) else { return nil }
            offset = sign == "+" ? n : -n
        } else if !rest.isEmpty {
            return nil
        }
        return resolve(section, name.lowercased()).map { $0 + offset }
    }

    /// C `atoi`'s reading: an optional sign and the digits after it; nil when there are none.
    private static func leadingInteger(_ text: Substring) -> Int? {
        let sign = text.first == "-" || text.first == "+" ? 1 : 0
        let digits = text.dropFirst(sign).prefix { $0.isASCII && $0.isNumber }.prefix(9)
        guard let value = Int(digits) else { return nil }
        return text.first == "-" ? -value : value
    }
}

/// The `[sonique colors]` keys NullPlayer draws with, so a misspelt one does not compile rather
/// than trapping in `SoniqueSkinSettings.int`. Every case has a default (`SoniqueSkinDefaults`).
enum SoniqueColour: String, CaseIterable {
    case systemColor1 = "SystemColor_1", systemColor2 = "SystemColor_2", systemColor3 = "SystemColor_3"
    case borderColor = "BorderColor", systemBkColor1 = "SystemBkColor_1", systemBkColor2 = "SystemBkColor_2"
    case playListColor1 = "PlayListColor_1", playListColor2 = "PlayListColor_2"
    case progressColor1 = "ProgressColor_1", progressBkColor = "ProgressBkColor"
    case statusBarBgColor = "StatusBarBgColor", statusBarFgColor = "StatusBarFgColor", statusBarTextColor = "StatusBarTextColor"
    case openFileColor = "OpenFileColor", ampKnobColor = "AmpKnobColor", balKnobColor = "BalKnobColor"
    case pitchKnobColor = "PitchKnobColor", logoColor = "LogoColor", logoRingColor = "LogoRingColor"
    case blueBallsColor = "BlueBallsColor"
}

/// The `[misc locations]` lit states NullPlayer draws from `/jpeg/misc`. Sonique's loop-one,
/// `GREENON2`, is not here: NullPlayer's repeat is on or off.
enum SoniqueLitState: String, CaseIterable {
    case playOn = "PLAYON", stopOn = "STOPON", stopOff = "STOPOFF", pauseOn = "PAUSEON"
    case prev = "PREV", next = "NEXT", orangeOn = "ORANGEON", greenOn = "GREENON", cyanOn = "CYANON", redOn = "REDON"
    case bigUp = "BIGUP", bigOnDown = "BIGON_DOWN", sliderOff = "SLIDEROFF", sliderOn = "SLIDERON", drawer = "DRAWER"

    /// Whether the navigator has its own `NAV_` position for it: the transport and the round buttons do.
    var hasNavigatorTwin: Bool {
        switch self {
        case .bigUp, .bigOnDown, .sliderOff, .sliderOn, .drawer: return false
        default: return true
        }
    }
}

/// A knob's animation strip: its picture and its `[misc values]` key.
enum SoniqueKnobStrip: String, CaseIterable {
    case volume = "MISC_VOLUME_KNOB", navVolume = "MISC_NAV_VOLUME_KNOB"
    case drawer = "MISC_SMALL_KNOB", shuttle = "MISC_SHUTTLE_KNOB"

    var image: String {
        switch self {
        case .volume: return "/jpeg/volumeknob"
        case .navVolume: return "/jpeg/nav_volumeknob"
        case .drawer: return "/jpeg/smallknob"
        case .shuttle: return "/jpeg/shuttle"
        }
    }
}

/// The navigator drawer's 20 EQ slider tracks, `pitch` apart from (`left`, `top`) in the drawer's
/// own pixels, and the handle that rides them.
struct SoniqueDrawerSliders {
    let left, top, pitch, width, height, handleWidth, handleHeight: Int
}
