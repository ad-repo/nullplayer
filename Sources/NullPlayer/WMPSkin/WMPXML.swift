import Foundation

struct WMPXMLLimits: Equatable {
    var maximumNestingDepth = WMPPhase0Limits.xmlDepth
    var maximumNodeCount = WMPPhase0Limits.xmlNodes

    static let production = WMPXMLLimits()
}

struct WMPXMLAttribute: Hashable {
    let name: String
    let value: String
}

final class WMPXMLNode {
    let name: String
    let attributes: [WMPXMLAttribute]
    let location: WMPSourceLocation
    private(set) var children: [WMPXMLNode] = []

    init(name: String, attributes: [WMPXMLAttribute], location: WMPSourceLocation) {
        self.name = name
        self.attributes = attributes
        self.location = location
    }

    func attribute(_ name: String) -> String? {
        attributes.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }?.value
    }

    fileprivate func append(_ node: WMPXMLNode) { children.append(node) }
}

struct WMPXMLDocument {
    let roots: [WMPXMLNode]
    let nodeCount: Int
}

final class WMPXMLParser: NSObject, XMLParserDelegate {
    private let limits: WMPXMLLimits
    private var path = ""
    private var roots: [WMPXMLNode] = []
    private var stack: [WMPXMLNode] = []
    private var count = 0
    private var failure: WMPFailure?

    init(limits: WMPXMLLimits = .production) {
        self.limits = limits
    }

    func parse(_ text: String, path: String) throws -> WMPXMLDocument {
        self.path = path
        roots = []
        stack = []
        count = 0
        failure = nil
        let parserText = Self.maskXMLDeclaration(in: text)
        guard let data = parserText.data(using: .utf8) else {
            throw WMPFailure(WMPDiagnostic(.invalidTextEncoding, "Unable to encode decoded XML text.",
                                           location: WMPSourceLocation(path: path)))
        }
        let parser = XMLParser(data: data)
        parser.delegate = self
        parser.shouldResolveExternalEntities = false
        let succeeded = parser.parse()
        if let failure { throw failure }
        guard succeeded else {
            let error = parser.parserError
            throw WMPFailure(WMPDiagnostic(.malformedXML,
                error?.localizedDescription ?? "Malformed XML.",
                location: WMPSourceLocation(path: path,
                    line: max(1, parser.lineNumber), column: max(1, parser.columnNumber))))
        }
        return WMPXMLDocument(roots: roots, nodeCount: count)
    }

    /// The text decoder has already honored the original byte encoding. XMLParser receives UTF-8
    /// bytes here, so leaving `encoding="UTF-16"` in the declaration would make it reinterpret those
    /// bytes incorrectly. Mask rather than delete it to keep source lines and columns stable.
    private static func maskXMLDeclaration(in text: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: #"^\s*<\?xml[^?]*\?>"#,
                                                   options: [.caseInsensitive]),
              let match = regex.firstMatch(in: text,
                  range: NSRange(text.startIndex..<text.endIndex, in: text)),
              let range = Range(match.range, in: text) else { return text }
        let replacement = text[range].map { $0 == "\n" || $0 == "\r" ? $0 : " " }
        var result = text
        result.replaceSubrange(range, with: replacement)
        return result
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String,
                namespaceURI: String?, qualifiedName qName: String?,
                attributes attributeDict: [String: String] = [:]) {
        guard failure == nil else { return }
        count += 1
        let location = WMPSourceLocation(path: path, line: parser.lineNumber, column: parser.columnNumber)
        guard count <= limits.maximumNodeCount else {
            failure = WMPFailure(WMPDiagnostic(.expandedNodeLimitExceeded,
                "XML contains more than \(limits.maximumNodeCount) nodes.", location: location))
            parser.abortParsing()
            return
        }
        guard stack.count + 1 <= limits.maximumNestingDepth else {
            failure = WMPFailure(WMPDiagnostic(.xmlDepthExceeded,
                "XML nesting exceeds \(limits.maximumNestingDepth) levels.", location: location))
            parser.abortParsing()
            return
        }
        let attributes = attributeDict.map { WMPXMLAttribute(name: $0.key, value: $0.value) }
            .sorted { WMPPath.less($0.name, $1.name) }
        let node = WMPXMLNode(name: qName ?? elementName, attributes: attributes, location: location)
        if let parent = stack.last { parent.append(node) } else { roots.append(node) }
        stack.append(node)
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String,
                namespaceURI: String?, qualifiedName qName: String?) {
        if !stack.isEmpty { stack.removeLast() }
    }

    func parser(_ parser: XMLParser, foundExternalEntityDeclarationWithName name: String,
                publicID: String?, systemID: String?) {
        failure = WMPFailure(WMPDiagnostic(.malformedXML,
            "External XML entities are not supported.",
            location: WMPSourceLocation(path: path, line: parser.lineNumber, column: parser.columnNumber)))
        parser.abortParsing()
    }
}
