/*
Copyright 2020-2021 Panic Inc.

This file is part of Audion.

Audion is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

Audion is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with Audion.  If not, see <https://www.gnu.org/licenses/>.
*/
// NullPlayer: adapted from FaceKit `FaceKit/AudionFace.swift` at 5b7c847
// (https://gitlab.com/panicinc/facekit). The model and its font/colour rules are FaceKit's; loading
// moved to `AudionFaceDocument` and `AudionFaceLoader`, and the per-element properties became
// role-keyed dictionaries.

import AppKit

/// A loaded face: immutable, every image decoded. Built only by `AudionFaceLoader`, off the main thread.
struct AudionFace {
    let base: CGImage
    /// `base-alpha.png`: the window shape while active. Nil means the full `base` rectangle.
    let mask: CGImage?
    /// `inactive-alpha.png`: the window shape while inactive, when present.
    let inactiveMask: CGImage?

    let artist: TextLine?
    let album: TextLine?

    let buttons: [ButtonRole: Button]
    let indicators: [IndicatorRole: Indicator]
    let digits: [DigitRole: Digit]
    let animations: [AnimationRole: Animation]

    /// The author's credit lines, as authored.
    let faceInfo: [String]
    /// `about.png`, the author's credit art, any size. FaceKit ignores it; the info button shows it.
    let about: CGImage?
    /// Warnings only; a fatal finding is thrown instead of producing a face.
    let findings: [AudionFaceFinding]

    struct TextStyle: OptionSet, Hashable {
        let rawValue: Int
        static let bold = TextStyle(rawValue: 1 << 0)
        static let italic = TextStyle(rawValue: 1 << 1)
        static let underline = TextStyle(rawValue: 1 << 2)
        static let outline = TextStyle(rawValue: 1 << 3)
        static let shadow = TextStyle(rawValue: 1 << 4)
        static let condense = TextStyle(rawValue: 1 << 5)
        static let extend = TextStyle(rawValue: 1 << 6)
        static let justify = TextStyle(rawValue: 1 << 7)
    }

    struct TextLine {
        let rect: AudionFaceRect
        let font: CTFont
        let color: CGColor
        let style: TextStyle
        /// `…TextMode & 2`. Parsed, and deliberately not drawn (FaceKit does the same).
        let xor: Bool
    }

    struct Button {
        let image: CGImage
        let disabledImage: CGImage?
        let pressedImage: CGImage?
        let hoverImage: CGImage?
        /// Origin from `index.json`, size from `image`.
        let rect: AudionFaceRect
    }

    struct Indicator {
        let image: CGImage
        let onImage: CGImage
        let rect: AudionFaceRect
    }

    /// Each frame is drawn stretched into `rect`.
    struct Digit {
        let images: [CGImage]
        let rect: AudionFaceRect
    }

    struct Animation {
        let rect: AudionFaceRect
        let frames: [CGImage]
        /// Ticks of FaceKit's 60 Hz timer per frame; zero or less never advances.
        let frameDelay: Int
    }

    // MARK: - Roles. Each case order is FaceKit's draw order.

    /// FaceKit adds the buttons as subviews in this order, so a later one draws over (and is hit
    /// before) an earlier one it overlaps.
    enum ButtonRole: String, CaseIterable {
        case play, pause, stop, rewind = "rw", fastForward = "ff", eject
        case close, info, volume, playlist = "menu", mode = "music"

        /// The sprite's base name: `<sprite>.png`, `-active`, `-disabled`, `-hover`.
        var sprite: String { rawValue }
        /// `pause` shares `playButtonRect`; while playing, play hides and pause shows.
        var rectKey: String { self == .pause ? "playButtonRect" : "\(self)ButtonRect" }
    }

    enum IndicatorRole: CaseIterable {
        case cddb, cd, net, mp3, play, pause

        /// `<sprite>.png` off, `<sprite>-on.png` on.
        var sprite: String {
            switch self {
            case .play: "play-indicator"
            case .pause: "pause-indicator"
            default: "\(self)"
            }
        }

        var rectKey: String {
            switch self {
            case .cddb: "CDDBIndicatorRect"
            case .cd: "CDIndicatorRect"
            case .mp3: "MP3IndicatorRect"
            default: "\(self)IndicatorRect"
            }
        }
    }

    enum DigitRole: CaseIterable {
        case timeDigit1, timeDigit2, timeDigit3, timeDigit4, trackDigit1, trackDigit2

        /// Time digits show 0–9. Track digits carry an eleventh frame, a blank, at index 10.
        var frameCount: Int {
            switch self {
            case .trackDigit1, .trackDigit2: 11
            default: 10
            }
        }

        var rectKey: String { "\(self)Rect" }
        var firstPICTKey: String { "\(self)FirstPICTID" }
    }

    enum AnimationRole: CaseIterable {
        case connecting, streaming, netLag

        var rectKey: String { "\(self)AnimRect" }
        var frameDelayKey: String { "\(self)FrameDelay" }
        var firstPICTKey: String { "\(self)FirstPICTID" }
        var frameCountKey: String { "\(self)NumPICTs" }
    }

    enum TextRole: CaseIterable {
        case artist, album

        var rectKey: String { "\(self)DisplayRect" }
        var fontNameKey: String { "\(self)DisplayFontName" }
        var fontSizeKey: String { "\(self)FontSize" }
        var faceColorKey: String { "\(self)DisplayTextFaceColorFromFace" }
        var txtrColorKey: String { "\(self)DisplayTextFaceColorFromTxtr" }
        var textModeKey: String { "\(self)TextMode" }
        /// The eight style booleans, in `TextStyle` bit order.
        var styleKeys: [String] {
            ["Bold", "Italic", "Underline", "Outline", "Shadow", "Condense", "Extend", "Justify"]
                .map { "\(self)\($0)" }
        }
    }

    // MARK: - FaceKit's resolution rules

    /// FaceKit `decodeFont`: a name that does not resolve falls back to Helvetica at the authored
    /// size; a missing name or size falls back to Helvetica 12.
    static func font(named name: String?, size: Int?) -> CTFont {
        guard let name, let size else { return NSFont(name: "Helvetica", size: 12)! }
        return NSFont(name: name, size: CGFloat(size)) ?? NSFont(name: "Helvetica", size: CGFloat(size))!
    }

    /// FaceKit `decodeColor`'s output: 0–255 components, opaque.
    static func color(red: Int, green: Int, blue: Int) -> CGColor {
        CGColor(red: CGFloat(red) / 255, green: CGFloat(green) / 255, blue: CGFloat(blue) / 255, alpha: 1)
    }
}
