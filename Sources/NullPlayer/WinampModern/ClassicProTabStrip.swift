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
/// so the engine builds them hidden (`prepareFlags`), and once it has built the strip every flag is
/// cleared (`attach`). A close sets its tab's flag for the one switch that removes it.
///
/// **The tab's own right-click *Auto Close Tab* is withheld** (`attach`). Chosen, it sets
/// the same flag and takes the tab out of the strip — at once if the tab is not the selected one,
/// otherwise at the next switch — so tabs left the strip behind the Windows menu's back.
struct ClassicProTabStrip {
    struct Tab: Equatable {
        /// The tab's long name — its button's tooltip. The label itself drops to `LIB`/`PLE` when the
        /// strip is narrow.
        let label: String
        let identity: Identity
        let isInStrip: Bool
        let isActive: Bool

        enum Identity: Equatable {
            /// One of the engine's own tabs, by its tab number.
            case engine(Int32)
            /// A widget tab, by the widget's id.
            case widget(String)
        }

        /// The suffix of the tab's `…One.TabAutoClose.<key>` flag.
        var flagKey: String {
            switch identity {
            case .engine(let number): return String(number)
            case .widget(let id): return id
            }
        }
        /// The host surface this tab is — Media Library the Library Browser, Playlist the Playlist
        /// Editor — so the Windows menu lists it under that item rather than its own.
        var kind: WinampModernComponentKind? {
            switch identity {
            case .engine(0): return .library
            case .engine(1): return .playlist
            default: return nil
            }
        }
    }

    /// The two engine families spell their tab state differently (`CproTabs.m` in `_v1` and `_v2`).
    private struct Family {
        let publicPrefix: String
        /// `internalNames`, in tab-number order.
        let internalNames: [String]
        /// `internalNamesShort`, in tab-number order; empty for engine two, which always shows the
        /// long names.
        let shortNames: [String]
    }
    private static let one = Family(publicPrefix: "Cpro",
                                    internalNames: ["Media Library", "Playlist", "Video", "Visualization", "Browser", "Plugin"],
                                    shortNames: ["LIB", "PLE", "VID", "VIS", "BRO", "PLU"])
    private static let two = Family(publicPrefix: "cpro2",
                                    internalNames: ["Media Library", "Playlist", "Video", "Visualization", "Web Reader", "Plugin"],
                                    shortNames: [])
    /// Engine one's `alignByResize`: a tab is its label's `getAutoWidth()` plus this, and never
    /// squeezed below the floor.
    private static let tabPadding: Int32 = 14
    private static let tabFloor = 20.0
    /// The room a squeezed long label keeps past its last glyph before the row falls back to the
    /// short names.
    private static let inkClearance: CGFloat = 2

    /// Where the host keeps the closed tabs' flag keys, one per line.
    private static let closedSection = "@nullplayer.tabs"
    private static let closedKey = "closed"

    /// The tab number `switch_to_tab` takes for a widget tab, which its widget argument then names.
    private static let widgetTabNumber: Int32 = -666
    /// The engine's catch-all plugin page: hidden whenever it is not on screen, whatever anyone chose.
    private static let pluginTabNumber: Int32 = 5

    private let runtime: WinampModernScriptRuntime
    private let buttons: WasabiObject
    private let widgetLoader: WasabiObject?
    private let family: Family
    /// Select a tab, as `switch_to_tab` does.
    private let switchTo: (Tab) -> Void

    /// Nil unless the loaded skin runs the ClassicPro strip. `switchTab` stands in for the engine's
    /// `switch_to_tab`, which by default is sent to the SUI as `onaction`.
    init?(runtime: WinampModernScriptRuntime, switchTab: ((Tab) -> Void)? = nil) {
        let graph = runtime.loadedSkin.runtime.graph
        guard let (buttons, sui) = Self.locate(in: graph) else { return nil }
        self.runtime = runtime
        self.buttons = buttons
        // The strip's own bucket, beside its buttons: the player's drawer has a `widget.loader` too
        // (`centro.widgets.drawer`), and Venus Alpha declares that one first.
        widgetLoader = buttons.parent?.children.first { $0.xmlID == "widget.loader" }
        family = Self.family(of: buttons)
        switchTo = switchTab ?? { tab in
            let (widget, number): (String, Int32) = switch tab.identity {
            case .engine(let number): ("", number)
            case .widget(let id): (id, Self.widgetTabNumber)
            }
            _ = try? runtime.dispatch(object: sui, event: "onaction",
                                      arguments: [.string("switch_to_tab"), .string(widget), .integer(number),
                                                  .integer(0), .integer(0), .integer(0), .null])
        }
    }

    /// The strip's buttons and the SUI that switches it, or nil when the skin runs no ClassicPro strip.
    private static func locate(in graph: WasabiObjectGraph) -> (buttons: WasabiObject, sui: WasabiObject)? {
        guard let strip = graph.objects(xmlID: "Cpro.tabs").first,
              let buttons = graph.objects(xmlID: "cprotabs.buttons").first,
              let sui = sequence(first: strip, next: \.parent).prefix(64).first(where: {
                  $0.typeName.caseInsensitiveCompare("Centro:SUI") == .orderedSame
              })
        else { return nil }
        return (buttons, sui)
    }

    /// Before the scripts start: flag the tabs closed at the last unload so the engine builds them
    /// hidden, and nothing else.
    static func prepareFlags(in loaded: WinampModernLoadedSkin) {
        guard let (buttons, _) = locate(in: loaded.runtime.graph) else { return }
        let configuration = loaded.configuration
        let family = family(of: buttons)
        clearFlags(family, in: configuration)
        for key in closedKeys(in: configuration) {
            configuration.setInteger(1, section: "@public", key: "\(family.publicPrefix).One.TabAutoClose.\(key)")
        }
    }

    /// Once the engine has built its tabs — engine one in `start()`, engine two from `onSetVisible` —
    /// the flags go and the tab menu's *Auto Close Tab* is withheld, so no tab leaves the strip on its
    /// own. Nil unless the loaded skin runs the strip.
    static func attach(to runtime: WinampModernScriptRuntime) -> ClassicProTabStrip? {
        guard let strip = ClassicProTabStrip(runtime: runtime) else { return nil }
        clearFlags(strip.family, in: runtime.loadedSkin.configuration)
        runtime.withheldPopupTitles.insert("Auto Close Tab")
        return strip
    }

    private static func clearFlags(_ family: Family, in configuration: WinampModernConfiguration) {
        configuration.removeKeys(section: "@public", prefix: "\(family.publicPrefix).One.TabAutoClose.")
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

    /// Which engine built the strip, from where its `CproTabs.maki` lives (`…\CentroSUI\_v2\…`).
    /// The script belongs to the `cprotabs.xui` group holding the buttons, bound before any script
    /// runs.
    private static func family(of buttons: WasabiObject) -> Family {
        let paths = sequence(first: buttons, next: \.parent).prefix(4)
            .flatMap(\.scriptBindings).map { $0.logicalPath.lowercased() }
        return paths.contains { $0.contains("_v2") } ? two : one
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

    /// Forget the stored order and the closed tabs, so the next load builds every tab in the
    /// engine's own order. Only between unloading the skin and loading it again: `CproTabs.m` writes
    /// the order back from `onScriptUnloading`.
    static func resetLayout(in configuration: WinampModernConfiguration) {
        configuration.removeKeys(section: "ClassicPro", prefix: "TabOrder_")
        configuration.removeSection(closedSection)
    }

    /// Whether a Windows-menu item the skin registered is one of the strip's own — "Web Browser" and
    /// each widget tab's name, which `CproTabs.m` adds so Winamp's menu can reach them. The strip's
    /// tab items replace them.
    func ownsMenuItem(named name: String) -> Bool {
        WinampModernContainerTopology.menuLabel(name) == "Web Browser" || tab(named: name) != nil
    }

    /// Engine one's `alignByResize` shows the long names whenever the strip is wider than 50px a tab,
    /// then squeezes every tab by one ratio when the names need more room than that, so in between
    /// (a 500px window with the side playlist closed) each label is cut mid-letter: `Media Librar`.
    /// When a long label is squeezed, the row goes back to the short names, laid out as the script's
    /// own narrow branch lays them. Run after every script event that moved something: the script's
    /// next `alignByResize` writes the long names back, and its `alignFull` — the row fits again —
    /// widens the tabs without touching their text, so a short label in a tab wider than itself
    /// gets its long name back here.
    func fitLabels() {
        guard !family.shortNames.isEmpty,
              let stripWidth = runtime.resolvedFrame(of: buttons, in: .parent)?.width else { return }
        let row = buttons.children
            .compactMap { group -> (group: WasabiObject, text: WasabiObject, long: String, short: String)? in
                guard let tab = tab(of: group), tab.isInStrip,
                      let text = runtime.descendant(of: group, xmlID: "cpro.tab.text"),
                      let short = shortName(of: tab) else { return nil }
                return (group, text, tab.label, short)
            }
            .sorted { (Int($0.group.attributes["x"] ?? "") ?? 0) < (Int($1.group.attributes["x"] ?? "") ?? 0) }
        func width(of group: WasabiObject) -> Int32 { Int32(group.attributes["w"] ?? "") ?? 0 }
        func label(_ text: WasabiObject, _ value: String) -> Double {
            if text.attributes["text"] != value {
                _ = text.setAttribute("text", value: value)
                runtime.notifyObjectDidMutate(text)
            }
            return Double(runtime.autoWidth(of: text) + Self.tabPadding)
        }
        for entry in row where entry.text.attributes["text"] == entry.short
            && width(of: entry.group) > runtime.autoWidth(of: entry.text) + Self.tabPadding {
            _ = label(entry.text, entry.long)
        }
        // Squeezed past its ink, not past its padding: a tab is 18px wider than its string (the 14
        // plus the measurement's `boxMargin`), and the script's ratio eats that slack first.
        let squeezed = row.contains { entry in
            let ink = CGFloat(runtime.autoWidth(of: entry.text)) - WasabiTextMetrics.boxMargin
            let inset = CGFloat(Double(entry.text.attributes["x"] ?? "") ?? 0)
            return entry.text.attributes["text"] != entry.short
                && CGFloat(width(of: entry.group)) < inset + ink + Self.inkClearance
        }
        guard squeezed else { return }
        let natural = row.map { label($0.text, $0.short) }
        let floors = Double(row.count) * Self.tabFloor
        let ratio = min(1, max(0, (Double(stripWidth) - floors) / (natural.reduce(0, +) - floors)))
        var x = 0
        for (entry, width) in zip(row, natural) {
            let w = Int((width - Self.tabFloor) * ratio + Self.tabFloor)
            runtime.writeGeometry([("x", String(x)), ("w", String(w))], on: entry.group)
            x += w
        }
    }

    /// The script's `nameShort`: the engine's own abbreviation, or a widget's short name (its
    /// bucket entry's `name="Long;Short"`, else the long one) cut to three letters and uppercased.
    private func shortName(of tab: Tab) -> String? {
        switch tab.identity {
        case .engine(let number):
            return family.shortNames.indices.contains(Int(number)) ? family.shortNames[Int(number)] : nil
        case .widget:
            let names = widgetEntry(named: tab.label)?.attributes["name"]?.components(separatedBy: ";") ?? [tab.label]
            let source = names.count > 1 && !names[1].isEmpty ? names[1] : names[0]
            return String(source.prefix(3)).uppercased()
        }
    }

    // MARK: -

    private func tab(of group: WasabiObject) -> Tab? {
        guard let button = group.children.first(where: { $0.xmlID == "cpro.tab.button" }),
              let label = button.attributes["tooltip"], !label.isEmpty else { return nil }
        let identity: Tab.Identity
        if let index = family.internalNames.firstIndex(of: label) {
            identity = .engine(Int32(index))
        } else if let id = widgetID(named: label) {
            identity = .widget(id)
        } else {
            return nil
        }
        guard identity != .engine(Self.pluginTabNumber) else { return nil }
        let visible = group.attributes["visible"]?.lowercased()
        return Tab(label: label, identity: identity,
                   isInStrip: visible != "0" && visible != "false",
                   isActive: button.attributes["activated"] == "1")
    }

    /// A widget's id, from the component bucket the engine builds its widget tabs from
    /// (`name="Long;Short"`, `userdata="ids;statusbar"`).
    private func widgetID(named label: String) -> String? {
        widgetEntry(named: label)?.attributes["userdata"]?.components(separatedBy: ";").first
    }

    private func widgetEntry(named label: String) -> WasabiObject? {
        widgetLoader?.children.first { $0.attributes["name"]?.components(separatedBy: ";").first == label }
    }

    private func setAutoClose(_ on: Bool, for tab: Tab) {
        let key = "\(family.publicPrefix).One.TabAutoClose.\(tab.flagKey)"
        if on {
            runtime.loadedSkin.configuration.setInteger(1, section: "@public", key: key)
        } else {
            runtime.loadedSkin.configuration.removeValue(section: "@public", key: key)
        }
    }
}
