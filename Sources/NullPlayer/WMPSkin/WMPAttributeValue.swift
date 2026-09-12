import Foundation

struct WMPColor: Hashable, Codable, CustomStringConvertible {
    let red: UInt8
    let green: UInt8
    let blue: UInt8

    var description: String { String(format: "#%02X%02X%02X", red, green, blue) }
}

enum WMPBindingKind: String, Hashable, Codable {
    case property
    case enabled
}

enum WMPAttributeValue: Hashable {
    case literal(String)
    case jScript(String)
    case binding(kind: WMPBindingKind, path: String)
    case handler(event: String, source: String)
    case color(WMPColor)
    case resource(String)
    case unsupported(String)
}

struct WMPAttribute: Hashable {
    let name: String
    let rawValue: String
    let value: WMPAttributeValue
}

enum WMPAttributeParser {
    private static let resourceNames: Set<String> = [
        "image", "hoverimage", "downimage", "disabledimage", "mappingimage",
        "background", "backgroundimage", "foregroundimage", "cursor", "thumbnail",
        "thumbimage", "thumbhoverimage", "thumbdownimage", "thumbdisabledimage",
        "positionimage", "resizebackgroundimage", "clippingimage"
    ]
    private static let colorNames: Set<String> = [
        "mappingcolor", "transparencycolor", "clippingcolor", "backgroundcolor",
        "foregroundcolor", "color", "bordercolor"
    ]
    /// An attribute here becomes a `.handler` the dispatcher can find. A name missing from it is
    /// not a handler that fails — it is markup classified as a literal, invisible to every tally,
    /// which is why `onResize` went unnoticed through Phase 3: 47 uses across 19 skins sitting in
    /// the graph as `.literal` and `.jScript` text nothing would ever run. The corpus authors far
    /// more of these than are listed (`value_onchange` alone is 2,207 uses across 174 skins); each
    /// one also needs a dispatch site, so they are ranked in `WMP_TASKS.md` rather than added here
    /// where they would only look implemented.
    private static let handlerNames: Set<String> = [
        "onclick", "onchange", "onload", "onclose", "ontimer", "onresize",
        "onmouseover", "onmouseout", "onmousedown", "onmouseup",
        "openstatechange", "playstatechange", "status_onchange", "modechange",
        "buffering_onchange", "reception_onchange",
        // The `_onchange` spellings of three events the engine already dispatches. They are not
        // new events: `WMPMainWindowController.handlers(in:event:…)` accepts either spelling for
        // one dispatch, and the corpus writes these far more than the ones above — 175 archives
        // author `value_onchange`, 144 `OpenState_onchange`, 139 `PlayState_onchange`, against 11
        // and 7 for the `…change` forms.
        "openstate_onchange", "playstate_onchange", "value_onchange",
        // **A geometry `_onchange` is how a `.wmz` keeps a dependent pane glued to a moving one,**
        // and it has a dispatch site: `WMPScriptContext` raises it inside the same transaction as
        // the write, so the dependent moves in the frame that moved its dependency rather than the
        // frame after. It is authored 16 times across 6 skins and both compact-mode skins are among
        // them — `9SeriesDefault` and `corona` each hang
        // `height_onchange="svTransports.top=svVideo.top+svVideo.height"` off the video panel their
        // mini player collapses. Without it the transport bar chased the panel one frame behind all
        // the way down and the window visibly tore into two pieces (W87).
        "height_onchange", "width_onchange", "left_onchange", "top_onchange",
        // **The completion half of the animation trio, and the commit half of a drag (W55).**
        // `moveTo`/`alphaBlendTo` land their endpoint immediately (W38), so what a skin was missing
        // was the callback that starts the next step: `WMPScriptContext.raiseCompletionHandlers`
        // raises these in the same transaction as the call that completed. Measured over the 179
        // archives: `onEndMove` 247 uses / 113 skins, `onEndAlphaBlend` 50 / 21, `onDragEnd`
        // 141 / 88. **`onEndResize` is deliberately absent: zero uses corpus-wide**, so it would be
        // a name with a dispatch site and no skin to prove it.
        //
        // `onDragEnd` is the other kind — a user gesture, raised from `WMPMainView.mouseUp` — and
        // it is authored only on `SLIDER` (125) and `CUSTOMSLIDER` (16), where it is the seek
        // commit: 111 of its 141 sources are `player.controls.currentPosition = value`.
        "onendmove", "onendalphablend", "ondragend", "onvideostart", "onvideoend"
    ]

    /// **`<attribute>_onchange` is a general SDK mechanism, not a list (W129).** *Ambient Event
    /// Handlers*: "when a skin attribute changes value, an event occurs… the name of the event
    /// handler is the name of the attribute followed by `_onchange`". The set above carries the
    /// spellings that were enumerated one at a time; everything else the corpus authors in that
    /// form — `currentPosition_onchange` (77 skins), `currentEffectType_onchange` (57),
    /// `currentPlaylist_onchange` (48), `currentPreset_onchange` (30), `textWidth_onchange` (17),
    /// `selectedItem_onchange` (12), 387 handlers across 104 of the 177 measured archives — was
    /// classified `.literal`/`.jScript` and was therefore **not a handler at all**: invisible to
    /// the dispatcher, invisible to the tally, and silent, because nothing ever threw.
    ///
    /// Classification alone changes no screen, which is the trap this engine has fallen into
    /// before (`onResize`). The dispatch sites are the cost: element-side in
    /// `WMPScriptContext.raiseAttributeChangeHandlers`, host-side in
    /// `WMPMainWindowController.refreshHostState`.
    private static func isAmbientChangeHandler(_ lowerName: String) -> Bool {
        lowerName.count > "_onchange".count && lowerName.hasSuffix("_onchange")
    }

    static func parse(name: String, value raw: String) -> WMPAttributeValue {
        let lowerName = name.lowercased()
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if handlerNames.contains(lowerName) || isAmbientChangeHandler(lowerName) {
            return .handler(event: name, source: stripPrefix("jscript:", from: trimmed) ?? trimmed)
        }
        if let payload = stripPrefix("jscript:", from: trimmed) { return .jScript(payload) }
        if let payload = stripPrefix("wmpprop:", from: trimmed) {
            return .binding(kind: .property, path: payload.trimmingCharacters(in: .whitespaces))
        }
        if let payload = stripPrefix("wmpenabled:", from: trimmed) {
            return .binding(kind: .enabled, path: payload.trimmingCharacters(in: .whitespaces))
        }
        if colorNames.contains(lowerName), let color = color(from: trimmed) { return .color(color) }
        // **`cursor` names a shape far more often than a file.** 2,246 of the corpus's 2,319
        // non-empty values are `hand`, `sizenwse`, `system` and their peers; only ~70 name a
        // `.cur`/`.ani`. Classifying them all as resources made every named cursor a *missing
        // bitmap* — `BITMAPS … missing=hand sizenwse` in the probe — and hid the name from the
        // builder, which reads literals. A cursor is a resource only when it looks like a file.
        if lowerName == "cursor", !trimmed.contains(".") { return .literal(raw) }
        if resourceNames.contains(lowerName) {
            return isUnsupportedResource(trimmed) ? .unsupported(trimmed) : .resource(trimmed)
        }
        if isUnsupportedResource(trimmed) { return .unsupported(trimmed) }
        return .literal(raw)
    }

    /// Whether an attribute names artwork the loader should resolve and report as missing.
    ///
    /// The value matters, not only the name: `cursor="hand"` names a shape and `cursor="over.ani"`
    /// names a file, and treating both as artwork reported every named cursor in the corpus as a
    /// **missing bitmap** — `BITMAPS … missing=hand sizenwse` on 145 skins, a Class C detector
    /// crying wolf about 2,246 things that were never files.
    static func isResourceAttribute(_ name: String, value: String? = nil) -> Bool {
        guard resourceNames.contains(name.lowercased()) else { return false }
        guard name.lowercased() == "cursor", let value else { return true }
        return value.trimmingCharacters(in: .whitespacesAndNewlines).contains(".")
    }

    private static func stripPrefix(_ prefix: String, from value: String) -> String? {
        guard value.lowercased().hasPrefix(prefix) else { return nil }
        return String(value.dropFirst(prefix.count))
    }

    private static func isUnsupportedResource(_ value: String) -> Bool {
        let lower = value.lowercased()
        return lower.hasPrefix("res://") || lower.hasPrefix("file:")
            || lower.hasPrefix("http:") || lower.hasPrefix("https:")
            || lower.hasPrefix("activex:")
    }

    /// The engine's strict `#RRGGBB` parse, shared with `WMPSurfacePalette` — which reads colour
    /// attributes this parser does not classify (`itemPlayingColor` and its peers) out of their raw
    /// values, and must reject exactly what the engine rejects.
    static func color(from value: String) -> WMPColor? {
        let value = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if let named = namedColors[value.lowercased()] { return named }
        guard value.count == 7, value.first == "#",
              let number = UInt32(value.dropFirst(), radix: 16) else { return nil }
        return WMPColor(red: UInt8((number >> 16) & 0xFF),
                        green: UInt8((number >> 8) & 0xFF),
                        blue: UInt8(number & 0xFF))
    }

    private static let namedColors: [String: WMPColor] = [
        "aliceblue": WMPColor(red: 0xF0, green: 0xF8, blue: 0xFF),
        "antiquewhite": WMPColor(red: 0xFA, green: 0xEB, blue: 0xD7),
        "aqua": WMPColor(red: 0x00, green: 0xFF, blue: 0xFF),
        "aquamarine": WMPColor(red: 0x7F, green: 0xFF, blue: 0xD4),
        "azure": WMPColor(red: 0xF0, green: 0xFF, blue: 0xFF),
        "beige": WMPColor(red: 0xF5, green: 0xF5, blue: 0xDC),
        "bisque": WMPColor(red: 0xFF, green: 0xE4, blue: 0xC4),
        "black": WMPColor(red: 0x00, green: 0x00, blue: 0x00),
        "blanchedalmond": WMPColor(red: 0xFF, green: 0xEB, blue: 0xCD),
        "blue": WMPColor(red: 0x00, green: 0x00, blue: 0xFF),
        "blueviolet": WMPColor(red: 0x8A, green: 0x2B, blue: 0xE2),
        "brown": WMPColor(red: 0xA5, green: 0x2A, blue: 0x2A),
        "burlywood": WMPColor(red: 0xDE, green: 0xB8, blue: 0x87),
        "cadetblue": WMPColor(red: 0x5F, green: 0x9E, blue: 0xA0),
        "chartreuse": WMPColor(red: 0x7F, green: 0xFF, blue: 0x00),
        "chocolate": WMPColor(red: 0xD2, green: 0x69, blue: 0x1E),
        "coral": WMPColor(red: 0xFF, green: 0x7F, blue: 0x50),
        "cornflowerblue": WMPColor(red: 0x64, green: 0x95, blue: 0xED),
        "cornsilk": WMPColor(red: 0xFF, green: 0xF8, blue: 0xDC),
        "crimson": WMPColor(red: 0xDC, green: 0x14, blue: 0x3C),
        "cyan": WMPColor(red: 0x00, green: 0xFF, blue: 0xFF),
        "darkblue": WMPColor(red: 0x00, green: 0x00, blue: 0x8B),
        "darkcyan": WMPColor(red: 0x00, green: 0x8B, blue: 0x8B),
        "darkgoldenrod": WMPColor(red: 0xB8, green: 0x86, blue: 0x0B),
        "darkgray": WMPColor(red: 0xA9, green: 0xA9, blue: 0xA9),
        "darkgreen": WMPColor(red: 0x00, green: 0x64, blue: 0x00),
        "darkkhaki": WMPColor(red: 0xBD, green: 0xB7, blue: 0x6B),
        "darkmagenta": WMPColor(red: 0x8B, green: 0x00, blue: 0x8B),
        "darkolivegreen": WMPColor(red: 0x55, green: 0x6B, blue: 0x2F),
        "darkorange": WMPColor(red: 0xFF, green: 0x8C, blue: 0x00),
        "darkorchid": WMPColor(red: 0x99, green: 0x32, blue: 0xCC),
        "darkred": WMPColor(red: 0x8B, green: 0x00, blue: 0x00),
        "darksalmon": WMPColor(red: 0xE9, green: 0x96, blue: 0x7A),
        "darkseagreen": WMPColor(red: 0x8F, green: 0xBC, blue: 0x8B),
        "darkslateblue": WMPColor(red: 0x48, green: 0x3D, blue: 0x8B),
        "darkslategray": WMPColor(red: 0x2F, green: 0x4F, blue: 0x4F),
        "darkturquoise": WMPColor(red: 0x00, green: 0xCE, blue: 0xD1),
        "darkviolet": WMPColor(red: 0x94, green: 0x00, blue: 0xD3),
        "deeppink": WMPColor(red: 0xFF, green: 0x14, blue: 0x93),
        "deepskyblue": WMPColor(red: 0x00, green: 0xBF, blue: 0xFF),
        "dimgray": WMPColor(red: 0x69, green: 0x69, blue: 0x69),
        "dodgerblue": WMPColor(red: 0x1E, green: 0x90, blue: 0xFF),
        "firebrick": WMPColor(red: 0xB2, green: 0x22, blue: 0x22),
        "floralwhite": WMPColor(red: 0xFF, green: 0xFA, blue: 0xF0),
        "forestgreen": WMPColor(red: 0x22, green: 0x8B, blue: 0x22),
        "fuchsia": WMPColor(red: 0xFF, green: 0x00, blue: 0xFF),
        "gainsboro": WMPColor(red: 0xDC, green: 0xDC, blue: 0xDC),
        "ghostwhite": WMPColor(red: 0xF8, green: 0xF8, blue: 0xFF),
        "gold": WMPColor(red: 0xFF, green: 0xD7, blue: 0x00),
        "goldenrod": WMPColor(red: 0xDA, green: 0xA5, blue: 0x20),
        "gray": WMPColor(red: 0x80, green: 0x80, blue: 0x80),
        "green": WMPColor(red: 0x00, green: 0x80, blue: 0x00),
        "greenyellow": WMPColor(red: 0xAD, green: 0xFF, blue: 0x2F),
        "honeydew": WMPColor(red: 0xF0, green: 0xFF, blue: 0xF0),
        "hotpink": WMPColor(red: 0xFF, green: 0x69, blue: 0xB4),
        "indianred": WMPColor(red: 0xCD, green: 0x5C, blue: 0x5C),
        "indigo": WMPColor(red: 0x4B, green: 0x00, blue: 0x82),
        "ivory": WMPColor(red: 0xFF, green: 0xFF, blue: 0xF0),
        "khaki": WMPColor(red: 0xF0, green: 0xE6, blue: 0x8C),
        "lavender": WMPColor(red: 0xE6, green: 0xE6, blue: 0xFA),
        "lavenderblush": WMPColor(red: 0xFF, green: 0xF0, blue: 0xF5),
        "lawngreen": WMPColor(red: 0x7C, green: 0xFC, blue: 0x00),
        "lemonchiffon": WMPColor(red: 0xFF, green: 0xFA, blue: 0xCD),
        "lightblue": WMPColor(red: 0xAD, green: 0xD8, blue: 0xE6),
        "lightcoral": WMPColor(red: 0xF0, green: 0x80, blue: 0x80),
        "lightcyan": WMPColor(red: 0xE0, green: 0xFF, blue: 0xFF),
        "lightgoldenrodyellow": WMPColor(red: 0xFA, green: 0xFA, blue: 0xD2),
        "lightgreen": WMPColor(red: 0x90, green: 0xEE, blue: 0x90),
        "lightgrey": WMPColor(red: 0xD3, green: 0xD3, blue: 0xD3),
        "lightpink": WMPColor(red: 0xFF, green: 0xB6, blue: 0xC1),
        "lightsalmon": WMPColor(red: 0xFF, green: 0xA0, blue: 0x7A),
        "lightseagreen": WMPColor(red: 0x20, green: 0xB2, blue: 0xAA),
        "lightskyblue": WMPColor(red: 0x87, green: 0xCE, blue: 0xFA),
        "lightslategray": WMPColor(red: 0x77, green: 0x88, blue: 0x99),
        "lightsteelblue": WMPColor(red: 0xB0, green: 0xC4, blue: 0xDE),
        "lightyellow": WMPColor(red: 0xFF, green: 0xFF, blue: 0xE0),
        "lime": WMPColor(red: 0x00, green: 0xFF, blue: 0x00),
        "limegreen": WMPColor(red: 0x32, green: 0xCD, blue: 0x32),
        "linen": WMPColor(red: 0xFA, green: 0xF0, blue: 0xE6),
        "magenta": WMPColor(red: 0xFF, green: 0x00, blue: 0xFF),
        "maroon": WMPColor(red: 0x80, green: 0x00, blue: 0x00),
        "mediumaquamarine": WMPColor(red: 0x66, green: 0xCD, blue: 0xAA),
        "mediumblue": WMPColor(red: 0x00, green: 0x00, blue: 0xCD),
        "mediumorchid": WMPColor(red: 0xBA, green: 0x55, blue: 0xD3),
        "mediumpurple": WMPColor(red: 0x93, green: 0x70, blue: 0xDB),
        "mediumseagreen": WMPColor(red: 0x3C, green: 0xB3, blue: 0x71),
        "mediumslateblue": WMPColor(red: 0x7B, green: 0x68, blue: 0xEE),
        "mediumspringgreen": WMPColor(red: 0x00, green: 0xFA, blue: 0x9A),
        "mediumturquoise": WMPColor(red: 0x48, green: 0xD1, blue: 0xCC),
        "mediumvioletred": WMPColor(red: 0xC7, green: 0x15, blue: 0x85),
        "midnightblue": WMPColor(red: 0x19, green: 0x19, blue: 0x70),
        "mintcream": WMPColor(red: 0xF5, green: 0xFF, blue: 0xFA),
        "mistyrose": WMPColor(red: 0xFF, green: 0xE4, blue: 0xE1),
        "moccasin": WMPColor(red: 0xFF, green: 0xE4, blue: 0xB5),
        "navajowhite": WMPColor(red: 0xFF, green: 0xDE, blue: 0xAD),
        "navy": WMPColor(red: 0x00, green: 0x00, blue: 0x80),
        "oldlace": WMPColor(red: 0xFD, green: 0xF5, blue: 0xE6),
        "olive": WMPColor(red: 0x80, green: 0x80, blue: 0x00),
        "olivedrab": WMPColor(red: 0x6B, green: 0x8E, blue: 0x23),
        "orange": WMPColor(red: 0xFF, green: 0xA5, blue: 0x00),
        "orangered": WMPColor(red: 0xFF, green: 0x45, blue: 0x00),
        "orchid": WMPColor(red: 0xDA, green: 0x70, blue: 0xD6),
        "palegoldenrod": WMPColor(red: 0xEE, green: 0xE8, blue: 0xAA),
        "palegreen": WMPColor(red: 0x98, green: 0xFB, blue: 0x98),
        "paleturquoise": WMPColor(red: 0xAF, green: 0xEE, blue: 0xEE),
        "palevioletred": WMPColor(red: 0xDB, green: 0x70, blue: 0x93),
        "papayawhip": WMPColor(red: 0xFF, green: 0xEF, blue: 0xD5),
        "peachpuff": WMPColor(red: 0xFF, green: 0xDA, blue: 0xB9),
        "peru": WMPColor(red: 0xCD, green: 0x85, blue: 0x3F),
        "pink": WMPColor(red: 0xFF, green: 0xC0, blue: 0xCB),
        "plum": WMPColor(red: 0xDD, green: 0xA0, blue: 0xDD),
        "powderblue": WMPColor(red: 0xB0, green: 0xE0, blue: 0xE6),
        "purple": WMPColor(red: 0x80, green: 0x00, blue: 0x80),
        "red": WMPColor(red: 0xFF, green: 0x00, blue: 0x00),
        "rosybrown": WMPColor(red: 0xBC, green: 0x8F, blue: 0x8F),
        "royalblue": WMPColor(red: 0x41, green: 0x69, blue: 0xE1),
        "saddlebrown": WMPColor(red: 0x8B, green: 0x45, blue: 0x13),
        "salmon": WMPColor(red: 0xFA, green: 0x80, blue: 0x72),
        "sandybrown": WMPColor(red: 0xF4, green: 0xA4, blue: 0x60),
        "seagreen": WMPColor(red: 0x2E, green: 0x8B, blue: 0x57),
        "seashell": WMPColor(red: 0xFF, green: 0xF5, blue: 0xEE),
        "sienna": WMPColor(red: 0xA0, green: 0x52, blue: 0x2D),
        "silver": WMPColor(red: 0xC0, green: 0xC0, blue: 0xC0),
        "skyblue": WMPColor(red: 0x87, green: 0xCE, blue: 0xEB),
        "slateblue": WMPColor(red: 0x6A, green: 0x5A, blue: 0xCD),
        "slategray": WMPColor(red: 0x70, green: 0x80, blue: 0x90),
        "snow": WMPColor(red: 0xFF, green: 0xFA, blue: 0xFA),
        "springgreen": WMPColor(red: 0x00, green: 0xFF, blue: 0x7F),
        "steelblue": WMPColor(red: 0x46, green: 0x82, blue: 0xB4),
        "tan": WMPColor(red: 0xD2, green: 0xB4, blue: 0x8C),
        "teal": WMPColor(red: 0x00, green: 0x80, blue: 0x80),
        "thistle": WMPColor(red: 0xD8, green: 0xBF, blue: 0xD8),
        "tomato": WMPColor(red: 0xFF, green: 0x63, blue: 0x47),
        "turquoise": WMPColor(red: 0x40, green: 0xE0, blue: 0xD0),
        "violet": WMPColor(red: 0xEE, green: 0x82, blue: 0xEE),
        "wheat": WMPColor(red: 0xF5, green: 0xDE, blue: 0xB3),
        "white": WMPColor(red: 0xFF, green: 0xFF, blue: 0xFF),
        "whitesmoke": WMPColor(red: 0xF5, green: 0xF5, blue: 0xF5),
        "yellow": WMPColor(red: 0xFF, green: 0xFF, blue: 0x00),
        "yellowgreen": WMPColor(red: 0x9A, green: 0xCD, blue: 0x32)
    ]
}
