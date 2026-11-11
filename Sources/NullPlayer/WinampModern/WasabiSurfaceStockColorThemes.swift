import Foundation

/// Winamp's stock colour-theme window content, which `WasabiSurfaceSynthesizer.synthesize` appends
/// for a skin that names it and does not define it.
extension WasabiSurfaceSynthesizer {
    /// The group a skin's `colorthemes` container names as its content. Winamp defines it itself (a
    /// description, the theme list and the Switch button), so a skin may name it without defining
    /// it: Qwest_V2's Color Themes window was a black box (B420). Skins that define it
    /// (`inherit_content="1"` plus `sendparams`) restyle the stock group, and are left alone.
    static let stockColorThemesGroupIdentifier = "colorthemes.titlebox.content"

    /// A `<group id=…>` instance or a `content=` naming the group, anywhere in the document.
    private static func isNamed(_ id: String, in nodes: [WalXMLNode]) -> Bool {
        nodes.contains { node in
            let name = node.name.lowercased()
            let names = [name == "group" ? node.attribute("id") : nil, node.attribute("content")]
            return names.contains { $0.map { fold($0) == fold(id) } == true } || isNamed(id, in: node.children)
        }
    }

    /// That group, for a skin whose declared window names it and which does not define it: the
    /// skin's `<gammaset>` names in a list, and a Switch button that applies the picked one.
    static func stockColorThemesContentGroup(document: WalExpandedXMLDocument,
                                             definitions: [String: WalXMLNode]) -> WalXMLNode? {
        let id = stockColorThemesGroupIdentifier
        guard definitions[fold(id)] == nil, isNamed(id, in: document.roots) else { return nil }
        let location = WalSourceLocation(path: sourcePath)
        let list = WalXMLNode(name: "ColorThemes:List", attributes: [
            "id": "colorthemes.stock.list", "x": "0", "y": "0", "w": "0", "h": "-24", "relatw": "1", "relath": "1",
        ], location: location)
        let apply = WalXMLNode(name: "Wasabi:Button", attributes: [
            "id": "colorthemes.stock.switch", "action": "colorthemes_switch",
            "action_target": "colorthemes.stock.list", "text": "Switch",
            "x": "0", "y": "-21", "relaty": "1", "w": "60", "h": "21",
        ], location: location)
        return WalXMLNode(name: "groupdef", attributes: ["id": id], location: location,
                          children: [list, apply])
    }
}
