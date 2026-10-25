import AppKit

/// The skin's video surfaces (B20): which window the film goes in, and moving it there.
extension WinampModernMainWindowController {

    /// The skin's own video window, its holder filled with the app's video output.
    ///
    /// Five corpus skins declare a full `<container id="video">` — chrome, a `ledstatusbar` and the
    /// `VID_*` buttons — around a component holder that was decoration over an empty box. Returns
    /// false for a skin that declares none, which is what leaves NullPlayer's own video window in
    /// charge exactly as before.
    @discardableResult
    func hostVideoOutput() -> Bool {
        guard let coordinator = surfaceCoordinator else { return false }
        if case .embedded = coordinator.catalog.video { return hostVideoOutputInPlayer() }
        guard case .declaredContainer(let id) = coordinator.catalog.video,
              let container = auxiliaryContainer(id: id)
        else { return false }
        // The holder's surface is made by the view's own layout pass, and a window that has never
        // been on screen has not run one — the first video of a session would otherwise find no
        // surface to fill and fall back to our window while the skin's opened empty beside it.
        container.view.needsLayout = true
        container.view.layoutSubtreeIfNeeded()
        guard container.view.hostedVideoSurface != nil else { return false }
        // Not recorded: a film starting is not the user deciding this window should be open, and
        // writing it as one left an empty video window opening with the skin at every later launch
        // (B97). The same rule the runtime's `show()`/`hide()` already follow — this run, not the
        // next one.
        setAuxiliaryWindow(id: id, visible: true)
        return true
    }

    /// The other shape of a skin's video surface: a **tab of the player window** (B23).
    ///
    /// cPro-Bento hosts the video component in its SUI's Video tab and collapses its standalone
    /// `Video` container to a 1×1 stub, so there is no window to open — the tab has to be revealed
    /// instead, through the same `onGetCancelComponent` + `autoopen` route the Skin Windows menu and
    /// a script's `TOGGLE guid:{F0816D7B-…}` take. Answers **false** when revealing the tab produces
    /// no live holder, which is what leaves NullPlayer's own video window in charge rather than
    /// swallowing the picture into a surface that does not exist.
    func hostVideoOutputInPlayer() -> Bool {
        guard let view = skinView, let coordinator = surfaceCoordinator else { return false }
        coordinator.showSurface(.video)
        // The surface is made by the view's own layout pass, and revealing the tab has only changed
        // the graph so far: without this the first film of a session finds no box to fill.
        guard view.claimVideoSurface() != nil else { return openOwnVideoWindow() }
        // Key focus goes with the picture: off an embedded Library Browser that started the film,
        // where Return replays the row (M5), to the skin view, which hands the film its keys (M18).
        view.window?.makeFirstResponder(view)
        // …and again once the reveal has settled. Switching the tab sets off the skin's own
        // `onResize` cascade, which is what gives the box its final width — it runs after this turn,
        // and a film started while the tab was closed otherwise parked the picture over the box's
        // opening geometry and left it there, a white slab down one side of the tab.
        DispatchQueue.main.async { [weak self] in
            guard let view = self?.skinView else { return }
            view.needsLayout = true
            view.layoutSubtreeIfNeeded()
            view.hostedVideoSurface?.updateOutputPlacement()
        }
        return true
    }

    /// Put the skin's video window away — the `autoclose="1"` every measured holder declares. The
    /// picture stays lent, so the next play reopens rather than re-attaching.
    ///
    /// For an embedded surface there is no window to put away — hiding the player window is not what
    /// "close the video" means — so the picture is simply unparked and the tab left as it is, for the
    /// user or the skin to switch away from.
    @discardableResult
    func hideVideoSurfaceWindow() -> Bool {
        guard let coordinator = surfaceCoordinator else { return false }
        if case .embedded = coordinator.catalog.video {
            guard let surface = skinView?.hostedVideoSurface,
                  WindowManager.shared.currentVideoPlayerController?.isVideoOutputHosted == true
            else { return false }
            surface.hideVideoOutput()
            return true
        }
        return closeVideoSurfaceWindow()
    }

    /// Shut the skin's own video window, and nothing else — what Escape means. A video tab has no
    /// window of its own, so this leaves it alone: unparking there leaves the tab black while the
    /// film plays on, and selecting the tab again does not refill it.
    @discardableResult
    func closeVideoSurfaceWindow() -> Bool {
        guard case .declaredContainer(let id) = surfaceCoordinator?.catalog.video,
              let container = auxiliaryContainer(id: id),
              container.window.isVisible
        else { return false }
        // The `autoclose` counterpart of `hostVideoOutput`, and unrecorded for the same reason.
        setAuxiliaryWindow(id: id, visible: false)
        return true
    }

    /// Unpark the picture from the skin's box, leaving the window it came from alone.
    func detachVideoOutput() {
        guard let catalog = surfaceCoordinator?.catalog else { return }
        if case .embedded = catalog.video {
            skinView?.hostedVideoSurface?.detachVideoOutput()
            return
        }
        guard case .declaredContainer(let id) = catalog.video,
              let container = auxiliaryContainer(id: id)
        else { return }
        container.view.hostedVideoSurface?.detachVideoOutput()
    }

    /// Whether this container is a window the video box goes in: the one the catalog routes video
    /// to, or the video component's own window beside a player that holds the film (Winamp Single
    /// GUI's `Video`). Matched through the catalog rather than through `AuxiliaryContainer.kind`,
    /// because a skin can declare the window without a `component=` GUID (Love is War Miku's is a
    /// bare `<container id="video">`) and the catalog is the one place that reconciles both routes.
    func isVideoWindow(_ id: String) -> Bool {
        if case .declaredContainer(let videoID) = surfaceCoordinator?.catalog.video, videoID == id { return true }
        return videoDetachContainerID == id
    }

    /// Windows → Video Player. False when the skin has no surface for the film, which leaves
    /// NullPlayer's own video window in charge.
    func toggleVideo() -> Bool {
        guard let video = WindowManager.shared.currentVideoPlayerController else { return false }
        // A hosted picture lives in the skin's window, so that is what this shows and hides —
        // ordering out the controller's own window would do nothing visible at all (B20).
        if video.isVideoOutputHosted {
            if video.isVideoOutputVisible { hideVideoSurfaceWindow() } else { hostVideoOutput() }
            return true
        }
        // A film the player put away is unparked, not lost: showing it again asks the skin, as the
        // first showing did (B248).
        guard video.currentTitle != nil, video.window?.isVisible != true else { return false }
        return hostVideoOutput()
    }

    /// The video component's own window, for a film the player has no holder for — Winamp Single
    /// GUI's `Video` container while the player is shaded. Winamp shows a component in its own window
    /// only when no holder takes it, so neither the menu nor the host opens this window over a
    /// player that can hold the film: the skin's own Detach/Reattach buttons agree with the window
    /// only that way (B248). False when the skin ships no such window.
    private func openOwnVideoWindow() -> Bool {
        guard let id = videoDetachContainerID else { return false }
        setAuxiliaryWindow(id: id, visible: true)
        return true
    }

    /// A player holder that appears while the film is in the component's own window takes it back,
    /// which is what Single GUI's Reattach Video button relies on: it only switches the shaded player
    /// to its normal layout. Closing the window is the reattach (`setAuxiliaryWindow`).
    func playerVideoHolderWantsTheBox() {
        guard let id = videoDetachContainerID,
              let container = auxiliaryContainer(id: id),
              container.window.isVisible, container.view.hostedVideoSurface != nil else { return }
        setAuxiliaryWindow(id: id, visible: false)
    }

    /// A skin's own video window when the picture's home is the player: Winamp Single GUI's
    /// `Video` container, the detached view of the film its player panes show. Opening it detaches.
    var videoDetachContainerID: String? {
        guard case .embedded = surfaceCoordinator?.catalog.video else { return nil }
        return loadedSkin?.surfaceInventory.declaredContainers[.video]
    }

    /// `VID_1X` / `VID_2X`: size the skin's video window so its **box** is the stream's own pixel
    /// size times `multiple`.
    ///
    /// Winamp sizes its video window from the stream, not from an invented pixel count, and a `.wal`
    /// video layout is chrome around a `relatw="1"` holder — so the window grows by exactly the
    /// difference between the box the skin is drawing and the box the stream wants, and the skin's
    /// own frame, buttons and status bar stay where they are. Answers false when nothing is playing
    /// or the decoder has not published a size yet, which is where these buttons stay inert rather
    /// than resizing to a guess.
    ///
    /// **Inert for an embedded surface** (B23): there the box is a tab inside the player, and sizing
    /// it to the stream would resize the whole player window around a tab — Winamp sizes a *video
    /// window* from the stream, and cPro-Bento's video is not one. The buttons answer false and
    /// nothing moves, which is what they did before the tab hosted anything at all.
    @discardableResult
    func sizeVideoSurface(toNativeMultiple multiple: CGFloat) -> Bool {
        guard let coordinator = surfaceCoordinator,
              case .declaredContainer(let id) = coordinator.catalog.video,
              let container = auxiliaryContainer(id: id),
              let holder = container.view.videoHolderFrame,
              let surface = container.view.hostedVideoSurface
        else { return false }
        let renderer = container.view.renderer
        guard let proposed = WinampModernVideoHolder.canvasSize(canvas: renderer.canvasSize,
                                                                holder: holder,
                                                                native: surface.presentationSize,
                                                                multiple: multiple)
        else { return false }
        // Clamped to the screen as well as to the layout's own range. A 1x on a 1080p film is a
        // ~1940px window and a 2x is nearly 3900 — Winamp's own 1x/2x are exactly that literal, but a
        // window wider than the display is one the user cannot get hold of again.
        let visibleFrame = (container.window.screen ?? NSScreen.main)?.visibleFrame
        let visible = visibleFrame?.size ?? CGSize(width: 1_440, height: 900)
        let limits = renderer.userResizeLimits
        let ceilingW = min(limits.maximum.width, visible.width / skinScale)
        let ceilingH = min(limits.maximum.height, visible.height / skinScale)
        renderer.resize(to: CGSize(
            width: min(max(proposed.width, limits.minimum.width), ceilingW),
            height: min(max(proposed.height, limits.minimum.height), ceilingH)))
        let size = container.view.scaledCanvasSize
        resize(window: container.window, to: size)
        // …and kept on it. The resize holds the top-left corner, so Anunaki's video window, opened
        // low on the screen, grew off the bottom edge with its 1X/2X buttons — the only way back.
        if let visibleFrame {
            container.window.setFrameOrigin(
                WindowPlacement.rescued(container.window.frame, into: visibleFrame).origin)
        }
        container.view.setFrameSize(size)
        container.view.needsLayout = true
        container.view.needsDisplay = true
        return true
    }
}
