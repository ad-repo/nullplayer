import Foundation

/// Dock sites: a `LayoutDockSite` item in the main form holds another of the skin's forms (Bliss
/// Compact Dark's and Telos's playlist, Acubens' library and visualization) where AIMP would
/// otherwise open it as a window. `.acs4` names the form by `ControlName`, `.acs5` by its
/// `AllowedForms`' `default`; `InitialDocked` `False` starts it as a window. Scripts move it
/// between the two (`form.Dock`, `form.Undock`: A4 3.2's layouts, Red Bias's).
///
/// While docked, the painter lays the form out in its site inside one item named after the form
/// (`holder`), so the keys that show and hide the form (`PlaylistFrame.Visible`) show and hide it
/// in place, and its window stays closed. `ContentExtends` (l, t, r, b) lays the form out that much
/// past the site's edges, and the site clips it: the docked form's own window frame falls outside
/// (KibTech's 48 px, DEFIX Hi-End's 6).
enum AIMPSkinDockSites {
    struct Site: Sendable {
        /// The form the site holds.
        let form: String
        /// The item the painter lays out in the site while the form is docked.
        let holder: AIMPNode
        let initiallyDocked: Bool
    }

    /// The form a site names, and whether it starts docked; nil for an item that is no site.
    static func form(ofSite item: AIMPNode) -> (name: String, docked: Bool)? {
        guard item.tag == "item", item["class"] == "LayoutDockSite" else { return nil }
        let props = item.properties
        guard let name = props["ControlName"]?["value"] ?? props["AllowedForms"]?["default"], !name.isEmpty else { return nil }
        return (name, props["InitialDocked"]?["value"] != "False")
    }

    /// The main form's sites by name, for the forms `reading` finds. A form takes the first site
    /// that names it.
    static func sites(in main: AIMPNode, reading: (String) -> AIMPNode?) -> [String: Site] {
        var sites: [String: Site] = [:]
        var placed: Set<String> = []
        for item in main.descendants() {
            guard let site = item["name"], let named = form(ofSite: item), !placed.contains(named.name),
                  let form = reading(named.name) else { continue }
            placed.insert(named.name)
            sites[site] = Site(form: named.name, holder: holder(named.name, of: form, extends: AIMPNode.numbers(item.properties["ContentExtends"]?["value"])),
                               initiallyDocked: named.docked)
        }
        return sites
    }

    /// The item a docked form's items and controls sit in, filling the site.
    private static func holder(_ name: String, of form: AIMPNode, extends: [Int]) -> AIMPNode {
        var props = [AIMPNode.property("Alignment", "laClient")]
        if extends.count == 4 { props.append(AIMPNode.property("AlignmentMargins", extends.map { String(-$0) }.joined(separator: ","))) }
        return AIMPNode.element("item", ["class": "LayoutItem", "name": name],
                                [AIMPNode.propertyList(props)] + form.children.filter { $0.tag == "items" || $0.tag == "controls" })
    }
}
