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
