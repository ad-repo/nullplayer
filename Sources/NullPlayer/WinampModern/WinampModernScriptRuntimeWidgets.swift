import Foundation

/// The script surface of Wasabi's container widgets that the GUI receiver does not already cover:
/// `CfgGroup`, the `DropDownList` reads, `ComponentBucket` scrolling, `MouseRedir`, the `GuiList`
/// column and row edits, and `GuiTree`/`TreeItem`. Split out of
/// `WinampModernScriptRuntimeObject.swift`; see
/// `skills/winamp-modern-skin-guide/reference/compatibility/maki-surface.md`.
/// The `TreeItem`s scripts made, by their dynamic id, and each `GuiTree`'s top-level items. Only
/// this file reads or writes them.
struct WinampModernScriptTrees {
    /// One `TreeItem`: a script-owned node a `GuiTree` holds. Its id is the `new TreeItem` object's.
    fileprivate struct Node {
        var label = ""
        var parent: UInt64?
        var children: [UInt64] = []
        var expanded = false
        /// The `GuiTree` the node was added to; nil until `addTreeItem`.
        var tree: WasabiObjectID?
    }

    fileprivate var nodes: [UInt64: Node] = [:]
    fileprivate var roots: [WasabiObjectID: [UInt64]] = [:]
}

extension WinampModernScriptRuntime {
    /// Answers the widget methods, or `nil` for anything it does not own so `invokeGUI` goes on.
    func invokeWidget(method: String, object: WasabiObject, arguments: [MakiValue]) throws -> MakiValue? {
        if WasabiGuiList.isTree(object), let value = try invokeTree(method: method, tree: object, arguments: arguments) {
            return value
        }
        if WasabiGuiList.isList(object), let value = invokeListEdit(method: method, list: object, arguments: arguments) {
            return value
        }
        if WasabiFormWidgets.kind(of: object) == .dropDownList,
           let value = invokeDropDownItems(method: method, object: object, arguments: arguments) {
            return value
        }
        switch method {
        // `GroupList`: the groups `instantiate` stacked into it. ClassicPro's Widgets Manager reads its
        // rows back with `enumItem` to place each widget.
        case "enumitem" where Self.isGroupList(object):
            let index = Int(arguments[0].integerValue)
            return object.children.indices.contains(index) ? objectValue(object.children[index]) : .null
        case "getnumitems" where Self.isGroupList(object):
            return .integer(Int32(object.children.count))
        case "removeall" where Self.isGroupList(object):
            for child in object.children { loadedSkin.runtime.graph.discardSubtree(child) }
            noteGeometryChange()
            notifyGraphDidMutate()
            return .null
        // `CfgGroup`: a group bound to one configuration attribute, which its script reads and writes
        // (Wasabi's own preference pages, which 21 skins ship in `system/Scripts/cfg*.m`).
        case "cfggetint", "cfggetfloat", "cfggetstring", "cfggetname", "cfggetguid":
            guard let binding = Self.cfgGroupBinding(of: object) else { return method == "cfggetint" ? .integer(0) : .string("") }
            let stored = loadedSkin.configuration.string(section: binding.section, key: binding.key, default: "")
            switch method {
            case "cfggetint": return .integer(Int32(stored) ?? Int32(Double(stored) ?? 0))
            case "cfggetfloat": return .double(Double(stored) ?? 0)
            case "cfggetname": return .string(binding.key)
            case "cfggetguid": return .string(binding.section)
            default: return .string(stored)
            }
        case "cfgsetint", "cfgsetfloat", "cfgsetstring":
            guard let binding = Self.cfgGroupBinding(of: object) else { return .null }
            let value = method == "cfgsetint" ? String(arguments[0].integerValue)
                : method == "cfgsetfloat" ? String(arguments[0].doubleValue) : arguments[0].stringValue
            setConfigAttribute(section: binding.section, key: binding.key, value: value)
            _ = try dispatch(object: object, event: "oncfgchanged")
            return .null
        // The drop-down's reads beside the click path in the view (`presentDropDownList`).
        case "getselectedtext" where WasabiFormWidgets.kind(of: object) == .dropDownList:
            return .string(WasabiFormWidgets.selection(of: object))
        case "selectitem" where WasabiFormWidgets.kind(of: object) == .dropDownList:
            let items = WasabiFormWidgets.items(of: object)
            let index = Int(arguments[0].integerValue)
            guard items.indices.contains(index) else { return .null }
            try selectDropDownItem(items[index], on: object)
            return .null
        // The open list's height, recorded: the list opens as an AppKit menu sized to its items.
        case "setlistheight":
            _ = object.setAttribute("listheight", value: String(arguments[0].integerValue))
            return .null
        // The thinger's scroll, in icons. winampmodern566 saves it at unload and restores it at
        // startup, so only the round trip has to hold.
        case "getscroll": return .integer(Int32(loadedSkin.runtime.componentBucket.offset))
        case "setscroll":
            let bucket = loadedSkin.runtime.componentBucket
            bucket.scroll(by: Int(arguments[0].integerValue) - bucket.offset, visibleCount: 1)
            notifyGraphDidMutate()
            return .integer(Int32(bucket.offset))
        // `MouseRedir.setRedirection(o)`: presses on this object reach `o` instead (the view resolves it).
        case "setredirection":
            guard case .object(let reference) = arguments[0], case .gui(let targetID) = reference.kind else {
                _ = object.setAttribute(Self.mouseRedirectionKey, value: "")
                return .null
            }
            _ = object.setAttribute(Self.mouseRedirectionKey, value: String(targetID.rawValue))
            return .null
        // There is no modal loop here, so ending one closes the dialog's window.
        case "endmodal":
            guard let container = ancestor(of: object, type: .container) else { return .null }
            _ = container.setAttribute("visible", value: "0")
            notifyGraphDidMutate()
            requestWindow(for: container, visible: false)
            return .null
        default:
            return nil
        }
    }

    /// The drop-down's item list, which lives in its `items` attribute (`;`-separated, as the markup
    /// writes it). Ids are 0-based positions. WinampAzenis2's SC-CD panel refills its list this way.
    private func invokeDropDownItems(method: String, object: WasabiObject, arguments: [MakiValue]) -> MakiValue? {
        var items = WasabiFormWidgets.items(of: object)
        func store() {
            _ = object.setAttribute("items", value: items.joined(separator: ";"))
            notifyObjectDidMutate(object)
        }
        switch method {
        case "additem":
            guard items.count < WasabiGuiList.maximumItems else { return .integer(-1) }
            items.append(arguments[0].stringValue)
            store()
            return .integer(Int32(items.count - 1))
        case "deleteallitems":
            items = []
            store()
            return .null
        case "finditem": return .integer(Int32(items.firstIndex(of: arguments[0].stringValue) ?? -1))
        case "getnumitems": return .integer(Int32(items.count))
        case "getitemtext":
            let index = Int(arguments[0].integerValue)
            return .string(items.indices.contains(index) ? items[index] : "")
        case "setitems":
            items = arguments[0].stringValue.split(separator: ";").map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
            store()
            return .null
        case "delitem":
            let index = Int(arguments[0].integerValue)
            if items.indices.contains(index) { items.remove(at: index); store() }
            return .null
        case "getselected":
            return .integer(Int32(items.firstIndex(of: WasabiFormWidgets.selection(of: object)) ?? -1))
        case "getitemselected": return .string(WasabiFormWidgets.selection(of: object))
        default: return nil
        }
    }

    static let mouseRedirectionKey = "nullplayer.mouseredir"

    static func isGroupList(_ object: WasabiObject) -> Bool {
        object.tag.is(.groupList)
    }

    /// Where a press on `object` goes: its `setRedirection` target, or itself.
    func mouseRedirectionTarget(of object: WasabiObject) -> WasabiObject {
        guard let raw = object.attributes[Self.mouseRedirectionKey], let id = UInt64(raw),
              let target = loadedSkin.runtime.graph.object(withID: WasabiObjectID(rawValue: id)) else { return object }
        return target
    }

    /// The group a mouse event on `object` is measured from: its parent, unless that parent is an XUI
    /// widget instance (`<groupdef xuitag=…>`) whose own script is not listening — then the space
    /// climbs past it, as far as the first plain group or listening script's group. `nil` means the
    /// parent.
    ///
    /// A widget is one control to the script that placed it. Alpha Media Player X5's slider channels
    /// are a `main.c` layer inside an `amp:channel.v`, and its player script clamps `y` to the
    /// channel's top *in the player group* — told the widget-relative point, bass and treble pinned at
    /// their top and volume landed 128px off the press. A plain group is a space of its own whoever
    /// listens: JRS's layout-level knob script subtracts `getTop()` inside `eq.normal.group`, and Lobe's
    /// dial script sits in the dial's own group.
    private func mouseEventSpace(of object: WasabiObject, event: String) -> WasabiObject? {
        let event = event.lowercased()
        let owners = Set(programsBinding(object) { $0 == event }.compactMap(\.ownerID))
        let types = loadedSkin.runtime.types
        guard !owners.isEmpty, let parent = object.parent, types.isXUITag(parent.typeName) else { return nil }
        return sequence(first: parent, next: { $0.parent })
            .first { owners.contains($0.stableID) || !types.isXUITag($0.typeName) }
    }

    /// The canvas point in the space `event` on `object` is measured in: `mouseEventSpace`, else
    /// `object`'s parent. Unchanged for anything whose space sits at the origin, which is why this was
    /// invisible until a skin put a knob inside a placed group. The view and both click harnesses
    /// convert through here, so a probe drives exactly what the app sends.
    func pointInEventSpace(of object: WasabiObject, event: String, canvasPoint: CGPoint,
                           renderer: WasabiSceneRenderer) -> CGPoint {
        let space = mouseEventSpace(of: object, event: event).flatMap { renderer.resolvedGeometry(of: $0)?.frame }
            ?? renderer.resolvedGeometry(of: object)?.parent
        guard let space else { return canvasPoint }
        return CGPoint(x: canvasPoint.x - space.minX, y: canvasPoint.y - space.minY)
    }

    /// A `CfgGroup`'s attribute: `cfgguid` plus `cfgattrib`, or the `{guid};name` form a control uses.
    static func cfgGroupBinding(of object: WasabiObject) -> (section: String, key: String)? {
        if let guid = object.attributes["cfgguid"], !guid.isEmpty {
            return (guid, object.attributes["cfgattrib"] ?? "")
        }
        return configBinding(of: object)
    }

    /// Show `picked` in a drop-down and tell its label, which is where a skin persists the choice.
    /// The view's click route and `selectItem` both land here.
    func selectDropDownItem(_ picked: String, on object: WasabiObject) throws {
        guard picked != WasabiFormWidgets.selection(of: object) else { return }
        _ = object.setAttribute("default", value: picked)
        if let label = WasabiFormWidgets.dropDownLabel(of: object) {
            _ = label.setAttribute("text", value: picked)
            _ = try dispatch(object: label, event: "ontextchanged", arguments: [.string(picked)])
        }
        notifyObjectDidMutate(object)
    }

    // MARK: - GuiList edits

    private func invokeListEdit(method: String, list: WasabiObject, arguments: [MakiValue]) -> MakiValue? {
        var items = WasabiGuiList.items(of: list)
        func row(_ value: MakiValue) -> Int { Int(value.integerValue) }
        switch method {
        case "insertitem":
            guard items.count < WasabiGuiList.maximumItems else { return .integer(-1) }
            let position = max(0, min(items.count, row(arguments[0])))
            items.insert(arguments[1].stringValue, at: position)
            WasabiGuiList.setItems(items, on: list)
            WasabiGuiList.setSelection(WasabiGuiList.selection(of: list).map { $0 >= position ? $0 + 1 : $0 }, on: list)
            notifyObjectDidMutate(list)
            return .integer(Int32(position))
        case "deletebypos":
            let position = row(arguments[0])
            guard items.indices.contains(position) else { return .integer(0) }
            items.remove(at: position)
            WasabiGuiList.setItems(items, on: list)
            WasabiGuiList.setSelection(WasabiGuiList.selection(of: list).compactMap {
                $0 == position ? nil : ($0 > position ? $0 - 1 : $0)
            }, on: list)
            notifyObjectDidMutate(list)
            return .integer(1)
        case "moveitem":
            let from = row(arguments[0]), to = row(arguments[1])
            guard items.indices.contains(from), items.indices.contains(to) else { return .null }
            items.insert(items.remove(at: from), at: to)
            WasabiGuiList.setItems(items, on: list)
            notifyObjectDidMutate(list)
            return .null
        case "getsubitemtext":
            let cells = WasabiGuiList.columns(ofRow: row(arguments[0]), on: list)
            let column = row(arguments[1])
            return .string(cells.indices.contains(column) ? cells[column] : "")
        case "deselectall":
            WasabiGuiList.setSelection([], on: list)
            notifyObjectDidMutate(list)
            return .integer(0)
        case "getitemfocused": return .integer(Int32(list.attributes[Self.focusedRowKey].flatMap(Int32.init) ?? -1))
        case "setitemfocused":
            _ = list.setAttribute(Self.focusedRowKey, value: String(row(arguments[0])))
            return .null
        // Column headers: recorded label and width per column, which `getColumnLabel` reads back. The
        // list draws its cells, not a header strip.
        case "addcolumn":
            var columns = Self.listColumns(of: list)
            guard columns.count < WasabiGuiList.maximumColumns else { return .integer(-1) }
            columns.append((arguments[0].stringValue, Int(arguments[1].integerValue)))
            Self.setListColumns(columns, on: list)
            return .integer(Int32(columns.count - 1))
        case "setcolumnlabel", "setcolumnwidth":
            var columns = Self.listColumns(of: list)
            let column = row(arguments[0])
            guard columns.indices.contains(column) else { return .null }
            if method == "setcolumnlabel" { columns[column].label = arguments[1].stringValue }
            else { columns[column].width = Int(arguments[1].integerValue) }
            Self.setListColumns(columns, on: list)
            return .null
        case "getcolumnlabel":
            let columns = Self.listColumns(of: list)
            let column = row(arguments[0])
            return .string(columns.indices.contains(column) ? columns[column].label : "")
        // Sorting and single-selection preferences, recorded: rows stay in the order the script
        // wrote them, and a click selects one row.
        case "setautosort", "setpreventmultipleselection":
            _ = list.setAttribute("nullplayer.script.list." + method, value: String(arguments[0].integerValue))
            return method == "setpreventmultipleselection" ? .integer(0) : .null
        default:
            return nil
        }
    }

    private static let focusedRowKey = "nullplayer.script.listfocus"
    private static let columnsKey = "nullplayer.script.listcolumns"

    private static func listColumns(of list: WasabiObject) -> [(label: String, width: Int)] {
        (list.attributes[columnsKey] ?? "").split(separator: "\u{1}", omittingEmptySubsequences: false)
            .filter { !$0.isEmpty }
            .map { entry in
                let parts = entry.split(separator: "\u{2}", omittingEmptySubsequences: false)
                return (String(parts.first ?? ""), Int(parts.dropFirst().first ?? "") ?? 0)
            }
    }

    private static func setListColumns(_ columns: [(label: String, width: Int)], on list: WasabiObject) {
        _ = list.setAttribute(columnsKey, value: columns.map { "\($0.label)\u{2}\($0.width)" }.joined(separator: "\u{1}"))
    }

    // MARK: - GuiTree and TreeItem

    /// `TreeItem` methods, on the dynamic object a script made with `new TreeItem`.
    func invokeTreeItem(method: String, id: UInt64, arguments: [MakiValue]) throws -> MakiValue? {
        switch method {
        case "setlabel":
            trees.nodes[id, default: .init()].label = arguments[0].stringValue
            refreshTree(containing: id)
            return .null
        case "getlabel": return .string(trees.nodes[id]?.label ?? "")
        case "expand", "collapse":
            trees.nodes[id, default: .init()].expanded = method == "expand"
            refreshTree(containing: id)
            _ = try dispatch(target: MakiObjectReference(.dynamic(id)), event: "on" + method, arguments: [])
            return .integer(1)
        case "isexpanded": return .integer(trees.nodes[id]?.expanded == true ? 1 : 0)
        case "getnumchildren": return .integer(Int32(trees.nodes[id]?.children.count ?? 0))
        case "getparent": return trees.nodes[id]?.parent.map(treeItemValue) ?? .null
        default: return nil
        }
    }

    private func invokeTree(method: String, tree: WasabiObject, arguments: [MakiValue]) throws -> MakiValue? {
        func item(_ value: MakiValue) -> UInt64? {
            guard case .object(let reference) = value, case .dynamic(let id) = reference.kind else { return nil }
            return id
        }
        switch method {
        case "addtreeitem":
            guard let id = item(arguments[0]) else { return .null }
            attachTreeItem(id, to: item(arguments[1]), in: tree.stableID)
            refreshTree(tree)
            return treeItemValue(id)
        case "movetreeitem":
            guard let id = item(arguments[0]) else { return .null }
            attachTreeItem(id, to: item(arguments[1]), in: tree.stableID)
            refreshTree(tree)
            return .null
        case "deleteallitems":
            for id in trees.nodes.keys where trees.nodes[id]?.tree == tree.stableID { trees.nodes[id] = nil }
            trees.roots[tree.stableID] = []
            refreshTree(tree)
            return .null
        case "enumrootitem":
            let roots = sortedTreeChildren(trees.roots[tree.stableID] ?? [], of: tree)
            let index = Int(arguments[0].integerValue)
            return roots.indices.contains(index) ? treeItemValue(roots[index]) : .null
        case "enumallitems":
            let all = flattenedTree(tree, visibleOnly: false)
            let index = Int(arguments[0].integerValue)
            return all.indices.contains(index) ? treeItemValue(all[index].id) : .null
        case "getnumvisibleitems": return .integer(Int32(flattenedTree(tree, visibleOnly: true).count))
        // Depth-first under the item, or through the whole tree from null: 1010 Fullscreen finds a
        // second-level page ("Cover Search") by label to hang its own sub-page under it.
        case "getbylabel":
            var pending = Array((item(arguments[0]).flatMap { trees.nodes[$0]?.children }
                                 ?? trees.roots[tree.stableID] ?? []).reversed())
            let wanted = arguments[1].stringValue
            while let id = pending.popLast() {
                if trees.nodes[id]?.label == wanted { return treeItemValue(id) }
                pending.append(contentsOf: (trees.nodes[id]?.children ?? []).reversed())
            }
            return .null
        case "selectitem":
            guard let id = item(arguments[0]) else { return .null }
            // Selecting an item shows it: every ancestor opens.
            var ancestor = trees.nodes[id]?.parent
            while let current = ancestor {
                trees.nodes[current]?.expanded = true
                ancestor = trees.nodes[current]?.parent
            }
            refreshTree(tree)
            try selectTreeItem(id, in: tree)
            return .null
        case "setsorted":
            _ = tree.setAttribute(Self.treeSortedKey, value: arguments[0].truthy ? "1" : "0")
            refreshTree(tree)
            return .null
        case "getsorted": return .integer(tree.attributes[Self.treeSortedKey] == "1" ? 1 : 0)
        default: return nil
        }
    }

    /// A click on a tree row: select it, open or close it when it has children, and tell the skin.
    func clickTreeRow(_ row: Int, in tree: WasabiObject) throws {
        let rows = flattenedTree(tree, visibleOnly: true)
        guard rows.indices.contains(row) else { return }
        let id = rows[row].id
        if trees.nodes[id]?.children.isEmpty == false {
            trees.nodes[id]?.expanded.toggle()
            refreshTree(tree)
        }
        try selectTreeItem(id, in: tree)
    }

    private func selectTreeItem(_ id: UInt64, in tree: WasabiObject) throws {
        if let row = flattenedTree(tree, visibleOnly: true).firstIndex(where: { $0.id == id }) {
            WasabiGuiList.setSelection([row], on: tree)
            notifyObjectDidMutate(tree)
        }
        _ = try dispatch(object: tree, event: "onitemselected", arguments: [treeItemValue(id)])
        _ = try dispatch(target: MakiObjectReference(.dynamic(id)), event: "onselect", arguments: [])
    }

    private static let treeSortedKey = "nullplayer.script.treesorted"

    private func treeItemValue(_ id: UInt64) -> MakiValue { .object(MakiObjectReference(.dynamic(id))) }

    private func attachTreeItem(_ id: UInt64, to parent: UInt64?, in tree: WasabiObjectID) {
        // A parent that is the item or one of its descendants would make a cycle; the item stays put.
        var ancestor = parent
        while let current = ancestor {
            if current == id { return }
            ancestor = trees.nodes[current]?.parent
        }
        if let old = trees.nodes[id]?.parent { trees.nodes[old]?.children.removeAll { $0 == id } }
        trees.roots[tree]?.removeAll { $0 == id }
        trees.nodes[id, default: .init()].parent = parent
        trees.nodes[id]?.tree = tree
        if let parent { trees.nodes[parent, default: .init()].children.append(id) }
        else { trees.roots[tree, default: []].append(id) }
    }

    private func sortedTreeChildren(_ ids: [UInt64], of tree: WasabiObject) -> [UInt64] {
        guard tree.attributes[Self.treeSortedKey] == "1" else { return ids }
        return ids.sorted {
            (trees.nodes[$0]?.label ?? "").localizedStandardCompare(trees.nodes[$1]?.label ?? "") == .orderedAscending
        }
    }

    /// Pre-order, depth-annotated; `visibleOnly` stops at a closed item. Depth-bounded like the menus.
    private func flattenedTree(_ tree: WasabiObject, visibleOnly: Bool) -> [(id: UInt64, depth: Int)] {
        var rows: [(id: UInt64, depth: Int)] = []
        func walk(_ ids: [UInt64], depth: Int) {
            guard depth < 32 else { return }
            for id in sortedTreeChildren(ids, of: tree) {
                guard rows.count < WasabiGuiList.maximumItems, let node = trees.nodes[id] else { return }
                rows.append((id, depth))
                if !visibleOnly || node.expanded { walk(node.children, depth: depth + 1) }
            }
        }
        walk(trees.roots[tree.stableID] ?? [], depth: 0)
        return rows
    }

    private func refreshTree(containing id: UInt64) {
        guard let treeID = trees.nodes[id]?.tree, let tree = loadedSkin.runtime.graph.object(withID: treeID) else { return }
        refreshTree(tree)
    }

    /// Draw the tree through the list renderer: one row per visible item, indented, with an arrow on
    /// an item that has children.
    private func refreshTree(_ tree: WasabiObject) {
        let rows = flattenedTree(tree, visibleOnly: true).map { row -> String in
            let node = trees.nodes[row.id]
            let marker = node?.children.isEmpty == false ? (node?.expanded == true ? "▾ " : "▸ ") : "   "
            return String(repeating: "   ", count: row.depth) + marker + (node?.label ?? "")
        }
        WasabiGuiList.setItems(rows, on: tree)
        notifyObjectDidMutate(tree)
    }
}
