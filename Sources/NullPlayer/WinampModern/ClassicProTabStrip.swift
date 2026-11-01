import Foundation

/// ClassicPro's SUI tab strip, read from the graph and driven through the engine's own messages (B350).
///
/// The strip belongs to `CproTabs.m`. A tab is **open** while it is in the strip and **closed** once
/// the engine has taken it out, and the Windows menu ticks exactly the open ones. The host never
/// edits the strip, it sends the engine's own messages: the SUI's `switch_to_tab` opens a tab, pulling
/// a hidden one back in, and a tab whose *Auto Close Tab* flag is set leaves the strip as it is
/// switched away from (`closeTab` → `removeTab`), which is how the host closes one.
///
/// **The flag is a load-time mechanism only.** Left set during a session it removes a tab behind
/// the user's back: the engine reopens a closed tab by itself (the side playlist opening over the
/// Playlist page switches to Media Library; a film starting switches to Video), and that tab would
/// vanish again at the next click. So which tabs are closed is the host's record, snapshotted from
/// the strip as the skin unloads (`recordClosedTabs`); before the scripts start their flags are set
/// so the engine builds them hidden (`prepareFlags`), and once they have started every flag is
/// cleared (`clearFlags`). A close sets its tab's flag for the one switch that removes it.
///
/// **The tab's own right-click *Auto Close Tab* is withheld** (`withholdAutoClose`). Chosen, it sets
/// the same flag and takes the tab out of the strip — at once if the tab is not the selected one,
/// otherwise at the next switch — so tabs left the strip behind the Windows menu's back.
struct ClassicProTabStrip {
    struct Tab: Equatable {
        /// The tab's long name — its button's tooltip. The label itself drops to `LIB`/`PLE` when the
        /// strip is narrow.
        let label: String
        /// The engine's tab number, or `widgetTabID` for a widget tab, which `widget` then names.
        let id: Int32
        let widget: String
        let isInStrip: Bool
        let isActive: Bool
        /// The suffix of the tab's `…One.TabAutoClose.<key>` flag.
        var flagKey: String { widget.isEmpty ? String(id) : widget }
        /// The host surface this tab is — Media Library the Library Browser, Playlist the Playlist
        /// Editor — so the Windows menu lists it under that item rather than its own.
        var kind: WinampModernComponentKind? {
            guard widget.isEmpty else { return nil }
            switch id {
            case 0: return .library
            case 1: return .playlist
            default: return nil
            }
        }
    }

    /// The two engine families spell their tab state differently (`CproTabs.m` in `_v1` and `_v2`).
    private struct Family {
        let publicPrefix: String
        /// `internalNames`, in tab-number order.
        let internalNames: [String]
    }
    private static let one = Family(publicPrefix: "Cpro",
                                    internalNames: ["Media Library", "Playlist", "Video", "Visualization", "Browser", "Plugin"])
    private static let two = Family(publicPrefix: "cpro2",
                                    internalNames: ["Media Library", "Playlist", "Video", "Visualization", "Web Reader", "Plugin"])

    /// Where the host keeps the closed tabs' flag keys, one per line.
    private static let closedSection = "@nullplayer.tabs"
    private static let closedKey = "closed"

    static let widgetTabID: Int32 = -666
    /// The engine's catch-all plugin page: hidden whenever it is not on screen, whatever anyone chose.
    private static let pluginTabID: Int32 = 5

    private let runtime: WinampModernScriptRuntime
    private let sui: WasabiObject
    private let buttons: WasabiObject
    private let widgetLoader: WasabiObject?
    private let family: Family

    /// Nil unless the loaded skin runs the ClassicPro strip.
    init?(runtime: WinampModernScriptRuntime) {
        let graph = runtime.loadedSkin.runtime.graph
        guard let strip = graph.objects(xmlID: "Cpro.tabs").first,
              let buttons = graph.objects(xmlID: "cprotabs.buttons").first,
              let sui = sequence(first: strip, next: \.parent).prefix(64).first(where: {
                  $0.typeName.caseInsensitiveCompare("Centro:SUI") == .orderedSame
              })
        else { return nil }
        self.runtime = runtime
        self.sui = sui
        self.buttons = buttons
        widgetLoader = graph.objects(xmlID: "widget.loader").first
        family = Self.family(of: runtime.loadedSkin.configuration)
    }

    /// Before the scripts start: flag the tabs closed at the last unload so the engine builds them
    /// hidden, and nothing else.
    static func prepareFlags(in loaded: WinampModernLoadedSkin) {
        guard !loaded.runtime.graph.objects(xmlID: "Cpro.tabs").isEmpty else { return }
        let configuration = loaded.configuration
        clearFlags(in: configuration)
        let prefix = family(of: configuration).publicPrefix
        for key in closedKeys(in: configuration) {
            configuration.setInteger(1, section: "@public", key: "\(prefix).One.TabAutoClose.\(key)")
        }
    }

    /// Once the scripts have started: no tab may leave the strip on its own.
    static func clearFlags(in configuration: WinampModernConfiguration) {
        for family in [one, two] {
            configuration.removeSection("@public", keyPrefix: "\(family.publicPrefix).One.TabAutoClose.")
        }
    }

    /// The tabs out of the strip now: after each open and close, and as the skin unloads or the app
    /// quits — the engine reopens tabs by itself too.
    func recordClosedTabs() {
        let keys = tabs.filter { !$0.isInStrip }.map(\.flagKey)
        runtime.loadedSkin.configuration.setString(keys.joined(separator: "\n"),
                                                   section: Self.closedSection, key: Self.closedKey)
    }

    private static func closedKeys(in configuration: WinampModernConfiguration) -> [String] {
        configuration.string(section: closedSection, key: closedKey)
            .split(separator: "\n").map(String.init)
    }

    // ponytail: the family is read from which spelling of the active page the engine has written,
    // which it does on its first tab switch; a skin's very first load reads as `one`, harmless then
    // because nothing is closed yet. A graph marker would be sturdier.
    private static func family(of configuration: WinampModernConfiguration) -> Family {
        configuration.integer(section: "@public", key: "cpro2.lastComponentPage", default: -1) == -1 ? one : two
    }

    /// Every tab the engine built, open ones first in strip order, then the closed ones. The plugin
    /// page is left out: nothing the user does keeps it open.
    var tabs: [Tab] {
        let built = buttons.children.compactMap { group in tab(of: group).map { (group: group, tab: $0) } }
        let open = built.filter(\.tab.isInStrip)
            .sorted { (Int($0.group.attributes["x"] ?? "") ?? 0) < (Int($1.group.attributes["x"] ?? "") ?? 0) }
        return (open + built.filter { !$0.tab.isInStrip }).map(\.tab)
    }

    func tab(named label: String) -> Tab? { tabs.first { $0.label == label } }

    /// The tab holding a surface the host also lists (Library Browser, Playlist Editor).
    func tab(for kind: WinampModernComponentKind) -> Tab? { tabs.first { $0.kind == kind } }

    /// Whether the tab can leave the strip: the last open tab cannot, or the strip would be empty.
    static func canClose(_ tab: Tab, among tabs: [Tab]) -> Bool {
        tab.isInStrip && tabs.filter(\.isInStrip).count > 1
    }

    /// Put the tab in the strip and select it.
    func open(_ tab: Tab) {
        switchTo(tab)
        recordClosedTabs()
    }

    /// Take the tab out of the strip, unless it is the last one there.
    func close(_ tab: Tab) {
        let tabs = tabs
        let open = tabs.filter(\.isInStrip)
        guard Self.canClose(tab, among: tabs), let index = open.firstIndex(of: tab) else { return }
        let neighbour = index > 0 ? open[index - 1] : open[index + 1]
        setAutoClose(true, for: tab)
        if tab.isActive {
            switchTo(neighbour)
        } else {
            // The engine removes a tab only as it is switched away from.
            let previous = open.first(where: \.isActive) ?? neighbour
            switchTo(tab)
            switchTo(previous)
        }
        setAutoClose(false, for: tab)
        recordClosedTabs()
    }

    /// Forget the stored order and every Auto Close flag, so the next load builds every tab in the
    /// engine's own order. Only between unloading the skin and loading it again: `CproTabs.m` writes
    /// the order back from `onScriptUnloading`.
    static func resetLayout(in configuration: WinampModernConfiguration) {
        configuration.removeSection("ClassicPro", keyPrefix: "TabOrder_")
        configuration.removeSection(closedSection)
        clearFlags(in: configuration)
    }

    /// Whether a Windows-menu item the skin registered is one of the strip's own — "Web Browser" and
    /// each widget tab's name, which `CproTabs.m` adds so Winamp's menu can reach them. The strip's
    /// tab items replace them.
    func ownsMenuItem(named name: String) -> Bool {
        WinampModernContainerTopology.menuLabel(name) == "Web Browser" || tab(named: name) != nil
    }

    /// Leave the tab menu's *Auto Close Tab* out of every script-built popup from now on. Once the
    /// scripts have started, when the view's presenter is in place.
    func withholdAutoClose() {
        guard let present = runtime.popupPresenter else { return }
        runtime.popupPresenter = { items, point in
            present(items.filter { $0.title != "Auto Close Tab" }, point)
        }
    }

    // MARK: -

    private func tab(of group: WasabiObject) -> Tab? {
        guard let button = group.children.first(where: { $0.xmlID == "cpro.tab.button" }),
              let label = button.attributes["tooltip"], !label.isEmpty else { return nil }
        let id: Int32
        var widget = ""
        if let index = family.internalNames.firstIndex(of: label) {
            id = Int32(index)
        } else if let ids = widgetID(named: label) {
            id = Self.widgetTabID
            widget = ids
        } else {
            return nil
        }
        guard id != Self.pluginTabID else { return nil }
        let visible = group.attributes["visible"]?.lowercased()
        return Tab(label: label, id: id, widget: widget,
                   isInStrip: visible != "0" && visible != "false",
                   isActive: button.attributes["activated"] == "1")
    }

    /// A widget's id, from the component bucket the engine builds its widget tabs from
    /// (`name="Long;Short"`, `userdata="ids;statusbar"`).
    private func widgetID(named label: String) -> String? {
        widgetLoader?.children.first {
            $0.attributes["name"]?.components(separatedBy: ";").first == label
        }?.attributes["userdata"]?.components(separatedBy: ";").first
    }

    private func setAutoClose(_ on: Bool, for tab: Tab) {
        let key = "\(family.publicPrefix).One.TabAutoClose.\(tab.flagKey)"
        if on {
            runtime.loadedSkin.configuration.setInteger(1, section: "@public", key: key)
        } else {
            runtime.loadedSkin.configuration.removeValue(section: "@public", key: key)
        }
    }

    private func switchTo(_ tab: Tab) {
        _ = try? runtime.dispatch(object: sui, event: "onaction",
                                  arguments: [.string("switch_to_tab"), .string(tab.widget), .integer(tab.id),
                                              .integer(0), .integer(0), .integer(0), .null])
    }
}
