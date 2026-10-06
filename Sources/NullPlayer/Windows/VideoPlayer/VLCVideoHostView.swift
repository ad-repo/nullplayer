import AppKit
import VLCKit

/// Host view for VLCKit's video output.
///
/// VLCKit inserts its own rendering subview into whatever NSView is assigned as
/// the player's `drawable`, and it sizes that subview to the host's bounds *at
/// insertion time*. For instant-starting local files (e.g. a freshly ripped
/// clip) that insertion can happen before the window has been laid out, leaving
/// the video pinned to the bottom-left corner at a stale size until a manual
/// resize nudges it. Streamed sources avoid this only because their first-frame
/// delay lets layout settle first. Forcing every subview to fill the host on
/// insertion and on every resize keeps the video output matched to the host
/// regardless of when VLCKit attaches it.
final class VLCVideoHostView: NSView {
    override func didAddSubview(_ subview: NSView) {
        super.didAddSubview(subview)
        subview.autoresizingMask = [.width, .height]
        subview.frame = bounds
        traceLayout("didAddSubview \(type(of: subview))")
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        for subview in subviews {
            subview.frame = bounds
        }
        traceLayout("setFrameSize")
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        // AppKit updates the render layer's `contentsScale` around this call; report after it.
        DispatchQueue.main.async { [weak self] in self?.reportSizeToVideoOutput() }
    }

    /// VLC's render layer (`VLCCAOpenGLLayer`, VLC 3.0 `caopengllayer.m`) tells its video output the
    /// drawing size only from `layoutSublayers`, as visible size × `contentsScale`, and drops the
    /// report while the output does not exist yet. A layout before the first frame therefore leaves
    /// the video at its own pixel size, cropped to the bottom-left; one while the layer is still at
    /// scale 1 on a Retina window puts the video in the bottom-left quarter. Neither is re-reported,
    /// because nothing lays the layer out again. Call this once the output exists and when the
    /// backing scale changes.
    func reportSizeToVideoOutput() {
        func relayout(_ layer: CALayer) {
            layer.setNeedsLayout()
            layer.layoutIfNeeded()
            layer.sublayers?.forEach(relayout)
        }
        layer?.sublayers?.forEach(relayout)
        traceLayout("reportSizeToVideoOutput")
    }

    // MARK: - Layout trace

    /// `VIDEO_LAYOUT_TRACE=1` (debug builds): log the host's view and layer tree, so a video drawn
    /// at the wrong size can be told apart from a view laid out at the wrong size.
    private static let layoutTraceEnabled: Bool = {
        #if DEBUG
        return ProcessInfo.processInfo.environment["VIDEO_LAYOUT_TRACE"] == "1"
        #else
        return false
        #endif
    }()

    func traceLayout(_ event: String) {
        guard Self.layoutTraceEnabled else { return }
        var lines = ["VIDEO_LAYOUT \(event) host=\(NSStringFromRect(bounds))"]
        func walk(_ view: NSView, _ depth: Int) {
            let pad = String(repeating: "  ", count: depth)
            lines.append("\(pad)view \(type(of: view)) frame=\(NSStringFromRect(view.frame))")
            if let layer = view.layer { walkLayer(layer, depth + 1) }
            view.subviews.forEach { walk($0, depth + 1) }
        }
        func walkLayer(_ layer: CALayer, _ depth: Int) {
            let pad = String(repeating: "  ", count: depth)
            lines.append("\(pad)layer \(type(of: layer)) frame=\(NSStringFromRect(layer.frame)) bounds=\(NSStringFromRect(layer.bounds)) scale=\(layer.contentsScale) gravity=\(layer.contentsGravity.rawValue)")
            layer.sublayers?.forEach { walkLayer($0, depth + 1) }
        }
        subviews.forEach { walk($0, 1) }
        if let layer { walkLayer(layer, 1) }
        NSLog("%@", lines.joined(separator: "\n"))
    }

    /// The trace at 0.3, 1 and 3 s after `player` starts, with VLC's video size.
    func traceLayoutAfterPlay(of player: VLCMediaPlayer) {
        guard Self.layoutTraceEnabled else { return }
        for delay in [0.3, 1.0, 3.0] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self, weak player] in
                self?.traceLayout("after play +\(delay)s videoSize=\(NSStringFromSize(player?.videoSize ?? .zero))")
            }
        }
    }
}
