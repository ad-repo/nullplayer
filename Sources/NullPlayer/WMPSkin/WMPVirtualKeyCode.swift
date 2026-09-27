import AppKit

/// The number a `.wmz` skin's `onKeyDown` handler is written against.
///
/// **WMP hands the script a Windows virtual key code, not a name.** This is the whole contract and
/// it is the opposite shape to the `.wal` one next door: `WinampModernKeyAccelerator` produces the
/// string `"alt+g"` because every Wasabi handler compares a string, and every WMP handler compares
/// an integer. Measured over the 184-archive corpus, `event.keyCode` is **405 of the 409** member
/// reads in a key handler or a function one calls (`event.shiftKey` is the other 4), and the
/// literals it is compared against are VK values — `37`/`38`/`39`/`40` for the arrows, `13` for
/// Return, `88` and `90` for X and Z.
///
/// **The corpus hedges between the two Windows conventions and this answers both.** `ALXMorph`'s
/// `onHotKeyPress` is `case 122: case 90: player.controls.previous()` — `90` is VK_Z, which is what
/// `onkeydown` carries, and `122` is the character `z`, which is what `onkeypress` carries. A skin
/// listing both works under either event, so `keyDown` below answers the VK and `charCode` answers
/// the character, and the same handler matches whichever one raised it.
///
/// Kept free of `NSEvent` at its core, for the same reason its `.wal` neighbour is: the mapping is
/// testable without a window.
enum WMPVirtualKeyCode {

    /// The VK for a key press — what `onkeydown` and `onkeyup` carry.
    ///
    /// `nil` for a key with no VK this engine can name honestly. **Not `0`**: every corpus handler
    /// switches over the number, `0` is VK_NULL rather than "no key", and answering it would be
    /// W260's absent-attribute trap in a second place. An unmappable key raises no event at all and
    /// falls through to whatever the engine does with it.
    static func keyDown(keyCode: UInt16, charactersIgnoringModifiers: String?) -> Int? {
        if let named = namedKeys[keyCode] { return named }
        // `charactersIgnoringModifiers` is the key as engraved — Option-G is `g` there, not the `©`
        // that `characters` reports. VK_A…VK_Z are 0x41…0x5A and VK_0…VK_9 are 0x30…0x39, which are
        // the ASCII values of the *uppercase* forms, so the letter uppercased is already the VK.
        guard let scalar = asciiScalar(charactersIgnoringModifiers?.uppercased()),
              (scalar >= 0x30 && scalar <= 0x39) || (scalar >= 0x41 && scalar <= 0x5A) else { return nil }
        return Int(scalar)
    }

    /// **Why `onkeypress` is raised with the VK too, rather than a character code.** Windows sends
    /// a character there, and the corpus is written for that — but it is written for *both*: every
    /// letter compared in an `onkeypress` handler is compared in both cases, 72 times each
    /// (`case 88: case 120:` for X, `case 90: case 122:` for Z, and the same for B, C, F, L, P, V),
    /// so the uppercase half is the VK and every one of them matches. `onkeyup` compares only `13`,
    /// which is `VK_RETURN` and the carriage return alike, and `onkeydown` compares the arrows and
    /// space, which have no character form at all. Measured over 184 archives 2026-09-22: one
    /// number answers all three events, and a second one would only be a second thing to get wrong.

    private static func asciiScalar(_ characters: String?) -> UInt32? {
        guard let characters, characters.count == 1, let scalar = characters.unicodeScalars.first,
              scalar.isASCII else { return nil }
        return scalar.value
    }

    /// The keys Windows numbers rather than spells, by macOS virtual keycode.
    ///
    /// Punctuation is deliberately absent: those are the OEM range (`VK_OEM_1`…), whose meaning
    /// depends on the keyboard layout Windows was using, and **no corpus handler compares one**.
    /// Naming them would be guessing at a number no skin reads.
    private static let namedKeys: [UInt16: Int] = [
        53: 27,                                                   // esc       VK_ESCAPE
        122: 112, 120: 113, 99: 114, 118: 115, 96: 116, 97: 117,  // f1-f6     VK_F1…
        98: 118, 100: 119, 101: 120, 109: 121, 103: 122, 111: 123, // f7-f12
        123: 37, 126: 38, 124: 39, 125: 40,                       // arrows    VK_LEFT…VK_DOWN
        115: 36, 119: 35, 116: 33, 121: 34,                       // home/end/pgup/pgdn
        51: 8, 117: 46,                                           // backspace VK_BACK, del VK_DELETE
        48: 9, 49: 32,                                            // tab, space
        36: 13, 76: 13                                            // return, enter
    ]
}
