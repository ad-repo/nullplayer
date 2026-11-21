import Foundation

/// A Windows INI file (Sonique's `/skin.ini`), read the way Win32's `GetPrivateProfileString` reads
/// it: sections and keys case-insensitive, the first section of a name is the only one consulted, and
/// the first value of a key within it wins. Values stay raw text, both ends trimmed; interpreting them
/// is the family's.
///
/// - A header is a line that starts with `[`, named up to its first `]`; one with no `]` is skipped.
/// - A line starting with `;` or `//` is a comment; one with no `=` that is no header is ignored.
/// - Lines before the first header belong to no section.
struct INIFile: Sendable {
    private var sections: [String: [String: String]] = [:]

    init(_ text: String) {
        var current: String?
        var seen: Set<String> = []
        for raw in text.split(whereSeparator: \.isNewline) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("[") {
                guard let close = line.firstIndex(of: "]") else { continue }
                let name = line[line.index(after: line.startIndex)..<close].trimmingCharacters(in: .whitespaces).lowercased()
                current = seen.insert(name).inserted ? name : nil
                continue
            }
            guard let section = current, !line.hasPrefix(";"), !line.hasPrefix("//"),
                  let equals = line.firstIndex(of: "=") else { continue }
            let key = line[..<equals].trimmingCharacters(in: .whitespaces).lowercased()
            let value = line[line.index(after: equals)...].trimmingCharacters(in: .whitespaces)
            if !key.isEmpty, sections[section, default: [:]][key] == nil {
                sections[section, default: [:]][key] = value
            }
        }
    }

    /// `section`'s `key`; nil when either is missing.
    func value(_ section: String, _ key: String) -> String? {
        sections[section.lowercased()]?[key.lowercased()]
    }
}
