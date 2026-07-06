import Foundation
import CoreGraphics
import ImageIO

/// Loads and caches the bundled PeppyMeter meter templates (meters.txt + image assets).
///
/// The bundled meters are GPL-3.0 licensed and live in their own resource folder
/// (`Resources/PeppyMeter/<resolution>/`). See `Resources/ThirdPartyLicenses`.
final class PeppyMeterLibrary {
    static let shared = PeppyMeterLibrary()

    /// Default catalog used for menus/random selection because it contains the full bundled meter set.
    let defaultResolutionFolder = "480x320"
    private let knownResolutionFolders = ["1280x400", "800x480", "480x320"]

    private(set) var templates: [PeppyMeterTemplate] = []
    private(set) var availableResolutionFolders: [String] = []
    private var templatesByResolution: [String: [PeppyMeterTemplate]] = [:]
    private var imageCache: [String: CGImage] = [:]
    private var sizeCache: [String: CGSize] = [:]
    private var loaded = false

    private init() {}

    /// Parse `meters.txt` once. Safe to call repeatedly.
    func loadIfNeeded() {
        guard !loaded else { return }
        loaded = true

        for folder in knownResolutionFolders {
            guard let parsed = loadTemplates(in: folder), !parsed.isEmpty else { continue }
            templatesByResolution[folder] = parsed
            availableResolutionFolders.append(folder)
        }
        templates = templatesByResolution[defaultResolutionFolder] ?? templatesByResolution.values.first ?? []
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

    func template(named name: String, preferredFor targetSize: CGSize) -> PeppyMeterTemplate? {
        loadIfNeeded()
        for folder in Self.preferredResolutionFolders(for: targetSize, available: availableResolutionFolders) {
            if let template = templatesByResolution[folder]?.first(where: { $0.name == name }) {
                return template
            }
        }
        return template(named: name)
    }

    /// The template for `name`, or the first available template as a fallback.
    func templateOrFirst(named name: String?) -> PeppyMeterTemplate? {
        loadIfNeeded()
        if let name, let t = template(named: name) { return t }
        return templates.first
    }

    /// A CGImage for a `meters.txt` filename (e.g. `bar-bgr.png`), cached.
    func image(named filename: String, for template: PeppyMeterTemplate) -> CGImage? {
        image(named: filename, resolutionFolder: resolvedResolutionFolder(for: template))
    }

    private func image(named filename: String, resolutionFolder: String) -> CGImage? {
        let key = cacheKey(filename, resolutionFolder: resolutionFolder)
        if let cached = imageCache[key] { return cached }
        let ns = filename as NSString
        let ext = ns.pathExtension
        let base = ns.deletingPathExtension
        guard let url = BundleHelper.url(forResource: base, withExtension: ext, subdirectory: subdirectory(for: resolutionFolder)),
              let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            return nil
        }
        imageCache[key] = image
        return image
    }

    /// A horizontally-mirrored version of a filename's image (for `flip.left.x` / `flip.right.x`), cached.
    func flippedImage(named filename: String, for template: PeppyMeterTemplate) -> CGImage? {
        let resolutionFolder = resolvedResolutionFolder(for: template)
        let key = "flip:" + cacheKey(filename, resolutionFolder: resolutionFolder)
        if let cached = imageCache[key] { return cached }
        guard let img = image(named: filename, resolutionFolder: resolutionFolder),
              let flipped = Self.horizontallyFlip(img) else {
            return nil
        }
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
        let key = cacheKey(template.bgrFilename, resolutionFolder: resolvedResolutionFolder(for: template))
        if let cached = sizeCache[key] { return cached }
        let size: CGSize
        if let bgr = image(named: template.bgrFilename, for: template) {
            size = CGSize(width: bgr.width, height: bgr.height)
        } else {
            size = CGSize(width: 480, height: 320)
        }
        sizeCache[key] = size
        return size
    }

    static func preferredResolutionFolders(for targetSize: CGSize, available: [String]) -> [String] {
        guard !available.isEmpty else { return [] }
        guard targetSize.width > 0, targetSize.height > 0 else { return available }

        let targetAspect = targetSize.width / targetSize.height
        return available.sorted { lhs, rhs in
            let l = resolutionScore(folder: lhs, targetAspect: targetAspect)
            let r = resolutionScore(folder: rhs, targetAspect: targetAspect)
            if l.aspectDelta != r.aspectDelta { return l.aspectDelta < r.aspectDelta }
            return l.pixelArea > r.pixelArea
        }
    }

    private func loadTemplates(in folder: String) -> [PeppyMeterTemplate]? {
        guard let url = BundleHelper.url(forResource: "meters", withExtension: "txt", subdirectory: subdirectory(for: folder)),
              let text = try? String(contentsOf: url, encoding: .utf8) else {
            return nil
        }
        return PeppyMeterConfig.parse(text).compactMap { template in
            var t = template
            t.resolutionFolder = folder
            return image(named: t.bgrFilename, resolutionFolder: folder) == nil ? nil : t
        }
    }

    private func resolvedResolutionFolder(for template: PeppyMeterTemplate) -> String {
        template.resolutionFolder.isEmpty ? defaultResolutionFolder : template.resolutionFolder
    }

    private func subdirectory(for resolutionFolder: String) -> String {
        "PeppyMeter/\(resolutionFolder)"
    }

    private func cacheKey(_ filename: String, resolutionFolder: String) -> String {
        "\(resolutionFolder):\(filename)"
    }

    private static func resolutionScore(folder: String, targetAspect: CGFloat) -> (aspectDelta: CGFloat, pixelArea: CGFloat) {
        guard let size = resolutionSize(folder) else {
            return (.greatestFiniteMagnitude, 0)
        }
        let aspect = size.width / size.height
        return (abs(log(aspect / targetAspect)), size.width * size.height)
    }

    private static func resolutionSize(_ folder: String) -> CGSize? {
        let parts = folder.split(separator: "x")
        guard parts.count == 2,
              let width = Double(parts[0]),
              let height = Double(parts[1]),
              width > 0,
              height > 0 else {
            return nil
        }
        return CGSize(width: width, height: height)
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
