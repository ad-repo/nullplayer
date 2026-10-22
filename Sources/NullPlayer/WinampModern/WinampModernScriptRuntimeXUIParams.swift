import AppKit
import CoreGraphics
import Foundation

/// `<script>` and XUI parameter delivery to embedded groups and wrappers, and the auto-size
/// answers that read them. Split out of
/// `WinampModernScriptRuntime.swift`.
extension WinampModernScriptRuntime {
    /// A param the **object itself** answers, so its script never hears it.
    ///
    /// Wasabi hands a XUI tag's attributes to `GuiObject::setXmlParam` first and only calls
    /// `onSetXuiParam` for what that leaves unclaimed — which is why a XUI wrapper can afford to
    /// forward everything it is given straight to the control it wraps. ClassicPro's does exactly
    /// that: `ModernSongticker.maki` names eight `id_*` params it uses itself and pushes every
    /// other one onto the `<SongTicker fitparent="1"/>` inside its group. Handing that `else` the
    /// group's own geometry as well put Venus's `x="25" y="78" w="-53" h="20"` onto a ticker that
    /// is meant to fill the group those numbers already placed, and the song title landed a second
    /// display's width down and to the right — over the playback buttons (B142).
    ///
    /// Only geometry and `id`: `font`, `align` and `color` reach the wrapper on purpose — a `<group>`
    /// has no use for them and forwarding them to the text inside is the whole point of the tag.
    /// `id` is the object's own name, and handed on it *renames* the control inside: cPro2 minimal's
    /// `<SC:OneDirectionText>` embeds a `<OneDirectionText id="sc.main.text">` whose script forwards
    /// every param onto its `my.text.main`, which became a second `sc.main.text` that the `embed_xui`
    /// link could no longer find — so `sc_text.maki`'s `setText` landed on the wrapper and the
    /// artist and title lines drew nothing. `nullplayer.*` keys are our own markers; no skin's
    /// script was ever handed one.
    static func isConsumedBeforeXUIParams(_ name: String) -> Bool {
        let lowered = name.lowercased()
        return WasabiGeometrySpec.geometryAttributes.contains(lowered)
            || lowered == "id" || lowered.hasPrefix("nullplayer.")
            || name == WasabiSkinInitializer.skinTabSheetAttribute
    }

    /// What a plain `<group>` answers itself, so its scripts never hear it as an XUI param.
    static let groupClaimedParams: Set<String> = [
        "id", "name", "background", "drawbackground", "sysregion", "notify", "alpha", "activealpha",
        "inactivealpha", "visible", "ghost", "tooltip", "move", "fitparent", "wantfocus", "regionop",
        "rectrgn", "cursor", "droptarget", "userdata",
    ]

    func deliverXUIParams(forSubtreeOf object: WasabiObject) {
        deliverXUIParams(for: object)
        for child in object.children { deliverXUIParams(forSubtreeOf: child) }
    }

    func deliverXUIParams(for object: WasabiObject) {
        guard !object.scriptBindings.isEmpty else { return }
        let owned = programs.filter { $0.ownerID == object.stableID }
        guard !owned.isEmpty else { return }
        // `onSetXuiParam` is a *System* event, and each XUI instance gets its own program instance,
        // so the params must go only to the programs that instance owns — dispatching to every
        // program would hand one frame's `content` to all of them.
        //
        // A plain `<group>` hears what it does not claim itself too. Prakrit's equalizer is
        // `<group id="wasabi.standardframe.statusbar" content="eq.generic">` around the skin's own
        // frame script, which builds the body from `content`; with only XUI tags delivered, the
        // window was an empty frame.
        let isXUI = loadedSkin.runtime.types.isXUITag(object.typeName)
        if isXUI || object.tag.is(.group) {
            // In the order the tag wrote them, as Wasabi delivers them: Simple's `xui-button.m`
            // reads `symboltype` to decide what the `symbol` after it means, and alphabetised the
            // symbol came first and every button drew its symbol's group id as a label.
            for name in object.orderedAttributeNames
            where !Self.isConsumedBeforeXUIParams(name)
                && (isXUI || !Self.groupClaimedParams.contains(name.lowercased())) {
                _ = try? dispatch(target: MakiObjectReference(.system), event: "onsetxuiparam",
                                  arguments: [.string(name), .string(object.attributes[name] ?? "")], in: owned)
            }
        }
        // Wasabi's `notify="key,value"` delivers `key` as an XUI param with the given value.
        // Lobe uses `<group id="wasabi.standardframe.statusbar" notify="content,pledit.normal.
        // content.group">` — a `<group>` instance, not a XUI tag, so the standard param loop
        // above never fires, but the standard frame script still needs `content` to instantiate
        // the playlist body.
        if let notify = object.attributes["notify"] {
            let parts = notify.split(separator: ",", maxSplits: 1)
            if parts.count == 2 {
                let key = String(parts[0])
                let value = String(parts[1])
                _ = try? dispatch(target: MakiObjectReference(.system), event: "onsetxuiparam",
                                  arguments: [.string(key), .string(value)], in: owned)
            }
        }
    }

    /// `<CustomObject groupid="…">` — a holder whose **content is named by an attribute**.
    ///
    /// Unlike a `<group id="x">`, which instantiates `x` once at parse time, a custom object is empty
    /// until a script names a groupdef for it, and it swaps that content whenever the name changes.
    /// ClassicPro's widget panes are the measured case: `<CustomObject id="widget.holder"
    /// fitparent="1"/>` sits in the SUI's widget tab, and choosing a widget is one line —
    /// `widgetHolder.setXmlParam("groupid", ids)` — after which the pane *is* that widget.
    ///
    /// No skin in the corpus declares `groupid` in markup, so this runtime write is the whole path.
    ///
    /// The old content is discarded rather than hidden: a custom object holds one thing at a time,
    /// and leaving the previous widget in the tree keeps its scripts and timers running behind the
    /// one on screen.
    func applyCustomObjectGroup(_ key: String, value: String, to object: WasabiObject) {
        guard key.caseInsensitiveCompare("groupid") == .orderedSame,
              object.tag.is(.customObject)
        else { return }
        // `children` is a value-typed array, so the loop iterates the snapshot it took even though
        // `discardSubtree` empties the property underneath it.
        for child in object.children { loadedSkin.runtime.graph.discardSubtree(child) }
        guard !value.isEmpty, let instantiate = loadedSkin.runtime.instantiateGroup,
              let child = try? instantiate(value, object) else { return }
        // A custom object's content **fills it** — the object is the box, the named group is what
        // goes in it. `instantiateGroup` builds a bare `<group id="…">`, which declares no geometry
        // and so resolves to 0x0 (measured: `centro.widgets.nowplaying` laid out at
        // `frame=(8.0, 132.0, 0.0, 0.0)` inside a 280x176 holder, drawing nothing at all while its
        // script ran perfectly). `System.newGroup`'s path deliberately keeps the bare node — there
        // the script places the group itself with `init(parent)` — so the fill belongs here.
        //
        // Filled means placed at the box's origin too: Wasabi resizes the content to the custom
        // object's own rect, so a groupdef's `x`/`y` does not move it. And when neither side states
        // a size there is no box to fill — Anunaki's stick and shade LCD groups declare none and
        // carry the main LCD's `x="51" y="32"`, so filling a 0x0 holder clipped the whole display
        // away. Left unsized, the group does not clip, and its children land where the skin drew them.
        _ = child.setAttribute("x", value: "0")
        _ = child.setAttribute("y", value: "0")
        let sizeKeys = ["w", "h", "relatw", "relath", "fitparent"]
        if sizeKeys.contains(where: { object.attributes[$0] != nil })
            || child.attributes["w"] != nil || child.attributes["h"] != nil {
            _ = child.setAttribute("fitparent", value: "1")
        }
        // Started now, for the reason `instantiate` starts its own: the group is already parented,
        // and the caller's next move is to configure what it just put on screen.
        try? startScripts(addedBeneath: child)
        // Content that comes up on screen is told so, as Wasabi tells a group it shows. Anunaki's
        // digital clock starts its tick from `onSetVisible(1)` alone; without it the stick and main
        // LCD clocks drew the time once and stood still.
        if effectiveVisibility(of: object) {
            _ = try? dispatch(object: child, event: "onsetvisible", arguments: [.boolean(true)])
        }
        noteGeometryChange()
        notifyGraphDidMutate()
    }

    /// A runtime `setXmlParam(key, value)` is also an `onSetXuiParam(key, value)` to the scripts the
    /// written object owns — that is how Wasabi delivers a param a *script* sets, as opposed to one
    /// the markup declares (`deliverXUIParams`, which runs once at load and only for XUI tags).
    ///
    /// Scoped to the target's own programs, exactly as the load-time delivery is, so an object with
    /// no script of its own is untouched and nothing else in the skin hears it.
    ///
    /// ClassicPro's Widgets Manager is the measured case: `widgetsManager.maki` instantiates a
    /// `widgets.manager.listitem` per widget and then *only* writes params on it —
    /// `g.setXmlParam("widgetname", …)`, `"widgetauthor"`, `"widgetversion"`, `"widgetpos_main"` and
    /// the rest — while `widgetManItem.maki`'s whole body is one `system.onSetXuiParam` switch. With
    /// the write silent, every row drew with the groupdef's placeholder text and dead buttons.
    func deliverRuntimeXUIParam(_ key: String, value: String, to object: WasabiObject) {
        guard !Self.isConsumedBeforeXUIParams(key), !object.scriptBindings.isEmpty else { return }
        let owned = programs.filter { $0.ownerID == object.stableID }
        guard !owned.isEmpty else { return }
        _ = try? dispatch(target: MakiObjectReference(.system), event: "onsetxuiparam",
                          arguments: [.string(key), .string(value)], in: owned)
    }

    /// `getAutoWidth()` — the width an object wants to be. A group delegates to the object named by
    /// its `autowidthsource` attribute, which is how the menubar sizes itself: each `menugroup.*`
    /// points at the layer holding its rendered label bitmap, and `menualign.maki` reads these
    /// widths to lay the menus out left-to-right. Returning a text estimate for those groups (the
    /// previous behaviour) left every menu at width 0, stacked on the same x.
    func autoWidth(of object: WasabiObject) -> Int32 {
        if let sourceID = object.attributes["autowidthsource"],
           let source = descendant(of: object, xmlID: sourceID), source !== object {
            // The source's width is not the group's: it is what the source resolves to *inside*
            // the group, so a source that keeps room beside itself needs the group to be that much
            // wider (B68). Shared with the renderer so a script's measurement and the drawn box stay
            // one number. Only applied to a real measurement — a source that answers 0 answers 0.
            let width = autoWidth(of: source)
            guard width > 0 else { return width }
            let inset = WasabiGeometrySpec.autoWidthInset(of: source.attributes)
            return Int32(clamping: Int(width) + Int(inset.rounded(.up)))
        }
        // Measured with the font the renderer draws with, not estimated: ClassicPro sizes every SUI
        // tab to `label.getAutoWidth() + 14` and lays its menu bar out from these numbers, so an
        // estimate that runs narrow clips every label inside a box the skin thinks fits it.
        //
        // The measurement outranks the declared `w`. For a `<text>` the *box* and the *string* are
        // two different numbers, and "auto" is the string's — a label declared `w="0" relatw="1"`
        // stretches to its parent and would otherwise answer with that stretch.
        if object.tag.is(anyOf: [.text, .songticker]) {
            let text = WasabiTextMetrics.content(of: object, host: host)
            return Int32(clamping: Int(metrics.width(of: object, text: text).rounded(.up)))
        }
        if let explicit = object.attributes["w"], let width = Int32(explicit), width > 0 { return width }
        if let imageID = object.attributes["image"], let width = bitmapWidth(identifier: imageID) {
            return width
        }
        return 0
    }

    /// `getAutoHeight()` — the vertical twin of `autoWidth(of:)`, resolved from the same sources in
    /// the same order (a named source object, the font, a declared `h`, the artwork). Big Bento
    /// Modern's album-art script asks for both together (`getAutoWidth()` then `getAutoHeight()` on
    /// the cover layer) to keep the picture's aspect ratio, so answering one and aborting on the
    /// other took the whole cover panel's `onScriptLoaded` down with it.
    func autoHeight(of object: WasabiObject) -> Int32 {
        if let sourceID = object.attributes["autoheightsource"],
           let source = descendant(of: object, xmlID: sourceID), source !== object {
            return autoHeight(of: source)
        }
        // A single line in the font the renderer would draw with, and it outranks the declared `h`
        // for the same reason the width measurement outranks `w` — see `autoWidth(of:)`. Big Bento
        // Modern's tab strip is the case that shows it: `tabcontrol.maki` sizes every SUI tab to
        // `4 * label.y + label.getAutoHeight()`, and the label is declared `h="60"` inside a 60-tall
        // tab. Answering 60 made each tab 96 tall, which stretched all seven icons vertically and
        // pushed the strip 37px per tab down the column. Measured, the answer is the font's 24 and
        // the arithmetic lands back on the skin's own 60.
        if object.tag.is(anyOf: [.text, .songticker]) {
            return Int32(clamping: Int(metrics.lineHeight(of: object).rounded(.up)))
        }
        if let explicit = object.attributes["h"], let height = Int32(explicit), height > 0 { return height }
        if let imageID = object.attributes["image"], let height = bitmapHeight(identifier: imageID) {
            return height
        }
        return 0
    }

    /// Pixel width of a declared bitmap. Uses the resource's explicit `w` when the declaration crops
    /// a sprite sheet, otherwise reads the image header (no full decode) for whole-file bitmaps.
    func bitmapWidth(identifier: String) -> Int32? { bitmapSize(identifier: identifier)?.width }

    func bitmapHeight(identifier: String) -> Int32? { bitmapSize(identifier: identifier)?.height }

    func bitmapSize(identifier: String) -> (width: Int32, height: Int32)? {
        // Never cached: the cover changes with the track.
        if let cover = host.trackFolderCover(forImage: identifier) {
            return (Int32(clamping: cover.width), Int32(clamping: cover.height))
        }
        let key = identifier.lowercased()
        if let cached = scriptBitmaps.size(for: key) { return cached }
        let size = measureBitmap(identifier: identifier)
        scriptBitmaps.store(size, for: key)
        return size
    }

    private func measureBitmap(identifier: String) -> (width: Int32, height: Int32)? {
        guard let definition = loadedSkin.runtime.resources.resolvedDefinition(identifier: identifier),
              definition.kind == "bitmap" else { return nil }
        var declared: (Int32?, Int32?) = (definition.attributes["w"].flatMap { Int32($0) },
                                          definition.attributes["h"].flatMap { Int32($0) })
        if declared.0 == nil || declared.1 == nil,
           let path = definition.logicalFile,
           let data = try? loadedSkin.vfs.data(at: path, location: definition.source),
           let source = CGImageSourceCreateWithData(data as CFData, nil),
           let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] {
            declared.0 = declared.0 ?? (properties[kCGImagePropertyPixelWidth] as? Int).map { Int32(clamping: $0) }
            declared.1 = declared.1 ?? (properties[kCGImagePropertyPixelHeight] as? Int).map { Int32(clamping: $0) }
        }
        guard let width = declared.0, let height = declared.1, width > 0, height > 0 else { return nil }
        return (width, height)
    }

    /// The `<container>` an object lives in, or nil for one that is not inside a window.
    static func enclosingContainer(of object: WasabiObject) -> WasabiObject? {
        var node: WasabiObject? = object.parent
        while let current = node {
            if current.tag.is(.container) { return current }
            node = current.parent
        }
        return nil
    }

    static let embeddedXUIForwardedEvents: Set<String> = [
        "onleftbuttondown", "onleftbuttonup", "onleftclick", "onleftbuttondblclk",
        "onrightbuttondown", "onrightbuttonup", "onrightclick", "onenterarea", "onleavearea",
        // The slider's *value* events belong to the embedding too, and for the same reason as the
        // pointer's: a `<groupdef embed_xui="slider">` **is** a slider to anyone holding the group, so
        // a script that binds `onSetPosition` to the group is asking about the embedded control.
        // Big Bento Modern's scrollbar is exactly this shape — `SC:VScrollBar` wraps a `<slider>` and
        // the up/down buttons nudge the *inner* one (`cscrollbar.maki`), while the settings page binds
        // its `onSetPosition` to the **outer** `vscroll`. Without the forward the page never learned
        // the bar had moved, so the buttons and the drag both lit up and scrolled nothing (BB19).
        "onsetposition", "onsetfinalposition", "onpostedposition"
    ]

    /// The groups that declared `embed_xui` naming this object — the ancestors that speak for it.
    /// Nearly always none or one; the walk is up the parent chain, so it is bounded by tree depth.
    func embeddingOwners(of object: WasabiObject) -> [WasabiObject] {
        guard let id = object.xmlID?.lowercased() else { return [] }
        var owners: [WasabiObject] = []
        var candidate = object.parent
        while let current = candidate {
            if WasabiEmbeddedXUI.embeddedTag(of: current) == id { owners.append(current) }
            candidate = current.parent
        }
        return owners
    }
}
