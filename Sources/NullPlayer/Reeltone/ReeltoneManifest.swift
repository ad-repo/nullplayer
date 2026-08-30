import Foundation

struct ReeltoneManifest: Equatable, Sendable {
    let formatVersion: Int
    let id: String
    let name: String
    let author: String?
    let version: String?
    let license: String?
    let colors: ReeltoneColors?
    let fonts: ReeltoneFonts?
    let sprites: ReeltoneSprites?
    let window: ReeltoneWindow?
    let regions: [ReeltoneRegion]

    var referencedResources: Set<String> {
        var result = Set<String>()
        fonts?.allSources.compactMap(\.file).forEach { result.insert($0) }
        sprites?.all.map(\.file).forEach { result.insert($0) }
        window?.art.values.forEach { result.insert($0) }
        window?.panels.values.forEach { panel in
            panel.art.values.forEach { result.insert($0) }
            panel.regions.flatMap(\.referencedResources).forEach { result.insert($0) }
        }
        regions.flatMap(\.referencedResources).forEach { result.insert($0) }
        return result
    }

    var referencedImages: Set<String> {
        var result = Set<String>()
        sprites?.all.map(\.file).forEach { result.insert($0) }
        window?.art.values.forEach { result.insert($0) }
        window?.panels.values.forEach { panel in
            panel.art.values.forEach { result.insert($0) }
            panel.regions.flatMap(\.referencedImages).forEach { result.insert($0) }
        }
        regions.flatMap(\.referencedImages).forEach { result.insert($0) }
        return result
    }
}

struct ReeltoneColors: Codable, Equatable, Sendable {
    let screen: String?
    let ink: String?
    let inkDim: String?
    let panel: String?
    let panelText: String?
}

struct ReeltoneFonts: Codable, Equatable, Sendable {
    let display: ReeltoneFontSource?
    let digits: ReeltoneFontSource?
    let body: ReeltoneFontSource?
    let bodyBold: ReeltoneFontSource?

    var allSources: [ReeltoneFontSource] { [display, digits, body, bodyBold].compactMap { $0 } }
}

struct ReeltoneFontSource: Codable, Equatable, Sendable {
    let builtin: String?
    let file: String?
    let postScriptName: String?

    init(from decoder: Decoder) throws {
        let rawValues = try decoder.container(keyedBy: ReeltoneAnyCodingKey.self)
        let allowedKeys: Set<String> = ["builtin", "file", "postScriptName"]
        if let unknown = rawValues.allKeys.first(where: { !allowedKeys.contains($0.stringValue) }) {
            throw DecodingError.dataCorrupted(
                .init(codingPath: decoder.codingPath + [unknown], debugDescription: "Unknown font field '\(unknown.stringValue)'")
            )
        }
        let values = try decoder.container(keyedBy: CodingKeys.self)
        builtin = try values.decodeIfPresent(String.self, forKey: .builtin)
        file = try values.decodeIfPresent(String.self, forKey: .file)
        postScriptName = try values.decodeIfPresent(String.self, forKey: .postScriptName)
        let isBuiltin = builtin != nil && file == nil && postScriptName == nil
        let isBundled = builtin == nil && file != nil && postScriptName?.isEmpty == false
        guard isBuiltin || isBundled else {
            throw DecodingError.dataCorruptedError(
                forKey: .builtin,
                in: values,
                debugDescription: "A font must contain either 'builtin', or both 'file' and 'postScriptName'"
            )
        }
    }
}

struct ReeltoneSprite: Codable, Equatable, Sendable {
    enum Mode: String, Codable, Sendable { case fill, stretch, tile }
    let file: String
    let capInsets: [Double]?
    let mode: Mode?
}

struct ReeltoneSprites: Codable, Equatable, Sendable {
    let reelRim: ReeltoneSprite?
    let reelSpokes: ReeltoneSprite?
    let background: ReeltoneSprite?
    let keyNormal: ReeltoneSprite?
    let keyPressed: ReeltoneSprite?

    var all: [ReeltoneSprite] { [reelRim, reelSpokes, background, keyNormal, keyPressed].compactMap { $0 } }
}

enum ReeltoneArtState: String, Codable, Sendable {
    case normal, hover, pressed, playing, playingHover, playingPressed
}

struct ReeltoneArt: Codable, Equatable, Sendable {
    private let storage: [ReeltoneArtState: String]

    var values: Dictionary<ReeltoneArtState, String>.Values { storage.values }
    subscript(state: ReeltoneArtState) -> String? { storage[state] }

    init(from decoder: Decoder) throws {
        let raw = try [String: String](from: decoder)
        var decoded: [ReeltoneArtState: String] = [:]
        for (key, value) in raw {
            guard let state = ReeltoneArtState(rawValue: key) else {
                throw DecodingError.dataCorrupted(
                    .init(codingPath: decoder.codingPath, debugDescription: "Unknown art state '\(key)'")
                )
            }
            decoded[state] = value
        }
        storage = decoded
    }

    func encode(to encoder: Encoder) throws {
        try Dictionary(uniqueKeysWithValues: storage.map { ($0.key.rawValue, $0.value) }).encode(to: encoder)
    }
}

struct ReeltoneWindow: Codable, Equatable, Sendable {
    let size: [Double]
    let art: ReeltoneArt
    let panels: [String: ReeltonePanel]

    private enum CodingKeys: String, CodingKey { case size, art, panels }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        size = try values.decode([Double].self, forKey: .size)
        art = try values.decode(ReeltoneArt.self, forKey: .art)
        panels = try values.decodeIfPresent([String: ReeltonePanel].self, forKey: .panels) ?? [:]
    }
}

struct ReeltonePanel: Codable, Equatable, Sendable {
    enum Attachment: String, Codable, Sendable { case left, right, top, bottom }
    let size: [Double]
    let attach: Attachment
    let art: ReeltoneArt
    let regions: [ReeltoneRegion]
    let visible: Bool?

    private enum CodingKeys: String, CodingKey { case size, attach, art, regions, visible }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        size = try values.decode([Double].self, forKey: .size)
        attach = try values.decode(Attachment.self, forKey: .attach)
        art = try values.decode(ReeltoneArt.self, forKey: .art)
        regions = try values.decodeIfPresent([ReeltoneRegion].self, forKey: .regions) ?? []
        visible = try values.decodeIfPresent(Bool.self, forKey: .visible)
    }
}

enum ReeltoneComponent: String, Codable, Sendable {
    case play, pause, playPause, stop, prev, next, seek, volume, shuffle, repeatMode
    case title, elapsed, duration, artwork, trackList, visualiser, equaliser
    case close, minimise, togglePanel, decoration, library, libraryBack
}

struct ReeltoneRegion: Codable, Equatable, Sendable {
    enum Alignment: String, Codable, Sendable { case left, center, right }
    enum ControlStyle: String, Codable, Sendable { case bar, slider, knob }
    enum ClipShape: String, Codable, Sendable { case rectangle, ellipse }
    enum AnimationDriver: String, Codable, Sendable { case playback, always, never }

    let component: ReeltoneComponent
    let rect: [Double]
    let size: Double?
    let color: String?
    let highlightColor: String?
    let align: Alignment?
    let marquee: Bool?
    let rowHeight: Double?
    let controlStyle: ControlStyle?
    let clipShape: ClipShape?
    let art: ReeltoneArt?
    let frames: [String]?
    let fps: Double?
    let drivenBy: AnimationDriver?
    let panel: String?

    var referencedResources: [String] { (art.map { Array($0.values) } ?? []) + (frames ?? []) }
    var referencedImages: [String] { referencedResources }
}

private struct ReeltoneManifestEnvelope: Decodable {
    let formatVersion: Int
}

private struct ReeltoneAnyCodingKey: CodingKey {
    let stringValue: String
    let intValue: Int?

    init?(stringValue: String) { self.stringValue = stringValue; intValue = nil }
    init?(intValue: Int) { self.intValue = intValue; stringValue = String(intValue) }
}

private struct ReeltoneManifestDocument: Decodable {
    let formatVersion: Int
    let id: String
    let name: String
    let author: String?
    let version: String?
    let license: String?
    let colors: ReeltoneColors?
    let fonts: ReeltoneFonts?
    let sprites: ReeltoneSprites?
    let window: ReeltoneWindow?
    let regions: [ReeltoneRegion]?
}

enum ReeltoneManifestDecoder {
    static func decode(_ data: Data) throws -> ReeltoneManifest {
        let decoder = JSONDecoder()
        let envelope: ReeltoneManifestEnvelope
        do {
            envelope = try decoder.decode(ReeltoneManifestEnvelope.self, from: data)
        } catch {
            throw ReeltoneDiagnostic.decoding(error)
        }
        guard envelope.formatVersion == 1 || envelope.formatVersion == 2 else {
            throw ReeltoneDiagnostic(
                code: .unsupportedFormatVersion,
                message: "Unsupported Reeltone format version \(envelope.formatVersion)",
                codingPath: ["formatVersion"]
            )
        }

        let document: ReeltoneManifestDocument
        do {
            document = try decoder.decode(ReeltoneManifestDocument.self, from: data)
        } catch {
            throw ReeltoneDiagnostic.decoding(error)
        }
        if document.window != nil, document.regions == nil {
            throw ReeltoneDiagnostic(code: .invalidManifest, message: "Version 2 windows require a regions array", codingPath: ["regions"])
        }
        let manifest = ReeltoneManifest(
            formatVersion: document.formatVersion,
            id: document.id,
            name: document.name,
            author: document.author,
            version: document.version,
            license: document.license,
            colors: document.colors,
            fonts: document.fonts,
            sprites: document.sprites,
            window: document.window,
            regions: document.regions ?? []
        )
        try validate(manifest)
        return manifest
    }

    private static func validate(_ manifest: ReeltoneManifest) throws {
        guard !manifest.id.isEmpty,
              manifest.id != ".", manifest.id != "..",
              !manifest.id.contains("/"), !manifest.id.contains("\\") else {
            throw invalid("Manifest ID is not filesystem-safe", at: ["id"])
        }
        guard manifest.name.rangeOfCharacter(from: .whitespacesAndNewlines.inverted) != nil else {
            throw invalid("Manifest name must not be blank", at: ["name"])
        }
        try validateColors(manifest.colors)
        let builtinFonts: Set<String> = [
            "DSEG14Classic-Regular", "DSEG7Classic-Regular",
            "Silkscreen-Regular", "Silkscreen-Bold"
        ]
        for (index, source) in (manifest.fonts?.allSources ?? []).enumerated() {
            if let builtin = source.builtin, !builtinFonts.contains(builtin) {
                throw invalid("Unknown built-in font '\(builtin)'", at: ["fonts", "\(index)", "builtin"])
            }
        }
        try manifest.sprites?.all.enumerated().forEach { index, sprite in
            if let insets = sprite.capInsets, insets.count != 4 || insets.contains(where: { $0 < 0 }) {
                throw invalid("capInsets must contain four non-negative numbers", at: ["sprites", "\(index)", "capInsets"])
            }
            if manifest.formatVersion == 2, sprite.mode == .fill {
                throw invalid("Sprite mode 'fill' is only supported by version 1", at: ["sprites", "\(index)", "mode"])
            }
        }
        if manifest.formatVersion == 1, manifest.window != nil || !manifest.regions.isEmpty {
            throw invalid("Version 1 manifests cannot declare shaped windows or regions", at: ["formatVersion"])
        }
        if let window = manifest.window {
            guard manifest.formatVersion == 2 else { throw invalid("window requires formatVersion 2", at: ["window"]) }
            try validateSize(window.size, at: ["window", "size"])
            guard window.art[.normal] != nil else { throw invalid("Window art requires a normal state", at: ["window", "art", "normal"]) }
            for (name, panel) in window.panels {
                guard !name.isEmpty else { throw invalid("Panel names must not be empty", at: ["window", "panels"]) }
                try validateSize(panel.size, at: ["window", "panels", name, "size"])
                guard panel.art[.normal] != nil else { throw invalid("Panel art requires a normal state", at: ["window", "panels", name, "art", "normal"]) }
                try validateRegions(panel.regions, panelNames: Set(window.panels.keys), at: ["window", "panels", name, "regions"])
            }
            try validateRegions(manifest.regions, panelNames: Set(window.panels.keys), at: ["regions"])
        } else if !manifest.regions.isEmpty {
            throw invalid("regions requires a window", at: ["regions"])
        }
        for path in manifest.referencedResources { try ReeltoneResourcePath.validate(path) }
    }

    private static func validateSize(_ value: [Double], at path: [String]) throws {
        guard value.count == 2, value.allSatisfy({ $0.isFinite && $0 > 0 }) else {
            throw invalid("Size must contain two positive finite numbers", at: path)
        }
    }

    private static func validateRegions(_ regions: [ReeltoneRegion], panelNames: Set<String>, at path: [String]) throws {
        for (index, region) in regions.enumerated() {
            let location = path + ["\(index)"]
            guard region.rect.count == 4,
                  region.rect.allSatisfy(\.isFinite),
                  region.rect[0] >= 0, region.rect[1] >= 0,
                  region.rect[2] > 0, region.rect[3] > 0 else {
                throw invalid("Region rect must be [x, y, width, height] with positive dimensions", at: location + ["rect"])
            }
            for (value, key) in [(region.size, "size"), (region.rowHeight, "rowHeight"), (region.fps, "fps")] {
                if let value, !value.isFinite || value <= 0 { throw invalid("\(key) must be positive and finite", at: location + [key]) }
            }
            if region.component == .togglePanel {
                guard let target = region.panel, panelNames.contains(target) else {
                    throw invalid("togglePanel must target a declared panel", at: location + ["panel"])
                }
            }
            if let frames = region.frames, frames.isEmpty {
                throw invalid("frames must not be empty", at: location + ["frames"])
            }
        }
    }

    private static func validateColors(_ colors: ReeltoneColors?) throws {
        for (value, key) in [(colors?.screen, "screen"), (colors?.ink, "ink"), (colors?.inkDim, "inkDim"), (colors?.panel, "panel"), (colors?.panelText, "panelText")] {
            if let value {
                let hex = value.dropFirst()
                let validLength = hex.count == 6 || hex.count == 8
                let validDigits = hex.allSatisfy { $0.isHexDigit }
                if !value.hasPrefix("#") || !validLength || !validDigits {
                    throw invalid("Invalid color value", at: ["colors", key])
                }
            }
        }
    }

    private static func invalid(_ message: String, at path: [String]) -> ReeltoneDiagnostic {
        ReeltoneDiagnostic(code: .invalidManifest, message: message, codingPath: path)
    }
}
