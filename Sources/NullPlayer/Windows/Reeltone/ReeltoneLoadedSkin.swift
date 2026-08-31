import AppKit
import CoreText
import Foundation

extension ReeltoneResourceHandle {
    func image() throws -> NSImage {
        guard let image = NSImage(contentsOf: fileURL) else {
            throw ReeltoneDiagnostic(code: .invalidImage, message: "Image could not be decoded", resourcePath: relativePath)
        }
        return image
    }

    func registerFont(expectedPostScriptName: String) throws {
        if NSFont(name: expectedPostScriptName, size: 12) != nil { return }
        var unmanagedError: Unmanaged<CFError>?
        guard CTFontManagerRegisterFontsForURL(fileURL as CFURL, .process, &unmanagedError) else {
            let detail = unmanagedError?.takeRetainedValue().localizedDescription ?? "unknown CoreText error"
            throw ReeltoneDiagnostic(code: .invalidFont, message: "Font registration failed: \(detail)", resourcePath: relativePath)
        }
        guard NSFont(name: expectedPostScriptName, size: 12) != nil else {
            CTFontManagerUnregisterFontsForURL(fileURL as CFURL, .process, nil)
            throw ReeltoneDiagnostic(code: .invalidFont, message: "Font does not provide PostScript name '\(expectedPostScriptName)'", resourcePath: relativePath)
        }
    }
}

enum ReeltoneFontValidator {
    static func validate(_ handle: ReeltoneResourceHandle, expectedPostScriptName: String) throws {
        guard let descriptors = CTFontManagerCreateFontDescriptorsFromURL(handle.fileURL as CFURL) as? [CTFontDescriptor],
              descriptors.contains(where: {
                  (CTFontDescriptorCopyAttribute($0, kCTFontNameAttribute) as? String) == expectedPostScriptName
              }) else {
            throw ReeltoneDiagnostic(
                code: .invalidFont,
                message: "Font does not provide PostScript name '\(expectedPostScriptName)'",
                resourcePath: handle.relativePath
            )
        }
    }
}

final class ReeltoneLoadedSkin {
    static let hitTestAlphaThreshold: UInt8 = 3

    let manifest: ReeltoneManifest
    let rootURL: URL
    let resources: [String: ReeltoneResourceHandle]
    let imageInfo: [String: ReeltoneImageInfo]
    let diagnostics: [ReeltoneDiagnostic]

    private var cleanupURL: URL?
    private var decodedImageCache: [String: NSImage] = [:]
    private(set) var cachedDecodedImageBytes: UInt64 = 0

    init(
        manifest: ReeltoneManifest,
        rootURL: URL,
        resources: [String: ReeltoneResourceHandle],
        imageInfo: [String: ReeltoneImageInfo],
        diagnostics: [ReeltoneDiagnostic] = [],
        cleanupURL: URL? = nil
    ) {
        self.manifest = manifest
        self.rootURL = rootURL
        self.resources = resources
        self.imageInfo = imageInfo
        self.diagnostics = diagnostics
        self.cleanupURL = cleanupURL
    }

    deinit { close() }

    func close() {
        guard let cleanupURL else { return }
        self.cleanupURL = nil
        try? FileManager.default.removeItem(at: cleanupURL)
    }

    func image(for relativePath: String) throws -> NSImage {
        if let cached = decodedImageCache[relativePath] { return cached }
        guard let handle = resources[relativePath], let info = imageInfo[relativePath] else {
            throw ReeltoneDiagnostic(code: .missingResource, message: "Referenced image is missing", resourcePath: relativePath)
        }
        let (newTotal, overflow) = cachedDecodedImageBytes.addingReportingOverflow(info.decodedByteCount)
        guard !overflow, newTotal <= ReeltoneImageValidator.maximumDecodedBytes else {
            throw ReeltoneDiagnostic(code: .decodedImageMemoryLimit, message: "Decoded image cache exceeds the 64 MiB limit", resourcePath: relativePath)
        }
        let image = try handle.image()
        decodedImageCache[relativePath] = image
        cachedDecodedImageBytes = newTotal
        return image
    }

    func containsVisiblePixel(in relativePath: String, normalizedTopLeftPoint point: CGPoint) throws -> Bool {
        guard point.x.isFinite, point.y.isFinite,
              point.x >= 0, point.x <= 1, point.y >= 0, point.y <= 1 else { return false }
        let image = try image(for: relativePath)
        var proposedRect = NSRect(origin: .zero, size: image.size)
        guard let cgImage = image.cgImage(forProposedRect: &proposedRect, context: nil, hints: nil) else { return true }
        switch cgImage.alphaInfo {
        case .none, .noneSkipFirst, .noneSkipLast: return true
        default: break
        }
        let pixelX = min(cgImage.width - 1, max(0, Int(point.x * CGFloat(cgImage.width))))
        let pixelY = min(cgImage.height - 1, max(0, Int(point.y * CGFloat(cgImage.height))))
        guard let sample = cgImage.cropping(to: CGRect(x: pixelX, y: pixelY, width: 1, height: 1)) else { return true }
        var rgba = [UInt8](repeating: 0, count: 4)
        let rendered = rgba.withUnsafeMutableBytes { bytes -> Bool in
            guard let context = CGContext(
                data: bytes.baseAddress, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            context.draw(sample, in: CGRect(x: 0, y: 0, width: 1, height: 1))
            return true
        }
        return !rendered || rgba[3] >= Self.hitTestAlphaThreshold
    }
}
