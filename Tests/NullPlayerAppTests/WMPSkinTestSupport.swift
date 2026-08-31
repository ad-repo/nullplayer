import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import ZIPFoundation
@testable import NullPlayer

struct WMPTestArchiveEntry {
    let path: String
    let type: Entry.EntryType
    let data: Data
    let compression: CompressionMethod

    init(_ path: String, data: Data = Data(), type: Entry.EntryType = .file,
         compression: CompressionMethod = .none) {
        self.path = path
        self.type = type
        self.data = data
        self.compression = compression
    }
}

enum WMPSkinTestSupport {
    static func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("WMPSkinTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static func makeArchive(_ entries: [WMPTestArchiveEntry], filename: String = "fixture.wmz") throws -> URL {
        let directory = try temporaryDirectory()
        let url = directory.appendingPathComponent(filename)
        let archive = try Archive(url: url, accessMode: .create)
        for entry in entries {
            try archive.addEntry(with: entry.path, type: entry.type,
                uncompressedSize: Int64(entry.data.count), compressionMethod: entry.compression) { position, size in
                let start = Int(position)
                guard start < entry.data.count else { return Data() }
                return entry.data.subdata(in: start..<min(start + size, entry.data.count))
            }
        }
        return url
    }

    static func utf16(_ string: String, littleEndian: Bool, bom: Bool = true) -> Data {
        var bytes: [UInt8] = bom ? (littleEndian ? [0xFF, 0xFE] : [0xFE, 0xFF]) : []
        for unit in string.utf16 {
            if littleEndian { bytes.append(UInt8(unit & 0xFF)); bytes.append(UInt8(unit >> 8)) }
            else { bytes.append(UInt8(unit >> 8)); bytes.append(UInt8(unit & 0xFF)) }
        }
        return Data(bytes)
    }

    static func failureCode(_ body: () throws -> Any) -> WMPDiagnosticCode? {
        do { _ = try body(); return nil }
        catch let failure as WMPFailure { return failure.diagnostics.first?.code }
        catch { return nil }
    }

    static func failureCode(_ body: () async throws -> Any) async -> WMPDiagnosticCode? {
        do { _ = try await body(); return nil }
        catch let failure as WMPFailure { return failure.diagnostics.first?.code }
        catch { return nil }
    }

    static func encodedImage(width: Int, height: Int, rgba: [UInt8], type: UTType = .png) throws -> Data {
        precondition(rgba.count == width * height * 4)
        let provider = CGDataProvider(data: Data(rgba) as CFData)!
        let image = CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
            bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGBitmapInfo.byteOrder32Big.rawValue
                | CGImageAlphaInfo.last.rawValue), provider: provider,
            decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, type.identifier as CFString, 1, nil) else {
            throw NSError(domain: "WMPSkinTestSupport", code: 1)
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw NSError(domain: "WMPSkinTestSupport", code: 2)
        }
        return output as Data
    }

    static func rgba(_ image: CGImage, x: Int, yFromTop: Int) -> [UInt8] {
        let width = image.width, height = image.height
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        bytes.withUnsafeMutableBytes { buffer in
            let context = CGContext(data: buffer.baseAddress, width: width, height: height,
                bitsPerComponent: 8, bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue
                    | CGImageAlphaInfo.premultipliedLast.rawValue)!
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        }
        let offset = (yFromTop * width + x) * 4
        let alpha = bytes[offset + 3]
        guard alpha > 0, alpha < 255 else { return Array(bytes[offset..<(offset + 4)]) }
        func straight(_ value: UInt8) -> UInt8 {
            UInt8(min(255, (Int(value) * 255 + Int(alpha) / 2) / Int(alpha)))
        }
        return [straight(bytes[offset]), straight(bytes[offset + 1]), straight(bytes[offset + 2]), alpha]
    }
}

final class WMPMemoryResourceProvider: WMPResourceProviding {
    let resourcePaths: [String]
    private let resources: [String: Data]
    private let canonical: [String: String]

    init(_ resources: [String: Data]) {
        self.resources = resources
        resourcePaths = resources.keys.sorted(by: WMPPath.less)
        canonical = Dictionary(uniqueKeysWithValues: resources.keys.map { (WMPPath.fold($0), $0) })
    }

    func canonicalPath(for path: String) -> String? { canonical[WMPPath.fold(path)] }
    func data(for path: String) throws -> Data {
        guard let canonicalPath = canonicalPath(for: path), let data = resources[canonicalPath] else {
            throw WMPFailure(WMPDiagnostic(.resourceMissing, "Missing \(path)"))
        }
        return data
    }
}
