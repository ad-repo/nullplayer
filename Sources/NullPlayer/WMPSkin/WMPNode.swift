import Foundation

enum WMPElementKind: Hashable, CustomStringConvertible {
    case theme, view, subview, text, statusText, currentPositionText, image, button, buttonGroup, buttonElement
    case slider, volumeSlider, seekSlider, balanceSlider, customSlider, progressBar
    case playElement, pauseElement, stopElement, prevElement, nextElement
    case rewElement, ffwdElement
    case playButton, pauseButton, stopButton, prevButton, nextButton
    case rewButton, ffwdButton, muteButton, repeatButton, returnButton, shuffleButton
    case playlist, dropdownPlaylist, video, wmpVideo, effects
    case equalizerSettings, popup, editBox, listBox, player, network, script
    case unknown(String)

    init(tagName: String) {
        switch tagName.lowercased() {
        case "theme": self = .theme
        case "view": self = .view
        case "subview": self = .subview
        case "text": self = .text
        // WMP's readout tags are TEXT controls with a host-supplied value.  Treating the two
        // spellings as unknown left a skin's status and elapsed-time cells absent, even though the
        // adjacent ordinary TEXT metadata cell rendered correctly.
        case "statustext": self = .statusText
        case "currentpositiontext": self = .currentPositionText
        case "image": self = .image
        case "button": self = .button
        case "buttongroup": self = .buttonGroup
        case "buttonelement": self = .buttonElement
        case "slider": self = .slider
        case "volumeslider": self = .volumeSlider
        case "seekslider": self = .seekSlider
        case "balanceslider": self = .balanceSlider
        case "customslider": self = .customSlider
        case "progressbar": self = .progressBar
        // **WMP spells every transport control twice, and only one half was ever a kind.**
        // `<…ELEMENT>` is a `BUTTONELEMENT` subtype — a region of a `BUTTONGROUP`'s mapping image;
        // `<…BUTTON>` is a `BUTTON` subtype with artwork and a frame of its own. The table had
        // `playElement` but no `playButton`, `pauseButton` but no `pauseElement`, and so on for
        // every pair, so half of the vocabulary fell to `.unknown`: the node still painted its
        // `image`, was not interactive, and had no transport action, which is a play button that
        // draws and does nothing. Measured over the 172-archive markup census
        // (`scripts/wmp_markup_census.sh`), the missing spellings are
        // `PAUSEELEMENT` 80 uses / 69 skins, `PLAYBUTTON` 50 / 45, `PREVBUTTON` 50 / 45,
        // `NEXTBUTTON` 49 / 44, `STOPBUTTON` 48 / 42, `MUTEBUTTON` 10 / 9 and `REPEATBUTTON` 5 / 4.
        // `MUTEELEMENT`, `REPEATELEMENT`, `SHUFFLEELEMENT` and `RETURNELEMENT` are zero in the
        // corpus and are deliberately absent: a kind nothing authors is a phantom.
        case "playelement": self = .playElement
        case "pauseelement": self = .pauseElement
        case "stopelement": self = .stopElement
        case "prevelement": self = .prevElement
        case "nextelement": self = .nextElement
        case "rewelement": self = .rewElement
        case "ffwdelement": self = .ffwdElement
        case "playbutton": self = .playButton
        case "pausebutton": self = .pauseButton
        case "stopbutton": self = .stopButton
        case "prevbutton": self = .prevButton
        case "nextbutton": self = .nextButton
        case "rewbutton": self = .rewButton
        case "ffwdbutton": self = .ffwdButton
        case "mutebutton": self = .muteButton
        case "repeatbutton": self = .repeatButton
        case "returnbutton": self = .returnButton
        case "shufflebutton": self = .shuffleButton
        case "playlist": self = .playlist
        // **`ITEMSPLAYLIST` is a `PLAYLIST`, and the corpus is what says so.** 8 of the 179 measured
        // archives declare one — `corona`, `Optik`, `anemone`, `aoe`, `claw`, `gadget`, `gnome`,
        // `pharaoh` — and **not one of them declares a `PLAYLIST` beside it**, so it is the only
        // playlist those skins have. Falling to `.unknown` made it no widget at all, which is why
        // W93's routing correctly stood our window aside for a drawer that then drew nothing.
        // It maps wholesale rather than earning its own kind because the authored attributes are
        // `PLAYLIST`'s: list geometry (226x174, 187x139, 155x116 …) plus `backgroundColor`,
        // `foregroundColor`, `itemPlayingColor` and `backgroundImage`. `dropdownVisible` (7 of the
        // 8) asks for a playlist *chooser* above the rows, which needs `player.mediaCollection` and
        // is therefore W66's question, not this one — it is unhonoured here exactly as it is on
        // `PLAYLIST`, rather than faked with playlists this player invented.
        case "itemsplaylist": self = .playlist
        case "dropdownplaylist": self = .dropdownPlaylist
        case "video": self = .video
        case "wmpvideo": self = .wmpVideo
        // **`<EFFECTS>` and `<WMPEFFECTS>` are the same surface, and only the second was ever a
        // kind.** 183 uses across 166 of the 177 measured archives spell it `<EFFECTS>` against
        // `<WMPEFFECTS>`'s 5 of 5, so the visualization surface of the whole corpus fell to
        // `.unknown`, `widgetKind` answered nil, and nothing was ever hosted in a rect the skin had
        // already sized for it (W101). Reproduce with
        // `scripts/wmp_markup_census.sh <outdir> EFFECTS WMPEFFECTS`.
        case "effects", "wmpeffects": self = .effects
        case "equalizersettings": self = .equalizerSettings
        case "popup": self = .popup
        case "editbox": self = .editBox
        case "listbox": self = .listBox
        case "player": self = .player
        case "network": self = .network
        case "script": self = .script
        default: self = .unknown(tagName)
        }
    }

    var description: String {
        switch self {
        case .theme: return "theme"
        case .view: return "view"
        case .subview: return "subview"
        case .text: return "text"
        case .statusText: return "statusText"
        case .currentPositionText: return "currentPositionText"
        case .image: return "image"
        case .button: return "button"
        case .buttonGroup: return "buttonGroup"
        case .buttonElement: return "buttonElement"
        case .slider: return "slider"
        case .volumeSlider: return "volumeSlider"
        case .seekSlider: return "seekSlider"
        case .balanceSlider: return "balanceSlider"
        case .customSlider: return "customSlider"
        case .progressBar: return "progressBar"
        case .playElement: return "playElement"
        case .pauseElement: return "pauseElement"
        case .stopElement: return "stopElement"
        case .prevElement: return "prevElement"
        case .nextElement: return "nextElement"
        case .rewElement: return "rewElement"
        case .ffwdElement: return "ffwdElement"
        case .playButton: return "playButton"
        case .pauseButton: return "pauseButton"
        case .stopButton: return "stopButton"
        case .prevButton: return "prevButton"
        case .nextButton: return "nextButton"
        case .rewButton: return "rewButton"
        case .ffwdButton: return "ffwdButton"
        case .muteButton: return "muteButton"
        case .repeatButton: return "repeatButton"
        case .returnButton: return "returnButton"
        case .shuffleButton: return "shuffleButton"
        case .playlist: return "playlist"
        case .dropdownPlaylist: return "dropdownPlaylist"
        case .video: return "video"
        case .wmpVideo: return "wmpVideo"
        case .effects: return "effects"
        case .equalizerSettings: return "equalizerSettings"
        case .popup: return "popup"
        case .editBox: return "editBox"
        case .listBox: return "listBox"
        case .player: return "player"
        case .network: return "network"
        case .script: return "script"
        case let .unknown(name): return "unknown(\(name))"
        }
    }
}

final class WMPNode {
    let stableID: Int
    let kind: WMPElementKind
    let authoredTagName: String
    let attributes: [WMPAttribute]
    let location: WMPSourceLocation
    weak var parent: WMPNode?
    private(set) var children: [WMPNode] = []

    var xmlID: String? { attribute(named: "id")?.rawValue }

    init(stableID: Int, xml: WMPXMLNode) {
        self.stableID = stableID
        kind = WMPElementKind(tagName: xml.name)
        authoredTagName = xml.name
        attributes = xml.attributes.map {
            WMPAttribute(name: $0.name, rawValue: $0.value,
                         value: WMPAttributeParser.parse(name: $0.name, value: $0.value))
        }
        location = xml.location
    }

    func attribute(named name: String) -> WMPAttribute? {
        attributes.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }
    }

    fileprivate func append(_ node: WMPNode) {
        node.parent = self
        children.append(node)
    }
}

final class WMPObjectGraph {
    let roots: [WMPNode]
    let allNodes: [WMPNode]
    let diagnostics: [WMPDiagnostic]
    private let nodesByFoldedID: [String: [WMPNode]]

    init(document: WMPXMLDocument) {
        var nextID = 1
        var flat: [WMPNode] = []
        var byID: [String: [WMPNode]] = [:]
        var findings: [WMPDiagnostic] = []

        func build(_ xml: WMPXMLNode, parent: WMPNode?) -> WMPNode {
            let node = WMPNode(stableID: nextID, xml: xml)
            nextID += 1
            flat.append(node)
            if let id = node.xmlID, !id.isEmpty {
                let folded = WMPPath.fold(id)
                if let first = byID[folded]?.first {
                    findings.append(WMPDiagnostic(.duplicateIdentifier,
                        "Identifier '\(id)' duplicates the node at \(first.location).",
                        severity: .warning, location: node.location))
                }
                byID[folded, default: []].append(node)
            }
            for childXML in xml.children { node.append(build(childXML, parent: node)) }
            return node
        }

        roots = document.roots.map { build($0, parent: nil) }
        allNodes = flat
        nodesByFoldedID = byID
        diagnostics = findings
    }

    func nodes(id: String) -> [WMPNode] { nodesByFoldedID[WMPPath.fold(id)] ?? [] }

    func dump() -> String {
        allNodes.map { node in
            let parent = node.parent.map { String($0.stableID) } ?? "-"
            let attrs = node.attributes.map { "\($0.name)=\($0.rawValue)" }.joined(separator: ",")
            return "\(node.stableID) parent=\(parent) tag=\(node.authoredTagName) kind=\(node.kind) [\(attrs)] @\(node.location)"
        }.joined(separator: "\n")
    }
}
