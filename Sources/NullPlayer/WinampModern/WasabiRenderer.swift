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
    private var fonts: [String: CGFont] = [:]
    private var currentCost = 0
    private var accessCounter: UInt64 = 0
    private(set) var isTornDown = false

    init(loadedSkin: WinampModernLoadedSkin, themes: WasabiColorThemeCatalog,
         maximumCost: Int = 256 * 1_024 * 1_024) {
        self.loadedSkin = loadedSkin
        self.themes = themes
        self.maximumCost = maximumCost
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

    func teardown() {
        bitmaps.removeAll()
        fonts.removeAll()
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
}

final class WasabiSceneRenderer {
    let loadedSkin: WinampModernLoadedSkin
    let host: WinampModernHost
    let resources: WasabiResourceCache
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
        self.themes = WasabiColorThemeCatalog(loadedSkin: loadedSkin)
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
    }

    @discardableResult
    func activateTheme(_ name: String) -> Bool {
        guard themes.activate(name) else { return false }
        resources.invalidateTheme()
        loadedSkin.runtime.graph.markAllDirty(.appearance)
        return true
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

    @discardableResult
    func resize(to proposedSize: CGSize) -> CGSize {
        let minimumWidth = Self.dimension(layout.attributes, keys: ["minimum_w"], fallback: 1)
        let minimumHeight = Self.dimension(layout.attributes, keys: ["minimum_h"], fallback: 1)
        let maximumWidth = Self.optionalDimension(layout.attributes["maximum_w"]) ?? 16_384
        let maximumHeight = Self.optionalDimension(layout.attributes["maximum_h"]) ?? 16_384
        canvasSize = CGSize(width: max(minimumWidth, min(maximumWidth, proposedSize.width)),
                            height: max(minimumHeight, min(maximumHeight, proposedSize.height)))
        loadedSkin.runtime.graph.markAllDirty(.geometry)
        return canvasSize
    }

    func sceneNodes() -> [WasabiSceneNode] {
        let rootRect = CGRect(origin: .zero, size: canvasSize)
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

    // MARK: - Embedded component hosting

    /// Every `windowholder`/`componentbucket` in the active scene whose `hold`/id resolves to a
    /// typed component kind, with its frame in skin coordinates. Used to draw embedded playlist/EQ,
    /// place the library host view, and route input into the right surface.
    func componentHolders() -> [WinampModernComponentHolder] {
        sceneNodes().compactMap { node in
            let type = node.object.typeName.lowercased()
            guard type == "windowholder" || type == "componentbucket" else { return nil }
            guard isVisible(node.object) else { return nil }
            guard let kind = Self.componentKind(of: node.object) else { return nil }
            return WinampModernComponentHolder(object: node.object, kind: kind, frame: node.frame)
        }
    }

    func componentHolder(at point: CGPoint) -> WinampModernComponentHolder? {
        componentHolders().reversed().first { $0.frame.contains(point) }
    }

    static func componentKind(of object: WasabiObject) -> WinampModernComponentKind? {
        for key in ["hold", "component", "guid", "id"] {
            if let kind = WinampModernComponentRegistry.kind(for: object.attributes[key]) { return kind }
        }
        return nil
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

    func teardown() { resources.teardown() }

    private func append(object: WasabiObject, frame parentFrame: CGRect, clip parentClip: CGRect,
                        into nodes: inout [WasabiSceneNode], isRoot: Bool = false) {
        guard isVisible(object) else { return }
        let bitmapID = resolvedBitmapID(for: object, pressed: false, hovered: false)
        let intrinsic = resources.bitmap(identifier: bitmapID).map {
            WasabiSize(width: Double($0.width), height: Double($0.height))
        } ?? .zero
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
            ).standardized
            resolved = CGRect(x: wasabi.x, y: wasabi.y, width: wasabi.width, height: wasabi.height)
        }
        // An object parked outside its parent draws nothing, and neither do its children. Skins use
        // that as a hiding place: MMD3 keeps a dummy volume slider at (400,400) — outside the 583×216
        // layout — whose `thumb` is the 44×1012 knob *sheet*, and a slider centres its thumb on its
        // track, so without this the whole sheet painted a column of knobs across the window.
        if !resolved.isEmpty && !resolved.intersects(parentClip) { return }
        let clip = parentClip.intersection(resolved.isEmpty ? parentClip : resolved)
        nodes.append(WasabiSceneNode(object: object, frame: resolved, clip: parentClip,
                                     bitmapID: bitmapID))
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
        } else if type == "albumart" {
            if let artwork = host.albumArtwork {
                drawImage(artwork, in: node.frame, context: context)
            } else if let fallback = object.attributes["notfoundimage"],
                      let bitmap = resources.bitmap(identifier: fallback) {
                draw(bitmap, object: object, frame: node.frame, context: context)
            }
        } else if (type == "windowholder" || type == "componentbucket"),
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
        let display = object.attributes["display"]?.lowercased()
        let text: String
        // `setAlternateText` temporarily overrides whatever the object would otherwise show; the
        // script clears it with "" to hand the display back.
        if let alternate = object.attributes["alternatetext"], !alternate.isEmpty {
            drawText(alternate, object: object, frame: frame, context: context)
            return
        }
        switch display {
        case "time":
            let seconds = max(0, Int(host.currentTime))
            text = String(format: "%d:%02d", seconds / 60, seconds % 60)
        case "songname": text = host.trackTitle
        case "songinfo": text = host.trackInfo
        default:
            // A `songticker` carries no `text`/`default` — its content *is* the current track, which
            // is why the main display stayed blank while the bitmap-font timer worked.
            if object.typeName.caseInsensitiveCompare("songticker") == .orderedSame {
                text = host.trackDisplayTitle
            } else {
                text = object.attributes["text"] ?? object.attributes["default"] ?? ""
            }
        }
        drawText(text, object: object, frame: frame, context: context)
    }

    private func drawText(_ text: String, object: WasabiObject, frame: CGRect, context: CGContext) {
        if let fontID = object.attributes["font"],
           let definition = loadedSkin.runtime.resources.resolvedDefinition(identifier: fontID),
           definition.kind == "bitmapfont" {
            drawBitmapText(text, definition: definition, object: object, frame: frame, context: context)
            return
        }
        // A skin (or one of its scripts) can name any point size at all, including 0, a negative, or
        // something that does not parse. CoreText builds its own attribute dictionary from whatever
        // it is handed, and an unusable size or font there aborts the process from inside a draw.
        let requested = Double(object.attributes["fontsize"] ?? "11") ?? 11
        let size = CGFloat(requested.isFinite ? min(max(requested, 1), 256) : 11)
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
        guard let sheet = resources.bitmap(identifier: definition.attributes["file"]) else { return }
        let charWidth = max(1, Int(Double(definition.attributes["charwidth"] ?? "1") ?? 1))
        let charHeight = max(1, Int(Double(definition.attributes["charheight"] ?? "1") ?? 1))
        let spacing = Int(Double(definition.attributes["hspacing"] ?? "0") ?? 0)
        let advance = max(1, charWidth + spacing)
        let mapRows = [Array("abcdefghijklmnopqrstuvwxyz\"@  "),
                       Array("0123456789….:()-'!_+\\/[]^&%,=$#\nâöä?*")]
        var positions: [Character: (Int, Int)] = [:]
        for (row, characters) in mapRows.enumerated() {
            for (column, character) in characters.enumerated() { positions[character] = (column, row) }
        }
        let width = CGFloat(text.count * advance)
        var startX: CGFloat
        switch object.attributes["align"]?.lowercased() {
        case "center": startX = frame.midX - width / 2
        case "right": startX = frame.maxX - width
        default: startX = frame.minX
        }
        // Bitmap-font tickers share the TrueType path's motion model. The previous formula anchored
        // the run at `frame.maxX`, so at rest the text sat entirely off the right edge and a long
        // title simply vanished instead of scrolling.
        var repeats: [CGFloat] = []
        if width > frame.width, let scroll = tickerMotion(for: object, overflow: width - frame.width,
                                                          textWidth: width) {
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

    private func drawVisualization(_ object: WasabiObject, frame: CGRect, context: CGContext) {
        guard !host.spectrumLevels.isEmpty, frame.width > 0, frame.height > 0 else { return }
        let levels = host.spectrumLevels
        let count = min(64, levels.count)
        let width = frame.width / CGFloat(count)
        for index in 0..<count {
            let level = CGFloat(max(0, min(1, levels[index])))
            let colorName = object.attributes["colorband\(min(16, index + 1))"] ?? "255,255,255"
            context.setFillColor(resolvedColor(colorName).cgColor)
            context.fill(CGRect(x: frame.minX + CGFloat(index) * width,
                                y: frame.maxY - level * frame.height,
                                width: max(1, width - 1), height: level * frame.height))
        }
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
            context.setFillColor(NSColor(white: 0.06, alpha: 1).cgColor)
            context.fill(frame)
        }
    }

    private func drawPlaylistComponent(frame: CGRect, context: CGContext) {
        context.setFillColor(NSColor(white: 0.04, alpha: 1).cgColor)
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
            if row.isCurrent {
                context.setFillColor(NSColor(red: 0.12, green: 0.2, blue: 0.32, alpha: 1).cgColor)
                context.fill(rowRect)
            } else if index == snapshot.selectedIndex {
                context.setFillColor(NSColor(white: 0.16, alpha: 1).cgColor)
                context.fill(rowRect)
            }
            let color = row.isCurrent ? NSColor(red: 0.6, green: 0.85, blue: 1, alpha: 1)
                                      : NSColor(white: 0.75, alpha: 1)
            let label = "\(index + 1). \(row.title)"
            drawFlippedText(label, in: rowRect.insetBy(dx: 3, dy: 1), font: font, color: color,
                            alignment: .left, context: context)
            if row.duration > 0 {
                let seconds = Int(row.duration)
                let time = String(format: "%d:%02d", seconds / 60, seconds % 60)
                drawFlippedText(time, in: rowRect.insetBy(dx: 3, dy: 1), font: font, color: color,
                                alignment: .right, context: context)
            }
        }
        context.restoreGState()
    }

    private func drawEqualizerComponent(frame: CGRect, context: CGContext) {
        context.setFillColor(NSColor(white: 0.05, alpha: 1).cgColor)
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
            context.setFillColor((snapshot.enabled ? NSColor(red: 0.4, green: 0.8, blue: 1, alpha: 1)
                                                    : NSColor(white: 0.5, alpha: 1)).cgColor)
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
            let active = (id == "shuffle" && host.shuffleEnabled) || (id == "repeat" && host.repeatEnabled)
            if active, let image = object.attributes["activeimage"] { return image }
        }
        return object.attributes["image"]
    }

    private func isInteractive(_ object: WasabiObject) -> Bool {
        let type = object.typeName.lowercased()
        return type == "button" || type == "togglebutton" || type == "nstatesbutton" || type == "slider" ||
            object.attributes["action"] != nil || object.attributes["move"] == "1" ||
            (type == "layer" && object.attributes["ghost"] != "1")
    }

    private func isRenderable(_ object: WasabiObject, bitmapID: String?) -> Bool {
        object.attributes["background"] != nil || bitmapID != nil ||
            object.typeName.caseInsensitiveCompare("text") == .orderedSame ||
            object.typeName.caseInsensitiveCompare("songticker") == .orderedSame ||
            object.typeName.caseInsensitiveCompare("vis") == .orderedSame ||
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

    private func resolvedColor(_ raw: String) -> NSColor {
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
