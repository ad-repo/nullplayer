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
        "onendmove", "onendalphablend", "ondragend"
    ]

    static func parse(name: String, value raw: String) -> WMPAttributeValue {
        let lowerName = name.lowercased()
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if handlerNames.contains(lowerName) {
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
        guard value.count == 7, value.first == "#",
              let number = UInt32(value.dropFirst(), radix: 16) else { return nil }
        return WMPColor(red: UInt8((number >> 16) & 0xFF),
                        green: UInt8((number >> 8) & 0xFF),
                        blue: UInt8(number & 0xFF))
    }
}
