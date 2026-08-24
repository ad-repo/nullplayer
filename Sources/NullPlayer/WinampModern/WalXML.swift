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

    /// Same tag, same attributes, same children in the same order — **ignoring where it was read
    /// from**. This is what tells a re-include of an identical definition (ordinary Winamp practice:
    /// LOBE includes `player-elements.xml` from both `player.xml` and `eq.xml`) apart from a skin
    /// actually redefining something. Depth-bounded like every other walk over untrusted markup.
    func isStructurallyEqual(to other: WalXMLNode, depth: Int = 0) -> Bool {
        guard depth < 64 else { return false }
        guard name == other.name, attributes == other.attributes,
              children.count == other.children.count else { return false }
        for (mine, theirs) in zip(children, other.children)
        where !mine.isStructurallyEqual(to: theirs, depth: depth + 1) {
            return false
        }
        return true
    }
    func replaceChildren(_ newChildren: [WalXMLNode]) { children = newChildren }
    func appendChild(_ child: WalXMLNode) { children.append(child) }
}

/// What a single file's parse produced: the tree, plus anything the parser tolerated rather than
/// rejected. Only `parse` fills `diagnostics` in; the loader folds them into the document's own list.
struct WalParsedXML {
    let roots: [WalXMLNode]
    let diagnostics: [WalDiagnostic]
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

    func parse(_ text: String, path: String) throws -> WalParsedXML {
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

        // A file that runs out before it closes everything it opened is the skin's bug, not ours,
        // and Winamp loads those. Nothing is missing from the tree: a node is attached to its parent
        // (or to `roots`) when it *opens*, so the unclosed tag already has all of its children and
        // every sibling after it. `maximumDepth` still bounds how much can be left open, so warning
        // here changes nothing about the sandbox. `Shield_Amp`'s `opensource_notifier/notifier.xml`
        // is the measured case: two `<container>`s opened, one closed, file ends on a `<script/>`.
        var diagnostics: [WalDiagnostic] = []
        if let open = stack.last {
            let extra = stack.count > 1 ? " (\(stack.count) tags left open)" : ""
            diagnostics.append(WalDiagnostic(
                .malformedXML,
                "Unclosed <\(open.name)> tag at end of file\(extra); its children were kept.",
                severity: .warning,
                location: open.location))
        }
        return WalParsedXML(roots: roots, diagnostics: diagnostics)
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
    private var diagnostics: [WalDiagnostic] = []

    init(vfs: WalVirtualFileSystem, limits: WalXMLLimits = .production) {
        self.vfs = vfs
        self.limits = limits
    }

    func load(entryPath: String) throws -> WalExpandedXMLDocument {
        visited = []
        visitedSet = []
        expandedNodeCount = 0
        diagnostics = []
        let canonical = try vfs.resolve(entryPath, relativeTo: "/", mustExist: true).logicalPath
        let roots = try loadFile(canonical, includeStack: [], depth: 0)
        return WalExpandedXMLDocument(roots: roots, visitedPaths: visited, diagnostics: diagnostics)
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
        diagnostics.append(contentsOf: parsed.diagnostics)
        return try expand(parsed.roots, sourcePath: path, includeStack: includeStack + [folded], depth: depth)
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
                do {
                    let targets = try vfs.expand(file, relativeTo: sourcePath, location: node.location)
                    for target in targets {
                        result.append(contentsOf: try loadFile(target.logicalPath, includeStack: includeStack, depth: depth + 1))
                    }
                } catch let failure as WalFailure
                    where failure.diagnostics.allSatisfy({ $0.code == .resourceMissing })
                        && isInsideSkin(file, relativeTo: sourcePath) {
                    // Real skins ship `<include>`s naming files the archive does not contain —
                    // `Itemskin` asks for `xml/eq.xml`, `Overdrive_2` for `xml/pledit-elements.xml`.
                    // Winamp warns and carries on; failing the include failed the *whole skin*, so
                    // neither loaded at all. This is the same tolerance the initializer already
                    // applies one layer down to a missing bitmap, cursor or TTF. Security failures
                    // (traversal, escape, unresolved variable) and every other diagnostic code —
                    // malformed XML in a file that *does* exist, cycles, depth — still throw.
                    diagnostics.append(WalDiagnostic(
                        .resourceMissing,
                        "<\(node.name) file=\"\(file)\"> was not found; the include was skipped.",
                        severity: .warning,
                        location: node.location))
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

    /// A missing include is only tolerated when it names a file *inside the skin*. One that climbs
    /// into another mount — `@COLORTHEMESPATH@\..\..\Plugins\classicPro\engine\load.xml` — is a
    /// ClassicPro skin whose engine is not installed, and that stays a hard, nameable failure rather
    /// than a skin that loads and draws almost nothing.
    private func isInsideSkin(_ rawPath: String, relativeTo sourcePath: String) -> Bool {
        guard let skinRoot = vfs.skinRoot,
              let canonical = try? vfs.resolve(rawPath, relativeTo: sourcePath, mustExist: false)
        else { return false }
        return Self.fold(canonical.logicalPath).hasPrefix(Self.fold(skinRoot + "/"))
    }

    private static func fold(_ value: String) -> String {
        value.folding(options: [.caseInsensitive], locale: Locale(identifier: "en_US_POSIX"))
    }
}
