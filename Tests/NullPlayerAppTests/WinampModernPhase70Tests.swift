import XCTest
@testable import NullPlayer

/// Phase 70 (BENTO_TASKS BB29) — a skin's settings start in a state its own scripts can express.
///
/// Big Bento Modern's tab strip has three modes, held as a radio group of `cfgattrib`s in its
/// `Appearance` item. `loadattribs.maki` registers all three with a `"0"` default, and
/// `tabswitch.maki` / `tabcontrol.maki` / `tabbutton.maki` are each a three-way `if` with **no
/// `else`** — so a profile that has never run the skin reads all-zero and runs none of them. The
/// divider between the strip and the panel then keeps its markup `x` of 0 and draws over the icons,
/// and its button is dead for ever, because `onLeftClick` only cycles *between* the three states.
///
/// `WinampModernConfigDefaults` seeds the mode the markup is already laid out for, before the scripts
/// run. What these tests pin is the scoping, which is the whole risk of a rule like this: it is keyed
/// on the skin's own markup, it takes the section from that markup, and it never writes twice.
final class WinampModernPhase70Tests: XCTestCase {

    private let section = "{F1036C9C-3919-47ac-8494-366778CF10F9}"

    private func makeConfiguration(_ name: String = #function) -> WinampModernConfiguration {
        let suite = "WinampModernPhase70.\(name).\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
        return WinampModernConfiguration(namespace: "TestSkin", defaults: defaults)
    }

    /// The three checkboxes as Bento's `config.xml` writes them — including its own `+ text`
    /// mis-capitalization, which must not become the key that is written.
    private func bentoDocument() -> WalExpandedXMLDocument {
        let names = ["Tabs: Hidden", "Tabs: Icons", "Tabs: Icons + text"]
        let children = names.map {
            WalXMLNode(name: "togglebutton",
                       attributes: ["id": "tabs.checkbox", "cfgattrib": "\(section);\($0)"],
                       location: WalSourceLocation(path: "/Skins/TestSkin/xml/config.xml"))
        }
        let group = WalXMLNode(name: "groupdef", attributes: ["id": "tabs.options"],
                               location: WalSourceLocation(path: "/Skins/TestSkin/xml/config.xml"),
                               children: children)
        return WalExpandedXMLDocument(roots: [group], visitedPaths: [], diagnostics: [])
    }

    func testSeedsTheIconsModeWhenTheWholeGroupIsUnset() {
        let configuration = makeConfiguration()
        WinampModernConfigDefaults.apply(document: bentoDocument(), configuration: configuration)
        XCTAssertEqual(configuration.string(section: section, key: "Tabs: Icons"), "1")
        XCTAssertEqual(configuration.string(section: section, key: "Tabs: Hidden"), "")
        // The registered spelling, not the markup's.
        XCTAssertEqual(configuration.string(section: section, key: "Tabs: Icons + Text"), "")
        XCTAssertEqual(configuration.string(section: section, key: "Tabs: Icons + text"), "")
    }

    func testLeavesAChoiceTheUserAlreadyMadeAlone() {
        let configuration = makeConfiguration()
        configuration.setString("1", section: section, key: "Tabs: Icons + Text")
        WinampModernConfigDefaults.apply(document: bentoDocument(), configuration: configuration)
        XCTAssertEqual(configuration.string(section: section, key: "Tabs: Icons"), "")
        XCTAssertEqual(configuration.string(section: section, key: "Tabs: Icons + Text"), "1")
    }

    /// The all-`"0"` state a second launch reads back — the scripts wrote their defaults out, so the
    /// keys exist and are still a state the skin has no branch for. The seed has to heal it.
    func testHealsTheAllZeroStateAFirstLaunchLeftBehind() {
        let configuration = makeConfiguration()
        for key in ["Tabs: Hidden", "Tabs: Icons", "Tabs: Icons + Text"] {
            configuration.setString("0", section: section, key: key)
        }
        WinampModernConfigDefaults.apply(document: bentoDocument(), configuration: configuration)
        XCTAssertEqual(configuration.string(section: section, key: "Tabs: Icons"), "1")
    }

    func testWritesNothingForASkinThatDeclaresNoSuchGroup() {
        let configuration = makeConfiguration()
        let node = WalXMLNode(name: "togglebutton",
                              attributes: ["cfgattrib": "\(section);Show Winamp Logo"],
                              location: WalSourceLocation(path: "/Skins/TestSkin/xml/config.xml"))
        let document = WalExpandedXMLDocument(roots: [node], visitedPaths: [], diagnostics: [])
        WinampModernConfigDefaults.apply(document: document, configuration: configuration)
        XCTAssertEqual(configuration.string(section: section, key: "Tabs: Icons"), "")
    }

    /// One member bound in a different section is a different skin reusing a name, not this group.
    func testRequiresTheWholeGroupInOneSection() {
        let configuration = makeConfiguration()
        let nodes = [
            WalXMLNode(name: "togglebutton", attributes: ["cfgattrib": "\(section);Tabs: Icons"],
                       location: WalSourceLocation(path: "/Skins/TestSkin/xml/config.xml")),
            WalXMLNode(name: "togglebutton", attributes: ["cfgattrib": "{OTHER};Tabs: Hidden"],
                       location: WalSourceLocation(path: "/Skins/TestSkin/xml/config.xml"))
        ]
        let document = WalExpandedXMLDocument(roots: nodes, visitedPaths: [], diagnostics: [])
        WinampModernConfigDefaults.apply(document: document, configuration: configuration)
        XCTAssertEqual(configuration.string(section: section, key: "Tabs: Icons"), "")
    }
}
