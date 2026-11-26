import AppKit

extension WMPMainWindowController: SkinOwnedWindowsProviding {
    /// A skin's `theme.openView` panels, each a real top-level window: snap targets only, never
    /// centre-stack members. A `.wmz` view is an arbitrary authored canvas (Halo 2's panels are
    /// 406x209 against a 327x294 player), so there is no column for it to join.
    var managedSkinWindows: [ManagedSkinWindow] {
        materializedAuxiliaryWindows.map { ManagedSkinWindow(window: $0) }
    }
}
