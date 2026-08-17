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

/// A colour-theme adjustment, as per-channel **multipliers**.
///
/// A `<gammagroup value="r,g,b">` carries three signed values in −4096…4096 where **0 means "leave
/// this channel alone"**, so the channel factor is `(4096 + v) / 4096` — 4096 doubles a channel, −4096
/// zeroes it. Reading the value as an additive bias instead (`v / 4096` added to the channel) pushes
/// every midtone toward white, which is exactly what made MMD3's display render as a washed-out pastel
/// instead of a saturated orange on black.
struct WasabiGammaTransform: Equatable {
    let red: CGFloat
    let green: CGFloat
    let blue: CGFloat
    let grayscale: Bool

    static let identity = WasabiGammaTransform(red: 1, green: 1, blue: 1, grayscale: false)
    var isIdentity: Bool { self == .identity }

    /// Build from the raw XML attributes of one `<gammagroup>`.
    ///
    /// `gray` is a mode, not a flag — MMD3 uses both `gray="1"` and `gray="2"` — so any non-zero value
    /// desaturates. `boost` only widens the permitted range in Winamp; the multiplier form already
    /// carries values past 1 unclamped, so it needs no separate filter.
    init(value: String, gray: String?, boost: String?) {
        let components = value.split(separator: ",")
            .map { CGFloat(Double($0.trimmingCharacters(in: .whitespaces)) ?? 0) }
        let padded = (components + [0, 0, 0]).prefix(3).map { $0 }
        let limit: CGFloat = 4096
        self.red = max(0, (limit + padded[0]) / limit)
        self.green = max(0, (limit + padded[1]) / limit)
        self.blue = max(0, (limit + padded[2]) / limit)
        let grayMode = Int(Double(gray ?? "0") ?? 0)
        self.grayscale = grayMode != 0
        _ = boost
    }

    init(red: CGFloat, green: CGFloat, blue: CGFloat, grayscale: Bool) {
        self.red = red
        self.green = green
        self.blue = blue
        self.grayscale = grayscale
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

final class WasabiResourceCache {
    let loadedSkin: WinampModernLoadedSkin
    let maximumCost: Int
    let themes: WasabiColorThemeCatalog

    private struct CachedBitmap {
        let bitmap: WasabiBitmap
        var access: UInt64
    }
    private var bitmaps: [String: CachedBitmap] = [:]
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
    func font(identifier: String?, size: CGFloat) -> NSFont? {
        guard !isTornDown else { return nil }
        return metrics.font(identifier: identifier, size: size)
    }

    func teardown() {
        bitmaps.removeAll()
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
        // Scale each channel; alpha is left alone so the theme never dissolves a sprite's mask.
        output = output.applyingFilter("CIColorMatrix", parameters: [
            "inputRVector": CIVector(x: transform.red, y: 0, z: 0, w: 0),
            "inputGVector": CIVector(x: 0, y: transform.green, z: 0, w: 0),
            "inputBVector": CIVector(x: 0, y: 0, z: transform.blue, w: 0)
        ])
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
}

final class WasabiSceneRenderer {
    let loadedSkin: WinampModernLoadedSkin
    let host: WinampModernHost
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

    var activeLayoutID: String { layout.xmlID ?? "normal" }
    var availableLayoutIDs: [String] {
        container.children.compactMap { child in
            child.typeName.caseInsensitiveCompare("layout") == .orderedSame ? child.xmlID : nil
        }
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
        }), let layout = container.children.first(where: {
            $0.typeName.caseInsensitiveCompare("layout") == .orderedSame &&
            ($0.xmlID?.caseInsensitiveCompare("normal") == .orderedSame ||
             container.children.filter { $0.typeName.caseInsensitiveCompare("layout") == .orderedSame }.count == 1)
        }) else {
            throw WalFailure(WalDiagnostic(.malformedXML,
                                           "Winamp Modern skin has no '\(containerID)'/normal container layout."))
        }
        self.container = container
        self.layout = layout
        let width = Self.dimension(layout.attributes, keys: ["default_w", "w", "minimum_w"], fallback: 275)
        let height = Self.dimension(layout.attributes, keys: ["default_h", "h", "minimum_h"], fallback: 116)
        self.canvasSize = CGSize(width: width, height: height)
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
        loadedSkin.runtime.graph.markAllDirty(.appearance)
    }

    private var paletteCache: WasabiPalette?

    /// The colours NullPlayer's own surfaces draw with inside this skin, resolved through the very
    /// same resource + gamma path the skin's own drawing uses.
    var palette: WasabiPalette {
        if let paletteCache { return paletteCache }
        let palette = WasabiPalette.make { [weak self] identifier in
            guard let self,
                  let definition = loadedSkin.runtime.resources.resolvedDefinition(identifier: identifier),
                  definition.kind == "color" else { return nil }
            return resolvedColor(identifier)
        }
        paletteCache = palette
        return palette
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

    /// What the layout itself declares — the floor the protective probe starts searching from.
    private var declaredMinimumSize: CGSize {
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
        loadedSkin.runtime.graph.markAllDirty(.geometry)
        return canvasSize
    }

    func sceneNodes() -> [WasabiSceneNode] { sceneNodes(canvas: canvasSize) }

    private func sceneNodes(canvas: CGSize) -> [WasabiSceneNode] {
        let rootRect = CGRect(origin: .zero, size: canvas)
        var nodes: [WasabiSceneNode] = []
        append(object: layout, frame: rootRect, clip: rootRect, into: &nodes, isRoot: true)
        return nodes
    }

    func draw(in context: CGContext, pressed: WasabiObjectID? = nil,
              hovered: WasabiObjectID? = nil) {
        context.saveGState()
        context.translateBy(x: 0, y: canvasSize.height)
        context.scaleBy(x: 1, y: -1)
        context.interpolationQuality = .high
        for node in sceneNodes() {
            draw(node, in: context, pressed: pressed, hovered: hovered)
        }
        context.restoreGState()
        loadedSkin.runtime.markFirstPaintComplete()
    }

    func object(at point: CGPoint, interactiveOnly: Bool = true) -> WasabiObject? {
        for node in sceneNodes().reversed() where node.clip.contains(point) && node.frame.contains(point) {
            let object = node.object
            guard isVisible(object), object.attributes["ghost"] != "1" else { continue }
            if interactiveOnly && !isInteractive(object) { continue }
            if !interactiveOnly && !isRenderable(object, bitmapID: node.bitmapID) { continue }
            if let bitmap = resources.bitmap(identifier: node.bitmapID) {
                let local = CGPoint(x: (point.x - node.frame.minX) / max(1, node.frame.width) * CGFloat(bitmap.width),
                                    y: (point.y - node.frame.minY) / max(1, node.frame.height) * CGFloat(bitmap.height))
                guard bitmap.alpha(at: local) > 8 else { continue }
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
            guard let kind = Self.componentKind(of: node.object) else { return nil }
            if kind == .other, let diagnostic = Self.unknownComponentDiagnostic(for: node.object) {
                loadedSkin.runtime.record(diagnostic)
            }
            return WinampModernComponentHolder(object: node.object, kind: kind, frame: node.frame)
        }
    }

    func componentHolder(at point: CGPoint) -> WinampModernComponentHolder? {
        componentHolders().reversed().first { $0.frame.contains(point) }
    }

    /// The kind a holder element hosts. `<component param="guid:…">` is the third holder form (the
    /// one mmd3/CornerAmp/Winamp Modern actually use for their playlist and library content), and it
    /// names its component in `param` rather than in `hold`.
    static func componentKind(of object: WasabiObject) -> WinampModernComponentKind? {
        let reference = componentReference(of: object)
        guard let reference else { return nil }
        // A holder that names something unrecognizable stays in the scene as an inert `.other` frame:
        // an unknown GUID must never fall through to a host surface it did not ask for.
        return WinampModernComponentRegistry.kind(for: reference) ?? .other
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
                return value
            }
        }
        // Named engine holders encode the kind in their id (`centro.windowholder.library`) and carry
        // no explicit reference at all.
        return object.attributes["id"].flatMap {
            WinampModernComponentRegistry.kindFromHolderIdentifier($0) != nil ? $0 : nil
        }
    }

    private static func unknownComponentDiagnostic(for object: WasabiObject) -> WalDiagnostic? {
        guard let reference = componentReference(of: object),
              WinampModernComponentRegistry.kind(for: reference) == nil else { return nil }
        return WalDiagnostic(.unknownComponent,
                             "<\(object.typeName)> names unknown component '\(reference)'; "
                             + "it renders as an inert frame.",
                             severity: .warning)
    }

    /// Row height of the embedded playlist, in skin pixels.
    var playlistRowHeight: CGFloat { 12 }

    func playlistVisibleRowCount(in frame: CGRect) -> Int {
        max(0, Int(frame.height / playlistRowHeight))
    }

    /// Which playlist row (absolute index, accounting for scroll) sits under a point in a holder.
    func playlistRow(at point: CGPoint, in frame: CGRect) -> Int? {
        guard frame.contains(point), playlistRowHeight > 0 else { return nil }
        let row = Int((point.y - frame.minY) / playlistRowHeight) + playlistScrollOffset
        return row >= 0 ? row : nil
    }

    func scrollPlaylist(byRows delta: Int, rowCount: Int, in frame: CGRect) {
        let maxOffset = max(0, rowCount - playlistVisibleRowCount(in: frame))
        playlistScrollOffset = max(0, min(maxOffset, playlistScrollOffset + delta))
    }

    func teardown() {
        themeCoordinator.removeObserver(self)
        resources.teardown()
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
                        into nodes: inout [WasabiSceneNode], isRoot: Bool = false) {
        guard isVisible(object) else { return }
        let bitmapID = resolvedBitmapID(for: object, pressed: false, hovered: false)
        var intrinsic = resources.bitmap(identifier: bitmapID).map {
            WasabiSize(width: Double($0.width), height: Double($0.height))
        } ?? .zero
        // `autowidthsource="<id>"` sizes a group to the text of the named descendant. ClassicPro's
        // menu bar is five such groups: without this each is 0 wide and its label, a `relatw="1"`
        // child, has nowhere to draw — the whole File/Play/Options/View/Help strip disappears.
        if object.attributes["w"] == nil, let width = autoWidth(of: object) {
            intrinsic.width = Double(width)
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
            resolved = CGRect(x: box.x, y: box.y, width: box.width, height: box.height)
        }
        // An object parked outside its parent draws nothing, and neither do its children. Skins use
        // that as a hiding place: MMD3 keeps a dummy volume slider at (400,400) — outside the 583×216
        // layout — whose `thumb` is the 44×1012 knob *sheet*, and a slider centres its thumb on its
        // track, so without this the whole sheet painted a column of knobs across the window.
        if !resolved.isEmpty && !resolved.intersects(parentClip) { return }
        let clip = parentClip.intersection(resolved.isEmpty ? parentClip : resolved)
        nodes.append(WasabiSceneNode(object: object, frame: resolved, clip: parentClip,
                                     bitmapID: bitmapID, parentFrame: isRoot ? resolved : parentFrame))
        let childClip = clipsChildren(object) ? clip : parentClip
        for child in object.children {
            append(object: child, frame: resolved, clip: childClip, into: &nodes)
        }
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
        context.draw(image, in: rect)
        context.restoreGState()
    }

    private func draw(_ node: WasabiSceneNode, in context: CGContext,
                      pressed: WasabiObjectID?, hovered: WasabiObjectID?) {
        let object = node.object
        let type = object.typeName.lowercased()
        context.saveGState()
        context.clip(to: node.clip)

        if let background = object.attributes["background"],
           let bitmap = resources.bitmap(identifier: background) {
            drawImage(bitmap.image, in: node.frame, context: context)
        }

        if type == "text" || type == "songticker" {
            drawText(object, frame: node.frame, context: context)
        } else if type == "slider" {
            drawSlider(object, frame: node.frame, context: context,
                       pressed: pressed == object.stableID)
        } else if type == "vis" {
            drawVisualization(object, frame: node.frame, context: context)
        } else if type == "eqvis" {
            drawEQVis(object, frame: node.frame, context: context)
        } else if type == "albumart" {
            if let artwork = host.albumArtwork {
                drawImage(artwork, in: node.frame, context: context)
            } else if let fallback = object.attributes["notfoundimage"],
                      let bitmap = resources.bitmap(identifier: fallback) {
                draw(bitmap, object: object, frame: node.frame, context: context)
            }
        } else if WinampModernComponentRegistry.isHolderElement(type),
                  let kind = Self.componentKind(of: object) {
            drawComponent(kind: kind, frame: node.frame, context: context)
        } else if let imageID = resolvedBitmapID(for: object,
                                                  pressed: pressed == object.stableID,
                                                  hovered: hovered == object.stableID),
                  let bitmap = resources.bitmap(identifier: imageID) {
            if type == "animatedlayer" {
                drawAnimated(bitmap, object: object, frame: node.frame, context: context)
            } else {
                draw(bitmap, object: object, frame: node.frame, context: context)
            }
        }
        context.restoreGState()
    }

    private func draw(_ bitmap: WasabiBitmap, object: WasabiObject,
                      frame: CGRect, context: CGContext) {
        let alpha = max(0, min(255, Int(Double(object.attributes["alpha"] ?? "255") ?? 255)))
        context.setAlpha(CGFloat(alpha) / 255)
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
        let columns = tileX ? Int(ceil(frame.width / tileWidth)) : 1
        let rows = tileY ? Int(ceil(frame.height / tileHeight)) : 1
        // A degenerate tile against a huge frame must not turn into an unbounded draw loop.
        guard columns * rows <= 8_192 else {
            drawImage(bitmap.image, in: frame, context: context)
            return
        }
        context.saveGState()
        context.clip(to: frame)
        // Tiles are blitted 1:1; smoothing would resample each tile's edge and leave a visible seam
        // grid across every tiled background strip.
        context.interpolationQuality = .none
        for row in 0..<rows {
            for column in 0..<columns {
                let rect = CGRect(x: frame.minX + CGFloat(column) * tileWidth,
                                  y: frame.minY + CGFloat(row) * tileHeight,
                                  width: tileX ? tileWidth : frame.width,
                                  height: tileY ? tileHeight : frame.height)
                drawImage(bitmap.image, in: rect, context: context)
            }
        }
        context.restoreGState()
    }

    private func drawText(_ object: WasabiObject, frame: CGRect, context: CGContext) {
        // Content resolution (`display=`, a songticker's implicit track title, `setAlternateText`)
        // is shared with the measurement a script's `getAutoWidth()` gets — see `WasabiTextMetrics`.
        drawText(WasabiTextMetrics.content(of: object, host: host),
                 object: object, frame: frame, context: context)
    }

    private func drawText(_ text: String, object: WasabiObject, frame rawFrame: CGRect, context: CGContext) {
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
        let font = resources.font(identifier: object.attributes["font"], size: size)
            ?? NSFont.systemFont(ofSize: size)
        // Optional for the same reason as the font: nothing that ends up in a CoreText attribute
        // dictionary may be a null pointer, and only an `Optional` binding can see one.
        let resolved: NSColor? = resolvedColor(object.attributes["color"] ?? "255,255,255")
        let color = resolved ?? .white
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
        let measured = (text as NSString).size(withAttributes: attributes).width
        let overflow = measured - frame.width
        let scroll = overflow > 0 ? tickerMotion(for: object, overflow: overflow, textWidth: measured) : nil
        if scroll != nil {
            // While scrolling, the string is drawn into an oversized rect, so any alignment other
            // than left would re-centre it inside that rect and cancel the motion out.
            paragraph.alignment = .left
            attributes[.paragraphStyle] = paragraph
        }

        context.saveGState()
        context.clip(to: frame)
        context.translateBy(x: 0, y: frame.midY)
        context.scaleBy(x: 1, y: -1)
        context.translateBy(x: 0, y: -frame.midY)
        if let scroll {
            var textFrame = frame
            textFrame.origin.x -= scroll.offset
            textFrame.size.width = measured
            (text as NSString).draw(in: textFrame, withAttributes: attributes)
            if scroll.wraps {
                // Continuous mode runs the tail off the left edge, so draw a second copy a gap
                // behind it; otherwise the ticker would blank out between cycles.
                textFrame.origin.x += measured + Self.tickerGap
                (text as NSString).draw(in: textFrame, withAttributes: attributes)
            }
        } else {
            (text as NSString).draw(in: frame, withAttributes: attributes)
        }
        context.restoreGState()
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
                       ticker: object, context: context)
    }

    /// Draw a run of bitmap-font glyphs. `ticker` is the object whose scroll state applies, or nil for
    /// content NullPlayer draws itself (a playlist row never scrolls).
    private func drawBitmapText(_ text: String, definition: WalResourceDefinition, frame: CGRect,
                                alignment: NSTextAlignment, ticker: WasabiObject?,
                                context: CGContext) {
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
                   let glyph = sheet.image.cropping(to: cropRect) {
                    drawImage(glyph, in: CGRect(x: x, y: frame.minY,
                                                width: CGFloat(charWidth), height: CGFloat(charHeight)),
                              context: context)
                }
                x += CGFloat(advance)
            }
        }
        context.restoreGState()
    }

    private func drawAnimated(_ bitmap: WasabiBitmap, object: WasabiObject,
                              frame: CGRect, context: CGContext) {
        let frameWidth = max(1, Int(Double(object.attributes["framewidth"] ?? object.attributes["w"] ?? "") ?? Double(bitmap.width)))
        let frameHeight = max(1, Int(Double(object.attributes["frameheight"] ?? object.attributes["h"] ?? "") ?? Double(bitmap.height)))
        let columns = max(1, bitmap.width / frameWidth)
        let rows = max(1, bitmap.height / frameHeight)
        let count = max(1, Int(Double(object.attributes["frames"] ?? "") ?? Double(columns * rows)))
        let frameIndex = max(0, min(count - 1, WasabiAnimation.state(of: object, frameCount: count,
                                                                     clock: clock()).frame))
        let column = frameIndex % columns
        let row = frameIndex / columns
        let crop = CGRect(x: column * frameWidth, y: row * frameHeight,
                          width: frameWidth, height: frameHeight)
        guard crop.maxY <= CGFloat(bitmap.height), crop.maxX <= CGFloat(bitmap.width),
              let image = bitmap.image.cropping(to: crop) else { return }
        drawImage(image, in: frame, context: context)
    }

    /// `<vis mode>` — which visualization the skin wants in this box, and whether it wants one at all.
    ///
    /// The values are the ones a skin's own script switches between: MMD3's `ShowVISBg` sets 1 for its
    /// oscilloscope display, 2 for its analyzer display, and **3 whenever its own animated display is
    /// showing** — which is the shipped default (`mode="3"`), and which is why our bars were being
    /// painted straight over the skin's artwork. `setMode` writes the same attribute.
    private enum VisualizationMode {
        case oscilloscope, analyzer, off

        init(attribute: String?) {
            switch attribute?.trimmingCharacters(in: .whitespaces) {
            case "1": self = .oscilloscope
            case "0", "3": self = .off
            // A skin that declares no mode gets the analyzer, which is what a `<vis>` box is for.
            default: self = .analyzer
            }
        }
    }

    private func drawVisualization(_ object: WasabiObject, frame: CGRect, context: CGContext) {
        guard !host.spectrumLevels.isEmpty, frame.width > 0, frame.height > 0 else { return }
        let levels = host.spectrumLevels
        let count = min(64, levels.count)
        guard count > 0 else { return }
        func color(_ index: Int) -> CGColor {
            resolvedColor(object.attributes["colorband\(min(16, index + 1))"] ?? "255,255,255").cgColor
        }
        switch VisualizationMode(attribute: object.attributes["mode"]) {
        case .off:
            return
        case .analyzer:
            let width = frame.width / CGFloat(count)
            for index in 0..<count {
                let level = CGFloat(max(0, min(1, levels[index])))
                context.setFillColor(color(index))
                context.fill(CGRect(x: frame.minX + CGFloat(index) * width,
                                    y: frame.maxY - level * frame.height,
                                    width: max(1, width - 1), height: level * frame.height))
            }
        case .oscilloscope:
            // Drawn from the same band levels, mirrored about the centre line: the host publishes a
            // spectrum, not raw PCM, so this is the shape of the signal rather than the waveform
            // itself. It keeps a skin that asks for a scope from showing an analyzer instead.
            let step = frame.width / CGFloat(max(1, count - 1))
            context.saveGState()
            context.setLineWidth(1)
            context.setStrokeColor(color(0))
            context.beginPath()
            for index in 0..<count {
                let level = CGFloat(max(0, min(1, levels[index])))
                let point = CGPoint(x: frame.minX + CGFloat(index) * step,
                                    y: frame.midY + (index % 2 == 0 ? -1 : 1) * level * frame.height / 2)
                if index == 0 { context.move(to: point) } else { context.addLine(to: point) }
            }
            context.strokePath()
            context.restoreGState()
        }
    }

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

    private func drawSlider(_ object: WasabiObject, frame: CGRect, context: CGContext, pressed: Bool) {
        guard frame.width > 0, frame.height > 0 else { return }
        let thumbID = pressed ? (object.attributes["downthumb"] ?? object.attributes["thumb"])
                              : object.attributes["thumb"]
        guard let thumb = resources.bitmap(identifier: thumbID) else { return }
        let action = object.attributes["action"]?.lowercased()
        let normalized: CGFloat
        if action == "volume" {
            normalized = CGFloat(host.volume)
        } else if action == "seek", host.duration > 0 {
            normalized = CGFloat(host.currentTime / host.duration)
        } else if let eq = WinampModernEQAction.decode(action: object.attributes["action"],
                                                       parameter: object.attributes["param"]),
                  let snapshot = componentHost?.equalizerSnapshot() {
            // The thumb reads the same snapshot the drag writes, so a preset applied from a menu (or
            // from outside the skin entirely) moves the slider.
            normalized = eq.normalizedValue(in: snapshot)
        } else {
            let low = Double(object.attributes["low"] ?? "0") ?? 0
            let high = Double(object.attributes["high"] ?? "255") ?? 255
            let value = Double(object.attributes["value"] ?? "0") ?? 0
            normalized = high == low ? 0 : CGFloat((value - low) / (high - low))
        }
        let clamped = max(0, min(1, normalized))
        let vertical = object.attributes["orientation"]?.lowercased() == "vertical"
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
    private func drawComponent(kind: WinampModernComponentKind, frame: CGRect, context: CGContext) {
        guard frame.width > 1, frame.height > 1 else { return }
        switch kind {
        case .playlist: drawPlaylistComponent(frame: frame, context: context)
        case .equalizer: drawEqualizerComponent(frame: frame, context: context)
        case .visualization:
            context.setFillColor(NSColor.black.cgColor)
            context.fill(frame)
            drawVisualizationBars(frame: frame, context: context)
        case .library, .video, .other:
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

    private func drawPlaylistComponent(frame: CGRect, context: CGContext) {
        // Drawn by us, coloured by the skin: the list sits inside the skin's own frame, so its text
        // and selection follow the skin's colour resources and its active colour theme.
        let palette = palette
        context.setFillColor(palette.contentBackground.cgColor)
        context.fill(frame)
        guard let snapshot = componentHost?.playlistSnapshot() else { return }
        let visible = playlistVisibleRowCount(in: frame)
        guard visible > 0 else { return }
        // Keep the scroll offset in range as the list changes.
        let maxOffset = max(0, snapshot.rows.count - visible)
        let offset = max(0, min(maxOffset, playlistScrollOffset))
        let font = NSFont.systemFont(ofSize: 9)
        context.saveGState()
        context.clip(to: frame)
        for slot in 0..<visible {
            let index = offset + slot
            guard index < snapshot.rows.count else { break }
            let row = snapshot.rows[index]
            let rowRect = CGRect(x: frame.minX, y: frame.minY + CGFloat(slot) * playlistRowHeight,
                                 width: frame.width, height: playlistRowHeight)
            if index == snapshot.selectedIndex {
                context.setFillColor(palette.selectionBackground.cgColor)
                context.fill(rowRect)
            }
            let color = row.isCurrent ? palette.currentText
                : (index == snapshot.selectedIndex ? palette.selectionText : palette.listText)
            let label = "\(index + 1). \(row.title)"
            drawSurfaceText(label, in: rowRect.insetBy(dx: 3, dy: 1), color: color,
                            alignment: .left, pointSize: font.pointSize, context: context)
            if row.duration > 0 {
                let seconds = Int(row.duration)
                let time = String(format: "%d:%02d", seconds / 60, seconds % 60)
                drawSurfaceText(time, in: rowRect.insetBy(dx: 3, dy: 1), color: color,
                                alignment: .right, pointSize: font.pointSize, context: context)
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

    private func drawVisualizationBars(frame: CGRect, context: CGContext) {
        guard !host.spectrumLevels.isEmpty else { return }
        let levels = host.spectrumLevels
        let count = min(64, levels.count)
        let width = frame.width / CGFloat(count)
        context.setFillColor(NSColor(red: 0.3, green: 0.9, blue: 0.4, alpha: 1).cgColor)
        for index in 0..<count {
            let level = CGFloat(max(0, min(1, levels[index])))
            context.fill(CGRect(x: frame.minX + CGFloat(index) * width,
                                y: frame.maxY - level * frame.height,
                                width: max(1, width - 1), height: level * frame.height))
        }
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
        return value == "1" || value == "true"
    }

    private static func dimension(_ attributes: [String: String], keys: [String], fallback: CGFloat) -> CGFloat {
        for key in keys {
            if let raw = attributes[key], let value = Double(raw), value > 0 { return CGFloat(value) }
        }
        return fallback
    }

    private func defaultSize(for layout: WasabiObject) -> CGSize {
        CGSize(width: Self.dimension(layout.attributes, keys: ["default_w", "w", "minimum_w"], fallback: 275),
               height: Self.dimension(layout.attributes, keys: ["default_h", "h", "minimum_h"], fallback: 116))
    }

    private static func optionalDimension(_ raw: String?) -> CGFloat? {
        guard let raw, let value = Double(raw), value > 0 else { return nil }
        return CGFloat(value)
    }

    private static func color(_ raw: String) -> NSColor {
        let values = raw.split(separator: ",").compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
        guard values.count >= 3 else { return .white }
        return NSColor(red: max(0, min(255, values[0])) / 255,
                       green: max(0, min(255, values[1])) / 255,
                       blue: max(0, min(255, values[2])) / 255,
                       alpha: 1)
    }

    func resolvedColor(_ raw: String) -> NSColor {
        guard let definition = loadedSkin.runtime.resources.resolvedDefinition(identifier: raw),
              definition.kind == "color" else { return Self.color(raw) }
        let base = definition.attributes["value"] ?? "255,255,255"
        var values = base.split(separator: ",").map { CGFloat(Double($0.trimmingCharacters(in: .whitespaces)) ?? 255) }
        guard values.count >= 3 else { return .white }
        let gamma = themes.transform(group: definition.attributes["gammagroup"]) ?? .identity
        if gamma.grayscale {
            // Same order as the bitmap path: desaturate, then tint.
            let luminance = values[0] * 0.299 + values[1] * 0.587 + values[2] * 0.114
            values = [luminance, luminance, luminance]
        }
        let r = values[0] / 255 * gamma.red
        let g = values[1] / 255 * gamma.green
        let b = values[2] / 255 * gamma.blue
        return NSColor(red: max(0, min(1, r)), green: max(0, min(1, g)),
                       blue: max(0, min(1, b)), alpha: 1)
    }
}
