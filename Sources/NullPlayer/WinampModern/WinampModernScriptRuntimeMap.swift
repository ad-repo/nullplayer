import AppKit
import CoreGraphics
import Foundation

/// What scripts read out of a skin's bitmaps, memoised per runtime: decoded `Map` images and pixel
/// sizes, keyed by lower-cased resource id.
struct WinampModernScriptBitmaps {
    typealias Size = (width: Int32, height: Int32)

    /// Maps are small lookup images (44×44 for MMD3's volume knob) and there are a handful per skin.
    private static let maximumMaps = 16
    private var maps: [String: CGImage] = [:]
    /// `nil` records a resolved-but-unknown size.
    private var sizes: [String: Size?] = [:]

    /// Lookups and stores are separate calls so the decode between them runs with no access to this
    /// value held: a decode that reached back into the cache would otherwise trap as an overlapping
    /// access.
    func map(for key: String) -> CGImage? { maps[key] }
    /// A full cache answers no new map at all, rather than decoding one per call.
    var acceptsMaps: Bool { maps.count < Self.maximumMaps }
    mutating func store(_ image: CGImage, for key: String) { maps[key] = image }

    /// The memoised size, `.some(nil)` for one already known to be unknown, `nil` when never measured.
    func size(for key: String) -> Size?? { sizes[key] }

    mutating func store(_ size: Size?, for key: String) { sizes[key] = size }
}

/// `animatedlayer` frames and the MAKI `Map` class: pixels, crops and images read from a bitmap. Split out of
/// `WinampModernScriptRuntime.swift`.
extension WinampModernScriptRuntime {
    /// How many frames an `animatedlayer`'s sheet holds: its explicit `frames`, else the sheet
    /// divided by the layer's frame box (MMD3's volume knob is a 44×1012 strip of 44×44 frames).
    func animationFrameCount(of object: WasabiObject) -> Int {
        if let raw = object.attributes["frames"], let count = Int(raw), count > 0 { return count }
        // A cover beside the playing file is one frame when there is (or will be) art and none when
        // there is not — `cover.maki`'s "found" test, and the skin's own "no cover" art otherwise.
        if let imageID = object.attributes["image"], host.isTrackFolderImage(imageID) {
            return host.trackFolderCover(forImage: imageID) == nil ? 0 : 1
        }
        guard let imageID = object.attributes["image"], let sheet = bitmapSize(identifier: imageID) else { return 1 }
        let frameWidth = Int(object.attributes["framewidth"] ?? object.attributes["w"] ?? "") ?? Int(sheet.width)
        let frameHeight = Int(object.attributes["frameheight"] ?? object.attributes["h"] ?? "") ?? Int(sheet.height)
        guard frameWidth > 0, frameHeight > 0 else { return 1 }
        return max(1, (Int(sheet.width) / frameWidth) * (Int(sheet.height) / frameHeight))
    }

    func animationFrame(of object: WasabiObject) -> Int {
        WasabiAnimation.state(of: object, frameCount: animationFrameCount(of: object)).frame
    }

    /// Sample a `Map`'s bitmap at a point in its own pixel space. Decoded images are cached, bounded
    /// by `WinampModernScriptBitmaps`; the bitmap itself passed the loader's dimension limits.
    func mapPixel(bitmapID: String, source: WalSourceLocation, x: Int, y: Int)
        -> (red: UInt8, green: UInt8, blue: UInt8, alpha: UInt8, inBounds: Bool) {
        guard let image = mapImage(bitmapID: bitmapID, source: source) else { return (0, 0, 0, 0, false) }
        let crop = mapCrop(bitmapID: bitmapID, image: image)
        guard x >= 0, y >= 0, x < crop.width, y < crop.height else { return (0, 0, 0, 0, false) }
        let bitmap = WasabiBitmap(image: image, width: image.width, height: image.height, cost: 0)
        guard let pixel = bitmap.pixel(at: CGPoint(x: crop.x + x, y: crop.y + y))
        else { return (0, 0, 0, 0, false) }
        return (pixel.red, pixel.green, pixel.blue, pixel.alpha, true)
    }

    /// The region of the decoded file a `Map` actually covers.
    ///
    /// `loadMap` takes a **bitmap id** as well as a path, and a `<bitmap>` is routinely a *slice* of a
    /// shared sheet: `<bitmap id="window.titlebar.menu.1" file="buttons.png" x="0" y="87" w="10"
    /// h="21"/>`. A map of that id is 10x21 starting at (0, 87) — pixel (0, 0) of the map is pixel
    /// (0, 87) of the file — and sampling the file's own origin instead reads whatever art happens to
    /// sit in the sheet's top-left corner.
    ///
    /// Measured, and the whole of the cPro "pink menu bar": ClassicPro's `mainmenu.maki` opens with a
    /// self-check for a skin that never cut its menu artwork —
    ///
    /// ```maki
    /// temp.loadMap("window.titlebar.menu.1");
    /// if (temp.getARGBValue(0,0,3) != 0)                        // not fully transparent
    ///   if (temp.getARGBValue(0,0,2)==255 && temp.getARGBValue(0,0,1)==0
    ///       && temp.getARGBValue(0,0,0)==128) {                 // the template's (255,0,128) filler
    ///     myGroup.hide(); disableMenu = true; bg_title.show();  // no menu bar; centred title instead
    ///   }
    /// ```
    ///
    /// — so the engine hides its own menu bar and shows a plain title whenever the slice is filler.
    /// Reading (0, 0) of `buttons.png` gave it a transport button, the test never fired, and four cPro
    /// skins drew five magenta boxes across the titlebar that Winamp never shows.
    func mapCrop(bitmapID: String, image: CGImage) -> (x: Int, y: Int, width: Int, height: Int) {
        let whole = (x: 0, y: 0, width: image.width, height: image.height)
        guard let definition = loadedSkin.runtime.resources.resolvedDefinition(identifier: bitmapID),
              definition.kind == "bitmap" else { return whole }
        let number: (String) -> Int? = { definition.attributes[$0].flatMap { Int($0) } }
        // A `<bitmap>` with no `x`/`y`/`w`/`h` is the whole file, which is the common case and the one
        // the path form always takes.
        guard number("x") != nil || number("y") != nil
                || number("w") != nil || number("h") != nil else { return whole }
        let x = min(max(0, number("x") ?? 0), image.width)
        let y = min(max(0, number("y") ?? 0), image.height)
        return (x: x, y: y,
                width: min(number("w") ?? (image.width - x), image.width - x),
                height: min(number("h") ?? (image.height - y), image.height - y))
    }

    func mapImage(bitmapID: String, source scriptSource: WalSourceLocation) -> CGImage? {
        // A cover beside the playing file is the host's artwork, never a file read — and never
        // cached, because it changes with the track.
        if host.isTrackFolderImage(bitmapID) { return host.trackFolderCover(forImage: bitmapID) }
        let key = bitmapID.lowercased()
        if let cached = scriptBitmaps.map(for: key) { return cached }
        guard scriptBitmaps.acceptsMaps,
              let data = mapData(bitmapID: bitmapID, source: scriptSource),
              let imageSource = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(imageSource, 0, nil) else { return nil }
        scriptBitmaps.store(image, for: key)
        return image
    }

    /// `loadMap` takes *either* a declared bitmap id or a path. ClassicPro's install check is the
    /// second form — `warning.maki` loads `…\Plugins\classicPro\engine\image\installed.png` and
    /// treats a width other than 1 as "the plugin is missing", which made cPro-Bento conclude the
    /// engine was not installed and try to switch skins. Paths go through the VFS like any other
    /// resource, so they stay inside the mounts.
    func mapData(bitmapID: String, source scriptSource: WalSourceLocation) -> Data? {
        guard let path = mapLogicalPath(bitmapID: bitmapID, source: scriptSource) else { return nil }
        return try? loadedSkin.vfs.data(at: path, location: scriptSource)
    }

    /// Where a map's bitmap actually lives, by either route. The renderer needs this for a region,
    /// because the path form leaves nothing in the resource registry for it to look the map up by.
    func mapLogicalPath(bitmapID: String, source scriptSource: WalSourceLocation) -> String? {
        if let definition = loadedSkin.runtime.resources.resolvedDefinition(identifier: bitmapID),
           definition.kind == "bitmap", let path = definition.logicalFile,
           (try? loadedSkin.vfs.data(at: path, location: definition.source)) != nil {
            return path
        }
        // The path form is relative to the **skin**, not to the script that called it — a `.wal`
        // engine's scripts sit in their own mount and read the *skin's* artwork by bare filename.
        // ClassicPro's `player.maki` sizes the Winamp bolt from `buttons.png` and only gives that
        // button an `image` when the answer is 332 wide; resolved beside the script the file was
        // never found, `getWidth()` answered 0, and the logo stayed invisible until the pointer was
        // over it, because `hoverImage` is the only artwork its markup declares.
        for base in [scriptSource.path, loadedSkin.vfs.skinRoot.map { $0 + "/skin.xml" }] {
            guard let base,
                  let resolved = try? loadedSkin.vfs.resolve(bitmapID, relativeTo: base,
                                                             location: scriptSource),
                  (try? loadedSkin.vfs.data(at: resolved.logicalPath, location: scriptSource)) != nil
            else { continue }
            return resolved.logicalPath
        }
        return nil
    }
}
