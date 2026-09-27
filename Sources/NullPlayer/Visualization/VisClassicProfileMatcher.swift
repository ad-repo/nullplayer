import AppKit

/// The automatic default vis_classic profile for a `.wal` / `.wmz` skin: the bundled profile whose
/// bar colours sit nearest the skin's own.
///
/// Classic always defaults to "Purple Neon" and Original picks a profile per skin in `skin.json`.
/// A third-party `.wal` or `.wmz` skin has no `skin.json`, so the same choice is made from colour:
/// each bundled profile's `[BarColours]` table is summarised as a low and a high colour, and the
/// profile nearest the skin's `(low, high)` target wins. Distance is Lab ΔE with lightness at half
/// weight (the textile `kL = 2` convention): a skin's accent and a profile's bars differ in brightness
/// far more than in hue, and at full weight a mid-brown profile out-scored every red and pink one.
/// The high end counts double because it is what the eye reads.
///
/// **Once per skin, so a user pick survives.** `applySkinDefault` records the skin it matched for in
/// `PreferenceScope.skinDefaultAppliedForKey`; a relaunch on the same skin leaves the stored profile
/// alone, and only a different skin re-picks. That is Original's `preservePersistedProfiles`
/// behaviour, keyed on identity so no launch-vs-explicit-load path has to be told apart.
enum VisClassicProfileMatcher {
    struct Lab: Equatable {
        let l: Double
        let a: Double
        let b: Double

        var chroma: Double { (a * a + b * b).squareRoot() }

        /// ΔE with lightness at half weight (`kL = 2`).
        func distance(to other: Lab) -> Double {
            let dl = (l - other.l) / 2, da = a - other.a, db = b - other.b
            return (dl * dl + da * da + db * db).squareRoot()
        }
    }

    struct Summary: Equatable {
        let name: String
        let low: Lab
        let high: Lab
    }

    struct Match: Equatable {
        let name: String
        let score: Double
    }

    /// The profile that is the core's live scratch state, not a look anybody chose.
    private static let excludedProfileNames: Set<String> = ["Current Settings"]

    // MARK: - Parsing

    /// `[BarColours]` as 256 sRGB triples (0…255), or nil when the section is absent. Entries are
    /// `i=R G B`, the order `VisClassicCore.cpp`'s `parseRGB` reads. A missing index stays nil.
    static func barColours(fromINI text: String) -> [(r: Double, g: Double, b: Double)?]? {
        var colours = [(r: Double, g: Double, b: Double)?](repeating: nil, count: 256)
        var inSection = false
        var found = false
        for rawLine in text.split(whereSeparator: \.isNewline) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("[") {
                inSection = line.caseInsensitiveCompare("[BarColours]") == .orderedSame
                continue
            }
            guard inSection, let eq = line.firstIndex(of: "="),
                  let index = Int(line[..<eq].trimmingCharacters(in: .whitespaces)),
                  (0..<256).contains(index) else { continue }
            let parts = line[line.index(after: eq)...].split(separator: " ").compactMap { Double($0) }
            guard parts.count >= 3 else { continue }
            let clamp = { (v: Double) in min(max(v, 0), 255) }
            colours[index] = (r: clamp(parts[0]), g: clamp(parts[1]), b: clamp(parts[2]))
            found = true
        }
        return found ? colours : nil
    }

    /// `low` = mean of entries 32–127, `high` = mean of entries 128–255. Entries below 32 are the
    /// near-invisible foot of the bar and would drag every profile toward black.
    ///
    /// A profile whose bars are near-black (LCD draws only its peaks) has no bar colour to match
    /// and is not a candidate.
    static func summary(name: String, iniText: String) -> Summary? {
        guard let colours = barColours(fromINI: iniText),
              let low = mean(of: colours[32...127]),
              let high = mean(of: colours[128...255]) else { return nil }
        guard lab(r: high.r, g: high.g, b: high.b).l >= 15 else { return nil }
        return Summary(name: name, low: lab(r: low.r, g: low.g, b: low.b),
                       high: lab(r: high.r, g: high.g, b: high.b))
    }

    private static func mean(
        of slice: ArraySlice<(r: Double, g: Double, b: Double)?>
    ) -> (r: Double, g: Double, b: Double)? {
        let present = slice.compactMap { $0 }
        guard !present.isEmpty else { return nil }
        let n = Double(present.count)
        return (r: present.reduce(0) { $0 + $1.r } / n,
                g: present.reduce(0) { $0 + $1.g } / n,
                b: present.reduce(0) { $0 + $1.b } / n)
    }

    /// Every bundled profile, summarised. User profiles are excluded: the default must not depend on
    /// what happens to be in somebody's Application Support folder.
    static func summaries(inDirectory directory: URL) -> [Summary] {
        let items = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        return items
            .filter { $0.pathExtension.lowercased() == "ini" }
            .compactMap { url -> Summary? in
                let name = url.deletingPathExtension().lastPathComponent
                guard !excludedProfileNames.contains(name),
                      let data = try? Data(contentsOf: url) else { return nil }
                let text = String(decoding: data, as: UTF8.self)
                return summary(name: name, iniText: text)
            }
            .sorted { $0.name < $1.name }
    }

    private static var cachedBundledSummaries: [Summary]?

    /// The bundled profiles, parsed once per session (31 small files).
    static func bundledSummaries() -> [Summary] {
        if let cachedBundledSummaries { return cachedBundledSummaries }
        let summaries = VisClassicBridge.bundledProfilesDirectory.map { Self.summaries(inDirectory: $0) } ?? []
        cachedBundledSummaries = summaries
        return summaries
    }

    // MARK: - Matching

    /// The profile nearest `(low, high)`: lowest `ΔE(low) + 2·ΔE(high)`, ties broken by name so the
    /// answer is deterministic.
    static func bestMatch(low: NSColor, high: NSColor, among summaries: [Summary]) -> Match? {
        let lowLab = lab(low), highLab = lab(high)
        var best: Match?
        for summary in summaries {
            let score = summary.low.distance(to: lowLab) + 2 * summary.high.distance(to: highLab)
            if let current = best,
               score > current.score || (score == current.score && summary.name >= current.name) {
                continue
            }
            best = Match(name: summary.name, score: score)
        }
        return best
    }

    /// True when a `.wal` box's bands are shading rather than bar colour, so matching them would pick
    /// nonsense: both ends near-black (Rika's `colorallbands="0,0,0"` at `alpha="50"` over its
    /// artwork), or both near-white (the undeclared default `WasabiVisPainter` fills in). Thresholds
    /// are provisional.
    static func isDegenerateTarget(low: NSColor, high: NSColor) -> Bool {
        let lowLab = lab(low), highLab = lab(high)
        if lowLab.l < 10 && highLab.l < 10 { return true }
        let nearWhite = { (c: Lab) in c.l > 95 && c.chroma < 5 }
        return nearWhite(lowLab) && nearWhite(highLab)
    }

    // MARK: - Once per skin

    /// Writes the matched profile for `scope` when `skinIdentity` is not the skin the scope was last
    /// matched for, and returns the match; returns nil (and writes nothing) otherwise.
    @discardableResult
    static func applySkinDefault(
        for scope: VisClassicBridge.PreferenceScope,
        skinIdentity: String,
        low: NSColor,
        high: NSColor,
        defaults: UserDefaults = .standard,
        summaries: [Summary]? = nil
    ) -> Match? {
        guard defaults.string(forKey: scope.skinDefaultAppliedForKey) != skinIdentity,
              let match = bestMatch(low: low, high: high, among: summaries ?? bundledSummaries()) else {
            return nil
        }
        defaults.set(match.name, forKey: scope.lastProfileNameKey)
        defaults.set(skinIdentity, forKey: scope.skinDefaultAppliedForKey)
        #if DEBUG
        NSLog("VisClassicProfileMatcher: %@ -> \"%@\" (score %.1f) for %@",
              scope.lastProfileNameKey, match.name, match.score, skinIdentity)
        #endif
        return match
    }

    /// Forgets which skin `scopes` were matched for, so the next resolve re-picks.
    static func forgetAppliedSkin(for scopes: [VisClassicBridge.PreferenceScope],
                                  defaults: UserDefaults = .standard) {
        for scope in scopes { defaults.removeObject(forKey: scope.skinDefaultAppliedForKey) }
    }

    // MARK: - Colour space

    static func lab(_ color: NSColor) -> Lab {
        guard let srgb = color.usingColorSpace(.sRGB) else { return Lab(l: 0, a: 0, b: 0) }
        return lab(r: Double(srgb.redComponent) * 255,
                   g: Double(srgb.greenComponent) * 255,
                   b: Double(srgb.blueComponent) * 255)
    }

    /// sRGB (0…255) → CIE L*a*b*, D65.
    static func lab(r: Double, g: Double, b: Double) -> Lab {
        func linear(_ v: Double) -> Double {
            let c = min(max(v / 255, 0), 1)
            return c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
        }
        let rl = linear(r), gl = linear(g), bl = linear(b)
        let x = (0.4124 * rl + 0.3576 * gl + 0.1805 * bl) / 0.95047
        let y = (0.2126 * rl + 0.7152 * gl + 0.0722 * bl) / 1.0
        let z = (0.0193 * rl + 0.1192 * gl + 0.9505 * bl) / 1.08883
        func f(_ t: Double) -> Double {
            t > 216.0 / 24389.0 ? cbrt(t) : (24389.0 / 27.0 * t + 16) / 116
        }
        let fx = f(x), fy = f(y), fz = f(z)
        return Lab(l: 116 * fy - 16, a: 500 * (fx - fy), b: 200 * (fy - fz))
    }
}
