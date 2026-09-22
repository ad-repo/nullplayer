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
            // **A cast takes the picture away, not the session — so the window is handed back
            // visible.** Sending the film to a Chromecast stops the local decoder, `hasVideo` goes
            // false on the next host tick and this used to unpark the window *hidden*: the film
            // went to the television and every control over it went with it. Reported 2026-09-19 as
            // "the video player window disappeared when i casted to chromecast". It is the same
            // window that drives the cast in every other mode, so it stays on screen as the remote.
            detach(reveal: controller?.isCastingVideo == true)
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
        // **The picture keeps NullPlayer's own overlay — play, subtitles, casting, fullscreen.**
        // A `.wmz` draws its own transport, and for four phases that was the argument for switching
        // the bar off here; what it left was a skin's video window with no route to a subtitle, an
        // audio track or a cast device except a right-click most people never try. Reported
        // 2026-09-19 as "it is still not using the standard overlay with play, sub and casting
        // controls". The bar does not compress, so the box it lands in is built wide enough for it
        // — `WMPSceneBuilder.videoControlBarWidth`, applied to the *view*, which every corpus box
        // follows because it is authored `view.width` minus a shell.
        //
        // **But that widening is gated on `scene.isResizable` and a fixed view can never take it**
        // (W254). `WMPSceneBuilder.videoBarShortfall` refuses to grow a view pinned to its canvas —
        // correctly, because a window at a size its scene is not comes apart (W213) — so for a
        // fixed view the box stays whatever the skin authored, the bar's required constraints give
        // the parked window a minimum it cannot go under, and `setFrame` is silently refused:
        // `Revert`'s `vwPlayer` is `resizable="false"` with a 92pt box and the window took 395pt,
        // a black slab three hundred points wide hanging out through the skin's right edge, at the
        // exact height of the video band. The engine's own hosted-frame diagnostic had been naming
        // it all along — `box {92, 67} refused, window took {395, 67}`.
        //
        // So ask the box, not the skin: the bar goes on only where it fits. It does not compress,
        // which makes this bar-or-picture rather than a layout choice, and inside a box the skin
        // authored the picture is what the skin asked for. Every view that *can* be widened still
        // gets the bar, because the builder has already widened it by the time we are here — this
        // only ever fires on the boxes that were going to burst out of the window.
        controller.showsVideoControlBar = Self.barFits(box: visible.width,
                                                       minimumWidth: controller.videoControlBarMinimumWidth)
        // **And the window takes the pointer, because an overlay nobody can click is not one.**
        // The cost is the 21 `onClick` and 15 `onDblClick` attributes the corpus authors on
        // `<VIDEO>`; their nearest equivalents (play/pause, fullscreen) are on the bar itself, and
        // the skin's own controls outside the picture are untouched.
        controller.window?.ignoresMouseEvents = false
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
                } else if output.orderedIndex > parent.orderedIndex {
                    // Parented and still behind: order counts from the front, so a larger index is
                    // the defect. Belt and braces for a case the reparent above cannot reach.
                    output.order(.above, relativeTo: parent.windowNumber)
                }
            }
            controller.updateHostedOutputFrame(over: anchor)
        } else {
            controller.hostOutputWindow(over: anchor)
        }
    }

    /// Whether the command bar can be shown over a box this wide — the W254 rule, extracted so it
    /// is a fact a test can assert rather than a line inside a method that needs a window, a VLC
    /// session and a skin to reach. The half-point is the same tolerance
    /// `WMPSceneBuilder.videoBarShortfall` compares with, so the builder and the surface agree
    /// about which boxes are wide enough instead of disagreeing by a rounding error.
    static func barFits(box width: CGFloat, minimumWidth: CGFloat) -> Bool {
        width + 0.5 >= minimumWidth
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
    }
}
