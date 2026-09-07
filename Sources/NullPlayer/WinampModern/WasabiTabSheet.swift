import CoreGraphics
import Foundation

/// `<Wasabi:TabSheet>` — Wasabi's tabbed page host:
///
/// ```xml
/// <Wasabi:TabSheet x="15" y="20" w="-30" h="-40" relatw="1" relath="1"
///                  children="config.button.sel;config.colorthemes" />
/// ```
///
/// Like a standard frame and a `<Wasabi:TitleBox>`, a tab sheet **names its pages by group id**
/// rather than nesting them, and in Winamp the standard library's own object is what instantiates
/// them, draws a tab per page and shows one at a time. No `.wal` supplies that object, so the tag
/// resolved to an identifier-only shell: the sheet drew nothing and every page stayed out of the
/// graph. Shield_Amp's Configuration window is one tab sheet, which is why it came up as an empty
/// slab (B14).
///
/// Measured: 4 skins declare 5 tab sheets — Anexa's colour window, Enkera's config (two, one nested
/// inside the other), mmd3's winshade sidecar and Shield_Amp's notifier preferences.
///
/// **A page's tab label is the page groupdef's own `name`.** All four skins spell it that way and
/// nothing else in the markup names a tab: `<groupdef id="themes.stuff" name="Themes">`,
/// `<groupdef id="colour.main" name="Colour Themes">`. The instantiated page carries the attribute
/// because a groupdef's defaults merge onto its instance, so the label is read off the page object.
///
/// **The artwork is conventional and two skins ship it.** Bio-Nid replaces the widget wholesale and
/// its `wasabi.tabsheet.button.selected.group` / `.unselected.group` are the closest thing the corpus
/// has to Winamp's own definition: a nine-slice `<grid>` of `wasabi.tabsheet.button.*` for the
/// selected tab, the `.shade.*` set plus a `.bottom` strip for an unselected one, `h="20"`, and the
/// label auto-sizing the button (`autowidthsource="text"`, `x="5" w="-13"`). Shield_Amp and mmd3 both
/// ship those bitmap ids without the groupdefs, so this reads them the way the standard slider reads
/// `wasabi.slider.horizontal.*` — the skin's own artwork when it has any, a drawn strip when it does
/// not (Anexa and Enkera ship neither).
///
/// **Not handled, deliberately:** `type=` (Enkera's inner sheet and mmd3 say `type="2"`; nothing in
/// the corpus tells us what the variants look like, so every sheet gets the top strip), and
/// `windowtype=` — mmd3's sidecar hosts a *window* rather than a set of page groups and declares no
/// `children` at all, so it stays as inert as it is today rather than being guessed at.
enum WasabiTabSheet {
    static let xuiTag = "Wasabi:TabSheet"
    static let groupIdentifier = "wasabi.tabsheet"

    /// Height of the tab strip, from Bio-Nid's `h="20"` on both replacement groupdefs.
    static let stripHeight: CGFloat = 20

    /// Padding either side of a tab's label, from the same source: the label sits at `x="5"` in a
    /// box cut `w="-13"`, so it clears 5 on the left and 8 on the right.
    static let labelLeading: CGFloat = 5
    static let labelTrailing: CGFloat = 8

    /// A tab narrow enough to have lost its label is still a tab the pointer has to be able to find.
    static let minimumTabWidth: CGFloat = 16

    /// The nine-slice the selected tab is cut from, and the shaded one behind an unselected tab.
    /// Both sets are conventional ids the skins declare themselves; a missing part degrades to the
    /// drawn strip, exactly as a missing slider track does.
    static let selectedArtwork = (topLeft: "wasabi.tabsheet.button.topleft",
                                  top: "wasabi.tabsheet.button.top",
                                  topRight: "wasabi.tabsheet.button.topright",
                                  left: "wasabi.tabsheet.button.left",
                                  right: "wasabi.tabsheet.button.right")
    static let unselectedArtwork = (topLeft: "wasabi.tabsheet.button.shade.topleft",
                                    top: "wasabi.tabsheet.button.shade.top",
                                    topRight: "wasabi.tabsheet.button.shade.topright",
                                    left: "wasabi.tabsheet.button.shade.left",
                                    middle: "wasabi.tabsheet.button.shade.middle",
                                    right: "wasabi.tabsheet.button.shade.right")
    /// The lip an unselected tab draws along its bottom edge, level with the selected tab's baseline.
    static let unselectedBottom = "wasabi.tabsheet.button.bottom"

    /// How far an unselected tab is pushed down from the top of the strip — Bio-Nid's shaded grid
    /// starts at `y="3"`, which is what makes the selected tab stand proud of its neighbours.
    static let unselectedInset: CGFloat = 3

    /// Which page is showing. Held on the object rather than beside it so a redraw, a hit test and a
    /// script all read one answer, the way `<Wasabi:Frame>` holds its divider in `position`.
    static let selectedIndexAttribute = "nullplayer.tabsheet.selected"

    /// Stamped on a sheet **this engine** is hosting, and the containment for the whole widget.
    ///
    /// The `else` the form widgets rely on is not available here, because a tab sheet keeps its own
    /// type name whether or not a definition claimed the tag — so a skin shipping
    /// `<groupdef xuitag="Wasabi:TabSheet">` would otherwise get its own body *and* a strip drawn
    /// over it. The initializer stamps this only when the tag resolved to nothing but our own
    /// artwork-less shell, and the renderer and the view both key off it rather than off the tag.
    static let hostedAttribute = "nullplayer.tabsheet"

    static func isTabSheet(typeName: String) -> Bool {
        typeName.caseInsensitiveCompare(xuiTag) == .orderedSame
    }

    static func isTabSheet(_ object: WasabiObject) -> Bool { isTabSheet(typeName: object.typeName) }

    /// A tab sheet this engine supplies the body for — the only kind anything downstream acts on.
    static func isHosted(_ object: WasabiObject) -> Bool {
        isTabSheet(object) && object.attributes[hostedAttribute] == "1"
    }

    /// The page group ids this sheet instantiates, in declaration order. Winamp separates them with
    /// `;`. Empty for mmd3's `windowtype=` sidecar, which names no pages.
    static func pageIdentifiers(of object: WasabiObject) -> [String] {
        (object.attributes["children"] ?? "")
            .split(separator: ";", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    /// The page objects this sheet is showing between, in `children=` order. Matched by id rather
    /// than taken positionally: a sheet's own instance children (a script, say) are not pages.
    static func pages(of object: WasabiObject) -> [WasabiObject] {
        pageIdentifiers(of: object).compactMap { identifier in
            object.children.first { $0.xmlID?.caseInsensitiveCompare(identifier) == .orderedSame }
        }
    }

    /// A page's tab label: the groupdef's own `name`, falling back to its id so a skin that states
    /// none still gets a tab that can be told apart and clicked.
    static func label(of page: WasabiObject) -> String {
        let name = (page.attributes["name"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? (page.xmlID ?? "") : name
    }

    /// The showing page's index, clamped to the pages that exist.
    static func selectedIndex(of object: WasabiObject) -> Int {
        let count = pageIdentifiers(of: object).count
        guard count > 0 else { return 0 }
        let stored = object.attributes[selectedIndexAttribute].flatMap(Int.init) ?? 0
        return max(0, min(count - 1, stored))
    }

    /// Show one page and hide the rest. Returns whether anything changed, so a caller can skip the
    /// redraw and the script dispatch.
    ///
    /// Visibility is the whole mechanism: an invisible object leaves the scene with its subtree, so
    /// a hidden page neither draws nor answers the pointer, and nothing else in the renderer needs to
    /// know a tab sheet exists.
    @discardableResult
    static func select(index: Int, on object: WasabiObject) -> Bool {
        let pages = pages(of: object)
        guard !pages.isEmpty else { return false }
        let clamped = max(0, min(pages.count - 1, index))
        var changed = object.setAttribute(selectedIndexAttribute, value: String(clamped))
        for (position, page) in pages.enumerated() {
            changed = page.setAttribute("visible", value: position == clamped ? "1" : "0") || changed
        }
        return changed
    }

    /// The `<group>` nodes for this sheet's pages, inset below the strip and filling what is left.
    ///
    /// The first page starts visible and the rest start hidden, which is the state `select(index:)`
    /// then maintains. Written as instance attributes so they beat whatever the page's own groupdef
    /// says — an instance attribute wins over a definition default.
    static func pageNodes(for object: WasabiObject, location: WalSourceLocation) -> [WalXMLNode] {
        pageIdentifiers(of: object).enumerated().map { position, identifier in
            WalXMLNode(name: "group", attributes: [
                "id": identifier,
                "x": "0", "y": String(Int(stripHeight)),
                "w": "0", "h": String(-Int(stripHeight)),
                "relatw": "1", "relath": "1",
                "visible": position == 0 ? "1" : "0",
            ], location: location)
        }
    }

    /// Where each tab sits along the strip, given the width each label wants.
    ///
    /// Winamp sizes a tab to its own label (`autowidthsource="text"`), so that is the first answer.
    /// A row that would overflow the sheet is shared out equally instead — Enkera cuts four tabs into
    /// a 254px box and truncated labels the user can still tell apart beat tabs that run off the
    /// edge and cannot be clicked at all.
    static func tabRects(in frame: CGRect, labelWidths: [CGFloat]) -> [CGRect] {
        guard !labelWidths.isEmpty, frame.width > 0 else { return [] }
        let natural = labelWidths.map { max(minimumTabWidth, $0 + labelLeading + labelTrailing) }
        let total = natural.reduce(0, +)
        let widths = total <= frame.width
            ? natural
            : Array(repeating: frame.width / CGFloat(labelWidths.count), count: labelWidths.count)
        var x = frame.minX
        return widths.map { width in
            defer { x += width }
            return CGRect(x: x, y: frame.minY, width: width, height: min(stripHeight, frame.height))
        }
    }
}
