import Foundation

/// The command a skin puts on the **second** click or on the **right** button.
///
/// Wasabi has three action attributes on the same object, not one: `action=` fires on a normal
/// click, `dblclickaction=` on a double-click, `rightclickaction=` on the right button. The last two
/// were read nowhere, which is why a song title carrying
/// `dblclickaction="TRACKINFO" rightclickaction="TRACKMENU"` — six and five of the seventeen measured
/// skins — was dead to both, and why double-clicking a titlebar never went to winshade in the five
/// skins that spell that `dblclickaction="SWITCH;shade"`.
///
/// Two spellings for the parameter, and skins use both: a `;`-separated tail on the action itself
/// (`SWITCH;normal`, 45 of the 62 measured uses) or a sibling `dblclickparam=` / `rightclickparam=`
/// attribute (winampmodern566's `WA5:Prefs` page number). Splitting is done here rather than in the
/// view's switch so the probe and the view cannot disagree about what a click asked for.
enum WasabiClickGesture: String {
    case double = "dblclick"
    case right = "rightclick"

    var actionAttribute: String { rawValue + "action" }
    var parameterAttribute: String { rawValue + "param" }
}

enum WasabiClickAction {
    /// The action and parameter a gesture on this object asks for, or `nil` if it carries none.
    static func resolve(_ object: WasabiObject, gesture: WasabiClickGesture) -> (action: String, parameter: String?)? {
        guard let raw = object.attributes[gesture.actionAttribute],
              !raw.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        return split(action: raw, parameter: object.attributes[gesture.parameterAttribute])
    }

    /// Split a `ACTION;PARAM` action. An explicit parameter wins; a tail is only read when there is
    /// none, and only the *first* `;` separates, so `SWITCHTO;group;subpage` keeps its second field.
    static func split(action: String, parameter: String?) -> (action: String, parameter: String?) {
        let trimmed = action.trimmingCharacters(in: .whitespaces)
        guard let separator = trimmed.firstIndex(of: ";") else { return (trimmed, parameter) }
        let head = String(trimmed[trimmed.startIndex..<separator]).trimmingCharacters(in: .whitespaces)
        let tail = String(trimmed[trimmed.index(after: separator)...]).trimmingCharacters(in: .whitespaces)
        if let parameter, !parameter.isEmpty { return (head, parameter) }
        return (head, tail.isEmpty ? nil : tail)
    }
}
