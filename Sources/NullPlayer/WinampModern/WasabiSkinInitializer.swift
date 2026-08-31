import Foundation
import ImageIO

struct WasabiResourceLimits: Equatable {
    var maximumImageWidth = 8_192
    var maximumImageHeight = 8_192
    var maximumImagePixels = 32_000_000
    var maximumFontPointSize = 512.0
    var maximumScriptSize = 4 * 1_024 * 1_024

    static let production = WasabiResourceLimits()
}

struct WalResourceDefinition {
    let kind: String
    let identifier: String?
    let logicalFile: String?
    let attributes: [String: String]
    let source: WalSourceLocation
}

final class WalResourceRegistry {
    private(set) var definitions: [WalResourceDefinition] = []
    private(set) var diagnostics: [WalDiagnostic] = []
    private var byIdentifier: [String: WalResourceDefinition] = [:]
    /// The colour-carrying declarations only, indexed separately from everything else.
    ///
    /// Wasabi keeps bitmaps and colours in **different tables**, so one id may legitimately name both
    /// — and skins use that: Big Bento Modern declares `wasabi.list.background` as a `<color>` in
    /// `system-colors.xml` *and* as a tiled `<bitmap>` in `system-elements.xml`. With one flat table
    /// the bitmap won, a colour lookup found an image with no `color=` attribute, and every surface
    /// that asked the skin for its list background fell through to the black literal instead (BB2a).
    private var colorsByIdentifier: [String: WalResourceDefinition] = [:]
    private var aliases: [String: String] = [:]

    func register(_ definition: WalResourceDefinition) {
        definitions.append(definition)
        guard let identifier = definition.identifier, !identifier.isEmpty else { return }
        let key = Self.fold(identifier)
        // A *different* definition replacing an earlier one is worth saying; the same definition read
        // twice is not. A skin sharing an elements file between two containers re-includes every
        // resource in it, which is ordinary Winamp practice — 198 of LOBE's 233 findings were this,
        // and they were what pushed the skin's compatibility level to `degraded` (B29).
        if let previous = byIdentifier[key], !Self.isSameDefinition(previous, definition) {
            diagnostics.append(WalDiagnostic(
                .duplicateIdentifier,
                "Resource id '\(identifier)' replaces the earlier definition at \(previous.source).",
                severity: .warning,
                location: definition.source
            ))
        }
        byIdentifier[key] = definition
        // Later wins among equals, but a real `<color>` outranks a generated bitmap however late the
        // bitmap arrives. Ebonite_2_1 declares `wasabi.list.background` as **both**: a `<color>` at
        // 70,70,70 ("lists/trees item background") and a `$solid` at 237,237,237 ("Tree background
        // bitmap (tile)"). Its list text is white, so taking the tile painted white on near-white.
        // The two are different things to Winamp — one is a colour, one is artwork a tree tiles —
        // and only the first is an answer to "what colour is a list background".
        if Self.colorRank(definition) > Self.colorRank(colorsByIdentifier[key]) ||
            (Self.colorRank(definition) == Self.colorRank(colorsByIdentifier[key]) && Self.colorRank(definition) > 0) {
            colorsByIdentifier[key] = definition
        }
    }

    /// How well a declaration answers a **colour** request: a `<color>` best, then one of the
    /// generated `$solid`/`$gradient` bitmaps whose pixels *are* its `color=` attribute (cPro-Bento
    /// declares its list background only that way), then not at all.
    private static func colorRank(_ definition: WalResourceDefinition?) -> Int {
        guard let definition else { return 0 }
        if definition.kind.caseInsensitiveCompare("color") == .orderedSame { return 2 }
        let isGenerated = definition.kind.caseInsensitiveCompare("bitmap") == .orderedSame
            && definition.attributes["file"]?.hasPrefix("$") == true
            && definition.attributes["color"] != nil
        return isGenerated ? 1 : 0
    }

    func warn(_ diagnostic: WalDiagnostic) { diagnostics.append(diagnostic) }

    func definition(identifier: String) -> WalResourceDefinition? { byIdentifier[Self.fold(identifier)] }

    func registerAlias(identifier: String, target: String, source: WalSourceLocation) {
        let key = Self.fold(identifier)
        if aliases[key] != nil || byIdentifier[key] != nil {
            diagnostics.append(WalDiagnostic(.duplicateIdentifier,
                                             "Resource alias '\(identifier)' replaces an earlier resource.",
                                             severity: .warning, location: source))
        }
        aliases[key] = target
    }

    func resolvedDefinition(identifier: String) -> WalResourceDefinition? {
        resolved(identifier: identifier, in: byIdentifier)
    }

    /// The declaration that answers a **colour** request for this id, which is not always the one
    /// `resolvedDefinition` answers — see `colorsByIdentifier`. Falls back to the general table so an
    /// id declared only once behaves exactly as before.
    func resolvedColorDefinition(identifier: String) -> WalResourceDefinition? {
        resolved(identifier: identifier, in: colorsByIdentifier)
            ?? resolvedDefinition(identifier: identifier)
    }

    private func resolved(identifier: String,
                          in table: [String: WalResourceDefinition]) -> WalResourceDefinition? {
        var key = Self.fold(identifier)
        var visited: Set<String> = []
        for _ in 0..<64 {
            guard visited.insert(key).inserted else { return nil }
            if let definition = table[key] { return definition }
            guard let target = aliases[key] else { return nil }
            key = Self.fold(target)
        }
        return nil
    }

    /// What a resource *is*, with no regard for which file it was read from: the kind, the file it
    /// points at, and its attributes.
    private static func isSameDefinition(_ lhs: WalResourceDefinition,
                                         _ rhs: WalResourceDefinition) -> Bool {
        lhs.kind.caseInsensitiveCompare(rhs.kind) == .orderedSame
            && lhs.logicalFile == rhs.logicalFile
            && lhs.attributes == rhs.attributes
    }

    private static func fold(_ value: String) -> String {
        value.folding(options: [.caseInsensitive], locale: Locale(identifier: "en_US_POSIX"))
    }
}

struct WasabiGroupDefinition {
    let identifier: String
    let xuiTag: String?
    let inheritedGroup: String?
    let embeddedXUITag: String?
    let defaultAttributes: [String: String]
    let templateChildren: [WalXMLNode]
    let source: WalSourceLocation
    /// Where this `<groupdef>` sits in the expanded document, in pre-order. Winamp's parser is
    /// streaming: a `<group>` instantiates whatever definition of that id has been read *so far*,
    /// so a skin may redefine an id later in the document without disturbing the groups already
    /// built from the earlier one. `Int.min` (the default) means "predates the whole document",
    /// which is what our predefined Wasabi shells and test fixtures want.
    var documentOrder: Int = .min
}

struct WasabiResolvedGroupDefinition {
    let identifier: String
    let embeddedXUITag: String?
    let defaultAttributes: [String: String]
    let templateChildren: [WalXMLNode]
}

final class WasabiTypeRegistry {
    let maximumInheritanceDepth: Int
    private(set) var diagnostics: [WalDiagnostic] = []
    private var byIdentifier: [String: WasabiGroupDefinition] = [:]
    /// Every definition registered for an id, in registration (document) order. Only ids a skin
    /// actually redefines have more than one, so this costs nothing for the common case.
    private var versionsByIdentifier: [String: [WasabiGroupDefinition]] = [:]
    private var identifierByXUITag: [String: String] = [:]
    private var resolvedCache: [String: WasabiResolvedGroupDefinition] = [:]

    init(maximumInheritanceDepth: Int = 64) {
        self.maximumInheritanceDepth = maximumInheritanceDepth
    }

    func register(_ definition: WasabiGroupDefinition) {
        let key = Self.fold(definition.identifier)
        // Same rule as the resource registry: a re-include of an identical `<groupdef>` is not a
        // redefinition, and warning about it says nothing about the skin (B29).
        if let previous = byIdentifier[key], !Self.isSameDefinition(previous, definition) {
            diagnostics.append(WalDiagnostic(
                .duplicateIdentifier,
                "Group definition '\(definition.identifier)' is redefined; the earlier definition at "
                    + "\(previous.source) still serves the groups declared before this point.",
                severity: .warning,
                location: definition.source
            ))
        }
        byIdentifier[key] = definition
        versionsByIdentifier[key, default: []].append(definition)
        if let xuiTag = definition.xuiTag, !xuiTag.isEmpty {
            let xuiKey = Self.fold(xuiTag)
            if let previousID = identifierByXUITag[xuiKey],
               Self.fold(previousID) != Self.fold(definition.identifier) {
                diagnostics.append(WalDiagnostic(
                    .duplicateIdentifier,
                    "XUI tag '\(xuiTag)' is reassigned from group '\(previousID)' to '\(definition.identifier)'.",
                    severity: .warning,
                    location: definition.source
                ))
            }
            identifierByXUITag[xuiKey] = definition.identifier
        }
        resolvedCache.removeAll()
    }

    /// Point an unclaimed XUI tag at a groupdef the skin already declares.
    ///
    /// Narrow on purpose: it applies only when the destination groupdef exists *and* nothing has
    /// claimed the tag, so a skin that declares its own `xuitag=` always wins and no tag is ever
    /// silently repointed. Used for the conventional `wasabi.standardframe.*` pairs that mmd3 (like
    /// real Winamp's standard library) leaves to convention. Returns whether the alias was applied.
    @discardableResult
    func registerXUITagAlias(_ tag: String, to identifier: String) -> Bool {
        let tagKey = Self.fold(tag)
        guard identifierByXUITag[tagKey] == nil, contains(identifier: identifier) else { return false }
        identifierByXUITag[tagKey] = identifier
        resolvedCache.removeAll()
        return true
    }

    func validateInheritance() throws {
        for definition in versionsByIdentifier.values.flatMap({ $0 })
            .sorted(by: { ($0.identifier, $0.documentOrder) < ($1.identifier, $1.documentOrder) }) {
            _ = try resolved(definition)
        }
    }

    /// The definition a `<group>`/XUI-tag instance expands to. `documentOrder` is where the instance
    /// sits in the expanded document: the definition in force *there* wins, so a later redefinition
    /// of the same id (T800 gives `player.main.cms` a second body for its shade layout) reaches only
    /// the groups declared after it, exactly as Winamp's streaming parser does. Pass `nil` for an
    /// instance with no document position of its own — a script's `System.newGroup`, a synthesized
    /// node — which takes the newest definition.
    func definition(forInstance node: WalXMLNode, documentOrder: Int? = nil) -> WasabiGroupDefinition? {
        if let identifier = identifierByXUITag[Self.fold(node.name)] {
            return definition(identifier: identifier, documentOrder: documentOrder)
        }
        if node.name.caseInsensitiveCompare("group") == .orderedSame,
           let identifier = node.attribute("id") {
            return definition(identifier: identifier, documentOrder: documentOrder)
        }
        return nil
    }

    private func definition(identifier: String, documentOrder: Int?) -> WasabiGroupDefinition? {
        let key = Self.fold(identifier)
        guard let versions = versionsByIdentifier[key], versions.count > 1, let documentOrder else {
            return byIdentifier[key]
        }
        // Lenient where Winamp is not: a group referenced before any definition of its id gets the
        // first one rather than nothing, so a forward reference still renders something.
        return versions.last { $0.documentOrder <= documentOrder } ?? versions.first
    }

    func contains(identifier: String) -> Bool { byIdentifier[Self.fold(identifier)] != nil }

    /// Whether `tag` is a registered XUI tag (e.g. `Wasabi:MainFrame:NoStatus`). Objects created
    /// from one receive `onSetXuiParam` for their attributes, the way Wasabi delivers XUI params.
    func isXUITag(_ tag: String) -> Bool { identifierByXUITag[Self.fold(tag)] != nil }

    func resolved(identifier: String) throws -> WasabiResolvedGroupDefinition {
        guard let definition = byIdentifier[Self.fold(identifier)] else {
            throw WalFailure(WalDiagnostic(.missingGroupDefinition, "Group definition '\(identifier)' does not exist."))
        }
        return try resolve(definition: definition, stack: [])
    }

    /// Resolve one specific version of a definition — the one `definition(forInstance:documentOrder:)`
    /// picked, which is not necessarily the newest.
    func resolved(_ definition: WasabiGroupDefinition) throws -> WasabiResolvedGroupDefinition {
        try resolve(definition: definition, stack: [])
    }

    private func resolve(definition: WasabiGroupDefinition, stack: [String]) throws -> WasabiResolvedGroupDefinition {
        let identifier = definition.identifier
        let key = Self.fold(identifier)
        let cacheKey = "\(key)#\(definition.documentOrder)"
        if let cached = resolvedCache[cacheKey] { return cached }
        guard stack.count < maximumInheritanceDepth else {
            throw WalFailure(WalDiagnostic(.groupInheritanceDepthExceeded, "Group inheritance exceeds \(maximumInheritanceDepth) levels.", location: definition.source))
        }
        guard !stack.contains(key) else {
            let chain = (stack + [key]).joined(separator: " -> ")
            throw WalFailure(WalDiagnostic(.groupInheritanceCycle, "Group inheritance cycle detected: \(chain).", location: definition.source))
        }

        var attributes: [String: String] = [:]
        var children: [WalXMLNode] = []
        // `embed_xui` controls XUI embedding behavior; it is not an inheritance edge.
        if let parentReference = definition.inheritedGroup {
            let parentID = identifierByXUITag[Self.fold(parentReference)] ?? parentReference
            do {
                guard let base = self.definition(identifier: parentID, documentOrder: definition.documentOrder) else {
                    throw WalFailure(WalDiagnostic(.missingGroupDefinition,
                                                   "Group definition '\(parentID)' does not exist."))
                }
                let parent = try resolve(definition: base, stack: stack + [key])
                attributes.merge(parent.defaultAttributes) { _, new in new }
                children.append(contentsOf: parent.templateChildren)
            } catch let failure as WalFailure
                where failure.diagnostics.allSatisfy({ $0.code == .missingGroupDefinition }) {
                // Real skins/engines inherit from predefined Wasabi standard-library groups
                // (`wasabi.*`) that ship inside Winamp, not the skin. The common bases are now seeded
                // by `registerWasabiStandardLibrary`; this path only fires for a base outside that
                // curated set. Treat such an unknown base as empty and warn, so the derived group
                // still resolves. Inheritance cycles and depth overflows still hard-fail above.
                diagnostics.append(WalDiagnostic(.missingGroupDefinition,
                    "Group '\(identifier)' inherits unknown predefined group '\(parentReference)'; ignoring that base.",
                    severity: .warning, location: definition.source))
            }
        }
        attributes.merge(definition.defaultAttributes) { _, new in new }
        children.append(contentsOf: definition.templateChildren)

        let result = WasabiResolvedGroupDefinition(identifier: definition.identifier,
                                                   embeddedXUITag: definition.embeddedXUITag,
                                                   defaultAttributes: attributes,
                                                   templateChildren: children)
        resolvedCache[cacheKey] = result
        return result
    }

    /// What a `<groupdef>` *is* — its XUI tag, what it inherits, the XUI it embeds, its defaults and
    /// its whole template subtree — with no regard for the file it was read from.
    private static func isSameDefinition(_ lhs: WasabiGroupDefinition,
                                         _ rhs: WasabiGroupDefinition) -> Bool {
        guard lhs.xuiTag == rhs.xuiTag, lhs.inheritedGroup == rhs.inheritedGroup,
              lhs.embeddedXUITag == rhs.embeddedXUITag,
              lhs.defaultAttributes == rhs.defaultAttributes,
              lhs.templateChildren.count == rhs.templateChildren.count else { return false }
        for (mine, theirs) in zip(lhs.templateChildren, rhs.templateChildren)
        where !mine.isStructurallyEqual(to: theirs) {
            return false
        }
        return true
    }

    private static func fold(_ value: String) -> String {
        value.folding(options: [.caseInsensitive], locale: Locale(identifier: "en_US_POSIX"))
    }
}

enum WasabiInitializationPass: String, Codable {
    case resourceRegistration
    case groupAndXUIRegistration
    case objectCreation
    case scriptBinding
    case initialization
    case firstPaint
}

enum WasabiRuntimeState: Equatable {
    case initialized
    case awaitingFirstPaint
    case tornDown
}

final class WasabiSkinRuntime {
    let resources: WalResourceRegistry
    let types: WasabiTypeRegistry
    let graph: WasabiObjectGraph
    let scriptBindings: [WasabiScriptBinding]
    let completedPasses: [WasabiInitializationPass]
    let loadDiagnostics: [WalDiagnostic]
    private(set) var state: WasabiRuntimeState = .awaitingFirstPaint

    /// Whether `WinampModernScriptRuntime.start()` has run for this skin. Lives here rather than on
    /// the script runtime because a `WasabiSceneRenderer` holds the skin, not the scripts, and it is
    /// the renderer that has to know: a `Wasabi:StandardFrame`'s client group is instantiated by the
    /// skin's own `standardframe.maki` from an `onSetXuiParam`, so before this is true a window's
    /// scene is the bare frame with nothing in it (ClassicPro's Widgets Manager: 19 nodes before,
    /// 30 after). Anything sizing a window from what it contains has to wait for it.
    private(set) var hasStartedScripts = false

    func markScriptsStarted() { hasStartedScripts = true }

    /// Winamp's thinger (B34): which component icon the skin's `<componentbucket>`s are pointing at,
    /// and how far the strip is scrolled. Skin-wide — one skin has one thinger however many of its
    /// layouts and windows draw one.
    let componentBucket = WinampModernComponentBucketState()

    /// What paints this skin's `<vis>` boxes — Winamp's own analyzer/scope, or one of NullPlayer's
    /// (B53). Skin-wide for the thinger's reason: one skin draws its visualization in several boxes
    /// across several containers, and each has its own `WasabiSceneRenderer`.
    let spectrumAnalyzer = WinampModernSpectrumAnalyzerState()

    /// Diagnostics recorded *after* load — surface classification and synthesis decisions happen once
    /// the graph exists, and they belong in the same compatibility report as the load-time ones.
    /// Bounded and de-duplicated: a per-frame scene walk must not grow this without limit.
    private var postLoadDiagnostics: [WalDiagnostic] = []
    private var postLoadDiagnosticKeys: Set<String> = []
    private static let maximumPostLoadDiagnostics = 256
    private var trustedHostedContainerIDs: Set<WasabiObjectID> = []

    /// Every diagnostic this skin has produced, load-time first.
    var diagnostics: [WalDiagnostic] { loadDiagnostics + postLoadDiagnostics }

    func record(_ diagnostic: WalDiagnostic) {
        let key = "\(diagnostic.code.rawValue)\u{1}\(diagnostic.message)\u{1}\(diagnostic.location?.description ?? "")"
        guard !postLoadDiagnosticKeys.contains(key),
              postLoadDiagnostics.count < Self.maximumPostLoadDiagnostics else { return }
        postLoadDiagnosticKeys.insert(key)
        postLoadDiagnostics.append(diagnostic)
    }

    /// Instantiates a registered groupdef into the live graph, for MAKI's `System.newGroup`.
    /// Winamp Modern's window frames are hollow by design: `Wasabi:MainFrame:NoStatus` ships only
    /// the titlebar/menubar chrome, and `standardframe.maki` builds the client area at runtime from
    /// the frame's `content=` XUI param. Without this the main window renders as bare chrome.
    /// Set by `WasabiSkinInitializer`, which owns the expansion machinery (type registry, object
    /// limits, script path resolution).
    var instantiateGroup: ((_ identifier: String, _ parent: WasabiObject) throws -> WasabiObject)?

    /// Trusted, host-only request-time window growth. Unlike `instantiateGroup`, this closure is not
    /// reachable from MAKI and accepts only the typed NullPlayer hosted-window description.
    var instantiateHostedWindow: ((WinampModernHostedWindowInstantiation) throws -> WasabiObject)?

    func isTrustedHostedHolder(_ object: WasabiObject) -> Bool {
        var node: WasabiObject? = object
        while let current = node {
            if current.typeName.caseInsensitiveCompare("container") == .orderedSame {
                return trustedHostedContainerIDs.contains(current.stableID)
            }
            node = current.parent
        }
        return false
    }

    func discardHostedWindow(_ root: WasabiObject) {
        trustedHostedContainerIDs.remove(root.stableID)
        graph.discardSubtree(root)
    }

    fileprivate func registerHostedWindow(_ root: WasabiObject) {
        trustedHostedContainerIDs.insert(root.stableID)
    }

    init(resources: WalResourceRegistry, types: WasabiTypeRegistry, graph: WasabiObjectGraph,
         scriptBindings: [WasabiScriptBinding], completedPasses: [WasabiInitializationPass],
         diagnostics: [WalDiagnostic]) {
        self.resources = resources
        self.types = types
        self.graph = graph
        self.scriptBindings = scriptBindings
        self.completedPasses = completedPasses
        self.loadDiagnostics = diagnostics
    }

    func markFirstPaintComplete() {
        guard state == .awaitingFirstPaint else { return }
        state = .initialized
        _ = graph.consumeInvalidations()
    }

    func teardown() {
        guard state != .tornDown else { return }
        graph.teardown()
        state = .tornDown
    }
}

final class WasabiSkinInitializer {
    private struct PendingScript {
        weak var owner: WasabiObject?
        let rawPath: String
        let parameter: String?
        let source: WalSourceLocation
    }

    private struct PendingMetaCommand {
        weak var owner: WasabiObject?
        let kind: String
        let attributes: [String: String]
    }

    let vfs: WalVirtualFileSystem
    let maximumObjectCount: Int
    let resourceLimits: WasabiResourceLimits

    init(vfs: WalVirtualFileSystem, maximumObjectCount: Int = 100_000,
         resourceLimits: WasabiResourceLimits = .production) {
        self.vfs = vfs
        self.maximumObjectCount = maximumObjectCount
        self.resourceLimits = resourceLimits
    }

    func initialize(document: WalExpandedXMLDocument) throws -> WasabiSkinRuntime {
        var passes: [WasabiInitializationPass] = []
        let resources = WalResourceRegistry()
        var validatedImages: Set<String> = []
        var undecodableImages: Set<String> = []
        try registerResources(in: document.roots, registry: resources,
                              validatedImages: &validatedImages, undecodableImages: &undecodableImages)
        passes.append(.resourceRegistration)

        let types = WasabiTypeRegistry()
        // Register the skin/engine groupdefs first so an explicit definition always wins over our
        // predefined shell, then backfill any predefined Wasabi bases the skin inherits but omits.
        let documentOrder = documentOrder(of: document.roots)
        registerTypes(in: document.roots, registry: types, documentOrder: documentOrder)
        // Conventional tag → groupdef pairs before the shells: a skin that declares
        // `wasabi.standardframe.statusbar` without an `xuitag` (mmd3 does, exactly as real Winamp's
        // standard library expects) must still answer to `<Wasabi:StandardFrame:Status>`, and it must
        // win over the artwork-less shell registered next.
        for pair in WasabiStandardFrames.conventionalXUITags {
            types.registerXUITagAlias(pair.tag, to: pair.identifier)
        }
        registerWasabiStandardLibrary(in: types)
        try types.validateInheritance()
        passes.append(.groupAndXUIRegistration)

        let graph = WasabiObjectGraph()
        var pendingScripts: [PendingScript] = []
        var pendingMetaCommands: [PendingMetaCommand] = []
        var createdCount = 0
        try createObjects(from: document.roots, parent: nil, graph: graph, types: types,
                          pendingScripts: &pendingScripts, pendingMetaCommands: &pendingMetaCommands,
                          definitionStack: [], createdCount: &createdCount,
                          documentOrder: documentOrder, enclosingOrder: nil)
        applyMetaCommands(pendingMetaCommands)
        passes.append(.objectCreation)

        let bindings = try bindScripts(pendingScripts)
        for (pending, binding) in zip(pendingScripts, bindings) { pending.owner?.addScriptBinding(binding) }
        passes.append(.scriptBinding)

        passes.append(.initialization)
        graph.markAllDirty(.all)
        passes.append(.firstPaint)

        let runtime = WasabiSkinRuntime(
            resources: resources,
            types: types,
            graph: graph,
            scriptBindings: bindings,
            completedPasses: passes,
            diagnostics: document.diagnostics + resources.diagnostics + types.diagnostics
        )
        // The closure retains this initializer so runtime expansion keeps the same VFS, limits, and
        // object budget as load time. `createdCount` continues from the load-time total, so scripts
        // cannot grow the graph past `maximumObjectCount` by instantiating in a loop.
        runtime.instantiateGroup = { [self] identifier, parent in
            try instantiateGroupAtRuntime(identifier: identifier, parent: parent,
                                          graph: graph, types: types, createdCount: &createdCount)
        }
        runtime.instantiateHostedWindow = { [self] request in
            let root = try instantiateHostedWindowAtRuntime(request, graph: graph, types: types,
                                                            createdCount: &createdCount)
            runtime.registerHostedWindow(root)
            return root
        }
        return runtime
    }

    private func instantiateHostedWindowAtRuntime(
        _ request: WinampModernHostedWindowInstantiation,
        graph: WasabiObjectGraph,
        types: WasabiTypeRegistry,
        createdCount: inout Int
    ) throws -> WasabiObject {
        let id = request.definition.id
        let location = WalSourceLocation(path: WasabiSurfaceSynthesizer.sourcePath)
        let holder = WalXMLNode(name: "component", attributes: [
            "id": "\(id.contentGroupIdentifier).surface",
            "param": id.holderReference,
            "x": "0", "y": "0", "w": "0", "h": "0", "relatw": "1", "relath": "1",
        ], location: location)
        types.register(WasabiGroupDefinition(
            identifier: id.contentGroupIdentifier,
            xuiTag: nil,
            inheritedGroup: nil,
            embeddedXUITag: nil,
            defaultAttributes: [:],
            templateChildren: [holder],
            source: location
        ))
        try types.validateInheritance()

        var layoutAttributes: [String: String] = [
            "id": "normal",
            "default_w": String(Int(request.definition.defaultSize.width)),
            "default_h": String(Int(request.definition.defaultSize.height)),
            "minimum_w": String(Int(request.minimumSize.width)),
            "minimum_h": String(Int(request.minimumSize.height)),
        ]
        if let maximum = request.definition.maximumSize {
            if maximum.width.isFinite { layoutAttributes["maximum_w"] = String(Int(maximum.width)) }
            if maximum.height.isFinite { layoutAttributes["maximum_h"] = String(Int(maximum.height)) }
        }
        let frame = WalXMLNode(name: request.frame.xuiTag, attributes: [
            "id": "\(id.contentGroupIdentifier).frame",
            "content": id.contentGroupIdentifier,
            "componentname": request.definition.title,
            "x": "0", "y": "0", "w": "0", "h": "0", "relatw": "1", "relath": "1",
        ], location: location)
        let layout = WalXMLNode(name: "layout", attributes: layoutAttributes,
                                location: location, children: [frame])
        let containerNode = WalXMLNode(name: "container", attributes: [
            "id": id.containerIdentifier,
            "name": request.definition.title,
            "default_visible": "0",
            WinampModernContainerTopology.synthesizedAttribute: "1",
        ], location: location, children: [layout])

        let rootsBefore = Set(graph.roots.map(\.stableID))
        var pendingScripts: [PendingScript] = []
        var pendingMetaCommands: [PendingMetaCommand] = []
        do {
            try createObjects(from: [containerNode], parent: nil, graph: graph, types: types,
                              pendingScripts: &pendingScripts,
                              pendingMetaCommands: &pendingMetaCommands,
                              definitionStack: [], createdCount: &createdCount,
                              documentOrder: [:], enclosingOrder: nil)
            applyMetaCommands(pendingMetaCommands)
            let bindings = try bindScripts(pendingScripts)
            for (pending, binding) in zip(pendingScripts, bindings) {
                pending.owner?.addScriptBinding(binding)
            }
            guard let root = graph.roots.first(where: {
                !rootsBefore.contains($0.stableID) && $0.xmlID == id.containerIdentifier
            }) else {
                throw WalFailure(WalDiagnostic(.malformedXML,
                                               "Hosted window '\(id.rawValue)' created no container.",
                                               location: location))
            }
            return root
        } catch {
            for root in graph.roots where !rootsBefore.contains(root.stableID) {
                graph.discardSubtree(root)
            }
            throw error
        }
    }

    /// Expand `identifier`'s groupdef beneath `parent` after load, binding any scripts it declares
    /// so nested components (display, seek, vis…) come up exactly as they would have at load time.
    private func instantiateGroupAtRuntime(identifier: String, parent: WasabiObject,
                                           graph: WasabiObjectGraph, types: WasabiTypeRegistry,
                                           createdCount: inout Int) throws -> WasabiObject {
        guard types.contains(identifier: identifier) else {
            throw WalFailure(WalDiagnostic(.missingGroupDefinition,
                                           "Script requested unknown group '\(identifier)'.",
                                           location: parent.source))
        }
        let node = WalXMLNode(name: "group", attributes: ["id": identifier], location: parent.source)
        let existingChildren = parent.children.count
        var pendingScripts: [PendingScript] = []
        var pendingMetaCommands: [PendingMetaCommand] = []
        try createObjects(from: [node], parent: parent, graph: graph, types: types,
                          pendingScripts: &pendingScripts, pendingMetaCommands: &pendingMetaCommands,
                          definitionStack: [], createdCount: &createdCount,
                          documentOrder: [:], enclosingOrder: nil)
        applyMetaCommands(pendingMetaCommands)
        let bindings = try bindScripts(pendingScripts)
        for (pending, binding) in zip(pendingScripts, bindings) { pending.owner?.addScriptBinding(binding) }
        guard parent.children.count > existingChildren else {
            throw WalFailure(WalDiagnostic(.missingGroupDefinition,
                                           "Group '\(identifier)' expanded to no objects.",
                                           location: parent.source))
        }
        return parent.children[existingChildren]
    }

    private func registerResources(in nodes: [WalXMLNode], registry: WalResourceRegistry,
                                   validatedImages: inout Set<String>,
                                   undecodableImages: inout Set<String>) throws {
        // `gammagroup` is deliberately absent: its `id` is scoped to the enclosing `<gammaset>`, not
        // the global resource namespace, so registering it made every colour theme after the first
        // "replace" the previous theme's groups (MMD3 declares 83 themes → 1404 bogus duplicate-id
        // warnings). `WasabiColorThemeCatalog` reads the gammasets straight from the document.
        let resourceTags: Set<String> = ["bitmap", "bitmapfont", "truetypefont", "color", "gammaset", "cursor"]
        for node in nodes {
            let kind = node.name.lowercased()
            if kind == "elementalias", let identifier = node.attribute("id"),
               let target = node.attribute("target"), !identifier.isEmpty, !target.isEmpty {
                registry.registerAlias(identifier: identifier, target: target, source: node.location)
            }
            if resourceTags.contains(kind) {
                var logicalFile: String?
                // Bitmap-font `file` values come in **both** forms and a skin picks one freely: the
                // stock Winamp Modern skin names a previously declared bitmap, MMD3 names a path
                // ("player/tickerfont2.png"). So a bitmap font resolves its path here like any other
                // image and simply registers without one when that fails — the identifier stays in
                // `attributes` and the renderer looks it up in the registry instead. Resolving only
                // the identifier form dropped every bitmap-font string MMD3 draws.
                if let rawFile = node.attribute("file"), !rawFile.isEmpty,
                   // Predefined generated bitmaps (`file="$solid"` / `"$gradient"`) are synthesized
                   // from their `color`/`w`/`h` attributes, not loaded from the VFS. Keep the marker
                   // in `attributes`; the renderer generates the pixels on demand.
                   !rawFile.hasPrefix("$") {
                    do {
                        let resolved = try resolveSkinResource(rawFile, source: node.location).logicalPath
                        logicalFile = resolved
                        if kind == "bitmap" || kind == "cursor" || kind == "bitmapfont" {
                            // A dud file two `<bitmap>`s share degrades both, not just the first to
                            // reach it — without the memo the second would keep a `logicalFile` the
                            // renderer can never decode.
                            guard !undecodableImages.contains(resolved) else {
                                throw Self.undecodableImage(resolved, node.location)
                            }
                            if validatedImages.insert(resolved).inserted {
                                do {
                                    try validateImage(at: resolved, source: node.location)
                                } catch let failure as WalFailure
                                    where failure.diagnostics.allSatisfy({ $0.code == .invalidImageResource }) {
                                    undecodableImages.insert(resolved)
                                    throw failure
                                }
                            }
                        }
                    } catch let failure as WalFailure
                        where (kind == "bitmap" || kind == "cursor" || kind == "bitmapfont"
                                || kind == "truetypefont")
                            && failure.diagnostics.allSatisfy({
                                $0.code == .resourceMissing
                                    // A file that exists but is not a decodable image is a content
                                    // problem, not a security one, and the renderer already answers
                                    // `nil` for it safely. The Big Bento Modern Windows 10 edition
                                    // ships a **zero-byte** `window/no_alb_art_shade.png`, and one
                                    // dud PNG failed the whole skin — it would not load at all.
                                    // `.imageDimensionsExceeded` stays fatal: that one is the bound.
                                    || ($0.code == .invalidImageResource && kind != "truetypefont")
                            }) {
                        let undecodable = failure.diagnostics.contains { $0.code == .invalidImageResource }
                        // Real skins and the ClassicPro engine declare optional bitmaps whose image
                        // files aren't shipped; Winamp tolerates this and simply draws nothing.
                        // A `truetypefont` is tolerated for the same reason and was not: Rika
                        // declares `<truetypefont file="SUPERGLU.ttf">` and ships no such file, and
                        // one missing font failed the **whole skin** — it would not load at all,
                        // where Winamp falls back to a default face. `WasabiTextMetrics.font` already
                        // answers `nil` for a face it cannot produce and every caller has a fallback,
                        // so the cost of the miss is the skin's text in a substitute font.
                        // Register the resource without a file and record a warning rather than
                        // failing the whole load. Security failures (traversal/escape/variable/
                        // oversize/corrupt image) still throw above.
                        // A bitmap font that does not resolve as a path is the *identifier* form, not
                        // a missing file, so it is not worth a warning — the renderer resolves it
                        // through the registry and only a genuinely unknown id draws nothing.
                        if undecodable {
                            // The path *did* resolve, so drop it: a registered `logicalFile` the
                            // renderer cannot decode would have it retry the decode on every draw.
                            // An id that resolved to a dud file is worth a warning even for a
                            // bitmap font, where a plain miss is not.
                            logicalFile = nil
                            registry.warn(WalDiagnostic(.invalidImageResource,
                                "Bitmap resource '\(rawFile)' is not a decodable image; it will not render.",
                                severity: .warning, location: node.location))
                        } else if kind != "bitmapfont" {
                            registry.warn(WalDiagnostic(.resourceMissing,
                                "Optional \(kind) resource '\(rawFile)' is missing; it will not render.",
                                severity: .warning, location: node.location))
                        }
                    }
                }
                registry.register(WalResourceDefinition(
                    kind: kind,
                    identifier: node.attribute("id"),
                    logicalFile: logicalFile,
                    attributes: node.attributes,
                    source: node.location
                ))
            }
            try registerResources(in: node.children, registry: registry,
                                  validatedImages: &validatedImages,
                                  undecodableImages: &undecodableImages)
        }
    }

    private static func undecodableImage(_ path: String, _ source: WalSourceLocation) -> WalFailure {
        WalFailure(WalDiagnostic(.invalidImageResource,
                                 "Image resource '\(path)' has no valid image metadata.",
                                 location: source))
    }

    private func validateImage(at path: String, source: WalSourceLocation) throws {
        let data = try vfs.data(at: path, location: source)
        guard let imageSource = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(imageSource, 0, nil) as? [CFString: Any],
              let width = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue,
              let height = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue,
              width > 0, height > 0 else {
            throw Self.undecodableImage(path, source)
        }
        let (pixels, overflow) = width.multipliedReportingOverflow(by: height)
        guard !overflow,
              width <= resourceLimits.maximumImageWidth,
              height <= resourceLimits.maximumImageHeight,
              pixels <= resourceLimits.maximumImagePixels else {
            throw WalFailure(WalDiagnostic(
                .imageDimensionsExceeded,
                "Image resource '\(path)' is \(width)×\(height); limits are \(resourceLimits.maximumImageWidth)×\(resourceLimits.maximumImageHeight) and \(resourceLimits.maximumImagePixels) pixels.",
                location: source
            ))
        }
    }

    /// Number every node of the expanded document in pre-order — the order Winamp's streaming parser
    /// reads them in. `registerTypes` stamps each `<groupdef>` with its number and `createObjects`
    /// stamps each `<group>` instance with its own, which is what lets a redefined id serve two
    /// different bodies to the layouts on either side of it.
    private func documentOrder(of nodes: [WalXMLNode]) -> [ObjectIdentifier: Int] {
        var order: [ObjectIdentifier: Int] = [:]
        var next = 0
        func walk(_ nodes: [WalXMLNode]) {
            for node in nodes {
                order[ObjectIdentifier(node)] = next
                next += 1
                walk(node.children)
            }
        }
        walk(nodes)
        return order
    }

    private func registerTypes(in nodes: [WalXMLNode], registry: WasabiTypeRegistry,
                               documentOrder: [ObjectIdentifier: Int]) {
        for node in nodes {
            if node.name.caseInsensitiveCompare("groupdef") == .orderedSame,
               let identifier = node.attribute("id"), !identifier.isEmpty {
                var defaults = node.attributes
                for metadata in ["id", "xuitag", "inherit_group", "embed_xui"] { defaults.removeValue(forKey: metadata) }
                registry.register(WasabiGroupDefinition(
                    identifier: identifier,
                    xuiTag: node.attribute("xuitag"),
                    inheritedGroup: node.attribute("inherit_group"),
                    embeddedXUITag: node.attribute("embed_xui"),
                    defaultAttributes: defaults,
                    templateChildren: node.children,
                    source: node.location,
                    documentOrder: documentOrder[ObjectIdentifier(node)] ?? .min
                ))
            }
            registerTypes(in: node.children, registry: registry, documentOrder: documentOrder)
        }
    }

    /// Predefined Wasabi standard-library base groups. These ship *inside* Winamp (the stock
    /// `xml/wasabi.xml` / `xml/standard/*` library), not inside a `.wal` or the ClassicPro engine,
    /// so real skins and engines routinely `inherit_group="wasabi.*"` from bases we never receive as
    /// files. We seed them as minimal empty template groups so a derived group resolves a real (if
    /// artwork-less) base instead of dropping to a graceful-degradation warning. Genuinely unknown
    /// bases — anything not on this curated list — still warn-and-drop in `resolve(identifier:stack:)`.
    ///
    /// The list is curated from the measured targets' inheritance edges (Phase 0B inventory) plus the
    /// documented Wasabi standard library. No third-party art or SDK files are bundled; these are
    /// identifier-only shells. Add to this list on measured demand (Phase 7.3), not speculatively.
    static let wasabiStandardLibraryGroups: [String] = [
        // Client area / containers
        "wasabi.panel",
        "wasabi.frame",
        "wasabi.objectframe",
        "wasabi.objectframe.group",
        // Text
        "wasabi.text",
        "wasabi.text.group",
        // Buttons
        "wasabi.button",
        "wasabi.button.group",
        "wasabi.togglebutton",
        "wasabi.togglebutton.group",
        "wasabi.checkbox",
        // Edits
        "wasabi.edit",
        "wasabi.edit.box",
        "wasabi.edits",
        // Lists / scrolling
        "wasabi.list",
        "wasabi.scrollbar",
        "wasabi.scrollbar.horizontal",
        "wasabi.scrollbar.vertical",
        "wasabi.slider",
        // Standard window frames
        "wasabi.standardframe",
        "wasabi.standardframe.static",
        "wasabi.standardframe.modal",
        "wasabi.standardframe.statusbar",
        "wasabi.standardframe.nostatusbar",
        // Tabs / grouping
        "wasabi.tabsheet",
        "wasabi.titlebar",
        "wasabi.titlebox",
        "wasabi.tooltip",
        // Media-facing composites
        "wasabi.albumart",
        "wasabi.ratings",
    ]

    /// Where the seeded shells claim to come from. Not a real file — it exists so a diagnostic can say
    /// which definition a skin is actually using.
    static let wasabiStandardLibrarySource = WalSourceLocation(path: "/System/WasabiStandardLibrary.xml")

    /// Conventional tag → shell pairings, applied *after* the shells exist.
    ///
    /// `wasabi.standardframe.*` is aliased earlier (`WasabiStandardFrames.conventionalXUITags`) because
    /// there the destination is the skin's *own* groupdef. These point at our shells instead, so they
    /// have to run after seeding — `registerXUITagAlias` requires the destination to exist. Both passes
    /// only fill an *unclaimed* tag, so Winamp Modern's own `xuitag="Wasabi:TitleBar"` still wins.
    static let wasabiStandardLibraryXUITags: [(tag: String, identifier: String)] = [
        ("Wasabi:TitleBar", "wasabi.titlebar"),
        (WasabiTitleBox.xuiTag, WasabiTitleBox.groupIdentifier),
        (WasabiTabSheet.xuiTag, WasabiTabSheet.groupIdentifier),
    ]

    /// The standard-library shells that can be reconstructed from conventional skin resources.
    ///
    /// Most shells are identifier-only by design, but a title bar is a measured exception: CornerAmp
    /// instantiates `<Wasabi:TitleBar>` inside its own `wasabi.standardframe.nostatusbar` and never
    /// defines the tag — in real Winamp the standard library supplies it — so every CornerAmp window
    /// came up with a nameless title bar. The skin ships no `wasabi.titlebar.*` bitmaps either, so this
    /// invents no artwork: it restores the window *title*, resolved from `:componentname` the same way
    /// a skin-supplied title bar's own `<text>` is. `wasabi.window.text` and `wasabi.font.default` are
    /// the conventional ids — CornerAmp defines the colour, nothing measured defines the font, and both
    /// degrade (white, system font) when absent.
    private static func shellTemplateChildren(for identifier: String) -> [WalXMLNode] {
        switch identifier {
        case "wasabi.panel":
            return [standardLibraryGrid(
                id: "wasabi.panel.grid",
                prefix: "wasabi.panel",
                middle: "wasabi.panel.tint"
            )]
        case "wasabi.objectframe.group":
            return [standardLibraryGrid(
                id: "wasabi.objectframe.grid",
                prefix: "wasabi.objectframe",
                middle: "wasabi.objectframe.center"
            )]
        case "wasabi.titlebar":
            return [WalXMLNode(
                name: "text",
                attributes: [
                    "id": "window.titlebar.title",
                    "x": "0", "y": "0", "w": "0", "h": "0", "relatw": "1", "relath": "1",
                    "align": "center",
                    // A point under the 11 default: text draws from the top of its box and CornerAmp's
                    // title bar is 11px tall, where 11pt clips the descenders of "Playlist Editor".
                    "fontsize": "10",
                    "default": ":componentname",
                    "font": "wasabi.font.default",
                    "color": "wasabi.window.text",
                ],
                location: wasabiStandardLibrarySource
            )]
        default:
            return []
        }
    }

    /// Winamp supplies these two group bodies, while modern skins supply the artwork under stable
    /// `wasabi.*` bitmap ids. A tiled grid preserves the one-pixel edges and repeating centre
    /// textures used by the measured skins; absent parts already degrade to an empty grid.
    private static func standardLibraryGrid(id: String, prefix: String, middle: String) -> WalXMLNode {
        WalXMLNode(
            name: "grid",
            attributes: [
                "id": id,
                "x": "0", "y": "0", "w": "0", "h": "0", "relatw": "1", "relath": "1",
                "topleft": "\(prefix).top.left",
                "top": "\(prefix).top",
                "topright": "\(prefix).top.right",
                "left": "\(prefix).left",
                "middle": middle,
                "right": "\(prefix).right",
                "bottomleft": "\(prefix).bottom.left",
                "bottom": "\(prefix).bottom",
                "bottomright": "\(prefix).bottom.right",
                "tile": "1",
                "ghost": "1",
            ],
            location: wasabiStandardLibrarySource
        )
    }

    private func registerWasabiStandardLibrary(in registry: WasabiTypeRegistry) {
        // Seed each predefined base only when the skin/engine hasn't already declared it, so a skin
        // that *does* ship a fuller definition always wins over our shell.
        for identifier in Self.wasabiStandardLibraryGroups {
            guard !registry.contains(identifier: identifier) else { continue }
            registry.register(WasabiGroupDefinition(
                identifier: identifier,
                xuiTag: nil,
                inheritedGroup: nil,
                embeddedXUITag: nil,
                defaultAttributes: [:],
                templateChildren: Self.shellTemplateChildren(for: identifier),
                source: Self.wasabiStandardLibrarySource
            ))
        }
        for pair in Self.wasabiStandardLibraryXUITags {
            registry.registerXUITagAlias(pair.tag, to: pair.identifier)
        }
    }

    private func createObjects(
        from nodes: [WalXMLNode],
        parent: WasabiObject?,
        graph: WasabiObjectGraph,
        types: WasabiTypeRegistry,
        pendingScripts: inout [PendingScript],
        pendingMetaCommands: inout [PendingMetaCommand],
        definitionStack: [String],
        createdCount: inout Int,
        documentOrder: [ObjectIdentifier: Int],
        enclosingOrder: Int?
    ) throws {
        let wrappers: Set<String> = ["wasabixml", "winampabstractionlayer", "elements", "skininfo"]
        let declarations: Set<String> = ["groupdef", "bitmap", "bitmapfont", "truetypefont", "color", "gammagroup", "gammaset", "cursor", "elementalias"]

        for node in nodes {
            let lower = node.name.lowercased()
            if lower == "script" {
                if let rawFile = node.attribute("file"), !rawFile.isEmpty {
                    pendingScripts.append(PendingScript(owner: parent, rawPath: rawFile,
                                                        parameter: WasabiXMLMacroResolver.resolve(node.attribute("param")),
                                                        source: node.location))
                }
                continue
            }
            if ["sendparams", "hideobject", "showobject"].contains(lower) {
                pendingMetaCommands.append(PendingMetaCommand(owner: parent, kind: lower,
                                                              attributes: node.attributes))
                continue
            }
            if declarations.contains(lower) { continue }
            if wrappers.contains(lower) {
                try createObjects(from: node.children, parent: parent, graph: graph, types: types,
                                  pendingScripts: &pendingScripts, pendingMetaCommands: &pendingMetaCommands,
                                  definitionStack: definitionStack,
                                  createdCount: &createdCount,
                                  documentOrder: documentOrder, enclosingOrder: enclosingOrder)
                continue
            }

            var attributes = node.attributes
            if let rawSize = attributes["fontsize"], let pointSize = Double(rawSize),
               !pointSize.isFinite || pointSize > resourceLimits.maximumFontPointSize {
                throw WalFailure(WalDiagnostic(.fontSizeExceeded,
                                               "Font size '\(rawSize)' exceeds the \(resourceLimits.maximumFontPointSize)-point limit.",
                                               location: node.location))
            }
            var templateChildren: [WalXMLNode] = []
            let instanceChildren = node.children
            var embeddedXUITag: String?
            var nextDefinitionStack = definitionStack
            var typeName = node.name
            var formWidget: WasabiFormWidgets.Substitution?
            /// Whether the tag resolved to a definition the **skin** wrote, as opposed to one of our
            /// own artwork-less shells. A widget whose body a skin supplies is that skin's, and this
            /// is what keeps a hosted `<Wasabi:TabSheet>` from being drawn over a replacement.
            var claimedBySkin = false
            // A node the document itself contains is stamped with its own position; a template child
            // — expanded here, but written elsewhere — instantiates at the position of the reference
            // that brought it in, which is when Winamp would have read it.
            let nodeOrder = documentOrder[ObjectIdentifier(node)] ?? enclosingOrder
            if let definition = types.definition(forInstance: node, documentOrder: nodeOrder) {
                let key = definition.identifier.lowercased()
                guard !definitionStack.contains(key) else {
                    throw WalFailure(WalDiagnostic(.groupInheritanceCycle, "Recursive group expansion for '\(definition.identifier)'.", location: node.location))
                }
                let resolved = try types.resolved(definition)
                var merged = resolved.defaultAttributes
                merged.merge(attributes) { _, instance in instance }
                // `instanceid` *names the instance*: the expanded object answers to it instead of the
                // groupdef's id, which is how a skin tells two instantiations of one groupdef apart.
                // Winamp Modern's titlebar instantiates `wasabi.titlebar.streak` twice — left and
                // right — and both its `sendparams` and its script's
                // `findObject("wasabi.titlebar.streak.left")` address them this way. Without it the
                // script found neither streak, so the streaks kept their declared slot while the
                // title centred itself on the window and landed underneath them.
                if let instanceID = merged["instanceid"], !instanceID.isEmpty {
                    merged["id"] = instanceID
                }
                attributes = merged
                templateChildren = resolved.templateChildren
                embeddedXUITag = resolved.embeddedXUITag
                nextDefinitionStack.append(key)
                claimedBySkin = definition.source.path != Self.wasabiStandardLibrarySource.path
            } else if let substitution = WasabiFormWidgets.substitution(forTypeName: node.name) {
                // A Wasabi standard **form widget** nothing else claims. Winamp's own definition of
                // each is a thin wrapper around a primitive this engine already has, so the tag
                // becomes that primitive here and the rest of the engine needs to know nothing about
                // it — drawing, hit testing, `cfgattrib` binding and script dispatch all key off the
                // type. Without it 156 declarations across 15 skins were structure-free shells, which
                // is what an empty settings page usually is (B66).
                //
                // The `else` is the whole containment: a skin that defines the tag itself resolved a
                // definition above and never reaches here, so Big Bento Modern keeps its own search
                // box and Styx keeps its own drop-down wrapper.
                formWidget = substitution
                typeName = substitution.typeName
                attributes[WasabiFormWidgets.kindAttribute] = substitution.kind.rawValue
                for (name, value) in substitution.defaults where attributes[name] == nil {
                    attributes[name] = value
                }
            }

            createdCount += 1
            guard createdCount <= maximumObjectCount else {
                throw WalFailure(WalDiagnostic(.expandedNodeLimitExceeded, "Retained graph exceeds \(maximumObjectCount) objects.", location: node.location))
            }
            let object = graph.makeObject(typeName: typeName, attributes: attributes, source: node.location)
            if let parent { try parent.appendChild(object) } else { graph.appendRoot(object) }
            // A top-level container's *declared* visibility, snapshotted before anything can write
            // over it. `visible` is one attribute serving two questions — "is this an SUI-collapsed
            // stub the skin never means to show" (markup) and "is this window open right now"
            // (`setVisible`) — and a script hiding its own window at startup is the ordinary case, so
            // the second answer buries the first. Defix hides `VISCON` from `CORE_SCRIPT.maki` and
            // every later reader then classified the window as a stub that does not exist (B16).
            if parent == nil, typeName.caseInsensitiveCompare("container") == .orderedSame {
                _ = object.setAttribute(WinampModernContainerTopology.declaredVisibleAttribute,
                                        value: object.attributes["visible"] ?? "1")
            }
            try createObjects(from: templateChildren, parent: object, graph: graph, types: types,
                              pendingScripts: &pendingScripts, pendingMetaCommands: &pendingMetaCommands,
                              definitionStack: nextDefinitionStack,
                              createdCount: &createdCount,
                              documentOrder: documentOrder, enclosingOrder: nodeOrder)
            let embeddedParent = embeddedXUITag.flatMap { findObject(xmlID: $0, beneath: object) } ?? object
            // `embed_xui` does not only say where the instance's children go — it says which object
            // *is* the XUI, so the group answers for the embedded control's mouse events. Defix's
            // `bento.tabbutton` embeds its `mousetrap` button and the core script hooks `onLeftClick`
            // on the **group** (`switch.ml`); with nothing carrying the click across, the tab lit up
            // under the pointer and the SUI body never changed. Recorded on the group so the runtime
            // can find it from the child at dispatch time; `id` is not unique, but the pair
            // (this group, that id) is what the lookup above already resolved.
            if embeddedParent !== object, let tag = embeddedXUITag {
                _ = object.setAttribute("nullplayer.embedxui", value: tag.lowercased())
                // The wrapper *is* the control, so the range it declares is the **embedded** object's
                // range — a `<SC:VScrollBar low="0" high="100">` wrapping a bare `<slider>` means that
                // slider counts 0…100, not Winamp's default 0…255.
                //
                // Measured, from a live trace of Big Bento Modern's settings scrollbar: its up button
                // does `slider.setPosition(slider.getPosition() + 5)` on the **inner** slider, and the
                // page computes `scrollToPercent(99 - position)`. On the 0…255 default the positions
                // ran 113 → 118 → 123 → 128, so the percentage was *negative every time* and the page
                // clamped back to the top on every press: the bar moved, and nothing scrolled (BB19).
                // Only the range is carried across; geometry, identity and appearance belong to the
                // wrapper, and forwarding those would move the control inside its own group.
                for key in ["low", "high"] where embeddedParent.attributes[key] == nil {
                    if let value = attributes[key] { _ = embeddedParent.setAttribute(key, value: value) }
                }
                // The **commands** the instance declares, for the same reason and by the same rule:
                // the wrapper is a `<group>`, which has no click behaviour of its own, and the object
                // the pointer actually lands on is the embedded one. Enkera's whole transport is
                // `<button:glow … action="play">` over a bare `<button id="but" fitparent="1"/>`, and
                // Defix's two button bars are `<Defix:Bottom.bar.button action="PE_Add">` over a
                // `mousetrap`: in both the artwork drew, the press animated, and the command reached
                // nothing, because it stayed on a group that cannot run it. Commands only — geometry,
                // identity and appearance stay on the wrapper, which is what draws.
                for key in ["action", "param", "dblclickaction", "dbclickaction", "rightclickaction",
                            "tooltip"] where embeddedParent.attributes[key] == nil {
                    if let value = attributes[key] { _ = embeddedParent.setAttribute(key, value: value) }
                }
                // A **vertical** slider starts at the top of its travel, which is `high` — not at the
                // zero a missing value would otherwise read as. Only one that drives nothing itself
                // (no `action`, so no host value to take) and states a range is seeded; a seek or
                // volume slider is told its position by the host and must not be pre-empted.
                //
                // Measured: each of Big Bento Modern's settings pages opens by reading its
                // scrollbar's position and calling `scrollToPercent(99 - position)`. Read as 0 that
                // is *99% — the bottom*, and seven of the skin's nine pages launched scrolled to the
                // end of themselves. Seeding the attribute rather than special-casing the getter
                // keeps the thumb, the hit test and the script's arithmetic on one number.
                if embeddedParent.typeName.caseInsensitiveCompare("slider") == .orderedSame,
                   WasabiSceneRenderer.isVerticalOrientation(embeddedParent),
                   embeddedParent.attributes["action"] == nil,
                   embeddedParent.attributes["value"] == nil,
                   let high = embeddedParent.attributes["high"] {
                    _ = embeddedParent.setAttribute("value", value: high)
                }
            }
            try createObjects(from: instanceChildren, parent: embeddedParent, graph: graph, types: types,
                              pendingScripts: &pendingScripts, pendingMetaCommands: &pendingMetaCommands,
                              definitionStack: nextDefinitionStack,
                              createdCount: &createdCount,
                              documentOrder: documentOrder, enclosingOrder: nodeOrder)
            // A `<Wasabi:Frame>` declares its two panes by group id rather than nesting them, so the
            // splitter is what brings them into the graph. cPro-Bento's entire body (library tree,
            // playlist, tabs) hangs off one, and without this the SUI expands to an empty frame.
            if WasabiFrame.isFrame(object) {
                let panes = WasabiFrame.paneIdentifiers(of: object).map {
                    WalXMLNode(name: "group", attributes: ["id": $0], location: node.location)
                }
                try createObjects(from: panes, parent: object, graph: graph, types: types,
                                  pendingScripts: &pendingScripts, pendingMetaCommands: &pendingMetaCommands,
                                  definitionStack: nextDefinitionStack,
                                  createdCount: &createdCount,
                                  documentOrder: documentOrder, enclosingOrder: nodeOrder)
                WasabiFrame.applyLayout(to: object)
            }
            // A `<Wasabi:TitleBox>` names its body by group id the way a standard frame does, and
            // the object that would instantiate it lives in Winamp rather than in the skin. Without
            // this the body never enters the graph at all: Bio-Nid's `dtabox.content` — the one
            // control its only settings window exists to show — was simply absent.
            if WasabiTitleBox.isTitleBox(object),
               let content = WasabiTitleBox.contentGroupNode(for: object, location: node.location) {
                try createObjects(from: [content], parent: object, graph: graph, types: types,
                                  pendingScripts: &pendingScripts,
                                  pendingMetaCommands: &pendingMetaCommands,
                                  definitionStack: nextDefinitionStack,
                                  createdCount: &createdCount,
                                  documentOrder: documentOrder, enclosingOrder: nodeOrder)
            }
            // A `<Wasabi:TabSheet>` names its pages by group id the same way, and the object that
            // shows one of them at a time lives in Winamp rather than in the skin. Without this not
            // one page enters the graph: Shield_Amp's Configuration is a single tab sheet over three
            // groups whose form widgets are all implemented, and it drew as an empty slab (B14).
            if WasabiTabSheet.isTabSheet(object), !claimedBySkin {
                let pages = WasabiTabSheet.pageNodes(for: object, location: node.location)
                if !pages.isEmpty {
                    _ = object.setAttribute(WasabiTabSheet.hostedAttribute, value: "1")
                    try createObjects(from: pages, parent: object, graph: graph, types: types,
                                      pendingScripts: &pendingScripts,
                                      pendingMetaCommands: &pendingMetaCommands,
                                      definitionStack: nextDefinitionStack,
                                      createdCount: &createdCount,
                                      documentOrder: documentOrder, enclosingOrder: nodeOrder)
                    WasabiTabSheet.select(index: WasabiTabSheet.selectedIndex(of: object), on: object)
                }
            }
            // Winamp's drop-down carries a label object inside itself, and a skin's script reaches
            // for it by name: Styx's and Shield_Amp's `customdropdownlist.maki` are the same script,
            // and both do `findObject("dropdownlist.text")` then persist the pick from that object's
            // `onTextChanged`. With no such object the handle is null and the selection survives
            // nothing. The node is invisible — the drop-down draws its own label — so this adds a
            // handle, not a second copy of the text.
            if formWidget?.kind == .dropDownList,
               findObject(xmlID: WasabiFormWidgets.dropDownLabelID, beneath: object) == nil {
                try createObjects(from: [WasabiFormWidgets.labelNode(location: node.location)],
                                  parent: object, graph: graph, types: types,
                                  pendingScripts: &pendingScripts,
                                  pendingMetaCommands: &pendingMetaCommands,
                                  definitionStack: nextDefinitionStack,
                                  createdCount: &createdCount,
                                  documentOrder: documentOrder, enclosingOrder: nodeOrder)
            }
        }
    }

    private func applyMetaCommands(_ commands: [PendingMetaCommand]) {
        for command in commands {
            guard let owner = command.owner else { continue }
            let scope = command.attributes["group"].flatMap { findObject(xmlID: $0, beneath: owner) } ?? owner
            let targets = (command.attributes["target"] ?? "").split(separator: ";")
                .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            for targetID in targets {
                guard let target = findObject(xmlID: targetID, beneath: scope) else { continue }
                switch command.kind {
                case "hideobject": _ = target.setAttribute("visible", value: "0")
                case "showobject": _ = target.setAttribute("visible", value: "1")
                case "sendparams":
                    for (name, value) in command.attributes where name != "target" && name != "group" {
                        _ = target.setAttribute(name, value: value)
                    }
                default: break
                }
            }
        }
    }

    private func findObject(xmlID: String, beneath root: WasabiObject) -> WasabiObject? {
        if root.xmlID?.caseInsensitiveCompare(xmlID) == .orderedSame { return root }
        for child in root.children {
            if let match = findObject(xmlID: xmlID, beneath: child) { return match }
        }
        return nil
    }

    private func bindScripts(_ pendingScripts: [PendingScript]) throws -> [WasabiScriptBinding] {
        try pendingScripts.map { pending in
            let path = try resolveSkinResource(pending.rawPath, source: pending.source).logicalPath
            let data = try vfs.data(at: path, location: pending.source)
            guard data.count <= resourceLimits.maximumScriptSize else {
                throw WalFailure(WalDiagnostic(.entryTooLarge, "Script '\(path)' is \(data.count) bytes; the limit is \(resourceLimits.maximumScriptSize).", location: pending.source))
            }
            return WasabiScriptBinding(ownerID: pending.owner?.stableID, logicalPath: path,
                                       parameter: pending.parameter, source: pending.source)
        }
    }

    /// Wasabi includes are XML-file-relative, but bitmap/font/script declarations in real
    /// Winamp skins are commonly skin-root-relative even when declared by an included XML.
    /// Preserve the relative form first for authored subfolders, then fall back to the fixed
    /// `@SKINPATH@` VFS mount. Only a genuine missing-resource diagnostic may fall back;
    /// traversal, variables, and other security failures remain hard errors.
    private func resolveSkinResource(_ rawPath: String, source: WalSourceLocation) throws -> WalResolvedResource {
        do {
            return try vfs.resolve(rawPath, relativeTo: source.path, location: source)
        } catch let failure as WalFailure
            where failure.diagnostics.allSatisfy({ $0.code == .resourceMissing }) {
            return try vfs.resolve("@SKINPATH@/\(rawPath)", relativeTo: source.path, location: source)
        }
    }
}
