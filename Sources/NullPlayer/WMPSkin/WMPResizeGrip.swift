import Foundation

/// **The grip a view authors for its own resize, and the corner it asks for (W193, W227).**
///
/// A `.wmz` window is borderless, so the only resize WMP offers is the one the skin draws: a corner
/// button whose `onMouseDown` reaches `view.size('bottomright')`. This engine adds an edge band the
/// window frame would have had, and W227 is what that band skips — the *rest* of the grip handler,
/// which is the skin's bracket around its own resize (`XBOX`'s `saveVidSize()` persists the size
/// the user dragged to; `Compact`'s `DoSize()` unpins both drawers). Naming the grip is what lets
/// the band raise that handler instead of resizing behind the skin's back.
///
/// **One hop, because the corpus needs exactly one.** 233 of the 234 `view.size` calls in the 185
/// installed archives are spelled straight into the handler attribute. The one that is not is
/// `Compact`, which is the archive the whole bracket exists for — `onMouseDown="DoSize()"`, with
/// the call inside a function in `compact.js` — so a literal-only match would miss the only skin
/// whose tail does more than save a preference. Deeper than one hop is authored nowhere.
enum WMPResizeGrip {
    struct Grip: Hashable {
        let stableID: Int
        let nodeID: String?
        /// The authored corner word, as the skin spelled it. Read by
        /// `WMPMainView.edges(forCorner:)`, which matches substrings.
        let corner: String
    }

    /// Every mouse handler a `.wmz` can hang on a node. `view.size` is authored on `onMouseDown` in
    /// all 234 corpus calls; the rest are here so a skin that spells it elsewhere is still a grip
    /// rather than an ordinary control.
    private static let handlerNames = ["onMouseDown", "onMouseUp", "onClick", "onDblClick"]

    /// The grips in one view, in document order.
    static func grips(in view: WMPNode, scriptSources: [String: String]) -> [Grip] {
        let functions = self.functions(in: scriptSources)
        var found: [Grip] = []
        func walk(_ node: WMPNode) {
            if let corner = corner(of: node, functions: functions) {
                found.append(Grip(stableID: node.stableID, nodeID: node.xmlID, corner: corner))
            }
            for child in node.children { walk(child) }
        }
        walk(view)
        return found
    }

    private static func corner(of node: WMPNode, functions: [String: String]) -> String? {
        let handlers = handlerNames.compactMap { node.attribute(named: $0)?.rawValue }
        guard !handlers.isEmpty else { return nil }
        for handler in handlers {
            if let corner = corner(inSource: handler) { return corner }
            // One hop: a handler that names a function whose body makes the call.
            for name in identifiersCalled(in: handler) {
                guard let body = functions[name.lowercased()],
                      let corner = corner(inSource: body) else { continue }
                return corner
            }
        }
        return nil
    }

    /// The first `view.size('<corner>')` in a piece of script, and the word it asks for.
    private static func corner(inSource source: String) -> String? {
        guard let range = source.range(of: #"view\s*\.\s*size\s*\("#,
                                       options: [.regularExpression, .caseInsensitive])
        else { return nil }
        let rest = source[range.upperBound...]
        guard let close = rest.firstIndex(of: ")") else { return nil }
        let argument = rest[..<close].trimmingCharacters(in: .whitespacesAndNewlines)
        let word = argument.trimmingCharacters(in: CharacterSet(charactersIn: "'\" \t\r\n"))
        // A call whose corner is computed rather than authored is still a grip; `edges(forCorner:)`
        // answers nothing for a name it cannot read, and the caller falls back to the drag's own
        // edges, which is what the user is already pulling.
        return word.isEmpty ? "bottomright" : word
    }

    /// Bare `name(` calls in a handler, which is the only shape a `.wmz` handler attribute takes.
    private static func identifiersCalled(in source: String) -> [String] {
        var names: [String] = []
        let pattern = #"(?<![.\w])([A-Za-z_]\w*)\s*\("#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(source.startIndex..., in: source)
        for match in regex.matches(in: source, range: range) {
            guard let found = Range(match.range(at: 1), in: source) else { continue }
            names.append(String(source[found]))
        }
        return names
    }

    /// Every top-level function in the skin's scripts, folded name to body. Brace-counted rather
    /// than regexed, because a corpus function body routinely nests three blocks deep.
    private static func functions(in scriptSources: [String: String]) -> [String: String] {
        var bodies: [String: String] = [:]
        guard let regex = try? NSRegularExpression(
            pattern: #"\bfunction\s+([A-Za-z_]\w*)\s*\([^)]*\)\s*\{"#) else { return bodies }
        for source in scriptSources.values {
            let range = NSRange(source.startIndex..., in: source)
            for match in regex.matches(in: source, range: range) {
                guard let name = Range(match.range(at: 1), in: source),
                      let open = Range(match.range, in: source) else { continue }
                var depth = 1
                var index = open.upperBound
                while index < source.endIndex, depth > 0 {
                    if source[index] == "{" { depth += 1 }
                    else if source[index] == "}" { depth -= 1 }
                    index = source.index(after: index)
                }
                bodies[source[name].lowercased()] = String(source[open.upperBound..<index])
            }
        }
        return bodies
    }
}
