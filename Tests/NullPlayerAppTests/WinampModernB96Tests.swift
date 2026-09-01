import XCTest
import ZIPFoundation
@testable import NullPlayer

/// B96 — a container root carrying an `id` the skin has already used. One symptom, two causes, and
/// they want opposite answers:
///
/// * **A double include.** jvc.tape declares `Pledit` once, in `xml/pledit.xml`, and includes that
///   file from both `skin.xml` and `xml/amp.xml`. Two container roots come out of one declaration,
///   so the second is a phantom window: it appears in the Skin Windows menu and opens a duplicate.
/// * **A literal duplicate `id=`.** WMP11-BlueVU writes `<container id="Meter" name="VU Meters
///   Large">` and then `<container id="Meter" name="VU Meters Small">`. Two windows the skin plainly
///   intends, sharing one id.
///
/// Everything downstream addresses a window by its id *string* — the renderer's `containerID`, the
/// Skin Windows menu, and the per-container layout and frame persistence — so the second of a pair
/// was unreachable either way: opening "VU Meters Small" resolved the id back to the large meter.
/// The source location tells the two causes apart. Same location: one declaration reached twice, and
/// the repeat is dropped. Different locations: two declarations, and the second is given an id of
/// its own so it can be opened, while by-id lookups keep answering with the first — which is what
/// Winamp's own container table does.
final class WinampModernB96Tests: XCTestCase {

    // MARK: - Two declarations sharing one id

    /// The WMP11 shape. Both windows survive, and the second answers to an id of its own instead of
    /// being a second name for the first.
    func testASecondDeclarationSharingAnIdKeepsItsOwnWindow() throws {
        let loaded = try makeSkin(containers: [
            Self.container(id: "Meter", name: "VU Meters Large", width: 16, height: 8),
            Self.container(id: "Meter", name: "VU Meters Small", width: 32, height: 4),
        ])
        let containers = WinampModernContainerTopology.windowContainers(graph: loaded.runtime.graph)
        let ids = containers.map(\.id)
        XCTAssertEqual(ids.filter { $0.lowercased().hasPrefix("meter") }, ["Meter", "Meter#2"],
                       "both meters are windows, and they are two different windows")
        XCTAssertEqual(Set(ids).count, ids.count, "no id is claimed twice")
    }

    /// And the second window is the *second* declaration, not a second view of the first: the small
    /// meter's own 32×4 layout is what its renderer measures.
    func testTheRenamedContainerRendersItsOwnDeclaration() throws {
        let loaded = try makeSkin(containers: [
            Self.container(id: "Meter", name: "VU Meters Large", width: 16, height: 8),
            Self.container(id: "Meter", name: "VU Meters Small", width: 32, height: 4),
        ])
        let large = try renderer(for: loaded, containerID: "Meter")
        let small = try renderer(for: loaded, containerID: "Meter#2")
        XCTAssertEqual(large.canvasSize, CGSize(width: 16, height: 8))
        XCTAssertEqual(small.canvasSize, CGSize(width: 32, height: 4),
                       "the small meter draws its own layout, not the large one's")
    }

    /// The skin's own name for each window is untouched — that is what the Skin Windows menu shows,
    /// and it is the only thing distinguishing the pair to a user.
    func testRenamingTheIdLeavesTheSkinsOwnWindowNameAlone() throws {
        let loaded = try makeSkin(containers: [
            Self.container(id: "Meter", name: "VU Meters Large", width: 16, height: 8),
            Self.container(id: "Meter", name: "VU Meters Small", width: 32, height: 4),
        ])
        let names = loaded.runtime.graph.roots
            .filter { $0.typeName.caseInsensitiveCompare("container") == .orderedSame }
            .compactMap { $0.attributes["name"] }
        XCTAssertEqual(names, ["Main Window", "VU Meters Large", "VU Meters Small"])
    }

    /// The **first** declaration keeps the id, so a script's `getContainer("Meter")` and every
    /// persisted layout/frame key resolve exactly where they did before. Only the second moves.
    func testAByIdLookupStillAnswersWithTheFirstDeclaration() throws {
        let loaded = try makeSkin(containers: [
            Self.container(id: "Meter", name: "VU Meters Large", width: 16, height: 8),
            Self.container(id: "Meter", name: "VU Meters Small", width: 32, height: 4),
        ])
        let matches = loaded.runtime.graph.objects(xmlID: "Meter")
            .filter { $0.typeName.caseInsensitiveCompare("container") == .orderedSame }
        XCTAssertEqual(matches.count, 1, "one container answers to the declared id")
        XCTAssertEqual(matches.first?.attributes["name"], "VU Meters Large",
                       "and it is the first declaration, the way Winamp's container table answers")
    }

    /// A third declaration takes the next free suffix rather than colliding with the second.
    func testAThirdDeclarationTakesTheNextFreeIdentifier() throws {
        let loaded = try makeSkin(containers: [
            Self.container(id: "Meter", name: "One", width: 16, height: 8),
            Self.container(id: "Meter", name: "Two", width: 16, height: 8),
            Self.container(id: "Meter", name: "Three", width: 16, height: 8),
        ])
        let ids = WinampModernContainerTopology.windowContainers(graph: loaded.runtime.graph)
            .map(\.id)
            .filter { $0.lowercased().hasPrefix("meter") }
        XCTAssertEqual(ids, ["Meter", "Meter#2", "Meter#3"])
    }

    /// The rename is reported. A window that answers to an id the skin never wrote is exactly the
    /// kind of thing a later triage pass has to be able to see.
    func testTheRenameIsReported() throws {
        let loaded = try makeSkin(containers: [
            Self.container(id: "Meter", name: "VU Meters Large", width: 16, height: 8),
            Self.container(id: "Meter", name: "VU Meters Small", width: 32, height: 4),
        ])
        XCTAssertTrue(loaded.runtime.diagnostics.contains {
            $0.code == .duplicateIdentifier && $0.message.contains("'Meter#2'")
        }, "the diagnostics name the id the second window answers to")
    }

    // MARK: - One declaration included twice

    /// The jvc.tape shape: one `<container>`, two include paths to it. The repeat is dropped, so the
    /// skin gets the one window it declared.
    func testAFileIncludedTwiceStillDeclaresOneWindow() throws {
        let loaded = try makeDoubleIncludeSkin()
        let ids = WinampModernContainerTopology.windowContainers(graph: loaded.runtime.graph).map(\.id)
        XCTAssertEqual(ids.filter { $0.caseInsensitiveCompare("Pledit") == .orderedSame }, ["Pledit"],
                       "the second include does not open a phantom playlist window")
        XCTAssertEqual(Set(ids).count, ids.count)
    }

    /// Dropping the repeat is not the same as dropping the container: the one that survives is whole.
    func testTheSurvivingContainerKeepsItsLayout() throws {
        let loaded = try makeDoubleIncludeSkin()
        let pledit = try renderer(for: loaded, containerID: "Pledit")
        XCTAssertEqual(pledit.canvasSize, CGSize(width: 24, height: 12))
    }

    /// And the drop is reported rather than silent.
    func testTheDroppedRepeatIsReported() throws {
        let loaded = try makeDoubleIncludeSkin()
        XCTAssertTrue(loaded.runtime.diagnostics.contains {
            $0.code == .duplicateIdentifier && $0.message.contains("included twice")
        })
    }

    // MARK: - The ordinary skin

    /// The containment. A skin with no repeated container id takes the identical path it always did,
    /// which is what keeps this out of the other 69 archives in the corpus.
    func testASkinWithNoRepeatedIdIsUntouched() throws {
        let loaded = try makeSkin(containers: [
            Self.container(id: "Meter", name: "VU Meters", width: 16, height: 8),
            Self.container(id: "Pledit", name: "Playlist", width: 24, height: 12),
        ])
        let ids = WinampModernContainerTopology.windowContainers(graph: loaded.runtime.graph).map(\.id)
        XCTAssertEqual(ids.filter { $0 != "main" && !$0.hasPrefix("nullplayer.") },
                       ["Meter", "Pledit"])
        XCTAssertFalse(loaded.runtime.diagnostics.contains { $0.code == .duplicateIdentifier },
                       "nothing is renamed and nothing is dropped")
    }

    // MARK: - Fixtures

    private static func container(id: String, name: String, width: Int, height: Int) -> String {
        """
        <container id="\(id)" name="\(name)">
          <layout id="normal" w="\(width)" h="\(height)">
            <layer id="\(id).body" x="0" y="0" w="\(width)" h="\(height)"/>
          </layout>
        </container>
        """
    }

    /// A main player plus whatever containers the case declares, all in `skin.xml` — so every
    /// duplicate id here comes from a *different* source location, which is the "two declarations"
    /// half of B96.
    private func makeSkin(containers: [String]) throws -> WinampModernLoadedSkin {
        let markup = """
        <WasabiXML>
        \(Self.container(id: "main", name: "Main Window", width: 20, height: 10))
        \(containers.joined(separator: "\n"))
        </WasabiXML>
        """
        return try load(files: ["skin.xml": Data(markup.utf8)])
    }

    /// One `<container>`, in one file, reached from two include paths — jvc.tape's `xml/pledit.xml`
    /// read from both `skin.xml` and `xml/amp.xml`.
    private func makeDoubleIncludeSkin() throws -> WinampModernLoadedSkin {
        let pledit = """
        <WasabiXML>
        \(Self.container(id: "Pledit", name: "Playlist", width: 24, height: 12))
        </WasabiXML>
        """
        let amp = """
        <WasabiXML>
        \(Self.container(id: "main", name: "Main Window", width: 20, height: 10))
          <include file="pledit.xml"/>
        </WasabiXML>
        """
        let root = """
        <WasabiXML>
          <include file="xml/amp.xml"/>
          <include file="xml/pledit.xml"/>
        </WasabiXML>
        """
        return try load(files: [
            "skin.xml": Data(root.utf8),
            "xml/amp.xml": Data(amp.utf8),
            "xml/pledit.xml": Data(pledit.utf8),
        ])
    }

    private func load(files: [String: Data]) throws -> WinampModernLoadedSkin {
        let loaded = try WinampModernSkinLoader(engineStore: nil).load(from: try makeArchive(files: files))
        addTeardownBlock { loaded.teardown() }
        return loaded
    }

    private func renderer(for loaded: WinampModernLoadedSkin,
                          containerID: String) throws -> WasabiSceneRenderer {
        let renderer = try WasabiSceneRenderer(loadedSkin: loaded, host: Host(),
                                               containerID: containerID, clock: { 0 })
        addTeardownBlock { renderer.teardown() }
        return renderer
    }

    private func makeArchive(files: [String: Data]) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("WinampModernB96Tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("B96-\(UUID().uuidString).wal")
        let archive = try Archive(url: url, accessMode: .create)
        for (name, payload) in files.sorted(by: { $0.key < $1.key }) {
            try archive.addEntry(with: name, type: .file, uncompressedSize: Int64(payload.count),
                                 compressionMethod: .none) { position, size in
                let start = Int(position)
                guard start < payload.count else { return Data() }
                return payload.subdata(in: start..<min(payload.count, start + size))
            }
        }
        return url
    }

    private final class Host: WinampModernHost {
        var playbackState: PlaybackState = .stopped
        var currentTime: TimeInterval = 0
        var duration: TimeInterval = 200
        var volume: Double = 0.5
        var balance: Double = 0
        var shuffleEnabled = false
        var repeatEnabled = false
        var trackTitle = ""
        var trackInfo = ""
        var spectrumLevels: [Float] = []

        func play() {}
        func pause() {}
        func stop() {}
        func previous() {}
        func next() {}
        func seek(to seconds: TimeInterval) {}
        func openFiles() {}
        func beginVisualizationConsumption() {}
        func endVisualizationConsumption() {}
    }
}
