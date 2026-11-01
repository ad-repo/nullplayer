import AppKit

/// The fonts face authors shipped beside their faces, which the 2021 conversion dropped: freeware
/// pixel and display fonts (Mini, Orchis, the 04b family, …), extracted from Panic's original
/// archives by `scripts/audion_face_fonts.py`, which also records each one's licence evidence in
/// its `NOTICE.txt`. Read from `Fonts/AudionFaces/<family>/` in the bundle: `sfnt-0.ttf` is the
/// TrueType font, `<size>-0.nfnt` a QuickDraw bitmap strike. Never registered, so no other window
/// or skin family sees them. A departure from FaceKit, which draws all of them as Helvetica.
enum AudionFaceOriginalFonts {
    private struct Family {
        var outline: CTFontDescriptor?
        var strikes: [Int: URL] = [:]
    }

    private static let families: [String: Family] = {
        guard let root = BundleHelper.url(forResource: "AudionFaces", withExtension: nil, subdirectory: "Fonts"),
              let folders = try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
        else { return [:] }
        var families: [String: Family] = [:]
        for folder in folders {
            var family = Family()
            for file in (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? [] {
                let name = file.deletingPathExtension().lastPathComponent
                if file.pathExtension == "ttf" {
                    family.outline = (CTFontManagerCreateFontDescriptorsFromURL(file as CFURL) as? [CTFontDescriptor])?.first
                } else if file.pathExtension == "nfnt", let size = Int(name.split(separator: "-")[0]) {
                    family.strikes[size] = file
                }
            }
            families[key(folder.lastPathComponent)] = family
        }
        return families
    }()

    private static func key(_ name: String) -> String { name.trimmingCharacters(in: .whitespaces).lowercased() }

    /// The family's TrueType font at `size`, when it shipped one.
    static func font(named name: String, size: CGFloat) -> NSFont? {
        families[key(name)]?.outline.map { CTFontCreateWithFontDescriptor($0, size, nil) as NSFont }
    }

    /// The family's bitmap strike at `size`. A family with no TrueType font takes its nearest
    /// strike instead, at that strike's own size.
    static func bitmap(named name: String, size: Int) -> AudionFaceBitmapFont? {
        guard let family = families[key(name)] else { return nil }
        // ponytail: QuickDraw scaled the nearest strike to the size asked for; 15 lines in the corpus
        // ask for a size their bitmap-only family lacks (Mini 6/8/9, Orchis 5 at 8/10, 04bit-16 at 12).
        let strike = family.strikes[size] ?? (family.outline == nil
            ? family.strikes.keys.min { abs($0 - size) < abs($1 - size) }.flatMap { family.strikes[$0] } : nil)
        return strike.flatMap(AudionFaceBitmapFont.nfnt(at:))
    }
}
