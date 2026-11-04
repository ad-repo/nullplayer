import CoreGraphics
import Foundation

extension AIMPSkinLegacy {
    /// Builds the form tree the later formats have from an AIMP 3.0 attribute-style item tree and
    /// the `Object`s and `Settings` a reader found in `main.ini`.
    struct Translator {
        let documents: AIMPSkinDocuments
        let images: [String: AIMPSkinImage]
        let settings: Settings
        /// A window of the skin's own that the equalizer keys show and hide (AIMP 2's); nil when
        /// they open the equalizer as AIMP's action does.
        let equalizerWindow: String?
        /// Each item's objects, back to front, by the item's name.
        let objects: [String: [Object]]
        var unnamed = 0

        init(documents: AIMPSkinDocuments, images: [String: AIMPSkinImage], objects: [Object], settings: Settings,
             equalizerWindow: String? = nil) {
            self.documents = documents
            self.images = images
            self.settings = settings
            self.equalizerWindow = equalizerWindow
            self.objects = Dictionary(grouping: objects, by: \.item).mapValues { $0.sorted { $0.z < $1.z } }
        }

        /// A picture that draws: AIMP 3.0 keeps a 0×0 one for every object.
        func picture(_ name: String) -> AIMPSkinImage? {
            images[(name + ".img").lowercased()].flatMap { $0.hasPixels ? $0 : nil }
        }

        mutating func form(_ layout: AIMPNode) -> AIMPNode {
            var items: [AIMPNode] = []
            for child in layout.children("item") { items.append(item(child)) }
            let root = AIMPNode.element("item", ["class": "LayoutContainer", "name": "AIMP3Form"], [
                AIMPNode.propertyList([AIMPNode.property("Alignment", "laClient")]),
                AIMPNode.element("items", [:], items),
            ])
            let size = naturalSize(root)
            var props = [AIMPNode.property("Alignment", "laClient"), AIMPNode.property("SizeMinimal", "\(Int(size.width)),\(Int(size.height))")]
            // The window sizes from its edges (`[MainFrame]`); the size above is its smallest.
            if let edge = settings.sizingEdge { props.append(AIMPNode.property("SizingHitTestAreaWidth", edge)) }
            return AIMPNode.element("layout", [:], [AIMPNode.element("items", [:], [
                AIMPNode.element("item", root.attributes, [
                    AIMPNode.propertyList(props),
                    AIMPNode.element("items", [:], items),
                ]),
            ])])
        }

        /// One layout item, its children docked lowest `AlignLevel` first, and the controls
        /// `[Parents]` puts in it.
        mutating func item(_ source: AIMPNode) -> AIMPNode {
            let name: String
            if let given = source["Name"] {
                name = given
            } else {
                unnamed += 1
                name = "AIMP3Item\(unnamed)"
            }
            let align = ["top": "laTop", "bottom": "laBottom", "left": "laLeft", "right": "laRight", "client": "laClient"][
                source["Align"] ?? "top"] ?? "laTop"
            var props = [AIMPNode.property("Alignment", align)]
            if let margins = source["AlignMargins"] { props.append(AIMPNode.property("AlignmentMargins", margins)) }
            if picture(name) != nil { props.append(AIMPNode.property("Texture", name)) }
            var items: [AIMPNode] = []
            for child in source.children("item").enumerated()
                .sorted(by: { (Int($0.element["AlignLevel"] ?? "") ?? 0, $0.offset) < (Int($1.element["AlignLevel"] ?? "") ?? 0, $1.offset) }) {
                items.append(item(child.element))
            }
            var controls: [AIMPNode] = []
            if source["Class"] == "TAIMPLayoutDockSiteItem" {
                // A dock site holds a frame of its own layout (`PlaylistFrame`; the equalizer's is
                // `EqFrame`); one that does not read is a finding, and the site is left as if it had none.
                if let layout = documents.node(name == "EqualizerFrame" ? "EqFrame.xml" : name + ".xml") {
                    items = []
                    for child in layout.children("item") { items.append(item(child)) }
                } else if name == "TabCtrl" {
                    controls += tabs()
                    // With no bar of its own, the row is as tall as its tab (AIMP 2's Old Systems).
                    if picture(name) == nil, let tab = picture("TabCtrlTab") {
                        props.append(AIMPNode.property("SizeMinimal", "0,\(Int(tab.frameSize.height))"))
                    }
                } else if name == "Container" {
                    controls += playlist()
                    props.append(AIMPNode.property("SizeMinimal", "0,170"))
                }
            }
            // An item with no picture is as big as what docks in it; the renderer is told so.
            let content = contentSize(AIMPNode.element("item", [:], [AIMPNode.propertyList(props), AIMPNode.element("items", [:], items)]))
            if picture(name) == nil, !props.contains(where: { $0["name"] == "SizeMinimal" }), content.width > 0 || content.height > 0 {
                props.append(AIMPNode.property("SizeMinimal", "\(Int(content.width)),\(Int(content.height))"))
            }
            controls += self.controls(in: name, size: content)
            return AIMPNode.element("item", ["class": "LayoutContainer", "name": name], [
                AIMPNode.propertyList(props), AIMPNode.element("items", [:], items), AIMPNode.element("controls", [:], controls),
            ])
        }

        /// The playlist tabs: NullPlayer has one playlist, its tab lit.
        func tabs() -> [AIMPNode] {
            guard let tab = picture("TabCtrlTab") else { return [] }
            let size = tab.frameSize
            return [AIMPNode.element("control", ["class": "TextDisplay", "name": "PlaylistTab"], [AIMPNode.propertyList([
                placement(anchors: [1, 1, 0, 0], margins: [0, 0, 0, 0], size: size),
                AIMPNode.property("Skin", "TabCtrlTab"), AIMPNode.property("Frame", tab.frameCount > 2 ? "2" : "0"),
                AIMPNode.property("Caption", "Playlist"), AIMPNode.property("Font", settings.activeTab ?? "Tahoma,0,12,0"),
            ])])]
        }

        /// The playlist in `[Playlist]`'s fonts and colours, its scroll bar down the right.
        func playlist() -> [AIMPNode] {
            var resources: [AIMPNode] = []
            for (resource, key) in [("ItemLine1Font", "Nrm"), ("ItemLine1FontPlaying", "Act"), ("ItemLine1FontSelected", "Sel"),
                                    ("ItemLine1FontPlayingSelected", "SelAct"), ("BackgroundColor", "BK"),
                                    ("ItemHighlightColorPlaying", "ABK"), ("ItemHighlightColorSelected", "SBK"),
                                    ("ItemHighlightColorSelectedPlaying", "SABK")] {
                if let value = settings.playlist[key] { resources.append(AIMPNode.property(resource, value)) }
            }
            let bar = Int(picture("PlaylistScroll")?.frameSize.width ?? 0)
            var controls = [AIMPNode.element("control", ["class": "Panel", "name": "Playlist", "link": "Playlist"], [AIMPNode.propertyList([
                placement(anchors: [1, 1, 1, 1], margins: [0, 0, bar, 0], size: .zero),
                AIMPNode.element("property", ["name": "Resources"], resources),
            ])])]
            if bar > 0 {
                var props = [placement(anchors: [0, 1, 1, 1], margins: [0, 0, 0, 0], size: CGSize(width: bar, height: 0)),
                             AIMPNode.property("Skin", "PlaylistScroll"),
                             AIMPNode.bindings(AIMPNode.binding("Playlist", "Position", "Action"))]
                if picture("PlaylistScroll_thumb") != nil { props.append(AIMPNode.property("SkinThumb", "PlaylistScroll_thumb")) }
                controls.append(AIMPNode.element("control", ["class": "ScrollBar", "name": "PlaylistScroll"], [AIMPNode.propertyList(props)]))
            }
            return controls
        }

        /// The controls in `item`, back to front, less those parked.
        func controls(in item: String, size: CGSize) -> [AIMPNode] {
            (objects[item] ?? []).flatMap { object -> [AIMPNode] in
                let rect = AIMPPlacement.rect(anchors: object.anchors, margins: object.margins, size: object.size,
                                              in: CGRect(origin: .zero, size: size)) ?? .zero
                // Parked objects sit left of or above the item; those past its right or bottom edge
                // show when the window grows (Vega's EQ, right of the info panel).
                guard rect.width > 0, rect.height > 0, rect.maxX > 0, rect.maxY > 0 else { return [] }
                return control(object)
            }
        }

        /// The control, or controls, an object is.
        func control(_ object: Object) -> [AIMPNode] {
            let name = object.name
            let place = placement(anchors: object.anchors, margins: object.margins, size: object.size)
            var props = [place]
            var cls = "Button"
            func bind(_ source: String, _ pin: String, _ target: String) {
                props.append(AIMPNode.bindings(AIMPNode.binding(source, pin, target)))
            }
            func font() { if let font = object.font { props.append(AIMPNode.property("Font", font)) } }
            func align() {
                if let align = [1: "taRightJustify", 2: "taCenter"][object.textAlign ?? 0] { props.append(AIMPNode.property("Alignment", align)) }
            }
            let thumb = picture(name + "_thumb") != nil
            if picture(name) != nil { props.append(AIMPNode.property("Skin", name)) }
            switch object.kind {
            case .text(let template):
                cls = "TextDisplay"
                if template.contains("%") {
                    props.append(AIMPNode.property("Template", template))
                    bind("prvPlayingFileInfo", "FileInfo", "DisplayValue")
                } else {
                    props.append(AIMPNode.property("Caption", template))
                }
                font()
                align()
            case .time(let time, let digits, let indent):
                cls = "TimeDisplay"
                props += [AIMPNode.property("Digits", digits), AIMPNode.property("IndentBetweenDigits", indent)]
                let pin = switch time {
                case .duration: "TrackDuration"
                case .remaining: "TrackPositionRemaining"
                case .position: "TrackPosition"
                }
                bind("prvPlayerState", pin, "DisplayValue")
            case .bitrate:
                cls = "DigitsDisplay"
                bind("prvPlayingFileInfo", "Bitrate", "DisplayValue")
            case .sampleRate:
                cls = "DigitsDisplay"
                bind("prvPlayingFileInfo", "SampleRate", "DisplayValue")
            case .status(let showsState):
                // A picture per state: stopped, playing, paused.
                cls = "DigitsDisplay"
                props.append(AIMPNode.property("Digits", "1"))
                if showsState { bind("prvPlayerState", "State", "DisplayValue") }
            case .seekBar:
                cls = "SeekBar"
                if thumb { props.append(AIMPNode.property("SkinThumb", name + "_thumb")) }
            case .animator(let interval):
                // AIMP 3 runs them all the time (Vega's logo turns while stopped; a lamp over it hides
                // it while playing).
                cls = "Animator"
                props += [AIMPNode.property("AnimationInterval", interval),
                          AIMPNode.bindings(AIMPNode.binding("AIMPMainForm", "Visible", "Accessibility"))]
            case .spectrum(let peaks, let indent, let colour, let flipped):
                // Its picture is the empty display; the bars are `Color` (a Delphi colour), `Peaks` of them.
                var spectrum = [place, AIMPNode.property("ColumnsCount", peaks), AIMPNode.property("ColumnsIndent", indent)]
                if let colour { spectrum.append(AIMPNode.property("Color", String(AIMPSkinColor.argb(delphi: colour)))) }
                if flipped { spectrum.append(AIMPNode.property("FlipVertically", "True")) }
                return [AIMPNode.element("control", ["class": "TextDisplay", "name": name + "Back"], [AIMPNode.propertyList(props)]),
                        AIMPNode.element("control", ["class": "SpectrumDisplay", "name": name], [AIMPNode.propertyList(spectrum)])]
            case .coverArt:
                // Its picture with no cover, the cover over it.
                return [AIMPNode.element("control", ["class": "TextDisplay", "name": name + "Back"], [AIMPNode.propertyList(props)]),
                        AIMPNode.element("control", ["class": "CoverArtDisplay", "name": name], [AIMPNode.propertyList([place])])]
            case .equalizerDisplay(let curve, let preamp):
                // Its picture is the grid; the curve is `EQVISE`, the preamp line `EQVISL`.
                cls = "EqualizerDisplay"
                for (key, colour) in [("ColorCurve", curve), ("ColorPreamp", preamp)] {
                    if let colour {
                        props.append(AIMPNode.element("property", ["name": key], [AIMPNode.property("Value", String(AIMPSkinColor.argb(delphi: colour)))]))
                    }
                }
            case .object(let key):
                guard let made = aimpObject(key, name: name, thumb: thumb, orientation: object.orientation, into: &props) else { return [] }
                cls = made
                if key == "infobar" || key == "countlabel" || key == "lengthlabel" { font() }
                if key == "countlabel" || key == "lengthlabel" { align() }
            }
            return [AIMPNode.element("control", ["class": cls, "name": name], [AIMPNode.propertyList(props)])]
        }

        /// The control class of AIMP's own object `key`, its bindings added to `props`; nil for an
        /// object NullPlayer has no counterpart for and that draws nothing.
        private func aimpObject(_ key: String, name: String, thumb: Bool, orientation: Int?, into props: inout [AIMPNode]) -> String? {
            func bind(_ source: String, _ pin: String, _ target: String) {
                props.append(AIMPNode.bindings(AIMPNode.binding(source, pin, target)))
            }
            if let window = equalizerWindow, key == "eqbtn" || key == "hidebtn" {
                // AIMP 2's equalizer is a window beside the player: its key and the window's own
                // hide key show and hide it.
                bind(window, "Visible", "Action")
            } else if let action = Self.actions[key] {
                bind(action, "Action", "Action")
            } else if key == "playpausebtn" {
                // Play's four frames, then pause's, shown while playing.
                props += [AIMPNode.property("FramesPerState", "4"),
                          AIMPNode.bindings(AIMPNode.binding("acPlayerPlayPause", "Action", "Action"),
                                            AIMPNode.binding("prvPlayerState", "State", "State"))]
            } else if let action = Self.switches[key] {
                props.append(AIMPNode.property("FramesPerState", "3"))
                bind(action, "Action", "Action")
                return "Switch"
            } else if let menu = Self.menus[key] {
                props.append(AIMPNode.property("PopupMenu", menu))
            } else if let provider = Self.sliders[key] ?? (key == "preamp" || key.hasPrefix("aimpslider") ? "prvEqualizer" : nil) {
                // `Orientation` 0 upright, 1 across, 2 a knob turned through its frames.
                let cls = orientation == 2 ? "SliderMasked" : orientation == 1 ? "Slider" : "SliderVertical"
                if thumb, cls != "SliderMasked" { props.append(AIMPNode.property("SkinThumb", name + "_thumb")) }
                let pin = key == "preamp" ? "Preamp" : key.hasPrefix("aimpslider") ? "Band" + key.dropFirst(10) : "Action"
                bind(provider, pin, "Action")
                return cls
            } else if key == "infobar" {
                return "RunningLine"
            } else if key == "countlabel" || key == "lengthlabel" {
                bind("Playlist", key == "countlabel" ? "Count" : "Duration", "DisplayValue")
                if key == "lengthlabel" { props.append(AIMPNode.property("Template", "%time(HMS;:;)")) }
                return "TextDisplay"
            } else if picture(name) == nil {
                return nil
            }
            return "Button"
        }

        private static let actions = [
            "playbtn": "acPlayerPlay", "pausebtn": "acPlayerPause", "stopbtn": "acPlayerStop",
            "prevbtn": "acPlayerPrevTrack", "nextbtn": "acPlayerNextTrack", "openbtn": "acPlayerOpenFiles",
            "closebtn": "acMainExit", "totraybtn": "acMainMinimize", "fileinfo": "acPlayableFileShowFileInfoAtCursor",
            "tageditbtn": "acSendToTagEditor", "tagedit": "acSendToTagEditor", "eqbtn": "acEqualizerShow",
            "plsbtn": "acPlaylistShow", "lib": "acMainShowMusicLibrary", "visualbtn": "acVisualizationShow",
            "dspbtn": "acMainDSPManager", "capradio": "acPlayerRadioCapture",
            "qficopyfile": "acPlayableFileCopyFileToClipboard", "qficopyfileinfo": "acPlayableFileCopyInfoToClipboard",
        ]
        private static let switches = ["shuffle": "acPlayerShuffle", "repeat_": "acPlayerRepeat", "stayontop": "acMainStayOnTop",
                                       "mutebtn": "acPlayerVolumeMute", "eqswitch": "acEqualizerSwitch"]
        private static let sliders = ["volumebar": "prvVolume", "balanceslider": "prvBalance", "speedslider": "prvSpeed",
                                      "temposlider": "prvTempo", "pitchslider": "prvPitch"]
        private static let menus = ["menubtn": "pmMenu", "addbtn": "pmAdd", "delbtn": "pmDelete", "sortbtn": "pmSort",
                                    "miscbtn": "pmMisc", "plsopt": "pmPlaylist", "btnplaylistslistmenu": "pmPlaylists"]

        /// What an item takes up when nothing stretches it, its `AlignmentMargins` around it.
        func naturalSize(_ item: AIMPNode) -> CGSize { AIMPSkinItem.Layout(item).slot(contentSize(item)) }

        /// An item's own size: its picture, else its children docked around each other, its
        /// clients over one another.
        func contentSize(_ item: AIMPNode) -> CGSize {
            var size = item.properties["Texture"]?["value"].flatMap { picture($0)?.frameSize } ?? .zero
            if size == .zero {
                size = AIMPSkinAlignment.aggregate((item.child("items")?.children("item") ?? []).map {
                    (AIMPSkinItem.Layout($0).dock, naturalSize($0))
                }, clients: .overlap)
            }
            return AIMPSkinItem.Layout(item).floored(size)
        }

        func placement(anchors: [Int], margins: [Int], size: CGSize) -> AIMPNode {
            AIMPNode.element("property", ["name": "PlaceInfo", "anchors": anchors.map(String.init).joined(separator: ","),
                                          "margins": margins.map(String.init).joined(separator: ","),
                                          "Size": "\(Int(size.width)),\(Int(size.height))"], [])
        }
    }
}
