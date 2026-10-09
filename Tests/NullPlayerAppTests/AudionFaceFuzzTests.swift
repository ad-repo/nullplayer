import XCTest
@testable import NullPlayer

/// Seeded mutations of a face that uses every element kind: each must load or fail with a finding,
/// and every face that loads must render every state at every scale. A trap anywhere in the loader,
/// document, scene, text or renderer fails the run; the printed seed and mutation reproduce it.
final class AudionFaceFuzzTests: XCTestCase {
    private static let iterations = 400

    func testMutatedFacesLoadOrFailWithAFindingAndRenderEveryState() async throws {
        let fixture = try Self.everyElementFixture()
        let original = Self.everyElementJSON()
        let sprites = try FileManager.default.contentsOfDirectory(atPath: fixture.folder.path)
            .filter { $0.hasSuffix(".png") }.sorted()
        let pristine = try sprites.map { try Data(contentsOf: fixture.folder.appendingPathComponent($0)) }
        var random = SplitMix64(seed: 0xA0D1_0FAC)
        var loaded = 0, refused = 0

        for iteration in 0..<Self.iterations {
            // One fixture throughout: every sprite is put back before the next mutation.
            for (name, data) in zip(sprites, pristine) { try fixture.write(name, data) }
            let mutation = try Self.mutate(fixture, json: original, sprites: sprites, random: &random)
            let face: AudionFace
            do {
                face = try await fixture.load()
            } catch is AudionFaceFinding {
                refused += 1
                continue
            } catch {
                return XCTFail("iteration \(iteration) (\(mutation)) threw a non-finding: \(error)")
            }
            loaded += 1
            // Each state at one of the scales and clock frames, so every pairing recurs across faces.
            for (index, (host, interaction)) in Self.states(face).enumerated() {
                let scale = [1, 3][index % 2], frame = [0, 81, 100_000][index % 3]
                let image = AudionFaceRenderer.render(AudionFaceScene(face: face, host: host, interaction: interaction,
                                                                      frame: frame, scale: scale))
                XCTAssertEqual(image.map { [$0.width, $0.height] }, [face.base.width * scale, face.base.height * scale],
                               "iteration \(iteration) (\(mutation))")
            }
        }
        // Both outcomes must actually be exercised, or the mutations have stopped reaching the loader.
        XCTAssertGreaterThan(loaded, Self.iterations / 4)
        XCTAssertGreaterThan(refused, 0)
    }

    // MARK: - The face every mutation starts from

    private static let rect: [String: Int] = AudionFaceFixture.rect(top: 1, left: 1, bottom: 5, right: 9)

    static func everyElementJSON() -> [String: Any] {
        var json: [String: Any] = ["faceInfo": ["fuzz"]]
        for role in AudionFace.ButtonRole.allCases { json[role.rectKey] = rect }
        for role in AudionFace.IndicatorRole.allCases { json[role.rectKey] = rect }
        for (index, role) in AudionFace.DigitRole.allCases.enumerated() {
            json[role.rectKey] = rect
            json[role.firstPICTKey] = index < 4 ? 100 : 200
        }
        for role in AudionFace.AnimationRole.allCases {
            json[role.rectKey] = rect
            json[role.firstPICTKey] = 300
            json[role.frameCountKey] = 3
            json[role.frameDelayKey] = 2
        }
        for role in AudionFace.TextRole.allCases {
            json[role.rectKey] = AudionFaceFixture.rect(top: 6, left: 0, bottom: 14, right: 40)
            json[role.textModeKey] = 1
            json[role.fontNameKey] = "Helvetica"
            json[role.fontSizeKey] = 9
            json[role.txtrColorKey] = ["red": 10, "green": 200, "blue": 30]
            for (bit, key) in role.styleKeys.enumerated() { json[key] = bit % 3 == 0 }
        }
        return json
    }

    static func everyElementFixture() throws -> AudionFaceFixture {
        let fixture = try AudionFaceFixture(json: everyElementJSON())
        try fixture.png("base.png", width: 48, height: 16, fill: [40, 40, 40, 255])
        try fixture.png("base-alpha.png", width: 48, height: 16)
        try fixture.png("inactive-alpha.png", width: 40, height: 12)
        for role in AudionFace.ButtonRole.allCases {
            for state in ["", "-active", "-disabled", "-hover"] { try fixture.png("\(role.sprite)\(state).png", width: 3, height: 2) }
        }
        for role in AudionFace.IndicatorRole.allCases {
            try fixture.png("\(role.sprite).png")
            try fixture.png("\(role.sprite)-on.png")
        }
        try fixture.picts(100, count: 10)
        try fixture.picts(200, count: 11)
        try fixture.picts(300, count: 3)
        return fixture
    }

    // MARK: - Mutations

    /// Values a hostile `index.json` puts where a well-formed one has a number, rect, colour or name.
    private static let hostileValues: [Any] = [
        Int.max, Int.min, Int.max - 1, -1, 0, 1, 99_999, 100_000, 1e308, -1e308, 0.5, "12", "", true, NSNull(),
        [Any](), [String: Any](), String(repeating: "W", count: 4_096),
        ["top": Int.min, "left": Int.min, "bottom": Int.max, "right": Int.max],
        ["top": 0, "left": -1, "bottom": 1, "right": Int.max],
        ["top": Int.max - 1, "left": Int.max - 1, "bottom": Int.max, "right": Int.max],
        ["top": 0, "left": 0, "bottom": 100_000, "right": 100_000],
        ["top": 3, "left": 3, "bottom": 1, "right": 1],
        ["red": Int.max, "green": Int.min, "blue": -1],
    ]

    /// One to four mutations of the JSON, sometimes followed by byte damage to the serialized index
    /// or to one sprite. Returns a description that reproduces it.
    private static func mutate(_ fixture: AudionFaceFixture, json original: [String: Any], sprites: [String],
                               random: inout SplitMix64) throws -> String {
        var json = original
        var steps: [String] = []
        let keys = original.keys.sorted()
        for _ in 0...random.next(below: 3) {
            let key = keys[random.next(below: keys.count)]
            switch random.next(below: 4) {
            case 0:
                json[key] = nil
                steps.append("remove \(key)")
            case 1:
                let index = random.next(below: hostileValues.count)
                json[key] = hostileValues[index]
                steps.append("\(key)=hostile[\(index)]")
            case 2:
                json["\(key)X"] = original[key]
                steps.append("add \(key)X")
            default:
                let value = [Int.max, Int.min, -1, 0, 50_000][random.next(below: 5)]
                if var nested = json[key] as? [String: Any], let field = nested.keys.sorted().first {
                    nested[field] = value
                    json[key] = nested
                    steps.append("\(key).\(field)=\(value)")
                } else {
                    json[key] = value
                    steps.append("\(key)=\(value)")
                }
            }
        }
        var index = try JSONSerialization.data(withJSONObject: json)
        if random.next(below: 4) == 0, !index.isEmpty {
            let at = random.next(below: index.count)
            if random.next(below: 2) == 0 {
                index = index.prefix(at)
                steps.append("truncate index at \(at)")
            } else {
                index[at] ^= UInt8(1 + random.next(below: 255))
                steps.append("flip index byte \(at)")
            }
        }
        try fixture.write("index.json", index)
        if random.next(below: 4) == 0 {
            let name = sprites[random.next(below: sprites.count)]
            var bytes = try Data(contentsOf: fixture.folder.appendingPathComponent(name))
            let at = 8 + random.next(below: bytes.count - 8)
            if random.next(below: 2) == 0 { bytes = bytes.prefix(at) } else { bytes[at] ^= 0xFF }
            try fixture.write(name, bytes)
            steps.append("damage \(name) at \(at)")
        }
        return steps.joined(separator: ", ")
    }

    // MARK: - States

    /// Every host and interaction state the scene branches on.
    private static func states(_ face: AudionFace) -> [(AudionFaceHostState, AudionFaceInteractionState)] {
        var hosts: [AudionFaceHostState] = []
        for phase in [AudionFaceHostState.StreamPhase.none, .connecting, .streaming, .lag] {
            for (playing, track, elapsed) in [(false, nil, 0), (true, 1, 61), (true, 150, 6_000), (false, 0, Int.max / 2)] as [(Bool, Int?, Int)] {
                var host = AudionFaceHostState()
                host.playState = playing ? .playing : .paused
                host.trackIndex = track
                host.elapsedSeconds = elapsed
                host.durationSeconds = elapsed * 2
                host.title = "A title long enough to need cutting from the middle"
                host.artist = "Artist"
                host.album = "Album"
                host.streamPhase = phase
                host.isWindowActive = track != 150
                host.reduceMotion = track == 1
                hosts.append(host)
            }
        }
        let interactions = [AudionFaceInteractionState()] + AudionFace.ButtonRole.allCases.map { role in
            var interaction = AudionFaceInteractionState()
            interaction.hovered = role
            interaction.pressed = role
            interaction.disabled = [role]
            return interaction
        }
        return hosts.map { ($0, interactions[0]) } + interactions.dropFirst().map { (hosts[1], $0) }
    }
}

/// A seeded generator, so a failing iteration reproduces exactly.
private struct SplitMix64: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    mutating func next(below bound: Int) -> Int { Int(next() % UInt64(bound)) }
}
