import CoreGraphics
import Foundation

extension AIMPSkinLegacy {
    /// AIMP 2's `.acs` (`reference/format.md` § *AIMP 2*), read into the AIMP 3.0 model `Translator`
    /// takes: an attribute-style item tree, `main.ini` sections that place each object
    /// (`PlaceAnchors`, `PlaceMargins`, `PlaceWidth`, `PlaceHeight`, `ZOrder`), `[Parents]`,
    /// `[Clones]` and `[CustomObjects]`.
    ///
    /// - **Panels.** An object's parent is a panel: `MAIN` the player (`MainClient` over the second
    ///   of `BottomDock`'s two stacked states, the one docked to the playlist), `EQ` the equalizer
    ///   (`MainEquaFrame`; version 2's `Client`), `TOP` and `BTM` the playlist's `TopPanel` and
    ///   `BottomPanel`, `ContainerN` a skin's own panel. The tray control (`TCCTRL`, `TCINFO`), quick
    ///   file info (`QFIClient`) and the detached playlist's title bar (`PlaylistFrame`, over
    ///   `PlsTopDock`) are AIMP's windows and are left out.
    /// - **Layout.** Version 3 has `MainLayout.xml` and `PlaylistLayout.xml`: sibling `<item Align
    ///   Level Control>` elements, the `Control` a panel; the playlist frame holds the playlist
    ///   layout inside `PlsLeftBar`, `PlsRightBar` and `PlsBottomBar`. Version 2 has none: the
    ///   player over the playlist, its tabs (when `TabCtrlIsUp`), top panel, bottom panel and list.
    ///   An equalizer the layout leaves out (not all-in-one) is a window right of the player that
    ///   `EQBtn` opens (`[EquaForm]`).
    /// - **Placement.** Version 3's object sections give `Bounds` (left, top, right, bottom in the
    ///   panel), `ParentBounds` (the panel when the skin was saved) and `Align`: 0 keeps the left
    ///   edge, 1 the right, 2 both (it stretches), 3 neither (it keeps its proportion). Version 2
    ///   keeps the bounds in `[SKIN_OBJS]`, the parents in `[PARENTS]` (none for the equalizer's
    ///   objects) and the rest as `[SKIN_WIDTHS]` `<Object>_align`, `_HORIZONTAL` and `Digits`,
    ///   `[SKIN_FONTS]` and `[SKIN_TEXTALIGNS]`. Unused objects have empty bounds.
    /// - **Pictures** are `<Object>.bmp` (version 2: `<Object>_skin.bmp`), states side by side:
    ///   `SkinFrames` of them, else as many as fit the object's width (a digit strip's: its
    ///   `Digits`' width). A slider's lit track is `<Object>_sel`, its thumb `<Object>_thumb`. A
    ///   panel's `TLC` and `TRC` (version 2: `[SKIN_RECTS]` `<Panel>_TLC`) are the columns that
    ///   stretch, as `x1,0,x2,0`.
    struct AIMP2 {
        let documents: AIMPSkinDocuments
        let ini: AIMPSkinINI
        /// The bitmaps by the names version 3 gives them: version 2's `_skin` dropped, its
        /// equalizer `Client` as `MainEquaFrame`; `SRINFO` reads `BRINFO`'s digits when it has none.
        let images: [String: AIMPSkinImage]
        /// Version 2's `main.ini` (`[SKIN_OBJS]`) has no layout files; version 3's has.
        let isVersion2: Bool

        init(documents: AIMPSkinDocuments, ini: AIMPSkinINI, images: [String: AIMPSkinImage]) {
            self.documents = documents
            self.ini = ini
            isVersion2 = ini["SKIN_OBJS"] != nil
            var renamed: [String: AIMPSkinImage] = [:]
            for (key, image) in images {
                var stem = String(key.dropLast(4))
                if isVersion2, stem.hasSuffix("_skin") { stem = String(stem.dropLast(5)) }
                if isVersion2, stem == "client" { stem = "mainequaframe" }
                renamed[stem + ".img"] = image
            }
            if renamed["srinfo.img"] == nil { renamed["srinfo.img"] = renamed["brinfo.img"] }
            // The skin editor gives the equalizer's bands one picture, the ninth's (every version 2
            // skin has `AIMPSlider9_skin` and few another band's).
            for band in 1...18 where renamed["aimpslider\(band).img"] == nil {
                for part in ["", "_thumb", "_sel"] { renamed["aimpslider\(band)\(part).img"] = renamed["aimpslider9\(part).img"] }
            }
            self.images = renamed
        }

        /// AIMP 2's built-in objects that AIMP 3.0 writes as `[CustomObjects]`, by lowercased name.
        private static let builtIns = [
            "time": "ClassNumLabel;4", "brinfo": "ClassNumLabel;5", "srinfo": "ClassNumLabel;6",
            "playermode": "ClassStatusLabel;2", "spectrum": "ClassSpectrum", "seekbar": "ClassSeekBar",
            "ititle": "ClassTextLabel;1", "iartist": "ClassTextLabel;2", "ialbum": "ClassTextLabel;3", "igenre": "ClassTextLabel;5",
        ]
        /// The equalizer panel's own names for sliders the player has too.
        private static let aliases = [("balance", "BalanceSlider"), ("speed", "SpeedSlider")]
        /// The sleep timer's display: NullPlayer has no sleep timer.
        private static let withoutCounterpart: Set<String> = ["sleeptime"]
        /// What a `ClassTextLabel;N` shows: title, artist, album, year, genre.
        private static let labelTemplates = ["1": "%T", "2": "%R", "3": "%A", "4": "%Y", "5": "%G"]
        /// Version 2's objects with no parent that are not the equalizer's: the playlist's own
        /// parts (its title bar's keys, scroll bar and tab scroll keys) and quick file info.
        private static let playlistParts: Set<String> = ["plsmenu", "plsclose", "playlistscroll", "tcn", "tcp"]
        private static let equalizerWindow = "EquaForm"
        /// A digit strip's glyphs: 0–9, the separator, the minus and a blank, as AIMP 3's.
        private static let digitGlyphs = 13

        /// One object as AIMP 2 places it, whichever version wrote it, before it is an `Object`.
        private struct Placed {
            let name: String
            /// The panel's item.
            let item: String
            /// Left, top, right, bottom in the panel.
            let bounds: [Int]
            /// 0 keeps the left edge, 1 the right, 2 both, 3 neither.
            let align: Int
            /// The panel's size when the skin was saved (version 3's `ParentBounds`): a right-kept edge
            /// is measured from it, and what lies outside it does not show.
            let parentSize: CGSize?
            /// Its own keys (Font, TextAlign, Digits, Reverse, Static, Orientation, SkinFrames, Color,
            /// Peaks…), by lowercased key.
            var settings: [String: String]
            /// What it is when AIMP 3.0 would write it in `[CustomObjects]` (`ClassNumLabel;4`).
            var custom: String?
            /// The AIMP object it is or copies, lowercased.
            var base: String

            func setting(_ key: String) -> String? { settings[key.lowercased()] }
        }

        func forms() throws -> Forms {
            var images = self.images
            let placed = classified(isVersion2 ? version2Objects() : version3Objects())
            let main = try mainLayout()
            let hasPlaylist = main.descendants().contains { $0["Name"] == "PlaylistFrame" }
            layOut(&images, objects: placed, playlistDocked: hasPlaylist)
            let ownsEqualizer = !main.descendants().contains { $0["Name"] == "MainEquaFrame" } && images["mainequaframe.img"] != nil
            var translator = Translator(documents: documents, images: images, objects: objects(placed), settings: settings(placed),
                                        equalizerWindow: ownsEqualizer ? Self.equalizerWindow : nil)
            let form = translator.form(main)
            var companions: [AIMPSkin.Companion] = []
            if ownsEqualizer {
                let layout = AIMPNode.element("layout", [:], [AIMPNode.element("item", ["Name": "MainEquaFrame", "Class": "TAIMPLayoutItem"])])
                companions.append(AIMPSkin.Companion(name: Self.equalizerWindow, title: "Equalizer", form: translator.form(layout),
                                                     initiallyVisible: false, role: .other, placement: .right))
            }
            return Forms(main: form, companions: companions, images: images)
        }

        // MARK: Pictures

        /// Each object's picture cut into its states, a slider's lit track as its second frame, the
        /// panels' stretching columns, the docked `BottomDock` state, the playlist tab.
        private func layOut(_ images: inout [String: AIMPSkinImage], objects: [Placed], playlistDocked: Bool) {
            for object in objects {
                let key = object.name.lowercased()
                guard let image = images[key + ".img"] else { continue }
                let width = object.bounds[2] - object.bounds[0]
                var frames = Int(object.setting("SkinFrames") ?? "") ?? 0
                // A digit strip's glyphs may leave a column over (Digital Light's 144-px strip).
                if object.custom?.hasPrefix("ClassNumLabel") == true {
                    frames = Self.digitGlyphs
                } else if frames <= 0 || image.width % frames != 0 {
                    frames = width > 0 && image.width % width == 0 ? image.width / width : 1
                }
                images[key + ".img"] = image.laidOut(AIMPSkinImage.Layout(frames: frames))
                if let lit = images[key + "_sel.img"], frames == 1, let track = AIMPSkinImage.stacking([image, lit]) {
                    images[key + ".img"] = track
                }
            }
            for (panel, columns) in stretchColumns() {
                if let image = images[panel + ".img"] { images[panel + ".img"] = image.laidOut(AIMPSkinImage.Layout(columns: columns)) }
            }
            if let dock = images["bottomdock.img"], dock.height > 1 {
                images["bottomdock.img"] = dock.stackedFrame(playlistDocked ? 1 : 0, of: 2) ?? dock
            }
            if let tab = images["activetab.img"] { images["tabctrltab.img"] = tab }
        }

        /// The two stretching columns of each panel, by lowercased panel name, from `TLC` and `TRC`
        /// (`x1,0,x2,0`); a panel with one stretches it as two halves.
        private func stretchColumns() -> [String: AIMPSkinImage.StretchColumns] {
            var ranges: [String: [[Int]]] = [:]
            if isVersion2 {
                for (key, value) in ini["SKIN_RECTS"]?.lines ?? [] where key.uppercased().hasSuffix("_TLC") || key.uppercased().hasSuffix("_TRC") {
                    ranges[key.dropLast(4).lowercased(), default: []].append(AIMPNode.numbers(value))
                }
            } else {
                for section in ini.sections {
                    let corner = section.lines.filter { $0.key == "TLC" || $0.key == "TRC" }.map { AIMPNode.numbers($0.value) }
                    if !corner.isEmpty { ranges[section.name.lowercased()] = corner }
                }
            }
            return ranges.compactMapValues { corners in
                let spans = corners.filter { $0.count == 4 && $0[2] > $0[0] }.map { (x: $0[0], width: $0[2] - $0[0]) }.sorted { $0.x < $1.x }
                switch spans.count {
                case 2: return AIMPSkinImage.StretchColumns(spans[0], spans[1])
                case 1 where spans[0].width >= 2:
                    let half = spans[0].width / 2
                    return AIMPSkinImage.StretchColumns((spans[0].x, half), (spans[0].x + half, spans[0].width - half))
                default: return nil
                }
            }
        }

        // MARK: Objects

        /// The panel an object's parent names, as the item it is placed in; nil for AIMP's own windows.
        private static func item(ofPanel panel: String) -> String? {
            switch panel.lowercased() {
            case "main": return "MainFrame"
            case "eq": return "MainEquaFrame"
            case "top": return "TopPanel"
            case "btm": return "BottomPanel"
            case let container where container.hasPrefix("container"): return panel
            default: return nil
            }
        }

        /// Version 3: a section per object, in file order, its panel in `[Parents]`.
        private func version3Objects() -> [Placed] {
            ini.sections.compactMap { section -> Placed? in
                guard let bounds = section["Bounds"].map(AIMPNode.numbers), bounds.count == 4,
                      let item = ini["Parents", section.name].flatMap(Self.item(ofPanel:)) else { return nil }
                let parent = section["ParentBounds"].map(AIMPNode.numbers)
                var settings: [String: String] = [:]
                for (key, value) in section.lines where settings[key.lowercased()] == nil { settings[key.lowercased()] = value }
                return Placed(name: section.name, item: item, bounds: bounds, align: Int(section["Align"] ?? "") ?? 0,
                              parentSize: parent.flatMap { $0.count == 4 ? CGSize(width: $0[2] - $0[0], height: $0[3] - $0[1]) : nil },
                              settings: settings, base: section.name.lowercased())
            }
        }

        /// Version 2: bounds in `[SKIN_OBJS]`, the rest in sections of their own.
        private func version2Objects() -> [Placed] {
            let tray = Set((ini["TC_PARENTS"]?.lines ?? []).map { $0.key.lowercased() })
            return (ini["SKIN_OBJS"]?.lines ?? []).compactMap { name, value in
                let key = name.lowercased()
                let bounds = AIMPNode.numbers(value)
                guard bounds.count == 4, !tray.contains(key), !Self.playlistParts.contains(key), !key.hasPrefix("qfi"),
                      let item = Self.item(ofPanel: ini["PARENTS", key] ?? "EQ") else { return nil }
                var settings: [String: String] = [:]
                settings["font"] = ini["SKIN_FONTS", key]
                settings["textalign"] = ini["SKIN_TEXTALIGNS", key]
                settings["digits"] = ini["SKIN_WIDTHS", key + "digits"]
                settings["orientation"] = ini["SKIN_WIDTHS", key + "_horizontal"]
                switch key {
                case "aimpeqdisplay":
                    settings["eqvise"] = ini["SKIN_FONTS", "EQVISE"]
                    settings["eqvisl"] = ini["SKIN_FONTS", "EQVISL"]
                case "spectrum":
                    settings["color"] = ini["SKIN_OPTIONS", "spectrumcolor"]
                    settings["peaks"] = ini["SKIN_OPTIONS", "spectrumpeaks"]
                default: break
                }
                return Placed(name: name, item: item, bounds: bounds, align: Int(ini["SKIN_WIDTHS", key + "_align"] ?? "") ?? 0,
                              parentSize: nil, settings: settings, base: key)
            }
        }

        /// `[Clones]` (version 2: `[SKIN_VIRTUAL_OBJS]`), then the equalizer panel's aliases.
        private var clones: [String: String] {
            let own = (isVersion2 ? ini["SKIN_VIRTUAL_OBJS"] : ini["Clones"])?.lines ?? []
            return AIMPSkinLegacy.clones(own + Self.aliases.map { (key: $0.0, value: $0.1) })
        }

        /// Each object's `[CustomObjects]` class: the skin's own (version 3), else the one AIMP 3.0
        /// gives AIMP 2's built-in object it is or clones; a text label's template; a digit strip's
        /// places, as many glyphs as fit when the skin gives none; a slider's direction, from its
        /// shape when the skin gives none.
        private func classified(_ objects: [Placed]) -> [Placed] {
            let clones = self.clones
            return objects.filter { object in
                // A panel is a window: what lies outside it does not show (cPro Insomnis' labels in
                // its collapsed top panel).
                let b = object.bounds
                return !Self.withoutCounterpart.contains(object.name.lowercased())
                    && CGRect(x: b[0], y: b[1], width: b[2] - b[0], height: b[3] - b[1]).intersects(CGRect(origin: .zero, size: panelSize(object)))
            }.map { object in
                var object = object
                object.base = AIMPSkinLegacy.original(of: object.name, clones: clones)
                object.custom = ini["CustomObjects", object.name] ?? Self.builtIns[object.base]
                let width = object.bounds[2] - object.bounds[0], height = object.bounds[3] - object.bounds[1]
                let parts = object.custom?.split(separator: ";").map(String.init) ?? []
                if parts.first == "ClassTextLabel", object.setting("Template") == nil {
                    object.settings["template"] = Self.labelTemplates[parts.count > 1 ? parts[1] : ""]
                }
                if parts.first == "ClassNumLabel", object.setting("Digits") == nil,
                   let strip = images[object.name.lowercased() + ".img"], strip.width >= Self.digitGlyphs {
                    object.settings["digits"] = String(width / (strip.width / Self.digitGlyphs))
                }
                if object.setting("Orientation") == nil, images[object.name.lowercased() + "_thumb.img"] != nil {
                    object.settings["orientation"] = width > height ? "1" : "0"
                }
                return object
            }
        }

        /// The objects as AIMP 3.0 places them, stacked in the order found: `PlaceAnchors` and
        /// `PlaceMargins` from the bounds and `Align`.
        private func objects(_ placed: [Placed]) -> [Object] {
            placed.enumerated().compactMap { z, object in
                guard let kind = Kind(custom: object.custom, base: object.base, setting: object.setting) else { return nil }
                let b = object.bounds
                let right = Int(panelSize(object).width) - b[2]
                let (anchors, margins): ([Int], [Int])
                switch object.align {
                case 1: (anchors, margins) = ([0, 1, 1, 0], [0, b[1], right, 0])
                case 2: (anchors, margins) = ([1, 1, 1, 0], [b[0], b[1], right, 0])
                case 3: (anchors, margins) = ([0, 1, 0, 0], [b[0], b[1], right, 0])
                default: (anchors, margins) = ([1, 1, 0, 0], [b[0], b[1], 0, 0])
                }
                return Object(name: object.name, item: object.item, anchors: anchors, margins: margins,
                              size: CGSize(width: b[2] - b[0], height: b[3] - b[1]), z: z, kind: kind, font: object.setting("Font"),
                              textAlign: object.setting("TextAlign").flatMap { Int($0) },
                              orientation: object.setting("Orientation").flatMap { Int($0) })
            }
        }

        /// The playlist's fonts and colours (version 2: `[SKIN_WIDTHS]` `Switch_*`) and the tabs' font.
        private func settings(_ placed: [Placed]) -> Settings {
            guard isVersion2 else {
                return Settings(playlist: AIMPSkinLegacy.playlistSettings(ini), activeTab: ini["TabCtrl", "ActiveTab"])
            }
            var playlist: [String: String] = [:]
            for key in ["Nrm", "Act", "Sel", "BK", "ABK", "SBK"] { playlist[key] = ini["SKIN_WIDTHS", "switch_" + key] }
            return Settings(playlist: playlist, activeTab: ini["SKIN_FONTS", "activetab"])
        }

        /// The panel's size as the skin was saved: version 3's `ParentBounds`, else its picture's
        /// (the player's is `MainClient` over a state of `BottomDock`).
        private func panelSize(_ object: Placed) -> CGSize {
            if let size = object.parentSize { return size }
            guard object.item == "MainFrame" else { return images[object.item.lowercased() + ".img"]?.frameSize ?? .zero }
            let client = images["mainclient.img"]?.frameSize ?? .zero
            let dock = images["bottomdock.img"].map { $0.height > 1 && $0.height % 2 == 0 ? $0.height / 2 : $0.height } ?? 0
            return CGSize(width: client.width, height: client.height + CGFloat(dock))
        }

        // MARK: Layout

        /// The player's item tree in AIMP 3.0's attribute style: version 3's `MainLayout.xml` (the
        /// playlist frame's `PlaylistLayout.xml`), which it must have and read, or version 2's fixed one.
        private func mainLayout() throws -> AIMPNode {
            let main = isVersion2 ? [item(control: "MainFrame", align: "top", level: 0), item(control: "PlaylistFrame", align: "client", level: 0)]
                : try documents.throwing("MainLayout.xml", missing: "An AIMP 2 skin with no MainLayout.xml.", documents.items)
            return AIMPNode.element("layout", [:], try main.map(translated))
        }

        /// `PlaylistLayout.xml`'s items, which version 3 must have and read when its layout holds the
        /// playlist frame, or version 2's: tabs over the top panel when `TabCtrlIsUp`, under it otherwise.
        private func playlistLayout() throws -> [AIMPNode] {
            guard isVersion2 else {
                return try documents.throwing("PlaylistLayout.xml", missing: "An AIMP 2 skin with no PlaylistLayout.xml.", documents.items)
            }
            let tabsUp = ini["SKIN_WIDTHS", "tabctrlisup"] != "0"
            return [item(control: "TabCtrl", align: "top", level: tabsUp ? 0 : 1),
                    item(control: "TopPanel", align: "top", level: tabsUp ? 1 : 0),
                    item(control: "BottomPanel", align: "bottom", level: 0),
                    item(control: "Container", align: "client", level: 0)]
        }

        private func item(control: String, align: String, level: Int) -> AIMPNode {
            AIMPNode.element("item", ["Control": control, "Align": align, "Level": String(level)])
        }

        /// One AIMP 2 layout item as AIMP 3.0 writes it: named after its panel, the playlist and
        /// its tabs dock sites, the player and the playlist frame groups of their parts.
        private func translated(_ source: AIMPNode) throws -> AIMPNode {
            var attributes = ["Class": "TAIMPLayoutItem", "Align": source["Align"] ?? "top", "AlignLevel": source["Level"] ?? "0"]
            var children = try source.children("item").map(translated)
            switch source["Control"] {
            case "MainFrame":
                attributes["Name"] = "MainFrame"
                children = [AIMPNode.element("item", ["Name": "MainClient", "Class": "TAIMPLayoutItem", "Align": "top", "AlignLevel": "0"]),
                            AIMPNode.element("item", ["Name": "BottomDock", "Class": "TAIMPLayoutItem", "Align": "top", "AlignLevel": "1"])]
            case "EqualizerFrame":
                attributes["Name"] = "MainEquaFrame"
            case "PlaylistFrame":
                attributes["Name"] = "PlaylistFrame"
                let list = AIMPNode.element("item", ["Class": "TAIMPLayoutItem", "Align": "client", "AlignLevel": "2"],
                                            try playlistLayout().map(translated))
                children = [("PlsBottomBar", "bottom", "0"), ("PlsLeftBar", "left", "1"), ("PlsRightBar", "right", "1")]
                    .filter { images[$0.0.lowercased() + ".img"] != nil }
                    .map { AIMPNode.element("item", ["Name": $0.0, "Class": "TAIMPLayoutItem", "Align": $0.1, "AlignLevel": $0.2]) } + [list]
            case let control?:
                attributes["Name"] = control
                if control == "Container" || control == "TabCtrl" { attributes["Class"] = "TAIMPLayoutDockSiteItem" }
            case nil:
                break
            }
            return AIMPNode.element("item", attributes, children)
        }
    }
}
