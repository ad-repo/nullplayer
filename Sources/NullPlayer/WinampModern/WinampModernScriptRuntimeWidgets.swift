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
    /// The drop-down's item list, which lives in its `items` attribute (`;`-separated, as the markup
    /// writes it). Ids are 0-based positions. WinampAzenis2's SC-CD panel refills its list this way.
    private func storeDropDownItems(_ items: [String], on object: WasabiObject) {
        _ = object.setAttribute("items", value: items.joined(separator: ";"))
        notifyObjectDidMutate(object)
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
            ?? renderer.coordinateSpace(of: object)
        guard let space else { return canvasPoint }
        return CGPoint(x: canvasPoint.x - space.minX, y: canvasPoint.y - space.minY)
    }

    /// The stored value of a `CfgGroup`'s attribute, or nil for a group bound to none.
    private func cfgGroupValue(of object: WasabiObject) -> String? {
        guard let binding = Self.cfgGroupBinding(of: object) else { return nil }
        return loadedSkin.configuration.string(section: binding.section, key: binding.key, default: "")
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

    /// The `TreeItem` a `MakiValue` names, by its dynamic id.
    private static func treeItemID(_ value: MakiValue) -> UInt64? {
        guard case .object(let reference) = value, case .dynamic(let id) = reference.kind else { return nil }
        return id
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

extension WinampModernScriptRuntime {
    static let widgetMethods: MakiMethodTable<WasabiObject> = {
        var table = MakiMethodTable<WasabiObject>()
        // `GroupList`: the groups `instantiate` stacked into it. ClassicPro's Widgets Manager reads its
        // rows back with `enumItem` to place each widget.
        table.add("enumitem", 1) { runtime, call in
            if WinampModernScriptRuntime.isGroupList(call.object) {
                let index = Int(call.arguments[0].integerValue)
                let children = call.object.children
                return children.indices.contains(index) ? runtime.objectValue(children[index]) : .null
            }
            return nil
        }
        table.add("getnumitems", 0) { runtime, call in
            if WinampModernScriptRuntime.isGroupList(call.object) {
                return .integer(Int32(call.object.children.count))
            }
            return nil
        }
        table.add("removeall", 0) { runtime, call in
            if WinampModernScriptRuntime.isGroupList(call.object) {
                for child in call.object.children { runtime.loadedSkin.runtime.graph.discardSubtree(child) }
                runtime.noteGeometryChange()
                runtime.notifyGraphDidMutate()
                return .null
            }
            return nil
        }
        // `CfgGroup`: a group bound to one configuration attribute, which its script reads and writes
        // (Wasabi's own preference pages, which 21 skins ship in `system/Scripts/cfg*.m`).
        table.add("cfggetint", 0) { runtime, call in
            guard let stored = runtime.cfgGroupValue(of: call.object) else { return .integer(0) }
            return .integer(Int32(stored) ?? Int32(Double(stored) ?? 0))
        }
        table.add("cfggetfloat", 0) { runtime, call in
            guard let stored = runtime.cfgGroupValue(of: call.object) else { return .string("") }
            return .double(Double(stored) ?? 0)
        }
        table.add("cfggetstring", 0) { runtime, call in .string(runtime.cfgGroupValue(of: call.object) ?? "") }
        table.add("cfggetname", 0) { runtime, call in
            .string(WinampModernScriptRuntime.cfgGroupBinding(of: call.object)?.key ?? "")
        }
        table.add("cfggetguid", 0) { runtime, call in
            .string(WinampModernScriptRuntime.cfgGroupBinding(of: call.object)?.section ?? "")
        }
        table.add(["cfgsetint", "cfgsetfloat", "cfgsetstring"], 1) { runtime, call in
            guard let binding = WinampModernScriptRuntime.cfgGroupBinding(of: call.object) else { return .null }
            let value = call.method == "cfgsetint" ? String(call.arguments[0].integerValue)
                : call.method == "cfgsetfloat" ? String(call.arguments[0].doubleValue) : call.arguments[0].stringValue
            runtime.setConfigAttribute(section: binding.section, key: binding.key, value: value)
            _ = try runtime.dispatch(object: call.object, event: "oncfgchanged")
            return .null
        }
        // The open list's height, recorded: the list opens as an AppKit menu sized to its items.
        table.add("setlistheight", 1) { runtime, call in
            _ = call.object.setAttribute("listheight", value: String(call.arguments[0].integerValue))
            return .null
        }
        // The thinger's scroll, in icons. winampmodern566 saves it at unload and restores it at
        // startup, so only the round trip has to hold.
        table.add("getscroll", 0) { runtime, call in
            .integer(Int32(runtime.loadedSkin.runtime.componentBucket.offset))
        }
        table.add("setscroll", 1) { runtime, call in
            let bucket = runtime.loadedSkin.runtime.componentBucket
            bucket.scroll(by: Int(call.arguments[0].integerValue) - bucket.offset, visibleCount: 1)
            runtime.notifyGraphDidMutate()
            return .integer(Int32(bucket.offset))
        }
        // `MouseRedir.setRedirection(o)`: presses on this object reach `o` instead (the view resolves it).
        table.add("setredirection", 1) { runtime, call in
            guard case .object(let reference) = call.arguments[0], case .gui(let targetID) = reference.kind else {
                _ = call.object.setAttribute(WinampModernScriptRuntime.mouseRedirectionKey, value: "")
                return .null
            }
            _ = call.object.setAttribute(WinampModernScriptRuntime.mouseRedirectionKey,
                                         value: String(targetID.rawValue))
            return .null
        }
        // There is no modal loop here, so ending one closes the dialog's window.
        table.add("endmodal", 1) { runtime, call in
            guard let container = runtime.ancestor(of: call.object, type: .container) else { return .null }
            _ = container.setAttribute("visible", value: "0")
            runtime.notifyGraphDidMutate()
            runtime.requestWindow(for: container, visible: false)
            return .null
        }
        return table
    }()

    /// A `DropDownList`'s methods; `invokeGUI` asks this table only for a drop-down.
    static let dropDownItemMethods: MakiMethodTable<WasabiObject> = {
        var table = MakiMethodTable<WasabiObject>()
        table.add("additem", 1) { runtime, call in
            var items = WasabiFormWidgets.items(of: call.object)
            guard items.count < WasabiGuiList.maximumItems else { return .integer(-1) }
            items.append(call.arguments[0].stringValue)
            runtime.storeDropDownItems(items, on: call.object)
            return .integer(Int32(items.count - 1))
        }
        table.add("deleteallitems", 0) { runtime, call in
            runtime.storeDropDownItems([], on: call.object)
            return .null
        }
        table.add("finditem", 1) { runtime, call in
            .integer(Int32(WasabiFormWidgets.items(of: call.object).firstIndex(of: call.arguments[0].stringValue) ?? -1))
        }
        table.add("getnumitems", 0) { runtime, call in .integer(Int32(WasabiFormWidgets.items(of: call.object).count)) }
        table.add("getitemtext", 1) { runtime, call in
            let items = WasabiFormWidgets.items(of: call.object)
            let index = Int(call.arguments[0].integerValue)
            return .string(items.indices.contains(index) ? items[index] : "")
        }
        table.add("setitems", 1) { runtime, call in
            let items = call.arguments[0].stringValue.split(separator: ";").map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
            runtime.storeDropDownItems(items, on: call.object)
            return .null
        }
        table.add("delitem", 1) { runtime, call in
            var items = WasabiFormWidgets.items(of: call.object)
            let index = Int(call.arguments[0].integerValue)
            if items.indices.contains(index) {
                items.remove(at: index)
                runtime.storeDropDownItems(items, on: call.object)
            }
            return .null
        }
        table.add("getselected", 0) { runtime, call in
            let items = WasabiFormWidgets.items(of: call.object)
            return .integer(Int32(items.firstIndex(of: WasabiFormWidgets.selection(of: call.object)) ?? -1))
        }
        // The drop-down's reads beside the click path in the view (`presentDropDownList`).
        table.add("getselectedtext", 0) { runtime, call in .string(WasabiFormWidgets.selection(of: call.object)) }
        // `selectItem` is `(id, hover)` on a drop-down and `(item)` on a tree (B182).
        table.add("selectitem", 2, on: MakiClassGUID.dropDownList) { runtime, call in
            let items = WasabiFormWidgets.items(of: call.object)
            let index = Int(call.arguments[0].integerValue)
            guard items.indices.contains(index) else { return .null }
            try runtime.selectDropDownItem(items[index], on: call.object)
            return .null
        }
        // `GuiList`'s `getItemSelected(pos)` takes a row; the drop-down's takes nothing (B182).
        table.add("getitemselected", 0, on: MakiClassGUID.dropDownList) { runtime, call in
            .string(WasabiFormWidgets.selection(of: call.object))
        }
        return table
    }()

    static let listEditMethods: MakiMethodTable<WasabiObject> = {
        var table = MakiMethodTable<WasabiObject>()
        table.add("insertitem", 2) { runtime, call in
            var items = WasabiGuiList.items(of: call.object)
            guard items.count < WasabiGuiList.maximumItems else { return .integer(-1) }
            let position = max(0, min(items.count, Int(call.arguments[0].integerValue)))
            items.insert(call.arguments[1].stringValue, at: position)
            WasabiGuiList.setItems(items, on: call.object)
            WasabiGuiList.setSelection(WasabiGuiList.selection(of: call.object).map { $0 >= position ? $0 + 1 : $0 },
                                       on: call.object)
            runtime.notifyObjectDidMutate(call.object)
            return .integer(Int32(position))
        }
        table.add("deletebypos", 1) { runtime, call in
            var items = WasabiGuiList.items(of: call.object)
            let position = Int(call.arguments[0].integerValue)
            guard items.indices.contains(position) else { return .integer(0) }
            items.remove(at: position)
            WasabiGuiList.setItems(items, on: call.object)
            WasabiGuiList.setSelection(WasabiGuiList.selection(of: call.object).compactMap {
                $0 == position ? nil : ($0 > position ? $0 - 1 : $0)
            }, on: call.object)
            runtime.notifyObjectDidMutate(call.object)
            return .integer(1)
        }
        table.add("moveitem", 2) { runtime, call in
            var items = WasabiGuiList.items(of: call.object)
            let from = Int(call.arguments[0].integerValue), to = Int(call.arguments[1].integerValue)
            guard items.indices.contains(from), items.indices.contains(to) else { return .null }
            items.insert(items.remove(at: from), at: to)
            WasabiGuiList.setItems(items, on: call.object)
            runtime.notifyObjectDidMutate(call.object)
            return .null
        }
        table.add("getsubitemtext", 2) { runtime, call in
            let cells = WasabiGuiList.columns(ofRow: Int(call.arguments[0].integerValue), on: call.object)
            let column = Int(call.arguments[1].integerValue)
            return .string(cells.indices.contains(column) ? cells[column] : "")
        }
        table.add("deselectall", 0) { runtime, call in
            WasabiGuiList.setSelection([], on: call.object)
            runtime.notifyObjectDidMutate(call.object)
            return .integer(0)
        }
        table.add("getitemfocused", 0) { runtime, call in
            .integer(Int32(call.object.attributes[WinampModernScriptRuntime.focusedRowKey].flatMap(Int32.init) ?? -1))
        }
        table.add("setitemfocused", 1) { runtime, call in
            _ = call.object.setAttribute(WinampModernScriptRuntime.focusedRowKey,
                                         value: String(Int(call.arguments[0].integerValue)))
            return .null
        }
        // Column headers: recorded label and width per column, which `getColumnLabel` reads back. The
        // list draws its cells, not a header strip.
        table.add("addcolumn", 3) { runtime, call in
            var columns = WinampModernScriptRuntime.listColumns(of: call.object)
            guard columns.count < WasabiGuiList.maximumColumns else { return .integer(-1) }
            columns.append((call.arguments[0].stringValue, Int(call.arguments[1].integerValue)))
            WinampModernScriptRuntime.setListColumns(columns, on: call.object)
            return .integer(Int32(columns.count - 1))
        }
        table.add(["setcolumnlabel", "setcolumnwidth"], 2) { runtime, call in
            var columns = WinampModernScriptRuntime.listColumns(of: call.object)
            let column = Int(call.arguments[0].integerValue)
            guard columns.indices.contains(column) else { return .null }
            if call.method == "setcolumnlabel" { columns[column].label = call.arguments[1].stringValue }
            else { columns[column].width = Int(call.arguments[1].integerValue) }
            WinampModernScriptRuntime.setListColumns(columns, on: call.object)
            return .null
        }
        table.add("getcolumnlabel", 1) { runtime, call in
            let columns = WinampModernScriptRuntime.listColumns(of: call.object)
            let column = Int(call.arguments[0].integerValue)
            return .string(columns.indices.contains(column) ? columns[column].label : "")
        }
        // Sorting and single-selection preferences, recorded: rows stay in the order the script
        // wrote them, and a click selects one row.
        table.add(["setautosort", "setpreventmultipleselection"], 1) { runtime, call in
            _ = call.object.setAttribute("nullplayer.script.list." + call.method,
                                         value: String(call.arguments[0].integerValue))
            return call.method == "setpreventmultipleselection" ? .integer(0) : .null
        }
        return table
    }()

    /// `TreeItem` methods, on the dynamic object a script made with `new TreeItem`.
    static let treeItemMethods: MakiMethodTable<UInt64> = {
        var table = MakiMethodTable<UInt64>()
        table.add("setlabel", 1) { runtime, call in
            runtime.trees.nodes[call.id, default: .init()].label = call.arguments[0].stringValue
            runtime.refreshTree(containing: call.id)
            return .null
        }
        table.add("getlabel", 0) { runtime, call in .string(runtime.trees.nodes[call.id]?.label ?? "") }
        table.add(["expand", "collapse"], 0) { runtime, call in
            runtime.trees.nodes[call.id, default: .init()].expanded = call.method == "expand"
            runtime.refreshTree(containing: call.id)
            _ = try runtime.dispatch(target: MakiObjectReference(.dynamic(call.id)), event: "on" + call.method,
                                     arguments: [])
            return .integer(1)
        }
        table.add("isexpanded", 0) { runtime, call in
            .integer(runtime.trees.nodes[call.id]?.expanded == true ? 1 : 0)
        }
        table.add("getnumchildren", 0) { runtime, call in
            .integer(Int32(runtime.trees.nodes[call.id]?.children.count ?? 0))
        }
        table.add("getparent", 0) { runtime, call in
            runtime.trees.nodes[call.id]?.parent.map(runtime.treeItemValue) ?? .null
        }
        return table
    }()

    static let treeMethods: MakiMethodTable<WasabiObject> = {
        var table = MakiMethodTable<WasabiObject>()
        table.add("addtreeitem", 4) { runtime, call in
            guard let id = WinampModernScriptRuntime.treeItemID(call.arguments[0]) else { return .null }
            runtime.attachTreeItem(id, to: WinampModernScriptRuntime.treeItemID(call.arguments[1]),
                                   in: call.object.stableID)
            runtime.refreshTree(call.object)
            return runtime.treeItemValue(id)
        }
        table.add("movetreeitem", 2) { runtime, call in
            guard let id = WinampModernScriptRuntime.treeItemID(call.arguments[0]) else { return .null }
            runtime.attachTreeItem(id, to: WinampModernScriptRuntime.treeItemID(call.arguments[1]),
                                   in: call.object.stableID)
            runtime.refreshTree(call.object)
            return .null
        }
        table.add("deleteallitems", 0) { runtime, call in
            for id in runtime.trees.nodes.keys where runtime.trees.nodes[id]?.tree == call.object.stableID {
                runtime.trees.nodes[id] = nil
            }
            runtime.trees.roots[call.object.stableID] = []
            runtime.refreshTree(call.object)
            return .null
        }
        table.add("enumrootitem", 1) { runtime, call in
            let roots = runtime.sortedTreeChildren(runtime.trees.roots[call.object.stableID] ?? [], of: call.object)
            let index = Int(call.arguments[0].integerValue)
            return roots.indices.contains(index) ? runtime.treeItemValue(roots[index]) : .null
        }
        table.add("enumallitems", 1) { runtime, call in
            let all = runtime.flattenedTree(call.object, visibleOnly: false)
            let index = Int(call.arguments[0].integerValue)
            return all.indices.contains(index) ? runtime.treeItemValue(all[index].id) : .null
        }
        table.add("getnumvisibleitems", 0) { runtime, call in
            .integer(Int32(runtime.flattenedTree(call.object, visibleOnly: true).count))
        }
        // Depth-first under the item, or through the whole tree from null: 1010 Fullscreen finds a
        // second-level page ("Cover Search") by label to hang its own sub-page under it.
        table.add("getbylabel", 2) { runtime, call in
            let trees = runtime.trees
            let start = WinampModernScriptRuntime.treeItemID(call.arguments[0]).flatMap { trees.nodes[$0]?.children }
            var pending = Array((start ?? trees.roots[call.object.stableID] ?? []).reversed())
            let wanted = call.arguments[1].stringValue
            while let id = pending.popLast() {
                if runtime.trees.nodes[id]?.label == wanted { return runtime.treeItemValue(id) }
                pending.append(contentsOf: (runtime.trees.nodes[id]?.children ?? []).reversed())
            }
            return .null
        }
        table.add("selectitem", 1, on: MakiClassGUID.guiTree) { runtime, call in
            guard let id = WinampModernScriptRuntime.treeItemID(call.arguments[0]) else { return .null }
            // Selecting an item shows it: every ancestor opens.
            var ancestor = runtime.trees.nodes[id]?.parent
            while let current = ancestor {
                runtime.trees.nodes[current]?.expanded = true
                ancestor = runtime.trees.nodes[current]?.parent
            }
            runtime.refreshTree(call.object)
            try runtime.selectTreeItem(id, in: call.object)
            return .null
        }
        table.add("setsorted", 1) { runtime, call in
            _ = call.object.setAttribute(WinampModernScriptRuntime.treeSortedKey,
                                         value: call.arguments[0].truthy ? "1" : "0")
            runtime.refreshTree(call.object)
            return .null
        }
        table.add("getsorted", 0) { runtime, call in
            .integer(call.object.attributes[WinampModernScriptRuntime.treeSortedKey] == "1" ? 1 : 0)
        }
        return table
    }()
}
