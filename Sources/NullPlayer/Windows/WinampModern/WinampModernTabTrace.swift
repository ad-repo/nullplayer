#if DEBUG
import Foundation

/// `WINAMP_MODERN_TAB_TRACE=1`: one `TABS` line each time ClassicPro's SUI changes — the strip's tabs
/// left to right with the active one starred and each tab's centre in skin pixels (`@x,y`), the
/// pages on screen, and the skin canvas the centres are measured in (B350). Polled, so a change
/// from any route (a tab click, a menu item, the skin's own timers) is caught; the Bento tab script
/// `skills/app-control/scripts/bento_tabs.sh` reads the last line after each step.
final class WinampModernTabTrace {
    static let isEnabled = ProcessInfo.processInfo.environment["WINAMP_MODERN_TAB_TRACE"] != nil

    /// The SUI pages `CentroSUI.m` shows and hides, by object id.
    private static let pages: [(id: String, name: String)] = [
        ("centro.library", "library"), ("centro.playlist2", "playlist"), ("centro.video", "video"),
        ("centro.visualization", "visualization"), ("centro.browser", "browser"),
        ("centro.other", "other"), ("centro.widget", "widget"), ("centro.playlist1", "side-playlist"),
    ]

    private weak var renderer: WasabiSceneRenderer?
    private var timer: Timer?
    private var last = ""

    init?(renderer: WasabiSceneRenderer) {
        guard Self.isEnabled else { return nil }
        self.renderer = renderer
        timer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in self?.poll() }
    }

    deinit { timer?.invalidate() }

    private func poll() {
        guard let renderer else { return }
        let nodes = renderer.sceneNodes()
        let tabs = nodes.filter { $0.object.xmlID == "cpro.tab.text" && $0.frame.width > 0 }
            .sorted { $0.frame.minX < $1.frame.minX }
            .map { node -> String in
                let button = node.object.parent?.children.first { $0.xmlID == "cpro.tab.button" }
                let label = node.object.attributes["text"] ?? "?"
                let tab = node.frame.union(button.flatMap { renderer.frame(of: $0) } ?? node.frame)
                return (button?.attributes["activated"] == "1" ? label + "*" : label)
                    + "@\(Int(tab.midX)),\(Int(tab.midY))"
            }
        let shown = Set(nodes.filter { $0.frame.width >= 10 && $0.frame.height >= 10 }.compactMap(\.object.xmlID))
        let pages = Self.pages.filter { shown.contains($0.id) }.map(\.name)
        let canvas = renderer.canvasSize
        let line = "strip=[\(tabs.joined(separator: "|"))] pages=[\(pages.joined(separator: ","))]"
            + " canvas=\(Int(canvas.width))x\(Int(canvas.height))"
        guard line != last else { return }
        last = line
        NSLog("WinampModern TABS %@", line)
    }
}
#endif
