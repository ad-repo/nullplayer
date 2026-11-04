import Foundation

/// An INI file as AIMP writes them: `main.ini` (AIMP 3.0 and AIMP 2 skins) and `.lng` language files,
/// UTF-16, `[Section]` headers over `key=value` lines. Read once per file; every reader of one goes
/// through this, so they agree on what a line means.
///
/// - A line splits at its first `=`: the key is trimmed, and the value keeps the spaces it starts
///   with (`Template= / %S`: Splash's separator is spaced off the bitrate) but not those it ends with
///   (`writtenLines` keeps those). A line with no `=` that is no header is ignored; lines before the
///   first header belong to a section "".
/// - Sections and keys are found without regard to case, as Delphi's INI files are (AIMP 2's
///   version-2 `main.ini` spells `PLAYBTN`, `Volumebar`), the first one of a name winning; a header
///   repeated later carries on its section.
/// - Sections and each section's lines keep their file order: AIMP 2's objects stack in section order.
///
/// Not `SoniqueSkinINI`: that one is Sonique's, and families do not share readers
/// (`skin-subsystem-blueprint` § *Isolation*); sharing it would make an AIMP fix a change to Sonique.
struct AIMPSkinINI: Sendable {
    struct Section: Sendable {
        /// As the file first spells it.
        let name: String
        /// Every `key=value` line, in file order, duplicates included.
        fileprivate(set) var lines: [(key: String, value: String)] = []
        /// The same lines with each value as written, the spaces it ends with kept: a language
        /// file's captions, where a trailing space is part of the text (Euphoria Lux's centred
        /// "Bookmarks ").
        fileprivate(set) var writtenLines: [(key: String, value: String)] = []
        /// Lowercased key to its first value.
        private var first: [String: String] = [:]

        fileprivate init(name: String) { self.name = name }

        fileprivate mutating func append(_ key: String, written: Substring) {
            let value = String(written.reversed().drop { $0.isWhitespace && !$0.isNewline }.reversed())
            lines.append((key, value))
            writtenLines.append((key, String(written)))
            let lower = key.lowercased()
            if first[lower] == nil { first[lower] = value }
        }

        subscript(key: String) -> String? { first[key.lowercased()] }
    }

    /// In file order.
    private(set) var sections: [Section] = []
    private var index: [String: Int] = [:]

    init(_ text: String) {
        var current: Int?
        for raw in text.components(separatedBy: .newlines) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("["), line.hasSuffix("]"), line.count >= 2 {
                current = section(named: String(line.dropFirst().dropLast()).trimmingCharacters(in: .whitespaces))
            } else if let equals = line.firstIndex(of: "=") {
                let at = current ?? section(named: "")
                current = at
                sections[at].append(String(line[..<equals]).trimmingCharacters(in: .whitespaces),
                                    written: raw[raw.index(after: raw.firstIndex(of: "=")!)...])
            }
        }
    }

    /// An entry's UTF-16 text (a byte-order mark, or little-endian without one).
    init(utf16 data: Data, name: String) throws {
        guard let text = String(data: data, encoding: .utf16) else {
            throw AIMPSkinFinding(.entryUnreadable, "\(name) is not UTF-16 text.")
        }
        self.init(text)
    }

    subscript(section: String) -> Section? { index[section.lowercased()].map { sections[$0] } }

    /// `section`'s `key`, nil when either is missing.
    subscript(section: String, key: String) -> String? { self[section]?[key] }

    private mutating func section(named name: String) -> Int {
        let lower = name.lowercased()
        if let at = index[lower] { return at }
        sections.append(Section(name: name))
        index[lower] = sections.count - 1
        return sections.count - 1
    }
}
