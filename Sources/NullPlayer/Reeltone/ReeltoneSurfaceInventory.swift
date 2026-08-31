import Foundation

enum ReeltoneSurfaceID: Hashable, Codable, Sendable, Comparable {
    case main
    case panel(String)

    var rawValue: String {
        switch self {
        case .main: return "main"
        case .panel(let name): return "panel:\(name)"
        }
    }

    var panelName: String? {
        if case .panel(let name) = self { return name }
        return nil
    }

    static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
}

struct ReeltoneAuthoredSize: Equatable, Sendable {
    let width: Double
    let height: Double
}

struct ReeltoneAuthoredRect: Equatable, Sendable {
    let x: Double
    let y: Double
    let width: Double
    let height: Double

    func containsTopLeftPoint(x pointX: Double, y pointY: Double, clipShape: ReeltoneRegion.ClipShape?) -> Bool {
        guard pointX >= x, pointX <= x + width, pointY >= y, pointY <= y + height else { return false }
        guard clipShape == .ellipse else { return true }
        let rx = width / 2
        let ry = height / 2
        let nx = (pointX - (x + rx)) / rx
        let ny = (pointY - (y + ry)) / ry
        return nx * nx + ny * ny <= 1
    }

    /// Converts the authored top-left rect into the bottom-left point space used by AppKit.
    func appKitRect(surfaceHeight: Double, scale: Double) -> CGRect {
        CGRect(
            x: x * scale,
            y: (surfaceHeight - y - height) * scale,
            width: width * scale,
            height: height * scale
        )
    }

    static func topLeftPoint(
        fromAppKitPoint point: CGPoint,
        surfaceHeight: Double,
        scale: Double
    ) -> CGPoint {
        guard scale.isFinite, scale > 0 else { return .zero }
        return CGPoint(x: point.x / scale, y: surfaceHeight - point.y / scale)
    }
}

struct ReeltoneSurfaceRegion: Equatable, Sendable {
    let index: Int
    let manifestRegion: ReeltoneRegion
    let authoredRect: ReeltoneAuthoredRect
    let ownsSingletonHost: Bool

    var component: ReeltoneComponent { manifestRegion.component }
    var isInteractive: Bool {
        switch component {
        case .title, .elapsed, .duration, .artwork, .visualiser, .decoration, .trackList, .equaliser, .library:
            return false
        default:
            return true
        }
    }

    var isAccessibilityText: Bool {
        component == .title || component == .elapsed || component == .duration
    }
}

struct ReeltoneSurface: Equatable, Sendable {
    let id: ReeltoneSurfaceID
    let displayName: String
    let authoredSize: ReeltoneAuthoredSize
    let attachment: ReeltonePanel.Attachment?
    let initiallyVisible: Bool
    let art: ReeltoneArt
    let regions: [ReeltoneSurfaceRegion]

    /// Last eligible region wins, matching v2 paint order.
    func hitRegion(atTopLeftX x: Double, y: Double) -> ReeltoneSurfaceRegion? {
        regions.reversed().first {
            $0.isInteractive && $0.authoredRect.containsTopLeftPoint(
                x: x, y: y, clipShape: $0.manifestRegion.clipShape
            )
        }
    }
}

struct ReeltoneSurfaceInventory: Equatable, Sendable {
    static let singletonComponents: Set<ReeltoneComponent> = [.trackList, .equaliser, .library]

    let main: ReeltoneSurface
    let panels: [ReeltoneSurface]
    let diagnostics: [ReeltoneDiagnostic]

    var allSurfaces: [ReeltoneSurface] { [main] + panels }

    init?(manifest: ReeltoneManifest) {
        guard let window = manifest.window else { return nil }
        var claimedSingletons = Set<ReeltoneComponent>()
        var diagnostics: [ReeltoneDiagnostic] = []

        func normalizeRegions(
            _ regions: [ReeltoneRegion],
            surfaceID: ReeltoneSurfaceID,
            path: [String]
        ) -> [ReeltoneSurfaceRegion] {
            regions.enumerated().map { index, region in
                var ownsSingleton = true
                if Self.singletonComponents.contains(region.component) {
                    if claimedSingletons.contains(region.component) {
                        ownsSingleton = false
                        diagnostics.append(ReeltoneDiagnostic(
                            severity: .warning,
                            code: .duplicateSingletonComponent,
                            message: "Duplicate \(region.component.rawValue) host is disabled; the first declaration owns the shared component",
                            codingPath: path + [String(index), "component"],
                            skinID: manifest.id,
                            surfaceID: surfaceID.rawValue,
                            regionIndex: index,
                            component: region.component.rawValue
                        ))
                    } else {
                        claimedSingletons.insert(region.component)
                    }
                }
                return ReeltoneSurfaceRegion(
                    index: index,
                    manifestRegion: region,
                    authoredRect: ReeltoneAuthoredRect(
                        x: region.rect[0], y: region.rect[1], width: region.rect[2], height: region.rect[3]
                    ),
                    ownsSingletonHost: ownsSingleton
                )
            }
        }

        main = ReeltoneSurface(
            id: .main,
            displayName: manifest.name,
            authoredSize: .init(width: window.size[0], height: window.size[1]),
            attachment: nil,
            initiallyVisible: true,
            art: window.art,
            regions: normalizeRegions(manifest.regions, surfaceID: .main, path: ["regions"])
        )

        panels = window.panels.keys.sorted().compactMap { name in
            guard let panel = window.panels[name] else { return nil }
            return ReeltoneSurface(
                id: .panel(name),
                displayName: Self.safePanelDisplayName(name),
                authoredSize: .init(width: panel.size[0], height: panel.size[1]),
                attachment: panel.attach,
                initiallyVisible: panel.visible ?? false,
                art: panel.art,
                regions: normalizeRegions(
                    panel.regions,
                    surfaceID: .panel(name),
                    path: ["window", "panels", name, "regions"]
                )
            )
        }
        self.diagnostics = diagnostics
    }

    func owner(of component: ReeltoneComponent) -> ReeltoneSurfaceID? {
        allSurfaces.first { surface in
            surface.regions.contains { $0.component == component && $0.ownsSingletonHost }
        }?.id
    }

    static func safePanelDisplayName(_ name: String) -> String {
        let collapsed = name
            .components(separatedBy: .controlCharacters)
            .joined(separator: " ")
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
        guard !collapsed.isEmpty else { return "Panel" }
        return String(collapsed.prefix(80))
    }
}

enum ReeltoneControlArtSelector {
    static func state(isPlaying: Bool, isHovered: Bool, isPressed: Bool) -> ReeltoneArtState {
        if isPlaying {
            if isPressed { return .playingPressed }
            if isHovered { return .playingHover }
            return .playing
        }
        if isPressed { return .pressed }
        if isHovered { return .hover }
        return .normal
    }

    static func resourcePath(
        in art: ReeltoneArt?,
        isPlaying: Bool,
        isHovered: Bool,
        isPressed: Bool
    ) -> String? {
        guard let art else { return nil }
        let preferred = state(isPlaying: isPlaying, isHovered: isHovered, isPressed: isPressed)
        return art[preferred]
            ?? (isPlaying ? art[.playing] : nil)
            ?? (isPressed ? art[.pressed] : nil)
            ?? (isHovered ? art[.hover] : nil)
            ?? art[.normal]
    }

    static func changesWithPlayback(_ art: ReeltoneArt?) -> Bool {
        guard let art else { return false }
        return art[.playing] != nil || art[.playingHover] != nil || art[.playingPressed] != nil
    }
}

enum ReeltoneControlMapping {
    static func fraction(
        point: CGPoint,
        in rect: CGRect,
        style: ReeltoneRegion.ControlStyle?
    ) -> CGFloat {
        guard rect.width > 0, rect.height > 0 else { return 0 }
        let raw: CGFloat
        if style == .knob {
            let angle = atan2(point.y - rect.midY, point.x - rect.midX)
            raw = (angle + .pi) / (2 * .pi)
        } else {
            raw = (point.x - rect.minX) / rect.width
        }
        return min(1, max(0, raw))
    }
}

enum ReeltoneControlGeometry {
    /// Positions an authored slider thumb without stretching it to the track bounds.
    static func sliderThumbRect(
        in trackRect: CGRect,
        authoredThumbSize: CGSize,
        scale: CGFloat,
        fraction: CGFloat
    ) -> CGRect {
        guard trackRect.width > 0, trackRect.height > 0 else { return .zero }
        let safeScale = scale.isFinite && scale > 0 ? scale : 1
        let width = min(trackRect.width, max(1, authoredThumbSize.width * safeScale))
        let height = min(trackRect.height, max(1, authoredThumbSize.height * safeScale))
        let value = min(1, max(0, fraction))
        return CGRect(
            x: trackRect.minX + (trackRect.width - width) * value,
            y: trackRect.midY - height / 2,
            width: width,
            height: height
        )
    }
}

struct ReeltoneAnimationClock: Equatable, Sendable {
    static func frameIndex(
        frameCount: Int,
        fps: Double,
        elapsed: TimeInterval,
        driver: ReeltoneRegion.AnimationDriver?,
        isPlaying: Bool
    ) -> Int? {
        guard frameCount > 0, fps.isFinite, fps > 0 else { return nil }
        switch driver ?? .always {
        case .never: return 0
        case .playback where !isPlaying: return 0
        case .playback, .always:
            return Int(floor(max(0, elapsed) * fps)) % frameCount
        }
    }
}

enum ReeltonePanelGeometry {
    static func attachedFrame(
        mainFrame: CGRect,
        panelSize: CGSize,
        attachment: ReeltonePanel.Attachment
    ) -> CGRect {
        switch attachment {
        case .left:
            return CGRect(x: mainFrame.minX - panelSize.width, y: mainFrame.maxY - panelSize.height, width: panelSize.width, height: panelSize.height)
        case .right:
            return CGRect(x: mainFrame.maxX, y: mainFrame.maxY - panelSize.height, width: panelSize.width, height: panelSize.height)
        case .top:
            return CGRect(x: mainFrame.minX, y: mainFrame.maxY, width: panelSize.width, height: panelSize.height)
        case .bottom:
            return CGRect(x: mainFrame.minX, y: mainFrame.minY - panelSize.height, width: panelSize.width, height: panelSize.height)
        }
    }

    /// Clamp only a restored frame at presentation time. Authored geometry is never mutated.
    static func frameForPresentation(_ frame: CGRect, visibleFrames: [CGRect]) -> CGRect {
        guard frame != .zero, !visibleFrames.isEmpty else { return frame }
        let target = visibleFrames.max { lhs, rhs in
            lhs.intersection(frame).reeltoneArea < rhs.intersection(frame).reeltoneArea
        } ?? visibleFrames[0]
        var result = frame
        let maxX = max(target.minX, target.maxX - result.width)
        let maxY = max(target.minY, target.maxY - result.height)
        result.origin.x = min(max(result.minX, target.minX), maxX)
        result.origin.y = min(max(result.minY, target.minY), maxY)
        return result
    }
}

private extension CGRect {
    var reeltoneArea: CGFloat { isNull || isEmpty ? 0 : width * height }
}
