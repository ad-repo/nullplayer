import Foundation
import XCTest
@testable import NullPlayer

/// The skin model's pure parts, without a corpus: the `Expression` language, the control class and
/// form role read from names, and the index a skin's forms and `Schema.xml` build.
extension AIMPSkinExpression {
    static func evaluate(_ text: String, value: Double) -> Double? { AIMPSkinExpression(text)?.evaluate(value: value) }

    static func evaluate(_ text: String, variables: [String: Double]) -> Double? {
        AIMPSkinExpression(text)?.evaluate(variables: variables)
    }
}

final class AIMPSkinModelTests: XCTestCase {
    // MARK: - Expressions

    func testExpressionsTheCorpusUses() {
        XCTAssertEqual(AIMPSkinExpression.evaluate("not value", value: 0), 1)
        XCTAssertEqual(AIMPSkinExpression.evaluate("not value", value: 3), 0)
        XCTAssertEqual(AIMPSkinExpression.evaluate("value=1", value: 1), 1)
        XCTAssertEqual(AIMPSkinExpression.evaluate("value<>50", value: 50), 0)
        XCTAssertEqual(AIMPSkinExpression.evaluate("value div 3600", value: 7300), 2)
        XCTAssertEqual(AIMPSkinExpression.evaluate("(value+1) mod 3", value: 4), 2)
        XCTAssertEqual(AIMPSkinExpression.evaluate("if(value3,value1,value2)",
                                                   variables: ["value1": 7, "value2": 9, "value3": 1]), 7)
        XCTAssertEqual(AIMPSkinExpression.evaluate("if(value3,value1,value2)",
                                                   variables: ["value1": 7, "value2": 9, "value3": 0]), 9)
        XCTAssertEqual(AIMPSkinExpression.evaluate("round(value)", value: 2.4), 2)
        XCTAssertEqual(AIMPSkinExpression.evaluate("log10(value)", value: 100), 2)
    }

    func testPrecedenceAndCase() {
        XCTAssertEqual(AIMPSkinExpression.evaluate("1+2*3", value: 0), 7)
        XCTAssertEqual(AIMPSkinExpression.evaluate("-value+1", value: 4), -3)
        XCTAssertEqual(AIMPSkinExpression.evaluate("1 or 0 and 0", value: 0), 1, "and binds tighter than or")
        XCTAssertEqual(AIMPSkinExpression.evaluate("NOT Value", value: 0), 1, "keywords and names ignore case")
        XCTAssertEqual(AIMPSkinExpression.evaluate("(0-5) mod 3", value: 0), -2, "mod truncates, as Pascal's")
        XCTAssertEqual(AIMPSkinExpression.evaluate("true and not false", value: 0), 1)
    }

    /// Anything the evaluator cannot answer is nil, so the caller keeps the unshaped value.
    func testWhatEvaluatesToNil() {
        XCTAssertNil(AIMPSkinExpression("value +"), "incomplete syntax does not compile")
        XCTAssertNil(AIMPSkinExpression("(value"))
        XCTAssertNil(AIMPSkinExpression.evaluate("value / 0", value: 1))
        XCTAssertNil(AIMPSkinExpression.evaluate("value div 0", value: 1))
        XCTAssertNil(AIMPSkinExpression.evaluate("value2 + 1", value: 1), "an unknown variable")
        XCTAssertNil(AIMPSkinExpression.evaluate("min(1)", value: 0), "a call with the wrong arguments")
    }

    /// `and`, `or`, `xor` are Pascal's: bitwise on whole numbers, so logical on 0 and 1; a fraction
    /// (which Delphi refuses) is read by whether it is zero. The script engine uses the same core
    /// (`AIMPSkinScriptTests.testOperatorsAnswerAsBindingsDo`).
    func testLogicalOperatorsAreBitwiseOnWholeNumbers() {
        XCTAssertEqual(AIMPSkinExpression.evaluate("value xor 1", value: 2), 3, "Kenwood's speaker switch")
        XCTAssertEqual(AIMPSkinExpression.evaluate("value and 3", value: 6), 2)
        XCTAssertEqual(AIMPSkinExpression.evaluate("value or 1", value: 4), 5)
        XCTAssertEqual(AIMPSkinExpression.evaluate("(value=1) and (value<2)", value: 1), 1)
        XCTAssertEqual(AIMPSkinExpression.evaluate("value and 1", value: 0.5), 1)
        XCTAssertEqual(AIMPSkinExpression.evaluate("1 shl value", value: 3), 8)
    }

    func testCompiledOnceEvaluatesMany() throws {
        let expression = try XCTUnwrap(AIMPSkinExpression("value*2"))
        XCTAssertEqual((0..<4).compactMap { expression.evaluate(value: Double($0)) }, [0, 2, 4, 6])
    }

    // MARK: - Names

    func testControlClassByName() throws {
        func read(_ name: String?, link: String? = nil, _ props: String = "") throws -> AIMPControlClass {
            let attributes = [name.map { " class=\"\($0)\"" }, link.map { " link=\"\($0)\"" }].compactMap { $0 }.joined()
            let node = try Self.node("<control\(attributes)><properties>\(props)</properties></control>")
            return AIMPControlClass(node, bindings: AIMPSkinBindings(node, names: .init()), resources: [:])
        }
        XCTAssertEqual(try read("Button").key?.role, .button)
        XCTAssertEqual(try read("Switch").key?.isKey, true)
        XCTAssertEqual(try read("TextDisplayEx").key?.role, .textDisplay)
        XCTAssertEqual(try read("RunningLine").key?.showsText, true)
        XCTAssertEqual(try read("ScrollBarVertical").key?.role, .picture, "a scroll bar bound to no list is a picture")
        XCTAssertEqual(try read("Mystery").key?.role, .picture)
        XCTAssertEqual(try read(nil).key?.role, .picture)
        XCTAssertEqual(try read("Panel", #"<property name="Color" value="-1"/>"#).key?.fill, .argb(0xFFFF_FFFF))
        guard case .slider(let vertical) = try read("SliderVertical"), vertical.isVertical, !vertical.isSeek else { return XCTFail() }
        guard case .slider(let seek) = try read("SeekBar"), seek.isSeek, !seek.isVertical else { return XCTFail() }
        guard case .selector = try read("SliderMasked") else { return XCTFail("the filmstrip is not a plain slider") }
        guard case .gauge(let reaction) = try read("Gauge"), reaction == nil else { return XCTFail() }
        guard case .playlist = try read("Panel", link: "Playlist") else { return XCTFail("bound to the playlist, the playlist") }
        guard case .search(.playlist) = try read(nil, link: "PlaylistSearch") else { return XCTFail() }
    }

    func testFormRoleByName() {
        XCTAssertEqual(AIMPFormRole("AIMPMainForm"), .main)
        XCTAssertEqual(AIMPFormRole("TA2066_PlaylistWindow"), .playlist)
        XCTAssertEqual(AIMPFormRole("PLWin"), .playlist)
        XCTAssertEqual(AIMPFormRole("RX80_MusicLibraryFrame"), .library)
        XCTAssertEqual(AIMPFormRole("EqualizerFrame"), .equalizer)
        XCTAssertEqual(AIMPFormRole("Menu"), .menu)
        XCTAssertEqual(AIMPFormRole("Win_1"), .other)
        XCTAssertTrue(AIMPFormRole("LyricsFrame").isNullPlayers)
        XCTAssertFalse(AIMPFormRole("EqualizerFrame").isNullPlayers)
    }

    // MARK: - Languages

    func testPreferredLanguagesMapToAIMPFileNames() {
        XCTAssertEqual(AIMPSkinLanguage.fileNames(for: "ru-RU"), ["russian"])
        XCTAssertEqual(AIMPSkinLanguage.fileNames(for: "pt-BR"), ["brazilian", "portuguese"])
        XCTAssertEqual(AIMPSkinLanguage.fileNames(for: "es-AR").first, "espanol-ar")
        XCTAssertEqual(AIMPSkinLanguage.fileNames(for: "es").first, "espanol-es")
        XCTAssertEqual(AIMPSkinLanguage.fileNames(for: "zh-Hans-CN"), ["simplified_chinese"])
        XCTAssertEqual(AIMPSkinLanguage.fileNames(for: "zh-Hant-HK").first, "hongkongese")
        XCTAssertEqual(AIMPSkinLanguage.fileNames(for: "zh-Hant-TW").first, "traditional_chinese")
        XCTAssertEqual(AIMPSkinLanguage.fileNames(for: "uk"), ["ukrainian", "ukranian"], "a misspelling skins ship")
        XCTAssertEqual(AIMPSkinLanguage.fileNames(for: "xx"), [])
    }

    /// The first preferred language the skin has wins; none, and English alone is read.
    func testTheFirstPreferredLanguageTheSkinHasWins() {
        let skin: Set<String> = ["english", "russian", "polish"]
        XCTAssertEqual(AIMPSkinLanguage.choose(available: skin, preferred: ["de-DE", "pl-PL", "ru"]), "polish")
        XCTAssertEqual(AIMPSkinLanguage.choose(available: skin, preferred: ["en-US", "ru"]), "english")
        XCTAssertNil(AIMPSkinLanguage.choose(available: skin, preferred: ["fr-FR"]))
    }

    func testPlayerStringsReadAsWords() {
        XCTAssertEqual(AIMPSkinLanguage.playerString(#"Actions\QuickSearch"#), "Quick search")
        XCTAssertEqual(AIMPSkinLanguage.playerString(#"AIMP\acPlayerRepeat"#), "Player repeat")
        XCTAssertEqual(AIMPSkinLanguage.playerString(#"AIMPML\Duration"#), "Duration")
        XCTAssertNil(AIMPSkinLanguage.playerString("10"), "the skin's own strings are numbered")
    }

    func testLngFilesReadAsAIMPWritesThem() throws {
        let text = "[SkinCustoms]\r\n1=МЕНЮ\r\n2=Плейлист=x\r\n"
        let data = try XCTUnwrap(text.data(using: .utf16LittleEndian).map { Data([0xFF, 0xFE]) + $0 })
        XCTAssertEqual(try AIMPSkinLanguage.strings(data), ["1": "МЕНЮ", "2": "Плейлист=x"])
    }

    /// One rule for every `@Lng:key;`, wherever it stands: the skin's string, else AIMP's own; a key
    /// neither has reads as nothing.
    func testLanguageStringsExpandOneWay() {
        let strings = ["10": "Main", "36": "Playlist"]
        XCTAssertEqual(AIMPSkinLanguage.expanded("@Lng:10;", strings: strings), "Main")
        XCTAssertEqual(AIMPSkinLanguage.expanded("Akai GX-635D - @Lng:10;", strings: strings), "Akai GX-635D - Main")
        XCTAssertEqual(AIMPSkinLanguage.expanded("@Lng:10; - @Lng:36;", strings: strings), "Main - Playlist")
        XCTAssertEqual(AIMPSkinLanguage.expanded(#"@Lng:Actions\QuickSearch;"#, strings: strings), "Quick search")
        XCTAssertEqual(AIMPSkinLanguage.expanded("@Lng:99;", strings: strings), "", "no raw key on screen")
        XCTAssertEqual(AIMPSkinLanguage.expanded("x @Lng:99; @Lng:10;", strings: strings), "x  Main")
    }

    /// A `.lng` that does not read is a finding of the load, not silently no strings.
    func testAnUnreadableLanguageFileIsAFinding() throws {
        let skin = try Self.project([("AIMPMainForm.xml", Data(#"<form name="AIMPMainForm"/>"#.utf8)),
                                     ("English.lng", Data([0xFF, 0xFE, 0x00, 0xD8]))], languages: ["en"])
        XCTAssertEqual(skin.strings, [:])
        XCTAssertTrue(skin.findings.contains { $0.code == .entryUnreadable && $0.message.contains("English.lng") })
    }

    // MARK: - Text and triggers

    /// A display's number reads by what its link reads, not by matching the names again: the
    /// volume's `Position` is a number, not a time.
    func testDisplayNumbersFormatByWhatTheLinkReads() {
        func text(_ value: Double, _ source: String, _ pin: String) -> String {
            AIMPSkinDataflow.text(of: value, read: AIMPSkinSource(source, pin, names: .init()))
        }
        XCTAssertEqual(text(1, "prvVolume", "Position"), "1")
        XCTAssertEqual(text(75, "prvPlayerState", "TrackPosition"), "1:15")
        XCTAssertEqual(text(75, "prvPlayingFileInfo", "Duration"), "1:15")
        XCTAssertEqual(text(3_723, "prvSystemTime", "Time"), "01:02")
        XCTAssertEqual(text(3_725, "Playlist", "Duration"), "1:02:05")
        XCTAssertEqual(text(1_048_576, "MLTable", "Size"), "1.00 MB")
        XCTAssertEqual(text(42.4, "prvBalance", "Position"), "42")
        XCTAssertEqual(text(0, "prvSleepTime", "Time"), "0:00", "no sleep timer, still a time")
        var names = AIMPSkinIndex.Names()
        names.items.insert("Playlist")
        XCTAssertEqual(AIMPSkinDataflow.text(of: 3_725, read: AIMPSkinSource("Playlist", "Duration", names: names)), "1:02:05",
                       "the list's total, though an item is named after it")
    }

    /// A concatenator triggers on its inputs as they are: (1, 0) and (0, 1000) are different texts.
    /// One reading another reads its text, and triggers on its inputs.
    func testConcatenatorTriggersOnItsInputs() throws {
        let schema = """
        <schema><providers>
          <provider name="A" class="LogicalOperatorCounter"/><provider name="B" class="LogicalOperatorCounter"/>
          <provider name="Join" class="StringOperatorConcatenator"><properties><property name="Bindings">
            <link Source="A" SourcePin="Position" TargetPin="Value1"/><link Source="B" SourcePin="Position" TargetPin="Value2"/>
          </property><property name="Expression" value="%TextValue1-%TextValue2"/></properties></provider>
          <provider name="Outer" class="StringOperatorConcatenatorNotificator"><properties><property name="Bindings">
            <link Source="Join" SourcePin="Result" TargetPin="Value1"/>
          </property><property name="Expression" value="[%TextValue1]"/></properties></provider>
          <provider name="Digit" class="StringOperatorConcatenator"><properties><property name="Bindings">
            <link Source="A" SourcePin="Position" TargetPin="Value1"/>
          </property><property name="Expression" value="%Value1"/></properties></provider>
        </providers></schema>
        """
        let skin = try Self.project([("AIMPMainForm.xml", Data(#"<form name="AIMPMainForm"/>"#.utf8)), ("Schema.xml", Data(schema.utf8))])
        let link = AIMPSkinLink(try Self.node(#"<link Source="Join" SourcePin="Result" TargetPin="Handler"/>"#), names: skin.index.names)
        func inputs(_ a: Int, _ b: Int) -> [Double] {
            var state = AIMPSkinState()
            state.script.counters = ["A": a, "B": b]
            return AIMPSkinDataflow(skin: skin, host: AIMPSkinHostState(player: .probe), state: state).inputs(of: link)
        }
        XCTAssertEqual(inputs(1, 0), [1, 0])
        XCTAssertNotEqual(inputs(1, 0), inputs(0, 1_000))

        var state = AIMPSkinState()
        state.script.counters = ["A": 3, "B": 4]
        let flow = AIMPSkinDataflow(skin: skin, host: AIMPSkinHostState(player: .probe), state: state)
        let outer = try XCTUnwrap(skin.index.providers["Outer"]).bindings.links
        XCTAssertEqual(flow.concatenation(outer, template: "[%TextValue1]"), "[3-4]")
        XCTAssertEqual(flow.value("Digit", "Result"), 3, "a text read as a number is the number it spells")
        XCTAssertEqual(flow.value("Outer", "Result"), 0, "else none")
        state.script.expressions["Join"] = "%Value2"
        XCTAssertEqual(AIMPSkinDataflow(skin: skin, host: AIMPSkinHostState(player: .probe), state: state).concatenatorText("Outer"), "[4]",
                       "an `Expression` a script set")
        XCTAssertEqual(flow.inputs(of: AIMPSkinLink(try Self.node(#"<link Source="Outer" SourcePin="Result" TargetPin="Handler"/>"#),
                                                     names: skin.index.names)), [3, 4])
    }

    // MARK: - Commands

    /// The action trace and the harness print commands in this form; the live-run baseline is keyed by it.
    func testCommandsPrintAsTheTraceReadsThem() throws {
        let id = try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000001"))
        XCTAssertEqual(AIMPSkinCommand.action(.playerPlay).description, "acPlayerPlay")
        XCTAssertEqual(AIMPSkinCommand.seek(seconds: 0).description, "seek:0.0")
        XCTAssertEqual(AIMPSkinCommand.equalizerBand(3, dB: -1.5).description, "eq:3:-1.5")
        XCTAssertEqual(AIMPSkinCommand.setValue(provider: .named("prvReverb"), 0.5).description, "set:prvReverb:0.5")
        XCTAssertEqual(AIMPSkinCommand.playLibraryTrack(id).description, "libplay:00000000-0000-0000-0000-000000000001")
    }

    /// An action reads once from its AIMP name and prints back as that name; one NullPlayer lacks
    /// keeps the skin's spelling, and a source that is no action (a provider) is none.
    func testActionsReadByTheirAIMPNames() {
        XCTAssertEqual(AIMPAction("acPlayerPlay"), .playerPlay)
        XCTAssertEqual(AIMPAction("acMLAddFiles")?.name, "acMLAddFiles")
        XCTAssertEqual(AIMPAction("acPlayerSeekForward")?.title, "Fast forward")
        XCTAssertEqual(AIMPAction("acPlayerJumpToTime"), .unknown("acPlayerJumpToTime"))
        XCTAssertEqual(AIMPAction("acPlayerJumpToTime")?.name, "acPlayerJumpToTime")
        XCTAssertNil(AIMPAction("prvVolume"))
        for name in ["acPlayerShuffleMode", "acMainDSPManagerEQ", "acPlayableFileShowQTE", "acSearchAdvanced"] {
            XCTAssertEqual(AIMPAction(name)?.name, name)
            XCTAssertNotEqual(AIMPAction(name), .unknown(name))
        }
    }

    // MARK: - The script budget

    /// A runaway loop stops at the step limit, unbounded recursion at the depth limit, and a later
    /// run on a spent budget stops at once: one tick's script work is bounded, however the skin is
    /// written. Prints the worst case's time, the cost a runaway skin adds to a frame on main.
    @MainActor func testScriptBudgetBoundsATick() throws {
        let url = try XCTUnwrap(try AIMPCorpusLoadTests.installedSkins().first, "no installed AIMP skin to run scripts against")
        let skin = try AIMPSkinLoader.load(contentsOf: url)
        let loop = try Self.node("""
        <program><procedure><name text="Execute"/><compoundstmt>
          <whilestmt><expr><number text="1"/></expr><compoundstmt/></whilestmt>
        </compoundstmt></procedure></program>
        """)
        let recursion = try Self.node("""
        <program>
          <procedure><name text="F"/><compoundstmt><callstmt><dsgn><node text="F"/></dsgn></callstmt></compoundstmt></procedure>
          <procedure><name text="Execute"/><compoundstmt><callstmt><dsgn><node text="F"/></dsgn></callstmt></compoundstmt></procedure>
        </program>
        """)
        func stop(_ program: AIMPNode, _ budget: AIMPSkinScript.Budget) -> String {
            do {
                let engine = AIMPSkinScript.Engine(skin: skin, host: AIMPSkinHostState(player: .probe), state: AIMPSkinState(), budget: budget)
                try engine.run(AIMPSkinScript.compile(program))
                return "finished"
            } catch {
                return (error as? AIMPSkinScript.Budget.Spent)?.what ?? "\(error)"
            }
        }

        let budget = AIMPSkinScript.Budget()
        let began = CFAbsoluteTimeGetCurrent()
        XCTAssertEqual(stop(loop, budget), "step budget")
        let spent = (CFAbsoluteTimeGetCurrent() - began) * 1_000
        XCTAssertTrue(budget.isSpent)
        XCTAssertEqual(stop(recursion, budget), "step budget", "a later run on a spent budget stops at once")
        XCTAssertEqual(stop(recursion, AIMPSkinScript.Budget()), "call depth")
        print("AIMP script budget: \(AIMPSkinScript.Budget.stepLimit) steps spent in \(Int(spent)) ms")
    }

    // MARK: - The caches

    /// A value is made outside the cache's lock: another window's lookup goes through while one is
    /// being made (a blur, a mask), rather than waiting on the lock for it.
    func testCacheMakesOutsideItsLock() {
        let cache = AIMPSkinCache<Int, Int>(limit: 4)
        XCTAssertEqual(cache.value(1) { 10 }, 10)
        let looked = DispatchSemaphore(value: 0)
        let made = cache.value(2) { () -> Int in
            DispatchQueue.global().async {
                XCTAssertEqual(cache.value(1) { 0 }, 10)
                looked.signal()
            }
            XCTAssertEqual(looked.wait(timeout: .now() + 2), .success, "a lookup waited for a value being made")
            return 20
        }
        XCTAssertEqual(made, 20)
        XCTAssertEqual(cache.value(2) { 0 }, 20, "made once, then kept")
    }

    /// At most `limit` values are kept, the oldest stored let go first.
    func testCacheKeepsAtMostItsLimit() {
        let cache = AIMPSkinCache<Int, Int>(limit: 3)
        for key in 1...5 { _ = cache.value(key) { key } }
        XCTAssertEqual(cache.count, 3)
        XCTAssertEqual(cache.value(5) { -1 }, 5, "the newest kept")
        XCTAssertEqual(cache.value(3) { -1 }, 3)
        XCTAssertEqual(cache.value(1) { -1 }, -1, "the oldest let go, and made again")
        XCTAssertEqual(cache.count, 3)
    }

    // MARK: - The index

    func testIndexReadsFormsAndSchema() throws {
        let form = try Self.node("""
        <layout><items>
          <item name="Pages" class="LayoutTabbedGroup">
            <items><item name="PageA"/><item name="PageB"/></items>
          </item>
          <item name="Meters"><properties><property name="InitialVisible" value="False"/></properties></item>
        </items><controls>
          <control name="Reel" class="Animator"/>
          <control name="Selector" class="SliderMasked">
            <properties><property name="Bindings">
              <link Source="Mode" SourcePin="Position" TargetPin="Action" Expression="value+1"/>
            </property></properties>
          </control>
        </controls></layout>
        """)
        let schema = try Self.node("""
        <schema><providers>
          <provider name="Mode" class="LogicalOperatorCounter"><properties><property name="Module" value="3"/></properties></provider>
          <provider name="Blink" class="LogicalOperatorTimer"/>
          <provider name="Scale" class="Calculator"><properties><property name="Expression" value="value*2"/></properties></provider>
        </providers></schema>
        """)
        let speakers = AIMPSkin.Companion(name: "Speakers", title: "Speakers", form: try Self.node("<form name=\"Speakers\"/>"),
                                          initiallyVisible: false, role: .other)
        let index = AIMPSkinIndex(main: form, companions: [speakers], schema: schema)

        XCTAssertEqual(index.groups["Pages"], ["PageA", "PageB"])
        XCTAssertEqual(index.tabOf["PageB"]?.group, "Pages")
        XCTAssertEqual(index.tabOf["PageB"]?.index, 1)
        XCTAssertTrue(index.names.items.isSuperset(of: ["Pages", "PageA", "Meters", "Speakers"]))
        XCTAssertEqual(index.hiddenItems, ["Meters", "Speakers"])
        XCTAssertEqual(index.animatorList.compactMap(\.name), ["Reel"])
        XCTAssertEqual(index.timers.map(\.name), ["Blink"])
        XCTAssertEqual(index.selectorCounters, ["Mode"])
        XCTAssertEqual(index.counterModule("Mode"), 3)
        XCTAssertNil(index.counterModule("Blink"), "not a counter")
        XCTAssertEqual(Set(index.names.expressions.keys), ["value+1", "value*2"])
        XCTAssertEqual(index.expression("value*2")?.evaluate(value: 4), 8)
        XCTAssertEqual(index.expression("value-1")?.evaluate(value: 4), 3, "one the skin does not hold compiles now")
    }

    func testTabbedGroupsStartOnTheirFirstPageNotSavedHidden() throws {
        let hidden = "<properties><property name=\"InitialVisible\" value=\"False\"/></properties>"
        let form = try Self.node("""
        <form name="AIMPMainForm">
          <item name="Views" class="LayoutTabbedGroup">
            <items><item name="Compact">\(hidden)</item><item name="Full"/></items>
          </item>
          <item name="Lone" class="LayoutTabbedGroup"><items><item name="Only">\(hidden)</item></items></item>
          <item name="Plain" class="LayoutTabbedGroup"><items><item name="First"/><item name="Second">\(hidden)</item></items></item>
        </form>
        """)
        let index = AIMPSkinIndex(main: form, companions: [], schema: nil)

        XCTAssertEqual(index.initialPages["Views"], 1, "Unsquareable starts on its second page, the one saved shown")
        XCTAssertEqual(index.initialPages["Lone"], 0, "every page saved hidden: the group still shows its first")
        XCTAssertEqual(index.initialPages["Plain"], 0)
        XCTAssertTrue(index.hiddenItems.isDisjoint(with: ["Compact", "Only", "Second"]),
                      "a page shows by being its group's active one, not by what it was saved as")
    }

    func testDeclaredPlacementReadsSideAndOffset() throws {
        func placement(_ value: String, _ margins: String) throws -> AIMPSkin.Companion.DeclaredPlacement? {
            .init(try Self.node("<property name=\"Placement\" value=\"\(value)\" margins=\"\(margins)\"/>"))
        }
        XCTAssertEqual(try placement("1", "0,0,0,0")?.side, .above, "K-2's open glass lid stands on the deck")
        XCTAssertEqual(try placement("2", "0,-626,12,0").map { [$0.side == .right, $0.offset == -626] }, [true, true],
                       "Vilma M-212C's right speaker, its bottom level with the deck's")
        XCTAssertEqual(try placement("0", "0,0,0,0")?.side, .left)
        XCTAssertEqual(try placement("3", "0,10,0,10")?.offset, 10)
        XCTAssertNil(try placement("7", "0,0,0,0"))
        XCTAssertNil(AIMPSkin.Companion.DeclaredPlacement(nil))
    }

    func testCompanionsOpenBesideTheDeck() throws {
        let form = try Self.node("<layout/>")
        let deck = CGRect(x: 100, y: 500, width: 400, height: 200)
        func origin(_ name: String, _ size: CGSize) -> CGPoint {
            AIMPSkin.Companion(name: name, title: name, form: form, initiallyVisible: true, role: .other)
                .origin(size: size, beside: deck, scale: 2)
        }
        XCTAssertEqual(origin("LSpeaker", CGSize(width: 80, height: 100)), CGPoint(x: 20, y: 600), "left, tops level")
        XCTAssertEqual(origin("SpeakerRightWindow", CGSize(width: 80, height: 300)), CGPoint(x: 500, y: 500),
                       "a speaker taller than the deck stands level with its bottom")
        XCTAssertEqual(origin("Amplifier", CGSize(width: 300, height: 50)), CGPoint(x: 100, y: 450), "below, at its left edge")
        let lid = try Self.node(#"<property name="Placement" value="1" margins="0,0,0,7"/>"#)
        var k2 = AIMPSkin.Companion(name: "Lid", title: "Lid", form: form, initiallyVisible: true, role: .other)
        k2.declaredPlacement = .init(lid)
        XCTAssertEqual(k2.origin(size: CGSize(width: 200, height: 40), beside: deck, scale: 2), CGPoint(x: 200, y: 714),
                       "declared above: centred, its offset scaled")
    }

    // MARK: - Dock sites

    func testDockSitesMountTheFormsTheyName() throws {
        let main = try Self.node("""
        <layout><items>
          <item class="LayoutDockSite" name="PlaylistSite">
            <properties>
              <property name="ControlName" value="PlaylistFrame"/>
              <property name="ContentExtends" value="6,6,6,6"/>
            </properties>
          </item>
          <item class="LayoutDockSite" name="LibrarySite">
            <properties>
              <property name="AllowedForms" default="MusicLibraryFrame"/>
              <property name="InitialDocked" value="False"/>
            </properties>
          </item>
          <item class="LayoutDockSite" name="Spare">
            <properties><property name="AllowedForms" default="Visuals"/></properties>
          </item>
        </items></layout>
        """)
        let playlist = try Self.node("<layout><items><item name=\"PlaylistClient\"/></items></layout>")
        let library = try Self.node("<layout><items><item name=\"LibraryClient\"/></items></layout>")
        let sites = AIMPSkinDockSites.sites(in: main) { ["PlaylistFrame": playlist, "MusicLibraryFrame": library][$0] }

        XCTAssertEqual(Set(sites.keys), ["PlaylistSite", "LibrarySite"], "a site whose form the skin lacks holds nothing")
        XCTAssertEqual(sites["LibrarySite"]?.form, "MusicLibraryFrame")
        XCTAssertEqual(sites["PlaylistSite"]?.initiallyDocked, true)
        XCTAssertEqual(sites["LibrarySite"]?.initiallyDocked, false, "InitialDocked False starts it as a window")
        let holder = sites["PlaylistSite"]?.holder
        XCTAssertEqual(holder?["name"], "PlaylistFrame", "the form's keys show and hide it by its name")
        XCTAssertEqual(holder?.properties["AlignmentMargins"]?["value"], "-6,-6,-6,-6", "ContentExtends lays it out past the site")
        XCTAssertEqual(holder?.child("items")?.children("item").first?["name"], "PlaylistClient")

        let companions = [("PlaylistFrame", playlist), ("MusicLibraryFrame", library)].map {
            AIMPSkin.Companion(name: $0.0, title: $0.0, form: $0.1, initiallyVisible: true, role: .other)
        }
        let index = AIMPSkinIndex(main: main, companions: companions, schema: nil, sites: sites)
        XCTAssertEqual(index.siteOf["PlaylistFrame"], "PlaylistSite")
        XCTAssertEqual(index.parentOf["PlaylistSite"], nil, "a top-level item sits in the form")
        XCTAssertNotNil(index.byName["PlaylistClient"])
    }

    // MARK: - Layout

    func testClientItemsShareTheirParentSideBySide() throws {
        func item(_ xml: String) throws -> AIMPNode { try Self.node("<item><properties>\(xml)</properties></item>") }
        let fixed = try item("<property name=\"SizeMinimal\" value=\"100,0\"/><property name=\"SizeMaximal\" value=\"100,0\"/>")
        let late = try item("<property name=\"AlignmentLevel\" value=\"2\"/><property name=\"AlignmentMargins\" value=\"10,0,0,0\"/>")
        let grows = try item("<property name=\"AlignmentLevel\" value=\"1\"/>")
        let slots = AIMPSkinAlignment.share(CGRect(x: 0, y: 0, width: 300, height: 50), among: [fixed, late, grows].map(AIMPSkinItem.Layout.init),
                                       vertical: false)

        XCTAssertEqual(slots[0], CGRect(x: 0, y: 0, width: 100, height: 50), "a fixed group keeps its width (Office 2016's ribbon)")
        XCTAssertEqual(slots[2], CGRect(x: 100, y: 0, width: 95, height: 50), "the growing ones split the rest, in AlignmentLevel order")
        XCTAssertEqual(slots[1], CGRect(x: 195, y: 0, width: 105, height: 50), "margins included in the slot")
        let stacked = AIMPSkinAlignment.share(CGRect(x: 0, y: 0, width: 50, height: 200), among: [grows, grows].map(AIMPSkinItem.Layout.init),
                                         vertical: true)
        XCTAssertEqual(stacked.map(\.minY), [0, 100], "under ldVertical one above another")
    }

    func testEachEdgeDocksItsItemsByLevel() throws {
        let form = try Self.node("""
        <layout><items>
          <item name="Boxes"><properties><property name="Alignment" value="laBottom"/><property name="AlignmentLevel" value="2"/></properties></item>
          <item name="Caption"><properties><property name="Alignment" value="laTop"/></properties></item>
          <item name="Deck"><properties><property name="Alignment" value="laBottom"/><property name="AlignmentLevel" value="1"/></properties></item>
          <item name="Amplifier"><properties><property name="Alignment" value="laBottom"/></properties></item>
        </items></layout>
        """)
        let items = form.child("items")?.children("item") ?? []
        XCTAssertEqual(AIMPSkinAlignment.levelOrder(items.map(AIMPSkinItem.Layout.init)).map { items[$0]["name"] }, ["Amplifier", "Caption", "Deck", "Boxes"],
                       "level 0 docks first, against the edge; the top bar keeps its place between them")
    }

    func testClientsHoldWhatTheyNeed() throws {
        let free = try Self.node(#"<item><properties><property name="Alignment" value="laClient"/></properties></item>"#)
        // LX-tix: a cover and info panel needing 400 px of a 420-px row, beside an empty client.
        let slots = AIMPSkinAlignment.share(CGRect(x: 0, y: 0, width: 420, height: 50), among: [free, free].map(AIMPSkinItem.Layout.init), vertical: false,
                                          minimums: [400, 0])
        XCTAssertEqual(slots.map(\.width), [410, 10], "the content minimum, then the rest evenly")
    }

    func testDockedChildrenAddUp() {
        let bar = CGSize(width: 300, height: 20), panel = CGSize(width: 50, height: 100), list = CGSize(width: 200, height: 80)
        let docked: [(dock: AIMPSkinDock?, size: CGSize)] = [(.top, bar), (.left, panel), (.client, list), (nil, bar)]
        XCTAssertEqual(AIMPSkinAlignment.aggregate(docked, clients: .share(row: true)), CGSize(width: 300, height: 140),
                       "bars and undocked items stack over the panels beside the client")
        let clients: [(dock: AIMPSkinDock?, size: CGSize)] = [(.client, panel), (.client, list)]
        XCTAssertEqual(AIMPSkinAlignment.aggregate(clients, clients: .share(row: true)), CGSize(width: 250, height: 100), "along the row")
        XCTAssertEqual(AIMPSkinAlignment.aggregate(clients, clients: .share(row: false)), CGSize(width: 200, height: 180), "down it")
        XCTAssertEqual(AIMPSkinAlignment.aggregate(clients, clients: .overlap), CGSize(width: 200, height: 100), "as alternatives")
    }

    func testTabbedGroupsTakePartByTheirPages() throws {
        let group = """
        <item name="Pages" class="LayoutTabbedGroup"><items>
          <item name="First"><properties><property name="Visible" value="False"/></properties></item>
          <item name="Second"/>
          <item name="Third"><properties><property name="AutoHide" value="True"/><property name="Visible" value="False"/></properties></item>
        </items></item>
        """
        let index = AIMPSkinIndex(main: try Self.node("<layout><items>\(group)</items></layout>"), companions: [], schema: nil)
        let read = try XCTUnwrap(index.form(nil)?.item(named: "Pages"))
        func names(_ choice: AIMPSkinAlignment.Pages, _ shown: (AIMPSkinItem) -> Bool) -> [String] {
            AIMPSkinAlignment.participants(read.items, of: read, pages: choice, index: index, isShown: shown).compactMap(\.name)
        }
        XCTAssertEqual(names(.every) { $0.savedShown }, ["Second", "Third"], "AutoHide shows whatever was saved")
        XCTAssertEqual(names(.everyElseFirst) { _ in false }, ["First"], "none shown: the first still measures")
        XCTAssertEqual(names(.active { _ in 2 }) { AIMPSkinAlignment.startsShown($0, in: index) }, ["Third"], "the active page alone")
        XCTAssertEqual(index.initialPages["Pages"], 1, "a group starts on its first page saved shown")
        XCTAssertFalse(index.hiddenItems.contains("Third"))
    }

    /// A frame's size and the least size measure an item alike: what it holds docked, each child in
    /// its slot with its `AlignmentMargins`, as the layout then places it. (The frame's measure used
    /// to leave the margins out of a pictureless holder, so its bar was inset to half its height.)
    @MainActor func testFrameAndLeastSizesCountChildMargins() throws {
        let skin = try AIMPSkinScriptTests.skin(form: """
        <layout><items>
          <item name="Holder"><properties><property name="Alignment" value="laTop"/></properties><items>
            <item name="Bar"><properties><property name="Alignment" value="laTop"/><property name="Size" value="100,20"/>
              <property name="SizeMinimal" value="100,20"/><property name="AlignmentMargins" value="5,5,5,5"/></properties></item>
          </items></item>
        </items></layout>
        """)
        let layout = AIMPSkinLayout(flow: AIMPSkinDataflow(skin: skin, host: .init(), state: .init()))
        let holder = try XCTUnwrap(skin.index.form(nil)?.item(named: "Holder"))
        XCTAssertEqual(layout.size(holder), CGSize(width: 110, height: 30))
        XCTAssertEqual(layout.leastSize(holder), layout.size(holder))
        let tree = try XCTUnwrap(layout.tree(size: CGSize(width: 200, height: 100)))
        let bar = try XCTUnwrap(tree.root.items.first?.items.first)
        XCTAssertEqual(bar.rect, CGRect(x: 5, y: 5, width: 190, height: 20), "the bar keeps its 20 px inside its margins")
    }

    /// A main form gives the form docked in it at least its site's `SizeMinimal`: the deck docked
    /// over the site keeps its size and the window grows, rather than cutting the docked playlist
    /// to a strip (Trident 3).
    @MainActor func testAMainFormHoldsItsDockedFormAtItsSiteMinimum() throws {
        let skin = try AIMPSkinScriptTests.skin(form: """
        <layout><items>
          <item class="LayoutDockSite" name="PlaylistFrameSite"><properties><property name="Alignment" value="laClient"/>
            <property name="ControlName" value="PlaylistFrame"/><property name="SizeMinimal" value="100,120"/></properties></item>
          <item name="Main"><items>
            <item name="Deck"><properties><property name="Size" value="100,100"/></properties></item>
          </items></item>
        </items></layout>
        """, entries: [("PlaylistFrame.xml", #"<layout><items><item name="PlaylistClient"/></items></layout>"#)])
        XCTAssertEqual(skin.index.siteOf["PlaylistFrame"], "PlaylistFrameSite")
        let size = try XCTUnwrap(AIMPSkinRenderer.naturalSize(skin))
        XCTAssertEqual(size.height, 220, "the 100-px deck over the site's 120")
        let layout = AIMPSkinLayout(flow: AIMPSkinDataflow(skin: skin, host: .init(), state: .init()))
        XCTAssertEqual(layout.tree(size: size)?.offers.namedRects["PlaylistFrameSite"]?.height, 120)
    }

    func testColoursFollowResourcesAndLinks() throws {
        func resource(_ xml: String) throws -> [String: AIMPNode] { ["Resource": try Self.node(xml)] }
        let resources = [
            "Content.Background": try resource(#"<property name="Resource"><property name="ID" value="Content.Background.Dark"/></property>"#),
            "Content.Background.Dark": try resource(#"<property name="Resource"><property name="Value" value="4282137660"/></property>"#),
            "Content.Background.Light": try resource(#"<property name="Resource"><property name="Value" value="4294967295"/></property>"#),
        ]
        XCTAssertEqual(AIMPSkin.color("Content.Background", in: resources), 0xFF3C_3C3C, "a resource naming another")
        XCTAssertEqual(AIMPSkin.color("Content.Background", in: resources, links: ["Content.Background": "Content.Background.Light"]),
                       0xFFFF_FFFF, "a theme a script repointed")
        XCTAssertNil(AIMPSkin.color("clrNone", in: resources))
    }

    /// Images, colours and fonts resolve through one resolver: a `link` or an `ID` naming another
    /// resource, and a script's repointing first.
    func testResourcesResolveOneWayForImagesColoursAndFonts() throws {
        func resource(_ xml: String) throws -> [String: AIMPNode] { ["Resource": try Self.node(xml)] }
        let resources = [
            "Bobina": try resource(#"<property name="Resource" link="Bob"/>"#),
            "Bob": try resource(#"<property name="Resource" value="BobResource"/>"#),
            "Font.Title": try resource(#"<property name="Resource"><property name="ID" value="Font.Big"/><property name="Color" value="4278190335"/></property>"#),
            "Font.Big": try resource(#"<property name="Resource"><property name="Name" value="Arial"/><property name="Height" value="20"/></property>"#),
            "Font.Small": try resource(#"<property name="Resource"><property name="Height" value="9"/></property>"#),
        ]
        let bob = AIMPSkin.resource("Bobina", in: resources)
        XCTAssertEqual(bob?.id, "Bob")
        XCTAssertEqual(bob?.node?["value"], "BobResource")
        XCTAssertEqual(AIMPSkin.resource("Picture", in: resources)?.id, "Picture", "an entry named directly")
        XCTAssertEqual(AIMPSkin.resource("Self", in: ["Self": try resource(#"<property name="Resource" link="Self"/>"#)])?.id, "Self",
                       "one naming itself is itself")
        XCTAssertNil(AIMPSkin.resource("Ping", in: ["Ping": try resource(#"<property name="Resource" link="Pong"/>"#),
                                                     "Pong": try resource(#"<property name="Resource" link="Ping"/>"#)]))

        let font = AIMPSkinFont(try Self.node(#"<property name="Font"><property name="ID" value="Font.Title"/></property>"#), resources: resources)
        XCTAssertEqual(font.name, "Arial", "a font resource naming another")
        XCTAssertEqual(font.height, 20)
        XCTAssertEqual(font.color, 0xFF00_00FF, "its own colour over the font it names")
        XCTAssertEqual(font.resource?.id, "Font.Title")
        let repointed = try XCTUnwrap(AIMPSkin.resource("Font.Title", in: resources, links: ["Font.Title": "Font.Small"])?.chain)
        XCTAssertEqual(AIMPSkinFont(resource: repointed), AIMPSkinFont(name: "Tahoma", height: 9, bold: false, color: 0xFFFF_FFFF),
                       "a font a script repointed")
        var sized = font
        sized.height = 30
        let drawn = sized.resolved(in: resources, links: ["Font.Title": "Font.Small"])
        XCTAssertEqual(drawn.name, "Tahoma", "the repointed resource's face")
        XCTAssertEqual(drawn.height, 30, "what the skin set over the resource stays")
        XCTAssertEqual(font.resolved(in: resources, links: [:]), font)
    }

    func testDelphiColoursReadAsARGB() {
        XCTAssertEqual(AIMPSkinColor.argb(delphi: 0x0033_66CC), 0xFFCC_6633, "$00BBGGRR, opaque")
        XCTAssertEqual(AIMPSkinColor.argb(delphi: 0x80FF_0000), 0x80FF_0000, "the top byte set: ARGB already")
        XCTAssertEqual(AIMPSkinColor.argb(delphi: 0xFF00_0005), 0xFFFF_FFFF, "a system colour (the window's)")
    }

    private static func node(_ xml: String) throws -> AIMPNode {
        try AIMPNode.parse(Data(xml.utf8), name: "test.xml")
    }

    /// A project file (`ACSJ`) of `entries`: the header (13 bytes), the metadata block (u32 length:
    /// name, author, about, no preview), the entry count and the entries.
    private static func project(_ entries: [(String, Data)], languages: [String] = ["en"]) throws -> AIMPSkin {
        func utf16LE(_ text: String) -> Data {
            Data([UInt8(text.utf16.count & 0xFF), UInt8(text.utf16.count >> 8)]) + (text.data(using: .utf16LittleEndian) ?? Data())
        }
        func u32(_ value: Int) -> Data { withUnsafeBytes(of: UInt32(value).littleEndian) { Data($0) } }
        let meta = utf16LE("Test") + utf16LE("") + utf16LE("") + [0]
        var data = Data("ACSJ".utf8) + Data(count: 9) + u32(meta.count) + meta + u32(entries.count)
        for (name, bytes) in entries { data += utf16LE(name) + u32(bytes.count) + bytes }
        return try AIMPSkinLoader.load(data: data, languages: languages)
    }
}
