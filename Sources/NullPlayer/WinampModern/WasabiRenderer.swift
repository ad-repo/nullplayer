import AppKit
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

final class WasabiResourceCache {
    let loadedSkin: WinampModernLoadedSkin
    let maximumCost: Int

    private struct CachedBitmap {
        let bitmap: WasabiBitmap
        var access: UInt64
    }
    private var bitmaps: [String: CachedBitmap] = [:]
    private var fonts: [String: CGFont] = [:]
    private var currentCost = 0
    private var accessCounter: UInt64 = 0
    private(set) var isTornDown = false

    init(loadedSkin: WinampModernLoadedSkin, maximumCost: Int = 256 * 1_024 * 1_024) {
        self.loadedSkin = loadedSkin
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
        guard let definition = loadedSkin.runtime.resources.definition(identifier: identifier),
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
              let image = fullImage.cropping(to: CGRect(x: x, y: cropY, width: width, height: height)) else { return nil }
        let cost = width * height * 4
        let bitmap = WasabiBitmap(image: image, width: width, height: height, cost: cost)
        bitmaps[key] = CachedBitmap(bitmap: bitmap, access: accessCounter)
        currentCost += cost
        evictIfNeeded(protecting: key)
        return bitmap
    }

    func font(identifier: String?, size: CGFloat) -> NSFont {
        guard !isTornDown, let identifier,
              let definition = loadedSkin.runtime.resources.definition(identifier: identifier),
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
    let container: WasabiObject
    let layout: WasabiObject
    let canvasSize: CGSize

    init(loadedSkin: WinampModernLoadedSkin, host: WinampModernHost) throws {
        self.loadedSkin = loadedSkin
        self.host = host
        self.resources = WasabiResourceCache(loadedSkin: loadedSkin)
        guard let container = loadedSkin.runtime.graph.roots.first(where: {
            $0.typeName.caseInsensitiveCompare("container") == .orderedSame &&
            $0.xmlID?.caseInsensitiveCompare("main") == .orderedSame
        }), let layout = container.children.first(where: {
            $0.typeName.caseInsensitiveCompare("layout") == .orderedSame &&
            ($0.xmlID?.caseInsensitiveCompare("normal") == .orderedSame || container.children.count == 1)
        }) else {
            throw WalFailure(WalDiagnostic(.malformedXML,
                                           "Winamp Modern skin has no Main/normal container layout."))
        }
        self.container = container
        self.layout = layout
        let width = Self.dimension(layout.attributes, keys: ["default_w", "minimum_w", "w"], fallback: 275)
        let height = Self.dimension(layout.attributes, keys: ["default_h", "minimum_h", "h"], fallback: 116)
        self.canvasSize = CGSize(width: width, height: height)
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

        if type == "text" {
            drawText(object, frame: node.frame, context: context)
        } else if type == "slider" {
            drawSlider(object, frame: node.frame, context: context,
                       pressed: pressed == object.stableID)
        } else if let imageID = resolvedBitmapID(for: object,
                                                  pressed: pressed == object.stableID,
                                                  hovered: hovered == object.stableID),
                  let bitmap = resources.bitmap(identifier: imageID) {
            draw(bitmap, object: object, frame: node.frame, context: context)
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
        let size = CGFloat(Double(object.attributes["fontsize"] ?? "11") ?? 11)
        let font = resources.font(identifier: object.attributes["font"], size: size)
        let color = Self.color(object.attributes["color"] ?? "255,255,255")
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
        if type == "togglebutton" || object.attributes["activeimage"] != nil {
            let id = object.xmlID?.lowercased()
            let active = (id == "shuffle" && host.shuffleEnabled) || (id == "repeat" && host.repeatEnabled)
            if active, let image = object.attributes["activeimage"] { return image }
        }
        return object.attributes["image"]
    }

    private func isInteractive(_ object: WasabiObject) -> Bool {
        let type = object.typeName.lowercased()
        return type == "button" || type == "togglebutton" || type == "slider" ||
            object.attributes["action"] != nil || object.attributes["move"] == "1" ||
            (type == "layer" && object.attributes["ghost"] != "1")
    }

    private func isRenderable(_ object: WasabiObject, bitmapID: String?) -> Bool {
        object.attributes["background"] != nil || bitmapID != nil ||
            object.typeName.caseInsensitiveCompare("text") == .orderedSame ||
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

    private static func color(_ raw: String) -> NSColor {
        let values = raw.split(separator: ",").compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
        guard values.count >= 3 else { return .white }
        return NSColor(red: max(0, min(255, values[0])) / 255,
                       green: max(0, min(255, values[1])) / 255,
                       blue: max(0, min(255, values[2])) / 255,
                       alpha: 1)
    }
}
