import CoreGraphics

/// One image to draw, in face pixels with a top-left origin.
struct AudionFaceDrawOp {
    /// FaceKit's layer stack, bottom to top. `AudionFaceRenderer` composites each the way its
    /// layer does: `base` and `readouts` clear an op's rect before drawing it (FaceKit
    /// `context.clear`), `readouts` is its own transparent buffer (FaceKit's `sublayer`, zPosition 2,
    /// above the buttons at 1), `labels` draw unscaled and clipped (zPosition 10), and `mask` keeps
    /// only the alpha it covers.
    enum Layer: CaseIterable { case base, buttons, readouts, labels, mask }

    let layer: Layer
    /// `base`, `animation:<role>`, `digit:<role>`, `indicator:<role>`, `button:<role>`,
    /// `label:<role>` or `mask`; what the harness's probe prints.
    let element: String
    let image: CGImage
    /// Where the image is stretched to; for a label, the box that clips it.
    let rect: AudionFaceRect
    /// Labels only: the marquee offset from the box's left edge, in device pixels.
    var textOffset = 0
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
        var ops = [AudionFaceDrawOp(layer: .base, element: "base", image: face.base,
                                    rect: AudionFaceRect(x: 0, y: 0, width: width, height: height))]

        if let role = host.streamPhase.animation, let animation = face.animations[role] {
            let index = animation.frameDelay > 0 ? (frame / animation.frameDelay) % animation.frames.count : 0
            ops.append(AudionFaceDrawOp(layer: .base, element: "animation:\(role)",
                                        image: animation.frames[index], rect: animation.rect))
        }

        for (role, button) in Self.visibleButtons(face, host) {
            let enabled = (role != .stop || host.durationSeconds != 0) && !interaction.disabled.contains(role)
            let image = !enabled ? button.disabledImage ?? button.image
                : interaction.pressed == role ? button.pressedImage ?? button.image
                : interaction.hovered == role ? button.hoverImage ?? button.image
                : button.image
            ops.append(AudionFaceDrawOp(layer: .buttons, element: "button:\(role)", image: image, rect: button.rect))
        }

        let minutes = host.elapsedSeconds / 60, seconds = host.elapsedSeconds % 60
        let track = host.trackIndex.flatMap { (1...99).contains($0) ? [$0 / 10, $0 % 10] : nil } ?? [10, 10]
        let numbers: [AudionFace.DigitRole: Int] = [
            .timeDigit1: minutes / 10, .timeDigit2: minutes % 10, .timeDigit3: seconds / 10, .timeDigit4: seconds % 10,
            .trackDigit1: track[0], .trackDigit2: track[1],
        ]
        for role in AudionFace.DigitRole.allCases {
            guard let digit = face.digits[role], let number = numbers[role], digit.images.indices.contains(number)
            else { continue }
            ops.append(AudionFaceDrawOp(layer: .readouts, element: "digit:\(role)", image: digit.images[number],
                                        rect: digit.rect))
        }

        let hasTrack = host.durationSeconds != 0
        for role in AudionFace.IndicatorRole.allCases {
            guard let indicator = face.indicators[role] else { continue }
            let on = switch role {
            case .cddb, .cd: false
            case .net: hasTrack && host.streamPhase != .none
            case .mp3: hasTrack && host.streamPhase == .none
            case .play: host.isPlaying
            case .pause: hasTrack && !host.isPlaying
            }
            ops.append(AudionFaceDrawOp(layer: .readouts, element: "indicator:\(role)",
                                        image: on ? indicator.onImage : indicator.image, rect: indicator.rect))
        }

        // The artist line is always middle-truncated and pinned; the album line truncates only when
        // justified, and scrolls unless Reduce Motion is on — even when justified (FaceKit sets the
        // album label's own `justify` to false).
        let labels: [(AudionFace.TextRole, AudionFace.TextLine?, String?, Bool)] = [
            (.artist, face.artist, host.artistLine.flatMap { $0.isEmpty ? nil : $0 }, true),
            (.album, face.album, host.albumLine, face.album?.style.contains(.justify) == true),
        ]
        for (role, line, text, justify) in labels {
            guard let line, let text, line.rect.width > 12,
                  let image = AudionFaceRenderer.textImage(text, line: line, justify: justify, scale: scale,
                                                          reduceMotion: host.reduceMotion) else { continue }
            let pinned = role == .artist || host.reduceMotion
            ops.append(AudionFaceDrawOp(layer: .labels, element: "label:\(role)", image: image, rect: line.rect,
                textOffset: pinned ? 0 : Self.marqueeOffset(frame: frame, textWidth: image.width,
                                                            boxWidth: line.rect.width * scale)))
        }

        if let mask = !host.isWindowActive ? face.inactiveMask ?? face.mask : face.mask {
            // `contentsGravity = .bottomLeft`: drawn at its own size from the bottom-left corner.
            ops.append(AudionFaceDrawOp(layer: .mask, element: "mask", image: mask,
                rect: AudionFaceRect(x: 0, y: height - mask.height, width: mask.width, height: mask.height)))
        }
        self.ops = ops
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

    /// FaceKit `LabelView.frameNum`: an 80-tick hold, then one pixel every two ticks, the text
    /// re-entering from the right after a 60 px gap. All widths in device pixels.
    static func marqueeOffset(frame: Int, textWidth: Int, boxWidth: Int) -> Int {
        let margin = 60, startup = 80
        let step = frame < startup ? 0 : ((frame - startup) / 2) % (textWidth + boxWidth + margin)
        return step > textWidth + margin ? boxWidth - (step - textWidth - margin) : -step
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
