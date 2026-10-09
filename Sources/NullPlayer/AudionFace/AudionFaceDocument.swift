import CoreGraphics
import Foundation

/// What `index.json` says, element by element, read the way FaceKit reads it but tolerantly:
/// unknown keys are ignored, an absent rect means an absent element, and a key that is present but
/// malformed drops only its element, with an `AUD0013` finding. Holds no images; the loader pairs
/// these with the files on disk. Text needs no files, so it resolves here, to the model's own type.
struct AudionFaceDocument: Decodable {
    struct Button {
        /// Top-left from the rect; FaceKit takes the size from the sprite.
        let x, y: Int
        /// The authored rect has area, so a missing sprite is worth an `AUD0009`.
        let hasAuthoredArea: Bool
    }

    struct Strip {
        let rect: AudionFaceRect
        let pictIDs: Range<Int>
    }

    struct Animation {
        let strip: Strip
        let frameDelay: Int
    }

    let artist: AudionFace.TextLine?
    let album: AudionFace.TextLine?
    let buttons: [AudionFace.ButtonRole: Button]
    let indicators: [AudionFace.IndicatorRole: AudionFaceRect]
    let digits: [AudionFace.DigitRole: Strip]
    let animations: [AudionFace.AnimationRole: Animation]
    let faceInfo: [String]
    let findings: [AudionFaceFinding]

    init(from decoder: Decoder) throws {
        var reader = Reader(container: try decoder.container(keyedBy: Key.self))
        var buttons: [AudionFace.ButtonRole: Button] = [:]
        for role in AudionFace.ButtonRole.allCases {
            buttons[role] = reader.button(role)
        }
        var indicators: [AudionFace.IndicatorRole: AudionFaceRect] = [:]
        for role in AudionFace.IndicatorRole.allCases {
            indicators[role] = reader.rect(role.rectKey, element: role.sprite)
        }
        var digits: [AudionFace.DigitRole: Strip] = [:]
        for role in AudionFace.DigitRole.allCases {
            digits[role] = reader.digit(role)
        }
        var animations: [AudionFace.AnimationRole: Animation] = [:]
        for role in AudionFace.AnimationRole.allCases {
            animations[role] = reader.animation(role)
        }
        artist = reader.textLine(.artist)
        album = reader.textLine(.album)
        self.buttons = buttons
        self.indicators = indicators
        self.digits = digits
        self.animations = animations
        faceInfo = (try? reader.container.decode([String].self, forKey: Key("faceInfo"))) ?? []
        findings = reader.findings
    }
}

private struct Key: CodingKey {
    let stringValue: String
    var intValue: Int? { nil }
    init(_ string: String) { stringValue = string }
    init?(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { nil }
}

/// `{top, left, bottom, right}`. Only `top` and `left` are required: a button reads no more.
private struct Edges: Decodable {
    let top, left: Int
    let bottom, right: Int?

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: Key.self)
        top = try container.decode(Int.self, forKey: Key("top"))
        left = try container.decode(Int.self, forKey: Key("left"))
        bottom = try? container.decode(Int.self, forKey: Key("bottom"))
        right = try? container.decode(Int.self, forKey: Key("right"))
        guard [top, left, bottom ?? 0, right ?? 0].allSatisfy(AudionFacePolicy.coordinates.contains) else {
            throw DecodingError.dataCorruptedError(forKey: Key("top"), in: container,
                                                   debugDescription: "An edge is outside the coordinate bound.")
        }
    }

    enum Reading { case absent, malformed, rect(AudionFaceRect) }

    /// All four edges. Zero width or height is an absent element (FaceKit `decodeRect`).
    /// Negative is a listed departure: FaceKit keeps it, NullPlayer drops it as malformed.
    var reading: Reading {
        guard let bottom, let right else { return .malformed }
        let width = right - left, height = bottom - top
        if width == 0 || height == 0 { return .absent }
        if width < 0 || height < 0 { return .malformed }
        return .rect(AudionFaceRect(x: left, y: top, width: width, height: height))
    }
}

private struct Reader {
    let container: KeyedDecodingContainer<Key>
    var findings: [AudionFaceFinding] = []

    init(container: KeyedDecodingContainer<Key>) { self.container = container }

    mutating func drop(_ element: String, _ why: String) {
        findings.append(AudionFaceFinding(.elementDropped, "\(element) dropped: \(why)."))
    }

    func int(_ key: String) -> Int? { try? container.decode(Int.self, forKey: Key(key)) }

    /// Nil when the key is absent. A present key that does not decode drops `element`.
    mutating func edges(_ key: String, element: String) -> Edges? {
        guard container.contains(Key(key)) else { return nil }
        guard let edges = try? container.decode(Edges.self, forKey: Key(key)) else {
            drop(element, "`\(key)` is malformed")
            return nil
        }
        return edges
    }

    mutating func rect(_ key: String, element: String) -> AudionFaceRect? {
        switch edges(key, element: element)?.reading {
        case .rect(let rect): return rect
        case .malformed: drop(element, "`\(key)` is malformed"); return nil
        case .absent, nil: return nil
        }
    }

    mutating func button(_ role: AudionFace.ButtonRole) -> AudionFaceDocument.Button? {
        guard let edges = edges(role.rectKey, element: "\(role.sprite) button") else { return nil }
        var hasArea = false
        if case .rect = edges.reading { hasArea = true }
        return AudionFaceDocument.Button(x: edges.left, y: edges.top, hasAuthoredArea: hasArea)
    }

    /// `count` frames from `first`, every one inside `AudionFacePolicy.pictIDs` (`AUD0007`).
    mutating func pictIDs(first: Int, count: Int, element: String) -> Range<Int>? {
        let range = AudionFacePolicy.pictIDs
        guard range.contains(first), count <= range.upperBound, range.contains(first + count - 1) else {
            findings.append(AudionFaceFinding(.pictOutOfRange,
                "\(element) dropped: \(count) PICT IDs from \(first) leave \(range.lowerBound)…\(range.upperBound)."))
            return nil
        }
        return first..<(first + count)
    }

    /// FaceKit throws, failing the whole face, when a digit has a rect and no `FirstPICTID`.
    /// NullPlayer drops the digit (decision record § *Deliberate departures from FaceKit*).
    mutating func digit(_ role: AudionFace.DigitRole) -> AudionFaceDocument.Strip? {
        let element = "\(role)"
        guard let rect = rect(role.rectKey, element: element) else { return nil }
        guard let first = int(role.firstPICTKey) else {
            drop(element, "`\(role.firstPICTKey)` is missing or malformed")
            return nil
        }
        guard let ids = pictIDs(first: first, count: role.frameCount, element: element) else { return nil }
        return AudionFaceDocument.Strip(rect: rect, pictIDs: ids)
    }

    mutating func animation(_ role: AudionFace.AnimationRole) -> AudionFaceDocument.Animation? {
        let element = "\(role) animation"
        guard let rect = rect(role.rectKey, element: element) else { return nil }
        guard let delay = int(role.frameDelayKey), let count = int(role.frameCountKey),
              let first = int(role.firstPICTKey) else {
            drop(element, "a frame delay, count or first PICT ID is missing or malformed")
            return nil
        }
        // FaceKit traps on a negative count and keeps an animation of no frames; neither draws.
        guard count > 0 else {
            drop(element, "it has \(count) frames")
            return nil
        }
        guard let ids = pictIDs(first: first, count: count, element: element) else { return nil }
        return AudionFaceDocument.Animation(strip: AudionFaceDocument.Strip(rect: rect, pictIDs: ids),
                                            frameDelay: delay)
    }

    func color(_ key: String) -> CGColor? {
        guard let nested = try? container.nestedContainer(keyedBy: Key.self, forKey: Key(key)),
              let red = try? nested.decode(Int.self, forKey: Key("red")),
              let green = try? nested.decode(Int.self, forKey: Key("green")),
              let blue = try? nested.decode(Int.self, forKey: Key("blue")) else { return nil }
        return AudionFace.color(red: red, green: green, blue: blue)
    }

    mutating func textLine(_ role: AudionFace.TextRole) -> AudionFace.TextLine? {
        let element = "\(role) text"
        guard let rect = rect(role.rectKey, element: element) else { return nil }
        // FaceKit throws here too; see `digit`.
        guard let mode = int(role.textModeKey) else {
            drop(element, "`\(role.textModeKey)` is missing or malformed")
            return nil
        }
        let fontName = try? container.decode(String.self, forKey: Key(role.fontNameKey))
        // FaceKit `decodeStyle`: if any one of the eight keys fails to decode, the style is empty.
        var style: AudionFace.TextStyle = []
        for (bit, key) in role.styleKeys.enumerated() {
            guard let on = try? container.decode(Bool.self, forKey: Key(key)) else { style = []; break }
            if on { style.insert(AudionFace.TextStyle(rawValue: 1 << bit)) }
        }
        return AudionFace.TextLine(
            rect: rect, font: AudionFace.font(named: fontName,
                                              size: int(role.fontSizeKey).flatMap { AudionFacePolicy.fontSizes.contains($0) ? $0 : nil }),
            color: color(role.txtrColorKey) ?? color(role.faceColorKey) ?? AudionFace.color(red: 0, green: 0, blue: 0),
            style: style, xor: mode & 2 != 0)
    }
}
