import Foundation

/// The state a skin keeps for itself, apart from the player's, in three parts by how often it moves:
/// what keys, scripts and bindings set (`script`), what moves every frame (`animation`), and where
/// the skin's own lists stand (`lists`). It starts empty: every group on its first page, every
/// counter at its default.
struct AIMPSkinState: Equatable, Sendable {
    var script = Script()
    var animation = Animation()
    var lists = Lists()

    /// Whether going from `old` to this can change which parts of a form show: anything but the
    /// animation (a page turned, an item shown, a list scrolled). The window measures its content
    /// again only then.
    func layoutMoved(from old: AIMPSkinState) -> Bool { script != old.script || lists != old.lists }

    /// What keys, bindings and scripts set: the page each tabbed group shows and each counter's
    /// position (Vega MP-120's tape-type keys step a group's page), and what scripts change.
    struct Script: Equatable, Sendable {
        var activePages: [String: Int] = [:]
        var counters: [String: Int] = [:]
        /// Resource aliases a script repointed (`Skin.BodyFace_` → `Skin.BodyFace_7`).
        var resourceLinks: [String: String] = [:]
        /// Controls and items a script showed or hid (`FindObject(name).Set('Visible', …)`).
        var visible: [String: Bool] = [:]
        /// Other properties a script set on a control or item, by dotted path (`Playlist.Set('Resources.BackgroundColor', …)`:
        /// Unsquareable's light theme), drawn over what the skin wrote (`AIMPNode.overriding`).
        var propertySets: [String: [String: String]] = [:]
        /// Text providers' `Expression`s a script set (Soot's `SetCustomLabels` labels its options so).
        var expressions: [String: String] = [:]
        /// Forms a script docked or undocked (`AIMPSkinDockSites`), and items and controls it moved into
        /// another item (`Parent :=`).
        var docked: [String: Bool] = [:]
        var parents: [String: String] = [:]
        /// Items AIMP hid as the last layout found their parent smaller than their
        /// `AutoHideParentSizeThreshold` (or too small to hold them): bindings read them hidden
        /// (Soot's size triggers).
        var autoHidden: Set<String> = []
        /// What scripts stored with `ConfigSet`.
        var config: [String: String] = [:]
        /// Timers a script switched on or off (`Set('Enabled', …)`) or retimed (`Set('Interval', …)`).
        var timerEnabled: [String: Bool] = [:]
        var timerIntervals: [String: Double] = [:]
        /// Each timer's `Accessibility` binding value as last seen, so a change hands the timer back
        /// to the binding.
        var timerGates: [String: Double] = [:]
        /// Margins a script moved a control to (`PlaceInfo.Margins.Left`…: 0 left, 1 top, 2 right,
        /// 3 bottom), and text it gave a display (`Template`): the reel decks' position preview
        /// follows the pointer.
        var margins: [String: [Int: Double]] = [:]
        var texts: [String: String] = [:]
        /// The skin's variables a script has written (`AIMPSkinIndex.variables`), by lowercased name.
        var variables: [String: String] = [:]
    }

    /// What moves every frame while the skin plays: timers and animators, lamps, and the inputs the
    /// scripts last ran on. None of it moves a form's layout.
    struct Animation: Equatable, Sendable {
        /// When each `LogicalOperatorTimer` last fired, on the window's clock.
        var timerFired: [String: Double] = [:]
        /// The inputs each script last ran on (`AIMPSkinScript.Engine.settle`, `AIMPSkinDataflow.inputs`).
        var scriptInputs: [String: [Double]] = [:]
        /// Animators that keep their own frame: one a script set (`Set('FrameIndex', 0)`: a speaker's
        /// visualization handler kicks its cone) or one that stops itself (`Accessibility` on its own
        /// `AnimationFrameIndex`), and when each last stepped; a `StateDisplay`'s `State` a script set.
        var animatorFrames: [String: Int] = [:]
        var animatorStepped: [String: Double] = [:]
        /// Controls a script faded (`Set('BlendingModeOpacity', 0–255)`: the color-music lamps).
        var opacities: [String: Double] = [:]
    }

    /// Where the skin's own playlist and library windows stand: scrolled, chosen, searched.
    struct Lists: Equatable, Sendable {
        /// The skin's own playlist: the track at the top of the view, and the one clicked.
        var playlistTop = 0
        var playlistSelected: Int?
        /// The skin playlist's quick search: only rows holding every word of it show.
        var playlistSearch = ""
        /// The list whose quick search the window is typing into ("Playlist", "MLTable",
        /// "MLGroupingTree"); its box then leaves the text to the field.
        var searchEditing: AIMPSkinList?
        /// The skin's library window: its grouping preset (`AIMPSkinLibrary.Grouping`), the tree's open
        /// groups and chosen row (a row's `path`, empty for all tracks), the rows at the top of tree
        /// and table, the chosen track, and each list's quick search.
        var libraryGrouping = AIMPSkinLibrary.Grouping.artistAlbum
        var libraryExpanded: Set<String> = []
        var libraryPath = ""
        var libraryTreeTop = 0
        var libraryTableTop = 0
        var librarySelected: UUID?
        var librarySearch = ""
        var libraryTreeSearch = ""

        /// The quick search of `list`.
        func search(_ list: AIMPSkinList) -> String {
            switch list {
            case .libraryTable: return librarySearch
            case .libraryTree: return libraryTreeSearch
            case .playlist: return playlistSearch
            }
        }

        mutating func setSearch(_ list: AIMPSkinList, _ text: String) {
            switch list {
            case .libraryTable: librarySearch = text; libraryTableTop = 0
            case .libraryTree: libraryTreeSearch = text; libraryTreeTop = 0
            // A chosen row the search hides is no longer chosen.
            case .playlist: playlistSearch = text; playlistTop = 0; playlistSelected = nil
            }
        }
    }
}

/// Answers what a binding reads: `source`'s `pin`, from the form (a tabbed group's page, an item's
/// visibility), the player (`AIMPSkinHostState.pin`), or `Schema.xml`'s providers, the skin's own
/// dataflow (`reference/layout.md` § *Providers*):
/// - `LogicalOperatorCommutator`: `Result` is its `Expression` over `value1…valueN`, each a link
///   (with none, `value1`);
/// - `LogicalOperatorCounter` / `ScriptableOperatorCounter`: `Position` is the skin state's, else a
///   bound `Position` link, else `PositionDefault`.
/// Anything else, and anything a script would set, reads 0. What a frame makes of a control from
/// these is `AIMPSkinDataflow+Controls.swift`.
struct AIMPSkinDataflow {
    let skin: AIMPSkin
    let host: AIMPSkinHostState
    let state: AIMPSkinState

    /// Whether a form or item is shown: its `Visible` pin.
    func isVisible(_ name: String) -> Bool { value(name, "Visible") != 0 }

    /// Whether `form` is in its dock site now; a form no site holds never is.
    func isDocked(_ form: String) -> Bool {
        state.script.docked[form] ?? skin.index.siteOf[form].flatMap { skin.index.sites[$0]?.initiallyDocked } ?? false
    }

    /// The item `name` sits in now.
    func parent(of name: String) -> String? { state.script.parents[name] ?? skin.index.parentOf[name] }

    /// `value` as provider `name` holds it: wrapped by its `Module`, when it has one. A `Module` of 1
    /// holds it at 0, as AIMP does; `AIMPSkinIndex.counterModule`, the positions a control can show, has none then.
    func wrapped(_ value: Int, counter name: String) -> Int {
        guard let module = skin.index.providers[name]?.module, module > 0 else { return value }
        return ((value % module) + module) % module
    }

    /// The page a group shows: what its `ActivePage` binding reads, else what a key or script
    /// turned it to, else the first.
    func activePage(_ group: String, depth: Int = 0) -> Int {
        let count = skin.index.groups[group]?.count ?? 0
        let bound = skin.index.pageLinks[group].map { Int(value(of: $0, depth: depth + 1).rounded()) }
        return count == 0 ? 0 : min(max(bound ?? state.script.activePages[group] ?? skin.index.initialPages[group] ?? 0, 0), count - 1)
    }

    /// Whether `item` is its group's active page. Only its own group counts: Revox B-710 keeps its
    /// counter and meter modes (`TimeMode`, `Level`) as tabbed groups on a hidden page of an outer
    /// group, and their pages still read visible. Hidden-outright items are the layout's business.
    func isOnActivePage(_ item: String) -> Bool {
        guard let tab = skin.index.tabOf[item] else { return true }
        return activePage(tab.group) == tab.index
    }

    /// One link's value: what it reads, shaped by the link's own `Expression`.
    func value(of link: AIMPSkinLink, depth: Int = 0) -> Double {
        link.shaped(value(link.read, depth: depth))
    }

    /// What `link` reads, as a trigger watches it: a concatenator's inputs, and theirs (its text
    /// changes when any of them does), else its value.
    func inputs(of link: AIMPSkinLink, depth: Int = 0) -> [Double] {
        guard case .concatenator(let name) = link.read, depth < 8 else { return [value(of: link)] }
        return (skin.index.providers[name]?.bindings.links ?? []).flatMap { inputs(of: $0, depth: depth + 1) }
    }

    /// `source`'s `pin`, named at run time (a script's `BindingsGetDataAsInteger`, a counter's
    /// `Position`), resolved as a link's is.
    func value(_ source: String, _ pin: String, depth: Int = 0) -> Double {
        value(AIMPSkinSource(source, pin, names: skin.index.names), depth: depth)
    }

    func value(_ source: AIMPSkinSource, depth: Int = 0) -> Double {
        guard depth < 32 else { return 0 }
        switch source {
        case .page(let group): return Double(activePage(group, depth: depth))
        case .pointerOver(let name, let otherwise):
            guard let rect = host.feedback.hoverRects[name] else { return value(otherwise, depth: depth) }
            switch host.feedback.pointer {
            case .anywhere: return value(otherwise, depth: depth)
            case .outside: return 0
            case .at(let point): return rect.contains(point) ? 1 : 0
            }
        case .animatorFrame(let name, let otherwise):
            return state.animation.animatorFrames[name].map(Double.init) ?? value(otherwise, depth: depth)
        case .item(let name):
            if state.script.autoHidden.contains(name) { return 0 }
            if let set = state.script.visible[name] { return set ? 1 : 0 }
            // An item's own `Visibility` bindings, as the painter shows it (Unsquareable's tab column
            // shows while `TabControl_Small`, shown with the hidden compact player, is hidden).
            let gates = skin.index.byName[name]?.gates ?? []
            if !gates.isEmpty, !gates.allSatisfy({ value(of: $0, depth: depth + 1) != 0 }) { return 0 }
            return (!skin.index.hiddenItems.contains(name) && isOnActivePage(name)) ? 1 : 0
        case .value(let constant): return constant
        case .player(let pin): return host.value(pin)
        // Before the list has been drawn, any rows count.
        case .playlistScrolls:
            let rows = host.playlistIndices(matching: state.lists.playlistSearch).count
            return rows > (host.feedback.playlistRowsShown ?? 0) ? 1 : 0
        case .table(let pin):
            guard let library = host.player.library else { return 0 }
            let rows = library.table(state.lists.libraryGrouping, path: state.lists.libraryPath, search: state.lists.librarySearch)
            switch pin {
            case .count: return Double(rows.count)
            case .duration: return Double(rows.reduce(0) { $0 + AIMPSkinLibrary.seconds(library.tracks[$1]) })
            case .size: return Double(rows.reduce(Int64(0)) { $0 + library.tracks[$1].fileSize })
            }
        case .libraryScanning: return host.player.libraryScanning ? 1 : 0
        case .libraryGrouping: return Double(state.lists.libraryGrouping.rawValue)
        case .commutator(let name):
            guard let provider = skin.index.providers[name] else { return 0 }
            let links = provider.bindings.links
            // No `Expression`: it passes its first value on (Office 2016's volume read-out; 28 corpus skins).
            guard let expression = provider.expression else {
                return links.first { $0.target?.lowercased() == "value1" }.map { value(of: $0, depth: depth + 1) } ?? 0
            }
            var variables: [String: Double] = [:]
            for link in links {
                guard let target = link.target?.lowercased() else { continue }
                variables[target] = value(of: link, depth: depth + 1)
            }
            return skin.index.expression(expression)?.evaluate(variables: variables) ?? 0
        // Text joined from its values, read as the number it spells, else 0 (Antares' source digit:
        // `%IFEqual(…)` to 0 for a file, 2 for radio). A trigger watches its inputs (`inputs(of:)`).
        case .concatenator(let name):
            return Double(concatenatorText(name, depth: depth + 1).trimmingCharacters(in: .whitespaces)) ?? 0
        case .counter(let name):
            if let held = state.script.counters[name] { return Double(held) }
            guard let provider = skin.index.providers[name] else { return 0 }
            if let link = provider.bindings["Position"] { return value(of: link, depth: depth + 1) }
            return Double(provider.positionDefault)
        }
    }
}
