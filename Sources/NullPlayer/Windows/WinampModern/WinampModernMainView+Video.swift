import AppKit

/// The skin's one video box in this scene (B20, B246). The bridge owns the box and which view holds
/// it; this view mounts it, places it and feeds it only while it is the holder.
extension WinampModernMainView {

    /// The video surface in this scene, while this view holds the box. The window layer needs it to
    /// hand the picture over before showing the skin's video window, and to size that window from
    /// the stream's own dimensions for `VID_1X` / `VID_2X`.
    var hostedVideoSurface: WinampModernVideoSurface? { componentHost?.videoSurface(heldBy: self) }

    /// The video holder's frame in skin pixels, for the sizing arithmetic `VID_1X` / `VID_2X` do:
    /// the window grows by the difference between the box the skin drew and the box the stream wants.
    var videoHolderFrame: CGRect? {
        renderer.componentHolders().first { $0.kind == .video }?.frame
    }

    /// Pull the skin's one video box into this view's holder and park the picture on it: the detach
    /// into a skin's video window, and the reattach back into the player. The reconcile never moves
    /// the box out of a window on screen, so a deliberate move has to say so.
    @discardableResult
    func claimVideoSurface() -> WinampModernVideoSurface? {
        needsLayout = true
        layoutSubtreeIfNeeded()
        guard let holder = Self.videoHolder(among: renderer.componentHolders()),
              let surface = componentHost?.claimVideoSurface(by: self, fromVisibleWindow: true)
        else { return nil }
        if surface.view.superview !== self {
            mount(surface, for: holder)
            needsLayout = true
            layoutSubtreeIfNeeded()
        }
        surface.attachVideoOutput()
        surface.updateOutputPlacement()
        return surface
    }

    /// The reconcile's video half. Returns true when the box has just arrived in this view, which is
    /// the holder appearing (a tab switched to again) and the moment to park the picture there.
    func reconcileVideoSurface(holders: [WinampModernComponentHolder]) -> Bool {
        guard let holder = Self.videoHolder(among: holders) else {
            if let surface = hostedVideoSurface {
                // Unparks the picture — the one video view in the app must never be left orphaned in
                // a view that is about to leave the hierarchy — and leaves it hidden. The holder going
                // away is a tab switch, not a stop, so the film plays on and the window it came from
                // stays put.
                surface.unmountFromHolder()
                componentHost?.releaseVideoSurface(heldBy: self)
            }
            return false
        }
        guard hostedVideoSurface == nil else { return false }
        guard let surface = componentHost?.claimVideoSurface(by: self, fromVisibleWindow: false) else {
            // Asked after this pass: the answer may close a window and re-park the picture.
            if let refused = videoHolderRefused { DispatchQueue.main.async(execute: refused) }
            return false
        }
        mount(surface, for: holder)
        return true
    }

    /// Place the box over its holder, `placed` turning a skin rect into this view's.
    func layoutVideoSurface(holders: [WinampModernComponentHolder], placed: (CGRect) -> NSRect) {
        guard let surface = hostedVideoSurface, let holder = Self.videoHolder(among: holders) else { return }
        // The box re-places the parked picture itself when this actually moves or resizes it.
        // Clipped like the renderer's black box: the picture is a window of its own, so nothing
        // else cuts it, and Winamp Single GUI's 228px mini pane in a 280px player ran it down over
        // the LCD and the transport.
        surface.view.frame = placed(holder.frame.intersection(holder.clip))
    }

    /// **The biggest visible box wins.** A skin can hold the same component in several places at
    /// once — cPro-Bento's video lives in its tab, in the mini view above the playlist column *and*
    /// in the drawer. The largest is the one the user asked to see: the small ones are strips the
    /// skin leaves open beside it.
    private static func videoHolder(among holders: [WinampModernComponentHolder]) -> WinampModernComponentHolder? {
        holders.filter { $0.kind == .video }
            .max { $0.frame.width * $0.frame.height < $1.frame.width * $1.frame.height }
    }

    private func mount(_ surface: WinampModernVideoSurface, for holder: WinampModernComponentHolder) {
        // `noshowcmdbar="1"` — the holder's own instruction that it draws the transport itself.
        surface.showsCommandBar =
            WinampModernVideoHolder.showsCommandBar(holderAttributes: holder.object.attributes)
        surface.applySkinScale(skinScale)
        surface.applyPalette(renderer.palette)
        addSubview(surface.view)
    }
}
