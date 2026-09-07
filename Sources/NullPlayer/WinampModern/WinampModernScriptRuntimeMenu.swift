import AppKit
import CoreGraphics
import Foundation

/// The MAKI `PopupMenu` receiver: building a popup's command list, resolving a submenu,
/// and reporting the command the user picked. Split out of
/// `WinampModernScriptRuntime.swift`; see
/// `skills/winamp-modern-skin-guide/reference/compatibility/maki-surface.md`.
extension WinampModernScriptRuntime {
    func invokePopup(method: String, id: UInt64, arguments: [MakiValue]) -> MakiValue {
        switch method {
        case "addcommand":
            // Winamp's fourth argument is *disabled*, not "separator": storing it in the separator
            // slot turned every greyed-out command into a divider.
            popupCommands[id, default: []].append(
                PopupEntry(title: arguments[0].stringValue, commandID: arguments[1].integerValue,
                           checked: arguments[2].truthy, disabled: arguments[3].truthy))
            return .null
        case "addseparator":
            popupCommands[id, default: []].append(PopupEntry(isSeparator: true))
            return .null
        case "addsubmenu":
            // `parent.addSubMenu(child, title)` — the child is a PopupMenu the script has already
            // filled in. It is referenced rather than copied, so a script that keeps adding to the
            // child after attaching it still gets what it built (Love is War Miku's visualization
            // menu nests its Spectrum Analyzer and Oscilloscope presets this way).
            guard case .object(let reference) = arguments[0],
                  case .popupMenu(let child) = reference.kind else { return .null }
            popupCommands[id, default: []].append(
                PopupEntry(title: arguments[1].stringValue, submenu: child))
            return .null
        case "checkcommand":
            let commandID = arguments[0].integerValue
            if let index = popupCommands[id]?.firstIndex(where: { $0.commandID == commandID }) {
                popupCommands[id]?[index].checked = arguments[1].truthy
            }
            return .null
        case "popatmouse": return .integer(popupPresenter?(popupItems(of: id, depth: 0), nil) ?? 0)
        case "popatxy":
            // ClassicPro positions its tab-strip and "goto" menus with
            // `popAtXY(clientToScreenX(b.getLeft()), clientToScreenY(b.getTop() + 26))` — the point is
            // whatever those conversions answer, so the two have to agree. They do: both are
            // window-client space, and the presenter places the menu in that window.
            return .integer(popupPresenter?(popupItems(of: id, depth: 0),
                                            CGPoint(x: Int(arguments[0].integerValue),
                                                    y: Int(arguments[1].integerValue))) ?? 0)
        default: return .null
        }
    }

    /// One entry of a script-built menu, before its submenus are resolved.
    struct PopupEntry {
        var title = ""
        var commandID: Int32 = 0
        var checked = false
        var disabled = false
        var isSeparator = false
        /// The id of the `PopupMenu` this entry opens, for a submenu row.
        var submenu: UInt64?
    }

    /// Resolve a menu and everything it nests into the presenter's shape. A skin could attach a menu
    /// to itself, so the walk is depth-bounded rather than trusting the graph of menus to be a tree.
    private func popupItems(of id: UInt64, depth: Int) -> [WinampModernPopupMenuItem] {
        guard depth < 8, let entries = popupCommands[id] else { return [] }
        return entries.map { entry in
            WinampModernPopupMenuItem(
                title: entry.title, commandID: entry.commandID, checked: entry.checked,
                disabled: entry.disabled, isSeparator: entry.isSeparator,
                children: entry.submenu.map { popupItems(of: $0, depth: depth + 1) } ?? [])
        }
    }
}
