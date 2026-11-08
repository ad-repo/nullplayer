import AppKit

/// What the script-glued window pairs (`WinampModernGluedWindows`) read from the controller: the pairs
/// the runtime learned, the window and picture of each container, and whether a container hosts a
/// surface.
extension WinampModernMainWindowController: WinampModernGlueSource {
    var gluedOver: [(leader: WasabiObjectID, follower: WasabiObjectID)] {
        skinView?.scripts.windowsGluedOver.map { (leader: $0.key, follower: $0.value) } ?? []
    }

    var gluedBehindCandidates: [(leader: WasabiObjectID, follower: WasabiObjectID)] {
        skinView?.scripts.windowsGluedBehind.map { (leader: $0.key, follower: $0.value) } ?? []
    }

    func gluedWindow(_ id: WasabiObjectID) -> NSWindow? { viewsByContainer[id]?.window }

    func gluedPicture(_ id: WasabiObjectID) -> CGImage? { viewsByContainer[id]?.frames.outline }

    func isHostSurface(_ id: WasabiObjectID) -> Bool {
        auxiliaryContainers.contains { $0.view.containerID == id && $0.kind != nil }
    }
}
