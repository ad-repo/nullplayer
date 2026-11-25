import AppKit

extension SkinElements.Playlist {
    /// The standard Winamp 2 playlist editor's frame (`ClassicPlaylistStyle.winamp`): the 20px
    /// scrollbar border, the 38px bottom bar and where PLEDIT.BMP's art puts each control on them,
    /// measured from the base 2.91 skin. Skin coordinates, top-left origin, unscaled; the right-hand
    /// controls follow the window's right edge.
    enum Editor {
        static let barHeight: CGFloat = 38
        static let rightBorder: CGFloat = 20
        /// The bar's right corner, which carries LIST OPTS, the transport and both time displays.
        static let rightCornerWidth: CGFloat = SkinElements.Playlist.bottomRightCorner.width

        /// The close button's hit width: from just left of the title corner's close glyph to the
        /// right edge, short of the shade glyph beside it.
        static let closeWidth: CGFloat = 12

        /// The close glyph in the title bar's original right corner.
        static func closeGlyph(width: CGFloat) -> NSRect {
            NSRect(x: width - closeWidth + 1, y: 3, width: 9, height: 9)
        }

        enum Control: CaseIterable {
            case add, remove, select, misc, list
            case previous, play, pause, stop, next, eject
            case scrollUp, scrollDown
        }

        /// The control under `point` in a window of `size`, or nil.
        static func control(at point: NSPoint, size: NSSize) -> Control? {
            Control.allCases.first { rect(for: $0, size: size).contains(point) }
        }

        static func rect(for control: Control, size: NSSize) -> NSRect {
            let barTop = size.height - barHeight
            let right = size.width - rightCornerWidth
            func left(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> NSRect {
                NSRect(x: x, y: barTop + y, width: w, height: h)
            }
            func corner(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> NSRect {
                NSRect(x: right + x, y: barTop + y, width: w, height: h)
            }
            switch control {
            case .add: return left(11, 8, 25, 18)
            case .remove: return left(40, 8, 25, 18)
            case .select: return left(69, 8, 25, 18)
            case .misc: return left(98, 8, 25, 18)
            case .list: return corner(103, 8, 25, 18)
            case .previous: return corner(3, 22, 10, 9)
            case .play: return corner(13, 22, 9, 9)
            case .pause: return corner(22, 22, 10, 9)
            case .stop: return corner(32, 22, 9, 9)
            case .next: return corner(41, 22, 9, 9)
            case .eject: return corner(50, 22, 10, 9)
            case .scrollUp: return corner(134, 1, 10, 6)
            case .scrollDown: return corner(134, 7, 10, 6)
            }
        }

        /// The scrollbar groove inside the right border.
        static func scrollbarRect(size: NSSize) -> NSRect {
            NSRect(x: size.width - 15, y: titleHeight, width: 8,
                   height: max(0, size.height - titleHeight - barHeight))
        }

        /// Where the running time (`selected/total`) starts, in TEXT.BMP's 5×6 font.
        static func runningTimeOrigin(size: NSSize) -> NSPoint {
            NSPoint(x: size.width - rightCornerWidth + 7, y: size.height - barHeight + 10)
        }

        /// The colon the art bakes into the track time; minutes end left of it, seconds start right.
        static func trackTimeColon(size: NSSize) -> NSPoint {
            NSPoint(x: size.width - rightCornerWidth + 83, y: size.height - barHeight + 23)
        }
    }
}
