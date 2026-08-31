import Foundation

enum WMPElementKind: Hashable, CustomStringConvertible {
    case theme, view, subview, text, image, button, buttonGroup, buttonElement
    case slider, volumeSlider, seekSlider, balanceSlider
    case playElement, pauseButton, stopElement, prevElement, nextElement
    case rewButton, rewElement, ffwdButton, ffwdElement, returnButton, shuffleButton
    case playlist, dropdownPlaylist, video, wmpVideo, wmpEffects
    case equalizerSettings, popup, player, network, script
    case unknown(String)

    init(tagName: String) {
        switch tagName.lowercased() {
        case "theme": self = .theme
        case "view": self = .view
        case "subview": self = .subview
        case "text": self = .text
        case "image": self = .image
        case "button": self = .button
        case "buttongroup": self = .buttonGroup
        case "buttonelement": self = .buttonElement
        case "slider": self = .slider
        case "volumeslider": self = .volumeSlider
        case "seekslider": self = .seekSlider
        case "balanceslider": self = .balanceSlider
        case "playelement": self = .playElement
        case "pausebutton": self = .pauseButton
        case "stopelement": self = .stopElement
        case "prevelement": self = .prevElement
        case "nextelement": self = .nextElement
        case "rewbutton": self = .rewButton
        case "rewelement": self = .rewElement
        case "ffwdbutton": self = .ffwdButton
        case "ffwdelement": self = .ffwdElement
        case "returnbutton": self = .returnButton
        case "shufflebutton": self = .shuffleButton
        case "playlist": self = .playlist
        case "dropdownplaylist": self = .dropdownPlaylist
        case "video": self = .video
        case "wmpvideo": self = .wmpVideo
        case "wmpeffects": self = .wmpEffects
        case "equalizersettings": self = .equalizerSettings
        case "popup": self = .popup
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
        case .image: return "image"
        case .button: return "button"
        case .buttonGroup: return "buttonGroup"
        case .buttonElement: return "buttonElement"
        case .slider: return "slider"
        case .volumeSlider: return "volumeSlider"
        case .seekSlider: return "seekSlider"
        case .balanceSlider: return "balanceSlider"
        case .playElement: return "playElement"
        case .pauseButton: return "pauseButton"
        case .stopElement: return "stopElement"
        case .prevElement: return "prevElement"
        case .nextElement: return "nextElement"
        case .rewButton: return "rewButton"
        case .rewElement: return "rewElement"
        case .ffwdButton: return "ffwdButton"
        case .ffwdElement: return "ffwdElement"
        case .returnButton: return "returnButton"
        case .shuffleButton: return "shuffleButton"
        case .playlist: return "playlist"
        case .dropdownPlaylist: return "dropdownPlaylist"
        case .video: return "video"
        case .wmpVideo: return "wmpVideo"
        case .wmpEffects: return "wmpEffects"
        case .equalizerSettings: return "equalizerSettings"
        case .popup: return "popup"
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
