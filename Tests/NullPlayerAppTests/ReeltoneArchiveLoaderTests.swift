import AppKit
import XCTest
import ZIPFoundation
@testable import NullPlayer

final class ReeltoneArchiveLoaderTests: XCTestCase {
    private var temporaryRoot: URL!

    override func setUpWithError() throws {
        temporaryRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("ReeltoneTests-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryRoot, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: temporaryRoot)
    }

    func testLoadsValidVersionOneAndCleansTransientDirectory() throws {
        let archiveURL = temporaryRoot.appendingPathComponent("valid.reeltone")
        try makeArchive(at: archiveURL, files: [
            "skin.json": Data(#"{"formatVersion":1,"id":"com.example.valid","name":"Valid","sprites":{"background":{"file":"art.png"}}}"#.utf8),
            "art.png": try png(width: 2, height: 3)
        ])

        var loaded: ReeltoneLoadedSkin? = try ReeltoneSkinLoader(temporaryDirectory: temporaryRoot).loadArchive(at: archiveURL)
        let extractedRoot = try XCTUnwrap(loaded?.rootURL)
        XCTAssertTrue(FileManager.default.fileExists(atPath: extractedRoot.path))
        XCTAssertEqual(loaded?.imageInfo["art.png"], ReeltoneImageInfo(width: 2, height: 3))
        loaded?.close()
        XCTAssertFalse(FileManager.default.fileExists(atPath: extractedRoot.path))
        loaded = nil
    }

    func testLoadsValidVersionTwoArchive() throws {
        let archiveURL = temporaryRoot.appendingPathComponent("valid-v2.reeltone")
        try makeArchive(at: archiveURL, files: [
            "skin.json": Data(#"{"formatVersion":2,"id":"com.example.v2","name":"V2","window":{"size":[8,4],"art":{"normal":"chassis.png"}},"regions":[]}"#.utf8),
            "chassis.png": try png(width: 8, height: 4)
        ])
        let loaded = try ReeltoneSkinLoader(temporaryDirectory: temporaryRoot).loadArchive(at: archiveURL)
        XCTAssertEqual(loaded.manifest.formatVersion, 2)
        XCTAssertEqual(loaded.manifest.window?.size, [8, 4])
        loaded.close()
    }

    func testRejectsCorruptArchive() throws {
        let archiveURL = temporaryRoot.appendingPathComponent("corrupt.reeltone")
        try Data("not a zip".utf8).write(to: archiveURL)
        try assertLoad(archiveURL, limits: .published, code: .unreadableArchive)
    }

    func testRejectsTraversalSymlinkDuplicateAndUnexpectedRootLayout() throws {
        try assertArchive(files: ["skin.json": minimalManifest, "../escape": Data()], code: .invalidArchivePath)
        try assertArchive(files: ["skin.json": minimalManifest, "/absolute": Data()], code: .invalidArchivePath)
        try assertArchive(files: ["skin.json": minimalManifest, "C:/windows": Data()], code: .invalidArchivePath)
        try assertArchive(entries: [
            ("skin.json", .file, minimalManifest),
            ("link", .symlink, Data("target".utf8))
        ], code: .symbolicLink)
        try assertArchive(entries: [
            ("skin.json", .file, minimalManifest),
            ("Art.png", .file, Data()),
            ("art.png", .file, Data())
        ], code: .duplicatePath)
        try assertArchive(files: ["folder/skin.json": minimalManifest], code: .unexpectedRootLayout)
    }

    func testRejectsEntryCountSizeAndCompressionRatioLimits() throws {
        let countURL = temporaryRoot.appendingPathComponent("count.reeltone")
        try makeArchive(at: countURL, files: ["skin.json": minimalManifest, "a": Data(), "b": Data()])
        try assertLoad(countURL, limits: .init(maximumEntryCount: 2, maximumUncompressedBytes: 1_000, maximumCompressionRatio: 1_000), code: .entryCountLimit)

        let sizeURL = temporaryRoot.appendingPathComponent("size.reeltone")
        try makeArchive(at: sizeURL, files: ["skin.json": minimalManifest])
        try assertLoad(sizeURL, limits: .init(maximumEntryCount: 10, maximumUncompressedBytes: 4, maximumCompressionRatio: 1_000), code: .uncompressedSizeLimit)

        let ratioURL = temporaryRoot.appendingPathComponent("ratio.reeltone")
        try makeArchive(at: ratioURL, files: ["skin.json": minimalManifest, "zeros": Data(repeating: 0, count: 32_768)], compression: .deflate)
        try assertLoad(ratioURL, limits: .init(maximumEntryCount: 10, maximumUncompressedBytes: 100_000, maximumCompressionRatio: 2), code: .compressionRatioLimit)
    }

    func testRejectsMissingCorruptAndOversizedImages() throws {
        try assertArchive(
            files: ["skin.json": Data(#"{"formatVersion":1,"id":"x","name":"X","sprites":{"background":{"file":"missing.png"}}}"#.utf8)],
            code: .missingResource
        )
        try assertArchive(files: [
            "skin.json": Data(#"{"formatVersion":1,"id":"x","name":"X","sprites":{"background":{"file":"bad.png"}}}"#.utf8),
            "bad.png": Data("not an image".utf8)
        ], code: .invalidImage)
        try assertArchive(files: [
            "skin.json": Data(#"{"formatVersion":1,"id":"x","name":"X","sprites":{"background":{"file":"wide.png"}}}"#.utf8),
            "wide.png": try png(width: 2_049, height: 1)
        ], code: .imageDimensionLimit)
    }

    func testRejectsDecodedImageMemoryBudgetViolation() throws {
        let image = try png(width: 2_048, height: 2_048)
        let names = (0..<5).map { "image\($0).png" }
        let sprites = names.map { #"{"component":"decoration","rect":[0,0,1,1],"art":{"normal":"\#($0)"}}"# }
            .joined(separator: ",")
        var files = Dictionary(uniqueKeysWithValues: names.map { ($0, image) })
        files["skin.json"] = Data("""
        {"formatVersion":2,"id":"x","name":"X","window":{"size":[1,1],"art":{"normal":"image0.png"}},"regions":[\(sprites)]}
        """.utf8)
        try assertArchive(files: files, code: .decodedImageMemoryLimit)
    }

    func testDirectoryLoaderRejectsSymlinkedResourceEscape() throws {
        let skinRoot = temporaryRoot.appendingPathComponent("skin", isDirectory: true)
        try FileManager.default.createDirectory(at: skinRoot, withIntermediateDirectories: true)
        try Data(#"{"formatVersion":1,"id":"x","name":"X","sprites":{"background":{"file":"art.png"}}}"#.utf8)
            .write(to: skinRoot.appendingPathComponent("skin.json"))
        let outside = temporaryRoot.appendingPathComponent("outside.png")
        try png(width: 1, height: 1).write(to: outside)
        try FileManager.default.createSymbolicLink(at: skinRoot.appendingPathComponent("art.png"), withDestinationURL: outside)

        XCTAssertThrowsError(try ReeltoneSkinLoader().loadDirectory(at: skinRoot)) {
            XCTAssertEqual(($0 as? ReeltoneDiagnostic)?.code, .invalidResourcePath)
        }
    }

    private var minimalManifest: Data { Data(#"{"formatVersion":1,"id":"x","name":"X"}"#.utf8) }

    private func assertArchive(files: [String: Data], code: ReeltoneDiagnosticCode) throws {
        let entries = files.map { ($0.key, Entry.EntryType.file, $0.value) }
        try assertArchive(entries: entries, code: code)
    }

    private func assertArchive(entries: [(String, Entry.EntryType, Data)], code: ReeltoneDiagnosticCode) throws {
        let archiveURL = temporaryRoot.appendingPathComponent(UUID().uuidString + ".reeltone")
        try makeArchive(at: archiveURL, entries: entries)
        try assertLoad(archiveURL, limits: .published, code: code)
    }

    private func assertLoad(_ url: URL, limits: ReeltoneArchiveLimits, code: ReeltoneDiagnosticCode) throws {
        XCTAssertThrowsError(try ReeltoneSkinLoader(limits: limits, temporaryDirectory: temporaryRoot).loadArchive(at: url)) {
            XCTAssertEqual(($0 as? ReeltoneDiagnostic)?.code, code, "Unexpected error: \($0)")
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: temporaryRoot.appendingPathComponent("escape").path))
    }

    private func makeArchive(at url: URL, files: [String: Data], compression: CompressionMethod = .none) throws {
        try makeArchive(at: url, entries: files.map { ($0.key, Entry.EntryType.file, $0.value) }, compression: compression)
    }

    private func makeArchive(
        at url: URL,
        entries: [(String, Entry.EntryType, Data)],
        compression: CompressionMethod = .none
    ) throws {
        let archive = try Archive(url: url, accessMode: .create)
        for (path, type, data) in entries {
            try archive.addEntry(with: path, type: type, uncompressedSize: Int64(data.count), compressionMethod: compression) { position, size in
                data.subdata(in: Int(position)..<Int(position) + size)
            }
        }
    }

    private func png(width: Int, height: Int) throws -> Data {
        guard let representation = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: width,
            pixelsHigh: height,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ), let data = representation.representation(using: .png, properties: [:]) else {
            throw CocoaError(.fileWriteUnknown)
        }
        return data
    }
}
