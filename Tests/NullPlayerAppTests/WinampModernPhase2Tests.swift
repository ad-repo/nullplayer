import Foundation
import XCTest
import ZIPFoundation
@testable import NullPlayer

final class WinampModernPhase2Tests: XCTestCase {
    private struct TestEntry {
        let path: String
        let type: Entry.EntryType
        let data: Data
        let compression: CompressionMethod

        init(_ path: String, data: Data = Data(), type: Entry.EntryType = .file,
             compression: CompressionMethod = .none) {
            self.path = path
            self.type = type
            self.data = data
            self.compression = compression
        }
    }

    // MARK: - Archive validation

    func testArchiveAcceptsOneWrapperAndReadsCaseInsensitively() throws {
        let url = try makeArchive([
            TestEntry("Example/SKIN.XML", data: Data("<WasabiXML/>".utf8)),
            TestEntry("Example/Images/Background.PNG", data: Data([1, 2, 3]))
        ])
        let archive = try WalArchive(url: url)

        XCTAssertEqual(archive.rootPrefix, "Example")
        XCTAssertEqual(archive.skinXMLPath, "SKIN.XML")
        XCTAssertEqual(try archive.data(for: "images/background.png"), Data([1, 2, 3]))
        XCTAssertEqual(archive.resourcePaths, ["Images/Background.PNG", "SKIN.XML"])
    }

    func testArchiveRejectsTraversalSymlinksAndCaseCollisions() throws {
        let traversal = try makeArchive([
            TestEntry("skin.xml", data: Data("<WasabiXML/>".utf8)),
            TestEntry("../escape.txt", data: Data("bad".utf8))
        ])
        XCTAssertEqual(errorCode { try WalArchive(url: traversal) }, .unsafePath)

        let symlink = try makeArchive([
            TestEntry("skin.xml", data: Data("<WasabiXML/>".utf8)),
            TestEntry("link", data: Data("target".utf8), type: .symlink)
        ])
        XCTAssertEqual(errorCode { try WalArchive(url: symlink) }, .symbolicLink)

        let collision = try makeArchive([
            TestEntry("skin.xml", data: Data("<WasabiXML/>".utf8)),
            TestEntry("Images/a.png", data: Data([1])),
            TestEntry("images/A.PNG", data: Data([2]))
        ])
        XCTAssertEqual(errorCode { try WalArchive(url: collision) }, .caseCollision)
    }

    func testArchiveRejectsAllDeclaredLimits() throws {
        let entries = try makeArchive([
            TestEntry("skin.xml", data: Data("<WasabiXML/>".utf8)),
            TestEntry("one"), TestEntry("two")
        ])
        var entryLimits = WalArchiveLimits.production
        entryLimits.maximumEntryCount = 2
        XCTAssertEqual(errorCode { try WalArchive(url: entries, limits: entryLimits) }, .entryLimitExceeded)

        let sized = try makeArchive([
            TestEntry("skin.xml", data: Data("1234".utf8)),
            TestEntry("data.bin", data: Data("12345".utf8))
        ])
        var perEntry = WalArchiveLimits.production
        perEntry.maximumEntrySize = 4
        XCTAssertEqual(errorCode { try WalArchive(url: sized, limits: perEntry) }, .entryTooLarge)

        var total = WalArchiveLimits.production
        total.maximumEntrySize = 20
        total.maximumTotalSize = 8
        XCTAssertEqual(errorCode { try WalArchive(url: sized, limits: total) }, .totalSizeExceeded)

        let compressed = try makeArchive([
            TestEntry("skin.xml", data: Data("<WasabiXML/>".utf8)),
            TestEntry("zeros.bin", data: Data(repeating: 0, count: 8_192), compression: .deflate)
        ])
        var ratio = WalArchiveLimits.production
        ratio.maximumCompressionRatio = 2
        XCTAssertEqual(errorCode { try WalArchive(url: compressed, limits: ratio) }, .compressionRatioExceeded)
    }

    func testArchiveRejectsMissingDeepAndSplitRoots() throws {
        let missing = try makeArchive([TestEntry("other.xml", data: Data("<x/>".utf8))])
        XCTAssertEqual(errorCode { try WalArchive(url: missing) }, .invalidRoot)

        let deep = try makeArchive([TestEntry("one/two/skin.xml", data: Data("<x/>".utf8))])
        XCTAssertEqual(errorCode { try WalArchive(url: deep) }, .invalidRoot)

        let split = try makeArchive([
            TestEntry("wrapper/skin.xml", data: Data("<x/>".utf8)),
            TestEntry("outside.txt", data: Data())
        ])
        XCTAssertEqual(errorCode { try WalArchive(url: split) }, .invalidRoot)

        let corrupt = temporaryDirectory().appendingPathComponent("corrupt.wal")
        try Data("not a zip".utf8).write(to: corrupt)
        XCTAssertEqual(errorCode { try WalArchive(url: corrupt) }, .invalidArchive)
    }

    // MARK: - VFS and include expansion

    func testVFSResolvesVariablesBackslashesCrossMountsAndGlobs() throws {
        let skin = try WalMemoryResourceProvider(resources: [
            "skin.xml": Data(),
            "widgets/load/B.xml": Data("b".utf8),
            "widgets/load/a.XML": Data("a".utf8)
        ])
        let engine = try WalMemoryResourceProvider(resources: ["Load.XML": Data("engine".utf8)])
        let vfs = try WalVirtualFileSystem(skinName: "Bento", skin: skin)
        try vfs.mount(engine, at: "/Plugins/ClassicPro/engine")

        let crossMount = try vfs.resolve(
            "@COLORTHEMESPATH@\\..\\..\\Plugins\\classicpro\\engine\\load.xml",
            relativeTo: "/Skins/Bento/skin.xml"
        )
        XCTAssertEqual(crossMount.logicalPath, "/Plugins/ClassicPro/engine/Load.XML")
        XCTAssertEqual(try vfs.data(at: crossMount.logicalPath), Data("engine".utf8))

        let glob = try vfs.expand("widgets\\load\\*.xml", relativeTo: "/Skins/Bento/skin.xml")
        XCTAssertEqual(glob.map(\.logicalPath), [
            "/Skins/Bento/widgets/load/B.xml",
            "/Skins/Bento/widgets/load/a.XML"
        ].sorted())
    }

    func testVFSRejectsUnknownVariablesEscapesAndMissingResources() throws {
        let skin = try WalMemoryResourceProvider(resources: ["skin.xml": Data()])
        let vfs = try WalVirtualFileSystem(skinName: "Test", skin: skin)

        XCTAssertEqual(errorCode {
            try vfs.resolve("@UNKNOWN@/x", relativeTo: "/Skins/Test/skin.xml")
        }, .unresolvedPathVariable)
        XCTAssertEqual(errorCode {
            try vfs.resolve("../../../outside", relativeTo: "/Skins/Test/skin.xml")
        }, .resourceEscapesVFS)
        XCTAssertEqual(errorCode {
            try vfs.resolve("missing.xml", relativeTo: "/Skins/Test/skin.xml")
        }, .resourceMissing)
    }

    func testXMLIncludesAreExpandedWithSourceLocations() throws {
        let skin = try WalMemoryResourceProvider(resources: [
            "skin.xml": Data("<WasabiXML>\n<include file=\"parts/ui.xml\"/>\n</WasabiXML>".utf8),
            "parts/ui.xml": Data("<container id=\"main\"/>".utf8)
        ])
        let vfs = try WalVirtualFileSystem(skinName: "Test", skin: skin)
        let document = try WalXMLDocumentLoader(vfs: vfs).load(entryPath: "/Skins/Test/skin.xml")

        XCTAssertEqual(document.visitedPaths, ["/Skins/Test/skin.xml", "/Skins/Test/parts/ui.xml"])
        XCTAssertEqual(document.roots.first?.children.first?.name.lowercased(), "container")
        XCTAssertEqual(document.roots.first?.children.first?.location.path, "/Skins/Test/parts/ui.xml")
    }

    func testXMLIncludeCycleMissingIncludeAndExpansionLimitsFailActionably() throws {
        let cycleProvider = try WalMemoryResourceProvider(resources: [
            "skin.xml": Data("<include file=\"a.xml\"/>".utf8),
            "a.xml": Data("<include file=\"skin.xml\"/>".utf8)
        ])
        let cycleVFS = try WalVirtualFileSystem(skinName: "Cycle", skin: cycleProvider)
        XCTAssertEqual(errorCode {
            try WalXMLDocumentLoader(vfs: cycleVFS).load(entryPath: "/Skins/Cycle/skin.xml")
        }, .includeCycle)

        // A missing include is a *warning*, not a failure: Winamp carries on, and two shipped skins
        // (Itemskin, Overdrive_2) name a file their archive does not contain and would otherwise
        // not load at all. The rest of the document still expands.
        let missingProvider = try WalMemoryResourceProvider(resources: [
            "skin.xml": Data("<include file=\"missing.xml\"/><container id=\"main\"/>".utf8)
        ])
        let missingVFS = try WalVirtualFileSystem(skinName: "Missing", skin: missingProvider)
        let missingDocument = try WalXMLDocumentLoader(vfs: missingVFS)
            .load(entryPath: "/Skins/Missing/skin.xml")
        XCTAssertEqual(missingDocument.roots.map(\.name), ["container"])
        XCTAssertEqual(missingDocument.diagnostics.map(\.code), [.resourceMissing])
        XCTAssertEqual(missingDocument.diagnostics.map(\.severity), [.warning])

        let includeDepthProvider = try WalMemoryResourceProvider(resources: [
            "skin.xml": Data("<include file=\"a.xml\"/>".utf8),
            "a.xml": Data("<include file=\"b.xml\"/>".utf8),
            "b.xml": Data("<container/>".utf8)
        ])
        let includeDepthVFS = try WalVirtualFileSystem(skinName: "IncludeDepth", skin: includeDepthProvider)
        var includeDepthLimits = WalXMLLimits.production
        includeDepthLimits.maximumIncludeDepth = 1
        XCTAssertEqual(errorCode {
            try WalXMLDocumentLoader(vfs: includeDepthVFS, limits: includeDepthLimits)
                .load(entryPath: "/Skins/IncludeDepth/skin.xml")
        }, .includeDepthExceeded)

        let nodesProvider = try WalMemoryResourceProvider(resources: [
            "skin.xml": Data("<a><b><c><d/></c></b></a>".utf8)
        ])
        let nodesVFS = try WalVirtualFileSystem(skinName: "Nodes", skin: nodesProvider)
        var nodeLimits = WalXMLLimits.production
        nodeLimits.maximumExpandedNodeCount = 2
        XCTAssertEqual(errorCode {
            try WalXMLDocumentLoader(vfs: nodesVFS, limits: nodeLimits)
                .load(entryPath: "/Skins/Nodes/skin.xml")
        }, .expandedNodeLimitExceeded)

        var depthLimits = WalXMLLimits.production
        depthLimits.maximumNestingDepth = 2
        XCTAssertEqual(errorCode {
            try WalXMLDocumentLoader(vfs: nodesVFS, limits: depthLimits)
                .load(entryPath: "/Skins/Nodes/skin.xml")
        }, .xmlDepthExceeded)
    }

    // MARK: - Initialization and retained graph

    func testInitializationPassesProduceDeterministicGraphSnapshot() throws {
        let first = try makeInitializedRuntime()
        let second = try makeInitializedRuntime()

        XCTAssertEqual(first.completedPasses, [
            .resourceRegistration, .groupAndXUIRegistration, .objectCreation,
            .scriptBinding, .initialization, .firstPaint
        ])
        XCTAssertEqual(first.state, .awaitingFirstPaint)
        XCTAssertEqual(first.graph.objectCount, 5)
        XCTAssertEqual(first.graph.snapshot(), second.graph.snapshot())
        XCTAssertEqual(first.resources.definition(identifier: "background")?.logicalFile,
                       "/Skins/Synthetic/Images/BG.PNG")
        XCTAssertEqual(first.scriptBindings.count, 1)
        XCTAssertEqual(first.scriptBindings.first?.logicalPath, "/Skins/Synthetic/Scripts/Main.maki")

        let instance = try XCTUnwrap(first.graph.objects(xmlID: "instance").first)
        XCTAssertEqual(instance.attributes["x"], "4")
        XCTAssertEqual(instance.attributes["w"], "-8")
        XCTAssertEqual(instance.children.map { $0.xmlID ?? "" }, ["base.layer", "templated"])
    }

    func testProductionLoaderRunsArchiveThroughTheCompletePhase2Pipeline() throws {
        let xml = """
        <WasabiXML><container id="main"><layout id="normal"><layer id="background"/></layout></container></WasabiXML>
        """
        let archiveURL = try makeArchive([TestEntry("skin.xml", data: Data(xml.utf8))], filename: "End To End.wal")
        let loaded = try WinampModernSkinLoader().load(from: archiveURL)

        XCTAssertEqual(loaded.document.visitedPaths, ["/Skins/End To End/skin.xml"])
        XCTAssertEqual(loaded.runtime.graph.objectCount, 3)
        XCTAssertEqual(loaded.runtime.graph.objects(xmlID: "background").count, 1)
        loaded.teardown()
        XCTAssertEqual(loaded.runtime.state, .tornDown)
    }

    func testGraphMutationInvalidationStableIDsAndTeardown() throws {
        let runtime = try makeInitializedRuntime()
        runtime.markFirstPaintComplete()
        XCTAssertEqual(runtime.state, .initialized)
        XCTAssertTrue(runtime.graph.consumeInvalidations().isEmpty)

        let instance = try XCTUnwrap(runtime.graph.objects(xmlID: "instance").first)
        let stableID = instance.stableID
        XCTAssertTrue(instance.setAttribute("x", value: "12"))
        XCTAssertEqual(instance.stableID, stableID)
        XCTAssertEqual(runtime.graph.consumeInvalidations().first?.1, .geometry)

        weak var weakChild: WasabiObject?
        do {
            let child = runtime.graph.makeObject(typeName: "layer", attributes: ["id": "dynamic"],
                                                 source: WalSourceLocation(path: "/dynamic"))
            weakChild = child
            try instance.appendChild(child)
            XCTAssertTrue(child.parent === instance)
        }
        runtime.teardown()
        XCTAssertEqual(runtime.state, .tornDown)
        XCTAssertTrue(runtime.graph.isTornDown)
        XCTAssertNil(weakChild)
    }

    func testGroupCyclesAndMissingResourcesFailDuringInitialization() throws {
        let cycleXML = """
        <WasabiXML><elements>
          <groupdef id="a" inherit_group="b"/>
          <groupdef id="b" inherit_group="a"/>
        </elements></WasabiXML>
        """
        XCTAssertEqual(errorCode { try self.initialize(xml: cycleXML, resources: [:]) }, .groupInheritanceCycle)

        // A missing *bitmap* image is tolerated (Winamp draws nothing) — it records a warning rather
        // than failing the load, so real skins/engines that declare unshipped optional art still open.
        // Security failures (traversal/escape/oversize/corrupt) and missing includes still hard-fail.
        let missingResourceXML = "<WasabiXML><elements><bitmap id=\"x\" file=\"missing.png\"/></elements></WasabiXML>"
        let tolerant = try self.initialize(xml: missingResourceXML, resources: [:])
        XCTAssertTrue(tolerant.diagnostics.contains {
            $0.code == .resourceMissing && $0.severity == .warning
        }, "missing bitmap should record a warning")

        let oversizedFontXML = "<WasabiXML><container><layout><text fontsize=\"513\"/></layout></container></WasabiXML>"
        XCTAssertEqual(errorCode { try self.initialize(xml: oversizedFontXML, resources: [:]) }, .fontSizeExceeded)
    }

    func testImageAndScriptResourceLimitsFailDuringInitialization() throws {
        let png = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=")!
        let xml = """
        <WasabiXML><elements><bitmap id="image" file="image.png"/></elements>
        <container><layout><script file="main.maki"/></layout></container></WasabiXML>
        """
        let provider = try WalMemoryResourceProvider(resources: [
            "skin.xml": Data(xml.utf8), "image.png": png, "main.maki": Data([0x46, 0x47])
        ])
        let vfs = try WalVirtualFileSystem(skinName: "Limits", skin: provider)
        let document = try WalXMLDocumentLoader(vfs: vfs).load(entryPath: "/Skins/Limits/skin.xml")

        var imageLimits = WasabiResourceLimits.production
        imageLimits.maximumImageWidth = 0
        XCTAssertEqual(errorCode {
            try WasabiSkinInitializer(vfs: vfs, resourceLimits: imageLimits).initialize(document: document)
        }, .imageDimensionsExceeded)

        var scriptLimits = WasabiResourceLimits.production
        scriptLimits.maximumScriptSize = 1
        XCTAssertEqual(errorCode {
            try WasabiSkinInitializer(vfs: vfs, resourceLimits: scriptLimits).initialize(document: document)
        }, .entryTooLarge)
    }

    func testCoordinateAndAnchorModelHandlesSignedRelativeDimensions() {
        let parent = WasabiRect(x: 10, y: 20, width: 300, height: 200)
        let spec = WasabiGeometrySpec(attributes: [
            "x": "-60", "y": "-26", "w": "-120", "h": "-47",
            "relatx": "1", "relaty": "1", "relatw": "1", "relath": "1"
        ])
        XCTAssertEqual(spec.resolve(in: parent), WasabiRect(x: 250, y: 194, width: 180, height: 153))

        let signed = WasabiGeometrySpec(attributes: ["x": "5", "y": "6", "w": "-10", "h": "-20"])
            .resolve(in: parent)
        XCTAssertEqual(signed, WasabiRect(x: 15, y: 26, width: -10, height: -20))
        XCTAssertEqual(signed.standardized, WasabiRect(x: 5, y: 6, width: 10, height: 20))
    }

    // MARK: - Import/store

    func testImporterValidatesBeforeAtomicStorageAndDiscoversInstalledSkins() throws {
        let destination = temporaryDirectory().appendingPathComponent("WinampModernSkins")
        let importer = WinampModernSkinImporter(destinationDirectory: destination)
        let valid = try makeArchive([TestEntry("skin.xml", data: Data("<WasabiXML/>".utf8))], filename: "Good.wal")

        let imported = try importer.importContainer(at: valid)
        XCTAssertEqual(imported.archiveURL, destination.appendingPathComponent("Good.wal"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: imported.archiveURL.path))
        let installed = importer.installedSkins()
        XCTAssertEqual(installed.map(\.name), ["Good"])
        XCTAssertEqual(installed.first?.archiveURL.resolvingSymlinksInPath(),
                       imported.archiveURL.resolvingSymlinksInPath())

        let otherDirectory = temporaryDirectory()
        let invalid = otherDirectory.appendingPathComponent("Good.wal")
        try Data("not a zip".utf8).write(to: invalid)
        let before = try Data(contentsOf: imported.archiveURL)
        XCTAssertEqual(errorCode { try importer.importContainer(at: invalid) }, .invalidArchive)
        XCTAssertEqual(try Data(contentsOf: imported.archiveURL), before,
                       "An invalid replacement must not touch the installed archive")
    }

    func testImporterRejectsUnsupportedContainerFormat() throws {
        let source = temporaryDirectory().appendingPathComponent("skin.zip")
        try Data().write(to: source)
        let importer = WinampModernSkinImporter(destinationDirectory: temporaryDirectory())
        XCTAssertEqual(errorCode { try importer.importContainer(at: source) }, .unsupportedContainer)
    }

    // MARK: - Helpers

    private func makeInitializedRuntime() throws -> WasabiSkinRuntime {
        let xml = """
        <WasabiXML>
          <elements>
            <bitmap id="background" file="images/bg.png"/>
            <groupdef id="base" x="4" relatw="1" w="-8"><layer id="base.layer"/></groupdef>
            <groupdef id="derived" inherit_group="base" xuitag="Test:Panel">
              <button id="templated"><script file="scripts/main.maki"/></button>
            </groupdef>
          </elements>
          <container id="main"><layout id="normal" w="300" h="100"><Test:Panel id="instance" y="2"/></layout></container>
        </WasabiXML>
        """
        return try initialize(xml: xml, resources: [
            "Images/BG.PNG": Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=")!,
            "Scripts/Main.maki": Data([0x46, 0x47])
        ])
    }

    private func initialize(xml: String, resources: [String: Data]) throws -> WasabiSkinRuntime {
        var allResources = resources
        allResources["skin.xml"] = Data(xml.utf8)
        let provider = try WalMemoryResourceProvider(resources: allResources)
        let vfs = try WalVirtualFileSystem(skinName: "Synthetic", skin: provider)
        let document = try WalXMLDocumentLoader(vfs: vfs).load(entryPath: "/Skins/Synthetic/skin.xml")
        return try WasabiSkinInitializer(vfs: vfs).initialize(document: document)
    }

    private func makeArchive(_ entries: [TestEntry], filename: String = "fixture.wal") throws -> URL {
        let directory = temporaryDirectory()
        let url = directory.appendingPathComponent(filename)
        let archive = try Archive(url: url, accessMode: .create)
        for entry in entries {
            try archive.addEntry(
                with: entry.path,
                type: entry.type,
                uncompressedSize: Int64(entry.data.count),
                compressionMethod: entry.compression
            ) { position, size in
                let start = Int(position)
                guard start < entry.data.count else { return Data() }
                return entry.data.subdata(in: start..<min(start + size, entry.data.count))
            }
        }
        return url
    }

    private func temporaryDirectory() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("WinampModernPhase2Tests-\(UUID().uuidString)", isDirectory: true)
        try! FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    private func errorCode(_ body: () throws -> Any) -> WalDiagnosticCode? {
        do {
            _ = try body()
            XCTFail("Expected operation to throw")
            return nil
        } catch let failure as WalFailure {
            return failure.diagnostics.first?.code
        } catch {
            XCTFail("Expected WalFailure, received \(error)")
            return nil
        }
    }
}
