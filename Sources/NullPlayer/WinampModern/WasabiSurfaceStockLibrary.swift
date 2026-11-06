import Foundation

/// Winamp's stock library content group, which `WasabiSurfaceSynthesizer.synthesize` appends for a
/// skin that names it and does not define it. Split out of `WasabiSurfaceSynthesizer.swift`.
extension WasabiSurfaceSynthesizer {
    /// The group a standard frame names as `content` to show the Media Library. Winamp defines it
    /// itself, so a skin may name it without defining it: WinPlain's `ml` window, the MXP flavours,
    /// UltraBM, VISION and Radio_Flash_Online do, and their frame opened empty (B369). Every skin
    /// that does define it defines the same thing — Andromeda, Anime_Shogo, Cannes, Electra and
    /// Koalla_2 — one Media Library `<component>` filling the group.
    static let stockLibraryGroupIdentifier = "library.content.group"

    /// That group, for a skin whose declared window names it and which does not define it.
    static func stockLibraryContentGroup(document: WalExpandedXMLDocument,
                                         definitions: [String: WalXMLNode]) -> WalXMLNode? {
        let id = stockLibraryGroupIdentifier
        guard definitions[fold(id)] == nil, containerHosting(group: id, in: document.roots) != nil,
              let reference = componentReference(for: .library) else { return nil }
        let location = WalSourceLocation(path: sourcePath)
        let component = WalXMLNode(name: "component", attributes: [
            "id": "library.content", "param": reference,
            "x": "0", "y": "0", "w": "0", "h": "0", "relatw": "1", "relath": "1",
        ], location: location)
        return WalXMLNode(name: "groupdef", attributes: ["id": id], location: location,
                          children: [component])
    }
}
