import Foundation

/// Gives a separate-window skin a window for a surface it never declared.
///
/// mmd3 ships a playlist window but no equalizer or library window; CornerAmp ships a playlist and an
/// equalizer but no library; Winamp Modern ships a playlist and a library but no equalizer. In real
/// Winamp those surfaces still open — the *component* supplies its own window frame. We have no such
/// component, so the skin's own standard frame is borrowed instead: a synthetic container holding one
/// `<Wasabi:StandardFrame:…>` around a `<component>` of the missing kind, drawn with the skin's own
/// artwork rather than a foreign chrome.
///
/// This runs on the **expanded document**, before `WasabiSkinInitializer`, so the synthetic XML goes
/// through the same registration, inheritance validation, object creation, and script binding as
/// everything the skin declared. It never edits an initialized graph.
///
/// It also declines readily. A frame that cannot instantiate its content group would produce a titled
/// empty box — worse than the classic window it replaces — so every prerequisite is checked and a
/// failure records why and leaves the surface to the classic fallback.
enum WasabiSurfaceSynthesizer {

    struct Result {
        let document: WalExpandedXMLDocument
        /// Container id per surface this pass created.
        let synthesizedContainers: [WinampModernComponentKind: String]
        /// Why a synthesizable surface got no window, per surface. These become classic fallbacks.
        let unavailable: [WinampModernComponentKind: String]
        /// Routes for app-owned windows. These are descriptors, not synthesized graph containers.
        let hostedWindows: WinampModernHostedWindowCatalog
        let diagnostics: [WalDiagnostic]

        static func unchanged(_ document: WalExpandedXMLDocument,
                              hostedWindows: WinampModernHostedWindowCatalog) -> Result {
            Result(document: document, synthesizedContainers: [:], unavailable: [:],
                   hostedWindows: hostedWindows, diagnostics: [])
        }
    }

    /// Synthetic nodes are sourced here so a diagnostic never points at a file the skin author wrote.
    static let sourcePath = "/System/NullPlayerSurfaceSynthesis.xml"

    /// Default and minimum canvas for a synthesized window, in skin pixels. Sized from the measured
    /// skins' own equivalents (mmd3's `Pledit` is 381×260, CornerAmp's `eq` 275×145).
    private static func geometry(for kind: WinampModernComponentKind)
        -> (defaultSize: CGSize, minimumSize: CGSize) {
        switch kind {
        case .playlist: return (CGSize(width: 400, height: 280), CGSize(width: 275, height: 116))
        case .equalizer: return (CGSize(width: 275, height: 145), CGSize(width: 275, height: 116))
        case .library: return (CGSize(width: 640, height: 400), CGSize(width: 320, height: 200))
        default: return (CGSize(width: 400, height: 280), CGSize(width: 200, height: 100))
        }
    }

    private static func title(for kind: WinampModernComponentKind) -> String {
        switch kind {
        case .playlist: return "Playlist"
        case .equalizer: return "Equalizer"
        case .library: return "Media Library"
        default: return "NullPlayer"
        }
    }

    /// The reference a synthetic `<component>`/`<container component=…>` names. Winamp defines no
    /// equalizer component GUID — no measured skin contains one — so the equalizer uses the `guid:eq`
    /// short form the registry already understands.
    private static func componentReference(for kind: WinampModernComponentKind) -> String? {
        switch kind {
        case .playlist: return "guid:{45F3F7C1-A6F3-4EE6-A15E-125E92FC3F8D}"
        case .library: return "guid:{6B0EDF80-C9A5-11D3-9F26-00C04F39FFC6}"
        case .equalizer: return "guid:eq"
        default: return nil
        }
    }

    static func synthesize(document: WalExpandedXMLDocument,
                           inventory: WinampModernSurfaceInventory,
                           limits: WalXMLLimits = .production) -> Result {
        let kinds = inventory.synthesizableKinds
        let definitions = groupDefinitions(in: document.roots)
        let hostedWindows = hostedWindowCatalog(frame: usableFrame(in: definitions))
        guard !kinds.isEmpty else { return .unchanged(document, hostedWindows: hostedWindows) }

        var appended: [WalXMLNode] = []
        var synthesized: [WinampModernComponentKind: String] = [:]
        var unavailable: [WinampModernComponentKind: String] = [:]
        var diagnostics: [WalDiagnostic] = []
        var budget = limits.maximumExpandedNodeCount - countNodes(document.roots)

        for kind in kinds {
            guard let reference = componentReference(for: kind) else { continue }
            switch usableFrame(in: definitions) {
            case .failure(let reason):
                unavailable[kind] = reason
                diagnostics.append(WalDiagnostic(
                    .missingGroupDefinition,
                    "No usable standard frame to host the \(kind.rawValue) surface (\(reason)); "
                    + "it falls back to NullPlayer's own window.",
                    severity: .warning, location: WalSourceLocation(path: sourcePath)))
            case .success(let frame):
                let nodes = makeNodes(kind: kind, reference: reference, frame: frame)
                let cost = countNodes(nodes)
                guard cost <= budget else {
                    unavailable[kind] = "the expanded document has no room left for synthetic nodes"
                    diagnostics.append(WalDiagnostic(
                        .expandedNodeLimitExceeded,
                        "Synthesizing the \(kind.rawValue) window would exceed the "
                        + "\(limits.maximumExpandedNodeCount)-node budget; it falls back to "
                        + "NullPlayer's own window.",
                        severity: .warning, location: WalSourceLocation(path: sourcePath)))
                    continue
                }
                budget -= cost
                appended.append(contentsOf: nodes)
                synthesized[kind] = containerIdentifier(for: kind)
                if !frame.hasArtwork {
                    diagnostics.append(WalDiagnostic(
                        .resourceMissing,
                        "Standard frame '\(frame.groupIdentifier)' resolves no artwork; the "
                        + "synthesized \(kind.rawValue) window will be plain.",
                        severity: .warning, location: WalSourceLocation(path: sourcePath)))
                }
            }
        }

        guard !appended.isEmpty else {
            return Result(document: document, synthesizedContainers: [:],
                          unavailable: unavailable, hostedWindows: hostedWindows,
                          diagnostics: diagnostics)
        }
        return Result(document: WalExpandedXMLDocument(roots: document.roots + appended,
                                                       visitedPaths: document.visitedPaths,
                                                       diagnostics: document.diagnostics + diagnostics),
                      synthesizedContainers: synthesized,
                      unavailable: unavailable,
                      hostedWindows: hostedWindows,
                      diagnostics: diagnostics)
    }

    static func containerIdentifier(for kind: WinampModernComponentKind) -> String {
        "nullplayer.\(kind.rawValue)"
    }

    // MARK: - Frame selection

    struct Frame {
        let flavour: WasabiStandardFrames.Flavour
        let groupIdentifier: String
        let xuiTag: String
        let hasArtwork: Bool
    }

    private enum FrameSelection {
        case success(Frame)
        case failure(String)
    }

    private static func hostedWindowCatalog(frame: FrameSelection)
        -> WinampModernHostedWindowCatalog {
        let route: WinampModernHostedWindowRoute
        switch frame {
        case .success(let frame):
            route = .skinFrame(WinampModernHostedFrameDescriptor(
                groupIdentifier: frame.groupIdentifier,
                xuiTag: frame.xuiTag,
                hasArtwork: frame.hasArtwork
            ))
        case .failure(let reason):
            route = .classicFallback(reason: reason)
        }
        return WinampModernHostedWindowCatalog(routes: Dictionary(
            uniqueKeysWithValues: WinampModernHostedWindowRegistry.all.map { ($0.id, route) }
        ))
    }

    /// Prefer a status bar, then no status bar, then a static frame — but only accept one the skin
    /// can actually build a window out of.
    private static func usableFrame(in definitions: [String: WalXMLNode]) -> FrameSelection {
        var reasons: [String] = []
        for flavour in WasabiStandardFrames.Flavour.allCases {
            guard let definition = definitions[fold(flavour.groupIdentifier)] else {
                reasons.append("\(flavour.rawValue): the skin declares no '\(flavour.groupIdentifier)'")
                continue
            }
            // A frame builds its client area from `content=` in its own script. Without that script
            // the window would be chrome around an empty hole — exactly what the artwork-less Wasabi
            // shells produce.
            guard hasContentScript(definition, definitions: definitions, depth: 0) else {
                reasons.append("\(flavour.rawValue): '\(flavour.groupIdentifier)' has no frame script "
                               + "to instantiate its content")
                continue
            }
            return .success(Frame(flavour: flavour,
                                  groupIdentifier: flavour.groupIdentifier,
                                  xuiTag: flavour.xuiTag,
                                  hasArtwork: hasArtwork(definition, definitions: definitions, depth: 0)))
        }
        return .failure(reasons.joined(separator: "; "))
    }

    private static let maximumInheritanceDepth = 16

    private static func hasContentScript(_ definition: WalXMLNode,
                                         definitions: [String: WalXMLNode], depth: Int) -> Bool {
        guard depth <= maximumInheritanceDepth else { return false }
        if contains(definition, where: { $0.name.caseInsensitiveCompare("script") == .orderedSame }) {
            return true
        }
        guard let parent = definition.attribute("inherit_group"),
              let inherited = definitions[fold(parent)] else { return false }
        return hasContentScript(inherited, definitions: definitions, depth: depth + 1)
    }

    private static func hasArtwork(_ definition: WalXMLNode,
                                   definitions: [String: WalXMLNode], depth: Int) -> Bool {
        guard depth <= maximumInheritanceDepth else { return false }
        if definition.attribute("background") != nil { return true }
        if contains(definition, where: {
            $0.attribute("image") != nil || $0.attribute("background") != nil
        }) { return true }
        guard let parent = definition.attribute("inherit_group"),
              let inherited = definitions[fold(parent)] else { return false }
        return hasArtwork(inherited, definitions: definitions, depth: depth + 1)
    }

    // MARK: - Node construction

    private static func makeNodes(kind: WinampModernComponentKind, reference: String,
                                  frame: Frame) -> [WalXMLNode] {
        let location = WalSourceLocation(path: sourcePath)
        let geometry = geometry(for: kind)
        let name = title(for: kind)
        let contentGroupID = "nullplayer.\(kind.rawValue).content"

        let component = WalXMLNode(name: "component", attributes: [
            "id": "\(contentGroupID).surface",
            "param": reference,
            "x": "0", "y": "0", "w": "0", "h": "0", "relatw": "1", "relath": "1",
        ], location: location)
        let contentGroup = WalXMLNode(name: "groupdef", attributes: ["id": contentGroupID],
                                      location: location, children: [component])

        let frameNode = WalXMLNode(name: frame.xuiTag, attributes: [
            "id": "\(contentGroupID).frame",
            "content": contentGroupID,
            "componentname": name,
            "x": "0", "y": "0", "w": "0", "h": "0", "relatw": "1", "relath": "1",
        ], location: location)
        let layout = WalXMLNode(name: "layout", attributes: [
            "id": "normal",
            "default_w": String(Int(geometry.defaultSize.width)),
            "default_h": String(Int(geometry.defaultSize.height)),
            "minimum_w": String(Int(geometry.minimumSize.width)),
            "minimum_h": String(Int(geometry.minimumSize.height)),
        ], location: location, children: [frameNode])
        let container = WalXMLNode(name: "container", attributes: [
            "id": containerIdentifier(for: kind),
            "name": name,
            "component": reference,
            "default_visible": "0",
            WinampModernContainerTopology.synthesizedAttribute: "1",
        ], location: location, children: [layout])

        return [contentGroup, container]
    }

    // MARK: - Document helpers

    private static func groupDefinitions(in nodes: [WalXMLNode]) -> [String: WalXMLNode] {
        var result: [String: WalXMLNode] = [:]
        func walk(_ nodes: [WalXMLNode]) {
            for node in nodes {
                if node.name.caseInsensitiveCompare("groupdef") == .orderedSame,
                   let id = node.attribute("id"), !id.isEmpty {
                    result[fold(id)] = node
                }
                walk(node.children)
            }
        }
        walk(nodes)
        return result
    }

    private static func contains(_ node: WalXMLNode, where predicate: (WalXMLNode) -> Bool) -> Bool {
        for child in node.children {
            if predicate(child) || contains(child, where: predicate) { return true }
        }
        return false
    }

    private static func countNodes(_ nodes: [WalXMLNode]) -> Int {
        nodes.reduce(0) { $0 + 1 + countNodes($1.children) }
    }

    private static func fold(_ value: String) -> String {
        value.folding(options: [.caseInsensitive], locale: Locale(identifier: "en_US_POSIX"))
    }
}
