import Foundation

/// What a skin declares, per surface, before anything is instantiated.
///
/// Phase 13 has to answer one question per surface — *does this skin already show a playlist / EQ /
/// library, and where?* — and it has to answer it **before** the graph exists, because the answer
/// decides whether we append synthetic XML for the surfaces the skin leaves out. Reading the live
/// graph instead would come too late (synthesis must go through the normal initialization passes)
/// and would also mistake cPro-Bento's script-built holders for missing surfaces, since at load time
/// its tabs have not built their content yet.
///
/// So this walks the *expanded document*: containers, their layouts, and the groupdefs those layouts
/// can reach. It is deliberately conservative. Where reachability depends on a script's choice, it
/// records the surface as ambiguous and suppresses synthesis: a classic fallback window is a much
/// smaller failure than a second, duplicate skin window.
struct WinampModernSurfaceInventory {

    /// One top-level `<container>` as declared in XML.
    struct Container: Equatable {
        let id: String
        /// The surface this container *is*, from its own `component=` GUID (or an exact short-token
        /// id, for CornerAmp's `<container id="eq">`).
        let kind: WinampModernComponentKind?
        let isMainPlayer: Bool
        /// False for an SUI-collapsed stub (`window-overrides.xml` shrinks cPro's standalone windows
        /// to 1×1 invisible because their surfaces are embedded in the main window).
        let isVisibleWindow: Bool
        /// Surfaces reachable *inside* this container's layouts.
        let reachableKinds: Set<WinampModernComponentKind>
        /// True when this container's layouts reach skin-drawn equalizer controls (`EQ_BAND`,
        /// `EQ_PREAMP`, `<eqvis>`) rather than an EQ component GUID — which is the only way any
        /// measured skin expresses an equalizer, since Winamp has no EQ component GUID.
        let hasEqualizerControls: Bool
    }

    let containers: [Container]
    let arrangement: WinampModernSurfaceArrangement
    /// Surfaces the skin already shows inside its main window.
    let embeddedKinds: Set<WinampModernComponentKind>
    /// Surfaces the skin declares a separate window for, by container id.
    let declaredContainers: [WinampModernComponentKind: String]
    /// Surfaces whose reachability could not be decided declaratively; never synthesized.
    let ambiguousKinds: Set<WinampModernComponentKind>
    let diagnostics: [WalDiagnostic]

    /// The surfaces Phase 13 can host and therefore cares about.
    static let managedKinds: [WinampModernComponentKind] = [.playlist, .equalizer, .library]

    /// The surfaces the catalog routes. `.video` is routed but **not managed** (B20), and the
    /// distinction is doing three separate jobs:
    ///
    /// * it is never **synthesized** — a skin that draws no video window is a skin the host's own
    ///   video window serves, and a synthesized one would be a `.wal` frame around our picture that
    ///   the skin never asked for;
    /// * it is never **embedded** — Winamp Modern's player also declares an invisible in-player
    ///   `windowholder` for the video component, and resolving the surface to that would leave the
    ///   skin's real video window, the one with the chrome and the `VID_*` buttons, empty;
    /// * it stays in the **Skin Windows** menu, because unlike the playlist / EQ / library it has no
    ///   menu item of its own to collide with, and Winamp lists Video in its Windows menu too.
    static let routedKinds: [WinampModernComponentKind] = managedKinds + [.video]

    /// Surfaces with no home in this skin: not embedded, no declared container, not ambiguous, and
    /// only ever non-empty for the separate-window arrangement — an SUI skin that appears to be
    /// missing a surface is not missing it, it builds it from a script at runtime.
    var synthesizableKinds: [WinampModernComponentKind] {
        guard arrangement == .separateWindows else { return [] }
        return Self.managedKinds.filter {
            // The **equalizer** is never synthesized. A synthesized window's body is always a
            // component holder we invented, and unlike the playlist's and the library's, the
            // equalizer's hosted surface is a stand-in — eleven painted tracks with no on/off, auto,
            // presets, labels or scale. Building it produced a window that only NullPlayer's own
            // routing could reach, and worse, two routes that disagreed: the menu resolved through
            // the catalog to the full classic EQ while a skin's `TOGGLE Eq` button found the
            // synthesized container in `routeComponentToggle` and opened the stub instead. A skin
            // that draws its own equalizer is matched as embedded or declared and never reaches here.
            $0 != .equalizer &&
            !embeddedKinds.contains($0) && declaredContainers[$0] == nil && !ambiguousKinds.contains($0)
        }
    }

    // MARK: - Walk

    /// Bounds mirroring the XML loader's: a malicious or merely enormous document must not be able to
    /// make this walk expensive, and a groupdef cycle must terminate.
    struct Limits {
        var maximumVisitedNodes = 50_000
        var maximumGroupDepth = 64
        static let production = Limits()
    }

    static func build(document: WalExpandedXMLDocument, limits: Limits = .production) -> Self {
        var groupdefsByID: [String: WalXMLNode] = [:]
        var groupdefsByXUITag: [String: String] = [:]
        var diagnostics: [WalDiagnostic] = []

        func collectDefinitions(_ nodes: [WalXMLNode]) {
            for node in nodes {
                if node.name.caseInsensitiveCompare("groupdef") == .orderedSame,
                   let id = node.attribute("id"), !id.isEmpty {
                    groupdefsByID[fold(id)] = node
                    if let tag = node.attribute("xuitag"), !tag.isEmpty {
                        groupdefsByXUITag[fold(tag)] = fold(id)
                    }
                }
                collectDefinitions(node.children)
            }
        }
        collectDefinitions(document.roots)
        // The conventional pairs let mmd3's `<Wasabi:StandardFrame:Status>` find the frame it declares
        // without an `xuitag=`; the same table the type registry aliases with.
        for (tag, identifier) in WasabiStandardFrames.conventionalXUITags
        where groupdefsByXUITag[fold(tag)] == nil && groupdefsByID[fold(identifier)] != nil {
            groupdefsByXUITag[fold(tag)] = fold(identifier)
        }

        var containers: [Container] = []
        var visitedBudget = limits.maximumVisitedNodes
        var ambiguous: Set<WinampModernComponentKind> = []

        func topLevelContainers(_ nodes: [WalXMLNode]) -> [WalXMLNode] {
            nodes.flatMap { node -> [WalXMLNode] in
                if node.name.caseInsensitiveCompare("container") == .orderedSame { return [node] }
                // `<WasabiXML>`/`<WinampAbstractionLayer>` wrappers and includes nest containers one
                // or more levels down; groupdefs never contain a container.
                if node.name.caseInsensitiveCompare("groupdef") == .orderedSame { return [] }
                return topLevelContainers(node.children)
            }
        }

        for container in topLevelContainers(document.roots) {
            let id = container.attribute("id") ?? ""
            var visitedGroups: Set<String> = []
            var found: Set<WinampModernComponentKind> = []
            var equalizerControls = false

            func visit(_ node: WalXMLNode, depth: Int) {
                guard visitedBudget > 0, depth <= limits.maximumGroupDepth else {
                    if visitedBudget <= 0 {
                        diagnostics.append(WalDiagnostic(
                            .expandedNodeLimitExceeded,
                            "Surface inventory stopped after \(limits.maximumVisitedNodes) nodes; "
                            + "surfaces beyond that point are treated as ambiguous.",
                            severity: .warning, location: node.location))
                        ambiguous.formUnion(managedKinds)
                    }
                    return
                }
                visitedBudget -= 1

                if WinampModernComponentRegistry.isHolderElement(node.name) {
                    if let kind = holderKind(of: node) { found.insert(kind) }
                }
                if isEqualizerControl(node) { equalizerControls = true }

                for identifier in referencedGroupIdentifiers(of: node, xuiTags: groupdefsByXUITag) {
                    visitGroup(identifier, depth: depth + 1)
                }
                for child in node.children { visit(child, depth: depth) }
            }

            func visitGroup(_ identifier: String, depth: Int) {
                let key = fold(identifier)
                guard visitedGroups.insert(key).inserted else { return }   // cycle / already seen
                guard depth <= limits.maximumGroupDepth else { return }
                guard let definition = groupdefsByID[key] else { return }
                if let inherited = definition.attribute("inherit_group") {
                    visitGroup(groupdefsByXUITag[fold(inherited)] ?? inherited, depth: depth + 1)
                }
                if let embedded = definition.attribute("embed_xui") {
                    visitGroup(groupdefsByXUITag[fold(embedded)] ?? embedded, depth: depth + 1)
                }
                visit(definition, depth: depth)
            }

            for layout in container.children
            where layout.name.caseInsensitiveCompare("layout") == .orderedSame {
                visit(layout, depth: 0)
            }

            let declaredKind = containerKind(of: container)
            containers.append(Container(
                id: id,
                kind: declaredKind,
                isMainPlayer: id.caseInsensitiveCompare("main") == .orderedSame,
                isVisibleWindow: isVisibleWindow(container),
                reachableKinds: found,
                hasEqualizerControls: equalizerControls
            ))
        }

        let main = containers.first { $0.isMainPlayer } ?? containers.first
        var embedded = main?.reachableKinds ?? []
        // A skin-drawn equalizer *is* the equalizer surface. Winamp defines no EQ component GUID, so
        // every measured skin expresses one as ordinary sliders carrying `EQ_BAND`/`EQ_PREAMP` — cPro
        // in a drawer, mmd3 in a main-window drawer, CornerAmp in its own `eq` container.
        if main?.hasEqualizerControls == true { embedded.insert(.equalizer) }
        embedded.formIntersection(Set(managedKinds))

        var declared: [WinampModernComponentKind: String] = [:]
        for container in containers where !container.isMainPlayer && container.isVisibleWindow {
            // The container's declared kind first; failing that, a container that reaches exactly one
            // managed surface *is* that surface's window (mmd3's `Pledit` would qualify either way).
            let kind = container.kind
                ?? container.reachableKinds.intersection(Set(managedKinds)).singleElement
                ?? (container.hasEqualizerControls ? .equalizer : nil)
            guard let kind, declared[kind] == nil else { continue }
            declared[kind] = container.id
        }

        // cPro-Bento hosts its surfaces inside the player window; everyone else opens windows. The
        // count of containers cannot tell them apart (cPro also ships a notifier, a widget manager and
        // a browser window), but what the *main* window embeds can.
        let arrangement: WinampModernSurfaceArrangement =
            embedded.contains(.playlist) || embedded.contains(.library) ? .singleWindowSUI : .separateWindows

        return WinampModernSurfaceInventory(
            containers: containers,
            arrangement: arrangement,
            embeddedKinds: embedded,
            declaredContainers: declared,
            ambiguousKinds: ambiguous,
            diagnostics: diagnostics
        )
    }

    // MARK: - Edges

    /// Every groupdef identifier this node can bring into the scene.
    private static func referencedGroupIdentifiers(of node: WalXMLNode,
                                                   xuiTags: [String: String]) -> [String] {
        var identifiers: [String] = []
        let name = node.name.lowercased()

        // `<group id="X"/>` instantiates groupdef X; a bare XUI tag instantiates the groupdef that
        // claims it.
        if name == "group", let id = node.attribute("id") { identifiers.append(id) }
        if let mapped = xuiTags[fold(node.name)] { identifiers.append(mapped) }

        // A standard frame builds its client area from `content=` — the frame's own script does the
        // instantiating at runtime, but the edge is declared right here.
        if let content = node.attribute("content"), !content.isEmpty { identifiers.append(content) }

        // `<Wasabi:Frame left="…" right="…">` instantiates the two groups it names.
        if WasabiFrame.isFrame(typeName: node.name) {
            for direction in ["left", "right", "top", "bottom"] {
                if let pane = node.attribute(direction), !pane.isEmpty { identifiers.append(pane) }
            }
        }
        return identifiers.filter { !$0.isEmpty }
    }

    private static func holderKind(of node: WalXMLNode) -> WinampModernComponentKind? {
        let keys = node.name.caseInsensitiveCompare("component") == .orderedSame
            ? ["param", "guid"]
            : ["hold", "component", "guid"]
        for key in keys {
            if let value = node.attribute(key), let kind = WinampModernComponentRegistry.kind(for: value) {
                return kind
            }
        }
        return node.attribute("id").flatMap { WinampModernComponentRegistry.kindFromHolderIdentifier($0) }
    }

    /// A control that drives the equalizer. `EQ_TOGGLE`/`EQ_AUTO` deliberately do not count: a skin
    /// can put an "open the EQ" button anywhere, and that button is not an equalizer.
    private static func isEqualizerControl(_ node: WalXMLNode) -> Bool {
        if node.name.caseInsensitiveCompare("eqvis") == .orderedSame { return true }
        switch node.attribute("action")?.uppercased() {
        case "EQ_BAND", "EQ_PREAMP": return true
        default: return false
        }
    }

    private static func containerKind(of container: WalXMLNode) -> WinampModernComponentKind? {
        if let declared = container.attribute("component"),
           let kind = WinampModernComponentRegistry.kind(for: declared) {
            return kind
        }
        return container.attribute("id").flatMap { WinampModernComponentRegistry.kind(for: $0) }
    }

    private static func isVisibleWindow(_ container: WalXMLNode) -> Bool {
        if container.attribute("id")?.caseInsensitiveCompare("main") == .orderedSame { return true }
        switch container.attribute("visible")?.lowercased() {
        case "0", "false", "no": return false
        default: break
        }
        // A container whose normal layout is at most 2px on a side has been neutralized by a
        // `window-overrides.xml`, the way cPro collapses the standalone windows it embeds instead.
        let layouts = container.children.filter { $0.name.caseInsensitiveCompare("layout") == .orderedSame }
        let layout = layouts.first { $0.attribute("id")?.caseInsensitiveCompare("normal") == .orderedSame }
            ?? layouts.first
        guard let layout else { return true }
        func dimension(_ keys: [String]) -> Double {
            for key in keys {
                if let raw = layout.attribute(key), let value = Double(raw) { return value }
            }
            return 0
        }
        let width = dimension(["default_w", "w", "minimum_w"])
        let height = dimension(["default_h", "h", "minimum_h"])
        // A layout that declares no box at all is not collapsed — it is sized by its `background`
        // bitmap. Counting its two zeroes as 0×0 made the skin's own equalizer look absent, and the
        // synthesizer then built a plain one over the top of it.
        guard width > 0 || height > 0 else { return true }
        return !(width <= 2 && height <= 2)
    }

    private static func fold(_ value: String) -> String {
        value.folding(options: [.caseInsensitive], locale: Locale(identifier: "en_US_POSIX"))
    }
}

private extension Set where Element == WinampModernComponentKind {
    /// The single element, or `nil` when there are none or several — "exactly one surface lives here"
    /// is evidence; "some surfaces live here" is not.
    var singleElement: WinampModernComponentKind? { count == 1 ? first : nil }
}
