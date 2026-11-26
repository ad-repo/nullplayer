import AppKit

extension WinampModernMainWindowController: SkinOwnedWindowsProviding {
    /// Already-created skin-owned windows only, containers then hosted windows: reading this never
    /// materializes a hosted window. A container a script claims (`isDynamicWindow`: a
    /// `newDynamicContainer` copy, B110, or the declared container when a script is first to claim
    /// it, as Ebonite's playlist frame is) is still managed (levels, minimize) but is not a snap
    /// target: it is a frame glued to another window's rect. A hosted window joins the centre stack
    /// as its definition says.
    var managedSkinWindows: [ManagedSkinWindow] {
        let instances = Set(dynamicInstanceAuxiliaryWindows.map(ObjectIdentifier.init))
        return materializedAuxiliaryWindows.map { ManagedSkinWindow(window: $0, snapTarget: !instances.contains(ObjectIdentifier($0))) }
            + materializedHostedWindows.map {
                ManagedSkinWindow(window: $0.window, centerStack: $0.id.definition.stackPolicy.participatesInCenterStack)
            }
    }
}
