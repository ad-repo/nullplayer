import Foundation

/// One element of an AIMP skin document: a form, `Schema.xml`, an image set. AIMP stores these
/// three ways, all decoded here to the same tree:
/// - `SXML` (`.acs5`): a varint-coded node stream with a tag/attribute name table at the end;
/// - `BXML` (`.acs4`): length-prefixed ASCII names and UTF-16LE values;
/// - text XML (`.acs4proj`).
/// Layouts in `reference/format.md` § *Documents*.
struct AIMPNode: Sendable {
    let tag: String
    let attributes: [String: String]
    let children: [AIMPNode]
    let text: String?
    /// The `property` children by `name`, first one winning: a property's nested properties
    /// (`Fonts`' `Normal`, a resource's `ID`).
    let named: [String: AIMPNode]
    /// The `properties/property` children by `name`: what a control, item or provider is set to.
    /// Both are worked out once as the document is read; the renderer reads them every frame.
    let properties: [String: AIMPNode]

    init(tag: String, attributes: [String: String], children: [AIMPNode], text: String?) {
        self.tag = tag
        self.attributes = attributes
        self.children = children
        self.text = text
        named = Dictionary(children.lazy.filter { $0.tag == "property" }.map { ($0["name"] ?? "", $0) },
                           uniquingKeysWith: { first, _ in first })
        properties = children.first { $0.tag == "properties" }?.named ?? [:]
    }

    subscript(attribute: String) -> String? { attributes[attribute] }

    func children(_ tag: String) -> [AIMPNode] { children.filter { $0.tag == tag } }

    func child(_ tag: String) -> AIMPNode? { children.first { $0.tag == tag } }

    /// Every descendant, depth first, self included.
    func descendants() -> [AIMPNode] { [self] + children.flatMap { $0.descendants() } }

    static func parse(_ data: Data, name: String) throws -> AIMPNode {
        do {
            switch data.prefix(4) {
            case Data("SXML".utf8):
                var reader = SXMLReader(data)
                return try reader.document()
            case Data("BXML".utf8):
                var reader = BXMLReader(data)
                return try reader.document()
            default: return try TextXMLReader.parse(data)
            }
        } catch let finding as AIMPSkinFinding {
            throw AIMPSkinFinding(finding.code, "\(name): \(finding.message)")
        }
    }
}

private func malformed(_ message: String) -> AIMPSkinFinding { AIMPSkinFinding(.xmlMalformed, message) }

/// Shared bounds: depth and total node count, per document.
private struct NodeBudget {
    var nodes = 0

    mutating func enter(depth: Int) throws {
        nodes += 1
        guard depth <= AIMPSkinPolicy.xmlDepth, nodes <= AIMPSkinPolicy.xmlNodes else {
            throw malformed("Nested deeper than \(AIMPSkinPolicy.xmlDepth) or more than \(AIMPSkinPolicy.xmlNodes) nodes.")
        }
    }
}

/// `SXML`: u32 name-table offset (from byte 12), u32, u8 version, root node. A node is a varint
/// name index, flags (1 attributes, 2 children, 4 text), then text, attributes, children.
private struct SXMLReader {
    var bytes: AIMPSkinBytes
    var names: [String] = []
    var budget = NodeBudget()

    init(_ data: Data) { bytes = AIMPSkinBytes(data, code: .xmlMalformed) }

    mutating func document() throws -> AIMPNode {
        guard bytes.end >= 13 else { throw malformed("Truncated header.") }
        bytes.offset = 12 + (try bytes.u32(at: 4))
        for _ in 0..<(try bytes.varint()) {
            names.append(try bytes.ascii(try bytes.varint()))
        }
        bytes.offset = 13
        return try node(depth: 0)
    }

    mutating func name() throws -> String {
        let index = try bytes.varint()
        guard index < names.count else { throw malformed("Name index \(index) of \(names.count).") }
        return names[index]
    }

    mutating func node(depth: Int) throws -> AIMPNode {
        try budget.enter(depth: depth)
        let tag = try name()
        let flags = try bytes.u8()
        guard flags & ~7 == 0 else { throw malformed("Unknown flags \(flags) at \(bytes.offset - 1).") }
        let text = flags & 4 != 0 ? try bytes.utf16(units: try bytes.varint()) : nil
        var attributes: [String: String] = [:]
        if flags & 1 != 0 {
            for _ in 0..<(try bytes.varint()) {
                let key = try name()
                attributes[key] = try bytes.utf16(units: try bytes.varint())
            }
        }
        var children: [AIMPNode] = []
        if flags & 2 != 0 {
            for _ in 0..<(try bytes.varint()) { children.append(try node(depth: depth + 1)) }
        }
        return AIMPNode(tag: tag, attributes: attributes, children: children, text: text)
    }
}

/// `BXML`: u32 version, root node. A node is a u16 ASCII tag, flags (1 attributes, 2 children,
/// 4 text), then attributes `{ u16 ASCII name, u16 UTF-16LE value }`, children, u32 UTF-16LE text.
private struct BXMLReader {
    var bytes: AIMPSkinBytes
    var budget = NodeBudget()

    init(_ data: Data) {
        bytes = AIMPSkinBytes(data, code: .xmlMalformed)
        bytes.offset = 8
    }

    mutating func document() throws -> AIMPNode { try node(depth: 0) }

    mutating func node(depth: Int) throws -> AIMPNode {
        try budget.enter(depth: depth)
        let tag = try bytes.ascii(try bytes.u16())
        let flags = try bytes.u8()
        guard flags & ~7 == 0 else { throw malformed("Unknown flags \(flags) at \(bytes.offset - 1).") }
        var attributes: [String: String] = [:]
        if flags & 1 != 0 {
            for _ in 0..<(try bytes.u32()) {
                let key = try bytes.ascii(try bytes.u16())
                attributes[key] = try bytes.utf16(units: try bytes.u16())
            }
        }
        var children: [AIMPNode] = []
        if flags & 2 != 0 {
            for _ in 0..<(try bytes.u32()) { children.append(try node(depth: depth + 1)) }
        }
        let text = flags & 4 != 0 ? try bytes.utf16(units: try bytes.u32()) : nil
        return AIMPNode(tag: tag, attributes: attributes, children: children, text: text)
    }
}

/// Text XML through Foundation's parser, into the same tree.
private final class TextXMLReader: NSObject, XMLParserDelegate {
    private final class Building {
        let tag: String
        let attributes: [String: String]
        var children: [AIMPNode] = []
        var text = ""

        init(tag: String, attributes: [String: String]) {
            self.tag = tag
            self.attributes = attributes
        }
    }

    private var stack: [Building] = []
    private var root: AIMPNode?
    private var budget = NodeBudget()
    private var failure: AIMPSkinFinding?

    static func parse(_ data: Data) throws -> AIMPNode {
        let reader = TextXMLReader()
        let parser = XMLParser(data: data)
        parser.delegate = reader
        parser.shouldResolveExternalEntities = false
        let ok = parser.parse()
        if let failure = reader.failure { throw failure }
        guard ok, let root = reader.root else {
            throw malformed(parser.parserError?.localizedDescription ?? "Not XML.")
        }
        return root
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
                qualifiedName: String?, attributes: [String: String]) {
        do {
            try budget.enter(depth: stack.count)
        } catch {
            failure = error as? AIMPSkinFinding
            parser.abortParsing()
            return
        }
        stack.append(Building(tag: elementName, attributes: attributes))
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        stack.last?.text += string
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?,
                qualifiedName: String?) {
        guard let done = stack.popLast() else { return }
        let text = done.text.trimmingCharacters(in: .whitespacesAndNewlines)
        let node = AIMPNode(tag: done.tag, attributes: done.attributes, children: done.children,
                            text: text.isEmpty ? nil : text)
        if let parent = stack.last { parent.children.append(node) } else { root = node }
    }
}

extension AIMPNode {
    // Building nodes: the forms the loader makes itself (`AIMPSkinLegacy`, `AIMPSkinDockSites`).

    static func element(_ tag: String, _ attributes: [String: String] = [:], _ children: [AIMPNode] = []) -> AIMPNode {
        AIMPNode(tag: tag, attributes: attributes, children: children, text: nil)
    }

    /// A `properties` node holding `list`.
    static func propertyList(_ list: [AIMPNode]) -> AIMPNode { element("properties", [:], list) }

    static func property(_ name: String, _ value: String) -> AIMPNode { element("property", ["name": name, "value": value]) }

    /// A `Bindings` property holding `links`.
    static func bindings(_ links: AIMPNode...) -> AIMPNode { element("property", ["name": "Bindings"], links) }

    /// A `Bindings` link: `target` reads `source`'s `pin`.
    static func binding(_ source: String, _ pin: String, _ target: String) -> AIMPNode {
        element("link", ["Source": source, "SourcePin": pin, "TargetPin": target])
    }
}

extension AIMPNode {
    /// This control or item with properties a script set, by dotted path
    /// (`Resources.ItemBackgroundColors.Playing`); a colour held in a nested `Value` is set there.
    func overriding(_ sets: [String: String]) -> AIMPNode {
        guard !sets.isEmpty else { return self }
        var list = children.first { $0.tag == "properties" } ?? .element("properties")
        for (path, value) in sets.sorted(by: { $0.key < $1.key }) {
            list = list.setting(path.split(separator: ".").map(String.init)[...], to: value)
        }
        return AIMPNode(tag: tag, attributes: attributes, children: [list] + children.filter { $0.tag != "properties" }, text: text)
    }

    private func setting(_ path: ArraySlice<String>, to value: String) -> AIMPNode {
        guard let first = path.first else {
            if named["Value"] != nil { return setting(["Value"], to: value) }
            var attributes = self.attributes
            attributes["value"] = value
            return AIMPNode(tag: tag, attributes: attributes, children: children, text: text)
        }
        var children = self.children
        if let index = children.firstIndex(where: { $0.tag == "property" && $0["name"] == first }) {
            children[index] = children[index].setting(path.dropFirst(), to: value)
        } else {
            children.append(AIMPNode.element("property", ["name": first]).setting(path.dropFirst(), to: value))
        }
        return AIMPNode(tag: tag, attributes: attributes, children: children, text: text)
    }
}
