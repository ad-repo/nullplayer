import CryptoKit
import Foundation
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
/// **It is a ratchet, not an absolute.** It first asserted that *every* installed archive loads,
/// which was right for the 14-skin corpus and became wrong the moment the corpus grew to 180: a
/// user's personal skin folder grows, and roughly one archive in nine is rejected by a bound the
/// engine deliberately enforces. A suite that is permanently red trains people to ignore it, which
/// is the same failure as a suite that is permanently green over four rejections — just louder.
///
/// So the assertion is against `Fixtures/WMPSkin/corpus-baseline.tsv`, keyed by sha256:
///
///   * recorded `ok`, now rejected — a **regression**, and the suite fails naming it;
///   * recorded `failed`, now loading — progress; the suite passes and asks you to re-record;
///   * absent from the baseline — reported in the tally and never fails the build;
///   * rejected with an **untyped** error — always a failure, ranked or not. Every rejection owes
///     the reader a `WMPFailure` with a diagnostic code.
///
/// Re-record with `scripts/wmp_corpus_baseline.py <census outdir>` only after *improving* the
/// loader — never to turn a red suite green.
final class WMPCorpusLoadTests: XCTestCase {
    func testNoArchiveThatUsedToLoadStoppedLoading() throws {
        let archives = try Self.installedArchives()
        let baseline = try Self.baseline()
        var regressions: [String] = []
        var improvements: [String] = []
        var loaded = 0, rejected = 0, unranked = 0
        var rejectionCodes: [String: Int] = [:]

        for url in archives {
            let digest = try Self.sha256(of: url)
            let outcome = Result { try Self.loadSynchronously(url) }
            let expected = baseline[digest]

            switch outcome {
            case .success:
                loaded += 1
                if expected == .failed { improvements.append(url.lastPathComponent) }
            case .failure(let error):
                rejected += 1
                let described = (error as? WMPFailure)
                    .map { $0.diagnostics.map(\.description).joined(separator: "; ") }
                    ?? "untyped error \(error)"
                for code in (error as? WMPFailure)?.diagnostics.map(\.code.rawValue) ?? [] {
                    rejectionCodes[code, default: 0] += 1
                }
                if expected == .ok {
                    regressions.append("\(url.lastPathComponent): \(described)")
                }
                // An untyped error is always a defect: every rejection must be a diagnosable
                // `WMPFailure`, whether or not the archive is one we expect to load.
                if !(error is WMPFailure) {
                    regressions.append("\(url.lastPathComponent): \(described)")
                }
            }
            if expected == nil { unranked += 1 }
        }

        print("""
        WMP corpus: \(loaded)/\(archives.count) loaded, \(rejected) rejected, \(unranked) unranked
        WMP corpus: rejections by code \
        \(rejectionCodes.isEmpty ? "none"
            : rejectionCodes.sorted { $0.value > $1.value }.map { "\($0.key)=\($0.value)" }
                .joined(separator: ", "))
        """)
        if !improvements.isEmpty {
            print("WMP corpus: \(improvements.count) archive(s) recorded as failing now load — "
                + "re-record with scripts/wmp_corpus_baseline.py: "
                + improvements.sorted().joined(separator: ", "))
        }

        XCTAssertTrue(regressions.isEmpty,
                      "\(regressions.count) archive(s) that the baseline records as loading were "
                        + "rejected:\n" + regressions.sorted().joined(separator: "\n"))
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

    enum BaselineOutcome: String { case ok, failed }

    /// The loader is `async` and this suite is not; `XCTestExpectation` per archive over 180 archives
    /// is slower than the load itself. A semaphore is the honest tool here.
    static func loadSynchronously(_ url: URL) throws -> WMPLoadedSkin {
        var result: Result<WMPLoadedSkin, Error>!
        let done = DispatchSemaphore(value: 0)
        Task {
            do { result = .success(try await WMPSkinLoader().load(from: url)) }
            catch { result = .failure(error) }
            done.signal()
        }
        done.wait()
        return try result.get()
    }

    static func sha256(of url: URL) throws -> String {
        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    static func baseline() throws -> [String: BaselineOutcome] {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/WMPSkin/corpus-baseline.tsv")
        var outcomes: [String: BaselineOutcome] = [:]
        for line in try String(contentsOf: url, encoding: .utf8).split(separator: "\n") {
            guard !line.hasPrefix("#") else { continue }
            let fields = line.split(separator: "\t", omittingEmptySubsequences: false)
            guard fields.count >= 2, let outcome = BaselineOutcome(rawValue: String(fields[1]))
            else { continue }
            outcomes[String(fields[0])] = outcome
        }
        XCTAssertFalse(outcomes.isEmpty, "corpus-baseline.tsv parsed to nothing")
        return outcomes
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
