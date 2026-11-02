#if DEBUG
import Foundation

/// `WINAMP_MODERN_TAB_TRACE=1`: one `TABS` line each time ClassicPro's SUI changes — the strip's tabs
/// in strip order by their long name (the tooltip, which the Windows menu uses too), the active one
/// starred and each tab's centre in skin pixels (`@x,y`, or `@-` past the end of a strip that
/// scrolls), the tabs out of the strip, the pages on screen, and the skin canvas the centres are
/// measured in (B350). Which tabs are in the strip and which is active is the engine's own state. Polled, so a change from any
/// route (a tab click, a menu item, the skin's own timers) is caught; the ClassicPro tab script
/// `skills/app-control/scripts/bento_tabs.sh` reads the last line after each step. Silent on a skin
/// without the strip.
final class WinampModernTabTrace {
    static let isEnabled = ProcessInfo.processInfo.environment["WINAMP_MODERN_TAB_TRACE"] != nil

    /// The SUI pages `CentroSUI.m` shows and hides, by object id.
    private static let pages: [(id: String, name: String)] = [
        ("centro.library", "library"), ("centro.playlist2", "playlist"), ("centro.video", "video"),
        ("centro.visualization", "visualization"), ("centro.browser", "browser"),
        ("centro.other", "other"), ("centro.widget", "widget"), ("centro.playlist1", "side-playlist"),
    ]

    private weak var renderer: WasabiSceneRenderer?
    private let strip: ClassicProTabStrip
    private var timer: Timer?
    private var last = ""

    init?(renderer: WasabiSceneRenderer, strip: ClassicProTabStrip?) {
        guard Self.isEnabled, let strip else { return nil }
        self.renderer = renderer
        self.strip = strip
        timer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in self?.poll() }
    }

    deinit { timer?.invalidate() }

    private func poll() {
        guard let renderer else { return }
        let nodes = renderer.sceneNodes()
        // Where each drawn tab is, by its long name. A tab in the strip can be past its end — a
        // narrow strip scrolls (Insomnis) — and is then listed with `@-`.
        var drawn: [String: CGRect] = [:]
        for node in nodes where node.object.xmlID == "cpro.tab.text" && node.frame.width > 0 {
            guard let button = node.object.parent?.children.first(where: { $0.xmlID == "cpro.tab.button" }),
                  let label = button.attributes["tooltip"] else { continue }
            drawn[label] = node.frame.union(renderer.frame(of: button) ?? node.frame)
        }
        let tabs = strip.tabs
        let open = tabs.filter(\.isInStrip).map { tab in
            (tab.isActive ? tab.label + "*" : tab.label)
                + (drawn[tab.label].map { "@\(Int($0.midX)),\(Int($0.midY))" } ?? "@-")
        }
        let closed = tabs.filter { !$0.isInStrip }.map(\.label)
        let shown = Set(nodes.filter { $0.frame.width >= 10 && $0.frame.height >= 10 }.compactMap(\.object.xmlID))
        let pages = Self.pages.filter { shown.contains($0.id) }.map(\.name)
        let canvas = renderer.canvasSize
        let line = "strip=[\(open.joined(separator: "|"))] closed=[\(closed.joined(separator: "|"))]"
            + " pages=[\(pages.joined(separator: ","))]"
            + " canvas=\(Int(canvas.width))x\(Int(canvas.height))"
        guard line != last else { return }
        last = line
        NSLog("WinampModern TABS %@", line)
    }
}
#endif
