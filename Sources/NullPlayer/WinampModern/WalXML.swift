import Foundation

struct WalXMLLimits: Equatable {
    var maximumNestingDepth = 256
    var maximumIncludeDepth = 32
    var maximumExpandedNodeCount = 100_000

    static let production = WalXMLLimits()
}

final class WalXMLNode {
    let name: String
    private(set) var attributes: [String: String]
    let location: WalSourceLocation
    private(set) var children: [WalXMLNode]

    init(name: String, attributes: [String: String], location: WalSourceLocation, children: [WalXMLNode] = []) {
        self.name = name
        self.attributes = attributes
        self.location = location
        self.children = children
    }

    func attribute(_ name: String) -> String? { attributes[name.lowercased()] }
    func replaceChildren(_ newChildren: [WalXMLNode]) { children = newChildren }
    func appendChild(_ child: WalXMLNode) { children.append(child) }
}

struct WalExpandedXMLDocument {
    let roots: [WalXMLNode]
    let visitedPaths: [String]
    let diagnostics: [WalDiagnostic]
}

/// Wasabi XML is often a fragment rather than one strict XML document. This parser accepts multiple
/// roots and raw ampersands while still enforcing balanced tags and the production nesting cap.
struct WalLenientXMLParser {
    let maximumDepth: Int
    let maximumNodeCount: Int

    init(maximumDepth: Int = WalXMLLimits.production.maximumNestingDepth,
         maximumNodeCount: Int = WalXMLLimits.production.maximumExpandedNodeCount) {
        self.maximumDepth = maximumDepth
        self.maximumNodeCount = maximumNodeCount
    }

    func parse(_ text: String, path: String) throws -> [WalXMLNode] {
        let chars = Array(text)
        var roots: [WalXMLNode] = []
        var stack: [WalXMLNode] = []
        var index = 0
        var line = 1
        var column = 1
        var nodeCount = 0

        func advanced(_ range: Range<Int>) -> (Int, Int) {
            var nextLine = line
            var nextColumn = column
            for i in range {
                if chars[i] == "\n" { nextLine += 1; nextColumn = 1 }
                else { nextColumn += 1 }
            }
            return (nextLine, nextColumn)
        }

        func match(_ start: Int, _ value: String) -> Bool {
            let needle = Array(value)
            guard start + needle.count <= chars.count else { return false }
            return needle.indices.allSatisfy { chars[start + $0] == needle[$0] }
        }

        func endOf(_ value: String, after start: Int) -> Int? {
            var cursor = start
            while cursor < chars.count {
                if match(cursor, value) { return cursor + value.count }
                cursor += 1
            }
            return nil
        }

        while index < chars.count {
            guard chars[index] == "<" else {
                if chars[index] == "\n" { line += 1; column = 1 } else { column += 1 }
                index += 1
                continue
            }

            let tagLine = line
            let tagColumn = column
            if match(index, "<!--") {
                guard let end = endOf("-->", after: index + 4) else {
                    throw WalFailure(WalDiagnostic(.malformedXML, "Unterminated XML comment.", location: WalSourceLocation(path: path, line: tagLine, column: tagColumn)))
                }
                (line, column) = advanced(index..<end)
                index = end
                continue
            }
            if match(index, "<?") || match(index, "<!") {
                guard let end = endOf(">", after: index + 2) else {
                    throw WalFailure(WalDiagnostic(.malformedXML, "Unterminated XML declaration.", location: WalSourceLocation(path: path, line: tagLine, column: tagColumn)))
                }
                (line, column) = advanced(index..<end)
                index = end
                continue
            }

            var cursor = index + 1
            let isClosing = cursor < chars.count && chars[cursor] == "/"
            if isClosing { cursor += 1 }
            while cursor < chars.count, chars[cursor].isWhitespace { cursor += 1 }
            let nameStart = cursor
            while cursor < chars.count,
                  !chars[cursor].isWhitespace, chars[cursor] != ">", chars[cursor] != "/" {
                cursor += 1
            }
            let name = String(chars[nameStart..<cursor])
            guard !name.isEmpty else {
                throw WalFailure(WalDiagnostic(.malformedXML, "Tag has no name.", location: WalSourceLocation(path: path, line: tagLine, column: tagColumn)))
            }

            if isClosing {
                guard let end = endOf(">", after: cursor), let open = stack.last,
                      open.name.caseInsensitiveCompare(name) == .orderedSame else {
                    throw WalFailure(WalDiagnostic(.malformedXML, "Unexpected closing tag </\(name)>.", location: WalSourceLocation(path: path, line: tagLine, column: tagColumn)))
                }
                stack.removeLast()
                (line, column) = advanced(index..<end)
                index = end
                continue
            }

            var attributes: [String: String] = [:]
            var selfClosing = false
            var closed = false
            while cursor < chars.count {
                let iterationStart = cursor
                while cursor < chars.count, chars[cursor].isWhitespace { cursor += 1 }
                if cursor < chars.count, chars[cursor] == ">" {
                    cursor += 1; closed = true; break
                }
                if cursor + 1 < chars.count, chars[cursor] == "/", chars[cursor + 1] == ">" {
                    cursor += 2; selfClosing = true; closed = true; break
                }
                let attrStart = cursor
                while cursor < chars.count,
                      !chars[cursor].isWhitespace, chars[cursor] != "=", chars[cursor] != ">", chars[cursor] != "/" {
                    cursor += 1
                }
                let attrName = String(chars[attrStart..<cursor]).lowercased()
                while cursor < chars.count, chars[cursor].isWhitespace { cursor += 1 }
                var attrValue = ""
                if cursor < chars.count, chars[cursor] == "=" {
                    cursor += 1
                    while cursor < chars.count, chars[cursor].isWhitespace { cursor += 1 }
                    if cursor < chars.count, chars[cursor] == "\"" || chars[cursor] == "'" {
                        let quote = chars[cursor]
                        cursor += 1
                        let valueStart = cursor
                        while cursor < chars.count, chars[cursor] != quote { cursor += 1 }
                        guard cursor < chars.count else {
                            throw WalFailure(WalDiagnostic(.malformedXML, "Unterminated value for attribute '\(attrName)'.", location: WalSourceLocation(path: path, line: tagLine, column: tagColumn)))
                        }
                        attrValue = Self.unescape(String(chars[valueStart..<cursor]))
                        cursor += 1
                    } else {
                        let valueStart = cursor
                        while cursor < chars.count, !chars[cursor].isWhitespace, chars[cursor] != ">" { cursor += 1 }
                        attrValue = Self.unescape(String(chars[valueStart..<cursor]))
                    }
                }
                if !attrName.isEmpty { attributes[attrName] = attrValue }
                // A stray '/' that does not close the tag matches no branch above and would
                // otherwise leave the cursor parked forever. Skip it so the scan always advances.
                if cursor == iterationStart { cursor += 1 }
            }
            guard closed else {
                throw WalFailure(WalDiagnostic(.malformedXML, "Unterminated <\(name)> tag.", location: WalSourceLocation(path: path, line: tagLine, column: tagColumn)))
            }

            let node = WalXMLNode(name: name, attributes: attributes,
                                  location: WalSourceLocation(path: path, line: tagLine, column: tagColumn))
            nodeCount += 1
            guard nodeCount <= maximumNodeCount else {
                throw WalFailure(WalDiagnostic(.expandedNodeLimitExceeded, "XML contains more than \(maximumNodeCount) nodes before include expansion.", location: node.location))
            }
            if let parent = stack.last {
                parent.appendChild(node)
            } else {
                roots.append(node)
            }
            if !selfClosing {
                stack.append(node)
                guard stack.count <= maximumDepth else {
                    throw WalFailure(WalDiagnostic(.xmlDepthExceeded, "XML nesting exceeds \(maximumDepth) levels.", location: node.location))
                }
            }
            (line, column) = advanced(index..<cursor)
            index = cursor
        }

        guard stack.isEmpty else {
            let open = stack.last!
            throw WalFailure(WalDiagnostic(.malformedXML, "Unclosed <\(open.name)> tag.", location: open.location))
        }
        return roots
    }

    private static func unescape(_ value: String) -> String {
        value.replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&apos;", with: "'")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&amp;", with: "&")
    }
}

final class WalXMLDocumentLoader {
    let vfs: WalVirtualFileSystem
    let limits: WalXMLLimits

    private var visited: [String] = []
    private var visitedSet: Set<String> = []
    private var expandedNodeCount = 0

    init(vfs: WalVirtualFileSystem, limits: WalXMLLimits = .production) {
        self.vfs = vfs
        self.limits = limits
    }

    func load(entryPath: String) throws -> WalExpandedXMLDocument {
        visited = []
        visitedSet = []
        expandedNodeCount = 0
        let canonical = try vfs.resolve(entryPath, relativeTo: "/", mustExist: true).logicalPath
        let roots = try loadFile(canonical, includeStack: [], depth: 0)
        return WalExpandedXMLDocument(roots: roots, visitedPaths: visited, diagnostics: [])
    }

    private func loadFile(_ path: String, includeStack: [String], depth: Int) throws -> [WalXMLNode] {
        guard depth <= limits.maximumIncludeDepth else {
            throw WalFailure(WalDiagnostic(.includeDepthExceeded, "Include expansion exceeds \(limits.maximumIncludeDepth) levels.", location: WalSourceLocation(path: path)))
        }
        let folded = Self.fold(path)
        if let cycleIndex = includeStack.firstIndex(of: folded) {
            let cycle = (Array(includeStack[cycleIndex...]) + [folded]).joined(separator: " -> ")
            throw WalFailure(WalDiagnostic(.includeCycle, "Include cycle detected: \(cycle).", location: WalSourceLocation(path: path)))
        }
        if visitedSet.insert(folded).inserted { visited.append(path) }

        let data = try vfs.data(at: path, location: WalSourceLocation(path: path))
        let text: String
        if let utf8 = String(data: data, encoding: .utf8) { text = utf8 }
        else if let latin1 = String(data: data, encoding: .isoLatin1) { text = latin1 }
        else {
            throw WalFailure(WalDiagnostic(.malformedXML, "XML resource is neither UTF-8 nor ISO-8859-1 text.", location: WalSourceLocation(path: path)))
        }
        let parsed = try WalLenientXMLParser(maximumDepth: limits.maximumNestingDepth,
                                             maximumNodeCount: limits.maximumExpandedNodeCount).parse(text, path: path)
        return try expand(parsed, sourcePath: path, includeStack: includeStack + [folded], depth: depth)
    }

    private func expand(
        _ nodes: [WalXMLNode],
        sourcePath: String,
        includeStack: [String],
        depth: Int
    ) throws -> [WalXMLNode] {
        var result: [WalXMLNode] = []
        for node in nodes {
            let lower = node.name.lowercased()
            if lower == "include" || lower == "elementinclude" {
                guard let file = node.attribute("file"), !file.isEmpty else {
                    throw WalFailure(WalDiagnostic(.malformedXML, "<\(node.name)> requires a non-empty file attribute.", location: node.location))
                }
                let targets = try vfs.expand(file, relativeTo: sourcePath, location: node.location)
                for target in targets {
                    result.append(contentsOf: try loadFile(target.logicalPath, includeStack: includeStack, depth: depth + 1))
                }
                continue
            }

            expandedNodeCount += 1
            guard expandedNodeCount <= limits.maximumExpandedNodeCount else {
                throw WalFailure(WalDiagnostic(.expandedNodeLimitExceeded, "Expanded XML exceeds \(limits.maximumExpandedNodeCount) nodes.", location: node.location))
            }
            node.replaceChildren(try expand(node.children, sourcePath: sourcePath,
                                            includeStack: includeStack, depth: depth))
            result.append(node)
        }
        return result
    }

    private static func fold(_ value: String) -> String {
        value.folding(options: [.caseInsensitive], locale: Locale(identifier: "en_US_POSIX"))
    }
}
