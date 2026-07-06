import Foundation
import CoreGraphics

/// A PeppyMeter meter type. See the `meters.txt` `meter.type` key.
enum PeppyMeterType: String {
    case linear
    case circular
}

/// Movement direction for linear meters (`direction` key). Default is `left-right`.
enum PeppyMeterDirection: String {
    case leftRight = "left-right"
    case rightLeft = "right-left"
    case bottomTop = "bottom-top"
    case topBottom = "top-bottom"
    case edgesCenter = "edges-center"
    case centerEdges = "center-edges"
}

/// A single meter definition parsed from a PeppyMeter `meters.txt` section.
///
/// All coordinates use PeppyMeter's native **top-left origin, y-down** pixel space, matching the
/// values in `meters.txt` verbatim. The renderer converts to CoreGraphics' bottom-left space.
struct PeppyMeterTemplate {
    let name: String
    let type: PeppyMeterType
    /// Resource folder this template was loaded from, e.g. `480x320`.
    var resolutionFolder: String = ""
    /// 1 = mono (single needle/bar), 2 = stereo (left + right).
    let channels: Int

    let bgrFilename: String
    /// Optional overlay drawn on top of the needle(s) (`fgr.filename`; may be absent/empty).
    let fgrFilename: String?
    let indicatorFilename: String

    /// Offset applied to the whole meter within the screen (`meter.x` / `meter.y`).
    var meterOffset: CGPoint = .zero

    // MARK: Circular
    var stepsPerDegree: Double = 2
    var distance: CGFloat = 0
    /// Rotation angle (degrees, CCW-positive) at volume 0 for the left/mono needle.
    var leftStartAngle: Double = 0
    /// Rotation angle at volume 100 for the left/mono needle.
    var leftStopAngle: Double = 0
    var rightStartAngle: Double = 0
    var rightStopAngle: Double = 0
    var monoOrigin: CGPoint = .zero
    var leftOrigin: CGPoint = .zero
    var rightOrigin: CGPoint = .zero

    // MARK: Linear
    var direction: PeppyMeterDirection = .leftRight
    /// `indicator.type = single` — a sprite that *moves* rather than a bar that grows.
    var indicatorSingle: Bool = false
    var flipLeftX: Bool = false
    var flipRightX: Bool = false
    /// Top-left anchor of the left/mono indicator (`left.x` / `left.y`).
    var leftPos: CGPoint = .zero
    var rightPos: CGPoint = .zero
    var positionRegular: Int = 0
    var positionOverload: Int = 0
    var stepWidthRegular: CGFloat = 0
    var stepWidthOverload: CGFloat = 0

    /// Cumulative pixel-width table for linear meters, ported from PeppyMeter's `MaskFactory`.
    /// Index 0 = 0 px; regular steps then overload steps accumulate.
    var linearMasks: [CGFloat] {
        var masks: [CGFloat] = [0]
        if positionRegular > 0 {
            for n in 1...positionRegular { masks.append(CGFloat(n) * stepWidthRegular) }
        }
        if positionOverload > 0 {
            let base = CGFloat(positionRegular) * stepWidthRegular
            for n in 1...positionOverload { masks.append(base + CGFloat(n) * stepWidthOverload) }
        }
        return masks
    }
}

/// Parser for a PeppyMeter `meters.txt` file (a simple `[section]` + `key = value` INI dialect).
enum PeppyMeterConfig {

    /// Parse the raw text of a `meters.txt` file into ordered meter templates.
    /// Malformed sections are skipped; a section is kept only if it has a valid `meter.type`.
    static func parse(_ text: String) -> [PeppyMeterTemplate] {
        var sections: [(name: String, keys: [String: String])] = []
        var currentName: String?
        var currentKeys: [String: String] = [:]

        func flush() {
            if let name = currentName {
                sections.append((name, currentKeys))
            }
            currentKeys = [:]
        }

        for rawLine in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("#") || line.hasPrefix(";") { continue }
            if line.hasPrefix("[") && line.hasSuffix("]") {
                flush()
                currentName = String(line.dropFirst().dropLast()).trimmingCharacters(in: .whitespaces)
                continue
            }
            guard let eq = line.firstIndex(of: "=") else { continue }
            let key = line[..<eq].trimmingCharacters(in: .whitespaces)
            let value = line[line.index(after: eq)...].trimmingCharacters(in: .whitespaces)
            currentKeys[key] = value
        }
        flush()

        return sections.compactMap { template(name: $0.name, keys: $0.keys) }
    }

    private static func template(name: String, keys: [String: String]) -> PeppyMeterTemplate? {
        guard let typeRaw = keys["meter.type"], let type = PeppyMeterType(rawValue: typeRaw) else { return nil }
        guard let bgr = keys["bgr.filename"], !bgr.isEmpty else { return nil }
        guard let indicator = keys["indicator.filename"], !indicator.isEmpty else { return nil }

        func num(_ key: String) -> Double? {
            guard let v = keys[key], !v.isEmpty else { return nil }
            return Double(v)
        }
        func cg(_ key: String) -> CGFloat? { num(key).map { CGFloat($0) } }
        func bool(_ key: String) -> Bool { (keys[key]?.lowercased() == "true") }

        let fgrRaw = keys["fgr.filename"]?.trimmingCharacters(in: .whitespaces)
        let channels = Int(num("channels") ?? 1)

        var t = PeppyMeterTemplate(
            name: name,
            type: type,
            channels: channels == 2 ? 2 : 1,
            bgrFilename: bgr,
            fgrFilename: (fgrRaw?.isEmpty == false) ? fgrRaw : nil,
            indicatorFilename: indicator
        )
        t.meterOffset = CGPoint(x: cg("meter.x") ?? 0, y: cg("meter.y") ?? 0)

        switch type {
        case .circular:
            t.stepsPerDegree = max(1, num("steps.per.degree") ?? 2)
            t.distance = cg("distance") ?? 0
            // Per-channel angles fall back to the shared start/stop angles.
            let start = num("start.angle") ?? 0
            let stop = num("stop.angle") ?? 0
            t.leftStartAngle = num("left.start.angle") ?? start
            t.leftStopAngle = num("left.stop.angle") ?? stop
            t.rightStartAngle = num("right.start.angle") ?? start
            t.rightStopAngle = num("right.stop.angle") ?? stop
            t.monoOrigin = CGPoint(x: cg("mono.origin.x") ?? 0, y: cg("mono.origin.y") ?? 0)
            t.leftOrigin = CGPoint(x: cg("left.origin.x") ?? 0, y: cg("left.origin.y") ?? 0)
            t.rightOrigin = CGPoint(x: cg("right.origin.x") ?? 0, y: cg("right.origin.y") ?? 0)
        case .linear:
            t.direction = PeppyMeterDirection(rawValue: keys["direction"] ?? "") ?? .leftRight
            t.indicatorSingle = (keys["indicator.type"]?.lowercased() == "single")
            t.flipLeftX = bool("flip.left.x")
            t.flipRightX = bool("flip.right.x")
            t.leftPos = CGPoint(x: cg("left.x") ?? 0, y: cg("left.y") ?? 0)
            t.rightPos = CGPoint(x: cg("right.x") ?? 0, y: cg("right.y") ?? 0)
            t.positionRegular = Int(num("position.regular") ?? 0)
            t.positionOverload = Int(num("position.overload") ?? 0)
            t.stepWidthRegular = cg("step.width.regular") ?? 0
            t.stepWidthOverload = cg("step.width.overload") ?? 0
        }
        return t
    }
}
