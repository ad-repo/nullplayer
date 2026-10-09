import Foundation
import XCTest
@testable import NullPlayer

/// The load gate over the installed corpus, on by default; skips only when no corpus is installed.
/// `AUDION_CORPUS_PATH` overrides `~/Library/Application Support/NullPlayer/AudionFaces`.
///
/// A ratchet against `Fixtures/AudionFace/corpus-baseline.tsv`, keyed by `AudionFaceHarness.digest`, as
/// `WMPCorpusLoadTests` is: a face recorded `ok` that now fails is a regression and fails the suite;
/// one recorded `failed` that now loads is progress, reported for a re-record; an unrecorded face
/// never fails the build. Re-record with `scripts/audion_corpus_baseline.py` only after improving
/// the loader.
final class AudionFaceCorpusLoadTests: XCTestCase {
    func testNoFaceThatUsedToLoadStoppedLoading() async throws {
        let faces = try Self.installedFaces()
        let baseline = try Self.baseline()
        let outcomes = try await withThrowingTaskGroup(of: (String, String, AudionFaceFinding?).self) { group in
            for folder in faces {
                group.addTask {
                    let digest = try AudionFaceHarness.digest(of: folder)
                    do {
                        _ = try await AudionFaceLoader.load(folder: folder)
                        return (folder.lastPathComponent, digest, nil)
                    } catch let finding as AudionFaceFinding {
                        return (folder.lastPathComponent, digest, finding)
                    }
                }
            }
            return try await group.reduce(into: []) { $0.append($1) }
        }

        var regressions: [String] = [], improvements: [String] = []
        for (name, digest, finding) in outcomes {
            switch (baseline[digest], finding) {
            case ("ok", let finding?): regressions.append("\(name): \(finding)")
            case ("failed", nil): improvements.append(name)
            default: break
            }
        }
        let rejected = outcomes.filter { $0.2 != nil }.count
        print("Audion corpus: \(outcomes.count - rejected)/\(outcomes.count) loaded, \(rejected) rejected, "
            + "\(outcomes.filter { baseline[$0.1] == nil }.count) unranked")
        if !improvements.isEmpty {
            print("Audion corpus: \(improvements.count) face(s) recorded as failing now load — re-record with "
                + "scripts/audion_corpus_baseline.py: " + improvements.sorted().joined(separator: ", "))
        }
        XCTAssertTrue(regressions.isEmpty, "\(regressions.count) face(s) the baseline records as loading were "
            + "rejected:\n" + regressions.sorted().joined(separator: "\n"))
    }

    static func baseline() throws -> [String: String] {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("Fixtures/AudionFace/corpus-baseline.tsv")
        var outcomes: [String: String] = [:]
        for line in try String(contentsOf: url, encoding: .utf8).split(separator: "\n") where !line.hasPrefix("#") {
            let fields = line.split(separator: "\t", omittingEmptySubsequences: false)
            if fields.count >= 2 { outcomes[String(fields[0])] = String(fields[1]) }
        }
        XCTAssertFalse(outcomes.isEmpty, "corpus-baseline.tsv parsed to nothing")
        return outcomes
    }

    static func installedFaces() throws -> [URL] {
        let root = ProcessInfo.processInfo.environment["AUDION_CORPUS_PATH"]
            .map { URL(fileURLWithPath: $0, isDirectory: true) }
            ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("NullPlayer/AudionFaces", isDirectory: true)
        guard FileManager.default.fileExists(atPath: root.path) else {
            throw XCTSkip("No installed Audion corpus. Install faces, or set AUDION_CORPUS_PATH.")
        }
        let faces = AudionFaceProbe.faces(at: root.path)
        guard !faces.isEmpty else { throw XCTSkip("No faces under \(root.path).") }
        return faces
    }
}
