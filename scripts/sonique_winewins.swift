// Prints every on-screen window owned by a Wine process: id x y width height title.
// winhelper filters to NullPlayer's windows; Wine's are owned by the preloader, so they need this.
import CoreGraphics

let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
for w in windows where (w["kCGWindowOwnerName"] as? String ?? "").lowercased().contains("wine") {
    let b = w["kCGWindowBounds"] as? [String: Any] ?? [:]
    print(w["kCGWindowNumber"] ?? 0, b["X"] ?? 0, b["Y"] ?? 0, b["Width"] ?? 0, b["Height"] ?? 0,
          w["kCGWindowName"] as? String ?? "")
}
