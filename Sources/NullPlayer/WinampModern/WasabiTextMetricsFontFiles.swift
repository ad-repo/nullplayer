import AppKit

/// Fonts loaded from a skin's own files: a declared `<truetypefont>` file, or a file a `font=` names.
extension WasabiTextMetrics {
    /// A `font=` that names a font *file* the skin ships without declaring it as a `<truetypefont>`
    /// (EI_V2's `font="BNKGOTHM.TTF"`, beside its `skin.xml`; DewyTears' `UNVR67X.ttf`, in `font/`).
    /// The skin's own screenshot draws in that face, so a file of that name anywhere in the skin's
    /// archive is loaded. Reached only after `systemFont` misses, so an installed face still wins.
    func shippedFont(namedBySkin name: String, size: CGFloat, traits: NSFontTraitMask) -> NSFont? {
        guard Self.windowsFontFileStem(of: name) != name, let root = loadedSkin.vfs.skinRoot else { return nil }
        let leaf = "/" + name.lowercased()
        guard let path = loadedSkin.vfs.allLogicalPaths().first(where: {
            $0.hasPrefix(root + "/") && $0.lowercased().hasSuffix(leaf)
        }) else { return nil }
        return fileFont(at: path, location: nil, size: size, traits: traits)
    }

    func fileFont(at path: String, location: WalSourceLocation?, size: CGFloat,
                          traits: NSFontTraitMask) -> NSFont? {
        let key = path.lowercased()
        let cgFont: CGFont?
        if let cached = fonts[key] {
            cgFont = cached
        } else if let data = try? loadedSkin.vfs.data(at: path, location: location),
                  let provider = CGDataProvider(data: data as CFData),
                  let decoded = CGFont(provider) {
            fonts[key] = decoded
            cgFont = decoded
        } else {
            cgFont = nil
        }
        if let cgFont {
            let created = CTFontCreateWithGraphicsFont(cgFont, size, nil, nil)
            // A font parsed out of a skin can come back null from a constructor imported as
            // non-optional. Put in an attributes dictionary, that null reaches the ObjC bridge as a
            // real nil and aborts the **process** from inside `NSString.size(withAttributes:)`:
            //
            //   -[__NSPlaceholderDictionary initWithObjects:forKeys:count:]: attempt to insert nil
            //   object from objects[0]
            //
            // which is the 2026-08-16 cPro-Bento report exactly. Assigning to an `NSFont?` is the
            // whole defence: a nil class reference lands as `.none`, so `if let` catches it and the
            // caller's guaranteed fallback answers instead.
            //
            // **Do not reinstate a PostScript-name check here.** Two have been tried and neither
            // could ever fire. `CTFontCopyPostScriptName(created) == nil` is *always false* — the
            // overlay returns a non-optional `CFString`. Testing the name for `isEmpty` (0.30.0) is
            // no better: CoreGraphics **synthesizes** a name (`font00000000308faa8`) for any font
            // whose `name` table is missing, empty, or carries a zero-length nameID 6, and rejects
            // outright anything malformed enough to have no name at all — so no font that reaches
            // this line can have an empty name. Measured, not reasoned:
            // `WinampModernNamelessFontTests`.
            let bridged: NSFont? = created as NSFont
            if let bridged { return Self.applying(traits, to: bridged) }
        }
        return nil
    }
}
