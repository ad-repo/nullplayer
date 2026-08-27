import AppKit
import CoreImage
import CoreGraphics
import CoreText
import Foundation
import ImageIO

struct WasabiBitmap {
    let image: CGImage
    let width: Int
    let height: Int
    let cost: Int

    func alpha(at point: CGPoint) -> UInt8 { pixel(at: point)?.alpha ?? 0 }

    /// One pixel in top-left (Wasabi) coordinates, or `nil` outside the bitmap.
    ///
    /// MMD3's rotary knobs are driven by a `Map`: a grayscale bitmap whose value at the cursor *is*
    /// the knob's angle, so the script needs the colour channels, not just the mask.
    func pixel(at point: CGPoint) -> (red: UInt8, green: UInt8, blue: UInt8, alpha: UInt8)? {
        let x = Int(point.x.rounded(.down))
        let y = Int(point.y.rounded(.down))
        guard x >= 0, y >= 0, x < width, y < height else { return nil }
        var pixel = [UInt8](repeating: 0, count: 4)
        pixel.withUnsafeMutableBytes { bytes in
            guard let context = CGContext(data: bytes.baseAddress, width: 1, height: 1,
                                          bitsPerComponent: 8, bytesPerRow: 4,
                                          space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return }
            context.translateBy(x: CGFloat(-x), y: CGFloat(-(height - y - 1)))
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        }
        return (pixel[0], pixel[1], pixel[2], pixel[3])
    }
}

/// A colour-theme adjustment: a per-channel amount plus the model it is applied under.
///
/// A `<gammagroup value="r,g,b">` carries three signed values in −4096…4096 where **0 means "leave
/// this channel alone"**. The stored `red`/`green`/`blue` are that raw amount normalized to −1…1;
/// `additive` picks how it combines with a pixel, and that choice belongs to the skin, not to us:
///
/// - `boost="0"`, or the attribute omitted → **multiply**, `channel × (1 + amount)`. This tints real
///   artwork without washing it out. Every group in Anexa is `boost="0"`, and so are MMD3's
///   `Backgrounds`/`Display`/`Buttons` — an additive model there pushed midtones toward white and
///   rendered MMD3's display as washed-out pastel instead of saturated orange on black.
/// - `boost` non-zero → **add**, `channel + amount`. This is how a skin recolors a black template.
///   Anaheim Player 01 marks 57 of its 65 groups `boost="1"`, its themed bitmaps are pure black with
///   only an alpha mask, and every `<color>` in its `studio-colors.xml` is `0,0,0`; under the
///   multiplicative model 0 × anything stays 0, which is black text on a black window. Stock
///   `winampmodern566` draws the same line — `boost="0"` on `Backgrounds`, `boost="1"` on exactly the
///   groups whose source colour is `0,0,0` (`wasabi.button.text`, `wasabi.list.column.text`,
///   `drawer.color.text.dark`) and on the hover-glow bitmaps.
///
/// MMD3 and Itemskin also ship `boost="2"`; its precise difference from `boost="1"` is unknown, so it
/// is treated as additive too — both appear on the same label groups, and either beats multiplying.
struct WasabiGammaTransform: Equatable {
    /// Per-channel amount normalized to −1…1 (the XML value over 4096). 0 leaves a channel alone
    /// under both models.
    let red: CGFloat
    let green: CGFloat
    let blue: CGFloat
    let grayscale: Bool
    /// `true` when the skin asked for the offset model via a non-zero `boost`.
    let additive: Bool

    static let identity = WasabiGammaTransform(red: 0, green: 0, blue: 0, grayscale: false)
    /// A zero amount is a no-op under *either* model, so the `additive` flag does not enter into it.
    var isIdentity: Bool { red == 0 && green == 0 && blue == 0 && !grayscale }

    /// Build from the raw XML attributes of one `<gammagroup>`.
    ///
    /// `gray` is a mode, not a flag — MMD3 uses both `gray="1"` and `gray="2"` — so any non-zero value
    /// desaturates. `boost` is likewise a mode; see the type comment for what each value selects.
    init(value: String, gray: String?, boost: String?) {
        let components = value.split(separator: ",")
            .map { CGFloat(Double($0.trimmingCharacters(in: .whitespaces)) ?? 0) }
        let padded = (components + [0, 0, 0]).prefix(3).map { $0 }
        let limit: CGFloat = 4096
        self.red = padded[0] / limit
        self.green = padded[1] / limit
        self.blue = padded[2] / limit
        let grayMode = Int(Double(gray ?? "0") ?? 0)
        self.grayscale = grayMode != 0
        let boostMode = Int(Double(boost ?? "0") ?? 0)
        self.additive = boostMode != 0
    }

    init(red: CGFloat, green: CGFloat, blue: CGFloat, grayscale: Bool, additive: Bool = false) {
        self.red = red
        self.green = green
        self.blue = blue
        self.grayscale = grayscale
        self.additive = additive
    }

    /// One channel through this group. `channel` and the result are both 0…1.
    func apply(_ channel: CGFloat, amount: CGFloat) -> CGFloat {
        additive ? channel + amount : channel * (1 + amount)
    }
}

final class WasabiColorThemeCatalog {
    private let loadedSkin: WinampModernLoadedSkin
    private var sets: [String: [String: WasabiGammaTransform]] = [:]
    private var displayNames: [String: String] = [:]
    /// Folded keys in document order — Winamp's colour-theme list order, and the source of the
    /// default theme.
    private var order: [String] = []
    private(set) var activeTheme: String = "Default"

    var themeNames: [String] { order.compactMap { displayNames[$0] } }

    init(loadedSkin: WinampModernLoadedSkin) {
        self.loadedSkin = loadedSkin
        func collect(_ nodes: [WalXMLNode]) {
            for node in nodes {
                if node.name.caseInsensitiveCompare("gammaset") == .orderedSame,
                   let name = node.attribute("id"), !name.isEmpty {
                    let key = Self.fold(name)
                    if displayNames[key] == nil { order.append(key) }
                    displayNames[key] = name
                    var groups: [String: WasabiGammaTransform] = [:]
                    for child in node.children where child.name.caseInsensitiveCompare("gammagroup") == .orderedSame {
                        guard let id = child.attribute("id") else { continue }
                        groups[Self.fold(id)] = WasabiGammaTransform(value: child.attribute("value") ?? "0,0,0",
                                                                     gray: child.attribute("gray"),
                                                                     boost: child.attribute("boost"))
                    }
                    sets[key] = groups
                }
                collect(node.children)
            }
        }
        collect(loadedSkin.document.roots)
        let stored = loadedSkin.configuration.string(section: "appearance", key: "theme", default: "")
        let storedKey = Self.fold(stored)
        if sets[storedKey] != nil {
            activeTheme = displayNames[storedKey] ?? stored
        } else {
            // Winamp's default colour theme is the **first gammaset in the document**, which skins name
            // freely ("clean | orange (default)"). Picking the alphabetically first name instead handed
            // MMD3 a green theme on every launch.
            activeTheme = order.first.flatMap { displayNames[$0] } ?? "Default"
        }
    }

    @discardableResult
    func activate(_ name: String) -> Bool {
        let key = Self.fold(name)
        guard let displayName = displayNames[key], displayName != activeTheme else { return false }
        activeTheme = displayName
        loadedSkin.configuration.setString(displayName, section: "appearance", key: "theme")
        return true
    }

    func transform(group: String?) -> WasabiGammaTransform? {
        guard let group else { return nil }
        return sets[Self.fold(activeTheme)]?[Self.fold(group)]
    }

    private static func fold(_ value: String) -> String {
        value.folding(options: [.caseInsensitive], locale: Locale(identifier: "en_US_POSIX"))
    }
}

/// A non-rectangular clip a script put on one object, taken from a greyscale **map** bitmap.
///
/// `Region.loadFromMap(Map, Int threshold, Boolean reversed)` (the signature is `std.mi`'s, not a
/// guess) reads the map's red channel as a 0–255 *position*: reversed selects every pixel at or
/// below the threshold, which is how a skin fills a bar as the value rises, and the unreversed form
/// selects everything at or above it. `Layer.setRegion` then clips the control to that shape;
/// `Layer.setRegionFromMap` is the same thing without the intermediate object.
///
/// It lives on the object as attributes because the renderer draws from the graph and nothing else —
/// the same route every animation call takes. The keys are namespaced so they cannot collide with a
/// skin's own markup.
struct WasabiRegionClip: Equatable {
    static let mapKey = "nullplayer.script.region.map"
    static let mapPathKey = "nullplayer.script.region.mappath"
    static let thresholdKey = "nullplayer.script.region.threshold"
    static let reversedKey = "nullplayer.script.region.reversed"
    static let offsetXKey = "nullplayer.script.region.offsetx"
    static let offsetYKey = "nullplayer.script.region.offsety"

    /// The map's declared `<bitmap>` id, or the raw string `loadMap` was given when it was a path.
    let mapID: String
    /// The logical path the id resolved to, for the path form of `loadMap`, which has no definition.
    let mapPath: String?
    let threshold: Int
    let reversed: Bool
    /// `Region.offset`, in map pixels: skins whose map covers a whole window shift the region back
    /// into the clipped layer's own space (the stock `customseek.m` does exactly this).
    let offsetX: Int
    let offsetY: Int

    init(mapID: String, mapPath: String?, threshold: Int, reversed: Bool,
         offsetX: Int = 0, offsetY: Int = 0) {
        self.mapID = mapID
        self.mapPath = mapPath
        self.threshold = threshold
        self.reversed = reversed
        self.offsetX = offsetX
        self.offsetY = offsetY
    }

    init?(object: WasabiObject) {
        guard let mapID = object.attributes[Self.mapKey], !mapID.isEmpty else { return nil }
        self.mapID = mapID
        self.mapPath = object.attributes[Self.mapPathKey]
        self.threshold = Int(object.attributes[Self.thresholdKey] ?? "") ?? 0
        self.reversed = object.attributes[Self.reversedKey] == "1"
        self.offsetX = Int(object.attributes[Self.offsetXKey] ?? "") ?? 0
        self.offsetY = Int(object.attributes[Self.offsetYKey] ?? "") ?? 0
    }

    var cacheKey: String {
        "\(mapPath ?? mapID.lowercased())|\(threshold)|\(reversed ? 1 : 0)"
    }

    /// Whether the map's value at one pixel is inside the region.
    static func contains(value: UInt8, threshold: Int, reversed: Bool) -> Bool {
        reversed ? Int(value) <= threshold : Int(value) >= threshold
    }

    @discardableResult
    func apply(to object: WasabiObject) -> Bool {
        var changed = object.setAttribute(Self.mapKey, value: mapID)
        changed = object.setAttribute(Self.mapPathKey, value: mapPath) || changed
        changed = object.setAttribute(Self.thresholdKey, value: String(threshold)) || changed
        changed = object.setAttribute(Self.reversedKey, value: reversed ? "1" : "0") || changed
        changed = object.setAttribute(Self.offsetXKey, value: String(offsetX)) || changed
        changed = object.setAttribute(Self.offsetYKey, value: String(offsetY)) || changed
        return changed
    }

    @discardableResult
    static func clear(on object: WasabiObject) -> Bool {
        var changed = false
        for key in [mapKey, mapPathKey, thresholdKey, reversedKey, offsetXKey, offsetYKey] {
            changed = object.setAttribute(key, value: nil) || changed
        }
        return changed
    }
}

final class WasabiResourceCache {
    let loadedSkin: WinampModernLoadedSkin
    let maximumCost: Int
    let themes: WasabiColorThemeCatalog

    private struct CachedBitmap {
        let bitmap: WasabiBitmap
        var access: UInt64
    }
    private var bitmaps: [String: CachedBitmap] = [:]
    /// Region masks, keyed by map and threshold. Separate from `bitmaps` because they are derived
    /// data with a different lifetime: a drag regenerates them, and the colour theme cannot touch
    /// them.
    private var regionMasks: [String: CGImage] = [:]
    private static let maximumCachedRegionMasks = 256
    /// Fonts and text measurement live in one shared place so a script's `getAutoWidth()` and this
    /// renderer's drawing agree on how wide a string is. See `WasabiTextMetrics`.
    let metrics: WasabiTextMetrics
    private var currentCost = 0
    private var accessCounter: UInt64 = 0
    private(set) var isTornDown = false

    init(loadedSkin: WinampModernLoadedSkin, themes: WasabiColorThemeCatalog,
         maximumCost: Int = 256 * 1_024 * 1_024) {
        self.loadedSkin = loadedSkin
        self.themes = themes
        self.maximumCost = maximumCost
        self.metrics = WasabiTextMetrics(loadedSkin: loadedSkin)
    }

    func bitmap(identifier: String?) -> WasabiBitmap? {
        guard !isTornDown, let identifier, !identifier.isEmpty else { return nil }
        let key = identifier.folding(options: [.caseInsensitive], locale: Locale(identifier: "en_US_POSIX"))
        accessCounter &+= 1
        if var cached = bitmaps[key] {
            cached.access = accessCounter
            bitmaps[key] = cached
            return cached.bitmap
        }
        guard let definition = loadedSkin.runtime.resources.resolvedDefinition(identifier: identifier),
              definition.kind == "bitmap", let path = definition.logicalFile,
              let data = try? loadedSkin.vfs.data(at: path, location: definition.source),
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              let fullImage = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
        let x = max(0, Int(Double(definition.attributes["x"] ?? "0") ?? 0))
        let topY = max(0, Int(Double(definition.attributes["y"] ?? "0") ?? 0))
        let width = max(1, min(fullImage.width - x,
                               Int(Double(definition.attributes["w"] ?? "") ?? Double(fullImage.width - x))))
        let height = max(1, min(fullImage.height - topY,
                                Int(Double(definition.attributes["h"] ?? "") ?? Double(fullImage.height - topY))))
        // `CGImage.cropping(to:)` addresses raw pixel data, whose origin is the image's TOP-left —
        // the same convention Wasabi's `y=` uses. Converting to a bottom-left origin here mirrored
        // every sprite's source rect about the sheet's centreline, so each element was cut from the
        // wrong row of the atlas.
        guard topY + height <= fullImage.height,
              let cropped = fullImage.cropping(to: CGRect(x: x, y: topY, width: width, height: height)) else { return nil }
        let image = themed(cropped, transform: themes.transform(group: definition.attributes["gammagroup"]))
        let cost = width * height * 4
        let bitmap = WasabiBitmap(image: image, width: width, height: height, cost: cost)
        bitmaps[key] = CachedBitmap(bitmap: bitmap, access: accessCounter)
        currentCost += cost
        evictIfNeeded(protecting: key)
        return bitmap
    }

    /// The alpha mask for a script-set region, or `nil` when the map cannot be resolved — in which
    /// case the caller must leave the object unclipped rather than draw an empty control.
    ///
    /// The map is decoded **without** the colour theme's gamma: a map's channels are data, not
    /// artwork, and a `gammagroup` on one (T800 puts its maps in `Background`) would move every
    /// threshold. The rows are written bottom-up because the mask is mapped onto its rect exactly as
    /// a drawn image is, and the scene is painted in a y-flipped context — see `drawImage`.
    func regionMask(_ region: WasabiRegionClip) -> CGImage? {
        guard !isTornDown else { return nil }
        let key = region.cacheKey
        if let cached = regionMasks[key] { return cached }
        guard let source = rawMapImage(region) else { return nil }
        let width = source.width
        let height = source.height
        var rgba = [UInt8](repeating: 0, count: width * height * 4)
        rgba.withUnsafeMutableBytes { bytes in
            guard let context = CGContext(data: bytes.baseAddress, width: width, height: height,
                                          bitsPerComponent: 8, bytesPerRow: width * 4,
                                          space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return }
            context.draw(source, in: CGRect(x: 0, y: 0, width: width, height: height))
        }
        var mask = [UInt8](repeating: 0, count: width * height)
        for row in 0..<height {
            // Row 0 of a bitmap context's data is the image's *top* row, so this reads the map
            // bottom-up: the mask has to arrive pre-flipped to survive the y-flipped scene context.
            let sourceRow = height - 1 - row
            for column in 0..<width {
                let offset = (sourceRow * width + column) * 4
                let inside = WasabiRegionClip.contains(value: rgba[offset],
                                                       threshold: region.threshold,
                                                       reversed: region.reversed)
                // A transparent pixel is outside every region: it is not part of the artwork.
                mask[row * width + column] = inside && rgba[offset + 3] > 0 ? 255 : 0
            }
        }
        guard let provider = CGDataProvider(data: Data(mask) as CFData),
              let image = CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 8,
                                  bytesPerRow: width, space: CGColorSpaceCreateDeviceGray(),
                                  bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
                                  provider: provider, decode: nil, shouldInterpolate: false,
                                  intent: .defaultIntent) else { return nil }
        // A volume drag walks the threshold, so this fills with one entry per value it passes.
        // Small (a map is a control-sized bitmap), but bounded all the same.
        if regionMasks.count >= Self.maximumCachedRegionMasks { regionMasks.removeAll() }
        regionMasks[key] = image
        return image
    }

    /// The map bitmap behind a region, gamma-free. `loadMap` takes either a declared id or a path,
    /// and the runtime records whichever it resolved.
    private func rawMapImage(_ region: WasabiRegionClip) -> CGImage? {
        let definition = loadedSkin.runtime.resources.resolvedDefinition(identifier: region.mapID)
        let path = (definition?.kind == "bitmap" ? definition?.logicalFile : nil) ?? region.mapPath
        guard let path, let data = try? loadedSkin.vfs.data(at: path),
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              let full = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
        guard let definition, definition.kind == "bitmap", definition.logicalFile == path else { return full }
        let x = max(0, Int(Double(definition.attributes["x"] ?? "0") ?? 0))
        let y = max(0, Int(Double(definition.attributes["y"] ?? "0") ?? 0))
        let width = max(1, min(full.width - x, Int(Double(definition.attributes["w"] ?? "") ?? Double(full.width - x))))
        let height = max(1, min(full.height - y, Int(Double(definition.attributes["h"] ?? "") ?? Double(full.height - y))))
        guard y + height <= full.height else { return full }
        return full.cropping(to: CGRect(x: x, y: y, width: width, height: height)) ?? full
    }

    /// The glyph sheet behind a `<bitmapfont>`.
    ///
    /// Winamp accepts **either** form for `file=`, exactly as `loadMap` does: the stock Winamp Modern
    /// skin names a previously declared `<bitmap>`, MMD3 names a path inside the skin
    /// (`file="player/tickerfont2.png"`), which the loader has already resolved into `logicalFile`.
    /// Resolving only the id form returned nil for MMD3 and therefore dropped *every* bitmap-font
    /// string it draws — the song ticker, the time, KBPS, KHZ — while leaving no diagnostic behind,
    /// because a font with no sheet simply draws nothing.
    ///
    /// The sheet is cached under its own key so it cannot collide with a `<bitmap>` of the same name,
    /// and it carries the font's own `gammagroup`, or the colour theme would tint the skin's artwork
    /// and leave its text untinted.
    func fontSheet(for definition: WalResourceDefinition) -> WasabiBitmap? {
        guard !isTornDown else { return nil }
        if let declared = bitmap(identifier: definition.attributes["file"]) { return declared }
        guard let path = definition.logicalFile else { return nil }
        let key = "bitmapfont:" + path.folding(options: [.caseInsensitive],
                                               locale: Locale(identifier: "en_US_POSIX"))
        accessCounter &+= 1
        if var cached = bitmaps[key] {
            cached.access = accessCounter
            bitmaps[key] = cached
            return cached.bitmap
        }
        guard let data = try? loadedSkin.vfs.data(at: path, location: definition.source),
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              let decoded = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
        let image = themed(decoded, transform: themes.transform(group: definition.attributes["gammagroup"]))
        let cost = decoded.width * decoded.height * 4
        let sheet = WasabiBitmap(image: image, width: decoded.width, height: decoded.height, cost: cost)
        bitmaps[key] = CachedBitmap(bitmap: sheet, access: accessCounter)
        currentCost += cost
        evictIfNeeded(protecting: key)
        return sheet
    }

    /// A font for a text object, or `nil` when nothing usable could be produced. See
    /// `WasabiTextMetrics.font(identifier:size:)` for why this is optional.
    func font(identifier: String?, size: CGFloat, traits: NSFontTraitMask = []) -> NSFont? {
        guard !isTornDown else { return nil }
        return metrics.font(identifier: identifier, size: size, traits: traits)
    }

    func teardown() {
        bitmaps.removeAll()
        regionMasks.removeAll()
        metrics.teardown()
        currentCost = 0
        isTornDown = true
    }

    func invalidateTheme() {
        bitmaps.removeAll()
        currentCost = 0
    }

    private func themed(_ image: CGImage, transform: WasabiGammaTransform?) -> CGImage {
        guard let transform, !transform.isIdentity else { return image }
        var output = CIImage(cgImage: image)
        if transform.grayscale {
            output = output.applyingFilter("CIColorControls", parameters: [kCIInputSaturationKey: 0])
        }
        // Offset or scale each channel per the group's `boost` mode; alpha is left alone so the theme
        // never dissolves a sprite's mask.
        if transform.additive {
            output = output.applyingFilter("CIColorMatrix", parameters: [
                "inputRVector": CIVector(x: 1, y: 0, z: 0, w: 0),
                "inputGVector": CIVector(x: 0, y: 1, z: 0, w: 0),
                "inputBVector": CIVector(x: 0, y: 0, z: 1, w: 0),
                "inputBiasVector": CIVector(x: transform.red, y: transform.green, z: transform.blue, w: 0)
            ])
        } else {
            output = output.applyingFilter("CIColorMatrix", parameters: [
                "inputRVector": CIVector(x: 1 + transform.red, y: 0, z: 0, w: 0),
                "inputGVector": CIVector(x: 0, y: 1 + transform.green, z: 0, w: 0),
                "inputBVector": CIVector(x: 0, y: 0, z: 1 + transform.blue, w: 0)
            ])
        }
        return CIContext(options: [.cacheIntermediates: false]).createCGImage(output, from: output.extent) ?? image
    }

    private func evictIfNeeded(protecting protectedKey: String) {
        while currentCost > maximumCost,
              let victim = bitmaps.filter({ $0.key != protectedKey }).min(by: { $0.value.access < $1.value.access }) {
            currentCost -= victim.value.bitmap.cost
            bitmaps[victim.key] = nil
        }
    }
}

/// The playback model shared by the renderer (which paints the current frame) and the script runtime
/// (which answers `getCurFrame()` / `isPlaying()`).
///
/// An `animatedlayer` is a sprite sheet plus a play head. Winamp scripts drive it as a *range*:
/// `setStartFrame(current)`, `setEndFrame(target)`, `setSpeed(msPerFrame)`, `play()` — MMD3 turns its
/// volume/bass/treble knobs exactly this way and polls `isPlaying()` to know when the sweep is done.
/// Keeping the play head a pure function of the elapsed time since `play()` means both sides agree
/// without either of them owning a ticking clock.
enum WasabiAnimation {
    static func now() -> TimeInterval { ProcessInfo.processInfo.systemUptime }

    static func state(of object: WasabiObject, frameCount: Int,
                      clock: TimeInterval = now()) -> (frame: Int, isPlaying: Bool) {
        let attributes = object.attributes
        let count = max(1, frameCount)
        let selected = max(0, min(count - 1, Int(attributes["frame"] ?? "0") ?? 0))
        // An explicit `playing` (set by `play()`/`stop()`) wins over the XML's `autoplay`, so a script
        // can stop a layer the skin declared as self-playing.
        let playing: Bool
        if let explicit = attributes["playing"] {
            playing = explicit == "1"
        } else {
            playing = attributes["autoplay"] == "1" || attributes["autoreplay"] == "1"
        }
        guard playing else { return (selected, false) }
        let period = max(0.008, (Double(attributes["speed"] ?? "100") ?? 100) / 1_000)
        let elapsed = max(0, clock - (Double(attributes["animstart"] ?? "") ?? 0))
        let steps = Int(elapsed / period)

        guard let endRaw = attributes["endframe"], let end = Int(endRaw) else {
            // No range set: the classic looping animation.
            return ((selected + steps) % count, true)
        }
        let start = max(0, min(count - 1, Int(attributes["startframe"] ?? "") ?? selected))
        let target = max(0, min(count - 1, end))
        let distance = abs(target - start)
        guard distance > 0 else { return (target, false) }
        if steps >= distance { return (target, false) }
        return (start + (target > start ? steps : -steps), true)
    }
}

struct WasabiSceneNode {
    let object: WasabiObject
    let frame: CGRect
    let clip: CGRect
    let bitmapID: String?
    /// The box this node resolved against. Only the protective-minimum probe reads it: a child that
    /// escapes this rect is an object whose parent has become too small to hold it.
    let parentFrame: CGRect
    /// Product of ancestor alphas (0…1). Groups with alpha < 255 multiply into their children.
    let inheritedAlpha: CGFloat
}

final class WasabiSceneRenderer {
    /// `WINAMP_MODERN_DRAW_PROFILE=1` accumulates per-object draw time, so "which node costs the
    /// frame?" is answerable from the harness rather than from a sampling profiler.
    static let profilesDrawing = ProcessInfo.processInfo.environment["WINAMP_MODERN_DRAW_PROFILE"] != nil
    static var drawProfile: [String: TimeInterval] = [:]

    let loadedSkin: WinampModernLoadedSkin
    let host: WinampModernHost
    /// Reads a `cfgattrib`-bound control's current value. Supplied by the script runtime, which owns
    /// the configuration store; nil in a renderer built without one (the pixel tests).
    var configStateProvider: ((WasabiObject) -> Bool)?
    /// The raw integer behind a `cfgattrib` binding, in the control's own unit — what a **slider**
    /// bound to an attribute stands at. Separate from `configStateProvider` because a lamp and a
    /// number are different questions about the same binding: mmd3's crossfade slider names
    /// `Crossfade time`, and reading its seconds as a truth value would light an `activeimage`.
    /// Nil in a renderer built without a script runtime (the pixel tests).
    var configValueProvider: ((WasabiObject) -> Int32?)?
    /// Visualization holders the view layer has put a live engine into (B20a). The renderer paints
    /// their boxes black and leaves the drawing to it.
    var hostedVisualizationHolders: Set<WasabiObjectID> = []
        /// The Layer FX warp for one object, or nil when it has none. Supplied by the script runtime,
    /// which owns the FX state and runs the skin's `fx_onGetPixel*` callbacks (Phase 28).
    var layerFXProvider: ((WasabiObject) -> WasabiLayerFXMesh?)?
    let resources: WasabiResourceCache
    let themeCoordinator: WinampModernThemeCoordinator
    let themes: WasabiColorThemeCatalog
    let container: WasabiObject
    private(set) var layout: WasabiObject
    private(set) var canvasSize: CGSize
    private let clock: () -> TimeInterval

    /// Optional sandboxed seam supplying playlist/EQ/library content for embedded component holders.
    /// Weak so the retained graph never keeps the host (owned by the window controller) alive.
    weak var componentHost: WinampModernComponentHost?
    private var playlistScrollOffset = 0
    /// The scroll position `revealPlaylistRow` computes, for the tests that assert the arithmetic.
    var playlistScrollOffsetForTesting: Int { playlistScrollOffset }
    /// How large NullPlayer draws its own text on this scene's host surfaces — the embedded playlist
    /// here, and the embedded library through the view layer, so the two cannot drift apart. Seeded
    /// from the skin's stored preference at load and set from the Text Size menu.
    var textScale: WinampModernTextScale = .auto
    /// The `<edit>` holding the keyboard, so it can draw a caret. Owned by the view (focus is a
    /// window's property); `nil` in every window that does not have one focused, which is most.
    var focusedEditID: WasabiObjectID?
    /// Per-object `<ColorThemes:List>` state. Keyed by object because a skin may show the same list
    /// in two places (mmd3 puts one in its player drawer and one in a standalone window) and each
    /// keeps its own selection and scroll.
    private var colorThemeListStates: [WasabiObjectID: WasabiColorThemeListState] = [:]

    var activeLayoutID: String { layout.xmlID ?? "normal" }
    var availableLayoutIDs: [String] {
        container.children.compactMap { child in
            child.typeName.caseInsensitiveCompare("layout") == .orderedSame ? child.xmlID : nil
        }
    }

    /// The layout a container opens in: the one named `normal`, else its **first declared** layout.
    /// Winamp's own rule, and the reason Lobe's Colour Themes window (six layouts, `about1`…`about6`,
    /// none of them `normal`) used to be unreachable — the initializer threw and the host dropped the
    /// whole container. `WinampModernContainerTopology.normalLayout` picks by the same rule, so the
    /// window the topology measures is the window this renderer draws.
    static func primaryLayout(of container: WasabiObject) -> WasabiObject? {
        let layouts = container.children.filter {
            $0.typeName.caseInsensitiveCompare("layout") == .orderedSame
        }
        return layouts.first { $0.xmlID?.caseInsensitiveCompare("normal") == .orderedSame } ?? layouts.first
    }

    init(loadedSkin: WinampModernLoadedSkin, host: WinampModernHost, containerID: String = "main",
         clock: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }) throws {
        self.loadedSkin = loadedSkin
        self.host = host
        self.clock = clock
        // One catalog per skin, shared by every window it opens: a colour theme belongs to the skin,
        // not to a window, so switching one has to recolour the player and the playlist together.
        self.themeCoordinator = loadedSkin.themeCoordinator
        self.themes = loadedSkin.themeCoordinator.catalog
        self.resources = WasabiResourceCache(loadedSkin: loadedSkin, themes: themes)
        guard let container = loadedSkin.runtime.graph.roots.first(where: {
            $0.typeName.caseInsensitiveCompare("container") == .orderedSame &&
            $0.xmlID?.caseInsensitiveCompare(containerID) == .orderedSame
        }), let layout = Self.primaryLayout(of: container) else {
            throw WalFailure(WalDiagnostic(.malformedXML,
                                           "Winamp Modern skin has no '\(containerID)' container layout."))
        }
        self.container = container
        self.layout = layout
        self.canvasSize = Self.defaultSize(for: layout, resources: self.resources)
        // Whichever window switches the theme, every renderer of this skin drops its themed bitmaps.
        themeCoordinator.addObserver(self) { [weak self] in self?.themeDidChange() }
    }

    @discardableResult
    func activateTheme(_ name: String) -> Bool {
        // The coordinator switches once and notifies every subscriber, this renderer included.
        themeCoordinator.activate(name)
    }

    /// Drop this renderer's themed bitmaps and repaint. Called for every renderer of the skin when
    /// any of them switches theme.
    func themeDidChange() {
        resources.invalidateTheme()
        paletteCache = nil
        warpSourceCache.removeAll()
        warpedImageCache.removeAll()
        clearPrescaledCache()
        invalidateSceneCache()
        loadedSkin.runtime.graph.markAllDirty(.appearance)
    }

    private var paletteCache: WasabiPalette?
    /// Rasterized sources for the Layer FX warp, keyed by image + size.
    private var warpSourceCache: [WarpSourceKey: (source: CGImage, pixels: [UInt8])] = [:]

    /// The colours NullPlayer's own surfaces draw with inside this skin, resolved through the very
    /// same resource + gamma path the skin's own drawing uses.
    var palette: WasabiPalette {
        if let paletteCache { return paletteCache }
        let palette = WasabiPalette.make { [weak self] identifier in
            guard let self,
                  let definition = loadedSkin.runtime.resources.resolvedColorDefinition(identifier: identifier),
                  Self.declaredColor(of: definition) != nil else { return nil }
            return resolvedColor(identifier)
        }
        paletteCache = palette
        return palette
    }

    /// A line-per-link account of how `palette` resolved, for the `RENDER_PALETTE` probe.
    ///
    /// The palette is the one thing about an embedded surface that *is* observable headlessly — the
    /// harness sets no component host, so nothing is drawn into a holder, but the colours those
    /// surfaces would be painted in resolve exactly as they do in the app. Every link reports why it
    /// answered or did not (missing definition, a bitmap with no `color=`, a value that is not three
    /// numbers), plus the declared value, the gammagroup, and the RGB the gamma left behind — which
    /// is what tells "the skin never declared it" apart from "a colour theme crushed it" (BB2a).
    func paletteResolutionReport() -> [String] {
        var lines: [String] = []
        let palette = palette
        for role in WasabiPalette.Role.allCases {
            let resolved = palette.color(for: role)
            lines.append("PALETTE \(role.rawValue) = \(Self.describe(resolved)) "
                         + "(fallback: \(role.fallbackDescription))")
            for identifier in role.identifiers {
                lines.append("PALETTE   \(identifier): \(describeLink(identifier))")
            }
        }
        return lines
    }

    /// Why one identifier in a role's chain answered, or did not.
    private func describeLink(_ identifier: String) -> String {
        guard let definition = loadedSkin.runtime.resources.resolvedColorDefinition(identifier: identifier) else {
            return "undeclared"
        }
        let origin = "kind=\(definition.kind)"
            + (definition.attributes["file"].map { " file=\($0)" } ?? "")
        guard let declared = Self.declaredColor(of: definition) else {
            // A bitmap that is a real image file carries no colour, so the chain skips it.
            return "\(origin) — no declared colour, skipped"
        }
        let (literal, gammaGroup) = Self.dereference(declared,
                                                     gammaGroup: definition.attributes["gammagroup"],
                                                     resources: loadedSkin.runtime.resources)
        let reference = literal == declared ? "" : " -> \(literal)"
        let gammagroup = gammaGroup.map { " gammagroup=\($0)" } ?? ""
        return "\(origin) value=\(declared)\(reference)\(gammagroup) -> \(Self.describe(resolvedColor(identifier)))"
    }

    /// `r,g,b` in the 0…255 the skin's XML is written in, so a probe line can be compared against the
    /// skin file by eye.
    private static func describe(_ color: NSColor) -> String {
        guard let rgb = color.usingColorSpace(.deviceRGB) else { return "non-RGB" }
        return String(format: "rgb(%.0f,%.0f,%.0f)", rgb.redComponent * 255,
                      rgb.greenComponent * 255, rgb.blueComponent * 255)
    }

    @discardableResult
    func activateLayout(id: String) throws -> CGSize {
        guard let next = container.children.first(where: {
            $0.typeName.caseInsensitiveCompare("layout") == .orderedSame &&
            $0.xmlID?.caseInsensitiveCompare(id) == .orderedSame
        }) else {
            throw WalFailure(WalDiagnostic(.malformedXML,
                                           "Container '\(container.xmlID ?? "Main")' has no layout '\(id)'.",
                                           location: container.source))
        }
        layout = next
        canvasSize = defaultSize(for: next)
        invalidateSceneCache()
        loadedSkin.runtime.graph.markAllDirty([.geometry, .appearance])
        return canvasSize
    }

    /// The active layout's own `minimum_w`/`minimum_h`, in skin pixels, raised to the protective
    /// minimum below. Every window hosting this renderer takes its `minSize` from here, so a restored
    /// or dragged frame can never ask the scene for a size the skin does not describe.
    var layoutMinimumSize: CGSize {
        let declared = declaredMinimumSize
        let protective = protectiveMinimumSize
        return CGSize(width: max(declared.width, protective.width),
                      height: max(declared.height, protective.height))
    }

    /// Whether the skin described a resize range for the active layout **at all** — any one of
    /// `minimum_w`/`minimum_h`/`maximum_w`/`maximum_h`.
    ///
    /// A layout that declares none of them is fixed at the size its author drew, and Winamp gives
    /// its window no resize affordance. Treating "undeclared" as "unbounded" instead let a restored
    /// frame stretch the scene: T800 is a 177×400 window whose whole face is one background layer,
    /// and it came back from saved state in a frame several hundred pixels wider with the head
    /// smeared across it. cPro-Bento declares 317×168…1920×1080 and is unaffected; so is Winamp
    /// Modern 5.66, which declares a minimum and is meant to widen.
    var layoutIsUserResizable: Bool {
        ["minimum_w", "minimum_h", "maximum_w", "maximum_h"].contains {
            Self.optionalDimension(layout.attributes[$0]) != nil
        }
    }

    /// The size range a *window* hosting this layout may take, which is not the same as the range
    /// `resize(to:)` accepts: a script may still resize a fixed layout, exactly as Winamp lets one.
    var userResizeLimits: (minimum: CGSize, maximum: CGSize) {
        guard layoutIsUserResizable else { return (canvasSize, canvasSize) }
        return (layoutMinimumSize, layoutMaximumSize)
    }

    /// What the layout itself declares — the floor the protective probe starts searching from.
    var declaredMinimumSize: CGSize {
        CGSize(width: Self.dimension(layout.attributes, keys: ["minimum_w"], fallback: 1),
               height: Self.dimension(layout.attributes, keys: ["minimum_h"], fallback: 1))
    }

    private var protectiveMinimumCache: [String: CGSize] = [:]

    /// The smallest canvas at which the scene still lays itself out the way its author drew it.
    ///
    /// R1's second half: a skin's declared `minimum_w`/`minimum_h` is written for Winamp, where a
    /// group clips its children; we clip only on `clipchildren="1"`, so below a certain size a child
    /// that no longer fits paints *over* its siblings instead of being cut off (cPro-Bento at
    /// 376×182 — above its declared 317×168 — overlaps its tab strip onto the transport). Rather
    /// than change clipping globally, we refuse to go small enough for it to happen.
    ///
    /// The skin's own default size is the reference: at the size its author chose, the scene is by
    /// definition correct, so any object already escaping its parent there is deliberate (a slider
    /// centres its thumb on its track, and thumb sheets routinely overhang). Overflow present *only*
    /// after shrinking is the failure, so the probe searches for the smallest size whose overflow set
    /// is still a subset of that baseline, per axis, bounded by the default size.
    private var protectiveMinimumSize: CGSize {
        let key = activeLayoutID
        if let cached = protectiveMinimumCache[key] { return cached }
        let computed = computeProtectiveMinimumSize()
        protectiveMinimumCache[key] = computed
        return computed
    }

    private func computeProtectiveMinimumSize() -> CGSize {
        let declared = declaredMinimumSize
        let ceiling = defaultSize(for: layout)
        guard ceiling.width > declared.width || ceiling.height > declared.height else { return declared }
        let reference = Set(sceneNodes(canvas: ceiling).map(\.object.stableID))
        let baseline = fitFailures(atCanvas: ceiling, reference: reference)
        let width = Self.smallestSatisfying(from: declared.width, to: ceiling.width) { candidate in
            fitFailures(atCanvas: CGSize(width: candidate, height: ceiling.height), reference: reference)
                .isNoWorse(than: baseline)
        }
        let height = Self.smallestSatisfying(from: declared.height, to: ceiling.height) { candidate in
            fitFailures(atCanvas: CGSize(width: width, height: candidate), reference: reference)
                .isNoWorse(than: baseline)
        }
        return CGSize(width: width, height: height)
    }

    /// How a scene fails to place itself at a hypothetical canvas size. The two kinds are kept apart
    /// deliberately: an object that already overhangs at the skin's own size is allowed to keep
    /// overhanging, but it is never allowed to *disappear*.
    struct WasabiFitFailures {
        var overflowing: Set<WasabiObjectID> = []
        var missing: Set<WasabiObjectID> = []

        /// No worse than `baseline` — the failures of the scene at the size its author drew it.
        func isNoWorse(than baseline: WasabiFitFailures) -> Bool {
            overflowing.isSubset(of: baseline.overflowing) && missing.isSubset(of: baseline.missing)
        }
    }

    /// Objects the scene fails to place at a hypothetical canvas size — escaping the box they
    /// resolved against, or gone entirely (`append` drops a node that lands wholly outside its
    /// parent, so a shrinking window makes objects *vanish* as well as overlap; count only the first
    /// and the search loses its monotonicity, because a wildly overflowing object stops being
    /// counted once it leaves the parent completely). `canvasSize` is untouched — the probe runs off
    /// to the side of the live scene.
    func fitFailures(atCanvas size: CGSize, reference: Set<WasabiObjectID>) -> WasabiFitFailures {
        var present: Set<WasabiObjectID> = []
        var result = WasabiFitFailures()
        for node in sceneNodes(canvas: size) {
            present.insert(node.object.stableID)
            // A half-pixel slack: geometry resolves in Double, and a box that lands exactly on its
            // parent's edge is flush, not overflowing.
            guard !node.frame.isEmpty,
                  !node.parentFrame.insetBy(dx: -0.5, dy: -0.5).contains(node.frame) else { continue }
            result.overflowing.insert(node.object.stableID)
        }
        result.missing = reference.subtracting(present)
        return result
    }

    /// Smallest whole pixel in `from...to` satisfying `predicate`, assuming it is monotone (a scene
    /// that fits at a size fits at every larger one). ~10 probes; the result is cached per layout.
    private static func smallestSatisfying(from: CGFloat, to: CGFloat,
                                           predicate: (CGFloat) -> Bool) -> CGFloat {
        var low = max(1, from.rounded(.up))
        var high = max(low, to.rounded(.up))
        if predicate(low) { return low }
        guard predicate(high) else { return high }
        while high - low > 1 {
            let middle = ((low + high) / 2).rounded()   // whole pixels: this becomes a window's minSize
            if predicate(middle) { high = middle } else { low = middle }
        }
        return high
    }

    /// The active layout's `maximum_w`/`maximum_h`, defaulting to the renderer's own 16384 ceiling.
    var layoutMaximumSize: CGSize {
        CGSize(width: Self.optionalDimension(layout.attributes["maximum_w"]) ?? 16_384,
               height: Self.optionalDimension(layout.attributes["maximum_h"]) ?? 16_384)
    }

    @discardableResult
    func resize(to proposedSize: CGSize) -> CGSize {
        let minimum = layoutMinimumSize
        let maximum = layoutMaximumSize
        canvasSize = CGSize(width: max(minimum.width, min(maximum.width, proposedSize.width)),
                            height: max(minimum.height, min(maximum.height, proposedSize.height)))
        invalidateSceneCache()
        warpedImageCache.removeAll()
        // Every destination size in the pre-scaled cache is now a size nothing draws at.
        clearPrescaledCache()
        loadedSkin.runtime.graph.markAllDirty(.geometry)
        return canvasSize
    }

    /// The painted scene, memoized against the graph's own mutation counter.
    ///
    /// The walk resolves every object's geometry from its parent's, and it ran again for *every*
    /// caller — the draw, the animation-rect scan, the visualization-rect scan, every hit test — so a
    /// scene that had not changed at all was re-solved several times a frame on the main thread. The
    /// graph bumps `sceneGeneration` on any attribute write the walk reads, which covers everything a
    /// script can do to the scene (move, hide, reparent, retext) and everything a resize or a theme
    /// switch does through `markAllDirty`; `invalidateSceneCache()` covers the few inputs that are
    /// *not* graph state, chiefly the host's playback state feeding `resolvedBitmapID`. The one
    /// attribute deliberately left out of that counter is `alpha`, re-resolved below.
    func sceneNodes() -> [WasabiSceneNode] {
        let generation = loadedSkin.runtime.graph.sceneGeneration
        if let cache = sceneNodeCache, cache.generation == generation, cache.canvas == canvasSize {
            return withRefreshedAlpha(cache.nodes.map(withRefreshedBitmapID))
        }
        WasabiMutationTrace.recordResolve("scene")
        let nodes = sceneNodes(canvas: canvasSize)
        sceneNodeCache = (generation, canvasSize, nodes)
        return nodes
    }

    /// Re-resolve `inheritedAlpha` over a memoized scene.
    ///
    /// `alpha` is the attribute skins *animate* — a target-alpha fade writes it up to sixty times a
    /// second — and it is the only one `append` consumes purely as a multiplier handed down the
    /// tree. So it is kept out of `sceneGeneration` and recomputed here instead, which turns a fade
    /// from a full re-solve of the object tree per step into one pass over an array (B52). Nodes are
    /// in pre-order, so a parent's product is always in the map before its children need it.
    private func withRefreshedAlpha(_ nodes: [WasabiSceneNode]) -> [WasabiSceneNode] {
        var product: [ObjectIdentifier: CGFloat] = [:]
        product.reserveCapacity(nodes.count)
        var refreshed: [WasabiSceneNode] = []
        refreshed.reserveCapacity(nodes.count)
        for node in nodes {
            let inherited = node.object.parent
                .flatMap { product[ObjectIdentifier($0)] } ?? node.inheritedAlpha
            product[ObjectIdentifier(node.object)] = inherited * Self.alphaFraction(of: node.object)
            if inherited == node.inheritedAlpha {
                refreshed.append(node)
            } else {
                refreshed.append(WasabiSceneNode(object: node.object, frame: node.frame,
                                                 clip: node.clip, bitmapID: node.bitmapID,
                                                 parentFrame: node.parentFrame,
                                                 inheritedAlpha: inherited))
            }
        }
        return refreshed
    }

    /// A node's *geometry* is a function of the graph; its **bitmap** is not. Play/pause artwork,
    /// the shuffle and repeat lamps, the EQ on/auto buttons and every `cfgattrib`-bound switch are
    /// resolved from the host and the configuration store, neither of which bumps the graph's
    /// mutation counter — so a memoized node has its image re-resolved on the way out rather than
    /// serving a stale one. Only the kinds that can vary pay for it.
    private func withRefreshedBitmapID(_ node: WasabiSceneNode) -> WasabiSceneNode {
        let type = node.object.typeName.lowercased()
        guard type == "status" || type == "nstatesbutton" || type == "togglebutton"
                || node.object.attributes["activeimage"] != nil else { return node }
        let bitmapID = resolvedBitmapID(for: node.object, pressed: false, hovered: false)
        guard bitmapID != node.bitmapID else { return node }
        return WasabiSceneNode(object: node.object, frame: node.frame, clip: node.clip,
                               bitmapID: bitmapID, parentFrame: node.parentFrame,
                               inheritedAlpha: node.inheritedAlpha)
    }

    /// Drop the memoized scene. Needed only for the inputs the graph's own generation cannot see.
    func invalidateSceneCache(_ caller: String = #function) {
        WasabiMutationTrace.recordResolve("drop(\(caller))")
        sceneNodeCache = nil
        layoutNodeCache = nil
    }

    private var sceneNodeCache: (generation: UInt64, canvas: CGSize, nodes: [WasabiSceneNode])?

    private func sceneNodes(canvas: CGSize) -> [WasabiSceneNode] {
        let rootRect = CGRect(origin: .zero, size: canvas)
        var nodes: [WasabiSceneNode] = []
        append(object: layout, frame: rootRect, clip: rootRect, into: &nodes, isRoot: true)
        return nodes
    }

    /// The active layout's geometry **including hidden subtrees** — what is laid out, not what is
    /// painted. Never used for drawing or hit testing.
    ///
    /// Wasabi lays a hidden object out anyway, and skins depend on that: cPro-Bento's side view is
    /// hidden when it closes, and the only thing that can bring it back is its own `onResize` deciding
    /// the pane is wide again (`if (w < 10) hide() else show()`). Resolving geometry only for what is
    /// on screen made that unreachable — closing the playlist hid it permanently.
    /// `layoutNodes()` for the harness: the geometry probe has to see inside a closed tab.
    func layoutNodesForTesting() -> [WasabiSceneNode] { layoutNodes() }

    /// Cached on the same key `sceneNodes()` uses, and for a much sharper reason: `resolvedGeometry`
    /// goes through here, and that is what answers every `getWidth`/`getLeft`/`getGuiW` a script
    /// asks. Uncached, one script event walking its own layout a few dozen times walked the entire
    /// object graph a few dozen times — and `browserNodes()` re-walked it again on every `layout()`
    /// pass on top of that.
    private var layoutNodeCache: (generation: UInt64, canvas: CGSize, nodes: [WasabiSceneNode])?

    private func layoutNodes() -> [WasabiSceneNode] {
        let generation = loadedSkin.runtime.graph.sceneGeneration
        if let cache = layoutNodeCache, cache.generation == generation, cache.canvas == canvasSize {
            return cache.nodes
        }
        WasabiMutationTrace.recordResolve("layout")
        let rootRect = CGRect(origin: .zero, size: canvasSize)
        var nodes: [WasabiSceneNode] = []
        append(object: layout, frame: rootRect, clip: rootRect, into: &nodes, isRoot: true,
               includingHidden: true)
        layoutNodeCache = (generation, canvasSize, nodes)
        return nodes
    }

    func draw(in context: CGContext, pressed: WasabiObjectID? = nil,
              hovered: WasabiObjectID? = nil) {
        // Whether the host's PCM tap needs to run is a property of the graph, and the frame is where
        // every route that can change it — a menu, a script's `setMode`, a scene rebuild — has
        // certainly landed. Cached against the graph's generation, so this is a `UInt64` compare on
        // the frames where nothing moved.
        refreshWaveformDemand()
        // Once per frame, not once per box. The tap plays its chunks out against the clock, so two
        // boxes reading it a few microseconds apart can straddle a 13 ms boundary and draw different
        // chunks — which in Big Bento's butterfly is a mirror that does not quite mirror.
        frameWaveform = waveformDemand?.needed == true ? host.waveformSamples : nil
        // The box runs a suite engine draws across are a property of this frame's scene (B53), and
        // they are worked out on the first `<vis>` that asks rather than up front — most skins have
        // one box and most frames draw no suite engine at all.
        frameVisRows = nil
        defer {
            frameWaveform = nil
            frameVisRows = nil
        }
        context.saveGState()
        context.translateBy(x: 0, y: canvasSize.height)
        context.scaleBy(x: 1, y: -1)
        context.interpolationQuality = .high
        if Self.profilesDrawing {
            for node in sceneNodes() {
                let start = Date()
                draw(node, in: context, pressed: pressed, hovered: hovered)
                let key = "\(node.object.typeName.lowercased())#\(node.object.xmlID ?? "-")"
                Self.drawProfile[key, default: 0] += Date().timeIntervalSince(start)
            }
        } else {
            for node in sceneNodes() {
                draw(node, in: context, pressed: pressed, hovered: hovered)
            }
        }
        context.restoreGState()
        loadedSkin.runtime.markFirstPaintComplete()
    }

    /// The alpha above which a bitmap pixel is *inside* an object's region, and so takes a click.
    ///
    /// Wasabi's region is every pixel with a non-zero alpha, and this used to be `8` to shrug off
    /// anti-aliased fringes. That threshold assumes artwork drawn at full opacity, and a skin is
    /// under no obligation to oblige: LOBE draws its whole button set as glassy discs whose
    /// **maximum** alpha is 79/255, with each glyph engraved into the disc at alpha **3** — a hole
    /// exactly where a user aims. Thirteen of its twenty-three main-window controls were dead at
    /// their own centre, and the click fell through to whatever layer was behind them, so the window
    /// read as inert rather than as a button that missed. Its `toggle-always-on-top` uses the same
    /// artwork and worked, because `rectrgn="1"` skips this test entirely — which is the control
    /// experiment for the whole diagnosis.
    ///
    /// A skin's hover and pressed overlays sit directly above the control they decorate and are
    /// often opaque enough to swallow a click at any threshold; what keeps them out of the way is
    /// `ghost="1"`, which `object(at:)` honours before it ever gets here.
    private static let regionAlphaFloor = 0

    func object(at point: CGPoint, interactiveOnly: Bool = true,
                ignoring shouldIgnore: ((WasabiObject) -> Bool)? = nil) -> WasabiObject? {
        for node in sceneNodes().reversed() where node.clip.contains(point) && node.frame.contains(point) {
            let object = node.object
            guard isVisible(object), object.attributes["ghost"] != "1" else { continue }
            if shouldIgnore?(object) == true { continue }
            if interactiveOnly && !isInteractive(object) { continue }
            if !interactiveOnly && !isRenderable(object, bitmapID: node.bitmapID) { continue }
            // `rectrgn="1"` *is* the region — the whole rect, artwork or not — so it also settles the
            // alpha question, and testing the bitmap anyway contradicts the attribute. Defix's four
            // main-window buttons are `rectrgn="1"` icons drawn as outlines with transparent gaps: a
            // click through a gap fell past the button onto the `ButtonBG` panel behind it, so the
            // first and fourth buttons were dead while the second and third (denser artwork under the
            // same point) worked — which reads as "two of my buttons are broken", not as a hit test
            // disagreeing with a declared region.
            if object.attributes["rectrgn"] != "1",
               let bitmap = resources.bitmap(identifier: node.bitmapID) {
                // An animated layer's artwork is a *strip*, and mapping the point across the whole
                // sheet would sample whichever frame happened to line up with that row. Its region is
                // the union of its frames instead — a point is clickable if **any** frame paints
                // there. That is both stable (a click does not depend on which frame is showing) and
                // what a fill animation needs: multipass's seek bar is empty ahead of the playhead, so
                // testing the current frame alone would make the whole point of a seek bar — clicking
                // *forward* — unreachable.
                if object.typeName.caseInsensitiveCompare("animatedlayer") == .orderedSame {
                    guard animationUnionAlpha(bitmap, object: object, node: node, point: point)
                            > Self.regionAlphaFloor
                    else { continue }
                } else {
                    let local = CGPoint(x: (point.x - node.frame.minX) / max(1, node.frame.width) * CGFloat(bitmap.width),
                                        y: (point.y - node.frame.minY) / max(1, node.frame.height) * CGFloat(bitmap.height))
                    guard bitmap.alpha(at: local) > Self.regionAlphaFloor else { continue }
                }
            }
            return object
        }
        return nil
    }

    func containsVisiblePixel(at point: CGPoint) -> Bool {
        object(at: point, interactiveOnly: false) != nil
    }

    func frame(of object: WasabiObject) -> CGRect? {
        sceneNodes().first(where: { $0.object === object })?.frame
    }

    /// Everything one object puts on screen: its own box **and its subtree's**.
    ///
    /// The object's own frame is not enough for a targeted repaint, because a child is not obliged to
    /// stay inside its parent — a group only clips when it says so. `alpha` is the case that makes
    /// this matter: it is inherited multiplicatively, so fading a group repaints every descendant,
    /// and invalidating the group's own rect alone leaves whatever hangs outside it half-faded on
    /// screen (B52).
    func paintedBounds(of object: WasabiObject) -> CGRect? {
        var subtree: Set<ObjectIdentifier> = []
        func collect(_ node: WasabiObject) {
            subtree.insert(ObjectIdentifier(node))
            for child in node.children { collect(child) }
        }
        collect(object)
        var bounds: CGRect?
        for node in sceneNodes() where subtree.contains(ObjectIdentifier(node.object)) {
            let rect = node.frame.intersection(node.clip)
            guard !rect.isNull, !rect.isEmpty else { continue }
            bounds = bounds.map { $0.union(rect) } ?? rect
        }
        return bounds
    }

    /// One object's resolved geometry: where it actually landed, and the box it resolved against.
    ///
    /// Scripts ask for this constantly (`getWidth`, `getGuiX`, …) and a *declared* attribute is no
    /// answer at all for relative geometry: cPro's tab strip is `w="-4" relatw="1"`, so
    /// `getWidth()` off the attribute is −4, and `CproTabs.m` compares that against the space its tabs
    /// need and collapses every one of them to 20px. See `WinampModernScriptRuntime.resolvedFrame`.
    func resolvedGeometry(of object: WasabiObject) -> (frame: CGRect, parent: CGRect)? {
        layoutNodes().first { $0.object === object }.map { ($0.frame, $0.parentFrame) }
    }

    /// The objects in the active scene a resize is reported to, with their resolved frames.
    ///
    /// Wasabi addresses `onResize` to containers of other objects, and every handler ClassicPro
    /// declares is on one: a layout (`beat.m`'s `frameGroup` *is* `layout id=normal`, `player.m`'s
    /// `myLayout`), a group (`shade.m`, `mainmenu.m`, `eq.m`), or a XUI instance of a groupdef. Leaf
    /// controls are excluded so a window resize does not spray the event across every button.
    /// Frames are **parent-relative**, the space a script's own `getGuiX`/`getGuiY` reports in.
    func resizeTargets() -> [(object: WasabiObject, frame: CGRect)] {
        layoutNodes().compactMap { node in
            let type = node.object.typeName.lowercased()
            guard type == "layout" || type == "group" || WasabiFrame.isFrame(node.object)
                    || loadedSkin.runtime.types.isXUITag(node.object.typeName) else { return nil }
            return (node.object, node.frame.offsetBy(dx: -node.parentFrame.minX,
                                                     dy: -node.parentFrame.minY))
        }
    }

    // MARK: - Splitter dragging

    /// Every draggable `<Wasabi:Frame>` divider in the active scene, with its grab strip in skin
    /// coordinates. Innermost last, so a hit test walking backwards finds the nested splitter first
    /// (cPro-Bento's playlist frame lives inside its main frame).
    func frameDividers() -> [(object: WasabiObject, rect: CGRect, isVertical: Bool)] {
        sceneNodes().compactMap { node in
            guard WasabiFrame.isFrame(node.object), isVisible(node.object),
                  let rect = WasabiFrame.dividerRect(of: node.object, in: node.frame) else { return nil }
            return (node.object, rect, rect.height >= rect.width)
        }
    }

    /// What outranks a splitter on the splitter's own grab strip.
    ///
    /// `object(at:)` answers "is anything interactive here", and for a splitter that question is too
    /// generous. A grab strip spans the full height of its frame, so it crosses whatever the skin has
    /// laid over that column — cPro's tab strip runs straight through the 8px seam, and a control the
    /// user can see must always win. But Big Bento Modern covers **every pixel of its window** with
    /// `<layer id="player.resizer.disable" move="1" alpha="0">`, plus four alpha-0
    /// `player.mainframe.grabber.mousetrap*` layers laid directly on the seam. Against the plain rule
    /// the splitter therefore never claimed a single press: every drag on it moved the window, while
    /// `resetCursorRects` promised a resize cursor over that same pixel (BB21).
    ///
    /// Two things do not outrank a splitter. **An object the user cannot see** (`alpha="0"`) is a
    /// mousetrap, not a control — it exists to catch events the skin routes elsewhere, and it has no
    /// claim on a strip the user is being shown a resize cursor over. **A surface whose only
    /// interactivity is `move="1"`** is window dragging, which is precisely the gesture a splitter
    /// exists to reinterpret over its own 8px strip. Everything else still wins.
    func objectOverridingDivider(at point: CGPoint) -> WasabiObject? {
        object(at: point) { object in
            if (Int(object.attributes["alpha"] ?? "255") ?? 255) <= 0 { return true }
            // `move="1"` alone. An object that also carries an action, or is a button or a slider, is
            // a real control that happens to be draggable, and keeps its claim.
            return object.attributes["move"] == "1" && !Self.hasOwnCommand(object)
        }
    }

    /// Whether an object carries a command of its own, independent of being draggable — the test that
    /// separates a skin's window-drag surface from a control that also moves the window.
    private static func hasOwnCommand(_ object: WasabiObject) -> Bool {
        let type = object.typeName.lowercased()
        if type == "button" || type == "togglebutton" || type == "nstatesbutton" || type == "slider" {
            return true
        }
        return object.attributes["action"] != nil
            || object.attributes[WasabiClickGesture.double.actionAttribute] != nil
            || object.attributes[WasabiClickGesture.right.actionAttribute] != nil
    }

    /// Every `<Wasabi:Frame>` in this scene that is a real two-pane splitter and carries an `id`,
    /// with the box its position is measured in — the frames whose divider can be saved and restored
    /// **by name** across launches (B44).
    ///
    /// `layoutNodes()`, not `sceneNodes()`: Wasabi lays a hidden object out anyway, and a splitter
    /// inside a closed drawer still has a position the user set. Restoring only what is painted would
    /// lose it for any skin whose drawer happened to be shut at quit.
    func persistableFrames() -> [(object: WasabiObject, id: String, frame: CGRect)] {
        layoutNodes().compactMap { node in
            guard WasabiFrame.isFrame(node.object),
                  WasabiFrame.paneIdentifiers(of: node.object).count == 2,
                  let id = node.object.xmlID, !id.isEmpty else { return nil }
            return (node.object, id, node.frame)
        }
    }

    /// Put every splitter in this scene back where the user dragged it (B44). Returns whether
    /// anything actually moved, so a caller can skip the resize dispatch and the repaint.
    ///
    /// Idempotent and safe to run more than once: it re-reads the store each time, so a drag that
    /// happens between two passes wins the second one as well. A frame the user has never touched has
    /// nothing stored and is left entirely to the skin.
    @discardableResult
    func restorePersistedFramePositions() -> Bool {
        guard let containerID = container.xmlID else { return false }
        var moved = false
        for frame in persistableFrames() {
            guard let stored = WinampModernSkinState.framePosition(container: containerID,
                                                                   frame: frame.id,
                                                                   in: loadedSkin.configuration)
            else { continue }
            // Re-clamp against the box as it is *now*: the window may have been resized since, and a
            // frame's `maxwidth="-300"` is measured from the far edge, so yesterday's legal offset can
            // be out of bounds today.
            let extent = WasabiFrame.isVerticalDivider(frame.object) ? frame.frame.width
                                                                     : frame.frame.height
            let clamped = WasabiFrame.clampedPosition(stored, extent: extent, object: frame.object)
            moved = WasabiFrame.setPosition(clamped, on: frame.object) || moved
        }
        return moved
    }

    /// Remember where the user left a divider (B44). Only a **drag** calls this: a script moving its
    /// own splitter is the skin's default speaking, and storing that would freeze the author's opening
    /// layout into a preference the user never expressed.
    func persistFramePosition(of object: WasabiObject) {
        guard let containerID = container.xmlID,
              let id = object.xmlID, !id.isEmpty else { return }
        WinampModernSkinState.setFramePosition(WasabiFrame.position(of: object),
                                               container: containerID, frame: id,
                                               in: loadedSkin.configuration)
    }

    // MARK: - Layout persistence (B44a)

    /// The layout the user last switched this container to, if it still exists in the skin. Checked
    /// against the container's own children so a renamed or removed layout in an updated skin is
    /// ignored rather than throwing on activation.
    var rememberedLayoutID: String? {
        guard let containerID = container.xmlID,
              let stored = WinampModernSkinState.layout(container: containerID,
                                                        in: loadedSkin.configuration),
              stored.caseInsensitiveCompare(activeLayoutID) != .orderedSame,
              container.children.contains(where: {
                  $0.typeName.caseInsensitiveCompare("layout") == .orderedSame &&
                  $0.xmlID?.caseInsensitiveCompare(stored) == .orderedSame
              }) else { return nil }
        return stored
    }

    /// Remember the layout this container is on. Called for a `SWITCH` the **user** clicked and for
    /// nothing else — a script's `switchToLayout` is the skin describing this run.
    func persistActiveLayout() {
        guard let containerID = container.xmlID else { return }
        WinampModernSkinState.setLayout(activeLayoutID, container: containerID,
                                        in: loadedSkin.configuration)
    }

    func frameDivider(at point: CGPoint) -> WasabiObject? {
        frameDividers().reversed().first { $0.rect.contains(point) }?.object
    }

    /// Move a splitter to where the pointer is. Returns whether anything moved, so the caller can
    /// skip the repaint — a drag along the divider's own axis produces a great many no-op events.
    @discardableResult
    func dragFrameDivider(_ object: WasabiObject, to point: CGPoint) -> Bool {
        guard let frame = frame(of: object) else { return false }
        return WasabiFrame.setPosition(WasabiFrame.position(draggedTo: point, in: frame, object: object),
                                       on: object)
    }

    // MARK: - Embedded component hosting

    /// Every `windowholder`/`componentbucket` in the active scene whose `hold`/id resolves to a
    /// typed component kind, with its frame in skin coordinates. Used to draw embedded playlist/EQ,
    /// place the library host view, and route input into the right surface.
    func componentHolders() -> [WinampModernComponentHolder] {
        sceneNodes().compactMap { node in
            guard WinampModernComponentRegistry.isHolderElement(node.object.typeName) else { return nil }
            guard isVisible(node.object) else { return nil }
            guard var surfaceID = Self.surfaceID(of: node.object) else { return nil }
            // The source/attribute/token checks prevent ordinary XML spoofing. The runtime identity
            // closes the remaining edge: after a host content group is registered, skin MAKI must
            // not be able to instantiate it beneath a lookalike container of its own.
            if case .hostWindow = surfaceID,
               !loadedSkin.runtime.isTrustedHostedHolder(node.object) {
                surfaceID = .component(.other)
            }
            if surfaceID.componentKind == .other,
               let diagnostic = Self.unknownComponentDiagnostic(for: node.object) {
                loadedSkin.runtime.record(diagnostic)
            }
            return WinampModernComponentHolder(object: node.object, surfaceID: surfaceID, frame: node.frame)
        }
    }

    func componentHolder(at point: CGPoint) -> WinampModernComponentHolder? {
        componentHolders().reversed().first { $0.frame.contains(point) }
    }

    /// The visible `<edit>` under a point, if the click landed in one. Its own hit test rather than
    /// `object(at:)`'s: an edit carries no artwork and no `action=`, so the interactive test skips it
    /// and the renderable one has no bitmap to measure — yet a click in the box is exactly how a text
    /// field takes the keyboard.
    func editControl(at point: CGPoint) -> WasabiObject? {
        for node in sceneNodes().reversed()
        where node.clip.contains(point) && node.frame.contains(point) {
            guard node.object.typeName.lowercased().components(separatedBy: ":").last == "edit",
                  isVisible(node.object) else { continue }
            return node.object
        }
        return nil
    }

    // MARK: - Component bucket (Winamp's thinger)

    static func isComponentBucket(_ object: WasabiObject) -> Bool {
        object.typeName.caseInsensitiveCompare("componentbucket") == .orderedSame
    }

    /// The skin-wide strip state every bucket in every one of this skin's windows shares.
    var componentBucket: WinampModernComponentBucketState { loadedSkin.runtime.componentBucket }

    /// Every `<componentbucket>` on screen in this window, with its box in skin coordinates.
    func componentBuckets() -> [(object: WasabiObject, frame: CGRect)] {
        sceneNodes().compactMap { node in
            Self.isComponentBucket(node.object) ? (object: node.object, frame: node.frame) : nil
        }
    }

    /// The icon under a point, with its index in the published set.
    func componentBucketIcon(at point: CGPoint) -> (icon: WinampModernBucketIcon, index: Int)? {
        let state = componentBucket
        for entry in componentBuckets().reversed() {
            let layout = WinampModernComponentBucketLayout(object: entry.object, frame: entry.frame)
            guard let slot = layout.slot(at: point) else { continue }
            let index = state.clampedOffset(state.offset, visibleCount: layout.visibleCount) + slot
            guard state.icons.indices.contains(index) else { continue }
            return (state.icons[index], index)
        }
        return nil
    }

    /// `CB_NEXT`/`CB_PREV` (`page: false`) and `CB_NEXTPAGE`/`CB_PREVPAGE`.
    ///
    /// A `CB_*` button names no bucket — in Winamp it is simply the button beside the strip — so the
    /// step is measured against the widest bucket this window is showing, and the scrolled state is
    /// skin-wide. A window whose layout draws no bucket (a `CB_*` button in a drawer that is closed)
    /// still steps by one, which is what `visibleCount` of an unseen box would come out at anyway.
    @discardableResult
    func scrollComponentBucket(by delta: Int, page: Bool) -> Bool {
        let visible = componentBuckets()
            .map { WinampModernComponentBucketLayout(object: $0.object, frame: $0.frame).visibleCount }
            .max() ?? 1
        let step = page ? delta * max(1, visible) : delta
        return componentBucket.scroll(by: step, visibleCount: max(1, visible))
    }

    /// Move the caption to the icon under the pointer. Returns whether it moved.
    @discardableResult
    func focusComponentBucketIcon(at point: CGPoint) -> Bool {
        guard let hit = componentBucketIcon(at: point) else { return false }
        return componentBucket.focus(hit.index)
    }

    // MARK: - Browser element discovery

    /// Every `<browser>` element in the layout, visible or not (B19). These are NOT component
    /// holders — they bypass `isHolderElement` (which gates the draw path and hit testing) and have
    /// their own independent surface lifecycle so they don't compete with the bridge's cached
    /// library surface. `layoutNodes()` is used instead of `sceneNodes()` so surfaces are created
    /// eagerly for browser elements inside initially-hidden tab groups; the view layer toggles each
    /// surface's `isHidden` from the scene set.
    func browserNodes() -> [(object: WasabiObject, frame: CGRect)] {
        layoutNodes().compactMap { node in
            guard Self.isBrowserElement(node.object) else { return nil }
            return (object: node.object, frame: node.frame)
        }
    }

    static func isBrowserElement(_ object: WasabiObject) -> Bool {
        let lower = object.typeName.lowercased()
        return lower == "browser" || lower == "winamp:browser"
    }

    /// Whether a `<browser>` element is currently visible in the scene (all ancestors visible).
    func isBrowserVisible(_ object: WasabiObject) -> Bool {
        sceneNodes().contains { $0.object === object }
    }

    /// The kind a holder element hosts. `<component param="guid:…">` is the third holder form (the
    /// one mmd3/CornerAmp/Winamp Modern actually use for their playlist and library content), and it
    /// names its component in `param` rather than in `hold`.
    static func surfaceID(of object: WasabiObject) -> WinampModernSurfaceID? {
        guard let reference = componentReference(of: object) else { return nil }
        if let hosted = hostedWindowID(for: object, reference: reference) {
            return .hostWindow(hosted)
        }
        // A holder that names something unrecognizable stays in the scene as an inert `.other`
        // component: an unknown GUID must never fall through to a host surface it did not ask for.
        return .component(WinampModernComponentRegistry.kind(for: reference) ?? .other)
    }

    static func componentKind(of object: WasabiObject) -> WinampModernComponentKind? {
        surfaceID(of: object)?.componentKind
    }

    /// The raw component reference a holder declares, in the order Wasabi reads them for that element.
    private static func componentReference(of object: WasabiObject) -> String? {
        let keys: [String]
        if object.typeName.caseInsensitiveCompare("component") == .orderedSame {
            keys = ["param", "guid"]
        } else {
            keys = ["hold", "component", "guid"]
        }
        for key in keys {
            if let value = object.attributes[key]?.trimmingCharacters(in: .whitespacesAndNewlines),
               !value.isEmpty {
                // `none` is not an unknown component — it is Wasabi for "this holder holds nothing",
                // and a holder that holds nothing must draw nothing. Falling through to `.other`
                // painted an opaque slab of the palette's content colour over whatever the skin had
                // drawn underneath: Big Bento's `wdh.waveseeker` (its WACUP-only waveform seeker)
                // sits directly over the seek bar, which is why the seek bar was a solid black bar.
                // Answering nil here also stops the id heuristic below, which is a *fallback* for a
                // holder that names nothing at all, not for one that explicitly names nothing.
                if value.caseInsensitiveCompare("none") == .orderedSame { return nil }
                return value
            }
        }
        // Named engine holders encode the kind in their id (`centro.windowholder.library`) and carry
        // no explicit reference at all.
        return object.attributes["id"].flatMap {
            WinampModernComponentRegistry.kindFromHolderIdentifier($0) != nil ? $0 : nil
        }
    }

    private static func hostedWindowID(for object: WasabiObject, reference: String)
        -> WinampModernHostedWindowID? {
        guard object.source.path == WasabiSurfaceSynthesizer.sourcePath else { return nil }
        guard let container = enclosingContainer(of: object),
              container.attributes[WinampModernContainerTopology.synthesizedAttribute] == "1"
        else { return nil }
        for id in WinampModernHostedWindowID.allCases {
            if reference == "guid:np.\(id.rawValue)" {
                return WinampModernHostedWindowRegistry.entry(id: id)?.id
            }
        }
        return nil
    }

    private static func enclosingContainer(of object: WasabiObject) -> WasabiObject? {
        var node: WasabiObject? = object
        while let current = node {
            if current.typeName.caseInsensitiveCompare("container") == .orderedSame {
                return current
            }
            node = current.parent
        }
        return nil
    }

    private static func unknownComponentDiagnostic(for object: WasabiObject) -> WalDiagnostic? {
        guard let reference = componentReference(of: object),
              WinampModernComponentRegistry.kind(for: reference) == nil else { return nil }
        return WalDiagnostic(.unknownComponent,
                             "<\(object.typeName)> names unknown component '\(reference)'; "
                             + "it renders as an inert frame.",
                             severity: .warning)
    }

    /// The text size the embedded playlist draws at, in skin pixels — the Text Size setting, resolved
    /// against this scene's canvas.
    ///
    /// The `holder` is unused and stays in the signature deliberately: the render-dump probe reports
    /// per holder, and the size is a property of the *window*, not of the pane inside it. That is the
    /// whole point of the rule — Big Bento's playlist keeps one size whether its side pane is
    /// collapsed to 202px or enlarged to 819px.
    func playlistTextPixelHeight(in holder: WasabiObject?) -> Double {
        textScale.cellPixelHeight(canvasHeight: canvasSize.height)
    }

    /// Row height of the embedded playlist, in skin pixels. One cell plus the gap the 12px rows of
    /// the original fixed metric had at 11px text.
    func playlistRowHeight(in holder: WasabiObject? = nil) -> CGFloat {
        CGFloat((playlistTextPixelHeight(in: holder) * 1.1).rounded())
    }

    func playlistVisibleRowCount(in frame: CGRect, holder: WasabiObject? = nil) -> Int {
        max(0, Int(frame.height / playlistRowHeight(in: holder)))
    }

    /// Which playlist row (absolute index, accounting for scroll) sits under a point in a holder.
    func playlistRow(at point: CGPoint, in frame: CGRect, holder: WasabiObject? = nil) -> Int? {
        let rowHeight = playlistRowHeight(in: holder)
        guard frame.contains(point), rowHeight > 0 else { return nil }
        let row = Int((point.y - frame.minY) / rowHeight) + playlistScrollOffset
        return row >= 0 ? row : nil
    }

    func scrollPlaylist(byRows delta: Int, rowCount: Int, in frame: CGRect, holder: WasabiObject? = nil) {
        let maxOffset = max(0, rowCount - playlistVisibleRowCount(in: frame, holder: holder))
        playlistScrollOffset = max(0, min(maxOffset, playlistScrollOffset + delta))
    }

    /// Scroll the least that brings a row on screen — what `PlEdit.showTrack(n)` and
    /// `showCurrentlyPlayingTrack()` mean. A row already visible does not move the list, so a skin
    /// that calls this from a timer does not fight the user's own scrolling.
    func revealPlaylistRow(_ row: Int, rowCount: Int, in frame: CGRect, holder: WasabiObject? = nil) {
        let visible = playlistVisibleRowCount(in: frame, holder: holder)
        guard visible > 0, rowCount > 0, row >= 0, row < rowCount else { return }
        let maxOffset = max(0, rowCount - visible)
        var offset = max(0, min(maxOffset, playlistScrollOffset))
        if row < offset { offset = row }
        if row >= offset + visible { offset = row - visible + 1 }
        playlistScrollOffset = max(0, min(maxOffset, offset))
    }

    // MARK: - Colour theme list (Phase 32)

    /// Whether an object is a `<ColorThemes:List>`. The tag is unregistered — Winamp supplies it, not
    /// the skin — so it arrives as a leaf with this type name and nothing else.
    static func isColorThemeList(_ object: WasabiObject) -> Bool {
        object.typeName.caseInsensitiveCompare("colorthemes:list") == .orderedSame
    }

    /// Every colour-theme list in the active scene, with its resolved frame.
    func colorThemeLists() -> [(object: WasabiObject, frame: CGRect)] {
        sceneNodes().compactMap { node in
            guard Self.isColorThemeList(node.object), isVisible(node.object) else { return nil }
            return (node.object, node.frame)
        }
    }

    /// The list under a point, topmost first.
    func colorThemeList(at point: CGPoint) -> (object: WasabiObject, frame: CGRect)? {
        colorThemeLists().reversed().first { $0.frame.contains(point) }
    }

    /// The theme names this list shows, in catalog (document) order — Winamp's own order.
    var colorThemeNames: [String] { themes.themeNames }

    /// Index of the applied theme in `colorThemeNames`, or nil when the skin declares none.
    var activeColorThemeIndex: Int? {
        colorThemeNames.firstIndex { $0.caseInsensitiveCompare(themes.activeTheme) == .orderedSame }
    }

    func colorThemeListRow(at point: CGPoint, in object: WasabiObject) -> Int? {
        guard let frame = frame(of: object) else { return nil }
        return state(ofColorThemeList: object, frame: frame)
            .row(at: point, in: frame, rowCount: colorThemeNames.count)
    }

    func scrollColorThemeList(byRows delta: Int, in object: WasabiObject) {
        guard let frame = frame(of: object) else { return }
        var state = state(ofColorThemeList: object, frame: frame)
        state.scroll(byRows: delta, rowCount: colorThemeNames.count, in: frame)
        colorThemeListStates[object.stableID] = state
    }

    func selectColorThemeRow(_ index: Int, in object: WasabiObject) {
        guard let frame = frame(of: object) else { return }
        var state = state(ofColorThemeList: object, frame: frame)
        state.select(index, rowCount: colorThemeNames.count, in: frame)
        colorThemeListStates[object.stableID] = state
    }

    /// The name this list has picked out — what its `Switch` button applies.
    func selectedColorTheme(in object: WasabiObject) -> String? {
        guard let frame = frame(of: object) else { return nil }
        let names = colorThemeNames
        let index = state(ofColorThemeList: object, frame: frame).selectedIndex
        return names.indices.contains(index) ? names[index] : nil
    }

    /// Put every list's selection back on the applied theme. Called after an activation that did not
    /// come from a list (the skin's next/previous buttons, the host menu, a script), so no list is
    /// left pointing at a theme the window is not wearing.
    func syncColorThemeLists() {
        guard let active = activeColorThemeIndex else { return }
        let count = colorThemeNames.count
        for entry in colorThemeLists() {
            var state = state(ofColorThemeList: entry.object, frame: entry.frame)
            state.follow(activeIndex: active, rowCount: count, in: entry.frame)
            colorThemeListStates[entry.object.stableID] = state
        }
    }

    /// What `action_target="<id>"` on a button names.
    ///
    /// Wasabi's own lookup semantics, the **wide** ones `findObject` uses: the button's own container
    /// subtree first, then the whole graph. The wide half is load-bearing — multipass's theme list
    /// lives in `player.normal.group.drawer.colorthemes.list`, a separate `nodock="1"` groupdef that
    /// is not in the switch button's container at all — and the nearest match still wins, so a skin
    /// with the same id in two windows keeps getting its own.
    func actionTarget(of object: WasabiObject) -> WasabiObject? {
        guard let wanted = object.attributes["action_target"]?
            .trimmingCharacters(in: .whitespacesAndNewlines), !wanted.isEmpty else { return nil }
        var ancestor: WasabiObject? = object
        while let current = ancestor,
              current.typeName.caseInsensitiveCompare("container") != .orderedSame {
            ancestor = current.parent
        }
        if let container = ancestor, let near = Self.descendant(of: container, xmlID: wanted) {
            return near
        }
        return loadedSkin.runtime.graph.objects(xmlID: wanted).first
    }

    private static func descendant(of object: WasabiObject, xmlID: String) -> WasabiObject? {
        for child in object.children {
            if child.xmlID?.caseInsensitiveCompare(xmlID) == .orderedSame { return child }
        }
        for child in object.children {
            if let found = descendant(of: child, xmlID: xmlID) { return found }
        }
        return nil
    }

    /// The list a colour-theme button acts on: the one its `action_target` names, else the only one
    /// in the scene. A skin that puts its Switch button beside its list and names no target — mmd3's
    /// standalone window — is the common case, and it has exactly one list to mean.
    func colorThemeList(forAction object: WasabiObject) -> WasabiObject? {
        if let target = actionTarget(of: object), Self.isColorThemeList(target) { return target }
        let lists = colorThemeLists()
        return lists.count == 1 ? lists[0].object : nil
    }

    /// This list's state, seeded on first use so it opens showing the applied theme rather than
    /// row 0 — the difference between "which of these 83 am I wearing?" and a list that answers it.
    private func state(ofColorThemeList object: WasabiObject, frame: CGRect) -> WasabiColorThemeListState {
        var state = colorThemeListStates[object.stableID] ?? WasabiColorThemeListState()
        if !state.isSeeded, let active = activeColorThemeIndex {
            state.seed(activeIndex: active, rowCount: colorThemeNames.count, in: frame)
            colorThemeListStates[object.stableID] = state
        }
        return state
    }

    func teardown() {
        themeCoordinator.removeObserver(self)
        resources.teardown()
        sceneNodeCache = nil
        warpSourceCache.removeAll()
        warpedImageCache.removeAll()
        clearPrescaledCache()
    }

    /// Drop the pre-scaled artwork. Called when the bitmaps behind it are replaced (a theme switch)
    /// or when this renderer is going away.
    func clearPrescaledCache() {
        prescaledCache.removeAll()
        prescaledPixelCost = 0
        cropCache.removeAll()
    }

    /// Width an object takes from text rather than from a `w=`, in skin pixels — `nil` when it takes
    /// none. Two cases: a group with `autowidthsource="<id>"` sizes to that descendant's text, and a
    /// text object that declares no width at all sizes to its own (ClassicPro's menu labels do the
    /// latter inside groups that do the former).
    private func autoWidth(of object: WasabiObject) -> CGFloat? {
        if let sourceID = object.attributes["autowidthsource"],
           let source = descendant(of: object, xmlID: sourceID) {
            return autoWidth(of: source)
        }
        let type = object.typeName.lowercased()
        guard type == "text" || type == "songticker" else { return nil }
        return resources.metrics.width(of: object,
                                       text: WasabiTextMetrics.content(of: object, host: host))
    }

    private func descendant(of root: WasabiObject, xmlID: String) -> WasabiObject? {
        for child in root.children {
            if child.xmlID?.caseInsensitiveCompare(xmlID) == .orderedSame { return child }
            if let match = descendant(of: child, xmlID: xmlID) { return match }
        }
        return nil
    }

    private func append(object: WasabiObject, frame parentFrame: CGRect, clip parentClip: CGRect,
                        into nodes: inout [WasabiSceneNode], isRoot: Bool = false,
                        includingHidden: Bool = false, inheritedAlpha: CGFloat = 1) {
        guard includingHidden || isVisible(object) else { return }
        let bitmapID = resolvedBitmapID(for: object, pressed: false, hovered: false)
        var intrinsic = resources.bitmap(identifier: bitmapID).map {
            WasabiSize(width: Double($0.width), height: Double($0.height))
        } ?? .zero
        // An animated layer that states no size of its own is one **frame** tall, not one sheet tall:
        // its bitmap is a strip of N frames and `framewidth`/`frameheight` say how it is cut. Taking
        // the sheet made multipass's seek bar a 139×364 box where the skin drew a 139×13 one — one
        // frame stretched over twenty-eight frames' worth of height, then clipped by the display group
        // to a transparent sliver, so the skin's only seek indicator was invisible while the script
        // behind it worked perfectly.
        if object.typeName.caseInsensitiveCompare("animatedlayer") == .orderedSame {
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
        // the box we draw are one measurement.
        if object.attributes["h"] == nil,
           (object.typeName.lowercased().components(separatedBy: ":").last ?? "") == "text" {
            intrinsic.height = Double(resources.metrics.lineHeight(of: object))
        }
        let resolved: CGRect
        if isRoot {
            resolved = parentFrame
        } else if object.attributes["fitparent"] == "1" {
            // `fitparent="1"` fills the parent regardless of x/y/w/h. Groups use it constantly
            // (`<group id="cpro.normal.background" fitparent="1"/>`); without it they resolve to a
            // 0×0 rect at the origin and every descendant collapses into the top-left corner.
            resolved = parentFrame
        } else {
            let wasabi = object.geometry.resolve(
                in: WasabiRect(x: Double(parentFrame.minX), y: Double(parentFrame.minY),
                               width: Double(parentFrame.width), height: Double(parentFrame.height)),
                intrinsicSize: intrinsic
            )
            // A *negative* box is not a box drawn backwards — it is an object whose parent is smaller
            // than the object's own margins (`h="-168" relath="1"` in a parent shorter than 168). Real
            // Wasabi draws nothing for it; `standardized` would instead flip it across its origin and
            // paint it over its siblings, which is what scrambles the scene when a window is dragged
            // below its layout minimum (R1). Drop it, and its subtree with it: every descendant
            // resolves against a box that does not exist.
            if wasabi.width < 0 || wasabi.height < 0 { return }
            let box = wasabi.standardized
            let placed = CGRect(x: box.x, y: box.y, width: box.width, height: box.height)
            // A correction for arithmetic the skin's own script gets wrong. Deliberately rare — see
            // `WasabiSkinQuirks` for the bar an entry has to clear.
            resolved = WasabiSkinQuirks.correctedFrame(for: object, resolved: placed) ?? placed
        }
        // An object parked outside its parent draws nothing, and neither do its children. Skins use
        // that as a hiding place: MMD3 keeps a dummy volume slider at (400,400) — outside the 583×216
        // layout — whose `thumb` is the 44×1012 knob *sheet*, and a slider centres its thumb on its
        // track, so without this the whole sheet painted a column of knobs across the window.
        if !includingHidden, !resolved.isEmpty, !resolved.intersects(parentClip) { return }
        let clip = parentClip.intersection(resolved.isEmpty ? parentClip : resolved)
        nodes.append(WasabiSceneNode(object: object, frame: resolved, clip: parentClip,
                                     bitmapID: bitmapID, parentFrame: isRoot ? resolved : parentFrame,
                                     inheritedAlpha: inheritedAlpha))
        let childClip = clipsChildren(object) || isFramePane(object) ? clip : parentClip
        let childAlpha = inheritedAlpha * Self.alphaFraction(of: object)
        // A container a script has scrolled lays its children out against a box shifted *up* by the
        // offset; the clip stays on the unscrolled box, so content leaves through the top and arrives
        // from the bottom exactly as it should. Doing it here rather than at draw time is what makes
        // hit testing follow for free — `object(at:)` walks these same nodes, so a control scrolled
        // halfway up the page is clickable where it is drawn and nowhere else.
        let childFrame = resolved.offsetBy(dx: 0, dy: -scrollOffset(of: object, frame: resolved))
        for child in object.children {
            append(object: child, frame: childFrame, clip: childClip, into: &nodes,
                   includingHidden: includingHidden, inheritedAlpha: childAlpha)
        }
    }

    /// Is this control laid out along the vertical axis?
    ///
    /// Skins spell it **both** ways and mean the same thing. Across the installed corpus: 158 slider
    /// declarations say `vertical`, and **49 say `v`** (either case), in 8 skins — Big Bento Modern
    /// ×4, Anexa, Enkera, Lobe and the Nokia 5220. Testing only for the long spelling made every one
    /// of those 49 a *horizontal* control, with two consequences that look nothing like each other:
    /// the thumb was drawn along the wrong axis, and — worse — a drag read its value from the
    /// pointer's **x** across a bar 16px wide, so the position snapped to one end instead of
    /// tracking the mouse. That is why Big Bento Modern's settings pages could not be scrolled by
    /// dragging their scrollbar (BB19).
    static func isVerticalOrientation(_ object: WasabiObject) -> Bool {
        switch object.attributes["orientation"]?.lowercased() {
        case "v", "vertical": return true
        default: return false
        }
    }

    /// The scroll attribute a script writes through `scrollToPercent`, as a percentage of travel.
    static let scrollPercentKey = "nullplayer.script.scrollpercent"

    /// How far this container's contents have been scrolled, in skin pixels.
    ///
    /// The travel is whatever the children overflow their container by, so a page whose content fits
    /// never moves however hard a skin scrolls it — which is what keeps a short settings page still
    /// while a long one scrolls, with no per-page configuration.
    private func scrollOffset(of object: WasabiObject, frame: CGRect) -> CGFloat {
        guard let raw = object.attributes[Self.scrollPercentKey], let percent = Double(raw),
              percent > 0, frame.height > 0 else { return 0 }
        let travel = max(0, contentHeight(of: object, in: frame) - frame.height)
        guard travel > 0 else { return 0 }
        return CGFloat(min(100, max(0, percent)) / 100) * travel
    }

    /// How tall this container's content is, measured from its own direct children.
    ///
    /// Deliberately one level deep and intrinsic-free: the case this serves is a `<GroupList>` whose
    /// entries a script stacked with `instantiate` (BB7), and those carry declared heights. A child
    /// sized only by its artwork measures as its declared box here, which can under-report the
    /// travel — extend this if a skin turns up that scrolls bitmap-sized content.
    private func contentHeight(of object: WasabiObject, in frame: CGRect) -> CGFloat {
        let box = WasabiRect(x: Double(frame.minX), y: Double(frame.minY),
                             width: Double(frame.width), height: Double(frame.height))
        var maxY = frame.minY
        for child in object.children where isVisible(child) {
            let resolved = child.geometry.resolve(in: box, intrinsicSize: .zero)
            guard resolved.width >= 0, resolved.height >= 0 else { continue }
            maxY = max(maxY, CGFloat(resolved.y + resolved.height))
        }
        return maxY - frame.minY
    }

    /// Draw a `CGImage` into the flipped (top-left origin) skin space `draw(in:)` establishes.
    /// `CGContext.draw` always puts the image's *bottom* row at `rect.minY`, which under that flip is
    /// the visual top — so every bitmap has to be re-flipped about its own rect or it renders
    /// vertically mirrored in place. Text uses the same trick (`drawFlippedText`).
    private func drawImage(_ image: CGImage, in rect: CGRect, context: CGContext) {
        context.saveGState()
        context.translateBy(x: 0, y: rect.midY)
        context.scaleBy(x: 1, y: -1)
        context.translateBy(x: 0, y: -rect.midY)
        let quality = WasabiBitmapInterpolationPolicy.quality(
            sourcePixelSize: CGSize(width: image.width, height: image.height),
            destination: rect,
            in: context)
        context.interpolationQuality = quality
        context.draw(prescaled(image, for: rect, in: context, quality: quality), in: rect)
        context.restoreGState()
    }

    /// The same artwork, already rasterized at the size this context will put it on screen.
    ///
    /// A `.wal` scene is laid out in skin pixels and drawn through a scaled CTM — ×2 on a Retina
    /// display, more at a larger UI Size — so `CGContext.draw` resampled every bitmap in the window
    /// with `.high` interpolation on *every frame*. That is the measured cost of a Defix frame:
    /// 6.7 ms in unnamed layers, 3.7 ms in the layout's own background, all of it re-derived from
    /// artwork that had not changed. Scaling once and keeping the result turns the per-frame draw
    /// into a blit at the device resolution, and the pixels are identical — the same interpolation
    /// runs, just not sixty times a second.
    ///
    /// Only a genuine rescale is cached: art already at its device size is drawn straight through,
    /// so a skin at 1× on a non-Retina display pays nothing for this at all.
    private func prescaled(_ image: CGImage, for rect: CGRect, in context: CGContext,
                           quality: CGInterpolationQuality) -> CGImage {
        let ctm = context.ctm
        let width = Int((rect.width * abs(ctm.a)).rounded())
        let height = Int((rect.height * abs(ctm.d)).rounded())
        guard width > 0, height > 0, width * height <= Self.maximumPrescaledPixels,
              width * height >= Self.minimumPrescaledPixels,
              width != image.width || height != image.height else { return image }
        let key = WarpSourceKey(image: ObjectIdentifier(image), width: width, height: height)
        if let cached = prescaledCache[key] { return cached.image }
        guard let scaled = Self.resized(image, width: width, height: height, quality: quality)
        else { return image }
        // Bounded by pixel budget rather than by entry count: a skin's window backgrounds are the
        // entries that matter and one of those is worth a hundred button faces.
        prescaledPixelCost += width * height
        if prescaledPixelCost > Self.maximumPrescaledCachePixels {
            prescaledCache.removeAll()
            prescaledPixelCost = width * height
        }
        prescaledCache[key] = (image, scaled)
        return scaled
    }

    /// Largest single pre-scaled raster, in pixels (2048² — a full-window background at 4× UI Size).
    private static let maximumPrescaledPixels = 16_777_216
    /// Below this the resample is not worth an entry: a 32×32 button face costs microseconds, and the
    /// backgrounds and panels this exists for are two orders of magnitude larger.
    private static let minimumPrescaledPixels = 1_024
    /// Total pre-scaled pixels held, ~32 MB at 4 bytes each.
    private static let maximumPrescaledCachePixels = 25_165_824

    private var prescaledCache: [WarpSourceKey: (source: CGImage, image: CGImage)] = [:]
    private var prescaledPixelCost = 0

    private static func resized(_ image: CGImage, width: Int, height: Int,
                                quality: CGInterpolationQuality) -> CGImage? {
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                      bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        context.interpolationQuality = quality
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()
    }

    private func draw(_ node: WasabiSceneNode, in context: CGContext,
                      pressed: WasabiObjectID?, hovered: WasabiObjectID?) {
        let object = node.object
        let type = object.typeName.lowercased()
        guard !Self.isRegionOnly(object, type: type) else { return }
        // Fully transparent draws nothing, so don't pay to composite it. Setting `alpha(0)` on the
        // context and drawing anyway costs full price: Big Bento Modern lays
        // `<layer id="player.resizer.disable" … alpha="0">` over its **entire** 1526×868 window as a
        // mousetrap, and that one invisible layer measured **42.8 ms/frame** at Retina scale, with
        // `focus.dummy` — another full-window alpha-0 layer — costing another 42.0. Alpha is read per
        // frame, so an object fading in starts drawing again the moment it is no longer transparent.
        let effectiveAlpha = Self.alphaFraction(of: object) * node.inheritedAlpha
        guard effectiveAlpha > 0 else { return }
        context.saveGState()
        context.clip(to: node.clip)
        applyRegionClip(of: object, frame: node.frame, context: context)
        // `alpha` belongs to the *object*, not to one kind of drawing. Only the bitmap paths honoured
        // it, so a `<text alpha="0">` drew at full strength: Defix stacks its Kbps / KHz / Channels
        // readouts in one slot and shows one at a time purely by moving their alphas, and all three
        // (plus Extension over Broadcasting) came up printed on top of each other. Setting it here
        // covers text, bitmap fonts and the `background=` draw below as well; the per-drawer calls
        // that follow read the same attribute, so they are idempotent.
        context.setAlpha(effectiveAlpha)
        applyFlip(of: object, frame: node.frame, context: context)

        if let background = object.attributes["background"],
           let bitmap = resources.bitmap(identifier: background) {
            drawImage(bitmap.image, in: node.frame, context: context)
        }

        if type == "text" || type == "songticker" {
            drawText(object, frame: node.frame, context: context)
        } else if type == "edit" {
            drawEdit(object, frame: node.frame, context: context)
        } else if type == "list" {
            drawGuiList(object, frame: node.frame, context: context)
        } else if type == "slider" {
            drawSlider(object, frame: node.frame, context: context,
                       pressed: pressed == object.stableID)
        } else if type == "progressgrid" {
            drawProgressGrid(object, frame: node.frame, context: context)
        } else if type == "grid" {
            drawGrid(object, frame: node.frame, context: context)
        } else if type == "rect" {
            drawRect(object, frame: node.frame, context: context)
        } else if type == "gradient" {
            drawGradient(object, frame: node.frame, context: context)
        } else if type == "vis" {
            drawVisualization(object, frame: node.frame, context: context)
        } else if type == "eqvis" {
            drawEQVis(object, frame: node.frame, context: context)
        } else if type == "colorthemes:list" {
            drawColorThemeList(object, frame: node.frame, context: context)
        } else if type == "albumart" {
            if let artwork = host.albumArtwork {
                drawImage(artwork, in: node.frame, context: context)
            } else if let fallback = object.attributes["notfoundimage"],
                      let bitmap = resources.bitmap(identifier: fallback) {
                draw(bitmap, object: object, frame: node.frame, context: context)
            }
        } else if type == "componentbucket" {
            // Before the holder branch: a bucket *is* a holder element, and a skin whose bucket id
            // happened to name a component must still draw the strip rather than a playlist.
            drawComponentBucket(object, frame: node.frame, context: context)
        } else if WinampModernComponentRegistry.isHolderElement(type),
                  let kind = Self.componentKind(of: object) {
            drawComponent(kind: kind, object: object, frame: node.frame, context: context)
        } else if let imageID = resolvedBitmapID(for: object,
                                                  pressed: pressed == object.stableID,
                                                  hovered: hovered == object.stableID),
                  let bitmap = resources.bitmap(identifier: imageID) {
            // Layer FX first: the warp replaces the layer's own draw, and it applies to an animated
            // layer's current frame exactly as it does to a plain one (Defix's cassette reels are
            // rotated single images; its needles are too).
            if let mesh = layerFXProvider?(object),
               let image = layerImage(bitmap, object: object, type: type),
               drawWarped(image, in: node.frame, mesh: mesh, context: context) {
                // drawn
            } else if type == "animatedlayer" {
                drawAnimated(bitmap, object: object, frame: node.frame, context: context)
            } else {
                draw(bitmap, object: object, frame: node.frame, context: context)
            }
        } else if Self.isTextButton(object) {
            drawTextButton(object, frame: node.frame, context: context,
                           pressed: pressed == object.stableID)
        }
        context.restoreGState()
    }

    /// Mirror an object's content inside its own box, for `fliph` / `flipv`.
    ///
    /// The reflection is about the object's **own frame**, so a flipped object occupies exactly the
    /// rect it declares — only what is painted inside it turns around. Applied here, at the one seam
    /// every kind of drawing passes through, rather than in the bitmap path: the attribute belongs to
    /// the *object*, not to one way of filling it, which is the same lesson `alpha` taught two lines
    /// above. In the installed corpus all 15 declarations happen to be on `<vis>` (Big Bento Modern
    /// and its Windows 10 edition, Styx, Enkera, multipass), so nothing else moves today — but a
    /// `<layer fliph="1">` is legal Wasabi and would have silently drawn unflipped.
    ///
    /// Deliberately after both clips: `node.clip` and a region mask are set in the unflipped space,
    /// so an object cannot escape its box by mirroring, and a region map stays where its author put
    /// it. Children are their own scene nodes and are unaffected — flipping a `<group>` turns its own
    /// background around, not the objects inside it, which is what Wasabi does.
    ///
    /// Big Bento Modern's header is what this is for: `main.vis` (`fliph="1"`) and `main.vis2` sit
    /// side by side, 144px each, so the two analyzers meet low-frequency-to-low-frequency in the
    /// middle and read as one symmetric butterfly. Below them `main.vis.mirror` / `main.vis.mirror2`
    /// are `flipv="1" alpha="110" ghost="1"`, a dimmed 10px reflection. Ignoring the flags drew two
    /// identical copies with a seam down the middle and two reflections that were not reflected.
    ///
    /// **One exception, and it is a deliberate one (B53).** A `<vis>` painted by one of NullPlayer's
    /// own engines does not take `fliph`. The horizontal mirror is a composition Winamp's analyzer
    /// was drawn *for* — two rows of bands meeting at their low frequencies — and it does not
    /// transfer: a mirrored Cava runs its frequency sweep backwards, and vis_classic's profile
    /// artwork comes out reversed. `flipv` is untouched, because the dimmed reflection strip beneath
    /// the boxes is a reflection of whatever is above it and reads correctly for any engine.
    private func applyFlip(of object: WasabiObject, frame: CGRect, context: CGContext) {
        let suppressHorizontal = spectrumAnalyzer != .skin
            && object.typeName.caseInsensitiveCompare("vis") == .orderedSame
        guard let transform = Self.flipTransform(of: object, frame: frame,
                                                 suppressHorizontal: suppressHorizontal) else {
            return
        }
        context.concatenate(transform)
    }

    /// The mirror an object's `fliph` / `flipv` ask for, or `nil` when it asks for neither.
    ///
    /// Split out from the drawing call so the arithmetic can be asserted without a window: the
    /// defining property is that a flip is an **involution about the frame** — it maps `minX` to
    /// `maxX` and back, so applying it twice is the identity and the object still covers exactly the
    /// rect it declares. The flags are read with `WasabiGeometrySpec.flag`, so `fliph="2"` flips for
    /// the same `atoi` reason `relatw="2"` is relative (B42).
    static func flipTransform(of object: WasabiObject, frame: CGRect,
                              suppressHorizontal: Bool = false) -> CGAffineTransform? {
        let horizontal = !suppressHorizontal && WasabiGeometrySpec.flag(object.attributes["fliph"])
        let vertical = WasabiGeometrySpec.flag(object.attributes["flipv"])
        guard horizontal || vertical else { return nil }
        // x' = (minX + maxX) - x sends minX to maxX and back, which is the mirror about the frame.
        return CGAffineTransform(translationX: horizontal ? frame.minX + frame.maxX : 0,
                                 y: vertical ? frame.minY + frame.maxY : 0)
            .scaledBy(x: horizontal ? -1 : 1, y: vertical ? -1 : 1)
    }

    /// Clip one object to the region a script gave it, if any.
    ///
    /// The mask is placed at its own natural size at the object's origin, not stretched to the
    /// object's rect: a region is a set of *map pixels*, and `Region.offset` moves it in those same
    /// units. An unresolvable map leaves the object unclipped — a skin whose map is missing should
    /// look the way it did before regions existed, not lose the control altogether.
    private func applyRegionClip(of object: WasabiObject, frame: CGRect, context: CGContext) {
        guard let region = WasabiRegionClip(object: object),
              let mask = resources.regionMask(region) else { return }
        let rect = CGRect(x: frame.minX + CGFloat(region.offsetX),
                          y: frame.minY + CGFloat(region.offsetY),
                          width: CGFloat(mask.width), height: CGFloat(mask.height))
        let quality = context.interpolationQuality
        context.interpolationQuality = .none
        context.clip(to: rect, mask: mask)
        context.interpolationQuality = quality
    }

    /// A layer that contributes its bitmap to the **window region** and nothing else.
    ///
    /// `sysregion` is a signed combining mode, and a **negative** value means "region only, do not
    /// paint". The bitmap behind such a layer is a silhouette mask, not artwork: Ujola Cat's
    /// `standardframe.xml` — inherited by every `Wasabi:StandardFrame:*`, so by the playlist window
    /// and by the library window the synthesizer builds — carries five of them over
    /// `window-regions.png`, a magenta-and-white mask. Painted as ordinary layers they put a magenta
    /// slab across the full width at the top and white slabs along the bottom, on top of the real
    /// title strips: "layered full backgrounds in different colours" and "multiple top menubars".
    ///
    /// Only the sign matters. `0`, a positive value (Ujola's own console art is `sysregion="1"` on
    /// real bitmaps) and the non-numeric forms a skin writes (`"AND"`, which Anexa uses 15 times)
    /// all paint exactly as before. `sysregion="-2"` appears in 11 of the 18 installed skins.
    static func isRegionOnly(_ object: WasabiObject, type: String) -> Bool {
        guard type == "layer" || type == "animatedlayer",
              let raw = object.attributes["sysregion"], let value = Int(raw.trimmingCharacters(in: .whitespaces))
        else { return false }
        return value < 0
    }

    /// An object's `alpha` as a 0…1 fraction. An absent or unparsable value is opaque.
    static func alphaFraction(of object: WasabiObject) -> CGFloat {
        let alpha = max(0, min(255, Int(Double(object.attributes["alpha"] ?? "255") ?? 255)))
        return CGFloat(alpha) / 255
    }

    private func draw(_ bitmap: WasabiBitmap, object: WasabiObject,
                      frame: CGRect, context: CGContext) {
        let tileX = object.attributes["tile"] == "1" || object.attributes["tilex"] == "1"
        let tileY = object.attributes["tile"] == "1" || object.attributes["tiley"] == "1"
        if tileX || tileY {
            drawTiled(bitmap, in: frame, tileX: tileX, tileY: tileY, context: context)
            return
        }
        // A non-tiled layer stretches its bitmap to fill its rect. Resizable window chrome depends on
        // this: `wasabi.frame.top` is a 10×18 sprite stretched across the whole titlebar, and the
        // menubar/titlebar streaks are 5–10px sprites stretched to hundreds of pixels. Drawing them
        // at natural size instead painted one sprite and left the rest of the bar blank.
        drawImage(bitmap.image, in: frame, context: context)
    }

    /// `tile`/`tilex`/`tiley`: repeat the bitmap across the layer instead of stretching it. Every
    /// resizable strip in a Bento-style frame (top/bottom/left/right/center) is a tiled layer, so
    /// without this the frame paints one tile and leaves the rest of the window empty.
    private func drawTiled(_ bitmap: WasabiBitmap, in frame: CGRect, tileX: Bool, tileY: Bool,
                           context: CGContext) {
        let tileWidth = CGFloat(bitmap.width)
        let tileHeight = CGFloat(bitmap.height)
        guard tileWidth >= 1, tileHeight >= 1, frame.width > 0, frame.height > 0 else { return }
        context.saveGState()
        context.clip(to: frame)
        // Tiles are blitted 1:1; smoothing would resample each tile's edge and leave a visible seam
        // grid across every tiled background strip.
        context.interpolationQuality = .none
        // One tiling draw, not one blit per tile. The loop this replaces issued up to 8192 separate
        // `drawImage` calls per frame, and Big Bento Modern's window-sized tiled `<grid>` measured
        // **60.4 ms/frame** at Retina scale on its own — with the spectrum analyzer invalidating the
        // scene at the audio tap's rate, that is the main thread gone.
        //
        // `draw(_:in:byTiling:)` repeats the image across the whole clip, so the tiling axes are
        // chosen by the size of the rect handed to it: an axis that should *stretch* instead of
        // repeating is given the frame's full extent, and its repeats then fall outside the clip.
        //
        // The y-flip is the same one `drawImage` applies, and it has to be here too: skin artwork is
        // top-left origin against a bottom-left context, and tiling straight through drew every tiled
        // background upside down across 20 skins in the corpus. Flipping about the tile's own midY
        // leaves the tiling grid anchored where the old per-tile loop put it.
        let tile = CGRect(x: frame.minX, y: frame.minY,
                          width: tileX ? tileWidth : frame.width,
                          height: tileY ? tileHeight : frame.height)
        context.translateBy(x: 0, y: tile.midY)
        context.scaleBy(x: 1, y: -1)
        context.translateBy(x: 0, y: -tile.midY)
        context.draw(bitmap.image, in: tile, byTiling: true)
        context.restoreGState()
    }

    /// The `<list>` control: the rows a script put in it, in the skin's own colours.
    ///
    /// Winamp fills this box with a native list; the skin draws only the frame around it, so — like
    /// the playlist panel and the `<edit>` — the content is ours to paint. It takes its text size from
    /// the object's own `fontsize` and its colours from the skin's list palette, which is what keeps a
    /// search-results popup legible in a Light skin and a dark one without either being special-cased.
    private func drawGuiList(_ object: WasabiObject, frame: CGRect, context: CGContext) {
        let items = WasabiGuiList.items(of: object)
        guard !items.isEmpty, frame.width > 2, frame.height > 2 else { return }
        let rowHeight = CGFloat(WasabiGuiList.rowHeight(of: object))
        let visible = max(0, Int(frame.height / rowHeight))
        guard visible > 0 else { return }
        let maxOffset = max(0, items.count - visible)
        let offset = min(max(0, WasabiGuiList.scrollOffset(of: object)), maxOffset)
        let selected = Set(WasabiGuiList.selection(of: object))
        let pointSize = CGFloat(WasabiTextMetrics.pixelHeight(of: object)
                                * WasabiTextMetrics.pixelHeightToPointSize)
        context.saveGState()
        context.clip(to: frame)
        for slot in 0..<visible {
            let index = offset + slot
            guard items.indices.contains(index) else { break }
            let rowRect = CGRect(x: frame.minX, y: frame.minY + CGFloat(slot) * rowHeight,
                                 width: frame.width, height: rowHeight)
            let isSelected = selected.contains(index)
            if isSelected {
                context.setFillColor(palette.selectionBackground.cgColor)
                context.fill(rowRect)
            }
            let color = legibleRowColor(isSelected ? palette.selectionText : palette.listText,
                                        selected: isSelected)
            drawSurfaceText(items[index], in: rowRect.insetBy(dx: 3, dy: 1), color: color,
                            alignment: .left, pointSize: pointSize, context: context)
        }
        context.restoreGState()
    }

    /// Which row of a `<list>` sits under a point, for the click that selects it.
    func guiListRow(at point: CGPoint, in object: WasabiObject) -> Int? {
        guard let frame = frame(of: object), frame.contains(point) else { return nil }
        let rowHeight = CGFloat(WasabiGuiList.rowHeight(of: object))
        guard rowHeight > 0 else { return nil }
        let row = Int((point.y - frame.minY) / rowHeight) + WasabiGuiList.scrollOffset(of: object)
        return WasabiGuiList.items(of: object).indices.contains(row) ? row : nil
    }

    /// Wheel a script-filled list, clamped to what it holds against the box it is drawn in.
    func scrollGuiList(byRows delta: Int, in object: WasabiObject) {
        guard let frame = frame(of: object) else { return }
        let rowHeight = CGFloat(WasabiGuiList.rowHeight(of: object))
        let visible = max(1, Int(frame.height / max(1, rowHeight)))
        let maximum = max(0, WasabiGuiList.items(of: object).count - visible)
        let offset = WasabiGuiList.scrollOffset(of: object) + delta
        WasabiGuiList.setScrollOffset(min(max(0, offset), maximum), on: object)
    }

    /// The visible `<list>` under a point, if any — the same reason `editControl(at:)` has its own hit
    /// test: a list carries no artwork and no `action=`.
    func guiList(at point: CGPoint) -> WasabiObject? {
        for node in sceneNodes().reversed()
        where node.clip.contains(point) && node.frame.contains(point) {
            guard WasabiGuiList.isList(node.object), isVisible(node.object) else { continue }
            return node.object
        }
        return nil
    }

    /// The `<edit>` control: the text the user has typed, plus a caret while it holds the keyboard.
    ///
    /// A skin draws the box itself (Big Bento's search bar is three grids and a hover layer) and never
    /// draws the string — in Winamp the edit is a native child window. So this paints only the content
    /// and the insertion point, in the object's own font and colour, which is what makes the typed
    /// text land in the box the skin drew rather than in a rectangle of our choosing.
    private func drawEdit(_ object: WasabiObject, frame: CGRect, context: CGContext) {
        let text = object.attributes["text"] ?? ""
        if !text.isEmpty {
            drawText(text, object: object, frame: frame, context: context,
                     undeclaredColor: palette.listText)
        }
        guard focusedEditID == object.stableID else { return }
        let size = WasabiTextMetrics.pointSize(of: object)
        let font = resources.font(identifier: object.attributes["font"], size: size,
                                  traits: WasabiTextMetrics.traits(of: object))
            ?? NSFont.systemFont(ofSize: size)
        let width = (text as NSString).size(withAttributes: [.font: font]).width
        // Where the string ends, which depends on how it is aligned in the box — a centred search
        // field grows from the middle outwards and its caret has to travel with the last glyph.
        let x: CGFloat
        switch object.attributes["align"]?.lowercased() {
        case "center", "middle": x = frame.midX + width / 2
        case "right": x = frame.maxX - 1
        default: x = frame.minX + width + 1
        }
        let inset = max(1, (frame.height - CGFloat(size) * 1.2) / 2)
        let caret = CGRect(x: min(max(frame.minX, x), frame.maxX - 1), y: frame.minY + inset,
                           width: 1, height: max(2, frame.height - inset * 2))
        let caretColor = object.attributes["color"].flatMap(resolvedColor) ?? palette.listText
        context.setFillColor(caretColor.cgColor)
        context.fill(caret)
    }

    private func drawText(_ object: WasabiObject, frame: CGRect, context: CGContext) {
        // Content resolution (`display=`, a songticker's implicit track title, `setAlternateText`)
        // is shared with the measurement a script's `getAutoWidth()` gets — see `WasabiTextMetrics`.
        drawText(WasabiTextMetrics.content(of: object, host: host),
                 object: object, frame: frame, context: context)
    }

    /// `undeclaredColor` is what a text object that names no `color=` draws in. White for everything
    /// the skin lays out itself — Wasabi's own default, and what the corpus is drawn against — but an
    /// `<edit>` is different: Winamp fills it with a native child window whose text is
    /// `wasabi.list.text`, the same colour the lists take (Big Bento says so in its own markup:
    /// *"lists/trees item foreground (also edit text)"*). Left as white, a search box typed into a
    /// Light skin wrote white on white.
    private func drawText(_ text: String, object: WasabiObject, frame rawFrame: CGRect,
                          context: CGContext, undeclaredColor: NSColor = .white) {
        // `leftpadding`/`rightpadding` inset the text inside its own rect. They are part of the width
        // a script measures with `getAutoWidth()`, so honouring them here is what makes a box sized
        // from that measurement fit the string it was sized for (ClassicPro's menu bar and SUI tabs).
        let left = CGFloat(Double(object.attributes["leftpadding"] ?? "0") ?? 0)
        let right = CGFloat(Double(object.attributes["rightpadding"] ?? "0") ?? 0)
        let frame = CGRect(x: rawFrame.minX + left, y: rawFrame.minY,
                           width: max(0, rawFrame.width - left - right), height: rawFrame.height)
        if let fontID = object.attributes["font"],
           let definition = loadedSkin.runtime.resources.resolvedDefinition(identifier: fontID),
           definition.kind == "bitmapfont" {
            drawBitmapText(text, definition: definition, object: object, frame: frame, context: context)
            return
        }
        // A skin (or one of its scripts) can name any point size at all, including 0, a negative, or
        // something that does not parse. CoreText builds its own attribute dictionary from whatever
        // it is handed, and an unusable size or font there aborts the process from inside a draw.
        let size = WasabiTextMetrics.pointSize(of: object)
        let font = resources.font(identifier: object.attributes["font"], size: size,
                                  traits: WasabiTextMetrics.traits(of: object))
            ?? NSFont.systemFont(ofSize: size)
        // Optional for the same reason as the font: nothing that ends up in a CoreText attribute
        // dictionary may be a null pointer, and only an `Optional` binding can see one.
        let resolved: NSColor? = object.attributes["color"].flatMap(resolvedColor)
        let color = resolved ?? undeclaredColor
        let alignment: NSTextAlignment
        switch object.attributes["align"]?.lowercased() {
        case "center": alignment = .center
        case "right": alignment = .right
        default: alignment = .left
        }
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = alignment
        paragraph.lineBreakMode = .byClipping
        var attributes: [NSAttributedString.Key: Any] = [
            .font: font, .foregroundColor: color, .paragraphStyle: paragraph
        ]
        // `forcefixed` is a different layout, not a different font: every glyph gets the same cell.
        // A fixed run is a clock or a counter and is sized to fit, so it never enters the ticker.
        let pitch = WasabiTextMetrics.fixedPitch(of: object, font: font)
        // A clock is laid out in fields with their own cells, which is a third layout again — and it
        // is sized to fit for the same reason a fixed run is, so it never scrolls either.
        let clock = WasabiTextMetrics.clockRun(of: object, text: text, font: font)
        let measured = clock?.width ?? pitch?.width(of: text)
            ?? (text as NSString).size(withAttributes: attributes).width
        let overflow = pitch == nil && clock == nil ? measured - frame.width : 0
        let scroll = overflow > 0 ? tickerMotion(for: object, overflow: overflow, textWidth: measured) : nil
        if scroll != nil {
            // While scrolling, the string is drawn into an oversized rect, so any alignment other
            // than left would re-centre it inside that rect and cancel the motion out.
            paragraph.alignment = .left
            attributes[.paragraphStyle] = paragraph
        }

        // Wasabi centres a string in its box unless `valign=` says otherwise; `NSString.draw(in:)`
        // starts at the box's top edge, which is `valign="top"` and nothing else. The difference is a
        // whole line's leading on a tall box (Love is War Miku's 30px time readout) and enough on a
        // tight one to push the song ticker's descenders onto the seek bar below it. Under the local
        // mirror below, a rect's *top* edge is its `maxY`, so lowering the text by `inset` means
        // moving the rect down the same amount. Clamped at zero: a string taller than its own box
        // starts at the top rather than above it, whatever it asked for.
        let cell = font.ascender - font.descender
        let inset = max(0, WasabiTextMetrics.verticalAlignment(of: object)
            .offset(cell: cell, in: frame.height))
        // `offsetx`/`offsety` shift the *string* inside its own box without moving the box — so the
        // object still measures and hit-tests where it was declared, and its parent still clips it
        // where it was. Big Bento Modern's SUI tab labels are the measured case: `offsetx="35"` puts
        // the label clear of the 40px icon, which in the icons-only tab mode (a 40px-wide strip) is
        // also what pushes it entirely outside the clip. Ignoring the attribute drew every tab's
        // caption straight over its own icon.
        let offsetX = CGFloat(Double(object.attributes["offsetx"] ?? "0") ?? 0)
        let offsetY = CGFloat(Double(object.attributes["offsety"] ?? "0") ?? 0)
        let drawFrame = frame.offsetBy(dx: offsetX, dy: -inset - offsetY)
        // …and when the shift lands the string's own origin in the **last pixel column** of what is
        // still visible, the skin means it to be gone, not to leave a sliver. Big Bento Modern's SUI
        // tab captions land exactly there in the icons-only mode: `offsetx="35"` on a box at x=4
        // starts the string on column 39 of a 40px strip, so a glyph with no left side bearing (`V`,
        // `W`) paints one bright column beside its icon and one of antialiasing beside that, and each
        // caption's first letter decides how much — which is what made the strip look notched. A
        // single column of a 24px letter is never information; it is the fringe of a string the
        // clip was meant to swallow.
        if scroll == nil, alignment == .left {
            let visible = context.boundingBoxOfClipPath.intersection(frame)
            if !visible.isNull, drawFrame.minX >= visible.maxX - 1 { return }
        }

        context.saveGState()
        context.clip(to: frame)
        context.translateBy(x: 0, y: frame.midY)
        context.scaleBy(x: 1, y: -1)
        context.translateBy(x: 0, y: -frame.midY)
        if let scroll {
            var textFrame = drawFrame
            textFrame.origin.x -= scroll.offset
            textFrame.size.width = measured
            (text as NSString).draw(in: textFrame, withAttributes: attributes)
            if scroll.wraps {
                // Continuous mode runs the tail off the left edge, so draw a second copy a gap
                // behind it; otherwise the ticker would blank out between cycles.
                textFrame.origin.x += measured + Self.tickerGap
                (text as NSString).draw(in: textFrame, withAttributes: attributes)
            }
        } else if let clock {
            // The run keeps a pixel or two of clearance from the edge it is aligned against — a skin
            // that puts a separator beside a readout counts on it, and centring needs none because
            // both edges are already free.
            // Aligned by the room the clock holds, then drawn from that room's left edge — so the
            // digits stay in their columns rather than shuffling when the value gains one.
            let room = clock.layoutWidth
            var origin: CGFloat
            switch alignment {
            case .right: origin = drawFrame.maxX - WasabiTextMetrics.ClockRun.edgeInset - room
            case .center: origin = drawFrame.minX + (drawFrame.width - room) / 2
            default: origin = drawFrame.minX + WasabiTextMetrics.ClockRun.edgeInset
            }
            // Each cell places its own field, so the object's alignment must not apply a second time
            // inside one.
            let centred = attributes.merging([.paragraphStyle: centredParagraph]) { _, new in new }
            let leading = attributes.merging([.paragraphStyle: leadingParagraph]) { _, new in new }
            for cell in clock.cells {
                (cell.text as NSString).draw(
                    in: CGRect(x: origin, y: drawFrame.minY, width: cell.width, height: drawFrame.height),
                    withAttributes: cell.centred ? centred : leading)
                origin += cell.width
            }
        } else if let pitch {
            var origin: CGFloat
            switch alignment {
            case .right: origin = drawFrame.maxX - measured
            case .center: origin = drawFrame.midX - measured / 2
            default: origin = drawFrame.minX
            }
            // Each glyph is centred in its own cell, which is what keeps a `1` in the same column as
            // an `8` — the point of asking for fixed pitch in the first place.
            let cellAttributes = attributes.merging([.paragraphStyle: centredParagraph]) { _, new in new }
            for character in text {
                let width = character == ":" ? pitch.colon : pitch.cell
                (String(character) as NSString).draw(
                    in: CGRect(x: origin, y: drawFrame.minY, width: width, height: drawFrame.height),
                    withAttributes: cellAttributes)
                origin += width
            }
        } else {
            (text as NSString).draw(in: drawFrame, withAttributes: attributes)
        }
        context.restoreGState()
    }

    /// Starts a clock's field at its own cell's left edge.
    private var leadingParagraph: NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.alignment = .left
        style.lineBreakMode = .byClipping
        return style
    }

    /// Centres a single glyph inside its fixed-pitch cell.
    private var centredParagraph: NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.alignment = .center
        style.lineBreakMode = .byClipping
        return style
    }

    /// Gap between the repeats of a continuously scrolling ticker, in skin pixels.
    private static let tickerGap: CGFloat = 40
    /// Ticker scroll speed, in skin pixels per second.
    private static let tickerSpeed: Double = 30

    /// How far to shift an over-long string this frame, and whether the motion wraps.
    ///
    /// `ticker="bounce"` slides to the end and back; any other enabled value scrolls continuously.
    /// A `songticker` scrolls by default — that is the whole point of the object — while a plain
    /// `text` only scrolls when it opts in, so static labels stay put.
    private func tickerMotion(for object: WasabiObject, overflow: CGFloat,
                              textWidth: CGFloat) -> (offset: CGFloat, wraps: Bool)? {
        let isSongticker = object.typeName.caseInsensitiveCompare("songticker") == .orderedSame
        let mode = (object.attributes["ticker"] ?? (isSongticker ? "1" : "0")).lowercased()
        guard !["0", "off", "false", "no"].contains(mode) else { return nil }
        if mode == "bounce" {
            let span = Double(overflow)
            let cycle = span * 2
            guard cycle > 0 else { return nil }
            let phase = (clock() * Self.tickerSpeed).truncatingRemainder(dividingBy: cycle)
            return (CGFloat(phase <= span ? phase : cycle - phase), false)
        }
        // One cycle carries the string its own width plus the gap, at which point the trailing copy
        // has taken its place exactly.
        let cycle = Double(textWidth + Self.tickerGap)
        guard cycle > 0 else { return nil }
        return (CGFloat((clock() * Self.tickerSpeed).truncatingRemainder(dividingBy: cycle)), true)
    }

    private func drawBitmapText(_ text: String, definition: WalResourceDefinition,
                                object: WasabiObject, frame: CGRect, context: CGContext) {
        let alignment: NSTextAlignment
        switch object.attributes["align"]?.lowercased() {
        case "center": alignment = .center
        case "right": alignment = .right
        default: alignment = .left
        }
        drawBitmapText(text, definition: definition, frame: frame, alignment: alignment,
                       verticalAlignment: WasabiTextMetrics.verticalAlignment(of: object),
                       ticker: object, context: context)
    }

    /// Draw a run of bitmap-font glyphs. `ticker` is the object whose scroll state applies, or nil for
    /// content NullPlayer draws itself (a playlist row never scrolls).
    private func drawBitmapText(_ text: String, definition: WalResourceDefinition, frame: CGRect,
                                alignment: NSTextAlignment,
                                verticalAlignment: WasabiTextMetrics.VerticalAlignment = .center,
                                ticker: WasabiObject?, context: CGContext) {
        guard let sheet = resources.fontSheet(for: definition) else { return }
        let charWidth = max(1, Int(Double(definition.attributes["charwidth"] ?? "1") ?? 1))
        let charHeight = max(1, Int(Double(definition.attributes["charheight"] ?? "1") ?? 1))
        let spacing = Int(Double(definition.attributes["hspacing"] ?? "0") ?? 0)
        let advance = max(1, charWidth + spacing)
        // Winamp's bitmap-font sheet is three rows of glyphs. The accented row used to be appended to
        // the second one, which put it past column 32 — outside every real sheet, so those glyphs
        // cropped out of bounds and drew nothing.
        // The two trailing spaces are load-bearing: they map the space character onto a blank cell of
        // the sheet's first row rather than onto its fallback, glyph (0, 0).
        let mapRows = [Array("abcdefghijklmnopqrstuvwxyz\"@  "),
                       Array("0123456789….:()-'!_+\\/[]^&%,=$#"),
                       Array("âöä?*")]
        var positions: [Character: (Int, Int)] = [:]
        for (row, characters) in mapRows.enumerated() {
            for (column, character) in characters.enumerated() { positions[character] = (column, row) }
        }
        let width = CGFloat(text.count * advance)
        var startX: CGFloat
        switch alignment {
        case .center: startX = frame.midX - width / 2
        case .right: startX = frame.maxX - width
        default: startX = frame.minX
        }
        // Bitmap-font tickers share the TrueType path's motion model. The previous formula anchored
        // the run at `frame.maxX`, so at rest the text sat entirely off the right edge and a long
        // title simply vanished instead of scrolling.
        var repeats: [CGFloat] = []
        if width > frame.width, let ticker,
           let scroll = tickerMotion(for: ticker, overflow: width - frame.width, textWidth: width) {
            startX = frame.minX - scroll.offset
            repeats = scroll.wraps ? [width + Self.tickerGap] : []
        }

        // A sheet's glyphs are a fixed `charheight` tall, so the run's vertical placement is one
        // offset for the whole line. The scene is drawn top-origin (see `draw(in:)`), so this is a
        // distance down from `minY` — it was pinned there, which is `valign="top"` and only correct
        // for the 54 declarations that ask for it. Rounded: a glyph is a blit, and a half-pixel
        // origin resamples an LED readout into a blur. Clamped at zero for the same reason as the
        // Core Text path: a sheet whose glyphs are taller than the box keeps their tops.
        let top = frame.minY + max(0, verticalAlignment
            .offset(cell: CGFloat(charHeight), in: frame.height).rounded())

        context.saveGState()
        context.clip(to: frame)
        for origin in [CGFloat.zero] + repeats {
            var x = startX + origin
            for character in text.lowercased() {
                let (column, row) = positions[character] ?? positions[" "] ?? (0, 0)
                // Top-left origin: `cropping(to:)` indexes pixel rows directly (see `bitmap(identifier:)`).
                let cropRect = CGRect(x: column * charWidth, y: row * charHeight,
                                      width: charWidth, height: charHeight)
                if x + CGFloat(advance) >= frame.minX, x <= frame.maxX,
                   cropRect.maxY <= CGFloat(sheet.height), cropRect.maxX <= CGFloat(sheet.width),
                   let glyph = cropped(sheet.image, to: cropRect) {
                    drawImage(glyph, in: CGRect(x: x, y: top,
                                                width: CGFloat(charWidth), height: CGFloat(charHeight)),
                              context: context)
                }
                x += CGFloat(advance)
            }
        }
        context.restoreGState()
    }

    /// Largest warped surface, per axis. A warp is a CPU resample of the whole layer, so the work is
    /// its area; every FX layer measured in the corpus is a few hundred pixels square (Defix's
    /// needles are 264×264), and this is the ceiling that keeps a skin asking for a full-window warp
    /// off the frame budget.
    private static let maximumWarpExtent = 1_024

    /// Draw `image` warped by `mesh`, filling `rect`. Returns false when the warp could not be built,
    /// so the caller can fall back to the layer's ordinary draw rather than paint nothing.
    ///
    /// The mesh gives the source coordinate at each grid **vertex**; every destination pixel takes
    /// its source from the bilinear interpolation of the four vertices around it. A rotation is
    /// affine in x/y, so a 1×1 grid — Defix's cassette reels — reproduces one exactly, and a warp
    /// that is not affine gets as much fidelity as the grid the skin asked for.
    @discardableResult
    private func drawWarped(_ image: CGImage, in rect: CGRect, mesh: WasabiLayerFXMesh,
                            context: CGContext) -> Bool {
        let width = min(Self.maximumWarpExtent, max(1, Int(rect.width.rounded())))
        let height = min(Self.maximumWarpExtent, max(1, Int(rect.height.rounded())))
        let key = WarpSourceKey(image: ObjectIdentifier(image), width: width, height: height)
        // The resample is the expensive half of the warp and it depends on nothing but the source
        // raster and the mesh. A repaint the *skin* did not ask for — the window invalidating a rect
        // for its own reasons, a neighbouring object moving, a partial repaint being widened by
        // AppKit — would otherwise re-run the whole pixel loop for a warp that has not moved a
        // vertex since the last frame.
        if let cached = warpedImageCache[key], cached.mesh == mesh {
            drawImage(cached.image, in: rect, context: context)
            return true
        }
        guard let source = warpSourcePixels(image, width: width, height: height),
              let warpedPixels = mesh.resample(source: source, width: width, height: height),
              let warped = Self.image(fromPixels: warpedPixels, width: width, height: height)
        else { return false }
        // Bounded for the same reason as `warpSourceCache`: one entry per FX layer, and a skin has a
        // handful of them.
        if warpedImageCache.count > 16 { warpedImageCache.removeAll() }
        warpedImageCache[key] = (image, mesh, warped)
        drawImage(warped, in: rect, context: context)
        return true
    }

    /// The last warped raster per FX layer, with the mesh it was built from.
    private var warpedImageCache: [WarpSourceKey: (source: CGImage, mesh: WasabiLayerFXMesh, image: CGImage)] = [:]

    /// The layer's own image rasterized at the size it draws at, in top-left row order — the space
    /// the mesh's normalized coordinates are in. Cached: the source only changes when the layer's
    /// bitmap or its box does, while the mesh changes every frame a meter moves.
    private func warpSourcePixels(_ image: CGImage, width: Int, height: Int) -> [UInt8]? {
        let key = WarpSourceKey(image: ObjectIdentifier(image), width: width, height: height)
        if let cached = warpSourceCache[key] { return cached.pixels }
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let drawn = pixels.withUnsafeMutableBytes { bytes -> Bool in
            guard let context = CGContext(data: bytes.baseAddress, width: width, height: height,
                                          bitsPerComponent: 8, bytesPerRow: width * 4,
                                          space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            else { return false }
            context.interpolationQuality = WasabiBitmapInterpolationPolicy.quality(
                sourceWidth: image.width, sourceHeight: image.height,
                destinationWidth: width, destinationHeight: height)
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { return nil }
        // Bounded: a handful of FX layers per skin, and one entry each. Cleared wholesale rather than
        // aged, because the only thing that invalidates an entry is the layer being redrawn at a
        // different size, which happens on resize and theme changes.
        if warpSourceCache.count > 16 { warpSourceCache.removeAll() }
        warpSourceCache[key] = (image, pixels)
        return pixels
    }

    private struct WarpSourceKey: Hashable {
        let image: ObjectIdentifier
        let width: Int
        let height: Int
    }

    private static func image(fromPixels pixels: [UInt8], width: Int, height: Int) -> CGImage? {
        var pixels = pixels
        return pixels.withUnsafeMutableBytes { bytes -> CGImage? in
            guard let context = CGContext(data: bytes.baseAddress, width: width, height: height,
                                          bitsPerComponent: 8, bytesPerRow: width * 4,
                                          space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            else { return nil }
            return context.makeImage()
        }
    }

    /// The single image a bitmap layer paints right now: an animated layer's current frame, or the
    /// whole bitmap for a plain one. Shared with the Layer FX path, which warps exactly that image.
    private func layerImage(_ bitmap: WasabiBitmap, object: WasabiObject, type: String) -> CGImage? {
        guard type == "animatedlayer" else { return bitmap.image }
        return animatedFrameImage(bitmap, object: object)
    }

    /// How an animated layer's sheet is cut into frames: one frame's size, how many there are, and how
    /// many sit side by side. Shared by the frame the layer draws and the region it can be clicked on.
    private func animationGrid(_ bitmap: WasabiBitmap,
                               object: WasabiObject) -> (width: Int, height: Int, count: Int, columns: Int) {
        let frameWidth = max(1, Int(Double(object.attributes["framewidth"] ?? object.attributes["w"] ?? "") ?? Double(bitmap.width)))
        let frameHeight = max(1, Int(Double(object.attributes["frameheight"] ?? object.attributes["h"] ?? "") ?? Double(bitmap.height)))
        let columns = max(1, bitmap.width / frameWidth)
        let rows = max(1, bitmap.height / frameHeight)
        let count = max(1, Int(Double(object.attributes["frames"] ?? "") ?? Double(columns * rows)))
        return (frameWidth, frameHeight, count, columns)
    }

    /// The most opaque any frame is at `point` — the layer's region, see the call site in `object(at:)`.
    private func animationUnionAlpha(_ bitmap: WasabiBitmap, object: WasabiObject,
                                     node: WasabiSceneNode, point: CGPoint) -> Int {
        let grid = animationGrid(bitmap, object: object)
        let x = (point.x - node.frame.minX) / max(1, node.frame.width) * CGFloat(grid.width)
        let y = (point.y - node.frame.minY) / max(1, node.frame.height) * CGFloat(grid.height)
        var strongest = 0
        for index in 0..<grid.count {
            let origin = CGPoint(x: CGFloat((index % grid.columns) * grid.width),
                                 y: CGFloat((index / grid.columns) * grid.height))
            strongest = max(strongest, Int(bitmap.alpha(at: CGPoint(x: origin.x + x, y: origin.y + y))))
            if strongest > Self.regionAlphaFloor { break }
        }
        return strongest
    }

    private func animatedFrameImage(_ bitmap: WasabiBitmap, object: WasabiObject) -> CGImage? {
        let (frameWidth, frameHeight, count, columns) = animationGrid(bitmap, object: object)
        let frameIndex = max(0, min(count - 1, WasabiAnimation.state(of: object, frameCount: count,
                                                                     clock: clock()).frame))
        let column = frameIndex % columns
        let row = frameIndex / columns
        let crop = CGRect(x: column * frameWidth, y: row * frameHeight,
                          width: frameWidth, height: frameHeight)
        guard crop.maxY <= CGFloat(bitmap.height), crop.maxX <= CGFloat(bitmap.width) else { return nil }
        return cropped(bitmap.image, to: crop)
    }

    /// One sub-rectangle of a sheet, **stably**. `CGImage.cropping(to:)` allocates a fresh image on
    /// every call, so a glyph or an animation frame had a different object identity each frame — and
    /// every cache downstream of it (the pre-scaled raster, the warp's source raster) is keyed by
    /// exactly that identity. Without this, drawing an animated layer or a line of bitmap-font text
    /// missed those caches on every frame *and* churned them, which is worse than not caching at all.
    private func cropped(_ image: CGImage, to rect: CGRect) -> CGImage? {
        let key = CropKey(image: ObjectIdentifier(image), x: Int(rect.minX), y: Int(rect.minY),
                          width: Int(rect.width), height: Int(rect.height))
        if let cached = cropCache[key] { return cached.crop }
        guard let crop = image.cropping(to: rect) else { return nil }
        // The source is held with the entry: an `ObjectIdentifier` is an address, and an address that
        // has been freed can come back attached to a different image.
        if cropCache.count > Self.maximumCachedCrops { cropCache.removeAll() }
        cropCache[key] = (image, crop)
        return crop
    }

    /// A bitmap font is one entry per glyph per sheet; an animation, one per frame. A few hundred
    /// covers every skin measured and is a few hundred *references*, not pixels — a crop shares its
    /// parent's backing store.
    private static let maximumCachedCrops = 512
    private var cropCache: [CropKey: (source: CGImage, crop: CGImage)] = [:]

    private struct CropKey: Hashable {
        let image: ObjectIdentifier
        let x: Int
        let y: Int
        let width: Int
        let height: Int
    }

    private func drawAnimated(_ bitmap: WasabiBitmap, object: WasabiObject,
                              frame: CGRect, context: CGContext) {
        guard let image = animatedFrameImage(bitmap, object: object) else { return }
        drawImage(image, in: frame, context: context)
    }

    /// `<vis mode>` — which visualization the skin wants in this box, and whether it wants one at all.
    ///
    /// `1` is the **spectrum analyzer** and `2` the **oscilloscope**; `0`/`3` are off, and an
    /// undeclared mode is the analyzer. A skin's own menu script pins the pairing beyond doubt:
    /// Love is War Miku's `visualizer.maki` sets `bandwidth` (`wide`/`thin`) then `setMode(1)` for its
    /// Spectrum Analyzer commands, and `oscstyle` (`Solid`/`Dots`/`Lines`) then `setMode(2)` for its
    /// Oscilloscope ones. Reversed, every skin drew the other visualization than the one its menu had
    /// just been asked for — and this skin's shipped default (`Visualizer Mode` = 1) came up as an
    /// oscilloscope where its own screenshot shows bars.
    ///
    /// MMD3's `ShowVISBg` switches between all three and ships `mode="3"`, its own animated display,
    /// which is why an unrecognized mode must stay silent rather than paint over the skin's artwork.
    /// `setMode` writes the same attribute.
    /// The mode itself lives in `WasabiVisualizationMode` (`WinampModernHostActions.swift`), because
    /// `VIS_NEXT`/`VIS_PREV`/`VIS_MENU` write the same attribute this reads — the drawing and the
    /// host actions must not hold two ideas of what `mode="2"` means.

    // MARK: - The skin's own `<vis>` boxes, as the host actions see them

    /// Every `<vis>` in the skin's graph — not only the ones in the active layout.
    ///
    /// Whole graph on purpose: a skin draws its visualization in several layouts (normal, shade,
    /// and MMD3's drawer), and `VIS_NEXT` in one of them must not leave the others showing the mode
    /// the user just stepped away from.
    func visualizationObjects() -> [WasabiObject] {
        loadedSkin.runtime.graph.allObjectsUnordered.filter {
            $0.typeName.caseInsensitiveCompare("vis") == .orderedSame
        }
    }

    /// What the skin's visualization is showing, or `nil` when the skin declares no `<vis>` at all
    /// (Defix, whose VIS buttons are a toolbar over the host's own visualization window).
    var visualizationMode: WasabiVisualizationMode? {
        guard let object = visualizationObjects().first else { return nil }
        return WasabiVisualizationMode(attribute: object.attributes["mode"])
    }

    /// `wide` (Winamp's fat blocks) or `thin` (the full comb), the analyzer's only real option.
    var analyzerBandwidthIsThin: Bool {
        visualizationAttribute("bandwidth")?.lowercased() == "thin"
    }

    /// One `<vis>` attribute as the skin currently has it — what a menu ticks its current entry from.
    /// The first box's, because `setVisualizationAttribute` writes them all together.
    func visualizationAttribute(_ name: String) -> String? {
        visualizationObjects().first?.attributes[name]
    }

    @discardableResult
    func setVisualizationMode(_ mode: WasabiVisualizationMode) -> Bool {
        setVisualizationAttribute("mode", value: mode.attributeValue)
    }

    /// Write one attribute across every `<vis>`, reporting whether anything actually moved so the
    /// caller can skip the repaint.
    @discardableResult
    func setVisualizationAttribute(_ name: String, value: String) -> Bool {
        var changed = false
        for object in visualizationObjects() where object.setAttribute(name, value: value) {
            changed = true
        }
        if changed {
            invalidateSceneCache()
            refreshWaveformDemand()
        }
        return changed
    }

    /// Does anything in this skin want the host's PCM tap running?
    ///
    /// **Any** `<vis>` in the graph, not all of them: one scope among Big Bento's five analyzers
    /// still needs the waveform. Whole-graph for the same reason `visualizationObjects()` is — a skin
    /// draws its visualization in several layouts, and every `WasabiSceneRenderer` in the skin shares
    /// one `loadedSkin.runtime.graph`, so each of them computes the same answer and the host does not
    /// have to refcount per renderer.
    ///
    /// Cached against the graph's own mutation counter rather than recomputed per draw:
    /// `visualizationObjects()` is an uncached filter over every object in the graph, and this is
    /// asked once per frame. Not from `invalidateSceneCache()` either — that runs on every playback
    /// tick, which the graph's generation does not move for. **The `mode` attribute has two writers**:
    /// `setVisualizationAttribute` (the host's own menus) and MAKI's `setMode`/`setXmlParam`, which
    /// write the object directly — Big Bento's visualization menu is entirely the second kind — and
    /// both bump `sceneGeneration`, which is what makes it the right key.
    func refreshWaveformDemand() {
        let generation = loadedSkin.runtime.graph.sceneGeneration
        if let waveformDemand, waveformDemand.generation == generation { return }
        // Resolved once, not once per box: `visRenderer` is a lookup through the skin's runtime now
        // that the engine is selectable (B53).
        let renderer = visRenderer
        let needed = visualizationObjects().contains {
            renderer.needsWaveform(forMode: WasabiVisualizationMode(attribute: $0.attributes["mode"]))
        }
        let changed = waveformDemand?.needed != needed
        waveformDemand = (generation, needed)
        // Pushed only on a change, though `setWaveformNeeded` is idempotent regardless.
        if changed { host.setWaveformNeeded(needed) }
    }

    /// Whether any box in this skin is a PCM-fed visualization, as of the last `refreshWaveformDemand`
    /// — the window reads it to decide how fast its visualization clock has to run.
    var visualizationNeedsWaveform: Bool { waveformDemand?.needed ?? false }

    private var waveformDemand: (generation: UInt64, needed: Bool)?
    /// The waveform every `<vis>` in *this* frame draws from. See `draw(in:)`.
    private var frameWaveform: (left: [UInt8], right: [UInt8])?

    /// The `{0000000A}` holder fallback's falling caps, keyed by object, in bar fractions. Decayed
    /// once per draw — that surface has no `<vis>` to take a `peakfalloff` from, by design, and is
    /// left as it was.
    private var analyzerPeaks: [WasabiObjectID: [CGFloat]] = [:]
    /// How far one of those caps falls per frame. At the scene's redraw rate this is roughly the drop
    /// Winamp's own caps have — fast enough to follow a track, slow enough to read as a cap.
    private static let analyzerPeakDecay: CGFloat = 0.015

    /// What actually paints a `<vis>` box (`WasabiVisPainter.swift`) — Winamp's own analyzer and
    /// oscilloscope, or one of NullPlayer's (B53). Behind a protocol because each of those engines
    /// is a renderer of the same shape; it owns the bar and cap decay state, keyed by object, which
    /// used to live here as `analyzerPeaks`.
    ///
    /// Held on the **skin's runtime**, not here: one skin's boxes are spread across several
    /// containers and several `WasabiSceneRenderer`s, and they must all draw the same engine from
    /// the same per-object state.
    var visRenderer: WasabiVisRenderer {
        loadedSkin.runtime.spectrumAnalyzer.renderer(in: loadedSkin.configuration)
    }

    /// Which engine is drawing this skin's `<vis>` boxes.
    var spectrumAnalyzer: WinampModernSpectrumAnalyzer {
        loadedSkin.runtime.spectrumAnalyzer.suite(in: loadedSkin.configuration)
    }

    /// Every NullPlayer engine's own controls, for the menus that offer them.
    func spectrumAnalyzerMenus() -> [(suite: WinampModernSpectrumAnalyzer, menu: NSMenu)] {
        loadedSkin.runtime.spectrumAnalyzer.optionMenus()
    }

    /// The `<vis>` box under a point, **whatever is stacked on top of it**.
    ///
    /// Deliberately not `object(at:)`, which answers the topmost object and is the right answer for
    /// a click: a skin is free to cover its visualization with a layer that claims the mouse, and Big
    /// Bento Modern does — `main.vis.trigger` is an invisible layer over the whole header group,
    /// carrying the skin's own visualization settings page. This asks the other question, "is the
    /// user pointing at the visualization", which is what decides whether the engine picker belongs
    /// in the menu about to open there.
    func visualizationObject(at point: CGPoint) -> WasabiObject? {
        sceneNodes().last {
            $0.object.typeName.caseInsensitiveCompare("vis") == .orderedSame
                && $0.frame.contains(point)
        }?.object
    }

    /// Change engines, reporting whether anything moved so the caller can skip the repaint.
    ///
    /// The waveform demand has to be recomputed by hand here. It is cached against the graph's own
    /// generation — the right key for a `mode` write, which is a graph write — but an engine change
    /// is not a graph write at all: swapping Winamp's analyzer for vis_classic turns the PCM tap
    /// *on* without a single attribute moving, so the cached answer has to be dropped rather than
    /// re-derived.
    @discardableResult
    func setSpectrumAnalyzer(_ suite: WinampModernSpectrumAnalyzer) -> Bool {
        guard loadedSkin.runtime.spectrumAnalyzer.select(suite, in: loadedSkin.configuration) else {
            return false
        }
        invalidateWaveformDemand()
        invalidateSceneCache()
        return true
    }

    /// Drop the cached waveform demand and work it out again.
    ///
    /// For the engine change above, and for the other renderers of the same skin, which share the
    /// selection but each cache their own answer to it.
    func invalidateWaveformDemand() {
        waveformDemand = nil
        refreshWaveformDemand()
    }

    /// Whether any box still has a bar or a cap above the floor — what tells the window it can stop
    /// repainting once the audio has gone quiet.
    var hasDecayingVisualizationState: Bool { visRenderer.hasDecayingState }

    private func drawVisualization(_ object: WasabiObject, frame: CGRect, context: CGContext) {
        // Only the box's own size is a precondition here. The spectrum-levels check used to be, and
        // that gated the *oscilloscope* — which reads PCM — on the analyzer's input: with nothing
        // playing (`endVisualizationConsumption` clears the levels, and they are empty before the
        // first tap after a skin load) a scope could not even paint its flat centre line. It now
        // lives in the analyzer branch, where it belongs.
        guard frame.width > 0, frame.height > 0 else { return }
        // A skin colours its analyzer per band (`colorband1`…`colorband16`) **or** in one stroke with
        // `colorallbands`, and its oscilloscope with `colorosc1`…`colorosc5`. Reading only the
        // per-band form and defaulting to white painted Rika's spectrum as bright white bars across
        // the butterfly it sits on: that skin asks for `colorallbands="0,0,0"` at `alpha="50"`, a
        // dark shading over its own art.
        //
        // Through `objectColor`, not `resolvedColor`: these are inline `r,g,b` triples, and the
        // named-resource path leaves an inline triple untinted. Ujola Cat declares all 22 of its vis
        // colours inline under `gammagroup="Energy"`, so its analyzer stayed lime green through all
        // 38 of the skin's colour themes while everything around it recoloured. A named `<color>`
        // carries its own group and `objectColor` hands it back to `resolvedColor`, so nothing is
        // tinted twice.
        let gammaGroup = object.attributes["gammagroup"]
        let style = WasabiVisStyle.decode(attributes: object.attributes) {
            objectColor($0, gammaGroup: gammaGroup).cgColor
        }
        context.saveGState()
        defer { context.restoreGState() }
        // **One visualization across the row, not one per box** (B53), and only for NullPlayer's own
        // engines. A skin cuts its `<vis>` into as many boxes as its artwork needs: Big Bento Modern
        // declares `main.vis` and `main.vis2` side by side, 144px each, and Winamp's analyzer in each
        // of them — the left one mirrored — reads as one symmetric butterfly. Drop the mirror (which
        // no other engine can wear) and the same two boxes read as two identical copies of the same
        // spectrum, which is worse than either. So a suite engine is handed the **row's** rect and
        // clipped to this box: each box shows its own slice of one continuous analyzer, and the skin's
        // geometry is still exactly obeyed — nothing paints outside the box the author drew.
        var drawFrame = frame
        if spectrumAnalyzer != .skin {
            drawFrame = visualizationRowFrame(for: object, frame: frame)
            context.clip(to: frame)
        }
        // The frame's waveform, taken once in `draw(in:)`. A box drawn outside a full frame (a probe,
        // a golden image) falls back to asking the host directly.
        let waveform = visRenderer.needsWaveform(forMode: style.mode)
            ? (frameWaveform ?? host.waveformSamples)
            : (WinampModernWaveformTap.silence, WinampModernWaveformTap.silence)
        visRenderer.draw(WasabiVisInput(objectID: object.stableID, style: style,
                                        levels: host.spectrumLevels, waveform: waveform,
                                        sampleRate: host.sampleRateHz > 0
                                            ? Double(host.sampleRateHz) : 44_100),
                         in: drawFrame, context: context)
    }

    /// The rect one continuous visualization is drawn across for this box: the **run of `<vis>`
    /// boxes it sits in**, or its own frame when it stands alone.
    ///
    /// A run is boxes on the same line — same top edge, same height — that touch, within a couple of
    /// pixels of each other. That is deliberately narrow: it merges Big Bento's `main.vis` +
    /// `main.vis2` (144px each, adjacent, 288 together) and its two 10px reflection strips as a
    /// separate run of their own, while a skin that puts one `<vis>` in the player and another in a
    /// shade layout, or two at different sizes, keeps them apart. Boxes that merely *overlap* are a
    /// run too — Nullsoft.Winamp.2000.SP4.Lite declares the same box twice, and one analyzer across
    /// the pair is exactly right there as well.
    ///
    /// Computed once per frame and dropped with the frame's waveform: it walks the scene, and this is
    /// asked once per box.
    private func visualizationRowFrame(for object: WasabiObject, frame: CGRect) -> CGRect {
        if frameVisRows == nil { frameVisRows = computeVisualizationRows() }
        return frameVisRows?[object.stableID] ?? frame
    }

    private func computeVisualizationRows() -> [WasabiObjectID: CGRect] {
        Self.visualizationRows(boxes: sceneNodes().compactMap { node in
            guard node.object.typeName.caseInsensitiveCompare("vis") == .orderedSame,
                  node.frame.width > 0, node.frame.height > 0 else { return nil }
            return (node.object.stableID, node.frame)
        })
    }

    /// The run each box belongs to, as a pure function of the boxes — split out from the scene walk
    /// so the geometry can be asserted without a skin.
    static func visualizationRows(
        boxes: [(id: WasabiObjectID, frame: CGRect)]) -> [WasabiObjectID: CGRect] {
        guard boxes.count > 1 else { return [:] }
        // Same line, same height — a reflection strip is not part of the row it reflects.
        let lines = Dictionary(grouping: boxes) {
            LineKey(top: ($0.frame.minY).rounded(), height: ($0.frame.height).rounded())
        }
        var rows: [WasabiObjectID: CGRect] = [:]
        for (_, line) in lines {
            var run: [(id: WasabiObjectID, frame: CGRect)] = []
            func closeRun() {
                guard run.count > 1 else { return run.removeAll() }
                let union = run.dropFirst().reduce(run[0].frame) { $0.union($1.frame) }
                for box in run { rows[box.id] = union }
                run.removeAll()
            }
            for box in line.sorted(by: { $0.frame.minX < $1.frame.minX }) {
                if let previous = run.last,
                   box.frame.minX - previous.frame.maxX > Self.visualizationRowGap {
                    closeRun()
                }
                run.append(box)
            }
            closeRun()
        }
        return rows
    }

    /// How far apart two boxes may be and still be one visualization. Big Bento's pair is flush; a
    /// hairline is allowed for a skin that leaves a seam.
    private static let visualizationRowGap: CGFloat = 2

    private struct LineKey: Hashable {
        let top: CGFloat
        let height: CGFloat
    }

    /// This frame's box runs, alongside `frameWaveform` and cleared with it.
    private var frameVisRows: [WasabiObjectID: CGRect]?

    /// `<eqvis>` — the little curve a skin draws over its equalizer, from the current band gains.
    /// Winamp colours it with a top/middle/bottom triple plus a separate preamp line colour.
    private func drawEQVis(_ object: WasabiObject, frame: CGRect, context: CGContext) {
        guard frame.width > 1, frame.height > 1, let snapshot = componentHost?.equalizerSnapshot() else { return }
        let bands = snapshot.bandGainsDB
        guard !bands.isEmpty else { return }
        let top = resolvedColor(object.attributes["colortop"] ?? "0,255,0")
        let middle = resolvedColor(object.attributes["colormiddle"] ?? "255,255,0")
        let bottom = resolvedColor(object.attributes["colorbottom"] ?? "255,0,0")
        let preampColor = resolvedColor(object.attributes["colorpreamp"] ?? "255,255,255")

        context.saveGState()
        context.clip(to: frame)
        let step = frame.width / CGFloat(bands.count)
        for (index, gain) in bands.enumerated() {
            let normalized = CGFloat((gain + 12) / 24)             // 0…1, bottom to top
            let y = frame.maxY - normalized * frame.height
            let color = normalized > 0.66 ? top : (normalized < 0.33 ? bottom : middle)
            context.setFillColor(color.cgColor)
            context.fill(CGRect(x: frame.minX + CGFloat(index) * step, y: y - 1,
                                width: max(1, step - 1), height: 2))
        }
        let preamp = CGFloat((snapshot.preampDB + 12) / 24)
        context.setFillColor(preampColor.cgColor)
        context.fill(CGRect(x: frame.minX, y: frame.maxY - preamp * frame.height,
                            width: frame.width, height: 1))
        context.restoreGState()
    }

    /// Where a value-carrying object currently stands, 0…1. Shared by the slider thumb and the
    /// progress grid drawn under it so the two can never disagree about the same value.
    private func normalizedValue(of object: WasabiObject) -> CGFloat {
        let action = object.attributes["action"]?.lowercased()
        let normalized: CGFloat
        if action == "volume" {
            normalized = CGFloat(host.volume)
        } else if action == "seek", host.duration > 0 {
            normalized = CGFloat(host.currentTime / host.duration)
        } else if WinampModernPanAction.matches(action: action) {
            // Read back from the host, not from the drag, so a balance changed anywhere else moves
            // the skin's thumb — and so a skin that draws two balance sliders (multipass ships a real
            // one and a ghosted LED twin over it) cannot show two different positions.
            normalized = WinampModernPanAction.normalized(balance: host.balance)
        } else if let eq = WinampModernEQAction.decode(action: object.attributes["action"],
                                                       parameter: object.attributes["param"]),
                  let snapshot = componentHost?.equalizerSnapshot() {
            // The thumb reads the same snapshot the drag writes, so a preset applied from a menu (or
            // from outside the skin entirely) moves the slider.
            normalized = eq.normalizedValue(in: snapshot)
        } else {
            let low = Double(object.attributes["low"] ?? "0") ?? 0
            let high = Double(object.attributes["high"] ?? "255") ?? 255
            // A `cfgattrib`-bound slider stands where the *setting* stands, not where the last drag
            // left a local copy — so the thumb follows a crossfade length changed from NullPlayer's
            // own Fade Duration menu, and a value the host clamped shows the clamped position.
            let value = configValueProvider?(object).map(Double.init)
                ?? Double(object.attributes["value"] ?? "0") ?? 0
            normalized = high == low ? 0 : CGFloat((value - low) / (high - low))
        }
        return max(0, min(1, normalized))
    }

    /// `<ProgressGrid>` — the *filled* part of a bar, drawn as `left` cap + stretched `middle` +
    /// `right` cap growing from the edge `orientation` names.
    ///
    /// A skin pairs one with a `<slider>` over the same rect and gives the slider a thumb that is
    /// deliberately invisible — Love is War Miku's seek "thumb" is a 1×1 pixel, and the grid is the
    /// only thing that shows a position at all. Drawing nothing for the grid left its seek bar an
    /// empty white box with no indication of progress anywhere in the window.
    ///
    /// The grid carries no `action` of its own there, so the value comes from the sibling that does:
    /// pairing them by rect is the whole idiom.
    private func drawProgressGrid(_ object: WasabiObject, frame: CGRect, context: CGContext) {
        guard frame.width > 0, frame.height > 0 else { return }
        let source = object.attributes["action"] != nil ? object : (valueSibling(of: object) ?? object)
        let clamped = normalizedValue(of: source)
        let left = resources.bitmap(identifier: object.attributes["left"])
        let middle = resources.bitmap(identifier: object.attributes["middle"])
        let right = resources.bitmap(identifier: object.attributes["right"])
        guard left != nil || middle != nil || right != nil else { return }

        // `orientation` names the direction the fill *grows*, so it is also the edge it is anchored
        // to. Skins spell it both ways round and in both axes; the vertical forms anchor the same way.
        let orientation = object.attributes["orientation"]?.lowercased() ?? "right"
        let vertical = orientation == "up" || orientation == "down" || orientation == "vertical"
        let reversed = orientation == "left" || orientation == "up"
        let span = (vertical ? frame.height : frame.width) * clamped
        guard span > 0 else { return }
        let filled: CGRect
        if vertical {
            filled = CGRect(x: frame.minX, y: reversed ? frame.maxY - span : frame.minY,
                            width: frame.width, height: span)
        } else {
            filled = CGRect(x: reversed ? frame.maxX - span : frame.minX, y: frame.minY,
                            width: span, height: frame.height)
        }

        context.saveGState()
        context.clip(to: filled)
        // The caps keep their own size and the middle takes everything between them, which is what
        // makes a one-pixel `middle` stretch across the whole elapsed span.
        var body = filled
        if let left {
            let width = min(CGFloat(left.width), body.width)
            drawImage(left.image, in: CGRect(x: body.minX, y: body.minY,
                                             width: width, height: body.height), context: context)
            body = CGRect(x: body.minX + width, y: body.minY,
                          width: body.width - width, height: body.height)
        }
        if let right {
            let width = min(CGFloat(right.width), body.width)
            drawImage(right.image, in: CGRect(x: body.maxX - width, y: body.minY,
                                              width: width, height: body.height), context: context)
            body = CGRect(x: body.minX, y: body.minY,
                          width: body.width - width, height: body.height)
        }
        if let middle, body.width > 0, body.height > 0 {
            draw(middle, object: object, frame: body, context: context)
        }
        context.restoreGState()
    }

    /// `<grid>` — nine-slice chrome: the element every framed surface in a Bento-style skin is made of.
    ///
    /// The corners keep their own size, the four edges stretch (or tile) along one axis only, and
    /// `middle` fills what is left. Every part is optional and a grid carries no `image` of its own, so
    /// before this it fell through to the bitmap fallback and drew **nothing** — which is why
    /// cPro-Bento's tab pills read as bare text on black, and its SUI sheet, playlist box, mini-view
    /// strip and seek track as flat black holes. 49 of them in that skin's include graph alone.
    ///
    /// A grid with only the three `top*` parts is a horizontal three-slice (the tab pills, and the
    /// engine's `left`/`middle`/`right` seek track is the same thing rotated); its absent rows take no
    /// height, rather than a missing `middle` being stretched over everything.
    private func drawGrid(_ object: WasabiObject, frame: CGRect, context: CGContext) {
        guard frame.width > 0, frame.height > 0 else { return }
        func part(_ key: String) -> WasabiBitmap? { resources.bitmap(identifier: object.attributes[key]) }
        let topLeft = part("topleft"), top = part("top"), topRight = part("topright")
        let left = part("left"), middle = part("middle"), right = part("right")
        let bottomLeft = part("bottomleft"), bottom = part("bottom"), bottomRight = part("bottomright")
        let parts = [topLeft, top, topRight, left, middle, right, bottomLeft, bottom, bottomRight]
        guard parts.contains(where: { $0 != nil }) else { return }

        // Which of the three columns and rows the skin actually declared. A grid that declares one
        // row is a **three-slice**, and its row takes the whole height: cPro's tab pills carry only
        // `topleft`/`top`/`topright`, and the engine's seek track only `left`/`middle`/`right`.
        // Splitting the extent as though the absent rows were there would leave most of the surface
        // blank — the same hole the missing element left in the first place.
        let declaredColumns = (0..<3).filter { column in (0..<3).contains { parts[$0 * 3 + column] != nil } }
        let declaredRows = (0..<3).filter { row in (0..<3).contains { parts[row * 3 + $0] != nil } }

        /// Extents for the three slots along one axis: a single declared slot spans everything, and
        /// otherwise the edges keep their art's own size and the centre takes the remainder. Edges
        /// that together exceed the box (a pane the user collapsed) shrink instead of overlapping.
        func extents(total: CGFloat, declared: [Int], natural: (Int) -> CGFloat) -> [CGFloat] {
            if declared.count == 1 {
                var result: [CGFloat] = [0, 0, 0]
                result[declared[0]] = total
                return result
            }
            var (start, end) = (natural(0), natural(2))
            if start + end > total {
                let scale = total / max(1, start + end)
                start = (start * scale).rounded(.down)
                end = total - start
            }
            return [start, total - start - end, end]
        }
        func widest(_ candidates: [WasabiBitmap?]) -> CGFloat {
            CGFloat(candidates.compactMap { $0?.width }.max() ?? 0)
        }
        func tallest(_ candidates: [WasabiBitmap?]) -> CGFloat {
            CGFloat(candidates.compactMap { $0?.height }.max() ?? 0)
        }
        let columnArt = [[topLeft, left, bottomLeft], [top, middle, bottom], [topRight, right, bottomRight]]
        let rowArt = [[topLeft, top, topRight], [left, middle, right], [bottomLeft, bottom, bottomRight]]
        let columns = extents(total: frame.width, declared: declaredColumns) { widest(columnArt[$0]) }
        let rows = extents(total: frame.height, declared: declaredRows) { tallest(rowArt[$0]) }

        let tiles = object.attributes["tile"] == "1"
        context.saveGState()
        var y = frame.minY
        for (row, rowHeight) in rows.enumerated() {
            var x = frame.minX
            for (column, columnWidth) in columns.enumerated() {
                defer { x += columnWidth }
                guard let bitmap = parts[row * 3 + column], columnWidth > 0, rowHeight > 0 else { continue }
                let cell = CGRect(x: x, y: y, width: columnWidth, height: rowHeight)
                // A corner is one natural-size blit whatever `tile` says; only the stretched axes of
                // an edge or the middle repeat.
                let tileX = tiles && column == 1
                let tileY = tiles && row == 1
                if tileX || tileY {
                    drawTiled(bitmap, in: cell, tileX: tileX, tileY: tileY, context: context)
                } else {
                    drawImage(bitmap.image, in: cell, context: context)
                }
            }
            y += rowHeight
        }
        context.restoreGState()
    }

    /// `<rect>` — a flat colour fill or outline. 44 of them in the ClassicPro engine, including the
    /// backing behind the SUI list surfaces and the browser, all of which drew nothing.
    private func drawRect(_ object: WasabiObject, frame: CGRect, context: CGContext) {
        guard frame.width > 0, frame.height > 0 else { return }
        let color = objectColor(object.attributes["color"] ?? "255,255,255",
                               gammaGroup: object.attributes["gammagroup"])
        context.saveGState()
        // Winamp's default is an outline; the engine writes `filled="1"` wherever it wants a fill and
        // `filled="0"` wherever it wants the border, so neither case is guessed at.
        if ["1", "true", "yes"].contains(object.attributes["filled"]?.lowercased() ?? "0") {
            context.setFillColor(color.cgColor)
            context.fill(frame)
        } else {
            context.setStrokeColor(color.cgColor)
            context.setLineWidth(1)
            // Half-pixel inset so a 1px stroke lands *inside* the rect rather than straddling its edge.
            context.stroke(frame.insetBy(dx: 0.5, dy: 0.5))
        }
        context.restoreGState()
    }

    /// One stop of a `<gradient points>` list: a position and a premultiplication-free RGBA.
    private struct WasabiGradientStop {
        let location: CGFloat
        let red: CGFloat
        let green: CGFloat
        let blue: CGFloat
        let alpha: CGFloat
    }

    /// `<gradient>` — ClassicPro uses it for one thing, and uses it in exactly one shape:
    ///
    /// ```xml
    /// <gradient id="cdbox.fg.fademask" fitparent="1" ghost="1" mode="linear"
    ///           gradient_x1="0" gradient_y1="0" gradient_x2="0" gradient_y2="1"
    ///           points="0.0=128,128,128,0;1.0=128,128,128,255" gammagroup="n.Color.ListBg"/>
    /// ```
    ///
    /// The direction is normalized 0…1 across the object's own rect and each stop carries its own
    /// alpha — which is the whole point of the element here, a fade that masks a reflection back into
    /// the list background. Anything this cannot parse draws nothing and records a diagnostic rather
    /// than guessing at a colour to paint over the skin's artwork with.
    private func drawGradient(_ object: WasabiObject, frame: CGRect, context: CGContext) {
        guard frame.width > 0, frame.height > 0 else { return }
        let mode = (object.attributes["mode"] ?? "linear").lowercased()
        guard mode == "linear" else {
            loadedSkin.runtime.record(WalDiagnostic(.unsupportedElement,
                                                    "<gradient mode=\"\(mode)\"> is not implemented; "
                                                    + "it draws nothing.",
                                                    severity: .warning, location: object.source))
            return
        }
        let stops = Self.gradientStops(object.attributes["points"])
        guard stops.count >= 2 else {
            loadedSkin.runtime.record(WalDiagnostic(.malformedXML,
                                                    "<gradient points=…> needs at least two parseable "
                                                    + "stops; it draws nothing.",
                                                    severity: .warning, location: object.source))
            return
        }
        let gamma = themes.transform(group: object.attributes["gammagroup"]) ?? .identity
        let colors = stops.map { stop -> CGColor in
            let (red, green, blue) = Self.themed(red: stop.red, green: stop.green, blue: stop.blue,
                                                 gamma: gamma)
            return NSColor(red: red, green: green, blue: blue, alpha: stop.alpha).cgColor
        }
        guard let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                        colors: colors as CFArray,
                                        locations: stops.map(\.location)) else { return }
        func coordinate(_ key: String) -> CGFloat {
            max(0, min(1, CGFloat(Double(object.attributes[key] ?? "0") ?? 0)))
        }
        // The scene is painted y-flipped, so `frame.minY` *is* the object's visual top edge and
        // `gradient_y1="0"` lands there without any further correction.
        let start = CGPoint(x: frame.minX + coordinate("gradient_x1") * frame.width,
                            y: frame.minY + coordinate("gradient_y1") * frame.height)
        let end = CGPoint(x: frame.minX + coordinate("gradient_x2") * frame.width,
                          y: frame.minY + coordinate("gradient_y2") * frame.height)
        context.saveGState()
        context.clip(to: frame)
        context.drawLinearGradient(gradient, start: start, end: end,
                                   options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
        context.restoreGState()
    }

    /// `"0.0=R,G,B,A;1.0=R,G,B,A"` → sorted stops. Every position and channel is clamped, and a stop
    /// that does not parse is dropped rather than defaulted, so a malformed list fails the ≥2 check
    /// above instead of painting an invented colour.
    private static func gradientStops(_ raw: String?) -> [WasabiGradientStop] {
        guard let raw else { return [] }
        return raw.split(separator: ";").compactMap { entry -> WasabiGradientStop? in
            let halves = entry.split(separator: "=", maxSplits: 1)
            guard halves.count == 2,
                  let location = Double(halves[0].trimmingCharacters(in: .whitespaces)) else { return nil }
            let channels = halves[1].split(separator: ",")
                .compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
            guard channels.count >= 3 else { return nil }
            func channel(_ index: Int) -> CGFloat {
                CGFloat(max(0, min(255, channels[index])) / 255)
            }
            return WasabiGradientStop(location: CGFloat(max(0, min(1, location))),
                                      red: channel(0), green: channel(1), blue: channel(2),
                                      // An omitted alpha is opaque, as everywhere else here.
                                      alpha: channels.count >= 4 ? channel(3) : 1)
        }.sorted { $0.location < $1.location }
    }

    /// The colour an object declares **inline**, with that object's own `gammagroup` applied.
    ///
    /// A named `<color>` resource carries its own gammagroup and `resolvedColor` already applies it;
    /// applying the object's on top would tint the same channels twice.
    private func objectColor(_ raw: String, gammaGroup: String?) -> NSColor {
        if let definition = loadedSkin.runtime.resources.resolvedColorDefinition(identifier: raw),
           Self.declaredColor(of: definition) != nil {
            return resolvedColor(raw)
        }
        let base = Self.color(raw)
        guard let gamma = themes.transform(group: gammaGroup), !gamma.isIdentity else { return base }
        let (red, green, blue) = Self.themed(red: base.redComponent, green: base.greenComponent,
                                             blue: base.blueComponent, gamma: gamma)
        return NSColor(red: red, green: green, blue: blue, alpha: base.alphaComponent)
    }

    /// One colour through a `<gammagroup>`: desaturate first if the group asks, then offset or scale
    /// each channel per its `boost` mode — the same order the bitmap and `<color>` paths use.
    private static func themed(red: CGFloat, green: CGFloat, blue: CGFloat,
                               gamma: WasabiGammaTransform) -> (CGFloat, CGFloat, CGFloat) {
        var (red, green, blue) = (red, green, blue)
        if gamma.grayscale {
            let luminance = red * 0.299 + green * 0.587 + blue * 0.114
            (red, green, blue) = (luminance, luminance, luminance)
        }
        return (max(0, min(1, gamma.apply(red, amount: gamma.red))),
                max(0, min(1, gamma.apply(green, amount: gamma.green))),
                max(0, min(1, gamma.apply(blue, amount: gamma.blue))))
    }

    /// The sibling whose value a bare `<ProgressGrid>` shows: the slider drawn over the same rect.
    private func valueSibling(of object: WasabiObject) -> WasabiObject? {
        guard let parent = object.parent else { return nil }
        return parent.children.first {
            $0 !== object && $0.attributes["action"] != nil &&
                $0.typeName.caseInsensitiveCompare("slider") == .orderedSame
        }
    }

    private func drawSlider(_ object: WasabiObject, frame: CGRect, context: CGContext, pressed: Bool) {
        guard frame.width > 0, frame.height > 0 else { return }
        let thumbID = pressed ? (object.attributes["downthumb"] ?? object.attributes["thumb"])
                              : object.attributes["thumb"]
        guard let thumb = resources.bitmap(identifier: thumbID) else { return }
        let clamped = normalizedValue(of: object)
        let vertical = Self.isVerticalOrientation(object)
        let thumbWidth = CGFloat(thumb.width)
        let thumbHeight = CGFloat(thumb.height)
        let thumbFrame: CGRect
        if vertical {
            let travel = max(CGFloat.zero, frame.height - thumbHeight)
            thumbFrame = CGRect(x: frame.midX - thumbWidth / 2,
                                y: frame.minY + (1 - clamped) * travel,
                                width: thumbWidth, height: thumbHeight)
        } else {
            let travel = max(CGFloat.zero, frame.width - thumbWidth)
            thumbFrame = CGRect(x: frame.minX + clamped * travel,
                                y: frame.midY - thumbHeight / 2,
                                width: thumbWidth, height: thumbHeight)
        }
        drawImage(thumb.image, in: thumbFrame, context: context)
    }

    // MARK: - Embedded component drawing

    /// Draw a hosted component into its holder frame. Playlist/EQ/vis are skin-framed but
    /// engine-drawn here; library/video/other are hosted as live AppKit subviews by the view layer,
    /// so this only paints a bounded neutral backing for them.
    /// Winamp's thinger: the strip of installed-component icons, and the one it is pointing at (B34).
    ///
    /// No background of its own — the skin has already drawn whatever sits behind the strip, and
    /// every measured bucket is placed on artwork that is meant to show. Each icon gets a rounded
    /// plate instead, which is what keeps a glyph readable on a bucket parked over a bright
    /// background (the same guarantee `legibleRowColor` gives the lists this renderer draws).
    private func drawComponentBucket(_ object: WasabiObject, frame: CGRect, context: CGContext) {
        guard frame.width > 1, frame.height > 1 else { return }
        let state = componentBucket
        let layout = WinampModernComponentBucketLayout(object: object, frame: frame)
        let visible = layout.visibleCount
        guard visible > 0 else { return }
        let offset = state.clampedOffset(state.offset, visibleCount: visible)
        let plate = palette.contentBackground
        let glyph = WinampModernSurfaceStyle.legible(
            preferring: [palette.listText, palette.currentText, palette.selectionText], on: plate)
        let focusPlate = palette.selectionBackground
        let focusGlyph = WinampModernSurfaceStyle.legible(
            preferring: [palette.selectionText, palette.currentText, palette.listText],
            on: focusPlate)
        context.saveGState()
        context.clip(to: frame)
        for slot in 0..<visible {
            let index = offset + slot
            guard state.icons.indices.contains(index) else { break }
            let rect = layout.iconRect(slot: slot)
            let focused = index == state.focusedIndex
            context.setFillColor((focused ? focusPlate : plate).withAlphaComponent(0.75).cgColor)
            context.addPath(CGPath(roundedRect: rect, cornerWidth: 2, cornerHeight: 2,
                                   transform: nil))
            context.fillPath()
            WinampModernComponentBucketCatalog.draw(state.icons[index], in: rect,
                                                    color: focused ? focusGlyph : glyph,
                                                    context: context)
        }
        context.restoreGState()
    }

    private func drawComponent(kind: WinampModernComponentKind, object: WasabiObject,
                               frame: CGRect, context: CGContext) {
        guard frame.width > 1, frame.height > 1 else { return }
        switch kind {
        case .playlist: drawPlaylistComponent(object, frame: frame, context: context)
        case .equalizer: drawEqualizerComponent(frame: frame, context: context)
        case .visualization:
            context.setFillColor(NSColor.black.cgColor)
            context.fill(frame)
            // A holder the view layer has filled with the host's own engine (B20a) draws itself, in
            // an OpenGL view over this box: bars underneath it would be a second visualization
            // nobody can see, costing a repaint every frame. Black is what shows before its first
            // frame arrives. Every *other* `{0000000A}` holder — a letterbox strip, or a second one
            // while the single engine surface is in the first — gets the analyzer, which is what the
            // slot shows in Winamp by default anyway (BB9). Headlessly the set is always empty.
            guard !hostedVisualizationHolders.contains(object.stableID) else { return }
            drawVisualizationBars(object, frame: frame, context: context)
        case .video:
            // Black, not the palette's content colour: a video box is black in Winamp and in all five
            // corpus skins that draw one, and while a film is playing this is what shows in the
            // letterbox margins around the hosted picture (B20).
            context.setFillColor(NSColor.black.cgColor)
            context.fill(frame)
        case .library, .other:
            context.setFillColor(palette.contentBackground.cgColor)
            context.fill(frame)
        }
    }

    /// The font NullPlayer's own surfaces draw with inside this skin.
    ///
    /// A skin's list font may be a bitmap-font *sheet*, which has no `NSFont` at all — passing its id
    /// into a CoreText attribute dictionary is how the Phase 11 `drawText` crash happened. This
    /// returns the resolved resource so the caller can take the right path, never a bare id.
    private var surfaceFont: WalResourceDefinition? {
        for identifier in ["pledit.font", "wasabi.list.font", "studio.list.font"] {
            if let definition = loadedSkin.runtime.resources.resolvedDefinition(identifier: identifier),
               definition.kind == "bitmapfont" || definition.kind == "truetypefont" {
                return definition
            }
        }
        return nil
    }

    /// Draw one line of NullPlayer-owned content (a playlist row, a status line) with the skin's own
    /// font when it has one, and a system font when it does not.
    private func drawSurfaceText(_ text: String, in rect: CGRect, color: NSColor,
                                 alignment: NSTextAlignment, pointSize: CGFloat,
                                 context: CGContext) {
        if let definition = surfaceFont, definition.kind == "bitmapfont" {
            drawBitmapText(text, definition: definition, frame: rect, alignment: alignment,
                           ticker: nil, context: context)
            return
        }
        let font = resources.font(identifier: surfaceFont?.identifier, size: pointSize)
            ?? NSFont.systemFont(ofSize: pointSize)
        drawFlippedText(text, in: rect, font: font, color: color, alignment: alignment, context: context)
    }

    /// A row colour that can be read on the bar behind it, for the lists **this renderer** draws
    /// itself — the skin's own playlist panel and colour-theme picker.
    ///
    /// The same guarantee `WinampModernSurfaceStyle` gives NullPlayer's AppKit surfaces (B48), needed
    /// again here because these rows never pass through a style: they read `WasabiPalette` directly,
    /// and the palette resolves each role from an independent id chain with nothing checking that the
    /// pair can be seen together. Big Bento is the measured case — `selectionText` is its pale
    /// blue-grey `color.display` and `selectionBackground` its orange `color.selected.active`, 1.06:1
    /// apart, and a *current* row over that same bar is orange on orange at 1.00:1.
    ///
    /// Unselected rows are returned untouched: they land on the content background, which is a
    /// separate pairing and a separate measurement.
    private func legibleRowColor(_ preferred: NSColor, selected: Bool) -> NSColor {
        guard selected else { return preferred }
        return WinampModernSurfaceStyle.legible(
            preferring: [preferred, palette.selectionText, palette.currentText, palette.listText,
                         palette.contentBackground],
            on: palette.selectionBackground)
    }

    /// Winamp's colour-theme picker: the skin's `<gammaset>` names, in document order.
    ///
    /// The rows are ours to draw — the widget lives inside Winamp, the skin ships only the tag — so
    /// they follow the same route every NullPlayer-owned surface inside a `.wal` takes: the skin's
    /// list colours, the skin's list font, the skin's active gamma. Two colours are deliberately
    /// distinct: the **selected** row (what the `Switch` button would apply) and the **applied** one
    /// (what the window is wearing). Winamp shows both at once and a picker that conflated them would
    /// make "did my click do anything?" unanswerable.
    ///
    /// **No scrollbar.** The renderer has no scrollbar support at all, so a `<Wasabi:Scrollbar>` a
    /// skin places beside its list stays inert and the wheel is the only way down an 83-row list.
    /// Opening scrolled to the applied theme is the mitigation; see the rendering reference.
    private func drawColorThemeList(_ object: WasabiObject, frame: CGRect, context: CGContext) {
        guard frame.width > 1, frame.height > 1 else { return }
        let palette = palette
        // The caller has already drawn a declared `background=`. Only when the skin declared none do
        // we paint one — first the conventional list background bitmap, then a flat fill.
        if object.attributes["background"] == nil {
            if let bitmap = resources.bitmap(identifier: "wasabi.list.background") {
                drawTiled(bitmap, in: frame, tileX: true, tileY: true, context: context)
            } else {
                context.setFillColor(palette.contentBackground.cgColor)
                context.fill(frame)
            }
        }
        let names = colorThemeNames
        guard !names.isEmpty else { return }
        let state = state(ofColorThemeList: object, frame: frame)
        let rowHeight = WasabiColorThemeListState.rowHeight
        let visible = WasabiColorThemeListState.visibleRowCount(in: frame)
        guard visible > 0 else { return }
        let offset = WasabiColorThemeListState.clampedOffset(state.scrollOffset,
                                                             rowCount: names.count, in: frame)
        let active = activeColorThemeIndex
        context.saveGState()
        context.clip(to: frame)
        for slot in 0..<visible {
            let index = offset + slot
            guard index < names.count else { break }
            let rowRect = CGRect(x: frame.minX, y: frame.minY + CGFloat(slot) * rowHeight,
                                 width: frame.width, height: rowHeight)
            if index == state.selectedIndex {
                context.setFillColor(palette.selectionBackground.cgColor)
                context.fill(rowRect)
            }
            let selected = index == state.selectedIndex
            let color = legibleRowColor(index == active ? palette.currentText
                                            : (selected ? palette.selectionText : palette.listText),
                                        selected: selected)
            drawSurfaceText(names[index], in: rowRect.insetBy(dx: 3, dy: 1), color: color,
                            alignment: .left, pointSize: 9, context: context)
        }
        context.restoreGState()
    }

    /// A `<Wasabi:Button>` that resolves no artwork but carries a label.
    ///
    /// Deliberate exception to the identifier-only-shell rule (`wasabiStandardLibraryGroups`), which
    /// exists so we never invent artwork a skin did not ship. Three measured skins — CornerAmp, mmd3's
    /// big colour-theme window and Anexa — put a bare `<Wasabi:Button text="Switch">` under their
    /// theme list, and **no** `.wal` ships `wasabi.button.*` bitmaps because in real Winamp the
    /// standard library supplies them. So the choice is a plain border with the skin's own list colour
    /// or a screen whose only working control is an undiscoverable double-click. Contained by
    /// construction: a skin with its own button artwork resolves a bitmap and never reaches here
    /// (mmd3's in-player drawer and multipass both ship theirs).
    static func isTextButton(_ object: WasabiObject) -> Bool {
        guard object.typeName.caseInsensitiveCompare("wasabi:button") == .orderedSame else { return false }
        return !(object.attributes["text"] ?? "").isEmpty
    }

    private func drawTextButton(_ object: WasabiObject, frame: CGRect, context: CGContext,
                                pressed: Bool) {
        guard frame.width > 2, frame.height > 2 else { return }
        let color = palette.listText
        context.saveGState()
        context.setStrokeColor(color.cgColor)
        context.setLineWidth(1)
        context.stroke(frame.insetBy(dx: 0.5, dy: 0.5))
        if pressed {
            context.setFillColor(color.withAlphaComponent(0.25).cgColor)
            context.fill(frame.insetBy(dx: 1, dy: 1))
        }
        let label = object.attributes["text"] ?? ""
        let inset = frame.insetBy(dx: 2, dy: max(0, (frame.height - 11) / 2))
        drawSurfaceText(label, in: inset, color: color, alignment: .center, pointSize: 9,
                        context: context)
        context.restoreGState()
    }

    private func drawPlaylistComponent(_ holder: WasabiObject, frame: CGRect, context: CGContext) {
        // Drawn by us, coloured by the skin: the list sits inside the skin's own frame, so its text
        // and selection follow the skin's colour resources and its active colour theme.
        let palette = palette
        context.setFillColor(palette.contentBackground.cgColor)
        context.fill(frame)
        guard let snapshot = componentHost?.playlistSnapshot() else { return }
        let rowHeight = playlistRowHeight(in: holder)
        let visible = playlistVisibleRowCount(in: frame, holder: holder)
        guard visible > 0 else { return }
        // Keep the scroll offset in range as the list changes.
        let maxOffset = max(0, snapshot.rows.count - visible)
        let offset = max(0, min(maxOffset, playlistScrollOffset))
        let pointSize = CGFloat(playlistTextPixelHeight(in: holder)
                                * WasabiTextMetrics.pixelHeightToPointSize)
        context.saveGState()
        context.clip(to: frame)
        for slot in 0..<visible {
            let index = offset + slot
            guard index < snapshot.rows.count else { break }
            let row = snapshot.rows[index]
            let rowRect = CGRect(x: frame.minX, y: frame.minY + CGFloat(slot) * rowHeight,
                                 width: frame.width, height: rowHeight)
            let selected = snapshot.isSelected(index)
            if selected {
                context.setFillColor(palette.selectionBackground.cgColor)
                context.fill(rowRect)
            }
            // A current row keeps its own colour over the selection bar, as Winamp's playlist does —
            // but only when the skin actually named one. `currentText` falls back to `listText`, and
            // list text over the selection background is what `selectionText` exists to avoid.
            let hasCurrentColor = palette.currentText != palette.listText
            let color = legibleRowColor(row.isCurrent && (hasCurrentColor || !selected)
                                            ? palette.currentText
                                            : (selected ? palette.selectionText : palette.listText),
                                        selected: selected)
            let label = "\(index + 1). \(row.title)"
            drawSurfaceText(label, in: rowRect.insetBy(dx: 3, dy: 1), color: color,
                            alignment: .left, pointSize: pointSize, context: context)
            if row.duration > 0 {
                let seconds = Int(row.duration)
                let time = String(format: "%d:%02d", seconds / 60, seconds % 60)
                drawSurfaceText(time, in: rowRect.insetBy(dx: 3, dy: 1), color: color,
                                alignment: .right, pointSize: pointSize, context: context)
            }
        }
        context.restoreGState()
    }

    private func drawEqualizerComponent(frame: CGRect, context: CGContext) {
        let palette = palette
        context.setFillColor(palette.contentBackground.cgColor)
        context.fill(frame)
        guard let snapshot = componentHost?.equalizerSnapshot() else { return }
        let bands = snapshot.bandGainsDB
        let all = [snapshot.preampDB] + bands
        guard !all.isEmpty else { return }
        let slotWidth = frame.width / CGFloat(all.count)
        context.saveGState()
        context.clip(to: frame)
        for (index, gain) in all.enumerated() {
            let x = frame.minX + CGFloat(index) * slotWidth
            let normalized = CGFloat((gain + 12) / 24) // -12…12 → 0…1
            let trackRect = CGRect(x: x + slotWidth * 0.35, y: frame.minY + 2,
                                   width: max(1, slotWidth * 0.3), height: frame.height - 4)
            context.setFillColor(NSColor(white: 0.18, alpha: 1).cgColor)
            context.fill(trackRect)
            let thumbHeight: CGFloat = 3
            let travel = max(0, trackRect.height - thumbHeight)
            let thumbY = trackRect.minY + (1 - normalized) * travel
            context.setFillColor((snapshot.enabled ? palette.currentText
                                                    : palette.listText.withAlphaComponent(0.5)).cgColor)
            context.fill(CGRect(x: x + slotWidth * 0.2, y: thumbY,
                                width: max(2, slotWidth * 0.6), height: thumbHeight))
        }
        context.restoreGState()
    }

    /// Roughly how many points of box each band gets, bar plus gap. The band count is clamped to the
    /// tap's own resolution above this, so a wide pane draws every band the tap has and a small box
    /// draws as many as fit legibly.
    private static let analyzerBandPitch: CGFloat = 6

    /// The spectrum analyzer a `<component hold="guid:{0000000A-…}">` box draws when the view layer
    /// has not mounted the host's engine over it.
    ///
    /// `{0000000A}` is Winamp's visualization *plugin host*, whose default content is Winamp's own
    /// built-in analyzer — so this is not a placeholder for an empty box any more, it is what the
    /// slot is supposed to show. `WinampModernVisualizationHolder` decides which holders reach here.
    ///
    /// It has **no `<vis>` element** to take its styling from, and it deliberately does not borrow a
    /// nearby one's: `bandwidth="wide"` is 19 bands, sized for that skin's own 144px box, and 19
    /// bands across a 1400px pane is a row of slabs. The band count comes from the box, and the
    /// colours from the skin's palette — the same route every other NullPlayer-owned surface inside a
    /// `.wal` takes, so a colour-theme switch recolours this with everything else.
    private func drawVisualizationBars(_ object: WasabiObject, frame: CGRect, context: CGContext) {
        guard !host.spectrumLevels.isEmpty, frame.width > 0, frame.height > 0 else { return }
        let levels = host.spectrumLevels
        let count = max(1, min(levels.count, Int(frame.width / Self.analyzerBandPitch)))
        let slot = frame.width / CGFloat(count)

        // The same falling caps the `<vis>` analyzer has, held in the same store — a `<component>`
        // holder and a `<vis>` are different objects, so the keys cannot collide.
        var peaks = analyzerPeaks[object.stableID] ?? []
        if peaks.count != count { peaks = Array(repeating: 0, count: count) }

        var bars: [CGRect] = []
        var caps: [CGRect] = []
        let capHeight: CGFloat = frame.height >= 16 ? 2 : 1
        for index in 0..<count {
            // One band is the loudest bin in its bucket, on the same decibel scale `getVisBand` and
            // the `<vis>` analyzer answer in: the tap is linear, and drawn linearly ordinary music
            // sits in the bottom of the box.
            let start = index * levels.count / count
            let end = min(levels.count, max(start + 1, (index + 1) * levels.count / count))
            var magnitude: Float = 0
            for bin in start..<end { magnitude = max(magnitude, levels[bin]) }
            let level = max(0, min(1, CGFloat(WinampModernScriptRuntime.visByte(forMagnitude: magnitude)) / 255))
            peaks[index] = max(level, peaks[index] - Self.analyzerPeakDecay)
            // Whole pixels, for the `<vis>` analyzer's reason: a fractional slot antialiases the 1px
            // gap into a smear and the row reads as one solid block.
            let left = (CGFloat(index) * slot).rounded(.down)
            let right = (CGFloat(index + 1) * slot).rounded(.down)
            let x = frame.minX + left
            let width = max(1, right - left - 1)
            if level > 0 {
                bars.append(CGRect(x: x, y: frame.maxY - level * frame.height,
                                   width: width, height: level * frame.height))
            }
            guard peaks[index] > level else { continue }
            caps.append(CGRect(x: x, y: min(frame.maxY - capHeight,
                                            frame.maxY - peaks[index] * frame.height),
                               width: width, height: capHeight))
        }
        analyzerPeaks[object.stableID] = peaks

        let bright = palette.listText
        let dim = Self.blend(bright, toward: palette.contentBackground, by: 0.6)
        context.saveGState()
        defer { context.restoreGState() }
        if !bars.isEmpty {
            // One gradient for the whole row, clipped to the bars, rather than one per bar: this runs
            // at the scene's redraw rate against as many bands as the tap has.
            context.beginPath()
            for bar in bars { context.addRect(bar) }
            context.clip()
            if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                         colors: [dim.cgColor, bright.cgColor] as CFArray,
                                         locations: [0, 1]) {
                context.drawLinearGradient(gradient,
                                           start: CGPoint(x: frame.minX, y: frame.maxY),
                                           end: CGPoint(x: frame.minX, y: frame.minY),
                                           options: [])
            } else {
                context.setFillColor(bright.cgColor)
                context.fill(frame)
            }
            context.resetClip()
        }
        context.setFillColor(bright.cgColor)
        for cap in caps { context.fill(cap) }
    }

    /// Mix two palette roles. Both are already device RGB (`WasabiPalette` converts on the way in),
    /// so the components can be read without the greyscale trap that `redComponent` raises on.
    private static func blend(_ color: NSColor, toward other: NSColor, by fraction: CGFloat) -> NSColor {
        let f = max(0, min(1, fraction))
        return NSColor(deviceRed: color.redComponent + (other.redComponent - color.redComponent) * f,
                       green: color.greenComponent + (other.greenComponent - color.greenComponent) * f,
                       blue: color.blueComponent + (other.blueComponent - color.blueComponent) * f,
                       alpha: 1)
    }

    private func drawFlippedText(_ text: String, in frame: CGRect, font: NSFont, color: NSColor,
                                 alignment: NSTextAlignment, context: CGContext) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = alignment
        paragraph.lineBreakMode = .byTruncatingTail
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font, .foregroundColor: color, .paragraphStyle: paragraph
        ]
        context.saveGState()
        context.translateBy(x: 0, y: frame.midY)
        context.scaleBy(x: 1, y: -1)
        context.translateBy(x: 0, y: -frame.midY)
        (text as NSString).draw(in: frame, withAttributes: attributes)
        context.restoreGState()
    }

    private func resolvedBitmapID(for object: WasabiObject, pressed: Bool, hovered: Bool) -> String? {
        let type = object.typeName.lowercased()
        if type == "status" {
            switch host.playbackState {
            case .playing: return object.attributes["playbitmap"]
            case .paused: return object.attributes["pausebitmap"]
            case .stopped: return object.attributes["stopbitmap"]
            }
        }
        if pressed, let down = object.attributes["downimage"] { return down }
        if hovered, let hover = object.attributes["hoverimage"] { return hover }
        if type == "nstatesbutton", let base = object.attributes["image"] {
            let state: Int
            if object.xmlID?.lowercased().contains("repeat") == true {
                state = host.repeatEnabled ? 1 : 0
            } else {
                state = max(0, Int(object.attributes["state"] ?? "0") ?? 0)
            }
            // Not every skin names its states `<base><n>`; Winamp Modern's LEDs use a plain `image`
            // with separate `activeimage`. Fall back to the base rather than a dangling id.
            let stateID = "\(base)\(state)"
            return resources.bitmap(identifier: stateID) != nil ? stateID : base
        }
        if type == "togglebutton" || object.attributes["activeimage"] != nil {
            let id = object.xmlID?.lowercased()
            var active = (id == "shuffle" && host.shuffleEnabled) || (id == "repeat" && host.repeatEnabled)
            // EQ on/auto read the engine, not a local toggle state, so a change made from the menu
            // bar or a script lights the skin's own button.
            switch object.attributes["action"]?.uppercased() {
            case "EQ_TOGGLE": active = componentHost?.equalizerSnapshot().enabled ?? false
            case "EQ_AUTO": active = componentHost?.equalizerSnapshot().auto ?? false
            default: break
            }
            // A `cfgattrib` binding *is* the button's state — it is how a skin draws a preference it
            // does not otherwise track. Defix pairs a `ghost="1"` indicator with a bare click target
            // over the same rect, both naming the attribute, so without this every switch in its
            // settings window painted its "off" artwork whatever the stored value was.
            if let scripts = configStateProvider, scripts(object) { active = true }
            if active, let image = object.attributes["activeimage"] { return image }
        }
        return object.attributes["image"]
    }

    private func isInteractive(_ object: WasabiObject) -> Bool {
        let type = object.typeName.lowercased()
        if type == "button" || type == "togglebutton" || type == "nstatesbutton" || type == "slider" {
            return true
        }
        if object.attributes["action"] != nil { return true }
        // A command on the *second* click or the right button is still a command, and it is the only
        // one some objects carry: a `<text>` song title with `dblclickaction="TRACKINFO"` is not one
        // of the types above and has no `action=`, so it was never under the mouse at all. Ghosts are
        // already excluded by `object(at:)`, which is what keeps multipass's `ghost="1"` playlist
        // ticker from swallowing clicks meant for the list behind it.
        if object.attributes[WasabiClickGesture.double.actionAttribute] != nil
            || object.attributes[WasabiClickGesture.right.actionAttribute] != nil { return true }
        // A colour-theme list owns no bitmap and carries no action — Winamp supplies the widget, the
        // skin supplies only the tag — so without naming it here a click could never reach a row.
        if Self.isColorThemeList(object) { return true }
        // Same for a component bucket: the skin ships the box, Winamp ships the icons, and clicking
        // one is how the thinger opens that component (B34).
        if Self.isComponentBucket(object) { return true }
        // `<Wasabi:Button text="…">` with no artwork: the renderer draws the label and its border
        // (see `drawTextButton`), so it has a region and has to be clickable. Every measured instance
        // also carries an `action`, which the line above already accepts; this covers one that does
        // not and is driven from a script instead.
        if Self.isTextButton(object) { return true }
        // A container has **no region of its own** in Wasabi — its children supply one. MMD3 declares
        // `<group id="main.mmd3" move="1">` last in its layout, so it is topmost across the whole
        // window; accepting a bare group for `move="1"` made it swallow every click that was not over
        // one of its own children, which is what killed the drawer tabs and the colour-theme strip
        // declared before it. A group that paints a background does have a region and keeps one.
        // (Window dragging is unaffected: `shouldDragWindow` only ever accepts a `layer`.)
        if type == "group" || type == "layout" { return object.attributes["background"] != nil }
        if object.attributes["move"] == "1" { return true }
        // An `animatedlayer` is a layer that moves. MMD3's rotary volume/bass/treble knobs are
        // animated layers with their own `onLeftButtonDown` handlers, and leaving the type out here
        // meant a click never reached them.
        return (type == "layer" || type == "animatedlayer") && object.attributes["ghost"] != "1"
    }

    private func isRenderable(_ object: WasabiObject, bitmapID: String?) -> Bool {
        // A component holder paints a real surface (the playlist list, the EQ sliders), so it is
        // opaque to hit testing even though it owns no bitmap of its own.
        if WinampModernComponentRegistry.isHolderElement(object.typeName),
           Self.componentKind(of: object) != nil {
            return true
        }
        // `rectrgn="1"` *is* the object's region: its whole rect, artwork or not. Skins use a bare
        // layer with it as an invisible click target (Love is War Miku switches its visualization mode
        // through `visual.trigger`), and a hit test that insists on a bitmap can never reach one.
        if object.attributes["rectrgn"] == "1" { return true }
        // A colour-theme list, an artwork-less text button and a component bucket all paint a real
        // surface of their own (rows; a bordered label; the thinger's icons), so each is opaque to
        // hit testing without owning a bitmap.
        if Self.isColorThemeList(object) || Self.isTextButton(object)
            || Self.isComponentBucket(object) { return true }
        return object.attributes["background"] != nil || bitmapID != nil ||
            object.typeName.caseInsensitiveCompare("text") == .orderedSame ||
            object.typeName.caseInsensitiveCompare("songticker") == .orderedSame ||
            object.typeName.caseInsensitiveCompare("vis") == .orderedSame ||
            object.typeName.caseInsensitiveCompare("eqvis") == .orderedSame ||
            object.typeName.caseInsensitiveCompare("albumart") == .orderedSame ||
            object.typeName.caseInsensitiveCompare("slider") == .orderedSame
    }

    private func isVisible(_ object: WasabiObject) -> Bool {
        guard !object.isTornDown else { return false }
        let value = object.attributes["visible"]?.lowercased()
        return value != "0" && value != "false" && value != "no"
    }

    private func clipsChildren(_ object: WasabiObject) -> Bool {
        let value = object.attributes["clipchildren"]?.lowercased()
        if value == "1" || value == "true" { return true }
        return isSizedGroup(object)
    }

    /// A `<group>` is a **window** in Wasabi, so its children are bounded by it whether or not the
    /// skin says `clipchildren`. Defix's cassette display is a 263×79 group holding a 117×117 reel
    /// bitmap: unclipped, the two reels spilled 53px past the bottom of the cassette and painted
    /// straight over the song ticker below it, leaving the title visible only in the gaps between
    /// them.
    ///
    /// Only a group whose box the skin actually **declared** clips. One that is sized from its
    /// background bitmap, or that falls through to the renderer's default, has a rect we inferred —
    /// and clipping children to a guess can erase content that is really there, which is a far worse
    /// failure than the overhang it would prevent. `fitparent` counts as declared: it resolves to the
    /// parent's box, so the clip it produces is the one the children already had.
    private func isSizedGroup(_ object: WasabiObject) -> Bool {
        guard object.typeName.caseInsensitiveCompare("group") == .orderedSame else { return false }
        if object.attributes["fitparent"] == "1" { return true }
        return object.geometry.width != nil && object.geometry.height != nil
    }

    /// Whether this object is one of the two panes of a `<Wasabi:Frame>`.
    ///
    /// A pane is a **window** in real Wasabi, so it always clips, `clipchildren` or not — and that is
    /// load-bearing for a *collapsed* one. cPro-Bento closes its mini view by putting the horizontal
    /// splitter's divider 10px from the top, which correctly leaves `centro.playlist.directory` 6px
    /// tall; but that pane's children are all bottom-anchored for the 27px strip it has when open
    /// (`y="-27" relaty="1"`), so they resolve to y = 6 − 27 = −21 → **21px above the pane**, straight
    /// over the volume slider, the mute button and the kbps/kHz readouts, with `comp.goto` left
    /// floating as a stray `▭≡` on the display. Only the pane's own rect bounds them.
    private func isFramePane(_ object: WasabiObject) -> Bool {
        guard let parent = object.parent, WasabiFrame.isFrame(parent), let id = object.xmlID else {
            return false
        }
        let panes = WasabiFrame.paneIdentifiers(of: parent)
        // Exactly two is what makes it a splitter at all; real skins use a `<Wasabi:Frame>` naming
        // neither pair as a plain group, and that one keeps the inherited clip.
        return panes.count == 2 && panes.contains { $0.caseInsensitiveCompare(id) == .orderedSame }
    }

    private static func dimension(_ attributes: [String: String], keys: [String], fallback: CGFloat) -> CGFloat {
        for key in keys {
            if let raw = attributes[key], let value = Double(raw), value > 0 { return CGFloat(value) }
        }
        return fallback
    }

    private func defaultSize(for layout: WasabiObject) -> CGSize {
        Self.defaultSize(for: layout, resources: resources)
    }

    /// A layout's canvas size.
    ///
    /// `w`/`h` are **optional** on a layout: Wasabi sizes one that declares none to its `background`
    /// bitmap, exactly as it sizes every other object with artwork and no box. ZDL's Reel-To-Reel
    /// declares every one of its layouts that way, so falling straight through to the 275×116 classic
    /// default gave its 275×348 player a canvas a third of its height — everything below the reels
    /// landed outside the canvas, where `append` drops it, and what was left stacked on top of the
    /// reels. The declared box still wins where a skin gives one.
    /// The size a layout opens at: its own `default_w`/`default_h`, **never below the minimum it
    /// declares for itself**.
    ///
    /// Four layouts in the 31-skin corpus declare a default smaller than their own minimum, and two
    /// of them are the visualization windows this was found on: Anaheim_Player_01's `avs_window` is
    /// `default_w="120"` against `minimum_w="180"`, and Styx's `AVS` is 300×300 against 400×230. The
    /// window opened at the default, so the standard frame's corner and edge art was laid out for a
    /// window 60pt wider than the one drawing it and the chrome came out cut off down the right-hand
    /// side — reported as "a misformed rectangle box". Winamp cannot show a window below its declared
    /// minimum either; this is the same clamp `resize(to:)` already applies to every later size.
    ///
    /// Only the **declared** minimum clamps here, not `layoutMinimumSize` — that one folds in the
    /// computed protective minimum, which is a defence against a *shrunk* window and has no business
    /// enlarging one the skin's author sized deliberately.
    private static func defaultSize(for layout: WasabiObject, resources: WasabiResourceCache) -> CGSize {
        let background = resources.bitmap(identifier: layout.attributes["background"])
        let size = CGSize(
            width: dimension(layout.attributes, keys: ["default_w", "w", "minimum_w"],
                             fallback: background.map { CGFloat($0.width) } ?? 275),
            height: dimension(layout.attributes, keys: ["default_h", "h", "minimum_h"],
                              fallback: background.map { CGFloat($0.height) } ?? 116)
        )
        let minimum = CGSize(width: dimension(layout.attributes, keys: ["minimum_w"], fallback: 1),
                             height: dimension(layout.attributes, keys: ["minimum_h"], fallback: 1))
        return CGSize(width: max(size.width, minimum.width), height: max(size.height, minimum.height))
    }

    private static func optionalDimension(_ raw: String?) -> CGFloat? {
        guard let raw, let value = Double(raw), value > 0 else { return nil }
        return CGFloat(value)
    }

    /// The `r,g,b` a resource declares, or `nil` when it declares no colour at all.
    ///
    /// Two kinds carry one. A `<color>` obviously does — and a **generated solid bitmap**
    /// (`<bitmap file="$solid" color="8,9,10">`) does too: it *is* a colour, with the pixels
    /// synthesized from it. cPro-Bento declares `wasabi.list.background` as both, and the bitmap wins
    /// the registry, so insisting on `kind == "color"` sent the name down the literal-parsing path,
    /// where it is not three numbers and became the **white** fallback — a white slab across the tab
    /// strip and behind the SUI list surfaces of a near-black skin.
    private static func declaredColor(of definition: WalResourceDefinition) -> String? {
        if definition.kind == "color" { return definition.attributes["value"] ?? "255,255,255" }
        guard definition.kind == "bitmap",
              definition.attributes["file"]?.hasPrefix("$") == true else { return nil }
        return definition.attributes["color"]
    }

    /// Follow a `<color>` whose value names another colour resource until a literal triple is
    /// reached, carrying the first `gammagroup` seen along the chain.
    ///
    /// Bounded and cycle-guarded like the alias walk in the registry: a skin can write
    /// `value="<id>"` pointing anywhere, including at itself.
    private static func dereference(_ declared: String, gammaGroup: String?,
                                    resources: WalResourceRegistry) -> (value: String, gammaGroup: String?) {
        var value = declared
        var group = gammaGroup
        var visited: Set<String> = []
        for _ in 0..<16 {
            let trimmed = value.trimmingCharacters(in: .whitespaces)
            // A literal (`r,g,b` or `#rrggbb`) ends the walk; anything else may be an id to follow.
            if channels(of: trimmed) != nil { return (value, group) }
            guard visited.insert(trimmed.lowercased()).inserted,
                  let next = resources.resolvedColorDefinition(identifier: trimmed),
                  let nextDeclared = declaredColor(of: next), nextDeclared != value else {
                return (value, group)
            }
            value = nextDeclared
            group = group ?? next.attributes["gammagroup"]
        }
        return (value, group)
    }

    /// Every colour this file hands out is component-readable RGB — never `.white`/`.black`, which
    /// AppKit vends as greyscale tagged pointers whose `redComponent` *raises*. Callers that tint
    /// their own glyphs (the library's star rating, for one) read the channels directly.
    static let unparseableColor = NSColor(red: 1, green: 1, blue: 1, alpha: 1)

    private static func color(_ raw: String) -> NSColor {
        // A skin writes an inline colour two ways. `r,g,b` is the common one; **`#rrggbb` is not
        // rare** — Big Bento Modern writes all 22 of its analyzer colours that way
        // (`colorband1="#5a5490"` … `colorband16="#bda4fc"`, plus `colorbandpeak` and `colorosc1..5`),
        // and with only the triple parsed every one of them fell through to `unparseableColor`. That
        // is white, so the skin's purple analyzer drew as white slabs wherever it appeared.
        if let hex = hexColor(raw) { return hex }
        let values = raw.split(separator: ",").compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
        guard values.count >= 3 else { return unparseableColor }
        return NSColor(red: max(0, min(255, values[0])) / 255,
                       green: max(0, min(255, values[1])) / 255,
                       blue: max(0, min(255, values[2])) / 255,
                       alpha: 1)
    }

    /// The 0…255 channels a **declared** colour value spells out, either as `r,g,b` or as `#rrggbb`,
    /// or `nil` for a value that is neither.
    ///
    /// Only the colour-*resource* path uses this. A `<color value="#800000">` cannot be anything but
    /// a literal — Enkera declares its whole palette that way, and every one of those roles was
    /// resolving to `unparseableColor`, i.e. white text on a white list (BB2a). The inline-attribute
    /// path in `color(_:)` keeps its own rules, where a bare token may still be a resource id.
    private static func channels(of declared: String) -> [CGFloat]? {
        if let hex = hexColor(declared), let rgb = hex.usingColorSpace(.deviceRGB) {
            return [rgb.redComponent * 255, rgb.greenComponent * 255, rgb.blueComponent * 255]
        }
        let values = declared.split(separator: ",")
            .map { CGFloat(Double($0.trimmingCharacters(in: .whitespaces)) ?? 255) }
        return values.count >= 3 ? values : nil
    }

    /// `#rrggbb` or the three-digit shorthand, or `nil` for anything that is not one. Deliberately
    /// strict: a bare `abcdef` with no `#` stays a resource identifier, which is what the caller
    /// already tried it as.
    private static func hexColor(_ raw: String) -> NSColor? {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("#") else { return nil }
        let digits = trimmed.dropFirst()
        guard digits.count == 3 || digits.count == 6, digits.allSatisfy(\.isHexDigit) else { return nil }
        let expanded = digits.count == 3 ? String(digits.flatMap { [$0, $0] }) : String(digits)
        guard let value = UInt32(expanded, radix: 16) else { return nil }
        return NSColor(red: CGFloat((value >> 16) & 0xFF) / 255,
                       green: CGFloat((value >> 8) & 0xFF) / 255,
                       blue: CGFloat(value & 0xFF) / 255, alpha: 1)
    }

    func resolvedColor(_ raw: String) -> NSColor {
        guard let definition = loadedSkin.runtime.resources.resolvedColorDefinition(identifier: raw),
              let declared = Self.declaredColor(of: definition) else { return Self.color(raw) }
        // A `<color>`'s value may name **another colour resource** rather than spell out a triple,
        // and Big Bento Modern writes nearly every one of its list colours that way
        // (`wasabi.list.text` = `color.display`, `wasabi.list.background` = `color.window.bg`).
        // Without following the reference the value is not three numbers, so it became
        // `unparseableColor` — white — and the whole skin's list palette came out white-on-black
        // (BB2a). The gammagroup taken is the *referring* declaration's where it has one, so the
        // channels are tinted once, by the group the id that was actually asked for names.
        let (base, gammaGroup) = Self.dereference(declared,
                                                  gammaGroup: definition.attributes["gammagroup"],
                                                  resources: loadedSkin.runtime.resources)
        guard var values = Self.channels(of: base) else { return Self.unparseableColor }
        let gamma = themes.transform(group: gammaGroup) ?? .identity
        if gamma.grayscale {
            // Same order as the bitmap path: desaturate, then tint.
            let luminance = values[0] * 0.299 + values[1] * 0.587 + values[2] * 0.114
            values = [luminance, luminance, luminance]
        }
        let r = gamma.apply(values[0] / 255, amount: gamma.red)
        let g = gamma.apply(values[1] / 255, amount: gamma.green)
        let b = gamma.apply(values[2] / 255, amount: gamma.blue)
        return NSColor(red: max(0, min(1, r)), green: max(0, min(1, g)),
                       blue: max(0, min(1, b)), alpha: 1)
    }
}
