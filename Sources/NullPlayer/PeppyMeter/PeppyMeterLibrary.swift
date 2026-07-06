import Foundation
import CoreGraphics
import ImageIO

/// Loads and caches the bundled PeppyMeter meter templates (meters.txt + image assets).
///
/// The bundled meters are GPL-3.0 licensed and live in their own resource folder
/// (`Resources/PeppyMeter/<resolution>/`). See `Resources/ThirdPartyLicenses`.
final class PeppyMeterLibrary {
    static let shared = PeppyMeterLibrary()

    /// Bundled resolution folder. Other resolutions can be added as sibling folders later.
    let resolutionFolder = "480x320"

    private(set) var templates: [PeppyMeterTemplate] = []
    private var imageCache: [String: CGImage] = [:]
    private var sizeCache: [String: CGSize] = [:]
    private var loaded = false

    private var subdirectory: String { "PeppyMeter/\(resolutionFolder)" }

    private init() {}

    /// Parse `meters.txt` once. Safe to call repeatedly.
    func loadIfNeeded() {
        guard !loaded else { return }
        loaded = true
        guard let url = BundleHelper.url(forResource: "meters", withExtension: "txt", subdirectory: subdirectory),
              let text = try? String(contentsOf: url, encoding: .utf8) else {
            return
        }
        // Keep only templates whose background image actually loads.
        templates = PeppyMeterConfig.parse(text).filter { image(named: $0.bgrFilename) != nil }
    }

    var meterNames: [String] { templates.map { $0.name } }

    var isEmpty: Bool {
        loadIfNeeded()
        return templates.isEmpty
    }

    func template(named name: String) -> PeppyMeterTemplate? {
        loadIfNeeded()
        return templates.first { $0.name == name }
    }

    /// The template for `name`, or the first available template as a fallback.
    func templateOrFirst(named name: String?) -> PeppyMeterTemplate? {
        loadIfNeeded()
        if let name, let t = template(named: name) { return t }
        return templates.first
    }

    /// A CGImage for a `meters.txt` filename (e.g. `bar-bgr.png`), cached.
    func image(named filename: String) -> CGImage? {
        if let cached = imageCache[filename] { return cached }
        let ns = filename as NSString
        let ext = ns.pathExtension
        let base = ns.deletingPathExtension
        guard let url = BundleHelper.url(forResource: base, withExtension: ext, subdirectory: subdirectory),
              let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            return nil
        }
        imageCache[filename] = image
        return image
    }

    /// A horizontally-mirrored version of a filename's image (for `flip.left.x` / `flip.right.x`), cached.
    func flippedImage(named filename: String) -> CGImage? {
        let key = "flip:" + filename
        if let cached = imageCache[key] { return cached }
        guard let img = image(named: filename), let flipped = Self.horizontallyFlip(img) else { return nil }
        imageCache[key] = flipped
        return flipped
    }

    private static func horizontallyFlip(_ image: CGImage) -> CGImage? {
        let w = image.width, h = image.height
        guard let ctx = CGContext(
            data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        ctx.translateBy(x: CGFloat(w), y: 0)
        ctx.scaleBy(x: -1, y: 1)
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        return ctx.makeImage()
    }

    /// The native pixel size of a meter, taken from its background image.
    func nativeSize(for template: PeppyMeterTemplate) -> CGSize {
        if let cached = sizeCache[template.bgrFilename] { return cached }
        let size: CGSize
        if let bgr = image(named: template.bgrFilename) {
            size = CGSize(width: bgr.width, height: bgr.height)
        } else {
            size = CGSize(width: 480, height: 320)
        }
        sizeCache[template.bgrFilename] = size
        return size
    }
}

/// User-facing PeppyMeter preferences, persisted to `UserDefaults`
/// (independent of "Remember State on Quit", matching the spectrum settings pattern).
enum PeppyMeterSettings {
    private static let defaults = UserDefaults.standard

    private static let currentMeterKey = "peppyMeterCurrentMeter"
    private static let randomKey = "peppyMeterRandomEnabled"
    private static let randomIntervalKey = "peppyMeterRandomIntervalSeconds"

    static var currentMeter: String? {
        get { defaults.string(forKey: currentMeterKey) }
        set { defaults.set(newValue, forKey: currentMeterKey) }
    }

    static var randomEnabled: Bool {
        get { defaults.bool(forKey: randomKey) }
        set { defaults.set(newValue, forKey: randomKey) }
    }

    /// Seconds between meter switches when Random is on. Defaults to 20.
    static var randomIntervalSeconds: Double {
        get {
            let v = defaults.double(forKey: randomIntervalKey)
            return v > 0 ? v : 20
        }
        set { defaults.set(newValue, forKey: randomIntervalKey) }
    }
}
