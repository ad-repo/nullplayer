import AppKit
import CoreGraphics
import Foundation

/// The MAKI `PopupMenu` receiver: building a popup's command list, resolving a submenu,
/// and reporting the command the user picked. Split out of
/// `WinampModernScriptRuntime.swift`; see
/// `skills/winamp-modern-skin-guide/reference/compatibility/maki-surface.md`.
extension WinampModernScriptRuntime {
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

extension WinampModernScriptRuntime {
    /// The `PopupMenu` methods. One a popup does not declare is inert (`invokeTraced`).
    static let popupMethods: MakiMethodTable<UInt64> = {
        var table = MakiMethodTable<UInt64>()
        table.add("addcommand", 4) { runtime, call in
            // Winamp's fourth argument is *disabled*, not "separator": storing it in the separator
            // slot turned every greyed-out command into a divider.
            runtime.popupCommands[call.id, default: []].append(
                PopupEntry(title: call.arguments[0].stringValue, commandID: call.arguments[1].integerValue,
                           checked: call.arguments[2].truthy, disabled: call.arguments[3].truthy))
            return .null
        }
        table.add("addseparator", 0) { runtime, call in
            runtime.popupCommands[call.id, default: []].append(PopupEntry(isSeparator: true))
            return .null
        }
        table.add("addsubmenu", 2) { runtime, call in
            // `parent.addSubMenu(child, title)` — the child is a PopupMenu the script has already
            // filled in. It is referenced rather than copied, so a script that keeps adding to the
            // child after attaching it still gets what it built (Love is War Miku's visualization
            // menu nests its Spectrum Analyzer and Oscilloscope presets this way).
            guard case .object(let reference) = call.arguments[0],
                  case .popupMenu(let child) = reference.kind else { return .null }
            runtime.popupCommands[call.id, default: []].append(
                PopupEntry(title: call.arguments[1].stringValue, submenu: child))
            return .null
        }
        table.add("checkcommand", 2) { runtime, call in
            let commandID = call.arguments[0].integerValue
            if let index = runtime.popupCommands[call.id]?.firstIndex(where: { $0.commandID == commandID }) {
                runtime.popupCommands[call.id]?[index].checked = call.arguments[1].truthy
            }
            return .null
        }
        table.add("disablecommand", 2) { runtime, call in
            let commandID = call.arguments[0].integerValue
            if let index = runtime.popupCommands[call.id]?.firstIndex(where: { $0.commandID == commandID }) {
                runtime.popupCommands[call.id]?[index].disabled = call.arguments[1].truthy
            }
            return .null
        }
        // No presenter means no menu was shown, which a skin reads as a dismissal.
        table.add("popatmouse", 0) { runtime, call in
            .integer(runtime.popupPresenter?(runtime.popupItems(of: call.id, depth: 0), nil)
                     ?? WinampModernScriptRuntime.popupDismissed)
        }
        table.add("popatxy", 2) { runtime, call in
            // ClassicPro positions its tab-strip and "goto" menus with
            // `popAtXY(clientToScreenX(b.getLeft()), clientToScreenY(b.getTop() + 26))` — the point is
            // whatever those conversions answer, so the two have to agree. They do: both are
            // window-client space, and the presenter places the menu in that window.
            let point = CGPoint(x: Int(call.arguments[0].integerValue), y: Int(call.arguments[1].integerValue))
            return .integer(runtime.popupPresenter?(runtime.popupItems(of: call.id, depth: 0), point)
                            ?? WinampModernScriptRuntime.popupDismissed)
        }
        return table
    }()
}
