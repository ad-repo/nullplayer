import CoreGraphics
import CoreText
import Foundation

/// The pointer's effect on one frame: the control under it and the one held down.
struct AIMPSkinInteraction: Equatable, Sendable {
    var hovered: AIMPSkinControl.ID?
    var pressed: AIMPSkinControl.ID?
}

/// Something on screen the pointer can work: a control's rect in skin pixels and what it does.
struct AIMPSkinTarget: Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        /// An AIMP action (`acPlayerPlay`), carried out by the window or the player.
        case action(AIMPAction)
        /// Runs the skin's `OnClick` event handler with this control as `Sender`.
        case handler(String)
        /// Runs `down` when pressed, with the pointer's place in the control as `Arguments` `X` and
        /// `Y`, and `up` when released, wherever the pointer is then. GX-R60's and the Onkyos' REW and
        /// FF wind while held (the handlers switch a seek timer on and off); a click on SL-1200's
        /// record drops the needle at that groove.
        case hold(down: String, up: String?)
        /// Opens a menu: NullPlayer's like the one a key's `PopupMenu` names (`pmEqualizer`: the
        /// presets), else the player's.
        case menu(AIMPSkinPopup?)
        /// A playlist or library window's own maximize key: the window fills its screen, and back.
        case maximize
        /// Sets a counter's position: the step over the current one, wrapped by its `Module`.
        case counter(name: String, step: AIMPSkinStep)
        /// Shows or hides a layout item (Cassette-3D's VU meter panel).
        case toggle(item: String)
        /// Sets a provider to a fixed value, 0–1 (Vega's balance left/centre/right keys).
        case setValue(provider: AIMPSkinProvider, value: Double)
        /// Sets a tabbed group's page: the step over the current page, wrapped to its tab count.
        case page(group: String, step: AIMPSkinStep)
        /// A slider over a data provider (`prvVolume`), dragged along its long side.
        case slider(provider: AIMPSkinProvider?, vertical: Bool)
        /// A filmstrip knob over a data provider, turned by dragging.
        case knob(provider: AIMPSkinProvider?)
        /// A skin's own playlist: rows `rowHeight` tall from the top of the rect, the first being
        /// the `first` row the quick search leaves. A click selects a row, a double click plays
        /// it, the wheel scrolls.
        case playlist(first: Int, rowHeight: CGFloat)
        /// A list's quick search box ("Playlist", "MLTable", "MLGroupingTree"): a click types into it.
        case search(list: AIMPSkinList)
        /// The library window's group tree: rows `rowHeight` tall from the top, the first being row
        /// `first`. A click chooses a group (on its arrow, opens or closes it), a double click opens
        /// or closes it.
        case libraryTree(first: Int, rowHeight: CGFloat)
        /// The library window's table: a header `header` px tall, then rows `rowHeight` tall from row
        /// `first`. A click chooses a track, a double click adds it to the playlist and plays it.
        case libraryTable(first: Int, rowHeight: CGFloat, header: CGFloat)
        /// The playlist's scroll bar: a press or drag puts the thumb (`thumb` px long) under the
        /// pointer, scrolling to that share of `maxTop`, the last row that can be at the top.
        case playlistScroll(maxTop: Int, thumb: CGFloat)
        case seek

        /// Moved by dragging: a knob, slider or seek bar.
        var isDraggable: Bool {
            switch self {
            case .knob, .slider, .seek: return true
            default: return false
            }
        }

        /// A key a press on may become a drag of the knob or slider under it, once the pointer moves.
        var passesDragsThrough: Bool {
            switch self {
            case .action, .menu, .maximize: return true
            default: return false
            }
        }
    }

    /// The control it is on, and its name: what a script's handler gets as `Sender`.
    let control: AIMPSkinControl.ID
    let name: String
    let kind: Kind
    let rect: CGRect
    /// The button's hit mask, at the rect's size: a click on a transparent pixel of it falls through
    /// (Pioneer CT-F1000 draws REW and FF as two halves of one rect).
    var mask: AIMPAlphaMask? = nil
    /// What it repeats while held (`ActionOnHold`: PREV and NEXT wind, VOLUME − and + step).
    var holdAction: AIMPAction?
    /// The skin counter a long press sets, and to what (`ActionOnLongClick`).
    var longClick: LongClick?
    struct LongClick: Equatable, Sendable {
        let counter: String
        let value: Int
    }
    /// The skin handler a key runs when let go (`OnMouseUp`), whatever else it does.
    var releaseHandler: String?
    /// What a right-click does instead of the menu (`ContextMenu`): a knob back to its middle
    /// (the Akais' bass and treble to 60), the balance keys to centre, an action.
    var rightClick: Kind?

    init(control: AIMPSkinControl.ID, name: String, kind: Kind, rect: CGRect, mask: AIMPAlphaMask? = nil) {
        self.control = control
        self.name = name
        self.kind = kind
        self.rect = rect
        self.mask = mask
    }

    /// Whether `point` (skin pixels) hits this target: inside its rect, on a drawn pixel.
    func hit(_ point: CGPoint) -> Bool {
        guard rect.contains(point) else { return false }
        guard let mask, mask.width == Int(rect.width), mask.height == Int(rect.height) else { return true }
        return mask.covers(Int(point.x - rect.minX), Int(point.y - rect.minY))
    }
}

/// What a click, or a wheel notch, does to a skin counter's position or a tabbed group's page: the
/// skin's `Expression` over the current one (`Value`), compiled once and sorted by what the wheel
/// does with it.
struct AIMPSkinStep: Equatable, Sendable {
    /// Nil for none, or one that does not parse: a click leaves the position where it is.
    let expression: AIMPSkinExpression?
    let wheel: Wheel

    enum Wheel: Equatable, Sendable {
        /// Takes no notches: the expression picks a position, or there is none.
        case none
        /// One position a notch, stopping at the ends; a click steps to the next, however the skin
        /// spells it (`Value + 1`, `(value+1)mod 3`, `(Value + 1) MOD 6`). Akai CS-F33's TAPE
        /// SELECTOR, Pioneer's TAPE switch.
        case next
        /// The notches are the expression's `ScrollDelta` (`Value + ScrollDelta`: Denon DR-F8's
        /// MONITOR); a click is one.
        case scrollDelta
    }

    init(_ text: String?) {
        expression = text.flatMap(AIMPSkinExpression.init)
        if expression?.reads("scrolldelta") == true {
            wheel = .scrollDelta
        } else if expression?.stepsToNext == true {
            wheel = .next
        } else {
            wheel = .none
        }
    }

    /// The fixed position the expression names (`3`): what a right-click's `ContextMenu` sets.
    var position: Int? { expression?.constant.flatMap { $0 == $0.rounded() ? Int($0) : nil } }

    /// Where a click, or `notches` of the wheel, takes `current`; nil where the expression gives
    /// nothing (none, or one that does not evaluate), and the position stays.
    func next(from current: Double, notches: Int = 1) -> Double? {
        var variables = ["value": current]
        if wheel == .scrollDelta { variables["scrolldelta"] = Double(notches) }
        return expression?.evaluate(variables: variables)
    }
}

/// A picture's pixels, read once as the frame is drawn (off main), so a hit test on main reads one
/// byte of them rather than copying the picture.
struct AIMPAlphaMask: Equatable, Sendable {
    let width: Int
    let height: Int
    private let pixels: Data
    private let bytesPerRow: Int
    /// Where alpha sits in a pixel: first of ARGB or last of RGBA, in memory order.
    private let offset: Int

    /// Nil for a picture that is not 32 bits a pixel (hit as its whole rect).
    init?(_ image: CGImage?) {
        guard let image, image.bitsPerPixel == 32, let data = image.dataProvider?.data else { return nil }
        // Alpha is the first byte of ARGB, or the last; little-endian swaps the order in memory.
        let alphaFirst = [CGImageAlphaInfo.premultipliedFirst, .first].contains(image.alphaInfo)
        offset = alphaFirst != image.bitmapInfo.contains(.byteOrder32Little) ? 0 : 3
        width = image.width
        height = image.height
        bytesPerRow = image.bytesPerRow
        pixels = data as Data
    }

    func covers(_ x: Int, _ y: Int) -> Bool {
        guard x >= 0, y >= 0, x < width, y < height else { return false }
        let at = y * bytesPerRow + x * 4 + offset
        return at < pixels.count && pixels[pixels.startIndex + at] > 0
    }

    /// The bounding box of every pixel with any alpha, nil when nothing is drawn: the part of a
    /// frame a window shows (`AIMPSkinMainView.contentRect`). Measured inward from the edges, so a
    /// solid deck costs a row and a column rather than every pixel: it runs whenever a counter or
    /// page changes, which some skins do every tick (Sony TC-RX80's reels).
    var drawnBounds: CGRect? {
        pixels.withUnsafeBytes { raw -> CGRect? in
            let bytes = raw.bindMemory(to: UInt8.self)
            func drawn(_ x: Int, _ y: Int) -> Bool {
                let at = y * bytesPerRow + x * 4 + offset
                return at < bytes.count && bytes[at] > 0
            }
            func rowDrawn(_ y: Int) -> Bool { (0..<width).contains { drawn($0, y) } }
            guard let minY = (0..<height).first(where: rowDrawn),
                  let maxY = (minY..<height).reversed().first(where: rowDrawn) else { return nil }
            var minX = width, maxX = -1
            for y in minY...maxY {
                // Only the columns outside what is already known can widen the box.
                if let x = (0..<minX).first(where: { drawn($0, y) }) { minX = x }
                if let x = (max(maxX + 1, minX)..<width).reversed().first(where: { drawn($0, y) }) { maxX = x }
            }
            guard maxX >= minX else { return nil }
            return CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
        }
    }
}

/// One drawn frame and what can be clicked on it.
struct AIMPSkinFrame: Sendable {
    let image: CGImage
    /// Topmost last, as drawn.
    let targets: [AIMPSkinTarget]
    /// The image's alpha: where the window is.
    var alpha: AIMPAlphaMask?
    /// Each shown control's tooltip (its `Hint`), topmost last.
    var hints: [(rect: CGRect, text: String)] = []
    /// Where each named item and control was drawn, for `IsActive` on the next frame.
    var namedRects: [String: CGRect] = [:]
    /// A control's `OnMouseEnter`, `OnMouseMove` and `OnMouseLeave` handlers, where it was drawn.
    struct MouseHandlers: Sendable {
        let name: String
        let rect: CGRect
        let enter: String?
        let move: String?
        let leave: String?
    }
    var mouseHandlers: [MouseHandlers] = []
    /// Each gauge's value this frame and how fast it may rise and fall toward it, in its units
    /// per thirtieth of a second.
    var gauges: [AIMPSkinControl.ID: (value: Double, up: Double, down: Double)] = [:]
    /// The quick search box's font, for the field the window types into over it.
    var searchFont: AIMPSkinFont?
    /// The items this layout hid (`AIMPSkinState.Script.autoHidden`), for the next frame's bindings.
    var autoHidden: Set<String> = []

    func target(at point: CGPoint) -> AIMPSkinTarget? { targets.last { $0.hit(point) } }
    func hint(at point: CGPoint) -> String? { hints.last { $0.rect.contains(point) }?.text }

    /// Whether a pixel is part of the window: anything drawn there.
    func isOpaque(at point: CGPoint) -> Bool { alpha?.covers(Int(point.x), Int(point.y)) ?? false }
}

/// The menus a skin's keys pop up (`PopupMenu`, a list's right-click) that NullPlayer has one like,
/// read once from AIMP's names; a name it has none for opens the player menu.
enum AIMPSkinPopup: Sendable, Equatable {
    /// The playlist's own (`pmPlaylistMain`, `pmMisc`), adding files (`pmAdd`), taking them out
    /// (`pmDelete`), sorting (`pmSorting`).
    case playlist, add, remove, sort
    /// The EQ presets.
    case equalizer
    /// The library window's: its tree's and table's, its grouping presets, removing, and the rest.
    case libraryTree, libraryTable, libraryGroupings, libraryRemove, library

    init?(_ name: String) {
        switch name {
        case "pmPlaylistMain", "pmMisc": self = .playlist
        case "pmAdd": self = .add
        case "pmDelete": self = .remove
        case "pmSorting", "pmSort": self = .sort
        case "pmEqualizer", "pmEQPresets", "pmEQMenu", "pm_EQMenu": self = .equalizer
        case "pmMLGroupingTree": self = .libraryTree
        case "pmMLTable": self = .libraryTable
        case "pmMLGroupingPresets": self = .libraryGroupings
        case "pmMLDelete": self = .libraryRemove
        case "pmMLMisc", "pmMLMainMenu": self = .library
        default: return nil
        }
    }
}

/// The lists a skin's windows draw from NullPlayer's: the playlist, and the library's table and
/// group tree. The raw value is the name a skin binds to (`Source="MLTable"`).
enum AIMPSkinList: String, Sendable {
    case playlist = "Playlist"
    case libraryTable = "MLTable"
    case libraryTree = "MLGroupingTree"
}
