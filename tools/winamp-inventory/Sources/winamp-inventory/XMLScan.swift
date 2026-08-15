import Foundation

struct Located {
    let file: String    // path relative to the winamp root
    let line: Int
}

struct GroupDef { let id: String?; let xuitag: String?; let inherit: String?; let embed: String?; let at: Located }
struct ContainerDef { let id: String?; let name: String?; let at: Located }
struct LayoutDef { let id: String?; let at: Located }
struct WindowHolder { let id: String?; let hold: String; let at: Located }
struct ScriptRef { let file: String; let param: String?; let at: Located }
struct Resource { let kind: String; let id: String?; let file: String?; let at: Located }

/// Accumulated inventory across the whole expanded include graph.
final class Inventory {
    var groupDefs: [GroupDef] = []
    var containers: [ContainerDef] = []
    var layouts: [LayoutDef] = []
    var windowHolders: [WindowHolder] = []
    var scripts: [ScriptRef] = []
    var resources: [Resource] = []
    var elementHistogram: [String: Int] = [:]
    var xuitagUsage: [String: Int] = [:]    // tag name -> times instantiated
    var visitedFiles: [String] = []
    var missingIncludes: [(String, Located)] = []
    var includeCycles: [(String, Located)] = []
}

/// A lenient start-tag tokenizer. Wasabi XML is frequently not well-formed by strict
/// XML rules (multiple roots, unescaped `&`), so we scan for `<tag attr="...">` tokens
/// directly rather than using a validating parser. Good enough for inventory.
struct TagTokenizer {
    let text: [Character]
    init(_ s: String) { text = Array(s) }

    struct Tag { let name: String; let attrs: [String: String]; let line: Int }

    func tags() -> [Tag] {
        var out: [Tag] = []
        var i = 0
        var line = 1
        let n = text.count
        while i < n {
            let c = text[i]
            if c == "\n" { line += 1; i += 1; continue }
            if c == "<" {
                // Skip comments and declarations.
                if match(i, "<!--") {
                    let (ni, nl) = skipUntil(i + 4, "-->", line); i = ni; line = nl; continue
                }
                if i + 1 < n && (text[i+1] == "?" || text[i+1] == "!") {
                    let (ni, nl) = skipUntil(i + 1, ">", line); i = ni; line = nl; continue
                }
                if i + 1 < n && text[i+1] == "/" {   // closing tag
                    let (ni, nl) = skipUntil(i + 1, ">", line); i = ni; line = nl; continue
                }
                if let (tag, ni, nl) = parseStartTag(i, line) {
                    out.append(tag); i = ni; line = nl; continue
                }
            }
            i += 1
        }
        return out
    }

    private func match(_ i: Int, _ s: String) -> Bool {
        let a = Array(s)
        guard i + a.count <= text.count else { return false }
        for k in 0..<a.count where text[i + k] != a[k] { return false }
        return true
    }

    private func skipUntil(_ start: Int, _ delim: String, _ line: Int) -> (Int, Int) {
        var i = start, l = line
        let d = Array(delim)
        while i < text.count {
            if text[i] == "\n" { l += 1 }
            if i + d.count <= text.count {
                var ok = true
                for k in 0..<d.count where text[i + k] != d[k] { ok = false; break }
                if ok { return (i + d.count, l) }
            }
            i += 1
        }
        return (text.count, l)
    }

    private func parseStartTag(_ start: Int, _ startLine: Int) -> (Tag, Int, Int)? {
        var i = start + 1
        var line = startLine
        var name = ""
        while i < text.count, !text[i].isWhitespace, text[i] != ">", text[i] != "/" {
            name.append(text[i]); i += 1
        }
        if name.isEmpty { return nil }
        var attrs: [String: String] = [:]
        while i < text.count, text[i] != ">" {
            if text[i] == "\n" { line += 1 }
            if text[i].isWhitespace || text[i] == "/" { i += 1; continue }
            // attribute name
            var an = ""
            while i < text.count, text[i] != "=", !text[i].isWhitespace, text[i] != ">", text[i] != "/" {
                an.append(text[i]); i += 1
            }
            while i < text.count, text[i].isWhitespace { if text[i] == "\n" { line += 1 }; i += 1 }
            var av = ""
            if i < text.count, text[i] == "=" {
                i += 1
                while i < text.count, text[i].isWhitespace { if text[i] == "\n" { line += 1 }; i += 1 }
                if i < text.count, text[i] == "\"" || text[i] == "'" {
                    let q = text[i]; i += 1
                    while i < text.count, text[i] != q {
                        if text[i] == "\n" { line += 1 }
                        av.append(text[i]); i += 1
                    }
                    if i < text.count { i += 1 }
                }
            }
            if !an.isEmpty { attrs[an.lowercased()] = av }
        }
        if i < text.count { i += 1 }   // consume '>'
        return (Tag(name: name, attrs: attrs, line: line), i, line)
    }
}

/// Walks the include graph starting at a skin's `skin.xml`, expanding includes via
/// the VFS (globs + backslashes + variables), detecting cycles, and populating an
/// `Inventory`.
final class InventoryWalker {
    let vfs: VFS
    let inv = Inventory()
    private var onStack = Set<String>()
    private var done = Set<String>()

    init(vfs: VFS) { self.vfs = vfs }

    private func rel(_ url: URL) -> String {
        String(url.path.dropFirst(vfs.root.path.count))
    }

    func walk(_ url: URL) {
        let key = url.standardizedFileURL.path
        if onStack.contains(key) { return }        // cycle guard (caller records it)
        if done.contains(key) { return }
        onStack.insert(key); defer { onStack.remove(key) }
        done.insert(key)

        let text: String
        if let t = try? String(contentsOf: url, encoding: .utf8) { text = t }
        else if let t = try? String(contentsOf: url, encoding: .isoLatin1) { text = t }
        else { return }
        let relPath = rel(url)
        inv.visitedFiles.append(relPath)
        let dir = url.deletingLastPathComponent()

        for tag in TagTokenizer(text).tags() {
            let at = Located(file: relPath, line: tag.line)
            let name = tag.name
            inv.elementHistogram[name, default: 0] += 1
            let lname = name.lowercased()

            switch lname {
            case "include", "elementinclude":
                guard let file = tag.attrs["file"] else { break }
                let targets = vfs.expandGlob(file, relativeTo: dir)
                if targets.isEmpty { inv.missingIncludes.append((file, at)) }
                for t in targets {
                    if onStack.contains(t.standardizedFileURL.path) {
                        inv.includeCycles.append((rel(t), at))
                    } else {
                        walk(t)
                    }
                }
            case "script":
                if let f = tag.attrs["file"] {
                    inv.scripts.append(ScriptRef(file: f, param: tag.attrs["param"], at: at))
                }
            case "groupdef":
                inv.groupDefs.append(GroupDef(id: tag.attrs["id"], xuitag: tag.attrs["xuitag"],
                    inherit: tag.attrs["inherit_group"], embed: tag.attrs["embed_xui"], at: at))
            case "container":
                inv.containers.append(ContainerDef(id: tag.attrs["id"], name: tag.attrs["name"], at: at))
            case "layout":
                inv.layouts.append(LayoutDef(id: tag.attrs["id"], at: at))
            case "windowholder":
                inv.windowHolders.append(WindowHolder(id: tag.attrs["id"],
                    hold: tag.attrs["hold"] ?? "?", at: at))
            case "componentbucket":
                inv.windowHolders.append(WindowHolder(id: tag.attrs["id"],
                    hold: "componentbucket:" + (tag.attrs["wndtype"] ?? "?"), at: at))
            case "bitmap":
                inv.resources.append(Resource(kind: "bitmap", id: tag.attrs["id"], file: tag.attrs["file"], at: at))
            case "truetypefont", "bitmapfont":
                inv.resources.append(Resource(kind: lname, id: tag.attrs["id"], file: tag.attrs["file"], at: at))
            case "color", "gammagroup", "gammaset":
                inv.resources.append(Resource(kind: lname, id: tag.attrs["id"], file: nil, at: at))
            default:
                // Instantiations of a custom XUI tag (e.g. <PlaylistPro/>, <Cpro:Tabs/>).
                if name.contains(":") || name.first?.isUppercase == true {
                    inv.xuitagUsage[name, default: 0] += 1
                }
            }
        }
    }
}
