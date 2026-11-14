import AppKit
import CAvsCore
import UniformTypeIdentifiers

/// **Edit Preset…** for the AVS engine: a plain AppKit tool window over one `AvsEngine`'s preset.
/// The left pane is the component tree (add, delete, duplicate, drag to move, an enabled box per
/// row); the right is `AvsParameterInspector`. Edits go straight into the running preset, so the
/// visualization shows them on its next frame. One editor at a time; it closes when its engine stops.
final class AvsEditorWindowController: NSWindowController, NSWindowDelegate {
    private static var current: AvsEditorWindowController?
    private static let dragType = NSPasteboard.PasteboardType("org.nullplayer.avs.component")

    private weak var engine: AvsEngine?
    private let core: AvsCore
    private let outline = NSOutlineView()
    private let inspector: AvsParameterInspector
    private let addButton = NSPopUpButton(frame: .zero, pullsDown: true)
    /// The tree the outline shows, read from libavs in one locked pass per `reloadTree`; the
    /// data source never reaches into libavs between reloads.
    private var tree: Node?
    private var nodes: [AVS_Component_Handle: Node] = [:]
    private var observers: [NSObjectProtocol] = []

    static func show(for engine: AvsEngine) {
        if let current, current.engine === engine {
            current.window?.makeKeyAndOrderFront(nil)
            return
        }
        current?.close()
        guard let core = engine.core else { return }
        let controller = AvsEditorWindowController(engine: engine, core: core)
        current = controller
        controller.showWindow(nil)
    }

    private init(engine: AvsEngine, core: AvsCore) {
        self.engine = engine
        self.core = core
        inspector = AvsParameterInspector(core: core)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 820, height: 560),
                              styleMask: [.titled, .closable, .resizable, .miniaturizable],
                              backing: .buffered, defer: false)
        window.title = "AVS Preset Editor"
        window.minSize = NSSize(width: 600, height: 360)
        window.isReleasedWhenClosed = false
        window.center()
        super.init(window: window)
        window.delegate = self
        engine.isBeingEdited = true
        buildContent()
        buildAddMenu()
        reloadTree()

        let id = ObjectIdentifier(engine)
        observers = [
            NotificationCenter.default.addObserver(forName: AvsEngine.presetDidLoad, object: engine, queue: .main) { [weak self] _ in
                self?.reloadTree()
            },
            NotificationCenter.default.addObserver(forName: AvsEngine.didStop, object: nil, queue: .main) { [weak self] note in
                if (note.userInfo?["engine"] as? ObjectIdentifier) == id { self?.close() }
            },
        ]
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func windowWillClose(_ notification: Notification) {
        window?.makeFirstResponder(nil)   // commits a code edit still being typed
        engine?.isBeingEdited = false
        observers.forEach(NotificationCenter.default.removeObserver)
        observers = []
        if Self.current === self { Self.current = nil }
    }

    // MARK: - Layout

    private func buildContent() {
        let column = NSTableColumn(identifier: .init("component"))
        outline.addTableColumn(column)
        outline.outlineTableColumn = column
        outline.headerView = nil
        outline.dataSource = self
        outline.delegate = self
        outline.registerForDraggedTypes([Self.dragType])
        outline.setDraggingSourceOperationMask(.move, forLocal: true)
        let treeScroll = NSScrollView()
        treeScroll.documentView = outline
        treeScroll.hasVerticalScroller = true

        let delete = NSButton(title: "Delete", target: self, action: #selector(deleteComponent))
        let duplicate = NSButton(title: "Duplicate", target: self, action: #selector(duplicateComponent))
        addButton.addItem(withTitle: "Add Effect")
        let treeButtons = NSStackView(views: [addButton, duplicate, delete])
        let left = NSStackView(views: [treeScroll, treeButtons])
        left.orientation = .vertical
        left.edgeInsets = NSEdgeInsets(top: 0, left: 0, bottom: 8, right: 0)

        let inspectorScroll = NSScrollView()
        inspectorScroll.documentView = inspector
        inspectorScroll.hasVerticalScroller = true
        inspector.translatesAutoresizingMaskIntoConstraints = false
        inspector.widthAnchor.constraint(equalTo: inspectorScroll.contentView.widthAnchor).isActive = true

        let split = NSSplitView()
        split.isVertical = true
        split.dividerStyle = .thin
        split.addArrangedSubview(left)
        split.addArrangedSubview(inspectorScroll)
        left.widthAnchor.constraint(greaterThanOrEqualToConstant: 220).isActive = true

        let file = NSStackView(views: [
            NSButton(title: "New", target: self, action: #selector(newPreset)),
            NSButton(title: "Open…", target: self, action: #selector(openPreset)),
            NSButton(title: "Save…", target: self, action: #selector(savePreset)),
            NSButton(title: "Export JSON…", target: self, action: #selector(exportJSON)),
        ])
        let content = NSStackView(views: [file, split])
        content.orientation = .vertical
        content.alignment = .leading
        content.edgeInsets = NSEdgeInsets(top: 8, left: 8, bottom: 0, right: 8)
        split.widthAnchor.constraint(equalTo: content.widthAnchor, constant: -16).isActive = true
        window?.contentView = content
        split.setPosition(260, ofDividerAt: 0)
    }

    /// The effect library, grouped as libavs groups it; only effects a user may create.
    private func buildAddMenu() {
        let effects: [(group: String, name: String, effect: AVS_Effect_Handle)] = core.withHandle { handle in
            var count: UInt32 = 0
            guard let library = avs_effect_library(handle, &count) else { return [] }
            return UnsafeBufferPointer(start: library, count: Int(count)).compactMap { effect in
                var info = AVS_Effect_Info()
                guard avs_effect_info(handle, effect, &info), info.is_user_creatable, let name = info.name else { return nil }
                return (info.group.map { String(cString: $0) } ?? "", String(cString: name), effect)
            }
        }
        guard let menu = addButton.menu else { return }
        for group in Set(effects.map(\.group)).sorted() {
            let submenu = NSMenu()
            for entry in effects.filter({ $0.group == group }).sorted(by: { $0.name < $1.name }) {
                let item = NSMenuItem(title: entry.name, action: #selector(addComponent(_:)), keyEquivalent: "")
                item.target = self
                item.tag = Int(entry.effect)
                submenu.addItem(item)
            }
            let groupItem = NSMenuItem(title: group.isEmpty ? "Other" : group, action: nil, keyEquivalent: "")
            groupItem.submenu = submenu
            menu.addItem(groupItem)
        }
    }

    // MARK: - Tree

    /// One component as the outline shows it.
    final class Node {
        let handle: AVS_Component_Handle
        let name: String
        var enabled: Bool
        let canHaveChildren: Bool
        let children: [Node]

        init(_ handle: AVS_Component_Handle, in avs: AVS_Handle) {
            self.handle = handle
            var info = AVS_Effect_Info()
            name = avs_effect_info(avs, avs_component_effect(avs, handle), &info)
                ? info.name.map { String(cString: $0) } ?? "?" : "?"
            var properties = AVS_Component_Properties()
            enabled = avs_component_properties_get(avs, handle, &properties) && properties.enabled
            canHaveChildren = avs_component_can_have_child_components(avs, handle)
            var count: UInt32 = 0
            let list = avs_component_children(avs, handle, &count)
            children = list.map { UnsafeBufferPointer(start: $0, count: Int(count)).map { Node($0, in: avs) } } ?? []
        }

        func flattened() -> [Node] { [self] + children.flatMap { $0.flattened() } }
    }

    private var selected: Node? { outline.item(atRow: outline.selectedRow) as? Node }

    /// Re-reads the tree from libavs, keeping the selection when it still exists.
    private func reloadTree(select wanted: AVS_Component_Handle? = nil) {
        let keep = wanted ?? selected?.handle
        tree = core.withHandle { Node(avs_component_root($0), in: $0) }
        nodes = Dictionary(uniqueKeysWithValues: (tree?.flattened() ?? []).map { ($0.handle, $0) })
        outline.reloadData()
        outline.expandItem(nil, expandChildren: true)
        let row = keep.flatMap { nodes[$0] }.map { outline.row(forItem: $0) } ?? -1
        outline.selectRowIndexes(IndexSet(integer: row >= 0 ? row : 0), byExtendingSelection: false)
        inspector.show(selected?.handle ?? 0)
    }

    // MARK: - Tree actions

    @objc private func addComponent(_ sender: NSMenuItem) {
        guard let target = selected ?? tree else { return }
        let intoTarget = target === tree || (target.canHaveChildren && outline.isItemExpanded(target))
        let created = core.withHandle { handle -> AVS_Component_Handle in
            avs_component_create(handle, AVS_Effect_Handle(sender.tag), target.handle,
                                        intoTarget ? AVS_COMPONENT_POSITION_CHILD : AVS_COMPONENT_POSITION_AFTER)
        }
        reloadTree(select: created == 0 ? nil : created)
    }

    @objc private func deleteComponent() {
        guard let component = selected, component !== tree else { return }
        _ = core.withHandle { avs_component_delete($0, component.handle) }
        reloadTree()
    }

    @objc private func duplicateComponent() {
        guard let component = selected, component !== tree else { return }
        let copy = core.withHandle { avs_component_duplicate($0, component.handle) }
        reloadTree(select: copy == 0 ? nil : copy)
    }

    @objc private func toggleEnabled(_ sender: NSButton) {
        guard let node = outline.item(atRow: outline.row(for: sender)) as? Node else { return }
        node.enabled = core.withHandle { handle in
            var properties = AVS_Component_Properties()
            guard avs_component_properties_get(handle, node.handle, &properties) else { return node.enabled }
            properties.enabled = sender.state == .on
            return avs_component_properties_set(handle, node.handle, properties) ? properties.enabled : node.enabled
        }
        sender.state = node.enabled ? .on : .off
    }

    // MARK: - File

    @objc private func newPreset() {
        // Deleting the root clears the preset; libavs makes a new, empty root.
        _ = core.withHandle { avs_component_delete($0, avs_component_root($0)) }
        reloadTree()
    }

    @objc private func openPreset() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "avs") ?? .data, .json]
        panel.directoryURL = AvsPresets.customFolder
        guard let window, panel.runModal() == .OK, let url = panel.url else { return }
        if !core.loadPreset(at: url) {
            NSAlert.informational("Could not open \(url.lastPathComponent)", core.lastError).beginSheetModal(for: window)
        }
        reloadTree()
    }

    /// Legacy `.avs`: what the preset list reads and Winamp's AVS opens.
    @objc private func savePreset() {
        save(as: UTType(filenameExtension: "avs") ?? .data) { avs_preset_save_legacy($0, $1) }
    }

    /// libavs's JSON preset, which keeps what the legacy format cannot (comments, newer fields).
    @objc private func exportJSON() {
        save(as: .json) { avs_preset_save($0, $1, false, true) }
    }

    private func save(as type: UTType, _ write: (AVS_Handle, String) -> Bool) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [type]
        panel.directoryURL = AvsPresets.customFolder
        panel.nameFieldStringValue = "Untitled"
        guard let window, panel.runModal() == .OK, let url = panel.url else { return }
        window.makeFirstResponder(nil)
        if core.withHandle({ write($0, url.path) }) {
            engine?.reloadPresets()
        } else {
            NSAlert.informational("Could not save \(url.lastPathComponent)", core.lastError).beginSheetModal(for: window)
        }
    }
}

// MARK: - Outline data source and delegate

extension AvsEditorWindowController: NSOutlineViewDataSource, NSOutlineViewDelegate {
    func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
        guard let node = item as? Node else { return tree == nil ? 0 : 1 }
        return node.children.count
    }

    func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
        (item as? Node)?.children[index] ?? tree as Any
    }

    func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
        (item as? Node)?.canHaveChildren ?? false
    }

    func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
        guard let node = item as? Node else { return nil }
        // A bare checkbox beside a label: a click on the name selects the row, not toggles it.
        let box = NSButton(checkboxWithTitle: "", target: self, action: #selector(toggleEnabled(_:)))
        box.state = node.enabled ? .on : .off
        return NSStackView(views: [box, NSTextField(labelWithString: node.name)])
    }

    func outlineViewSelectionDidChange(_ notification: Notification) {
        inspector.show(selected?.handle ?? 0)
    }

    // Drag to move: the dragged row's handle on the pasteboard, `avs_component_move` on drop.

    func outlineView(_ outlineView: NSOutlineView, pasteboardWriterForItem item: Any) -> NSPasteboardWriting? {
        guard let node = item as? Node, node !== tree else { return nil }
        let entry = NSPasteboardItem()
        entry.setString(String(node.handle), forType: Self.dragType)
        return entry
    }

    func outlineView(_ outlineView: NSOutlineView, validateDrop info: NSDraggingInfo,
                     proposedItem item: Any?, proposedChildIndex index: Int) -> NSDragOperation {
        (item as? Node)?.canHaveChildren == true ? .move : []
    }

    func outlineView(_ outlineView: NSOutlineView, acceptDrop info: NSDraggingInfo,
                     item: Any?, childIndex index: Int) -> Bool {
        guard let parent = item as? Node,
              let string = info.draggingPasteboard.string(forType: Self.dragType),
              let dragged = AVS_Component_Handle(string) else { return false }
        let siblings = parent.children.map(\.handle)
        let moved = core.withHandle { handle -> Bool in
            if index >= 0, index < siblings.count {
                return siblings[index] == dragged
                    || avs_component_move(handle, dragged, siblings[index], AVS_COMPONENT_POSITION_BEFORE)
            }
            // Dropped on the parent or past its last child: the end of its children.
            if let last = siblings.last {
                return last == dragged || avs_component_move(handle, dragged, last, AVS_COMPONENT_POSITION_AFTER)
            }
            return avs_component_move(handle, dragged, parent.handle, AVS_COMPONENT_POSITION_CHILD)
        }
        reloadTree(select: dragged)
        return moved
    }
}

private extension NSAlert {
    static func informational(_ message: String, _ detail: String) -> NSAlert {
        let alert = NSAlert()
        alert.messageText = message
        alert.informativeText = detail
        return alert
    }
}
