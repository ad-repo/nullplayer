import CoreGraphics

/// One image to draw, in face pixels with a top-left origin.
struct AudionFaceDrawOp {
    /// FaceKit's layer stack, bottom to top. `AudionFaceRenderer` composites each the way its
    /// layer does: `base` and `readouts` clear an op's rect before drawing it (FaceKit
    /// `context.clear`), `readouts` is its own transparent buffer (FaceKit's `sublayer`, zPosition 2,
    /// above the buttons at 1), `labels` draw unscaled and clipped (zPosition 10), and `mask` keeps
    /// only the alpha it covers.
    enum Layer: CaseIterable { case base, buttons, readouts, labels, mask }

    /// What the op draws, which decides its layer. The description is what the harness's probe prints.
    enum Element: Equatable, CustomStringConvertible {
        case base, mask
        case animation(AudionFace.AnimationRole)
        case button(AudionFace.ButtonRole)
        case digit(AudionFace.DigitRole)
        case indicator(AudionFace.IndicatorRole)
        /// `offset` is the marquee offset from the box's left edge, in device pixels.
        case label(AudionFace.TextRole, offset: Int)

        var layer: Layer {
            switch self {
            case .base, .animation: .base
            case .button: .buttons
            case .digit, .indicator: .readouts
            case .label: .labels
            case .mask: .mask
            }
        }

        var description: String {
            switch self {
            case .base: "base"
            case .mask: "mask"
            case .animation(let role): "animation:\(role)"
            case .button(let role): "button:\(role)"
            case .digit(let role): "digit:\(role)"
            case .indicator(let role): "indicator:\(role)"
            case .label(let role, _): "label:\(role)"
            }
        }
    }

    let element: Element
    let image: CGImage
    /// Where the image is stretched to; for a label, the box that clips it.
    let rect: AudionFaceRect
}

/// A face in a given state as the list of draws that make it, the one draw path the harness and
/// the window share. Pure: everything it reads is an argument. The state rules are FaceKit
/// `AudionFaceView`'s; `skills/audion-face-guide/reference/rendering.md` lists them.
struct AudionFaceScene {
    let width: Int
    let height: Int
    /// Integer scale. Ops stay in face pixels; text is rasterized at this scale.
    let scale: Int
    let ops: [AudionFaceDrawOp]

    /// `frame` is FaceKit's 60 Hz tick count; it drives the animation and the album marquee.
    init(face: AudionFace, host: AudionFaceHostState, interaction: AudionFaceInteractionState = .init(),
         frame: Int = 0, scale: Int = 1) {
        width = face.base.width
        height = face.base.height
        self.scale = scale
        ops = Self.baseOps(face, host, frame: frame) + Self.buttonOps(face, host, interaction)
            + Self.digitOps(face, host) + Self.indicatorOps(face, host)
            + Self.labelOps(face, host, frame: frame, scale: scale) + Self.maskOps(face, host)
    }

    /// The buttons drawn in this state, bottom first: play hides while playing when there is a pause
    /// button to show instead.
    static func visibleButtons(_ face: AudionFace, _ host: AudionFaceHostState) -> [(AudionFace.ButtonRole, AudionFace.Button)] {
        let pauseShows = host.isPlaying && face.buttons[.pause] != nil
        return AudionFace.ButtonRole.allCases.compactMap { role in
            guard let button = face.buttons[role], role != (pauseShows ? .play : .pause) else { return nil }
            return (role, button)
        }
    }

    /// The topmost visible button under a point in face pixels, top-left origin.
    static func button(atX x: Int, y: Int, face: AudionFace, host: AudionFaceHostState) -> AudionFace.ButtonRole? {
        visibleButtons(face, host).last { _, button in
            (button.rect.x..<button.rect.x + button.rect.width).contains(x)
                && (button.rect.y..<button.rect.y + button.rect.height).contains(y)
        }?.0
    }

    /// Whether a button takes a press and draws its own sprites rather than its disabled one: stop
    /// needs a track, and the window can disable any button.
    static func isEnabled(_ role: AudionFace.ButtonRole, host: AudionFaceHostState,
                          interaction: AudionFaceInteractionState) -> Bool {
        (role != .stop || host.hasTrack) && !interaction.disabled.contains(role)
    }

    /// FaceKit `LabelView.frameNum`: an 80-tick hold, then one pixel every two ticks, the text
    /// re-entering from the right after a 60 px gap. All widths in device pixels.
    static func marqueeOffset(frame: Int, textWidth: Int, boxWidth: Int) -> Int {
        let margin = 60, startup = 80
        let step = frame < startup ? 0 : ((frame - startup) / 2) % (textWidth + boxWidth + margin)
        return step > textWidth + margin ? boxWidth - (step - textWidth - margin) : -step
    }

    // MARK: - One function per element kind, in FaceKit's draw order

    private static func baseOps(_ face: AudionFace, _ host: AudionFaceHostState, frame: Int) -> [AudionFaceDrawOp] {
        var ops = [AudionFaceDrawOp(element: .base, image: face.base,
                                    rect: AudionFaceRect(x: 0, y: 0, width: face.base.width, height: face.base.height))]
        if let role = host.streamPhase.animation, let animation = face.animations[role] {
            let index = animation.frameDelay > 0 ? (frame / animation.frameDelay) % animation.frames.count : 0
            ops.append(AudionFaceDrawOp(element: .animation(role), image: animation.frames[index], rect: animation.rect))
        }
        return ops
    }

    private static func buttonOps(_ face: AudionFace, _ host: AudionFaceHostState,
                                  _ interaction: AudionFaceInteractionState) -> [AudionFaceDrawOp] {
        visibleButtons(face, host).map { role, button in
            let image = !isEnabled(role, host: host, interaction: interaction) ? button.disabledImage ?? button.image
                : interaction.pressed == role ? button.pressedImage ?? button.image
                : interaction.hovered == role ? button.hoverImage ?? button.image
                : button.image
            return AudionFaceDrawOp(element: .button(role), image: image, rect: button.rect)
        }
    }

    private static func digitOps(_ face: AudionFace, _ host: AudionFaceHostState) -> [AudionFaceDrawOp] {
        let minutes = host.elapsedSeconds / 60, seconds = host.elapsedSeconds % 60
        let track = host.trackIndex.flatMap { (1...99).contains($0) ? [$0 / 10, $0 % 10] : nil } ?? [10, 10]
        let numbers: [AudionFace.DigitRole: Int] = [
            .timeDigit1: minutes / 10, .timeDigit2: minutes % 10, .timeDigit3: seconds / 10, .timeDigit4: seconds % 10,
            .trackDigit1: track[0], .trackDigit2: track[1],
        ]
        return AudionFace.DigitRole.allCases.compactMap { role in
            guard let digit = face.digits[role], let number = numbers[role], digit.images.indices.contains(number)
            else { return nil }
            return AudionFaceDrawOp(element: .digit(role), image: digit.images[number], rect: digit.rect)
        }
    }

    private static func indicatorOps(_ face: AudionFace, _ host: AudionFaceHostState) -> [AudionFaceDrawOp] {
        AudionFace.IndicatorRole.allCases.compactMap { role in
            guard let indicator = face.indicators[role] else { return nil }
            let on = switch role {
            case .cddb, .cd: false
            case .net: host.hasTrack && host.streamPhase != .none
            case .mp3: host.hasTrack && host.streamPhase == .none
            case .play: host.isPlaying
            case .pause: host.hasTrack && !host.isPlaying
            }
            return AudionFaceDrawOp(element: .indicator(role), image: on ? indicator.onImage : indicator.image,
                                    rect: indicator.rect)
        }
    }

    /// The artist line is always middle-truncated and pinned; the album line truncates only when
    /// justified, and scrolls unless Reduce Motion is on — even when justified (FaceKit sets the
    /// album label's own `justify` to false). A box 12 px wide or narrower draws no text.
    private static func labelOps(_ face: AudionFace, _ host: AudionFaceHostState, frame: Int,
                                 scale: Int) -> [AudionFaceDrawOp] {
        let labels: [(AudionFace.TextRole, AudionFace.TextLine?, String?, Bool)] = [
            (.artist, face.artist, host.artistLine, true),
            (.album, face.album, host.albumLine, face.album?.style.contains(.justify) == true),
        ]
        return labels.compactMap { role, line, text, justify in
            guard let line, let text, line.rect.width > 12,
                  let image = AudionFaceText.image(text, line: line, justify: justify, scale: scale,
                                                   reduceMotion: host.reduceMotion) else { return nil }
            let pinned = role == .artist || host.reduceMotion
            let offset = pinned ? 0 : marqueeOffset(frame: frame, textWidth: image.width, boxWidth: line.rect.width * scale)
            return AudionFaceDrawOp(element: .label(role, offset: offset), image: image, rect: line.rect)
        }
    }

    private static func maskOps(_ face: AudionFace, _ host: AudionFaceHostState) -> [AudionFaceDrawOp] {
        guard let mask = !host.isWindowActive ? face.inactiveMask ?? face.mask : face.mask else { return [] }
        // `contentsGravity = .bottomLeft`: drawn at its own size from the bottom-left corner.
        return [AudionFaceDrawOp(element: .mask, image: mask,
                                 rect: AudionFaceRect(x: 0, y: face.base.height - mask.height,
                                                      width: mask.width, height: mask.height))]
    }
}

private extension AudionFaceHostState.StreamPhase {
    var animation: AudionFace.AnimationRole? {
        switch self {
        case .none: nil
        case .connecting: .connecting
        case .streaming: .streaming
        case .lag: .netLag
        }
    }
}
