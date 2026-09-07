import Foundation
import CoreGraphics

/// The window-chrome buttons Winamp supplied and a `.wal` never ships.
///
/// A Winamp3-era skin writes `<button action="CLOSE" image="wasabi.button.exit"/>` and declares no
/// `<bitmap>` for it, because the artwork lived in Wasabi's built-in resources rather than in the
/// archive. We ship none, so every such button resolved no image, sized itself to 0x0 and vanished:
/// `Winamp 3.0 Default` — Nullsoft's own *Winamp3 Base Skin* — has 24 references and not one
/// declaration, which left its player with no menu, no minimize, no windowshade and no close (B95).
///
/// The same deliberate exception to the identifier-only-shell rule as `WasabiTitleBox` and the
/// artwork-less `<Wasabi:Button text="…">`: the alternative is a titlebar whose every control is
/// invisible. Contained the same way too — a skin that declares its own `wasabi.button.*` bitmap
/// resolves it and never reaches here, which is why the four skins that declare *some* of the set
/// keep every piece of artwork they ship.
enum WasabiChromeButtons {

    /// The roles the corpus actually references. Anything else under `wasabi.button.` is left alone:
    /// this draws a known control, not a box around every unresolved id.
    enum Role: String, CaseIterable {
        case appmenu
        case sysmenu
        case minimize
        case maximize
        case restore
        case winshade
        case close
        case exit
        case more
        case less
        case arrowLeft = "label.arrow.left"
        case arrowRight = "label.arrow.right"
        case arrowUp = "label.arrow.up"
        case arrowDown = "label.arrow.down"

        /// What such a button measures when the skin states no `w`/`h` — it would otherwise size to
        /// the artwork, which is exactly what is missing.
        ///
        /// Measured from `Winamp 3.0 Default`'s own titlebar rather than chosen: its three right-hand
        /// buttons sit at `x="230"`, `x="244"` and `x="261"` in a 275-wide window, so each is 14 wide
        /// and the last one ends flush with the window edge. The 9 is the title strip
        /// (`WasabiStandardFrames.titleHeight`) less the `y="3"` they all declare, twice.
        var defaultSize: CGSize {
            switch self {
            case .arrowLeft, .arrowRight, .arrowUp, .arrowDown: return CGSize(width: 9, height: 9)
            default: return CGSize(width: 14, height: 9)
            }
        }
    }

    private static let prefix = "wasabi.button."

    /// The role a bitmap id names, ignoring the `.pressed` / `.active` state suffix skins append.
    static func role(forBitmapID identifier: String) -> Role? {
        let lower = identifier.lowercased()
        guard lower.hasPrefix(prefix) else { return nil }
        var name = String(lower.dropFirst(prefix.count))
        for suffix in [".pressed", ".active", ".inactive", ".hover", ".disabled", ".enabled"]
        where name.hasSuffix(suffix) {
            name = String(name.dropLast(suffix.count))
            break
        }
        return Role(rawValue: name)
    }

    /// The role this object is a chrome button for, or `nil` if it is not one.
    ///
    /// `resolvedBitmapID` has already answered which of `image=` / `downImage=` / `activeImage=` is in
    /// force, so the caller passes that; a button whose id resolved to a real resource never gets here.
    static func role(of object: WasabiObject, bitmapID: String?) -> Role? {
        let type = object.typeName.lowercased()
        guard type == "button" || type == "togglebutton" || type == "wasabi:button" else { return nil }
        if let bitmapID, let role = role(forBitmapID: bitmapID) { return role }
        // A button whose *current* state has no id at all (an `activeImage` the skin omits) still
        // draws its role, taken from the one it always states.
        for attribute in ["image", "downImage", "activeImage"] {
            if let value = object.attributes[attribute], let role = role(forBitmapID: value) { return role }
        }
        return nil
    }

    /// The glyph, as a unit-square path the renderer scales into the button.
    ///
    /// Line work only, in one colour: these are chrome, and a skin's titlebar is as often light as it
    /// is dark, so the drawing has to read either way with nothing but the palette's text colour.
    static func glyphPath(for role: Role, in box: CGRect) -> CGPath {
        let path = CGMutablePath()
        let inset = box.insetBy(dx: box.width * 0.25, dy: box.height * 0.25)
        switch role {
        case .close, .exit:
            path.move(to: CGPoint(x: inset.minX, y: inset.minY))
            path.addLine(to: CGPoint(x: inset.maxX, y: inset.maxY))
            path.move(to: CGPoint(x: inset.minX, y: inset.maxY))
            path.addLine(to: CGPoint(x: inset.maxX, y: inset.minY))
        case .minimize:
            path.move(to: CGPoint(x: inset.minX, y: box.midY))
            path.addLine(to: CGPoint(x: inset.maxX, y: box.midY))
        case .winshade:
            // Rolling the window up to its title strip: the strip, with the body folding into it.
            path.move(to: CGPoint(x: inset.minX, y: inset.maxY))
            path.addLine(to: CGPoint(x: inset.maxX, y: inset.maxY))
            path.move(to: CGPoint(x: inset.minX, y: inset.minY))
            path.addLine(to: CGPoint(x: box.midX, y: inset.midY))
            path.addLine(to: CGPoint(x: inset.maxX, y: inset.minY))
        case .maximize, .restore:
            path.addRect(inset)
        case .appmenu, .sysmenu:
            for step in 0...2 {
                let y = inset.minY + inset.height * CGFloat(step) / 2
                path.move(to: CGPoint(x: inset.minX, y: y))
                path.addLine(to: CGPoint(x: inset.maxX, y: y))
            }
        case .more, .arrowDown:
            path.move(to: CGPoint(x: inset.minX, y: inset.maxY))
            path.addLine(to: CGPoint(x: box.midX, y: inset.minY))
            path.addLine(to: CGPoint(x: inset.maxX, y: inset.maxY))
        case .less, .arrowUp:
            path.move(to: CGPoint(x: inset.minX, y: inset.minY))
            path.addLine(to: CGPoint(x: box.midX, y: inset.maxY))
            path.addLine(to: CGPoint(x: inset.maxX, y: inset.minY))
        case .arrowLeft:
            path.move(to: CGPoint(x: inset.maxX, y: inset.minY))
            path.addLine(to: CGPoint(x: inset.minX, y: box.midY))
            path.addLine(to: CGPoint(x: inset.maxX, y: inset.maxY))
        case .arrowRight:
            path.move(to: CGPoint(x: inset.minX, y: inset.minY))
            path.addLine(to: CGPoint(x: inset.maxX, y: box.midY))
            path.addLine(to: CGPoint(x: inset.minX, y: inset.maxY))
        }
        return path
    }
}
