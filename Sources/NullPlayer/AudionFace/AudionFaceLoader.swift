import CoreGraphics
import Foundation
import ImageIO

/// A face folder to an `AudionFace`, bounded by `AudionFacePolicy` in the order the decision record's
/// § *Threat model* gives: walk (no symlinks), `index.json` (size, then parse), every PNG header and
/// the pixel budgets, and only then any decode. A fatal finding is thrown; warnings ride on the face.
///
/// Files are matched case-insensitively at the folder's top level, as FaceKit's lookups behave on a
/// default macOS volume. The files FaceKit ignores (`window.png`, `drag.png`, `inactive.png`,
/// `active-alpha.png`, `about.png`) are counted by the walk and never read.
enum AudionFaceLoader {
    /// The production entry point. Even a MainActor caller leaves the UI executor before the
    /// folder is touched, and receives only the completed face.
    static func load(folder: URL) async throws -> AudionFace {
        try await Task.detached(priority: .userInitiated) {
            try loadOffMain(folder: folder)
        }.value
    }

    private static func loadOffMain(folder: URL) throws -> AudionFace {
        let files = try walk(folder)

        guard let index = files["index.json"] else {
            throw AudionFaceFinding(.missingIndex, "No index.json in '\(folder.lastPathComponent)'.")
        }
        guard let json = read(index.url, upTo: AudionFacePolicy.indexBytes + 1) else {
            throw AudionFaceFinding(.malformedIndex, "index.json could not be read.")
        }
        guard json.count <= AudionFacePolicy.indexBytes else {
            throw AudionFaceFinding(.indexTooLarge, "index.json is over \(AudionFacePolicy.indexBytes) bytes.")
        }
        let document: AudionFaceDocument
        do {
            document = try JSONDecoder().decode(AudionFaceDocument.self, from: json)
        } catch {
            throw AudionFaceFinding(.malformedIndex, "index.json is not a JSON object: \(error.localizedDescription)")
        }

        // Read only the headers an element asks for, so an ignored file is never opened.
        func png(_ name: String) -> PNGFile? {
            guard let file = files[name], let size = pngSize(file.url) else { return nil }
            return PNGFile(name: name, url: file.url, bytes: file.bytes, width: size.width, height: size.height)
        }
        guard let baseFile = png("base.png") else {
            throw AudionFaceFinding(.missingBase, "No readable base.png.")
        }

        let needed = [baseFile] + Plan(document: document, lookup: png).files
        var pixels = 0
        for file in needed {
            guard file.width <= AudionFacePolicy.imageSide, file.height <= AudionFacePolicy.imageSide,
                  file.bytes <= AudionFacePolicy.imageBytes else {
                throw AudionFaceFinding(.imageTooLarge, "\(file.name) is \(file.width)×\(file.height), \(file.bytes) bytes.")
            }
            pixels += file.width * file.height
            guard pixels <= AudionFacePolicy.decodedPixels else {
                throw AudionFaceFinding(.pixelBudgetExceeded,
                    "The decoded images exceed \(AudionFacePolicy.decodedPixels) pixels at \(file.name).")
            }
        }

        var images: [String: CGImage] = [:]
        for file in needed {
            if let image = decode(file.url), image.width == file.width, image.height == file.height {
                images[file.name] = image
            }
        }
        guard let base = images["base.png"] else {
            throw AudionFaceFinding(.missingBase, "base.png does not decode.")
        }
        // Planned again over what decoded: a header that decodes to nothing is a missing file, as
        // FaceKit's `loadImage` treats it.
        return Plan(document: document) { images[$0] }.face(document: document, base: base)
    }

    // MARK: - Walk

    private struct File {
        let url: URL
        let bytes: Int
    }

    /// Every entry, recursively, before any file is opened: `AUD0006` for a symlink, `AUD0005` past
    /// the entry or byte bound. Returns the top level's regular files keyed by lowercased name.
    private static func walk(_ folder: URL) throws -> [String: File] {
        let root = try? folder.resourceValues(forKeys: [.isSymbolicLinkKey, .isDirectoryKey])
        guard root?.isSymbolicLink != true else {
            throw AudionFaceFinding(.pathEscape, "'\(folder.lastPathComponent)' is a symbolic link.")
        }
        guard root?.isDirectory == true else {
            throw AudionFaceFinding(.missingIndex, "'\(folder.lastPathComponent)' is not a folder.")
        }
        let keys: [URLResourceKey] = [.isSymbolicLinkKey, .isRegularFileKey, .fileSizeKey]
        guard let walker = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: keys) else {
            throw AudionFaceFinding(.missingIndex, "'\(folder.lastPathComponent)' cannot be listed.")
        }
        var files: [String: File] = [:]
        var count = 0, total = 0
        for case let url as URL in walker {
            count += 1
            guard count <= AudionFacePolicy.faceFiles else {
                throw AudionFaceFinding(.faceTooLarge, "More than \(AudionFacePolicy.faceFiles) files.")
            }
            let values = try? url.resourceValues(forKeys: Set(keys))
            guard values?.isSymbolicLink != true else {
                throw AudionFaceFinding(.pathEscape, "'\(url.lastPathComponent)' is a symbolic link.")
            }
            guard values?.isRegularFile == true else { continue }
            let bytes = values?.fileSize ?? 0
            guard bytes <= AudionFacePolicy.faceBytes - total else {
                throw AudionFaceFinding(.faceTooLarge, "More than \(AudionFacePolicy.faceBytes) bytes.")
            }
            total += bytes
            if walker.level == 1 {
                files[url.lastPathComponent.lowercased()] = File(url: url, bytes: bytes)
            }
        }
        return files
    }

    // MARK: - Images

    private static func read(_ url: URL, upTo count: Int) -> Data? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        return (try? handle.read(upToCount: count)) ?? Data()
    }

    /// Width and height from the IHDR chunk, without decoding. Nil for anything that is not a PNG.
    private static func pngSize(_ url: URL) -> (width: Int, height: Int)? {
        guard let bytes = read(url, upTo: 24).map(Array.init), bytes.count == 24,
              bytes[0..<8] == [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A],
              bytes[12..<16] == [0x49, 0x48, 0x44, 0x52] else { return nil }
        let width = bytes[16..<20].reduce(0) { $0 << 8 | Int($1) }
        let height = bytes[20..<24].reduce(0) { $0 << 8 | Int($1) }
        return width > 0 && height > 0 ? (width, height) : nil
    }

    private static func decode(_ url: URL) -> CGImage? {
        guard let data = read(url, upTo: AudionFacePolicy.imageBytes),
              let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, [kCGImageSourceShouldCacheImmediately: true] as CFDictionary)
    }
}

/// A top-level file whose PNG header has been read and whose pixels have not.
private struct PNGFile {
    let name: String
    let url: URL
    let bytes: Int
    let width, height: Int
}

/// Which `Asset` each element gets from `lookup`, and what was dropped for want of one. Built over
/// `PNGFile` headers to decide what to decode, then over the decoded `CGImage`s to build the face, so
/// the rule for which files an element needs exists once.
private struct Plan<Asset> {
    struct Button {
        let x, y: Int
        let normal: Asset
        let disabled, pressed, hover: Asset?
    }

    var mask, inactiveMask: Asset?
    var buttons: [AudionFace.ButtonRole: Button] = [:]
    var indicators: [AudionFace.IndicatorRole: (rect: AudionFaceRect, off: Asset, on: Asset)] = [:]
    var digits: [AudionFace.DigitRole: (rect: AudionFaceRect, frames: [Asset])] = [:]
    var animations: [AudionFace.AnimationRole: (rect: AudionFaceRect, frames: [Asset], delay: Int)] = [:]
    var findings: [AudionFaceFinding] = []

    /// Roles are walked in `allCases` order so findings come out in the same order every run.
    init(document: AudionFaceDocument, lookup: (String) -> Asset?) {
        mask = lookup("base-alpha.png")
        inactiveMask = lookup("inactive-alpha.png")

        for role in AudionFace.ButtonRole.allCases {
            guard let spec = document.buttons[role] else { continue }
            guard let normal = lookup("\(role.sprite).png") else {
                // FaceKit drops the button. A missing pause sprite is ordinary: most faces draw
                // pause into the play sprite's place only when they ship one.
                if spec.hasAuthoredArea, role != .pause {
                    findings.append(AudionFaceFinding(.buttonWithoutSprite,
                        "\(role.sprite) button dropped: it has a rect and no \(role.sprite).png."))
                }
                continue
            }
            buttons[role] = Button(x: spec.x, y: spec.y, normal: normal,
                                   disabled: lookup("\(role.sprite)-disabled.png"),
                                   pressed: lookup("\(role.sprite)-active.png"),
                                   hover: lookup("\(role.sprite)-hover.png"))
        }
        for role in AudionFace.IndicatorRole.allCases {
            guard let rect = document.indicators[role] else { continue }
            let element = "\(role.sprite) indicator", off = "\(role.sprite).png", on = "\(role.sprite)-on.png"
            guard let offAsset = lookup(off) else { drop(element, off); continue }
            guard let onAsset = lookup(on) else { drop(element, on); continue }
            indicators[role] = (rect, offAsset, onAsset)
        }
        for role in AudionFace.DigitRole.allCases {
            guard let strip = document.digits[role] else { continue }
            if let frames = frames(strip, element: "\(role)", lookup: lookup) {
                digits[role] = (strip.rect, frames)
            }
        }
        for role in AudionFace.AnimationRole.allCases {
            guard let animation = document.animations[role] else { continue }
            if let frames = frames(animation.strip, element: "\(role) animation", lookup: lookup) {
                animations[role] = (animation.strip.rect, frames, animation.frameDelay)
            }
        }
    }

    /// Any frame missing drops the whole element (FaceKit `decodeDigit`, `decodeAnimation`).
    private mutating func frames(_ strip: AudionFaceDocument.Strip, element: String,
                                 lookup: (String) -> Asset?) -> [Asset]? {
        var frames: [Asset] = []
        for id in strip.pictIDs {
            guard let frame = lookup("\(id).png") else {
                drop(element, "\(id).png")
                return nil
            }
            frames.append(frame)
        }
        return frames
    }

    private mutating func drop(_ element: String, _ missing: String) {
        findings.append(AudionFaceFinding(.elementDropped, "\(element) dropped: \(missing) is missing."))
    }
}

extension Plan where Asset == PNGFile {
    /// Every distinct file the planned elements decode, by name.
    var files: [PNGFile] {
        var all = [mask, inactiveMask].compactMap { $0 }
        for button in buttons.values {
            all += [button.normal] + [button.disabled, button.pressed, button.hover].compactMap { $0 }
        }
        for indicator in indicators.values { all += [indicator.off, indicator.on] }
        for digit in digits.values { all += digit.frames }
        for animation in animations.values { all += animation.frames }
        return Dictionary(all.map { ($0.name, $0) }) { first, _ in first }.values.sorted { $0.name < $1.name }
    }
}

extension Plan where Asset == CGImage {
    func face(document: AudionFaceDocument, base: CGImage) -> AudionFace {
        var findings = document.findings + self.findings
        for (name, mask) in [("base-alpha.png", mask), ("inactive-alpha.png", inactiveMask)] {
            guard let mask, mask.width != base.width || mask.height != base.height else { continue }
            findings.append(AudionFaceFinding(.maskSizeMismatch,
                "\(name) is \(mask.width)×\(mask.height) and base.png \(base.width)×\(base.height); anchored bottom-left."))
        }
        return AudionFace(
            base: base,
            mask: mask,
            inactiveMask: inactiveMask,
            artist: document.artist,
            album: document.album,
            buttons: buttons.mapValues {
                AudionFace.Button(image: $0.normal, disabledImage: $0.disabled, pressedImage: $0.pressed,
                                  hoverImage: $0.hover,
                                  rect: AudionFaceRect(x: $0.x, y: $0.y, width: $0.normal.width, height: $0.normal.height))
            },
            indicators: indicators.mapValues { AudionFace.Indicator(image: $0.off, onImage: $0.on, rect: $0.rect) },
            digits: digits.mapValues { AudionFace.Digit(images: $0.frames, rect: $0.rect) },
            animations: animations.mapValues {
                AudionFace.Animation(rect: $0.rect, frames: $0.frames, frameDelay: $0.delay)
            },
            faceInfo: document.faceInfo,
            findings: findings)
    }
}
