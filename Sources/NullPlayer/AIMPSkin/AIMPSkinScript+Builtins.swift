import Foundation

/// The Delphi run-time functions skins call that read nothing of the skin or the player: strings,
/// numbers, colours, dates and times, and the calls for things NullPlayer has nowhere to show.
/// Found by auditing every script in the corpus for names the interpreter did not handle
/// (`skills/aimp-skin-guide/reference/harness.md`). Each is resolved by name as the script
/// compiles; what reads the skin or the player is a `HostCall` (`AIMPSkinScript+HostBridge.swift`).
extension AIMPSkinScript {
    enum Builtin: Sendable {
        // `var` parameters: the first argument is the variable, read by name.
        case inc, dec, delete
        // Strings, 1-based as Pascal's.
        case toText, toNumber, copy, pos, chr, ord, insert, compareText, compareStr, trim, length, uppercase, lowercase, format
        // Numbers.
        case round, trunc, frac, abs, sqr, sqrt, ln, exp, sin, cos, arctan, log10, pi, power, min, max, random
        case strToBool, boolToStr, validInt, validFloat, formatFloat, null
        // Colours: a `TColor` is $00BBGGRR, an ARGB number $AARRGGBB.
        case hsvToColor, hsvToColorAlpha, colorToHSV, colorToString, stringToColor, argbToColor, colorToARGB
        // Dates and times, as Delphi's `TDateTime`: days since 30 December 1899, the time its fraction.
        case now, date, time, encodeDate, encodeTime, decodeTime, decodeDate, dayOfWeek, formatDateTime
        case dateTimeToStr, timeToStr, dateToStr
        /// `TASEBindings(V.Get('Bindings'))`, `TComponent(…)`: a cast is the value as it is; the
        /// bare class is what `TASEBindings.Create` is called on.
        case cast
        case findResource
        /// AIMP's colour dialog; NullPlayer has none to show, so it reads as cancelled and the
        /// colour stays (A4's custom background colour).
        case executeColorPicker
        /// AIMP's "smooth animation" option; NullPlayer has none, so skins take their instant path.
        case isFadingEnabled
        /// Messages, debugging, the clipboard, update batching, seeding `Random` (which is fixed),
        /// and switching to another installed skin by name (Red Bias's "back to the old skin"
        /// button, NullPlayer's own skin menu's job): nothing to do.
        case nothing

        /// The one table of names: what each built-in is called in a script, lowercased.
        private static let table: [String: Builtin] = [
            "inttostr": .toText, "floattostr": .toText, "vartostr": .toText,
            "strtoint": .toNumber, "strtofloat": .toNumber, "strtointdef": .toNumber, "strtoint64": .toNumber, "strtoint64def": .toNumber,
            "copy": .copy, "pos": .pos, "chr": .chr, "ord": .ord, "insert": .insert,
            "comparetext": .compareText, "comparestr": .compareStr, "trim": .trim, "length": .length,
            "uppercase": .uppercase, "lowercase": .lowercase, "format": .format,
            "round": .round, "trunc": .trunc, "int": .trunc, "frac": .frac, "abs": .abs, "sqr": .sqr, "sqrt": .sqrt,
            "ln": .ln, "exp": .exp, "sin": .sin, "cos": .cos, "arctan": .arctan, "log10": .log10, "pi": .pi,
            "power": .power, "min": .min, "max": .max, "random": .random,
            "strtobool": .strToBool, "booltostr": .boolToStr, "validint": .validInt, "validfloat": .validFloat,
            "formatfloat": .formatFloat, "null": .null,
            "hsvtocolor": .hsvToColor, "hsvtocolora": .hsvToColorAlpha, "hsltocolor": .hsvToColorAlpha,
            "colortohsv": .colorToHSV, "colortohsva": .colorToHSV, "colortostring": .colorToString,
            "stringtocolor": .stringToColor, "argbtocolor": .argbToColor, "colortoargb": .colorToARGB,
            "now": .now, "date": .date, "time": .time, "encodedate": .encodeDate, "encodetime": .encodeTime,
            "decodetime": .decodeTime, "decodedate": .decodeDate, "dayofweek": .dayOfWeek, "formatdatetime": .formatDateTime,
            "datetimetostr": .dateTimeToStr, "timetostr": .timeToStr, "datetostr": .dateToStr,
            "tasebindings": .cast, "tcomponent": .cast, "findresource": .findResource,
            "executecolorpicker": .executeColorPicker, "isfadingenabled": .isFadingEnabled,
            "showmessage": .nothing, "outputdebugstring": .nothing, "copytoclipboard": .nothing, "applyskin": .nothing,
            "randomize": .nothing, "beginupdateresources": .nothing, "endupdateresources": .nothing,
            "beginupdate": .nothing, "endupdate": .nothing,
        ]

        /// The built-in `key` names, other than those that write a variable (`writingVariable`).
        init?(_ key: String) {
            guard let builtin = Self.table[key] else { return nil }
            self = builtin
        }

        /// `Inc(X[, n])`, `Dec(X[, n])` and `Delete(S, Index, Count)` when their first argument is a
        /// variable: these come before the program's own routines of the name.
        static func writingVariable(_ key: String, _ arguments: [Argument]) -> Builtin? {
            guard arguments.first?.variable != nil else { return nil }
            switch key {
            case "inc": return .inc
            case "dec": return .dec
            case "delete" where arguments.count == 3: return .delete
            default: return nil
            }
        }

        /// Whether the first argument is the variable's value as it stands (`Inc`, `Dec`, `Delete`),
        /// read by name rather than evaluated.
        var readsVariable: Bool {
            switch self {
            case .inc, .dec, .delete: return true
            default: return false
            }
        }

        /// What the built-in gives for `args`, and what it writes to its `var` parameters, by
        /// argument position.
        func call(_ args: [Value]) -> (value: Value, outputs: [Int: Value]) {
            func number(_ i: Int) -> Double { i < args.count ? args[i].number : 0 }
            func text(_ i: Int) -> String { i < args.count ? args[i].string : "" }
            func value(_ value: Value) -> (Value, [Int: Value]) { (value, [:]) }
            switch self {
            case .inc, .dec:
                let step = args.count > 1 ? number(1) : 1
                return (.none, [0: .number(number(0) + (self == .inc ? step : -step))])
            // Denon's EQ bands read their number from their name: `Band_7` less its first five letters.
            case .delete:
                var chars = Array(text(0))
                let start = Swift.max(0, Int(number(1)) - 1), count = Swift.max(0, Int(number(2)))
                if start < chars.count { chars.removeSubrange(start..<Swift.min(chars.count, start + count)) }
                return (.none, [0: .string(String(chars))])
            case .toText: return value(.string(text(0)))
            case .toNumber: return value(.number(Double(text(0)) ?? number(1)))
            case .copy:
                let chars = Array(text(0)), start = Swift.max(0, Int(number(1)) - 1)
                let count = args.count > 2 ? Swift.max(0, Int(number(2))) : chars.count
                return value(.string(start < chars.count ? String(chars[start..<Swift.min(chars.count, start + count)]) : ""))
            case .pos:
                guard let range = text(1).range(of: text(0)), !text(0).isEmpty else { return value(.number(0)) }
                return value(.number(Double(text(1).distance(from: text(1).startIndex, to: range.lowerBound) + 1)))
            case .chr: return value(.string(UnicodeScalar(UInt32(Swift.max(0, number(0)))).map { String(Character($0)) } ?? ""))
            case .ord: return value(.number(Double(text(0).unicodeScalars.first?.value ?? 0)))
            case .insert:
                var target = Array(text(1))
                target.insert(contentsOf: Array(text(0)), at: Swift.min(Swift.max(0, Int(number(2)) - 1), target.count))
                return (.none, [1: .string(String(target))])
            case .compareText, .compareStr:
                let a = self == .compareText ? text(0).lowercased() : text(0), b = self == .compareText ? text(1).lowercased() : text(1)
                return value(.number(a == b ? 0 : a < b ? -1 : 1))
            case .trim: return value(.string(text(0).trimmingCharacters(in: .whitespaces)))
            case .length: return value(.number(Double(args.first?.string.count ?? 0)))
            case .uppercase: return value(.string(text(0).uppercased()))
            case .lowercase: return value(.string(text(0).lowercased()))
            case .format: return value(.string(AIMPSkinScript.format(text(0), args.count > 1 ? args[1] : .none)))
            case .round: return value(.number(number(0).rounded()))
            case .trunc: return value(.number(number(0).rounded(.towardZero)))
            case .frac: return value(.number(number(0) - number(0).rounded(.towardZero)))
            case .abs: return value(.number(Swift.abs(number(0))))
            case .sqr: return value(.number(number(0) * number(0)))
            case .sqrt: return value(.number(number(0) >= 0 ? number(0).squareRoot() : 0))
            case .ln: return value(.number(number(0) > 0 ? Foundation.log(number(0)) : 0))
            case .exp: return value(.number(Foundation.exp(number(0))))
            case .sin: return value(.number(Foundation.sin(number(0))))
            case .cos: return value(.number(Foundation.cos(number(0))))
            case .arctan: return value(.number(atan(number(0))))
            case .log10: return value(.number(number(0) > 0 ? Foundation.log10(number(0)) : 0))
            case .pi: return value(.number(Double.pi))
            case .power: return value(.number(pow(number(0), number(1))))
            case .min: return value(.number(Swift.min(number(0), number(1))))
            case .max: return value(.number(Swift.max(number(0), number(1))))
            // Fixed at 0, so `Randomize` has nothing to seed.
            case .random: return value(.number(0))
            case .strToBool: return value(.number(["true", "1", "-1"].contains(text(0).lowercased()) ? 1 : 0))
            case .boolToStr: return value(.string(number(0) != 0 ? "True" : "False"))
            case .validInt: return value(.number(Int(text(0)) != nil ? 1 : 0))
            case .validFloat: return value(.number(Double(text(0)) != nil ? 1 : 0))
            case .formatFloat:
                // `0.00`, `#,##0.0`: as many decimals as the pattern has after its point.
                let decimals = text(0).split(separator: ".").dropFirst().first.map { $0.filter { $0 == "0" || $0 == "#" }.count } ?? 0
                return value(.string(String(format: "%.\(decimals)f", number(1))))
            case .null: return value(.none)
            case .hsvToColor: return value(.number(Self.argb(hue: number(0), saturation: number(1), value: number(2))))
            case .hsvToColorAlpha:
                let alpha = args.count > 3 ? Int(Swift.max(0, Swift.min(255, number(3)))) : 255
                return value(.number(Self.argb(hue: number(0), saturation: number(1), value: number(2), alpha: alpha)))
            case .colorToHSV:
                // `ColorToHSV(Color, var H, S, V)`: hue 0–360, saturation and value 0–100.
                let c = UInt32(truncatingIfNeeded: Int(number(0)))
                let r = Double(c & 0xFF) / 255, g = Double((c >> 8) & 0xFF) / 255, b = Double((c >> 16) & 0xFF) / 255
                let high = Swift.max(r, g, b), low = Swift.min(r, g, b), d = high - low
                var h = 0.0
                if d > 0 { h = high == r ? 60 * ((g - b) / d).truncatingRemainder(dividingBy: 6) : high == g ? 60 * ((b - r) / d + 2) : 60 * ((r - g) / d + 4) }
                if h < 0 { h += 360 }
                return (.none, [1: .number(h.rounded()), 2: .number(high > 0 ? (d / high * 100).rounded() : 0), 3: .number((high * 100).rounded())])
            case .colorToString: return value(.string(String(format: "$%08X", UInt32(truncatingIfNeeded: Int(number(0))))))
            case .stringToColor:
                let s = text(0)
                if s.hasPrefix("$") { return value(.number(Double(UInt32(s.dropFirst(), radix: 16) ?? 0))) }
                return value(.number(Double(s) ?? 0))
            case .argbToColor:
                let v = UInt32(truncatingIfNeeded: Int(number(0)))
                return value(.number(Double((v >> 16) & 0xFF | (v & 0xFF00) | (v & 0xFF) << 16)))
            case .colorToARGB:
                let c = UInt32(truncatingIfNeeded: Int(number(0))), alpha = args.count > 1 ? UInt32(Swift.max(0, Swift.min(255, number(1)))) : 255
                return value(.number(Double(alpha << 24 | (c & 0xFF) << 16 | (c & 0xFF00) | (c >> 16) & 0xFF)))
            case .now: return value(.number(Self.dateTime(Date())))
            case .date: return value(.number(Self.dateTime(Date()).rounded(.down)))
            case .time:
                let now = Self.dateTime(Date())
                return value(.number(now - now.rounded(.down)))
            case .encodeDate:
                let parts = DateComponents(calendar: Calendar(identifier: .gregorian), year: Int(number(0)), month: Int(number(1)), day: Int(number(2)))
                return value(.number(parts.date.map { ($0.timeIntervalSince(Self.epoch) / 86_400).rounded() } ?? 0))
            case .encodeTime: return value(.number((number(0) * 3_600 + number(1) * 60 + number(2) + number(3) / 1_000) / 86_400))
            case .decodeTime:
                let seconds = (number(0) - number(0).rounded(.down)) * 86_400
                return (.none, [1: .number((seconds / 3_600).rounded(.down)),
                                2: .number((seconds / 60).truncatingRemainder(dividingBy: 60).rounded(.down)),
                                3: .number(seconds.truncatingRemainder(dividingBy: 60).rounded(.down)),
                                4: .number((seconds * 1_000).truncatingRemainder(dividingBy: 1_000).rounded(.down))])
            case .decodeDate:
                let parts = Calendar(identifier: .gregorian).dateComponents([.year, .month, .day], from: Self.date(number(0)))
                return (.none, [1: .number(Double(parts.year ?? 0)), 2: .number(Double(parts.month ?? 0)), 3: .number(Double(parts.day ?? 0))])
            case .dayOfWeek: return value(.number(Double(Calendar(identifier: .gregorian).component(.weekday, from: Self.date(number(0))))))
            case .formatDateTime: return value(.string(Self.format(dateTime: number(1), pattern: text(0))))
            case .dateTimeToStr: return value(.string(Self.format(dateTime: number(0), pattern: "dd.mm.yyyy hh:nn:ss")))
            case .timeToStr: return value(.string(Self.format(dateTime: number(0), pattern: "hh:nn:ss")))
            case .dateToStr: return value(.string(Self.format(dateTime: number(0), pattern: "dd.mm.yyyy")))
            case .cast: return value(args.count == 1 ? args[0] : .bindingsClass)
            case .findResource: return value(.resource(text(0)))
            case .executeColorPicker, .isFadingEnabled: return value(.number(0))
            case .nothing: return value(.none)
            }
        }

        private static let epoch = DateComponents(calendar: Calendar(identifier: .gregorian), year: 1899, month: 12, day: 30).date!

        static func dateTime(_ date: Date) -> Double {
            let local = date.addingTimeInterval(TimeInterval(TimeZone.current.secondsFromGMT(for: date)))
            return local.timeIntervalSince(epoch) / 86_400
        }

        static func date(_ dateTime: Double) -> Date {
            let local = epoch.addingTimeInterval(dateTime * 86_400)
            return local.addingTimeInterval(-TimeInterval(TimeZone.current.secondsFromGMT(for: local)))
        }

        /// Delphi's `FormatDateTime` for the letters skins use: `yyyy` `yy` `mm` `m` `dd` `d` `hh` `h`
        /// `nn` `n` `ss` `s` `zzz`; anything else (`:`, `.`, quoted text) as written.
        static func format(dateTime: Double, pattern: String) -> String {
            let parts = Calendar(identifier: .gregorian).dateComponents([.year, .month, .day, .hour, .minute, .second, .nanosecond], from: date(dateTime))
            var out = "", chars = Array(pattern)[...]
            var afterHour = false
            while let c = chars.first {
                var run = 1
                while run < chars.count, chars[chars.startIndex + run].lowercased() == c.lowercased() { run += 1 }
                let token = String(repeating: c.lowercased(), count: run)
                func pad(_ n: Int?, _ width: Int) -> String { String(format: "%0\(width)d", n ?? 0) }
                switch token.first {
                case "y": out += run >= 4 ? pad(parts.year, 4) : pad((parts.year ?? 0) % 100, 2)
                // `mm` after an hour is minutes, as in Delphi.
                case "m": out += afterHour ? pad(parts.minute, run >= 2 ? 2 : 1) : pad(parts.month, run >= 2 ? 2 : 1)
                case "d": out += pad(parts.day, run >= 2 ? 2 : 1)
                case "h": out += pad(parts.hour, run >= 2 ? 2 : 1); afterHour = true
                case "n": out += pad(parts.minute, run >= 2 ? 2 : 1)
                case "s": out += pad(parts.second, run >= 2 ? 2 : 1)
                case "z": out += pad((parts.nanosecond ?? 0) / 1_000_000, 3)
                case "'", "\"":
                    chars.removeFirst()
                    while let q = chars.first, q != c { out.append(q); chars.removeFirst() }
                    if !chars.isEmpty { chars.removeFirst() }
                    continue
                default: out += String(chars.prefix(run))
                }
                if token.first != "h", token.first != "m" { afterHour = token.first == "n" ? false : afterHour }
                chars.removeFirst(run)
            }
            return out
        }

        /// `HSVToColor`: hue 0–360, saturation and value 0–100, as an ARGB number with `alpha` (0–255).
        static func argb(hue: Double, saturation: Double, value: Double, alpha: Int = 255) -> Double {
            let h = hue.truncatingRemainder(dividingBy: 360) / 60, v = value / 100
            let c = v * saturation / 100, x = c * (1 - Swift.abs(h.truncatingRemainder(dividingBy: 2) - 1)), m = v - c
            let (r, g, b): (Double, Double, Double) = h < 1 ? (c, x, 0) : h < 2 ? (x, c, 0) : h < 3 ? (0, c, x)
                : h < 4 ? (0, x, c) : h < 5 ? (x, 0, c) : (c, 0, x)
            func byte(_ f: Double) -> Int { Int(((f + m) * 255).rounded()) }
            return Double(alpha << 24 | byte(r) << 16 | byte(g) << 8 | byte(b))
        }
    }

    /// Delphi's `Format(pattern, [values])`: `%d`, `%s`, `%f`, `%x` with width and precision
    /// (`%.2d` zero-pads to two), and `%%`.
    static func format(_ pattern: String, _ values: Value) -> String {
        var list: [Value] = []
        if case .array(let elements) = values { list = elements.keys.sorted().compactMap { elements[$0] } }
        else if case .none = values {} else { list = [values] }
        var out = ""
        var next = 0
        var chars = Array(pattern)[...]
        while let c = chars.popFirst() {
            guard c == "%" else { out.append(c); continue }
            var spec = ""
            while let s = chars.first, "-0123456789.".contains(s) { spec.append(s); chars.removeFirst() }
            guard let kind = chars.popFirst() else { break }
            if kind == "%" { out.append("%"); continue }
            let value = next < list.count ? list[next] : .number(0)
            next += 1
            let parts = spec.split(separator: ".", omittingEmptySubsequences: false)
            let width = Int(parts.first ?? "") ?? 0
            let precision = parts.count > 1 ? Int(parts[1]) : nil
            var text: String
            switch kind.lowercased() {
            case "d", "u":
                text = String(Int(value.number.rounded(.towardZero)))
                if let precision, text.count < precision { text = String(repeating: "0", count: precision - text.count) + text }
            case "f", "n": text = String(format: "%.\(precision ?? 2)f", value.number)
            case "x": text = String(Int(value.number), radix: 16, uppercase: true)
            default: text = value.string
            }
            if width > text.count { text = String(repeating: " ", count: width - text.count) + text }
            out += text
        }
        return out
    }
}
