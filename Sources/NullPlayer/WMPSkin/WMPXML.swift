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
    /// The attributes **in the order the document wrote them**, with the authored spelling of each
    /// name preserved and duplicates collapsed.
    ///
    /// Document order is load-bearing, not cosmetic. The previous parser sorted these alphabetically
    /// and the `.wal` engine paid for the identical mistake first: handing a skin an alphabetised
    /// attribute list put `id` at position 4 of 10 and silently dropped four style properties, which
    /// is how cPro2's clock lost its metrics and drew its elapsed and total times on top of each
    /// other (`WalXMLNode.attributeOrder`). WMP skins read their own markup the same way.
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
    /// What the parser tolerated rather than rejected. The loader folds these into the skin's list.
    let diagnostics: [WMPDiagnostic]
}

/// A hand-rolled, deliberately lenient parser for `.wms` markup.
///
/// **Why not `XMLParser`.** WMP theme files are not well-formed XML and WMP loads them anyway. Four
/// of the fourteen corpus archives — Alpine7618_v09, anemone, Official_Xbox_XP and The Unit — repeat
/// an attribute on a tag, and libxml2 aborts the whole document on that (`XML_ERR_ATTRIBUTE_REDEFINED`,
/// surfaced as `NSXMLParserErrorDomain 111`) *before* the delegate is ever called. There was no
/// warning to switch off: the abort happens below Foundation, and the delegate signature
/// `attributes: [String: String]` could not have carried a duplicate even if it had run. So the
/// parser is replaced rather than softened — which is also what unlocks the next leniency the corpus
/// asks for, none of which `XMLParser` can express.
///
/// This is a port of `WinampModern/WalXML.swift`'s `WalLenientXMLParser`, which solved the same
/// problem for Wasabi markup. The rule both engines follow: **degrade with a diagnostic, never fail
/// the skin.**
///
/// What is still fatal, and why:
///   * a closing tag that does not match the tag it closes — the document's shape is then unknowable,
///     and no corpus skin needs this tolerance today;
///   * an entity *declaration* — the `res://`-and-`file://` sandbox posture applies to XML too;
///   * the depth and node caps from `WMPPhase0Limits`, which bound untrusted markup and are never
///     relaxed to make a skin load.
struct WMPXMLParser {
    private let limits: WMPXMLLimits

    init(limits: WMPXMLLimits = .production) {
        self.limits = limits
    }

    func parse(_ text: String, path: String) throws -> WMPXMLDocument {
        let chars = Array(text)
        var roots: [WMPXMLNode] = []
        var stack: [WMPXMLNode] = []
        var diagnostics: [WMPDiagnostic] = []
        var index = 0
        var line = 1
        var column = 1
        var nodeCount = 0

        // `isNewline`, not `== "\n"`. Corona, Alpine and Official_Xbox_XP are authored with CR-only
        // line endings, and counting only line feeds reported every diagnostic in them at line 1 with
        // a five-digit column — which is what libxml2 was quietly getting right before. A location is
        // the first thing triage reads; one that always says line 1 is worse than none.
        // Swift folds a CRLF pair into a single `Character`, so this counts it once.
        func advance(over range: Range<Int>) {
            for i in range {
                if chars[i].isNewline { line += 1; column = 1 } else { column += 1 }
            }
        }

        func matches(_ start: Int, _ value: String) -> Bool {
            let needle = Array(value)
            guard start + needle.count <= chars.count else { return false }
            return needle.indices.allSatisfy { chars[start + $0] == needle[$0] }
        }

        func end(of value: String, after start: Int) -> Int? {
            var cursor = start
            while cursor < chars.count {
                if matches(cursor, value) { return cursor + value.count }
                cursor += 1
            }
            return nil
        }

        func malformed(_ message: String, _ line: Int, _ column: Int) -> WMPFailure {
            WMPFailure(WMPDiagnostic(.malformedXML, message,
                                     location: WMPSourceLocation(path: path, line: line, column: column)))
        }

        while index < chars.count {
            guard chars[index] == "<" else {
                if chars[index].isNewline { line += 1; column = 1 } else { column += 1 }
                index += 1
                continue
            }

            let tagLine = line
            let tagColumn = column

            if matches(index, "<!--") {
                guard let stop = end(of: "-->", after: index + 4) else {
                    throw malformed("Unterminated XML comment.", tagLine, tagColumn)
                }
                advance(over: index..<stop)
                index = stop
                continue
            }
            if matches(index, "<![CDATA[") {
                guard let stop = end(of: "]]>", after: index + 9) else {
                    throw malformed("Unterminated CDATA section.", tagLine, tagColumn)
                }
                advance(over: index..<stop)
                index = stop
                continue
            }
            if matches(index, "<?") {
                // The text decoder has already honoured the byte encoding, so the declaration's own
                // `encoding=` is not merely redundant, it is wrong by the time we see the string.
                // Skipping it outright is what lets a UTF-16-authored file keep its `é`.
                guard let stop = end(of: "?>", after: index + 2) ?? end(of: ">", after: index + 2) else {
                    throw malformed("Unterminated XML declaration.", tagLine, tagColumn)
                }
                advance(over: index..<stop)
                index = stop
                continue
            }
            if matches(index, "<!") {
                let stop = try endOfMarkupDeclaration(chars, from: index, path: path,
                                                      line: tagLine, column: tagColumn)
                advance(over: index..<stop)
                index = stop
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
            guard !name.isEmpty else { throw malformed("Tag has no name.", tagLine, tagColumn) }

            if isClosing {
                guard let stop = end(of: ">", after: cursor), let open = stack.last,
                      open.name.caseInsensitiveCompare(name) == .orderedSame else {
                    throw malformed("Unexpected closing tag </\(name)>.", tagLine, tagColumn)
                }
                stack.removeLast()
                advance(over: index..<stop)
                index = stop
                continue
            }

            var attributes: [WMPXMLAttribute] = []
            var positionByFoldedName: [String: Int] = [:]
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
                let attributeStart = cursor
                while cursor < chars.count, !chars[cursor].isWhitespace,
                      chars[cursor] != "=", chars[cursor] != ">", chars[cursor] != "/" {
                    cursor += 1
                }
                let attributeName = String(chars[attributeStart..<cursor])
                while cursor < chars.count, chars[cursor].isWhitespace { cursor += 1 }
                var attributeValue = ""
                if cursor < chars.count, chars[cursor] == "=" {
                    cursor += 1
                    while cursor < chars.count, chars[cursor].isWhitespace { cursor += 1 }
                    if cursor < chars.count, chars[cursor] == "\"" || chars[cursor] == "'" {
                        let quote = chars[cursor]
                        cursor += 1
                        let valueStart = cursor
                        while cursor < chars.count, chars[cursor] != quote { cursor += 1 }
                        guard cursor < chars.count else {
                            throw malformed("Unterminated value for attribute '\(attributeName)'.",
                                            tagLine, tagColumn)
                        }
                        attributeValue = Self.unescape(String(chars[valueStart..<cursor]))
                        cursor += 1
                    } else {
                        let valueStart = cursor
                        while cursor < chars.count, !chars[cursor].isWhitespace, chars[cursor] != ">" {
                            cursor += 1
                        }
                        attributeValue = Self.unescape(String(chars[valueStart..<cursor]))
                    }
                }
                if !attributeName.isEmpty {
                    let folded = WMPPath.fold(attributeName)
                    let attribute = WMPXMLAttribute(name: attributeName, value: attributeValue)
                    if let existing = positionByFoldedName[folded] {
                        // Last wins, in the slot the *first* spelling claimed, so the document order
                        // the rest of the engine reads stays the document's own. All three duplicates
                        // measured across the corpus repeat an identical value, so the choice is
                        // invisible today; the diagnostic carries both values so that the first case
                        // where they differ shows up in the census instead of being silently decided.
                        diagnostics.append(WMPDiagnostic(
                            .duplicateAttribute,
                            "<\(name)> repeats attribute '\(attributeName)'; "
                                + "kept \"\(attributeValue)\" over \"\(attributes[existing].value)\".",
                            severity: .warning,
                            location: WMPSourceLocation(path: path, line: tagLine, column: tagColumn)))
                        attributes[existing] = attribute
                    } else {
                        positionByFoldedName[folded] = attributes.count
                        attributes.append(attribute)
                    }
                }
                // A stray '/' that does not close the tag matches no branch above and would otherwise
                // park the cursor forever. Skip it so the scan always advances.
                if cursor == iterationStart { cursor += 1 }
            }
            guard closed else { throw malformed("Unterminated <\(name)> tag.", tagLine, tagColumn) }

            let location = WMPSourceLocation(path: path, line: tagLine, column: tagColumn)
            nodeCount += 1
            guard nodeCount <= limits.maximumNodeCount else {
                throw WMPFailure(WMPDiagnostic(.expandedNodeLimitExceeded,
                    "XML contains more than \(limits.maximumNodeCount) nodes.", location: location))
            }
            guard stack.count + 1 <= limits.maximumNestingDepth else {
                throw WMPFailure(WMPDiagnostic(.xmlDepthExceeded,
                    "XML nesting exceeds \(limits.maximumNestingDepth) levels.", location: location))
            }

            let node = WMPXMLNode(name: name, attributes: attributes, location: location)
            if let parent = stack.last { parent.append(node) } else { roots.append(node) }
            if !selfClosing { stack.append(node) }
            advance(over: index..<cursor)
            index = cursor
        }

        // A file that ends before it closes everything it opened is the skin's bug, and WMP loads
        // those. Nothing is missing from the tree: a node is attached to its parent (or to `roots`)
        // when it *opens*, so an unclosed tag already holds every child and sibling that followed it.
        // The depth cap still bounds how much can be left open.
        if let open = stack.last {
            let extra = stack.count > 1 ? " (\(stack.count) tags left open)" : ""
            diagnostics.append(WMPDiagnostic(.unclosedTag,
                "Unclosed <\(open.name)> tag at end of file\(extra); its children were kept.",
                severity: .warning, location: open.location))
        }
        return WMPXMLDocument(roots: roots, nodeCount: nodeCount, diagnostics: diagnostics)
    }

    /// Consume a `<!…>` markup declaration and reject any entity declaration inside it.
    ///
    /// A DOCTYPE's internal subset is bracketed, and its own `<!ENTITY …>` closes on a `>` well
    /// before the DOCTYPE does — so scanning to the first `>` would step over the declaration
    /// without ever seeing it. Track the `[ … ]` subset and inspect everything consumed.
    private func endOfMarkupDeclaration(
        _ chars: [Character], from start: Int, path: String, line: Int, column: Int
    ) throws -> Int {
        var cursor = start + 2
        var inSubset = false
        var quote: Character?
        while cursor < chars.count {
            let character = chars[cursor]
            if let open = quote {
                if character == open { quote = nil }
            } else if character == "\"" || character == "'" {
                quote = character
            } else if character == "[" {
                inSubset = true
            } else if character == "]" {
                inSubset = false
            } else if character == ">", !inSubset {
                cursor += 1
                break
            }
            cursor += 1
        }
        let consumed = String(chars[start..<min(cursor, chars.count)])
        guard consumed.range(of: "<!ENTITY", options: [.caseInsensitive]) == nil else {
            throw WMPFailure(WMPDiagnostic(.malformedXML, "External XML entities are not supported.",
                location: WMPSourceLocation(path: path, line: line, column: column)))
        }
        return min(cursor, chars.count)
    }

    private static func unescape(_ value: String) -> String {
        guard value.contains("&") else { return value }
        var result = ""
        result.reserveCapacity(value.count)
        var rest = Substring(value)
        while let ampersand = rest.firstIndex(of: "&") {
            result += rest[rest.startIndex..<ampersand]
            rest = rest[ampersand...]
            guard let semicolon = rest.dropFirst().firstIndex(of: ";"),
                  rest.distance(from: rest.startIndex, to: semicolon) <= 10 else {
                result.append("&")
                rest = rest.dropFirst()
                continue
            }
            let entity = rest[rest.index(after: rest.startIndex)..<semicolon]
            if let replacement = Self.replacement(for: entity) {
                result += replacement
            } else {
                // An unrecognised entity is markup the skin meant literally — a bare `&` in a URL or
                // a JScript `&&`. Keeping it verbatim is what WMP does; dropping it corrupts the
                // expression the skin lays itself out with.
                result += rest[rest.startIndex...semicolon]
            }
            rest = rest[rest.index(after: semicolon)...]
        }
        result += rest
        return result
    }

    private static func replacement(for entity: Substring) -> String? {
        switch entity {
        case "quot": return "\""
        case "apos": return "'"
        case "lt": return "<"
        case "gt": return ">"
        case "amp": return "&"
        default: break
        }
        guard entity.first == "#" else { return nil }
        let digits = entity.dropFirst()
        let scalarValue: UInt32?
        if digits.first == "x" || digits.first == "X" {
            scalarValue = UInt32(digits.dropFirst(), radix: 16)
        } else {
            scalarValue = UInt32(digits, radix: 10)
        }
        // A NUL from a character reference is the same hazard `WMPTextDecoder` rejects at the byte
        // level, so it is never produced here either.
        guard let scalarValue, scalarValue != 0, let scalar = UnicodeScalar(scalarValue) else {
            return nil
        }
        return String(Character(scalar))
    }
}
