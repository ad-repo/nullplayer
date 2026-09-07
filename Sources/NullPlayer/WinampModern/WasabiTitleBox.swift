import Foundation

/// `<Wasabi:TitleBox>` — Wasabi's titled group box:
///
/// ```xml
/// <Wasabi:TitleBox id="radarbox" x="1" y="12" w="-3" h="70" relatw="1"
///                  title="THIS BUTTON MUST BE TURNED ON FOR GRAPHICS SMOOTHING"
///                  content="dtabox.content" />
/// ```
///
/// Like a standard frame, a title box **names its body by group id** rather than nesting it, and in
/// Winamp the standard library's own object is what instantiates that group. Unlike a standard frame,
/// no `.wal` supplies the object: the tag resolves to nothing, so the box drew nothing and its whole
/// content group stayed out of the graph. Bio-Nid's only settings window is one title box, which is
/// why it came up as an empty slab (measured: 9 of the 35 installed skins declare 33 title boxes
/// between them, and **none** ships a `wasabi.titlebox.*` bitmap — the artwork lives in Winamp).
enum WasabiTitleBox {
    static let xuiTag = "Wasabi:TitleBox"
    static let groupIdentifier = "wasabi.titlebox"

    /// Where the body sits inside the box: clear of the border, below the title.
    ///
    /// Calibrated against the measured content groups rather than invented — Shield_Amp and Itemskin
    /// wrap one 20px row in `h="40"`, and their rows start at `y="0"`, which puts the body's top edge
    /// 18px down and leaves 6px under it.
    static let contentInset = (x: 8.0, y: 18.0, width: -16.0, height: -24.0)

    /// Height of the title line above the border.
    static let titleHeight = 12.0

    static func isTitleBox(typeName: String) -> Bool {
        typeName.caseInsensitiveCompare(xuiTag) == .orderedSame
    }

    static func isTitleBox(_ object: WasabiObject) -> Bool { isTitleBox(typeName: object.typeName) }

    /// The title as written, trimmed — skins pad it for the artwork we do not have (Bio-Nid's begins
    /// with a space, which would otherwise indent the label past its own border).
    static func title(of object: WasabiObject) -> String {
        (object.attributes["title"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The `<group>` node for this box's body, or `nil` when the skin named none (Enkera declares two
    /// title boxes as bare labelled frames around objects placed beside them).
    static func contentGroupNode(for object: WasabiObject, location: WalSourceLocation) -> WalXMLNode? {
        guard let content = object.attributes["content"]?
            .trimmingCharacters(in: .whitespacesAndNewlines), !content.isEmpty else { return nil }
        return WalXMLNode(name: "group", attributes: [
            "id": content,
            "x": String(Int(contentInset.x)), "y": String(Int(contentInset.y)),
            "w": String(Int(contentInset.width)), "h": String(Int(contentInset.height)),
            "relatw": "1", "relath": "1",
        ], location: location)
    }
}
