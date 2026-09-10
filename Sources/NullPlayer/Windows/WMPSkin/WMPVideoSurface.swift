import AppKit

/// Owns only the presentation loan. The existing video controller retains playback and decoding.
@MainActor
final class WMPVideoSurface {
    private final class Anchor: NSView {
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }
    private let anchor = Anchor(frame: .zero)
    private weak var output: VideoPlayerWindowController?
    private var savedControlBar = true
    private var savedIgnoresMouse = false
    private var savedAlpha: CGFloat = 1

    func update(in view: NSView, scene: WMPScene, video: WMPVideoSnapshot,
                controller: VideoPlayerWindowController?) {
        guard video.hasVideo, let controller, !video.fullScreen,
              !controller.isVideoFullScreenTransition, view.window != nil,
              let widget = scene.widgets.last(where: {
                  $0.kind == .video && ($0.videoPresentation?.alpha ?? 1) > 0
              }) else {
            detach(reveal: false)
            return
        }
        let scaleX = view.bounds.width / max(1, scene.canvasSize.width)
        let scaleY = view.bounds.height / max(1, scene.canvasSize.height)
        let frame = CGRect(x: widget.frame.x * scaleX, y: widget.frame.y * scaleY,
                           width: widget.frame.width * scaleX, height: widget.frame.height * scaleY)
        let clip = widget.clipRect.map {
            CGRect(x: $0.x * scaleX, y: $0.y * scaleY, width: $0.width * scaleX, height: $0.height * scaleY)
        } ?? view.bounds
        let visible = frame.intersection(clip).intersection(view.bounds)
        guard !visible.isNull, !visible.isEmpty else { detach(reveal: false); return }
        if output !== controller {
            detach(reveal: false)
            savedControlBar = controller.showsVideoControlBar
            savedIgnoresMouse = controller.window?.ignoresMouseEvents ?? false
            savedAlpha = controller.window?.alphaValue ?? 1
            output = controller
        }
        if anchor.superview !== view { view.addSubview(anchor) }
        anchor.frame = visible
        let presentation = widget.videoPresentation ?? WMPVideoPresentation()
        let image = presentation.imageRect(source: CGSize(width: video.width, height: video.height),
                                           bounds: frame)
            .offsetBy(dx: -visible.minX, dy: -visible.minY)
        controller.showsVideoControlBar = false
        // **The picture is click-through, except while its own track panel is up.** 21 `onClick`
        // and 15 `onDblClick` attributes are authored on corpus `<VIDEO>` elements and those
        // handlers belong to the skin's scene, so the parked window must not swallow the event —
        // it passes through to `WMPMainView`, which hit-tests the widget frames. The one thing
        // that does need a pointer is the slide-out track panel (subtitle delay, external subtitle
        // tracks), which is drawn *inside* this window. Deriving the flag here rather than toggling
        // it when the panel opens makes it self-healing: `update` re-asserts it on every host tick,
        // so a panel dismissed by any route gets the click-through back within one tick.
        controller.window?.ignoresMouseEvents = !controller.isTrackSelectionPanelVisible
        controller.window?.alphaValue = presentation.alpha
        controller.configureWMPVideoOutput(imageRect: image,
                                            maintainAspectRatio: presentation.maintainAspectRatio)
        if controller.isVideoOutputHosted {
            // **`isVideoOutputHosted` is our flag; being a child window is AppKit's fact, and the
            // two drift apart.** Three reported defects are one cause: the picture went black while
            // the audio played and seeking still worked (it had fallen *behind* the skin, which a
            // real child can never do); it lagged out of the window frame on a drag (a real child
            // moves with its parent atomically — what was left was this 10 Hz reposition trailing
            // one tick behind); and switching apps put it right (activation makes AppKit re-collect
            // child windows). `hostOutputWindow` re-parents only when `!isVideoOutputHosted`, so
            // once the link is lost nothing restores it. Re-assert the relationship itself, not
            // just the ordering — a pointer compare on the common path.
            if let parent = view.window, let output = controller.window {
                if output.parent !== parent {
                    output.parent?.removeChildWindow(output)
                    parent.addChildWindow(output, ordered: .above)
                    WMPMainWindowController.traceInput("video reparented (was \(output.parent == nil ? "orphaned" : "elsewhere"))")
                } else if output.orderedIndex > parent.orderedIndex {
                    // Parented and still behind: order counts from the front, so a larger index is
                    // the defect. Belt and braces for a case the reparent above cannot reach.
                    output.order(.above, relativeTo: parent.windowNumber)
                    WMPMainWindowController.traceInput("video reordered above parent")
                }
            }
            controller.updateHostedOutputFrame(over: anchor)
        } else {
            controller.hostOutputWindow(over: anchor)
            WMPMainWindowController.traceInput("video hosted id=\(widget.nodeID ?? "-") frame=\(visible) source=\(video.width)x\(video.height)")
        }
    }

    /// The picture's menu, for a right-click that landed inside the box it is hosted in.
    ///
    /// `point` is in the holder view's coordinates, which is what `anchor.frame` is expressed in.
    /// Nil everywhere else, so the skin's own right-click behaviour is untouched.
    func menu(at point: NSPoint) -> NSMenu? {
        guard let output, anchor.superview != nil, anchor.frame.contains(point) else { return nil }
        return output.videoOutputMenu
    }

    func detach(reveal: Bool) {
        guard let output else { anchor.removeFromSuperview(); return }
        output.configureWMPVideoOutput(imageRect: nil)
        // A fullscreen transition has already reclaimed the window; never move it a second time.
        if output.isVideoOutputHosted { output.reclaimVideoOutput(reveal: reveal) }
        output.showsVideoControlBar = savedControlBar
        output.window?.ignoresMouseEvents = savedIgnoresMouse
        output.window?.alphaValue = savedAlpha
        self.output = nil
        anchor.removeFromSuperview()
        WMPMainWindowController.traceInput("video detached reveal=\(reveal)")
    }
}
