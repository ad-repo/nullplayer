import CoreGraphics
import Foundation
import ImageIO

/// An `.sgf` file to a `SoniqueSkin`, bounded by `SoniqueSkinPolicy` in the order the decision
/// record's § *Threat model* gives: file size, the whole entry table, `skin.ini`'s size, every JPEG's
/// header and the pixel budget, and only then any decode. A fatal finding is thrown; warnings ride
/// on the skin.
enum SoniqueSkinLoader {
    /// The production entry point. Even a MainActor caller leaves the UI executor before the file is
    /// touched, and receives only the completed skin.
    static func load(file: URL) async throws -> SoniqueSkin {
        try await Task.detached(priority: .userInitiated) {
            try load(contentsOf: file)
        }.value
    }

    static func load(contentsOf file: URL) throws -> SoniqueSkin {
        guard let size = (try? file.resourceValues(forKeys: [.fileSizeKey]))?.fileSize else {
            throw SoniqueSkinFinding(.notAnArchive, "'\(file.lastPathComponent)' cannot be read.")
        }
        guard size <= SoniqueSkinPolicy.fileBytes else {
            throw SoniqueSkinFinding(.fileTooLarge, "\(size) bytes, more than \(SoniqueSkinPolicy.fileBytes).")
        }
        guard let data = try? Data(contentsOf: file) else {
            throw SoniqueSkinFinding(.notAnArchive, "'\(file.lastPathComponent)' cannot be read.")
        }
        return try load(data: data)
    }

    static func load(data: Data) throws -> SoniqueSkin {
        guard data.count <= SoniqueSkinPolicy.fileBytes else {
            throw SoniqueSkinFinding(.fileTooLarge, "\(data.count) bytes, more than \(SoniqueSkinPolicy.fileBytes).")
        }
        // The last entry of a name wins: the oracle draws the last of a repeated `/rgn/nav/drawer`;
        // names are matched case-insensitively (`logoHREF`, `logohref`).
        var payloads: [String: Data] = [:]
        for entry in try SoniqueSkinArchive.entries(in: data) {
            payloads[entry.name.lowercased()] = entry.payload
        }
        let names = payloads.keys.sorted()
        var findings: [SoniqueSkinFinding] = []

        let iniData = payloads["/skin.ini"] ?? Data()
        guard iniData.count <= SoniqueSkinPolicy.iniBytes else {
            throw SoniqueSkinFinding(.iniTooLarge, "skin.ini is \(iniData.count) bytes, more than \(SoniqueSkinPolicy.iniBytes).")
        }
        let ini = SoniqueSkinINI(String(data: iniData, encoding: .isoLatin1) ?? "")
        let settings = SoniqueSkinSettings(ini)
        findings += settings.findings

        var sizes: [String: (width: Int, height: Int)] = [:]
        var pixels = 0
        for name in names where name.hasPrefix("/jpeg/") {
            guard let size = jpegSize(payloads[name]!) else {
                findings.append(SoniqueSkinFinding(.entryUnreadable, "\(name) has no JPEG frame header."))
                continue
            }
            guard size.width <= SoniqueSkinPolicy.imageSide, size.height <= SoniqueSkinPolicy.imageSide else {
                throw SoniqueSkinFinding(.imageTooLarge, "\(name) is \(size.width)×\(size.height).")
            }
            pixels += size.width * size.height
            guard pixels <= SoniqueSkinPolicy.decodedPixels else {
                throw SoniqueSkinFinding(.pixelBudgetExceeded,
                    "The images exceed \(SoniqueSkinPolicy.decodedPixels) pixels at \(name).")
            }
            sizes[name] = size
        }

        var images: [String: CGImage] = [:]
        for name in names {
            guard let size = sizes[name] else { continue }
            guard let image = decode(payloads[name]!), image.width == size.width, image.height == size.height else {
                findings.append(SoniqueSkinFinding(.entryUnreadable, "\(name) does not decode."))
                continue
            }
            images[name] = image
        }

        var regions: [String: SoniqueSkinRegion] = [:]
        for name in names where name.hasPrefix("/rgn/") {
            guard let region = SoniqueSkinRegion(payloads[name]!) else {
                findings.append(SoniqueSkinFinding(.entryUnreadable, "\(name) is not a well-formed region."))
                continue
            }
            regions[name] = region
            // Small mode's drawers slide out above and below the bar, so they lie past its picture
            // by design (408 skins' `extrabottom`); every other region is drawn on its mode picture.
            guard !name.hasPrefix("/rgn/small/extra"),
                  let mode = SoniqueSkin.Mode.allCases.first(where: { name.hasPrefix($0.regions) }),
                  let picture = images[mode.picture] else { continue }
            let clipped = region.clipped(width: picture.width, height: picture.height)
            if clipped.rects != region.rects || clipped.bounds != region.bounds {
                findings.append(SoniqueSkinFinding(.regionClipped,
                    "\(name) extends past the \(picture.width)×\(picture.height) picture; clipped."))
                regions[name] = clipped
            }
        }

        // Every other omitted entry, a frame included, falls back on its own (S4).
        var defaultModes: Set<SoniqueSkin.Mode> = []
        for mode in SoniqueSkin.Mode.allCases {
            let reason = settings.int("skin", mode.touchKey) == 0 ? "\(mode.touchKey) is 0"
                : images[mode.picture] == nil ? "no \(mode.picture)" : nil
            if let reason {
                defaultModes.insert(mode)
                findings.append(SoniqueSkinFinding(.modeUsesDefault, "\(mode) mode draws the default skin: \(reason)."))
            }
        }

        return SoniqueSkin(ini: ini, settings: settings, images: images, regions: regions, defaultModes: defaultModes, findings: findings)
    }

    /// Width and height from the first SOF marker, without decoding. Nil when there is none.
    static func jpegSize(_ payload: Data) -> (width: Int, height: Int)? {
        let bytes = [UInt8](payload)
        guard bytes.count > 4, bytes[0] == 0xFF, bytes[1] == 0xD8 else { return nil }
        let frameMarkers: Set<UInt8> = [0xC0, 0xC1, 0xC2, 0xC3, 0xC5, 0xC6, 0xC7, 0xC9, 0xCA, 0xCB, 0xCD, 0xCE, 0xCF]
        var at = 2
        while at + 9 <= bytes.count {
            guard bytes[at] == 0xFF else { at += 1; continue }
            let marker = bytes[at + 1]
            if frameMarkers.contains(marker) {
                let height = Int(bytes[at + 5]) << 8 | Int(bytes[at + 6])
                let width = Int(bytes[at + 7]) << 8 | Int(bytes[at + 8])
                return width > 0 && height > 0 ? (width, height) : nil
            }
            if marker == 0xFF { at += 1; continue }
            if marker == 0x01 || (0xD0...0xD8).contains(marker) { at += 2; continue }
            at += 2 + (Int(bytes[at + 2]) << 8 | Int(bytes[at + 3]))
        }
        return nil
    }

    /// The JPEG with pure black made transparent, as Sonique draws every picture (`format.md`
    /// § *What a skin can and cannot change*). Exact zero only: authors use a near-black for black.
    private static func decode(_ payload: Data) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(payload as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
        let w = image.width, h = image.height
        guard let context = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let data = context.data else { return nil }
        context.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        let pixels = data.bindMemory(to: UInt32.self, capacity: w * h)
        // RGBA in memory, so opaque black is 0xFF000000 read little-endian; transparent is 0.
        for i in 0..<(w * h) where pixels[i] == 0xFF00_0000 { pixels[i] = 0 }
        return context.makeImage()
    }
}
