import AppKit
import CoreGraphics
import Foundation
import ImageIO

let args = CommandLine.arguments

struct WindowRow { let id: Int, layer: Int, x: Int, y: Int, w: Int, h: Int, alpha: Double, name: String, pid: Int }

/// On-screen windows owned by NullPlayer, front to back.
///
/// `.optionOnScreenOnly` is load-bearing: `.optionAll` includes offscreen windows and its order
/// means nothing. `pid` narrows to one process — the installed app is also "NullPlayer", and a row
/// from it looks exactly like one from the build under test. `size` narrows to the skin's canvas: a
/// `.wmz` list can carry a transient second row for the same app, and a click computed from it
/// lands on the desktop and reads like a dead control.
func windowRows(pid: Int? = nil, size: (Int, Int)? = nil) -> [WindowRow] {
    guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements],
                                                kCGNullWindowID) as? [[String: Any]] else { return [] }
    var rows: [WindowRow] = []
    for w in list {
        guard let owner = w[kCGWindowOwnerName as String] as? String, owner == "NullPlayer" else { continue }
        guard let id = w[kCGWindowNumber as String] as? Int,
              let b = w[kCGWindowBounds as String] as? [String: Any],
              let x = b["X"] as? Double, let y = b["Y"] as? Double,
              let width = b["Width"] as? Double, let height = b["Height"] as? Double else { continue }
        let owningPID = w[kCGWindowOwnerPID as String] as? Int ?? 0
        if let pid, owningPID != pid { continue }
        if let size, Int(width) != size.0 || Int(height) != size.1 { continue }
        rows.append(WindowRow(id: id, layer: w[kCGWindowLayer as String] as? Int ?? 0,
                              x: Int(x), y: Int(y), w: Int(width), h: Int(height),
                              alpha: w[kCGWindowAlpha as String] as? Double ?? 1,
                              name: w[kCGWindowName as String] as? String ?? "", pid: owningPID))
    }
    return rows
}

func windows(pid: Int?, size: (Int, Int)?) {
    for r in windowRows(pid: pid, size: size) {
        print("\(r.id)\t\(r.layer)\t\(r.x)\t\(r.y)\t\(r.w)\t\(r.h)\t\(r.alpha)\t\(r.name)")
    }
}

func fail(_ message: String) -> Never {
    FileHandle.standardError.write("winhelper: \(message)\n".data(using: .utf8)!)
    exit(1)
}

/// Bring one process to the front through System Events, by unix id, and prove it took.
///
/// `NSRunningApplication.activate()` from a background process is refused by recent macOS — it
/// returns and changes nothing — and `activate application "NullPlayer"` launches the *installed*
/// copy. A keystroke or first click sent to the wrong app reads exactly like a dead control, so this
/// exits non-zero unless `pid` is frontmost afterwards.
func raise(pid: Int) {
    let script = "tell application \"System Events\" to set frontmost of (first process whose unix id is \(pid)) to true"
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
    p.arguments = ["-e", script]
    do { try p.run() } catch { fail("osascript: \(error)") }
    p.waitUntilExit()
    for _ in 0..<20 {
        if NSWorkspace.shared.frontmostApplication?.processIdentifier == pid_t(pid) { print("frontmost \(pid)"); return }
        usleep(100_000)
    }
    fail("pid \(pid) is not frontmost after raising (frontmost: \(NSWorkspace.shared.frontmostApplication?.processIdentifier ?? -1))")
}

/// Move one window of `pid`, found by title, to a top-left screen point and raise it; prove it took.
///
/// A window that runs off the screen cannot be captured by id — `-l` returns a full-screen image
/// for it — so it has to be parked on-screen first. Position is set through System Events (the
/// same top-left origin as `winhelper windows`), then read back from the window list: a title that
/// matched nothing, or a window the app snapped elsewhere, exits non-zero instead of leaving the
/// next capture to photograph the wrong place.
func park(pid: Int, name: String, x: Int, y: Int) {
    let quoted = name.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
    let target = "tell application \"System Events\" to tell (first process whose unix id is \(pid)) to tell (first window whose name is \"\(quoted)\")"
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
    p.arguments = ["-e", "\(target) to set position to {\(x), \(y)}", "-e", "\(target) to perform action \"AXRaise\""]
    p.standardOutput = FileHandle.nullDevice
    p.standardError = FileHandle.nullDevice
    do { try p.run() } catch { fail("osascript: \(error)") }
    p.waitUntilExit()
    if p.terminationStatus != 0 { fail("no window titled \"\(name)\" in pid \(pid)") }
    for _ in 0..<10 {
        if let r = windowRows(pid: pid).first(where: { $0.name == name }), r.x == x, r.y == y {
            print("\(r.id)\t\(r.layer)\t\(r.x)\t\(r.y)\t\(r.w)\t\(r.h)\t\(r.alpha)\t\(r.name)"); return
        }
        usleep(100_000)
    }
    let now = windowRows(pid: pid).first(where: { $0.name == name }).map { "\($0.x),\($0.y)" } ?? "not on screen"
    fail("window \"\(name)\" is at \(now) after parking at \(x),\(y)")
}

/// The window-frame check: list the windows, click, wait, list them again, and say what changed.
///
/// This is the measurement for "does this control do anything" — `harness/live-loop.md` § *A live pass is a
/// window frame, before and after*. Windows are matched by id, so a view switch that replaces its
/// window reads as one `gone` and one `new`, not as a resize. `--size` narrows only the *before*
/// listing (to find the skin's canvas); the *after* listing takes every window of the same
/// processes, since a resize is exactly what would otherwise drop the row. Exits 2 when nothing
/// changed, so a dead click cannot pass for a live one — and the before listing is printed first,
/// so a launch that came up on the unskinned 440x170 view is visible at a glance.
func clickdiff(_ x: Double, _ y: Double, pid: Int?, size: (Int, Int)?, settle: Double, double: Bool) {
    let before = windowRows(pid: pid, size: size)
    guard !before.isEmpty else { fail("no on-screen NullPlayer window matches (see `winhelper windows`)") }
    let pids = Set(before.map(\.pid))
    let existing = Set(windowRows().filter { pids.contains($0.pid) }.map(\.id))
    func line(_ tag: String, _ r: WindowRow) -> String {
        "\(tag)\t\(r.id)\t\(r.x)\t\(r.y)\t\(r.w)\t\(r.h)\t\(r.alpha)\t\(r.name)"
    }
    for r in before { print(line("before", r)) }
    if double { dblclick(x, y) } else { click(x, y) }
    usleep(useconds_t(settle * 1_000_000))
    let after = windowRows().filter { pids.contains($0.pid) }
    for r in after { print(line("after", r)) }
    var changes = 0
    let afterByID = Dictionary(after.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
    let beforeIDs = Set(before.map(\.id))
    for b in before {
        guard let a = afterByID[b.id] else { print(line("gone", b)); changes += 1; continue }
        var what: [String] = []
        if (a.x, a.y) != (b.x, b.y) { what.append("moved \(b.x),\(b.y)->\(a.x),\(a.y)") }
        if (a.w, a.h) != (b.w, b.h) { what.append("resized \(b.w)x\(b.h)->\(a.w)x\(a.h)") }
        if a.alpha != b.alpha { what.append("alpha \(b.alpha)->\(a.alpha)") }
        if a.name != b.name { what.append("renamed \"\(b.name)\"->\"\(a.name)\"") }
        if !what.isEmpty { print("changed\t\(b.id)\t\(what.joined(separator: " "))\t\(a.name)"); changes += 1 }
    }
    // A window --size filtered out of `before` existed already; the click did not create it.
    for a in after where !beforeIDs.contains(a.id) && !existing.contains(a.id) {
        print(line("new", a)); changes += 1
    }
    if changes == 0 { print("unchanged"); exit(2) }
}

/// Capture one window's **own** content with `screencapture -l`, and refuse a wrong picture.
///
/// `-l` sees the window regardless of what occludes it (`-R` photographs the screen — including a
/// terminal on top, or whatever shows through a keyed-out hole). It has two silent traps, and the
/// pixel size is what exposes both:
///
/// * for an id that is off-screen or stale it returns a **full-screen** image;
/// * for a window with attached child windows — a docked `.wmz` group — it returns the **whole
///   group**: `-l` on a 197x194 pt window returned 950x890 pt, the bounding box of it and its two
///   docked neighbours (measured 2026-09-24).
///
/// So the image must be the window's points times a backing scale, or — the group case — the
/// bounding box of the process's on-screen windows times a scale, in which case the window's own
/// rect is cropped out of it and the output says `cropped-from-group`. Anything else exits non-zero.
func capture(_ row: WindowRow, to path: String, siblings: [WindowRow], quiet: Bool = false) -> Bool {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
    p.arguments = ["-o", "-x", "-l", String(row.id), path]
    do { try p.run() } catch { return false }
    p.waitUntilExit()
    let url = URL(fileURLWithPath: path) as CFURL
    guard let src = CGImageSourceCreateWithURL(url, nil),
          let image = CGImageSourceCreateImageAtIndex(src, 0, nil) else {
        FileHandle.standardError.write("winhelper: no image for window \(row.id)\n".data(using: .utf8)!)
        return false
    }
    let pw = image.width, ph = image.height
    for scale in [1, 2, 3] where pw == row.w * scale && ph == row.h * scale {
        print("\(path)\t\(pw)x\(ph)\t@\(scale)x\t\(row.id)\t\(row.name)")
        return true
    }
    let minX = siblings.map(\.x).min() ?? row.x, minY = siblings.map(\.y).min() ?? row.y
    let maxX = siblings.map { $0.x + $0.w }.max() ?? row.x + row.w
    let maxY = siblings.map { $0.y + $0.h }.max() ?? row.y + row.h
    for scale in [1, 2, 3] where pw == (maxX - minX) * scale && ph == (maxY - minY) * scale {
        let rect = CGRect(x: (row.x - minX) * scale, y: (row.y - minY) * scale, width: row.w * scale, height: row.h * scale)
        guard let cropped = image.cropping(to: rect),
              let dst = CGImageDestinationCreateWithURL(url, "public.png" as CFString, 1, nil) else { break }
        CGImageDestinationAddImage(dst, cropped, nil)
        guard CGImageDestinationFinalize(dst) else { break }
        print("\(path)\t\(cropped.width)x\(cropped.height)\t@\(scale)x\t\(row.id)\t\(row.name)\tcropped-from-group")
        return true
    }
    try? FileManager.default.removeItem(atPath: path)
    if quiet { return false }
    FileHandle.standardError.write(("winhelper: window \(row.id) (\(row.name)) is \(row.w)x\(row.h) pt but the capture is "
        + "\(pw)x\(ph) px — neither this window nor its group; off-screen or stale. Move it on-screen and retry.\n")
        .data(using: .utf8)!)
    return false
}

/// `capture`, re-reading the window's geometry between attempts: a window that is fading in or
/// resizing (a `.wmz` pane animates both) changes size between the listing and the shot, and the
/// size check rightly refuses that picture. Three attempts, 400 ms apart; only the last one reports.
func captureSettled(id: Int, pid: Int?, to path: String) -> Bool {
    for attempt in 0..<3 {
        guard let row = windowRows(pid: pid).first(where: { $0.id == id }) else {
            fail("window \(id) is not an on-screen NullPlayer window (see `winhelper windows`)")
        }
        if capture(row, to: path, siblings: windowRows(pid: row.pid), quiet: attempt < 2) { return true }
        usleep(400_000)
    }
    return false
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

/// Wheel events at one point.
///
/// `units` is the whole difference between the two devices and a surface may read only one of
/// them: `.pixel` is a trackpad — a precise, continuous delta in points, which is what
/// `hasPreciseScrollingDeltas` reports and what a per-point scroller consumes — and `.line` is a
/// mouse wheel, whose delta is a line count. A view that scrolls under one and not the other is
/// not a flaky view; post both before believing either.
func scroll(_ x: Double, _ y: Double, count: Int, delta: Int32, precise: Bool) {
    let p = CGPoint(x: x, y: y)
    CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: p, mouseButton: .left)?
        .post(tap: .cghidEventTap)
    usleep(150_000)
    for _ in 0..<count {
        let event = CGEvent(scrollWheelEvent2Source: nil, units: precise ? .pixel : .line,
                            wheelCount: 1, wheel1: delta, wheel2: 0, wheel3: 0)
        event?.location = p
        if precise { event?.setIntegerValueField(.scrollWheelEventIsContinuous, value: 1) }
        event?.post(tap: .cghidEventTap)
        usleep(40_000)
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

/// `--pid <n>` and `--size <w>x<h>` filters, wherever they appear after the verb.
func filters(_ raw: ArraySlice<String>) -> (pid: Int?, size: (Int, Int)?, rest: [String]) {
    var pid: Int?, size: (Int, Int)?, rest: [String] = [], it = raw.makeIterator()
    while let a = it.next() {
        switch a {
        case "--pid": guard let v = it.next(), let n = Int(v) else { fail("--pid needs a number") }; pid = n
        case "--size":
            let parts = (it.next() ?? "").split(separator: "x").compactMap { Int($0) }
            guard parts.count == 2 else { fail("--size needs <w>x<h>") }
            size = (parts[0], parts[1])
        default: rest.append(a)
        }
    }
    return (pid, size, rest)
}

switch args.count > 1 ? args[1] : "" {
case "windows":
    let f = filters(args.dropFirst(2)); windows(pid: f.pid, size: f.size)
case "screens":
    // Each display's visibleFrame (menu bar and Dock excluded) in the same top-left global points
    // as `windows`, plus its backing scale: the space `WindowPlacement.isReachable` measures in.
    let top = NSScreen.screens.first?.frame.maxY ?? 0
    for s in NSScreen.screens {
        let v = s.visibleFrame
        print("\(Int(v.minX))\t\(Int(top - v.maxY))\t\(Int(v.width))\t\(Int(v.height))\t\(s.backingScaleFactor)")
    }
case "raise":
    guard args.count == 3, let pid = Int(args[2]) else { fail("usage: winhelper raise <pid>") }
    raise(pid: pid)
case "capture":
    let f = filters(args.dropFirst(2))
    guard f.rest.count == 2, let id = Int(f.rest[0]) else {
        fail("usage: winhelper capture <windowid> <out.png>")
    }
    exit(captureSettled(id: id, pid: f.pid, to: f.rest[1]) ? 0 : 1)
case "capture-all":
    let f = filters(args.dropFirst(2))
    guard f.rest.count == 1 else { fail("usage: winhelper capture-all <outdir> [--pid <n>] [--size <w>x<h>]") }
    try? FileManager.default.createDirectory(atPath: f.rest[0], withIntermediateDirectories: true)
    var failed = 0
    for row in windowRows(pid: f.pid, size: f.size) {
        let safe = row.name.isEmpty ? "untitled" : row.name.replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: " ", with: "_")
        if !captureSettled(id: row.id, pid: row.pid, to: "\(f.rest[0])/\(row.id)-\(safe).png") { failed += 1 }
    }
    exit(failed == 0 ? 0 : 1)
case "park":
    guard args.count == 6, let pid = Int(args[2]), let x = Int(args[4]), let y = Int(args[5]) else {
        fail("usage: winhelper park <pid> <window-title> <x> <y>")
    }
    park(pid: pid, name: args[3], x: x, y: y)
case "clickdiff", "dblclickdiff":
    var f = filters(args.dropFirst(2)), settle = 1.0
    if let i = f.rest.firstIndex(of: "--settle"), i + 1 < f.rest.count, let s = Double(f.rest[i + 1]) {
        settle = s; f.rest.removeSubrange(i...(i + 1))
    }
    guard f.rest.count == 2, let x = Double(f.rest[0]), let y = Double(f.rest[1]) else {
        fail("usage: winhelper \(args[1]) <x> <y> [--pid <n>] [--size <w>x<h>] [--settle <seconds>]")
    }
    clickdiff(x, y, pid: f.pid, size: f.size, settle: settle, double: args[1] == "dblclickdiff")
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
case "scroll":
    guard args.count >= 6, let x = Double(args[2]), let y = Double(args[3]),
          let count = Int(args[4]), let delta = Int32(args[5]) else {
        FileHandle.standardError.write(
            "usage: winhelper scroll <x> <y> <count> <delta> [line|precise]\n".data(using: .utf8)!)
        exit(1)
    }
    scroll(x, y, count: count, delta: delta, precise: args.count > 6 && args[6] == "precise")
case "move":
    move(pairs("move", args.dropFirst(2), minimum: 2))
case "drag":
    drag(pairs("drag", args.dropFirst(2), minimum: 4))
default:
    FileHandle.standardError.write(
        "usage: winhelper windows|screens|raise|park|capture|capture-all|click|dblclick|clickdiff|dblclickdiff|scroll|move|drag\n".data(using: .utf8)!)
    exit(1)
}
