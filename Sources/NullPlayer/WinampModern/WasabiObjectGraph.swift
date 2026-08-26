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
        markDirty(Self.dirtyFlag(for: key), reason: key)
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

    func markDirty(_ flags: WasabiDirtyFlags, reason: String? = nil) {
        guard !isTornDown, !flags.isEmpty else { return }
        dirtyFlags.formUnion(flags)
        if WasabiMutationTrace.isEnabled {
            WasabiMutationTrace.record(object: self, reason: reason ?? Self.reasonName(for: flags))
        }
        graph?.recordInvalidation(stableID, flags: flags,
                                  sceneAffecting: reason.map { !WasabiObjectGraph.isSceneNeutral(attribute: $0) } ?? true)
    }

    private static func reasonName(for flags: WasabiDirtyFlags) -> String {
        var names: [String] = []
        if flags.contains(.geometry) { names.append("geometry") }
        if flags.contains(.appearance) { names.append("appearance") }
        if flags.contains(.content) { names.append("content") }
        if flags.contains(.structure) { names.append("structure") }
        if flags.contains(.script) { names.append("script") }
        return "<\(names.joined(separator: "+"))>"
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

/// Names whoever moves `mutationGeneration`. `WINAMP_MODERN_MUTATION_TRACE=1`.
///
/// The counter keys the renderer's layout and scene caches, so a skin that writes one attribute per
/// frame re-solves the entire object tree per frame — a cost that lands in `layout()` and `draw`,
/// nowhere near the write that caused it, and that no other probe can attribute (B52). Aggregated
/// rather than logged per write: at sixty writes a second a line each is unreadable, and the finding
/// is always *which* attribute on *which* object, not the order they arrived in.
enum WasabiMutationTrace {
    static let isEnabled = ProcessInfo.processInfo.environment["WINAMP_MODERN_MUTATION_TRACE"] == "1"

    /// Seconds between reports. `WINAMP_MODERN_MUTATION_TRACE_INTERVAL=<seconds>`.
    private static let interval: Double = {
        let raw = ProcessInfo.processInfo.environment["WINAMP_MODERN_MUTATION_TRACE_INTERVAL"]
        return max(0.5, Double(raw ?? "") ?? 2)
    }()

    /// How many writers a report names. `WINAMP_MODERN_MUTATION_TRACE_TOP=<n>`.
    private static let top: Int = {
        Int(ProcessInfo.processInfo.environment["WINAMP_MODERN_MUTATION_TRACE_TOP"] ?? "") ?? 12
    }()

    private static var counts: [String: Int] = [:]
    private static var total = 0
    private static var windowStart = Date.timeIntervalSinceReferenceDate

    /// Full re-solves of the object tree in this window — the cost the writes above are being blamed
    /// for. A write is only expensive because a cache did not survive it, so the two numbers belong
    /// on the same line: `writes=145 resolves=3` is a healthy skin, `resolves=60` is the defect.
    private static var resolves: [String: Int] = [:]

    /// Called from the renderer wherever a memoized walk is recomputed.
    static func recordResolve(_ kind: @autoclosure () -> String) {
        guard isEnabled else { return }
        resolves[kind(), default: 0] += 1
    }

    /// Main-thread only, like every graph mutation.
    static func record(object: WasabiObject, reason: String) {
        let id = object.xmlID.map { "#\($0)" } ?? ""
        let key = "\(reason)\t\(object.typeName.lowercased())\(id)\t\(object.source)"
        counts[key, default: 0] += 1
        total += 1
        let now = Date.timeIntervalSinceReferenceDate
        guard now - windowStart >= interval else { return }
        flush(elapsed: now - windowStart)
        counts.removeAll(keepingCapacity: true)
        resolves.removeAll(keepingCapacity: true)
        total = 0
        windowStart = now
    }

    private static func flush(elapsed: Double) {
        guard total > 0 else { return }
        let rate = Int((Double(total) / elapsed).rounded())
        let resolved = resolves.sorted { $0.key < $1.key }
            .map { "\($0.key)=\($0.value)" }.joined(separator: " ")
        print(String(format: "MUTATION-TRACE %.1fs writes=%d rate=%d/s writers=%d %@",
                     elapsed, total, rate, counts.count,
                     resolved.isEmpty ? "resolves=0" : "resolves: " + resolved))
        for (key, count) in counts.sorted(by: { $0.value > $1.value }).prefix(top) {
            let parts = key.split(separator: "\t", omittingEmptySubsequences: false)
            let reason = parts.count > 0 ? String(parts[0]) : "?"
            let object = parts.count > 1 ? String(parts[1]) : "?"
            let source = parts.count > 2 ? String(parts[2]) : "?"
            let column = { (value: String, width: Int) in
                value.padding(toLength: max(width, value.count), withPad: " ", startingAt: 0)
            }
            print("MUTATION-TRACE   \(column(String(count), 5)) \(column(reason, 18)) "
                  + "\(column(object, 34)) \(source)")
        }
    }
}

final class WasabiObjectGraph {
    private(set) var roots: [WasabiObject] = []
    private(set) var mutationGeneration: UInt64 = 0

    /// Bumped by every mutation **except** the ones the scene walk does not read.
    ///
    /// Today that is `alpha` alone, and it earns its own counter because it is the attribute skins
    /// animate: a target-alpha fade writes it up to sixty times a second, and keying the renderer's
    /// scene and layout caches on `mutationGeneration` meant every one of those writes re-solved the
    /// whole object tree — geometry, clips, bitmaps — to change one multiplier (B52). `append`
    /// consumes alpha only as `inheritedAlpha`, which `sceneNodes()` re-resolves over the cached
    /// nodes on the way out, so a fade now costs a repaint and nothing else.
    ///
    /// Anything else that stops moving this counter has to be provably invisible to `append` in the
    /// same way. `visible` is not (it decides membership), `image`/`text` are not (they can size an
    /// object), and an attribute the flag map does not recognise is not.
    private(set) var sceneGeneration: UInt64 = 0

    private(set) var isTornDown = false

    /// Attributes `append` never reads except through the value `sceneNodes()` re-resolves itself.
    static func isSceneNeutral(attribute: String) -> Bool { attribute == "alpha" }

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

    fileprivate func recordInvalidation(_ id: WasabiObjectID, flags: WasabiDirtyFlags,
                                        sceneAffecting: Bool = true) {
        guard !isTornDown else { return }
        invalidated[id, default: []].formUnion(flags)
        mutationGeneration &+= 1
        if sceneAffecting { sceneGeneration &+= 1 }
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
        sceneGeneration &+= 1
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
        sceneGeneration &+= 1
    }

    private static func fold(_ value: String) -> String {
        value.folding(options: [.caseInsensitive], locale: Locale(identifier: "en_US_POSIX"))
    }
}
