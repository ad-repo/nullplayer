import Foundation

/// What a Wasabi object is, parsed once from its tag when the object is made (B228).
///
/// A tag is a local name and an optional namespace: `Wasabi:Button` is `button` in `wasabi`, a bare
/// `<button>` is `button` in `none`. The two answer different questions, and a compare used to pick
/// one by spelling — the full name or the namespace-dropped one — at each site, which is how B217
/// found the two spellings matching differently from one line to the next. Now a site says which
/// it means: `tag.is(.button)` for the bare tag, `tag.is(.button, in: .wasabi)` for the standard
/// library's, `tag.isStandard(.button)` for either. There is no any-namespace match (B237): `ColorThemes:List` is not a list, so a site
/// that wants a foreign namespace names it.
///
/// The cases are the tags the engine treats specially; every other tag is `.other`. A skin's own
/// XUI tags are not cases: they are the skin's, looked up in its registry.
enum WasabiKind: String {
    case albumArt = "albumart"
    case animatedLayer = "animatedlayer"
    case browser
    case button
    case component
    case componentBucket = "componentbucket"
    case container
    case customObject = "customobject"
    case edit
    case editBox = "editbox"
    case eqVis = "eqvis"
    case frame
    case gradient
    case grid
    case group
    case groupList = "grouplist"
    case images
    case layer
    case layout
    case layoutStatus = "layoutstatus"
    case list
    case menu
    case nStatesButton = "nstatesbutton"
    case noStatus = "nostatus"
    case progressGrid = "progressgrid"
    case rect
    case scripts
    case slider
    case songticker
    case staticFrame = "static"
    case status
    case tabSheet = "tabsheet"
    case text
    case titleBox = "titlebox"
    case toggleButton = "togglebutton"
    case tree
    case vis
    case windowHolder = "windowholder"
    case other

    /// The buttons. Each site still says which namespace it means: `isInteractive` hit-tests a
    /// `Wasabi:Button` as a button, while `hasOwnCommand` leaves one with no command a drag surface.
    static let buttons: Set<WasabiKind> = [.button, .toggleButton, .nStatesButton]

    /// The controls whose press is a command by their type alone.
    static let commands: Set<WasabiKind> = buttons.union([.slider])
}

/// The namespace a tag was written in: `Wasabi:`, `Wasabi:StandardFrame:`, `Winamp:`,
/// `ColorThemes:`, or none.
enum WasabiNamespace {
    case none
    case wasabi
    case wasabiStandardFrame
    case winamp
    case colorThemes
    case other
}

/// A tag parsed once into its kind and namespace, ignoring case (`WasabiKind`).
struct WasabiTag: Hashable {
    /// The local name whatever the namespace — private, so every match names its namespace too.
    private let kind: WasabiKind
    let namespace: WasabiNamespace

    init(_ name: String) {
        let lower = name.lowercased()
        guard let colon = lower.lastIndex(of: ":") else {
            kind = WasabiKind(rawValue: lower) ?? .other
            namespace = .none
            return
        }
        switch lower[..<colon] {
        case "wasabi": namespace = .wasabi
        case "wasabi:standardframe": namespace = .wasabiStandardFrame
        case "winamp": namespace = .winamp
        case "colorthemes": namespace = .colorThemes
        default: namespace = .other
        }
        kind = WasabiKind(rawValue: String(lower[lower.index(after: colon)...])) ?? .other
    }

    /// Whether the tag is `kind` written in `namespace`: `is(.layout)` is a bare `<layout>`,
    /// `is(.button, in: .wasabi)` the standard library's `Wasabi:Button`.
    func `is`(_ kind: WasabiKind, in namespace: WasabiNamespace = .none) -> Bool {
        self.kind == kind && self.namespace == namespace
    }

    /// Whether the tag is one of `kinds`, written in `namespace`.
    func `is`(anyOf kinds: Set<WasabiKind>, in namespace: WasabiNamespace = .none) -> Bool {
        self.namespace == namespace && kinds.contains(kind)
    }

    /// Whether the tag is `kind` bare or in the standard library: `<text>` or `<Wasabi:Text>`.
    func isStandard(_ kind: WasabiKind) -> Bool {
        isStandard(anyOf: [kind])
    }

    /// Whether the tag is one of `kinds`, bare or in the standard library.
    func isStandard(anyOf kinds: Set<WasabiKind>) -> Bool {
        (namespace == .none || namespace == .wasabi) && kinds.contains(kind)
    }
}
