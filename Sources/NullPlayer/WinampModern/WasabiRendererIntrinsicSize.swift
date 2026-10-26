import AppKit

/// How big an object is when it does not say: the intrinsic size `append(object:)` resolves its
/// geometry against. Split out of `WasabiRenderer.swift`; see
/// `skills/winamp-modern-skin-guide/reference/rendering.md`.
extension WasabiSceneRenderer {
    /// The size an object takes when it states none: its artwork, its text, its content, or a rule
    /// a skin taught us. `geometry(of:).resolve` reads it only on an axis the object leaves unstated.
    /// Every rule is a clause here, in priority order, so a new one joins this list rather than
    /// `append(object:)`.
    func intrinsicSize(of object: WasabiObject, bitmapID: String?, parentFrame: CGRect,
                       isRoot: Bool) -> WasabiSize {
        var intrinsic = resources.bitmap(identifier: bitmapID).map {
            WasabiSize(width: Double($0.width), height: Double($0.height))
        } ?? .zero
        // An animated layer that states no size of its own is one **frame** tall, not one sheet tall:
        // its bitmap is a strip of N frames and `framewidth`/`frameheight` say how it is cut. Taking
        // the sheet made multipass's seek bar a 139×364 box where the skin drew a 139×13 one — one
        // frame stretched over twenty-eight frames' worth of height, then clipped by the display group
        // to a transparent sliver, so the skin's only seek indicator was invisible while the script
        // behind it worked perfectly.
        if object.tag.is(.animatedLayer) {
            if let width = Double(object.attributes["framewidth"] ?? ""), width > 0 { intrinsic.width = width }
            if let height = Double(object.attributes["frameheight"] ?? ""), height > 0 { intrinsic.height = height }
        }
        // `autowidthsource="<id>"` sizes a group to the text of the named descendant. ClassicPro's
        // menu bar is five such groups: without this each is 0 wide and its label, a `relatw="1"`
        // child, has nowhere to draw — the whole File/Play/Options/View/Help strip disappears.
        if object.attributes["w"] == nil, let width = autoWidth(of: object) {
            intrinsic.width = Double(width)
        }
        // A `<text>` that states no `h` is one line tall, not zero. Wasabi sizes such an object to the
        // font it draws in; here it resolved to 0, the draw clipped to the frame, and the string was
        // simply absent. Big Bento's notifier is three of them — `<text id="title" w="0" relatw="1"
        // fontsize="46">` with no height at all — so its song title never drew, and the host had to
        // paste a height on before showing the toast (`ensureTextHeight`) to get anything on screen.
        // That patch guessed `fontsize * 1.4`, which is 18 pixels taller than the line the skin
        // spaced its rows for, and the title then sat on top of the artist underneath it (BB27).
        // `lineHeight` is the same number `getAutoHeight()` answers, so the box a script measures and
        // the box we draw are one measurement. A `<SongTicker>` is a Wasabi text too: CopperdeckII's
        // states no `h`, and its song title was a zero-height box.
        if object.attributes["h"] == nil,
           object.tag.is(anyOf: [.text, .songticker]) {
            intrinsic.height = Double(resources.metrics.lineHeight(of: object))
        }
        // A window-chrome button whose artwork Winamp supplied and the skin does not. It has no
        // bitmap to size to, so it resolved to 0x0 and never appeared at all — `Winamp 3.0 Default`'s
        // titlebar is four such buttons and had no menu, minimize, windowshade or close (B95).
        if intrinsic == .zero, let role = chromeButtonRole(of: object, bitmapID: bitmapID) {
            if object.attributes["w"] == nil { intrinsic.width = Double(role.defaultSize.width) }
            if object.attributes["h"] == nil { intrinsic.height = Double(role.defaultSize.height) }
        }
        // A `<Wasabi:TitleBox>` that declares no `h` is as tall as its body needs (B67). Four of
        // impulse's five say `<Wasabi:TitleBox x="320" y="5" w="-325" relatw="1" …/>` and nothing
        // more, so the box resolved to no height, the negative-box guard below dropped it, and its
        // whole content group was laid out inside nothing — only its one sized box appeared.
        if object.attributes["h"] == nil, WasabiTitleBox.isTitleBox(object),
           let height = titleBoxAutoHeight(of: object) {
            intrinsic.height = Double(height)
        }
        // `autoheightsource="<id>"` on a plain `<group>` is the same rule the title box already uses:
        // the group is as tall as the bottom of the child it names. It was only ever read for a
        // `<Wasabi:TitleBox>`, so every other group carrying it resolved to **no height**.
        //
        // ClassicPro engine "two" is the measured case. Its whole transport band is
        // `<group id="two.playback" autoheightsource="two.playback.left">` with no `h`, so it came out
        // 0 tall — and a zero-height group is not a resize target, so `playback-layout.maki`'s
        // `g.onResize` never ran. That handler is what centres the transport strip
        // (`g_buttons.x = w/2 - 112`), picks the normal/mini/micro band from the window width, and
        // places the volume group; with it dead the buttons stayed hard left at their declared `x=8`,
        // the visualization sat on top of them at the same x, and the volume slider never appeared.
        // The children still drew, because a group does not clip to its own box — which is why this
        // read as a layout bug rather than a missing group.
        if object.attributes["h"] == nil,
           object.tag.is(.group),
           object.attributes["autoheightsource"] != nil,
           let bottom = contentBottom(of: object), bottom > 0 {
            intrinsic.height = Double(bottom)
        }
        // A `<group>` draws no artwork of its own, so it had no intrinsic size at all — but Wasabi
        // sizes a group that declares no `w`/`h` to its **`background`** bitmap, and that box is the
        // whole point of the attribute for a group that says `drawbackground="0"`: the bitmap is
        // never painted, it only states how big the group is.
        //
        // BLAKK's boombox is the measured case, and it is a drawer. `blakk.bb.group.SpecVol` is
        // `background="player.bb-SpecVol-map"` (192x14) at (122,84) holding two child groups that
        // slide through it: the spectrum sits at y=0 and the volume bar at y=14, and hovering the
        // player moves both up by 14 so the volume takes the spectrum's place while the spectrum
        // leaves through the top. The aperture *is* the effect. With the group resolving 0x0 it
        // clipped nothing, so both halves drew at once — the volume bar parked permanently over the
        // seek bar as a second, wrong progress bar — and on mouseover the spectrum climbed out over
        // the song ticker and the timer instead of disappearing.
        //
        // Per axis, and only where nothing more specific has already answered: `autowidthsource` and
        // `autoheightsource` above name a *child* to size to, and that beats the backing artwork —
        // mmd3's component title bar is `background="component.titlebg" autowidthsource="titlebar"`,
        // where the backing is a narrow tile meant to stretch, so taking its width clipped every
        // hosted component's title to "CO".
        if object.tag.is(.group),
           let background = backgroundBitmap(of: object) {
            if object.attributes["w"] == nil, intrinsic.width == 0 {
                intrinsic.width = Double(background.width)
            }
            if object.attributes["h"] == nil, intrinsic.height == 0 {
                intrinsic.height = Double(background.height)
            }
        }
        // A `<CustomObject>` that states no size is the size of the group it hosts, the way Wasabi
        // sizes any object from its content's suggested size. Anunaki's LCD is
        // `<customobject groupid="main.lcd.layout2" x="51" y="32"/>` around a `fitparent="1"`
        // group declared 482x281: at 0x0 the group fitted to nothing and the display stayed empty.
        if object.tag.is(.customObject),
           let content = object.children.first(where: { $0.tag.is(.group) }) {
            if object.attributes["w"] == nil, intrinsic.width == 0, content.attributes["relatw"] != "1" {
                intrinsic.width = max(0, Double(content.attributes["w"] ?? "") ?? 0)
            }
            if object.attributes["h"] == nil, intrinsic.height == 0, content.attributes["relath"] != "1" {
                intrinsic.height = max(0, Double(content.attributes["h"] ?? "") ?? 0)
            }
        }
        // A labelled `<Wasabi:Button>` that states no height is Winamp's stock button, which sizes
        // itself to its label. machina's help window writes `<wasabi:button text="switch" w="100">`
        // with no `h`, so it resolved 0 tall and the one way to reach the winshade help never drew.
        // ponytail: a fixed 20 (machina's own About switch buttons state h="20"), not a measured label.
        if object.attributes["h"] == nil, intrinsic.height == 0, Self.isTextButton(object) {
            intrinsic.height = 20
        }
        // A `<Menu>`'s hover or pressed art that states no size of its own is the entry's size (B150).
        // winampmodern566 and The_Nokia_5220 write `<menu:button_hover id="File.hover.btn" x="0"
        // y="0"/>` into a groupdef with only `h="16"`, and the art inside is a three-slice cut to
        // stretch (`w="-7" relatw="1"`) — so at 0 wide, hovering or pressing an entry drew nothing.
        // Only an unstated axis is filled: every other `<Menu>` in the corpus (Big Bento, nsmp10,
        // impulse, cPro Venus, NWA2000) gives its state objects explicit geometry, some deliberately
        // different from the entry's box, and that stays theirs.
        if !isRoot, object.attributes["w"] == nil || object.attributes["h"] == nil,
           intrinsic.width == 0 || intrinsic.height == 0,
           let menu = WasabiMenuBar.owningMenu(of: object) {
            let entry = geometry(of: menu).resolve(
                in: WasabiRect(x: Double(parentFrame.minX), y: Double(parentFrame.minY),
                               width: Double(parentFrame.width), height: Double(parentFrame.height)),
                intrinsicSize: .zero
            )
            if object.attributes["w"] == nil, intrinsic.width == 0 { intrinsic.width = max(0, entry.width) }
            if object.attributes["h"] == nil, intrinsic.height == 0 { intrinsic.height = max(0, entry.height) }
        }
        // A custom XUI instance that states no width, around a child sized from it, spans its parent
        // from its `x`. Nebular's `<Nebular:Checkbox x="0" y="0" usetext="…"/>` carries its label as
        // `w="-10" relatw="1"`: at 0 wide the label was -10 and every Configure checkbox drew bare,
        // while the same author sized the dropdown beside them. ponytail: the parent's width, not a
        // measured label; a skin whose unsized XUI should stop short would need its content's extent.
        if !isRoot, WasabiEmbeddedXUI.embeddedTag(of: object) != nil,
           object.attributes["w"] == nil, intrinsic.width == 0,
           object.children.contains(where: { $0.attributes["relatw"] == "1" }) {
            intrinsic.width = max(0, Double(parentFrame.width) - (Double(object.attributes["x"] ?? "") ?? 0))
        }
        // A button on Winamp's stock check-box art, which no skin that names it without defining it
        // can ship: the 7x7 every defining skin in the corpus cuts (`drawStockCheckBox` draws it).
        if isUnshippedStockCheckBox(object) {
            if object.attributes["w"] == nil { intrinsic.width = WasabiFormWidgets.stockCheckBoxSide }
            if object.attributes["h"] == nil { intrinsic.height = WasabiFormWidgets.stockCheckBoxSide }
        }
        // An object that states `default_w`/`default_h` but no `w`/`h` is that size, as a layout is.
        // LCDx's "plus" player is `<Wasabi:StandardFrame:noStatus h="0" relath="1" default_w="543">`
        // holding the whole player: at 0 wide its body drew nothing but the layout's own buttons.
        // The only such object in the four tiers (zip scan, 2026-10-25).
        if !isRoot {
            if object.attributes["w"] == nil, intrinsic.width == 0,
               let width = Double(object.attributes["default_w"] ?? ""), width > 0 { intrinsic.width = width }
            if object.attributes["h"] == nil, intrinsic.height == 0,
               let height = Double(object.attributes["default_h"] ?? ""), height > 0 { intrinsic.height = height }
        }
        return intrinsic
    }

    /// Width an object takes from text rather than from a `w=`, in skin pixels — `nil` when it takes
    /// none. Two cases: a group with `autowidthsource="<id>"` sizes to that descendant's text, and a
    /// text object that declares no width at all sizes to its own (ClassicPro's menu labels do the
    /// latter inside groups that do the former).
    private func autoWidth(of object: WasabiObject) -> CGFloat? {
        if let sourceID = object.attributes["autowidthsource"],
           let source = descendant(of: object, xmlID: sourceID) {
            // The inset corrects a real measurement. A source that measures nothing — S7Reflex's
            // config tabs are `<text default="">` filled in by a script that has not run — wants a
            // collapsed group, not a group the width of its own padding.
            //
            // A source that is not text is sized by its artwork (B79): winampmodern566 and
            // The_Nokia_5220 point every `menugroup.*` at a `<layer id="File.txt" image=…>`, and
            // answering nil left each group 0 wide, so the `<Menu>` filling it had no hit target.
            // Same order as the script's `getAutoWidth()` — a declared width, then the bitmap.
            guard let width = autoWidth(of: source) ?? artworkWidth(of: source) else { return nil }
            guard width > 0 else { return width }
            return width + WasabiGeometrySpec.autoWidthInset(of: source.attributes)
        }
        // A `<Wasabi:CheckBox>` states no width — Winamp sizes it to its own label, the way the
        // groupdefs that replace the tag do (`autowidthsource` on their label). Left at zero the box
        // and its text both fell outside the object and the whole switch was unclickable.
        if WasabiFormWidgets.kind(of: object) == .checkBox {
            let label = object.attributes["text"] ?? ""
            return WasabiFormWidgets.checkBoxGlyph + WasabiFormWidgets.checkBoxLabelGap
                + resources.metrics.width(of: object, text: label)
        }
        guard object.tag.is(anyOf: [.text, .songticker]) else { return nil }
        return resources.metrics.width(of: object,
                                       text: WasabiTextMetrics.content(of: object, host: host))
    }

    /// The width an `autowidthsource` that is not text answers: its declared width when positive,
    /// otherwise the bitmap it draws at rest. `nil` when it has neither.
    private func artworkWidth(of object: WasabiObject) -> CGFloat? {
        if let declared = Double(object.attributes["w"] ?? ""), declared > 0 { return CGFloat(declared) }
        let bitmapID = resolvedBitmapID(for: object, pressed: false, hovered: false)
        return resources.bitmap(identifier: bitmapID).map { CGFloat($0.width) }
    }

    /// How tall a `<Wasabi:TitleBox>` that declares no height has to be, or `nil` when its body says
    /// nothing that can be measured (B67).
    ///
    /// **Measured, not guessed.** The height is the body's own content height plus the inset the body
    /// already sits in (`WasabiTitleBox.contentInset` — 18 above, 6 below), which is the only number
    /// that makes the box fit exactly what it was drawn around. Checked against impulse, the one skin
    /// that needs it: `Skin Options` measures 74 + 24 = 98 under a box declared at `y="5"` with the
    /// next box at `y="110"`, and `Glass Opacity` 13 + 24 = 37 at `y="273"` with the next at
    /// `y="319"` — a 7–9px gap between boxes in all three cases, which is the spacing the skin's own
    /// sized box has.
    ///
    /// The body's content height comes from the same two sources Wasabi resolves any auto height
    /// from: an `autoheightsource="<id>"` naming the last child (all four of impulse's content groups
    /// state one), and otherwise the lowest edge any child reaches. Both answer the child's **bottom**
    /// rather than its own height — a group sized to the height of its last row would clip everything
    /// above it.
    private func titleBoxAutoHeight(of object: WasabiObject) -> CGFloat? {
        guard let body = object.children.first(where: { $0.tag.is(.group) }),
              let content = contentBottom(of: body) else { return nil }
        return content - CGFloat(WasabiTitleBox.contentInset.height)
    }

    /// The lowest edge anything inside this group reaches, in the group's own coordinates.
    ///
    /// Relative geometry is skipped rather than resolved: a child anchored to a parent whose height
    /// is what we are trying to compute has no answer, and one that states a relative height is
    /// asking to *fill* the box, not to size it.
    private func contentBottom(of group: WasabiObject) -> CGFloat? {
        if let sourceID = group.attributes["autoheightsource"],
           let source = descendant(of: group, xmlID: sourceID), source !== group {
            return declaredBottom(of: source)
        }
        return group.children.compactMap(declaredBottom(of:)).max()
    }

    private func declaredBottom(of object: WasabiObject) -> CGFloat? {
        let spec = WasabiGeometrySpec(attributes: object.attributes)
        guard !spec.relativeY, !spec.relativeHeight else { return nil }
        if let height = spec.height, height > 0 { return CGFloat(spec.y + height) }
        guard object.tag.is(.text) else {
            return nil
        }
        return CGFloat(spec.y) + resources.metrics.lineHeight(of: object)
    }

    private func descendant(of root: WasabiObject, xmlID: String) -> WasabiObject? {
        for child in root.children {
            if child.xmlID?.caseInsensitiveCompare(xmlID) == .orderedSame { return child }
            if let match = descendant(of: child, xmlID: xmlID) { return match }
        }
        return nil
    }
}
