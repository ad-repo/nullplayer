import Foundation
import XCTest
import ZIPFoundation
@testable import NullPlayer

final class ReeltoneSkinStoreTests: XCTestCase {
    private var temporaryRoot: URL!
    private var storeRoot: URL!

    override func setUpWithError() throws {
        temporaryRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("ReeltoneStoreTests-" + UUID().uuidString, isDirectory: true)
        storeRoot = temporaryRoot.appendingPathComponent("store", isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryRoot, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: temporaryRoot)
    }

    func testInstallDiscoveryAndDuplicateManifestIDsUseDistinctIdentities() throws {
        let archiveA = try archive(name: "First", version: "1")
        let archiveB = try archive(name: "Second", version: "2")
        let store = ReeltoneSkinStore(rootURL: storeRoot)

        let first = try store.install(archiveAt: archiveA)
        let second = try store.install(archiveAt: archiveB)
        XCTAssertNotEqual(first.record.identity, second.record.identity)
        XCTAssertEqual(first.record.manifestID, second.record.manifestID)
        XCTAssertTrue(FileManager.default.fileExists(atPath: first.rootURL.appendingPathComponent("skin.json").path))

        let discovery = store.discover()
        XCTAssertTrue(discovery.diagnostics.isEmpty)
        XCTAssertEqual(Set(discovery.installations.map(\.record.identity)), Set([first.record.identity, second.record.identity]))
    }

    func testPreferredSelectionReplacementAndRemoval() throws {
        let suiteName = "ReeltoneSkinStoreTests-" + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = ReeltoneSkinStore(rootURL: storeRoot)
        let installed = try store.install(archiveAt: archive(name: "Before", version: "1"))

        store.selectPreferred(installed, in: defaults)
        XCTAssertEqual(store.preferredSkin(in: defaults)?.record.identity, installed.record.identity)

        let replaced = try store.replace(identity: installed.record.identity, withArchiveAt: archive(name: "After", version: "2"))
        XCTAssertEqual(replaced.record.identity, installed.record.identity)
        XCTAssertEqual(try store.load(replaced).manifest.name, "After")
        try store.remove(identity: replaced.record.identity)
        XCTAssertTrue(store.discover().installations.isEmpty)
    }

    func testFailedInstallLeavesNoPartialInstallation() throws {
        let invalid = temporaryRoot.appendingPathComponent("invalid.reeltone")
        try makeArchive(at: invalid, manifest: Data(#"{"formatVersion":1,"id":"x","name":"X","sprites":{"background":{"file":"missing.png"}}}"#.utf8))
        let store = ReeltoneSkinStore(rootURL: storeRoot)

        XCTAssertThrowsError(try store.install(archiveAt: invalid))
        XCTAssertTrue(store.discover().installations.isEmpty)
        let children = try FileManager.default.contentsOfDirectory(at: storeRoot, includingPropertiesForKeys: nil)
        XCTAssertFalse(children.contains { $0.lastPathComponent.hasPrefix(".staging-") })
    }

    private func archive(name: String, version: String) throws -> URL {
        let url = temporaryRoot.appendingPathComponent(UUID().uuidString + ".reeltone")
        let manifest = Data("""
        {"formatVersion":1,"id":"com.example.same","name":"\(name)","version":"\(version)"}
        """.utf8)
        try makeArchive(at: url, manifest: manifest)
        return url
    }

    private func makeArchive(at url: URL, manifest: Data) throws {
        let archive = try Archive(url: url, accessMode: .create)
        try archive.addEntry(with: "skin.json", type: .file, uncompressedSize: Int64(manifest.count)) { position, size in
            manifest.subdata(in: Int(position)..<Int(position) + size)
        }
    }
}
