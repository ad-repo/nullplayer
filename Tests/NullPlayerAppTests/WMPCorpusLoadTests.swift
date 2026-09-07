import XCTest
@testable import NullPlayer

/// **The load gate, on by default.**
///
/// Every other real-skin WMP test is opt-in behind an environment variable, which is how the engine
/// arrived at a state where 4 of 14 installed archives were rejected and `swift test` reported green
/// the whole way. Structural cleanliness over synthetic fixtures measures nothing; the corpus is the
/// only denominator that means anything.
///
/// So this reads the **installed** corpus — the same
/// `~/Library/Application Support/NullPlayer/WMPSkins` directory `WMPSkinImporter` writes to, matching
/// the `.wal` convention that skins live outside the repo and only per-skin notes are committed — and
/// skips *only* when that directory is absent or empty. `WMP_CORPUS_PATH` overrides it.
///
/// The assertion is deliberately whole-corpus rather than per-skin: a rejection here is a loader bug
/// until proven otherwise, and the failure message names every archive and its diagnostic so the
/// ranked list arrives without a second run.
final class WMPCorpusLoadTests: XCTestCase {
    func testEveryInstalledArchiveLoads() async throws {
        let archives = try Self.installedArchives()
        var failures: [String] = []
        var loaded = 0
        var warnings: [String: Int] = [:]

        for url in archives {
            do {
                let skin = try await WMPSkinLoader().load(from: url)
                loaded += 1
                for diagnostic in skin.diagnostics where diagnostic.severity == .warning {
                    warnings[diagnostic.code.rawValue, default: 0] += 1
                }
            } catch let failure as WMPFailure {
                failures.append("\(url.lastPathComponent): "
                    + failure.diagnostics.map(\.description).joined(separator: "; "))
            } catch {
                failures.append("\(url.lastPathComponent): untyped error \(error)")
            }
        }

        // The tally is evidence for the next phase, not decoration: a duplicate-attribute or
        // unclosed-tag warning is a skin the old parser rejected outright.
        print("WMP corpus: \(loaded)/\(archives.count) loaded; warnings by code "
            + (warnings.isEmpty ? "none"
               : warnings.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }
                   .joined(separator: ", ")))
        XCTAssertTrue(failures.isEmpty,
                      "\(failures.count) of \(archives.count) archives were rejected:\n"
                        + failures.joined(separator: "\n"))
    }

    /// A skin the loader accepts must also survive being read twice with identical results. The
    /// deterministic dump is what a render sweep diffs against, so a parser that is order-dependent
    /// would make every later comparison meaningless rather than merely wrong.
    func testLoadingIsDeterministic() async throws {
        for url in try Self.installedArchives() {
            guard let first = try? await WMPSkinLoader().load(from: url) else { continue }
            let second = try await WMPSkinLoader().load(from: url)
            XCTAssertEqual(first.deterministicGraphDump, second.deterministicGraphDump,
                           "\(url.lastPathComponent) did not parse identically twice")
        }
    }

    static func installedArchives() throws -> [URL] {
        let fileManager = FileManager.default
        let root = ProcessInfo.processInfo.environment["WMP_CORPUS_PATH"]
            .map { URL(fileURLWithPath: $0, isDirectory: true) }
            ?? fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
                .appendingPathComponent("NullPlayer", isDirectory: true)
                .appendingPathComponent("WMPSkins", isDirectory: true)
        guard let root, fileManager.fileExists(atPath: root.path) else {
            throw XCTSkip("No installed WMP corpus. Install .wmz skins, or set WMP_CORPUS_PATH.")
        }
        // The enumeration rule: every case spelling, files only, and the count is measured rather
        // than asserted — the corpus moves, and a frozen number goes wrong in a way that looks right.
        let archives = try fileManager.contentsOfDirectory(
            at: root, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles])
            .filter {
                $0.pathExtension.caseInsensitiveCompare("wmz") == .orderedSame
                    && (try? $0.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true
            }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        guard !archives.isEmpty else { throw XCTSkip("No .wmz archives under \(root.path).") }
        return archives
    }
}
