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
    func font(identifier: String?, size: CGFloat) -> NSFont? {
        guard !isTornDown, let identifier,
              let definition = loadedSkin.runtime.resources.resolvedDefinition(identifier: identifier),
              definition.kind == "truetypefont", let path = definition.logicalFile else {
            let fallback: NSFont? = .monospacedSystemFont(ofSize: size, weight: .regular)
            return fallback
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
            if let named { return named }
        }
        let fallback: NSFont? = .monospacedSystemFont(ofSize: size, weight: .regular)
        return fallback
    }

    /// Point size a text object draws at, clamped to something CoreText will accept. A skin (or one
    /// of its scripts) may name 0, a negative, or an unparseable size.
    static func pointSize(of object: WasabiObject) -> CGFloat {
        let requested = Double(object.attributes["fontsize"] ?? "11") ?? 11
        return CGFloat(requested.isFinite ? min(max(requested, 1), 256) : 11)
    }

    /// The one place a component's own text comes from.
    ///
    /// A skin's playlist status line is `<text id="PE_Info">`, whose contents Winamp fills in from the
    /// playlist component. The renderer draws it and a script measures it with `getAutoWidth()`, so
    /// both have to ask the same question — and neither may reach into the component host directly
    /// (the script runtime has no host adapter, and the measurement runs in the headless harness).
    /// The window controller installs this; unset, a `PE_Info` simply reads empty.
    static var componentTextProvider: (() -> WinampModernPlaylistSnapshot?)?

    /// What a text object currently shows. `display=` binds it to a playback value; a `songticker`
    /// carries no text of its own and always shows the current track.
    static func content(of object: WasabiObject, host: WinampModernHost) -> String {
        if let identifier = object.xmlID, identifier.caseInsensitiveCompare("PE_Info") == .orderedSame {
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
        let font = font(identifier: object.attributes["font"], size: size) ?? NSFont.systemFont(ofSize: size)
        return (text as NSString).size(withAttributes: [.font: font]).width + padding
    }
}
