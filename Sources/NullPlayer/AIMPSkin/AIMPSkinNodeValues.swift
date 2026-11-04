import Foundation

extension AIMPNode {
    /// A property's value, else its link, else its nested `ID`: the picture, script or handler a
    /// control or item names through it (`Skin`, `OnClick`, `Texture`).
    var reference: String? {
        if let value = self["value"], !value.isEmpty { return value }
        if let link = self["link"], !link.isEmpty { return link }
        return named["ID"]?["value"]
    }

    /// A list of integers as AIMP writes one, comma-separated (`Size` "300,120", `AlignmentMargins`
    /// "0,4,0,4"); what does not read as a number is left out.
    static func numbers(_ text: String?) -> [Int] {
        (text ?? "").split(separator: ",").compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
    }
}

extension AIMPSkinColor {
    /// A Delphi `TColor` ($00BBGGRR) as ARGB; one with the top byte set is ARGB already, except the
    /// system colours ($FF0000xx: the window text's, 8, is black).
    static func argb(delphi value: Int64) -> UInt32 {
        let raw = UInt32(truncatingIfNeeded: value)
        if raw & 0xFF00_0000 != 0 {
            guard raw & 0x00FF_FFFF < 0x40 else { return raw }
            return [5: 0xFFFF_FFFF, 15: 0xFFF0_F0F0, 13: 0xFF33_99FF][Int(raw & 0xFF)] ?? 0xFF00_0000
        }
        return 0xFF00_0000 | (raw & 0xFF) << 16 | (raw & 0xFF00) | (raw >> 16) & 0xFF
    }
}
