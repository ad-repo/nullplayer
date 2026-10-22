import XCTest
@testable import NullPlayer

/// Alpha Media Player X5's report (2026-10-21): "sliders do not all work", and the EQ and Mute switch
/// levers disappear. The sliders are `WinampModernPhase51Tests`' event space; these are the switches.
final class WinampModernAlphaMediaPlayerTests: XCTestCase {
    /// The lever script: on is `setTargetY(getXmlParam("y") - 17)`, off is `setTargetY(getXmlParam("y"))`.
    /// Both only work while `getXmlParam("y")` answers the declared 20 after the lever has moved.
    func testATargetAnimationLeavesTheXMLParamAsDeclared() throws {
        let (runtime, lever) = try makeRuntime()
        let program = Self.emptyProgram()
        try move(lever, toY: 3, runtime, program)
        XCTAssertEqual(lever.attributes["y"], "3", "the lever moved")
        XCTAssertEqual(try runtime.invokeGUI(method: "getxmlparam", object: lever,
                                             arguments: [.string("y")], program: program).stringValue,
                       "20", "its XML param did not")
        try move(lever, toY: 20, runtime, program)
        try move(lever, toY: 3, runtime, program)
        XCTAssertEqual(try runtime.invokeGUI(method: "getxmlparam", object: lever,
                                             arguments: [.string("y")], program: program).stringValue,
                       "20", "a second move keeps the first declared value")
    }

    /// `setXmlParam` *is* the XML, so it replaces the declared value an animation kept.
    func testSetXmlParamReplacesTheKeptValue() throws {
        let (runtime, lever) = try makeRuntime()
        let program = Self.emptyProgram()
        try move(lever, toY: 3, runtime, program)
        _ = try runtime.invokeGUI(method: "setxmlparam", object: lever,
                                  arguments: [.string("y"), .string("8")], program: program)
        XCTAssertEqual(try runtime.invokeGUI(method: "getxmlparam", object: lever,
                                             arguments: [.string("y")], program: program).stringValue, "8")
    }

    /// The skin's own `setVolume` is announced once, by `setVolume`. The window's poll compares
    /// against what was last announced, so it must see this level as already told.
    func testSetVolumeRecordsTheLevelItAnnounced() throws {
        let (runtime, _) = try makeRuntime()
        _ = try runtime.invokeSystem(method: "setvolume", arguments: [.integer(51)], program: Self.emptyProgram())
        XCTAssertEqual(runtime.announcedVolume, WinampModernScriptRuntime.volumeLevel(runtime.host.volume))
    }

    // MARK: - Fixtures

    private func move(_ lever: WasabiObject, toY y: Int32, _ runtime: WinampModernScriptRuntime,
                      _ program: MakiProgram) throws {
        _ = try runtime.invokeGUI(method: "settargety", object: lever, arguments: [.integer(y)], program: program)
        _ = try runtime.invokeGUI(method: "settargetspeed", object: lever, arguments: [.integer(0)], program: program)
        _ = try runtime.invokeGUI(method: "gototarget", object: lever, arguments: [], program: program)
    }

    private func makeRuntime() throws -> (WinampModernScriptRuntime, WasabiObject) {
        let loaded = try makeWinampModernSkin(xml: """
        <WasabiXML>
          <container id="main">
            <layout id="normal" w="100" h="100">
              <layer id="crandle" x="3" y="20" w="20" h="10"/>
            </layout>
          </container>
        </WasabiXML>
        """)
        let runtime = try WinampModernScriptRuntime(loadedSkin: loaded, host: WinampModernStubHost())
        addTeardownBlock { runtime.teardown() }
        return (runtime, try XCTUnwrap(loaded.runtime.graph.objects(xmlID: "crandle").first))
    }

    private static func emptyProgram() -> MakiProgram {
        MakiProgram(version: 0x0403, classes: [], methods: [], variables: [], bindings: [],
                    instructions: [], source: WalSourceLocation(path: "/Skins/Synthetic/alpha.maki"),
                    ownerID: nil, parameter: nil)
    }
}
