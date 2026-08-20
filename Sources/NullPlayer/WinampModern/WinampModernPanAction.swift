import Foundation

/// `action="PAN"` — the balance slider, in the two units it has to live in at once.
///
/// The host keeps stereo balance the way the engine does, −1 (hard left) … +1 (hard right). A Wasabi
/// slider is a 0…255 position, and a skin's script reads *that* number back: multipass's
/// `onSetPosition` prints "Balance: Left +x%" from `intNewPosition` against a centre of 127. Both
/// edges — the drag that writes the balance, and the thumb that draws where it stands — convert
/// here, so the two can never disagree about where the centre is.
enum WinampModernPanAction {
    /// Whether an `action=` is the balance slider. Case- and whitespace-tolerant, as every other
    /// action match in the view is: skins write `PAN` on its own line in an attribute block.
    static func matches(action: String?) -> Bool {
        guard let action else { return false }
        return action.trimmingCharacters(in: .whitespaces).caseInsensitiveCompare("PAN") == .orderedSame
    }

    /// A 0…1 slider position as engine balance.
    static func balance(normalized: CGFloat) -> Double {
        Double(max(0, min(1, normalized))) * 2 - 1
    }

    /// Engine balance as the 0…1 position the thumb is drawn at.
    static func normalized(balance: Double) -> CGFloat {
        CGFloat((max(-1, min(1, balance)) + 1) / 2)
    }
}
