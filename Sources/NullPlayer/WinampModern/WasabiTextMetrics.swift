import AppKit
import Foundation

/// Font resolution and text measurement for Wasabi text objects.
///
/// This is deliberately shared by the renderer and the script runtime rather than duplicated: a skin
/// lays itself out from `getAutoWidth()` (ClassicPro's menu bar positions File/Play/Options/View/Help
/// that way, and its SUI sizes every tab to its label), so a script that measures text differently
/// from the code that draws it produces boxes that do not fit their own contents. Neither may depend
/// on the other — the render harness runs the scripts before any renderer exists — so the measurement
/// lives here, on the loaded skin, and both sides ask it the same question.
final class WasabiTextMetrics {
    let loadedSkin: WinampModernLoadedSkin
    private var fonts: [String: CGFont] = [:]
    private(set) var isTornDown = false

    init(loadedSkin: WinampModernLoadedSkin) {
        self.loadedSkin = loadedSkin
    }

    func teardown() {
        fonts.removeAll()
        isTornDown = true
    }

    /// A font for a text object, or `nil` when nothing usable could be produced.
    ///
    /// Optional on purpose: these are ObjC constructors imported as non-optional that can still
    /// return null, and a null font reaches CoreText as a nil attribute value, which aborts the
    /// **process** (`attempt to insert nil object`) from inside `NSView.draw`. A skin resource must
    /// never be able to do that, so the null is caught here — assigning to an `NSFont?` is what makes
    /// it visible — and answered by the caller's guaranteed fallback.
    func font(identifier: String?, size: CGFloat, traits: NSFontTraitMask = []) -> NSFont? {
        guard !isTornDown, let identifier,
              let definition = loadedSkin.runtime.resources.resolvedDefinition(identifier: identifier),
              definition.kind == "truetypefont", let path = definition.logicalFile else {
            // `font=` is an id **or** a plain family name. A skin that ships no font resource simply
            // names one it expects the system to have ("Arial", "Tahoma"), which is what Winamp asks
            // GDI for — resolving only declared resources drew every such string in the monospaced
            // fallback (the whole of Love is War Miku's display).
            if let identifier, let installed = Self.installedFont(named: identifier, size: size,
                                                                 traits: traits) {
                return installed
            }
            let fallback: NSFont? = .monospacedSystemFont(ofSize: size, weight: .regular)
            return fallback.flatMap { Self.applying(traits, to: $0) }
        }
        let key = path.lowercased()
        let cgFont: CGFont?
        if let cached = fonts[key] {
            cgFont = cached
        } else if let data = try? loadedSkin.vfs.data(at: path, location: definition.source),
                  let provider = CGDataProvider(data: data as CFData),
                  let decoded = CGFont(provider) {
            fonts[key] = decoded
            cgFont = decoded
        } else {
            cgFont = nil
        }
        if let cgFont {
            let created = CTFontCreateWithGraphicsFont(cgFont, size, nil, nil)
            // A font parsed out of a skin can be missing the name table CoreText expects; it then
            // builds an attribute dictionary with a nil in it and aborts the process. A font with no
            // PostScript name is not usable, so fall back rather than hand it on.
            let named: NSFont? = CTFontCopyPostScriptName(created) == nil ? nil : (created as NSFont)
            if let named { return Self.applying(traits, to: named) }
        }
        let fallback: NSFont? = .monospacedSystemFont(ofSize: size, weight: .regular)
        return fallback.flatMap { Self.applying(traits, to: $0) }
    }

    /// A font installed on the system, by family or PostScript name. Optional for the same reason as
    /// everything else here: the name comes from the skin, and a null must never reach CoreText.
    private static func installedFont(named name: String, size: CGFloat,
                                      traits: NSFontTraitMask) -> NSFont? {
        let manager = NSFontManager.shared
        if let family: NSFont = manager.font(withFamily: name, traits: traits, weight: 5, size: size) {
            return family
        }
        guard let exact: NSFont = NSFont(name: name, size: size) else { return nil }
        return applying(traits, to: exact)
    }

    private static func applying(_ traits: NSFontTraitMask, to font: NSFont) -> NSFont? {
        guard !traits.isEmpty else { return font }
        let converted: NSFont? = NSFontManager.shared.convert(font, toHaveTrait: traits)
        return converted ?? font
    }

    /// A cell width per character, for a text object that asks to be drawn fixed-pitch.
    ///
    /// `forcefixed="1"` gives every glyph the same advance — a clock whose digits do not shuffle
    /// sideways as they tick — and `timecolonwidth` gives the colon a narrower cell of its own, since
    /// a full digit cell around a colon leaves a visible hole. Love is War Miku's `0:00` readout is
    /// exactly this pair, and drawn proportionally it is both narrower and unstable.
    struct FixedPitch {
        let cell: CGFloat
        let colon: CGFloat

        func width(of text: String) -> CGFloat {
            text.reduce(0) { $0 + ($1 == ":" ? colon : cell) }
        }
    }

    /// The widest digit is the cell: Winamp sizes the run so any digit fits any position.
    static func fixedPitch(of object: WasabiObject, font: NSFont) -> FixedPitch? {
        guard isEnabled(object.attributes["forcefixed"]) else { return nil }
        let cell = "0123456789".map {
            (String($0) as NSString).size(withAttributes: [.font: font]).width
        }.max() ?? font.pointSize
        // A skin pixel, not a point size: this is a width in the same units as `w`/`h`.
        let colon = object.attributes["timecolonwidth"].flatMap { Double($0) }
        return FixedPitch(cell: cell, colon: colon.map { CGFloat($0) } ?? cell)
    }

    /// The bold/italic a text object asks for. Winamp spells them as their own attributes rather than
    /// as part of the font name.
    static func traits(of object: WasabiObject) -> NSFontTraitMask {
        var traits: NSFontTraitMask = []
        if isEnabled(object.attributes["bold"]) { traits.insert(.boldFontMask) }
        if isEnabled(object.attributes["italic"]) { traits.insert(.italicFontMask) }
        return traits
    }

    private static func isEnabled(_ value: String?) -> Bool {
        guard let value = value?.lowercased() else { return false }
        return !["0", "off", "false", "no", ""].contains(value)
    }

    /// Point size a text object draws at, clamped to something CoreText will accept. A skin (or one
    /// of its scripts) may name 0, a negative, or an unparseable size.
    ///
    /// `fontsize=` is a **pixel height**, not a point size: Winamp hands it to GDI as a font height,
    /// and the em it ends up drawing is measurably smaller than the number. Measured against Love is
    /// War Miku's own screenshot (its shipped reference for the skin): `fontsize="30"` draws digits
    /// 17px tall — Arial's cap height at a 24px em — and `fontsize="10"` matches an 8px em, both at
    /// the same 0.8 ratio. Taken as a point size, every string is a quarter too big and overflows the
    /// box the skin drew for it.
    static func pointSize(of object: WasabiObject) -> CGFloat {
        let requested = Double(object.attributes["fontsize"] ?? "11") ?? 11
        let clamped = requested.isFinite ? min(max(requested, 1), 256) : 11
        return CGFloat(clamped * pixelHeightToPointSize)
    }

    static let pixelHeightToPointSize = 0.8

    /// The one place a component's own text comes from.
    ///
    /// A skin's playlist status line is `<text id="PE_Info">`, whose contents Winamp fills in from the
    /// playlist component. The renderer draws it and a script measures it with `getAutoWidth()`, so
    /// both have to ask the same question — and neither may reach into the component host directly
    /// (the script runtime has no host adapter, and the measurement runs in the headless harness).
    /// The window controller installs this; unset, a `PE_Info` simply reads empty.
    static var componentTextProvider: (() -> WinampModernPlaylistSnapshot?)?

    /// Whether this object is the skin's playlist status line, by **either** of the two forms skins
    /// use: `id="PE_Info"` or `display="PE_Info"`. Both are live in the measured corpus.
    static func isPlaylistStatusLine(_ object: WasabiObject) -> Bool {
        if let identifier = object.xmlID, identifier.caseInsensitiveCompare("PE_Info") == .orderedSame {
            return true
        }
        return object.attributes["display"]?.caseInsensitiveCompare("PE_Info") == .orderedSame
    }

    /// What a text object currently shows. `display=` binds it to a playback value; a `songticker`
    /// carries no text of its own and always shows the current track.
    static func content(of object: WasabiObject, host: WinampModernHost) -> String {
        // The status line is claimed **either** by `id="PE_Info"` (mmd3) **or** by
        // `display="PE_Info"` (Defix, whose `<text id="info.input" display="PE_Info" w="0" h="0"
        // visible="0"/>` is a hidden feed its script parses into the playlist box's track count and
        // total time). Matching only the id left Defix's script reading an empty string, so
        // `onTextChanged` never fired and both readouts sat on their XML placeholder, "-".
        if isPlaylistStatusLine(object) {
            return componentTextProvider?()?.infoLine ?? ""
        }
        // A script's `setAlternateText` *overrides* the content for as long as it is set (MMD3 shows
        // its SEEK/VOLUME/BASS/TREBLE readouts on the song ticker this way). The XML attribute of the
        // same name is a different thing: a placeholder for "nothing to show". Treating the two as one
        // value pinned MMD3's display to its shipped placeholder, "updating songticker", forever.
        if let override = object.attributes[scriptAlternateTextKey], !override.isEmpty { return override }
        let resolved = bound(object, host: host)
        if resolved.isEmpty, let placeholder = object.attributes["alternatetext"], !placeholder.isEmpty {
            return placeholder
        }
        return resolved
    }

    /// Where `setAlternateText` keeps its value — deliberately not the XML `alternatetext` attribute.
    /// Not a Wasabi attribute name, so a skin cannot declare it.
    static let scriptAlternateTextKey = "nullplayer.script.alternatetext"

    private static func bound(_ object: WasabiObject, host: WinampModernHost) -> String {
        switch object.attributes["display"]?.lowercased() {
        case "time":
            let seconds = max(0, Int(host.currentTime))
            return String(format: "%d:%02d", seconds / 60, seconds % 60)
        // Winamp's "song name" is the playlist's display title — "Artist - Title" — which is exactly
        // what a skin puts in its main display, and what `songticker` shows.
        case "songname": return host.trackDisplayTitle
        // `songinfo` is the **stream info** line, not the artist/album: `songinfo.maki` reads this
        // object's own text back and tokenises it looking for `kbps`, `khz` and the channel words,
        // which is the only way MMD3's KBPS/KHZ fields are ever filled in.
        case "songinfo": return host.songInfoText
        default:
            if object.typeName.caseInsensitiveCompare("songticker") == .orderedSame {
                return host.trackDisplayTitle
            }
            let literal = object.attributes["text"] ?? object.attributes["default"] ?? ""
            return resolvePlaceholder(literal, on: object)
        }
    }

    /// Wasabi's title-bar placeholders. A standard frame's title is
    /// `<text default=":componentname"/>` — the colon marks a value the frame supplies, not a string
    /// to draw. Left unresolved, a window's title bar reads ":componentname" *and* the script's
    /// `getAutoWidth()` sizes the title to that literal, so the box does not fit the real name.
    private static func resolvePlaceholder(_ value: String, on object: WasabiObject) -> String {
        guard value.hasPrefix(":") else { return value }
        let key = String(value.dropFirst()).lowercased()
        guard key == "componentname" || key == "name" else { return value }
        // Nearest wins: the XUI frame instance that declares `componentname=`, else the container's
        // own `name=`.
        var current: WasabiObject? = object
        var depth = 0
        while let node = current, depth < 64 {
            if let name = node.attributes["componentname"], !name.isEmpty { return name }
            if node.typeName.caseInsensitiveCompare("container") == .orderedSame,
               let name = node.attributes["name"], !name.isEmpty {
                return name
            }
            current = node.parent
            depth += 1
        }
        return ""
    }

    /// Width the object's text occupies when drawn, in skin pixels, including its horizontal padding.
    /// Bitmap fonts are a fixed-pitch atlas (`charwidth` + `hspacing` per glyph); everything else is
    /// measured with the very font `WasabiSceneRenderer.drawText` would use.
    func width(of object: WasabiObject, text: String) -> CGFloat {
        let padding = CGFloat((Double(object.attributes["leftpadding"] ?? "0") ?? 0)
                              + (Double(object.attributes["rightpadding"] ?? "0") ?? 0))
        if let fontID = object.attributes["font"],
           let definition = loadedSkin.runtime.resources.resolvedDefinition(identifier: fontID),
           definition.kind == "bitmapfont" {
            let charWidth = max(1, Int(Double(definition.attributes["charwidth"] ?? "1") ?? 1))
            let spacing = Int(Double(definition.attributes["hspacing"] ?? "0") ?? 0)
            return CGFloat(text.count * max(1, charWidth + spacing)) + padding
        }
        let size = Self.pointSize(of: object)
        let font = font(identifier: object.attributes["font"], size: size,
                        traits: Self.traits(of: object)) ?? NSFont.systemFont(ofSize: size)
        if let pitch = Self.fixedPitch(of: object, font: font) {
            return pitch.width(of: text) + padding
        }
        return (text as NSString).size(withAttributes: [.font: font]).width + padding
    }
}
