import CoreGraphics
import Foundation

/// AIMP 3.0 skins (Vega AIO), read into the form tree the later formats have, so the renderer and
/// the window take them as they are (`reference/format.md` § *AIMP 3.0*):
/// - `MainFrame.xml` (and `PlaylistFrame.xml`, `EqFrame.xml` for the dock sites that name them) is
///   the item tree, attribute style: `Class` `TAIMPLayoutContainerItem` (a picture named after the
///   item), `TAIMPLayoutTextureItem`, `TAIMPLayoutItem`, `TAIMPLayoutDockSiteItem`; `Align` (none is
///   top), `AlignLevel` (lower docks first), `AlignMargins`.
/// - `main.ini` places the controls: `[Parents]` names each one's item, its own section its
///   `PlaceAnchors`, `PlaceMargins`, `PlaceWidth`/`PlaceHeight` and `ZOrder`. What a control is
///   comes from its name (AIMP's own objects: `PlayPauseBtn`, `VolumeBar`), `[Clones]` (a copy of
///   one) or `[CustomObjects]` (`ClassTextLabel`, `ClassNumLabel;4`). Its picture is `<name>.myimg`, or `<name>.bmp`.
/// Objects AIMP 3 parks left of or above their item (every unused one) are left out. Its colours
/// are Delphi's (`$00BBGGRR`); the form takes them as ARGB, as the later formats write them.
///
/// AIMP 2's `.acs` is read into the same model (`AIMPSkinLegacy+AIMP2.swift`): each reader gives
/// `Object`s and `Settings`, which `Translator` builds the form from (`AIMPSkinLegacy+Translator.swift`).
enum AIMPSkinLegacy {
    /// What `main.ini` gives: the main form, the windows beside it, and the pictures as the forms
    /// lay them out (AIMP 2's bitmaps carry no layout of their own).
    struct Forms {
        let main: AIMPNode
        let companions: [AIMPSkin.Companion]
        let images: [String: AIMPSkinImage]
    }

    /// One object `main.ini` places, as AIMP 3.0 writes it, whichever reader found it.
    struct Object {
        let name: String
        /// The item it is placed in.
        let item: String
        /// AIMP 3's `PlaceInfo`: the edges it keeps (left, top, right, bottom), its distances from
        /// them, and its own size.
        let anchors: [Int]
        let margins: [Int]
        let size: CGSize
        /// Back to front.
        let z: Int
        let kind: Kind
        /// `Font`: `name,BGR,height,style`.
        let font: String?
        /// `TextAlign`: 0 left, 1 right, 2 centred.
        let textAlign: Int?
        /// A slider's `Orientation`: 0 upright, 1 across, 2 a knob turned through its frames.
        let orientation: Int?
    }

    /// What an object is: `[CustomObjects]`' class, else AIMP's own object its name names.
    enum Kind {
        /// `ClassTextLabel`: a caption, or a template of the playing file's tags (`%T`).
        case text(String)
        /// `ClassNumLabel;4`: the time in `digits` places, `indent` apart.
        case time(Time, digits: String, indent: String)
        /// `ClassNumLabel;5` and `;6`.
        case bitrate, sampleRate
        /// `ClassStatusLabel`: a picture per play state; `;2` shows the player's.
        case status(showsState: Bool)
        case seekBar
        /// `ClassAnimator`, a frame every `interval` ms.
        case animator(interval: String)
        /// `ClassSpectrum`: `peaks` bars `indent` apart in `colour` (Delphi), upside down when `flipped`.
        case spectrum(peaks: String, indent: String, colour: Int64?, flipped: Bool)
        case coverArt
        /// `AIMPEQDisplay`: the curve's and the preamp line's colours (`EQVISE`, `EQVISL`, Delphi).
        case equalizerDisplay(curve: Int64?, preamp: Int64?)
        /// AIMP's own object (`playpausebtn`, `volumebar`), lowercased: the name, or through
        /// `[Clones]` the object it copies.
        case object(String)

        enum Time { case position, remaining, duration }

        /// `custom` the `[CustomObjects]` class (`ClassNumLabel;4`), `base` the AIMP object the name
        /// is or copies, `setting` the object's own keys. Nil for a class NullPlayer does not draw.
        init?(custom: String?, base: String, setting: (String) -> String?) {
            let parts = custom?.split(separator: ";").map(String.init) ?? []
            switch parts.first {
            case "ClassTextLabel":
                guard let template = setting("Template"), !template.isEmpty else { return nil }
                self = .text(template)
            case "ClassNumLabel":
                switch parts.dropFirst().first {
                case "4":
                    let time: Time = setting("Static") == "1" ? .duration : setting("Reverse") == "1" ? .remaining : .position
                    self = .time(time, digits: setting("Digits") ?? "5", indent: setting("IndentBetweenDigits") ?? "0")
                case "5": self = .bitrate
                case "6": self = .sampleRate
                default: return nil
                }
            case "ClassStatusLabel": self = .status(showsState: parts.dropFirst().first == "2")
            case "ClassSeekBar": self = .seekBar
            case "ClassAnimator": self = .animator(interval: setting("AnimationInterval") ?? "50")
            case "ClassSpectrum":
                self = .spectrum(peaks: setting("Peaks") ?? "16", indent: setting("Indent") ?? "1",
                                 colour: setting("Color").flatMap { Int64($0) }, flipped: setting("Orientation") == "1")
            case "ClassCoverArt": self = .coverArt
            default:
                func colour(_ key: String) -> Int64? { setting(key).flatMap { UInt32($0) }.map(Int64.init) }
                self = base == "aimpeqdisplay" ? .equalizerDisplay(curve: colour("EQVISE"), preamp: colour("EQVISL")) : .object(base)
            }
        }
    }

    /// What `main.ini` says of the windows rather than their objects.
    struct Settings {
        /// `[MainFrame] SizingHitTestAreaWidth`: the window sizes from its edges.
        var sizingEdge: String?
        /// `[Playlist]`'s fonts (`Nrm`, `Act`, `Sel`, `SelAct`) and colours (`BK`, `ABK`, `SBK`, `SABK`).
        var playlist: [String: String] = [:]
        /// `[TabCtrl] ActiveTab`: the lit tab's font.
        var activeTab: String?
    }

    /// The forms of an AIMP 3.0 or AIMP 2 skin (`archive.isLegacy`), its parse failures in `documents`.
    /// Throws when it has no main form: the layout missing (AM0010) or not reading (its finding).
    static func forms(_ documents: AIMPSkinDocuments, ini: AIMPSkinINI, images: [String: AIMPSkinImage]) throws -> Forms {
        if documents.archive.format == .acsp { return try AIMP2(documents: documents, ini: ini, images: images).forms() }
        let layout = try documents.throwing("MainFrame.xml", missing: "An AIMP 3.0 skin with no MainFrame.xml.", documents.node)
        var settings = Settings(sizingEdge: ini["MainFrame", "SizingHitTestAreaWidth"], activeTab: ini["TabCtrl", "ActiveTab"])
        settings.playlist = playlistSettings(ini)
        var translator = Translator(documents: documents, images: images, objects: objects(ini), settings: settings)
        return Forms(main: translator.form(layout), companions: [], images: images)
    }

    /// AIMP 3.0's objects: `[Parents]` in file order, each placed by its own section.
    static func objects(_ ini: AIMPSkinINI) -> [Object] {
        let clones = Self.clones(ini["Clones"]?.lines ?? [])
        return (ini["Parents"]?.lines ?? []).compactMap { name, item in
            let own = ini[name]
            func setting(_ key: String) -> String? { own?[key] }
            guard let kind = Kind(custom: ini["CustomObjects", name], base: original(of: name, clones: clones), setting: setting) else {
                return nil
            }
            return Object(name: name, item: item,
                          anchors: AIMPNode.numbers(setting("PlaceAnchors") ?? "1,1,0,0"),
                          margins: AIMPNode.numbers(setting("PlaceMargins") ?? "0,0,0,0"),
                          size: CGSize(width: Int(setting("PlaceWidth") ?? "") ?? 0, height: Int(setting("PlaceHeight") ?? "") ?? 0),
                          z: Int(setting("ZOrder") ?? "") ?? 0, kind: kind, font: setting("Font"),
                          textAlign: setting("TextAlign").flatMap { Int($0) }, orientation: setting("Orientation").flatMap { Int($0) })
        }
    }

    /// `[Playlist]`'s fonts and colours, as AIMP 3 names them.
    static func playlistSettings(_ ini: AIMPSkinINI) -> [String: String] {
        var found: [String: String] = [:]
        for key in ["Nrm", "Act", "Sel", "SelAct", "BK", "ABK", "SBK", "SABK"] { found[key] = ini["Playlist", key] }
        return found
    }

    /// `[Clones]` lines (copy, original) as a table by the copy's lowercased name, the first winning.
    static func clones(_ lines: [(key: String, value: String)]) -> [String: String] {
        Dictionary(lines.map { ($0.key.lowercased(), $0.value) }, uniquingKeysWith: { first, _ in first })
    }

    /// The AIMP object `name` is, lowercased: itself, or through `clones` the object it copies (a
    /// copy of a copy too; a loop ends where it would come round).
    static func original(of name: String, clones: [String: String]) -> String {
        var base = name.lowercased()
        var seen: Set<String> = [base]
        while let next = clones[base]?.lowercased(), seen.insert(next).inserted { base = next }
        return base
    }

    /// How each BMP picture of an AIMP 3.0 skin is cut, by lowercased object name: its `main.ini`
    /// section's `SkinFrames`, `SkinLayout` (1 stacked), `Margins` (left, top, right, bottom) and, when
    /// `StretchMode` is 1, the two stretched columns `TLC` and `TRC` (each `left, top, right, bottom`).
    static func bitmapLayouts(_ ini: AIMPSkinINI) -> [String: AIMPSkinImage.Layout] {
        var layouts: [String: AIMPSkinImage.Layout] = [:]
        for section in ini.sections {
            var layout = AIMPSkinImage.Layout()
            layout.frames = max(1, Int(section["SkinFrames"] ?? "") ?? 1)
            layout.stacked = section["SkinLayout"] == "1"
            let m = AIMPNode.numbers(section["Margins"])
            if m.count == 4 { layout.margins = .init(left: m[0], top: m[1], right: m[2], bottom: m[3]) }
            let left = AIMPNode.numbers(section["TLC"]), right = AIMPNode.numbers(section["TRC"])
            if section["StretchMode"] == "1", left.count == 4, right.count == 4 {
                layout.columns = .init((left[0], left[2] - left[0]), (right[0], right[2] - right[0]))
            }
            layouts[section.name.lowercased()] = layout
        }
        return layouts
    }
}
