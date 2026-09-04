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
    /// The attribute names in the order the document wrote them, lowercased, without duplicates.
    ///
    /// `attributes` is a dictionary and therefore unordered, which is fine for every lookup — but a
    /// skin's `parser_onCallback` receives its attributes as two parallel **lists**, and Winamp fills
    /// those in document order. ClassicPro's `read-classicpro.m` depends on it outright: it reads
    /// each `<Style>` with `if (name == "id") busyWith = value; else if (busyWith == …) apply`, so
    /// every attribute written before `id` is skipped. Handing it an alphabetised list put `id` at
    /// position 4 of 10 and silently dropped `display`, `fontsize`, `forcefixed` and `h` from every
    /// style in the file — which is why cPro2's clock lost `forcefixed="1"` and `fontsize="26"`, was
    /// measured with the wrong metrics, and had its elapsed and total times laid out on top of each
    /// other in the corner. The script even comments that it relies on the id arriving first.
    ///
    /// Empty for a node built in code rather than parsed; callers fall back to sorted order.
    private(set) var attributeOrder: [String]
    let location: WalSourceLocation
    private(set) var children: [WalXMLNode]

    init(name: String, attributes: [String: String], location: WalSourceLocation,
         children: [WalXMLNode] = [], attributeOrder: [String] = []) {
        self.name = name
        self.attributes = attributes
        self.attributeOrder = attributeOrder
        self.location = location
        self.children = children
    }

    /// The node's attributes as the document wrote them: document order where it is known, and
    /// alphabetical as a stable fallback for a node assembled in code.
    var orderedAttributes: [(key: String, value: String)] {
        guard !attributeOrder.isEmpty else {
            return attributes.sorted { $0.key < $1.key }.map { ($0.key, $0.value) }
        }
        var seen = Set<String>()
        var ordered = attributeOrder.compactMap { name -> (key: String, value: String)? in
            guard seen.insert(name).inserted, let value = attributes[name] else { return nil }
            return (name, value)
        }
        // Anything added after parsing keeps a deterministic place at the end rather than vanishing.
        ordered += attributes.keys.filter { !seen.contains($0) }.sorted().map { ($0, attributes[$0]!) }
        return ordered
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
    func resolveAttributeValues(with resolver: (String) -> String) {
        for (name, value) in attributes {
            attributes[name] = resolver(value)
        }
    }
    func replaceChildren(_ newChildren: [WalXMLNode]) { children = newChildren }
    func setAttributes(_ values: [String: String]) {
        for (name, value) in values { attributes[name] = value }
    }
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

/// Winamp expands a small set of host-capability macros in markup values after includes have been
/// resolved. Keep these separate from VFS path variables: values such as `default_visible` and a
/// script's `param` are not paths and never pass through `WalVirtualFileSystem`.
enum WasabiXMLMacroResolver {
    static func resolve(_ raw: String) -> String {
        guard raw.contains("@") else { return raw }
        return raw.replacingOccurrences(of: "@HAVE_LIBRARY@", with: "1",
                                        options: [.caseInsensitive])
    }

    static func resolve(_ raw: String?) -> String? {
        raw.map(resolve)
    }

    static func resolve(in document: WalExpandedXMLDocument) {
        func walk(_ nodes: [WalXMLNode]) {
            for node in nodes {
                node.resolveAttributeValues(with: resolve)
                walk(node.children)
            }
        }
        walk(document.roots)
    }
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
            var attributeOrder: [String] = []
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
                if !attrName.isEmpty {
                    if attributes.updateValue(attrValue, forKey: attrName) == nil {
                        attributeOrder.append(attrName)
                    }
                }
                // A stray '/' that does not close the tag matches no branch above and would
                // otherwise leave the cursor parked forever. Skip it so the scan always advances.
                if cursor == iterationStart { cursor += 1 }
            }
            guard closed else {
                throw WalFailure(WalDiagnostic(.malformedXML, "Unterminated <\(name)> tag.", location: WalSourceLocation(path: path, line: tagLine, column: tagColumn)))
            }

            let node = WalXMLNode(name: name, attributes: attributes,
                                  location: WalSourceLocation(path: path, line: tagLine, column: tagColumn),
                                  attributeOrder: attributeOrder)
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
        guard let text = Self.decodeText(data) else {
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
                let targets: [WalResolvedResource]
                do {
                    // Only *this* node's own resolution is covered by the tolerance below. A failure
                    // raised while loading a file that was found — a missing include nested inside
                    // it — is that file's business and is already tolerated, or deliberately fatal,
                    // at its own level. Wrapping the recursion here attributed every depth to this
                    // node instead: one unfound include three files down discarded everything the
                    // outer file contained, silently and under the outer file's name, which is how
                    // Shield_Amp's playlist layout vanished (B45). It also laundered the one failure
                    // `isInsideSkin` exists to keep fatal — a ClassicPro engine include — into a
                    // warning, because the *outer* path was inside the skin.
                    targets = try vfs.expand(file, relativeTo: sourcePath, location: node.location)
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
                    continue
                }
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

    /// A missing include is only tolerated when it names a file *inside the skin*. One that climbs
    /// into another mount — `@COLORTHEMESPATH@\..\..\Plugins\classicPro\engine\load.xml` — is a
    /// ClassicPro skin whose engine is not installed, and that stays a hard, nameable failure rather
    /// than a skin that loads and draws almost nothing.
    private func isInsideSkin(_ rawPath: String, relativeTo sourcePath: String) -> Bool {
        guard let canonical = try? vfs.resolve(rawPath, relativeTo: sourcePath, mustExist: false)
        else { return false }
        let folded = Self.fold(canonical.logicalPath)
        if let skinRoot = vfs.skinRoot, folded.hasPrefix(Self.fold(skinRoot + "/")) { return true }
        // `@DEFAULTSKINPATH@` names Winamp's stock Modern skin, which NullPlayer does not ship, so
        // nothing is mounted there. canum includes three of its files — `xml/eq.xml`,
        // `xml/thinger.xml`, `xml/pledit.xml` — for surfaces it does not skin itself; skipping them
        // leaves those surfaces to `WasabiSurfaceSynthesizer`, which builds them out of the skin's
        // *own* frame. That is closer to what the author asked for than failing the load (B92).
        return folded.hasPrefix(Self.fold(WalVirtualFileSystem.defaultSkinRoot + "/"))
    }

    /// Windows XML tooling routinely emits UTF-16, so honour a byte order mark before falling back
    /// to the byte encodings. The fallback cannot find this on its own: `ff fe` is not valid UTF-8,
    /// so a UTF-16 file skipped straight to ISO-8859-1 -- an encoding that accepts *every* byte
    /// sequence and so never reports a wrong guess. It yielded one character per byte, nulls
    /// included, and the parser saw a `<` that no `</` ever closed (B93).
    static func decodeText(_ data: Data) -> String? {
        let bytes = [UInt8](data.prefix(4))
        let body = { (count: Int) in data.subdata(in: data.startIndex.advanced(by: count) ..< data.endIndex) }
        if bytes.count >= 4, bytes[0] == 0xFF, bytes[1] == 0xFE, bytes[2] == 0x00, bytes[3] == 0x00 {
            if let text = String(data: body(4), encoding: .utf32LittleEndian) { return text }
        } else if bytes.count >= 4, bytes[0] == 0x00, bytes[1] == 0x00, bytes[2] == 0xFE, bytes[3] == 0xFF {
            if let text = String(data: body(4), encoding: .utf32BigEndian) { return text }
        } else if bytes.count >= 3, bytes[0] == 0xEF, bytes[1] == 0xBB, bytes[2] == 0xBF {
            if let text = String(data: body(3), encoding: .utf8) { return text }
        } else if bytes.count >= 2, bytes[0] == 0xFF, bytes[1] == 0xFE {
            if let text = String(data: body(2), encoding: .utf16LittleEndian) { return text }
        } else if bytes.count >= 2, bytes[0] == 0xFE, bytes[1] == 0xFF {
            if let text = String(data: body(2), encoding: .utf16BigEndian) { return text }
        }
        if let utf8 = String(data: data, encoding: .utf8) { return utf8 }
        return String(data: data, encoding: .isoLatin1)
    }

    private static func fold(_ value: String) -> String {
        value.folding(options: [.caseInsensitive], locale: Locale(identifier: "en_US_POSIX"))
    }
}
