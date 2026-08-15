import Foundation

/// A logical, read-only virtual filesystem over a synthetic "Winamp root". It
/// resolves the `@VAR@` path variables cPro uses, normalizes Windows backslash
/// separators, canonicalizes `.`/`..`, and performs case-insensitive lookup — the
/// Phase-0B stand-in for the production VFS (Phase 2). Escaping the root is an error.
///
/// Layout built physically in a temp dir:
///   <root>/Skins/<skin>/...                     (@SKINPATH@, @COLORTHEMESPATH@)
///   <root>/Plugins/classicPro/engine/...        (engine mount)
///
/// The one cross-mount include in cPro-Bento —
///   `@COLORTHEMESPATH@\..\..\Plugins\classicPro\engine\load.xml`
/// — resolves cleanly because @COLORTHEMESPATH@ sits two levels under the root.
final class VFS {
    let root: URL
    let skinDir: URL
    let engineDir: URL
    private var vars: [String: String] = [:]

    init(root: URL, skinName: String, engineDir: URL) {
        self.root = root
        self.skinDir = root.appendingPathComponent("Skins/\(skinName)")
        self.engineDir = engineDir
        vars["WINAMPPATH"] = root.path
        vars["SKINPATH"] = skinDir.path
        vars["COLORTHEMESPATH"] = skinDir.path      // cPro defines this == skin root
        vars["DEFAULTSKINPATH"] = root.appendingPathComponent("Skins/Default").path
    }

    /// The set of `@VAR@` tokens actually seen while resolving (for reporting).
    private(set) var seenVars = Set<String>()
    private(set) var unresolvedVars = Set<String>()

    /// Resolve a raw XML `file=`/path string (which may contain `@VARS@`, backslashes,
    /// and `..`) to an absolute logical URL, relative to `base` if it has no variable.
    /// Returns nil if it escapes the root or resolves nowhere.
    func resolve(_ raw: String, relativeTo base: URL) -> URL? {
        var s = raw.replacingOccurrences(of: "\\", with: "/")
        var absolute: String

        if let range = s.range(of: #"@[A-Z_]+@"#, options: .regularExpression) {
            let token = String(s[range]).trimmingCharacters(in: CharacterSet(charactersIn: "@"))
            seenVars.insert(token)
            guard let mapped = vars[token] else {
                unresolvedVars.insert(token)
                return nil
            }
            s.replaceSubrange(range, with: mapped)
            absolute = s
        } else if s.hasPrefix("/") {
            absolute = s
        } else {
            absolute = base.appendingPathComponent(s).path
        }

        let canon = canonicalize(absolute)
        guard canon.hasPrefix(root.path) else { return nil }   // escaped the root
        return caseInsensitiveExisting(URL(fileURLWithPath: canon))
    }

    /// Collapse `.` and `..` without touching the filesystem.
    private func canonicalize(_ path: String) -> String {
        var out: [String] = []
        for comp in path.split(separator: "/", omittingEmptySubsequences: true) {
            if comp == "." { continue }
            if comp == ".." { if !out.isEmpty { out.removeLast() }; continue }
            out.append(String(comp))
        }
        return "/" + out.joined(separator: "/")
    }

    /// Resolve a path case-insensitively component by component (real Winamp lookups
    /// are case-insensitive; our fixtures may differ in case from the XML references).
    private func caseInsensitiveExisting(_ url: URL) -> URL? {
        let fm = FileManager.default
        if fm.fileExists(atPath: url.path) { return url }
        // Walk from root matching each component case-insensitively.
        let rel = url.path.dropFirst(root.path.count)
        var cur = root
        for comp in rel.split(separator: "/", omittingEmptySubsequences: true) {
            guard let children = try? fm.contentsOfDirectory(atPath: cur.path) else { return nil }
            guard let match = children.first(where: { $0.caseInsensitiveCompare(String(comp)) == .orderedSame })
            else { return nil }
            cur = cur.appendingPathComponent(match)
        }
        return fm.fileExists(atPath: cur.path) ? cur : nil
    }

    /// Expand an include target that may contain a `*` glob in its final component.
    func expandGlob(_ raw: String, relativeTo base: URL) -> [URL] {
        guard raw.contains("*") else {
            return resolve(raw, relativeTo: base).map { [$0] } ?? []
        }
        let normalized = raw.replacingOccurrences(of: "\\", with: "/")
        let dirPart = (normalized as NSString).deletingLastPathComponent
        let pattern = (normalized as NSString).lastPathComponent
        guard let dirURL = resolve(dirPart.isEmpty ? "." : dirPart, relativeTo: base),
              let children = try? FileManager.default.contentsOfDirectory(atPath: dirURL.path)
        else { return [] }
        let regex = "^" + NSRegularExpression.escapedPattern(for: pattern)
            .replacingOccurrences(of: "\\*", with: ".*") + "$"
        return children
            .filter { $0.range(of: regex, options: [.regularExpression, .caseInsensitive]) != nil }
            .sorted()
            .map { dirURL.appendingPathComponent($0) }
    }
}
