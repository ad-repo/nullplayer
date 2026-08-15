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

    func alpha(at point: CGPoint) -> UInt8 {
        let x = Int(point.x.rounded(.down))
        let y = Int(point.y.rounded(.down))
        guard x >= 0, y >= 0, x < width, y < height else { return 0 }
        var pixel = [UInt8](repeating: 0, count: 4)
        pixel.withUnsafeMutableBytes { bytes in
            guard let context = CGContext(data: bytes.baseAddress, width: 1, height: 1,
                                          bitsPerComponent: 8, bytesPerRow: 4,
                                          space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return }
            context.translateBy(x: CGFloat(-x), y: CGFloat(-(height - y - 1)))
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        }
        return pixel[3]
    }
}

struct WasabiGammaTransform: Equatable {
    let red: CGFloat
    let green: CGFloat
    let blue: CGFloat
    let grayscale: Bool
    let boost: Bool
}

final class WasabiColorThemeCatalog {
    private let loadedSkin: WinampModernLoadedSkin
    private var sets: [String: [String: WasabiGammaTransform]] = [:]
    private var displayNames: [String: String] = [:]
    private(set) var activeTheme: String = "Default"

    var themeNames: [String] { displayNames.values.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending } }

    init(loadedSkin: WinampModernLoadedSkin) {
        self.loadedSkin = loadedSkin
        func collect(_ nodes: [WalXMLNode]) {
            for node in nodes {
                if node.name.caseInsensitiveCompare("gammaset") == .orderedSame,
                   let name = node.attribute("id"), !name.isEmpty {
                    let key = Self.fold(name)
                    displayNames[key] = name
                    var groups: [String: WasabiGammaTransform] = [:]
                    for child in node.children where child.name.caseInsensitiveCompare("gammagroup") == .orderedSame {
                        guard let id = child.attribute("id") else { continue }
                        let values = Self.components(child.attribute("value") ?? "0,0,0")
                        groups[Self.fold(id)] = WasabiGammaTransform(
                            red: values[0] / 4096, green: values[1] / 4096, blue: values[2] / 4096,
                            grayscale: Self.bool(child.attribute("gray")), boost: Self.bool(child.attribute("boost")))
                    }
                    sets[key] = groups
                }
                collect(node.children)
            }
        }
        collect(loadedSkin.document.roots)
        let stored = loadedSkin.configuration.string(section: "appearance", key: "theme", default: "")
        let storedKey = Self.fold(stored)
        if sets[storedKey] != nil { activeTheme = displayNames[storedKey] ?? stored }
        else { activeTheme = themeNames.first(where: { $0.caseInsensitiveCompare("Default") == .orderedSame }) ?? themeNames.first ?? "Default" }
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

    private static func components(_ raw: String) -> [CGFloat] {
        let parsed = raw.split(separator: ",").map { CGFloat(Double($0.trimmingCharacters(in: .whitespaces)) ?? 0) }
        return (parsed + [0, 0, 0]).prefix(3).map { $0 }
    }
    private static func bool(_ raw: String?) -> Bool { raw == "1" || raw?.lowercased() == "true" }
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
        let cropY = fullImage.height - topY - height
        guard cropY >= 0,
              let cropped = fullImage.cropping(to: CGRect(x: x, y: cropY, width: width, height: height)) else { return nil }
        let image = themed(cropped, transform: themes.transform(group: definition.attributes["gammagroup"]))
        let cost = width * height * 4
        let bitmap = WasabiBitmap(image: image, width: width, height: height, cost: cost)
        bitmaps[key] = CachedBitmap(bitmap: bitmap, access: accessCounter)
        currentCost += cost
        evictIfNeeded(protecting: key)
        return bitmap
    }

    func font(identifier: String?, size: CGFloat) -> NSFont {
        guard !isTornDown, let identifier,
              let definition = loadedSkin.runtime.resources.resolvedDefinition(identifier: identifier),
              definition.kind == "truetypefont", let path = definition.logicalFile else {
            return .monospacedSystemFont(ofSize: size, weight: .regular)
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
            return CTFontCreateWithGraphicsFont(cgFont, size, nil, nil) as NSFont
        }
        return .monospacedSystemFont(ofSize: size, weight: .regular)
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
        guard let transform, transform != WasabiGammaTransform(red: 0, green: 0, blue: 0,
                                                               grayscale: false, boost: false) else { return image }
        var output = CIImage(cgImage: image)
        if transform.grayscale {
            output = output.applyingFilter("CIColorControls", parameters: [kCIInputSaturationKey: 0])
        }
        if transform.boost {
            output = output.applyingFilter("CIColorControls", parameters: [kCIInputContrastKey: 1.2])
        }
        output = output.applyingFilter("CIColorMatrix", parameters: [
            "inputBiasVector": CIVector(x: transform.red, y: transform.green, z: transform.blue, w: 0)
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
        } else {
            let wasabi = object.geometry.resolve(
                in: WasabiRect(x: Double(parentFrame.minX), y: Double(parentFrame.minY),
                               width: Double(parentFrame.width), height: Double(parentFrame.height)),
                intrinsicSize: intrinsic
            ).standardized
            resolved = CGRect(x: wasabi.x, y: wasabi.y, width: wasabi.width, height: wasabi.height)
        }
        let clip = parentClip.intersection(resolved.isEmpty ? parentClip : resolved)
        nodes.append(WasabiSceneNode(object: object, frame: resolved, clip: parentClip,
                                     bitmapID: bitmapID))
        let childClip = clipsChildren(object) ? clip : parentClip
        for child in object.children {
            append(object: child, frame: resolved, clip: childClip, into: &nodes)
        }
    }

    private func draw(_ node: WasabiSceneNode, in context: CGContext,
                      pressed: WasabiObjectID?, hovered: WasabiObjectID?) {
        let object = node.object
        let type = object.typeName.lowercased()
        context.saveGState()
        context.clip(to: node.clip)

        if let background = object.attributes["background"],
           let bitmap = resources.bitmap(identifier: background) {
            context.draw(bitmap.image, in: node.frame)
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
                context.draw(artwork, in: node.frame)
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
        let explicitSize = object.attributes["w"] != nil || object.attributes["h"] != nil
        let shouldScale = object.attributes["scale"] != nil || object.typeName.caseInsensitiveCompare("layout") == .orderedSame
        if explicitSize && !shouldScale {
            context.saveGState()
            context.clip(to: frame)
            context.draw(bitmap.image, in: CGRect(x: frame.minX, y: frame.minY,
                                                  width: CGFloat(bitmap.width), height: CGFloat(bitmap.height)))
            context.restoreGState()
        } else {
            context.draw(bitmap.image, in: frame)
        }
    }

    private func drawText(_ object: WasabiObject, frame: CGRect, context: CGContext) {
        let display = object.attributes["display"]?.lowercased()
        let text: String
        switch display {
        case "time":
            let seconds = max(0, Int(host.currentTime))
            text = String(format: "%d:%02d", seconds / 60, seconds % 60)
        case "songname": text = host.trackTitle
        case "songinfo": text = host.trackInfo
        default: text = object.attributes["text"] ?? object.attributes["default"] ?? ""
        }
        if let fontID = object.attributes["font"],
           let definition = loadedSkin.runtime.resources.resolvedDefinition(identifier: fontID),
           definition.kind == "bitmapfont" {
            drawBitmapText(text, definition: definition, object: object, frame: frame, context: context)
            return
        }
        let size = CGFloat(Double(object.attributes["fontsize"] ?? "11") ?? 11)
        let font = resources.font(identifier: object.attributes["font"], size: size)
        let color = resolvedColor(object.attributes["color"] ?? "255,255,255")
        let alignment: NSTextAlignment
        switch object.attributes["align"]?.lowercased() {
        case "center": alignment = .center
        case "right": alignment = .right
        default: alignment = .left
        }
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = alignment
        paragraph.lineBreakMode = .byClipping
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
        if object.typeName.caseInsensitiveCompare("songticker") == .orderedSame, width > frame.width {
            let travel = width + frame.width
            startX = frame.maxX - CGFloat(clock().truncatingRemainder(dividingBy: Double(travel) / 30) * 30)
        }
        var x = startX
        context.saveGState()
        context.clip(to: frame)
        for character in text.lowercased() {
            let (column, row) = positions[character] ?? positions[" "] ?? (0, 0)
            let cropRect = CGRect(x: column * charWidth,
                                  y: sheet.height - (row + 1) * charHeight,
                                  width: charWidth, height: charHeight)
            if cropRect.minY >= 0, cropRect.maxX <= CGFloat(sheet.width),
               let glyph = sheet.image.cropping(to: cropRect) {
                context.draw(glyph, in: CGRect(x: x, y: frame.minY,
                                              width: CGFloat(charWidth), height: CGFloat(charHeight)))
            }
            x += CGFloat(advance)
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
        let playing = object.attributes["playing"] == "1" || object.attributes["autoplay"] == "1"
        let period = max(0.008, (Double(object.attributes["speed"] ?? "100") ?? 100) / 1_000)
        let selected = Int(object.attributes["frame"] ?? "0") ?? 0
        let frameIndex = max(0, min(count - 1, playing ? Int(clock() / period) % count : selected))
        let column = frameIndex % columns
        let row = frameIndex / columns
        let crop = CGRect(x: column * frameWidth,
                          y: bitmap.height - (row + 1) * frameHeight,
                          width: frameWidth, height: frameHeight)
        guard crop.minY >= 0, crop.maxX <= CGFloat(bitmap.width),
              let image = bitmap.image.cropping(to: crop) else { return }
        context.draw(image, in: frame)
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
        context.draw(thumb.image, in: thumbFrame)
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
            return "\(base)\(state)"
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
        let values = base.split(separator: ",").map { CGFloat(Double($0.trimmingCharacters(in: .whitespaces)) ?? 255) }
        guard values.count >= 3 else { return .white }
        let gamma = themes.transform(group: definition.attributes["gammagroup"])
        let r = values[0] / 255 + (gamma?.red ?? 0)
        let g = values[1] / 255 + (gamma?.green ?? 0)
        let b = values[2] / 255 + (gamma?.blue ?? 0)
        return NSColor(red: max(0, min(1, r)), green: max(0, min(1, g)),
                       blue: max(0, min(1, b)), alpha: 1)
    }
}
