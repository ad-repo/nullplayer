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
    private var aliases: [String: String] = [:]

    func register(_ definition: WalResourceDefinition) {
        definitions.append(definition)
        guard let identifier = definition.identifier, !identifier.isEmpty else { return }
        let key = Self.fold(identifier)
        if let previous = byIdentifier[key] {
            diagnostics.append(WalDiagnostic(
                .duplicateIdentifier,
                "Resource id '\(identifier)' replaces the earlier definition at \(previous.source).",
                severity: .warning,
                location: definition.source
            ))
        }
        byIdentifier[key] = definition
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
        var key = Self.fold(identifier)
        var visited: Set<String> = []
        for _ in 0..<64 {
            guard visited.insert(key).inserted else { return nil }
            if let definition = byIdentifier[key] { return definition }
            guard let target = aliases[key] else { return nil }
            key = Self.fold(target)
        }
        return nil
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
        if let previous = byIdentifier[key] {
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
            if let previousID = identifierByXUITag[xuiKey] {
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

    /// Diagnostics recorded *after* load — surface classification and synthesis decisions happen once
    /// the graph exists, and they belong in the same compatibility report as the load-time ones.
    /// Bounded and de-duplicated: a per-frame scene walk must not grow this without limit.
    private var postLoadDiagnostics: [WalDiagnostic] = []
    private var postLoadDiagnosticKeys: Set<String> = []
    private static let maximumPostLoadDiagnostics = 256

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

    /// A `<script param="…">` carries macros Winamp expands before the script reads it back with
    /// `getParam()`, not a path, so this is deliberately separate from the VFS's path variables.
    ///
    /// `@HAVE_LIBRARY@` is the one skins act on: Defix's global script takes
    /// `stringToInteger(getParam())` as "is there a media library?" and, reading the literal `0`,
    /// dropped the Media Library and Playlist tabs out of its SUI tab strip and squeezed the two it
    /// kept to their 20px floor. NullPlayer hosts the library surface, so the answer is 1. An
    /// unrecognized macro is left alone — a skin that invented one gets what it wrote.
    private static func resolvedScriptParameter(_ raw: String?) -> String? {
        guard let raw, raw.contains("@") else { return raw }
        return raw.replacingOccurrences(of: "@HAVE_LIBRARY@", with: "1",
                                        options: [.caseInsensitive])
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
        try registerResources(in: document.roots, registry: resources, validatedImages: &validatedImages)
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
        return runtime
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
                                   validatedImages: inout Set<String>) throws {
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
                        if (kind == "bitmap" || kind == "cursor" || kind == "bitmapfont"),
                           validatedImages.insert(resolved).inserted {
                            try validateImage(at: resolved, source: node.location)
                        }
                    } catch let failure as WalFailure
                        where (kind == "bitmap" || kind == "cursor" || kind == "bitmapfont"
                                || kind == "truetypefont")
                            && failure.diagnostics.allSatisfy({ $0.code == .resourceMissing }) {
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
                        if kind != "bitmapfont" {
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
            try registerResources(in: node.children, registry: registry, validatedImages: &validatedImages)
        }
    }

    private func validateImage(at path: String, source: WalSourceLocation) throws {
        let data = try vfs.data(at: path, location: source)
        guard let imageSource = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(imageSource, 0, nil) as? [CFString: Any],
              let width = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue,
              let height = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue,
              width > 0, height > 0 else {
            throw WalFailure(WalDiagnostic(.invalidImageResource, "Image resource '\(path)' has no valid image metadata.", location: source))
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
    ]

    /// The one shell that draws something.
    ///
    /// The shells are identifier-only by design, but a title bar is a measured exception: CornerAmp
    /// instantiates `<Wasabi:TitleBar>` inside its own `wasabi.standardframe.nostatusbar` and never
    /// defines the tag — in real Winamp the standard library supplies it — so every CornerAmp window
    /// came up with a nameless title bar. The skin ships no `wasabi.titlebar.*` bitmaps either, so this
    /// invents no artwork: it restores the window *title*, resolved from `:componentname` the same way
    /// a skin-supplied title bar's own `<text>` is. `wasabi.window.text` and `wasabi.font.default` are
    /// the conventional ids — CornerAmp defines the colour, nothing measured defines the font, and both
    /// degrade (white, system font) when absent.
    private static func shellTemplateChildren(for identifier: String) -> [WalXMLNode] {
        guard identifier == "wasabi.titlebar" else { return [] }
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
                                                        parameter: Self.resolvedScriptParameter(node.attribute("param")),
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
            }

            createdCount += 1
            guard createdCount <= maximumObjectCount else {
                throw WalFailure(WalDiagnostic(.expandedNodeLimitExceeded, "Retained graph exceeds \(maximumObjectCount) objects.", location: node.location))
            }
            let object = graph.makeObject(typeName: node.name, attributes: attributes, source: node.location)
            if let parent { try parent.appendChild(object) } else { graph.appendRoot(object) }
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
