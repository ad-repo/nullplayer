import Foundation

/// Wasabi's `<Menu>` — one entry of a skin's own menu bar.
///
/// ```xml
/// <groupdef id="menugroup.file" autowidthsource="File.txt" h="16">
///   <menu:button_normal  id="File.up.btn"    x="0" y="0"/>
///   <menu:button_pressed id="File.down.btn"  x="0" y="0" visible="0"/>
///   <menu:button_hover   id="File.hover.btn" x="0" y="0" visible="0"/>
///   <layer id="File.txt" image="txt.menu.file" x="0" y="0"/>
///   <Menu id="File.menu" menugroup="main" next="Play.menu" prev="Help.menu"
///         x="0" y="0" h="16" w="0" relatw="1" menu="WA5:File"
///         normal="File.up.btn" hover="File.hover.btn" down="File.down.btn"/>
/// </groupdef>
/// ```
///
/// The object draws nothing. It is a hit region over three sibling objects it owns, and it swaps
/// which of them is visible as the pointer arrives, presses and leaves. `menu=` names the **host's**
/// menu to pop — the entry is a handle on one of Winamp's own menus, not a menu the skin builds.
///
/// **The `normal` object is visible at rest** — that is what the markup says (`visible="1"` on the
/// normal layer, `visible="0"` on the other two) and what Nullsoft's own skin confirms from the other
/// direction: Winamp Modern 5.66's `menu.button.normal` groupdef is literally `<!-- Dummy -->`, an
/// empty group, and it is the one of the three left visible. A `<Menu>` swaps states; it never hides
/// the bar at rest. Recorded because the alternative reading — that Winamp reveals `normal` only
/// while the menu group is active — would have been an engine-level way to hide the magenta filler
/// four cPro skins ship in place of cut menu artwork, and it is not what Winamp does. That filler is
/// a per-skin defect; see `skins/` for the four.
enum WasabiMenuBar {

    static func isMenu(_ object: WasabiObject) -> Bool {
        // Namespaced spellings resolve through the type registry to the same tag, so the last
        // component is what identifies it.
        (object.typeName.lowercased().components(separatedBy: ":").last ?? "") == "menu"
    }

    /// Which of the three state objects a `<Menu>` is showing.
    enum State: String {
        case normal, hover, down
    }

    /// The sibling named by `normal=`/`hover=`/`down=`, if the skin declared one for that state.
    ///
    /// Looked up from the `<Menu>`'s **parent**, because that is the scope the ids are written in:
    /// every menu entry is its own groupdef and names three siblings inside it. Falling back to a
    /// whole-layout search would let `File.up.btn` be answered by another entry's object in a skin
    /// that reuses ids across groups.
    static func stateObject(_ state: State, of object: WasabiObject) -> WasabiObject? {
        guard let identifier = object.attributes[state.rawValue], !identifier.isEmpty,
              let parent = object.parent else { return nil }
        return descendant(of: parent, xmlID: identifier)
    }

    /// Show the object for `state` and hide the other two.
    ///
    /// Returns whether anything actually changed, so a caller can skip the repaint. Exactly one of
    /// the three is visible at a time, which is the state the markup ships in.
    @discardableResult
    static func apply(_ state: State, to object: WasabiObject) -> Bool {
        var changed = false
        for candidate in State.allStates {
            guard let target = stateObject(candidate, of: object) else { continue }
            let wanted = candidate == state ? "1" : "0"
            if target.attributes["visible"] != wanted {
                _ = target.setAttribute("visible", value: wanted)
                changed = true
            }
        }
        return changed
    }

    /// The host menu this entry opens — `menu="WA5:File"` → `"WA5:File"`. `nil` for a `<Menu>` that
    /// names none, which is an entry with nothing behind it rather than a defect.
    static func hostMenuIdentifier(of object: WasabiObject) -> String? {
        guard let raw = object.attributes["menu"]?.trimmingCharacters(in: .whitespaces),
              !raw.isEmpty else { return nil }
        return raw
    }

    /// The `menugroup=` this entry belongs to. Winamp uses it, with `next=`/`prev=`, to move an open
    /// menu along the bar as the pointer crosses its siblings. NullPlayer opens each entry on its own
    /// click; the group is read but that traversal is not implemented (see `reference/rendering.md`).
    static func menuGroup(of object: WasabiObject) -> String? {
        object.attributes["menugroup"]
    }

    private static func descendant(of root: WasabiObject, xmlID: String) -> WasabiObject? {
        for child in root.children {
            if child.xmlID?.caseInsensitiveCompare(xmlID) == .orderedSame { return child }
            if let match = descendant(of: child, xmlID: xmlID) { return match }
        }
        return nil
    }
}

private extension WasabiMenuBar.State {
    static var allStates: [WasabiMenuBar.State] { [.normal, .hover, .down] }
}
