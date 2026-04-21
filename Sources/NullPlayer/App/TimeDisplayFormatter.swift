import Foundation

struct TimeDisplayFormatter {
    static func string(
        currentTime: TimeInterval,
        duration: TimeInterval,
        mode: TimeDisplayMode,
        numberSystem: TimeDisplayNumberSystem
    ) -> String {
        let displayTime: TimeInterval
        let showMinus: Bool

        if mode == .remaining && duration > 0 {
            displayTime = duration - currentTime
            showMinus = true
        } else {
            displayTime = currentTime
            showMinus = false
        }

        let totalSeconds = Int(abs(displayTime))
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return string(minutes: minutes, seconds: seconds, isNegative: showMinus, numberSystem: numberSystem)
    }

    static func string(
        minutes: Int,
        seconds: Int,
        isNegative: Bool,
        numberSystem: TimeDisplayNumberSystem
    ) -> String {
        let prefix = isNegative ? "-" : ""

        switch numberSystem {
        case .decimal:
            return prefix + mapDecimalNumber(minutes, digits: "0123456789") + ":" + mapDecimalNumber(seconds, digits: "0123456789", minimumDigits: 2)
        case .arabicIndic:
            return prefix + mapDecimalNumber(minutes, digits: "٠١٢٣٤٥٦٧٨٩") + ":" + mapDecimalNumber(seconds, digits: "٠١٢٣٤٥٦٧٨٩", minimumDigits: 2)
        case .extendedArabicIndic:
            return prefix + mapDecimalNumber(minutes, digits: "۰۱۲۳۴۵۶۷۸۹") + ":" + mapDecimalNumber(seconds, digits: "۰۱۲۳۴۵۶۷۸۹", minimumDigits: 2)
        case .devanagari:
            return prefix + mapDecimalNumber(minutes, digits: "०१२३४५६७८९") + ":" + mapDecimalNumber(seconds, digits: "०१२३४५६७८९", minimumDigits: 2)
        case .bengali:
            return prefix + mapDecimalNumber(minutes, digits: "০১২৩৪৫৬৭৮৯") + ":" + mapDecimalNumber(seconds, digits: "০১২৩৪৫৬৭৮৯", minimumDigits: 2)
        case .thai:
            return prefix + mapDecimalNumber(minutes, digits: "๐๑๒๓๔๕๖๗๘๙") + ":" + mapDecimalNumber(seconds, digits: "๐๑๒๓๔๕๖๗๘๙", minimumDigits: 2)
        case .fullwidth:
            return prefix + mapDecimalNumber(minutes, digits: "０１２３４５６７８９") + ":" + mapDecimalNumber(seconds, digits: "０１２３４５６７８９", minimumDigits: 2)
        case .octal:
            return prefix + convert(minutes, base: 8, symbols: Array("01234567")) + ":" + convert(seconds, base: 8, symbols: Array("01234567"), minimumDigits: 2)
        case .hexadecimal:
            return prefix + convert(minutes, base: 16, symbols: Array("0123456789ABCDEF")) + ":" + convert(seconds, base: 16, symbols: Array("0123456789ABCDEF"), minimumDigits: 2)
        }
    }

    private static func mapDecimalNumber(_ value: Int, digits: String, minimumDigits: Int = 1) -> String {
        let westernDigits = Array("0123456789")
        let replacementDigits = Array(digits).map(String.init)
        let padded = String(format: "%0\(minimumDigits)d", max(0, value))

        return padded.map { char in
            if let index = westernDigits.firstIndex(of: char) {
                return replacementDigits[index]
            }
            return String(char)
        }.joined()
    }

    private static func convert(_ value: Int, base: Int, symbols: [Character], minimumDigits: Int = 1) -> String {
        precondition(base >= 2)
        precondition(symbols.count >= base)

        var number = max(0, value)
        var digits: [String] = []

        repeat {
            digits.append(String(symbols[number % base]))
            number /= base
        } while number > 0

        while digits.count < minimumDigits {
            digits.append(String(symbols[0]))
        }

        return digits.reversed().joined()
    }

}
