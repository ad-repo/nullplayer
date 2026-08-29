import CoreGraphics
import Foundation

/// The Wasabi standard library's **form widgets** — `<Wasabi:Text>`, `<Wasabi:CheckBox>`,
/// `<Wasabi:EditBox>`, `<Wasabi:HSlider>` and `<Wasabi:DropDownList>`.
///
/// Every one is a conventional XUI tag whose body lives inside Winamp rather than inside the `.wal`,
/// so each resolved to a structure-free shell and became an inert node: 156 declarations across 15
/// skins, and **this is what an empty settings page usually is** (B66). Styx's Config draws three
/// labelled boxes and two of them were empty, because their bodies are these widgets.
///
/// What Winamp's own definitions are, measured from the three skins that ship a *replacement* for one
/// (Lobe, Big Bento Modern and ZDL each define `<groupdef xuitag="Wasabi:Text" embed_xui="wasabi.text"
/// h="12"><text …/></groupdef>`): a standard widget is a thin wrapper around **one primitive the
/// engine already has**. So the mapping here is a type substitution rather than a new control — the
/// tag becomes the primitive, and hit testing, drawing, script dispatch, `cfgattrib` binding and
/// geometry all follow with nothing else to teach.
///
/// Two of the five have no primitive to become, because Winamp composes them from a button and a
/// label: a check box and a drop-down list are drawn here, on the same deliberate exception to the
/// identifier-only-shell rule as an artwork-less `<Wasabi:Button text="…">` and `<Wasabi:TitleBox>`.
/// No `.wal` in the corpus ships `wasabi.checkbox.*` artwork, so the alternative is a settings page
/// whose switches are invisible. A slider is the opposite case and worth the contrast: **19** of the
/// 36 installed skins do ship `wasabi.slider.horizontal.button`, which is why the mapping seeds those
/// conventional ids rather than drawing a thumb of its own, and only falls back to a drawn one when
/// the skin ships neither.
///
/// The mapping is applied **only when nothing else claims the tag** (`WasabiSkinInitializer`), so a
/// skin's own `<groupdef xuitag="Wasabi:Text">` always wins — which is how Big Bento Modern keeps its
/// own search box and Styx keeps its own drop-down wrapper.
enum WasabiFormWidgets {
    /// Stamped on the object so the renderer can tell a substituted widget from the primitive a skin
    /// wrote itself. A `<slider>` a skin declared must keep drawing exactly what it drew before.
    static let kindAttribute = "nullplayer.formwidget"

    enum Kind: String {
        case text
        case edit
        case horizontalSlider
        case checkBox
        case dropDownList
    }

    /// The primitive a standard tag becomes, plus the attributes Winamp's own definition supplies.
    ///
    /// Seeded attributes never override the instance's own: `high="40"` on Shield_Amp's hold-time
    /// slider and a `thumb=` on impulse's both stand.
    struct Substitution {
        var kind: Kind
        var typeName: String
        var defaults: [String: String]
    }

    /// Conventional id of the standard horizontal slider's thumb, and of its pressed frame.
    ///
    /// Not invented: it is what impulse's own `<Wasabi:HSlider thumb="wasabi.slider.horizontal.button">`
    /// names, and 19 installed skins declare the bitmap — including all four that use the tag.
    static let horizontalSliderThumb = "wasabi.slider.horizontal.button"
    static let horizontalSliderDownThumb = "wasabi.slider.horizontal.button.pressed"

    /// The three-part track the same skins cut beside the thumb.
    static let horizontalTrack = (left: "wasabi.slider.horizontal.left",
                                  middle: "wasabi.slider.horizontal.middle",
                                  right: "wasabi.slider.horizontal.right")

    /// A check box's glyph is a square the height of one row, with the label starting after it.
    static let checkBoxGlyph: CGFloat = 11
    static let checkBoxLabelGap: CGFloat = 4

    /// One row, which is the height Winamp's check box takes when a skin states none — impulse's own
    /// `Impulse:Checkbox` groupdef says `h="14"` and stacks its rows on a 20px pitch, and Styx spaces
    /// its unsized ones 14 apart (`y="57"`, `y="71"`). Every measured declaration agrees on 14.
    static let checkBoxHeight = 14

    /// Where the drop-down's arrow sits, and how wide a bite it takes out of the label.
    static let dropDownArrowWidth: CGFloat = 14

    /// The object id Winamp's drop-down gives the label inside it, and the handle a skin's script
    /// reaches for. Styx's and Shield_Amp's `customdropdownlist.maki` are the same script:
    /// `findObject("dropdownlist.text")`, then `onTextChanged` writes the pick to a private string.
    /// Without an object carrying that id the handle is null and the selection is never persisted.
    static let dropDownLabelID = "dropdownlist.text"

    static func substitution(forTypeName name: String) -> Substitution? {
        switch name.lowercased() {
        case "wasabi:text":
            return Substitution(kind: .text, typeName: "text", defaults: [:])
        case "wasabi:editbox", "wasabi:editbox2":
            return Substitution(kind: .edit, typeName: "edit", defaults: [:])
        case "wasabi:hslider":
            return Substitution(kind: .horizontalSlider, typeName: "slider", defaults: [
                "thumb": horizontalSliderThumb,
                "downthumb": horizontalSliderDownThumb,
            ])
        case "wasabi:checkbox":
            // A togglebutton, because that is what a check box is: `toggleActivation` gives it the
            // flip and the `onToggle`/`onActivate` pair its script listens for, and a bound one goes
            // down the `cfgattrib` road every other switch in the skin already takes.
            return Substitution(kind: .checkBox, typeName: "togglebutton",
                                defaults: ["h": String(checkBoxHeight)])
        case "wasabi:dropdownlist":
            return Substitution(kind: .dropDownList, typeName: "button", defaults: [:])
        default:
            return nil
        }
    }

    static func kind(of object: WasabiObject) -> Kind? {
        object.attributes[kindAttribute].flatMap(Kind.init(rawValue:))
    }

    /// A check box drawn as a **radio button**: one of a set named by `radioid`, of which exactly one
    /// is on. Styx spells all four of its preference pairs this way and 32 of the corpus's 67 check
    /// boxes carry the attribute, so this is not an edge of the tag — it is half of it.
    static func radioIdentifier(of object: WasabiObject) -> String? {
        guard let raw = object.attributes["radioid"]?
            .trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else { return nil }
        return raw.lowercased()
    }

    /// The items a drop-down offers, in declaration order. Winamp separates them with `;`.
    static func items(of object: WasabiObject) -> [String] {
        (object.attributes["items"] ?? "")
            .split(separator: ";", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    /// What a drop-down is showing.
    ///
    /// `default` is the attribute Winamp's own object reads and the one a skin's script writes
    /// (`setXmlParam("default", getPrivateString(…))`), so a restored selection arrives here. A skin
    /// that instantiates the tag directly instead names its starting item `defaultlistitem`.
    static func selection(of object: WasabiObject) -> String {
        for key in ["default", "defaultlistitem", "text"] {
            if let value = object.attributes[key], !value.isEmpty { return value }
        }
        return items(of: object).first ?? ""
    }

    /// The `<text>` node Winamp's drop-down carries inside itself, expanded beneath the substituted
    /// object so a skin's script can find it.
    ///
    /// Deliberately invisible: the drop-down draws its own label from `default`, so a second text
    /// object over the same rect would print the selection twice. It exists to *be found* — this is
    /// the handle `onTextChanged` is hung on.
    /// The label object inside a drop-down, wherever it came from: the node above, or — for a skin
    /// that wraps the tag in its own groupdef — the one the skin wrote itself.
    static func dropDownLabel(of object: WasabiObject) -> WasabiObject? {
        for child in object.children {
            if child.xmlID?.caseInsensitiveCompare(dropDownLabelID) == .orderedSame { return child }
            if let match = dropDownLabel(of: child) { return match }
        }
        return nil
    }

    static func labelNode(location: WalSourceLocation) -> WalXMLNode {
        WalXMLNode(name: "text", attributes: [
            "id": dropDownLabelID,
            "x": "0", "y": "0", "w": "0", "h": "0", "relatw": "1", "relath": "1",
            "visible": "0", "ghost": "1",
        ], location: location)
    }
}
