import CoreGraphics
import Foundation

let args = CommandLine.arguments

func windows() {
    guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements],
                                                kCGNullWindowID) as? [[String: Any]] else { return }
    for w in list {
        guard let owner = w[kCGWindowOwnerName as String] as? String, owner == "NullPlayer" else { continue }
        guard let id = w[kCGWindowNumber as String] as? Int,
              let b = w[kCGWindowBounds as String] as? [String: Any],
              let x = b["X"] as? Double, let y = b["Y"] as? Double,
              let width = b["Width"] as? Double, let height = b["Height"] as? Double else { continue }
        let layer = w[kCGWindowLayer as String] as? Int ?? 0
        let name = w[kCGWindowName as String] as? String ?? ""
        let alpha = w[kCGWindowAlpha as String] as? Double ?? 1
        print("\(id)\t\(layer)\t\(Int(x))\t\(Int(y))\t\(Int(width))\t\(Int(height))\t\(alpha)\t\(name)")
    }
}

/// A press-release pair at one point, with `mouseEventClickState` set.
///
/// `clickState` is not optional decoration: an event posted without it arrives as
/// `clickCount == 0`, and any handler that gates on `clickCount == 1` ignores it while the
/// window still highlights — a click that looks like it landed and did nothing.
func click(_ x: Double, _ y: Double, clickState: Int64 = 1) {
    let p = CGPoint(x: x, y: y)
    let move = CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: p, mouseButton: .left)
    move?.post(tap: .cghidEventTap)
    usleep(120_000)
    let down = CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown, mouseCursorPosition: p, mouseButton: .left)
    down?.setIntegerValueField(.mouseEventClickState, value: clickState)
    down?.post(tap: .cghidEventTap)
    usleep(80_000)
    let up = CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp, mouseCursorPosition: p, mouseButton: .left)
    up?.setIntegerValueField(.mouseEventClickState, value: clickState)
    up?.post(tap: .cghidEventTap)
}

/// Two clicks at one point, the second carrying `clickState == 2`.
func dblclick(_ x: Double, _ y: Double) {
    click(x, y, clickState: 1)
    usleep(60_000)
    click(x, y, clickState: 2)
}

/// Press at the first point, move with the button held through the rest, release at the last.
///
/// The held moves are `leftMouseDragged`, not `mouseMoved`: a slider tracks the drag events and
/// sees nothing at all from a move posted without the button down.
func drag(_ points: [CGPoint]) {
    guard let first = points.first, let last = points.last else { return }
    let move = CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: first, mouseButton: .left)
    move?.post(tap: .cghidEventTap)
    usleep(120_000)
    let down = CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown, mouseCursorPosition: first, mouseButton: .left)
    down?.setIntegerValueField(.mouseEventClickState, value: 1)
    down?.post(tap: .cghidEventTap)
    usleep(80_000)
    for p in points.dropFirst() {
        let dragged = CGEvent(mouseEventSource: nil, mouseType: .leftMouseDragged, mouseCursorPosition: p, mouseButton: .left)
        dragged?.setIntegerValueField(.mouseEventClickState, value: 1)
        dragged?.post(tap: .cghidEventTap)
        usleep(60_000)
    }
    let up = CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp, mouseCursorPosition: last, mouseButton: .left)
    up?.setIntegerValueField(.mouseEventClickState, value: 1)
    up?.post(tap: .cghidEventTap)
}

/// Hover: post `mouseMoved` through a path, pausing between points.
///
/// A hover is not a click with the buttons left out — the app only learns the pointer moved from
/// these events, and a skin's `onMouseOver`/`onMouseOut` fire on the *edges* between controls, so
/// the path matters. Points are screen coordinates, pairwise.
func move(_ points: [CGPoint]) {
    for p in points {
        CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: p, mouseButton: .left)?
            .post(tap: .cghidEventTap)
        usleep(250_000)
    }
}

func pairs(_ label: String, _ raw: ArraySlice<String>, minimum: Int) -> [CGPoint] {
    let numbers = raw.compactMap(Double.init)
    guard numbers.count >= minimum, numbers.count % 2 == 0 else {
        FileHandle.standardError.write("usage: winhelper \(label) <x> <y> [<x> <y> …]\n".data(using: .utf8)!)
        exit(1)
    }
    return stride(from: 0, to: numbers.count, by: 2).map { CGPoint(x: numbers[$0], y: numbers[$0 + 1]) }
}

switch args.count > 1 ? args[1] : "" {
case "windows": windows()
case "click":
    guard args.count == 4, let x = Double(args[2]), let y = Double(args[3]) else {
        FileHandle.standardError.write("usage: winhelper click <x> <y>\n".data(using: .utf8)!); exit(1)
    }
    click(x, y)
case "dblclick":
    guard args.count == 4, let x = Double(args[2]), let y = Double(args[3]) else {
        FileHandle.standardError.write("usage: winhelper dblclick <x> <y>\n".data(using: .utf8)!); exit(1)
    }
    dblclick(x, y)
case "move":
    move(pairs("move", args.dropFirst(2), minimum: 2))
case "drag":
    drag(pairs("drag", args.dropFirst(2), minimum: 4))
default:
    FileHandle.standardError.write("usage: winhelper windows|click|dblclick|move|drag\n".data(using: .utf8)!); exit(1)
}
