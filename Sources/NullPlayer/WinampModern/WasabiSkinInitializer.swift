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
                "Group definition '\(definition.identifier)' replaces the earlier definition at \(previous.source).",
                severity: .warning,
                location: definition.source
            ))
        }
        byIdentifier[key] = definition
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

    func validateInheritance() throws {
        for definition in byIdentifier.values.sorted(by: { $0.identifier < $1.identifier }) {
            _ = try resolved(identifier: definition.identifier)
        }
    }

    func definition(forInstance node: WalXMLNode) -> WasabiGroupDefinition? {
        if let identifier = identifierByXUITag[Self.fold(node.name)] {
            return byIdentifier[Self.fold(identifier)]
        }
        if node.name.caseInsensitiveCompare("group") == .orderedSame,
           let identifier = node.attribute("id") {
            return byIdentifier[Self.fold(identifier)]
        }
        return nil
    }

    func contains(identifier: String) -> Bool { byIdentifier[Self.fold(identifier)] != nil }

    func resolved(identifier: String) throws -> WasabiResolvedGroupDefinition {
        try resolve(identifier: identifier, stack: [])
    }

    private func resolve(identifier: String, stack: [String]) throws -> WasabiResolvedGroupDefinition {
        let key = Self.fold(identifier)
        if let cached = resolvedCache[key] { return cached }
        guard let definition = byIdentifier[key] else {
            throw WalFailure(WalDiagnostic(.missingGroupDefinition, "Group definition '\(identifier)' does not exist."))
        }
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
                let parent = try resolve(identifier: parentID, stack: stack + [key])
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
        resolvedCache[key] = result
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
    let diagnostics: [WalDiagnostic]
    private(set) var state: WasabiRuntimeState = .awaitingFirstPaint

    init(resources: WalResourceRegistry, types: WasabiTypeRegistry, graph: WasabiObjectGraph,
         scriptBindings: [WasabiScriptBinding], completedPasses: [WasabiInitializationPass],
         diagnostics: [WalDiagnostic]) {
        self.resources = resources
        self.types = types
        self.graph = graph
        self.scriptBindings = scriptBindings
        self.completedPasses = completedPasses
        self.diagnostics = diagnostics
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
        try registerResources(in: document.roots, registry: resources, validatedImages: &validatedImages)
        passes.append(.resourceRegistration)

        let types = WasabiTypeRegistry()
        // Register the skin/engine groupdefs first so an explicit definition always wins over our
        // predefined shell, then backfill any predefined Wasabi bases the skin inherits but omits.
        registerTypes(in: document.roots, registry: types)
        registerWasabiStandardLibrary(in: types)
        try types.validateInheritance()
        passes.append(.groupAndXUIRegistration)

        let graph = WasabiObjectGraph()
        var pendingScripts: [PendingScript] = []
        var pendingMetaCommands: [PendingMetaCommand] = []
        var createdCount = 0
        try createObjects(from: document.roots, parent: nil, graph: graph, types: types,
                          pendingScripts: &pendingScripts, pendingMetaCommands: &pendingMetaCommands,
                          definitionStack: [], createdCount: &createdCount)
        applyMetaCommands(pendingMetaCommands)
        passes.append(.objectCreation)

        let bindings = try bindScripts(pendingScripts)
        for (pending, binding) in zip(pendingScripts, bindings) { pending.owner?.addScriptBinding(binding) }
        passes.append(.scriptBinding)

        passes.append(.initialization)
        graph.markAllDirty(.all)
        passes.append(.firstPaint)

        return WasabiSkinRuntime(
            resources: resources,
            types: types,
            graph: graph,
            scriptBindings: bindings,
            completedPasses: passes,
            diagnostics: document.diagnostics + resources.diagnostics + types.diagnostics
        )
    }

    private func registerResources(in nodes: [WalXMLNode], registry: WalResourceRegistry,
                                   validatedImages: inout Set<String>) throws {
        let resourceTags: Set<String> = ["bitmap", "bitmapfont", "truetypefont", "color", "gammagroup", "gammaset", "cursor"]
        for node in nodes {
            let kind = node.name.lowercased()
            if kind == "elementalias", let identifier = node.attribute("id"),
               let target = node.attribute("target"), !identifier.isEmpty, !target.isEmpty {
                registry.registerAlias(identifier: identifier, target: target, source: node.location)
            }
            if resourceTags.contains(kind) {
                var logicalFile: String?
                // Bitmap-font `file` values may name a previously declared bitmap rather
                // than a VFS path (the stock Winamp Modern skin uses this form for every
                // bitmap font). Keep that identifier in `attributes`; the renderer resolves
                // it through the bounded resource registry. TrueType fonts and image-backed
                // resources still resolve through the VFS here and fail closed when missing.
                if kind != "bitmapfont",
                   let rawFile = node.attribute("file"), !rawFile.isEmpty,
                   // Predefined generated bitmaps (`file="$solid"` / `"$gradient"`) are synthesized
                   // from their `color`/`w`/`h` attributes, not loaded from the VFS. Keep the marker
                   // in `attributes`; the renderer generates the pixels on demand.
                   !rawFile.hasPrefix("$") {
                    do {
                        let resolved = try resolveSkinResource(rawFile, source: node.location).logicalPath
                        logicalFile = resolved
                        if (kind == "bitmap" || kind == "cursor"),
                           validatedImages.insert(resolved).inserted {
                            try validateImage(at: resolved, source: node.location)
                        }
                    } catch let failure as WalFailure
                        where (kind == "bitmap" || kind == "cursor")
                            && failure.diagnostics.allSatisfy({ $0.code == .resourceMissing }) {
                        // Real skins and the ClassicPro engine declare optional bitmaps whose image
                        // files aren't shipped; Winamp tolerates this and simply draws nothing.
                        // Register the resource without a file and record a warning rather than
                        // failing the whole load. Security failures (traversal/escape/variable/
                        // oversize/corrupt image) still throw above.
                        registry.warn(WalDiagnostic(.resourceMissing,
                            "Optional \(kind) resource '\(rawFile)' is missing; it will not render.",
                            severity: .warning, location: node.location))
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

    private func registerTypes(in nodes: [WalXMLNode], registry: WasabiTypeRegistry) {
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
                    source: node.location
                ))
            }
            registerTypes(in: node.children, registry: registry)
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
        // Media-facing composites
        "wasabi.albumart",
        "wasabi.ratings",
    ]

    private func registerWasabiStandardLibrary(in registry: WasabiTypeRegistry) {
        // Seed each predefined base only when the skin/engine hasn't already declared it, so a skin
        // that *does* ship a fuller definition always wins over our identifier-only shell.
        for identifier in Self.wasabiStandardLibraryGroups {
            guard !registry.contains(identifier: identifier) else { continue }
            registry.register(WasabiGroupDefinition(
                identifier: identifier,
                xuiTag: nil,
                inheritedGroup: nil,
                embeddedXUITag: nil,
                defaultAttributes: [:],
                templateChildren: [],
                source: WalSourceLocation(path: "/System/WasabiStandardLibrary.xml")
            ))
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
        createdCount: inout Int
    ) throws {
        let wrappers: Set<String> = ["wasabixml", "winampabstractionlayer", "elements", "skininfo"]
        let declarations: Set<String> = ["groupdef", "bitmap", "bitmapfont", "truetypefont", "color", "gammagroup", "gammaset", "cursor", "elementalias"]

        for node in nodes {
            let lower = node.name.lowercased()
            if lower == "script" {
                if let rawFile = node.attribute("file"), !rawFile.isEmpty {
                    pendingScripts.append(PendingScript(owner: parent, rawPath: rawFile,
                                                        parameter: node.attribute("param"), source: node.location))
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
                                  createdCount: &createdCount)
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
            if let definition = types.definition(forInstance: node) {
                let key = definition.identifier.lowercased()
                guard !definitionStack.contains(key) else {
                    throw WalFailure(WalDiagnostic(.groupInheritanceCycle, "Recursive group expansion for '\(definition.identifier)'.", location: node.location))
                }
                let resolved = try types.resolved(identifier: definition.identifier)
                var merged = resolved.defaultAttributes
                merged.merge(attributes) { _, instance in instance }
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
                              createdCount: &createdCount)
            let embeddedParent = embeddedXUITag.flatMap { findObject(xmlID: $0, beneath: object) } ?? object
            try createObjects(from: instanceChildren, parent: embeddedParent, graph: graph, types: types,
                              pendingScripts: &pendingScripts, pendingMetaCommands: &pendingMetaCommands,
                              definitionStack: nextDefinitionStack,
                              createdCount: &createdCount)
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
