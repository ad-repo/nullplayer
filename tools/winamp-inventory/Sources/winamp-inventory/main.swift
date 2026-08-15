import Foundation

// THROWAWAY Phase-0B inventory harness. Usage:
//   winamp-inventory --wal <skin.wal> --engine <.../ClassicPro/engine> [--out <dir>]
// Opens the .wal as a bounded archive, mounts skin + engine into a synthetic Winamp
// root, expands the include graph, and dumps an XML + MAKI compatibility inventory.

func arg(_ flag: String) -> String? {
    guard let i = CommandLine.arguments.firstIndex(of: flag), i + 1 < CommandLine.arguments.count
    else { return nil }
    return CommandLine.arguments[i + 1]
}

guard let walPath = arg("--wal"), let enginePath = arg("--engine") else {
    FileHandle.standardError.write(Data("usage: winamp-inventory --wal <skin.wal> --engine <engineDir> [--out <dir>]\n".utf8))
    exit(2)
}
let walURL = URL(fileURLWithPath: walPath)
let engineSrc = URL(fileURLWithPath: enginePath)
let skinName = walURL.deletingPathExtension().lastPathComponent
let fm = FileManager.default

func fail(_ m: String) -> Never {
    FileHandle.standardError.write(Data("ERROR: \(m)\n".utf8)); exit(1)
}

var report = ""
func out(_ s: String = "") { report += s + "\n"; print(s) }

out("# Winamp Modern .wal inventory — \(skinName)")
out("_generated \(ISO8601DateFormatter().string(from: Date()))_\n")

// --- 1. Bounded archive open --------------------------------------------------
let zip: BoundedZip
do { zip = try BoundedZip(url: walURL) }
catch { fail("archive open failed: \(error)") }
let totalUncompressed = zip.entries.reduce(0) { $0 + $1.uncompressedSize }
out("## 1. Bounded archive")
out("- entries: **\(zip.entries.count)** (cap \(zip.limits.maxEntries))")
out("- total uncompressed: **\(totalUncompressed / 1024) KB** (cap \(zip.limits.maxTotalUncompressed / 1024 / 1024) MB)")
let byExt = Dictionary(grouping: zip.entries) { ($0.name as NSString).pathExtension.lowercased() }
    .mapValues { $0.count }.sorted { $0.value > $1.value }
out("- entry types: " + byExt.prefix(12).map { "\($0.key.isEmpty ? "(none)" : $0.key)×\($0.value)" }.joined(separator: ", "))
out("")

// --- 2. Mount skin + engine into a synthetic Winamp root ----------------------
let rootURL = fm.temporaryDirectory.appendingPathComponent("winamp-inv-\(UUID().uuidString)")
let skinDest = rootURL.appendingPathComponent("Skins/\(skinName)")
let engineMount = rootURL.appendingPathComponent("Plugins/classicPro/engine")
try? fm.createDirectory(at: skinDest, withIntermediateDirectories: true)
try? fm.createDirectory(at: engineMount.deletingLastPathComponent(), withIntermediateDirectories: true)
do { try fm.createSymbolicLink(at: engineMount, withDestinationURL: engineSrc) }
catch { fail("engine mount failed: \(error)") }

for entry in zip.entries {
    guard let data = try? zip.read(entry) else { continue }
    let dest = skinDest.appendingPathComponent(entry.name.replacingOccurrences(of: "\\", with: "/"))
    try? fm.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
    try? data.write(to: dest)
}

// Locate skin.xml (root or one nested dir).
func findSkinXML() -> URL? {
    let direct = skinDest.appendingPathComponent("skin.xml")
    if fm.fileExists(atPath: direct.path) { return direct }
    if let kids = try? fm.contentsOfDirectory(at: skinDest, includingPropertiesForKeys: [.isDirectoryKey]) {
        for k in kids {
            let nested = k.appendingPathComponent("skin.xml")
            if fm.fileExists(atPath: nested.path) { return nested }
        }
    }
    return nil
}
guard let skinXML = findSkinXML() else { fail("skin.xml not found in archive") }
out("## 2. Mount")
out("- synthetic root: `\(rootURL.path)`")
out("- skin.xml: `\(String(skinXML.path.dropFirst(rootURL.path.count)))`")
out("- engine mounted at `/Plugins/classicPro/engine` → `\(engineSrc.path)`")
out("")

// --- 3. Expand include graph + XML inventory ----------------------------------
let vfs = VFS(root: rootURL, skinName: skinName, engineDir: engineMount)
let walker = InventoryWalker(vfs: vfs)
walker.walk(skinXML)
let inv = walker.inv

out("## 3. XML include graph + inventory")
out("- files visited (include-expanded): **\(inv.visitedFiles.count)**")
out("- `@VAR@` tokens resolved: " + (vfs.seenVars.sorted().map { "@\($0)@" }.joined(separator: ", ")))
if !vfs.unresolvedVars.isEmpty { out("- ⚠️ unresolved vars: " + vfs.unresolvedVars.sorted().joined(separator: ", ")) }
out("- groupdefs: **\(inv.groupDefs.count)** (xuitag registrations: **\(inv.groupDefs.filter { $0.xuitag != nil }.count)**)")
out("- containers: **\(inv.containers.count)**, layouts: **\(inv.layouts.count)**")
out("- windowholders / component buckets: **\(inv.windowHolders.count)**")
out("- scripts attached: **\(inv.scripts.count)**")
out("- resources: bitmaps=\(inv.resources.filter{$0.kind=="bitmap"}.count), " +
    "fonts=\(inv.resources.filter{$0.kind.contains("font")}.count), " +
    "colors=\(inv.resources.filter{$0.kind=="color"}.count), " +
    "gamma=\(inv.resources.filter{$0.kind.contains("gamma")}.count)")
if !inv.missingIncludes.isEmpty { out("- ⚠️ unresolved includes: \(inv.missingIncludes.count)") }
if !inv.includeCycles.isEmpty { out("- ⚠️ include cycles detected: \(inv.includeCycles.count)") }
out("")

out("### Custom XUI class registrations (`groupdef xuitag=`)")
out("| xuitag | groupdef id | inherit | embed_xui | source |")
out("|---|---|---|---|---|")
for g in inv.groupDefs where g.xuitag != nil {
    out("| `\(g.xuitag!)` | \(g.id ?? "-") | \(g.inherit ?? "-") | \(g.embed ?? "-") | \(g.at.file):\(g.at.line) |")
}
out("")

out("### Component hosting surfaces (windowholders / buckets → native GUIDs)")
out("| id | holds | source |")
out("|---|---|---|")
for w in inv.windowHolders {
    out("| \(w.id ?? "-") | `\(w.hold)` | \(w.at.file):\(w.at.line) |")
}
out("")

out("### Containers / layouts (top-level windows)")
if inv.containers.isEmpty { out("_none — single-UI (SUI) skin; surfaces are embedded, not separate windows_") }
for c in inv.containers { out("- container `\(c.id ?? "?")` name=\(c.name ?? "-") — \(c.at.file):\(c.at.line)") }
out("")

// --- 4. MAKI corpus inventory -------------------------------------------------
out("## 4. MAKI corpus inventory")
var makiURLs: [URL] = []
if let en = fm.enumerator(at: engineSrc, includingPropertiesForKeys: nil) {
    for case let u as URL in en where u.pathExtension.lowercased() == "maki" { makiURLs.append(u) }
}
if let en = fm.enumerator(at: skinDest, includingPropertiesForKeys: nil) {
    for case let u as URL in en where u.pathExtension.lowercased() == "maki" { makiURLs.append(u) }
}
var methodFreq: [String: Int] = [:]
var allGuids = Set<String>()
var validCount = 0, invalidCount = 0
var versions = Set<String>()
for u in makiURLs.sorted(by: { $0.path < $1.path }) {
    let base = u.path.hasPrefix(engineSrc.path) ? engineSrc.path : skinDest.path
    let mi = Maki.parse(u, relRoot: base)
    if mi.valid { validCount += 1; versions.insert(mi.version) } else { invalidCount += 1; continue }
    for m in mi.methodNames { methodFreq[m, default: 0] += 1 }
    allGuids.formUnion(mi.distinctGuids)
}
out("- `.maki` files parsed: **\(validCount)** valid, \(invalidCount) invalid")
out("- header versions seen: \(versions.sorted().joined(separator: ", "))")
out("- distinct imported class GUIDs across corpus: **\(allGuids.count)**")
out("- distinct API method names referenced: **\(methodFreq.count)**")
out("")
out("### Top 40 MAKI API methods (by files referencing them)")
out("| method | files | method | files |")
out("|---|--:|---|--:|")
let top = methodFreq.sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }.prefix(40)
let topArr = Array(top)
for r in stride(from: 0, to: topArr.count, by: 2) {
    let a = topArr[r]
    let b = r + 1 < topArr.count ? topArr[r + 1] : nil
    out("| `\(a.key)` | \(a.value) | " + (b.map { "`\($0.key)` | \($0.value)" } ?? " | ") + " |")
}
out("")

// --- write report -------------------------------------------------------------
if let outDir = arg("--out") {
    let dir = URL(fileURLWithPath: outDir)
    try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
    let f = dir.appendingPathComponent("inventory-\(skinName).md")
    try? report.write(to: f, atomically: true, encoding: .utf8)
    FileHandle.standardError.write(Data("\nreport written: \(f.path)\n".utf8))
}

// cleanup synthetic root
try? fm.removeItem(at: rootURL)
