import Foundation

/// Whether a skin's key handler **compares** a given key, rather than merely existing.
///
/// `WMPMainView` gives the skin every keystroke before its own built-ins, and the answer it needs is
/// synchronous — the script actor has not run yet. "A handler is authored" was that answer, and it
/// is wrong for the arrows. **68 of the 154 archives with an `<EFFECTS>` hang a key handler on the
/// view that holds it** (`onkeydown="viewHotKeys();"`, `"onHotKeyPress();"`), and not one of those
/// handlers compares `37`…`40` — they switch over letters and space (measured 2026-09-24, 179
/// archives). Every arrow pressed in those windows was claimed by a handler that then did nothing
/// with it, so the hosted surface's up/down (effect) and left/right (inside it) never fired there.
/// The arrow handlers the corpus does write are on sliders (`volKey(event)`) and on views with no
/// `<EFFECTS>` (`onViewResize(event)`), and they keep their keys.
///
/// The scan reads the handler text and, transitively, the bodies of the bare functions it calls
/// (`viewHotKeys()`, `onViewResize(event)`), and answers whether any of it compares the VK as a
/// literal — `case 38:`, `== 38`, `38 ==`. Member calls (`player.controls.next()`) are the engine's
/// and are not followed. A called function that cannot be found is treated as comparing the key,
/// so an unreadable handler keeps the key rather than losing it.
///
/// **Comments are not code.** `Age_of_Mythology_MPXP`'s `viewHotKeys` carries a commented-out
/// `//	videoZoom();`, whose body calls `updateZoomToolTip`, which the skin never defines — so the
/// scan followed a dead call into an unknown function and claimed every arrow for the view, and
/// the hosted visualizer's keys never fired. Handler text and sources are read without comments.
enum WMPKeyHandlerScan {

    static func handlers(_ handlers: [String], compare virtualKey: Int, in sources: [String]) -> Bool {
        let number = "(?:\(virtualKey)|0x\(String(virtualKey, radix: 16)))"
        let literal = "case\\s+\(number)\\s*:"
            + "|[!=]==?\\s*\(number)(?![0-9A-Za-z])"
            + "|(?<![0-9A-Za-z.])\(number)\\s*[!=]="
        guard let compares = try? NSRegularExpression(pattern: literal, options: [.caseInsensitive]) else {
            assertionFailure("WMPKeyHandlerScan: invalid pattern \(literal)")
            return true
        }
        let sources = sources.map(withoutComments)
        var pending = handlers.map(withoutComments), visited = Set<String>()
        while let text = pending.popLast() {
            if compares.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil { return true }
            for name in calledFunctions(in: text) where visited.insert(name.lowercased()).inserted {
                guard let body = functionBody(named: name, in: sources) else {
                    if builtins.contains(name.lowercased()) { continue }
                    return true
                }
                pending.append(body)
            }
        }
        return false
    }

    /// Bare `name(` calls — not `obj.name(`, and not the JScript keywords that take parentheses.
    private static func calledFunctions(in text: String) -> [String] {
        let pattern = try? NSRegularExpression(pattern: "(?<![.\\w$])([A-Za-z_$][\\w$]*)\\s*\\(")
        let range = NSRange(text.startIndex..., in: text)
        return (pattern?.matches(in: text, range: range) ?? []).compactMap { match in
            Range(match.range(at: 1), in: text).map { String(text[$0]) }
        }.filter { !keywords.contains($0.lowercased()) }
    }

    /// The brace-balanced body of `function name(…) { … }`, searched across every source.
    private static func functionBody(named name: String, in sources: [String]) -> String? {
        let escaped = NSRegularExpression.escapedPattern(for: name)
        guard let header = try? NSRegularExpression(pattern: "function\\s+\(escaped)\\s*\\([^)]*\\)\\s*\\{",
                                                    options: [.caseInsensitive]) else { return nil }
        for source in sources {
            guard let match = header.firstMatch(in: source, range: NSRange(source.startIndex..., in: source)),
                  let open = Range(match.range, in: source) else { continue }
            var depth = 1, index = open.upperBound
            while index < source.endIndex, depth > 0 {
                switch source[index] {
                case "{": depth += 1
                case "}": depth -= 1
                default: break
                }
                index = source.index(after: index)
            }
            return String(source[open.upperBound..<index])
        }
        return nil
    }

    /// `text` with its `//` and `/* */` comments blanked. A quoted string is skipped whole, so a URL
    /// keeps its `//`; a quote ends at the line too, since a JScript string cannot span one and a
    /// definition file's prose apostrophe must not swallow the rest of it.
    static func withoutComments(_ text: String) -> String {
        let chars = Array(text.unicodeScalars)
        var out = String.UnicodeScalarView(), index = 0, quote: Unicode.Scalar?
        while index < chars.count {
            let c = chars[index], next = index + 1 < chars.count ? chars[index + 1] : nil
            if let open = quote {
                if c == "\\", let next { out.append(c); out.append(next); index += 2; continue }
                if c == open || c == "\n" { quote = nil }
                out.append(c); index += 1
            } else if c == "\"" || c == "'" {
                quote = c; out.append(c); index += 1
            } else if c == "/", next == "/" {
                while index < chars.count, chars[index] != "\n" { index += 1 }
            } else if c == "/", next == "*" {
                index += 2
                while index < chars.count, !(chars[index] == "*" && index + 1 < chars.count
                                             && chars[index + 1] == "/") { index += 1 }
                index += 2; out.append(" ")
            } else {
                out.append(c); index += 1
            }
        }
        return String(out)
    }

    private static let keywords: Set<String> = [
        "if", "for", "while", "switch", "catch", "function", "return", "typeof", "with", "new", "delete", "void"
    ]

    /// Global functions JScript provides, which no skin defines and which compare nothing.
    private static let builtins: Set<String> = [
        "parseint", "parsefloat", "isnan", "isfinite", "string", "number", "boolean", "array", "object",
        "date", "math", "escape", "unescape", "eval", "settimeout", "setinterval", "cleartimeout",
        "clearinterval", "encodeuricomponent", "decodeuricomponent", "encodeuri", "decodeuri"
    ]
}
