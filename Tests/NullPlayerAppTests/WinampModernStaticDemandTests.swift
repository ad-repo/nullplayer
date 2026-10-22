import XCTest
@testable import NullPlayer

/// B168: the MAKI half of the static feature index (`corpus-runner-plan.md` S2). Every method each
/// skin's programs declare, class-qualified, marked against the runtime's own `signature(for:)`.
/// Parse-only: the runtime is built — which parses every bound program — and never started, so no
/// handler runs and no path depends on what was clicked.
///
///     WINAMP_MODERN_STATIC_DEMAND=<dir[:dir…]> \
///     WINAMP_MODERN_STATIC_DEMAND_OUT=<file.tsv> \
///       swift test --filter WinampModernStaticDemandTests
///
/// `scripts/wal_feature_index.sh` runs this and joins it with the XML scan into `features.tsv`.
/// Rows are `file, kind, feature, implemented`, written straight to the file: a corpus run on the
/// shared stdout loses lines (B166).
final class WinampModernStaticDemandTests: XCTestCase {

    func testEmitsStaticMakiDemand() throws {
        let env = ProcessInfo.processInfo.environment
        guard let list = env["WINAMP_MODERN_STATIC_DEMAND"], let out = env["WINAMP_MODERN_STATIC_DEMAND_OUT"] else {
            throw XCTSkip("Set WINAMP_MODERN_STATIC_DEMAND and WINAMP_MODERN_STATIC_DEMAND_OUT.")
        }
        let wals = WinampModernCorpusPaths.archives(in: list)
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
        var rows: [String] = []
        for wal in wals {
            let file = wal.lastPathComponent
            do {
                rows += try Self.demand(of: wal).map { "\(file)\t\($0)" }
                rows.append("\(file)\tload\tok\t-")
            } catch {
                // A skin that will not load is still a row, so nothing is skipped silently.
                rows.append("\(file)\tload\tfailed\t-")
            }
        }
        try (rows.joined(separator: "\n") + "\n").write(toFile: out, atomically: true, encoding: .utf8)
    }

    /// `maki-call` for a method an instruction invokes, `maki-event` for one only a binding names (a
    /// handler the host dispatches, which `signature(for:)` does not answer for). `<guid>.<name>`,
    /// with `-` for a pre-5.0 program that carries no class table.
    private static func demand(of wal: URL) throws -> Set<String> {
        let loaded = try WinampModernSkinLoader(engineStore: .shared).load(from: wal)
        defer { loaded.teardown() }
        let runtime = try WinampModernScriptRuntime(loadedSkin: loaded, host: WinampModernStubHost())
        defer { runtime.teardown() }
        // The bound programs (the engine's too, for a cPro skin) plus every `.maki` the archive ships.
        // The second half is not redundant: a `<script>` inside a `<groupdef>` binds only when
        // something instantiates the group at run time — Hal's Eye's `scripts/manual.maki` — and
        // those are the paths nobody clicked. One that will not parse is dropped, as the runtime does.
        let shipped = loaded.archive.resourcePaths
            .filter { $0.lowercased().hasSuffix(".maki") }
            .compactMap { path in
                try? MakiBytecodeParser().parse(loaded.archive.data(for: path), source: WalSourceLocation(path: path))
            }
        var rows: Set<String> = []
        for program in runtime.programs + shipped {
            let called = Set(program.instructions.compactMap { instruction -> Int? in
                guard case .method(let index) = instruction.argument else { return nil }
                return index
            })
            let bound = Set(program.bindings.map(\.methodIndex))
            for (index, method) in program.methods.enumerated() {
                let rawGUID = program.classes.indices.contains(method.classIndex) ? program.classes[method.classIndex] : nil
                let feature = "\(rawGUID.map(MakiClassGUID.canonical) ?? "-").\(method.name.lowercased())"
                if called.contains(index) {
                    let implemented = runtime.signature(for: method.name, classGUID: rawGUID) != nil
                    rows.insert("maki-call\t\(feature)\t\(implemented ? "yes" : "no")")
                } else if bound.contains(index) {
                    rows.insert("maki-event\t\(feature)\t-")
                }
            }
        }
        return rows
    }
}
