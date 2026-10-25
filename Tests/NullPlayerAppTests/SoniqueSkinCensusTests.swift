import CryptoKit
import XCTest
@testable import NullPlayer

// The Sonique census probe: one machine-readable line per fact, inside a `SKIN <file>` block, parsed
// by `scripts/sonique_census.sh`. It loads through `SoniqueSkinLoader`, the path the app will use.
// Every `SONIQUE_*` flag is documented once, in `skills/sonique-skin-guide/reference/harness.md`.
// Lines go through `HarnessOutput.emit`, never `print`.
final class SoniqueSkinCensusTests: XCTestCase {
    /// `SONIQUE_SKIN` is an `.sgf` file, a directory of them, or a text file listing them one per line.
    static func skins(at path: String) -> [URL] {
        let url = URL(fileURLWithPath: path)
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) else { return [] }
        if isDirectory.boolValue {
            let names = (try? FileManager.default.contentsOfDirectory(atPath: path)) ?? []
            return names.filter { $0.lowercased().hasSuffix(".sgf") }.sorted().map { url.appendingPathComponent($0) }
        }
        if path.lowercased().hasSuffix(".sgf") { return [url] }
        let list = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        return list.split(separator: "\n").map { URL(fileURLWithPath: String($0)) }
    }

    func testCensusSkinOrCorpus() throws {
        guard let path = ProcessInfo.processInfo.environment["SONIQUE_SKIN"], !path.isEmpty else {
            throw XCTSkip("Set SONIQUE_SKIN to an .sgf, a directory or a list file. "
                + "See skills/sonique-skin-guide/reference/harness.md.")
        }
        let skins = Self.skins(at: path)
        guard !skins.isEmpty else { throw XCTSkip("No .sgf under \(path).") }
        HarnessOutput.emit("HARNESS \(skins.count) skin(s) from \(path)")
        for file in skins {
            measure(file)
        }
    }

    private func measure(_ file: URL) {
        let name = file.lastPathComponent
        let skin: SoniqueSkin
        do {
            skin = try SoniqueSkinLoader.load(contentsOf: file)
        } catch {
            HarnessOutput.emit("SKIN \(name) FAILED \(error)")
            return
        }
        HarnessOutput.emit("SKIN \(name)")
        // Already loaded once within the size limit, so these reads cannot fail differently.
        let data = (try? Data(contentsOf: file)) ?? Data()
        HarnessOutput.emit("DIGEST " + SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined())
        let entries = (try? SoniqueSkinArchive.entries(in: data)) ?? []
        // The locked limits' inputs (decision record § *Measured headroom*), over every JPEG header.
        let sizes = entries.filter { $0.name.lowercased().hasPrefix("/jpeg/") }.compactMap { SoniqueSkinLoader.jpegSize($0.payload) }
        let ini = entries.last { $0.name.lowercased() == "/skin.ini" }?.payload.count ?? 0
        HarnessOutput.emit("SIZE bytes=\(data.count) entries=\(entries.count) ini=\(ini) "
            + "pixels=\(sizes.reduce(0) { $0 + $1.width * $1.height }) side=\(sizes.map { max($0.width, $0.height) }.max() ?? 0)")
        var seen: Set<String> = []
        for entry in entries where seen.insert(entry.name).inserted {
            HarnessOutput.emit("ENTRY \(entry.name)")
            if entry.name == "/skin.ini" {
                let text = String(data: entry.payload, encoding: .isoLatin1) ?? ""
                for line in text.split(whereSeparator: \.isNewline) where line.hasPrefix("[") {
                    guard let close = line.firstIndex(of: "]") else { continue }
                    HarnessOutput.emit("SECTION " + line[line.index(after: line.startIndex)..<close]
                        .trimmingCharacters(in: .whitespaces).lowercased())
                }
            }
        }
        let version = skin.ini.value("skin", "version").map { String($0.prefix { $0.isNumber }) }
        HarnessOutput.emit("VERSION " + (seen.contains("/skin.ini") ? (version.flatMap { $0.isEmpty ? nil : $0 } ?? "none") : "no-ini"))
        HarnessOutput.emit("MODES default=" + SoniqueSkin.Mode.allCases.filter(skin.defaultModes.contains).map { "\($0)" }.joined(separator: ","))
        for finding in skin.findings {
            HarnessOutput.emit("FINDING \(finding)")
        }
    }
}
