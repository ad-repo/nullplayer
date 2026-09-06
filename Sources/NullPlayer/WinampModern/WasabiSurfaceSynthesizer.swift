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
        /// The container id that shows the skin's own About page — the one a `TOGGLE
        /// guid:{D6201408-…}` opens. Either a container the skin declared around
        /// `skin.about.group` or the one synthesized here; `nil` when the skin has no About page
        /// at all, which is where NullPlayer's own panel takes over.
        let aboutContainer: String?
        let diagnostics: [WalDiagnostic]

        static func unchanged(_ document: WalExpandedXMLDocument,
                              hostedWindows: WinampModernHostedWindowCatalog,
                              aboutContainer: String? = nil) -> Result {
            Result(document: document, synthesizedContainers: [:], unavailable: [:],
                   hostedWindows: hostedWindows, aboutContainer: aboutContainer, diagnostics: [])
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
                           limits: WalXMLLimits = .production,
                           scriptReader: ScriptReader? = nil) -> Result {
        let kinds = inventory.synthesizableKinds
        let definitions = groupDefinitions(in: document.roots)
        let frame = usableFrame(in: definitions, document: document, scriptReader: scriptReader)
        let hostedWindows = hostedWindowCatalog(frame: frame)

        // The skin's own library window, re-framed in the same frame our windows wear.
        overrideDeclaredLibraryFrame(in: document, frame: frame)

        var appended: [WalXMLNode] = []
        var synthesized: [WinampModernComponentKind: String] = [:]
        var unavailable: [WinampModernComponentKind: String] = [:]
        var diagnostics: [WalDiagnostic] = []
        var budget = limits.maximumExpandedNodeCount - countNodes(document.roots)

        // The skin's own About page, before the surfaces: it is the cheapest subtree of the three
        // and the one a skin is likeliest to reach for (twenty of the measured seventy define
        // `skin.about.group`), so it must not be the one the node budget runs out on.
        let about = aboutRoute(document: document, definitions: definitions, frame: frame)
        var aboutContainer = about.containerID
        if !about.nodes.isEmpty {
            let cost = countNodes(about.nodes)
            if cost <= budget {
                budget -= cost
                appended.append(contentsOf: about.nodes)
            } else {
                aboutContainer = nil
                diagnostics.append(WalDiagnostic(
                    .expandedNodeLimitExceeded,
                    "Synthesizing the About window would exceed the "
                    + "\(limits.maximumExpandedNodeCount)-node budget; the skin's About page falls "
                    + "back to NullPlayer's own panel.",
                    severity: .warning, location: WalSourceLocation(path: sourcePath)))
            }
        }
        diagnostics.append(contentsOf: about.diagnostics)

        for kind in kinds {
            guard let reference = componentReference(for: kind) else { continue }
            switch frame {
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
                          aboutContainer: aboutContainer, diagnostics: diagnostics)
        }
        return Result(document: WalExpandedXMLDocument(roots: document.roots + appended,
                                                       visitedPaths: document.visitedPaths,
                                                       diagnostics: document.diagnostics + diagnostics),
                      synthesizedContainers: synthesized,
                      unavailable: unavailable,
                      hostedWindows: hostedWindows,
                      aboutContainer: aboutContainer,
                      diagnostics: diagnostics)
    }

    // MARK: - The skin's About page

    /// The groupdef Winamp instantiates for the "Skin" page of its About box. It is not a window: a
    /// skin defines the *contents* and Winamp supplies the frame around them, which is why twenty of
    /// the measured seventy skins define this group and only one wraps it in a container of its own.
    static let aboutGroupIdentifier = "skin.about.group"

    /// Where the synthesized About window lands. Distinct from `containerIdentifier(for:)` because
    /// the About page is not a component surface — it has no kind, no GUID, and no classic window.
    static let aboutContainerIdentifier = "nullplayer.about"

    /// The About page's canvas, in skin pixels. Every skin in the corpus draws its page fitparent
    /// and cuts the artwork behind it at 371×321 (Big Bento and Nullsoft 2000 at 380×321), so the
    /// size is the host's decision and this is Winamp's. The extra height is the standard frame's own
    /// title bar and border — Nullsoft 2000, the one skin that declares this window itself, asks for
    /// 388×349 around a 380×321 page.
    private static let aboutGeometry = (defaultSize: CGSize(width: 380, height: 358),
                                        minimumSize: CGSize(width: 240, height: 200))

    private struct AboutRoute {
        var containerID: String?
        var nodes: [WalXMLNode] = []
        var diagnostics: [WalDiagnostic] = []
    }

    /// Resolve the About page to a container, synthesizing a window for it only when the skin does
    /// not already declare one. Nullsoft 2000 SP4 Lite declares
    /// `<container id="about"><Wasabi:Standardframe:NoStatus content="skin.about.group"/></container>`
    /// — synthesizing a second window there would give that skin two About windows and route the
    /// skin's own button to the wrong one.
    private static func aboutRoute(document: WalExpandedXMLDocument,
                                   definitions: [String: WalXMLNode],
                                   frame: FrameSelection) -> AboutRoute {
        guard definitions[fold(aboutGroupIdentifier)] != nil else { return AboutRoute(containerID: nil) }
        if let declared = containerHosting(group: aboutGroupIdentifier, in: document.roots) {
            return AboutRoute(containerID: declared)
        }
        switch frame {
        case .failure(let reason):
            return AboutRoute(containerID: nil, nodes: [], diagnostics: [WalDiagnostic(
                .missingGroupDefinition,
                "No usable standard frame to host the skin's About page (\(reason)); it falls back "
                + "to NullPlayer's own panel.",
                severity: .warning, location: WalSourceLocation(path: sourcePath))])
        case .success(let frame):
            return AboutRoute(containerID: aboutContainerIdentifier,
                              nodes: [makeAboutContainer(frame: frame)])
        }
    }

    /// The id of a skin-declared container whose layout hands `group` to a frame as its `content`.
    private static func containerHosting(group: String, in nodes: [WalXMLNode]) -> String? {
        let wanted = fold(group)
        func hostsGroup(_ node: WalXMLNode) -> Bool {
            if let content = node.attribute("content"), fold(content) == wanted { return true }
            return node.children.contains(where: hostsGroup)
        }
        // Containers are nested inside the document's own root element, so this walks rather than
        // scanning the top level — the check that found nothing there let Nullsoft 2000 SP4 Lite,
        // the one skin that declares this window itself, end up with two About windows.
        func search(_ nodes: [WalXMLNode]) -> String? {
            for node in nodes {
                if node.name.caseInsensitiveCompare("container") == .orderedSame,
                   let id = node.attribute("id"), !id.isEmpty, hostsGroup(node) {
                    return id
                }
                if let found = search(node.children) { return found }
            }
            return nil
        }
        return search(nodes)
    }

    private static func makeAboutContainer(frame: Frame) -> WalXMLNode {
        let location = WalSourceLocation(path: sourcePath)
        let children = frameNodes(frame: frame, frameID: "\(aboutContainerIdentifier).frame",
                                  contentGroupID: aboutGroupIdentifier, componentName: "About",
                                  location: location)
        let floor = frame.floor(under: aboutGeometry.minimumSize)
        let opening = frame.floor(under: aboutGeometry.defaultSize)
        let layout = WalXMLNode(name: "layout", attributes: [
            "id": "normal",
            "default_w": String(Int(opening.width)),
            "default_h": String(Int(opening.height)),
            "minimum_w": String(Int(floor.width)),
            "minimum_h": String(Int(floor.height)),
        ], location: location, children: children)
        return WalXMLNode(name: "container", attributes: [
            "id": aboutContainerIdentifier,
            "name": "About",
            "default_visible": "0",
            WinampModernContainerTopology.synthesizedAttribute: "1",
        ], location: location, children: [layout])
    }

    static func containerIdentifier(for kind: WinampModernComponentKind) -> String {
        "nullplayer.\(kind.rawValue)"
    }

    // MARK: - Frame selection

    /// Reads the body of a `<script file=…>` the way `WasabiSkinInitializer` resolves one. Nil where
    /// there is no VFS to read from — synthetic documents in tests — which falls the frame test back
    /// to the weaker XML-only form.
    typealias ScriptReader = (_ rawPath: String, _ source: WalSourceLocation) -> Data?

    struct Frame {
        let groupIdentifier: String
        let xuiTag: String
        let hasArtwork: Bool
        /// How the skin itself lays this frame out in one of its own windows, when it does. Nil for
        /// the ordinary case, where the frame's own script builds its client area from `content=`.
        let exemplar: FrameExemplar?
        /// Where the frame's *own script* would put its client, for the ordinary `content=` case: the
        /// `origin` and total border of the `param="x,y,w,h,…"` its `standardframe.maki` applies to
        /// the group named by `content=`. Nil where the skin states no such rect.
        let scriptClient: CGRect?

        init(groupIdentifier: String, xuiTag: String, hasArtwork: Bool,
             exemplar: FrameExemplar?, scriptClient: CGRect? = nil) {
            self.groupIdentifier = groupIdentifier
            self.xuiTag = xuiTag
            self.hasArtwork = hasArtwork
            self.exemplar = exemplar
            self.scriptClient = scriptClient
        }

        /// The border this frame draws around a window of **ours**, per side, in skin pixels.
        ///
        /// The skin's own number is asymmetric wherever the author left padding on one side for
        /// contents Winamp supplies and we do not — HeadAMP's status frame states `25,28,-40,-70`,
        /// which is 25 left against 15 right and 28 top against 42 bottom, and a meter placed there
        /// reads as pushed right and sunk. Ours is the **larger** of each opposing pair, so the client
        /// is centred and still clears everything the author kept clear on either side. Nothing about
        /// the skin changes: this places the group we synthesized, in the window we synthesized.
        var symmetricBorder: CGSize? {
            guard exemplar == nil, let rect = scriptClient else { return nil }
            let horizontal = max(rect.minX, rect.width - rect.minX)
            let vertical = max(rect.minY, rect.height - rect.minY)
            guard horizontal > 0, vertical > 0 else { return nil }
            return CGSize(width: horizontal, height: vertical)
        }

        /// What this frame's border costs the window: the exemplar's own content rect where the skin
        /// lays its windows out itself — a `w="-66" h="-92"` client area is a 66x92 border around it —
        /// and otherwise twice the symmetric border we place our own client inside.
        var chromeInset: CGSize {
            guard let exemplar else {
                guard let border = symmetricBorder else { return .zero }
                return CGSize(width: 2 * border.width, height: 2 * border.height)
            }
            let width = Double(exemplar.content["w"] ?? "") ?? 0
            let height = Double(exemplar.content["h"] ?? "") ?? 0
            return CGSize(width: max(0, -width), height: max(0, -height))
        }

        /// `size` as a **client** size: grown by the border this frame draws around it, then raised to
        /// the floor the exemplar window declares. The identity without an exemplar, where the frame
        /// sizes its own client area.
        ///
        /// Every number in the hosted-window registry is the size of the *contents* — the spectrum's
        /// 343x145 is the bars. Treating it as the window's size instead left Itemskin's 33x55 border
        /// eating most of the window and reading as chrome far too thick for what it framed, and
        /// HeadAMP's 40x70 script inset squashing a 343x145 meter into 303x75 (B140).
        func floor(under size: CGSize) -> CGSize {
            let grown = CGSize(width: size.width + chromeInset.width,
                               height: size.height + chromeInset.height)
            guard let exemplar else { return grown }
            return CGSize(width: max(grown.width, exemplar.minimumSize.width),
                          height: max(grown.height, exemplar.minimumSize.height))
        }
    }

    /// One of the skin's own windows, read as a template.
    ///
    /// A standard frame is *supposed* to instantiate `content=` from its own `standardframe.maki`,
    /// and where it does, that is the whole contract and this is nil. Itemskin does it the other way
    /// round in every window it ships: the frame draws chrome only, and the content sits beside it as
    /// a **sibling** of the frame in the same layout —
    ///
    /// ```xml
    /// <Wasabi:StandardFrame:ML x="-8" y="7" w="15" h="3" relatw="1" relath="1"/>
    /// <component x="33" y="55" w="-66" h="-92" relatw="1" relath="1" …/>
    /// ```
    ///
    /// — written identically in `mlibrary.xml`, `pledit-normal.xml` and `dlibrary.xml`. Those two
    /// rects are the only statement of where the client area of such a frame goes, and guessing
    /// instead is what produced a window whose chrome and contents were in different places.
    struct FrameExemplar {
        /// Rect attributes for the `<Wasabi:StandardFrame:*>` node itself.
        let frame: [String: String]
        /// Rect attributes for our content group, placed as that frame's sibling.
        let content: [String: String]
        /// The floor the skin's own window declares. A frame of this kind draws its chrome in a
        /// *second* window that the script keeps the same size as this one, and that window has a
        /// minimum of its own: K-jr's `layout.clear.ml` will not go below 403x231, so a 343x145 Cava
        /// window would wear a frame bigger than itself. Our windows therefore inherit the floor the
        /// skin proved its own chrome is drawable at.
        let minimumSize: CGSize
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
                hasArtwork: frame.hasArtwork,
                exemplar: frame.exemplar,
                scriptClient: frame.scriptClient
            ))
        case .failure(let reason):
            route = .classicFallback(reason: reason)
        }
        return WinampModernHostedWindowCatalog(routes: Dictionary(
            uniqueKeysWithValues: WinampModernHostedWindowRegistry.all.map { ($0.id, route) }
        ))
    }

    /// The thinnest frame the skin declares that we can actually build a window out of.
    ///
    /// The order used to be "richest first" — a status bar, then no status bar, then a static frame —
    /// and for a NullPlayer-owned window that is backwards. A status frame reserves rows for a status
    /// strip whose text Winamp's own components supply and ours never do: HeadAMP's costs 70 rows
    /// against its no-status frame's 50, around a 145-row meter (B140). So among the flavours whose
    /// frame can build a client area, the one whose client rect leaves the most window wins, and the
    /// old order only breaks ties — including the tie every skin that states no rect is in.
    ///
    /// Two shapes qualify, in this order:
    ///
    /// 1. **The frame builds its own client area** from `content=` in its own script. This is the
    ///    Wasabi contract and every skin that follows it takes this branch unchanged.
    /// 2. **The skin lays the frame out itself**, chrome and content side by side, and we copy that
    ///    layout (`FrameExemplar`). Itemskin is the measured case and it declares no frame of the
    ///    first kind at all: its `wasabi.standardframe.static` runs a script that draws chrome and
    ///    never touches `content`, so left to the first rule every one of NullPlayer's own windows
    ///    materialized with no client area and fell back to NullPlayer's own chrome.
    private static func usableFrame(in definitions: [String: WalXMLNode],
                                    document: WalExpandedXMLDocument,
                                    scriptReader: ScriptReader?) -> FrameSelection {
        var reasons: [String] = []
        var declared: [(border: Double, order: Int, frame: Frame)] = []
        for (order, flavour) in WasabiStandardFrames.Flavour.allCases.enumerated() {
            guard let definition = definitions[fold(flavour.groupIdentifier)] else {
                reasons.append("\(flavour.rawValue): the skin declares no '\(flavour.groupIdentifier)'")
                continue
            }
            // A frame builds its client area from `content=` in its own script. Without that script
            // the window would be chrome around an empty hole — exactly what the artwork-less Wasabi
            // shells produce.
            guard hasContentScript(definition, definitions: definitions, depth: 0,
                                   scriptReader: scriptReader) else {
                reasons.append("\(flavour.rawValue): '\(flavour.groupIdentifier)' has no frame script "
                               + "that instantiates its content")
                continue
            }
            let frame = Frame(groupIdentifier: flavour.groupIdentifier,
                              xuiTag: flavour.xuiTag,
                              hasArtwork: hasArtwork(definition, definitions: definitions, depth: 0),
                              exemplar: nil,
                              scriptClient: scriptClientRect(definition, definitions: definitions,
                                                             depth: 0))
            declared.append((border: frame.chromeInset.width + frame.chromeInset.height,
                             order: order, frame: frame))
        }
        if let best = declared.sorted(by: { ($0.border, $0.order) < ($1.border, $1.order) }).first {
            return .success(best.frame)
        }
        // Nothing follows the contract. Copy one of the skin's own windows instead, if it has one:
        // its own layout is proof of where this frame's content goes, which nothing else here is.
        let candidates = exemplarCandidates(in: definitions)
        let ranked = frameExemplars(in: document).compactMap { exemplar -> (Int, Int, Int, Frame)? in
            guard let index = candidates.firstIndex(where: {
                $0.xuiTag.caseInsensitiveCompare(exemplar.tag) == .orderedSame
            }) else { return nil }
            let candidate = candidates[index]
            guard let definition = definitions[fold(candidate.groupIdentifier)] else { return nil }
            return (Int(borderWeight(exemplar)), exemplar.rank, index,
                    Frame(groupIdentifier: candidate.groupIdentifier,
                          xuiTag: candidate.xuiTag,
                          hasArtwork: hasArtwork(definition, definitions: definitions, depth: 0),
                          exemplar: FrameExemplar(frame: exemplar.frame, content: exemplar.content,
                                                  minimumSize: exemplar.minimumSize)))
        }.sorted { ($0.0, $0.1, $0.2) < ($1.0, $1.1, $1.2) }
        if let best = ranked.first { return .success(best.3) }
        return .failure(reasons.joined(separator: "; "))
    }

    /// Every `wasabi.standardframe.*` the skin declares, canonical flavours first, then the rest in a
    /// fixed order. Only reached once no frame follows the `content=` contract, and only a candidate
    /// the skin lays out around a component of its own is ever selected, so a frame invented for one
    /// specific window is never taken on faith. `wasabi.standardframe.modal` stays excluded as it
    /// always was: a modal frame hides its system menu.
    private static func exemplarCandidates(in definitions: [String: WalXMLNode])
        -> [(groupIdentifier: String, xuiTag: String)] {
        var candidates = WasabiStandardFrames.Flavour.allCases.map {
            (groupIdentifier: $0.groupIdentifier, xuiTag: $0.xuiTag)
        }
        let canonical = Set(candidates.map { fold($0.groupIdentifier) }
                            + [fold("wasabi.standardframe.modal")])
        let prefix = fold("wasabi.standardframe.")
        for key in definitions.keys.sorted() where key.hasPrefix(prefix) && !canonical.contains(key) {
            guard let definition = definitions[key],
                  let identifier = definition.attribute("id"), !identifier.isEmpty,
                  let tag = definition.attribute("xuitag"), !tag.isEmpty else { continue }
            candidates.append((groupIdentifier: identifier, xuiTag: tag))
        }
        return candidates
    }

    private struct DiscoveredExemplar {
        let tag: String
        let frame: [String: String]
        let content: [String: String]
        let minimumSize: CGSize
        /// Which of the skin's windows this came from. Lower is better.
        let rank: Int
    }

    /// Every window the skin builds as a standard frame beside a component, with the frame's rect and
    /// the component's rect taken from the same `<layout>`.
    ///
    /// **The thinnest border wins.** All of Itemskin's frames are laid out the same way and every one
    /// of them is control-free *as artwork*, but they are not the same weight: its playlist/library
    /// frame is 33px sides and a 55px band (drawn for a 660x274 library and far too heavy around a
    /// 343x145 meter), while its visualizer/video frame is 26/40 of thin dark border. Nothing about
    /// the contents of those windows carries over — the controls that live inside the thin frame's
    /// chrome are hidden in our copy of it, in
    /// `WinampModernScriptRuntime.adoptChromeForHostedWindow` — so the only thing left to choose on
    /// is how much of the window the border eats.
    ///
    /// The tie-break is the skin's own window kind (library, playlist, then the rest), which only
    /// decides between frames of identical weight.
    private static func frameExemplars(in document: WalExpandedXMLDocument) -> [DiscoveredExemplar] {
        let libraryGUID = "6b0edf80-c9a5-11d3-9f26-00c04f39ffc6"
        let playlistGUID = "45f3f7c1-a6f3-4ee6-a15e-125e92fc3f8d"
        var found: [DiscoveredExemplar] = []
        func rank(container: WalXMLNode?, component: WalXMLNode) -> Int {
            let reference = (component.attribute("param")
                             ?? container?.attribute("component") ?? "").lowercased()
            if reference.contains(libraryGUID) { return 0 }
            if reference.contains(playlistGUID) { return 1 }
            return 2
        }
        func walk(_ nodes: [WalXMLNode], container: WalXMLNode?) {
            for node in nodes {
                let isContainer = node.name.caseInsensitiveCompare("container") == .orderedSame
                if node.name.caseInsensitiveCompare("layout") == .orderedSame {
                    let frame = node.children.first {
                        fold($0.name).hasPrefix(fold(standardFrameTagPrefix))
                    }
                    let content = node.children.first {
                        $0.name.caseInsensitiveCompare("component") == .orderedSame
                    }
                    // A full-bleed component (`w="0" h="0" relatw="1" relath="1"`, MoonLight's video
                    // window) states nothing about where the client area goes: it fills the window and
                    // the chrome overlaps it from a window of its own size. Reading that as a
                    // zero-thickness border made it the "thinnest" candidate and gave Cava a frame
                    // 410x281 clipped into a 343x220 window. Only a real inset is an exemplar.
                    if let frame, let content, insetsClient(content) {
                        let floor = chromeFloor(forExemplarLayout: node, in: document)
                        found.append(DiscoveredExemplar(tag: frame.name,
                                                        frame: rectAttributes(of: frame),
                                                        content: rectAttributes(of: content),
                                                        minimumSize: floor,
                                                        rank: rank(container: container,
                                                                   component: content)))
                    }
                }
                walk(node.children, container: isContainer ? node : container)
            }
        }
        walk(document.roots, container: nil)
        return found
    }

    /// Whether this component rect actually leaves room for a border on both axes.
    private static func insetsClient(_ node: WalXMLNode) -> Bool {
        let width = Double(node.attribute("w") ?? "") ?? 0
        let height = Double(node.attribute("h") ?? "") ?? 0
        return width < 0 && height < 0
    }

    /// Put the skin's own **library** window in the thinner frame, when the skin has one.
    ///
    /// This is the one place the pass rewrites a window the skin declares rather than adding one of
    /// our own, and it is deliberate. The library window is the only skin window whose entire contents
    /// are NullPlayer's and whose rows are dense with information, so a frame drawn for a picture —
    /// Itemskin puts a 33px surround and a 55px band around its `MLibrary`, the same frame it gives
    /// its playlist — costs real rows on every screen. Every other window the author framed keeps the
    /// frame the author chose.
    ///
    /// It only ever *reduces* the border: a skin whose library already wears its thinnest frame, or
    /// which has no second frame to offer, is left exactly as written. `frame` here is the frame
    /// selection the rest of the pass already made, which is the thinnest the skin declares.
    private static func overrideDeclaredLibraryFrame(in document: WalExpandedXMLDocument,
                                                     frame: FrameSelection) {
        guard case .success(let frame) = frame, let exemplar = frame.exemplar,
              let layout = declaredLibraryLayout(in: document),
              let existing = layout.children.first(where: {
                  fold($0.name).hasPrefix(fold(standardFrameTagPrefix))
              }),
              existing.name.caseInsensitiveCompare(frame.xuiTag) != .orderedSame,
              let component = layout.children.first(where: {
                  $0.name.caseInsensitiveCompare("component") == .orderedSame
              }),
              weight(of: exemplar.content) < weight(of: rectAttributes(of: component))
        else { return }
        component.setAttributes(exemplar.content)
        var frameAttributes = existing.attributes
        for name in rectAttributeNames { frameAttributes[name] = nil }
        frameAttributes.merge(exemplar.frame) { _, new in new }
        let replacement = WalXMLNode(name: frame.xuiTag, attributes: frameAttributes,
                                     location: existing.location, children: existing.children)
        layout.replaceChildren(layout.children.map { $0 === existing ? replacement : $0 })
    }

    /// The `<layout>` of the window the skin declares for the media library, if it declares one.
    private static func declaredLibraryLayout(in document: WalExpandedXMLDocument) -> WalXMLNode? {
        let libraryGUID = "6b0edf80-c9a5-11d3-9f26-00c04f39ffc6"
        var found: WalXMLNode?
        func walk(_ nodes: [WalXMLNode], container: WalXMLNode?) {
            for node in nodes {
                if found != nil { return }
                let isContainer = node.name.caseInsensitiveCompare("container") == .orderedSame
                if node.name.caseInsensitiveCompare("layout") == .orderedSame,
                   let component = node.children.first(where: {
                       $0.name.caseInsensitiveCompare("component") == .orderedSame
                   }) {
                    let reference = (component.attribute("param")
                                     ?? container?.attribute("component") ?? "").lowercased()
                    if reference.contains(libraryGUID) { found = node; return }
                }
                walk(node.children, container: isContainer ? node : container)
            }
        }
        walk(document.roots, container: nil)
        return found
    }

    private static func weight(of rect: [String: String]) -> Double {
        let width = Double(rect["w"] ?? "") ?? 0
        let height = Double(rect["h"] ?? "") ?? 0
        return max(0, -width) + max(0, -height)
    }

    /// How much of the window this exemplar's border takes up, as one number to order by.
    private static func borderWeight(_ exemplar: DiscoveredExemplar) -> Double {
        let width = Double(exemplar.content["w"] ?? "") ?? 0
        let height = Double(exemplar.content["h"] ?? "") ?? 0
        return max(0, -width) + max(0, -height)
    }

    /// The floor a window built from this exemplar has to obey.
    ///
    /// It is the **chrome window's** minimum, not the exemplar's own. A frame of this kind draws in a
    /// second `dynamic="1"` container that the script keeps the same size as the window, and that
    /// container has a floor of its own that the content window's does not mention: K-jr's
    /// `layout.clear.ml` will not go below 403x231 while its `MLibrary` layout says 213 wide and
    /// mis-spells its own `minimum_h`. Left at the registry's 343x145, Cava wore a frame larger than
    /// itself with the top border off the window entirely.
    ///
    /// The chrome container is matched by **default size**: the skin sizes the pair together, so
    /// Itemskin's `layout.clear.ml` is 660x274 exactly like its `MLibrary`, and K-jr's is 213x246
    /// exactly like its own. Nothing else in the markup names the pairing — the script does it by id
    /// at runtime.
    private static func chromeFloor(forExemplarLayout layout: WalXMLNode,
                                    in document: WalExpandedXMLDocument) -> CGSize {
        // A layout states its size as `default_w`/`default_h` or as plain `w`/`h`, and the two halves
        // of a pair need not agree on which: Itemskin's `AVS_window` writes both, its
        // `layout.clear.avs` only `w`/`h`. Reading one form alone found no chrome for the pair, and
        // the window came up smaller than the frame around it.
        func size(_ node: WalXMLNode, _ prefix: String) -> CGSize {
            func number(_ name: String) -> Double? { node.attribute(name).flatMap(Double.init) }
            return CGSize(width: number("\(prefix)_w") ?? (prefix == "default" ? number("w") : nil) ?? 0,
                          height: number("\(prefix)_h") ?? (prefix == "default" ? number("h") : nil) ?? 0)
        }
        let own = size(layout, "minimum")
        let wanted = size(layout, "default")
        guard wanted.width > 0, wanted.height > 0 else { return own }
        var best = own
        func walk(_ nodes: [WalXMLNode], dynamicContainer: Bool) {
            for node in nodes {
                let isContainer = node.name.caseInsensitiveCompare("container") == .orderedSame
                let isDynamic = isContainer ? node.attribute("dynamic") == "1" : dynamicContainer
                if dynamicContainer, node.name.caseInsensitiveCompare("layout") == .orderedSame,
                   size(node, "default") == wanted {
                    let floor = size(node, "minimum")
                    best = CGSize(width: max(best.width, floor.width),
                                  height: max(best.height, floor.height))
                }
                walk(node.children, dynamicContainer: isDynamic)
            }
        }
        walk(document.roots, dynamicContainer: false)
        return best
    }

    private static let standardFrameTagPrefix = "wasabi:standardframe:"

    /// The frame node, plus the content group beside it when the skin lays its own windows out that
    /// way. One place, because the About window, a synthesized component surface and a hosted window
    /// must all be built the same way or they disagree about where the client area is.
    ///
    /// With an exemplar the frame carries **no `content=`**: the script would instantiate it at its
    /// own idea of the rect (Itemskin's `standardframe.maki` param is `0,0,-42,-80`, which lands the
    /// contents in the top-left corner, outside the chrome the same script draws), and the skin's own
    /// layout is the better answer.
    static func frameNodes(frame: Frame, frameID: String, contentGroupID: String,
                           componentName: String, location: WalSourceLocation) -> [WalXMLNode] {
        let fullBleed = ["x": "0", "y": "0", "w": "0", "h": "0", "relatw": "1", "relath": "1"]
        guard let exemplar = frame.exemplar else {
            guard let border = frame.symmetricBorder else {
                return [WalXMLNode(name: frame.xuiTag, attributes: fullBleed.merging([
                    "id": frameID,
                    "content": contentGroupID,
                    "componentname": componentName,
                ]) { _, new in new }, location: location)]
            }
            // The frame still draws its own artwork; only the client is ours to place, so the frame is
            // handed no `content=` and our group sits beside it, centred in the border. Letting the
            // script place it instead is what put the client off to one side (B140).
            return [
                WalXMLNode(name: frame.xuiTag, attributes: fullBleed.merging([
                    "id": frameID,
                    "componentname": componentName,
                ]) { _, new in new }, location: location),
                WalXMLNode(name: "group", attributes: [
                    "id": contentGroupID,
                    "x": String(Int(border.width)), "y": String(Int(border.height)),
                    "w": String(Int(-2 * border.width)), "h": String(Int(-2 * border.height)),
                    "relatw": "1", "relath": "1",
                ], location: location),
            ]
        }
        return [
            WalXMLNode(name: frame.xuiTag,
                       attributes: exemplar.frame.merging([
                           "id": frameID,
                           "componentname": componentName,
                       ]) { _, new in new },
                       location: location),
            WalXMLNode(name: "group",
                       attributes: bled(exemplar.content).merging(["id": contentGroupID]) { _, new in new },
                       location: location),
        ]
    }

    /// How far the client area tucks *under* the border, in skin pixels.
    ///
    /// A frame of this kind draws in a second window parked over this one, and the two rects the skin
    /// writes need not meet exactly: Itemskin's visualizer frame states its client at `x="27"` while
    /// the hole in `cont.clear.avs` starts at 26, leaving a one-pixel seam down the left edge and none
    /// on the other three. It never shows on the skin's own window because that window's content is
    /// black on a black border. Ours is not, so the client is grown to pass beneath the border, which
    /// is what the skin does deliberately elsewhere — its download window puts content at `36,36`
    /// under a hole at `33,55`.
    static let clientBleed = 2.0

    private static func bled(_ rect: [String: String]) -> [String: String] {
        var result = rect
        func adjust(_ name: String, by delta: Double) {
            guard let value = rect[name].flatMap(Double.init) else { return }
            result[name] = String(Int(value + delta))
        }
        adjust("x", by: -clientBleed)
        adjust("y", by: -clientBleed)
        adjust("w", by: 2 * clientBleed)
        adjust("h", by: 2 * clientBleed)
        return result
    }

    private static let rectAttributeNames = ["x", "y", "w", "h",
                                             "relatx", "relaty", "relatw", "relath"]

    private static func rectAttributes(of node: WalXMLNode) -> [String: String] {
        var result: [String: String] = [:]
        for name in rectAttributeNames {
            if let value = node.attribute(name) { result[name] = value }
        }
        return result
    }

    private static let maximumInheritanceDepth = 16

    /// Whether this frame's own script can build its client area — that is, whether it calls
    /// `newGroup`, which is how `standardframe.maki` instantiates the group named by `content=`.
    ///
    /// The bytecode is read rather than the markup because *declaring a script* turned out not to
    /// mean the frame instantiates anything. Itemskin's `wasabi.standardframe.static` declares
    /// `standardframeStatic.maki`, which draws the window's chrome and calls neither `getParam` nor
    /// `newGroup`; accepting it gave every hosted window a frame around an empty hole, which fails at
    /// materialization and drops the window into NullPlayer's own chrome.
    ///
    /// A script whose body cannot be read or parsed keeps the old, weaker answer, so a resolution
    /// difference here can only ever leave a skin where it already was.
    private static func hasContentScript(_ definition: WalXMLNode,
                                         definitions: [String: WalXMLNode], depth: Int,
                                         scriptReader: ScriptReader?) -> Bool {
        guard depth <= maximumInheritanceDepth else { return false }
        for script in scriptNodes(in: definition) {
            guard let scriptReader,
                  let rawPath = script.attribute("file"), !rawPath.isEmpty,
                  let data = scriptReader(rawPath, script.location),
                  let program = try? MakiBytecodeParser().parse(data, source: script.location) else {
                return true
            }
            if program.methods.contains(where: { $0.name == contentInstantiationMethod }) { return true }
        }
        guard let parent = definition.attribute("inherit_group"),
              let inherited = definitions[fold(parent)] else { return false }
        return hasContentScript(inherited, definitions: definitions, depth: depth + 1,
                                scriptReader: scriptReader)
    }

    /// The MAKI method a standard frame calls to build its client area out of `content=`. Method
    /// names are lowercased by the parser.
    private static let contentInstantiationMethod = "newgroup"

    /// Where a `content=` frame's own script puts its client, in skin pixels.
    ///
    /// `standardframe.maki` builds the client area from its `<script param="x,y,w,h,relatx,relaty,
    /// relatw,relath">` — the tokens are `setXmlParam`'d straight onto the group named by `content=` —
    /// so a negative `w`/`h` there is the border, exactly the way an exemplar's component rect is.
    /// It is the only statement such a skin makes about where its client goes, and 51 of the 67
    /// corpus archives make it: HeadAMP's status frame is `25,28,-40,-70`, which ate 40x70 of a
    /// window sized as if the frame cost nothing and left a 343x145 meter drawing in 303x75 (B140).
    ///
    /// Read from the markup and not from the bytecode because the rect is *in* the markup; a script
    /// that ignores its param only ever leaves the window the two skin pixels of slack a frame with
    /// no rect at all already had.
    private static func scriptClientRect(_ definition: WalXMLNode,
                                         definitions: [String: WalXMLNode], depth: Int) -> CGRect? {
        guard depth <= maximumInheritanceDepth else { return nil }
        for script in scriptNodes(in: definition) {
            let tokens = (script.attribute("param") ?? "")
                .split(separator: ",", omittingEmptySubsequences: false)
                .map { Double($0.trimmingCharacters(in: .whitespaces)) }
            guard tokens.count >= 4, let x = tokens[0], let y = tokens[1],
                  let width = tokens[2], let height = tokens[3],
                  width < 0, height < 0, x >= 0, y >= 0, -width > x, -height > y else { continue }
            return CGRect(x: x, y: y, width: -width, height: -height)
        }
        guard let parent = definition.attribute("inherit_group"),
              let inherited = definitions[fold(parent)] else { return nil }
        return scriptClientRect(inherited, definitions: definitions, depth: depth + 1)
    }

    private static func scriptNodes(in node: WalXMLNode) -> [WalXMLNode] {
        var found: [WalXMLNode] = []
        for child in node.children {
            if child.name.caseInsensitiveCompare("script") == .orderedSame { found.append(child) }
            found.append(contentsOf: scriptNodes(in: child))
        }
        return found
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

        let children = frameNodes(frame: frame, frameID: "\(contentGroupID).frame",
                                  contentGroupID: contentGroupID, componentName: name,
                                  location: location)
        let floor = frame.floor(under: geometry.minimumSize)
        let opening = frame.floor(under: geometry.defaultSize)
        let layout = WalXMLNode(name: "layout", attributes: [
            "id": "normal",
            "default_w": String(Int(opening.width)),
            "default_h": String(Int(opening.height)),
            "minimum_w": String(Int(floor.width)),
            "minimum_h": String(Int(floor.height)),
        ], location: location, children: children)
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
