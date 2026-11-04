import Foundation

/// What a skin's forms and `Schema.xml` declare, looked up by name, and the forms themselves read
/// into typed items and controls (`AIMPSkinItem`, `AIMPSkinControl`): worked out once as the skin
/// loads (off the main thread) and never changed, so the dataflow, scripts and renderer read it
/// many times a frame without rescanning the trees or parsing properties again.
struct AIMPSkinIndex: Sendable {
    /// Each tabbed group's tabs, in order, and each tab's group and index.
    var groups: [String: [String]] = [:]
    var tabOf: [String: (group: String, index: Int)] = [:]
    /// The page each tabbed group starts on: its first not saved hidden, else its first. A group
    /// always shows one page; its pages' `Visible`/`InitialVisible` only say which (Unsquareable
    /// starts on its playlist view, its second page; RealPlayer 11's equalizer window holds one
    /// page saved hidden, and shows it when it opens).
    var initialPages: [String: Int] = [:]
    /// A tabbed group's `ActivePage` binding, by group (Soot's playlist and lyrics pages follow
    /// `LyricsVisibility`).
    var pageLinks: [String: AIMPSkinLink] = [:]
    /// The companions' names.
    var companions: Set<String> = []
    /// Items the form starts with hidden (`InitialVisible` False: Cassette-3D's VU meters), less
    /// tab pages and `AutoHide` items (`AIMPSkinAlignment.startsShown`).
    var hiddenItems: Set<String> = []
    /// `Schema.xml`'s providers, the skin's own dataflow, by name.
    var providers: [String: Provider] = [:]
    /// `Animator` controls in form order, and by name (one animator follows another's frame).
    var animatorList: [AIMPSkinControl] = []
    var animators: [String: AIMPSkinControl] = [:]
    /// `LogicalOperatorTimer` and `ScriptableVisualizationHandler` providers, by name order.
    var timers: [(name: String, provider: Provider)] = []
    var visualizationHandlers: [(name: String, provider: Provider)] = []
    /// Skin counters some control sets through an `Action` binding (selectors and keys).
    var selectorCounters: Set<String> = []
    /// What links are read against: the expressions, and the groups, items and providers the
    /// skin names. Read before anything else, so every link resolves as it is read (`AIMPSkinSource`).
    private(set) var names = Names()

    struct Names: Sendable {
        /// Every `Expression` the forms and `Schema.xml` hold (on links and as provider properties),
        /// compiled; one that does not parse is absent.
        var expressions: [String: AIMPSkinExpression] = [:]
        var groups: Set<String> = []
        /// Every form's items, and the companions: a companion's switches read and set the main
        /// form's, and the reverse.
        var items: Set<String> = []
        var providers: [String: AIMPProviderClass] = [:]
    }
    /// `Schema.xml`'s `<variables>`: names every script of the skin reads and writes (the GX-77
    /// 4K's reel diameters `D0`, `Dm`; Soot's `g_…` state and `gc_…` constants), by lowercased
    /// name, with the value they start at.
    var variables: [String: Variable] = [:]
    /// What the windows need of the forms before they draw, worked out here, off the main thread:
    /// each sizable form's sizing by name ("" the main form), the items and controls bindings read
    /// `IsActive` of (the window redraws as the pointer crosses them), and whether a window of the
    /// skin lists NullPlayer's library (its own library window, or the library's lists on the deck:
    /// the host builds the library model only then).
    var sizing: [String: Sizing] = [:]
    var hoverSources: Set<String> = []
    var showsLibrary = false

    /// How the user sizes a form: how near its right and bottom edges a drag does
    /// (`SizingHitTestAreaWidth`), and the size it opens at before any is saved (`InitialSize`).
    struct Sizing: Sendable, Equatable {
        let edge: CGFloat
        let initialSize: CGSize?
    }

    /// `Schema.xml`'s resources by `ID`, and the `.lng` strings, which controls' fonts and texts
    /// are read through.
    var resources: [String: [String: AIMPNode]] = [:]
    var strings: [String: String] = [:]

    /// The main form's dock sites by name, and each docked form's site (`AIMPSkinDockSites`), and
    /// the item each site holds its form in while it is docked.
    var sites: [String: AIMPSkinDockSites.Site] = [:]
    var siteOf: [String: String] = [:]
    var holders: [String: AIMPSkinItem] = [:]
    /// Every named item and control, and the item it sits in: a script may move one into another
    /// (`FindObject('liMlTable').Parent := FindObject('liAioTableHost')`: Soot's all-in-one mode).
    var byName: [String: Element] = [:]
    var parentOf: [String: String] = [:]
    /// The main form (nil) and each companion's, read.
    private var forms: [String: AIMPSkinItem] = [:]
    /// Controls a script restyled, read again once per set of properties (`control(_:restyledBy:)`):
    /// a theme a script picked stays picked frame after frame (Unsquareable's light theme), and is
    /// read once, not every frame.
    private let restyled = AIMPSkinCache<Restyle, AIMPSkinControl>(limit: 1024)

    struct Variable: Sendable, Equatable {
        let value: String
        /// `String` (else a number; `Bool` reads `True` as 1).
        let isText: Bool
    }

    /// An item or a control, found by name.
    enum Element: Sendable {
        case item(AIMPSkinItem)
        case control(AIMPSkinControl)

        var node: AIMPNode {
            switch self {
            case .item(let item): return item.node
            case .control(let control): return control.node
            }
        }

        var name: String? { node["name"] }

        /// Its `Visibility` bindings.
        var gates: [AIMPSkinLink] {
            switch self {
            case .item(let item): return item.gates
            case .control(let control): return control.gates
            }
        }
    }

    /// A `Schema.xml` provider, read once: its class, bindings and the settings the dataflow and
    /// scripts read.
    struct Provider: Sendable {
        let node: AIMPNode
        let kind: AIMPProviderClass
        let bindings: AIMPSkinBindings
        /// The script a scriptable one runs, by name.
        let script: String?
        /// A commutator's `Expression` over `value1…valueN`.
        let expression: String?
        /// A timer's `Interval`, ms.
        let interval: Double?
        /// A counter's `Module` (its positions) and `PositionDefault`.
        let module: Int?
        let positionDefault: Int

        init(_ node: AIMPNode, names: Names) {
            let props = node.properties
            self.node = node
            kind = AIMPProviderClass(node["class"])
            bindings = AIMPSkinBindings(node, names: names)
            script = props["Script"]?["value"]
            expression = props["Expression"]?["value"]
            interval = Double(props["Interval"]?["value"] ?? "")
            module = props["Module"]?["value"].flatMap { Int($0) }
            positionDefault = props["PositionDefault"]?["value"].flatMap { Int($0) } ?? 0
        }
    }

    init(main: AIMPNode, companions: [AIMPSkin.Companion], schema: AIMPNode?, sites: [String: AIMPSkinDockSites.Site] = [:],
         resources: [String: [String: AIMPNode]] = [:], strings: [String: String] = [:]) {
        self.resources = resources
        self.strings = strings
        self.sites = sites
        siteOf = Dictionary(sites.map { ($0.value.form, $0.key) }, uniquingKeysWith: { first, _ in first })
        for companion in companions {
            names.items.insert(companion.name)
            self.companions.insert(companion.name)
            if !companion.initiallyVisible { hiddenItems.insert(companion.name) }
        }
        let nodes = ([main] + companions.map(\.form)).flatMap { $0.descendants() }
        hoverSources = Set(nodes.filter { $0.tag == "link" && $0["SourcePin"] == "IsActive" }.compactMap { $0["Source"] })
        showsLibrary = companions.contains { $0.role == .library }
            || main.descendants().contains { $0["link"] == AIMPSkinList.libraryTable.rawValue || $0["link"] == AIMPSkinList.libraryTree.rawValue }
        sizing = Self.sizing(main: main, companions: companions, schema: schema)
        for node in nodes + (schema?.descendants() ?? []) {
            let text = node.tag == "property" && node["name"] == "Expression" ? node["value"] : node["Expression"]
            if let text, names.expressions[text] == nil, let compiled = AIMPSkinExpression(text) { names.expressions[text] = compiled }
        }
        let providerNodes = schema?.child("providers")?.children("provider") ?? []
        for node in providerNodes {
            if let name = node["name"], names.providers[name] == nil { names.providers[name] = AIMPProviderClass(node["class"]) }
        }
        for node in nodes where node.tag == "item" {
            guard let name = node["name"] else { continue }
            let layout = AIMPSkinItem.Layout(node)
            names.items.insert(name)
            if !layout.savedShown { hiddenItems.insert(name) }
            guard layout.isTabbedGroup else { continue }
            let pages = node.child("items")?.children("item") ?? []
            let tabs = pages.compactMap { $0["name"] }
            groups[name] = tabs
            for (i, tab) in tabs.enumerated() { tabOf[tab] = (name, i) }
            initialPages[name] = pages.firstIndex { AIMPSkinItem.Layout($0).savedShown } ?? 0
        }
        // A page shows while it is its group's active one, whatever it was saved as.
        hiddenItems.subtract(tabOf.keys)
        names.groups = Set(groups.keys)
        for node in nodes where node.tag == "item" {
            guard let name = node["name"], AIMPSkinItem.Layout(node).isTabbedGroup else { continue }
            pageLinks[name] = node.properties["Bindings"]?.children("link").first { $0["TargetPin"] == "ActivePage" }
                .map { AIMPSkinLink($0, names: names) }
        }
        for node in providerNodes {
            guard let name = node["name"], providers[name] == nil else { continue }
            providers[name] = Provider(node, names: names)
        }
        let sorted = providers.sorted { $0.key < $1.key }
        timers = sorted.filter { $0.value.kind == .timer }.map { ($0.key, $0.value) }
        visualizationHandlers = sorted.filter { $0.value.kind == .visualizationHandler }.map { ($0.key, $0.value) }
        for variable in schema?.child("variables")?.children("variable") ?? [] {
            guard let name = variable["name"]?.lowercased() else { continue }
            variables[name] = Variable(value: variable["value"] ?? "", isText: variable["valueType"] == "String")
        }
        for node in nodes where node.tag == "control" {
            for link in node.properties["Bindings"]?.children("link") ?? []
            where link["TargetPin"] == "Action" && link["SourcePin"] == "Position" {
                if let source = link["Source"], counterModule(source) != nil { selectorCounters.insert(source) }
            }
        }

        // The forms, read with the tables above, every control numbered.
        let tables = self
        var controls = 0
        func compile(_ node: AIMPNode) -> AIMPSkinControl {
            let id = AIMPSkinControl.ID(value: controls)
            controls += 1
            let held = (node.child("controls")?.children("control") ?? []).map(compile)
            return AIMPSkinControl(node, id: id, index: tables, controls: held)
        }
        func read(_ form: AIMPNode) -> AIMPSkinItem {
            AIMPSkinItem(form, compile: compile, names: names)
        }
        forms[""] = read(main)
        for companion in companions where forms[companion.name] == nil { forms[companion.name] = read(companion.form) }
        holders = sites.mapValues { read($0.holder) }
        // In document order, as the skin wrote them: the first of a name is the one found.
        func walk(_ element: Element, in parent: String?) {
            let name = element.name.flatMap { $0.isEmpty ? nil : $0 }
            if let name, byName[name] == nil {
                byName[name] = element
                if let parent { parentOf[name] = parent }
            }
            if case .control(let control) = element, control.animator != nil { animatorList.append(control) }
            held(element, in: name ?? parent)
        }
        func held(_ element: Element, in holder: String?) {
            for child in element.node.children {
                switch (child.tag, element) {
                case ("items", .item(let item)): for each in item.items { walk(.item(each), in: holder) }
                case ("controls", .item(let item)): for each in item.controls { walk(.control(each), in: holder) }
                case ("controls", .control(let control)): for each in control.controls { walk(.control(each), in: holder) }
                default: break
                }
            }
        }
        for root in [forms[""]] + companions.map({ forms[$0.name] }) {
            if let root { held(.item(root), in: nil) }
        }
        animators = Dictionary(animatorList.compactMap { control in control.name.map { ($0, control) } },
                               uniquingKeysWith: { first, _ in first })
    }

    /// Each sizable form's sizing. The main form says how near its edges a drag sizes it on its
    /// root item (Vega AIO), or on `Schema.xml`'s entry (RealPlayer 11); a skin's playlist and
    /// library windows on their `Schema.xml` entry; its deck's other windows keep their size. A
    /// form opens at its entry's `InitialSize` (Pandemic's and Red Bias's 920×640), a side given as
    /// 0 the natural one.
    private static func sizing(main: AIMPNode, companions: [AIMPSkin.Companion], schema: AIMPNode?) -> [String: Sizing] {
        let entries = schema?.child("forms")?.children("form") ?? []
        func entry(_ name: String) -> AIMPNode? { entries.first { $0["name"] == name } }
        func number(_ node: AIMPNode?, _ name: String) -> Double? {
            node?.properties[name]?.reference.flatMap(Double.init).flatMap { $0 > 0 ? $0 : nil }
        }
        func made(_ edge: Double?, _ entry: AIMPNode?) -> Sizing? {
            guard let edge else { return nil }
            let asked = AIMPNode.numbers(entry?.properties["InitialSize"]?.reference)
            return Sizing(edge: CGFloat(edge), initialSize: asked.count == 2 ? CGSize(width: asked[0], height: asked[1]) : nil)
        }
        var sizing: [String: Sizing] = [:]
        let root = main.descendants().first { $0.tag == "item" }
        let mainEntry = entry("AIMPMainForm")
        // The root item's value is read as written: one that is not a number reads no sizing.
        let rootEdge = root?.properties["SizingHitTestAreaWidth"]?.reference ?? mainEntry?.properties["SizingHitTestAreaWidth"]?.reference
        sizing[""] = made(rootEdge.flatMap(Double.init).flatMap { $0 > 0 ? $0 : nil }, mainEntry)
        for companion in companions where companion.role != .other {
            sizing[companion.name] = made(number(entry(companion.name), "SizingHitTestAreaWidth"), entry(companion.name))
        }
        return sizing
    }

    /// The form called `name`, read; the main form for nil.
    func form(_ name: String?) -> AIMPSkinItem? { forms[name ?? ""] }

    /// `text` compiled: the skin's own as it loaded, anything else (a wheel's step) now.
    func expression(_ text: String) -> AIMPSkinExpression? { names.expressions[text] ?? AIMPSkinExpression(text) }

    /// A counter provider's `Module` (its positions), nil for anything else.
    func counterModule(_ name: String) -> Int? {
        guard let provider = providers[name], provider.kind.isCounter else { return nil }
        return provider.module.flatMap { $0 > 1 ? $0 : nil }
    }

    /// A control as a script restyled it (`AIMPSkinState.Script.propertySets`), read again; as it loaded
    /// when none did.
    func control(_ control: AIMPSkinControl, restyledBy sets: [String: [String: String]]) -> AIMPSkinControl {
        guard let key = control.styleKey, let set = sets[key] else { return control }
        return restyled.value(Restyle(control: control.id, set: set)) { control.restyled(set, index: self) }
    }

    /// A control and the properties a script set on it.
    private struct Restyle: Hashable, Sendable {
        let control: AIMPSkinControl.ID
        let set: [String: String]
    }
}
