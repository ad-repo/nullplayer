import AppKit
import CoreText
import Foundation
import ImageIO

struct ReeltoneImageInfo: Equatable, Sendable {
    let width: Int
    let height: Int
    var decodedByteCount: UInt64 { UInt64(width) * UInt64(height) * 4 }
}

struct ReeltoneResourceHandle: Hashable, Sendable {
    let relativePath: String
    private let root: URL

    init(relativePath: String, root: URL) throws {
        try ReeltoneResourcePath.validate(relativePath)
        self.relativePath = relativePath
        self.root = root
    }

    var fileURL: URL {
        // Construction already validated this path; force-try keeps the public access non-throwing.
        try! ReeltoneResourcePath.resolved(relativePath, beneath: root)
    }

    func data() throws -> Data {
        try Data(contentsOf: fileURL, options: [.mappedIfSafe])
    }

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

enum ReeltoneImageValidator {
    static let maximumDimension = 2_048
    static let maximumDecodedBytes: UInt64 = 64 * 1_024 * 1_024

    static func validate(_ handles: [ReeltoneResourceHandle]) throws -> [String: ReeltoneImageInfo] {
        var result: [String: ReeltoneImageInfo] = [:]
        var decodedBytes: UInt64 = 0
        for handle in handles {
            guard let source = CGImageSourceCreateWithURL(handle.fileURL as CFURL, nil),
                  CGImageSourceGetCount(source) > 0,
                  let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
                  let width = properties[kCGImagePropertyPixelWidth] as? NSNumber,
                  let height = properties[kCGImagePropertyPixelHeight] as? NSNumber,
                  width.intValue > 0, height.intValue > 0,
                  CGImageSourceCreateImageAtIndex(source, 0, nil) != nil else {
                throw ReeltoneDiagnostic(code: .invalidImage, message: "Image could not be decoded", resourcePath: handle.relativePath)
            }
            let info = ReeltoneImageInfo(width: width.intValue, height: height.intValue)
            guard info.width <= maximumDimension, info.height <= maximumDimension else {
                throw ReeltoneDiagnostic(code: .imageDimensionLimit, message: "Image exceeds 2048 by 2048 pixels", resourcePath: handle.relativePath)
            }
            let (sum, overflow) = decodedBytes.addingReportingOverflow(info.decodedByteCount)
            guard !overflow, sum <= maximumDecodedBytes else {
                throw ReeltoneDiagnostic(code: .decodedImageMemoryLimit, message: "Images exceed the 64 MiB decoded-memory limit", resourcePath: handle.relativePath)
            }
            decodedBytes = sum
            result[handle.relativePath] = info
        }
        return result
    }
}
