import Foundation

/// The Wasabi standard window frames, and the conventional tag ↔ groupdef pairing real skins rely on.
///
/// A `.wal` window is a frame plus a content group: `<Wasabi:StandardFrame:Status
/// content="pledit.content.group">`. The frame's own `standardframe.maki` instantiates the named
/// group into its client area at runtime, which is why the frame *must* be a real skin-supplied
/// groupdef with that script attached — the identifier-only shells we seed for missing Wasabi bases
/// build nothing and would give a synthesized window a title bar and an empty hole.
///
/// CornerAmp and Winamp Modern declare `xuitag="Wasabi:StandardFrame:Status"` on the groupdef, so the
/// tag resolves normally. **mmd3 declares the same conventional ids with no `xuitag` at all** — in
/// real Winamp the standard library supplies the tag and the skin only overrides the definition — so
/// without the pairing below its playlist window is a frame that instantiates nothing (measured: 5
/// scene nodes, an empty white rectangle).
enum WasabiStandardFrames {

    /// The frame flavours, in the order synthesis prefers them: a status bar is the richest, a static
    /// frame the barest.
    enum Flavour: String, CaseIterable {
        case statusbar
        case nostatusbar
        case `static`

        var groupIdentifier: String {
            switch self {
            case .statusbar: return "wasabi.standardframe.statusbar"
            case .nostatusbar: return "wasabi.standardframe.nostatusbar"
            case .static: return "wasabi.standardframe.static"
            }
        }

        var xuiTag: String {
            switch self {
            case .statusbar: return "Wasabi:StandardFrame:Status"
            case .nostatusbar: return "Wasabi:StandardFrame:NoStatus"
            case .static: return "Wasabi:StandardFrame:Static"
            }
        }
    }

    /// The measured conventional pairs. `modal` is included because skins declare it in the same
    /// block; synthesis never selects it (a modal frame hides its system menu).
    static let conventionalXUITags: [(tag: String, identifier: String)] =
        Flavour.allCases.map { ($0.xuiTag, $0.groupIdentifier) }
        + [("Wasabi:StandardFrame:Modal", "wasabi.standardframe.modal")]
}

extension WasabiStandardFrames {

    /// Where the client area sits inside a frame we drew ourselves.
    ///
    /// Only reached when the skin declares **no** `wasabi.standardframe.*` of its own, so these
    /// numbers never displace a skin's own chrome. Calibrated against `Winamp 3.0 Default`, the one
    /// corpus skin whose every full-size layout is a bare `<Wasabi:StandardFrame:*>`: its player's
    /// `placeholder` sits at `6,5` in the content group and lands at `11,20` in the skin's own
    /// screenshot, which puts the client origin at `5,15`; its resize grip is a 16px sprite at
    /// `254,85`, so the client must be at least 270x101 inside a 275x116 window, which is what the
    /// right and bottom insets below leave.
    static let contentInset = (x: 5.0, y: 15.0, width: -5.0, height: -15.0)

    /// The title strip drawn across the top of such a frame — `contentInset.y`, by construction: the
    /// client area starts where the strip ends.
    static var titleHeight: Double { contentInset.y }

    static func flavour(forTypeName typeName: String) -> Flavour? {
        Flavour.allCases.first { $0.xuiTag.caseInsensitiveCompare(typeName) == .orderedSame }
    }

    static func isStandardFrame(_ object: WasabiObject) -> Bool {
        flavour(forTypeName: object.typeName) != nil
    }

    /// Set on a `<Wasabi:StandardFrame:*>` instance whose groupdef the skin never supplied, so the
    /// renderer knows to paint the chrome Winamp's own frame would have drawn.
    static let hostedAttribute = "nullplayer.standardframe"

    static func isHostedFrame(_ object: WasabiObject) -> Bool {
        isStandardFrame(object) && object.attributes[hostedAttribute] == "1"
    }

    /// The edge drawn around a frame we painted ourselves. One point, inside `contentInset`'s
    /// margin, so it never moves an object the skin placed.
    static let borderWidth = 1.0

    /// The `<group>` node for this frame's client area, or `nil` when the frame names no content.
    ///
    /// A standard frame **names its body by group id** rather than nesting it, and in real Winamp the
    /// frame's own `standardframe.maki` does the `newGroup(getParam("content"))`. A skin that ships
    /// that groupdef ships the script with it; a skin that expects Winamp's ships neither, so without
    /// this the named group never enters the graph at all — the same shape as `WasabiTitleBox`.
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
