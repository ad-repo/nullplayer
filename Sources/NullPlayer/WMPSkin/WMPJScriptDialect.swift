import Foundation

/// The one place where skin JScript and JavaScriptCore are reconciled at the *language* level.
///
/// A `.wmz` is authored against JScript, and JavaScriptCore is not JScript. Almost every difference
/// is harmless, but one of them is load-bearing across a whole skin family: **`for (x in obj)`
/// enumerates live in JScript and from a snapshot in JavaScriptCore.** ES5.1 §12.6.4 says properties
/// added during enumeration *may* be skipped and JSC skips them; JScript visits them.
///
/// That is not a footnote. The WMP9 skins — every archive shipping the `numExtraArgs` rewrite of
/// `corona_tiny.js`, which is the whole Microsoft-derived family — chain their compact-mode
/// animation through exactly this. `TimerDispatch` enumerates `g_grpTimerEvents` with `for-in`,
/// copying survivors into a fresh array, and calls `eval(tEvent.end)` on an event that has just
/// finished. That `end` string is a `RegisterTimerEvent(…)` which **appends the next event to the
/// array being enumerated**: the `ResizeY` that collapses the video panel into a mini player, and,
/// for `RestorePlayer()`, the one whose own `end` is `theme.currentViewID = "vPlayer"`. Under a
/// snapshot enumeration the appended event is never reached, so it is dropped on the same tick it
/// was registered — the compact view never collapses and **there is no way back to the player**.
/// Reported live as "pressing the compact mode button has no visual difference on any skin… there
/// is no way to leave compact mode while in the skin" (W86).
///
/// Corona's own 2002 script is unaffected because it splices the array it is iterating instead of
/// rebuilding it, which is why `corona` passes and `9SeriesDefault` does not — and why fixing the
/// view-switch path (W46) made `corona` work and left the WMP9 family exactly as stuck.
///
/// **This is a dialect difference, not a skin bug, so it is fixed here and never in a skin.** It
/// belongs beside the loader's other JScript-era accommodations — the BOM-less UTF-16 sniff, the
/// Windows-1252 fallback, the hand-rolled lenient XML parser — for the same reason: the corpus was
/// written twenty years ago against a different implementation, and the engine meets it there.
enum WMPJScriptDialect {

    /// Defines `__wmpEnum`, the live enumerator the rewrite below targets. Evaluated once with the
    /// rest of the bootstrap and **never itself rewritten** — its own `for-in` is the native,
    /// snapshotting one, and recomputing it on every `next()` is precisely what makes the outer
    /// loop live.
    ///
    /// `seen` is a null-prototype map because the keys are attacker-supplied in the only sense that
    /// matters here: a plain `{}` would report `constructor` as already visited and silently skip a
    /// property with that name.
    static let prelude = #"""
    (function (global) {
      global.__wmpEnum = function (object) {
        return {
          o: object,
          seen: Object.create(null),
          key: null,
          next: function () {
            var target = this.o;
            if (target === null || target === undefined) return false;
            for (var name in target) {
              if (this.seen[name] !== 1) {
                this.seen[name] = 1;
                this.key = name;
                return true;
              }
            }
            return false;
          }
        };
      };
    })(this);
    """#

    /// Rewrites every `for (… in …)` in one program into a live enumeration.
    ///
    /// `for (LHS in OBJ) BODY` becomes
    /// `for (var __wmpEn = __wmpEnum(OBJ); __wmpEn.next() ? ((LHS = __wmpEn.key), true) : false; ) BODY`
    ///
    /// The shape is deliberate. It stays a `for` *statement* in the same position, so a label,
    /// `break`, `continue` and a body with no braces all keep working, and `continue` re-enters
    /// through the condition, which is where the next key comes from. The assignment happens in the
    /// condition rather than at the top of the body because the body may not be a block.
    ///
    /// `var` in the head is preserved as a declaration in the `for`'s own init clause; a bare head
    /// is left bare, so a skin relying on JScript's implicit global for its loop variable still gets
    /// one. Nothing else about the program changes, and a program with no `for-in` is returned
    /// unchanged.
    ///
    /// **What it deliberately does not reach:** a `for-in` inside a string that the skin later hands
    /// to `eval`. The scanner skips string bodies, as it must, and native `eval` compiles what it is
    /// given. No corpus skin does this; the WMP9 `end` strings are `RegisterTimerEvent(…)` calls.
    static func liveForIn(_ source: String) -> String {
        guard source.contains("for") else { return source }
        var scanner = Scanner(source: Array(source))
        return scanner.rewrite()
    }

    // MARK: - Scanning

    /// Enough of a JavaScript tokenizer to know when `for` is code: string bodies, both comment
    /// forms and regular-expression literals are skipped rather than searched. A rewrite driven by
    /// a plain textual search would fire inside `metadata.js`'s string tables.
    /// **Newlines are tested with `isNewline`, never against `"\n"`.** The corpus's scripts are
    /// CRLF, and Swift folds `"\r\n"` into a *single* `Character` that does not compare equal to
    /// `"\n"` — so a line-comment scanner written the obvious way runs to the end of the file and
    /// swallows the whole program. Every script in this corpus opens with a `//` comment, so the
    /// rewrite silently did nothing at all and `9SeriesDefault` behaved exactly as before the fix.
    private struct Scanner {
        let source: [Character]
        var index = 0
        var output = ""
        var counter = 0
        /// The last significant character emitted, which is how `/` is told apart: it opens a
        /// regular expression unless what precedes it can end an expression.
        var lastSignificant: Character?

        init(source: [Character]) { self.source = source }

        mutating func rewrite() -> String {
            output.reserveCapacity(source.count + 64)
            while index < source.count {
                let character = source[index]
                if character == "\"" || character == "'" { copyString() ; continue }
                if character == "/", peek(1) == "/" { copyLineComment(); continue }
                if character == "/", peek(1) == "*" { copyBlockComment(); continue }
                if character == "/", startsRegularExpression() { copyRegularExpression(); continue }
                if character == "f", isWord(at: index, "for"), let head = forHead(after: index + 3) {
                    if let rewritten = rewriteForIn(head: head) {
                        output += rewritten
                        index = head.end
                        lastSignificant = ")"
                        continue
                    }
                }
                append(character)
                index += 1
            }
            return output
        }

        // MARK: Emitting

        private mutating func append(_ character: Character) {
            output.append(character)
            if !character.isWhitespace { lastSignificant = character }
        }

        private mutating func copy(through end: Int) {
            while index < end, index < source.count { append(source[index]); index += 1 }
        }

        // MARK: Literals the rewrite must not look inside

        private mutating func copyString() {
            let quote = source[index]
            append(quote); index += 1
            while index < source.count {
                let character = source[index]
                append(character); index += 1
                if character == "\\" {
                    if index < source.count { append(source[index]); index += 1 }
                    continue
                }
                if character == quote { return }
                // An unterminated string is the skin's problem, not the scanner's: stop at the line
                // end rather than swallowing the rest of the program.
                if character.isNewline { return }
            }
        }

        private mutating func copyLineComment() {
            while index < source.count, !source[index].isNewline {
                output.append(source[index]); index += 1
            }
        }

        private mutating func copyBlockComment() {
            output.append(source[index]); index += 1
            output.append(source[index]); index += 1
            while index < source.count {
                if source[index] == "*", peek(1) == "/" {
                    output.append("*"); output.append("/"); index += 2; return
                }
                output.append(source[index]); index += 1
            }
        }

        private mutating func copyRegularExpression() {
            append("/"); index += 1
            var inClass = false
            while index < source.count {
                let character = source[index]
                append(character); index += 1
                if character == "\\" {
                    if index < source.count { append(source[index]); index += 1 }
                    continue
                }
                if character == "[" { inClass = true }
                else if character == "]" { inClass = false }
                else if character == "/", !inClass { return }
                else if character.isNewline { return }
            }
        }

        /// A `/` is a regular expression unless the previous significant character could end an
        /// expression. The usual heuristic, and sufficient for this corpus.
        private func startsRegularExpression() -> Bool {
            guard let previous = lastSignificant else { return true }
            if previous.isLetter || previous.isNumber || previous == "_" || previous == "$" { return false }
            return !(previous == ")" || previous == "]" || previous == "}")
        }

        // MARK: `for` heads

        private func peek(_ offset: Int) -> Character? {
            let target = index + offset
            return target < source.count ? source[target] : nil
        }

        private func isIdentifierCharacter(_ character: Character) -> Bool {
            character.isLetter || character.isNumber || character == "_" || character == "$"
        }

        /// Is `word` present at `position` as a whole token?
        private func isWord(at position: Int, _ word: String) -> Bool {
            let characters = Array(word)
            guard position + characters.count <= source.count else { return false }
            for (offset, character) in characters.enumerated()
            where source[position + offset] != character { return false }
            if position > 0, isIdentifierCharacter(source[position - 1]) { return false }
            let after = position + characters.count
            if after < source.count, isIdentifierCharacter(source[after]) { return false }
            return true
        }

        private struct Head {
            let open: Int       // index of `(`
            let close: Int      // index of `)`
            let end: Int        // one past `)`
            let text: String    // the head, without the parentheses
        }

        /// The balanced parenthesised head of a `for`, or `nil` if this `for` is not followed by one.
        private func forHead(after position: Int) -> Head? {
            var cursor = position
            while cursor < source.count, source[cursor].isWhitespace { cursor += 1 }
            guard cursor < source.count, source[cursor] == "(" else { return nil }
            let open = cursor
            var depth = 0
            var body = ""
            while cursor < source.count {
                let character = source[cursor]
                if character == "\"" || character == "'" {
                    let quote = character
                    body.append(character); cursor += 1
                    while cursor < source.count {
                        let inner = source[cursor]
                        body.append(inner); cursor += 1
                        if inner == "\\" {
                            if cursor < source.count { body.append(source[cursor]); cursor += 1 }
                            continue
                        }
                        if inner == quote || inner.isNewline { break }
                    }
                    continue
                }
                if character == "(" || character == "[" || character == "{" { depth += 1 }
                if character == ")" || character == "]" || character == "}" {
                    depth -= 1
                    if depth == 0, character == ")" {
                        return Head(open: open, close: cursor, end: cursor + 1,
                                    text: String(body.dropFirst()))
                    }
                }
                body.append(character)
                cursor += 1
            }
            return nil
        }

        /// Splits a head at its top-level `in`, or returns `nil` when this is an ordinary
        /// three-clause `for`. A `;` anywhere at top level settles it immediately.
        private func splitForIn(_ head: String) -> (lhs: String, object: String)? {
            let characters = Array(head)
            var depth = 0
            var index = 0
            while index < characters.count {
                let character = characters[index]
                if character == "\"" || character == "'" {
                    let quote = character
                    index += 1
                    while index < characters.count {
                        if characters[index] == "\\" { index += 2; continue }
                        if characters[index] == quote || characters[index].isNewline { break }
                        index += 1
                    }
                    index += 1
                    continue
                }
                if character == "(" || character == "[" || character == "{" { depth += 1 }
                if character == ")" || character == "]" || character == "}" { depth -= 1 }
                if depth == 0, character == ";" { return nil }
                if depth == 0, character == "i", index + 1 < characters.count, characters[index + 1] == "n" {
                    let before = index > 0 ? characters[index - 1] : " "
                    let afterIndex = index + 2
                    let after: Character = afterIndex < characters.count ? characters[afterIndex] : " "
                    let boundedBefore = !(before.isLetter || before.isNumber || before == "_" || before == "$")
                    let boundedAfter = !(after.isLetter || after.isNumber || after == "_" || after == "$")
                    if boundedBefore, boundedAfter {
                        let lhs = String(characters[0..<index])
                        let object = String(characters[afterIndex...])
                        return (lhs.trimmingCharacters(in: .whitespacesAndNewlines),
                                object.trimmingCharacters(in: .whitespacesAndNewlines))
                    }
                }
                index += 1
            }
            return nil
        }

        private mutating func rewriteForIn(head: Head) -> String? {
            guard let (rawLHS, object) = splitForIn(head.text), !object.isEmpty else { return nil }
            var target = rawLHS
            var declaration = ""
            if target.hasPrefix("var"), target.count > 3,
               !isIdentifierCharacter(Array(target)[3]) {
                target = String(target.dropFirst(3)).trimmingCharacters(in: .whitespacesAndNewlines)
                guard !target.isEmpty else { return nil }
                declaration = ", \(target)"
            }
            guard !target.isEmpty else { return nil }
            counter += 1
            let enumerator = "__wmpEn\(counter)"
            return "for (var \(enumerator) = __wmpEnum(\(object))\(declaration); "
                + "\(enumerator).next() ? ((\(target) = \(enumerator).key), true) : false; )"
        }
    }
}
