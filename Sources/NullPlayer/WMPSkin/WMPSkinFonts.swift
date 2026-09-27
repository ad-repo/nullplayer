import CoreGraphics
import CoreText
import Foundation

/// The fonts a skin ships in its own archive, registered for this process so its `fontFace` finds
/// them.
///
/// `Alpine7618_v09` names `fontFace="Quartz"` on every LCD readout and ships `Quartz.TTF` beside
/// them. Unregistered, `CTFontCreateWithName` silently answered Helvetica — a wider face than the
/// LCD's — so every readout overran the box it was laid out for. A face the system already has is
/// never registered over: a skin must not change what `Arial` means to another window, or to
/// another skin family.
enum WMPSkinFonts {
    private static let lock = NSLock()
    private static var registered = Set<String>()

    static func register(from archive: WMPResourceProviding) {
        for path in archive.resourcePaths {
            let lower = path.lowercased()
            guard lower.hasSuffix(".ttf") || lower.hasSuffix(".otf"),
                  let data = try? archive.data(for: path),
                  let provider = CGDataProvider(data: data as CFData),
                  let font = CGFont(provider),
                  let name = font.postScriptName as String? else { continue }
            lock.lock(); defer { lock.unlock() }
            guard !registered.contains(name), !isInstalled(font) else { continue }
            if CTFontManagerRegisterGraphicsFont(font, nil) { registered.insert(name) }
        }
    }

    private static func isInstalled(_ font: CGFont) -> Bool {
        let family = CTFontCopyFamilyName(CTFontCreateWithGraphicsFont(font, 12, nil, nil)) as String
        let installed = CTFontManagerCopyAvailableFontFamilyNames() as? [String] ?? []
        return installed.contains { $0.caseInsensitiveCompare(family) == .orderedSame }
    }
}
