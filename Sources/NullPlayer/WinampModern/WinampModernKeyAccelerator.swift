import AppKit

/// The keyboard name a `.wal` skin's `System.onKeyDown` handler is written against.
///
/// Winamp hands the script **one string**, not a virtual keycode: `"alt+g"`, `"ctrl+w"`, `"esc"`.
/// Every handler in the measured corpus compares it against a literal of exactly that shape —
/// multipass `System.strLower(strKey) == "alt+g"`, winampmodern566 `strKey == "alt+a"` and
/// `strLeft(strKey, 4) == "ctrl" && strSearch(strKey, "+w") != -1`, Defix `strKey == "esc"` — so the
/// string is the whole contract and it is **lowercase**: two of the three compare without
/// normalising first, and an "Alt+G" would miss every one of them.
///
/// Kept free of `NSEvent` at its core so the mapping is testable without a window: the view hands in
/// the three things AppKit knows and gets the skin's name back.
enum WinampModernKeyAccelerator {

    /// macOS modifiers map **literally**: Control → `ctrl`, Option → `alt`, Shift → `shift`.
    ///
    /// Command is deliberately *not* mapped onto `ctrl`. A Mac user's ⌘W closes a window and ⌘A
    /// selects all; folding those onto the skin's `ctrl+w` would let a skin shadow the app's own menu
    /// equivalents, which is a capability no skin asked for. `ctrl+w` in a `.wal` skin is Control-W
    /// here, and a ⌘-carrying event produces no accelerator at all.
    static func accelerator(keyCode: UInt16, charactersIgnoringModifiers: String?,
                            modifiers: NSEvent.ModifierFlags) -> String? {
        if modifiers.contains(.command) { return nil }
        guard let key = keyName(keyCode: keyCode,
                                charactersIgnoringModifiers: charactersIgnoringModifiers) else { return nil }
        // Winamp writes the prefixes in this order, and the corpus reads them positionally:
        // winampmodern566 tests `strLeft(strKey, 4) == "ctrl"`, so `ctrl` has to come first or its
        // playlist shade toggle never fires.
        var parts: [String] = []
        if modifiers.contains(.control) { parts.append("ctrl") }
        if modifiers.contains(.option) { parts.append("alt") }
        if modifiers.contains(.shift) { parts.append("shift") }
        parts.append(key)
        return parts.joined(separator: "+")
    }

    /// Convenience over the above for the one caller that has a real event.
    static func accelerator(for event: NSEvent) -> String? {
        accelerator(keyCode: event.keyCode,
                    charactersIgnoringModifiers: event.charactersIgnoringModifiers,
                    modifiers: event.modifierFlags)
    }

    /// The keys Winamp names rather than spells. Everything else is its own character.
    private static let namedKeys: [UInt16: String] = [
        53: "esc",
        122: "f1", 120: "f2", 99: "f3", 118: "f4", 96: "f5", 97: "f6",
        98: "f7", 100: "f8", 101: "f9", 109: "f10", 103: "f11", 111: "f12",
        126: "up", 125: "down", 123: "left", 124: "right",
        115: "home", 119: "end", 116: "pgup", 121: "pgdn",
        51: "backspace", 117: "del",
        48: "tab", 49: "space",
        36: "enter", 76: "enter"
    ]

    private static func keyName(keyCode: UInt16, charactersIgnoringModifiers: String?) -> String? {
        if let named = namedKeys[keyCode] { return named }
        // `charactersIgnoringModifiers` is what the key is *engraved* with — Option-G there is `g`,
        // not the `©` that `characters` reports, which is exactly the letter `alt+g` names. Shift is
        // the one modifier it does apply, so an uppercase letter is lowercased and announced through
        // the `shift+` prefix instead.
        guard let characters = charactersIgnoringModifiers?.lowercased(),
              characters.count == 1, let scalar = characters.unicodeScalars.first,
              scalar.value > 0x20, scalar.value < 0x7F else { return nil }
        return characters
    }
}
