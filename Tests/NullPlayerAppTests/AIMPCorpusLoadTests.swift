import CryptoKit
import Foundation
import XCTest
@testable import NullPlayer

/// **The load gate, on by default**, as `WMPCorpusLoadTests` is for `.wmz`.
///
/// Reads the **installed** corpus, `~/Library/Application Support/NullPlayer/AIMPSkins` (where
/// `AIMPSkinImporter` writes), or `AIMP_CORPUS_PATH`, and skips only when it is absent or empty.
///
/// **A ratchet, not an absolute**, against `Fixtures/AIMPSkin/corpus-baseline.tsv`, keyed by sha256:
///
///   * recorded `ok`, now rejected: a **regression**, and the suite fails naming it;
///   * recorded `failed`, now loading: progress; the suite passes and asks you to re-record;
///   * a skin whose scripts that run fall below the recorded count: a regression;
///   * absent from the baseline: tallied, never fails the build (a personal corpus grows);
///   * rejected with anything but an `AIMPSkinFinding`: always a failure, ranked or not.
///
/// `AIMP_CENSUS_OUT=<file>` also writes one TSV row per skin (sha256, outcome, codes, scripts run and
/// total, format, file): the census `scripts/aimp_skin_census.sh` runs and
/// `scripts/aimp_corpus_baseline.py` records. Re-record only after *improving* the engine, never to
/// turn a red suite green.
final class AIMPCorpusLoadTests: XCTestCase {
    @MainActor func testNoSkinThatUsedToLoadStoppedLoading() throws {
        let skins = try Self.installedSkins()
        let baseline = try Self.baseline()
        var regressions: [String] = [], improvements: [String] = []
        var loaded = 0, rejected = 0, unranked = 0
        var codes: [String: Int] = [:]
        var census: [String] = []

        for url in skins {
            let digest = try Self.sha256(of: url)
            let expected = baseline[digest]
            if expected == nil { unranked += 1 }
            let row: Row
            do {
                let skin = try AIMPSkinLoader.load(contentsOf: url)
                let runs = Self.dryRun(skin)
                row = Row(outcome: .ok, codes: [], scriptsRan: runs.filter(\.ran).count, scripts: runs.count,
                          format: Self.format(url))
                loaded += 1
                if expected?.outcome == .failed { improvements.append(url.lastPathComponent) }
                if let expected, expected.outcome == .ok, row.scriptsRan < expected.scriptsRan {
                    regressions.append("\(url.lastPathComponent): scripts that run fell from "
                                       + "\(expected.scriptsRan) to \(row.scriptsRan) of \(row.scripts)")
                }
            } catch let finding as AIMPSkinFinding {
                row = Row(outcome: .failed, codes: [finding.code.rawValue], scriptsRan: 0, scripts: 0, format: Self.format(url))
                rejected += 1
                codes[finding.code.rawValue, default: 0] += 1
                if expected?.outcome == .ok { regressions.append("\(url.lastPathComponent): \(finding)") }
            } catch {
                // Every rejection owes the reader an `AIMPSkinFinding` with a diagnostic code.
                row = Row(outcome: .failed, codes: ["untyped"], scriptsRan: 0, scripts: 0, format: Self.format(url))
                rejected += 1
                regressions.append("\(url.lastPathComponent): untyped error \(error)")
            }
            census.append([digest, row.outcome.rawValue, row.codes.joined(separator: ","), String(row.scriptsRan),
                           String(row.scripts), row.format, url.lastPathComponent].joined(separator: "\t"))
        }

        print("""
        AIMP corpus: \(loaded)/\(skins.count) loaded, \(rejected) rejected, \(unranked) unranked
        AIMP corpus: rejections by code \(codes.isEmpty ? "none"
            : codes.sorted { $0.value > $1.value }.map { "\($0.key)=\($0.value)" }.joined(separator: ", "))
        """)
        if let out = ProcessInfo.processInfo.environment["AIMP_CENSUS_OUT"], !out.isEmpty {
            try (["sha256\toutcome\tcodes\tscripts_ran\tscripts\tformat\tfile"] + census)
                .joined(separator: "\n").appending("\n").write(toFile: out, atomically: true, encoding: .utf8)
            print("AIMP corpus: census written to \(out)")
        }
        if !improvements.isEmpty {
            print("AIMP corpus: \(improvements.count) skin(s) recorded as failing now load; re-record with "
                  + "scripts/aimp_corpus_baseline.py: " + improvements.sorted().joined(separator: ", "))
        }
        XCTAssertTrue(regressions.isEmpty, "\(regressions.count) regression(s):\n" + regressions.sorted().joined(separator: "\n"))
    }

    /// A skin read twice comes out the same: forms, images, scripts and the index's tables. The render
    /// sweep and the census both diff against earlier output, which an order-dependent reader would
    /// make meaningless. Over the eight smallest skins: the property is the reader's, and the whole
    /// corpus (half a gigabyte of archives, gigabytes of pixels) read twice in a debug build was most
    /// of a minute; the gate above reads every skin once.
    func testLoadingIsDeterministic() throws {
        let smallest = try Self.installedSkins().sorted {
            (try? $0.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0) ?? 0
                < (try? $1.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0) ?? 0
        }.prefix(8)
        for url in smallest {
            guard let first = try? AIMPSkinLoader.load(contentsOf: url) else { continue }
            let second = try AIMPSkinLoader.load(contentsOf: url)
            XCTAssertEqual(Self.summary(first), Self.summary(second), "\(url.lastPathComponent) did not load identically twice")
        }
    }

    private static func summary(_ skin: AIMPSkin) -> String {
        let forms = skin.allForms.map { "\($0.descendants().count)" }.joined(separator: ",")
        let index = skin.index
        return [forms, skin.images.keys.sorted().joined(separator: ","), skin.scripts.programs.keys.sorted().joined(separator: ","),
                skin.companions.map(\.name).joined(separator: ","), index.groups.keys.sorted().joined(separator: ","),
                index.timers.map(\.name).joined(separator: ","), String(index.names.expressions.count)].joined(separator: "|")
    }

    /// Every compiled script of the skin run once from a fresh state against the probe's player,
    /// and every one that did not compile as it loaded: which finish, and why each other stopped.
    @MainActor static func dryRun(_ skin: AIMPSkin) -> [(name: String, ran: Bool, why: String)] {
        let ran = skin.scripts.programs.map { name, program -> (String, Bool, String) in
            let engine = AIMPSkinScript.Engine(skin: skin, host: AIMPSkinHostState(player: .probe), state: AIMPSkinState())
            do {
                try engine.run(program)
                return (name, true, engine.actions.map(\.description).joined(separator: ","))
            } catch {
                return (name, false, "\(error)")
            }
        }
        return (ran + skin.scripts.unreadable.map { ($0.key, false, $0.value) }).sorted { $0.0 < $1.0 }
    }

    enum Outcome: String { case ok, failed }

    struct Row {
        var outcome: Outcome
        var codes: [String]
        var scriptsRan: Int
        var scripts: Int
        var format: String
    }

    static func format(_ url: URL) -> String { url.pathExtension.lowercased() }

    static func sha256(of url: URL) throws -> String {
        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    static func baseline() throws -> [String: (outcome: Outcome, scriptsRan: Int)] {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("Fixtures/AIMPSkin/corpus-baseline.tsv")
        var rows: [String: (outcome: Outcome, scriptsRan: Int)] = [:]
        for line in try String(contentsOf: url, encoding: .utf8).split(separator: "\n") where !line.hasPrefix("#") {
            let fields = line.split(separator: "\t", omittingEmptySubsequences: false)
            guard fields.count >= 4, let outcome = Outcome(rawValue: String(fields[1])) else { continue }
            rows[String(fields[0])] = (outcome, Int(fields[3]) ?? 0)
        }
        XCTAssertFalse(rows.isEmpty, "corpus-baseline.tsv parsed to nothing")
        return rows
    }

    /// `.acs3`, `.acs4`, `.acs5` in every case spelling, files only; the count is measured, never
    /// asserted.
    static func installedSkins() throws -> [URL] {
        let fileManager = FileManager.default
        let root = ProcessInfo.processInfo.environment["AIMP_CORPUS_PATH"].map { URL(fileURLWithPath: $0, isDirectory: true) }
            ?? fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
                .appendingPathComponent("NullPlayer/AIMPSkins", isDirectory: true)
        guard let root, fileManager.fileExists(atPath: root.path) else {
            throw XCTSkip("No installed AIMP corpus. Install .acs/.acs3/.acs4/.acs5 skins, or set AIMP_CORPUS_PATH.")
        }
        let skins = try fileManager.contentsOfDirectory(at: root, includingPropertiesForKeys: [.isRegularFileKey],
                                                        options: [.skipsHiddenFiles])
            .filter {
                AIMPSkinImporter.fileExtensions.contains($0.pathExtension.lowercased())
                    && (try? $0.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true
            }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        guard !skins.isEmpty else { throw XCTSkip("No AIMP skins under \(root.path).") }
        return skins
    }
}

extension AIMPSkin {
    /// The main form and every companion's.
    var allForms: [AIMPNode] { [mainForm] + companions.map(\.form) }
}
