import Foundation

struct WasabiObjectID: RawRepresentable, Hashable, Codable, Comparable, CustomStringConvertible {
    let rawValue: UInt64
    static func < (lhs: WasabiObjectID, rhs: WasabiObjectID) -> Bool { lhs.rawValue < rhs.rawValue }
    var description: String { "o\(rawValue)" }
}

struct WasabiDirtyFlags: OptionSet, Hashable {
    let rawValue: Int

    static let geometry = WasabiDirtyFlags(rawValue: 1 << 0)
    static let appearance = WasabiDirtyFlags(rawValue: 1 << 1)
    static let content = WasabiDirtyFlags(rawValue: 1 << 2)
    static let structure = WasabiDirtyFlags(rawValue: 1 << 3)
    static let script = WasabiDirtyFlags(rawValue: 1 << 4)
    static let all: WasabiDirtyFlags = [.geometry, .appearance, .content, .structure, .script]
}

struct WasabiScriptBinding: Hashable {
    let ownerID: WasabiObjectID?
    let logicalPath: String
    let parameter: String?
    let source: WalSourceLocation
}

final class WasabiObject {
    let stableID: WasabiObjectID
    let typeName: String
    let source: WalSourceLocation
    private(set) var attributes: [String: String]
    private(set) weak var parent: WasabiObject?
    private(set) var children: [WasabiObject] = []
    private(set) var scriptBindings: [WasabiScriptBinding] = []
    private(set) var dirtyFlags: WasabiDirtyFlags = .all
    private(set) var isTornDown = false

    private weak var graph: WasabiObjectGraph?

    init(stableID: WasabiObjectID, typeName: String, attributes: [String: String],
         source: WalSourceLocation, graph: WasabiObjectGraph) {
        self.stableID = stableID
        self.typeName = typeName
        self.attributes = Dictionary(uniqueKeysWithValues: attributes.map { ($0.key.lowercased(), $0.value) })
        self.source = source
        self.graph = graph
    }

    var xmlID: String? { attributes["id"] }
    var geometry: WasabiGeometrySpec { WasabiGeometrySpec(attributes: attributes) }

    @discardableResult
    func setAttribute(_ name: String, value: String?) -> Bool {
        guard !isTornDown else { return false }
        let key = name.lowercased()
        let oldValue = attributes[key]
        guard oldValue != value else { return false }
        if let value { attributes[key] = value } else { attributes.removeValue(forKey: key) }
        // A script renaming an object invalidates the graph's id index. Rare, and cheap to be right
        // about: the alternative is a lookup that silently answers with the old name.
        if key == "id" { graph?.invalidateXMLIDIndex() }
        markDirty(Self.dirtyFlag(for: key))
        return true
    }

    func appendChild(_ child: WasabiObject) throws {
        try insertChild(child, at: children.count)
    }

    func insertChild(_ child: WasabiObject, at index: Int) throws {
        guard !isTornDown, !child.isTornDown, graph === child.graph else { return }
        var ancestor: WasabiObject? = self
        while let current = ancestor {
            guard current !== child else {
                throw WalFailure(WalDiagnostic(.malformedXML, "Object graph mutation would create an ownership cycle.", location: source))
            }
            ancestor = current.parent
        }
        child.parent?.removeChild(child)
        graph?.detachRoot(child)
        child.parent = self
        children.insert(child, at: max(0, min(index, children.count)))
        markDirty(.structure)
        child.markDirty(.all)
    }

    func removeChild(_ child: WasabiObject) {
        guard let index = children.firstIndex(where: { $0 === child }) else { return }
        children.remove(at: index)
        child.parent = nil
        graph?.promoteToRoot(child)
        markDirty(.structure)
    }

    func addScriptBinding(_ binding: WasabiScriptBinding) {
        guard !isTornDown else { return }
        scriptBindings.append(binding)
        markDirty(.script)
    }

    func markDirty(_ flags: WasabiDirtyFlags) {
        guard !isTornDown, !flags.isEmpty else { return }
        dirtyFlags.formUnion(flags)
        graph?.recordInvalidation(stableID, flags: flags)
    }

    @discardableResult
    func consumeDirtyFlags() -> WasabiDirtyFlags {
        let result = dirtyFlags
        dirtyFlags = []
        return result
    }

    fileprivate func teardownRecursively() {
        guard !isTornDown else { return }
        for child in children { child.teardownRecursively() }
        children.removeAll()
        scriptBindings.removeAll()
        parent = nil
        graph = nil
        dirtyFlags = []
        isTornDown = true
    }

    private static func dirtyFlag(for attribute: String) -> WasabiDirtyFlags {
        if ["x", "y", "w", "h", "relatx", "relaty", "relatw", "relath"].contains(attribute) { return .geometry }
        if ["text", "display", "value", "param"].contains(attribute) { return .content }
        if ["file", "image", "downimage", "hoverimage", "activeimage", "alpha", "visible", "color", "font"].contains(attribute) { return .appearance }
        return [.content, .appearance]
    }
}

final class WasabiObjectGraph {
    private(set) var roots: [WasabiObject] = []
    private(set) var mutationGeneration: UInt64 = 0
    private(set) var isTornDown = false

    private var nextRawID: UInt64 = 1
    private var objectsByID: [WasabiObjectID: WasabiObject] = [:]
    private var invalidated: [WasabiObjectID: WasabiDirtyFlags] = [:]

    var objectCount: Int { objectsByID.count }

    func makeObject(typeName: String, attributes: [String: String], source: WalSourceLocation) -> WasabiObject {
        precondition(!isTornDown, "Cannot add objects to a torn-down Wasabi graph")
        let id = WasabiObjectID(rawValue: nextRawID)
        nextRawID += 1
        let object = WasabiObject(stableID: id, typeName: typeName, attributes: attributes, source: source, graph: self)
        objectsByID[id] = object
        invalidated[id] = .all
        xmlIDIndex = nil
        return object
    }

    func appendRoot(_ object: WasabiObject) {
        guard !isTornDown, objectsByID[object.stableID] === object,
              object.parent == nil, !roots.contains(where: { $0 === object }) else { return }
        roots.append(object)
        recordInvalidation(object.stableID, flags: .structure)
    }

    fileprivate func detachRoot(_ object: WasabiObject) {
        roots.removeAll { $0 === object }
    }

    fileprivate func promoteToRoot(_ object: WasabiObject) {
        appendRoot(object)
    }

    func object(withID id: WasabiObjectID) -> WasabiObject? { objectsByID[id] }

    /// Every retained object. Unordered on purpose: the one caller that needs the whole graph is the
    /// bound-text poll behind `onTextChanged`, which runs on the playback tick and must not pay for a
    /// sort. Prefer a targeted lookup everywhere else.
    var allObjectsUnordered: Dictionary<WasabiObjectID, WasabiObject>.Values { objectsByID.values }

    /// Every object carrying an `id`, indexed by the folded id.
    ///
    /// Rebuilt lazily and dropped whenever the object set changes. Scanning and sorting the whole
    /// graph per call is what this replaces, and the caller that made it matter is the playback tick:
    /// `updateTime` looks `HiddenVolume` up on every time update, which on Big Bento Modern meant
    /// walking several thousand objects and sorting the result sixty times a minute — 4% of the app's
    /// entire wall clock in one lookup, measured with `sample`.
    private var xmlIDIndex: [String: [WasabiObject]]?

    func objects(xmlID: String) -> [WasabiObject] {
        let folded = Self.fold(xmlID)
        if xmlIDIndex == nil {
            var index: [String: [WasabiObject]] = [:]
            for object in objectsByID.values.sorted(by: { $0.stableID < $1.stableID }) {
                guard let id = object.xmlID.map(Self.fold), !id.isEmpty else { continue }
                index[id, default: []].append(object)
            }
            xmlIDIndex = index
        }
        return xmlIDIndex?[folded] ?? []
    }

    /// Drop the id index. Called wherever the object set or an object's `id` changes; rebuilding is
    /// one pass, and the alternative — keeping it in step incrementally — has to be right in five
    /// places instead of one.
    func invalidateXMLIDIndex() { xmlIDIndex = nil }

    func markAllDirty(_ flags: WasabiDirtyFlags = .all) {
        for object in objectsByID.values { object.markDirty(flags) }
    }

    func consumeInvalidations() -> [(WasabiObjectID, WasabiDirtyFlags)] {
        let result = invalidated.sorted { $0.key < $1.key }
        invalidated.removeAll()
        for (id, _) in result { _ = objectsByID[id]?.consumeDirtyFlags() }
        return result
    }

    fileprivate func recordInvalidation(_ id: WasabiObjectID, flags: WasabiDirtyFlags) {
        guard !isTornDown else { return }
        invalidated[id, default: []].formUnion(flags)
        mutationGeneration &+= 1
    }

    func snapshot() -> String {
        var lines: [String] = []
        func visit(_ object: WasabiObject, depth: Int) {
            let attrs = object.attributes.keys.sorted().map { "\($0)=\(object.attributes[$0]!)" }.joined(separator: ",")
            let scripts = object.scriptBindings.map(\.logicalPath).sorted().joined(separator: ",")
            let suffix = scripts.isEmpty ? "" : " scripts=[\(scripts)]"
            lines.append("\(String(repeating: "  ", count: depth))\(object.stableID) \(object.typeName.lowercased()) {\(attrs)}\(suffix) @\(object.source)")
            for child in object.children { visit(child, depth: depth + 1) }
        }
        for root in roots { visit(root, depth: 0) }
        return lines.joined(separator: "\n")
    }

    /// Remove one runtime-created tree completely. This is intentionally graph-owned so a failed
    /// trusted materialization cannot leave promoted roots or stale id lookups behind.
    func discardSubtree(_ root: WasabiObject) {
        guard !isTornDown, objectsByID[root.stableID] === root else { return }
        var ids: [WasabiObjectID] = []
        func collect(_ object: WasabiObject) {
            ids.append(object.stableID)
            for child in object.children { collect(child) }
        }
        collect(root)
        root.parent?.removeChild(root)
        detachRoot(root)
        root.teardownRecursively()
        for id in ids {
            objectsByID[id] = nil
            invalidated[id] = nil
        }
        xmlIDIndex = nil
        mutationGeneration &+= 1
    }

    func teardown() {
        guard !isTornDown else { return }
        // Include detached/orphaned objects held by callers, not only the current root forest.
        for object in objectsByID.values { object.teardownRecursively() }
        roots.removeAll()
        objectsByID.removeAll()
        invalidated.removeAll()
        isTornDown = true
        mutationGeneration &+= 1
    }

    private static func fold(_ value: String) -> String {
        value.folding(options: [.caseInsensitive], locale: Locale(identifier: "en_US_POSIX"))
    }
}
