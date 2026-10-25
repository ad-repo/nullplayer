import AppKit

/// The Classic main window's O A I D V clutterbar: press state, latched selections, and actions.
/// O and V are menus that pop on press; A, I and D act on release over the same button.
final class ClassicClutterbar {
    typealias Button = SkinElements.Clutterbar.Button

    private var pressed: Button?

    /// Pressed, plus A and D while their setting is on
    var selectedButtons: [Button] {
        let wm = WindowManager.shared
        var buttons = [pressed].compactMap { $0 }
        if wm.isAlwaysOnTop { buttons.append(.alwaysOnTop) }
        if wm.uiScaleLevel == .p200 { buttons.append(.doubleSize) }
        return buttons
    }

    /// A menu button is held drawn until its menu closes
    func press(_ button: Button, menuAnchor: NSPoint, in view: NSView) {
        pressed = button
        let menu: NSMenu
        switch button {
        case .options: menu = ContextMenuBuilder.buildMenu(includeOutputDevices: false, includeRepeatShuffle: false)
        case .visualization: menu = ContextMenuBuilder.buildMenuBarVisualsMenu()
        case .alwaysOnTop, .fileInfo, .doubleSize: return
        }
        view.display()
        menu.popUp(positioning: nil, at: menuAnchor, in: view)
        pressed = nil
    }

    /// Ends a press, acting if released over the pressed button. Returns whether a press ended.
    func release(over action: PlayerAction?) -> Bool {
        guard let button = pressed else { return false }
        pressed = nil
        guard action == .clutterbar(button) else { return true }
        let wm = WindowManager.shared
        switch button {
        case .alwaysOnTop: wm.isAlwaysOnTop.toggle()
        case .fileInfo: MenuActions.shared.showAboutPlaying()
        case .doubleSize: wm.uiScaleLevel = wm.uiScaleLevel == .p200 ? .p100 : .p200
        case .options, .visualization: break  // menus finish on press
        }
        return true
    }
}
