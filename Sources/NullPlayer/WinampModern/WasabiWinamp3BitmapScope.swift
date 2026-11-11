import Foundation

/// A Winamp3 skin's window takes the bitmap definition in effect where the window is declared (B401).
///
/// Winamp's parser streams the document, and a skin can define one bitmap id twice. The resource
/// registry lets the later definition win, which is what Winamp 5 skins are written against:
/// cPro-Bento's `custom-element-overide.xml` comes after the engine's `load.xml` that declares `main`,
/// and SpongeBob_Squarepants (`version="1.2"`) redefines `main.vol.*` for its EQ windowshade.
/// Lapis_Lazuli (`version="0.8"`) defines `glass` as its dome sheen in `player-elements.xml` and again
/// as a 195x21 rounded bar in `standardframe.xml`, included after its player, and its Winamp3
/// screenshot shows the sheen: there the player kept the definition read before it.
///
/// So, for a document whose `<WinampAbstractionLayer>` declares a version below 1 only, an attribute
/// naming a twice-defined bitmap is pointed at the definition in effect at its container's position,
/// registered under a private id. `0.8` is not Winamp3-only (141 of 315 gold+silver skins declare it),
/// but this changes the resolution in four (Lapis_Lazuli, Jenna_loves_mambo, Moonkore, NightWing_II),
/// and the render only in Lapis and a 3px corner of NightWing_II's playlist.
///
/// ponytail: rewritten once, on the objects built at load. A script's later `setXmlParam("image", id)`
/// and a dynamic container copied at runtime resolve the id as the registry does (the last definition).
enum WasabiWinamp3BitmapScope {

    /// Attribute keys that never name a bitmap, so an object whose own id matches one is left alone.
    private static let nonBitmapKeys: Set<String> = [
        "id", "name", "text", "default", "tooltip", "param", "action", "display", "font", "group",
    ]

    static func apply(roots: [WalXMLNode], graph: WasabiObjectGraph, resources: WalResourceRegistry) {
        guard declaresWinamp3(roots) else { return }
        // Pre-order, the parser's reading order: every `<bitmap>` and `<container>` with its position.
        var bitmaps: [String: [Int]] = [:]
        var containerOrders: [Int] = []
        var next = 0
        func walk(_ nodes: [WalXMLNode]) {
            for node in nodes {
                let order = next
                next += 1
                let name = node.name.lowercased()
                if name == "bitmap", let id = node.attribute("id"), !id.isEmpty {
                    bitmaps[id.lowercased(), default: []].append(order)
                } else if name == "container" {
                    containerOrders.append(order)
                }
                walk(node.children)
            }
        }
        walk(roots)

        // The registry holds the same definitions in the same order, already resolved to files.
        var registered: [String: [WalResourceDefinition]] = [:]
        for definition in resources.definitions
        where definition.kind.caseInsensitiveCompare("bitmap") == .orderedSame && !definition.isImplicit {
            guard let id = definition.identifier?.lowercased(), bitmaps[id] != nil else { continue }
            registered[id, default: []].append(definition)
        }
        let redefined = registered.filter { id, versions in
            versions.count > 1 && versions.count == bitmaps[id]?.count
                && Set(versions.map { "\($0.logicalFile ?? "")|\($0.attributes)" }).count > 1
        }
        let containers = graph.roots.filter { $0.tag.is(.container) }
        guard !redefined.isEmpty, containers.count == containerOrders.count else { return }

        for (container, containerOrder) in zip(containers, containerOrders) {
            var pending = [container]
            while let object = pending.popLast() {
                pending.append(contentsOf: object.children)
                for (key, value) in object.attributes where !nonBitmapKeys.contains(key) {
                    let id = value.lowercased()
                    guard let versions = redefined[id], let orders = bitmaps[id],
                          let index = orders.lastIndex(where: { $0 < containerOrder }),
                          index < versions.count - 1 else { continue }
                    let scoped = "\(value)@winamp3.\(orders[index])"
                    if resources.definition(identifier: scoped) == nil {
                        let earlier = versions[index]
                        resources.register(WalResourceDefinition(
                            kind: earlier.kind, identifier: scoped, logicalFile: earlier.logicalFile,
                            attributes: earlier.attributes, source: earlier.source))
                    }
                    _ = object.setAttribute(key, value: scoped)
                }
            }
        }
    }

    private static func declaresWinamp3(_ roots: [WalXMLNode]) -> Bool {
        var pending = roots
        while let node = pending.popLast() {
            if node.name.caseInsensitiveCompare("WinampAbstractionLayer") == .orderedSame {
                return node.attribute("version").flatMap(Double.init).map { $0 < 1 } ?? false
            }
            pending.append(contentsOf: node.children)
        }
        return false
    }
}
