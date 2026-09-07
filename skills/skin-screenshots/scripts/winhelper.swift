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

func click(_ x: Double, _ y: Double) {
    let p = CGPoint(x: x, y: y)
    let move = CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: p, mouseButton: .left)
    move?.post(tap: .cghidEventTap)
    usleep(120_000)
    let down = CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown, mouseCursorPosition: p, mouseButton: .left)
    down?.post(tap: .cghidEventTap)
    usleep(80_000)
    let up = CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp, mouseCursorPosition: p, mouseButton: .left)
    up?.post(tap: .cghidEventTap)
}

switch args.count > 1 ? args[1] : "" {
case "windows": windows()
case "click":
    guard args.count == 4, let x = Double(args[2]), let y = Double(args[3]) else {
        FileHandle.standardError.write("usage: winhelper click <x> <y>\n".data(using: .utf8)!); exit(1)
    }
    click(x, y)
default:
    FileHandle.standardError.write("usage: winhelper windows|click\n".data(using: .utf8)!); exit(1)
}
